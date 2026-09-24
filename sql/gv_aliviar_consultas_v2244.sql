-- v22.44 (Luis, 24/09): aliviar las 3 consultas que saturaban la base a las 11:49
-- (A Programar: gv_cuarentena_marcar / gv_ppp_web_dia_salida · Facturación: facturacion_neto_lote).
-- ⚠ PREPARADO EN BRANCH, NO APLICADO. Aplicarlo lo autoriza Luis.
--
-- Medido en transacción abortada (175 pedidos reales / 60 NP), salida IDÉNTICA (EXCEPT ALL 0/0):
--   gv_cuarentena_deuda_sucursal     1.127 ms ->   110 ms
--   gv_cuarentena_marcar_calc        1.019 ms ->   341 ms
--   gv_cuarentena_mismo_pedido_lote    782 ms ->   101 ms
--   gv_ppp_web_dia_salida            1.845 ms ->   566 ms
--   facturacion_neto_lote            1.452 ms ->   421 ms
--
-- CAUSA 1 (cuarentena y día de salida): gv_cuarentena_deuda_sucursal calculaba
-- gv_comprobante_key() sobre los ~41.000 comprobantes de isis_lk + isis_ch en CADA lectura
-- para cruzar 462 renglones de deuda (la función lleva SET search_path: no se inlinea, 2 regex
-- por fila). La leen mismo_pedido_lote -> marcar_calc -> retiene_lote -> dia_salida.
-- Arreglo: índice de EXPRESIÓN (la función es IMMUTABLE) + LEFT JOIN LATERAL por renglón.
--
-- CAUSA 2 (facturación): facturacion_neto_lote hacía JOIN contra vista_facturacion_neto_items,
-- que agrupa Entregas_Virgilio ENTERA (12.386 filas) antes de filtrar: un JOIN no baja por un
-- GROUP BY. Con `np = ANY(ARRAY(select …))` el filtro es un parámetro y SÍ baja.
--
-- Índices: aditivos sobre isis_lk/isis_ch.documentos (los escribe el parser de facturas).

create index if not exists gv_docs_lk_compkey_idx on isis_lk.documentos ((gv_comprobante_key(((CASE familia WHEN 'factura_venta'::text THEN 'FC'::text WHEN 'nc_venta'::text THEN 'NC'::text WHEN 'nd_venta'::text THEN 'ND'::text ELSE 'XX'::text END || COALESCE(letra, ''::text)) || lpad(regexp_replace(COALESCE(punto_venta, ''::text), '\D'::text, ''::text, 'g'::text), 4, '0'::text)) || lpad(regexp_replace(COALESCE(numero, ''::text), '\D'::text, ''::text, 'g'::text), 8, '0'::text)))) where familia = any (array['factura_venta'::text,'nc_venta'::text,'nd_venta'::text]);
create index if not exists gv_docs_ch_compkey_idx on isis_ch.documentos ((gv_comprobante_key(((CASE familia WHEN 'factura_venta'::text THEN 'FC'::text WHEN 'nc_venta'::text THEN 'NC'::text WHEN 'nd_venta'::text THEN 'ND'::text ELSE 'XX'::text END || COALESCE(letra, ''::text)) || lpad(regexp_replace(COALESCE(punto_venta, ''::text), '\D'::text, ''::text, 'g'::text), 4, '0'::text)) || lpad(regexp_replace(COALESCE(numero, ''::text), '\D'::text, ''::text, 'g'::text), 8, '0'::text)))) where familia = any (array['factura_venta'::text,'nc_venta'::text,'nd_venta'::text]);

