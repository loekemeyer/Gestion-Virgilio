-- =============================================================================
-- lk_pedidos_match.sql — Espejo local del string identificador de pedido web
-- de LK, con la SUCURSAL DE ENTREGA (2026-08-28)
-- =============================================================================
-- Virgilio no tenía la sucursal de entrega de los pedidos; LK sí
-- (orders.sheets_payload.sucursal_entrega). LK EMPUJA acá cada 15 min por su
-- FDW existente (server virgilio_db, rol lk_ppp_reader — el mismo del espejo
-- PPP, ahora con permiso de escritura SOLO sobre esta tabla). Virgilio lee su
-- tabla LOCAL: cero FDW en el camino caliente.
--
--   match_string = cod_cliente | fecha (ART, YYYY-MM-DD) | items
--   items        = cod_art x cajas, ordenado por cod_art, cajas sumadas por
--                  código repetido (ej: "026x1,027x10,315x2")
--
-- `ambiguo` = ese mismo string aparece ese día con MÁS DE UNA sucursal
-- distinta (mismo cliente, mismo día, mismo pedido exacto a dos sucursales:
-- la única excepción que el string no resuelve — histórico: 17 pedidos de
-- 977). `orden_en_dia` desempata por hora de alta. `order_id` es el
-- order_number del portal web (el mismo que viaja al Sheet).
--
-- Lado LK: vista fuente + sync + cron en sql/pedidos_match_virgilio.sql del
-- repo pagina-LK.
-- =============================================================================

create table if not exists public.lk_pedidos_match (
  order_id         bigint primary key,      -- orders.id en LK (= order_number del Sheet)
  cod_cliente      text not null,
  status           text,
  fecha_pedido     date not null,           -- fecha del pedido en hora argentina
  hora_pedido      text,                    -- HH24:MI:SS hora argentina
  created_at       timestamptz,
  sucursal_entrega text,                    -- el dato que Virgilio no tenía
  items_string     text,
  match_string     text,
  ambiguo          boolean default false,
  orden_en_dia     bigint,
  synced_at        timestamptz default now()
);

create index if not exists lk_pedidos_match_string_idx  on public.lk_pedidos_match (match_string);
create index if not exists lk_pedidos_match_fecha_idx   on public.lk_pedidos_match (fecha_pedido);
create index if not exists lk_pedidos_match_cliente_idx on public.lk_pedidos_match (cod_cliente, fecha_pedido);

alter table public.lk_pedidos_match enable row level security;

-- La app de Virgilio (anon) solo lee
drop policy if exists lk_pedidos_match_select on public.lk_pedidos_match;
create policy lk_pedidos_match_select on public.lk_pedidos_match
  for select to anon, authenticated using (true);

-- LK escribe vía FDW con lk_ppp_reader (única tabla donde ese rol escribe)
drop policy if exists lk_pedidos_match_writer on public.lk_pedidos_match;
create policy lk_pedidos_match_writer on public.lk_pedidos_match
  for all to lk_ppp_reader using (true) with check (true);

grant usage on schema public to lk_ppp_reader;
grant select, insert, update, delete on public.lk_pedidos_match to lk_ppp_reader;
