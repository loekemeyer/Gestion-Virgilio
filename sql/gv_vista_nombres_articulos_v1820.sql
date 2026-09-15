-- =====================================================================================
-- gv_vista_nombres_articulos_v1820.sql
-- La pantalla Stocks mostraba el CODIGO en vez del nombre en los articulos de Chef.
-- ✅ APLICADO el 2026-09-15. Problema 227 de github_repo_problemas.
--
-- EL SINTOMA. Thomas, con foto: 631, 706, 707, 708 y 731 aparecian en Stock y Compras con
-- DESCRIPCION = el propio codigo.
--
-- LA CAUSA. La descripcion SI existe, y en cuatro tablas de Virgilio:
--   GV_UxB, Articulos_Cajas, "Articulos Virgilio X Tallerista" y OC_Maximos
--   (706 = Abrelatas Unas · 731 = Sacacorcho Combinado Color · 631 = Espumadera Acero Inox).
-- Lo que pasaba es que `vista_nombres_articulos` pone PRIMERA en el coalesce a
-- `proyeccion_madre.gv_descripcion`, que desde la v16.88 viaja desde LK
-- (`estadistica_madre_cache`), y para los codigos que ese cache no conoce ese campo trae
-- EL CODIGO. O sea: la fuente con mas prioridad aportaba la falta de nombre disfrazada de
-- nombre, y tapaba a las tres que si lo tenian.
--
-- Medido el 2026-09-15: 225 de 461 filas de proyeccion_madre con gv_descripcion = el codigo,
-- y 95 filas de `stocks_carga_rapida` mostrando el numero como nombre.
--
-- ⚠ NO lo introdujeron los cambios del 15/09: el respaldo
--   zz_backups."GV_Backup_ProyeccionMadre_20260915", tomado ANTES de tocar nada, ya tenia
--   gv_descripcion = '706'. Viene de la v16.88 (12/09).
--
-- EL ARREGLO. Una "descripcion" igual al codigo no es un nombre: se descarta en el WHERE de
-- cada fuente, no solo en la de LK — ninguna puede aportar el codigo como si fuera nombre.
-- No se toca el orden del coalesce ni se agregan fuentes: la que tiene nombre de verdad
-- pasa a ganar sola.
--
-- RESULTADO, antes -> despues en `stocks_carga_rapida`: 95 -> 1 filas con el codigo como
-- descripcion. La que queda es 690E, que no tiene nombre en NINGUNA fuente: eso es un dato
-- que falta cargar, no un bug.
--   631 -> Espumadera Ac.Inox. · 706 -> Abrelatas Uña Blanco · 707 -> Rompenueces
--   708 -> Sacafuentes Articulado · 731 -> Sacacorcho Combinado Color
--
-- ⚠ `CREATE OR REPLACE VIEW` borra las reloptions sin avisar, asi que el
--   `alter view ... set (security_invoker = true)` del final NO es opcional.
-- =====================================================================================

