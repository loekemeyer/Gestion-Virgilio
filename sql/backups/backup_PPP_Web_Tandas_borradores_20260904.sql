-- BACKUP restore-ready — los 3 borradores de tanda de PRUEBA que quedaron en
-- PPP_Web_Tandas / PPP_Web_Tanda_Items el 2026-09-04 (creados 17:22–17:43 probando la
-- solapa "A Programar", v12.80–v12.83). Se borran antes de prender la numeración: un
-- pedido no puede estar en dos tandas y esos 7 bloques (pedidos 1117–1120, del
-- 2026-08-05, ya enviados a ISIS) quedarían trabados. Tablas nuestras; Producción no
-- las lee. Para restaurar: ejecutar este archivo tal cual.

insert into public."PPP_Web_Tandas"
select * from json_populate_recordset(null::public."PPP_Web_Tandas", $j$[
{"empresa":"lk","codigo":"GV-01A","estado":"borrador","fecha_entrega":null,"creado_por":"","creado_at":"2026-09-04T17:22:06.293014-03:00","programada_por":null,"programada_at":null},
{"empresa":"lk","codigo":"GV-01B","estado":"borrador","fecha_entrega":null,"creado_por":"","creado_at":"2026-09-04T17:22:07.658691-03:00","programada_por":null,"programada_at":null},
{"empresa":"lk","codigo":"GV-01C","estado":"borrador","fecha_entrega":null,"creado_por":"","creado_at":"2026-09-04T17:22:08.336401-03:00","programada_por":null,"programada_at":null}
]$j$::json)
on conflict do nothing;

insert into public."PPP_Web_Tanda_Items"
select * from json_populate_recordset(null::public."PPP_Web_Tanda_Items", $j$[
{"empresa":"lk","codigo":"GV-01A","order_id":1117,"np_idx":1,"np":null,"cod_cliente":"4178","razon_social":"Riesgo Marcelo Fabian","zona":"Zona 1 - CABA Sur","m3":0.121,"m3_parcial":false,"lineas":17,"cajas":17,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:31:27.400084-03:00","np_total":3},
{"empresa":"lk","codigo":"GV-01A","order_id":1117,"np_idx":2,"np":null,"cod_cliente":"4178","razon_social":"Riesgo Marcelo Fabian","zona":"Zona 1 - CABA Sur","m3":0.121,"m3_parcial":false,"lineas":17,"cajas":18,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:31:27.400084-03:00","np_total":3},
{"empresa":"lk","codigo":"GV-01A","order_id":1117,"np_idx":3,"np":null,"cod_cliente":"4178","razon_social":"Riesgo Marcelo Fabian","zona":"Zona 1 - CABA Sur","m3":0.125,"m3_parcial":false,"lineas":18,"cajas":23,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:31:27.400084-03:00","np_total":3},
{"empresa":"lk","codigo":"GV-01A","order_id":1120,"np_idx":1,"np":null,"cod_cliente":"1651","razon_social":"Inc Sociedad Anonima","zona":"Super","m3":2.932,"m3_parcial":false,"lineas":14,"cajas":437,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:43:55.209915-03:00","np_total":1},
{"empresa":"lk","codigo":"GV-01B","order_id":1118,"np_idx":1,"np":null,"cod_cliente":"1573","razon_social":"Messina Hnos S.A.","zona":"Zona 4 - GBA Sur","m3":0.659,"m3_parcial":false,"lineas":9,"cajas":173,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:31:33.97593-03:00","np_total":1},
{"empresa":"lk","codigo":"GV-01C","order_id":1119,"np_idx":1,"np":null,"cod_cliente":"1453","razon_social":"Hiper Bazar Gastronomico SA","zona":"Zona 1 - CABA Sur","m3":0.381,"m3_parcial":false,"lineas":15,"cajas":45,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:31:41.406856-03:00","np_total":2},
{"empresa":"lk","codigo":"GV-01C","order_id":1119,"np_idx":2,"np":null,"cod_cliente":"1453","razon_social":"Hiper Bazar Gastronomico SA","zona":"Zona 1 - CABA Sur","m3":0.242,"m3_parcial":false,"lineas":14,"cajas":48,"fecha_recep":"2026-08-05","agregado_por":"loekemeyer.n8n@gmail.com","agregado_at":"2026-09-04T17:31:41.406856-03:00","np_total":2}
]$j$::json)
on conflict do nothing;
