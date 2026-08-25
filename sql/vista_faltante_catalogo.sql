-- vista_faltante_catalogo
-- 1 fila por artículo: stock neto/bruto, proveedor (P1/P2), discontinuo,
-- última entrega, OC pendiente (solo la más reciente por código), notas.
--
-- Fix 2026-08-25: oc_pend ahora usa ROW_NUMBER() para mostrar solo la última
-- OC pendiente por código, en vez de sumar todas (bug: 590E mostraba 207 en
-- vez de 59).

CREATE OR REPLACE VIEW public.vista_faltante_catalogo AS
WITH saldos AS (
    SELECT norm_cod(cod_art) AS cod,
        max(descripcion) AS descripcion,
        sum(COALESCE(terminado, 0) + COALESCE(excedente, 0) + COALESCE(a_guardar, 0)
            + COALESCE(racks, 0) + COALESCE(racks_ch, 0) + COALESCE(para_envasar, 0)) AS stock_neto,
        sum(COALESCE(terminado, 0) + COALESCE(excedente, 0) + COALESCE(a_guardar, 0)
            + COALESCE(racks, 0) + COALESCE(racks_ch, 0) + COALESCE(para_envasar, 0)
            + COALESCE(separar_pedidos, 0) + COALESCE(a_facturar, 0)) AS stock_bruto
    FROM vista_saldos_stock
    GROUP BY norm_cod(cod_art)
),
provs AS (
    SELECT norm_cod(cod) AS cod,
        CASE
            WHEN NOT tiene_prov_real
                 OR TRIM(COALESCE(proveedor, '')) = '(sin proveedor)' THEN ''
            ELSE TRIM(COALESCE(proveedor, ''))
        END AS p1,
        CASE
            WHEN COALESCE(pr2, 0) > 0
                 AND TRIM(COALESCE(proveedor2, '')) <> ''
                 AND TRIM(COALESCE(proveedor2, '')) <> '(sin proveedor)' THEN TRIM(proveedor2)
            ELSE ''
        END AS p2
    FROM vista_generador_oc
    WHERE activo = true
),
prov_final AS (
    SELECT cod,
        CASE
            WHEN p1 <> '' AND p2 <> '' THEN p1 || ' / ' || p2
            WHEN p2 <> '' THEN p2
            ELSE p1
        END AS proveedor
    FROM provs
),
discont AS (
    SELECT DISTINCT norm_cod(cod) AS cod
    FROM "OC_Maximos"
    WHERE activo = false
),
ult_ent_raw AS (
    SELECT norm_cod(cod_art) AS cod,
        left(ts::text, 10) AS dia,
        delta AS cajas
    FROM "Movimientos_Stock"
    WHERE tipo = 'recepcion' AND deposito = 'a_guardar' AND delta > 0
),
ult_ent AS (
    SELECT x.cod, x.dia AS fecha, sum(x.cajas) AS cajas
    FROM (
        SELECT cod, dia, cajas,
            rank() OVER (PARTITION BY cod ORDER BY dia DESC) AS rn
        FROM ult_ent_raw
    ) x
    WHERE x.rn = 1
    GROUP BY x.cod, x.dia
),
-- Solo la OC pendiente más reciente por código (ROW_NUMBER, no SUM)
oc_pend AS (
    SELECT cod, cajas, fecha, prov
    FROM (
        SELECT norm_cod(codigo) AS cod,
            COALESCE(cantidad::numeric, 0) - COALESCE(cantidad_recibida::numeric, 0) AS cajas,
            left(fecha::text, 10) AS fecha,
            TRIM(COALESCE(proveedor, '')) AS prov,
            ROW_NUMBER() OVER (PARTITION BY norm_cod(codigo) ORDER BY fecha DESC, id DESC) AS rn
        FROM "Ordenes_Compra"
        WHERE estado = 'pendiente'
          AND (COALESCE(cantidad::numeric, 0) - COALESCE(cantidad_recibida::numeric, 0)) > 0
    ) ranked
    WHERE rn = 1
),
notas AS (
    SELECT TRIM(cod) AS cod,
        COALESCE(dia_resolucion, '') AS dia,
        COALESCE(motivo, '') AS motivo
    FROM "Faltantes_Notas"
)
SELECT COALESCE(s.cod, pf.cod) AS cod,
    COALESCE(s.descripcion, '') AS descripcion,
    COALESCE(s.stock_neto, 0) AS stock_neto,
    COALESCE(s.stock_bruto, 0) AS stock_bruto,
    COALESCE(pf.proveedor, '') AS proveedor,
    d.cod IS NOT NULL AS discontinuo,
    COALESCE(ue.fecha, '') AS ult_entrega_fecha,
    COALESCE(ue.cajas, 0) AS ult_entrega_cajas,
    COALESCE(op.cajas, 0) AS oc_pend_cajas,
    COALESCE(op.fecha, '') AS oc_pend_fecha,
    COALESCE(op.prov, '') AS oc_pend_prov,
    COALESCE(n.dia, '') AS nota_dia,
    COALESCE(n.motivo, '') AS nota_motivo
FROM saldos s
    FULL JOIN prov_final pf ON pf.cod = s.cod
    LEFT JOIN discont d ON d.cod = COALESCE(s.cod, pf.cod)
    LEFT JOIN ult_ent ue ON ue.cod = COALESCE(s.cod, pf.cod)
    LEFT JOIN oc_pend op ON op.cod = COALESCE(s.cod, pf.cod)
    LEFT JOIN notas n ON n.cod = COALESCE(s.cod, pf.cod);
