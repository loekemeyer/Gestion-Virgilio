-- v30.30 · 2026-10-14 · CONTEO DE INSUMOS EN RACKS (Luis, Virgilio). Aplicado por MCP en la sesión.
-- Luis: "hay varias espirales. las que estan en y04 ahora son las 1000900. en AD4 hay unas que se llaman
-- H201part ... que no se mezclen" · "si ayer se unifico algo que quede marcadamente separado ahora".
--
-- Backups: zz_backups."GV_Backup_546P_rename_20261014" y zz_backups."GV_Backup_Insumos_Conteo_20261014".
--
-- | insumo                  | rack  | conteo                 | u       | qué se hizo                                   |
-- |-------------------------|-------|------------------------|---------|-----------------------------------------------|
-- | 505C                    | X20   | 24 x 4.000 + 1 x 2.000 |  98.000 | coincide (110.000 Uni − 3 MC x 4.000): nada  |
-- | 1000900 Espiral Chino   | Y04   | 39 x 2.000             |  78.000 | ALTA del insumo + ajuste +78.000              |
-- | H201Part Espiral TN     | AD04  | 12 x 2.000             |  24.000 | ajuste −312.000 (las 156 cajas de Y04 del     |
-- |                         |       |                        |         | 13/10 eran del 1000900); sale Y04 de sus lugares|
-- | 1546903 (ex 546P)       | X13   | 47 x 144               |   6.768 | RENOMBRE 546P -> 1546903 (Insumos, movimientos |
-- |                         |       |                        |         | de insumos, factores, ubicación, map, GP2)    |
-- | 523C Cremallera         | Z01   | 25 x 240               |   6.000 | coincide; se muda de W01 (no estaba) a Z01    |
-- | 522ES                   | W04   | 20 x 100               |   2.000 | coincide; nota corregida (no 80 x 25)         |
-- | Mgo Pelador Ergonomico  | N01   | 35 x 250               |   8.750 | coincide; lugar N01 + vínculo GP2 PEP1        |
--
-- SEPARACIÓN H201Part / 1000900 (se habían unificado el 30/09 y el 13/10):
--   * GV_Importados_Insumo_Map: se saca H201Part -> 1000900 (importación ya no suma el Espiral TN al 1000900).
--   * GP2.insumo_equivalencia: se saca H201PART -> 163 (D1 Espiral Sacacorcho). H201Part queda SIN componente
--     de GP2 (no hay uno de Espiral TN): no se puede mandar a Cervantes hasta que se le cree uno.
--   * 1000900 -> D1 sigue. 007 (Espiral Chef, 3.500 u en Z02) -> D1 y -> importado 1000900 siguen: Luis no lo nombró.
--
-- Racks nuevos en GV_Lugar (empresa IN): N01 (orden 707) y Z01 (orden 865). Antes no existían y
-- gv_insumo_sector('N1'/'Z1') daba null.
--
-- 546P -> 1546903: GP2 ya tenía las DOS filas (546P y 1546903 -> C13). Se borró la de 546P y la de 1546903 tomó
-- el isis. Hay que hacerlo en ese orden: el trigger zz_gv_insumo_cod_sync_equiv renombra la equivalencia al
-- cambiar Insumos.cod y choca con la PK si la otra fila existe.
--
-- Verificación (14/10, 09:11):
select cod_art, unidad, saldo from public.vista_saldos_insumos_x_unidad
 where cod_art in ('H201Part','1000900','523C','522ES','Mgo Pelador Ergonomico','505C','1546903') and saldo <> 0;
--  1000900 78.000 · 1546903 6.768 · 505C 110.000 Uni / −3 MC · 522ES 2.000 · 523C 6.000 · H201Part 24.000 ·
--  Mgo Pelador Ergonomico 8.750
select cod, stock_uni from public.gv_importados_stock_insumos where cod in ('1000900','1546903','505C','523C','522ES');
--  1000900 81.500 (78.000 + 007 3.500) · 1546903 6.768 · 505C 98.000 · 523C 6.000 · 522ES 2.000
select cod, sector, estado from public.gv_insumo_ubicacion
 where cod in ('1000900','H201Part','523C','522ES','Mgo Pelador Ergonomico','1546903','505C');
--  todos 'ok': Y04 · AD04 · Z01 · W04 · N01 · X13 · X20
--
-- Rollback: reponer desde los dos backups; borrar los ajustes con ref 'CONTEO H201Part AD04 14/10' y
-- 'CONTEO 1000900 Y04 14/10', el Insumos 1000900 y sus ubicaciones, y los GV_Lugar N01 / Z01.

