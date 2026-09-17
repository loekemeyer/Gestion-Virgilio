-- =====================================================================
--  2026-09-17 (Marianela) — 838E "Rallador Cilíndrico Mini" ES DE CHEF,
--  no de Loekemeyer (corrección de DATOS, no de código). Problema 379.
--
--  ── EVIDENCIA (por qué es Chef, medido) ─────────────────────────────
--   • isis_ch.documento_items: 838E facturado 6 veces · isis_lk: 0.
--   • OC_Maximos.838E: descripcion "Rallador Cilindrico Mini", linea = CH,
--     uni_x_caja = 12 (coincide con Marianela).
--  Sin embargo la góndola y el caché lo tenían como LK:
--   • GV_Lugar sector Ñ55 = LK  (el sector sólo contiene 838E)
--   • GV_Articulo_Empresa_Cache.838E = LK (fuente 'gondola')
--   • gv_empresa_de_articulo('838E') → LK  (lee el caché)
--  Como el caché deriva de la góndola, el sector mal marcado LK envenenaba
--  toda la cadena: no aparecía en el stock/compras de Chef y la reposición
--  iría a la góndola equivocada.
--
--  ── CORRECCIÓN ──────────────────────────────────────────────────────
--  Backup: zz_backups."GV_Backup_838E_gondola_20260917" (4 filas).
-- =====================================================================

-- 1) el sector Ñ55 pasa a Chef (contiene sólo 838E)
update public."GV_Lugar" set empresa='CH', updated_at=now() where sector='Ñ55';

-- 2) capacidad de góndola: la fila LIBRE/LOKE de Ñ55 pasa a 838E / 35 cajas / CH
--    (Capacidad_Sector es la tabla que lee el front: SUPABASE_CAPACIDAD_ENDPOINT)
update public."Capacidad_Sector" set cod='838E', cajas_max=35, empresa='CH'
 where id=4566;   -- (sector Ñ55)

-- 3) GV_Lugar_Item: cajas_max del ítem 838E en Ñ55 = 35 (consistencia con la viva)
update public."GV_Lugar_Item" set cajas_max=35, updated_at=now()
 where sector='Ñ55' and cod='838E';

-- 4) caché de empresa: 838E -> CH (la función viva ya computa CH tras el paso 1)
update public."GV_Articulo_Empresa_Cache" set empresa='CH', fuente='gondola', refrescado_at=now()
 where cod_canon='838E';

-- VERIFICACIÓN
--   gv_empresa_de_articulo('838E')            -> CH
--   gv_lugar_articulo where sector='Ñ55'      -> CH / 838E
--   Capacidad_Sector id 4566                  -> 838E / 35 / CH
--   GV_Lugar_Item Ñ55/838E                    -> 35

-- ── RESIDUAL SIN IMPACTO ────────────────────────────────────────────
-- Un picking del 15/09 (tanda E11B, legajo 277) usó el código "838" (sin E),
-- delta 0 → sin impacto de stock. Es un typo de pedido aguas arriba; no se
-- tocó. Marianela lo ve como "838 que no existe".

-- ── ROLLBACK ────────────────────────────────────────────────────────
-- update public."GV_Lugar" set empresa='LK' where sector='Ñ55';
-- update public."Capacidad_Sector" set cod='LIBRE', cajas_max=null, empresa='LOKE' where id=4566;
-- update public."GV_Lugar_Item" set cajas_max=null where sector='Ñ55' and cod='838E';
-- update public."GV_Articulo_Empresa_Cache" set empresa='LK' where cod_canon='838E';
-- (valores previos en zz_backups."GV_Backup_838E_gondola_20260917")
