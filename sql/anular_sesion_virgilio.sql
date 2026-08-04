-- =====================================================================
-- anular_sesion_virgilio.sql — ANULAR una sesión empezada por error (v7.13 · RT en v7.15)
--
-- Pedido del usuario: al empezar el picking de una tanda no había forma clara de
-- darla de baja. "Cerrar" sólo sale del modal: el picking queda ABIERTO (EP sin
-- TP = inconsistencia tipo A), la tanda sigue reservada en Tandas_Lock y el
-- operario no puede arrancar otra. Ahora la app tiene un botón rojo "✕ Anular
-- picking" (y su equivalente en insumos RI/EI) que llama a estas RPC.
--
-- ¿Por qué RPC y no un DELETE directo con la anon key? La policy de delete
-- (`delete_recientes_undo`, la que usa el "Deshacer") sólo alcanza filas con
-- `created_at > now() - 15 min`, y un picking se anula bastante después.
--
-- Guardas (las dos funciones): sólo tocan el evento de APERTURA que sigue
-- ABIERTO, del propio legajo, de las últimas 24 h. Si ya se cerró (TP para el
-- picking, evento con ts_inicio para el toggle) devuelven 'ya_cerrado' y no
-- borran nada. Mismo patrón que `anular_modo_op` (recepción).
--
-- Devuelven: 'ok' | 'sin_ep' / 'sin_apertura' | 'ya_cerrado' | 'faltan_datos'.
-- Probadas en Supabase (2026-08-04): EP + PKC de prueba → 'ok' → 0 filas; la 2ª
-- llamada devuelve 'sin_ep'.
-- =====================================================================

-- (1) PICKING: borra el EP abierto de esa tanda + sus detalles PKC y suelta el lock.
create or replace function public.anular_picking_virgilio(p_legajo text, p_tanda text)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id uuid; v_ts timestamptz; v_leg text; v_tanda text;
begin
  v_leg := btrim(coalesce(p_legajo, ''));
  v_tanda := upper(btrim(coalesce(p_tanda, '')));
  if v_leg = '' or v_tanda = '' then return 'faltan_datos'; end if;

  select id, created_at into v_id, v_ts
    from public."Registros_Produccion_Virgilio"
   where opcion = 'EP' and legajo = v_leg
     and upper(btrim(coalesce(texto, ''))) = v_tanda
     and created_at > now() - interval '24 hours'
   order by created_at desc limit 1;
  if v_id is null then return 'sin_ep'; end if;

  -- si ya lo cerró con TP, el picking existió: no se anula
  if exists (select 1 from public."Registros_Produccion_Virgilio"
              where opcion = 'TP' and legajo = v_leg
                and upper(btrim(coalesce(texto, ''))) = v_tanda
                and created_at >= v_ts) then
    return 'ya_cerrado';
  end if;

  delete from public."Registros_Produccion_Virgilio"
   where opcion = 'PKC' and legajo = v_leg
     and upper(btrim(coalesce(texto, ''))) like v_tanda || '|%'
     and created_at >= v_ts;
  delete from public."Registros_Produccion_Virgilio" where id = v_id;

  begin perform public.tanda_liberar(v_tanda, 'picking', v_leg); exception when others then null; end;
  return 'ok';
end $fn$;

-- (2) TOGGLE (RI/EI insumos y RT recepción): borra el evento de apertura que quedó abierto.
--     Apertura = ts_inicio null; cierre = ts_inicio no nulo (convención de la app).
create or replace function public.anular_toggle_virgilio(p_legajo text, p_opcion text)
returns text language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id uuid; v_ts timestamptz; v_leg text; v_op text;
begin
  v_leg := btrim(coalesce(p_legajo, ''));
  v_op  := btrim(coalesce(p_opcion, ''));
  if v_leg = '' or v_op not in ('RI', 'EI', 'RT') then return 'faltan_datos'; end if;

  select id, created_at into v_id, v_ts
    from public."Registros_Produccion_Virgilio"
   where opcion = v_op and legajo = v_leg and ts_inicio is null
     and created_at > now() - interval '24 hours'
   order by created_at desc limit 1;
  if v_id is null then return 'sin_apertura'; end if;

  if exists (select 1 from public."Registros_Produccion_Virgilio"
              where opcion = v_op and legajo = v_leg and ts_inicio is not null
                and created_at >= v_ts) then
    return 'ya_cerrado';
  end if;

  delete from public."Registros_Produccion_Virgilio" where id = v_id;
  return 'ok';
end $fn$;

revoke all on function public.anular_picking_virgilio(text, text) from public;
revoke all on function public.anular_toggle_virgilio(text, text) from public;
grant execute on function public.anular_picking_virgilio(text, text) to anon, authenticated;
grant execute on function public.anular_toggle_virgilio(text, text) to anon, authenticated;
