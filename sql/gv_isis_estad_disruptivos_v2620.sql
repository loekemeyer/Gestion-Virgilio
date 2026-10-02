-- v26.20 (Luis, 02/10/2026) — PEDIDOS DISRUPTIVOS del reporte de pedidos por artículo (manual 31).
-- Lo usa estadisticas.js (📑 Estadísticas ISIS → Pedidos LK/CH): el artículo con un pedido disruptivo va en ROJO
-- y NEGRITA y la columna I lleva el detalle (cliente, cuánto, cuándo, contra qué promedio).
--
-- APLICADO el 02/10/2026 (el comentario de adentro de la función dice v26.19: es la etiqueta con que se aplicó;
-- la versión de la app salió v26.20 porque otra sesión publicó la v26.19 en el medio). Cómo se aplicó, porque el DROP de la versión anterior se colgaba en el MCP (60 s, sin
-- lock ni timeout de Postgres — mismo pozo que gv_hotsale_items_super, v25.98):
--   1) la versión v26.17 se renombró a gv_isis_estad_pedidos_disruptivos_v2617 (rollback, EXECUTE sólo service_role);
--   2) esta se creó como gv_isis_estad_pedidos_disruptivos_n y se RENOMBRÓ al nombre final.
-- md5(prosrc) vivo al 02/10: 511a83928e615d2f43b78ca72f90c218 (7.148 caracteres). Si difiere, alguien la tocó:
-- traer la viva con pg_get_functiondef antes de reemplazarla.
--
-- Cambios contra la v26.17 (la que contaba sólo pedidos web):
--   · HISTORIA (Luis, 02/10: "toma el dato de facturación y contempla facturación hasta que tengamos 12 meses de
--     data de pedidos"): antes del primer pedido web de la empresa (LK 30/03/2026, Chef 29/06/2026) el promedio
--     usa las FACTURAS de ISIS. Una factura = un pedido (no el día: un cliente con sucursales factura varias el
--     mismo día). Cuando la web tenga 12 meses (~marzo 2027 en LK) las facturas salen solas de la ventana.
--   · columna nueva hist_fc (cuántos del promedio salieron de facturas), por eso el DROP/CREATE.
--
-- Medido el 02/10, sept/26 (1,5 s como postgres):
--   LK: 143 pedidos disruptivos (13 incorporaciones · 69 alzas · 61 bajas) → 53 de 201 artículos en rojo;
--       108 de los 143 promedian con facturas de ISIS.
--   CH:  44 pedidos (17 · 9 · 18) → 35 de 95 artículos en rojo; 25 con facturas.
--
-- Rollback (vuelve a la v26.17, sólo pedidos web):
--   alter function public.gv_isis_estad_pedidos_disruptivos(text,date,date) rename to gv_isis_estad_pedidos_disruptivos_v2620;
--   alter function public.gv_isis_estad_pedidos_disruptivos_v2617(text,date,date) rename to gv_isis_estad_pedidos_disruptivos;
--   grant execute on function public.gv_isis_estad_pedidos_disruptivos(text,date,date) to authenticated;
-- (la v26.17 devuelve una columna menos: estadisticas.js no la lee, así que el front no cambia)

create or replace function public.gv_isis_estad_pedidos_disruptivos(p_empresa text, p_desde date, p_hasta date)
 returns table(cod text, cliente text, razon_social text, order_id bigint, fecha date, cajas numeric, unidades numeric,
               prom_cajas numeric, prom_unidades numeric, pedidos_hist integer, hist_fc integer, hist_desde date,
               desvio numeric, tipo text)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
/* v26.19 (Luis, 02/10/2026) — PEDIDOS DISRUPTIVOS del reporte de pedidos por artículo (manual 31).
   Disruptivo = el pedido de un cliente para un artículo difiere más de ±50 % del PROMEDIO DE SUS PEDIDOS
   ANTERIORES de ese artículo en los 12 meses previos (no del promedio mensual). Ej.: 400 el 1/1, 500 el 1/5
   y 700 el 1/10 → el del 1/10 da 700 / 450 = +56 % y se marca. Sin pedidos previos = INCORPORACIÓN.
   Mínimo de 10 cajas (el pedido o su promedio), como las Disruptivas de la Est. Madre.
   HISTORIA (Luis, 02/10): los pedidos web (lk_pedidos_match) desde que existen — LK 30/03/2026, Chef
   29/06/2026 — y, para lo anterior a eso, las FACTURAS de ISIS (isis_lk / isis_ch, en cajas). Una
   factura = un pedido: cada NP se factura aparte y un artículo va en una sola NP del pedido, así que un
   cliente con varias sucursales queda con una factura por sucursal, igual que sus pedidos web.
   Cuando el pipeline web tenga 12 meses (~marzo 2027 en LK) las facturas salen solas de la ventana:
   no hay que tocar nada. Las facturas no se mezclan con la web en el mismo tramo (la web se factura
   después: contaría dos veces). */
with par as (
  select case lower(btrim(coalesce(p_empresa, ''))) when 'lk' then 'lk' when 'ch' then 'chef' when 'chef' then 'chef' end emp,
         coalesce((select nullif(valor_texto, '')::date from public."PPP_Web_Config" where clave = 'gestion_desde'), date '9999-12-31') gdesde,
         (p_desde - interval '12 months')::date hdesde,
         10::numeric piso,          /* mínimo de volumen: el mismo de las Disruptivas de la Est. Madre (DISRUPTIVAS_MIN_CAJAS) */
         0.5::numeric umbral),      /* ±50 % contra el promedio (Luis, 02/10) */
/* desde cuándo hay pedidos web de esa empresa: antes de eso, la historia sale de las facturas */
ws as (select coalesce(min(x.fecha_pedido), date '9999-12-31') web_desde
         from public.lk_pedidos_match x, par where x.empresa = par.emp),
m as (
  select x.empresa, x.order_id, coalesce(x.pedido_origen, x.order_id) pedido, x.fecha_pedido, x.cod_cliente, x.items_string
    from public.lk_pedidos_match x, par
   where x.empresa = par.emp
     and x.fecha_pedido between par.hdesde and p_hasta
     and not exists (select 1 from public."GV_Web_Cancelados" wc where wc.empresa = x.empresa and wc.order_id = x.order_id)
     and not exists (select 1 from public."GV_Pedidos_Anulados" pa where pa.empresa = x.empresa and pa.order_id = x.order_id)
     and not exists (select 1 from public."GV_Clientes_Prueba" pr
                      where lower(btrim(pr.empresa)) in (x.empresa, case x.empresa when 'chef' then 'ch' end)
                        and regexp_replace(btrim(pr.cod), '^0+', '') = regexp_replace(btrim(coalesce(x.cod_cliente, '')), '^0+', ''))),
it as (   /* mismo parseo que gv_isis_estad_pedidos: el código queda igual al de la fila del reporte */
  select m.empresa, regexp_replace(btrim(coalesce(m.cod_cliente, '')), '^0+(?=.)', '') cli, m.pedido, m.order_id, m.fecha_pedido,
         regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', '') cod, (z.r[2])::numeric cajas
    from m
    cross join lateral unnest(string_to_array(coalesce(m.items_string, ''), ',')) t(item)
    cross join lateral (select regexp_match(btrim(t.item), '^(.+)x([0-9]+(?:\.[0-9]+)?)$') r) z
   where z.r is not null),
/* un pedido web = el order_id y sus partes (pedido_origen); la fecha, la del pedido */
pw as (
  select empresa, cli, cod, pedido, min(order_id) order_id, min(fecha_pedido) fecha, sum(cajas) cajas, 'web'::text src
    from it where cod <> '' and cli <> '' group by 1, 2, 3, 4),
/* las facturas de ISIS del tramo SIN pipeline web: una factura = un pedido (no el día: un cliente con
   sucursales factura varias el mismo día y cada una es un pedido distinto, como en la web) */
fd as (
  select x.id, x.fecha, x.contraparte_codigo
    from isis_lk.documentos x, par, ws
   where par.emp = 'lk' and x.familia = 'factura_venta' and x.fecha >= par.hdesde and x.fecha < least(ws.web_desde, p_hasta + 1)
  union all
  select x.id, x.fecha, x.contraparte_codigo
    from isis_ch.documentos x, par, ws
   where par.emp = 'chef' and x.familia = 'factura_venta' and x.fecha >= par.hdesde and x.fecha < least(ws.web_desde, p_hasta + 1)),
fi as (
  select i.documento_id, i.codigo_articulo, i.cantidad_caja from isis_lk.documento_items i, par
   where par.emp = 'lk' and i.documento_id in (select id from fd)
  union all
  select i.documento_id, i.codigo_articulo, i.cantidad_caja from isis_ch.documento_items i, par
   where par.emp = 'chef' and i.documento_id in (select id from fd)),
pf as (
  select par.emp empresa, regexp_replace(btrim(coalesce(fd.contraparte_codigo, '')), '^0+(?=.)', '') cli,
         upper(btrim(fi.codigo_articulo)) cod, fd.id pedido, null::bigint order_id, fd.fecha,
         sum(fi.cantidad_caja) cajas, 'fc'::text src
    from fd join fi on fi.documento_id = fd.id, par
   where coalesce(btrim(fi.codigo_articulo), '') <> '' and coalesce(fi.cantidad_caja, 0) > 0
   group by 1, 2, 3, 4, 6),
p as (select empresa, cli, cod, pedido, order_id, fecha, cajas, src from pw
      union all
      select empresa, cli, cod, pedido, order_id, fecha, cajas, src from pf where cli <> ''),
/* el promedio de los pedidos ANTERIORES de ese cliente para ese artículo, en los 12 meses previos */
h as (
  select p.*, avg(p.cajas) over w prom, count(*) over w n,
         count(*) filter (where p.src = 'fc') over w nfc, min(p.fecha) over w hdesde
    from p
  window w as (partition by p.empresa, p.cli, p.cod order by p.fecha
               range between interval '12 months' preceding and interval '1 day' preceding)),
ux as (select regexp_replace(btrim(cod), '^0+(?=.)', '') base, max(uxb) uxb from public.vista_uxb_articulo where uxb > 0 group by 1),
rs as (select empresa, regexp_replace(btrim(cod), '^0+(?=.)', '') cli, max(razon_social) rs
         from public."GV_Clientes_Direcciones" where coalesce(razon_social, '') <> '' group by 1, 2),
pr as (select empresa, order_id, max(razon_social) rs from public."PPP_Web_Programacion"
        where coalesce(razon_social, '') <> '' group by 1, 2)
select h.cod, h.cli, coalesce(pr.rs, rs.rs, ''), h.order_id, h.fecha, h.cajas,
       h.cajas * ux.uxb, round(h.prom, 2), round(h.prom * ux.uxb, 2), h.n::int, h.nfc::int, h.hdesde,
       case when h.n > 0 then round(h.cajas / h.prom - 1, 4) end,
       case when h.n = 0 then 'incorporacion' when h.cajas > h.prom then 'alza' else 'baja' end
  from h cross join par
  left join ux on ux.base = regexp_replace(regexp_replace(h.cod, '^0+(?=.)', ''), '([0-9E])L$', '\1')
  left join rs on rs.empresa = h.empresa and rs.cli = h.cli
  left join pr on pr.empresa = h.empresa and pr.order_id = h.order_id
 where h.src = 'web'
   and h.fecha between greatest(p_desde, par.gdesde) and p_hasta      /* se marcan sólo los pedidos del período del reporte */
   and ((h.n = 0 and h.cajas > par.piso)
     or (h.n > 0 and greatest(h.cajas, h.prom) > par.piso and abs(h.cajas / h.prom - 1) > par.umbral))
   and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
 order by h.cod collate "C", h.fecha, h.cli
;
$function$;
revoke all on function public.gv_isis_estad_pedidos_disruptivos(text, date, date) from public, anon;
grant execute on function public.gv_isis_estad_pedidos_disruptivos(text, date, date) to authenticated, service_role;
