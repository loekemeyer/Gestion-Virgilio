-- v19.93 — El armado de E12E y E12J drenaba el picking del inquilino anterior (problema 437)
-- ============================================================================================
-- Tercera y última capa del bug del PKC (problema 421). Quedó a la vista recién cuando la v19.91
-- puso cada picking en su tanda: con el picking correcto, el `separado` viejo quedó al descubierto.
--
-- `reconciliar_pipeline_stock_etapa2` es INSERT-ONLY con guard
-- (`not exists (separado de esa tanda+articulo)`): una vez que escribió el `separado`, **no lo
-- recalcula nunca**. Así que los armados del 18/09 drenaron lo que HABÍA pickeado bajo ese código
-- en ese momento — el picking del inquilino anterior, no el de sus propias NP.
--
-- LA FUENTE DURA ES `Entregas_Virgilio`: lo que el operario contó al armar, por NP y tanda.
--   E12E  →  98605:21 + 98606:16 + 98607:1 =  38   · el sistema drenó 114  → 76 de más
--   E12J  →  98618:20                      =  20   · el sistema drenó 100  → 80 de más
--
-- ⚠ E12K NO entra, aunque a primera vista parecía el tercer caso (drenó 46 con picking 0).
-- Es una tanda VIEJA, entregada y FACTURADA (LK 0004, LK 0005, LK 0006 en `Facturacion_NP`),
-- cuyo código se reutilizó después para 98618. Su drenaje de 46 corresponde a su propia entrega
-- (30 entregadas + 16 devueltas a góndola): es legítimo. Lo que le falta es su picking original,
-- perdido en una capa anterior — otro problema, y no sale el lunes. El primer conteo dijo
-- "192 cajas de más"; el bueno es **156**.
--
-- ⚠ Y por eso se pudo tocar: E12E y E12J son NP de ISIS y **ninguna está facturada**. No hay
-- factura emitida que contradecir. E12S y E12K sí lo están, y no se tocaron.
--
-- EL ARREGLO NO CALCULA NADA A MANO: borra el `separado` viejo y deja que `etapa2` lo rehaga.
-- Con el picking ya corregido por la v19.91, su propia lógica da el número bueno (net = picking
-- real; el reparto a_facturar/terminado sale de `Entregas_Virgilio`). Mientras las filas existan
-- el guard `not exists` impide que las rehaga, así que **poner el delta en 0 no sirve acá**:
-- hay que borrarlas. Es la excepción a la regla de "UPDATE y no DELETE" — por eso el paso 3
-- fuerza el recálculo del saldo, que el trigger no hace en DELETE.
--
-- Backup: zz_backups."GV_Backup_Separado_E12E_E12J_20260918" (516 filas), con RLS.

select pg_advisory_xact_lock(5768);

delete from public."Movimientos_Stock"
 where tipo = 'separado' and upper(btrim(ref)) in ('E12E','E12J');

select public.reconciliar_pipeline_stock_etapa2();

-- y el saldo por código, que el trigger no recalcula en DELETE:
--   update "Movimientos_Stock" m set delta = m.delta where m.id in (min(id) por cod_art+empresa)
--
-- Guardas usadas: las dos tandas en CERO de comprometido, y drenando exactamente 38 y 20.
--
-- RESULTADO, verificado corriendo `reconciliar_pipeline_stock()` después:
--   tanda   pickeado  armado  colgado  a_facturar
--   E12E       38      -38       0        38
--   E12J       20      -20       0        20
--   E12S      188     -188       0       188   (la de los remitos, intacta)
--   E12A       40        0      40         0   (LK 0029 Tegerina, sin armar)
--   E37F      107        0     107         0   (sin armar, sale el 24/09)
--   E12G       93      -93       0        92
-- Cero tandas E12 con comprometido negativo. picking duplicado, reglas perdidas, empresa
-- fantasma y dedup por empresa: todos en cero.
--
-- ⚠ `GV_Stock_Drenaje_Bloqueado` pasó de 0 a 32 filas, y NO es por esto: son todas de **E11D |
-- LK 0099**, una tanda que no se tocó. E11D está sana y cerrada (picking 46, separado −46,
-- facturado −46, todo en cero) con movimientos del 16/09. El guard `zzz_facturado_no_negativo`
-- frenó un segundo intento de drenar 92 sobre una pila ya en cero — hizo exactamente su trabajo.
-- Lo destapó una corrida manual del cron, pero el cron de los 10 minutos lo habría anotado igual.
-- Queda para mirar aparte: por qué la etapa3 vuelve a proponer ese drenaje.
--
-- Chequeo:
--   select * from public."GV_Stock_Drenaje_Bloqueado";
--   select * from public.gv_stock_picking_duplicado;   -- vacía
