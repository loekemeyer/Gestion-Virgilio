-- ════════════════════════════════════════════════════════════════════
-- EDITOR DE LUGARES — permisos de escritura para el supervisor (2026-09-11)
--
-- ╔══════════════════════════════════════════════════════════════════╗
-- ║  ⛔ NO APLICAR TODAVÍA — va con el merge de la rama a `main`.     ║
-- ║  Sin esto el editor nuevo NO PUEDE GUARDAR: GV_Lugar y           ║
-- ║  GV_Lugar_Item nacieron con RLS y SÓLO policy de SELECT.         ║
-- ╚══════════════════════════════════════════════════════════════════╝
--
-- Mismo patrón que ya usan las tablas que reemplazan:
--   Planimetria       planim_read (anon+authenticated, SELECT) · planim_write (authenticated, ALL)
--   Capacidad_Sector  cap_read (public, SELECT)                · cap_write   (authenticated, ALL)
--
-- El operario lee con la anon key (ya andaba); el supervisor escribe logueado con
-- Google, que es lo que resuelve `facAuthWriteHeaders` en el front — igual que el
-- editor viejo de Planimetría. No se abre nada a `anon`.
-- ════════════════════════════════════════════════════════════════════

drop policy if exists gv_lugar_write      on public."GV_Lugar";
drop policy if exists gv_lugar_item_write on public."GV_Lugar_Item";

create policy gv_lugar_write on public."GV_Lugar"
  for all to authenticated using (true) with check (true);

create policy gv_lugar_item_write on public."GV_Lugar_Item"
  for all to authenticated using (true) with check (true);

-- Verificación:
--   select tablename, policyname, cmd, roles::text from pg_policies
--    where schemaname='public' and tablename like 'GV_Lugar%' order by 1, 3;
--   -- GV_Lugar       gv_lugar_sel       SELECT {anon,authenticated}
--   -- GV_Lugar       gv_lugar_write     ALL    {authenticated}
--   -- GV_Lugar_Item  gv_lugar_item_sel  SELECT {anon,authenticated}
--   -- GV_Lugar_Item  gv_lugar_item_write ALL   {authenticated}
--
-- Rollback:
--   drop policy gv_lugar_write on public."GV_Lugar";
--   drop policy gv_lugar_item_write on public."GV_Lugar_Item";
-- (El editor queda sin poder guardar, que es el estado de hoy. Las lecturas no se
--  tocan, así que ni el picking ni el MG se enteran.)
