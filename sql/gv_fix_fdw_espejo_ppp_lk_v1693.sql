-- ============================================================================
-- v16.93 — El espejo PPP de LK estaba congelado desde el rename a GV_
--
-- Proyecto LK (kwkclwhmoygunqmlegrg) + grants en Virgilio (hrxfctzncixxqmpfhskv).
--
-- QUE PASO
-- La v16.x renombro en Virgilio:
--     PPP_Programacion_Diaria -> GV_PPP_Programacion_Diaria
--     PPP_Base_Pedidos        -> GV_PPP_Base_Pedidos
--     PPP_Entregados_Meta     -> GV_PPP_Entregados_Historico
-- Las foreign tables de LK (schema `virgilio`, server virgilio_db) siguieron
-- apuntando al nombre viejo, asi que fallaban con "relation does not exist".
--
-- Y no se notaba: el cron 19 de LK (sincronizar-ppp-diario, 10:00 UTC) figuraba
-- como `succeeded` todos los dias, porque cada bloque de public.sincronizar_ppp()
-- tiene su propio `EXCEPTION WHEN OTHERS` que se traga el error y deja la tabla
-- espejo con los datos viejos. Es EXACTAMENTE el pozo que avisa el comentario de
-- la propia funcion ("la caida de PPP_Pedidos_Entregados congelo TODAS las
-- tablas ppp_* durante 22 dias, en silencio").
--
-- Ademas habia tres bloques caidos por permisos del rol lk_ppp_reader.
--
-- COMO SE VE QUE ESTA BIEN:  select public.sincronizar_ppp();  -> "ok": true
-- ============================================================================

-- --- en VIRGILIO (hrxfctzncixxqmpfhskv) -------------------------------------
grant select on public."GV_PPP_Entregados_Historico" to lk_ppp_reader;
grant select on public."Facturacion_Cierres"         to lk_ppp_reader;
grant select on public.vista_facturacion_neto_items  to lk_ppp_reader;
grant select on public.cobranzas_precios             to lk_ppp_reader;
grant select on public."GV_Cliente_Razon_Social",
                public."GV_Precio_Facturado_Cache",
                public."GV_Precios_Cliente",
                public."GV_UxB",
                public.cobranzas_alias,
                public.precios_super_lk              to lk_ppp_reader;

-- --- en LK (kwkclwhmoygunqmlegrg) -------------------------------------------
alter foreign table virgilio.programacion_diaria options (set table_name 'GV_PPP_Programacion_Diaria');
alter foreign table virgilio.base_pedidos        options (set table_name 'GV_PPP_Base_Pedidos');
alter foreign table virgilio.entregados_meta     options (set table_name 'GV_PPP_Entregados_Historico');

select public.sincronizar_ppp();
-- resultado medido el 14/09 tras el fix:
-- {"ok": true, "base": 9781, "etapa": 29, "errores": {}, "np_feed": 1372,
--  "telefonos": 942, "entregados": 2783, "entregas_np": 1229,
--  "facturacion": 1237, "programacion": 133}

-- ROLLBACK (volver a los nombres viejos; el espejo se congela de nuevo)
--   alter foreign table virgilio.programacion_diaria options (set table_name 'PPP_Programacion_Diaria');
--   alter foreign table virgilio.base_pedidos        options (set table_name 'PPP_Base_Pedidos');
--   alter foreign table virgilio.entregados_meta     options (set table_name 'PPP_Entregados_Meta');
--   -- y en Virgilio: revoke select on <cada objeto> from lk_ppp_reader;

-- ⚠ PENDIENTE (no lo arregla este archivo): mientras sincronizar_ppp() siga
-- tragandose los errores con EXCEPTION WHEN OTHERS y devolviendo "succeeded",
-- el proximo rename vuelve a congelar el espejo sin que nadie se entere. El
-- cron tendria que fallar, o avisar, cuando `ok` viene en false.
