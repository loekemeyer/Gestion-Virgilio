-- =====================================================================
-- fn_proyeccion_oc_virgilio.sql - proyeccion de ventas que alimenta las OCs (PaginaLK)
--
-- Vive en el proyecto Supabase "loekemeyer's web" (PaginaLK, `kwkclwhmoygunqmlegrg`),
-- sobre `sales_lines`. Es la proyeccion que Produccion Virgilio baja a `proyeccion_madre`
-- (via `refresh_proyeccion_madre()`) y que fija el Maximo del generador de OCs
-- (Maximo = proyeccion x indice, topado a capacidad).
--
-- Ventana PRIMARIA = 6 meses corridos. Si un producto proyecta 0 en 6 meses, usa los
-- ultimos 12. Si en 12 sigue 0, queda en 0 (no se devuelve -> el generador lo trata como
-- "sin proyeccion" y usa el objetivo de OC_Maximos). Combina Loekemeyer + Chef.
--
-- == v2 (2026-09-02, propuesta 2496) - DOS ERRORES QUE SE COMPENSABAN (SUPERADA por v3, abajo) ==
--
-- Sintoma reportado: la proyeccion del art. 505 (1667,6 caj/mes) quedaba por debajo de
-- 5 de los 6 meses reales de venta (2134/2160/3609/2070/1421/2698).
--
-- (1) EL FILTRO DE ANOMALIAS ANULABA A LOS CLIENTES DE COMPRA OCASIONAL.
--     Descartaba el MES ENTERO si `v > 1.5*rawavg AND max_other < 0.8*v AND prev < 0.5*v`.
--     Para un cliente con UNA sola compra en la ventana las tres se cumplen POR
--     CONSTRUCCION (rawavg = v/n, max_other = 0, prev = 0): era imposible que zafara.
--     En el 505 eran 199 de 420 clientes anulados y 5.621 de 14.092 cajas tiradas (40%).
--     Golpeaba justo a los articulos con muchos compradores esporadicos (la familia 5xx):
--     29 de 316 articulos quedaban por debajo de 5+ de sus 6 meses.
--
-- (2) EL DIVISOR INFLABA. `n` era "meses desde la primera compra del cliente", asi que un
--     cliente que estrenaba el mes pasado (n=1) contaba su unico pedido como ritmo mensual
--     completo. Sin ningun filtro el catalogo daba 33.208 caj/mes contra 21.935 de promedio
--     real: +51%.
--
--     El filtro brutal venia cancelando esa inflacion, mal y de forma despareja. Arreglar
--     solo (1) destapaba (2) y subia las compras 40%. Por eso se arreglan LOS DOS.
--
-- Solucion (opcion elegida por el usuario):
--   . (v2, ELIMINADA en v3) La regla de descarte se extrajo a `fn_proy_descarte()`, que
--     ahora comparten este motor y `refresh_estadistica_madre_cache()`. Antes estaba
--     COPIADA en 4 funciones SQL + 2 archivos JS, y ya habian divergido.
--   . Solo se descarta el EXCEDENTE (v - 1.5*rawavg), no el mes entero.
--   . El filtro solo se activa si el cliente compro en >= 2 meses de la ventana.
--   . El divisor pasa a ser la VENTANA COMPLETA.
--
-- Verificado 2026-09-02 (385 articulos con venta en los 6 meses):
--   . articulos por debajo de 5 o 6 de sus 6 meses: 29 -> 6 (y 0 por debajo de LOS 6)
--   . balance (meses por encima de la proyeccion, promedio): 2,99 -> 3,01 (ideal 3,0)
--   . total del catalogo: 20.153 -> 19.792 caj/mes (-1,8%: no mueve el nivel de compras)
--   . art. 505: 1.667,6 -> 2.080,8 caj/mes (de 5/6 meses por encima a 4/6)
--
-- Backup de las definiciones anteriores: sql/backups/backup_proyeccion_LK_20260902.sql
--
-- (Antes se usaba `fn_proyeccion_madre_emp(p_emp)`, LK-only 24m; desde v2 esa funcion y
-- `fn_proyeccion_madre()` delegan en este mismo motor con ventana 6m, y se les saco el
-- hack hardcodeado que metia ventas de chef solo para el articulo 505 - que era un parche
-- puesto para tapar este mismo bug.)
--
-- WARNING La definicion VIVA esta en las migraciones de Supabase (proyecto kwkclwhmoygunqmlegrg);
-- esta es la copia documentada para el repo.
-- =====================================================================

