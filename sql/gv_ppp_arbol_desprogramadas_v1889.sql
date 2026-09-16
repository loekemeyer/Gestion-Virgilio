-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v18.89 (2026-09-16, Thomas) — UNA NP DESPROGRAMADA SALE DE LA PROGRAMACIÓN, TAMBIÉN
-- CUANDO ESTÁ FACTURADA.  Problema 336.
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- EL SÍNTOMA (Thomas, 16/09): *"fíjate los pedidos del cliente 4275. Está en la parte de
-- pedidos atrasados… que supuestamente se iba a entregar el 4 de septiembre, pero también
-- está en a programar. No pueden estar en los dos lados a la vez."*
--
-- Las 4 NP de LK 4275 (Zhang Qikuan: 98587, 98588, 98589, 98590 · tanda D56D · entrega
-- 04/09) aparecían al mismo tiempo en «Pedidos atrasados» y en «A Programar».
--
-- POR QUÉ. El 11/09 (v16.03) se las desprogramó a mano — `GV_PPP_Prog_Override`
-- `desprogramada = true`, con `tanda_previa = D56D` — porque estaban pickeadas, armadas y
-- facturadas pero NUNCA tuvieron Carga Camión. Esa marca hace dos cosas bien:
--   · `gv_ppp_programacion_diaria` les devuelve tanda = '' y fecha_entrega = ''  → salen de
--     la programación;
--   · `gv_ppp_isis_sin_tanda` las deja entrar **aunque estén facturadas** (regla de la
--     v15.93, punto 4)                                                          → A Programar.
--
-- Lo que no miraba el override era `gv_ppp_prog_arbol`, que arma el universo con CUATRO
-- fuentes y `distinct on (np)`:
--     1 gv_ppp_programacion_diaria (ISIS)   3 Facturacion_NP   (origen 'fact')
--     2 PPP_Web_Programacion                4 GV_PPP_Entregados_Historico
-- La fuente 1 ya no las traía (fecha vacía), pero la **fuente 3 sí**: `Facturacion_NP`
-- guarda `tanda = D56D` y `fecha_salida = 2026-09-04`, y nadie le preguntaba si esa NP
-- seguía programada. Así volvían a la PPP del 04/09, y como ese día ya pasó y nunca
-- tuvieron CCN, `gv_ppp_atrasados` (que se para sobre el mismo árbol) las contaba como
-- atrasadas. Dos pantallas, un pedido, dos verdades.
--
-- MEDIDO ANTES DEL CAMBIO (16/09):
--   · 18 filas en `gv_ppp_atrasados()`; 4 son estas.
--   · 5 NP con `desprogramada = true`; las 4 facturadas se duplicaban, la quinta (98617,
--     tanda previa E12I, sin factura) no — porque no tiene de dónde volver.
--   · Y el mismo agujero dejaba pasar a **98050** (Ferrero Santiago Miguel, C98F, 29/07),
--     que está `oculto = true` Y en `NP_Canceladas`, y aun así figuraba en la programación
--     del 29/07 por la fuente 3.
--
-- QUÉ SE CAMBIA. Una CTE `fuera` y una condición, en las DOS funciones que comparten el
-- universo (el encabezado de la v17.66 ya avisaba: *"Si se toca una, tocar la otra"*):
--
--     fuera as (  select o.np from "GV_PPP_Prog_Override" o where o.oculto or o.desprogramada
--                 union
--                 select regexp_replace(btrim(coalesce(c.np,'')), '\.0+$','') from "NP_Canceladas" c )
--     uni   as (  … where … and not exists (select 1 from fuera x where x.np = f.np) )
--
-- O sea: la NP desprogramada, oculta o cancelada **no entra por ninguna de las cuatro
-- fuentes**, no sólo por la de ISIS. El criterio es el mismo que ya usan las tres vistas
-- del espejo y `gv_pedidos_web_excluidos`; lo único que faltaba era aplicarlo acá.
--
-- Lo que NO cambia: una NP facturada cuya fila de ISIS desapareció del espejo sigue
-- entrando por la fuente 3 (es para lo que existe). Hoy son, entre otras, 98507 (Perez
-- Zarate, 01/09) y 98502 (Clapera, 03/09): ninguna tiene override, así que se quedan.
--
-- IMPACTO MEDIDO (después):
--   gv_ppp_atrasados()                → 18 filas → 14 (se van las 4 de 4275)
--   gv_ppp_avance_dias('2026-09-04')  → 23 pedidos / 3,901 m³ → 19 / 3,435
--   gv_ppp_prog_arbol('2026-01-01','2026-12-31') con oculto/cancelada → 1 fila → 0
--   gv_ppp_isis_sin_tanda (A Programar) → las 4 NP SIGUEN ahí, que es donde tienen que estar
--
-- OBJETOS: los dos son nuestros (`gv_*`). No se toca ninguna tabla ni ninguna función de
-- Producción, y no se escribe un solo dato: esto es sólo lectura.
--
-- ROLLBACK: volver a correr `sql/gv_ppp_prog_arbol_v1766.sql` (es idéntico a lo que había
-- vivo, verificado el 16/09 con `pg_get_functiondef`) y el bloque de `gv_ppp_avance_dias`
-- de `sql/backups/gv_ppp_avance_dias_20260916_pre_v1889.sql`.
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1) El árbol de Programación (y, por arriba, Pedidos atrasados) ─────────────────────
create or replace function public.gv_ppp_prog_arbol(p_desde date, p_hasta date)
returns table(
  fecha        date,
  tanda        text,
  np           text,
  np_num       numeric,
  cod          text,
  razon_social text,
  localidad    text,
  zona         text,
  zona_corta   text,
  empresa      text,
  origen       text,
  m3           numeric,
  estado       text,
  estado_orden integer,
  clave        text,
  pide_horario boolean,
  horario_fecha  date,
  horario_franja text,
  horario_origen text,
  barrio       text,
  fecha_pedido date
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
with fuentes as (
  select 1 as pri,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as np,
         upper(btrim(coalesce(p.tanda, '')))                               as tanda,
         coalesce(p.m3, 0)::numeric                                        as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date                as fe,
         coalesce(btrim(p.cod), '')                                        as cod,
         coalesce(btrim(p.razon_social), '')                               as razon_social,
         coalesce(nullif(btrim(coalesce(p.barrio, '')), ''),
                  btrim(coalesce(p.direccion, '')))                        as localidad,
         coalesce(btrim(p.zona), '')                                       as zona,
         regexp_replace(btrim(p.np), '\.0+$', '')                          as clave,
         nullif(btrim(coalesce(p.barrio, '')), '')                          as barrio,
         case when left(btrim(coalesce(p.fecha_recep, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(p.fecha_recep), 10)::date end                 as fecha_pedido,
         'isis'::text                                                      as origen
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
  union all
  select 2,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))),
         coalesce(w.m3, 0)::numeric,
         w.fecha_entrega,
         coalesce(btrim(w.cod_cliente), ''),
         coalesce(btrim(w.razon_social), ''),
         coalesce(nullif(btrim(coalesce(w.barrio, '')), ''), btrim(coalesce(w.direccion, ''))),
         coalesce(btrim(w.zona), ''),
         w.order_id::text,
         nullif(btrim(coalesce(w.barrio, '')), ''),
         w.fecha_recep::date,
         'web'
    from public."PPP_Web_Programacion" w
   where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  select 3,
         regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))),
         coalesce(f.m3, 0)::numeric,
         f.fecha_salida,
         coalesce(btrim(f.cod_cliente), ''),
         coalesce(btrim(f.razon_social), ''),
         '', '', regexp_replace(upper(btrim(f.np)), '\.0+$', ''), null::text, null::date, 'fact'
    from public."Facturacion_NP" f
   where f.fecha_salida is not null
  union all
  select 4,
         regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))),
         coalesce(h.m3, 0)::numeric,
         case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(h.fecha_entrega), 10)::date end,
         coalesce(btrim(h.cod), ''),
         coalesce(btrim(h.rs), ''),
         '', '', regexp_replace(btrim(h.np), '\.0+$', ''), null::text, null::date, 'hist'
    from public."GV_PPP_Entregados_Historico" h
),
-- v18.89 — la NP que un supervisor sacó de la programación (desprogramada), la que se
-- oculta por duplicar un pedido web, y la cancelada, NO entran por NINGUNA fuente. Sin
-- esto volvían por Facturacion_NP con su tanda y su fecha de salida viejas, y el mismo
-- pedido quedaba en Programación / Atrasados y en A Programar a la vez.
fuera as (
  select o.np
    from public."GV_PPP_Prog_Override" o
   where coalesce(o.oculto, false) or coalesce(o.desprogramada, false)
  union
  select regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '')
    from public."NP_Canceladas" c
),
uni as (
  select distinct on (f.np) f.*
    from fuentes f
   where f.np <> '' and f.fe is not null
     and not exists (select 1 from fuera x where x.np = f.np)
   order by f.np, f.pri, f.m3 desc
),
dia as (select * from uni where fe between p_desde and p_hasta),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP')
     and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
     and r.ts_cliente >= (p_desde - interval '60 days')
),
pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc),
arm  as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc),
salio as (   -- cargado al camión (CCN) o remito controlado (CRN) = salió, o sea armado sí o sí
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
est as (
  select d.fe, d.np, d.tanda, d.m3, d.cod, d.razon_social, d.localidad, d.zona, d.origen, d.clave, d.barrio, d.fecha_pedido,
         (fc.np is not null)                                   as b_fact,
         (s.np is not null or a.opcion = 'TAP')                as b_arm,
         (a.opcion = 'AP' or p.opcion in ('TP','EP'))          as b_curso
    from dia d
    left join salio s on s.np = upper(d.np)
    left join fact fc on fc.np = upper(d.np)
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
)
select e.fe,
       coalesce(nullif(e.tanda, ''), '—'),
       e.np,
       nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric,
       e.cod,
       e.razon_social,
       e.localidad,
       e.zona,
       case when e.zona ~* 'retira'                                    then 'Retira'
            when public.gv_es_super_np(e.np, e.cod)
              or e.zona ~* 'super|coto|carrefour|chango|krikos'        then 'Súper'
            else coalesce(substring(e.zona, '^(Zona\s*[0-9]+)'), nullif(btrim(e.zona), ''), 'Sin zona') end,
       -- una NP web ya viene etiquetada (LK 0052 / CH pedido 88); una de ISIS se deduce del número,
       -- igual que en gv_ppp_detalle_dia: arriba de 90000 es Loekemeyer, si no Chef.
       case when upper(e.np) like 'LK%' then 'LK'
            when upper(e.np) like 'CH%' then 'CH'
            when coalesce(nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'LK'
            else 'CH' end,
       e.origen,
       e.m3,
       case when e.b_fact  then 'facturado'
            when e.b_arm   then 'armado'
            when e.b_curso then 'proceso'
            else                'pendiente' end,
       case when e.b_fact  then 4
            when e.b_arm   then 3
            when e.b_curso then 2
            else                1 end,
       e.clave,
       public.gv_pide_horario_np(e.np, e.cod, e.zona),
       h.fecha, h.franja, h.origen,
       e.barrio, e.fecha_pedido
  from est e
  -- el horario se busca por la clave del pedido Y por la NP: en A Programar la clave de un
  -- pedido web es su order_id, y cuando se programa recibe ademas su NP.
  left join public."GV_Pedido_Horario" h
    on h.empresa = public.gv_emp_de_np(e.np)
   and h.clave in (e.clave, regexp_replace(upper(btrim(e.np)), '\.0+$', ''))
 order by e.fe, coalesce(nullif(e.tanda, ''), '—'),
          nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric nulls last, e.np;
$function$;

revoke all on function public.gv_ppp_prog_arbol(date, date) from public;
grant execute on function public.gv_ppp_prog_arbol(date, date) to anon, authenticated;

comment on function public.gv_ppp_prog_arbol(date, date) is
  'Programación como árbol día → tanda → NP, con el estado de cada NP ya decidido. Mismo '
  'universo que gv_ppp_avance_dias (4 fuentes, distinct on np). v18.89: la NP desprogramada, '
  'oculta o cancelada no entra por ninguna fuente — antes volvía por Facturacion_NP y quedaba '
  'en Programación y en A Programar a la vez.';

-- ── 2) El gemelo: el «Avance del día» ──────────────────────────────────────────────────
create or replace function public.gv_ppp_avance_dias(p_desde date, p_hasta date)
returns table(
  fecha date, pedidos integer, m3 numeric, pick_ped integer, pick_m3 numeric,
  arm_ped integer, arm_m3 numeric, curso_ped integer, sin_ped integer,
  pct_listo integer, pct_armado integer, pct_listo_ped integer, pct_armado_ped integer,
  pct_listo_m3 integer, pct_armado_m3 integer, base text, curso_m3 numeric, sin_m3 numeric,
  fact_ped integer, fact_m3 numeric, pct_fact integer, pct_curso integer, pct_sin integer
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
with fuentes as (
  -- ⚠ TABLAS BASE, no gv_ppp_en_salida / gv_ppp_entregados: esas dos vistas tardan 3 y 4 segundos
  --    y el rol anon corta a los 3 (statement_timeout). Ver §3.ef.
  select 1 as pri, regexp_replace(btrim(p.np), '\.0+$', '') as np,
         upper(btrim(coalesce(p.tanda, ''))) as tanda, coalesce(p.m3, 0)::numeric as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date as fe
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
  union all
  select 2, public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))), coalesce(w.m3, 0)::numeric, w.fecha_entrega
    from public."PPP_Web_Programacion" w where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  -- ya facturado: salió de la programación de ISIS. fecha_salida hace de fecha de entrega,
  -- igual que en gv_ppp_en_salida.
  select 3, regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))), coalesce(f.m3, 0)::numeric, f.fecha_salida
    from public."Facturacion_NP" f where f.fecha_salida is not null
  union all
  select 4, regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))), coalesce(h.m3, 0)::numeric,
         case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(h.fecha_entrega), 10)::date end
    from public."GV_PPP_Entregados_Historico" h
),
-- v18.89 — mismo filtro que gv_ppp_prog_arbol: si se toca una, se toca la otra, si no el
-- «Avance del día» y la tabla de Programación dicen números distintos del mismo día.
fuera as (
  select o.np
    from public."GV_PPP_Prog_Override" o
   where coalesce(o.oculto, false) or coalesce(o.desprogramada, false)
  union
  select regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '')
    from public."NP_Canceladas" c
),
uni as (
  select distinct on (f.np) f.np, f.tanda, f.m3, f.fe
    from fuentes f
   where f.np <> '' and f.fe is not null
     and not exists (select 1 from fuera x where x.np = f.np)
   order by f.np, f.pri, f.m3 desc
),
dia as (select * from uni where fe between p_desde and p_hasta),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> '' and r.ts_cliente >= (p_desde - interval '60 days')
),
pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc),
arm  as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc),
salio as (   -- cargado al camión (CCN) o remito controlado (CRN) = salió, o sea armado sí o sí
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
est as (
  select d.fe, d.m3,
         case when s.np is not null then 'armado'
              when a.opcion = 'TAP'  then 'armado'
              when a.opcion = 'AP'   then 'armando'
              when p.opcion = 'TP'   then 'picking'
              when p.opcion = 'EP'   then 'pickeando'
              else 'sin' end as est,
         (fc.np is not null) as facturada
    from dia d
    left join salio s on s.np = upper(d.np)
    left join fact fc on fc.np = upper(d.np)
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
),
agg as (
  select fe,
         count(*)::int as pedidos,
         round(sum(m3), 3) as m3,
         count(*) filter (where est in ('armado','armando','picking'))::int as pick_ped,
         round(coalesce(sum(m3) filter (where est in ('armado','armando','picking')), 0), 3) as pick_m3,
         count(*) filter (where est = 'armado')::int as arm_ped,
         round(coalesce(sum(m3) filter (where est = 'armado'), 0), 3) as arm_m3,
         count(*) filter (where est in ('armando','picking','pickeando'))::int as curso_ped,
         round(coalesce(sum(m3) filter (where est in ('armando','picking','pickeando')), 0), 3) as curso_m3,
         count(*) filter (where est = 'sin')::int as sin_ped,
         round(coalesce(sum(m3) filter (where est = 'sin'), 0), 3) as sin_m3,
         count(*) filter (where est = 'armado' and facturada)::int as fact_ped,
         round(coalesce(sum(m3) filter (where est = 'armado' and facturada), 0), 3) as fact_m3
    from est group by fe
)
select g.fecha,
       coalesce(a.pedidos, 0), coalesce(a.m3, 0),
       coalesce(a.pick_ped, 0), coalesce(a.pick_m3, 0),
       coalesce(a.arm_ped, 0), coalesce(a.arm_m3, 0),
       coalesce(a.curso_ped, 0), coalesce(a.sin_ped, 0),
       public.gv_pct(a.pick_ped, a.pedidos),
       public.gv_pct(a.arm_ped,  a.pedidos),
       public.gv_pct(a.pick_ped, a.pedidos),
       public.gv_pct(a.arm_ped,  a.pedidos),
       public.gv_pct(a.pick_m3,  a.m3),
       public.gv_pct(a.arm_m3,   a.m3),
       'pedidos'::text,
       coalesce(a.curso_m3, 0), coalesce(a.sin_m3, 0),
       coalesce(a.fact_ped, 0), coalesce(a.fact_m3, 0),
       public.gv_pct(a.fact_ped,  a.arm_ped),
       public.gv_pct(a.curso_ped, a.pedidos),
       public.gv_pct(a.sin_ped,   a.pedidos)
  from (select generate_series(p_desde, p_hasta, interval '1 day')::date as fecha) g
  left join agg a on a.fe = g.fecha
 order by 1;
$function$;

comment on function public.gv_ppp_avance_dias(date, date) is
  'Avance por día (pedidos / m³ / % facturado, armado, en curso y sin empezar). Mismo universo '
  'que gv_ppp_prog_arbol. v18.89: la NP desprogramada, oculta o cancelada no entra por ninguna '
  'fuente.';
