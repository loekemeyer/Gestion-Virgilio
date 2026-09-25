-- v22.48 (Luis, 25/09): botón «Recibido» en Pendientes de Recepción.
-- Guarda quién recibió y cuándo. Aplicado el 25/09.
alter table public."Control_Modo_OP" add column if not exists gv_recibido_por text,
                                     add column if not exists gv_recibido_at timestamptz;
-- rollback: alter table public."Control_Modo_OP" drop column gv_recibido_por, drop column gv_recibido_at;