-- == v3 (2026-09-02, mismo dia) - CRITERIO UNICO ======================================
-- El usuario rechazo la v2: "si esta por abajo de 4 de los ultimos 6 meses, no es una
-- proyeccion confiable. No puede ser diferente el criterio. Es solo UNA estadistica madre".
-- Cualquier recorte de volumen que ocurrio (descarte de picos) empuja la proyeccion por
-- debajo de la mayoria de los meses: con la v2 lo violaban 70 de 385 articulos.
--
-- Criterio: proyeccion = PROMEDIO SIMPLE de cajas facturadas de los ultimos 6 meses (LK+Chef,
-- meses sin venta cuentan 0), con PISO en el 4.o mejor mes de esos 6 -> por construccion nunca
-- queda por debajo de 4 de los 6. Medido: 0 violaciones (el promedio pelado tenia 28).
-- El piso aplica SOLO a la ventana de 6: en el fallback de 12 se usa el promedio pelado, para
-- no proyectar el ritmo viejo de un articulo que dejo de venderse.
-- Se elimino fn_proy_descarte (ya no hay regla de descarte) y refresh_estadistica_madre_cache
-- toma la proyeccion de fn_proyeccion_madre() -> este motor. UN numero en todo el sistema.
-- Verificado: 505 = 2.348,7 en motor, cache, vista estadistica_madre y proyeccion_madre de
-- Virgilio; total 22.371 caj/mes; balance 2,02 meses por encima.
-- ---------------------------------------------------------------------
-- Motor. UNA sola firma (limpieza 2026-09-02: la variante con p_emp existia solo para
-- fn_proyeccion_madre_emp, que no tenia llamadores; las dos se borraron).
-- ---------------------------------------------------------------------
create or replace function public._fn_proy_window(p_meses int)
 returns table(item text, proy_cajas numeric)
 language sql stable security definer set search_path to 'public' set statement_timeout to '60s'
as $fn$
  with vent as (select greatest(coalesce(p_meses,6),1)::int as meses),
  mm as (
    select max(extract(year from (invoice_date)::date)::int*12 + extract(month from (invoice_date)::date)::int) as endm
    from public.sales_lines where invoice_date ~ '^\d{4}-\d{2}-\d{2}'
  ),
  norm as (
    select regexp_replace(upper(sl.item_code),'^0+(?=.)','') as nitem,
           (extract(year from (sl.invoice_date)::date)::int*12 + extract(month from (sl.invoice_date)::date)::int) as midx,
           sl.boxes::numeric as v
    from public.sales_lines sl, mm, vent
    where sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
      and sl.customer_code is not null and sl.customer_code not in ('1','3878')
      and sl.empresa in ('lk','chef')
      and (extract(year from (sl.invoice_date)::date)::int*12 + extract(month from (sl.invoice_date)::date)::int)
          between mm.endm - (vent.meses - 1) and mm.endm
  ),
  base as (
    select coalesce(r.to_code, nz.nitem) as item, nz.midx, sum(nz.v) as v
    from norm nz
    left join public.sales_item_remap r on r.from_code = nz.nitem
    where not exists (select 1 from public.sales_excluded_items e where e.item_code = nz.nitem)
    group by 1,2
  ),
  -- serie completa: los meses sin venta cuentan 0
  grid as (
    select i.item, g as midx
    from (select distinct item from base) i, mm, vent, generate_series(mm.endm - (vent.meses - 1), mm.endm) g
  ),
  serie as (
    select g.item, g.midx, coalesce(b.v, 0) as v
    from grid g left join base b on b.item = g.item and b.midx = g.midx
  ),
  st as (
    select item,
           sum(v) / (select meses from vent) as media,
           (array_agg(v order by v desc))[least(4, (select meses from vent))] as m4
    from serie group by item
  )
  select item,
         round(case when (select meses from vent) <= 6 then greatest(media, coalesce(m4, 0)) else media end, 2) as proy_cajas
  from st;
