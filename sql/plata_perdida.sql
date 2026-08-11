-- ============================================================
-- v9.37 — Módulo "💸 Plata perdida de facturar" (faltante por quiebre)
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- Mide la plata que se dejó de facturar por NO poder entregar por falta de stock:
--   plata_perdida = Entregas_Virgilio.cajas_falto × precio_unit × uxb  (a precio de VENTA)
--
-- El precio de venta vive en LK (products.list_price por unidad + uxb unidades por caja).
-- Virgilio no tiene FDW a LK → se snapshotea en la tabla precios_venta.
-- ⚠ precio 8888 en LK = placeholder (sin precio real) → el módulo NO lo valoriza y lo marca.
-- ============================================================

create table if not exists public.precios_venta (
  cod         text primary key,   -- código de artículo (products.cod de LK)
  precio_unit numeric,            -- list_price (por unidad)
  uxb         integer,            -- unidades por caja (products.uxb)
  descripcion text,
  actualizado timestamptz default now()
);
alter table public.precios_venta enable row level security;
drop policy if exists pv_sel on public.precios_venta;
create policy pv_sel on public.precios_venta for select to anon, authenticated using (true);
drop policy if exists pv_wr on public.precios_venta;
create policy pv_wr on public.precios_venta for all to authenticated using (true) with check (true);

-- --------------------------------------------------------------
-- SYNC precios_venta desde LK (proyecto kwkclwhmoygunqmlegrg).
-- Correr en LK y ejecutar el INSERT resultante en Virgilio (misma técnica que clientes_vendedor):
--   select 'insert into public.precios_venta (cod, precio_unit, uxb, descripcion) values ' ||
--     string_agg('(' || quote_literal(btrim(cod)) || ',' || coalesce(list_price::text,'null') || ',' ||
--                coalesce(uxb::text,'null') || ',' || quote_literal(coalesce(description,'')) || ')', ',') ||
--     ' on conflict (cod) do update set precio_unit=excluded.precio_unit, uxb=excluded.uxb,'
--     ' descripcion=excluded.descripcion, actualizado=now();'
--   from products where coalesce(list_price,0) > 0 and btrim(coalesce(cod,'')) <> '';
-- Carga inicial: 214 productos, 2026-08-11 (7 con precio placeholder 8888).
-- --------------------------------------------------------------
