-- v26.02 (01/10/2026) — PRUEBA TEMPORAL de la alarma de inactivo, SÓLO en Mon. Admin.
--
-- Pedido: "cuando el legajo de prueba va al baño, que salte el mensaje de alarma en la pantalla;
-- cuando deje de ir al baño que se apague; que dure 1 hora". Legajo de prueba = 1. Sólo Mon. Admin.
--
--   celular (legajo 1): abre el baño (PB) → gv_alerta_prueba_bano(true); lo cierra → (false)
--   Mon. Admin:         lee gv_alertas_prueba_vivas() y muestra el cartel mientras siga abierta
--
-- NO toca la alarma real: gv_alerta_inactivo_abrir sigue rechazando 0/1 y gv_alertas_inactivo_vivas
-- sigue excluyéndolos, así que la TV del depósito no ve la prueba.
--
-- VENCE SOLA: abrir no hace nada desde las 18:35 ART y la lectura no devuelve nada desde las 18:40.
-- Cerrar anda siempre (para no dejar una fila abierta colgada).
--
-- Rollback:
--   drop function if exists public.gv_alerta_prueba_bano(boolean);
--   drop function if exists public.gv_alertas_prueba_vivas();

create or replace function public.gv_alerta_prueba_bano(p_abierto boolean)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_id bigint;
begin
  if not coalesce(p_abierto, false) then
    update public."GV_Alerta_Inactivo" set cerrada_en = now()
     where legajo = '1' and dispositivo = 'prueba-bano' and cerrada_en is null;
    get diagnostics v_id = row_count;
    return v_id;
  end if;
  -- v26.0 prueba temporal: vence 18:35 ART del 01/10
  if now() >= timestamptz '2026-10-01 18:35:00-03' then return null; end if;
  select id into v_id from public."GV_Alerta_Inactivo"
   where legajo = '1' and dispositivo = 'prueba-bano' and cerrada_en is null
     and abierta_en > now() - interval '2 hours'
   order by id desc limit 1;
  if v_id is not null then return v_id; end if;
  insert into public."GV_Alerta_Inactivo" (legajo, nombre, dispositivo)
  values ('1', 'PRUEBA (legajo 1)', 'prueba-bano')
  returning id into v_id;
  return v_id;
end $function$;

create or replace function public.gv_alertas_prueba_vivas()
returns table(id bigint, legajo text, nombre text, abierta_en timestamp with time zone, cerrada boolean)
language sql
stable security definer
set search_path to 'public'
as $function$
  -- v26.0 prueba temporal (Mon. Admin): legajo 1 en el baño. Vence 18:40 ART del 01/10.
  select a.id, a.legajo, a.nombre, a.abierta_en, a.cerrada_en is not null
    from public."GV_Alerta_Inactivo" a
   where a.legajo = '1' and a.dispositivo = 'prueba-bano'
     and now() < timestamptz '2026-10-01 18:40:00-03'
     and a.abierta_en > now() - interval '2 hours'
     and (a.cerrada_en is null or a.cerrada_en > now() - interval '1 minute')
   order by a.abierta_en;
$function$;

revoke all on function public.gv_alerta_prueba_bano(boolean) from public;
revoke all on function public.gv_alertas_prueba_vivas() from public;
grant execute on function public.gv_alerta_prueba_bano(boolean) to anon, authenticated;
grant execute on function public.gv_alertas_prueba_vivas() to anon, authenticated;
