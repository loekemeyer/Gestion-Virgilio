-- v26.16 · Estadísticas de ISIS por artículo, descargables desde Gestión (Luis, 02/10/2026).
-- Reemplaza la bajada a mano de ISIS de los manuales 29 (ventas por artículo → costos) y
-- 31 (pedidos por artículo → Estadística Madre). Objetos NUEVOS, sólo lectura, SECURITY
-- DEFINER con guard de supervisor (leen isis_lk / isis_ch, que anon no ve). Los usa
-- estadisticas.js, que arma el .xls con el layout exacto del export de ISIS.
--
-- VENTAS = facturas + NC de ISIS ya parseadas (isis_lk / isis_ch.documentos), por artículo:
--   cantidad  = Σ unidades (NC restan) · líneas con cantidad 0 afuera (Pago-25%, DtoSuper…:
--               ISIS tampoco las lista; un artículo que neto da 0 SÍ sale, como en ISIS)
--   precio    = precio de la línea × (1 − dto1)(1 − dto2) × el factor que ya trae el importe
--               (facturas E: el 2 % viene adentro de la línea) × (1 − descuento del documento)
--               × tipo de cambio si la factura es en dólares («Son Dolar», Chef → LK)
--               redondeado a 2 decimales, que es como lo hace ISIS
--   total     = Σ cantidad en la unidad de la línea × precio (una línea cargada por CAJA
--               — 982E, 123L de Cencosud — se cuenta por caja, igual que ISIS)
--   promedio  = total ÷ cantidad · máximo / mínimo = del precio por línea · % = total ÷ total general
--   Verificado contra los Excel de ISIS de septiembre 2026: CH 163 de 163 artículos idénticos en
--   las cinco columnas ($245.911.849,42); LK 183 de 184 ($457.686.221,84). La única diferencia
--   es 55219 / 55219ZZ: ISIS los tiene separados y la factura impresa dice 55219 en los dos.
--
-- PEDIDOS = lo que pidieron los clientes en la página (lk_pedidos_match, LK o Chef) por fecha del
--   pedido. NO es el «Totales de pedidos por artículo» de ISIS: ese sólo tiene lo que se cargó en
--   ISIS al facturar (y por la empresa del ISIS: un pedido LK de Tierra del Fuego cae en el de CH),
--   y no está en la base. Medido sept/26: ISIS LK 11.068 cajas, página LK 26.297.
--   unidades = cajas × UxB (vista_uxb_articulo; sin UxB, vacío) · importe = unidades × precio de lista
--   (precios_venta / precios_venta_chef; un código con L va a la lista LK). Sin clientes de prueba.
--   SÓLO EL PIPELINE DE GESTIÓN (v26.16, Luis 02/10: "solo va a ser para los pedidos web de nuestro
--   pipeline"): pedido desde PPP_Web_Config.gestion_desde (03/09; lo anterior se cargó en ISIS por el
--   mail), sin cancelados (GV_Web_Cancelados) ni anulados (GV_Pedidos_Anulados). Lo que espera en
--   A Programar / Cuarentena SÍ cuenta: el cliente lo pidió. Medido sept/26: LK 26.291 → 23.367 cajas
--   (14 pedidos del 01-02/09 y 4 anulados), CH 2.725 → 2.655 (3 pedidos del 02/09). Migración
--   gv_isis_estadisticas_v2615_pipeline (el marcador interno de la
--   función dice "v26.15-pipeline": así se aplicó en la base; la versión de la app es la v26.16).
--
-- Rollback: drop function public.gv_isis_estad_ventas(text,date,date);
--           drop function public.gv_isis_estad_pedidos(text,date,date);

create or replace function public.gv_isis_estad_ventas(p_empresa text, p_desde date, p_hasta date)
returns table(cod text, descripcion text, cantidad numeric, precio_max numeric, promedio numeric,
              precio_min numeric, total numeric, particip numeric)
language sql stable security definer set search_path = public, pg_temp as $$
with par as (
  select case lower(btrim(coalesce(p_empresa, ''))) when 'lk' then 'lk' when 'ch' then 'ch' when 'chef' then 'ch' end emp),
d as (
  select x.id, x.familia, coalesce(x.descuento, 0) dsc, x.texto_raw
    from isis_lk.documentos x, par
   where par.emp = 'lk' and x.fecha between p_desde and p_hasta and x.familia in ('factura_venta', 'nc_venta')
  union all
  select x.id, x.familia, coalesce(x.descuento, 0), x.texto_raw
    from isis_ch.documentos x, par
   where par.emp = 'ch' and x.fecha between p_desde and p_hasta and x.familia in ('factura_venta', 'nc_venta')),
