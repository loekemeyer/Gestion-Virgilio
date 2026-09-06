-- ============================================================================
-- BACKUP · PPP_Web_Programacion — filas borradas el 2026-09-06 (v13.59)
-- ----------------------------------------------------------------------------
-- MOTIVO: pedido del dueno. El automatico armaba una tanda NUEVA por cada
--   corrida del intradia (cada 15 min), porque `_open` —la lista de tandas que
--   pueden recibir un cliente mas— se crea VACIA en cada corrida y solo se
--   llena con lo que esa misma corrida arma. Resultado: cada pedido que entraba
--   solo se llevaba su propio camion.
--   Regla nueva del dueno: la tanda ACUMULA hasta 0,80 m3 (puede pasarse un
--   poco con el pedido que la cruza) y recien ahi se cierra.
--
-- QUE SE BORRO: las 4 tandas armadas por el automatico que quedaron por debajo
--   de 0,80 m3, para rearmarlas con la regla nueva. Se conservan E01A (0,985),
--   E03A (0,938) y E05A (1,184): son de un solo cliente que ya pasa el tope, o
--   sea tanda propia y cerrada por la regla vieja Y por la nueva.
--
--     E02A  chef 216 Elbantonio        Soldati              0,547 m3  (2 bloques)
--     E04A  lk 1349 Bazar Monica       San Antonio de Padua 0,105 m3
--     E06A  chef 217 Gifel             San Martin           0,136 m3
--     E08A  lk 1352 Muller y Muller    Pompeya              0,240 m3  (PEDIDO DE PRUEBA)
--
--   Ninguna tenia eventos de produccion (0 EP/TP/AP/TAP): nadie las empezo.
--   NO se tocaron `PPP_Web_Base` (foto de articulos) ni `PPP_Web_NP` (numero):
--   al sacar la fila de Programacion el pedido vuelve solo a "A Programar" con
--   todo su detalle intacto.
--
-- ROLLBACK: correr los INSERT de abajo en hrxfctzncixxqmpfhskv.
-- ============================================================================

INSERT INTO public."PPP_Web_Programacion" (empresa,order_id,np_idx,np,cod_cliente,razon_social,direccion,barrio,tanda,zona,fecha_entrega,op,observaciones,m3,m3_parcial,lineas,cajas,creado_por,creado_at,actualizado_at,fecha_recep,es_agregado,agregado_a_np,agregado_en,prioridad,np_total) VALUES ('chef',216,1,216,'2466','Elbantonio','Exp.  — Pergamino 3751 (I. Catolica 6- Rio Cuarto)','Soldati','E02A','Zona 1 - CABA Sur','2026-09-11',NULL,NULL,0.326,false,15,43,'sistema','2026-09-06 00:20:34.693974-03','2026-09-06 16:27:45.823738-03',NULL,false,NULL,NULL,0,NULL);
INSERT INTO public."PPP_Web_Programacion" (empresa,order_id,np_idx,np,cod_cliente,razon_social,direccion,barrio,tanda,zona,fecha_entrega,op,observaciones,m3,m3_parcial,lineas,cajas,creado_por,creado_at,actualizado_at,fecha_recep,es_agregado,agregado_a_np,agregado_en,prioridad,np_total) VALUES ('chef',216,2,216,'2466','Elbantonio','Exp.  — Pergamino 3751 (I. Catolica 6- Rio Cuarto)','Soldati','E02A','Zona 1 - CABA Sur','2026-09-11',NULL,NULL,0.221,false,8,18,'sistema','2026-09-06 00:20:34.693974-03','2026-09-06 16:27:45.823738-03',NULL,false,NULL,NULL,0,NULL);
INSERT INTO public."PPP_Web_Programacion" (empresa,order_id,np_idx,np,cod_cliente,razon_social,direccion,barrio,tanda,zona,fecha_entrega,op,observaciones,m3,m3_parcial,lineas,cajas,creado_por,creado_at,actualizado_at,fecha_recep,es_agregado,agregado_a_np,agregado_en,prioridad,np_total) VALUES ('lk',1349,1,1349,'4045','Bazar Monica S. CAP I SECC IV','Ayacucho 56 - San Antonio de P','San Antonio de Padua','E04A','Zona 5 - GBA Oeste','2026-09-11',NULL,NULL,0.105,false,16,19,'sistema','2026-09-06 16:15:11.534901-03','2026-09-06 16:27:45.823738-03',NULL,false,NULL,NULL,0,NULL);
INSERT INTO public."PPP_Web_Programacion" (empresa,order_id,np_idx,np,cod_cliente,razon_social,direccion,barrio,tanda,zona,fecha_entrega,op,observaciones,m3,m3_parcial,lineas,cajas,creado_por,creado_at,actualizado_at,fecha_recep,es_agregado,agregado_a_np,agregado_en,prioridad,np_total) VALUES ('chef',217,1,217,'2715','Gifel S.R.L.','Hilarion De La Quintana 2150','San Martin','E06A','Zona 6 - GBA Norte','2026-09-14',NULL,NULL,0.136,false,1,20,'sistema','2026-09-06 16:15:12.051931-03','2026-09-06 16:27:45.823738-03',NULL,false,NULL,NULL,0,NULL);
INSERT INTO public."PPP_Web_Programacion" (empresa,order_id,np_idx,np,cod_cliente,razon_social,direccion,barrio,tanda,zona,fecha_entrega,op,observaciones,m3,m3_parcial,lineas,cajas,creado_por,creado_at,actualizado_at,fecha_recep,es_agregado,agregado_a_np,agregado_en,prioridad,np_total) VALUES ('lk',1352,1,1352,'862','Muller Y Muller S.R.L.','Exp. Fontana — PEDRO BALLINA  4060, Pompeya (De L Americas 4384- Parana)','Pompeya','E08A','Zona 1 - CABA Sur','2026-09-14',NULL,NULL,0.24,false,1,100,'sistema','2026-09-06 20:30:11.85244-03','2026-09-06 20:30:11.85244-03',NULL,false,NULL,NULL,0,NULL);
