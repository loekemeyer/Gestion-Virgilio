-- v29.16 (Luis, 09/10/2026): log del asistente de ayuda del operario (Edge Function gv-ayuda).
-- Sólo lo escribe y lee el service_role (la función). anon/authenticated: nada.
-- Rollback: drop table public."GV_Ayuda_Log";
create table if not exists public."GV_Ayuda_Log" (
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  usuario text not null,
  pregunta text not null,
  respuesta text,
  fuente text,
  error text,
  ms int
);
alter table public."GV_Ayuda_Log" enable row level security;
revoke all on public."GV_Ayuda_Log" from anon, authenticated;
create index if not exists gv_ayuda_log_usr_ts on public."GV_Ayuda_Log" (usuario, ts desc);
create index if not exists gv_ayuda_log_ts on public."GV_Ayuda_Log" (ts desc);
