-- v29.50 (Luis, 13/10/2026, D3; el marcador interno dice v29.25-evdup: llave, no cambiar): el SERVIDOR reconoce un EVENTO DUPLICADO aunque llegue con otro client_id.
-- Caso: el replay de «Terminar Día» reenviaba las tareas de módulo con un id del Historial (h_*) distinto al del
-- evento real: 55 duplicados del 02/10 al 09/10 (anulados con X; backups zz_backups."GV_Backup_RegH_Replay_*").
-- El celular ya no los manda (v29.24), pero un celular viejo puede: lo frena la base.
--
-- Reglas (BEFORE INSERT en Registros_Produccion_Virgilio; corre DESPUÉS de aa_gv_registro_entrevista_a_empleado):
--  R1 mismo tramo: mismo legajo, ts_inicio y ts_cliente a menos de 2 s de un evento vivo (no termina en X) con
--     otro client_id → es el mismo cierre de tarea. Medido 60 días: 3 pares entre eventos «buenos», y los 3 eran
--     duplicados de verdad (TP fix2209_e39a_tp, APF frn_16).
--  R2 copia del Historial: client_id h_* y un evento vivo del mismo legajo a menos de 2 s → es la copia del
--     Historial de ese evento (el guardado cierra con MGC, que no trae ts_inicio). Sin gemelo, ENTRA: es el único dato.
-- Lo descartado no se pierde: queda entero en "GV_Evento_Duplicado" con el motivo y el gemelo.
-- Rollback: alter table public."Registros_Produccion_Virgilio" disable trigger ab_gv_evento_duplicado;

create or replace function public.gv_evento_duplicado()
returns trigger language plpgsql security definer set search_path = public as $f$
declare g record; v_motivo text;
begin
  -- v29.25-evdup
  if new.legajo is null or new.ts_cliente is null then return new; end if;
  if new.ts_inicio is not null then
    select r.client_id, r.opcion into g from public."Registros_Produccion_Virgilio" r
     where r.legajo = new.legajo and r.client_id <> new.client_id and r.opcion !~ 'X$'
       and r.ts_cliente between new.ts_cliente - interval '2 seconds' and new.ts_cliente + interval '2 seconds'
       and r.ts_inicio is not null
       and abs(extract(epoch from r.ts_inicio - new.ts_inicio)) < 2
     limit 1;
    if found then v_motivo := 'mismo tramo (legajo, inicio y fin a menos de 2 s)'; end if;
  end if;
  if v_motivo is null and new.client_id like 'h\_%' then
    select r.client_id, r.opcion into g from public."Registros_Produccion_Virgilio" r
     where r.legajo = new.legajo and r.client_id <> new.client_id and r.client_id not like 'h\_%'
       and r.opcion !~ 'X$'
       and r.ts_cliente between new.ts_cliente - interval '2 seconds' and new.ts_cliente + interval '2 seconds'
     order by abs(extract(epoch from r.ts_cliente - new.ts_cliente)) limit 1;
    if found then v_motivo := 'copia del Historial del celular (h_*) de un evento ya registrado'; end if;
  end if;
  if v_motivo is null then return new; end if;
  insert into public."GV_Evento_Duplicado"
    (client_id, legajo, opcion, texto, ts_inicio, ts_cliente, motivo, gemelo_client_id, gemelo_opcion, fila)
  values (new.client_id, new.legajo, new.opcion, new.texto, new.ts_inicio, new.ts_cliente, v_motivo,
          g.client_id, g.opcion, to_jsonb(new))
  on conflict do nothing;
  return null;
end $f$;

create or replace trigger ab_gv_evento_duplicado
  before insert on public."Registros_Produccion_Virgilio"
  for each row execute function public.gv_evento_duplicado();

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_evento_duplicado','funcion','abs\(extract\(epoch from r\.ts_inicio - new\.ts_inicio\)\) < 2',
        'El servidor descarta un evento que repite el mismo tramo (legajo, inicio y fin ±2 s) con otro client_id, y la copia h_* del Historial',
        'Luis','v29.25');

-- Lectura: select * from public."GV_Evento_Duplicado" order by id desc;
