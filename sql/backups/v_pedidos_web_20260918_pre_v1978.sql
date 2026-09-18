-- Backup de public.v_pedidos_web (proyecto LK kwkclwhmoygunqmlegrg) tomado el 2026-09-18
-- ANTES de la v19.78 (sql/gv_web_sucursal_match_v1978.sql, problema 418).
-- ROLLBACK: ejecutar este archivo entero contra LK. No toca datos, sólo la definición.
create or replace view public.v_pedidos_web as
 WITH base AS (
         SELECT o.id AS order_id,
            o.created_at,
            o.sheets_payload,
            o.enviado_a_compras_at,
            COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text) AS cod_cliente,
            c.business_name AS razon_social,
            c.cuit,
            COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text) AS sucursal_entrega,
            dir.localidad,
            dir.provincia,
            dir.zona_expreso,
            dir.nombre_expreso,
            dir.direccion_expreso,
            COALESCE(ov.isis_empresa,
                CASE
                    WHEN COALESCE(dir.provincia, ''::text) ~~* '%tierra del fuego%'::text THEN 'chef'::text
                    ELSE 'lk'::text
                END) AS isis_empresa
           FROM orders o
             LEFT JOIN customers c ON c.cod_cliente::text = COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text)
             LEFT JOIN gv_isis_override ov ON ov.cuit = regexp_replace(COALESCE(c.cuit, ''::text), '\D'::text, ''::text, 'g'::text)
             LEFT JOIN LATERAL ( SELECT d.localidad,
                    d.provincia,
                    d.zona_expreso,
                    d.nombre_expreso,
                    d.direccion_expreso
                   FROM customer_delivery_addresses d
                  WHERE d.customer_id = c.id AND btrim(lower(d.label)) = btrim(lower(COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text)))
                  ORDER BY (btrim(COALESCE(d.zona_expreso, ''::text)) <> ''::text) DESC, d.slot
                 LIMIT 1) dir ON true
          WHERE o.sheets_payload IS NOT NULL AND jsonb_typeof(o.sheets_payload -> 'items'::text) = 'array'::text
        )
 SELECT 'lk'::text AS empresa,
    b.order_id,
    it.ord::integer AS linea_rn,
    b.cod_cliente,
    b.razon_social,
    (b.created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'::text)::date AS fecha_pedido,
    to_char((b.created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'::text), 'HH24:MI:SS'::text) AS hora_pedido,
    b.created_at,
    b.sucursal_entrega,
    b.sheets_payload ->> 'vend'::text AS vend,
    COALESCE(b.sheets_payload ->> 'condicion_pago_code'::text, b.sheets_payload ->> 'condicionPagoCode'::text) AS condicion_pago_code,
    COALESCE(b.sheets_payload ->> 'numOC'::text, b.sheets_payload ->> 'numero_oc'::text, b.sheets_payload ->> 'numeroOC'::text) AS numero_oc,
    b.sheets_payload ->> 'observaciones'::text AS observaciones,
    (
        CASE
            WHEN char_length((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]) < 3 THEN lpad((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1], 3, '0'::text)
            ELSE (regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]
        END || COALESCE((regexp_match(it.value ->> 'cod_art'::text, '[a-zA-Z]+'::text))[1], ''::text)) ||
        CASE
            WHEN b.isis_empresa = 'chef'::text AND (
            CASE
                WHEN char_length((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]) < 3 THEN lpad((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1], 3, '0'::text)
                ELSE (regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]
            END || COALESCE((regexp_match(it.value ->> 'cod_art'::text, '[a-zA-Z]+'::text))[1], ''::text)) !~* 'L$'::text THEN 'L'::text
            ELSE ''::text
        END AS art,
    NULLIF(COALESCE(it.value ->> 'cajas'::text, it.value ->> 'Cajas'::text), ''::text)::numeric AS cajas,
    NULLIF(it.value ->> 'uxb'::text, ''::text)::numeric AS uxb,
    COALESCE(NULLIF(it.value ->> 'cajas'::text, ''::text), '0'::text)::numeric * COALESCE(NULLIF(it.value ->> 'uxb'::text, ''::text), '0'::text)::numeric AS uni,
    b.enviado_a_compras_at,
    b.localidad,
    b.provincia,
    NULLIF(btrim(b.zona_expreso), ''::text) AS zona_expreso,
    NULLIF(btrim(b.nombre_expreso), ''::text) AS nombre_expreso,
    NULLIF(btrim(b.direccion_expreso), ''::text) AS direccion_expreso,
    b.isis_empresa,
        CASE
            WHEN b.isis_empresa = 'chef'::text THEN ( SELECT p.cod_cliente
               FROM chef_padron p
              WHERE NULLIF(regexp_replace(COALESCE(p.cuit, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) IS NOT NULL AND regexp_replace(COALESCE(p.cuit, ''::text), '\D'::text, ''::text, 'g'::text) = regexp_replace(COALESCE(b.cuit, ''::text), '\D'::text, ''::text, 'g'::text)
              ORDER BY p.cod_cliente
             LIMIT 1)
            ELSE b.cod_cliente
        END AS cod_isis
   FROM base b
     CROSS JOIN LATERAL jsonb_array_elements(b.sheets_payload -> 'items'::text) WITH ORDINALITY it(value, ord)
  WHERE (it.value ->> 'cod_art'::text) ~ '\d'::text;
alter view public.v_pedidos_web set (security_invoker = true);
