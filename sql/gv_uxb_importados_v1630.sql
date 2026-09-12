-- ============================================================================
-- v16.30 (2026-09-12) — el módulo de Importados toma el UxB de GV_UxB
--
-- Tercer tramo de "que todos los lugares usen solo 1 lugar".
--
-- VERIFICACIÓN PREVIA (154 filas principal+activo de Importados):
--   · 0 difieren de GV_UxB — los que están, coinciden exacto
--   · sólo 4 faltaban con valor real: 119E=12, 522ES=25, 602E=12 y 814E=1
--   · 814E NO se absorbió: el 1 es el placeholder de "no sé" del catálogo de LK
--   · 32 no tienen dato en ningún lado (5 son PARTES —505C, 587C, 523C, 1000900,
--     1546903— que no llevan caja, y el resto son códigos sin UxB cargado)
--
-- UNA TRAMPA DEL MATCHEO, que vale anotar: cruzando por canon_cod parecían faltar 39,
-- pero canon_cod NO quita la L final, así que 437EL/438EL/439EL no encontraban a
-- 437E/438E/439E en GV_UxB. Cruzando por gv_cod_stock (que sí la quita) los 39 bajan
-- a 4. El código con L es el artículo de Loeke vendido por Chef, no otro artículo.
--
-- CAMBIO: gv_importados_ordenes toma el uxb de GV_UxB por empresa (CTE `gux`), con
-- Importados.uni_x_caja de FALLBACK para los que no están cargados. Los tres usos
-- —la columna de salida, est_madre_live y el cálculo de stock_actual/unidades— pasan
-- todos por el mismo valor, así que no puede volver a pasar lo de facturable_anticipado
-- (mostrar un UxB y calcular con otro).
--
-- MEDIDO: 156 filas · 18.173 cajas brutas · 1.351 pedidas · 17.130 disponibles —
-- idéntico a antes. Testigos: 584E 15-5=10 cajas / 60 u (el del dueño) · 824 en 36 ·
-- 437EL resuelto vía gv_cod_stock · los 3 absorbidos con su valor.
--
-- POR QUÉ NO SE RENOMBRA Importados.uni_x_caja: la leen todavía vista_importados_partes
-- y v_importados_ordenes, que es la vista vieja que usa Producción Virgilio y que por
-- protocolo no se toca. Además es un dato propio de la ficha del artículo importado, no
-- una copia: lo que importaba era que la vista que lo MUESTRA tome la fuente única, y
-- eso ya está.
-- ============================================================================

insert into public."GV_UxB" (empresa, cod, uxb, descripcion, origen, curado, actualizado)
select case when upper(coalesce(i.marca,''))='CH' then 'CH' else 'LK' end,
       i.cod_art, i.uni_x_caja, i.descripcion, 'absorbido de Importados 12/09 (v16.30)', false, now()
from public."Importados" i
where i.principal and i.activo and i.uni_x_caja > 1
  and public.gv_cod_stock(i.cod_art) in ('119E','522ES','602E')
on conflict (empresa,cod) do nothing;

-- gv_importados_ordenes: se agrega el CTE `gux` y se repuntan los 3 usos.
-- (aplicado con reemplazo de texto sobre pg_get_viewdef; ORDEN IMPORTANTE — primero el
--  CTE, después el join, después los COALESCE de las expresiones y AL FINAL la columna
--  de salida con su contexto. Al revés, el reemplazo de la columna se cuela adentro de
--  las expresiones y genera un "COALESCE(... AS uni_x_caja, 1)" que no compila.)
--
--   WITH gux AS (
--     SELECT CASE WHEN empresa='CH' THEN 'CH' ELSE 'LK' END AS emp,
--            gv_cod_stock(cod) AS c, max(uxb) AS u
--       FROM "GV_UxB" WHERE uxb > 1 GROUP BY 1,2
--   ), cfg AS ( ... )
--   LEFT JOIN gux gx ON gx.emp = (CH/LK segun i.marca) AND gx.c = gv_cod_stock(i.cod_art)
--   i.uni_x_caja                      -> COALESCE(gx.u, i.uni_x_caja)
--   COALESCE(i.uni_x_caja, 1::numeric) -> COALESCE(gx.u, i.uni_x_caja, 1::numeric)
--   COALESCE(i.uni_x_caja, 0::numeric) -> COALESCE(gx.u, i.uni_x_caja, 0::numeric)

-- ── verificación ──
-- select count(*), sum(stock_cajas_bruto), sum(cajas_pedidas), sum(stock_cajas)
--   from public.gv_importados_ordenes;      -- 156 · 18173 · 1351 · 17130
