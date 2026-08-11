-- ============================================================
-- vista_nc_loeke_chef — checklist "NC a Loeke + pasar stock a Chef" (Facturación)
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- NPs de Chef (pedido < 90000) que piden un artículo importado por Chef pero "home Loeke"
-- (coladores 437E/438E/439E). Al facturarlos por Chef hay que hacer Nota de Crédito a Loeke
-- y pasar el stock. Se muestra como filas ✓ "NC hecha" en Facturación (facFetchNcChef).
--
-- v9.45/9.46 (dueño) — 437E, 438E y 439E hacen NC a Loeke SOLO si el pedido usa la variante
-- "...L" (ej. 437EL, el código de Loeke); el código PELADO NO. Antes la vista normalizaba
-- sacando la "L" final y agarraba también los pelados. El fix agrega, en el WHERE, que si el
-- base es 437E/438E/439E el artículo del pedido tenga que terminar en "L".
-- ============================================================

create or replace view public.vista_nc_loeke_chef as
 WITH chef_imp AS (
         SELECT DISTINCT ltrim(upper(btrim("Importados".cod_art)), '0'::text) AS base
           FROM "Importados"
          WHERE ("Importados".activo AND (btrim("Importados".proveedor) = ANY (ARRAY['Ownland'::text, 'Kangli'::text, 'Fujian'::text, 'Frontier'::text])))
        ), split AS (
         SELECT ltrim(upper(replace(replace(btrim("Planimetria".cod), ' LK'::text, ''::text), ' CH'::text, ''::text)), '0'::text) AS base
           FROM "Planimetria"
          WHERE ((upper(btrim("Planimetria".cod)) ~~ '% LK'::text) OR (upper(btrim("Planimetria".cod)) ~~ '% CH'::text))
          GROUP BY (ltrim(upper(replace(replace(btrim("Planimetria".cod), ' LK'::text, ''::text), ' CH'::text, ''::text)), '0'::text))
         HAVING (bool_or((upper(btrim("Planimetria".cod)) ~~ '% LK'::text)) AND bool_or((upper(btrim("Planimetria".cod)) ~~ '% CH'::text)))
        ), home_chef AS (
         SELECT ltrim(upper(btrim("Equivalencias_Codigos".cod_pedido)), '0'::text) AS base
           FROM "Equivalencias_Codigos"
          WHERE ((upper(btrim("Equivalencias_Codigos".cod_real)) ~~ '% CH'::text) AND (upper(btrim("Equivalencias_Codigos".cod_pedido)) !~~ '%L'::text))
        ), candidatos AS (
         SELECT s.base
           FROM (split s JOIN chef_imp c ON ((c.base = s.base)))
          WHERE (NOT (s.base IN ( SELECT home_chef.base FROM home_chef)))
        )
 SELECT btrim(b.pedido) AS np,
    k.base AS cod,
    ( SELECT i.descripcion FROM "Importados" i
          WHERE ((ltrim(upper(btrim(i.cod_art)), '0'::text) = k.base) AND (i.descripcion IS NOT NULL)) LIMIT 1) AS descripcion,
    sum(COALESCE(b.cajas, (0)::numeric)) AS cajas
   FROM ("PPP_Base_Pedidos" b
     JOIN candidatos k ON ((k.base = ltrim(upper(regexp_replace(upper(btrim(b.articulo)), '([0-9E])L$'::text, '\1'::text)), '0'::text))))
  WHERE ((b.pedido ~ '^[0-9]+$'::text) AND ((b.pedido)::bigint < 90000)
     -- v9.45/9.46: 437E/438E/439E → NC a Loeke SOLO si el pedido es la variante "...L"; el pelado NO.
     AND (NOT (k.base = ANY (ARRAY['437E'::text, '438E'::text, '439E'::text])) OR (upper(btrim(b.articulo)) ~ 'L$'::text))
     AND (NOT (EXISTS ( SELECT 1 FROM "NC_Loeke_Chef_Hechas" h
          WHERE ((btrim(h.np) = btrim(b.pedido)) AND (ltrim(upper(btrim(h.cod)), '0'::text) = k.base))))))
  GROUP BY (btrim(b.pedido)), k.base
 HAVING (sum(COALESCE(b.cajas, (0)::numeric)) > (0)::numeric);
