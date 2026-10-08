-- v28.67 (Luis, 08/10): login «Soy otro» → legajo; sin legajo → nombre = ENTREVISTA, pero cada entrevistado con SU legajo.
-- Antes todos los entrevistados compartían el legajo 600 y el monitor los mostraba juntos como «Entrevista».
-- Ahora gv_operario_alta_crear:
--   1) si el nombre coincide con un empleado activo, devuelve SU legajo (caso Kevin Latronico = 504);
--   2) si no, le da un legajo de entrevista propio 6000 + id (6001..6999) y lo da de alta en Empleados
--      como «<nombre> (entrevista)» para que el monitor lo muestre por nombre y por separado.
-- gv_operario_alta_validar desactiva ese legajo de entrevista al darle el legajo real.
-- Rollback: las definiciones anteriores están en zz_backups."GV_Backup_OperarioAlta_defs_20261008".

create or replace function public.es_legajo_entrevista(p_legajo text)
 returns boolean language sql immutable parallel safe
return (case when coalesce(btrim(p_legajo),'') = '600' then true
             when coalesce(btrim(p_legajo),'') ~ '^6[0-9]{3}$' then btrim(p_legajo)::int between 6001 and 6999
             else false end);

create or replace function public.gv_operario_alta_crear(p_nombre text, p_dispositivo text default null)
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare v_n text := btrim(regexp_replace(coalesce(p_nombre,''),'\s+',' ','g')); v_id bigint; v_estado text;
        v_emp text; v_emp_nom text; v_leg text;
begin
  if length(v_n) < 3 then raise exception 'Poné tu nombre y apellido.' using errcode='22023'; end if;
  -- v28.66: si ya es empleado (mismo nombre, activo), entra con SU legajo
  select btrim("Legajo"), "Empleado" into v_emp, v_emp_nom from public."Empleados"
   where lower(btrim(regexp_replace(coalesce("Empleado",''),'\s+',' ','g'))) = lower(v_n)
     and upper(btrim(coalesce("Activo",'SI'))) <> 'NO' and btrim("Legajo") ~ '^\d+$'
     and not public.es_legajo_entrevista("Legajo") and btrim("Legajo") not in ('0','1')
   order by "Legajo"::int limit 1;
  if v_emp is not null then
    return jsonb_build_object('nombre', v_emp_nom, 'legajo', v_emp, 'tipo', 'empleado');
  end if;
  select id, estado into v_id, v_estado from public."GV_Operario_Alta"
    where nombre_norm = lower(v_n) and estado in ('pendiente','validado') limit 1;
  if v_id is null then
    insert into public."GV_Operario_Alta"(nombre, creado_dispositivo) values (v_n, nullif(btrim(p_dispositivo),''))
      returning id, estado into v_id, v_estado;
  end if;
  v_leg := (6000 + v_id)::text;   -- v28.66-entrevista: legajo propio por entrevistado
  if not exists (select 1 from public."Empleados" where btrim("Legajo") = v_leg) then
    insert into public."Empleados"("Legajo","Empleado","Activo","Sede") values (v_leg, v_n || ' (entrevista)', 'SI', 'V');
  end if;
  return jsonb_build_object('id', v_id, 'nombre', v_n, 'estado', v_estado, 'legajo', v_leg, 'tipo', 'entrevista');
end $function$;

create or replace function public.gv_operario_alta_validar(p_id bigint, p_legajo text, p_por text default null)
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare v_leg text := regexp_replace(coalesce(p_legajo,''),'\D','','g');
        v_nombre text; v_estado text; v_existe boolean; v_creado boolean := false;
        v_quien text := nullif(lower(coalesce(nullif(btrim(p_por),''), auth.jwt()->>'email','')),'');
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR' using errcode='42501'; end if;
  if v_leg = '' or v_leg in ('0','1') or public.es_legajo_entrevista(v_leg) then raise exception 'Poné un legajo válido (no 0, 1, 600 ni 6001-6999).' using errcode='22023'; end if;
  select nombre, estado into v_nombre, v_estado from public."GV_Operario_Alta" where id = p_id;
  if v_nombre is null then raise exception 'No existe ese alta.' using errcode='22023'; end if;
  select exists(select 1 from public."Empleados" where btrim("Legajo") = v_leg) into v_existe;
  if not v_existe then
    insert into public."Empleados"("Legajo","Empleado","Activo") values (v_leg, v_nombre, 'SI');
    v_creado := true;
  else
    update public."Empleados" set "Activo"='SI' where btrim("Legajo") = v_leg and upper(btrim(coalesce("Activo",'')))='NO';
  end if;
  -- v28.66: el legajo de entrevista deja de estar activo
  update public."Empleados" set "Activo"='NO' where btrim("Legajo") = (6000 + p_id)::text;
  update public."GV_Operario_Alta"
     set estado='validado', legajo=v_leg, empleado_creado=v_creado,
         validado_por=v_quien, validado_at=now()
   where id = p_id;
  return jsonb_build_object('ok',true,'id',p_id,'nombre',v_nombre,'legajo',v_leg,'empleado_creado',v_creado,'empleado_ya_existia',v_existe);
end $function$;
