-- =============================================================================
-- gv_ppp_entregados_v1851.sql — LA MISMA VISTA, 28 VECES MÁS RÁPIDA (2026-09-15, v18.51)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · problema 285
-- =============================================================================
-- SÍNTOMA. 236 HTTP 500 en 6 horas sobre /rest/v1/gv_ppp_entregados (449 timeouts en total,
-- también el 14/09). El front (pppRefreshControlado, index.html) cae en silencio al fallback
-- de "CRN de 60 días" y Pedidos Entregados queda inconsistente con Programación.
--
-- CAUSA. El `LEFT JOIN LATERAL (select … from isis where np = c.np order by prio limit 1)`
-- se re-evaluaba por cada una de las ~460 NP con CRN, y `isis` es la UNION de tres fuentes,
-- una de las cuales (gv_ppp_entregados_meta) vuelve a agrupar Registros_Produccion_Virgilio
-- adentro: 124.761 bloques de heap POR VUELTA. EXPLAIN ANALYZE: 7.967 ms. El statement_timeout
-- de anon es 8 s (v18.22) → algunas corridas pasan, la mayoría no.
--
-- ARREGLO. La unión se materializa UNA vez (`isis_all … materialized`) y la fila de menor prio
-- por NP se elige con DISTINCT ON. Mismo resultado fila por fila (verificado con EXCEPT en las
-- dos direcciones: 0 y 0 sobre 457 filas). EXPLAIN ANALYZE: 283 ms.
--
-- Columnas, nombres y tipos IGUALES (create or replace lo exige); gv_ppp_avance_dias() la sigue
-- leyendo sin cambios. security_invoker se declara en el WITH y se refuerza con el ALTER de abajo.
--
-- ROLLBACK: sql/backups/gv_ppp_entregados_pre_v1851_20260915.sql (definición viva anterior).
-- =============================================================================

create or replace view public.gv_ppp_entregados
with (security_invoker = true) as
with crn as (
  select regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') as np,
         max(nullif(upper(btrim(split_part(r.texto,'|',2))),'')) as tanda_crn,
         min(r.ts_cliente) as controlado_at, count(*) as n_crn
  from "Registros_Produccion_Virgilio" r
  where r.opcion = 'CRN' and not es_legajo_test(r.legajo)
  group by 1),
web as (
  select gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np, p.empresa, p.tanda, p.cod_cliente as cod,
         p.razon_social as rs, p.m3, p.fecha_entrega::text as fecha_entrega
  from "PPP_Web_Programacion" p),
-- v18.51: la union de las 3 fuentes se materializa UNA vez y se elige la de menor prio por NP con
-- DISTINCT ON. Antes era un LEFT JOIN LATERAL (... ORDER BY prio LIMIT 1) que re-evaluaba la union
-- entera (incluida gv_ppp_entregados_meta, que adentro vuelve a agrupar Registros) por cada una de
-- las ~460 NP con CRN: 7.967 ms, contra los 8 s de statement_timeout de anon → HTTP 500. Ahora 283 ms.
isis_all as materialized (
  select regexp_replace(btrim(np),'\.0+$','') as np, tanda, cod, razon_social as rs, m3, left(fecha_entrega,10) as fecha_entrega, 1 as prio
    from gv_ppp_programacion_diaria
  union all
  select regexp_replace(btrim(np),'\.0+$',''), tanda, cod_cliente, razon_social, m3, fecha_salida::text, 2
    from "Facturacion_NP"
  union all
  select regexp_replace(btrim(np),'\.0+$',''), tanda, cod, rs, m3, left(fecha_entrega,10), 3
    from gv_ppp_entregados_meta),
isis as (
  select distinct on (np) np, tanda, cod, rs, m3, fecha_entrega, prio from isis_all order by np, prio),
ccn as (
  select regexp_replace(upper(btrim(split_part(texto,'|',1))),'\.0+$','') as np,
         max((ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_carga
  from "Registros_Produccion_Virgilio" where opcion = 'CCN' group by 1),
ent as (
  select regexp_replace(upper(btrim(np)),'\.0+$','') as np,
         sum(cajas_pedidas) as cajas_pedidas, sum(cajas_entregadas) as cajas_entregadas, sum(cajas_falto) as cajas_falto
  from "Entregas_Virgilio" group by 1),
fact as (
  select distinct regexp_replace(upper(btrim(np)),'\.0+$','') as np from "Facturacion_NP")
select c.np,
       coalesce(w.empresa, case when c.np ~ '^9' then 'lk' when c.np ~ '^4' then 'chef' else null end) as empresa,
       w.np is not null as es_web,
       coalesce(w.tanda, i.tanda, c.tanda_crn) as tanda,
       coalesce(w.cod, i.cod) as cod_cliente,
       coalesce(w.rs, i.rs) as razon_social,
       coalesce(w.m3, i.m3) as m3,
       coalesce(w.fecha_entrega, i.fecha_entrega) as fecha_entrega,
       cc.fecha_carga, c.controlado_at, c.n_crn,
       e.cajas_pedidas, e.cajas_entregadas, e.cajas_falto,
       f.np is not null as facturada
from crn c
left join web w on w.np = c.np
left join isis i on i.np = c.np
left join ccn cc on cc.np = c.np
left join ent e on e.np = c.np
left join fact f on f.np = c.np
where w.np is not null or i.np is not null;

alter view public.gv_ppp_entregados set (security_invoker = true);

-- Prueba: tiene que dar 0 y 0 (misma salida que la definición anterior) y correr en < 1 s.
-- explain (analyze) select np from public.gv_ppp_entregados;
