-- ════════════════════════════════════════════════════════════════════════════════════════════
-- v18.07 (Luis, 2026-09-15) — En Salida: días HÁBILES, la vista 4× más rápida, y el camionero
-- ════════════════════════════════════════════════════════════════════════════════════════════
-- Tres cosas, todas sobre objetos NUESTROS (`gv_*`), sin tocar nada de Producción:
--
--   (1) `dias_sin_controlar` pasa a contar días HÁBILES. Con calendario, un pedido cargado el
--       viernes mostraba 3 días el lunes y el chip ya salía en amarillo (salta a los 2) habiendo
--       pasado 1 solo día de trabajo. Con el feriado del 07/09 en el medio: 4 en vez de 1.
--
--   (2) PERFORMANCE: 451 ms → 113 ms (promedio de 5 corridas, 25 filas). El cuello NO eran los
--       cuatro escaneos de `Registros_Produccion_Virgilio` (2,9 ms): era `gv_ppp_entregados_meta`,
--       213 ms de los 410, y la vista la llamaba DOS veces. Se los lleva su CTE `vivo`, que hace
--       3 LATERAL por cada NP con CRN sólo para resolver cod/rs/tanda/m3 — datos que acá no se
--       usan. Y `vivo` ⊆ `crn`, que esta vista ya excluye con `k.np IS NULL`, así que para este
--       uso alcanza con leer `GV_PPP_Entregados_Historico` directo, con el MISMO filtro de espejo
--       y de `oculto`. Medido: 0 filas de diferencia en las 22 columnas comunes.
--
--   (3) Columna `camionero`, aditiva y al final. El dato YA viajaba en el evento desde la v11.47
--       (`texto = NP|TANDA|CAMIONERO`) y nadie lo leía. Las 25 NP de En Salida lo tienen cargado.
--       El front todavía NO lo pinta: queda listo para cuando se pida.
--
-- Rollback: la definición anterior está en `zz_backups."GV_Backup_Funcdefs_20260915"`.
--   select def from zz_backups."GV_Backup_Funcdefs_20260915" where objeto='gv_ppp_en_salida';
-- ════════════════════════════════════════════════════════════════════════════════════════════

-- ── (1) días hábiles entre dos fechas, sin contar el día de partida ──────────────────────────
-- Reusa `gv_es_dia_habil()`, que ya mira `planify.feriados` y `GV_Dias_No_Habiles`.
create or replace function public.gv_dias_habiles(p_desde date, p_hasta date)
returns integer language sql stable as $$
  select case when p_desde is null or p_hasta is null or p_hasta <= p_desde then 0
         else (select count(*)::int from generate_series(p_desde + 1, p_hasta, interval '1 day') d
                where public.gv_es_dia_habil(d::date))
         end;
$$;
grant execute on function public.gv_dias_habiles(date,date) to anon, authenticated;

-- control:
--   gv_dias_habiles('2026-09-11','2026-09-14') = 1   (viernes → lunes; calendario 3)
--   gv_dias_habiles('2026-09-04','2026-09-08') = 1   (lunes 7 = Día del Metalúrgico; calendario 4)
--   gv_dias_habiles('2026-09-10','2026-09-14') = 2   (jueves → lunes: sigue en amarillo, correcto)

