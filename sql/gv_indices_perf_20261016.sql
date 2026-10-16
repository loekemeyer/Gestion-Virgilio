-- v31.37 (16/10/2026) — índices aditivos de la revisión de ineficiencias. Aplicados con CONCURRENTLY.
-- vista_ppp_pedidos_entregados: 1.770 → 167 ms
create index concurrently if not exists idx_rpv_ccn_np on public."Registros_Produccion_Virgilio" (btrim(split_part(texto, '|', 1))) where opcion = 'CCN';
-- gv_analisis_badge: 2.623 → 84 ms
create index concurrently if not exists gv_pk_paso_ev_mostrado on public."GV_Picking_Paso_Evento" (upper(btrim(tanda)), paso, legajo, ts_cliente) where evento = 'mostrado';
-- gv_vista_control_remitos: 213 → 11 ms
create index concurrently if not exists entregas_virgilio_np_norm_idx on public."Entregas_Virgilio" (regexp_replace(btrim(np), '\.0+$', ''));
create index concurrently if not exists facturacion_np_np_norm_idx on public."Facturacion_NP" (regexp_replace(btrim(np), '\.0+$', ''));
-- crons movidos de minuto (misma frecuencia), por MODULO-CRON.md: 25,34 → 1-59/2 · 87 → 1-51/10 · 95 → 9-59/10
-- 26 → 3-53/10 · 162 → 4-54/10 · 61 → 2-59/15 · 69 → 11-59/15 · 92 → 6-59/15
