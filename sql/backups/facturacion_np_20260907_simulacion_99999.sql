-- ============================================================================
-- BACKUP · Facturacion_NP — 20 filas de SIMULACIÓN borradas el 2026-09-07
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv)
-- ----------------------------------------------------------------------------
-- QUÉ ERAN: `cod_cliente = 99999`, razón social `CLIENTE SIMULACIÓN`, tandas
--   `SIM######`, m³ = 1,000 clavado en las 20 (número redondo = inventado).
--   Alguien probó la pantalla de FACTURACIÓN el lunes 2026-08-31 y los tics
--   quedaron en la tabla. Entraron de a una, con segundos de diferencia, en dos
--   tandas: 11:09–11:10 (8 filas) y 11:39–11:40 (12 filas) — eso es una persona
--   tildando NP a mano, no un insert masivo. Las 20 tienen `cierre_id` en NULL;
--   las facturaciones reales llevan cierre.
--
-- POR QUÉ NO ERAN REALES (verificado, no supuesto):
--   · 0 filas en `PPP_Programacion_Diaria` con esas NP o tandas
--   · 0 filas en `PPP_Base_Pedidos`
--   · 0 filas en `PPP_Web_Programacion`
--   · 0 eventos en `Registros_Produccion_Virgilio` (ni EP/TP/AP/TAP/CCN/CRN)
--   · 0 coincidencias en el código de Gestión Virgilio y de Producción Virgilio
--     (repo loekemeyer/produccion-virgilio, commit e15b682) — no las genera ninguna app
--   · 0 con `cierre_id`
--
-- POR QUÉ SALTARON A LA VISTA: la v13.62 cambió el universo de `gv_ppp_en_salida`
--   de "tiene CCN" a "está facturada sin CRN". Estas 20 están facturadas, nunca se
--   controlaron y no están en la hoja de entregados, así que pasaron a verse en la
--   pantalla En Salida como un renglón "Lun 31/8/2026 · 20 ped · 20,00 m³".
--
-- IMPACTO MEDIDO (gv_ppp_en_salida):
--   antes:  54 NP · 24,646 m³   (20 NP y 20,000 m³ eran éstas)
--   después: 34 NP ·  4,646 m³
--
-- ⚠ `Facturacion_NP` es una tabla COMPARTIDA con Producción Virgilio y la regla del
--   dueño es que ahí se AGREGA y no se borra. Este borrado va con su OK EXPLÍCITO
--   (2026-09-07, "Elimina las 20 de cliente simulación"), pedido después de que se le
--   explicara esa regla y se le ofreciera la alternativa de filtrarlas en la vista.
--
-- SENTENCIA QUE SE CORRIÓ:
--   delete from public."Facturacion_NP" where cod_cliente = '99999';
--   (con WHERE real: supautils bloquea DELETE sin WHERE para roles no superusuario)
--
-- ROLLBACK: correr los INSERT de abajo en hrxfctzncixxqmpfhskv.
-- ============================================================================

INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99900671051','SIM067105','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:39:38.749866-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99900671052','SIM067105','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:39:39.380436-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99900671053','SIM067105','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:39:42.202414-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99902156641','SIM215664','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:40:31.968719-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99902156642','SIM215664','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:40:32.627687-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99902156643','SIM215664','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:40:33.252354-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99902746351','SIM274635','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:10:19.145207-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99904224291','SIM422429','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:39:26.117665-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99904224292','SIM422429','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:39:27.830731-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99904224293','SIM422429','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:39:28.63323-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99906334221','SIM633422','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:40:43.983494-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99906334222','SIM633422','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:40:44.75591-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99906334223','SIM633422','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:40:45.373928-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99906642661','SIM664266','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:09:40.083449-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99909632381','SIM963238','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:09:49.382386-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99909632382','SIM963238','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:09:55.396493-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99909632383','SIM963238','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:09:57.807263-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99909966151','SIM996615','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:10:07.226413-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99909966152','SIM996615','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:10:09.53744-03',NULL);
INSERT INTO public."Facturacion_NP" (np,tanda,fecha_salida,m3,razon_social,cod_cliente,facturado_at,cierre_id) VALUES ('99909966153','SIM996615','2026-08-31',1.0,'CLIENTE SIMULACIÓN','99999','2026-08-31 11:10:11.615887-03',NULL);
