-- ═══════════════════════════════════════════════════════════════════════════
-- v17.97 — LA TAREA DE CUARENTENA TIENE QUE DECIR EL TRÁMITE QUE CORRESPONDE
-- Proyecto Gestión Virgilio (hrxfctzncixxqmpfhskv) · problema 200
-- ═══════════════════════════════════════════════════════════════════════════
-- QUÉ ESTABA MAL. La nota de la tarea que se le abre a Viviana arrancaba SIEMPRE
-- con el mismo renglón, cualquiera fuera el motivo:
--
--   "Falta: chequear si el cliente pago. Si pago, tocar 'Ya pago' en A Programar
--    → Cuarentena y el pedido sale solo."
--
-- Eso es cierto sólo para la deuda. `Ya pago` escribe en GV_Cuarentena_Pagados y
-- lo único que apaga es el motivo `deuda`; `cliente_nuevo`, `sin_cta_cte`,
-- `suspendido` y el exceso de límite quedan igual (el propio front lo avisa:
-- index.html, aprCuarentenaPagar, v17.12). O sea que la tarea mandaba a hacer un
-- trámite que dejaba el pedido tan retenido como antes — medido el 15/09 con los
-- pedidos LK 1441 y 1442, los dos por `cliente_nuevo`, los dos con el cliente en
-- estado Activo y sin deuda.
--
-- Y HABÍA UN SEGUNDO ERROR, EL DEL ROTULO. El motivo llegaba ya escrito desde la
-- Edge Function `gv-ppp-web-tandas-diarias`, que lo armaba con un `else` cajón de
-- sastre: todo lo que no fuera `deuda` ni `sin_cta_cte` salía como "Suspendido".
-- Con `cliente_nuevo` eso rotuló a LK 1441 y 1442 como suspendidos teniendo los dos
-- clientes estado Activo y `suspendido = false` en GV_Cuarentena_Fuente.
--
-- QUÉ CAMBIA. El texto del motivo lo arma ACÁ, que es el backend y la única parte que
-- puede mirar el dato de verdad: se piden los CÓDIGOS de motivo a
-- `gv_cuarentena_marcar_calc` (la variante pura — `gv_cuarentena_marcar` escribiría en
-- GV_Cuarentena_Log en cada corrida del cron) y se los traduce con un mapa explícito.
-- Del texto que manda la Edge Function sólo se conserva la parte que la base no puede
-- recalcular sin los ítems: "Supera el limite de credito por $X", que sale de
-- `gv_cuarentena_limite`. Si el cálculo no devuelve nada para ese pedido, se usa el
-- texto recibido tal cual, como hasta ahora.
--
-- Y el renglón de acción se elige según el motivo, en vez de ser fijo:
--
--   sólo deuda        → el texto de siempre, que para ese caso es correcto.
--   deuda + otra cosa → cobrar Y avisar que igual sigue retenido por lo otro.
--   sin deuda         → revisar y liberar a mano; y decir que `Ya pago` no sirve.
--
-- Lo demás de la función queda igual (altas, ledger, cierres, el guard de ISIS).
-- ROLLBACK: correr sql/backups/gv_cuarentena_planify_sync_20260915_pre_v1797.sql.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.gv_cuarentena_planify_sync(p_empresa text, p_pedidos jsonb)
 returns table(altas integer, cierres integer)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_emp  text := lower(nullif(btrim(p_empresa), ''));
  v_emp_lbl text := case when v_emp = 'chef' then 'CH' else 'LK' end;
  v_vivi bigint := 4;          -- Viviana Gauna (planify.employees)
  v_hoy  text := to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD');
  v_hora text := to_char(now() at time zone 'America/Argentina/Buenos_Aires', 'HH24:MI');
  v_altas int := 0;
  v_cierres int := 0;
  v_isis jsonb := '[]'::jsonb;
  v_isis_ok boolean := false;
  v_todos jsonb;
  r record;
  v_task bigint;
  v_partes text[];
  v_otros  text[];
  v_deuda  boolean;
  v_falta  text;
  v_cods   text[];
  v_monto  numeric;
  v_estado text;
  v_lbl    text[];
  v_motivo text;
