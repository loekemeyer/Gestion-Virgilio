-- =====================================================================================
-- v30.27 (Thomas, 2026-10-13) · PISO DE STOCK DEL SUPER EN EL GENERADOR DE OC
-- Proyecto: Virgilio (hrxfctzncixxqmpfhskv). Aplicado 2026-10-13.
--
-- PROBLEMA (caso 789 "Pisa Papas", Chef)
--   Un articulo de baja rotacion que compra un supermercado quiebra stock: el super no
--   compra todos los meses, pero cuando compra se lleva un pedido grande. La Estadistica
--   Madre (fn_proyeccion_oc_virgilio en LK, promedio de ventanas 6/12 meses) diluye ese
--   pedido en los meses sin compra: 789 proyectaba 8,83 caj/mes, el maximo de OC = ceil(8,83 x 1,5)
--   = 14, y Chango Mas (Dorinka 2686) habia pedido 18 en un mes. 14 < 18 = quiebre.
--
-- DECISION (Thomas): NO inflar la Estadistica Madre (es cuadro unico LK+Gestion, arrastra
--   GP2.est_madre y el semaforo de colores, y vive en LK). En su lugar, un PISO DE STOCK en
--   el generador de OC de Virgilio. D3: aplica a TODO codigo con cliente en GV_Supers.
--   D4: el piso es un PERCENTIL de los pedidos del super (no el promedio -> daria 7,33, menos
--   que hoy; no el maximo -> seria la incorporacion, siempre la compra mas alta y puntual),
--   configurable en Stock_Config('piso_super_percentil', default 0,75).
--
-- COMO FUNCIONA
--   maximo_OC = GREATEST(maximo_actual, piso_super)
--   Se auto-apaga en alta rotacion: si el motor ya proyecta mas que un pedido del super, gana
--   el motor y el piso es invisible (cero sobrestock). Medido 13/10: 129 codigos con super en
--   el generador, el piso solo MUERDE en 13 (baja rotacion); 107 de alta rotacion sin impacto.
--   789: maximo 14 -> 17, total 8 -> 11.
--
-- NOTAS / LIMITES
--   · Historia: hoy Entregas_Virgilio tiene ~4 meses de pedidos; la ventana de 12 meses
--     (Stock_Config 'piso_super_meses', default 12) recien pesa cuando haya mas data.
--   · El piso es por cod_canon (sin split de empresa). Un dual con super aplicaria el mismo
--     piso a su fila LK y CH; como solo muerde en baja rotacion, el riesgo es chico.
--   · Super = cliente activo en GV_Supers (empresa lk/chef), por codigo de cliente.
--   · Centinela GV_Reglas_Centinela id 455 (patron 'gv_piso_super' en vista_generador_oc).
-- =====================================================================================

create or replace view public.gv_piso_super
with (security_invoker = true) as
with cfg as (
  select coalesce((select valor::numeric from "Stock_Config" where clave='piso_super_percentil'), 0.75) as p,
         coalesce((select valor::numeric from "Stock_Config" where clave='piso_super_meses'), 12) as meses
),
ent as (
  select regexp_replace(e.np, '\.0+$', '') as np,
         canon_cod(e.cod_art) as cod_canon,
         regexp_replace(e.cod_cliente, '\D', '', 'g') as cc,
         max(nullif(btrim(e.fecha_salida), '')) as fecha,
         sum(coalesce(e.cajas_pedidas, 0)) as cajas_ped
  from "Entregas_Virgilio" e
  group by 1, 2, 3
),
npe as (
  select np, case when np ~* '^\s*LK' or (np !~* '^\s*CH' and np ~ '^9') then 'lk' else 'chef' end as empresa
  from (select distinct np from ent) d
),
sup as (
  select e.cod_canon, e.np, e.cajas_ped
  from ent e
  join npe on npe.np = e.np
  join "GV_Supers" s on s.activo and s.empresa = npe.empresa
       and regexp_replace(s.cod, '\D', '', 'g') = e.cc
  where e.cajas_ped > 0
    and e.fecha ~ '^\d{4}-\d{2}-\d{2}$'
    and e.fecha::date >= (current_date - ((select meses from cfg) || ' months')::interval)
)
select cod_canon,
       ceil(percentile_cont((select p from cfg)) within group (order by cajas_ped))::numeric as piso_cajas,
       count(*) as n_pedidos_super
from sup
group by cod_canon;

grant select on public.gv_piso_super to anon, authenticated, service_role;

-- ── vista_generador_oc: inyeccion del piso ─────────────────────────────────────────────
-- Se trajo la definicion VIVA (pg_get_viewdef) y se agrego, SIN tocar el resto (la regla
-- protegida de "pedidos web como demanda" queda intacta: pend_np + PPP_Web_Programacion +
-- gv_demanda_pedidos sin cambios). Dos cambios en el SELECT final:
--   from conmax cm
--   left join public.gv_piso_super ps
--     on regexp_replace(upper(ps.cod_canon),'^0+(?=.)','') = cm.codn_base
--   ... GREATEST(cm.maximo, COALESCE(ps.piso_cajas,0)) AS maximo,
--   ... GREATEST(0, ceil(GREATEST(cm.maximo, COALESCE(ps.piso_cajas,0)) + cm.pedidos - cm.stock))::int AS total,
-- El CREATE OR REPLACE completo se corrio con -- REGLA_CONFIRMADA_POR_USUARIO (Thomas).

-- ROLLBACK
--   Volver vista_generador_oc al SELECT final sin el join ps y con maximo/total sobre cm.maximo
--   (backup: sql/backup_vista_generador_oc_20260818.sql tiene una version previa de referencia).
--   drop view if exists public.gv_piso_super;
--   update "GV_Reglas_Centinela" set activo=false where id=455;