-- ── (2) y (3) la vista ──────────────────────────────────────────────────────────────────────
create or replace view public.gv_ppp_en_salida with (security_invoker = true) as
WITH cfg AS (
  SELECT COALESCE((SELECT c_1.valor FROM "PPP_Web_Config" c_1 WHERE c_1.clave='salida_presunta_horas'),36::numeric) AS horas,
         COALESCE((SELECT c_1.valor FROM "PPP_Web_Config" c_1 WHERE c_1.clave='en_salida_solo_cargadas'),1::numeric) AS solo_cargadas
), man AS (
  SELECT regexp_replace(btrim(o.np),'\.0+$','') AS np, o.en_salida_fecha, o.nota
    FROM "GV_PPP_Prog_Override" o WHERE o.en_salida_manual AND NOT COALESCE(o.oculto,false)
), ccn AS (
  SELECT regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') AS np,
         max(NULLIF(upper(btrim(split_part(r.texto,'|',2))),'')) AS tanda_ccn,
         -- (3) el camionero: se toma el del ÚLTIMO CCN, que es el que vale si se recargó
         (array_agg(NULLIF(btrim(split_part(r.texto,'|',3)),'') ORDER BY r.ts_cliente DESC)
            FILTER (WHERE NULLIF(btrim(split_part(r.texto,'|',3)),'') IS NOT NULL))[1] AS camionero,
         min(r.ts_cliente) AS cargado_at, max(r.ts_cliente) AS ultima_carga_at,
         max((r.ts_cliente AT TIME ZONE 'America/Argentina/Buenos_Aires')::date) AS fecha_carga,
         count(*) AS n_ccn
    FROM "Registros_Produccion_Virgilio" r
   WHERE r.opcion='CCN' AND NOT es_legajo_test(r.legajo)
   GROUP BY 1
), tal AS (
  SELECT regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') AS np, max(r.ts_cliente) AS armado_at
    FROM "Registros_Produccion_Virgilio" r WHERE r.opcion='TAL' AND NOT es_legajo_test(r.legajo) GROUP BY 1
), ccr AS (
  SELECT DISTINCT regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') AS np
    FROM "Registros_Produccion_Virgilio" r WHERE r.opcion='CCR'
), fss AS (
  SELECT regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') AS np, max(r.ts_cliente) AS fss_at
    FROM "Registros_Produccion_Virgilio" r WHERE r.opcion='FSS' GROUP BY 1
), crn AS (
  SELECT DISTINCT regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') AS np
    FROM "Registros_Produccion_Virgilio" r WHERE r.opcion='CRN'
), hist AS (
  -- (2) ACÁ ESTABA EL COSTO: antes se leía `gv_ppp_entregados_meta`, y dos veces.
  SELECT DISTINCT regexp_replace(btrim(m.np),'\.0+$','') AS np, m.tanda, m.cod, m.rs, m.m3, m.fecha_entrega
    FROM "GV_PPP_Entregados_Historico" m CROSS JOIN gv_espejo_corte() c(lk,chef)
   WHERE gv_espejo_np_pasa(m.np,c.lk,c.chef)
     AND NOT EXISTS (SELECT 1 FROM "GV_PPP_Prog_Override" o
                      WHERE o.oculto AND o.np = regexp_replace(btrim(m.np),'\.0+$',''))
), meta AS (SELECT DISTINCT np FROM hist
), fact AS (
  SELECT regexp_replace(upper(btrim(f.np)),'\.0+$','') AS np, max(f.fecha_salida) AS facturada_el
    FROM "Facturacion_NP" f GROUP BY 1
), web AS (
  SELECT gv_ppp_web_np_label(p.empresa,p.np,p.np_idx) AS np, p.empresa, p.tanda, p.cod_cliente AS cod,
         p.razon_social AS rs, p.m3, p.fecha_entrega::text AS fecha_entrega, p.zona, p.barrio, p.direccion
    FROM "PPP_Web_Programacion" p
), isis AS (
  SELECT x.np,x.tanda,x.cod,x.rs,x.m3,x.fecha_entrega,x.zona,x.barrio,x.direccion,x.prio FROM (
      SELECT regexp_replace(btrim(g.np),'\.0+$','') AS np, g.tanda, g.cod, g.razon_social AS rs, g.m3,
             "left"(g.fecha_entrega,10) AS fecha_entrega, g.zona, g.barrio, g.direccion, 1 AS prio
        FROM gv_ppp_programacion_diaria g
      UNION ALL
      SELECT regexp_replace(btrim(f.np),'\.0+$',''), f.tanda, f.cod_cliente, f.razon_social, f.m3,
             f.fecha_salida::text, NULL::text, NULL::text, NULL::text, 2 FROM "Facturacion_NP" f
      UNION ALL
      -- misma fuente barata que `meta`; la rama 3 sólo resuelve datos de NP históricas
      SELECT e.np, e.tanda, e.cod, e.rs, e.m3, "left"(e.fecha_entrega,10), NULL::text, NULL::text, NULL::text, 3
        FROM hist e) x
), base AS (
  SELECT np FROM ccn UNION SELECT np FROM fact
  UNION SELECT t_1.np FROM tal t_1 CROSS JOIN cfg cfg_1
         WHERE t_1.armado_at < (now() - make_interval(hours => cfg_1.horas::integer))
  UNION SELECT np FROM man
)
SELECT b.np,
  COALESCE(w.empresa, CASE WHEN b.np ~ '^9' THEN 'lk' WHEN b.np ~ '^4' THEN 'chef' ELSE NULL END) AS empresa,
  w.np IS NOT NULL AS es_web,
  COALESCE(w.tanda,i.tanda,c.tanda_ccn) AS tanda,
  COALESCE(w.cod,i.cod) AS cod_cliente, COALESCE(w.rs,i.rs) AS razon_social, COALESCE(w.m3,i.m3) AS m3,
  COALESCE(w.fecha_entrega,i.fecha_entrega) AS fecha_entrega,
  COALESCE(w.zona,i.zona) AS zona, COALESCE(w.barrio,i.barrio) AS barrio, COALESCE(w.direccion,i.direccion) AS direccion,
  COALESCE(c.fecha_carga, mn.en_salida_fecha) AS fecha_carga, c.cargado_at, COALESCE(c.n_ccn,0::bigint) AS n_ccn,
  fa.np IS NOT NULL AS facturada, t.np IS NOT NULL AS armada, t.armado_at,
  c.np IS NOT NULL AS cargada, cr.np IS NOT NULL AS control_previo, fa.facturada_el,
  CASE WHEN c.np IS NOT NULL THEN 'cargada' WHEN mn.np IS NOT NULL THEN 'salida_manual'
       WHEN fa.np IS NOT NULL THEN 'facturada_sin_cargar' ELSE 'armada_sin_carga' END AS estado,
  -- (1) días HÁBILES
  public.gv_dias_habiles(COALESCE(c.fecha_carga, mn.en_salida_fecha,
      NULLIF("left"(COALESCE(w.fecha_entrega,i.fecha_entrega),10),'')::date), CURRENT_DATE) AS dias_sin_controlar,
  round(EXTRACT(epoch FROM now()-t.armado_at)/3600::numeric) AS horas_desde_armado,
  c.np IS NULL AND fa.np IS NULL AS salida_presunta,
  c.camionero
