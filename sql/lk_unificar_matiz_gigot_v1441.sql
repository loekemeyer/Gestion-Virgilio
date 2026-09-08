-- Unificar "Gigot Cosméticos" (cod 5000) con "Matiz SA" (cod 4263)
-- Proyecto PaginaLK (kwkclwhmoygunqmlegrg) · 2026-09-08 · APLICADO
--
-- ── Qué pasaba ─────────────────────────────────────────────────────────────────────────────
-- Un mismo cliente estaba partido en dos:
--
--   · `customers` cod 5000 "Gigot Cosméticos", CUIT 30627435033, creado el 2026-04-09, con login
--     web y CERO pedidos por la página.
--   · ISIS factura al mismo CUIT como cod 4263 "Matiz SA" — 1 factura, FC A 0004-00035713 del
--     26/08/2026, $12.039.500, 208 cajas (NP 98109), más 3 NP en PPP (97889, 97964, 98426).
--
-- ISIS nunca vio el código 5000: cero comprobantes en `comprobantes_venta` (Virgilio) en 7 años y
-- 31.071 facturas LK. Y `customers` tiene UNIQUE sobre `cuit`, así que Matiz nunca pudo abrirse
-- su propia cuenta web: el CUIT ya lo ocupaba la fila de Gigot. Era una fila sola con el código
-- y el nombre equivocados, no dos clientes.
--
-- Diagnóstico anterior, corregido: se había reportado "cero facturas de este CUIT, carga de prueba
-- abandonada". Falso — la búsqueda usó el CUIT sin guiones (30627435033) y `comprobantes_venta` lo
-- guarda con guiones (30-62743503-3).
--
-- ── Las 121 líneas de `sales_lines` ────────────────────────────────────────────────────────
-- Carga a mano para poblarle los "sugeridos" del catálogo. Seis pruebas, todas medidas:
--
--   1. `boxes` en NULL en las 121 — sobre 233.898 filas de la tabla, las únicas sin cajas eran
--      esas 121 más una fila huérfana entera en NULL (122 en total).
--   2. `import_batch`, `imported_at` y `row_hash` también en NULL. El importador de ISIS los llena.
--   3. `invoice_date` = 2026-04-09, el mismo día en que se creó la cuenta.
--   4. 33 de los 35 artículos repetidos, hasta 4 veces. Ese día hay otros 11 clientes con ventas
--      reales y ninguno repite un artículo (max 1 fila por artículo). Sin `row_hash` no hay dedup,
--      así que cada corrida del insert manual apiló otra copia.
--   5. Son 35 códigos del catálogo LK (501 abrelatas, 941E espátula, 066, 234, 550…). El dueño:
--      *"compra por fuera de la página porque necesita sus propios códigos, no los normales de la
--      página LK, por lo que todos los códigos de LK no los compra"*. Matiz compró 55215, que ni
--      está en el catálogo.
--   6. El código 5000 no existe en ISIS.
--
-- Efecto que tenían: `get_customer_history` agrupa por (mes, artículo) y suma `coalesce(boxes,0)`,
-- así que le mostraba 35 artículos "comprados en 2026-04" con 0 cajas. Eso alimenta los sugeridos
-- del catálogo (`expoCatalogoBtn`, script.js) y el detector de anomalías de cantidad
-- (`loadAnomalyData`). Ruido puro para un cliente que compra con códigos propios.
--
-- ── Backups (protocolo) ────────────────────────────────────────────────────────────────────
-- Tomados ANTES de borrar, con RLS prendida y sin grants a anon/authenticated:
--   public.bkp_matiz_20260908_sales_lines  (122 filas)
--   public.bkp_matiz_20260908_customers    (1 fila)
--
-- ROLLBACK completo:
--   insert into public.sales_lines select * from public.bkp_matiz_20260908_sales_lines;
--   update public.customers c
--      set cod_cliente = b.cod_cliente, business_name = b.business_name
--     from public.bkp_matiz_20260908_customers b
--    where c.id = b.id;
--   refresh materialized view public.mv_loke_sales_agg;
--
-- ── Impacto medido ─────────────────────────────────────────────────────────────────────────
--   sales_lines con boxes NULL      122 → 0
--   sales_lines cod 5000            121 → 0
--   customers cod 5000                1 → 0   (pasó a 4263 "Matiz SA", mismo id, mismo login)
--   mv_loke_sales_agg           187.779 → 187.744 filas (−35, las del cliente 5000)
--   rep_salud()                 se apagó la alerta 🟠 "122 líneas de sales_lines con boxes NULL"
--
-- Antes de tocar nada se barrieron TODAS las tablas base de `public` con columna cod_cliente /
-- customer_code / cod_lk buscando el valor 5000: aparecía sólo en `sales_lines` (121) y
-- `customers` (1). Nada más que migrar.
--
-- Consecuencia buscada: con el código 4263 la cuenta web queda pegada a ISIS, así que el cliente
-- pasa a ver en la página su historial real y su deuda (la FC del 26/08). Antes no veía nada
-- porque el 5000 no existe en ISIS.

-- ── 1. Backups ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.bkp_matiz_20260908_sales_lines as
select * from public.sales_lines
 where customer_code = '5000'
    or (customer_code is null and item_code is null and invoice_date is null);

create table if not exists public.bkp_matiz_20260908_customers as
select * from public.customers where cod_cliente = 5000;

alter table public.bkp_matiz_20260908_sales_lines enable row level security;
alter table public.bkp_matiz_20260908_customers   enable row level security;
revoke all on public.bkp_matiz_20260908_sales_lines from anon, authenticated;
revoke all on public.bkp_matiz_20260908_customers   from anon, authenticated;

-- ── 2. Borrar la carga manual + la fila huérfana ───────────────────────────────────────────
delete from public.sales_lines
 where customer_code = '5000'
    or (customer_code is null and item_code is null and invoice_date is null);

-- ── 3. La fila del cliente pasa a ser la de ISIS ───────────────────────────────────────────
-- 4263 estaba libre en `customers` (verificado antes de correr esto).
update public.customers
   set cod_cliente = 4263,
       business_name = 'Matiz SA'
 where cod_cliente = 5000;

-- ── 4. La MV todavía tenía las 35 filas agregadas del 5000 ─────────────────────────────────
-- El cron 9 (`refresh-mvs-daily`, 03:00) lo haría solo, pero se fuerza para no dejar el
-- historial del cliente mintiendo hasta mañana.
refresh materialized view public.mv_loke_sales_agg;
