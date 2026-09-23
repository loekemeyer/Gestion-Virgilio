-- v21.47 · LA TABLA CANÓNICA DE FERIADOS — `public."GV_Feriados"`
--
-- Thomas, 2026-09-23: *"que quede bien definido que es la canónica así cualquier
-- implementación que requiera ver feriados la podés encontrar a futuro y dejar de
-- duplicarla"*.
--
-- ⚠ ANTES DE ESTO LA LISTA ESTABA ESCRITA TRES VECES, a mano y con el mismo
-- contenido: `FERIADOS_AR` en `index.html`, `FERIADOS` en `monitor/tv.html` y el CTE
-- `feriados` de `gv_monitor_horas_operario_dia`. Medido el 23/09: las tres tenían las
-- mismas 16 fechas — pero las tres **terminaban el 2026-12-25**, así que desde el 1.º
-- de enero ninguna conocía un solo feriado.
--
-- ⚠⚠ `GV_Feriados` NO ES `GV_Dias_No_Habiles`, y no hay que mezclarlas:
--
--   | tabla                | qué dice                          | qué mueve                          |
--   |----------------------|-----------------------------------|------------------------------------|
--   | `GV_Feriados`        | feriado NACIONAL (no se trabaja)  | el conteo de horas de un cierre    |
--   |                      |                                   | que cruza la medianoche            |
--   | `GV_Dias_No_Habiles` | el dueño CIERRA el depósito       | los días hábiles de TODA la        |
--   |                      |                                   | operación (espera, tope de 10,     |
--   |                      |                                   | anticipación mínima de 4)          |
--   | `GV_Dias_Sin_Reparto`| se trabaja pero no sale el camión | la programación del reparto        |
--
-- ⚠ Los «días NO laborables» con fines turísticos (los puentes) van con
-- `tipo = 'no_laborable'` y NO cuentan como feriado: en el depósito SÍ se trabaja.
-- Quien pregunte "¿se trabaja?" filtra `tipo = 'feriado'`, que es lo que hace
-- `gv_es_feriado`.
--
-- Al agregar un año: es un `insert`, no un deploy. Fuente: Ley 27.399 + decretos,
-- argentina.gob.ar/jefatura. Los trasladables van con su fecha OBSERVADA y el
-- original en `trasladado_de`.

create table if not exists public."GV_Feriados" (
  fecha         date primary key,
  nombre        text not null,
  tipo          text not null default 'feriado'
                 check (tipo in ('feriado','no_laborable')),
  trasladado_de date,
  fuente        text default 'Ley 27.399 + decretos',
  creado_en     timestamptz not null default now()
);

comment on table public."GV_Feriados" is
  'CANÓNICA de feriados. Única fuente para saber si un día es feriado nacional. '
  'La leen el SQL (gv_es_feriado) y el front (index.html y monitor/tv.html, que la '
  'bajan al abrir y sólo usan su lista hardcodeada como fallback si el fetch falla). '
  'NO es GV_Dias_No_Habiles (el dueño cierra el depósito: mueve los días hábiles de '
  'toda la operación) ni GV_Dias_Sin_Reparto (se trabaja pero no sale el camión). '
  'tipo=no_laborable son los puentes turísticos: se trabaja, no cuentan como feriado.';

alter table public."GV_Feriados" enable row level security;

-- Son las fechas de los feriados del país: las lee el navegador del operario.
drop policy if exists "GV_Feriados lectura" on public."GV_Feriados";
create policy "GV_Feriados lectura" on public."GV_Feriados" for select to anon, authenticated using (true);

grant select on public."GV_Feriados" to anon, authenticated;
revoke insert, update, delete, truncate on public."GV_Feriados" from anon, authenticated;

-- ── 2026: las 16 que ya estaban en las tres listas ────────────────────────────
insert into public."GV_Feriados" (fecha, nombre, tipo, trasladado_de) values
  ('2026-01-01','Año Nuevo','feriado',null),
  ('2026-02-16','Carnaval','feriado',null),
  ('2026-02-17','Carnaval','feriado',null),
  ('2026-03-24','Día de la Memoria','feriado',null),
  ('2026-04-02','Malvinas','feriado',null),
  ('2026-04-03','Viernes Santo','feriado',null),
  ('2026-05-01','Día del Trabajador','feriado',null),
  ('2026-05-25','Revolución de Mayo','feriado',null),
  ('2026-06-15','Güemes','feriado',date '2026-06-17'),
  ('2026-06-20','Día de la Bandera','feriado',null),
  ('2026-07-09','Independencia','feriado',null),
  ('2026-08-17','San Martín','feriado',null),
  ('2026-10-12','Diversidad Cultural','feriado',null),
  ('2026-11-23','Soberanía Nacional','feriado',date '2026-11-20'),
  ('2026-12-08','Inmaculada Concepción','feriado',null),
  ('2026-12-25','Navidad','feriado',null),
  -- Los puentes de 2026: SE TRABAJA. Están para que nadie los vuelva a agregar
  -- como feriado "porque faltaban".
  ('2026-03-23','Puente turístico','no_laborable',null),
  ('2026-07-10','Puente turístico','no_laborable',null),
  ('2026-12-07','Puente turístico','no_laborable',null)
on conflict (fecha) do nothing;

-- ── 2027, que es lo que faltaba ───────────────────────────────────────────────
-- ⚠ Los puentes de 2027 los fija el PEN por decreto y al 23/09/2026 no están
-- publicados: por eso 2027 va sólo con los feriados de la ley. Cuando salga el
-- decreto se agregan con un insert.
insert into public."GV_Feriados" (fecha, nombre, tipo, trasladado_de) values
  ('2027-01-01','Año Nuevo','feriado',null),
  ('2027-02-08','Carnaval','feriado',null),
  ('2027-02-09','Carnaval','feriado',null),
  ('2027-03-24','Día de la Memoria','feriado',null),
  ('2027-03-26','Viernes Santo','feriado',null),
  ('2027-04-02','Malvinas','feriado',null),
  ('2027-05-01','Día del Trabajador','feriado',null),
  ('2027-05-25','Revolución de Mayo','feriado',null),
  ('2027-06-21','Güemes','feriado',date '2027-06-17'),
  ('2027-06-20','Día de la Bandera','feriado',null),
  ('2027-07-09','Independencia','feriado',null),
  ('2027-08-16','San Martín','feriado',date '2027-08-17'),
  ('2027-10-11','Diversidad Cultural','feriado',date '2027-10-12'),
  ('2027-11-20','Soberanía Nacional','feriado',null),   -- cae SÁBADO: no se traslada
  ('2027-12-08','Inmaculada Concepción','feriado',null),
  ('2027-12-25','Navidad','feriado',null)
on conflict (fecha) do nothing;

-- ── La función que contesta la pregunta, para que nadie vuelva a escribir la lista ──
create or replace function public.gv_es_feriado(p_fecha date)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (select 1 from public."GV_Feriados" f
                  where f.fecha = p_fecha and f.tipo = 'feriado');
$$;

comment on function public.gv_es_feriado(date) is
  '¿Ese día es feriado nacional? Lee la CANÓNICA public."GV_Feriados". Los puentes '
  '(tipo=no_laborable) dan false: se trabaja. No confundir con gv_es_dia_habil (que '
  'mira GV_Dias_No_Habiles) ni con gv_es_dia_con_reparto.';

grant execute on function public.gv_es_feriado(date) to anon, authenticated, service_role;
