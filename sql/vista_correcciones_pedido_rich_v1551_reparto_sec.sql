-- v15.51 (2026-09-11) — Corregir códigos: el stock del SECUNDARIO se reparte entre TODAS las NP que lo piden.
-- Dueño, 11/09 (pantalla con 565 → 607E): "acá tenés mal la lógica. Mirá el 565 primero: el stock y sus pedidos".
-- Antes cada NP se comparaba sola contra el stock total del secundario: 565 = 2 en góndola salía "alcanza"
-- para las 7 NP que lo pedían (8 cajas). Ahora la vista arma una COLA por código secundario (fecha de salida →
-- estado → NP) y acumula las cajas: a una NP "le alcanza" sólo si lo que queda después de las NP anteriores
-- cubre sus cajas. Columnas NUEVAS al final (las 14 existentes no cambian de nombre, tipo ni orden):
--   sec_pedido_total  cajas pedidas del secundario en todas las NP pendientes
--   sec_np_total      cuántas NP lo piden
--   sec_orden         lugar de esta NP en la cola (1 = primera)
--   sec_acum_antes    cajas de las NP que están antes en la cola
--   sec_disp          lo que queda del secundario para esta NP = max(stk_sec − sec_acum_antes, 0)
--   sec_cubre         true = le alcanza → "mandalo tal cual, sin tocar NP"; false = URGENTE, cambiar NP al principal
-- Lo leen: index.html facCorreccDataRich (panel), corrLoadBadge (badges del panel supervisor) y el chip de Facturación.
-- Aplicado con apply_migration `gv_corr_sec_reparto_v1551`. Rollback: bloque al final (definición anterior).

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
  -- v15.51 — cola por código SECUNDARIO: primero la que sale antes; a igual fecha, la más avanzada
  -- (a facturar > pickeado > en picking > sin pickear); a igual estado, la NP más baja.
  select b.*,
    sum(b.cajas) over (partition by norm_cod(b.sec)) as sec_pedido_total,
    count(*)     over (partition by norm_cod(b.sec)) as sec_np_total,
    row_number() over w as sec_orden,
    coalesce(sum(b.cajas) over (w rows between unbounded preceding and 1 preceding), 0::numeric) as sec_acum_antes
  from base b
  window w as (partition by norm_cod(b.sec)
               order by nullif(b.fecha, ''::text) nulls last,
                        case b.estado when 'facturado' then 0 when 'afacturar' then 1 when 'pickeado' then 2 when 'enpicking' then 3 else 4 end,
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

-- Prueba (11/09, antes de aplicar, como SELECT sobre la vista vieja): 565 stk 2, 7 NP / 8 cajas →
--   98662 (D67A, 10/09, pickeado, 2 cajas) sec_orden 1, sec_disp 2, sec_cubre TRUE
--   98671, 98674 (pickeado), 98664, 98678, 98688 (sin pickear, 10/09), 98621 (14/09) → sec_disp 0, sec_cubre FALSE
--   338 stk 23, 1 NP (98532, 1 caja) → sec_cubre TRUE.

-- ============================================================================================
-- ROLLBACK — definición anterior (pg_get_viewdef del 2026-09-11 antes de la v15.51). Las 14 columnas
-- viejas quedan iguales; sólo se pierden las 6 nuevas (el front v15.51 cae al criterio viejo
-- stk_sec >= cajas si sec_cubre no viene).
-- ============================================================================================
/*
create or replace view public.vista_correcciones_pedido_rich as
 WITH pending AS (
         SELECT vps.np, vps.cod_secundario AS sec, vps.cod_principal AS ppal, vps.descripcion, vps.cajas
           FROM vista_pedidos_secundarios vps
          WHERE NOT (EXISTS ( SELECT 1 FROM "Correcciones_Pedido" cp
                  WHERE cp.np = vps.np AND cp.cod_secundario = vps.cod_secundario AND COALESCE(cp.origen, 'operadora'::text) <> 'auto'::text))
        ), ppp AS (
         SELECT DISTINCT ON ("PPP_Programacion_Diaria".np) "PPP_Programacion_Diaria".np,
            NULLIF(btrim("PPP_Programacion_Diaria".tanda), ''::text) AS tanda,
            "PPP_Programacion_Diaria".razon_social, "PPP_Programacion_Diaria".fecha_entrega
           FROM "PPP_Programacion_Diaria"
          WHERE ("PPP_Programacion_Diaria".np IN ( SELECT pending.np FROM pending))
          ORDER BY "PPP_Programacion_Diaria".np
        ), stk AS (
         SELECT norm_cod(vista_saldos_stock.cod_art) AS cod,
            COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) AS total
           FROM vista_saldos_stock
        ), ent AS (
         SELECT DISTINCT ON ("Entregas_Virgilio".np, (norm_cod("Entregas_Virgilio".cod_art))) "Entregas_Virgilio".np,
            norm_cod("Entregas_Virgilio".cod_art) AS cod,
            "Entregas_Virgilio".cajas_pedidas, "Entregas_Virgilio".cajas_entregadas, "Entregas_Virgilio".cajas_falto, "Entregas_Virgilio".fecha_salida
           FROM "Entregas_Virgilio"
          WHERE ("Entregas_Virgilio".np IN ( SELECT pending.np FROM pending))
          ORDER BY "Entregas_Virgilio".np, (norm_cod("Entregas_Virgilio".cod_art)), "Entregas_Virgilio".fecha_salida DESC NULLS LAST
        ), fact AS (
         SELECT DISTINCT ON ("Facturacion_NP".np) "Facturacion_NP".np, "Facturacion_NP".razon_social,
            NULLIF(btrim("Facturacion_NP".tanda), ''::text) AS tanda
           FROM "Facturacion_NP"
          WHERE ("Facturacion_NP".np IN ( SELECT pending.np FROM pending))
          ORDER BY "Facturacion_NP".np
        ), tanda_evts AS (
         SELECT "Registros_Produccion_Virgilio".texto AS tanda, "Registros_Produccion_Virgilio".opcion, "Registros_Produccion_Virgilio".ts_cliente,
            row_number() OVER (PARTITION BY "Registros_Produccion_Virgilio".texto, (
                CASE WHEN "Registros_Produccion_Virgilio".opcion = ANY (ARRAY['EP'::text, 'TP'::text]) THEN 'pick'::text ELSE 'arm'::text END)
                ORDER BY "Registros_Produccion_Virgilio".ts_cliente DESC) AS rn
           FROM "Registros_Produccion_Virgilio"
          WHERE ("Registros_Produccion_Virgilio".opcion = ANY (ARRAY['EP'::text, 'TP'::text, 'AP'::text, 'TAP'::text]))
            AND (NULLIF(btrim("Registros_Produccion_Virgilio".texto), ''::text) IN ( SELECT DISTINCT ppp_1.tanda FROM ppp ppp_1 WHERE ppp_1.tanda IS NOT NULL))
            AND NOT es_legajo_test("Registros_Produccion_Virgilio".legajo)
        ), tanda_status AS (
         SELECT tanda_evts.tanda,
            max(CASE WHEN (tanda_evts.opcion = ANY (ARRAY['EP'::text, 'TP'::text])) AND tanda_evts.rn = 1 THEN tanda_evts.opcion ELSE NULL::text END) AS last_pick,
            max(CASE WHEN (tanda_evts.opcion = ANY (ARRAY['AP'::text, 'TAP'::text])) AND tanda_evts.rn = 1 THEN tanda_evts.opcion ELSE NULL::text END) AS last_arm
           FROM tanda_evts WHERE tanda_evts.rn = 1 GROUP BY tanda_evts.tanda
        )
 SELECT p.np, p.sec, p.ppal, p.descripcion, p.cajas,
    COALESCE(ppp.razon_social, f.razon_social, ''::text) AS razon_social,
    COALESCE(ppp.tanda, f.tanda, ''::text) AS tanda,
    COALESCE(ppp.fecha_entrega, e_sec.fecha_salida, ''::text) AS fecha,
    COALESCE(s_sec.total, 0::numeric) AS stk_sec,
    COALESCE(s_ppal.total, 0::numeric) AS stk_ppal,
    e_any.cajas_pedidas AS ent_ped, e_any.cajas_entregadas AS ent_entr, e_any.cajas_falto AS ent_falto,
        CASE
            WHEN f.np IS NOT NULL THEN 'facturado'::text
            WHEN ts.last_pick IS NULL THEN 'sinpickear'::text
            WHEN ts.last_pick = 'EP'::text THEN 'enpicking'::text
            WHEN ts.last_pick = 'TP'::text AND ts.last_arm = 'TAP'::text THEN 'afacturar'::text
            WHEN ts.last_pick = 'TP'::text THEN 'pickeado'::text
            ELSE 'sinpickear'::text
        END AS estado
   FROM pending p
     LEFT JOIN ppp ON ppp.np = p.np
     LEFT JOIN stk s_sec ON s_sec.cod = norm_cod(p.sec)
     LEFT JOIN stk s_ppal ON s_ppal.cod = norm_cod(p.ppal)
     LEFT JOIN ent e_sec ON e_sec.np = p.np AND e_sec.cod = norm_cod(p.sec)
     LEFT JOIN ent e_ppal ON e_ppal.np = p.np AND e_ppal.cod = norm_cod(p.ppal)
     LEFT JOIN LATERAL ( SELECT COALESCE(e_sec.cajas_pedidas, e_ppal.cajas_pedidas) AS cajas_pedidas,
            COALESCE(e_sec.cajas_entregadas, e_ppal.cajas_entregadas) AS cajas_entregadas,
            COALESCE(e_sec.cajas_falto, e_ppal.cajas_falto) AS cajas_falto) e_any ON true
     LEFT JOIN fact f ON f.np = p.np
     LEFT JOIN tanda_status ts ON ts.tanda = NULLIF(btrim(COALESCE(ppp.tanda, f.tanda)), ''::text)
  ORDER BY p.sec, p.np;
*/
