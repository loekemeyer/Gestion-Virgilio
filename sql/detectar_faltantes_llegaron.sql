-- ═══════════════════════════════════════════════════════════════════════════════════════════
--  detectar_faltantes_llegaron.sql — cron 34: faltantes que se pueden COMPLETAR
--
--  ⚠⚠ v19.46 (2026-09-17) — ESTA FUNCIÓN ERA LA QUE TIRABA TIMEOUTS EN TODA LA APP.
--
--  Lo reportó Luis con una captura: tocar «Sí, cancelar» en la NP 98507 contestaba
--  **«canceling statement due to statement timeout»**. La RPC de cancelar tarda **1,3 s** con
--  la base tranquila (medido: es_supervisor 2 ms + gv_ppp_pedido_nps 17 ms +
--  gv_ppp_np_devolucion 363 ms + gv_ppp_np_desarmar 892 ms), así que el problema **no era ella**:
--  era que la base estaba ocupada y una RPC de 1,3 s no llega a entrar en los **8 s** de
--  `statement_timeout` del rol `authenticated`.
--
--  Quién la ocupaba, medido con `pg_stat_statements` (ventana del 12/09 14:53 al 17/09 15:12,
--  o sea 120 h de reloj):
--
--  | consulta | llamadas | media | máx | TOTAL ejecutado |
--  |---|---|---|---|---|
--  | `detectar_faltantes_llegaron()` | 3.606 | **64,7 s** | 110 s | **233.157 s = 64,8 h** |
--
--  **64,8 h de ejecución en 120 h de reloj = el 54 % del tiempo.** El cron 34 la dispara
--  `*/2 * * * *` y cada corrida tarda un minuto, así que **hay una o dos corriendo SIEMPRE**.
--  Cualquier statement de un supervisor competía por CPU con eso.
--
--  LA CAUSA, exacta: el CTE `fmark` corría un `exists` **correlacionado** contra
--  `Movimientos_Stock` por CADA fila de `Entregas_Virgilio` con `cajas_falto > 0`:
--  **967 filas × 63.614 movimientos = 61,5 millones de comparaciones**, con dos
--  `regexp_replace` por comparación y un `OR` que anula cualquier índice.
--
--  EL ARREGLO: el mismo dato, **una sola pasada**. Se pre-agrega `Movimientos_Stock` una vez
--  (`ag0`) y se JOINea por la clave normalizada. O(n+m) en lugar de O(n×m).
--
--  ⚠ LAS DOS SIMPLIFICACIONES NO SON LIBRES DE INTERPRETACIÓN, así que van escritas:
--   1. `ag.codn = X or rtrim(ag.codn,'E') = rtrim(X,'E')` **se reduce a la segunda mitad**:
--      si `codn = X` entonces los dos `rtrim` también son iguales. O sea que el `OR` era
--      redundante y el criterio real siempre fue "el código sin la E final".
--   2. `exists (… and m.ts > e.creado)` ≡ `max(m.ts) > e.creado`. Por eso `ag0` guarda
--      `max(ts) filter (where tipo='recepcion')` y alcanza.
--
--  VERIFICACIÓN (lo que exige el repo: fila por fila, sobre el 100 % de los datos, no una
--  muestra). Se comparó vieja vs nueva columna por columna sobre las **967 filas**:
--   · `llego`        → 967/967 iguales, 17 en `true`, **0 diferencias**
--   · `arrived_after`→ en 4 tandas por `id % 4`: 240+247+230+250 = **967**, 82+81+71+97 = 331
--     en `true` en las dos, **0 diferencias**
--
--  Problema 382 de `github_repo_problemas`. Rollback exacto:
--  `sql/backups/detectar_faltantes_llegaron_pre_v1946.sql`.
--
--  ⚠ Y el `exception when others then return 'error: ' || sqlerrm` del final se come CUALQUIER
--  fallo —incluido un timeout— y devuelve un texto, así que **el cron figura `succeeded` igual**.
--  Si esta función se rompe, nadie se entera: hay que mirar el valor que devuelve
--  (`select public.detectar_faltantes_llegaron();` tiene que empezar con `ok `).
--
--  ── Qué hace, para el que llega de nuevo ──────────────────────────────────────────────────
--  Detecta NPs con faltante (`Entregas_Virgilio.cajas_falto > 0`) para las que HAY stock en
--  «a guardar» del mismo código → crea la tarea (`Faltantes_Tareas`, que dispara el pop-up en
--  Virgilio) y avisa por Telegram para que un operario lo complete desde CP. No re-avisa si la
--  NP ya está facturada o ya tiene tarea abierta; dedup diario por `(np|códigos)`.
--
--  DOS CASOS EN EL MENSAJE (pedido del dueño) — según CUÁNDO llegó ese stock respecto del
--  armado del pedido (`Entregas_Virgilio.creado`):
--   · «FALTANTE QUE LLEGÓ»: hubo una RECEPCIÓN del código DESPUÉS de armado el pedido → la
--     mercadería ingresó en el día, después de armar.
--   · «FALTANTE QUE ESTÁ A GUARDAR»: el stock YA estaba en a_guardar antes de armar (pendiente
--     de subir a góndola) → por eso no lo tomaron al pickear.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.detectar_faltantes_llegaron()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
  v_rs text;
  n int := 0;
  v_bucket text := to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYYMMDD');
