-- ============================================================================
-- v17.16 — Chequeo: ¿sirve isis_lk / isis_ch para reemplazar la carga manual?
--
-- Pedido de Thomas (14/09): "avanzá con el chequeo de que realmente esté bien
-- lo que tenemos para implementar esto".
--
-- Este archivo NO cambia nada. Son las consultas del chequeo y su resultado,
-- para poder repetirlo.
--
-- VEREDICTO: SÍ, desde 2026-02 en adelante. Antes, no.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) ¿Reproduce ISIS lo que cargó el Excel?  SÍ, al entero.
--
--  mes | Excel  | ISIS con NC | ISIS solo FC | veredicto
--  ----|--------|-------------|--------------|------------------------------
--  feb | 19.367 | 19.367  ✅  | 19.962       | clavado
--  mar | 18.522 | 18.519      | 21.149       | dif 3 cajas (0,02 %)
--  abr | 14.196 | 13.829      | 14.196  ✅   | el Excel vino SIN notas de credito
--  may | 25.074 | 25.242  ✅  | 25.609       | el Excel trajo los codigos administrativos (-168)
--  jun | 16.625 | 16.625  ✅  | 16.713       | clavado
--
-- Cuatro de cinco meses cierran al entero; el quinto por 3 cajas. Y las dos
-- diferencias que parecian tales resultaron ser INCONSISTENCIAS DEL EXCEL, no
-- de ISIS: abril vino sin NC y mayo trajo los descuentos administrativos que
-- los otros meses excluyen.
--
-- Junio, ademas, se comparo ARTICULO POR ARTICULO y CLIENTE POR CLIENTE:
--   * clientes: 141 de 141, la cadena entera identica.
--   * articulos: 183 de 196 iguales. Los 13 restantes:
--       - 9 son codigos administrativos (P25%, DTOSUPER, DEVERRORFC...) que ya
--         estan en sales_excluded_items. Suman -204 y explican la diferencia
--         total al entero (16.421 + 204 = 16.625).
--       - 256 / 256ZZ: ISIS los separa, el Excel los neteo. Da cero igual.
--       - 580 / 580E: el EXCEL los fundio en 580=42; ISIS los distingue
--         (580=2, 580E=40). Punto a favor de ISIS.
-- ---------------------------------------------------------------------------

-- Totales por mes en ISIS (correr en VIRGILIO):
select to_char(d.fecha,'YYYY-MM') mes,
       round(sum(case when d.tipo ~* '^NC' then -1 else 1 end * i.cantidad_caja))::int con_nc,
       round(sum(i.cantidad_caja) filter (where d.tipo !~* '^NC'))::int solo_fc
  from isis_lk.documentos d
  join isis_lk.documento_items i on i.documento_id = d.id
 where d.contraparte_tipo = 'cliente'
   and i.codigo_articulo is not null
   and upper(btrim(i.codigo_articulo)) not in (
     'DEVERRORFC','DTOSUPER','DTOXVOL','P10%','P15%','P20%','P23.5%','P25%','P5%',
     '1101','COTIZ-2%','PAGO-15%','PAGO-16%','PAGO-20%','PAGO-24%','PAGO-25%','PAGO-30%')
 group by 1 order by 1;

-- El mismo mes en LK:  select import_batch, sum(boxes) from public.sales_lines group by 1;

-- ---------------------------------------------------------------------------
-- 2) Los 560 "archivos con error" NO son ventas.
--      419 son facturas de COMPRA ("FC Compra A LOEKEMEY_...")
--      141 son ajustes ("Aj.Negativo_", "Aj.Positivo_") que pdftotext no leyo
--        0 son facturas de venta
--    Chef tiene 1 error sobre 8.446.
-- ---------------------------------------------------------------------------
select count(*) total,
       count(*) filter (where archivo_nombre ilike '%Compra%') compras,
       count(*) filter (where archivo_nombre ilike 'Aj.%')     ajustes,
       count(*) filter (where archivo_nombre not ilike '%Compra%'
                          and archivo_nombre not ilike 'Aj.%')  ventas
  from isis_lk.ingesta_log where estado = 'error';

-- ---------------------------------------------------------------------------
-- 3) Las lineas sin codigo de articulo son texto legal, no mercaderia.
--    3.035 de 33.938 en 2026, TODAS con 0 cajas y 0 importe:
--    "2% Descuento Web", "Incluye 2% Cotizador", "Pequenos Contribuyentes de la
--    Ley 27.618", "El credito fiscal discriminado...", "Mercaderia de
--    devolucion". Se filtran con `i.codigo_articulo is not null`.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 4) ⚠ EL LIMITE: el historico viejo NO cierra.
--
--  anio | ISIS    | sales_lines | dif
--  -----|---------|-------------|---------------
--  2020 | 107.587 | 107.523     | +0,06 %
--  2021 | 169.302 | 164.767     | +2,8 %
--  2022 | 155.015 | 154.948     | +0,04 %
--  2023 | 142.586 | 143.648     | -0,7 %
--  2024 | 116.886 | 125.954     | -7,2 %   <-- disperso en todos los meses
--  2025 | 190.777 | 202.819     | -5,9 %   <-- idem
--  2026 | 154.111 | 154.699     | -0,4 %
--
-- Por que: la ingesta de ISIS arranco el 2026-07-03. Todo lo anterior entro de
-- una, leyendo los PDF que habia en disco — los meses recientes estaban
-- completos, los de 2024/2025 no. Las diferencias van para los dos lados
-- (2024-05 ISIS -26 %, 2025-04 ISIS +25 %), o sea ruido, no un agujero limpio.
--
-- CONSECUENCIA: el corte va en 2026-02. De ahi para adelante ISIS cierra al
-- entero; para atras se deja lo que ya esta cargado y no se toca.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 5) El mapeo, confirmado campo por campo
--      invoice_date   <- d.fecha
--      customer_code  <- btrim(d.contraparte_codigo)     (formato identico: junio dio 141 de 141)
--      item_code      <- btrim(i.codigo_articulo)        (zero-padded igual que products.cod)
--      boxes          <- i.cantidad_caja, en negativo si d.tipo empieza con NC
--      empresa        <- el esquema: isis_lk = 'lk', isis_ch = 'chef'
--    Filtros: d.contraparte_tipo = 'cliente' (hay 195 docs de proveedor y 209
--    sin tipo) · i.codigo_articulo is not null · sales_excluded_items.
-- ---------------------------------------------------------------------------
