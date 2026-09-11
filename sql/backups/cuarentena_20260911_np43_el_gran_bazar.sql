-- ============================================================================
-- BACKUP 2026-09-11 — El Gran Bazar S.R.L (lk 2375, pedido 1369, NP 43) sacado de
-- Programación (tanda E12A, entrega 18/09) para que vuelva a Cuarentena.
-- Dueño: "El gran bazar, pasalo a cuarentena". Deuda en GV_Cuarentena_Fuente:
-- $2.519,21. Se había programado el 08/09 16:30, antes de que existiera el dato
-- de deuda (cargado 10/09 17:27).
--
-- Mecanismo: el mismo de Pérez Zárate (NP 56) y del resync (`ppp_web_resync`):
-- se borra SÓLO la fila de PPP_Web_Programacion, con guarda "tanda sin arrancar"
-- (E12A: 0 eventos EP/TP/AP/TAP/CC; la tanda queda con 7 filas). La NP 43
-- (PPP_Web_NP) y los 7 ítems (PPP_Web_Base, np_label 'LK 0043') se DEJAN: se
-- reusan al reprogramar. PPP_Web_Tanda_Items: 0 filas. GV_Cuarentena_Liberados: 0.
-- ============================================================================

-- ROLLBACK: volver a programar a El Gran Bazar en E12A (fila exacta, to_jsonb antes del delete)
insert into public."PPP_Web_Programacion"
select * from jsonb_populate_record(null::public."PPP_Web_Programacion", $j$
{"m3":0.115,"np":43,"op":null,"zona":"Zona 1 - CABA Sur","cajas":15,"tanda":"E12A","barrio":"Soldati",
 "lineas":7,"np_idx":1,"empresa":"lk","np_total":null,"order_id":1369,
 "creado_at":"2026-09-08T16:30:15.8171-03:00",
 "direccion":"Exp. Tradelog — PERGAMINO 3751, Soldati (Tucuman 275- S.del Estero)",
 "prioridad":0,"creado_por":"sistema","m3_parcial":false,"agregado_en":null,"cod_cliente":"2375",
 "es_agregado":false,"fecha_recep":null,"razon_social":"El Gran Bazar S.R.L","agregado_a_np":null,
 "fecha_entrega":"2026-09-18","observaciones":null,"actualizado_at":"2026-09-10T09:52:47.036166-03:00"}
$j$::jsonb)
on conflict do nothing;

-- Referencia (NO se borraron, siguen en la base):
--   PPP_Web_NP: {"np":43,"np_idx":1,"empresa":"lk","order_id":1369,"creado_at":"2026-09-08T16:30:15.516109-03:00"}
--   PPP_Web_Base (7 filas, np_label 'LK 0043', creado 2026-09-08T16:30:17): artículos y cajas =
--     031x3, 034x2, 395x1, 544x4, 585Ex2, 587x2, 591x1
