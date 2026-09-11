-- v15.67 (2026-09-11) — Corregir códigos: la cola del secundario pone PRIMERO las NP sin pickear.
-- Dueño: "1 claro" a la pregunta de la v15.66 (¿el 565 lo toman las NP que todavía no se pickearon?).
-- Las tres NP "pickeado" (D67A, D67E, D67F) ya se llevaron 607E (PKC), así que no pueden usar los 2 de 565
-- que siguen en góndola. Sólo cambia el ORDER BY de la ventana `w`: estado (sin pickear → en picking →
-- pickeado → a facturar → facturado), después fecha de salida, después NP. Mismas 20 columnas que la v15.66:
-- el front no se entera (sólo cambia la leyenda del panel).
-- Aplicado con apply_migration `gv_corr_sec_orden_v1567`.
-- ROLLBACK: volver a correr el `create or replace view` de sql/vista_correcciones_pedido_rich_v1566_reparto_sec.sql
-- (orden fecha → estado → NP). Ahí está también la definición anterior a la v15.66.

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
  select norm_cod(vista_saldos_stock.cod_art) as cod,
    coalesce(vista_saldos_stock.terminado, 0::numeric) + coalesce(vista_saldos_stock.excedente, 0::numeric)
      + coalesce(vista_saldos_stock.a_guardar, 0::numeric) + coalesce(vista_saldos_stock.racks, 0::numeric)
      + coalesce(vista_saldos_stock.racks_ch, 0::numeric) + coalesce(vista_saldos_stock.para_envasar, 0::numeric) as total
  from vista_saldos_stock
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

-- Prueba (11/09, después de aplicar): 565 stk 2, 7 NP / 8 cajas →
--   98664 (D67I, sin pickear, 10/09) sec_orden 1, sec_disp 2, sec_cubre TRUE
--   98678 (D67G, sin pickear, 10/09) sec_orden 2, sec_disp 1, sec_cubre TRUE
--   98688 (D67L, sin pickear, 10/09), 98621 (D69B, sin pickear, 14/09) → sec_disp 0, FALSE
--   98662 (D67A, pickeado, 2 cajas), 98671 (D67E), 98674 (D67F) → al final de la cola, FALSE
