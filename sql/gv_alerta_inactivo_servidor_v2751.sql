-- v27.51 (Thomas, D8, 06/10/2026) — la alarma de 5 min de tiempo muerto la decide el SERVIDOR.
-- Caso: Franco Ortiz (237) entró a la app 08:29 y su primera tarea fue 10:37; no sonó nada porque
-- la alarma la disparaba sólo el celular con la botonera en pantalla. Ahora corre cada 2 min (cron
-- gv-alerta-inactivo-servidor, minutos impares) y escribe en GV_Alerta_Inactivo, la que lee la TV.
-- p_ahora: sólo para probar («qué habría hecho a tal hora»); en el cron va null = now().
-- Rollback: select cron.unschedule('gv-alerta-inactivo-servidor');
--           drop function public.gv_alerta_inactivo_servidor(boolean, timestamptz);
-- Cron (jobid 136, 07:00-18:58 ART, minutos impares, anti-solape):
-- select cron.schedule('gv-alerta-inactivo-servidor','1-59/2 10-21 * * *',
--   $c$do $d$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_alerta_inactivo_servidor')::bigint) then perform * from public.gv_alerta_inactivo_servidor(false, null); end if; end $d$;$c$);
-- Probar sin escribir: select * from public.gv_alerta_inactivo_servidor(true, '2026-10-06 08:40-03');  -- 237 Franco: ABRE ALERTA
-- (la v1 de 1 argumento, gv_alerta_inactivo_servidor(boolean), queda en la base sin llamador: el DROP se cuelga en el MCP)
create or replace function public.gv_alerta_inactivo_servidor(p_simular boolean, p_ahora timestamptz)
returns table(legajo text, nombre text, ultima_actividad timestamptz, minutos_quieto int, accion text)
language plpgsql security definer set search_path to 'public' as $f$
/* v27.51 (Thomas, D8) — alarma de tiempo muerto del lado del SERVIDOR: suena aunque el celular este
   bloqueado o con la app cerrada. Operario en jornada = entro hoy a la app (clave TV / legajo) o
   registro algo hoy, sin Terminar Dia (FJ) despues. Ultima actividad = max(primer ingreso del dia,
   ultimo evento de hoy). Tarea abierta = apertura (ts_inicio null) sin su cierre, < 12 h:
   EP->TP/PKF · AP->TAP/APF · MGI->MG/MGC · RKI->RKB · IRI->IRT · toggles (mismo codigo con
   ts_inicio) · FJ cierra todo. Abre en GV_Alerta_Inactivo y cierra la viva cuando vuelve la
   actividad. El celular sigue avisando igual. Lee 14 h por created_at (indexado). */
declare v_now timestamptz := coalesce(p_ahora, now());
        v_hoy date := (coalesce(p_ahora, now()) at time zone 'America/Argentina/Buenos_Aires')::date;
        v_desde timestamptz;
        v_hora int := extract(hour from coalesce(p_ahora, now()) at time zone 'America/Argentina/Buenos_Aires');
        v_habil boolean := true;
        r record;
begin
  v_desde := (v_hoy::timestamp at time zone 'America/Argentina/Buenos_Aires');
  begin v_habil := coalesce(public.gv_es_dia_habil(v_hoy), true); exception when others then v_habil := true; end;
  for r in
    with rec as materialized (
      select e.id, e.legajo, e.opcion, e.ts_cliente, e.ts_inicio from public."Registros_Produccion_Virgilio" e
       where e.created_at >= v_now - interval '14 hours' and e.created_at <= v_now and e.ts_cliente <= v_now
         and e.legajo !~ '^sup:' and e.legajo not in ('0','1')),
    ing as (
      select l.legajo, min(l.created_at) primero, max(l.created_at) ultimo
        from public."GV_Dispositivo_Login" l
       where l.tipo = 'operario' and l.created_at >= v_desde and l.created_at <= v_now
         and coalesce(l.legajo,'') not in ('','0','1')
       group by 1),
    ev as (
      select e.legajo, max(e.ts_cliente) ult, max(e.ts_cliente) filter (where e.opcion = 'FJ') fj
        from rec e where e.ts_cliente >= v_desde and e.opcion !~ 'X$' group by 1),
    ops as (select coalesce(i.legajo, ev.legajo) leg, i.primero, i.ultimo, ev.ult, ev.fj
              from ing i full join ev on ev.legajo = i.legajo),
    aper as (
      select distinct a.legajo from rec a
       where a.ts_inicio is null and a.ts_cliente > v_now - interval '12 hours'
         and a.opcion in ('EP','AP','MGI','RKI','IRI','AT','CC','CR','CT','EI','Limp','PB','PC','Perm','RI','RR','RT')
         and not exists (select 1 from rec c where c.legajo = a.legajo and c.ts_cliente >= a.ts_cliente and c.id <> a.id
            and ( c.opcion = 'FJ' or (c.opcion = a.opcion and c.ts_inicio is not null)
               or (a.opcion='EP' and c.opcion in ('TP','PKF')) or (a.opcion='AP' and c.opcion in ('TAP','APF'))
               or (a.opcion='MGI' and c.opcion in ('MG','MGC','MGI') and c.ts_cliente > a.ts_cliente)
               or (a.opcion='RKI' and c.opcion='RKB') or (a.opcion='IRI' and c.opcion='IRT'))))
    select o.leg, coalesce(nullif(btrim(emp."Empleado"),''), 'Legajo ' || o.leg) nom,
           greatest(o.primero, o.ult) ult,
           (o.leg in (select aper.legajo from aper)) abierta,
           (o.fj is not null and o.fj >= coalesce(o.ultimo, o.fj) and o.fj >= coalesce(o.ult, o.fj)) termino
      from ops o
      left join lateral (select x."Empleado" from public."Empleados" x where x."Legajo"::text = o.leg limit 1) emp on true
  loop
    legajo := r.leg; nombre := r.nom; ultima_actividad := r.ult;
    minutos_quieto := floor(extract(epoch from v_now - r.ult) / 60);
    if r.termino then accion := 'termino el dia';
    elsif r.abierta then accion := 'tarea abierta';
    elsif v_hora < 7 or v_hora >= 18 or not v_habil then accion := 'fuera de horario';
    elsif minutos_quieto < 5 then accion := 'trabajando';
    elsif exists (select 1 from public."GV_Alerta_Inactivo" a where a.legajo = r.leg and a.abierta_en >= r.ult and a.abierta_en <= v_now) then accion := 'ya avisado';
    else
      accion := 'ABRE ALERTA';
      if not p_simular then
        update public."GV_Alerta_Inactivo" a set cerrada_en = now() where a.legajo = r.leg and a.cerrada_en is null;
        insert into public."GV_Alerta_Inactivo" (legajo, nombre, dispositivo) values (r.leg, r.nom, 'servidor');
      end if;
    end if;
    if not p_simular and accion in ('termino el dia','tarea abierta','trabajando') then
      update public."GV_Alerta_Inactivo" a set cerrada_en = now() where a.legajo = r.leg and a.cerrada_en is null;
    end if;
    return next;
  end loop;
end $f$;
revoke all on function public.gv_alerta_inactivo_servidor(boolean, timestamptz) from public, anon, authenticated;
