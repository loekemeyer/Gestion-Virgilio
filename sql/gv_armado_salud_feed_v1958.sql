-- ============================================================================
-- v19.58 — EL CENTINELA DEL ARMADO TIENE QUE DECIR *POR QUÉ* NO CORRIÓ
--
-- Qué pasó (problema 403, 17/09 18:20 → 18/09 00:01 ART, 5 h 40 sin armar nada):
--   La base de LK quedó sin worker slots (problema 402) y `gv_pedidos_web_np_lk`
--   empezó a devolver 57014 / 504. La Edge Function `gv-ppp-web-tandas-diarias`
--   atrapaba ese error en el bloque intradía, dejaba `m3Auto` en 0 y caía por la
--   rama "no llegó al umbral": anotaba `estado = 'intradia_sin_umbral'`, motivo
--   "pendiente automático 0.000 m³ (0 NP) < umbral 0.001 m³" y contestaba
--   ok:true / HTTP 200. O sea, una lectura ROTA informada como "no había nada
--   que hacer". 30+ corridas seguidas así, ningún pedido web de LK programado,
--   y todo en verde.
--
--   Y el centinela no ayudaba: `gv_ppp_web_armado_salud` sólo miraba
--   `GV_PPP_Web_Armado_Log`, que en esas corridas NO TIENE FILA porque el
--   armador nunca se llamó. Decía "SIN CORRER hace mas de 20 min" sin poder
--   decir por qué, y decía lo mismo a las 3 de la mañana, cuando el cron 73 no
--   corre (`*/5 9-23 * * *` UTC = 06:00–20:55 ART) y no correr es lo correcto.
--
-- Qué cambia acá (sólo la vista; el arreglo de la Edge Function va en su repo):
--   1. Se cruza con `GV_Tandas_Auto_Log`, que la Edge Function escribe SIEMPRE,
--      corra o no el armador. Ahí está el motivo.
--   2. Las dos empresas salen siempre (lista fija + left join). Antes, si el
--      armador no había corrido nunca para una, esa empresa no aparecía: un
--      centinela que no muestra nada cuando todo está roto.
--   3. Tres estados nuevos que separan lo que antes era todo "SIN CORRER":
--        · FEED CAIDO      → hubo errores en los últimos intentos (con el motivo)
--        · sin nada que armar → el cron corrió hace poco y no había pendiente
--        · fuera de horario → estamos fuera de la ventana del cron 73
--
-- Rollback al final del archivo.
-- ============================================================================

create or replace view public.gv_ppp_web_armado_salud as
with emp as (
  select unnest(array['lk','chef']) as empresa
),
u as (
  select l.empresa,
         max(l.ts) as ultima,
         max(l.ms) filter (where l.ts >= now() - interval '24 hours') as ms_max_24h,
         sum(l.pospuestos) filter (where l.ts >= now() - interval '2 hours') as pospuestos_2h,
         count(*) filter (where l.ts >= now() - interval '2 hours') as corridas_2h
    from public."GV_PPP_Web_Armado_Log" l
   group by l.empresa
),
b as (
  select distinct on (l.empresa) l.empresa, l.pospuestos, l.entraron, l.ms, l.ts
    from public."GV_PPP_Web_Armado_Log" l
   order by l.empresa, l.ts desc
),
-- El último intento de la Edge Function, haya llamado al armador o no.
-- ⚠ Va como AGREGADO, no como `order by … limit 1`: los `cross join` de abajo
--   con una tabla vacía devolverían CERO filas, o sea el centinela mudo justo
--   el día que no hay ni un intento. Así siempre sale una fila (con nulls).
t as (
  select (array_agg(g.estado order by g.corrida_en desc))[1] as estado,
         (array_agg(g.motivo order by g.corrida_en desc))[1] as motivo,
         max(g.corrida_en) as corrida_en
    from public."GV_Tandas_Auto_Log" g
),
-- cuántos de los últimos 12 intentos fallaron (12 x 5 min = la última hora)
tf as (
  select count(*) filter (where z.estado = 'error') as errores_12,
         count(*) as n_12
    from (select g.estado from public."GV_Tandas_Auto_Log" g
           order by g.corrida_en desc limit 12) z
),
-- ¿estamos dentro de la ventana del cron 73? (*/5 9-23 UTC = 06:00-20:55 ART)
h as (
  select extract(hour from (now() at time zone 'America/Argentina/Buenos_Aires'))::int between 6 and 20
         as en_horario
)
select emp.empresa,
       u.ultima,
       round(extract(epoch from now() - u.ultima) / 60::numeric)::integer as hace_min,
       b.entraron  as ultima_entraron,
       b.pospuestos as ultima_pospuestos,
       b.ms         as ultima_ms,
       u.ms_max_24h,
       8000 - coalesce(u.ms_max_24h, 0) as margen_ms,
       coalesce(u.corridas_2h, 0::bigint)   as corridas_2h,
       coalesce(u.pospuestos_2h, 0::bigint) as pospuestos_2h,
       -- ⚠ las columnas NUEVAS van AL FINAL, después de `estado`: un
       --   `create or replace view` sólo deja agregar columnas al final, y
       --   meterlas en el medio obligaría a un DROP (y a recrear lo que cuelgue).
       case
         -- lo primero: el feed caído. Es lo que costó 5 h 40 el 17/09.
         when tf.errores_12 >= 3
           then 'FEED CAIDO: ' || left(coalesce(t.motivo, 'sin motivo'), 140)
         when u.ultima is null or u.ultima < now() - interval '20 minutes' then
           case
             when t.corrida_en is null or t.corrida_en < now() - interval '20 minutes' then
               case when h.en_horario
                    then 'SIN CORRER hace mas de 20 min'
                    else 'fuera de horario (el cron 73 corre 06:00-20:55 ART)' end
             else 'sin nada que armar (ultimo intento: ' || coalesce(t.estado, '?') || ')'
           end
         when coalesce(u.ms_max_24h, 0) > 6000
           then 'LENTO: a menos de 2 s del limite de 8 s'
         when coalesce(u.pospuestos_2h, 0::bigint) > 0
           then 'BACKLOG: quedaron pedidos para la proxima corrida'
         else 'ok'
       end as estado,
       t.corrida_en as ultimo_intento,
       t.estado     as ultimo_intento_estado,
       left(coalesce(t.motivo, ''), 200) as ultimo_intento_motivo,
       tf.errores_12
  from emp
  left join u on u.empresa = emp.empresa
  left join b on b.empresa = emp.empresa
  cross join t
  cross join tf
  cross join h;