-- La vista: mismas columnas, mismo orden, security_invoker conservado.
create or replace view public.gv_cuarentena_deuda_sucursal with (security_invoker = true) as
 WITH det AS (
         SELECT d_1.empresa, d_1.cod, d_1.razon_social, d_1.comprobante, d_1.pendiente, d_1.fila,
            gv_cuarentena_comp_key(d_1.fila, d_1.comprobante) AS ck
           FROM "GV_Cuarentena_Deuda_Detalle" d_1
        )
 SELECT d.empresa, d.cod, d.razon_social, d.comprobante, d.pendiente,
    doc.fecha AS fecha_comprobante, a.np, s.sucursal_entrega, s.direccion, s.dir_key, s.es_retira,
        CASE
            WHEN doc.doc_id IS NULL THEN 'sin factura parseada'::text
            WHEN a.np IS NULL THEN 'factura sin NP asignada'::text
            WHEN s.np IS NULL THEN 'NP sin sucursal registrada'::text
            ELSE 'ok'::text
        END AS estado_cadena,
    COALESCE(d.fila ->> 4, d.comprobante) AS tipo_comprobante,
    d.fila ->> 6 AS nro_comprobante
   FROM det d
     -- v22.44: lookup por índice de expresión (gv_docs_lk/ch_compkey_idx) en vez de calcular
     -- la clave de los ~41.000 comprobantes de ISIS en cada lectura.
     LEFT JOIN LATERAL (
         SELECT x.id AS doc_id, x.fecha FROM isis_lk.documentos x
          WHERE d.empresa = 'lk'
            AND x.familia = ANY (ARRAY['factura_venta'::text, 'nc_venta'::text, 'nd_venta'::text])
            AND gv_comprobante_key(((
                CASE x.familia WHEN 'factura_venta'::text THEN 'FC'::text WHEN 'nc_venta'::text THEN 'NC'::text
                    WHEN 'nd_venta'::text THEN 'ND'::text ELSE 'XX'::text END
                || COALESCE(x.letra, ''::text)) || lpad(regexp_replace(COALESCE(x.punto_venta, ''::text), '\D'::text, ''::text, 'g'::text), 4, '0'::text))
                || lpad(regexp_replace(COALESCE(x.numero, ''::text), '\D'::text, ''::text, 'g'::text), 8, '0'::text)) = d.ck
         UNION ALL
         SELECT x.id, x.fecha FROM isis_ch.documentos x
          WHERE d.empresa = 'chef'
            AND x.familia = ANY (ARRAY['factura_venta'::text, 'nc_venta'::text, 'nd_venta'::text])
            AND gv_comprobante_key(((
                CASE x.familia WHEN 'factura_venta'::text THEN 'FC'::text WHEN 'nc_venta'::text THEN 'NC'::text
                    WHEN 'nd_venta'::text THEN 'ND'::text ELSE 'XX'::text END
                || COALESCE(x.letra, ''::text)) || lpad(regexp_replace(COALESCE(x.punto_venta, ''::text), '\D'::text, ''::text, 'g'::text), 4, '0'::text))
                || lpad(regexp_replace(COALESCE(x.numero, ''::text), '\D'::text, ''::text, 'g'::text), 8, '0'::text)) = d.ck
     ) doc ON true
     LEFT JOIN "GV_Cruce_FC_Asig" a ON a.doc_id = doc.doc_id
     LEFT JOIN "GV_NP_Sucursal" s ON s.empresa = d.empresa AND s.np = a.np;

alter view public.gv_cuarentena_deuda_sucursal set (security_invoker = true);

-- facturacion_neto_lote: parche sobre la definición VIVA, idempotente.
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.facturacion_neto_lote(text[])'::regprocedure);
  if d like '%v22.44-fneto%' then raise notice 'ya aplicado'; return; end if;
  n := replace(d, '  JOIN want w ON w.np = i.np' || chr(10),
    '  -- v22.44-fneto: filtro como parametro (baja por el GROUP BY de la vista; un JOIN no baja)' || chr(10) ||
    '  WHERE i.np = ANY (ARRAY(SELECT w.np FROM want w))' || chr(10));
  if n = d then raise exception 'facturacion_neto_lote: el texto no matchea, traer la viva y revisar'; end if;
  execute n;
end $p$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_cuarentena_deuda_sucursal','vista','LEFT JOIN LATERAL','la deuda busca su comprobante por índice, no recalcula la clave de los 41.000 de ISIS','Luis','v22.44'),
 ('facturacion_neto_lote','funcion','ANY \(ARRAY\(SELECT w\.np','el filtro de NP baja por el GROUP BY de la vista (un JOIN no baja)','Luis','v22.44');

