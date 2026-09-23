-- v21.48 — El refresco del stock ENCADENA stocks_carga_rapida (Thomas, 2026-09-23)
--
-- Thomas, textual: "todo el stock tiene que verse lo mas en vivo posible siempre".
--
-- LO QUE SE MIDIO, Y ES LO QUE MOTIVA EL CAMBIO
-- =============================================
-- La pantalla de Stocks NO lee `vista_saldos_stock` ni la matview: lee la tabla
-- `stocks_carga_rapida`. O sea que el dato llega a la pantalla por TRES saltos:
--
--   Movimientos_Stock  -->  vista_stock_procesada  -->  stocks_carga_rapida  -->  pantalla
--     (el libro, vivo)      cron 55, */2, condicional   cron 57, */5, SIEMPRE
--
-- Atraso maximo: 2 + 5 = SIETE MINUTOS. Y los dos crons no estan sincronizados, asi
-- que si el 57 corre justo antes de que el 55 refresque, se pagan los 7 completos.
-- El cron 57, ademas, reescribe la tabla cada 5 min mire o no si algo cambio:
-- 580 corridas / 324 s / 559 ms en una ventana de 47,9 h, con el mismo 94,5 % de
-- corridas inutiles que ya se le habia sacado al 55 en la v21.06/v21.31.
--
-- EL CAMBIO: reescribirla en la MISMA corrida que refresca la matview.
--   * frescura: 7 min -> 2 min en la pantalla que mira el operario
--   * costo: el 57 deja de reescribirla cuando no cambio nada
--
-- (v19.53 ya habia sacado de `refresh_stocks_carga_rapida` su propio REFRESH de la
--  matview, justamente porque el cron 55 la refresca. Este cambio cierra esa cadena
--  desde el otro lado.)
--
-- LAS TRES DECISIONES QUE NO SON OBVIAS
-- =====================================
-- 1. TRY, no el lock bloqueante. El advisory 5768 lo comparten el cron 57 y el 68
--    (reconciliar-pipeline-stock, */10). Esperarlo ocuparia uno de los SEIS worker
--    slots de la instancia -- el pozo del apagon del 17/09 en LK. Si no se consigue,
--    no pasa nada: el cron 57 la reescribe en su proxima corrida.
-- 2. FAIL-OPEN, con el fallo A LA VISTA. Si la derivada explota, la matview se
--    refresca igual y el motivo lo dice. Probado rompiendo `refresh_stocks_carga_rapida`
--    a proposito (perform 1/0) en transaccion abortada:
--      refrescada=true | motivo=piso de frescura (60 min) (carga_rapida fallo: division by zero)
--    Tapar un error sin dejar como enterarse es cambiar un error ruidoso por uno mudo
--    (regla de Elias, v20.58).
-- 3. EL CRON 57 NO SE APAGA. Queda como red: es el que cubre el caso del lock ocupado
--    y el del fallo. Bajarlo a */10 es un segundo paso, y no esta hecho.
--
-- VERIFICACION (corrida de verdad, 23/09)
-- =======================================
--   solo_medir            -> refrescada=false, motivo='sin cambios'            (NO encadena)
--   piso de frescura en 0 -> refrescada=true,  motivo='... + carga_rapida'     3.260 ms
--   stocks_carga_rapida   -> 367 filas, md5 3000430e5cfbde71e8b995819a3ce21e
--                            IDENTICA antes y despues: el encadenado adelanta el
--                            dato, no lo cambia.
--   gv_reglas_perdidas    -> vacia
--
-- ROLLBACK (una linea, la definicion anterior esta en el backup):
--   select def from zz_backups."GV_Backup_funcdef_20260923"
--    where objeto = 'gv_refresh_stock_si_cambio(int,boolean)';
--   -- y se ejecuta ese texto tal cual.
--
-- OJO: traer SIEMPRE la definicion VIVA antes de tocar esta funcion
-- (select pg_get_functiondef('public.gv_refresh_stock_si_cambio(int, boolean)'::regprocedure);)
-- Varias sesiones tocan los objetos de stock al mismo tiempo.

-- ---------------------------------------------------------------------------
-- El bloque que se agrego, DENTRO de la rama que ya refrescaba:
-- ---------------------------------------------------------------------------
--   if v_do and not p_solo_medir then
--     refresh materialized view concurrently public.vista_stock_procesada;
--
--     begin
--       if pg_try_advisory_xact_lock(5768) then
--         perform public.refresh_stocks_carga_rapida();
--         v_cr := ' + carga_rapida';
--       else
--         v_cr := ' (carga_rapida: lock ocupado, la toma el cron 57)';
--       end if;
--     exception when others then
--       v_cr := ' (carga_rapida fallo: ' || left(sqlerrm, 60) || ')';
--     end;
--   end if;
--
-- y `v_cr` se concatena al motivo en los dos lugares donde se sella
-- (`ultimo_motivo` de GV_Stock_Refresh_Estado y el `motivo` que devuelve).

-- ---------------------------------------------------------------------------
-- Centinelas (es un insert, no codigo)
-- ---------------------------------------------------------------------------
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_refresh_stock_si_cambio', 'funcion', 'refresh_stocks_carga_rapida',
        'El refresco de la matview encadena la reescritura de stocks_carga_rapida en la MISMA corrida: la pantalla de Stocks lee esa tabla, no la matview, y sin el encadenado el dato le llega con hasta 7 min (2 del cron 55 + 5 del 57).',
        'Thomas', 'v21.48'),
       ('gv_refresh_stock_si_cambio', 'funcion', 'pg_try_advisory_xact_lock',
        'El encadenado toma el 5768 con TRY, nunca con el lock bloqueante: ese lock lo comparten el cron 57 y el 68, y esperarlo ocuparia uno de los SEIS worker slots de la instancia.',
        'Thomas', 'v21.48')
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Chequeos
-- ---------------------------------------------------------------------------
-- select * from public.gv_reglas_perdidas;        -- vacia = todo bien
-- select * from public.gv_stock_refresh_salud;    -- ultimo_motivo tiene que decir '+ carga_rapida'
--                                                 -- cuando refresco; 'sin cambios' cuando salto.
