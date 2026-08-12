-- ============================================================
-- v10.05 (2026-08-12) — volumen de la MASTER caja de importados (m³) editable.
-- Se usa en Pedidos Importación: m³ del pedido = master cajas a pedir (enteras) × m³/master.
-- ============================================================
create table if not exists public."Importados_Volumen" (
  cod text primary key,
  largo_cm numeric,
  ancho_cm numeric,
  alto_cm numeric,
  m3_master numeric,
  actualizado timestamptz not null default now()
);
alter table public."Importados_Volumen" enable row level security;
drop policy if exists impvol_sel on public."Importados_Volumen";
drop policy if exists impvol_ins on public."Importados_Volumen";
drop policy if exists impvol_upd on public."Importados_Volumen";
create policy impvol_sel on public."Importados_Volumen" for select to anon using (true);
create policy impvol_ins on public."Importados_Volumen" for insert to anon with check (true);
create policy impvol_upd on public."Importados_Volumen" for update to anon using (true) with check (true);
