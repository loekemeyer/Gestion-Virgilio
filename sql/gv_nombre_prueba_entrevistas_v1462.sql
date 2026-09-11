-- v14.62 — Legajo 600 = ENTREVISTAS / PRUEBA con nombre.  ✅ APLICADO 2026-09-10
--
-- El 600 es un legajo COMPARTIDO: cada candidato en entrevista entra con 600,
-- registra su nombre y hace la prueba REAL (persiste eventos y descuenta stock,
-- igual que un operario; NO es como el 0/1 que no persisten). Para saber QUIÉN
-- hizo cada prueba, cada evento del 600 se sella con el nombre del candidato en
-- la columna gv_nombre_prueba.
--
-- ── Por qué esto SÍ se puede sobre una tabla compartida ─────────────────────────
-- Sobre la tabla COMPARTIDA sólo se AGREGA: columna nullable, sin default, sin
-- backfill, con prefijo gv_. Mismo patrón exacto y verificado que gv_app (v14.51):
--   · grants INSERT a nivel TABLA (anon/authenticated) -> la columna queda cubierta sola.
--   · policy insert_all con with_check = true -> no enumera columnas, acepta el payload nuevo.
--   · sin trigger (prohibido sobre tabla compartida), sin tocar filas existentes.
--
-- ROLLBACK:
--   alter table public."Registros_Produccion_Virgilio" drop column gv_nombre_prueba;
--   drop function if exists public.es_legajo_entrevista(text);
--   (y sacar gv_nombre_prueba de los dos payloads de index.html)

alter table public."Registros_Produccion_Virgilio"
  add column if not exists gv_nombre_prueba text;

comment on column public."Registros_Produccion_Virgilio".gv_nombre_prueba is
  'v14.62 — nombre del candidato de entrevista cuando legajo = 600 (legajo compartido de prueba). NULL en todo evento de un operario real. Nullable, sin default y sin backfill: la tabla es compartida y sobre una tabla compartida sólo se AGREGA.';

-- Fuente de verdad de "cuál es el legajo de entrevista/prueba con nombre".
-- Hoy es el 600 (el dueño: "que todos los de entrevistas usen el 600").
-- Inmutable + parallel safe + sin search_path para no matar el inlining, igual que es_legajo_test.
create or replace function public.es_legajo_entrevista(p_legajo text)
returns boolean
language sql
immutable
parallel safe
return coalesce(btrim(p_legajo), '') = '600';

comment on function public.es_legajo_entrevista(text) is
  'v14.62 — TRUE si el legajo es el de ENTREVISTAS/PRUEBA con nombre (600). El 600 SÍ persiste y descuenta stock (prueba real); se distingue por gv_nombre_prueba. No confundir con es_legajo_test (0/1), que NO persisten.';

grant execute on function public.es_legajo_entrevista(text) to anon, authenticated, service_role;