begin
  if not gv_es_supervisor_o_servicio() then
    raise exception 'Solo el servicio puede sincronizar las tareas de cuarentena.' using errcode='42501';
  end if;
  if v_emp is null then
    raise exception 'Falta la empresa.' using errcode='22023';
  end if;

  -- ── 0. NP de ISIS sin tanda que están en cuarentena ────────────────────
  begin
    v_isis := coalesce(public.gv_cuarentena_isis_pedidos(v_emp), '[]'::jsonb);
    v_isis_ok := true;
  exception when others then
    v_isis := '[]'::jsonb;
    v_isis_ok := false;   -- no se pudo evaluar: abajo NO se cierra ninguna 'np%'
  end;
  v_todos := coalesce(p_pedidos, '[]'::jsonb) || v_isis;

  -- ── 0b. LOS MOTIVOS DE VERDAD, EN CODIGO (v17.97) ──────────────────────
  --   `_calc` es la variante PURA: `gv_cuarentena_marcar` haría además un INSERT en
  --   GV_Cuarentena_Log, y esto corre en cada vuelta del cron. Si falla, la tabla queda
  --   vacía y cada pedido usa el texto que mandó el llamador: la tarea es un aviso, no
  --   puede tumbar el armado.
  begin
    create temp table _mot_cuar on commit drop as
      select c.order_id, c.motivos, c.deuda, c.estado
        from public.gv_cuarentena_marcar_calc((
          select coalesce(jsonb_agg(jsonb_build_object(
                   'order_id', nullif(btrim(e->>'order_id'),''),
                   'empresa',  v_emp,
                   'cod',      nullif(btrim(e->>'cod'),''))), '[]'::jsonb)
            from jsonb_array_elements(v_todos) e
           where nullif(btrim(e->>'order_id'),'') is not null
             and nullif(btrim(e->>'cod'),'') is not null)) c;
  exception when others then
    create temp table if not exists _mot_cuar (order_id text, motivos text[], deuda numeric, estado text) on commit drop;
  end;

  -- ── 1. ALTAS: pedido en cuarentena que todavia no tiene tarea abierta ───
  for r in
    select nullif(btrim(e->>'order_id'),'')                      as order_id,
           nullif(btrim(e->>'cod'),'')                           as cod,
           coalesce(nullif(btrim(e->>'razon_social'),''), '(sin razon social)') as rs,
           coalesce(nullif(btrim(e->>'motivo'),''), 'Retenido en cuarentena')   as motivo,
           nullif(btrim(e->>'m3'),'')                            as m3
      from jsonb_array_elements(v_todos) e
  loop
    if r.order_id is null then continue; end if;
    -- Skip solo si el ledger esta abierto Y la tarea sigue existiendo y abierta.
    -- Si la borraron o la cerraron a mano, se recrea: el pedido sigue retenido.
    if exists (select 1 from public."GV_Cuarentena_Planify" q
                 join planify.tasks t on t.id = q.task_id
                where q.empresa = v_emp and q.order_id = r.order_id
                  and q.cerrada_at is null and t.done = false) then
      continue;
    end if;

    -- v17.97: el ROTULO se arma acá con los códigos de motivo reales. Lo único que se
    -- conserva del texto recibido es el exceso de límite, que necesita los ítems del
    -- pedido y sólo lo sabe calcular el llamador.
    v_cods := null; v_monto := null; v_estado := null;
    select m.motivos, m.deuda, m.estado into v_cods, v_monto, v_estado
      from _mot_cuar m where m.order_id = r.order_id limit 1;

    v_lbl := array(
      select case mm
               when 'deuda' then 'Deuda' || coalesce(' $' || replace(replace(replace(
                      to_char(round(v_monto, 2), 'FM999,999,999,990.00'), ',', 'X'), '.', ','), 'X', '.'), '')
               when 'sin_cta_cte'   then 'Sin Cta.Cte.'
               when 'cliente_nuevo' then 'Cliente nuevo'
               when 'suspendido'    then 'Suspendido' || coalesce(' (' || nullif(btrim(v_estado), '') || ')', '')
               else mm
             end
        from unnest(coalesce(v_cods, '{}'::text[])) mm)
      || array(select x from unnest(string_to_array(r.motivo, ' · ')) x where x ~ '^Supera el limite');

    v_motivo := case when coalesce(array_length(v_lbl, 1), 0) > 0
                     then array_to_string(v_lbl, ' · ') else r.motivo end;

    -- y el trámite que se le pide depende del motivo, no es fijo.
    v_partes := string_to_array(v_motivo, ' · ');
    v_deuda  := exists (select 1 from unnest(v_partes) x where x ~ '^Deuda');
    v_otros  := array(select x from unnest(v_partes) x where x !~ '^Deuda');

    if v_deuda and coalesce(array_length(v_otros, 1), 0) = 0 then
      v_falta := 'Falta: chequear si el cliente pago. Si pago, tocar "Ya pago" en '
              || 'A Programar → Cuarentena y el pedido sale solo. ';
    elsif v_deuda then
      v_falta := 'Falta: chequear si el cliente pago y tocar "Ya pago" en A Programar → '
              || 'Cuarentena. Ojo: aun pagando el pedido sigue retenido por '
              || array_to_string(v_otros, ' y ')
              || ', que se libera a mano desde esa misma pantalla. ';
    else
      v_falta := 'Falta: revisar el pedido en A Programar → Cuarentena y liberarlo si '
              || 'corresponde. El boton "Ya pago" NO lo saca: no esta retenido por deuda. ';
    end if;

    insert into planify.tasks (name, type, prio, time, date, note, rec, done, assignment_type,
      employee_id, department_id, system_generated, broadcast, created_at, updated_at)
    values (
      left('Cuarentena ' || v_emp_lbl || ' ' || r.order_id || ' · ' || r.rs, 60),
      'tarea', 'normal', v_hora, v_hoy,
      v_falta ||
        v_motivo || '. Pedido web ' || v_emp_lbl || ' ' || r.order_id || ' · ' || r.rs ||
        coalesce(' (cod ' || r.cod || ')', '') || coalesce(' · ' || r.m3 || ' m3', '') ||
        '. Cargada sola por Gestion Virgilio cuando el pedido entro en Cuarentena.',
      'none', false, 'employee', v_vivi, null, false, false, now(), now())
    returning id into v_task;

    insert into public."GV_Cuarentena_Planify" (empresa, order_id, task_id)
    values (v_emp, r.order_id, v_task)
    on conflict (empresa, order_id) do update
      set task_id = excluded.task_id, creada_at = now(), cerrada_at = null;
    v_altas := v_altas + 1;
  end loop;

  -- ── 2. CIERRES: tarea abierta de un pedido que ya no esta en cuarentena ──
  for r in
    select q.order_id, q.task_id
      from public."GV_Cuarentena_Planify" q
     where q.empresa = v_emp and q.cerrada_at is null
       and (v_isis_ok or q.order_id not like 'np%')   -- ISIS no evaluado: no cerrar sus tareas
       and not exists (
         select 1 from jsonb_array_elements(v_todos) e
          where nullif(btrim(e->>'order_id'),'') = q.order_id)
  loop
    update planify.tasks
       set done = true,
           note = left(note, 400) || ' — SALIO de cuarentena el ' || v_hoy || ', no hace falta nada mas.',
           updated_at = now()
     where id = r.task_id and done = false;
    update public."GV_Cuarentena_Planify" set cerrada_at = now()
     where empresa = v_emp and order_id = r.order_id;
    v_cierres := v_cierres + 1;
  end loop;

  return query select v_altas, v_cierres;
end;
$function$;
