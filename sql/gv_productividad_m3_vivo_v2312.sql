-- v23.12 (28/09): el RESUMEN SEMANAL de Telegram (reporte_semanal_telegram) salia con
-- "Equipo: 0 m³" y todos los operarios en 0 desde el 02/09.
-- Causa: vista_productividad_semanal sacaba los m³ de la tanda de "GV_PPP_Entregados_Historico",
-- el espejo del Sheet PPP Entregados, CONGELADO el 2026-09-02. Ninguna tanda nueva tenia m³.
-- Medido semana 21/09-27/09: 42 tandas con TP/TAP, 42 con m³ en vista_tanda_m3, 0 en el historico.
-- Arreglo: la CTE m3 lee vista_tanda_m3 (ISIS + web + historico, v16.44).
-- Lo usan: reporte_semanal_telegram y reporte_agentes_rendimiento_anomalo. Sin dependientes.
-- Se aplico sobre la definicion VIVA (pg_get_viewdef), manteniendo security_invoker.
do $x$ declare d text; n text; old_cte text;
begin
  d := rtrim(btrim(pg_get_viewdef('public.vista_productividad_semanal'::regclass, true)), ';');
  if d ~ 'FROM vista_tanda_m3' then raise notice 'ya aplicado'; return; end if;
  old_cte := substring(d from '(m3 AS \(\s*SELECT upper\(btrim\("GV_PPP_Entregados_Historico"\.tanda\)\).*?GROUP BY \(upper\(btrim\("GV_PPP_Entregados_Historico"\.tanda\)\)\)\s*\))');
  if old_cte is null then raise exception 'no matchea la CTE m3'; end if;
  n := replace(d, old_cte, 'm3 AS (
         SELECT upper(btrim(vista_tanda_m3.tanda)) AS tanda, max(vista_tanda_m3.m3) AS m3
           FROM vista_tanda_m3
          WHERE vista_tanda_m3.m3 > 0::numeric AND btrim(COALESCE(vista_tanda_m3.tanda, ''''::text)) <> ''''::text
          GROUP BY (upper(btrim(vista_tanda_m3.tanda)))
        )');
  execute 'create or replace view public.vista_productividad_semanal with (security_invoker = true) as ' || n;
end $x$;
-- Resultado 21/09-27/09: Equipo 48,34 m³ · 36 armadas · 41 pickeadas (antes 0 m³).
-- Chequeo: select public.reporte_semanal_telegram('2026-09-21', false);  -- NO encola
-- Rollback: la misma CTE leyendo "GV_PPP_Entregados_Historico" (ver sql/gv_productividad_horas_activas_v1923.sql).