$fn$;

create or replace function public.fn_proyeccion_oc_virgilio()
 returns table(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric)
 language sql stable security definer set search_path to 'public' set statement_timeout to '60s'
as $fn$
  with p6 as (select item, proy_cajas from public._fn_proy_window(6)),
       p12 as (select item, proy_cajas from public._fn_proy_window(12)),
       merged as (
         select coalesce(p6.item, p12.item) as item,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_cajas
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_cajas
                     else 0 end as proy_cajas
         from p6 full join p12 on p12.item = p6.item
       )
  select m.item as cod, m.proy_cajas as proy_cajas_mes,
         coalesce(p.uxb, lk.uxb)::integer as uxb,
         round(m.proy_cajas * coalesce(p.uxb, lk.uxb, 1))::numeric as proy_uni_mes
  from merged m
  left join public.products p on regexp_replace(upper(p.cod),'^0+(?=.)','') = m.item
  left join public.loke_products lk on regexp_replace(upper(lk.cod),'^0+(?=.)','') = m.item
  where m.proy_cajas > 0
  order by m.proy_cajas desc;
$fn$;

-- ---------------------------------------------------------------------
-- fn_proyeccion_madre delega en el mismo motor, ventana 6m (la usa refresh_estadistica_madre_cache).
-- ---------------------------------------------------------------------
create or replace function public.fn_proyeccion_madre()
 returns table(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric)
 language sql stable security definer set search_path to 'public' set statement_timeout to '60s'
as $fn$
  select w.item as cod, w.proy_cajas as proy_cajas_mes,
         coalesce(p.uxb, lk.uxb)::integer as uxb,
         round(w.proy_cajas * coalesce(p.uxb, lk.uxb, 1))::numeric as proy_uni_mes
  from public._fn_proy_window(6) w
  left join public.products p on regexp_replace(upper(p.cod),'^0+(?=.)','') = w.item
  left join public.loke_products lk on regexp_replace(upper(lk.cod),'^0+(?=.)','') = w.item
  where w.proy_cajas > 0
  order by w.proy_cajas desc;
$fn$;

-- (fn_proyeccion_madre_emp se borro en la limpieza del 2026-09-02: sin llamadores.)

-- WARNING El GRANT a anon esta COMENTADO a proposito. Un barrido de seguridad en LK le
-- revoco el EXECUTE a anon, y eso dejo a `refresh_proyeccion_madre()` de Virgilio
-- fallando en SILENCIO (devuelve -1 y el cron marca "succeeded"): la proyeccion quedo
-- congelada desde el 12/08 hasta el 02/09, tres semanas, sin que nadie se enterara.
-- Volver a abrirlo expone la proyeccion a cualquiera con la anon key de LK, que es
-- publica. Decision pendiente con el usuario: re-abrir a anon, o dar vuelta el sentido
-- y que LK EMPUJE a Virgilio por el FDW `virgilio_db` que ya existe (mismo patron que
-- `sync_pedidos_match_virgilio()`), que no expone nada.
-- grant execute on function public.fn_proyeccion_oc_virgilio() to anon, authenticated;
grant execute on function public.fn_proyeccion_oc_virgilio() to authenticated;
