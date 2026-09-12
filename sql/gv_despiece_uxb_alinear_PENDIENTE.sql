-- ============================================================================
-- PENDIENTE DE EJECUTAR — preparado el 12/09/2026, no aplicado todavía.
-- (se escribió con la conexión SQL caída; correr cuando el MCP responda)
--
-- QUÉ ARREGLA: "Despiece x Articulo"."Uni_x_Caja" está MAL CARGADA y no es un dato
-- decorativo: alimenta el cálculo del consumo mensual de cajas de CARTÓN en dos
-- pantallas de los admin de Cervantes —
--
--     cajasUsadas = Math.ceil(eMadre / uniXCaja)
--       · cervantes-admin/{entero,gp2}/Compras/cajas.html:405 y :432
--       · cervantes-admin/entero/Inicio/index.html:1480 y :1493
--
-- Con el UxB mal, el consumo de cartón sale mal y las alertas de compra no saltan
-- cuando deben. Muestra de los 21 códigos que difieren (columna nueva vs. la vieja
-- `Uni x Cja`, que coincide con lo correcto en 18 de 21):
--
--     cod   nueva  correcto   efecto sobre el consumo calculado
--     101     12       6      la MITAD
--     307    100      24      un CUARTO
--     390-394 12      24      el DOBLE
--     859/862/863/908  24  12  la MITAD
--
-- POR QUÉ SE ARREGLA EL DATO Y NO EL CÓDIGO: hay TRES copias del mismo front
-- (cervantes-admin/entero, cervantes-admin/gp2, y el repo original
-- Gestion-Productiva-2.0, que además es read-only en esta sesión). Corrigiendo la
-- tabla contra GV_UxB, las tres calculan bien sin tocar una línea. Y es lo que manda
-- el protocolo: la lógica de negocio vive en el backend.
--
-- ⚠ CUIDADO CON EL TIMEOUT. La tabla tiene ~1.245 filas y los joins con
-- gv_cod_stock() sobre ella TUMBARON la conexión (varios timeouts seguidos y después
-- el pool dejó de responder). Por eso va en PASOS CHICOS, materializando primero y
-- con índice. No correr los pasos juntos en una sola llamada.
-- ============================================================================

-- ── PASO 1 — backup (solo las 2 columnas, no la tabla entera) ──
create table zz_backups."GV_Despiece_uxc_20260912" as
  select "COD", "Uni_x_Caja", "Uni x Cja" from public."Despiece x Articulo";
alter table zz_backups."GV_Despiece_uxc_20260912" enable row level security;

-- ── PASO 2 — materializar el mapeo, con índice (para que el update no recalcule
--             gv_cod_stock por fila) ──
create table zz_backups."GV_tmp_despiece_map" as
  select "COD"::text cod, public.gv_cod_stock("COD"::text) cn from public."Despiece x Articulo";
create index on zz_backups."GV_tmp_despiece_map" (cn);
create index on zz_backups."GV_tmp_despiece_map" (cod);

-- ── PASO 3 — medir ANTES de tocar: cuántas difieren y en qué dirección ──
-- with g as (select public.gv_cod_stock(cod) c, max(uxb) u from public."GV_UxB" where uxb>0 group by 1)
-- select count(*) filas,
--        count(*) filter (where d."Uni_x_Caja"::numeric is distinct from g.u) difieren,
--        count(*) filter (where d."Uni_x_Caja"::numeric > g.u) uxb_de_mas_compra_de_menos,
--        count(*) filter (where d."Uni_x_Caja"::numeric < g.u) uxb_de_menos_compra_de_mas
--   from public."Despiece x Articulo" d
--   join zz_backups."GV_tmp_despiece_map" m on m.cod = d."COD"::text
--   join g on g.c = m.cn;

-- ── PASO 4 — alinear SOLO donde GV_UxB tiene el código (el resto se deja como está) ──
-- with g as (select public.gv_cod_stock(cod) c, max(uxb) u from public."GV_UxB" where uxb>0 group by 1)
-- update public."Despiece x Articulo" d
--    set "Uni_x_Caja" = g.u
--   from zz_backups."GV_tmp_despiece_map" m, g
--  where m.cod = d."COD"::text and g.c = m.cn
--    and d."Uni_x_Caja"::numeric is distinct from g.u;

-- ── PASO 5 — sumar Despiece al centinela, para que no se vuelva a desviar ──
-- (agregar una rama a gv_uxb_desalineado con 'Despiece x Articulo')

-- ── PASO 6 — limpiar el temporal ──
-- drop table zz_backups."GV_tmp_despiece_map";

-- ── VERIFICAR AL CIERRE ──
-- select count(*) from public.gv_uxb_desalineado;   -- 0
-- y volver a mirar el consumo de cartón en Compras/cajas.html: los códigos de arriba
-- deberían cambiar su "cajas usadas" en la proporción indicada.
