-- v20.35 — el DETALLE del Excel de deuda (comprobante por comprobante) deja de tirarse.
--
-- Luis, 2026-09-21: "el excel es el que se sube en configuracion de cuarentena". Correcto: el
-- Excel trae el detalle. El que lo tiraba era el front — cuarParseDeudaCrystal ya lee cada
-- renglon del Crystal (col E = comprobante, col L = pendiente) pero cuarImportGuardar mandaba
-- {cod, razon_social, deuda} y nada mas.
--
-- Cadena que esto habilita:
--   comprobante (saldo) -> factura de ISIS -> remito_ref -> GV_NP_Remito -> NP -> GV_NP_Sucursal

create table if not exists public."GV_Cuarentena_Deuda_Detalle" (
  id           bigserial primary key,
  empresa      text not null,
  cod          text not null,
  razon_social text,
  comprobante  text,
  comp_key     text,
  pendiente    numeric,
  fila         jsonb,          -- el renglon crudo del Excel: hoy se mapean 2 columnas, manana
  lote         text,           -- puede hacer falta la fecha de vencimiento o el importe original
  cargado_por  text,
  cargado_at   timestamptz not null default now()
);

alter table public."GV_Cuarentena_Deuda_Detalle" enable row level security;

do $$ begin
  if not exists (select 1 from pg_policy where polname = 'gv_cuar_deuda_detalle_lectura'
                   and polrelid = 'public."GV_Cuarentena_Deuda_Detalle"'::regclass) then
    create policy gv_cuar_deuda_detalle_lectura on public."GV_Cuarentena_Deuda_Detalle"
      for select to authenticated using (es_supervisor_virgilio());
  end if;
end $$;

grant select on public."GV_Cuarentena_Deuda_Detalle" to authenticated;
revoke insert, update, delete, truncate on public."GV_Cuarentena_Deuda_Detalle" from anon, authenticated;

create index if not exists gv_cuar_deuda_det_cod_idx  on public."GV_Cuarentena_Deuda_Detalle" (empresa, cod);
create index if not exists gv_cuar_deuda_det_comp_idx on public."GV_Cuarentena_Deuda_Detalle" (comp_key);

-- Clave de cruce: PREFIJO (FCA, NCA, FCCOMP...) + los digitos de punto de venta y numero.
create or replace function public.gv_comprobante_key(p_txt text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $function$
  select nullif(
    coalesce((regexp_match(upper(btrim(coalesce(p_txt, ''))), '^([A-Z]+)'))[1], '') || '-' ||
    regexp_replace(coalesce(p_txt, ''), '\D', '', 'g'), '-');
$function$;

create or replace function public.gv_cuarentena_deuda_detalle_cargar(
  p_empresa text, p_rows jsonb, p_lote text default null)
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare
  v_n integer;
  v_lote text := coalesce(nullif(trim(p_lote), ''),
                          to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYYMMDD"T"HH24MISS'));
  v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if not es_supervisor_virgilio() then
    raise exception 'Solo un supervisor puede importar reportes de cuarentena.' using errcode = '42501';
  end if;
  if p_empresa not in ('lk', 'chef') then raise exception 'empresa invalida: %', p_empresa; end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows debe ser un array jsonb'; end if;

  -- No aditiva, igual que gv_cuarentena_cargar: cada import borra y recarga su fuente.
  delete from public."GV_Cuarentena_Deuda_Detalle" where empresa = p_empresa;

  insert into public."GV_Cuarentena_Deuda_Detalle"
    (empresa, cod, razon_social, comprobante, comp_key, pendiente, fila, lote, cargado_por)
  select p_empresa,
         nullif(trim(r->>'cod'), ''),
         nullif(trim(r->>'razon_social'), ''),
         nullif(trim(r->>'comprobante'), ''),
         public.gv_comprobante_key(r->>'comprobante'),
         case when nullif(r->>'pendiente', '') is not null then (r->>'pendiente')::numeric end,
         r->'fila',
         v_lote, v_email
    from jsonb_array_elements(p_rows) as r
   where nullif(trim(r->>'cod'), '') is not null;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function public.gv_cuarentena_deuda_detalle_cargar(text, jsonb, text) from public, anon;
grant execute on function public.gv_cuarentena_deuda_detalle_cargar(text, jsonb, text) to authenticated;

-- La cadena completa, con estado_cadena diciendo donde se corta.
create or replace view public.gv_cuarentena_deuda_sucursal as
with doc as (
  select 'lk'::text as empresa,
         public.gv_comprobante_key(
           (case familia when 'factura_venta' then 'FC' when 'nc_venta' then 'NC'
                         when 'nd_venta' then 'ND' else 'XX' end)
           || coalesce(letra, '')
           || lpad(regexp_replace(coalesce(punto_venta, ''), '\D', '', 'g'), 4, '0')
           || lpad(regexp_replace(coalesce(numero, ''), '\D', '', 'g'), 8, '0')) as comp_key,
         fecha, total, remito_ref
    from isis_lk.documentos where familia in ('factura_venta', 'nc_venta', 'nd_venta')
  union all
  select 'chef'::text,
         public.gv_comprobante_key(
           (case familia when 'factura_venta' then 'FC' when 'nc_venta' then 'NC'
                         when 'nd_venta' then 'ND' else 'XX' end)
           || coalesce(letra, '')
           || lpad(regexp_replace(coalesce(punto_venta, ''), '\D', '', 'g'), 4, '0')
           || lpad(regexp_replace(coalesce(numero, ''), '\D', '', 'g'), 8, '0')),
         fecha, total, remito_ref
    from isis_ch.documentos where familia in ('factura_venta', 'nc_venta', 'nd_venta')
)
select d.empresa, d.cod, d.razon_social, d.comprobante, d.pendiente,
       doc.fecha as fecha_comprobante, doc.remito_ref, r.np,
       s.sucursal_entrega, s.direccion, s.dir_key, s.es_retira,
       case when doc.comp_key is null   then 'sin factura parseada'
            when doc.remito_ref is null then 'factura sin remito'
            when r.np is null           then 'remito sin NP'
            when s.np is null           then 'NP sin sucursal registrada'
            else 'ok' end as estado_cadena
  from public."GV_Cuarentena_Deuda_Detalle" d
  left join doc on doc.empresa = d.empresa and doc.comp_key = d.comp_key
  left join public."GV_NP_Remito" r
         on r.empresa = d.empresa
        and nullif(regexp_replace(coalesce(doc.remito_ref, ''), '\D', '', 'g'), '') =
            nullif(regexp_replace(coalesce(r.remito, ''), '\D', '', 'g'), '')
  left join public."GV_NP_Sucursal" s on s.empresa = d.empresa and s.np = r.np;

alter view public.gv_cuarentena_deuda_sucursal set (security_invoker = true);
grant select on public.gv_cuarentena_deuda_sucursal to authenticated;

-- Rollback:
--   drop view public.gv_cuarentena_deuda_sucursal;
--   drop function public.gv_cuarentena_deuda_detalle_cargar(text,jsonb,text);
--   drop table public."GV_Cuarentena_Deuda_Detalle";
