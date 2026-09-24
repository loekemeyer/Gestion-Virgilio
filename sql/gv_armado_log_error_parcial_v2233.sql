-- v22.33 (Luis, 24/09/2026): el registro del armado automático marcaba "ok" corridas en las que
-- UNA empresa se había cortado por timeout (23/09 9-14 h: 30 corridas con LK cortado en verde).
-- 1) CHECK gv_tandas_auto_log_estado_chk suma 'error_parcial'
--    (sin esto el trigger hacía fallar el INSERT y la Edge Function se come el error: se perdía la fila).
-- 2) gv_tandas_auto_log_estado_real() (trigger zzz_estado_real, BEFORE INSERT): además del caso
--    'intradia_sin_umbral' → 'error' (feed caído, v19.58), 'ok'/'intradia_ok' con detalle->lk|chef->>'error'
--    → 'error_parcial', motivo "Se cortó: …". Las filas viejas NO se reescriben.
-- 3) gv_ppp_web_armado_salud: columna nueva cortes_12 (al final) y estado 'CORTADO: n de las ultimas
--    12 corridas…' por empresa cuando son >= 3. Conserva security_invoker.
-- Probado con INSERT reales en transacción abortada: los 4 casos (cortado, sano, feed caído, salteada).
alter table public."GV_Tandas_Auto_Log" drop constraint gv_tandas_auto_log_estado_chk;
alter table public."GV_Tandas_Auto_Log" add constraint gv_tandas_auto_log_estado_chk
  check (estado = any (array['ok','salteada','error','error_parcial','intradia_ok','intradia_sin_umbral']));
-- (cuerpo del trigger y de la vista: ver pg_get_functiondef / pg_get_viewdef; aplicados el 24/09)