dt as (
  select d.id, d.familia, d.dsc,
         case when d.texto_raw ~* 'Son\s+D[oó]lar' then
           (select case when t ~ '^[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$' then replace(replace(t, '.', ''), ',', '.')
                        else replace(t, ',', '') end
              from (select substring(d.texto_raw from '(?i)Tipo de Cambio:\s*([0-9][0-9.,]*[0-9])') t) z)::numeric
         end tc
    from d),
it as (
  select i.documento_id, i.codigo_articulo, i.descripcion, i.cantidad, i.cantidad_caja, i.importe, i.precio_unit, i.dto_1, i.dto_2
    from isis_lk.documento_items i, par where par.emp = 'lk' and i.documento_id in (select id from d)
  union all
  select i.documento_id, i.codigo_articulo, i.descripcion, i.cantidad, i.cantidad_caja, i.importe, i.precio_unit, i.dto_1, i.dto_2
    from isis_ch.documento_items i, par where par.emp = 'ch' and i.documento_id in (select id from d)),
l0 as (
  select dt.id, dt.familia, dt.dsc, coalesce(dt.tc, 1) tc, upper(btrim(it.codigo_articulo)) cod,
         regexp_replace(btrim(it.descripcion), '^[0-9]{3,7}[A-Z]{0,3}\s+', '') ds,
         coalesce(it.cantidad, 0) cantidad, it.cantidad_caja, it.importe,
         coalesce(it.precio_unit, 0) * (1 - coalesce(it.dto_1, 0) / 100) * (1 - coalesce(it.dto_2, 0) / 100) p0
    from dt join it on it.documento_id = dt.id
   where coalesce(btrim(it.codigo_articulo), '') <> ''),
l1 as (
  select l0.*,
         case when importe is null or p0 = 0 then cantidad
              when abs(importe / p0 - cantidad) <= 0.02 * abs(cantidad) then cantidad
              when cantidad_caja is not null and abs(importe / p0 - cantidad_caja) <= 0.02 * abs(cantidad_caja) then cantidad_caja
              else cantidad end q
    from l0),
dr as (select id, coalesce(round(max(dsc) / nullif(sum(coalesce(importe, 0)), 0), 4), 0) r from l1 group by 1),
l as (
  select l1.cod, l1.ds, l1.cantidad, l1.q, case when l1.familia = 'nc_venta' then -1 else 1 end sg,
         round(l1.p0 * case when l1.importe is not null and l1.q * l1.p0 <> 0 then round(l1.importe / (l1.q * l1.p0), 4) else 1 end
                     * (1 - dr.r) * l1.tc, 2) pu
    from l1 join dr using (id)
   where l1.cantidad <> 0),
g as (select l.cod, sum(sg * cantidad) cant, max(pu) pmax, min(pu) pmin, sum(sg * q * pu) tot from l group by 1),
/* la descripción: la más usada para ese código. El parser a veces le pega adelante el código de
   la línea de arriba («529E Abr Mariposa Loke», «102E Abr Uña Pint Loke»): ninguna descripción de
   ISIS empieza con un código de 3+ dígitos (medido sobre los 4 Excel de sept/26), así que se saca. */
df as (
  select distinct on (cod) cod, ds from (select l.cod, l.ds, count(*) n from l where coalesce(l.ds, '') <> '' group by 1, 2) z
   order by cod, n desc, length(ds), ds)
select g.cod, coalesce(df.ds, ''), g.cant, g.pmax,
       case when g.cant <> 0 then g.tot / g.cant else 0 end,
       g.pmin, g.tot,
       round(g.tot / nullif(sum(g.tot) over (), 0) * 100, 2)
  from g left join df on df.cod = g.cod
 where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
 order by g.cod collate "C";
$$;

create or replace function public.gv_isis_estad_pedidos(p_empresa text, p_desde date, p_hasta date)
returns table(cod text, descripcion text, cajas numeric, unidades numeric, importe numeric, uxb numeric)
language sql stable security definer set search_path = public, pg_temp as $$
with par as (
  select case lower(btrim(coalesce(p_empresa, ''))) when 'lk' then 'lk' when 'ch' then 'chef' when 'chef' then 'chef' end emp,
         /* v26.15 (Luis, 02/10: "solo va a ser para los pedidos web de nuestro pipeline"):
            el pipeline de Gestión arranca en gestion_desde; lo anterior se cargó en ISIS por el mail */
         coalesce((select nullif(valor_texto, '')::date from public."PPP_Web_Config" where clave = 'gestion_desde'), date '9999-12-31') gdesde),
