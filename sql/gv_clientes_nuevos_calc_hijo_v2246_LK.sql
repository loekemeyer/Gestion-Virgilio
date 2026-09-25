-- v22.46 (Luis, 2026-09-25) — PROYECTO LK (kwkclwhmoygunqmlegrg), no Virgilio.
-- "Si un cliente nuevo hace un pedido con importados sin stock y se parte en dos pedidos para la
-- programación, es UN solo pedido para el límite de los 3 primeros pedidos."
--
-- gv_clientes_nuevos_calc cuenta pedidos = fechas de factura distintas (sales_lines). La parte
-- diferida de un pedido partido (sheets_payload.pedido_origen, LK en orders y Chef en
-- chef_orders_cache) se factura DESPUÉS, cuando entra la mercadería: sumaba una fecha más.
-- Ahora una fecha de factura NO cuenta si TODO lo que se facturó ese día son artículos de una parte
-- diferida de ese cliente (creada ese día o antes). Si el mismo día salió además otro pedido,
-- la fecha cuenta igual: ahí hubo un pedido de verdad.
-- Sin link factura↔pedido en LK: por eso el criterio es por artículos, conservador.
create or replace view public.gv_clientes_nuevos_calc as
 WITH RECURSIVE base AS (
         SELECT 'lk'::text AS empresa,
            c_1.cod_cliente::text AS cod,
            NULLIF(regexp_replace(COALESCE(c_1.cuit, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) AS cuit,
            c_1.business_name AS rs
           FROM customers c_1
        UNION ALL
         SELECT 'chef'::text AS text,
            btrim(p.cod_cliente) AS btrim,
            NULLIF(regexp_replace(COALESCE(p.cuit, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) AS "nullif",
            p.business_name
           FROM chef_padron p
        ), nodo AS (
         SELECT base.empresa, base.cod, max(base.cuit) AS cuit, max(base.rs) AS rs
           FROM base
          WHERE base.cod ~ '^\d+$'::text
          GROUP BY base.empresa, base.cod
        ), arista AS MATERIALIZED (
         SELECT a_1.empresa AS e1, a_1.cod AS c1, b.empresa AS e2, b.cod AS c2
           FROM nodo a_1
             JOIN nodo b ON a_1.cuit = b.cuit AND length(a_1.cuit) = 11 AND (a_1.empresa <> b.empresa OR a_1.cod <> b.cod)
        UNION
         SELECT g1.empresa, g1.cod_cliente, g2.empresa, g2.cod_cliente
           FROM customer_grupos g1
             JOIN customer_grupos g2 ON g1.grupo_id = g2.grupo_id AND g1.empresa = g2.empresa AND g1.cod_cliente <> g2.cod_cliente
        UNION
         SELECT l1.empresa, l1.cod_cliente, l2.empresa, l2.cod_cliente
           FROM clientes_lk_ch_links l1
             JOIN clientes_lk_ch_links l2 ON l1.link_id = l2.link_id AND (l1.empresa <> l2.empresa OR l1.cod_cliente <> l2.cod_cliente)
        UNION
         SELECT v1.empresa, v1.cod, v2.empresa, v2.cod
           FROM clientes_vinculados v1
             JOIN clientes_vinculados v2 ON v2.grupo = v1.grupo AND (v1.empresa <> v2.empresa OR v1.cod <> v2.cod)
        ), alto AS (
         SELECT nodo.empresa, nodo.cod, nodo.rs
           FROM nodo
          WHERE nodo.cod::bigint >= CASE WHEN nodo.empresa = 'lk'::text THEN 3800 ELSE 2300 END
        ), alcance AS (
         SELECT a_1.empresa, a_1.cod, a_1.empresa AS m_emp, a_1.cod AS m_cod
           FROM alto a_1
        UNION
         SELECT al.empresa, al.cod, ar.e2, ar.c2
           FROM alcance al
             JOIN arista ar ON ar.e1 = al.m_emp AND ar.c1 = al.m_cod
        ), hijo_it AS MATERIALIZED (
         -- v22.46: artículos de las partes diferidas (pedido_origen), LK y Chef
         SELECT 'lk'::text AS emp, btrim(o.customer_code) AS cod,
                to_char(o.created_at AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD') AS f,  -- invoice_date es TEXTO ISO
                upper(btrim(COALESCE(p.cod, lp.cod))) AS item
           FROM orders o
             JOIN order_items oi ON oi.order_id = o.id
             LEFT JOIN products p ON p.id = oi.product_id
             LEFT JOIN loke_products lp ON lp.id = oi.loke_product_id
          WHERE o.sheets_payload ? 'pedido_origen'
        UNION ALL
         SELECT 'chef'::text,
                btrim(COALESCE(NULLIF(c.sheets_payload ->> 'cod_cliente', ''), cc.cod_cliente::text)),
                to_char(c.created_at AT TIME ZONE 'America/Argentina/Buenos_Aires', 'YYYY-MM-DD'),
                upper(btrim(i.value ->> 'cod_art'))
           FROM chef_orders_cache c
             LEFT JOIN chef_customers_cache cc ON cc.id = c.customer_id  -- la copia LOCAL: chef_customers es FDW (+2 s)
             CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(c.sheets_payload -> 'items') = 'array'
                                                          THEN c.sheets_payload -> 'items' ELSE '[]'::jsonb END) i(value)
          WHERE c.sheets_payload ? 'pedido_origen'
        ), fecha_hijo AS MATERIALIZED (
         SELECT hc.emp, s.customer_code AS cod, s.invoice_date AS d
           FROM (SELECT DISTINCT hijo_it.emp, hijo_it.cod FROM hijo_it) hc
             JOIN sales_lines s ON s.customer_code = hc.cod AND lower(s.empresa) = hc.emp
          WHERE s.boxes > 0
          GROUP BY 1, 2, 3
         HAVING bool_and(EXISTS (SELECT 1 FROM hijo_it h
                                  WHERE h.emp = hc.emp AND h.cod = s.customer_code
                                    AND h.item = upper(btrim(s.item_code)) AND h.f <= s.invoice_date))
        ), cnt AS (
         SELECT al.empresa, al.cod,
            count(DISTINCT ROW(s.empresa, s.invoice_date)) AS pedidos,
            count(*) FILTER (WHERE s.customer_code IS NOT NULL) AS lineas,
            count(DISTINCT ROW(al.m_emp, al.m_cod)) AS codigos
           FROM alcance al
             LEFT JOIN sales_lines s ON s.customer_code = al.m_cod AND lower(s.empresa) = al.m_emp AND s.boxes > 0
                   AND NOT (s.item_code IN (SELECT sales_excluded_items.item_code FROM sales_excluded_items))
          GROUP BY al.empresa, al.cod
        ), corr AS (
         -- el cnt de siempre queda igual (mismo plan, ~600 ms); aparte se restan las fechas que
         -- son SOLO de una parte diferida. Unirlo adentro del cnt lo llevaba a 3-6 s.
         SELECT al.empresa, al.cod, count(DISTINCT ROW(fh.emp, fh.d)) AS n
           FROM alcance al
             JOIN fecha_hijo fh ON fh.emp = al.m_emp AND fh.cod = al.m_cod
          GROUP BY al.empresa, al.cod
        )
 SELECT c.empresa, c.cod, a.rs AS razon_social, c.pedidos - COALESCE(k.n, 0) AS pedidos, c.codigos,
    (c.pedidos - COALESCE(k.n, 0)) < 3 AS es_nuevo
   FROM cnt c
     JOIN alto a ON a.empresa = c.empresa AND a.cod = c.cod
     LEFT JOIN corr k ON k.empresa = c.empresa AND k.cod = c.cod;
-- CREATE OR REPLACE VIEW borra las reloptions: se repone.
alter view public.gv_clientes_nuevos_calc set (security_invoker = true);