begin
  for r in
    /* v19.46 — UNA sola pasada por Movimientos_Stock. Antes esto era un exists correlacionado
       por fila de Entregas_Virgilio: 61,5 millones de comparaciones y 65 s por corrida, cada
       2 minutos. Ver el encabezado del archivo. */
    with ag0 as (
      select upper(regexp_replace(trim(cod_art), '^0+', '')) codn,
             sum(delta) saldo,
             max(ts) filter (where tipo = 'recepcion') ult_recep
      from "Movimientos_Stock" where deposito = 'a_guardar'
      group by 1
    ),
    -- hay stock a guardar de ese código (clave = código sin la E final, igual que antes)
    agk as (select distinct rtrim(codn,'E') k from ag0 where saldo > 0),
    -- y cuándo fue la última RECEPCIÓN a a_guardar de ese código
    reck as (select rtrim(codn,'E') k, max(ult_recep) ult from ag0 where ult_recep is not null group by 1),
    ev as (
      select e.np, e.tanda, e.cod_cliente, e.cod_art, e.cajas_falto, e.creado,
             rtrim(upper(regexp_replace(trim(e.cod_art), '^0+', '')),'E') ck
      from "Entregas_Virgilio" e where e.cajas_falto > 0
    ),
    fmark as (
      select ev.np, ev.tanda, ev.cod_cliente, ev.cod_art, ev.cajas_falto,
             (agk.k is not null) as llego,
             -- ¿ese stock llegó DESPUÉS de armado el pedido? (recepción con ts > creado) → "LLEGÓ"
             coalesce(reck.ult > ev.creado, false) as arrived_after
      from ev
      left join agk  on agk.k  = ev.ck
      left join reck on reck.k = ev.ck
    ),
    falt as (
      select np,
             max(tanda) tanda, max(cod_cliente) cod_cliente,
             -- SOLO lo que se puede completar (hay stock a guardar):
             sum(cajas_falto) filter (where llego)::int cajas_arr,
             jsonb_agg(jsonb_build_object('cod', cod_art, 'falto', cajas_falto) order by cod_art) filter (where llego) arts_arr,
             string_agg(distinct case when llego then cod_art end, ', ') filter (where llego) arrived,
             bool_or(llego) hay,
             -- si ALGÚN código completable llegó después de armar → mensaje "LLEGÓ"
             coalesce(bool_or(case when llego then arrived_after else false end), false) es_llego
      from fmark group by np
    )
    select f.np, f.tanda, f.cod_cliente, f.cajas_arr, f.arts_arr, f.arrived, f.es_llego
    from falt f
    where f.hay
      and not exists (select 1 from "Facturacion_NP" fn where trim(fn.np) = trim(f.np))
      and not exists (select 1 from "Faltantes_Tareas" t where t.np = f.np and t.estado in ('pendiente','asignado'))
  loop
    select razon_social into v_rs from "GV_PPP_Programacion_Diaria" where trim(np) = trim(r.np) limit 1;
    -- La tarea se crea con SOLO los códigos completables (así el pop-up y el CP muestran eso).
    perform faltante_tarea_crear(r.np, coalesce(r.cod_cliente, ''), coalesce(v_rs, ''), coalesce(r.tanda, ''), coalesce(r.arts_arr, '[]'::jsonb), coalesce(r.cajas_arr, 0), '0');
    perform tg_enqueue(
      case when r.es_llego
        then '📦➡️ FALTANTE QUE LLEGÓ — NP ' || r.np || coalesce(' · ' || v_rs, '') ||
             E'\n' || 'Llegó a "a guardar": ' || coalesce(r.arrived, '?') ||
             ' (' || coalesce(r.cajas_arr, 0) || ' caja(s)). Que UN operario lo complete (ya les saltó el pop-up en Virgilio).'
        else '📦➡️ FALTANTE QUE ESTÁ A GUARDAR — NP ' || r.np || coalesce(' · ' || v_rs, '') ||
             E'\n' || 'Está en "a guardar" para completarlo: ' || coalesce(r.arrived, '?') ||
             ' (' || coalesce(r.cajas_arr, 0) || ' caja(s)). Que UN operario lo complete (ya les saltó el pop-up en Virgilio).'
      end,
      'faltllego|' || r.np || '|' || coalesce(r.arrived,'') || '|' || v_bucket
    );
    n := n + 1;
  end loop;
  perform tg_outbox_flush();
  return 'ok creadas=' || n;
exception when others then
  return 'error: ' || sqlerrm;
end $function$;
