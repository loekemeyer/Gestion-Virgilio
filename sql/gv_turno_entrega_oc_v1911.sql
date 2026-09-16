-- =============================================================================
-- gv_turno_entrega_oc_v1911.sql — v19.11 (2026-09-16)
--
-- DOS BUGS Y UNA FUNCIONALIDAD, todo sobre el mismo dato: el TURNO que pide la OC
-- de un súper (fecha y hora de entrega pactada).
--
-- Thomas, 16/09: *"justificativo de por qué cada uno de estos no fue programado
-- automáticamente. Del pedido de Inc Sociedad Anonima deberíamos tener el dato de la
-- fecha y hora de entrega (el turno que figura en el pedido). ¿Por qué no aparece?"*
--
-- ── (1) EL FEED WEB DE LK AL ARMADO DE GESTIÓN SE MATABA CON EL TURNO ─────────
-- `gv_pedidos_web_np_lk` (LK) devolvía `fecha_entrega_pactada` casteando el TEXTO
-- CRUDO de `orders.sheets_payload->>'fecha_entrega'` con `::date`. El pedido 1468
-- (INC, OC de Krikos) entró el 16/09 a las 13:53 ART con **"29/09/2026 14:00"** y
-- ese cast tira `22008 date/time field value out of range` (el datestyle del
-- proyecto no es DMY, así que el 29 lo lee como mes).
--
-- Consecuencia medida en `GV_Tandas_Auto_Log`: de las 13:55 a las 15:50 las **24
-- corridas seguidas** del cron 73 leyeron **0 NP de LK** (`{"lk":{"error":"…22008…"}}`)
-- y quedaron en `intradia_sin_umbral` con "pendiente automático 0.000 m³". O sea:
-- **ningún pedido web de LK se programó solo durante 2 horas** (LK 1470, que entró
-- 15:01, quedó en A Programar sin NP). Un solo pedido con turno dd/mm/yyyy apagaba
-- el armado automático de la empresa entera.
--
-- El mismo cast estaba en `gv_pedidos_web_np_chef` y `gv_pedidos_web_np_chef_fdw`:
-- la misma bomba esperando la primera OC de súper cargada por el portal de Chef.
--
-- El parseo bueno YA existía en `v_pedidos_match` (v13.77) y nadie lo reusó. Ahora
-- vive en UNA función (`gv_fe_pactada_fecha`) que además NUNCA falla: lo que no
-- entiende devuelve NULL.
--
-- ── (2) EL TURNO NO SE VEÍA EN NINGUNA PANTALLA ───────────────────────────────
-- `fecha_entrega_pactada` sólo salía por la RPC del job… que **no la usa** (el único
-- consumidor era el contador `con_fecha_pactada` del modo dry de la Edge Function).
-- La vista que lee el front de A Programar, `v_pedidos_web_np`, no la tenía, así que
-- el INC mostraba el reloj en "----" teniendo el turno cargado en el pedido. Y el
-- `::date` encima tiraba la HORA a la basura, que para un súper es la mitad del dato.
-- Ahora la vista publica `fecha_entrega_txt` (crudo), `fecha_entrega_pactada` y
-- `hora_entrega_pactada`, y el badge del reloj de A Programar los muestra (v19.11 de
-- `index.html`, `aprTurnoOc` / `aprHorBadge`; el horario cargado a mano MANDA).
--
-- ── (3) EL CHIP "DÍA DE SALIDA" DE A PROGRAMAR ESTABA MUERTO ─────────────────
-- `gv_ppp_web_dia_salida` (Virgilio) es justo el "justificativo" que pedía Thomas:
-- por pedido dice si lo agarra el automático y cuándo, o por qué no (retenido,
-- retira, súper, sin zona, sin camión). Desde la v18.77 castea `order_id` a bigint
-- para mirar `GV_PPP_Web_Retenido`, pero el front manda TAMBIÉN las NP de ISIS, que
-- disfraza de pedido con `order_id = 'np' || np` (`aprTraerIsis`). `'np98704'::bigint`
-- tira `22P02`, la RPC entera devuelve 400, `aprCargarSalida` cae al catch y
-- `_apr.salida` queda vacío: **ninguna** tarjeta mostraba su motivo, todas quedaban
-- en "🚚 …" con el title "calculando el día de salida…". Con 5 NP de ISIS sin tanda
-- (hoy) estaba roto siempre.
--
-- PROBLEMAS AUDITADOS: 357 (pagina-lk-copia) y 358 (gestion-virgilio).
--
-- ⚠ POR QUÉ ESTO SON `DO` BLOCKS Y NO UN `CREATE` PEGADO: los tres feeds cambiaron
-- varias veces desde que el repo guardó su texto (`sql/gv_pedidos_web_np_feeds.sql`
-- es del 04/09 y ya no coincide con lo vivo). Un parche sobre `pg_get_functiondef`
-- toca LO QUE ESTÁ, no una foto vieja, y si el ancla no está **falla** en vez de
-- pisar silenciosamente. Es el mismo loop que usa el repo para renombrar tablas.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PROYECTO LK (kwkclwhmoygunqmlegrg)
-- ─────────────────────────────────────────────────────────────────────────────

