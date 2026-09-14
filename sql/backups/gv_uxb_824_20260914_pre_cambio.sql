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

-- ─────────────────────────────────────────────────────────────────────────────────────────
-- TERCERA PASADA — v17.00, mismo día. Marianela: "donde esté el art 824 debe figurar por 12 uni".
-- Barrido de TODA la base buscando columnas de unidades por caja/bulto (information_schema:
-- uxb | uxc | uni_x_caja | *x_caja | *x_bulto | *por_bulto) y filtrando el 824 por gv_cod_stock().
-- Backups: zz_backups."GV_Backup_824_{OCMaximos,Importados,Maestro,Despiece}_20260914" (1 fila c/u).
update public."OC_Maximos" set uni_x_caja = 12 where public.gv_cod_stock(cod) = public.gv_cod_stock('824');
update public."Importados"  set uni_x_caja = 12 where public.gv_cod_stock(cod_art) = public.gv_cod_stock('824');
update public."Articulos Virgilio X Tallerista" set "Uni_x_Caja" = 12
 where public.gv_cod_stock("Cod_Art"::text) = public.gv_cod_stock('824');
update public."Despiece x Articulo" set "Uni_x_Caja" = 12, "Uni x Cja" = '12'
 where id = '4e1db1cf-fb67-4b8e-8052-bd8265dffe89';   -- estaba en NULL, no en 36
--
-- Después: las 11 lecturas del 824 dan 12 (GV_UxB CH y LK, gv_uxb_emp chef y lk,
-- vista_uxb_articulo, Articulos_Cajas, OC_Maximos, Importados, maestro, Despiece, Ordenes_Compra).
-- gv_uxb_desalineado volvió de 7 filas a 4, y ninguna es del 824 (las 4 son los 63xE, de antes).
--
-- ⚠ NO se tocó Ordenes_Compra: su única fila del 824 YA decía 12.0 — o sea que la OC que se
--    mandó al proveedor estaba bien y la que estaba mal era la ficha. Es la confirmación
--    independiente de que 12 es el número.
-- ⚠ Queda sin revisar OC_Maximos.max_cajas: el máximo está en CAJAS, así que el número no cambia,
--    pero las UNIDADES que muestra la pantalla de compra ahora dan un tercio.
--
-- Rollback de esta tercera pasada (cada backup tiene su fila original):
-- update public."OC_Maximos" o set uni_x_caja = b.uni_x_caja
--   from zz_backups."GV_Backup_824_OCMaximos_20260914" b where o.cod = b.cod;
-- update public."Importados" i set uni_x_caja = b.uni_x_caja
--   from zz_backups."GV_Backup_824_Importados_20260914" b where i.cod_art = b.cod_art;
-- update public."Articulos Virgilio X Tallerista" t set "Uni_x_Caja" = b."Uni_x_Caja"
--   from zz_backups."GV_Backup_824_Maestro_20260914" b where t."Cod_Art" = b."Cod_Art";
-- update public."Despiece x Articulo" d set "Uni_x_Caja" = b."Uni_x_Caja", "Uni x Cja" = b."Uni x Cja"
--   from zz_backups."GV_Backup_824_Despiece_20260914" b where d.id = b.id;
