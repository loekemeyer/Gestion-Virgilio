-- =============================================================================
-- gv_ppp_web_intradia.sql — ARMADO INTRADÍA DE ZONA 1 Y 2 (2026-09-05, idea 7317)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · objetos NUEVOS gv_ / filas nuevas en PPP_Web_Config
-- =============================================================================
-- LO QUE PIDIÓ EL DUEÑO: "la programación de los pedidos que se entregan en zona 1 y 2
-- deben programarse inmediatamente, apenas llegan, porque a esa zona voy todos los días".
-- Aclarado (AskUserQuestion): "cuando se llega a 0,80 m³ para zona 1 y 2, para el próximo
-- día que se pueda entregar según PPP; excepciones son las de súper". Lo que no llega a
-- 0,80 lo arma igual el job de las 00:01. "Hoy" cuenta si es antes de las 12:00 y hay cupo.
--
-- CÓMO. El armado ya es idempotente y ya se limita a `zonas_automaticas` (1 y 2); Súper
-- nunca es automático. Lo que faltaba era un disparador durante el día y una regla de
-- fecha. Esta función elige la fecha; la Edge Function `gv-ppp-web-tandas-diarias` con
-- `{"intradia": true}` mide lo pendiente de zonas automáticas (sin tanda) y, si suma
-- ≥ `intradia_umbral_m3`, corre el armado normal para esa fecha. Cron
-- `gv-ppp-web-tandas-intradia`: cada 15 min, lun-vie 07:00–18:45 ART.
--
-- NO TOCA PRODUCCIÓN: lee PPP_Web_Programacion (nuestra), Config (nuestra), feriados.
-- ROLLBACK: select cron.unschedule('gv-ppp-web-tandas-intradia');
--           drop function public.gv_ppp_web_proximo_dia_entrega(timestamptz);
--           delete from public."PPP_Web_Config" where clave in ('intradia_umbral_m3','intradia_corte_hora');
-- =============================================================================

insert into public."PPP_Web_Config" (clave, valor, valor_texto, descripcion) values
  ('intradia_umbral_m3', 0.80, null,
   'ARMADO INTRADIA (idea 7317). Cuando lo pendiente SIN tanda de las zonas automaticas (zonas_automaticas, hoy 1 y 2; Super nunca) suma este m3 o mas, la Edge Function arma las tandas ya, sin esperar al job de las 00:01. Dueno 2026-09-05: 0,80 (el mismo tope de mezcla). Lo que no llega lo arma igual el job de la noche.'),
  ('intradia_corte_hora', null, '12:00',
   'ARMADO INTRADIA. Hasta esta hora (Argentina) lo que se arma durante el dia va para HOY si hay cupo; despues, para el proximo dia habil con cupo (m3_max_dia). Dueno 2026-09-05.')
on conflict do nothing;

-- Próximo día en que se puede entregar: hoy si es antes del corte, es hábil y queda cupo;
-- si no, el primer día hábil siguiente con cupo (m3 programados < m3_max_dia).
create or replace function public.gv_ppp_web_proximo_dia_entrega(p_ahora timestamptz default now())
returns date
language plpgsql
stable
security definer
set search_path to 'public', 'planify'
as $function$
declare
  v_local timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  v_corte time := coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'intradia_corte_hora'), '12:00')::time;
  v_cupo  numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'm3_max_dia'), 5.00);
  v_d     date := v_local::date;
  v_usado numeric;
  v_i     int := 0;
begin
  if v_local::time >= v_corte then v_d := v_d + 1; end if;
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
end $function$;

comment on function public.gv_ppp_web_proximo_dia_entrega(timestamptz) is
  'Armado intradía (idea 7317): hoy si es antes de intradia_corte_hora, hábil y con cupo; si no, el próximo hábil con cupo (m3_max_dia).';
revoke all on function public.gv_ppp_web_proximo_dia_entrega(timestamptz) from public, anon;
grant execute on function public.gv_ppp_web_proximo_dia_entrega(timestamptz) to authenticated, service_role;

-- Cron (UTC): cada 15 min de 10:00 a 21:45 UTC = 07:00 a 18:45 ART, lunes a viernes.
-- select cron.schedule('gv-ppp-web-tandas-intradia', '*/15 10-21 * * 1-5', $$
--   select net.http_post(
--     url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/gv-ppp-web-tandas-diarias',
--     headers := jsonb_build_object('Content-Type', 'application/json',
--                  'Authorization', 'Bearer ' || (select v from lecturacvs.app_secrets where k = 'SUPABASE_SERVICE_ROLE_KEY')),
--     body    := '{"intradia": true}'::jsonb);
-- $$);
