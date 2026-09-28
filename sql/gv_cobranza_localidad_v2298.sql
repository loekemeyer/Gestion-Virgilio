-- v22.98 · CRM de cobranzas F1: localidad y provincia de ENTREGA de cada factura de la deuda viva.
-- Thomas 26/09: "el parámetro no es la parte fiscal, sino la dirección/localidad de entrega".
-- NO se usa contraparte_localidad de ISIS (es el domicilio fiscal).
--
-- Cadena:
--   1) factura -> NP (GV_Cruce_FC_Asig) -> gv_np_destino (provincia + localidad_destino)      fuente 'np'
--   2) sin NP: el cliente tiene UNA sola dirección de entrega en GV_Clientes_Direcciones       fuente 'padron unica'
--   3) varias direcciones y sin NP: queda NULL (no se adivina la sucursal)
-- Medido 26/09 sobre 326 facturas con deuda: 227 por NP; del resto, 110 con dirección única.
-- Sirve para cruzar un depósito sin cliente con la sucursal bancaria (provincia) del extracto.

alter table public."GV_Cobranza_Deuda_Viva" add column if not exists localidad_entrega text;
alter table public."GV_Cobranza_Deuda_Viva" add column if not exists provincia_entrega text;
alter table public."GV_Cobranza_Deuda_Viva" add column if not exists ubicacion_fuente text;

do $patch$
declare d text; ancla text := $a$  delete from "GV_Cobranza_Deuda_Viva" where (empresa = 'lk' and cod_cliente = '411')$a$;
        paso text := $p$  -- v22.98-loc: ubicacion de ENTREGA (no la fiscal): factura -> NP -> gv_np_destino; si no, direccion unica del padron
  update "GV_Cobranza_Deuda_Viva" v
     set provincia_entrega = nd.provincia, localidad_entrega = nd.localidad_destino, ubicacion_fuente = 'np'
    from (select 'lk' emp, id, gv_cobranza_doc_key(familia, punto_venta||numero) k from isis_lk.documentos
           where familia in ('factura_venta','nd_venta')
          union all
          select 'chef', id, gv_cobranza_doc_key(familia, punto_venta||numero) from isis_ch.documentos
           where familia in ('factura_venta','nd_venta')) i
    join "GV_Cruce_FC_Asig" a on a.doc_id::text = i.id::text
    join gv_np_destino nd on nd.np = a.np and nd.provincia is not null
   where v.empresa = i.emp and v.doc_key = i.k;
  update "GV_Cobranza_Deuda_Viva" v
     set provincia_entrega = p.provincia, localidad_entrega = p.localidad, ubicacion_fuente = 'padron unica'
    from (select empresa, regexp_replace(coalesce(cod,''),'^0+','') cod,
                 min(initcap(btrim(localidad))) localidad, min(initcap(btrim(provincia))) provincia
            from "GV_Clientes_Direcciones"
           where coalesce(btrim(provincia),'') <> ''
           group by 1, 2 having count(distinct dir_key) = 1) p
   where v.empresa = p.empresa and v.cod_cliente = p.cod and v.provincia_entrega is null;
$p$;
begin
  d := pg_get_functiondef('public.gv_cobranza_deuda_viva_refrescar()'::regprocedure);
  if position('v22.98-loc' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  if position(ancla in d) = 0 then raise exception 'gv_cobranza_deuda_viva_refrescar: no encontre el ancla, no se aplica'; end if;
  execute replace(d, ancla, paso || ancla);
end $patch$;
