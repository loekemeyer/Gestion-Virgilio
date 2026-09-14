-- gv_uxb_824_20260914_pre_cambio.sql — APLICADO 2026-09-14 (v16.91).
--
-- Pedido de Marianela: el bulto de Chef del 824 (COLADOR 8 CM) es de **12 unidades**, no de 36.
-- Sólo la fila CH; la de LK queda como está (36).
--
-- ⚠ Pisa una curación del dueño: la fila CH la había puesto Thomas a mano el 12/09 con origen
--    "Thomas 12/09/2026 (corrige el listado)". Se le avisó a Marianela antes de escribir, junto con
--    los 4 hermanos que dicen 36 (824 LK, 110 "Colador N° 8 Loke", 026 "COLADOR N°8", 831 pintado N8)
--    y con Articulos_Cajas, que también dice 36. Confirmó 12 igual.
--
-- ── ESTADO ANTES ─────────────────────────────────────────────────────────────────────────
--   GV_UxB  CH 824  uxb 36  "COLADOR 8 CM"  origen 'Thomas 12/09/2026 (corrige el listado)'  curado=true
--   GV_UxB  LK 824  uxb 36  "Colador  8 Cm" origen 'absorbido del fallback 12/09 (v16.28)…'  curado=false
--   Backup completo de las dos filas: zz_backups."GV_Backup_UxB_824_20260914" (RLS on, sin escritura para anon).
--
-- ── LO QUE SE CORRIÓ ─────────────────────────────────────────────────────────────────────
update public."GV_UxB"
   set uxb = 12,
       origen = 'Marianela 14/09/2026 (corrige a Thomas 12/09: el bulto de Chef es de 12)',
       curado = true,
       actualizado = now()
 where cod = '824' and empresa = 'CH';
--
-- ── MEDICIÓN (después) ───────────────────────────────────────────────────────────────────
--   GV_UxB CH 12 · GV_UxB LK 36 · gv_uxb_emp chef 12 · gv_uxb_emp lk 36
--   vista_uxb_articulo → 36  ← NO cambió, y es a propósito: toma max() entre las dos empresas
--                              del mismo código base, así que con LK en 36 el Excel de ISIS y la OC
--                              siguen viendo 36. Marianela eligió tocar sólo CH sabiendo esto.
--   vista_facturacion_neto_items, código 824: 36 líneas · 213 cajas entregadas
--       antes  uxb 36 → $8.965.915,20
--       ahora  uxb 12 → $2.988.638,40   (−$5.977.276,80; las 36 líneas se valorizan como Chef)
--
-- ── ROLLBACK ─────────────────────────────────────────────────────────────────────────────
-- update public."GV_UxB" g
--    set uxb = b.uxb, origen = b.origen, curado = b.curado, actualizado = b.actualizado
--   from zz_backups."GV_Backup_UxB_824_20260914" b
--  where g.cod = b.cod and g.empresa = b.empresa;
--
-- ── SI ADEMÁS SE QUIERE ALINEAR EL RESTO (hoy NO se hizo) ─────────────────────────────────
-- update public."GV_UxB" set uxb = 12, origen = '…', curado = true, actualizado = now()
--  where cod = '824' and empresa = 'LK';                      -- deja vista_uxb_articulo en 12
-- update public."Articulos_Cajas" set "Uni_x_Caja" = 12 where "Cod_Art" = '824';
-- Y el catálogo de la página de Chef (products.uxb, proyecto nkhzocgdpwtgrmwleihr): no se toca
-- desde acá, el MCP no tiene permiso sobre ese proyecto.

-- ─────────────────────────────────────────────────────────────────────────────────────────
-- SEGUNDA PASADA — v16.95, mismo día. Marianela contó el bulto: son 12. Se alinea el resto.
-- Backup del Articulos_Cajas: zz_backups."GV_Backup_ArticulosCajas_824_20260914" (1 fila, uxc 36).
update public."GV_UxB"
   set uxb = 12, origen = 'Marianela 14/09/2026 (conteo fisico del bulto)', curado = true, actualizado = now()
 where cod = '824' and empresa = 'LK';
update public."Articulos_Cajas" set "Uni_x_Caja" = 12 where "Cod_Art" = '824';
--
-- Después: GV_UxB LK 12 · GV_UxB CH 12 · gv_uxb_emp lk/chef 12 · vista_uxb_articulo 12 ·
--          Articulos_Cajas 12. El Excel de ISIS y la OC ya usan 12.
--          vista_facturacion_neto_items no se movió ($2.988.638,40): ya leía la fila CH.
--
-- Rollback de esta segunda pasada:
-- update public."GV_UxB" set uxb = 36, origen = 'absorbido del fallback 12/09 (v16.28) - venia de OC_Maximos',
--        curado = false where cod = '824' and empresa = 'LK';
-- update public."Articulos_Cajas" a set "Uni_x_Caja" = b."Uni_x_Caja"
--   from zz_backups."GV_Backup_ArticulosCajas_824_20260914" b where a."Cod_Art" = b."Cod_Art";
--
-- ⚠ PENDIENTE, sin tocar: gv_uxb_desalineado pasó de 4 filas a 7 — OC_Maximos, Importados y maestro
--    siguen con 36 para el 824. No son fuente de UxB para Gestión, pero son las que mira la compra.
