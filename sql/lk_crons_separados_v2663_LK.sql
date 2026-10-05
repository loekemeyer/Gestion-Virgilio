-- v26.63 (Luis, 2026-10-05, D5: "fijate que no se rompa nada y que el desfasaje tenga sentido")
-- PROYECTO LK (kwkclwhmoygunqmlegrg) — APLICADO el 05/10 ~11:35 ART.
--
-- Contexto: la base de LK dejó de responder de 10:35 a 11:18 (problema 701). En los minutos :06 y
-- :36 arrancaban juntos 4 jobs largos: 24 sync_pedidos_match_virgilio (6,4 s), 38 sincronizar_fact_live
-- (5,3 s, el que más escribe: 14 GB de WAL desde junio), 39 sync_reingresos_virgilio (9,9 s) y el 63
-- gv_watch_gestion_tick (3 s, cada minuto). Y 24 + 39 juntos en TODOS los :x1 / :x6.
--
-- Dependencias revisadas antes de mover (que el desfasaje tenga sentido):
--   · 24 lleva los pedidos web (LK por v_pedidos_match, Chef por v_pedidos_match_chef = FDW EN VIVO,
--     no la copia del cron 48) a lk_pedidos_match de Gestión. Lo lee el armado automático de Gestión
--     (cron 73, */5 → :00, :05, :10…). SE QUEDA en :01: 4 min antes de cada armado.
--   · 39 trae de Gestión los reingresos de importados (reingreso_cache, fecha estimada, ocultos de la
--     web). Lo usan la página (cartel) y el checkout (marcar_pedido_diferido). No depende de 24 ni
--     24 de él; 41 (sync_diferido) lee pedido_diferido CONGELADO, no reingreso_cache. Va a :03.
--   · 38 arma fact_live para reportes (Telegram 11:00 en adelante): sin dependencia de minuto. Va a :09/:39.
--
-- Resultado: tareas largas por minuto, peor caso 4 -> 2 (una sync + el watcher de cada minuto).
-- El :00 / :30 / :40 sigue con 9 jobs, pero son http_post de encolado (ms): no se tocó.

select cron.alter_job(39, schedule := '3-59/5 * * * *');   -- sync-reingresos-virgilio (antes 1-59/5)
select cron.alter_job(38, schedule := '9,39 * * * *');     -- sincronizar-fact-live   (antes 6,36)

-- Rollback:
-- select cron.alter_job(39, schedule := '1-59/5 * * * *');
-- select cron.alter_job(38, schedule := '6,36 * * * *');
