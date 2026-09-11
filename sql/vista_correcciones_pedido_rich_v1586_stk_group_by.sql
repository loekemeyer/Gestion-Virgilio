-- v15.86 (2026-09-11) — Corregir códigos: cada NP salía DOS veces y la cola contaba el doble.
-- Thomas, mirando el panel: *"¿Puede ser que acá figure dos veces y que eso signifique que el pedido
-- está duplicado, el 98678?"*. No: el pedido está bien (la NP 98678 pide el 565 una sola vez).
--
-- CAUSA: el CTE `stk` hacía `select norm_cod(cod_art), <suma de columnas> from vista_saldos_stock`
-- SIN group by. Desde la v15.71 (§3.cl, "la empresa es un atributo del lugar") esa vista devuelve
-- UNA FILA POR (cod_art, empresa): el 565 tiene fila **LK = 0** y fila **Mixto = 2**. Con eso el
-- `left join stk s_sec on s_sec.cod = norm_cod(p.sec)` duplicaba cada fila base.
--
-- CONSECUENCIA (no era sólo estético): la cola por secundario de la v15.66/67 contaba
-- "pedidas 12 en 12 NP" cuando son 6 cajas en 6 NP, cada NP ocupaba DOS lugares y se comía stock
-- fantasma, así que NP que tenían que salir verdes salían rojas ("cambiá la NP al principal").
-- Y `stk_sec` mostraba el saldo de UNA empresa (0 ó 2) en vez del total (2).
--
-- FIX: `sum(...) ... group by 1` en `stk`. Nada más cambia: mismas 20 columnas, mismo orden.
-- MEDIDO: vista 13 filas → 7 (una por NP+artículo, que es lo que hay); 565 = 12/12 → 6 cajas en 6 NP;
--   98664 y 98678 pasan a verde (le alcanza el 565), 98688/98621 y las tres pickeadas siguen rojas.
-- ROLLBACK: correr el `create or replace view` de
--   sql/vista_correcciones_pedido_rich_v1567_orden_sin_pickear.sql (vuelve el duplicado).

