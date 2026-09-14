-- ============================================================================
-- v16.99 — La alarma de clientes en riesgo mira las DOS empresas juntas
--
-- Proyecto: LK (kwkclwhmoygunqmlegrg). Reemplaza la version de gv_clientes_riesgo
-- que dejo `sql/gv_cliente_canon_v1693.sql` (punto 5 de ese archivo).
--
-- POR QUE
-- Thomas (14/09): "Chef y LK usan codigos diferentes. Tenemos clientes que
-- compran en los dos, clientes que solo le compran a uno, clientes que antes le
-- compraban a uno y despues pasaron a comprarle al otro. Cada empresa usa su
-- propia convencion de codigos (un cliente que tiene codigo 102 en LK puede
-- estar en CH con codigo 333). Queremos hacer el analisis limpio (a lo mejor
-- pasaron de comprarle a LK a comprarle a CH y la venta real no cayo)."
--
-- La union por CUIT ya la hace gv_cliente_canon (un cliente = un cliente_id =
-- su CUIT, con el codigo que tenga en cada empresa). Al 14/09 hay 183 clientes
-- que facturan en las dos empresas y practicamente ninguno comparte numero:
-- Aboudi Moussa es chef:2648 / lk:1800, Aimetta es chef:2460 / lk:490, etc.
--
-- LO QUE CAMBIA ACA son dos cosas del informe:
--
--   1) UN SOLO CORTE CALENDARIO PARA TODOS. Antes cada empresa se comparaba
--      contra su propio ultimo mes. Asi no se puede ver una migracion: si el
--      cliente dejo LK en mayo y arranco en Chef en junio, con ventanas
--      corridas los dos movimientos no caen en el mismo trimestre. Ahora las
--      dos empresas se miden en los MISMOS meses.
--
--   2) COLUMNAS NUEVAS: `lk_ahora` / `lk_pico` / `ch_ahora` / `ch_pico` para ver
--      de donde sale cada caja, y `migracion` ('paso de LK a Chef' / 'paso de
--      Chef a LK') cuando una empresa bajo y la otra subio. Un cliente que
--      migro sigue apareciendo en la vista, pero con el cartel puesto: la venta
--      real no cayo, cambio de empresa.
--
--   3) `chef_incompleto`: el cliente factura por Chef pero NO tiene ninguna fila
--      de Chef despues del corte del feed de Chef (al 14/09, 2026-06). Ahi la
--      caida puede ser mentira y no hay con que probarlo.
--
-- ⚠ AL 14/09 LAS 3 "MIGRACIONES" Y LOS 7 `chef_incompleto` DE LA ALARMA SON EL
-- MISMO ARTEFACTO DE CARGA, NO MOVIMIENTOS COMERCIALES: los batches `julio_26`
-- y `ago-26` metieron facturas de Chef con empresa='lk' (19 y 21 codigos que
-- solo existen en el padron de Chef: Dorinka, Del Plastic, Ierakuin, Clapera,
-- Superimperio...). Hasta que eso se acomode, esas filas hay que leerlas con
-- esta nota al lado. Ver §3.ec de docs/SUPABASE-GESTION-VIRGILIO.md.
--
-- ROLLBACK: drop view if exists public.gv_clientes_riesgo;  y volver a crear la
-- del punto 5 de sql/gv_cliente_canon_v1693.sql.
-- ============================================================================

