-- v27.81 (Luis, 07/10, D8) · Gestión. gv_ppp_entregados_meta: 741 ms -> 35 ms, mismas 3.192 filas
-- (EXCEPT ALL 0 en las dos direcciones, medido como anon). Cambios: short-circuit del espejo
-- (canilla abierta = no se llama gv_espejo_np_pasa por fila, mismo pozo que v20.78) y cada tabla
-- (programación ISIS, programación web, Facturacion_NP) se lee UNA vez y se cruza por hash, en vez
-- de un LATERAL por cada CRN. security_invoker se conserva. Centinela 347.
-- Rollback: el CREATE anterior (laterales) está en pg_get_viewdef de antes; el de abajo es el vivo.
create or replace view public.gv_ppp_entregados_meta with (security_invoker = true) as
 WITH c AS (select * from gv_espejo_corte() c(lk, chef)),
 hist AS MATERIALIZED (
  SELECT m.np, m.cod, m.rs, m.updated_at, m.tanda, m.m3, m.fecha_entrega, 'hoja'::text AS fuente,
         regexp_replace(btrim(m.np), '\.0+$', '') AS npk
  FROM "GV_PPP_Entregados_Historico" m CROSS JOIN c
  WHERE ((c.lk is null and c.chef is null) or gv_espejo_np_pasa(m.np, c.lk, c.chef))
    AND NOT EXISTS (SELECT 1 FROM "GV_PPP_Prog_Override" o WHERE o.oculto AND o.np = regexp_replace(btrim(m.np), '\.0+$', ''))),
 crn AS MATERIALIZED (
  SELECT regexp_replace(upper(btrim(split_part(r.texto,'|',1))), '\.0+$', '') AS np, max(r.ts_cliente) AS ts,
         max((r.ts_cliente AT TIME ZONE 'America/Argentina/Buenos_Aires')::date) AS fecha
  FROM "Registros_Produccion_Virgilio" r
  WHERE r.opcion='CRN' AND NULLIF(btrim(COALESCE(r.texto,'')),'') IS NOT NULL AND NOT es_legajo_test(r.legajo)
  GROUP BY 1),
 k AS MATERIALIZED (select crn.* from crn where not exists (select 1 from hist h where h.npk = crn.np)),
 i AS MATERIALIZED (select distinct on (npk) regexp_replace(btrim(g.np), '\.0+$', '') AS npk, g.cod, g.razon_social, g.tanda, g.m3
        from gv_ppp_programacion_diaria g where regexp_replace(btrim(g.np), '\.0+$', '') in (select np from k)),
 w AS MATERIALIZED (select distinct on (lbl) gv_ppp_web_np_label(p.empresa,p.np,p.np_idx) AS lbl, p.cod_cliente, p.razon_social, p.tanda, p.m3
        from "PPP_Web_Programacion" p),
 f AS MATERIALIZED (select distinct on (npk) regexp_replace(upper(btrim(x.np)), '\.0+$', '') AS npk, x.cod_cliente, x.razon_social, x.tanda, x.m3
        from "Facturacion_NP" x),
 vivo AS (SELECT k.np, COALESCE(i.cod, w.cod_cliente, f.cod_cliente) AS cod, COALESCE(i.razon_social, w.razon_social, f.razon_social) AS rs,
   k.ts AS updated_at, COALESCE(i.tanda, w.tanda, f.tanda) AS tanda, COALESCE(i.m3, w.m3, f.m3) AS m3, k.fecha::text AS fecha_entrega, 'remito'::text AS fuente
   FROM k LEFT JOIN i ON i.npk=k.np LEFT JOIN w ON w.lbl=k.np LEFT JOIN f ON f.npk=k.np)
 SELECT np, cod, rs, updated_at, tanda, m3, fecha_entrega, fuente FROM hist
 UNION ALL SELECT np, cod, rs, updated_at, tanda, m3, fecha_entrega, fuente FROM vivo;
