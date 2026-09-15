-- ═══════════════════════════════════════════════════════════════════════════════════════
-- CENTINELA: CAMIONES PASADOS DE CAPACIDAD — 2026-09-15
-- Luis: *"contempla capacidad máxima del camión eso, no? no puede asignar tandas a lo loco
--        ahí que haga que termine con más tandas de lo que le entra al camión, no? chequeá eso"*
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- LA RESPUESTA ES QUE NO LA CONTEMPLA, y no es sólo el bloque que preguntó: **el tope por
-- CAMIÓN no existe en el backend**. Medido: `PPP_Web_Config.camion_m3_tope` (6,00) tiene CERO
-- apariciones en `pg_proc`.
--
--   select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.prosrc ilike '%camion_m3_tope%';   -- vacío
--
-- Los dos topes que el backend SÍ aplica son otra cosa y no tapan éste:
--   · `tanda_m3_max_mezcla` (0,80) → por TANDA, no por camión;
--   · `gv_ppp_web_cupo` (pickers × 3 m³) → cupo de PICKING del día entero, no por camión.
-- Y el 6 del front (`pppGetCfg().dayCap`) vive en el `localStorage` de cada máquina, sólo pinta
-- el aviso naranja, y ni siquiera es el mismo dato que la clave de la base.
--
-- Dónde falta el chequeo, concretamente:
--   · `gv_ppp_web_dia_camion` elige el primer día que ya tiene camión a esa zona **sin mirar
--     cuánto lleva encima**;
--   · el reuso de camión de `ppp_web_armar_tandas` (v13.60) mete la tanda nueva en el camión
--     que ya va ese día **sin sumar m³**.
--
-- Al 15/09 NO explotó por apilado —el camión con más tandas va en 3,61 m³ de 6— pero eso es
-- azar, no una guarda. Esta vista es para enterarse, no para frenar: **no cambia el armado**.
--
-- `que_pasa` separa los dos casos, que se arreglan distinto:
--   · `apilado` → el automático juntó de más: ahí sirve un tope al reusar el camión;
--   · `una sola NP no entra en el camion` → ningún reparto lo arregla, hay que partir el
--     pedido o mandar otro camión. Los 3 del 15/09 son todos de éstos (Matiz SA).
--
-- Chequeo: `select * from public.gv_ppp_camion_pasado;` — vacía = todo bien.
-- Mismo criterio que `gv_ppp_super_mezclado` (v14.23).
-- ═══════════════════════════════════════════════════════════════════════════════════════

create or replace view public.gv_ppp_camion_pasado as
with filas as (
  select w.fecha_entrega as dia, upper(btrim(w.tanda)) as tanda,
         coalesce(w.m3, 0) as m3, coalesce(w.zona, '') as zona
    from public."PPP_Web_Programacion" w
   where coalesce(nullif(btrim(w.tanda), ''), '') <> '' and w.fecha_entrega is not null
  union all
  select left(btrim(i.fecha_entrega::text), 10)::date, upper(btrim(i.tanda)),
         coalesce(i.m3, 0), coalesce(i.zona, '')
    from public.gv_ppp_programacion_diaria i
   where coalesce(nullif(btrim(i.tanda), ''), '') <> ''
     and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
), cam as (
  -- El camión es LETRA+NN del código de tanda (D69H → D69), igual que el tablero y Producción.
  select dia, (regexp_match(tanda, '^([A-Z]+[0-9]+)'))[1] as camion,
         round(sum(m3), 3) as m3, count(distinct tanda)::int as tandas, count(*)::int as nps,
         bool_or(zona ~* 'super|retira|expo') as excluido
    from filas
   where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
   group by 1, 2
)
select c.dia, c.camion, c.m3, c.tandas, c.nps,
       (select coalesce(valor, 6.00) from public."PPP_Web_Config" where clave = 'camion_m3_tope') as tope,
       round(100 * c.m3 / nullif((select coalesce(valor, 6.00) from public."PPP_Web_Config" where clave = 'camion_m3_tope'), 0)) as pct,
       case when c.nps = 1 then 'una sola NP no entra en el camion'
            else 'apilado: ' || c.tandas || ' tandas juntas' end as que_pasa
  from cam c
 where not c.excluido
   and c.m3 > (select coalesce(valor, 6.00) from public."PPP_Web_Config" where clave = 'camion_m3_tope')
 order by c.dia, c.m3 desc;

-- ⚠ security_invoker SIEMPRE: sin esto la vista corre como `postgres` y saltea la RLS.
alter view public.gv_ppp_camion_pasado set (security_invoker = true);
grant select on public.gv_ppp_camion_pasado to anon, authenticated;

-- ═══ MEDICIÓN AL 2026-09-15 ════════════════════════════════════════════════════════════
-- dia        camion  m3     tandas nps tope pct que_pasa
-- 2026-09-16 D71     9.250  1      1   6.00 154 una sola NP no entra en el camion  (NP 97889)
-- 2026-10-07 D70     6.467  1      1   6.00 108 una sola NP no entra en el camion  (NP 97964)
-- 2026-10-28 D63     6.167  1      1   6.00 103 una sola NP no entra en el camion  (NP 98426)
-- Las tres son de Matiz SA (cod 4263) y vienen así desde ISIS. Ningún apilado pasado.
--
-- ═══ ROLLBACK ══════════════════════════════════════════════════════════════════════════
-- drop view public.gv_ppp_camion_pasado;
