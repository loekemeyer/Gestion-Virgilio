-- v28.02 (Luis, 07/10): ENTREGA PROY. + log 📓 por línea de OC. Aplicado por la sesión el 07/10.
-- Columnas nuevas (nullable, gv_) en Ordenes_Compra + tabla append-only GV_OC_Log (RLS sin policy:
-- sólo por RPC de supervisor). No toca impresos, WhatsApp ni Excel.
alter table public."Ordenes_Compra" add column if not exists gv_entrega_proy integer,
  add column if not exists gv_entrega_proy_por text, add column if not exists gv_entrega_proy_at timestamptz;
create table if not exists public."GV_OC_Log" (
  id bigserial primary key, oc_id bigint not null references public."Ordenes_Compra"(id),
  proveedor text, codigo text, oc_fecha date, autor text,
  texto text not null check (length(btrim(texto))>0), created_at timestamptz not null default now());
alter table public."GV_OC_Log" enable row level security;
revoke all on public."GV_OC_Log" from anon, authenticated;
create index if not exists gv_oc_log_oc_idx on public."GV_OC_Log"(oc_id);
-- RPC (security definer, es_supervisor_virgilio(), execute sólo authenticated):
--   gv_oc_entrega_proy_guardar(p_oc_id bigint, p_cant integer)  -> jsonb {ok, por, at}
--   gv_oc_log_agregar(p_oc_id bigint, p_texto text, p_autor text default null) -> GV_OC_Log
--   gv_oc_log_leer(p_oc_id bigint) -> setof GV_OC_Log
--   gv_oc_log_conteos(p_ids bigint[]) -> (oc_id, n, ultimo)
-- Definiciones vivas: select pg_get_functiondef('public.gv_oc_log_agregar(bigint,text,text)'::regprocedure);
-- Rollback: las columnas quedan (nullable); la tabla de log no se borra (es auditoría).

-- v28.27 (Luis, 07/10): HISTORIAL de Entrega proy. — cada guardado queda, aunque después se borre.
create table if not exists public."GV_OC_Entrega_Proy_Hist" (
  id bigserial primary key, oc_id bigint not null references public."Ordenes_Compra"(id),
  proveedor text, codigo text, oc_fecha date, valor integer, anterior integer,
  por text, created_at timestamptz not null default now());
alter table public."GV_OC_Entrega_Proy_Hist" enable row level security;
revoke all on public."GV_OC_Entrega_Proy_Hist" from anon, authenticated;
-- gv_oc_entrega_proy_guardar ahora inserta (valor, anterior, por) en el historial (marcador v28.27-hist, centinela);
-- lectura: gv_oc_entrega_proy_hist(oc_id) (supervisor). Probado en transacción abortada: 50 y vacío → 2 filas.
-- select * from public."GV_OC_Entrega_Proy_Hist" order by created_at desc;
