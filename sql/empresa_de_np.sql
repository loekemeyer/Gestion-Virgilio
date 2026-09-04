-- idea normalizar-datos (TOP-4) — la regla de empresa (LK/CH) en UN solo lugar.
-- Hoy la regla vive re-tipeada en ≥5 lados: empresaDeNp + EMPRESA_SPLIT_CODS +
-- NOMBRE_POR_EMPRESA en index.html (7360, 10202, 10185) y de nuevo en SQL
-- (sql/nc_loeke_chef.sql, vista_faltante_demanda). Acá se centraliza:
--   * empresa_de_np(np): 'LK' si el NP es 9xxxx (Loekemeyer), 'CH' si 4xxxx (Chef).
--     Verificado 2026-08-01 (idea 9020): las 947 NPs empezaban con 4 o 9 sin excepción.
--   * Codigos_Duales: los códigos que existen en las dos empresas (hoy hardcodeados
--     como EMPRESA_SPLIT_CODS = 437E/438E/439E/809E) + el nombre distinto por empresa
--     (NOMBRE_POR_EMPRESA: 809E = Corta Pizza Familiar en LK / Corta Queso en CH).
-- Después de aplicar: las vistas SQL usan empresa_de_np()/Codigos_Duales, y el front
-- puede fetchear Codigos_Duales al arrancar (las const quedan de semilla offline).
-- ✅ APLICADO 2026-08-28 (migración `empresa_de_np_codigos_duales`).
-- empresa_de_np() y Codigos_Duales existen en la base desde esa fecha.
-- Alcance medido de la duplicación que este archivo viene a resolver: la regla LK/CH está
-- re-escrita en **9 lugares** — 5 en el front (index.html:7360 `empresaDeNp`, :7973
-- `PICK_UBIC_DUAL`, :7984 `pkNpEsLoeke`, :10188 `NOMBRE_POR_EMPRESA`, :10200
-- `EMPRESA_SPLIT_CODS`) y 4 en la base (función `cob_empresa_np`, vistas
-- `vista_faltante_demanda`, `vista_faltante_real`, `vista_nc_loeke_chef`).

-- ────────────────────────────────────────────────────────────────────────────
-- ⚠ REVISADA 2026-09-04 — la regla vieja era CIEGA a las NP que genera Gestión.
--
-- Sacaba los dígitos y miraba si pasaban de 90.000. Eso sirve para las NP de ISIS
-- (9xxxx Loekemeyer / 4xxxx Chef), pero las NP web son **"LK 1343" / "CH 7"**:
-- 1343 no llega a 90.000, así que `empresa_de_np('LK 1343')` devolvía **'CH'**.
--
-- No era teórico. La usan `isis_encolar_facturado` (la empresa con la que el pedido
-- sale al ERP), `isis_pedido_json` y `trg_normalizar_empresa_stock`. La primera NP
-- web que se facturara se habría exportado a ISIS como Chef, fuera cual fuera.
--
-- El arreglo es ADITIVO: si la NP arranca con el prefijo de empresa, ese prefijo
-- manda; para todo lo demás queda exactamente la regla de antes. Verificado sobre
-- `PPP_Programacion_Diaria`: **0 NP cambian de empresa**. Ningún índice depende de
-- la función (chequeado), así que el `create or replace` es seguro.
-- ────────────────────────────────────────────────────────────────────────────
-- (El archivo traía todavía la primera versión, por prefijo `^9`/`^4`; la base venía
--  usando desde hace tiempo la variante por valor numérico. Se sincroniza acá.)
create or replace function public.empresa_de_np(p_np text)
returns text
language sql
immutable
as $function$
  select case
    -- NP de Gestión Virgilio: "LK 1343" / "CH 7". El prefijo ES la empresa.
    when upper(trim(coalesce(p_np,''))) ~ '^(LK|CH)[ -]' then upper(left(trim(p_np), 2))
    -- NP de ISIS: se decide por el número (9xxxx Loekemeyer / 4xxxx Chef).
    when regexp_replace(coalesce(p_np,''), '\D', '', 'g') = '' then null
    when (regexp_replace(p_np, '\D', '', 'g'))::bigint > 90000 then 'LK'
    else 'CH'
  end;
$function$;

-- Control:
--   select public.empresa_de_np('LK 1343'), public.empresa_de_np('CH 7'),
--          public.empresa_de_np('98213'),   public.empresa_de_np('44361');
--   -- → LK · CH · LK · CH
grant execute on function public.empresa_de_np(text) to anon, authenticated;

create table if not exists public."Codigos_Duales" (
  cod        text primary key,          -- código base sin sufijo (ej. '438E')
  nombre_lk  text,                      -- nombre del producto en Loekemeyer (null = mismo)
  nombre_ch  text,                      -- nombre del producto en Chef (null = mismo)
  actualizado_en timestamptz default now()
);
alter table public."Codigos_Duales" enable row level security;
drop policy if exists "codigos_duales_select" on public."Codigos_Duales";
create policy "codigos_duales_select" on public."Codigos_Duales" for select using (true);
revoke all on public."Codigos_Duales" from anon, authenticated;
grant select on public."Codigos_Duales" to anon, authenticated;

insert into public."Codigos_Duales" (cod, nombre_lk, nombre_ch) values
  ('437E', null, null),
  ('438E', null, null),
  ('439E', null, null),
  ('809E', 'Corta Pizza Familiar', 'Corta Queso')
on conflict (cod) do nothing;
