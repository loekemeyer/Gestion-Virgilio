-- ============================================================================
-- v19.58 — `GV_Tandas_Auto_Log` NO PUEDE ANOTAR "no había nada que armar"
--          CUANDO EL FEED FALLÓ
--
-- Problema 403. El 17/09, con la base de LK ahogada, la Edge Function
-- `gv-ppp-web-tandas-diarias` escribió 30+ filas así:
--
--   estado  = 'intradia_sin_umbral'
--   motivo  = 'intradía: pendiente automático 0.000 m³ (0 NP) < umbral 0.001 m³…'
--   detalle = {"lk":{"error":"LK gv_pedidos_web_np_lk: HTTP 504 upstream request timeout"}, …}
--
-- O sea: el error estaba ahí abajo, pero el ESTADO decía que no había nada que
-- hacer. El armado estuvo 5 h 40 sin correr y todo figuraba en verde.
--
-- El arreglo de fondo va en el TypeScript (ya está en el repo,
-- `supabase/functions/gv-ppp-web-tandas-diarias/index.ts`, bloque `preErrores`):
-- un feed caído sale por la rama de error y contesta 500. Pero **la Edge
-- Function se deploya a mano desde el Dashboard**, así que hasta que alguien la
-- suba la base tiene que defenderse sola. Este trigger hace eso, y cuando la
-- función esté al día queda como no-op (la función ya escribirá 'error').
--
-- ⚠ Alcance a propósito CHICO: sólo toca `intradia_sin_umbral`, que es el caso
--   donde NO se armó nada Y encima falló una lectura. Un `intradia_ok` con un
--   error de una sola empresa NO se toca: ahí la otra empresa sí se armó, y su
--   error ya viaja en `motivo`.
--
-- ⚠ `GV_Tandas_Auto_Log` es una tabla NUESTRA (prefijo GV_), no compartida con
--   Producción: por eso acá sí corresponde un trigger.
-- ============================================================================

create or replace function public.gv_tandas_auto_log_estado_real()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_err text;
begin
  if new.estado is distinct from 'intradia_sin_umbral' then
    return new;
  end if;

  select string_agg(e, ' | ')
    into v_err
    from (
      select new.detalle->'lk'->>'error'   as e
      union all
      select new.detalle->'chef'->>'error'
    ) z
   where z.e is not null and btrim(z.e) <> '';

  if v_err is null then
    return new;   -- las dos lecturas anduvieron: el umbral SÍ significa algo
  end if;

  new.estado := 'error';
  new.motivo := left(v_err || ' — NO se pudo medir lo pendiente, así que el umbral no dice nada'
                     || coalesce(' (decía: ' || new.motivo || ')', ''), 4000);
  return new;
end
$function$;

drop trigger if exists zzz_estado_real on public."GV_Tandas_Auto_Log";
create trigger zzz_estado_real
  before insert on public."GV_Tandas_Auto_Log"
  for each row execute function public.gv_tandas_auto_log_estado_real();

-- ============================================================================
-- PRUEBA — se hace con INSERTS DE VERDAD y se borran. Leer la función no prueba
-- nada (regla del CLAUDE.md). Los tres casos, dentro de una transacción que se
-- aborta:
-- ============================================================================
-- begin;
--   insert into public."GV_Tandas_Auto_Log"(fecha_objetivo, estado, motivo, detalle)
--   values (current_date, 'intradia_sin_umbral', 'no llego al umbral',
--           '{"lk":{"error":"HTTP 504"},"chef":{"np":0}}'::jsonb),          -- → error
--          (current_date, 'intradia_sin_umbral', 'no llego al umbral',
--           '{"lk":{"np":0},"chef":{"np":0}}'::jsonb),                      -- → queda igual
--          (current_date, 'intradia_ok', 'chef: HTTP 500',
--           '{"chef":{"error":"HTTP 500"}}'::jsonb);                        -- → queda igual
--   select estado, left(motivo,70) motivo from public."GV_Tandas_Auto_Log"
--    order by id desc limit 3;
-- rollback;
--
-- Esperado: error / intradia_sin_umbral / intradia_ok.

-- ============================================================================
-- ROLLBACK
-- ============================================================================
-- drop trigger if exists zzz_estado_real on public."GV_Tandas_Auto_Log";
-- drop function if exists public.gv_tandas_auto_log_estado_real();