alter view public.gv_ppp_web_armado_salud set (security_invoker = true);
grant select on public.gv_ppp_web_armado_salud to anon, authenticated;

-- ============================================================================
-- CHEQUEO
--   select * from public.gv_ppp_web_armado_salud;
--   -- las dos empresas siempre, con ultimo_intento / ultimo_intento_estado /
--   -- ultimo_intento_motivo, y el estado diciendo cuál de las cuatro cosas es.
-- ============================================================================

-- ============================================================================
-- ROLLBACK — la vista tal como estaba en la v19.55
-- ============================================================================
-- create or replace view public.gv_ppp_web_armado_salud as
--  with u as (
--          select l.empresa, max(l.ts) as ultima,
--             max(l.ms) filter (where l.ts >= (now() - '24:00:00'::interval)) as ms_max_24h,
--             sum(l.pospuestos) filter (where l.ts >= (now() - '02:00:00'::interval)) as pospuestos_2h,
--             count(*) filter (where l.ts >= (now() - '02:00:00'::interval)) as corridas_2h
--            from "GV_PPP_Web_Armado_Log" l group by l.empresa
--         ), b as (
--          select distinct on (l.empresa) l.empresa, l.pospuestos, l.entraron, l.ms, l.ts
--            from "GV_PPP_Web_Armado_Log" l order by l.empresa, l.ts desc
--         )
--  select u.empresa, u.ultima,
--     round(extract(epoch from now() - u.ultima) / 60::numeric)::integer as hace_min,
--     b.entraron as ultima_entraron, b.pospuestos as ultima_pospuestos, b.ms as ultima_ms,
--     u.ms_max_24h, 8000 - coalesce(u.ms_max_24h, 0) as margen_ms, u.corridas_2h,
--     coalesce(u.pospuestos_2h, 0::bigint) as pospuestos_2h,
--         case
--             when u.ultima < (now() - '00:20:00'::interval) then 'SIN CORRER hace mas de 20 min'::text
--             when coalesce(u.ms_max_24h, 0) > 6000 then 'LENTO: a menos de 2 s del limite de 8 s'::text
--             when coalesce(u.pospuestos_2h, 0::bigint) > 0 then 'BACKLOG: quedaron pedidos para la proxima corrida'::text
--             else 'ok'::text
--         end as estado
--    from u join b on b.empresa = u.empresa;
-- alter view public.gv_ppp_web_armado_salud set (security_invoker = true);
-- grant select on public.gv_ppp_web_armado_salud to anon, authenticated;
