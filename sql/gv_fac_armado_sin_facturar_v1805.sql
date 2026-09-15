-- v18.05 — `gv_fac_armado_sin_facturar`: la misma exclusión para el lado WEB
--
-- El centinela de facturación ("se armó y no está facturado") excluía `NP_Canceladas`, o sea que
-- una NP de ISIS anulada / cancelada / desarmada salía sola. El lado **web** no tenía
-- equivalente: su marca vive en `GV_Web_Cancelados`, que esta vista no miraba. Asimetría, no
-- decisión: el mismo hecho contado distinto según de dónde venga el pedido.
--
-- Hoy no cambia ninguna fila (no hay ningún pedido web cancelado CON entregas), pero el día que
-- se desarme un pedido web armado —`gv_ppp_np_desarmar` escribe en `GV_Web_Cancelados`— iba a
-- quedar colgado acá como *"la NP está en la PPP pero sin tanda"*, que es exactamente lo que el
-- desarme le acababa de hacer.
--
-- CONTROL POSITIVO (en transacción revertida): marcando cancelado el pedido lk/1344, el centinela
-- pasó de **8 a 6 filas** y sus dos NP (LK 0007 y LK 0008) desaparecieron. Sin el control, "no
-- cambió nada" también sería el resultado de una condición que no hace nada.
--
-- ⚠⚠ `CREATE OR REPLACE VIEW` sin `WITH (...)` borra las reloptions y se come el
-- `security_invoker = true`. Por eso el `alter view` del final — ver la nota del CLAUDE.md.
--
-- ROLLBACK: sacar el último `AND NOT (EXISTS (… GV_Web_Cancelados …))` y volver a correr el
-- `alter view`.

create or replace view public.gv_fac_armado_sin_facturar as
 WITH ent AS (
         SELECT btrim(e_1.np) AS np,
            max(NULLIF(btrim(e_1.tanda), ''::text)) AS tanda_armado,
            max(NULLIF(btrim(e_1.fecha_salida), ''::text)) AS fecha_salida,
            sum(COALESCE(e_1.cajas_entregadas, 0::numeric)) AS cajas,
            max(NULLIF(btrim(e_1.cod_cliente), ''::text)) AS cod
           FROM "Entregas_Virgilio" e_1
          WHERE NULLIF(btrim(e_1.np), ''::text) IS NOT NULL
          GROUP BY (btrim(e_1.np))
        ), prog AS (
         SELECT btrim(d.np) AS np,
            NULLIF(btrim(d.tanda), ''::text) AS tanda,
            d.razon_social,
            'isis'::text AS origen,
            gv_empresa_de_np_texto(btrim(d.np)) AS empresa
           FROM gv_ppp_programacion_diaria d
          WHERE NULLIF(regexp_replace(COALESCE(d.np, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) IS NOT NULL
        UNION ALL
         SELECT gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) AS gv_ppp_web_np_label,
            NULLIF(btrim(w.tanda), ''::text) AS "nullif",
            w.razon_social,
            'web'::text AS text,
            w.empresa
           FROM "PPP_Web_Programacion" w
          WHERE w.np IS NOT NULL
        )
 SELECT e.np,
    COALESCE(p.origen, 'fuera de la PPP'::text) AS origen,
    e.cod,
    COALESCE(p.razon_social, f.razon_social, gv_fac_rs_np(e.np)) AS razon_social,
    e.tanda_armado,
    p.tanda AS tanda_ppp,
    e.fecha_salida,
    e.cajas,
    p.np IS NOT NULL AND p.tanda IS NOT NULL AS se_ve_en_facturacion,
        CASE
            WHEN p.np IS NULL THEN 'la NP no esta en la PPP'::text
            WHEN p.tanda IS NULL THEN 'la NP esta en la PPP pero sin tanda'::text
            ELSE NULL::text
        END AS por_que_no_se_ve,
    COALESCE(p.empresa, gv_empresa_de_np_texto(e.np)) AS empresa
   FROM ent e
     LEFT JOIN prog p ON p.np = e.np
     LEFT JOIN "Facturacion_NP" f ON btrim(f.np) = e.np
  WHERE NOT (EXISTS ( SELECT 1
           FROM "Facturacion_NP" fn
          WHERE btrim(fn.np) = e.np))
    AND NOT (EXISTS ( SELECT 1
           FROM "NP_Canceladas" c
          WHERE regexp_replace(btrim(c.np), '\.0+$'::text, ''::text) = regexp_replace(e.np, '\.0+$'::text, ''::text)))
    -- v18.05 (Luis) — la MISMA exclusion para el lado WEB (ver la cabecera).
    AND NOT (EXISTS ( SELECT 1
           FROM "GV_Web_Cancelados" wc
           JOIN "PPP_Web_Programacion" w2
             ON w2.empresa = wc.empresa AND w2.order_id = wc.order_id
          WHERE gv_ppp_web_np_label(w2.empresa, w2.np, w2.np_idx) = e.np));

-- ⚠ OBLIGATORIO despues de cualquier create or replace de esta vista (ver la cabecera)
alter view public.gv_fac_armado_sin_facturar set (security_invoker = true);