-- Chequeo:
--   select * from public.gv_reglas_perdidas;            -- vacía
--   select estado_cadena, count(*) from public.gv_cuarentena_deuda_sucursal group by 1;
--
-- ROLLBACK:
--   drop index if exists isis_lk.gv_docs_lk_compkey_idx; drop index if exists isis_ch.gv_docs_ch_compkey_idx;
--   (la vista vieja: CTE doc con UNION ALL de isis_lk/isis_ch calculando gv_comprobante_key por fila
--    y LEFT JOIN doc ON doc.empresa = d.empresa AND doc.comp_key = d.ck — ver pg_get_viewdef en git
--    history de este archivo / docs/SUPABASE-GESTION-VIRGILIO.md)
--   facturacion_neto_lote: volver `WHERE i.np = ANY(...)` a `JOIN want w ON w.np = i.np`.

/* ROLLBACK de la vista (definición viva al 24/09, antes de v22.44):
create or replace view public.gv_cuarentena_deuda_sucursal with (security_invoker = true) as
 WITH doc AS (
   SELECT 'lk'::text AS empresa, d_1.id AS doc_id,
     gv_comprobante_key((((CASE d_1.familia WHEN 'factura_venta'::text THEN 'FC'::text WHEN 'nc_venta'::text THEN 'NC'::text
       WHEN 'nd_venta'::text THEN 'ND'::text ELSE 'XX'::text END || COALESCE(d_1.letra, ''::text))
       || lpad(regexp_replace(COALESCE(d_1.punto_venta, ''::text), '\D'::text, ''::text, 'g'::text), 4, '0'::text))
       || lpad(regexp_replace(COALESCE(d_1.numero, ''::text), '\D'::text, ''::text, 'g'::text), 8, '0'::text))) AS comp_key,
     d_1.fecha, d_1.total
   FROM isis_lk.documentos d_1 WHERE d_1.familia = ANY (ARRAY['factura_venta'::text, 'nc_venta'::text, 'nd_venta'::text])
   UNION ALL
   SELECT 'chef'::text, d_1.id,
     gv_comprobante_key((((CASE d_1.familia WHEN 'factura_venta'::text THEN 'FC'::text WHEN 'nc_venta'::text THEN 'NC'::text
       WHEN 'nd_venta'::text THEN 'ND'::text ELSE 'XX'::text END || COALESCE(d_1.letra, ''::text))
       || lpad(regexp_replace(COALESCE(d_1.punto_venta, ''::text), '\D'::text, ''::text, 'g'::text), 4, '0'::text))
       || lpad(regexp_replace(COALESCE(d_1.numero, ''::text), '\D'::text, ''::text, 'g'::text), 8, '0'::text))),
     d_1.fecha, d_1.total
   FROM isis_ch.documentos d_1 WHERE d_1.familia = ANY (ARRAY['factura_venta'::text, 'nc_venta'::text, 'nd_venta'::text])
 ), det AS (
   SELECT d_1.id, d_1.empresa, d_1.cod, d_1.razon_social, d_1.comprobante, d_1.comp_key, d_1.pendiente, d_1.fila,
          d_1.lote, d_1.cargado_por, d_1.cargado_at, gv_cuarentena_comp_key(d_1.fila, d_1.comprobante) AS ck
   FROM "GV_Cuarentena_Deuda_Detalle" d_1
 )
 SELECT d.empresa, d.cod, d.razon_social, d.comprobante, d.pendiente, doc.fecha AS fecha_comprobante, a.np,
   s.sucursal_entrega, s.direccion, s.dir_key, s.es_retira,
   CASE WHEN doc.doc_id IS NULL THEN 'sin factura parseada'::text WHEN a.np IS NULL THEN 'factura sin NP asignada'::text
        WHEN s.np IS NULL THEN 'NP sin sucursal registrada'::text ELSE 'ok'::text END AS estado_cadena,
   COALESCE(d.fila ->> 4, d.comprobante) AS tipo_comprobante, d.fila ->> 6 AS nro_comprobante
 FROM det d
 LEFT JOIN doc ON doc.empresa = d.empresa AND doc.comp_key = d.ck
 LEFT JOIN "GV_Cruce_FC_Asig" a ON a.doc_id = doc.doc_id
 LEFT JOIN "GV_NP_Sucursal" s ON s.empresa = d.empresa AND s.np = a.np;
*/
