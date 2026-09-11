-- gv_app — de qué app salió cada evento de operario · 2026-09-08 · APLICADO
--
-- ── Por qué ────────────────────────────────────────────────────────────────────────────────
-- Desde el lunes 07/09 los operarios tienen que usar Gestión, no Producción. No había forma de
-- verificarlo: `Registros_Produccion_Virgilio` es la MISMA tabla para las dos apps y no guarda
-- nada que las distinga — ni URL, ni user_agent, ni versión. `Auditoria_Produccion_Virgilio`
-- tiene user_agent pero sólo se llena en reintentos y errores (0 filas el 08/09), y
-- `errores_cliente` sólo cuando algo se rompe.
--
-- El martes 08/09 lo único que se pudo probar fue por rebote: el legajo 277 pickeó y armó la
-- tanda E01D, que existe únicamente en `PPP_Web_Programacion` (0 filas en la
-- `PPP_Programacion_Diaria` de Producción). O sea que 277 estaba en Gestión, seguro. De 104, 237
-- y 8 no se pudo decir nada: trabajaron tandas de ISIS, que se ven igual desde las dos apps.
-- Ese día hubo UNA sola tanda de Gestión, así que la prueba no alcanzaba para el resto. El dueño,
-- preguntado, contestó "no sé" — de ahí esta columna.
--
-- ── Cómo funciona ──────────────────────────────────────────────────────────────────────────
-- Gestión manda `gv_app = 'gestion@' + APP_VERSION` en cada evento. Producción **no la manda y
-- no hay que tocarla**: su payload nombra las columnas una por una, así que sigue insertando
-- igual y su `gv_app` queda NULL. El contrato es entonces:
--
--     gv_app IS NULL      → lo mandó Producción Virgilio
--     gv_app LIKE 'gestion@%' → lo mandó Gestión, y dice con qué versión
--
-- La versión va de yapa y responde otra pregunta que estaba abierta: si al celular le bajó la
-- build nueva o quedó con una vieja cacheada en el Service Worker.
--
-- ── Por qué esto SÍ se puede sobre una tabla compartida ─────────────────────────────────────
-- El protocolo permite agregar una columna nullable, sin default que reescriba, sin backfill y
-- con prefijo `gv_`. Es exactamente eso. No hay trigger (prohibido sobre tabla compartida), no se
-- toca ninguna fila existente y no se modifica ningún objeto de Producción.
--
-- Verificado ANTES de correrlo, no después:
--   · Producción no hace `select *` sobre la tabla — sus 18 referencias en index.html,
--     productividad.html, recepcion.js y sw.js nombran columnas. El único `SELECT *` del repo
--     está comentado, en un SQL de rollback de 2026-08-13.
--   · Los grants son a nivel TABLA (anon/authenticated tienen INSERT sobre la tabla, no ACL por
--     columna), así que la columna nueva queda cubierta sola: no hace falta ningún grant.
--   · La policy de INSERT es `insert_all` con `with_check = true` — no enumera columnas, así que
--     no rechaza el payload nuevo.
--
-- ── Cómo se lee ────────────────────────────────────────────────────────────────────────────
--   select coalesce(gv_app, 'PRODUCCIÓN (sin sello)') as app, legajo, count(*)
--     from public."Registros_Produccion_Virgilio"
--    where created_at >= current_date and legajo not in ('0','1')
--    group by 1, 2 order by 3 desc;
--
-- ── Ojo al leerlo ──────────────────────────────────────────────────────────────────────────
-- Un celular que quedó con la build vieja de Gestión cacheada tampoco manda el sello, así que
-- durante los primeros días NULL es "Producción **o** Gestión desactualizada". Se despeja solo:
-- en cuanto ese celu tome la v14.51 empieza a sellar. Por eso el tag lleva la versión.
--
-- ROLLBACK:  alter table public."Registros_Produccion_Virgilio" drop column gv_app;
--            (y sacar `gv_app` de los dos payloads de index.html)

alter table public."Registros_Produccion_Virgilio"
  add column if not exists gv_app text;

comment on column public."Registros_Produccion_Virgilio".gv_app is
  'v14.51 — qué app mandó el evento, en la forma "gestion@vX.YZ". Producción Virgilio no la manda, así que NULL = Producción. Nullable, sin default y sin backfill a propósito: la tabla es compartida y sobre una tabla compartida sólo se AGREGA.';
