-- ============================================================
-- Articulos_Discontinuados — RLS para que "Completar datos producto" marque discontinuo
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- v9.53 (dueño) — el botón "🚫 Discontinuo" del módulo "Completar datos producto"
-- hace un upsert POST con la anon key. La tabla solo tenía policy de SELECT para anon
-- → el INSERT daba HTTP 401 ("No se pudo marcar"). Se agregan INSERT + UPDATE
-- (with check true) para anon/authenticated, igual patrón que las demás tablas
-- operativas que la app escribe con la key pública.
-- ============================================================

create policy disc_anon_insert on public."Articulos_Discontinuados"
  for insert to anon, authenticated with check (true);

create policy disc_anon_update on public."Articulos_Discontinuados"
  for update to anon, authenticated using (true) with check (true);
