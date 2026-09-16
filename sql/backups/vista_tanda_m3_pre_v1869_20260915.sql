-- BACKUP de la definición viva de public.vista_tanda_m3 antes de la v18.69 (2026-09-15, pg_get_viewdef).
create or replace view public.vista_tanda_m3 with (security_invoker = true) as
 WITH ent AS (SELECT upper(btrim(m.tanda)) AS tanda, sum(m.m3) AS m3 FROM "GV_PPP_Entregados_Historico" m WHERE m.m3 > 0::numeric AND btrim(COALESCE(m.tanda, ''::text)) <> ''::text GROUP BY (upper(btrim(m.tanda)))),
 prog AS (SELECT upper(btrim(p_1.tanda)) AS tanda, sum(p_1.m3) AS m3 FROM gv_ppp_programacion_diaria p_1 WHERE p_1.m3 > 0::numeric AND btrim(COALESCE(p_1.tanda, ''::text)) <> ''::text GROUP BY (upper(btrim(p_1.tanda)))),
 web AS (SELECT upper(btrim(w.tanda)) AS tanda, sum(w.m3) AS m3 FROM "PPP_Web_Programacion" w WHERE w.m3 > 0::numeric AND btrim(COALESCE(w.tanda, ''::text)) <> ''::text GROUP BY (upper(btrim(w.tanda)))),
 u AS (SELECT ent.tanda FROM ent UNION SELECT prog.tanda FROM prog UNION SELECT web.tanda FROM web)
 SELECT u.tanda, round(COALESCE(e.m3, p.m3, b.m3), 3) AS m3, e.m3 IS NOT NULL AS entregado
   FROM u LEFT JOIN ent e ON e.tanda = u.tanda LEFT JOIN prog p ON p.tanda = u.tanda LEFT JOIN web b ON b.tanda = u.tanda
  WHERE COALESCE(e.m3, p.m3, b.m3) > 0::numeric;
alter view public.vista_tanda_m3 set (security_invoker = true);