-- ===================== v30.31 · 2026-10-14 (segunda pasada, Luis) =====================
-- Backup: zz_backups."GV_Backup_Insumos_Conteo2_20261014".
-- Descripciones: 1000900 «Espiral Chino» · H201Part «Espiral Chino TN» · 1546903 «Bastidor corta queso».
-- «Mgo Pelador Ergonomico» pasa a llamarse PEP1 «Mango pelador negro calado sin grabar» (Insumos, movimientos
--   de insumos, factores, ubicación N01; la equivalencia de GP2 la renombra el trigger -> PEP1 = componente 227).
-- Coinciden con el sistema (sólo nota): Z02 337P 31 x 144 = 4.464 · Z02 007 7 x 500 = 3.500 · X24 439E 13 MC x 24 = 312.
-- No estaban donde decía el sistema (se saca la posición; el stock queda y sale en gv_mapa_stock_sin_lugar):
--   H201Lever O01 (26.400 u) · CB01 N07 (2.950 u) · 590E Z07 (2.400 u) · 584E AC06 (0 u).
-- 440E es PRODUCTO, no insumo: insumos −528 Uni; racks +168 inner X21 (14 MC) y +360 inner X23 (30 MC).
-- Productos que Luis nombró y NO se tocaron: N07 513 360 cajas (coincide) · Z07 363E 15 MC (sistema 11 MC).

-- ===================== v30.33 · 2026-10-14 (tercera pasada, Luis) =====================
-- 363E Z07: +24 inner (11 MC -> 15 MC). gv_rack_celda Z07: master 15 inner 90.
-- En 0 "hasta contarlos": H201Lever −26.400 Uni · CB01 −2.950 Uni (ref 'CONTEO 0 (Luis 14/10)').
-- 590E: su total YA era 0 (Uni 2.400 + MC −4 x 600). El ajuste MC +4 lo convierte a Uni el trigger de
--   «el insumo con MC queda en unidades», así que no se puede cerrar la línea MC desde acá: se borraron los
--   dos movimientos de prueba (neto 0) y queda como estaba.
-- PEP1: «Mango pelador negro calado sin grabar» (confirmado por Luis).
-- 587C: no existe en el depósito (Luis). Se descarta del pendiente de la tarea 4448.

-- ===================== v30.34 · 2026-10-14 (cuarta pasada, Luis) =====================
-- Backup: zz_backups."GV_Backup_590E_007_20261014".
-- 590E: la entrega del 24/08 (id 19734959, −4 MC a Cervantes) se REEXPRESA a −2.400 Uni (update, no insert:
--   el trigger BEFORE INSERT gv_insumo_unidad_base convierte a unidades todo MC nuevo, así que un ajuste en MC
--   nunca cierra una línea MC vieja). Queda Uni 0 y sale de la alarma «con stock y sin lugar».
-- 007 «Espiral Chef»: se saca del map al importado 1000900 y del vínculo GP2 D1. D1 queda sólo con 1000900.
-- Importación 1000900: 78.000 (antes 81.500 con el 007).

-- ===================== v30.35 · 2026-10-14 (quinta pasada, Luis) =====================
-- «AD04 (24000)» en Stock → Insumos: el número entre paréntesis es Insumos_Ubicaciones.cantidad (cantidad
--   DECLARADA por posición, la usa el Mapa como «🧰 insumo · N»), NO el stock. El stock canónico es
--   Movimientos_Stock (vista_saldos_insumos_x_unidad) y la ubicación canónica es gv_insumo_ubicacion
--   (Insumos_Ubicaciones resuelto contra GV_Lugar). Se pone cantidad = 0 en las 3 que tenían una sola
--   posición: H201Part AD04 (24000), 439E X24 (312), 584E Z10 (12, con stock 0). Backup:
--   zz_backups."GV_Backup_InsUbic_cant_20261014".
-- 599ES: −1.200 Uni (Luis: «sacalo»). Con saldo 0 sale de la lista (la tabla filtra los que están en 0).

-- ===================== v30.36 · 2026-10-14 (sexta pasada, Luis) =====================
-- O06 alta en GV_Lugar (rack IN). Mgo Pelador 505 -> O06, 15 bolsas x 1.800 = 27.000 u (coincide con el stock).
-- 522ES: Insumos.ubicacion 'AD2' (texto viejo) -> 'W04', igual que su posición.
--
-- QUÉ LEE EL MAPA (verificado 14/10, como anon):
--   Racks del Mapa = gv_rack_celda = GV_Lugar (racks activos) + Racks_Planimetria (vista: PRODUCTO, sale del libro
--   de stock con ubicacion = sector) + gv_insumo_ubicacion (INSUMO: Insumos_Ubicaciones resuelto contra GV_Lugar).
--   Stock de insumos = Movimientos_Stock (vista_saldos_insumos_x_unidad). Insumos.ubicacion es texto viejo: la lista
--   lo usa SÓLO si el insumo no tiene fila en Insumos_Ubicaciones; el Mapa no lo lee.
-- QUIÉN ESCRIBE POSICIONES: sólo las RPC que dispara una persona (gv_insumo_posicion_guardar desde el Mapa,
--   gv_insumo_ubicaciones_guardar desde Insumos, gv_rack_posicion_guardar / gv_rack_partir / gv_lugar_orden).
--   Ningún cron escribe Insumos_Ubicaciones ni GV_Lugar (el único cron de insumos, 152, escribe en GP2).
--   => un conteo cargado no lo pisa ningún proceso automático.