-- 1) el parseo del turno, en un solo lugar y sin poder fallar
create or replace function public.gv_fe_pactada_fecha(p_txt text)
returns date language sql immutable
set search_path to 'public'
as $fn$
  /* v19.11 — LA FECHA DE ENTREGA PACTADA (el turno del super) NO SE CASTEA CON ::date.
     sheets_payload->>'fecha_entrega' es TEXTO CRUDO y viene como lo escribe la OC de
     Krikos: "29/09/2026 14:00". Un ::date sobre eso tira 22008 ("date/time field value
     out of range") y el 16/09/2026 a las 13:55 mato el feed entero de pedidos web de LK
     al armado de Gestion (24 corridas seguidas leyendo 0 NP). Mismo parseo que ya usaba
     v_pedidos_match: primera dd/mm/yyyy del texto, separador normalizado; ademas acepta
     ISO. Lo que no se entiende devuelve NULL, nunca un error. */
  select case
           when p_txt ~ '\d{1,2}[/.-]\d{1,2}[/.-]\d{4}'
             then to_date(translate(substring(p_txt, '\d{1,2}[/.-]\d{1,2}[/.-]\d{4}'), '.-', '//'), 'DD/MM/YYYY')
           when btrim(coalesce(p_txt,'')) ~ '^\d{4}-\d{2}-\d{2}'
             then substring(btrim(p_txt), 1, 10)::date
         end
$fn$;

create or replace function public.gv_fe_pactada_hora(p_txt text)
returns text language sql immutable
set search_path to 'public'
as $fn$
  /* La HORA del turno, si la OC la trae ("29/09/2026 14:00" -> "14:00"). El ::date de
     antes la tiraba a la basura, y para un super la hora es la mitad del dato. */
  select substring(coalesce(p_txt,''), '([0-2]?[0-9]:[0-5][0-9])')
$fn$;

-- Son parsers puros de su argumento: no leen ninguna tabla, asi que quedan con el
-- EXECUTE que Postgres le da a PUBLIC sin exponer nada.
-- Prueba:
--   select gv_fe_pactada_fecha('29/09/2026 14:00'),  -- 2026-09-29
--          gv_fe_pactada_hora ('29/09/2026 14:00'),  -- 14:00
--          gv_fe_pactada_fecha('15.09.2026 08:00'),  -- 2026-09-15
--          gv_fe_pactada_fecha('2026-09-29'),        -- 2026-09-29
--          gv_fe_pactada_fecha('cuando puedas');     -- null (NO explota)