create or replace view public.vista_nombres_articulos as
 WITH norm_pm AS (
         SELECT DISTINCT ON ((upper(regexp_replace(COALESCE(btrim(proyeccion_madre.cod), ''::text), '^0+(.)'::text, '\1'::text)))) upper(regexp_replace(COALESCE(btrim(proyeccion_madre.cod), ''::text), '^0+(.)'::text, '\1'::text)) AS k,
            NULLIF(btrim(proyeccion_madre.gv_descripcion), ''::text) AS d
           FROM proyeccion_madre
          WHERE (NULLIF(btrim(COALESCE(proyeccion_madre.gv_descripcion, ''::text)), ''::text) IS NOT NULL)
            AND (upper(btrim(COALESCE(proyeccion_madre.gv_descripcion, ''::text))) <> upper(regexp_replace(COALESCE(btrim(proyeccion_madre.cod), ''::text), '^0+(.)'::text, '\1'::text)))
          ORDER BY (upper(regexp_replace(COALESCE(btrim(proyeccion_madre.cod), ''::text), '^0+(.)'::text, '\1'::text))), NULLIF(btrim(proyeccion_madre.gv_descripcion), ''::text)
        ), norm_vxt AS (
         SELECT DISTINCT ON ((upper(regexp_replace(COALESCE(btrim(("Articulos Virgilio X Tallerista"."Cod_Art")::text), ''::text), '^0+(.)'::text, '\1'::text)))) upper(regexp_replace(COALESCE(btrim(("Articulos Virgilio X Tallerista"."Cod_Art")::text), ''::text), '^0+(.)'::text, '\1'::text)) AS k,
            NULLIF(btrim("Articulos Virgilio X Tallerista"."Desc"), ''::text) AS d
           FROM "Articulos Virgilio X Tallerista"
          WHERE (NULLIF(btrim(COALESCE("Articulos Virgilio X Tallerista"."Desc", ''::text)), ''::text) IS NOT NULL)
            AND (upper(btrim(COALESCE("Articulos Virgilio X Tallerista"."Desc", ''::text))) <> upper(regexp_replace(COALESCE(btrim(("Articulos Virgilio X Tallerista"."Cod_Art")::text), ''::text), '^0+(.)'::text, '\1'::text)))
          ORDER BY (upper(regexp_replace(COALESCE(btrim(("Articulos Virgilio X Tallerista"."Cod_Art")::text), ''::text), '^0+(.)'::text, '\1'::text))), NULLIF(btrim("Articulos Virgilio X Tallerista"."Desc"), ''::text)
        ), norm_oc AS (
         SELECT DISTINCT ON ((upper(regexp_replace(COALESCE(btrim("OC_Maximos".cod), ''::text), '^0+(.)'::text, '\1'::text)))) upper(regexp_replace(COALESCE(btrim("OC_Maximos".cod), ''::text), '^0+(.)'::text, '\1'::text)) AS k,
            NULLIF(btrim("OC_Maximos".descripcion), ''::text) AS d
           FROM "OC_Maximos"
          WHERE (("OC_Maximos".activo = true) AND (NULLIF(btrim(COALESCE("OC_Maximos".descripcion, ''::text)), ''::text) IS NOT NULL))
            AND (upper(btrim(COALESCE("OC_Maximos".descripcion, ''::text))) <> upper(regexp_replace(COALESCE(btrim("OC_Maximos".cod), ''::text), '^0+(.)'::text, '\1'::text)))
          ORDER BY (upper(regexp_replace(COALESCE(btrim("OC_Maximos".cod), ''::text), '^0+(.)'::text, '\1'::text))), NULLIF(btrim("OC_Maximos".descripcion), ''::text)
        ), norm_hist AS (
         SELECT "GV_Articulo_Nombre_Historico".cod AS k,
            "GV_Articulo_Nombre_Historico".descripcion AS d
           FROM "GV_Articulo_Nombre_Historico"
          WHERE (upper(btrim(COALESCE("GV_Articulo_Nombre_Historico".descripcion, ''::text))) <> upper(btrim(COALESCE("GV_Articulo_Nombre_Historico".cod, ''::text))))
        ), keys AS (
         SELECT norm_pm.k FROM norm_pm
        UNION
         SELECT norm_vxt.k FROM norm_vxt
        UNION
         SELECT norm_oc.k FROM norm_oc
        UNION
         SELECT norm_hist.k FROM norm_hist
        )
 SELECT kk.k AS cod,
    COALESCE(pm.d, v.d, o.d, h.d) AS descripcion,
        CASE
            WHEN (pm.d IS NOT NULL) THEN 'proyeccion_madre'::text
            WHEN (v.d IS NOT NULL) THEN 'virgilio_x_tall'::text
            WHEN (o.d IS NOT NULL) THEN 'excel'::text
            ELSE 'historico'::text
        END AS fuente
   FROM ((((keys kk
     LEFT JOIN norm_pm pm ON ((pm.k = kk.k)))
     LEFT JOIN norm_vxt v ON ((v.k = kk.k)))
     LEFT JOIN norm_oc o ON ((o.k = kk.k)))
     LEFT JOIN norm_hist h ON ((h.k = kk.k)))
  WHERE ((kk.k <> ''::text) AND (COALESCE(pm.d, v.d, o.d, h.d) IS NOT NULL));

alter view public.vista_nombres_articulos set (security_invoker = true);

-- la pantalla lee el espejo, asi que hay que refrescarlo (igual lo hace solo el cron 57)
select public.refresh_stocks_carga_rapida();


-- VERIFICAR ===========================================================================
-- (a) cuantas filas siguen mostrando el codigo como nombre -> esperado 1 (690E, sin nombre)
select cod, descripcion, linea from public.stocks_carga_rapida s
 where upper(btrim(s.descripcion)) = upper(regexp_replace(btrim(s.cod), '^0+(.)', '\1'));

-- (b) los de la foto
select cod, descripcion, linea, stock_total from public.stocks_carga_rapida
 where cod in ('631','706','707','708','731') order by cod;

-- (c) la vista conserva security_invoker -> una fila, con {security_invoker=true}
select relname, reloptions from pg_class where oid = 'public.vista_nombres_articulos'::regclass;


-- ROLLBACK ============================================================================
-- Sacar de cada CTE la condicion `AND (upper(btrim(...descripcion)) <> upper(...cod...))`
-- y volver a correr `alter view ... set (security_invoker = true)` + el refresh.