m as (
  select x.* from public.lk_pedidos_match x, par
   where x.empresa = par.emp and x.fecha_pedido between p_desde and p_hasta
     and x.fecha_pedido >= par.gdesde                                   /* v26.15-pipeline */
     and not exists (select 1 from public."GV_Web_Cancelados" wc       /* cancelado: no vuelve nunca */
                      where wc.empresa = x.empresa and wc.order_id = x.order_id)
     and not exists (select 1 from public."GV_Pedidos_Anulados" pa
                      where pa.empresa = x.empresa and pa.order_id = x.order_id)
     and not exists (select 1 from public."GV_Clientes_Prueba" pr
                      where lower(btrim(pr.empresa)) in (x.empresa, case x.empresa when 'chef' then 'ch' end)
                        and regexp_replace(btrim(pr.cod), '^0+', '') = regexp_replace(btrim(coalesce(x.cod_cliente, '')), '^0+', ''))),
it as (
  select regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', '') cod, (z.r[2])::numeric cajas
    from m
    cross join lateral unnest(string_to_array(coalesce(m.items_string, ''), ',')) t(item)
    cross join lateral (select regexp_match(btrim(t.item), '^(.+)x([0-9]+(?:\.[0-9]+)?)$') r) z
   where z.r is not null),
a as (
  select it.cod, regexp_replace(regexp_replace(it.cod, '^0+(?=.)', ''), '([0-9E])L$', '\1') base,
         it.cod ~ '[0-9E]L$' con_l, sum(it.cajas) cajas
    from it where it.cod <> '' group by 1, 2, 3),
pv as (select regexp_replace(btrim(cod), '^0+(?=.)', '') base, max(precio_unit) precio, max(descripcion) ds from public.precios_venta group by 1),
pc as (select regexp_replace(btrim(cod), '^0+(?=.)', '') base, max(precio_unit) precio, max(descripcion) ds from public.precios_venta_chef group by 1),
ux as (select regexp_replace(btrim(cod), '^0+(?=.)', '') base, max(uxb) uxb from public.vista_uxb_articulo where uxb > 0 group by 1),
/* la descripción de ISIS: la última con que se facturó ese mismo código en el ISIS de la empresa
   (sin el código que a veces pega adelante el parser) */
di as (
  select distinct on (cod) cod, ds from (
    select upper(btrim(i.codigo_articulo)) cod, regexp_replace(btrim(i.descripcion), '^[0-9]{3,7}[A-Z]{0,3}\s+', '') ds, x.fecha
      from isis_lk.documentos x join isis_lk.documento_items i on i.documento_id = x.id, par
     where par.emp = 'lk' and x.familia = 'factura_venta' and x.fecha >= p_hasta - 400
       and upper(btrim(i.codigo_articulo)) in (select a.cod from a)
    union all
    select upper(btrim(i.codigo_articulo)), regexp_replace(btrim(i.descripcion), '^[0-9]{3,7}[A-Z]{0,3}\s+', ''), x.fecha
      from isis_ch.documentos x join isis_ch.documento_items i on i.documento_id = x.id, par
     where par.emp = 'chef' and x.familia = 'factura_venta' and x.fecha >= p_hasta - 400
       and upper(btrim(i.codigo_articulo)) in (select a.cod from a)) z
   where coalesce(ds, '') <> ''
   order by cod, fecha desc),
na as (select regexp_replace(btrim(cod), '^0+(?=.)', '') base, max(descripcion) ds from public.vista_nombres_articulos group by 1)
select a.cod,
       coalesce(di.ds, na.ds, case when par.emp = 'lk' or a.con_l then pv.ds else pc.ds end, pv.ds, pc.ds, ''),
       a.cajas,
       a.cajas * ux.uxb,                      /* sin UxB queda vacío: «32 unidades» de algo que son 32 cajas mentiría */
       round(a.cajas * ux.uxb
             * coalesce(case when par.emp = 'lk' or a.con_l then pv.precio else pc.precio end, pv.precio, pc.precio, 0), 2),
       ux.uxb
  from a cross join par
  left join ux on ux.base = a.base
  left join pv on pv.base = a.base
  left join pc on pc.base = a.base
  left join di on di.cod = a.cod
  left join na on na.base = a.base
 where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
 order by a.cod collate "C";
$$;

revoke all on function public.gv_isis_estad_ventas(text, date, date) from public, anon;
revoke all on function public.gv_isis_estad_pedidos(text, date, date) from public, anon;
grant execute on function public.gv_isis_estad_ventas(text, date, date) to authenticated, service_role;
grant execute on function public.gv_isis_estad_pedidos(text, date, date) to authenticated, service_role;
