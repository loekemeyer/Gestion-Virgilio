-- Definición VIVA de public.gv_cuarentena_planify_sync(text,jsonb) al 2026-09-15,
-- ANTES de la v17.97 (problema 200: la nota pedía siempre "chequear si el cliente
-- pago", aunque el motivo no fuera deuda). Correr este archivo tal cual deshace el
-- cambio. Tomada con pg_get_functiondef.

CREATE OR REPLACE FUNCTION public.gv_cuarentena_planify_sync(p_empresa text, p_pedidos jsonb)
 RETURNS TABLE(altas integer, cierres integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    insert into planify.tasks (name, type, prio, time, date, note, rec, done, assignment_type,
      employee_id, department_id, system_generated, broadcast, created_at, updated_at)
    values (
      left('Cuarentena ' || v_emp_lbl || ' ' || r.order_id || ' · ' || r.rs, 60),
      'tarea', 'normal', v_hora, v_hoy,
      'Falta: chequear si el cliente pago. Si pago, tocar "Ya pago" en A Programar → Cuarentena y el pedido sale solo. ' ||
        r.motivo || '. Pedido web ' || v_emp_lbl || ' ' || r.order_id || ' · ' || r.rs ||
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
