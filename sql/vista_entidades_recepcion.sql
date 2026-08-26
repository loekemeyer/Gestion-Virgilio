-- =====================================================================
--  vista_entidades_recepcion.sql — entidades que se reciben en Recepción
--
--  La usa el módulo de Recepción (recepcion.js) para armar dos listas:
--    · tipo='tallerista' → talleristas que fabrican piezas (de "Codigos X Tallerista").
--    · tipo='prov_at'    → proveedores de artículos terminados (de "Tall_ProvAT_PS",
--                          filtrados prov_at=true AND rec_virg=true AND activo=true).
--
--  v11.75 — FIX MEZCLA TALLERISTA/PROV_AT.
--    Problema: 9 entidades (Cabral, Carriero, Lopez Jose, Manfer, Maspoli, Melinox,
--    Paternal Goma, Pintos, The Plast) existían en las DOS tablas fuente, así que la
--    vista las devolvía DUPLICADAS — una vez como tallerista y otra como prov_at.
--    Estas 9 entregan como PROV AT, no como tallerista (ej. Cabral entrega el Filtro
--    de Café 031 de forma eventual; el proveedor principal de ese artículo es Poly).
--    Fix: la mitad TALLERISTA agrega un NOT EXISTS que excluye a cualquier nombre que
--    sea Prov AT activo. Se auto-mantiene: si se marca/desmarca prov_at en Tall_ProvAT_PS,
--    la entidad sale/entra de la lista de talleristas sin tocar código ni datos.
--    Los datos quedan intactos (no se borró nada de "Codigos X Tallerista" ni de
--    "Articulos Virgilio X Tallerista"; de hecho una FK impide borrarlos).
--
--  La definición viva está en la migración homónima en Supabase; este archivo es la
--  documentación del diseño (convención de sql/).
-- =====================================================================

CREATE OR REPLACE VIEW vista_entidades_recepcion AS
 SELECT 'tallerista'::text AS tipo,
    "Codigos X Tallerista"."Nombre" AS nombre,
    max(
        CASE
            WHEN upper(TRIM(BOTH FROM COALESCE("Codigos X Tallerista"."Linea", ''::character varying))) = 'LK'::text THEN "Codigos X Tallerista"."Codigo"
            ELSE NULL::text
        END) AS cod_lk,
    max(
        CASE
            WHEN upper(TRIM(BOTH FROM COALESCE("Codigos X Tallerista"."Linea", ''::character varying))) = 'CH'::text THEN "Codigos X Tallerista"."Codigo"
            ELSE NULL::text
        END) AS cod_ch,
    max(
        CASE
            WHEN upper(TRIM(BOTH FROM COALESCE("Codigos X Tallerista"."Linea", ''::character varying))) <> ALL (ARRAY['LK'::text, 'CH'::text]) THEN "Codigos X Tallerista"."Codigo"
            ELSE NULL::text
        END) AS cod_default,
    NULL::text AS cod_factura
   FROM "Codigos X Tallerista"
  WHERE "Codigos X Tallerista"."Nombre" IS NOT NULL AND TRIM(BOTH FROM "Codigos X Tallerista"."Nombre") <> ''::text
    -- v11.75: excluir de la lista de talleristas a los que son Prov AT activo
    AND NOT (EXISTS ( SELECT 1
           FROM "Tall_ProvAT_PS" t
          WHERE t.nombre = "Codigos X Tallerista"."Nombre" AND t.prov_at = true AND t.rec_virg = true AND t.activo = true))
  GROUP BY "Codigos X Tallerista"."Nombre"
UNION ALL
 SELECT 'prov_at'::text AS tipo,
    "Tall_ProvAT_PS".nombre,
    NULL::text AS cod_lk,
    NULL::text AS cod_ch,
    NULL::text AS cod_default,
    "Tall_ProvAT_PS".cod_factura
   FROM "Tall_ProvAT_PS"
  WHERE "Tall_ProvAT_PS".prov_at = true AND "Tall_ProvAT_PS".rec_virg = true AND "Tall_ProvAT_PS".activo = true AND "Tall_ProvAT_PS".nombre IS NOT NULL AND TRIM(BOTH FROM "Tall_ProvAT_PS".nombre) <> ''::text
  ORDER BY 2;
