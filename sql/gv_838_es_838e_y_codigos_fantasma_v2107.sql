-- v21.07 (Luis, 2026-09-22) — limpieza de OCs y stock: el 838 no existe, cinco codigos
-- fantasma se apagan y el 581T queda con proveedor cargado para el futuro.
--
-- 1) EL 838 NO EXISTE COMO PRODUCTO (Luis, textual): "838 como producto para vender nunca
--    existio, se tomaron mal algunos pedidos... El que existio en su momento fue el 839 que
--    fue remplazado por el 838E". Medido en sales_lines de LK: el 838 tiene CERO lineas
--    facturadas en toda la historia; el 839 tiene 215 lineas y 706 cajas hasta el 15/09/2026.
--
--    No hace falta tocar ningun pedido a mano: alcanza UNA fila en Equivalencias_Familia,
--    porque la logica primario/secundario ya consolida stock, proyeccion y demanda contra el
--    principal y borra la fila del secundario del generador (CTE `fam` de vista_generador_oc).
--    Medido al aplicarlo: la fila 838 desaparecio del generador y el 838E paso de
--    16 a 48 cajas de pedidos y de 81 a 113 cajas a pedir. El maximo no se movio (67) porque
--    el 838 no tenia proyeccion propia.
--
--    ⚠ La semilla del front (EQUIV_FAMILIAS en index.html) ya tiene la familia 838E, asi que
--    equivFamiliasLoad() adopta el miembro nuevo sola: NO hace falta tocar el front.
--
-- 2) LOS CINCO QUE NO EXISTEN (505C, 587C, 501B, 731D, 228). Proyectan porque se facturaron
--    una vez y la proyeccion promedia esas cajas sobre la ventana — no porque el sistema los
--    crea vivos. La cuenta cierra al decimal:
--      505C  64 cajas (28 y 29/05/2026, cliente chef 1434)  -> 64/6  = 10,67
--      587C  11 cajas (las MISMAS dos facturas, mismo 1434) ->  11/6 =  1,83
--      731D   8 cajas (abr-may/2026)                        ->   8/6 =  1,33
--      501B  ultima venta 23/10/2025, fuera de los 6 meses  -> fallback 12m = 6,25
--      228    3 cajas 01/12/2025 (LK), fuera de los 6 meses -> fallback 12m = 0,25
--
--    ⚠ Borrarlos de proyeccion_madre NO sirve: esa tabla la reescribe entera el cron de LK
--    todas las mananas (06:20 ART). El interruptor que aguanta es OC_Maximos.activo = false,
--    que el generador respeta en el front ("if (r.activo === false) return;", v10.30).
--
-- 3) 581T: no se vende hoy, pero queda con proveedor Martin C por si vuelve. Pide 0 cajas
--    (stock 73 = capacidad 73), asi que cargarlo no dispara ninguna OC.
--
-- ⚠ El nombre del proveedor es "Martin C", no "Martin": OC_Maximos tiene 31 codigos con esa
--   grafia y ninguno con "Martin" a secas.
--
-- Rollback: delete de las 7 filas y el Suspendido vuelve del backup
--   zz_backups."GV_Backup_ArticulosCajas_838_20260922".

insert into public."Equivalencias_Familia" (cod_secundario, cod_principal, empresa, descripcion, actualizado_en)
values ('838','838E', null, 'Rallador Chico Chocolate (838 no existe como producto: pedidos mal tomados)', now())
on conflict (cod_secundario) do nothing;

insert into public."OC_Maximos" (cod, linea, descripcion, proveedor, activo, actualizado) values
 ('505C','CH','Discontinuado - no es un codigo real (Luis, 22/09/2026)', null, false, now()),
 ('587C','CH','Discontinuado - no es un codigo real (Luis, 22/09/2026)', null, false, now()),
 ('501B','CH','Discontinuado - no es un codigo real (Luis, 22/09/2026)', null, false, now()),
 ('731D','CH','Discontinuado - no es un codigo real (Luis, 22/09/2026)', null, false, now()),
 ('228','LK','Tenedor de Madera 30 cm - discontinuado (Luis, 22/09/2026)', null, false, now())
on conflict (cod, linea) do nothing;

insert into public."OC_Maximos" (cod, linea, descripcion, proveedor, activo, indice, actualizado)
values ('581T','LK','Sac. Cabo Nylon Tira Imp','Martin C', true, 1.5, now())
on conflict (cod, linea) do nothing;

-- la ficha que le daba cuerpo al codigo inventado (36 u/caja; la pagina lo manda con 12,
-- que es el uxb del 838E). ⚠ Suspendido NO filtra en ningun lado: se usa solo en el ORDER BY
-- del CTE nom_ac de vista_generador_oc para elegir la descripcion. Lo que apaga al 838 es la
-- equivalencia de arriba, no esto.
update public."Articulos_Cajas" set "Suspendido" = true where id = 310;

-- Chequeo
--   select * from public.vista_generador_oc where cod in ('838','838E','581T');   -- 838 no esta
--   select * from public.gv_oc_codigos_sin_config order by pedidos desc;          -- bajo de 16 a 7
