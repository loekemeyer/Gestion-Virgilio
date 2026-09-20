-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ANCLA DE ZONA EN EL ARMADO AUTOMÁTICO · v20.26 (2026-09-20)
--
-- Luis, 20/09: *"conectala"* · *"pero si ya fue programado, ya está. La lógica es para los
-- a programar únicamente"* · *"yo quiero que todo se programe automático"*.
--
-- QUÉ CAMBIA, EN UNA LÍNEA: para una zona automática, el día deja de ser "el próximo día con
-- cupo" y pasa a ser "el día en que YA va un camión a esa zona", si ese día cae dentro de la
-- ventana. Recién si no hay camión a esa zona, cascada de cupo como hasta hoy.
--
-- POR QUÉ. Medido el 20/09 sobre los 156 pedidos vivos: zona 5 iba 4 días distintos para
-- 3,45 m³ en total (0,86 m³ por viaje), zona 6 iba 3 días para 3,31 y zona 3 tres días para
-- 1,91. El armador elegía el día por cupo y el camión salía después, así que nada juntaba los
-- pedidos de una misma zona. Es el punto 3 de la lógica de Luis ("los km recorridos entre
-- destinos, los menores posibles") contra el punto 4 ("no más de 10 días hábiles en salir").
--
-- LA VENTANA ES EL COMPROMISO ENTRE ESOS DOS PUNTOS. Simulado con gv_ancla_demora_resumen
-- sobre los 60 días reales anteriores (410 pedidos, 164,97 m³) — ojo, se llama con
-- offset = ventana, ver §3.kk.1:
--
--   ventana | cam/día | máx/día | paradas/cam |   km  | p50 | p90 | máx | +10 días
--      real |   2,69  |    4    |    3,63     |   —   |  —  |  —  |  —  |   41
--       5   |   2,64  |    9    |    3,69     | 4.629 |  2  |  3  |  4  |    0
--       8   |   2,11  |    5    |    5,13     | 3.858 |  3  |  6  |  6  |    0
--    → 10   |   1,87  |    2    |    5,77     | 3.600 |  4  |  7  |  8  |    0
--      13   |   1,68  |    2    |    7,19     | 3.275 |  5  |  9  |  9  |    0
--
-- Se toma 10: es la primera ventana que cumple el tope de 2 camiones por día (punto 1) con 0
-- pedidos sin lugar, baja 22 % los km contra la ventana corta, y deja el p90 de demora en 7
-- días hábiles con 3 de margen contra el límite de 10 (punto 4).
--
-- LO QUE NO TOCA, A PROPÓSITO:
--   · Lo YA programado. Los tres pases llevan el mismo guard `not exists (… tanda <> '')` que
--     el resto del armador: una NP con tanda no vuelve a entrar. Los 156 pedidos vivos del
--     20/09 salen como están.
--   · El cupo. El pase nuevo llama a ppp_web_armar_tandas con p_forzar_cods = '{}', o sea que
--     el día ancla respeta los 4,30 m³ (punto 2). Y por eso recorre TODOS los días con camión a
--     esa zona dentro de la ventana, del más cercano al más lejano: si el primero no tiene cupo
--     se prueba el siguiente, y recién si no entra en ninguno cae a la cascada. Sin esa
--     iteración un día lleno mandaba el pedido a (b) y volvía a fundar el viaje solo — medido
--     el 20/09: la prueba de zona 6 salta 21/09 (6,00 m³) y 22/09 (4,55) y engancha el 02/10.
--     El pase (c) de zonas manuales sí fuerza, y queda como está.
--   · El súper. `gv_es_super` afuera: un súper NUNCA se cuelga del camión de clientes (regla
--     del dueño v14.23). Es la cuarta puerta del mismo agujero — Dorinka y Diarco vienen con
--     zona numérica ("Zona 5 - GBA Oeste"), así que un filtro por `'^Zona [0-9]+'` los deja
--     pasar. Por eso el guard es gv_es_super y no el regex.
--   · Retira y sin zona. No matchean `^Zona N`, siguen en A Programar salvo el pase (a4).
--
-- INTERRUPTOR: PPP_Web_Config.ancla_activa = 0 → el pase (b0) no hace nada y todo vuelve a la
-- cascada de cupo, sin redeployar ni tocar código.
--
-- ⚠ EL CUERPO DE gv_ppp_web_armar_pendientes NO ESTÁ EN EL REPO (son 23.483 caracteres que
--   crecieron pase por pase; sql/gv_ppp_web_armar_pendientes.sql quedó en la v13.47). Por eso
--   el parche de abajo NO reescribe la función: trae la definición VIVA con pg_get_functiondef,
--   le inserta el bloque encima y la vuelve a crear, y aborta si el anclaje no aparece exacto
--   una sola vez. Es la regla ⚠⚠⚠ del CLAUDE.md, y es la que evita pisar lo que otra sesión
--   escribió el mismo día (problema 390).
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1. CONFIG ──────────────────────────────────────────────────────────────────────────
-- ⚠ PPP_Web_Config NO tiene unique sobre `clave` (medido el 20/09): nada de `on conflict`.
insert into public."PPP_Web_Config" (clave, valor)
select 'ancla_activa', 1
 where not exists (select 1 from public."PPP_Web_Config" where clave = 'ancla_activa');
insert into public."PPP_Web_Config" (clave, valor)
select 'ancla_ventana_habiles', 10
 where not exists (select 1 from public."PPP_Web_Config" where clave = 'ancla_ventana_habiles');

-- ── 2. LOS DÍAS ANCLA ──────────────────────────────────────────────────────────────────
-- gv_ppp_web_dia_camion dice en qué día YA va un camión a esa zona, pero devuelve `min()` y
-- ⚠ topa el piso en mañana a propósito (v15.48), así que NO se la puede iterar para pedir "el
-- siguiente": con cualquier p_desde devuelve siempre el mismo día. Por eso esta función repite
-- su consulta sin el min() y sin el clamp, y le agrega el techo de la ventana.
-- ⚠ Los filtros tienen que quedar IGUALES que allá — tanda no vacía, KRIKOS afuera y sobre todo
--   gv_es_super / gv_es_super_np. Tiene centinela en GV_Reglas_Centinela por esa duplicación.
create or replace function public.gv_ppp_web_dias_ancla(
  p_zona text, p_desde date, p_ventana int default null)
returns date[]
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  with zn as (select (regexp_match(btrim(coalesce(p_zona, '')), '^Zona\s*([0-9]+)'))[1] as n),
  vent as (select coalesce(p_ventana,
                    (select valor::int from public."PPP_Web_Config" where clave = 'ancla_ventana_habiles'),
                    10) as v),
  piso as (select least(coalesce(p_desde, current_date + 1), current_date + 1) as d),
  hor as (select max(dia) as h from (
            select g::date dia, row_number() over (order by g) rn
              from piso, generate_series(piso.d, piso.d + 45, interval '1 day') g
             where public.gv_es_dia_habil(g::date)) q, vent
           where q.rn <= vent.v),
  dias as (
    select w.fecha_entrega as dia
      from public."PPP_Web_Programacion" w, zn, piso, hor
     where zn.n is not null
       and w.fecha_entrega >= piso.d and w.fecha_entrega <= hor.h
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and (regexp_match(btrim(coalesce(w.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
       and not public.gv_es_super(w.empresa, w.cod_cliente)
    union
    select left(btrim(i.fecha_entrega::text), 10)::date
      from public.gv_ppp_programacion_diaria i, zn, piso, hor
     where zn.n is not null
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date >= piso.d
       and left(btrim(i.fecha_entrega::text), 10)::date <= hor.h
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS'
       and (regexp_match(btrim(coalesce(i.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
       and not public.gv_es_super_np(i.np, i.cod))
  select coalesce(array_agg(dia order by dia), '{}') from (select distinct dia from dias) z;
$function$;

revoke all on function public.gv_ppp_web_dias_ancla(text, date, int) from public;
grant execute on function public.gv_ppp_web_dias_ancla(text, date, int) to anon, authenticated, service_role;

-- ── 3. EL PASE (b0) DENTRO DEL ARMADOR ─────────────────────────────────────────────────
-- El parche completo (DO block con pg_get_functiondef + substring por marcadores) está en
-- docs/SUPABASE-GESTION-VIRGILIO.md §3.kl. Se reaplica trayendo la definición VIVA: el cuerpo
-- de gv_ppp_web_armar_pendientes NO vive en el repo y no hay que retipearlo nunca.
-- El bloque que queda insertado, justo ANTES de "-- (b) zonas automaticas en cascada":
--
--   drop table if exists _gv_anc;
--   create temp table _gv_anc (d date, x jsonb) on commit drop;
--   insert into _gv_anc
--   select d, x from jsonb_array_elements(p_filas) x,
--        lateral unnest(public.gv_ppp_web_dias_ancla(x->>'zona', current_date + 1)) d
--    where coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
--      and public.gv_ppp_web_zona_automatica(x->>'zona')
--      and not public.gv_es_super(p_empresa, x->>'cod')
--      and coalesce((select valor from public."PPP_Web_Config" where clave = 'ancla_activa'), 1) <> 0;
--   for r in select distinct d from _gv_anc order by d loop
--     continue when <no queda ninguna fila de ese dia sin tanda>;
--     insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d,
--       <las filas de ese dia que siguen sin tanda>, '{}', false);
--     insert into _gv_res select r.d, t.* ... from _gv_tmp t;
--   end loop;

-- ── 4. CENTINELAS ──────────────────────────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
 ('gv_ppp_web_armar_pendientes','funcion','gv_ppp_web_dias_ancla',
  'El dia de una zona automatica lo da el camion que YA va a esa zona (ancla), no el cupo. Luis 20/09.','Luis','v20.26'),
 ('gv_ppp_web_armar_pendientes','funcion','gv_es_super\(p_empresa',
  'El pase del ancla deja afuera a los super: un super no se cuelga del camion de clientes (v14.23).','Luis','v20.26'),
 ('gv_ppp_web_dias_ancla','funcion','gv_es_super',
  'gv_ppp_web_dias_ancla copia los filtros de gv_ppp_web_dia_camion: un camion de super NO es camion a esa zona.','Luis','v20.26')
) v(objeto,clase,patron,regla,quien_pidio,version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto=v.objeto and c.patron=v.patron);

-- ── 5. CÓMO SE PROBÓ (y cómo hay que volver a probarlo) ────────────────────────────────
-- Leer la función NO prueba nada: el pase nuevo sólo explota cuando ENTRA por ahí. Se corre el
-- armador de verdad con filas de prueba, dentro de un `do` que termina en `raise exception`
-- para que la transacción se aborte y no quede nada escrito. Resultado del 20/09:
--
--   Zona 4 → 01/10  (el único día con camión a esa zona)
--   Zona 6 → 02/10  (saltea 21/09 con 6,00 m³ y 22/09 con 4,55: los dos sin cupo)
--   Súper Matiz (cod 4263, zona "Zona 5 - GBA Oeste") → NO se programa. Regla v14.23 en pie.
--   Una NP ya programada (order 1377, tanda E12R, 21/09) entra y sale IGUAL.
--
-- ⚠ Dos trampas del `p_filas` de prueba, que costaron dos corridas: `p_forzar` es un ARRAY
--   ('[]', no '{}') y `m3_parcial` es BOOLEAN, no el m³ parcial.
