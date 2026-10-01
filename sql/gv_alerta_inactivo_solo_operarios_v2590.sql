-- v25.90 (Luis, 01/10): vuelve la alarma de operario inactivo, sólo para operarios de verdad.
-- Legajo de prueba (0/1) y supervisor (vista de operario desde el admin) no abren alerta; la lista viva los saca.
-- Aplicado vía MCP. Para apagarla otra vez: gv_alertas_inactivo_vivas() con "where false" (v25.88).
CREATE OR REPLACE FUNCTION public.gv_alerta_inactivo_abrir(p_legajo text, p_dispositivo text DEFAULT NULL::text)
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_id bigint; v_leg text := nullif(btrim(p_legajo), ''); v_nom text;
begin
  if v_leg is null then return null; end if;
  if v_leg in ('0','1') then return null; end if;
  if coalesce(public.es_supervisor_virgilio(), false) then return null; end if;
  select id into v_id from public."GV_Alerta_Inactivo"
   where legajo = v_leg and cerrada_en is null and abierta_en > now() - interval '12 hours'
   order by id desc limit 1;
  if v_id is not null then return v_id; end if;
  select "Empleado" into v_nom from public."Empleados" where "Legajo"::text = v_leg limit 1;
  insert into public."GV_Alerta_Inactivo" (legajo, nombre, dispositivo)
  values (v_leg, coalesce(nullif(btrim(v_nom), ''), 'Legajo ' || v_leg), left(p_dispositivo, 80))
  returning id into v_id;
  return v_id;
end $function$;
CREATE OR REPLACE FUNCTION public.gv_alertas_inactivo_vivas()
 RETURNS TABLE(id bigint, legajo text, nombre text, abierta_en timestamp with time zone, cerrada boolean)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  select a.id, a.legajo, a.nombre, a.abierta_en, a.cerrada_en is not null
    from public."GV_Alerta_Inactivo" a
   where a.abierta_en > now() - interval '3 minutes' and a.legajo not in ('0','1')
   order by a.abierta_en;
$function$;
