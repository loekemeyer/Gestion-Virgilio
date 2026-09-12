-- gv_fix_entregados_y_deadlock_v1633.sql — APLICADO 2026-09-12. Dos arreglos chicos.
--
-- ═══ 1) vista_ppp_pedidos_entregados tiraba 500 por una fecha vacía (problema 99) ═══
--
-- SÍNTOMA: `invalid input syntax for type date: ""`, 39 veces en 24 h, contra el select exacto
-- de `pppRefreshDelivered()` (index.html), o sea el panel **Entregados / En viaje** de la PPP.
-- Y pegaba CALLADO: el front usa `supaFetchAllSafe`, que se traga el error y devuelve `[]`, así
-- que el supervisor veía el panel vacío y creía que no había entregas.
--
-- CAUSA: `PPP_Programacion_Diaria.fecha_entrega` es TEXT y la vista hacía `::date` pelado.
-- 16 filas tienen cadena vacía (44620, 44621, 98585-98590, 98696-98703) — y `''` no es `null`,
-- así que un `where fecha is null` no las encuentra: por eso nadie las vio. Era intermitente
-- porque el LATERAL sólo evalúa las NP que matchean una fila facturada.
--
-- FIX: `nullif(btrim(...), '')::date`. El arreglo NO es limpiar los datos: es que la vista no
-- reviente con algo que la tabla permite guardar. El front ya tolera el null
-- (`String(r.fecha_ppp || "").slice(0,10)` da "").
--
-- BONUS: la vista viva NO tenía `security_invoker` (reloptions null) aunque
-- `sql/ppp_vistas_sheet.sql` dice que sí — o sea corría como `postgres` y salteaba la RLS.
-- Se prendió en el mismo paso, después de comprobar que `anon` lee las 5 tablas base completas
-- (Facturacion_NP 1228, Facturacion_Cierres 114, Entregas_Virgilio 10652,
-- Registros_Produccion_Virgilio 30936, PPP_Programacion_Diaria 133), así que no cambia nada
-- para la app.
--
-- MEDICIÓN: antes reventaba; después 1227 filas, y el select exacto del front corrido como
-- `anon` devuelve las mismas 1227 (57 con fecha_ppp, 1170 sin).
-- BACKUP: `zz_backups."GV_Backup_viewdef_ppp_entregados_20260912"`.

do $$
declare d text; viejo text; nuevo text;
begin
  d := pg_get_viewdef('public.vista_ppp_pedidos_entregados'::regclass, true);
  viejo := 'SELECT max(p.fecha_entrega::date) AS fecha_ppp';
  nuevo := 'SELECT max(nullif(btrim(p.fecha_entrega), ''''::text)::date) AS fecha_ppp';
  if position(viejo in d) = 0 then raise exception 'no se encontro el cast de fecha_ppp'; end if;
  execute 'create or replace view public.vista_ppp_pedidos_entregados '
       || 'with (security_invoker = true) as ' || replace(d, viejo, nuevo);
end $$;

-- Rollback:
--   create or replace view public.vista_ppp_pedidos_entregados as
--     (select def from zz_backups."GV_Backup_viewdef_ppp_entregados_20260912");

-- ═══ 2) Deadlock diario entre el cron 57 y el cron 68 (problema 98) ═══
--
-- SÍNTOMA: 11 deadlocks el 12/09, y la víctima siempre la misma:
--   Process A: SELECT public.refresh_stocks_carga_rapida()    <- cron 57 (*/5)
--   Process B: select public.reconciliar_pipeline_stock();    <- cron 68 (*/10)
-- Se traban actualizando las mismas filas de `stocks_carga_rapida` en orden distinto.
--
-- QUE SON LOS DOS CRONS: los 11 caen en minuto múltiplo de 10 — exactamente cuando */5 y */10
-- coinciden. Si el otro lado fuera un trigger de operario, los horarios serían al azar. Además
-- los dos casos que quedaron en el server log nombran textual el command del cron 68.
--
-- FIX: el candado va sobre el COMMAND DEL CRON, no sobre las funciones. pg_cron manda el
-- command como una sola simple-query, así que los dos statements corren en la MISMA transacción
-- implícita: el `pg_advisory_xact_lock` se toma antes y se suelta al commit. Si una está
-- corriendo, la otra espera en vez de trabarse. No se toca una línea de lógica y el rollback es
-- volver a poner el command viejo.
--
-- POR QUÉ NO ADENTRO DE LAS FUNCIONES: `reconciliar_pipeline_stock` la llaman además 3 triggers
-- de operario (`trg_entregas_reconciliar` sobre Entregas_Virgilio, y `trg_tp_reconciliar_etapa1`
-- sobre Registros_Produccion_Virgilio ×2). Meterles un candado bloqueante ahí haría que la
-- escritura de un operario espere a un cron que tarda hasta 24 s — en pleno picking. El costo
-- es peor que el problema. Queda como riesgo residual: un trigger todavía puede chocar con el
-- cron 57. Si a las 24 h siguen apareciendo deadlocks, mirar si el otro lado es un trigger.
--
-- BACKUP: `zz_backups."GV_Backup_cron_job_20260912"` (jobid, schedule, command, active).

select cron.alter_job(57, command :=
  $c$select pg_advisory_xact_lock(5768); select public.refresh_stocks_carga_rapida();$c$);
select cron.alter_job(68, command :=
  $c$select pg_advisory_xact_lock(5768); select public.reconciliar_pipeline_stock();$c$);

-- Rollback:
--   select cron.alter_job(57, command := (select command from
--     zz_backups."GV_Backup_cron_job_20260912" where jobid = 57));
--   select cron.alter_job(68, command := (select command from
--     zz_backups."GV_Backup_cron_job_20260912" where jobid = 68));

-- Verificación a las 24 h — las tres tienen que dar 0:
--   select count(*) from cron.job_run_details
--    where jobid in (55,57) and status='failed' and start_time > now() - interval '24 hours';
--   select * from public.gv_stock_procesada_dup;
--   (y en los logs: 0 'deadlock detected' y 0 'invalid input syntax for type date')
