-- GV_Reingreso_Excluido — codigos SIN cartel "Sin stock / hasta dd/mm" y SIN pedido partido
-- (Luis, 2026-09-23). APLICADO en hrxfctzncixxqmpfhskv el 23/09.
--
-- El cartel de las paginas LK y Chef y el corte del pedido (pedido_diferido en LK:
-- marcar_pedido_diferido / marcar_diferidos_chef) salen de la MISMA lista:
-- gv_reingresos_feed -> v_lk_reingresos / v_ch_reingresos -> reingreso_cache(_chef) en LK
-- (cron 39, sync_reingresos_virgilio). Un codigo que no sale del feed no muestra cartel
-- ni parte pedidos, en las dos paginas, sin tocar el front.
-- Agregar / sacar un codigo = insert / delete aca. Tarda hasta 30 min (o correr el sync en LK).
-- Centinela: GV_Reglas_Centinela 142 (patron GV_Reingreso_Excluido).
create table if not exists public."GV_Reingreso_Excluido" (
  cod        text primary key,          -- gv_cod_stock(): sin ceros ni L ni sufijo de empresa
  motivo     text,
  pedido_por text,
  creado_en  timestamptz not null default now()
);
alter table public."GV_Reingreso_Excluido" enable row level security;
revoke all on public."GV_Reingreso_Excluido" from anon, authenticated;

insert into public."GV_Reingreso_Excluido" (cod, motivo, pedido_por)
select gv_cod_stock(c), 'sin cartel de reingreso ni pedido partido', 'Luis (23/09)'
from unnest(array['584E','590E','590ES','890E']) c
on conflict (cod) do nothing;

-- En gv_reingresos_feed(p_emp) el select final quedo:
--   select cod, reingreso_est, (disponible <= 0 or pedidos >= disponible) as sin_stock
--   from _rf_disp
--   where not exists (select 1 from public."GV_Reingreso_Excluido" x where x.cod = _rf_disp.cod);
-- (definicion completa: sql/gv_reingresos_feed_lk_chef.sql + este where)
