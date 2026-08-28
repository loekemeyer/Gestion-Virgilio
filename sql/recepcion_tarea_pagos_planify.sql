-- idea 4041 (usuario) — Vincular Virgilio con las alarmas de Planify:
-- al recepcionar un REMITO en Virgilio, crear una tarea en el Planify del sector PAGOS.
-- APLICADO en Supabase (migraciones recepcion_crea_tarea_pagos_planify +
-- recepcion_tarea_pagos_broadcast). Copia versionada.
--
-- Decisiones (confirmadas con el usuario):
--  · Backend (trigger), no front.
--  · Ambos orígenes: "Entregas Prov AT" (proveedores) + "Entregas Tallerista Virgilio".
--  · 1 tarea por remito (con o sin factura). Solo si hay Remito (no null/vacío).
--  · La tarea sale como AVISO CENTRADO del sector (broadcast=true, idea 6463): en vez
--    de caer en la esquina como una alarma más, abre un cartel bloqueante en el medio
--    de la pantalla de todos los de Pagos hasta que alguien aprieta "Me encargo yo"
--    (RPC planify.planify_claim_task — gana el primero). Front en el repo Planify.
--
-- Modelo Planify (mismo Postgres, schema planify): tarea de departamento =
--  assignment_type='department', department_id=6 (Pagos), type='tarea', prio='urgente',
--  date=YYYY-MM-DD (texto), system_generated=true, broadcast=true, done=false. Mismo
--  patrón que las
--  tareas automáticas que Planify ya crea (cumpleaños → RRHH dept 7).
--
-- Dedup: marcador oculto [vrec:origen|REMITO|ENTIDAD] al final de tasks.note + advisory
-- lock por remito → los N artículos de un remito generan UNA sola tarea (aunque Pagos ya
-- la haya completado, no se recrea).
--
-- Verificado: prov 2 artículos mismo remito → 1 tarea; tallerista otro remito → 1 tarea;
-- fila sin remito → 0; total 2; sin residuo.

create or replace function public.recepcion_crea_tarea_pagos()
returns trigger
language plpgsql
security definer
set search_path = public, planify, pg_temp
as $$
declare
  v_remito   text;
  v_entidad  text;
  v_origen   text;
  v_factura  text;
  v_fecha    text;
  v_marker   text;
  v_hoy      text := to_char((now() at time zone 'America/Argentina/Buenos_Aires'), 'YYYY-MM-DD');
  v_name     text;
  v_note     text;
begin
  if tg_table_name = 'Entregas Prov AT' then
    v_origen  := 'Proveedor';
    v_remito  := nullif(btrim(new."Remito"), '');
    v_entidad := coalesce(nullif(btrim(new."Proveedor"), ''), 'proveedor s/nombre');
    v_factura := nullif(btrim(new."Numero_Factura"), '');
    v_fecha   := coalesce(new."Fecha_RTO"::text, nullif(btrim(new."Dia_mes"), ''), v_hoy);
  elsif tg_table_name = 'Entregas Tallerista Virgilio' then
    v_origen  := 'Tallerista';
    v_remito  := nullif(btrim(new."Remito"), '');
    v_entidad := coalesce(nullif(btrim(new."Nombre_Tall"), ''), 'tallerista s/nombre');
    v_factura := nullif(btrim(new."Numero_Factura"), '');
    v_fecha   := coalesce(new."Fecha_RTO"::text, nullif(btrim(new."Fecha"), ''), v_hoy);
  else
    return new;
  end if;

  if v_remito is null then
    return new;  -- "cuando llega un remito": sin remito no hay tarea
  end if;

  v_marker := '[vrec:' || lower(v_origen) || '|' || upper(v_remito) || '|' || upper(v_entidad) || ']';
  perform pg_advisory_xact_lock(hashtextextended('recep_pagos:' || v_marker, 0));

  if exists (select 1 from planify.tasks t where t.note like '%' || v_marker || '%') then
    return new;  -- este remito ya tiene tarea (aunque esté hecha)
  end if;

  v_name := 'Remito ' || v_remito || ' — ' || v_entidad;
  v_note := 'Recepción cargada en Producción Virgilio.' || E'\n' ||
            v_origen || ': ' || v_entidad || E'\n' ||
            'Remito: ' || v_remito || E'\n' ||
            'Factura: ' || coalesce(v_factura, '(sin factura todavía)') || E'\n' ||
            'Fecha recepción: ' || v_fecha || E'\n' ||
            'Gestionar el pago de esta recepción.' || E'\n\n' || v_marker;

  insert into planify.tasks
    (name, type, prio, date, note, done, assignment_type, department_id,
     employee_id, created_by, system_generated, broadcast, created_at, updated_at)
  values
    (v_name, 'tarea', 'urgente', v_hoy, v_note, false, 'department', 6,
     null, null, true, true, now(), now());

  return new;
end;
$$;

revoke execute on function public.recepcion_crea_tarea_pagos() from public, anon, authenticated;

drop trigger if exists trg_recep_pagos_prov on public."Entregas Prov AT";
create trigger trg_recep_pagos_prov
  after insert on public."Entregas Prov AT"
  for each row execute function public.recepcion_crea_tarea_pagos();

drop trigger if exists trg_recep_pagos_tall on public."Entregas Tallerista Virgilio";
create trigger trg_recep_pagos_tall
  after insert on public."Entregas Tallerista Virgilio"
  for each row execute function public.recepcion_crea_tarea_pagos();
