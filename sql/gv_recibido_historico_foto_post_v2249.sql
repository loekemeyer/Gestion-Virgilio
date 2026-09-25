-- v22.49 (Luis, 25/09): "Recibió" en el Histórico de recepción + foto agregada a posteriori.
alter table public."Control_Modo_OP" add column if not exists gv_foto_post_por text,
                                     add column if not exists gv_foto_post_at timestamptz;

create or replace view public.vista_historial_entregas with (security_invoker = true) as
 SELECT 'tallerista'::text AS fuente,
    gv_fecha_recepcion_norm(t."Fecha") AS fecha,
    t.created_at,
    t."Cod" AS cod_art,
    ''::text AS descripcion,
    t."Cajas"::numeric AS cajas,
    t."Nombre_Tall" AS quien,
    t."Remito" AS remito,
    cmo.llegada,
    cmo.carga,
        CASE
            WHEN cmo.llegada IS NOT NULL AND cmo.carga IS NOT NULL THEN round(EXTRACT(epoch FROM cmo.carga - cmo.llegada) / 3600.0, 2)
            ELSE NULL::numeric
        END AS demora_hs,
    cmo.recibido_por,
    cmo.recibido_at
   FROM "Entregas Tallerista Virgilio" t
     LEFT JOIN LATERAL ( SELECT c.created_at AS llegada,
            c.procesado_at AS carga,
            c.gv_recibido_por AS recibido_por,
            c.gv_recibido_at AS recibido_at
           FROM "Control_Modo_OP" c
          WHERE c.estado = 'procesado'::text AND c.procesado_at IS NOT NULL AND NULLIF(btrim(c.remito), ''::text) = NULLIF(btrim(t."Remito"), ''::text) AND lower(btrim(c.nombre)) = lower(btrim(t."Nombre_Tall"))
          ORDER BY c.procesado_at DESC
         LIMIT 1) cmo ON true
UNION ALL
 SELECT 'prov_at'::text AS fuente,
    gv_fecha_recepcion_norm(p."Dia_mes") AS fecha,
    NULL::timestamp with time zone AS created_at,
    p."Cod_Art" AS cod_art,
    COALESCE(p."Descripcion", ''::text) AS descripcion,
    p."Cantidad"::numeric AS cajas,
    p."Proveedor" AS quien,
    p."Remito" AS remito,
    cmo.llegada,
    cmo.carga,
        CASE
            WHEN cmo.llegada IS NOT NULL AND cmo.carga IS NOT NULL THEN round(EXTRACT(epoch FROM cmo.carga - cmo.llegada) / 3600.0, 2)
            ELSE NULL::numeric
        END AS demora_hs,
    cmo.recibido_por,
    cmo.recibido_at
   FROM "Entregas Prov AT" p
     LEFT JOIN LATERAL ( SELECT c.created_at AS llegada,
            c.procesado_at AS carga,
            c.gv_recibido_por AS recibido_por,
            c.gv_recibido_at AS recibido_at
           FROM "Control_Modo_OP" c
          WHERE c.estado = 'procesado'::text AND c.procesado_at IS NOT NULL AND NULLIF(btrim(c.remito), ''::text) = NULLIF(btrim(p."Remito"), ''::text) AND lower(btrim(c.nombre)) = lower(btrim(p."Proveedor"))
          ORDER BY c.procesado_at DESC
         LIMIT 1) cmo ON true;
alter view public.vista_historial_entregas set (security_invoker = true);
