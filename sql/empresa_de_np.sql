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
-- ⚠ NO aplicar sin revisar contra la base (nombres/valores) — borrador.
-- ⚠ ESTADO REAL (verificado 2026-08-28): **NO APLICADO**. Ni `empresa_de_np()` ni
--    `Codigos_Duales` existen en la base. La línea que decía "Aplicado como migración
--    empresa_de_np_codigos_duales" era falsa (se escribió junto al borrador, sin correrlo).
-- Alcance medido de la duplicación que este archivo viene a resolver: la regla LK/CH está
-- re-escrita en **9 lugares** — 5 en el front (index.html:7360 `empresaDeNp`, :7973
-- `PICK_UBIC_DUAL`, :7984 `pkNpEsLoeke`, :10188 `NOMBRE_POR_EMPRESA`, :10200
-- `EMPRESA_SPLIT_CODS`) y 4 en la base (función `cob_empresa_np`, vistas
-- `vista_faltante_demanda`, `vista_faltante_real`, `vista_nc_loeke_chef`).

create or replace function public.empresa_de_np(p_np text)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when regexp_replace(trim(coalesce(p_np,'')), '\.0+$', '') ~ '^9' then 'LK'
    when regexp_replace(trim(coalesce(p_np,'')), '\.0+$', '') ~ '^4' then 'CH'
    else null
  end;
$$;
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