create or replace view public.vista_correcciones_pedido_rich as
with pending as (
  select vps.np, vps.cod_secundario as sec, vps.cod_principal as ppal, vps.descripcion, vps.cajas
  from vista_pedidos_secundarios vps
  where not (exists (select 1 from "Correcciones_Pedido" cp
                     where cp.np = vps.np and cp.cod_secundario = vps.cod_secundario
                       and coalesce(cp.origen, 'operadora'::text) <> 'auto'::text))
), ppp as (
  select distinct on ("PPP_Programacion_Diaria".np) "PPP_Programacion_Diaria".np,
    nullif(btrim("PPP_Programacion_Diaria".tanda), ''::text) as tanda,
    "PPP_Programacion_Diaria".razon_social,
    "PPP_Programacion_Diaria".fecha_entrega
  from "PPP_Programacion_Diaria"
  where ("PPP_Programacion_Diaria".np in (select pending.np from pending))
  order by "PPP_Programacion_Diaria".np
), stk as (
  -- v15.86: UNA fila por código. `vista_saldos_stock` devuelve una fila por (cod_art, empresa)
  -- desde la v15.71 (§3.cl), así que sin este group by el left join duplicaba TODA la vista.
  select norm_cod(vista_saldos_stock.cod_art) as cod,
    sum(coalesce(vista_saldos_stock.terminado, 0::numeric) + coalesce(vista_saldos_stock.excedente, 0::numeric)
      + coalesce(vista_saldos_stock.a_guardar, 0::numeric) + coalesce(vista_saldos_stock.racks, 0::numeric)
      + coalesce(vista_saldos_stock.racks_ch, 0::numeric) + coalesce(vista_saldos_stock.para_envasar, 0::numeric)) as total
  from vista_saldos_stock
  group by 1
), ent as (
  select distinct on ("Entregas_Virgilio".np, (norm_cod("Entregas_Virgilio".cod_art))) "Entregas_Virgilio".np,
    norm_cod("Entregas_Virgilio".cod_art) as cod,
    "Entregas_Virgilio".cajas_pedidas, "Entregas_Virgilio".cajas_entregadas,
    "Entregas_Virgilio".cajas_falto, "Entregas_Virgilio".fecha_salida
  from "Entregas_Virgilio"
  where ("Entregas_Virgilio".np in (select pending.np from pending))
  order by "Entregas_Virgilio".np, (norm_cod("Entregas_Virgilio".cod_art)), "Entregas_Virgilio".fecha_salida desc nulls last
), fact as (
  select distinct on ("Facturacion_NP".np) "Facturacion_NP".np, "Facturacion_NP".razon_social,
    nullif(btrim("Facturacion_NP".tanda), ''::text) as tanda
  from "Facturacion_NP"
  where ("Facturacion_NP".np in (select pending.np from pending))
  order by "Facturacion_NP".np
), tanda_evts as (
  select "Registros_Produccion_Virgilio".texto as tanda, "Registros_Produccion_Virgilio".opcion,
    "Registros_Produccion_Virgilio".ts_cliente,
    row_number() over (partition by "Registros_Produccion_Virgilio".texto,
      (case when "Registros_Produccion_Virgilio".opcion = any (array['EP'::text, 'TP'::text]) then 'pick'::text else 'arm'::text end)
      order by "Registros_Produccion_Virgilio".ts_cliente desc) as rn
  from "Registros_Produccion_Virgilio"
  where ("Registros_Produccion_Virgilio".opcion = any (array['EP'::text, 'TP'::text, 'AP'::text, 'TAP'::text]))
    and (nullif(btrim("Registros_Produccion_Virgilio".texto), ''::text) in
         (select distinct ppp_1.tanda from ppp ppp_1 where ppp_1.tanda is not null))
    and not es_legajo_test("Registros_Produccion_Virgilio".legajo)
), tanda_status as (
  select tanda_evts.tanda,
    max(case when (tanda_evts.opcion = any (array['EP'::text, 'TP'::text])) and tanda_evts.rn = 1 then tanda_evts.opcion else null::text end) as last_pick,
    max(case when (tanda_evts.opcion = any (array['AP'::text, 'TAP'::text])) and tanda_evts.rn = 1 then tanda_evts.opcion else null::text end) as last_arm
  from tanda_evts
  where tanda_evts.rn = 1
  group by tanda_evts.tanda
), base as (
  -- === hasta acá, la vista tal como estaba (v10.10 + es_legajo_test fase B) ===
  select p.np, p.sec, p.ppal, p.descripcion, p.cajas,
    coalesce(ppp.razon_social, f.razon_social, ''::text) as razon_social,
    coalesce(ppp.tanda, f.tanda, ''::text) as tanda,
    coalesce(ppp.fecha_entrega, e_sec.fecha_salida, ''::text) as fecha,
    coalesce(s_sec.total, 0::numeric) as stk_sec,
    coalesce(s_ppal.total, 0::numeric) as stk_ppal,
    e_any.cajas_pedidas as ent_ped,
    e_any.cajas_entregadas as ent_entr,
    e_any.cajas_falto as ent_falto,
    case
      when f.np is not null then 'facturado'::text
      when ts.last_pick is null then 'sinpickear'::text
      when ts.last_pick = 'EP'::text then 'enpicking'::text
      when ts.last_pick = 'TP'::text and ts.last_arm = 'TAP'::text then 'afacturar'::text
      when ts.last_pick = 'TP'::text then 'pickeado'::text
      else 'sinpickear'::text
    end as estado
  from pending p
    left join ppp on ppp.np = p.np
    left join stk s_sec on s_sec.cod = norm_cod(p.sec)
    left join stk s_ppal on s_ppal.cod = norm_cod(p.ppal)
    left join ent e_sec on e_sec.np = p.np and e_sec.cod = norm_cod(p.sec)
    left join ent e_ppal on e_ppal.np = p.np and e_ppal.cod = norm_cod(p.ppal)
    left join lateral (select coalesce(e_sec.cajas_pedidas, e_ppal.cajas_pedidas) as cajas_pedidas,
                              coalesce(e_sec.cajas_entregadas, e_ppal.cajas_entregadas) as cajas_entregadas,
                              coalesce(e_sec.cajas_falto, e_ppal.cajas_falto) as cajas_falto) e_any on true
    left join fact f on f.np = p.np
    left join tanda_status ts on ts.tanda = nullif(btrim(coalesce(ppp.tanda, f.tanda)), ''::text)
), cola as (
  -- v15.67 — cola por código SECUNDARIO: PRIMERO las NP que todavía no se pickearon (las ya pickeadas
  -- se llevaron el principal y no pueden usar el secundario), después la que sale antes, después la NP
  -- más baja. Estado: sin pickear → en picking → pickeado → a facturar → facturado.
  select b.*,
    sum(b.cajas) over (partition by norm_cod(b.sec)) as sec_pedido_total,
    count(*)     over (partition by norm_cod(b.sec)) as sec_np_total,
    row_number() over w as sec_orden,
    coalesce(sum(b.cajas) over (w rows between unbounded preceding and 1 preceding), 0::numeric) as sec_acum_antes
  from base b
  window w as (partition by norm_cod(b.sec)
               order by case b.estado when 'sinpickear' then 0 when 'enpicking' then 1 when 'pickeado' then 2 when 'afacturar' then 3 else 4 end,
                        nullif(b.fecha, ''::text) nulls last,
                        b.np)
)
select np, sec, ppal, descripcion, cajas, razon_social, tanda, fecha, stk_sec, stk_ppal, ent_ped, ent_entr, ent_falto, estado,
  sec_pedido_total,
  sec_np_total,
  sec_orden,
  sec_acum_antes,
  greatest(stk_sec - sec_acum_antes, 0::numeric) as sec_disp,
  (stk_sec - sec_acum_antes) >= cajas as sec_cubre
from cola
order by norm_cod(sec), sec_orden;

-- MEDIDO después de aplicar (11/09): la vista pasa de 13 filas a 7 (una por NP+artículo).
--   565 · stock 2 · 6 cajas en 6 NP (antes decía 12 en 12):
--     98664 D67I sin pickear 10/09 · orden 1 · disp 2 · cubre TRUE   (antes: dos filas, una roja)
--     98678 D67G sin pickear 10/09 · orden 2 · disp 1 · cubre TRUE   (la que preguntó el dueño)
--     98688 D67L sin pickear 10/09 · orden 3 · disp 0 · FALSE
--     98621 D69B sin pickear 14/09 · orden 4 · disp 0 · FALSE
--     98674 D67F pickeado   10/09 · orden 5 · FALSE   ·  98671 D67E a facturar · orden 6 · FALSE
--   338 → 941E (98532) queda igual: ese código tiene una sola fila de stock, nunca se duplicó.
