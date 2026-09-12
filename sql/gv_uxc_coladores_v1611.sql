-- ============================================================================
-- v16.11 (2026-09-12) — unidades por caja de los COLADORES, unificadas
-- Dueño, 12/09: "Colador 8cm: 36 · Colador 10: 24 · Colador 16: 24 · Colador 20: 24".
-- Es la primera bajada del problema 69 (uni_x_caja en 8 tablas, dos vistas
-- resolutoras que se contradicen). Ver docs/DUPLICADOS-SUPABASE-20260912.md.
--
-- Backup: public."GV_UxC_bkp_20260912" (7 filas, con tabla/cod/descripcion/uxc previos).
--
-- CAMBIOS (4 filas):
--   Articulos_Cajas  112 "Ø 16 Env. Loke"    12 -> 24
--   Articulos_Cajas  113 "Colador N°20 Loke" 12 -> 24
--   Articulos_Cajas  828 "COLADOR 16 CM"     36 -> 24   (la otra fila de 828 ya decía 24)
--   OC_Maximos       030 "Ø 20 Env."         12 -> 24
--
-- RESULTADO: los 13 códigos de colador 8/10/16/20 dan lo MISMO en las cuatro
-- fuentes (Articulos_Cajas, OC_Maximos, vista_uni_x_caja "compra" y
-- vista_uxb_articulo "factura"), salvo el 026, que es otra cosa (ver abajo).
--
-- NO SE TOCÓ, a propósito:
--   · 043 — en OC_Maximos y en el maestro NO es un colador, es "Tres En Uno" /
--     "Abrelatas Uña 3 En 1" a 12. La fila "COLADOR 10 CM" a 24 existe sólo en
--     Articulos_Cajas. Es un choque de códigos, no un uxc mal.
--   · 824 "COLADOR 8 CM" — dice 12 en las CUATRO tablas, sin contradicción. Por la
--     regla del dueño tendría que ser 36, pero es un código 8xx (Chef) y podría ser
--     otro empaque. No se cambia un valor consistente por inferencia: preguntar.
--   · 832 "COLADOR PINTADO N10" a 36 — mismo caso (la regla diría 24).
--
-- ROLLBACK:
--   update public."Articulos_Cajas" a set "Uni_x_Caja" = b.uxc
--     from public."GV_UxC_bkp_20260912" b
--    where b.tabla='Articulos_Cajas' and a."Cod_Art"=b.cod and a."Descripcion"=b.descripcion;
--   update public."OC_Maximos" o set uni_x_caja = b.uxc
--     from public."GV_UxC_bkp_20260912" b where b.tabla='OC_Maximos' and o.cod=b.cod;
-- ============================================================================

update public."Articulos_Cajas" set "Uni_x_Caja" = 24
 where regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') in ('112','113') and "Uni_x_Caja" = 12;
update public."Articulos_Cajas" set "Uni_x_Caja" = 24
 where regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') = '828' and "Uni_x_Caja" = 36;
update public."OC_Maximos" set uni_x_caja = 24
 where regexp_replace(upper(btrim(cod)),'^0+(?=.)','') = '30' and uni_x_caja = 12;

-- ---------------------------------------------------------------------------
-- LO QUE ESTO DESTAPÓ: `Articulos_Cajas` tiene el mismo código dos veces
-- ---------------------------------------------------------------------------
-- 21 códigos con más de una fila, 18 de ellos con `Uni_x_Caja` distinto. Y en
-- varios no es un error de carga: son DOS PRODUCTOS bajo el mismo número, uno
-- por empresa. El testigo es el 026:
--
--   026  LK  "COLADOR N°8"                    36
--   026  CH  "PINZA DE FIDEOS AC INOX VERDE"  12
--
-- `vista_uxb_articulo` no mira la empresa y se queda con 12, así que el Excel de
-- ISIS del colador 026 sale con 12 unidades por caja. Eso NO se arregla cambiando
-- un número: o la vista distingue empresa, o son códigos distintos. Decisión del
-- dueño. Chequeo:
--
--   select regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') cod,
--          count(*) filas, count(distinct "Uni_x_Caja") uxc_distintos,
--          string_agg("Marca" || ' ' || "Descripcion" || ' = ' || "Uni_x_Caja", ' | ')
--     from public."Articulos_Cajas" group by 1 having count(distinct "Uni_x_Caja") > 1;
