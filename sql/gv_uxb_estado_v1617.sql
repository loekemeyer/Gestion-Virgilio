-- ============================================================================
-- v16.17 (2026-09-12) — la columna Estado de los Excel, que la v16.16 se comió
--
-- Thomas: "revisaste los 2 excels que te pase?". Al revisarlos en serio aparecieron
-- dos cosas.
--
-- 1) LAS HOJAS ESTÁN COMPLETAS. Se comparó hoja contra hoja:
--      Chef  "Lista plana"   100  vs  "Por familia"   100  -> idénticas
--      Loeke "Listado plano" 199  vs  "Por familia"   204  -> los 5 de más son
--        subtítulos de subfamilia (Madera, Silicona, Nylon Premium, Inoxidable,
--        Nylon), no códigos.
--    Ningún código quedó afuera de la carga y ningún UxB difiere entre las hojas.
--
-- 2) SE HABÍA PERDIDO LA COLUMNA `Estado`. La v16.16 cargó código + UxB y descartó
--    esa columna. Traía 85 filas con dato:
--      Nuevo 66 · Nuevo · Reingreso est. 29/09  7 · Liquidación 7 ·
--      Sin stock 4 · Nuevo · Liquidación 1
--    Se agregó `GV_UxB.estado` y se cargó. Verificado: 85, el número exacto.
--
-- Los 7 con "Reingreso est. 29/09" (952E, 955E, 953E, 951E, 957E, 958E, 934E) YA
-- tenían `Importados.reingreso_est = 2026-09-29`. El Excel y la base coinciden, no
-- hubo nada que corregir; 5 de los 7 están además en stock 0, que es justo cuando
-- el portal de LK muestra el reingreso.
-- ============================================================================

alter table public."GV_UxB" add column if not exists estado text;
comment on column public."GV_UxB".estado is
  'Estado tal cual venia en la columna Estado del listado mayorista del 12/09: Nuevo, Liquidacion, Sin stock, y el reingreso estimado cuando lo trae.';
-- (el update de carga está en sql/data/gv_uxb_carga_20260912.sql)
