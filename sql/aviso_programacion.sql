-- ============================================================
-- v9.31 — Módulo "📲 Avisar programación"
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- Cuando se programa un pedido, el módulo (panel supervisor) lista los pedidos
-- programados (con fecha de salida) ordenados por esa fecha, y permite avisar por
-- WhatsApp al CLIENTE y al VENDEDOR que corresponde (salvo vend 7 = fábrica = nosotros).
--
-- 4 tablas nuevas:
--   clientes_vendedor      -> mapeo cod_cliente -> vend (snapshot de LK.customers.vend)
--   whatsapp_clientes      -> cod_cliente -> telefono
--   whatsapp_vendedores    -> vend -> telefono (+ nombre)
--   envio_programacion_log -> log de clicks (quién, día/hora, tipo cliente/vendedor)
--
-- RLS: todas SELECT para anon+authenticated (el app lee con la anon key). Las de
-- teléfonos se escriben solo con authenticated (el app solo LEE). El log acepta
-- INSERT de anon (append-only: registra cada aviso). clientes_vendedor se escribe
-- solo con authenticated (lo sincroniza el admin desde LK).
-- ============================================================

-- (a) mapeo cliente -> vendedor (snapshot de LK.customers; vend 7 = fábrica)
create table if not exists public.clientes_vendedor (
  cod_cliente text primary key,
  vend        text,
  actualizado timestamptz default now()
);
alter table public.clientes_vendedor enable row level security;
drop policy if exists cv_sel on public.clientes_vendedor;
create policy cv_sel on public.clientes_vendedor for select to anon, authenticated using (true);
drop policy if exists cv_wr on public.clientes_vendedor;
create policy cv_wr on public.clientes_vendedor for all to authenticated using (true) with check (true);

-- (b) WhatsApp de clientes
create table if not exists public.whatsapp_clientes (
  cod_cliente text primary key,
  telefono    text,
  actualizado timestamptz default now()
);
alter table public.whatsapp_clientes enable row level security;
drop policy if exists wc_sel on public.whatsapp_clientes;
create policy wc_sel on public.whatsapp_clientes for select to anon, authenticated using (true);
drop policy if exists wc_wr on public.whatsapp_clientes;
create policy wc_wr on public.whatsapp_clientes for all to authenticated using (true) with check (true);

-- (c) WhatsApp de vendedores
create table if not exists public.whatsapp_vendedores (
  vend        text primary key,
  telefono    text,
  nombre      text,
  actualizado timestamptz default now()
);
alter table public.whatsapp_vendedores enable row level security;
drop policy if exists wv_sel on public.whatsapp_vendedores;
create policy wv_sel on public.whatsapp_vendedores for select to anon, authenticated using (true);
drop policy if exists wv_wr on public.whatsapp_vendedores;
create policy wv_wr on public.whatsapp_vendedores for all to authenticated using (true) with check (true);

-- (d) log de clicks (día/hora + quién)
create table if not exists public.envio_programacion_log (
  id          bigint generated always as identity primary key,
  np          text,
  cod_cliente text,
  vend        text,
  tipo        text,          -- 'cliente' | 'vendedor'
  quien       text,
  ts          timestamptz default now()
);
alter table public.envio_programacion_log enable row level security;
drop policy if exists epl_sel on public.envio_programacion_log;
create policy epl_sel on public.envio_programacion_log for select to anon, authenticated using (true);
drop policy if exists epl_ins on public.envio_programacion_log;
create policy epl_ins on public.envio_programacion_log for insert to anon, authenticated with check (true);
create index if not exists epl_np_idx on public.envio_programacion_log (np);

-- --------------------------------------------------------------
-- SYNC clientes_vendedor desde LK (proyecto kwkclwhmoygunqmlegrg).
-- NO hay postgres_fdw entre Virgilio y LK. El snapshot se refresca corriendo en LK:
--   select 'insert into public.clientes_vendedor (cod_cliente, vend) values ' ||
--     string_agg('(' || quote_literal(cod_cliente::text) || ',' || quote_literal(coalesce(vend,'')) || ')', ',') ||
--     ' on conflict (cod_cliente) do update set vend=excluded.vend, actualizado=now();'
--   from customers where cod_cliente is not null;
-- y ejecutando el INSERT resultante en Virgilio. (Carga inicial: 1245 clientes, 2026-08-11.)
-- --------------------------------------------------------------
