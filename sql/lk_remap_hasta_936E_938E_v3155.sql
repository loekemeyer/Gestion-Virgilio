-- v31.55 · proyecto LK (kwkclwhmoygunqmlegrg) · Luis, 16/10/2026
-- «Los datos de estadística madre de 936E son en realidad del 938E. Que se le pasen para todo lo que
--  respecta al cálculo de proyección de ventas, compras, importaciones y demás. Y a partir de hoy se
--  trackean por separado.»
--
-- sales_item_remap junta un código con otro PARA SIEMPRE. Acá hace falta un remap CON FECHA DE CORTE:
-- lo facturado ANTES de `hasta` cuenta como `to_code`; desde `hasta` cada código es el suyo.
-- Se aplica en ventas_proy_lineas.nitem, que es la fuente de todo el motor de proyección:
-- _fn_proy_window(_split) → fn_proyeccion_madre / fn_proyeccion_oc_virgilio → sync a Gestión
-- (proyeccion_madre → stocks / OC / Importados / GP2.est_madre), get_estadistica_madre_mensual (meses de
-- la Est. Madre), fn_ventas_mensuales_virgilio, fn_ventas_6m_avg, fn_ventas_clientes_mes_fam_virgilio,
-- rep_top_clientes.
-- NO toca sales_lines (la factura sigue diciendo 936E) ni el caché del portal (refresh_estadistica_madre_cache
-- lee sales_lines; su proyección sí sale del motor).
--
-- Rollback: volver la vista a la definición de abajo sin el lateral `rh` (nitem = la expresión regexp) y
--   delete from public.sales_item_remap_hasta where from_code = '936E';

create table if not exists public.sales_item_remap_hasta (
  from_code text not null,
  to_code   text not null,
  hasta     date not null,           -- lo facturado con invoice_date < hasta va a to_code
  motivo    text,
  creado    timestamptz not null default now(),
  primary key (from_code, hasta)
);
alter table public.sales_item_remap_hasta enable row level security;
revoke all on public.sales_item_remap_hasta from anon, authenticated;

insert into public.sales_item_remap_hasta (from_code, to_code, hasta, motivo)
values ('936E', '938E', date '2026-10-16',
        'Luis 16/10/2026: la venta histórica del 936E es del 938E; desde el 16/10 se trackean por separado')
on conflict (from_code, hasta) do nothing;

create or replace view public.ventas_proy_lineas as
 WITH cli_art_lk AS (
         SELECT c.cod_cliente_chef AS cod
           FROM precios_super.cadena c
          WHERE ((c.empresa = 'chef'::text) AND (NOT COALESCE(c.usa_productos_chef, false)) AND (c.cod_cliente_chef IS NOT NULL))
        UNION
         SELECT i.cod_isis
           FROM cliente_isis_cache i
          WHERE ((i.isis_empresa = 'chef'::text) AND (i.cod_isis IS NOT NULL))
        ), cli_super_lk AS (
         SELECT c.cod_cliente_chef AS cod
           FROM precios_super.cadena c
          WHERE ((c.empresa = 'chef'::text) AND (NOT COALESCE(c.usa_productos_chef, false)) AND (c.cod_cliente_chef IS NOT NULL))
        ), cod_lk AS (
         SELECT p.cod
           FROM products p
        UNION
         SELECT l.cod
           FROM loke_products l
        )
 SELECT sl.invoice_date,
    sl.customer_code,
    sl.item_code,
    sl.empresa AS empresa_venta,
        CASE
            WHEN ((sl.empresa = 'chef'::text) AND (upper(btrim(sl.item_code)) ~ '[0-9E]L$'::text) AND (sl.customer_code IN ( SELECT cli_art_lk.cod
               FROM cli_art_lk))) THEN 'lk'::text
            WHEN ((sl.empresa = 'chef'::text) AND (sl.customer_code IN ( SELECT cli_super_lk.cod
               FROM cli_super_lk)) AND (upper(btrim(sl.item_code)) IN ( SELECT cod_lk.cod
               FROM cod_lk))) THEN 'lk'::text
            ELSE sl.empresa
        END AS empresa,
    -- v31.55: remap con fecha de corte (sales_item_remap_hasta), sobre el código ya normalizado
    COALESCE(rh.to_code, nz.n) AS nitem,
    sl.boxes
   FROM sales_lines sl
   CROSS JOIN LATERAL (SELECT regexp_replace(regexp_replace(upper(btrim(sl.item_code)), '^0+(?=.)'::text, ''::text), '([0-9E])L$'::text, '\1'::text) AS n) nz
   LEFT JOIN LATERAL (SELECT r.to_code FROM sales_item_remap_hasta r
                       WHERE r.from_code = nz.n AND sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
                         AND sl.invoice_date < to_char(r.hasta, 'YYYY-MM-DD')
                       ORDER BY r.hasta LIMIT 1) rh ON true
  WHERE ((sl.empresa = ANY (ARRAY['lk'::text, 'chef'::text])) AND (sl.customer_code IS NOT NULL) AND (NOT (EXISTS ( SELECT 1
           FROM ventas_clientes_internos vi
          WHERE ((vi.empresa = sl.empresa) AND (vi.cod_cliente = sl.customer_code))))) AND (COALESCE(sl.import_batch, ''::text) <> 'jumbo_2026_02_20'::text));