FROM base b CROSS JOIN cfg
  LEFT JOIN ccn c ON c.np=b.np
  LEFT JOIN tal t ON t.np=b.np
  LEFT JOIN ccr cr ON cr.np=b.np
  LEFT JOIN fact fa ON fa.np=b.np
  LEFT JOIN crn k ON k.np=b.np
  LEFT JOIN fss s ON s.np=b.np
  LEFT JOIN meta mt ON mt.np=b.np
  LEFT JOIN web w ON w.np=b.np
  LEFT JOIN man mn ON mn.np=b.np
  LEFT JOIN LATERAL (SELECT i1.np,i1.tanda,i1.cod,i1.rs,i1.m3,i1.fecha_entrega,i1.zona,i1.barrio,i1.direccion
                       FROM isis i1 WHERE i1.np=b.np ORDER BY i1.prio LIMIT 1) i ON true
WHERE k.np IS NULL AND mt.np IS NULL
  AND (s.fss_at IS NULL OR c.ultima_carga_at IS NOT NULL AND s.fss_at < c.ultima_carga_at)
  AND (w.np IS NOT NULL OR i.np IS NOT NULL)
  AND (cfg.solo_cargadas = 0::numeric OR c.np IS NOT NULL AND c.fecha_carga IS NOT NULL
       OR mn.np IS NOT NULL AND mn.en_salida_fecha IS NOT NULL)
  AND (c.np IS NOT NULL OR fa.np IS NOT NULL OR mn.np IS NOT NULL
       OR NULLIF("left"(COALESCE(w.fecha_entrega,i.fecha_entrega),10),'')::date < CURRENT_DATE)
  AND NOT EXISTS (SELECT 1 FROM "NP_Canceladas" nc WHERE regexp_replace(btrim(nc.np),'\.0+$','')=b.np)
  AND NOT EXISTS (SELECT 1 FROM "GV_Web_Cancelados" wc WHERE upper(btrim(wc.np_label))=upper(b.np));

-- ── controles corridos al aplicar (15/09) ───────────────────────────────────────────────────
-- filas 25 = 25, y 0 diferencias en las 22 columnas comunes (except en las dos direcciones)
-- 0 NP del histórico del Sheet coladas · 0 NP con CRN coladas
-- 25/25 con camionero (Eduardo 13, Guillermo 9, Nicolás 2, Edgardo 1)
-- security_invoker=true · anon: SELECT sí, INSERT/UPDATE no
-- gv_ppp_avance_dias(date,date) —única función que nombra la vista— LLAMADA y anda
