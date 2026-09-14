-- =====================================================================
--  BACKUP — definición VIVA de public.reconciliar_pipeline_stock() ANTES
--  de la v16.92 (2026-09-14). Volcada con pg_get_functiondef.
--
--  Para revertir: ejecutar este archivo tal cual en el SQL editor.
--
--  Lo que tenía de malo y por qué se cambió (ver sql/reconciliar_pipeline_stock.sql
--  y docs/SUPABASE-GESTION-VIRGILIO.md §3.bl):
--    • ETAPA 3 calcula el neto por tanda sumando SOLO 'separado' + 'facturado'.
--      Los movimientos 'ajuste' no entran, así que una corrección manual que
--      restó de a_facturar es INVISIBLE: la etapa sigue viendo net>0 y vuelve
--      a insertar el facturado → la misma caja se drena dos veces → negativo.
--    • ETAPA 4 sí suma 'ajuste', pero empareja por split_part(ref,'|',1), o sea
--      sólo si el ref arranca con el NP. Un ajuste con ref de texto libre
--      ("correccion 221 NP 98532: …") tampoco entra.
--    • Ninguna de las dos etapas mira el saldo disponible, así que nada impide
--      dejar a_facturar en negativo.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.reconciliar_pipeline_stock()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare
  v_cutoff timestamptz;
  n1 int := 0; n2 int := 0; n3 int := 0; n4 int := 0;
begin
  select coalesce((select valor::timestamptz from "Stock_Config" where clave='cutoff_ts'),
                  '2026-06-26 00:01:00-03'::timestamptz)
    into v_cutoff;

  n1 := public.reconciliar_pipeline_stock_etapa1();
  n2 := public.reconciliar_pipeline_stock_etapa2();

  -- ETAPA 3 — FACTURADO. v12.44: guard por tanda en CUALQUIER empresa (evita doble drenaje
  -- contra un facturado por-NP Mixto ya existente). La empresa correcta la lleva el INSERT.
  with src as (
    select case when tipo='separado' then upper(trim(ref))
                else upper(trim(split_part(ref,'|',1))) end tanda,
           cod_art art, coalesce(empresa,'Mixto') empresa, sum(delta) net
    from "Movimientos_Stock"
    where deposito='a_facturar' and tipo in ('separado','facturado')
    group by 1,2,3
  ),
  tandanp as (
    select upper(btrim(tanda)) tanda, btrim(np) np from "GV_PPP_Entregados_Historico" where coalesce(btrim(np),'')<>''
    union select upper(btrim(tanda)), btrim(np) from "GV_PPP_Programacion_Diaria" where coalesce(btrim(np),'')<>''
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select s.art, 'a_facturar', -s.net, 'facturado', s.tanda, 'pipeline', s.empresa
  from src s
  where s.net>0
    and not exists (select 1 from "Movimientos_Stock" m
                    where m.tipo='facturado' and m.deposito='a_facturar'
                      and (upper(trim(m.ref))=s.tanda or upper(trim(split_part(m.ref,'|',1)))=s.tanda))
    and exists (select 1 from tandanp pp where pp.tanda=s.tanda)
    and not exists (
      select 1 from tandanp pp
      where pp.tanda=s.tanda
        and not exists (select 1 from "Facturacion_NP" f where trim(f.np)=pp.np)
    )
  on conflict do nothing;
  get diagnostics n3 = row_count;

  -- ETAPA 4 — CP. v12.44: guard por np/tanda en cualquier empresa.
  with cp_nps as (
    select distinct upper(trim(split_part(ref,'|',1))) np
    from "Movimientos_Stock" where deposito='a_facturar' and tipo='cp'
  ),
  grp as (
    select upper(trim(split_part(m.ref,'|',1))) np, m.cod_art art, coalesce(m.empresa,'Mixto') empresa, sum(m.delta) net
    from "Movimientos_Stock" m
    where m.deposito='a_facturar' and m.tipo in ('cp','facturado','ajuste')
      and upper(trim(split_part(m.ref,'|',1))) in (select np from cp_nps)
    group by 1,2,3
  )
  insert into "Movimientos_Stock"(cod_art, deposito, delta, tipo, ref, ubicacion, legajo, empresa)
  select g.art, 'a_facturar', -g.net, 'facturado', g.np||'|CP', '__cp__', 'pipeline', g.empresa
  from grp g
  where g.net > 0
    and not exists (select 1 from "Movimientos_Stock" m2 where m2.tipo='facturado'
                    and m2.ref = g.np||'|CP')
    and exists (select 1 from "Facturacion_NP" f where trim(f.np)=g.np)
  on conflict do nothing;
  get diagnostics n4 = row_count;

  return format('ok etapa1=%s etapa2=%s etapa3=%s etapa4=%s cutoff=%s', n1, n2, n3, n4, v_cutoff::text);
exception when others then
  return 'error: '||sqlerrm;
end;
$function$;
