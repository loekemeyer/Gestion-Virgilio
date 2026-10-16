-- 16/10/2026 (Luis): 938E salía sin empresa (—) en la columna LK/CH de Stocks.
-- vista_marca_articulo sólo miraba OC_Maximos.linea y Articulos_Cajas.Marca; el 938E no está en ninguna.
-- Se agrega como ÚLTIMO recurso la empresa del código (GV_Articulo_Empresa_Cache = gv_empresa_de_articulo),
-- que es la fuente que vale (docs/REGLAS-STOCK-RACKS.md). No cambia ningún código que ya tenía marca
-- (3 choques medidos: 702EN, 724, 838E quedan como estaban). Suma 28 códigos, entre ellos 938E = LK.
-- ANTES:
--  WITH oc AS (...OC_Maximos activo, linea...), ac AS (...Articulos_Cajas.Marca...)
--  SELECT COALESCE(oc.k, ac.k) cod, COALESCE(oc.m, ac.m) marca,
--         CASE WHEN oc.m IS NOT NULL THEN 'oc_maximos' ELSE 'articulos_cajas' END fuente
--    FROM oc FULL JOIN ac ON oc.k = ac.k WHERE COALESCE(oc.m, ac.m) IN ('LK','CH');
create or replace view public.vista_marca_articulo with (security_invoker = true) as
 WITH oc AS (
         SELECT DISTINCT ON ((norm_cod("OC_Maximos".cod))) norm_cod("OC_Maximos".cod) AS k,
            upper(btrim("OC_Maximos".linea)) AS m
           FROM "OC_Maximos"
          WHERE ("OC_Maximos".activo AND (NULLIF(btrim("OC_Maximos".linea), ''::text) IS NOT NULL))
          ORDER BY (norm_cod("OC_Maximos".cod))
        ), ac AS (
         SELECT DISTINCT ON ((norm_cod("Articulos_Cajas"."Cod_Art"))) norm_cod("Articulos_Cajas"."Cod_Art") AS k,
            upper(replace(btrim("Articulos_Cajas"."Marca"), 'LOKE'::text, 'LK'::text)) AS m
           FROM "Articulos_Cajas"
          WHERE (NULLIF(btrim("Articulos_Cajas"."Marca"), ''::text) IS NOT NULL)
          ORDER BY (norm_cod("Articulos_Cajas"."Cod_Art"))
        ), base AS (
         SELECT COALESCE(oc.k, ac.k) AS cod,
            COALESCE(oc.m, ac.m) AS marca,
                CASE
                    WHEN (oc.m IS NOT NULL) THEN 'oc_maximos'::text
                    ELSE 'articulos_cajas'::text
                END AS fuente
           FROM (oc
             FULL JOIN ac ON ((oc.k = ac.k)))
          WHERE (COALESCE(oc.m, ac.m) = ANY (ARRAY['LK'::text, 'CH'::text]))
        )
 SELECT base.cod, base.marca, base.fuente FROM base
UNION ALL
 SELECT c.cod_canon AS cod, c.empresa AS marca, 'empresa_articulo'::text AS fuente
   FROM "GV_Articulo_Empresa_Cache" c
  WHERE (c.empresa = ANY (ARRAY['LK'::text, 'CH'::text]))
    AND NOT EXISTS (SELECT 1 FROM base b WHERE b.cod = c.cod_canon);

-- ═══ v31.48 (Luis, 16/10): FUENTE ÚNICA. La vista ya no mira OC_Maximos.linea ni Articulos_Cajas.Marca:
-- es la empresa del código (GV_Articulo_Empresa_Cache, la que llena gv_refrescar_articulo_empresa cada 15 min).
-- Medido antes: 125 códigos tenían marca SÓLO en las tablas viejas; 1 solo con saldo (007, en insumos "Mixto").
-- Cambian: 702EN LK→CH (planimetría vieja), 724 CH→LK (lista), 838E CH→LK (góndola); los 4 duales quedan sin marca
-- (el panel los muestra con sufijo "437E LK"). El impreso de OC (ocLoadLineas) también lee esta vista.
create or replace view public.vista_marca_articulo with (security_invoker = true) as
 SELECT c.cod_canon AS cod, c.empresa AS marca, c.fuente
   FROM "GV_Articulo_Empresa_Cache" c
  WHERE c.empresa = ANY (ARRAY['LK'::text, 'CH'::text]);

-- D1 (Luis, 16/10): el 936E tenía la descripción del 938E en OC_Maximos y Articulos_Cajas.
-- Backup: zz_backups.oc_maximos_936e_20261016 / zz_backups.articulos_cajas_936e_20261016.
update public."OC_Maximos" set descripcion='Cuchara Calada Nylon Mgo Madera' where norm_cod(cod)='936E';
update public."Articulos_Cajas" set "Descripcion"='Cuchara Calada Nylon Mgo Madera' where norm_cod("Cod_Art")='936E';