drop view if exists public.gv_clientes_riesgo;
create view public.gv_clientes_riesgo
with (security_invoker = true) as
with m as (
  select v.cliente_id, v.empresa, date_trunc('month', v.fecha)::date mes, sum(v.boxes) cajas
    from public.gv_ventas_cliente v group by 1, 2, 3
), corte as (
  -- UN solo corte calendario para todos: para ver si un cliente paso de LK a
  -- Chef hay que mirar las dos empresas en los MISMOS meses
  select max(mes) mes_corte from m
), kk as (
  select m.cliente_id, m.empresa,
         (extract(year  from age((select mes_corte from corte), m.mes)) * 12
        + extract(month from age((select mes_corte from corte), m.mes)))::int as k,
         sum(m.cajas) cajas
    from m group by 1, 2, 3
), serie as (
  select c.cliente_id, e.empresa, g.k, coalesce(sum(kk.cajas), 0) cajas,
         ((select mes_corte from corte) - (g.k || ' months')::interval)::date as mes
    from (select distinct cliente_id from m) c
    cross join (values ('lk'), ('chef')) e(empresa)
    cross join generate_series(0, 25) g(k)
    left join kk on kk.cliente_id = c.cliente_id and kk.empresa = e.empresa and kk.k = g.k
   group by 1, 2, 3, 5
), roll as (
  select cliente_id, empresa, k, mes,
         sum(cajas) over (partition by cliente_id, empresa order by k
                          rows between current row and 2 following) trim_emp
    from serie
), tot as (
  select cliente_id, k, min(mes) mes,
         sum(trim_emp)                               as trimestre,
         sum(trim_emp) filter (where empresa = 'lk')   as trim_lk,
         sum(trim_emp) filter (where empresa = 'chef') as trim_ch
    from roll group by 1, 2
), pico as (
  -- el pico se busca en ventanas que NO solapan con el trimestre actual
  -- (terminan 3 meses o mas atras): si no, un cliente que compra a saltos
  -- "cae" siempre
  select distinct on (cliente_id) cliente_id, mes mes_pico,
         trimestre pico, trim_lk pico_lk, trim_ch pico_ch
    from tot where k between 3 and 21 order by cliente_id, trimestre desc, k
), act as (
  select cliente_id, trimestre trim_actual, trim_lk act_lk, trim_ch act_ch from tot where k = 0
), gap as (
  select c.cliente_id,
         (exists (select 1 from m where m.cliente_id = c.cliente_id and m.empresa = 'chef'
                    and m.mes > (select mes_corte from corte) - interval '12 months')
      and not exists (select 1 from m where m.cliente_id = c.cliente_id and m.empresa = 'chef'
                    and m.mes > (select mes_corte from public.gv_ventas_corte_empresa where empresa = 'chef'))
         ) as chef_incompleto
    from (select distinct cliente_id from m) c
)
select n.cliente, a.cliente_id,
       a.trim_actual::int, p.pico::int, to_char(p.mes_pico, 'YYYY-MM') as mes_pico,
       round(100.0 * (a.trim_actual - p.pico) / nullif(p.pico, 0))::int as caida_pct,
       a.act_lk::int as lk_ahora, p.pico_lk::int as lk_pico,
       a.act_ch::int as ch_ahora, p.pico_ch::int as ch_pico,
       case when a.act_lk < p.pico_lk and a.act_ch > p.pico_ch then 'pasó de LK a Chef'
            when a.act_ch < p.pico_ch and a.act_lk > p.pico_lk then 'pasó de Chef a LK'
            else null end as migracion,
       g.chef_incompleto,
       (select max(fecha) from public.gv_ventas_cliente v where v.cliente_id = a.cliente_id) as ultima_compra
  from act a
  join pico p using (cliente_id)
  join gap  g using (cliente_id)
  join (select distinct cliente_id, cliente from public.gv_cliente_canon) n on n.cliente_id = a.cliente_id
 where a.trim_actual > 0 and p.pico > 0;

comment on view public.gv_clientes_riesgo is
  'v16.99 - clientes cayendo, por CUIT y con las dos empresas en los mismos meses. migracion avisa si la venta se paso de una empresa a la otra (no cayo); chef_incompleto avisa que al feed de Chef le faltan meses. Filtro tipico: pico >= 300 and caida_pct <= -30.';

-- ---------------------------------------------------------------------------
-- Medido al 2026-09-14 (pico >= 300 y caida <= -30 %):
--   40 clientes en la alarma · 3 con migracion · 7 con chef_incompleto ·
--   33 caida limpia. Los 3 + 7 son TODOS del artefacto julio_26 / ago-26.
--   Cencosud: 3.965 vs 4.664 = -15 %, todo por Chef, sin migracion -> NO esta
--   cayendo, y no aparece en la alarma. Relca no aparece: no vende por LK.
-- ---------------------------------------------------------------------------
