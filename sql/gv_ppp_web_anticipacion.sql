-- ANTICIPACIÓN MÍNIMA · v13.22 (2026-09-05 sábado, noche) · migración `gv_ppp_web_anticipacion_minima_v1322`
-- Dueño: "el lunes los operarios no van a tener que aplicar nada de la PPP para ese mismo día, salvo el
-- armado (de lo que ISIS ya dejó). Lo que haga Gestión va recién de acá a cuatro, cinco días en adelante."
--
-- → Gestión NUNCA programa para antes de hoy + N días hábiles. N = PPP_Web_Config.dias_anticipacion_min (4).
--   0 = como antes (hoy si es antes del corte, si no mañana). Afecta, todo en el backend:
--     · gv_ppp_web_dia_minimo(ahora)          → el primer día permitido (nueva)
--     · gv_ppp_web_proximo_dia_entrega(ahora) → arranca en el día mínimo (antes: hoy / mañana)
--     · gv_ppp_web_dia_salida(...)            → zonas manuales: primer camión ≥ día mínimo
--     · gv_ppp_web_calendario(...)            → columnas nuevas `muy_pronto`, `dia_minimo`
--     · gv_ppp_web_tanda_programar(...)       → rechaza p_fecha < día mínimo ("El 08/09 es muy pronto…")
--     · cron jobid 71 (job 00:01)             → manda {"fecha": gv_ppp_web_proximo_dia_entrega()} a la
--                                               Edge Function (que sin fecha usaba HOY). El intradía
--                                               (jobid 73) ya pedía la fecha al backend.
--   Medido (sábado 05/09 22:30): dia_minimo = jue 10 · desde el lunes 07 00:01 = vie 11 · lunes 13:00 = lun 14.
--   Calendario 07..14 (mirado el sábado): 07/08/09 muy_pronto = true. dia_salida simulado lunes 09:00:
--   zona 1 → vie 11, zona 4 → vie 11 (primer camión a la zona ≥ día mínimo), zona 6 → lun 14 (D69C).
-- Rollback total: update public."PPP_Web_Config" set valor = 0 where clave = 'dias_anticipacion_min';
--   (las funciones quedan, con N = 0 se comportan como antes). Para volver el cron:
--   select cron.alter_job(71, command := $$ … body := '{}'::jsonb $$);
-- Objetos NUESTROS (gv_*/ppp_web_*). No toca Producción.

insert into public."PPP_Web_Config" (clave, valor, descripcion)
values ('dias_anticipacion_min', 4, 'v13.22 · Gestión programa entregas recién a partir de hoy + N días hábiles (job 00:01, intradía, A Programar). 0 = hoy/mañana como antes.')
on conflict (clave) do nothing;

create or replace function public.gv_ppp_web_dia_minimo(p_ahora timestamptz default now())
returns date language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_local timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  v_corte time := coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'intradia_corte_hora'), '12:00')::time;
  v_n     int  := coalesce((select valor from public."PPP_Web_Config" where clave = 'dias_anticipacion_min'), 0)::int;
  v_d     date := v_local::date;
  v_g     int  := 0;
begin
  if v_local::time >= v_corte then v_d := v_d + 1; end if;
  while v_n > 0 and v_g < 60 loop
    v_d := v_d + 1; v_g := v_g + 1;
    if public.gv_es_dia_habil(v_d) then v_n := v_n - 1; end if;
  end loop;
  return v_d;
end $$;
revoke all on function public.gv_ppp_web_dia_minimo(timestamptz) from public, anon;
grant execute on function public.gv_ppp_web_dia_minimo(timestamptz) to authenticated, service_role;

create or replace function public.gv_ppp_web_proximo_dia_entrega(p_ahora timestamptz default now())
returns date language plpgsql stable security definer set search_path to 'public', 'planify' as $$
declare
  v_cupo  numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'm3_max_dia'), 5.00);
  v_d     date := public.gv_ppp_web_dia_minimo(p_ahora);   -- v13.22: anticipación mínima
  v_usado numeric;
  v_i     int := 0;
begin
  loop
    v_i := v_i + 1;
    if public.gv_es_dia_habil(v_d) then
      select coalesce(sum(m3), 0) into v_usado
        from public."PPP_Web_Programacion"
       where fecha_entrega = v_d and coalesce(nullif(trim(tanda), ''), '') <> '';
      if v_usado < v_cupo then return v_d; end if;
    end if;
    v_d := v_d + 1;
    exit when v_i > 40;
  end loop;
  return v_d;
end $$;

-- gv_ppp_web_dia_salida: ver sql/gv_ppp_web_dia_salida.sql (v_desde := gv_ppp_web_dia_minimo(p_ahora)).
-- gv_ppp_web_calendario: ver sql/gv_ppp_web_calendario.sql (+ muy_pronto, dia_minimo).

-- gv_ppp_web_tanda_programar: se insertó, después del chequeo de fecha nula:
--   if p_fecha < public.gv_ppp_web_dia_minimo() then
--     raise exception 'El % es muy pronto: Gestión programa desde el %.', to_char(p_fecha,'DD/MM'), to_char(public.gv_ppp_web_dia_minimo(),'DD/MM');
--   end if;
-- (hecho con replace() sobre pg_get_functiondef para no retipear la función; la migración falla si no
--  encuentra el punto de inserción).

select cron.alter_job(71, command := $cmd$
  select net.http_post(
    url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/gv-ppp-web-tandas-diarias',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'Authorization', 'Bearer ' || (select v from lecturacvs.app_secrets where k = 'SUPABASE_SERVICE_ROLE_KEY')),
    body    := jsonb_build_object('fecha', public.gv_ppp_web_proximo_dia_entrega()::text));
  $cmd$);
