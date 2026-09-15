-- =====================================================================================
-- gv_ventas_clientes_500_timeout_v1822.sql
-- "No se pudo traer el detalle (http 500)" al tocar un mes en el pop-up de Proyeccion.
-- ✅ APLICADO el 2026-09-15. Problema 234. Toca los DOS proyectos.
--
-- EL SINTOMA. Thomas, con foto: el desglose por cliente contestaba 500.
--
-- ⚠ LA FUNCION NUNCA ANDUVO DESDE EL NAVEGADOR. Se la dio por andando ese mismo dia despues
--   de probarla desde el MCP de Supabase, que entra como `postgres`. `postgres` no tiene el
--   techo que tiene `anon`. La verificacion estaba mal hecha, no el codigo: hay que probar
--   con el rol con el que va a correr.
--
-- LA CAUSA, dos cosas sumadas
-- ---------------------------------------------------------------------------------
-- 1. El rol `anon` corre con `statement_timeout = 3s` (rolconfig del proyecto), y
--    `gv_ventas_clientes_mes_cod` tardaba 4,5 s -> PostgREST cancela y devuelve 500.
-- 2. De esos 4,5 s:
--    · ~2 s son el viaje HTTP a LK, que es fijo. Por eso `ventas_mensuales_cod` (2,1 s),
--      que ya estaba en produccion, tambien estaba al filo y fallaba de a ratos.
--    · 578 ms eran la consulta en LK: el plan entraba por `idx_sales_lines_item_invoice`
--      usando SOLO item_code, traia los 10.060 renglones de TODOS los meses del codigo, y
--      recien ahi filtraba con `substr(invoice_date,1,7) = mes`, que no es indexable.
--
-- LO QUE SE HIZO
-- ---------------------------------------------------------------------------------
-- a) En LK: el mes pasa a filtrarse como RANGO de texto sobre `invoice_date`, que es la 2.ª
--    columna del indice. `invoice_date` es TEXTO en ISO, asi que comparar texto ordena igual
--    que comparar fechas, y el regex sigue cuidando las filas con otro formato. Del plan
--    desaparecen las 10.060 filas: quedan las 142 del mes.
-- b) En Virgilio: `anon` pasa de 3 s a 8 s, que es lo que YA tienen `authenticated` y
--    `authenticator`. No es aflojar un limite: es dejar los tres en el mismo numero.
--
-- ⚠ Lo que NO sirve, y por que: `alter function ... set statement_timeout` NO alcanza.
--    Postgres arma el timer al empezar la sentencia y cambiarlo adentro de la funcion no lo
--    re-arma. Medido: con la sesion en 1 s, la funcion con su propio SET de 15 s se cancelo
--    igual, en su RETURN QUERY. Se probo, no funciono, y se saco.
--
-- MEDIDO, antes -> despues (5 corridas seguidas, 5 meses distintos):
--    gv_ventas_clientes_mes_cod: 4,5 s -> 2,2 s, estable  (techo ahora 8 s)
--    ventas_mensuales_cod:       2,1 s -> 2,1 s           (deja de estar al filo)
-- =====================================================================================


-- 1) EN LK (kwkclwhmoygunqmlegrg) — el mes, indexable ==================================
-- Sólo cambian las dos líneas del rango dentro del CTE `base`; el resto de la función queda
-- igual que en sql/gv_ventas_clientes_mes_v1812.sql:
--
--      and sl.invoice_date >= tgt.mes || '-01'
--      and sl.invoice_date <  to_char((tgt.mes || '-01')::date + interval '1 month', 'YYYY-MM-DD')
--      and sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
--
-- (antes: `and substr(sl.invoice_date, 1, 7) = tgt.mes`)
-- El CREATE completo y vigente está en la migración `fn_ventas_clientes_mes_virgilio_rango_indexable`.


-- 2) EN VIRGILIO (hrxfctzncixxqmpfhskv) — el techo del rol ============================
alter function public.gv_ventas_clientes_mes_cod(text, text, text) reset statement_timeout;
alter function public.ventas_mensuales_cod(text, integer, text) reset statement_timeout;
alter role anon set statement_timeout to '8s';


-- 3) VERIFICAR ========================================================================
-- (a) los tres roles en el mismo numero
select rolname, rolconfig from pg_roles where rolname in ('anon','authenticated','authenticator');

-- (b) cuanto tarda de verdad, varias veces seguidas -> esperado ~2,2 s cada una
with t as (
  select g, clock_timestamp() t0,
         (select count(*) from public.gv_ventas_clientes_mes_cod('513', m, null)) n,
         clock_timestamp() t1
  from (values (1,'2026-08'),(2,'2026-07'),(3,'2026-06'),(4,'2026-05'),(5,'2026-04')) v(g,m)
)
select g, n, round(extract(epoch from (t1-t0))::numeric, 2) seg from t order by g;

-- (c) el plan en LK ya no trae los 10.060 renglones (correr en kwkclwhmoygunqmlegrg,
--     con el cuerpo de la funcion sin el `gate`): el Index Scan tiene que dar rows=142.


-- 4) ROLLBACK =========================================================================
-- alter role anon set statement_timeout to '3s';
-- y en LK, volver el CTE `base` a `and substr(sl.invoice_date, 1, 7) = tgt.mes`.
-- ⚠ Volver atras el timeout sin volver atras lo otro deja el 500 de nuevo: el viaje HTTP
--   solo ya se come ~2 s de los 3 s.