-- 2) los tres feeds dejan de castear el texto crudo
do $mig$
declare r record; v_def text; v_new text;
begin
  for r in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname in ('gv_pedidos_web_np_lk','gv_pedidos_web_np_chef','gv_pedidos_web_np_chef_fdw')
  loop
    v_def := pg_get_functiondef(r.oid);
    v_new := regexp_replace(v_def,
      'nullif\(coalesce\(([a-z])\.sheets_payload->>''fecha_entrega'',\s*[a-z]\.sheets_payload->>''fechaEntrega''\),\s*''''\)::date',
      'public.gv_fe_pactada_fecha(coalesce(\1.sheets_payload->>''fecha_entrega'', \1.sheets_payload->>''fechaEntrega''))',
      'g');
    if v_new = v_def then
      raise exception 'no matcheo el cast en %', r.oid::regprocedure;
    end if;
    execute v_new;                      -- OR REPLACE: conserva los grants y el search_path
    raise notice 'reemplazada %', r.oid::regprocedure;
  end loop;
end
$mig$;

-- Verificación (la que importa: LLAMAR a la función, no leerla):
--   select count(*) filas, count(fecha_entrega_pactada) con_pactada
--     from gv_pedidos_web_np_lk(current_date - 30);
--   -- 377 filas, 1 con turno (el 1468 -> 2026-09-29). Antes: HTTP 400 22008.

-- 3) la vista que lee el front publica el turno (crudo + fecha + hora)
do $mig$
declare v_def text;
begin
  v_def := rtrim(btrim(pg_get_viewdef('public.v_pedidos_web_np'::regclass, true)), ';');
  execute 'create or replace view public.v_pedidos_web_np as
    select g.*,
           fe.txt                              as fecha_entrega_txt,
           public.gv_fe_pactada_fecha(fe.txt)  as fecha_entrega_pactada,
           public.gv_fe_pactada_hora(fe.txt)   as hora_entrega_pactada
      from (' || v_def || ') g
      left join lateral (
        select nullif(coalesce(o.sheets_payload->>''fecha_entrega'',
                               o.sheets_payload->>''fechaEntrega''), '''') as txt
          from public.orders o
         where o.id = g.order_id
      ) fe on true';
  /* ⚠ CREATE OR REPLACE VIEW sin WITH (...) BORRA las reloptions: sin esta linea la
     vista pierde security_invoker y pasa a correr como postgres, salteando la RLS. */
  execute 'alter view public.v_pedidos_web_np set (security_invoker = true)';
end
$mig$;

-- Las 3 columnas van AL FINAL: CREATE OR REPLACE VIEW sólo permite agregar, y así
-- ningún consumidor de `select *` se mueve. El `left join lateral` contra `orders`
-- corre con la RLS del que consulta (security_invoker): si no ve el pedido, el turno
-- viene NULL, no da error.
-- Medido: 499 NP de los últimos 45 días, 1 con turno (LK 1468, INC → 29/09 14:00);
-- el resto NULL porque sólo las OC de súper (Krikos) traen turno.

-- ─────────────────────────────────────────────────────────────────────────────
-- PROYECTO VIRGILIO (hrxfctzncixxqmpfhskv)
-- ─────────────────────────────────────────────────────────────────────────────

-- 4) el chip "día de salida" no se rompe con las NP de ISIS
do $mig$
declare v_def text; v_new text;
begin
  v_def := pg_get_functiondef('public.gv_ppp_web_dia_salida(jsonb,timestamp with time zone)'::regprocedure);
  v_new := replace(v_def,
    'nullif(x.v->>''order_id'','''')::bigint as order_id',
    'case when x.v->>''order_id'' ~ ''^[0-9]+$'' then (x.v->>''order_id'')::bigint end as order_id');
  if v_new = v_def then raise exception 'no matcheo el cast de order_id'; end if;
  execute v_new;
end
$mig$;

-- Verificación: la lista real de A Programar, con una NP de ISIS en el medio.
--   select * from gv_ppp_web_dia_salida('[
--     {"zona":"Zona 1 - CABA Sur","m3":0.308,"empresa":"lk","order_id":1364},
--     {"zona":"Zona 1 - CABA Sur","m3":0.3,"empresa":"lk","order_id":"np98704"},
--     {"zona":"Retira","m3":0.024,"empresa":"lk","order_id":1416},
--     {"zona":"Super","m3":4.272,"empresa":"lk","order_id":1468},
--     {"zona":"Zona 1 - CABA Sur","m3":0.171,"empresa":"lk","order_id":1470}]'::jsonb);
--   -- retenido / job 23-09 / retira / super / job 23-09   (antes: 22P02 y 400)

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK
-- ─────────────────────────────────────────────────────────────────────────────
-- (4) y (2) son el mismo replace al revés (volver a poner el `::date` y el
--     `nullif(...)::bigint`); (3) es `create or replace view` con la definición sin
--     el `select g.*, fe.…` de arriba, y de nuevo el `alter view … security_invoker`.
--     Nada de esto toca datos: son funciones y una vista.
-- ⚠ NO conviene volver atrás (1): el rollback reinstala la bomba que apaga el armado
--     automático de LK la próxima vez que un súper mande un turno en dd/mm/yyyy.
