-- v18.00 (2026-09-15) — COMPATIBILIDAD de nombres para la app Produccion-Virgilio.
--
-- Qué pasó: el 2026-09-12 (v16.3x) se renombraron las tablas PPP para sacarlas del desorden
-- de `public` y marcarlas como nuestras:
--     public."PPP_Programacion_Diaria" -> public."GV_PPP_Programacion_Diaria"
--     public."PPP_Base_Pedidos"        -> public."GV_PPP_Base_Pedidos"
-- Las VISTAS referencian por OID, así que no se enteraron; lo que nombra por TEXTO sí. Ese día
-- se reescribieron las 31 funciones y el front de Gestión — y ahí quedó el agujero: el front de
-- la app VIEJA (loekemeyer/produccion-virgilio, v12.78) no se tocó, y esa app SIGUE VIVA.
-- Medido el 15/09: 33 eventos con gv_app NULL (= Producción) en los últimos 3 días, el último
-- el 15/09 08:02.
--
-- Cómo se manifestó: el remito de armado impreso salía con "Cliente —" y "Fecha Entrega —",
-- porque el GET a /rest/v1/PPP_Programacion_Diaria devolvía 404 y la cabecera quedaba sin nada.
-- Caso testigo: NP 98626 (cod 4223, Iro Iro S.R.L), impreso el 15/09 08:41 desde
-- loekemeyer.github.io/Produccion-Virgilio/. Lo reportó Franco Tierra.
-- En esa app son 6 fetch a PPP_Programacion_Diaria y 9 a PPP_Base_Pedidos, TODOS de lectura
-- (ni un POST/PATCH/DELETE) — por eso acá se otorga SELECT y nada más: una vista simple es
-- auto-updatable, y sin el revoke quedaría una puerta de escritura que antes no existía.
--
-- ⚠ Apuntan a las vistas gv_* (las que aplican GV_PPP_Prog_Override), NO a las tablas crudas.
-- Tienen exactamente las mismas columnas, así que la app vieja no nota la diferencia, pero ve
-- la MISMA verdad que Gestión: sin las filas ocultas (NP de ISIS que duplican un pedido web ya
-- programado) y con la tanda/fecha pisadas. Con la tabla cruda, el remito de la 98626 habría
-- salido "D68B · 11/09" cuando la NP está reprogramada a "D71B · 17/09" — un remito con la
-- fecha vieja es peor que uno sin fecha. Al 15/09 la vista tapa 10 filas de programación
-- y 118 de base.
--
-- ⚠ ESTO ES UN PUENTE, NO ALGO DEFINITIVO. Thomas, 15/09: *"nueva página para mañana, no usen más
-- la otra, usá esta"* -> https://loekemeyer.github.io/Gestion-Virgilio/ desde el 16/09. Cuando esta
-- consulta dé 0 durante una semana, estas dos vistas se borran:
--   select count(*) from public."Registros_Produccion_Virgilio"
--    where gv_app is null and ts_cliente >= now() - interval '7 days';
--
-- ROLLBACK (el día que la app vieja se apague):
--   drop view if exists public."PPP_Programacion_Diaria";
--   drop view if exists public."PPP_Base_Pedidos";
-- Chequeo de que no rompió nada:  select * from public.gv_endpoints_rotos;   -- vacío = OK

create or replace view public."PPP_Programacion_Diaria" with (security_invoker = true) as
  select * from public.gv_ppp_programacion_diaria;

create or replace view public."PPP_Base_Pedidos" with (security_invoker = true) as
  select * from public.gv_ppp_base_pedidos;

revoke all on public."PPP_Programacion_Diaria" from anon, authenticated;
revoke all on public."PPP_Base_Pedidos"        from anon, authenticated;
grant select on public."PPP_Programacion_Diaria" to anon, authenticated;
grant select on public."PPP_Base_Pedidos"        to anon, authenticated;

comment on view public."PPP_Programacion_Diaria" is
  'v18.00 — compat de nombre para la app Produccion-Virgilio (v12.78), que pega por texto. Espejo de gv_ppp_programacion_diaria (con override). Solo SELECT. Borrar cuando esa app se apague.';
comment on view public."PPP_Base_Pedidos" is
  'v18.00 — compat de nombre para la app Produccion-Virgilio (v12.78), que pega por texto. Espejo de gv_ppp_base_pedidos (con override). Solo SELECT. Borrar cuando esa app se apague.';
