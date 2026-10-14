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
