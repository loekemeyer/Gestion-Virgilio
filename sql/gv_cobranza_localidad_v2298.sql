-- v22.98 · CRM de cobranzas F1: localidad, CP y provincia de cada comprobante de la deuda viva.
-- Fuente: la factura de ISIS (contraparte_localidad / contraparte_cp); si el comprobante no
-- está en ISIS, la última factura del cliente; si tampoco, el padrón GV_Clientes_Direcciones.
-- Sirve para cruzar un depósito sin cliente con la sucursal bancaria (provincia) del extracto.

-- 1) provincia desde el texto de ISIS ("Mar Del Plata Buenos Aires", "Frias Sgo.del Estero")
create or replace function public.gv_cobranza_provincia(p_loc text, p_cp text)
returns text language sql immutable set search_path = public as $$
  select case
    when coalesce(p_cp,'') ~ '^\s*1[0-4]\d\d\s*$'
      or coalesce(p_loc,'') ~* '(^|\s)(c\.?a\.?b\.?a\.?|capital federal)(\s|$)' then 'Capital Federal'
    else (select pr from unnest(array['Buenos Aires','Catamarca','Chaco','Chubut','Córdoba','Corrientes',
            'Entre Ríos','Formosa','Jujuy','La Pampa','La Rioja','Mendoza','Misiones','Neuquén','Río Negro',
            'Salta','San Juan','San Luis','Santa Cruz','Santa Fe','Santiago del Estero','Tierra del Fuego','Tucumán']) pr
           where translate(lower(btrim(p_loc)),'áéíóú','aeiou') ~ ('(^|\s)' || translate(lower(pr),'áéíóú','aeiou') || '\s*$')
              or (pr = 'Santiago del Estero' and lower(btrim(p_loc)) ~ 'sgo\.?\s*del\s*estero\s*$')
           order by length(pr) desc limit 1)
  end
$$;

-- 2) localidad sin la provincia pegada ni el CP adelante
create or replace function public.gv_cobranza_localidad(p_loc text, p_prov text)
returns text language sql immutable set search_path = public as $$
  select nullif(initcap(btrim(regexp_replace(regexp_replace(
           regexp_replace(coalesce(p_loc,''), '^\s*\d+\s+', ''),
           '\s*(' || case when p_prov = 'Santiago del Estero' then 'sgo\.?\s*del\s*estero'
                          when p_prov = 'Capital Federal' then 'capital federal'
                          else coalesce(regexp_replace(translate(lower(p_prov),'áéíóú','aeiou'),'\s+','\\s+','g'),'$^') end
           || ')\s*$', '', 'i'), '\s+', ' ', 'g'))), '')
$$;

revoke all on function public.gv_cobranza_provincia(text,text), public.gv_cobranza_localidad(text,text) from anon;

-- 3) columnas nuevas (tabla derivada, se reconstruye entera en cada refresco)
alter table public."GV_Cobranza_Deuda_Viva" add column if not exists localidad text;
alter table public."GV_Cobranza_Deuda_Viva" add column if not exists cp text;
alter table public."GV_Cobranza_Deuda_Viva" add column if not exists provincia text;

-- 4) paso nuevo en gv_cobranza_deuda_viva_refrescar(), aplicado sobre la definición VIVA,
--    idempotente (marcador v22.98-loc) y con raise si el texto no matchea.
do $patch$
declare d text; ancla text := $a$  delete from "GV_Cobranza_Deuda_Viva" where (empresa = 'lk' and cod_cliente = '411')$a$;
        paso text := $p$  -- v22.98-loc: localidad/CP/provincia por comprobante (ISIS) -> ultima factura -> padron
  -- primero se junta el texto crudo sólo de lo que está en la deuda (423 filas), después se parsea:
  -- parsear las ~28 mil facturas de ISIS llevaba el refresco de 0,7 s a 17 s.
  update "GV_Cobranza_Deuda_Viva" v set cp = x.cp, provincia = gv_cobranza_provincia(x.loc0, x.cp),
         localidad = gv_cobranza_localidad(x.loc0, gv_cobranza_provincia(x.loc0, x.cp))
    from (select 'lk' emp, gv_cobranza_doc_key(familia, punto_venta||numero) k, contraparte_localidad loc0,
                 nullif(btrim(contraparte_cp),'') cp
            from isis_lk.documentos where familia in ('factura_venta','nc_venta','nd_venta') and contraparte_localidad is not null
          union all
          select 'chef', gv_cobranza_doc_key(familia, punto_venta||numero), contraparte_localidad, nullif(btrim(contraparte_cp),'')
            from isis_ch.documentos where familia in ('factura_venta','nc_venta','nd_venta') and contraparte_localidad is not null) x
   where v.empresa = x.emp and v.doc_key = x.k;
  update "GV_Cobranza_Deuda_Viva" v set cp = coalesce(v.cp, u.cp),
         provincia = coalesce(v.provincia, gv_cobranza_provincia(u.loc0, u.cp)),
         localidad = coalesce(v.localidad, gv_cobranza_localidad(u.loc0, gv_cobranza_provincia(u.loc0, u.cp)))
    from (select distinct on (emp, cod) emp, cod, loc0, cp from (
            select 'lk' emp, regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod, fecha,
                   contraparte_localidad loc0, nullif(btrim(contraparte_cp),'') cp
              from isis_lk.documentos where familia = 'factura_venta' and contraparte_localidad is not null
            union all
            select 'chef', regexp_replace(coalesce(contraparte_codigo,''),'^0+',''), fecha,
                   contraparte_localidad, nullif(btrim(contraparte_cp),'')
              from isis_ch.documentos where familia = 'factura_venta' and contraparte_localidad is not null) f
          order by emp, cod, fecha desc) u
   where v.empresa = u.emp and v.cod_cliente = u.cod and (v.provincia is null or v.localidad is null);
  update "GV_Cobranza_Deuda_Viva" v set localidad = coalesce(v.localidad, initcap(btrim(p.localidad))),
         provincia = coalesce(v.provincia, gv_cobranza_provincia(p.provincia, null), initcap(btrim(p.provincia)))
    from (select distinct on (empresa, cod) empresa, regexp_replace(coalesce(cod,''),'^0+','') cod, localidad, provincia
            from "GV_Clientes_Direcciones" where coalesce(btrim(provincia),'') <> ''
           order by empresa, cod) p
   where v.empresa = p.empresa and v.cod_cliente = p.cod and v.provincia is null;
$p$;
begin
  d := pg_get_functiondef('public.gv_cobranza_deuda_viva_refrescar()'::regprocedure);
  if position('v22.98-loc' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  if position(ancla in d) = 0 then raise exception 'gv_cobranza_deuda_viva_refrescar: no encontre el ancla, no se aplica'; end if;
  execute replace(d, ancla, paso || ancla);
end $patch$;
