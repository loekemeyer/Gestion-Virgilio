-- ============================================================
-- v9.85 (2026-08-12) — tabla de notas editables para Faltantes x día
-- (Día de resolución + Motivo falta) para el reporte al gerente.
-- Restore/recrear: ejecutar este archivo.
-- ============================================================
create table if not exists public."Faltantes_Notas" (
  cod text primary key,
  dia_resolucion text,
  motivo text,
  actualizado timestamptz not null default now()
);
alter table public."Faltantes_Notas" enable row level security;
drop policy if exists faltnotas_sel on public."Faltantes_Notas";
drop policy if exists faltnotas_ins on public."Faltantes_Notas";
drop policy if exists faltnotas_upd on public."Faltantes_Notas";
create policy faltnotas_sel on public."Faltantes_Notas" for select to anon using (true);
create policy faltnotas_ins on public."Faltantes_Notas" for insert to anon with check (true);
create policy faltnotas_upd on public."Faltantes_Notas" for update to anon using (true) with check (true);
