-- ============================================================================
-- v17.08 — Centinela de carga: avisa el mismo día si el Excel entró mezclado
--
-- Proyecto: LK (kwkclwhmoygunqmlegrg).
--
-- POR QUE
-- Thomas (14/09): "se puede hacer que cargue como corresponde?" y "fijate si no
-- rompe alguna otra cosa eso, o sea, si no esta asi por algun otro motivo".
--
-- NO esta asi por otro motivo. `sales_lines.empresa` se agrego en
-- `impactar_ventas_chef_en_sales_lines.sql` (repo pagina-LK-copia) como
-- `text not null default 'lk'` — el default era para que el historico que ya
-- estaba quedara marcado LK. Pero la carga mensual es MANUAL: el Excel de ISIS
-- se sube al Table Editor, un lote por mes con el `import_batch` tipeado a mano
-- (febrero_26, marzo_26, ... ago-26). Si ese Excel no trae la columna `empresa`,
-- el default la pone en 'lk' y NADIE se entera. Eso paso en julio y agosto.
--
-- Ya estaba auditado del otro lado: el CLAUDE.md de pagina-LK-copia tiene la
-- seccion "Anomalia de carga de julio-agosto 2026 - SIN RESOLVER" (9/9/2026),
-- con el mismo diagnostico y la misma indicacion ("Remarcar como empresa='chef'.
-- No borrar: son ventas reales en la empresa equivocada").
--
-- QUE HACE ESTA VISTA
-- Marca los codigos cargados como `empresa='lk'` que parecen de Chef, con tres
-- senales independientes:
--   1. TODAS sus lineas llevan sufijo L. Por la regla del dueno (v13.71) un
--      articulo de Loekemeyer va con L al final cuando se factura por Chef,
--      asi que eso es una factura de Chef, no de LK.
--   2. El codigo no existe en el padron de LK y si en el de Chef.
--   3. La mitad o mas de sus lineas son articulos que LK no vende (medido
--      contra junio 2026, que tiene las dos cargas separadas y limpias).
-- `ya_corregido` dice si ya esta asentado en GV_Ventas_Correccion.
--
-- COMO SE USA: despues de cada importacion mensual,
--   select * from public.gv_ventas_carga_sospechosa where not ya_corregido;
-- Vacio = el Excel entro bien. Con filas = entro mezclado otra vez.
--
-- Al 14/09 devuelve 53 codigos ya corregidos y 1 pendiente: el 1903, que es
-- Mundo Bazar en LK y Feser en Chef, con 10 de 11 lineas de articulos que LK no
-- vende — pero como tambien factura por LK de verdad, se dejo sin tocar.
--
-- ROLLBACK: drop view if exists public.gv_ventas_carga_sospechosa;
-- ============================================================================

drop view if exists public.gv_ventas_carga_sospechosa;
create view public.gv_ventas_carga_sospechosa
with (security_invoker = true) as
with ch_items as (
  select item_code from public.sales_lines
   where import_batch = 'chef_hist_xlsx_202607' and invoice_date::date between '2026-06-01' and '2026-06-30'
  except
  select item_code from public.sales_lines where import_batch = 'junio_26'
), x as (
  select s.import_batch, s.customer_code,
         count(*) filas, sum(s.boxes) cajas, min(s.invoice_date) desde, max(s.invoice_date) hasta,
         count(*) filter (where s.item_code ~ 'L$')      filas_sufijo_L,
         count(*) filter (where i.item_code is not null) filas_item_de_chef,
         (lkp.cod is null)     as sin_padron_lk,
         (chp.cod is not null) as en_padron_chef,
         coalesce(chp.nombre, lkp.nombre) nombre
    from public.sales_lines s
    left join ch_items i on i.item_code = s.item_code
    left join (select cod_cliente::text cod, business_name nombre from public.customers)   lkp on lkp.cod = s.customer_code
    left join (select cod_cliente::text cod, business_name nombre from public.chef_padron) chp on chp.cod = s.customer_code
   where s.empresa = 'lk' and s.import_batch is not null
   group by 1, 2, lkp.cod, chp.cod, chp.nombre, lkp.nombre
)
select x.import_batch, x.customer_code, x.nombre, x.filas::int, x.cajas, x.desde, x.hasta,
       x.filas_sufijo_L::int, x.filas_item_de_chef::int, x.sin_padron_lk, x.en_padron_chef,
       (f.customer_code is not null) as ya_corregido,
       case when x.filas_sufijo_L = x.filas           then 'todas las lineas llevan sufijo L: se facturo por Chef'
            when x.sin_padron_lk and x.en_padron_chef then 'el codigo no existe en el padron de LK y si en el de Chef'
            else 'la mayoria de las lineas son articulos que LK no vendio' end as motivo
  from x
  left join public."GV_Ventas_Correccion" f
    on f.import_batch = x.import_batch and f.customer_code = x.customer_code
 where x.filas_sufijo_L = x.filas
    or (x.sin_padron_lk and x.en_padron_chef)
    or x.filas_item_de_chef * 2 >= x.filas;

comment on view public.gv_ventas_carga_sospechosa is
  'v17.08 - centinela de carga: filas de sales_lines marcadas empresa=lk que parecen de Chef. Mirarla despues de cada importacion mensual; ya_corregido=false y no vacio = el Excel entro mezclado otra vez.';

-- ---------------------------------------------------------------------------
-- LO QUE FALTA, Y ES DECISION DEL DUENO (no se hizo):
--
-- a) Sacarle el `default 'lk'` a sales_lines.empresa. Con el default afuera, un
--    Excel sin la columna FALLA en vez de entrar mudo como LK. Es una linea:
--      alter table public.sales_lines alter column empresa drop default;
--    Pero rompe la rutina mensual tal como es hoy: hasta que el Excel traiga la
--    columna, ninguna importacion entra. Por eso no se toco.
--
-- b) Que el Excel de ISIS se exporte separado por empresa, o traiga la columna.
--    Eso esta afuera de la base.
--
-- c) La solucion de fondo ya esta planificada del otro lado: idea 4856,
--    `docs/plan-4856-auto-sales-lines.md` de pagina-LK-copia, Fase 1.5 — llenar
--    sales_lines desde la facturacion viva de Gestion, con la empresa sacada del
--    prefijo de la NP (4xxxx = Chef). El plan ya dice, textual, que eso
--    "resuelve solo el caso Cencosud".
-- ---------------------------------------------------------------------------
