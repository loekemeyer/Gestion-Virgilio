-- =====================================================================
-- vista_generador_oc.sql — El generador de OCs pasa a salir de STOCK (v7.68)
--
-- Pedido del usuario: que la generación de OCs tome los artículos de lo que el sistema
-- lleva y registra como STOCK (no de una lista cargada a mano en OC_Maximos), asigne a
-- cada código el/los proveedor(es) que ya tenemos anotados (y "(sin proveedor)" al resto),
-- y que Objetivo y Uni×Caja NO se carguen a mano (salen de otras tablas).
--
-- Decisiones (confirmadas con el usuario):
--   • Universo   = productos TERMINADOS de `vista_saldos_stock` ∪ lo que vende
--                  (proyeccion_madre) ∪ pedidos pendientes ∪ códigos ya configurados.
--                  Los insumos NO tienen capacidad de góndola ni proyección → no generan.
--   • Máximo     = proyección × índice, topado a capacidad. Si NO hay proyección (sin
--                  ventas en 6m→12m→0), el objetivo = capacidad de góndola (Capacidad_Sector),
--                  pero SOLO para códigos con proveedor real (si no, no se pide por góndola).
--   • Stock      = terminado + a_guardar + racks + excedente, con la familia por EMPRESA
--                  (" LK"/" CH") MERGEADA al código base → arregla el sobre-pedido de los
--                  códigos partidos (437E/438E/439E veían stock 0 y pedían de más).
--   • uni×caja   = `vista_uni_x_caja` (maestro Articulos Virgilio X Tallerista → OC_Maximos
--                  live → proyeccion_madre.uxb). El backup estático de OC_Maximos queda como
--                  copia de seguridad (no en el camino live, para que la vista sea INVOKER).
--
-- SEGURIDAD: ambas vistas son SECURITY INVOKER (respetan la RLS del que consulta) → sin el
-- advisor security_definer_view. Todas las tablas de base son anon-readable (el front ya las
-- lee con la anon key); verificado: anon ve las 501 filas y las 108 generables con uni×caja.
--   • Proveedor  = OC_Maximos (config: proveedor/prop_prov1/proveedor2/prop_prov2/indice/activo).
--                  Sin config → "(sin proveedor)": se MUESTRA en el front para asignarlo,
--                  pero NO se auto-genera (no se puede enviar sin proveedor).
--
-- La leen el front (index.html → ocgEnter / ocgEnterCfg) y el cron (generar/simular_ocs_automaticas).
-- OC_Maximos dejó de ser "la lista": es SOLO la config de proveedor por código (el editor
-- de Configuraciones hace INSERT/PATCH ahí). Objetivo (max_cajas) y uni_x_caja siguen como
-- columnas pero el generador ya no las usa (quedan en el backup estático).
--
-- ⚠ Definición VIVA en las migraciones de Supabase (vista_uni_x_caja_v768,
--    vista_generador_oc_v768c). Este archivo es la copia documentada para el repo.
-- =====================================================================

-- uni×caja por código normalizado, con prioridad maestro → OC_Maximos (live) → uxb.
drop view if exists public.vista_generador_oc;
drop view if exists public.vista_uni_x_caja;
create view public.vista_uni_x_caja with (security_invoker = on) as
with m as ( select regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') as codn, max("Uni_x_Caja")::numeric as u
            from public."Articulos Virgilio X Tallerista" where coalesce("Uni_x_Caja",0)>0 group by 1 ),
o as ( select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, max(uni_x_caja)::numeric as u
       from public."OC_Maximos" where coalesce(uni_x_caja,0)>0 group by 1 ),
p as ( select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, max(uxb)::numeric as u
       from public.proyeccion_madre where coalesce(uxb,0)>0 group by 1 )
select c.codn, coalesce(m.u, o.u, p.u) as uni_x_caja,
       case when m.u is not null then 'maestro' when o.u is not null then 'ocmax' else 'uxb' end as fuente
from (select codn from m union select codn from o union select codn from p) c
left join m on m.codn=c.codn
left join o on o.codn=c.codn
left join p on p.codn=c.codn;
grant select on public.vista_uni_x_caja to anon, authenticated;

