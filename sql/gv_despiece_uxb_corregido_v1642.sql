-- gv_despiece_uxb_corregido_v1642.sql — APLICADO 2026-09-12, con el OK del dueño ("Dale").
--
-- Corrige `Despiece x Articulo"."Uni_x_Caja"`, que alimenta el consumo mensual de cajas de
-- CARTÓN en los admin de Cervantes:
--   `cajasUsadas = Math.ceil(eMadre / uniXCaja)`
--     · cervantes-admin/{entero,gp2}/Compras/cajas.html:405 y :432
--     · cervantes-admin/entero/Inicio/index.html:1480 y :1493
--
-- ⚠⚠ DOS ERRORES MÍOS EN ESTE MISMO TRABAJO. Los dejo escritos porque los dos son del tipo
-- que se repite.
--
-- ── ERROR 1: el número que le di al dueño estaba mal ──────────────────────────────────────
-- Le dije **"67 códigos, casi todos ×2 o ÷2"**. Ese número salió de una medición que agrupaba
-- por código con `max()` de cada columna, y eso mezcló dos cosas distintas. Row por row:
--
--   A) tienen un valor DISTINTO (corregir)  → 103 filas,  23 códigos
--   B) están VACÍAS (rellenar)              → 132 filas,  55 códigos
--                                             ---------  ---------
--                                             235 filas,  77 códigos (uno cae en las dos)
--
-- O sea que **los que de verdad tenían un valor mal eran 23 códigos, no 67**. El resto estaba
-- en NULL. Lección: una medición agrupada con `max()` no describe lo que hace un UPDATE, que
-- va fila por fila. Medir con la MISMA granularidad con la que se va a escribir.
--
-- Se aplicaron las dos. Las dos tienen idéntica evidencia (la columna vieja `Uni x Cja` de la
-- propia tabla coincide con `GV_UxB`, o sea dos fuentes independientes contra el valor actual)
-- y rellenar un vacío es más seguro que pisar un valor.
--
-- **Efecto de (B), que conviene avisarle a Compras:** esos 55 códigos hoy dividían por NULL, o
-- sea no calculaban consumo de cartón. Ahora sí → **van a empezar a aparecer en las alertas de
-- compra**. Es lo correcto, pero es un cambio visible.
--
-- ── ERROR 2: el backup se guardó sin la clave ─────────────────────────────────────────────
-- `zz_backups."GV_Despiece_uxc_20260912"` guardó `("COD", "Uni_x_Caja", "Uni x Cja")` — pero la
-- clave de la tabla es **`id` (uuid)**, y `COD` NO es único (754 filas, 238 códigos). Para los
-- **49 códigos** que tenían filas con valores distintos entre sí, ese backup permite restaurar
-- el estado **a nivel código, no fila por fila**.
--
-- No es catastrófico —`Uni_x_Caja` es una propiedad del ARTÍCULO, así que las filas del mismo
-- código *deberían* tener el mismo valor, y la variación era justamente parte de la corrupción—
-- pero **no es un rollback exacto y no hay que decir que lo es**.
--
-- Se tomó una foto CON clave del estado post-fix: `zz_backups."GV_Despiece_uxc_postfix_20260912"`
-- (id, COD, Uni_x_Caja, Uni x Cja; 754/754 ids únicos). De acá en adelante es exacto.
--
-- **Regla: el backup se guarda con la CLAVE PRIMARIA de la tabla. Si no se sabe cuál es, se
-- averigua antes de escribir, no después.**
--
-- ── LA TRAMPA DEL JOIN, que mordió dos veces ──────────────────────────────────────────────
-- `COD` no es único, así que cualquier join por `COD` multiplica. El primer intento de contar
-- las filas a tocar dio **1320 de una tabla de 754** — imposible, y por eso no se ejecutó.
-- El mapa correcto es `zz_backups."GV_tmp_despiece_map2"`, con `select distinct` e índice único.
--
-- ── MEDICIÓN ──────────────────────────────────────────────────────────────────────────────
--   previsto : 235 filas / 77 códigos     ejecutado : 235 filas  ✓
--   códigos alineados con GV_UxB : 82 → **151**
--   los 85 que siguen distintos son exactamente los que NO se tocaron por falta de
--     corroboración (72 sin columna vieja + los ambiguos)
--   columna vieja `Uni x Cja` : **0 filas cambiadas**
--   corroboradas que hayan quedado sin arreglar : **0**
--   filas totales : 754, sin cambio
--
-- ── LO QUE SIGUE SIN TOCARSE, A PROPÓSITO ─────────────────────────────────────────────────
-- Los 85 códigos restantes no tienen segunda fuente que respalde el cambio. Entre ellos,
-- `A10`, `A15`, `C1`, `C10`, `GRJ9` y `V9` dicen 30 en las DOS columnas de la tabla contra 12
-- de `GV_UxB`: no parecen artículos de LK/Chef sino códigos propios de Cervantes, o sea
-- **otro dominio**. Ésos no se tocan ni con OK.
--
-- ── ROLLBACK ──────────────────────────────────────────────────────────────────────────────
-- A nivel código (ver ERROR 2 para la limitación):
--   update public."Despiece x Articulo" d set "Uni_x_Caja" = b."Uni_x_Caja"
--     from (select "COD", max("Uni_x_Caja") "Uni_x_Caja"
--             from zz_backups."GV_Despiece_uxc_20260912" group by "COD") b
--    where b."COD" = d."COD";

with upd as (
  update public."Despiece x Articulo" d
     set "Uni_x_Caja" = g.u
    from zz_backups."GV_tmp_despiece_map2" m,     -- ⚠ el mapa DEDUPLICADO, no el otro
         zz_backups."GV_tmp_gvuxb_map" g
   where m.cod = d."COD"::text
     and g.c = m.cn
     and d."Uni_x_Caja"::numeric is distinct from g.u
     and d."Uni x Cja"::numeric = g.u             -- ← la corroboración: esto lo acota
  returning 1)
select count(*) as filas_actualizadas from upd;   -- 235
