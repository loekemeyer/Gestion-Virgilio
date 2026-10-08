-- v28.69 (Luis, 08/10): un celular logueado con el 600 compartido (o 6xxx) y el nombre de un EMPLEADO ACTIVO
-- registra con el legajo de ese empleado. Caso Kevin Latronico (504): entró por nombre, salía «Entrevista».
-- Aplicado el 08/10. Datos movidos 600 → 504 (backup zz_backups."GV_Backup_Kevin600_20261008":
-- 20 Registros, 48 Movimientos_Stock F69A, 1 login, 44 pasos de picking F69A, lock F69A picking).
CREATE OR REPLACE FUNCTION public.gv_registro_entrevista_a_empleado()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_leg text;
begin
  if public.es_legajo_entrevista(new.legajo) and nullif(btrim(coalesce(new.gv_nombre_prueba,'')),'') is not null then
    select btrim("Legajo") into v_leg from public."Empleados"
     where lower(btrim(regexp_replace(coalesce("Empleado",''),'\s+',' ','g'))) = lower(btrim(regexp_replace(new.gv_nombre_prueba,'\s+',' ','g')))
       and upper(btrim(coalesce("Activo",'SI'))) <> 'NO' and btrim("Legajo") ~ '^\d+$'
       and not public.es_legajo_entrevista("Legajo") and btrim("Legajo") not in ('0','1')
     order by btrim("Legajo")::int limit 1;
    if v_leg is not null then new.legajo := v_leg; new.gv_nombre_prueba := null; end if;
  end if;
  return new;
end $function$;

create or replace trigger aa_gv_registro_entrevista_a_empleado BEFORE INSERT ON public."Registros_Produccion_Virgilio"
 FOR EACH ROW WHEN (((new.legajo = '600'::text) OR (new.legajo ~ '^6[0-9]{3}$'::text)))
 EXECUTE FUNCTION gv_registro_entrevista_a_empleado();
-- Rollback: alter table public."Registros_Produccion_Virgilio" disable trigger aa_gv_registro_entrevista_a_empleado;

-- v28.71 (08/10): el evento 600 SIN nombre (PKC, ENT…) toma el legajo real del ingreso de HOY de ese mismo
-- celular (GV_Dispositivo_Login.dispositivo = gv_dispositivo). Caso: el PKC de F69A de Kevin entró como 600
-- después de la v28.69. Aplicado el 08/10 (create or replace sobre la viva); probado en transacción abortada
-- (600 + su dispositivo -> 504) y movido ese PKC + 3 movimientos + 6 pasos a 504.

-- v28.72 (08/10, Luis D2): lo mismo para los pasos de picking (GV_Picking_Paso_Evento): el 600 toma el legajo
-- del ingreso de hoy de ese celular. Aplicado el 08/10.
create or replace function public.gv_pkpaso_entrevista_a_empleado()
 returns trigger language plpgsql security definer set search_path to 'public','pg_temp'
as $f$ declare v_leg text; begin
  if new.legajo = '600' and nullif(btrim(coalesce(new.dispositivo,'')),'') is not null then
    select btrim(l.legajo::text) into v_leg from public."GV_Dispositivo_Login" l
     where l.dispositivo = new.dispositivo
       and (l.created_at at time zone 'America/Argentina/Buenos_Aires')::date = (now() at time zone 'America/Argentina/Buenos_Aires')::date
       and btrim(l.legajo::text) ~ '^\d+$' and not public.es_legajo_entrevista(l.legajo::text) and btrim(l.legajo::text) not in ('0','1')
     order by l.created_at desc limit 1;
    if v_leg is not null then new.legajo := v_leg; end if;
  end if;
  return new; end $f$;
create or replace trigger aa_gv_pkpaso_entrevista_a_empleado before insert on public."GV_Picking_Paso_Evento"
 for each row when (new.legajo = '600') execute function public.gv_pkpaso_entrevista_a_empleado();
-- Nota: el lock de F69A quedó con legajo 600 (nombre Kevin Latronico) para que su celular, logueado con el 600, la siga.
