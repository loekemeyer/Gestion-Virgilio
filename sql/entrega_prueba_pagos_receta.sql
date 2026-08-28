-- RECETA: cargar (y despues borrar) una ENTREGA DE PRUEBA de tallerista, para
-- mostrarle el circuito completo a alguien (ej. demo al sector Pagos, 2026-08-28).
--
-- Se uso una vez con: Poly (cod 2416, linea LK) · remito 1500 · art 513 · 250 cajas.
-- Esa corrida YA SE CARGO Y YA SE BORRO (verificado: 0 filas en las 5 tablas y
-- stocks_carga_rapida del 513 de vuelta en a_guardar=321 / total=2027).
--
-- Las 5 escrituras son las mismas que hace recepcion.js en una recepcion real, en
-- este orden. Cambiar los literales de arriba y listo.
--
--   1. "Entregas Tallerista Virgilio"  -> dispara trg_recep_pagos_tall
--   2. planify.tasks                   -> la crea sola el trigger (dept 6 = Pagos, broadcast)
--   3. "Movimientos_Stock"             -> a_guardar +cajas (legajo '1' = Pruebas, para que
--                                         quede marcado como test)
--   4. "Pasaje_Papeles"                -> el remito pendiente de mandar a Cervantes
--   5. "Control_Modo_OP"               -> la ficha del checklist (con foto y codigo de 4 digitos)
--
-- La FOTO se puede reciclar de otra entrega: se copia el foto_url de un
-- Control_Modo_OP existente. Asi no se sube nada nuevo al bucket `remitos` y el
-- borrado no tiene que tocar Storage.

/* ---------- CARGA ---------- */

insert into public."Entregas Tallerista Virgilio"
  ("Fecha","Codigo_Tall","Nombre_Tall","Cod","Cajas","Remito","Tipo_Entrega","Fecha_RTO")
values ('2026-08-28','2416','Poly','513',250,'1500','remito','2026-08-28');

insert into public."Movimientos_Stock"
  (cod_art, descripcion, deposito, delta, tipo, ref, legajo, client_id)
values ('513','Pelador Mgo Metalico','a_guardar',250,'recepcion','1500','1',
        'mst_prueba_pagos_1500_513');

insert into public."Pasaje_Papeles"
  (planta, tipo_documento, razon_social, tipo_contenido, fecha_emision, fecha_recepcion,
   numero_remito, fecha_remito, legajo_usuario, cod_proveedor, enviado, enviado_a_cervantes, confirmado)
values ('virgilio','remito','Poly','mercaderia','2026-08-28', now(),
        '1500','2026-08-28','1','2416', false, false, false);

insert into public."Control_Modo_OP"
  (fecha, tipo, nombre, codigo_tall, linea, remito, detalle, cantidad_total, estado, foto_url, codigo)
values ('2026-08-28','tallerista','Poly','2416','LK','1500','513 → 250',250,'pendiente',
        'https://hrxfctzncixxqmpfhskv.supabase.co/storage/v1/object/public/remitos/358_1787846477142.jpg',
        '7250');

/* ---------- BORRADO ---------- */
-- De la punta hacia atras. La tarea de Planify va ANTES que la entrega: el trigger
-- dedupea por el marcador [vrec:...] que vive en tasks.note, asi que si se borra la
-- entrega primero y alguien recarga el mismo remito, la tarea se duplicaria.

begin;
delete from public."Control_Modo_OP"
 where remito='1500' and nombre='Poly' and codigo='7250';
delete from public."Pasaje_Papeles"
 where numero_remito='1500' and razon_social='Poly';
delete from public."Movimientos_Stock"
 where client_id='mst_prueba_pagos_1500_513';
delete from planify.tasks
 where note like '%[vrec:tallerista|1500|POLY]%';
delete from public."Entregas Tallerista Virgilio"
 where "Remito"='1500' and "Nombre_Tall"='Poly';
commit;

-- ⚠ OJO — EL PASO QUE SE OLVIDA: `stocks_carga_rapida` es un CACHE que mantiene el
-- trigger `trigger_actualizar_saldo_stock`, y ese trigger es AFTER INSERT/UPDATE:
-- NO se dispara con DELETE. Borrar el movimiento deja el saldo cacheado inflado.
-- Hay que recalcular a mano la fila del articulo tocado (misma cuenta que el trigger):

with s as (
  select
    coalesce(sum(delta::numeric) filter (where deposito='terminado'),0) t,
    coalesce(sum(delta::numeric) filter (where deposito='excedente'),0) e,
    coalesce(sum(delta::numeric) filter (where deposito='separar_pedidos'),0) sp,
    coalesce(sum(delta::numeric) filter (where deposito='a_facturar'),0) af,
    coalesce(sum(delta::numeric) filter (where deposito='a_guardar'),0) ag,
    coalesce(sum(delta::numeric) filter (where deposito='racks'),0) r,
    coalesce(sum(delta::numeric) filter (where deposito='racks_ch'),0) rch,
    coalesce(sum(delta::numeric) filter (where deposito='para_envasar'),0) pe,
    coalesce(sum(delta::numeric) filter (where deposito='insumos_dep'),0) idp,
    sum(delta::numeric) tot
  from public."Movimientos_Stock"
  where regexp_replace(upper(btrim(cod_art)),'^0+(?=.)','') = '513'   -- <-- el articulo
)
update public.stocks_carga_rapida q set
  terminado=s.t, excedente=s.e, separar_pedidos=s.sp, a_facturar=s.af,
  a_guardar=s.ag, racks=s.r, racks_ch=s.rch, para_envasar=s.pe,
  insumos_dep=s.idp, stock_total=s.tot
from s where q.cod='513';                                              -- <-- el articulo

-- Control post-borrado: las 5 primeras columnas tienen que dar 0.
-- select
--   (select count(*) from public."Entregas Tallerista Virgilio" where "Remito"='1500') as entregas,
--   (select count(*) from planify.tasks where note like '%[vrec:tallerista|1500|POLY]%') as tareas_pagos,
--   (select count(*) from public."Movimientos_Stock" where client_id='mst_prueba_pagos_1500_513') as stock,
--   (select count(*) from public."Pasaje_Papeles" where numero_remito='1500') as papeles,
--   (select count(*) from public."Control_Modo_OP" where remito='1500') as recepcion,
--   (select a_guardar from public.stocks_carga_rapida where cod='513') as cache_a_guardar;