-- Vista única del generador de OCs (una fila por código del universo).
create view public.vista_generador_oc with (security_invoker = on) as
with
stk as (
  select regexp_replace(regexp_replace(regexp_replace(upper(btrim(cod_art)),'^0+(?=.)',''),' +(LK|CH)$',''),'·.*$','') as codn,
         sum(coalesce(terminado,0)+coalesce(a_guardar,0)+coalesce(racks,0)+coalesce(excedente,0)) as stock,
         sum(coalesce(terminado,0)+coalesce(a_guardar,0)+coalesce(racks,0)+coalesce(excedente,0)+coalesce(para_envasar,0)+coalesce(racks_ch,0)) as fin_dep,
         max(descripcion) as descripcion
  from public.vista_saldos_stock group by 1
),
proy as ( select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, max(coalesce(proy_cajas_mes,0))::numeric as proy
          from public.proyeccion_madre group by 1 ),
cap as ( select regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, sum(coalesce(cajas_max,0))::numeric as cap
         from public."Capacidad_Sector" group by 1 ),
cfg as ( select distinct on (codn) regexp_replace(upper(btrim(cod)),'^0+(?=.)','') as codn, upper(btrim(cod)) as cod_cfg,
                descripcion, linea,
                nullif(btrim(coalesce(proveedor,'')),'') as proveedor,
                coalesce(prop_prov1,100)::numeric as pr1,
                nullif(btrim(coalesce(proveedor2,'')),'') as proveedor2,
                coalesce(prop_prov2,0)::numeric as pr2,
                case when coalesce(indice,0)>0 then indice::numeric else 1.5 end as indice,
                coalesce(activo,true) as activo
         from public."OC_Maximos" where nullif(btrim(cod),'') is not null
         order by codn, activo desc nulls last ),
pickeadas as ( select distinct upper(btrim(texto)) as tanda from public."Registros_Produccion_Virgilio"
               where opcion='TP' and nullif(btrim(coalesce(texto,'')),'') is not null ),
pend_np as ( select distinct btrim(p.np) as np from public."PPP_Programacion_Diaria" p
             where btrim(p.np) not in (select btrim(np) from public."Facturacion_NP")
               and upper(btrim(coalesce(p.tanda,''))) not in (select tanda from pickeadas) ),
dem as ( select regexp_replace(upper(btrim(b.articulo)),'^0+(?=.)','') as codn, sum(coalesce(b.cajas,0)) as pedidos
         from public."PPP_Base_Pedidos" b join pend_np n on btrim(b.pedido)=n.np
         where nullif(btrim(b.articulo),'') is not null group by 1 ),
ncaja as ( select distinct on (codn) codn, n_caja from (
             select regexp_replace(upper(btrim("Cod_Art")),'^0+(?=.)','') as codn, "N_Caja" as n_caja, count(*) as c
               from public."Articulos_Cajas" where "N_Caja" is not null group by 1,2
           ) t order by codn, c desc, n_caja ),
universo as (
  select codn from stk where fin_dep>0
  union select codn from proy where proy>0
  union select codn from dem
  union select codn from cap where cap>0
  union select codn from cfg
),
base as (
  select u.codn,
    coalesce(c.cod_cfg, u.codn) as cod,
    coalesce(c.descripcion, s.descripcion) as descripcion,
    c.linea,
    coalesce(c.proveedor, '(sin proveedor)') as proveedor,
    (c.proveedor is not null) as tiene_prov_real,
    coalesce(c.pr1, 100) as pr1,
    c.proveedor2,
    coalesce(c.pr2, 0) as pr2,
    coalesce(c.indice, 1.5) as indice,
    coalesce(c.activo, true) as activo,
    (c.codn is not null) as en_config,
    coalesce(s.stock,0) as stock,
    coalesce(pr.proy,0) as proy,
    coalesce(cp.cap,0) as cap,
    coalesce(d.pedidos,0) as pedidos,
    coalesce(ux.uni_x_caja,0) as uni_x_caja,
    nc.n_caja
  from universo u
  left join stk  s  on s.codn=u.codn
  left join proy pr on pr.codn=u.codn
  left join cap  cp on cp.codn=u.codn
  left join dem  d  on d.codn=u.codn
  left join cfg  c  on c.codn=u.codn
  left join ncaja nc on nc.codn=u.codn
  left join public.vista_uni_x_caja ux on ux.codn=u.codn
),
conmax as (
  select b.*,
    case when b.proy>0 then least(ceil(b.proy*b.indice)::numeric, coalesce(nullif(b.cap,0), 1e9))
         when b.tiene_prov_real then coalesce(nullif(b.cap,0), 0)   -- objetivo = capacidad SOLO si hay proveedor real
         else 0 end as maximo
  from base b
)
select cm.*, greatest(0, ceil(cm.maximo + cm.pedidos - cm.stock))::int as total
from conmax cm;
grant select on public.vista_generador_oc to anon, authenticated;
