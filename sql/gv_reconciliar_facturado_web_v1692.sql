-- =====================================================================
--  gv_reconciliar_facturado_web() — v16.92 (2026-09-14)
--
--  Es la GEMELA de la etapa 3 de reconciliar_pipeline_stock() para las tandas
--  WEB (las que salen de PPP_Web_Programacion, con NP tipo 'LK 0003'), y tenía
--  EXACTAMENTE el mismo bug: el neto por tanda sumaba sólo 'separado' +
--  'facturado', así que un `ajuste` manual que ya había restado de `a_facturar`
--  era invisible y la misma caja se drenaba dos veces → saldo negativo.
--  Ver el encabezado de sql/reconciliar_pipeline_stock_v1692.sql para el
--  diagnóstico completo y las cifras medidas.
--
--  Fix (idéntico al de la otra): (a) entra 'ajuste'; (b) se atribuye a su tanda
--  aunque el ref sea texto libre ('… tanda D47C …'); (c) clamp contra el saldo
--  disponible del artículo, repartido con ventana acumulada cuando varias tandas
--  del mismo artículo caen en la misma corrida.
--
--  Rollback: sql/backups/gv_reconciliar_facturado_web_pre_v1692_20260914.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION public.gv_reconciliar_facturado_web()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare n3 int := 0;
begin
  with mov as (
    select cod_art as art, coalesce(empresa, 'Mixto') as empresa, delta,
           case
             when tipo = 'separado' then upper(trim(ref))
             -- v16.92: los ajustes manuales vienen con ref de texto libre.
             when tipo = 'ajuste'   then upper(coalesce(
                    nullif(substring(ref from 'tanda ([A-Za-z0-9]+)'), ''),
                    trim(split_part(ref, '|', 1))))
             else upper(trim(split_part(ref, '|', 1)))
           end as tanda
      from public."Movimientos_Stock"
     where deposito = 'a_facturar' and tipo in ('separado', 'facturado', 'ajuste')
  ),
  src as (
    select tanda, art, empresa, sum(delta) as net from mov group by 1, 2, 3
  ),
  saldo as (
    select cod_art as art, coalesce(empresa, 'Mixto') as empresa, sum(delta) as disp
      from public."Movimientos_Stock" where deposito = 'a_facturar' group by 1, 2
  ),
  tandanp as (
    select upper(btrim(w.tanda)) as tanda,
           upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)) as np
      from public."PPP_Web_Programacion" w
     where coalesce(nullif(btrim(w.tanda), ''), '') <> '' and w.np is not null
  ),
  cand as (
    select s.tanda, s.art, s.empresa, s.net, sa.disp
      from src s
      join saldo sa on sa.art = s.art and sa.empresa = s.empresa
     where s.net > 0 and sa.disp > 0
       and exists (select 1 from tandanp pp where pp.tanda = s.tanda)
       and not exists (select 1 from public."Movimientos_Stock" m
                        where m.tipo = 'facturado' and m.deposito = 'a_facturar'
                          and (upper(trim(m.ref)) = s.tanda or upper(trim(split_part(m.ref, '|', 1))) = s.tanda))
       and not exists (select 1 from tandanp pp
                        where pp.tanda = s.tanda
                          and not exists (select 1 from public."Facturacion_NP" f where upper(trim(f.np)) = pp.np))
  ),
  rep as (
    select c.*,
           greatest(0, least(c.net, c.disp - coalesce(sum(c.net) over (
             partition by c.art, c.empresa order by c.tanda
             rows between unbounded preceding and 1 preceding), 0))) as drenar
      from cand c
  )
  insert into public."Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, empresa)
  select r.art, 'a_facturar', -r.drenar, 'facturado',
         case when r.drenar < r.net then r.tanda||'|PARCIAL' else r.tanda end,
         'pipeline', r.empresa
    from rep r
   where r.drenar > 0
  on conflict do nothing;
  get diagnostics n3 = row_count;
  return format('ok facturado_web=%s', n3);
exception when others then
  return 'error: ' || sqlerrm;
end
$function$;
