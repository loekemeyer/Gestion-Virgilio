-- v17.66 (Luis, 2026-09-14) — PROGRAMACIÓN COMO ÁRBOL: día → tanda → NP
--
-- Pedido: *"vamos a cambiar la visualización actual de Programación… una especie de tabla al
-- estilo del módulo de operarios. Arranca con el día, M3, Tandas, NPs, y agrega 4 columnas que son
-- el porcentaje de completado (Facturado, Armado —pendiente de facturar—, En proceso —armando o
-- pickeando— y Pendientes —programados para el día pero no empezados—). Cuando se aprieta sobre un
-- día se expande para mostrar las tandas, y cada tanda se puede apretar para mostrar las NPs."*
--
-- POR QUÉ UNA RPC Y NO CUENTAS EN EL FRONT: el día, la tanda y la NP tienen que cuadrar entre sí.
-- Si el total del día lo calcula una fuente y el de la tanda otra, el supervisor abre el día y las
-- partes no suman al todo. Acá sale UNA fila por NP con su estado YA decidido, y el front sólo
-- agrupa: por construcción, día = Σ tandas = Σ NPs.
--
-- EL UNIVERSO ES EL MISMO QUE `gv_ppp_avance_dias` (v16.97), a propósito: mismas 4 fuentes, mismo
-- `distinct on (np)` con la misma prioridad, misma clasificación de eventos. Si se toca una, tocar
-- la otra — si no, la tabla nueva y el "Avance del día" van a decir números distintos del mismo día.
--
--   1. `gv_ppp_programacion_diaria`  (ISIS, por la vista del espejo: respeta corte y ocultas)
--   2. `PPP_Web_Programacion`        (lo que programó Gestión)
--   3. `Facturacion_NP`              (ya facturado: salió de la programación de ISIS; fecha_salida
--                                     hace de fecha de entrega, igual que en gv_ppp_en_salida)
--   4. `GV_PPP_Entregados_Historico` (histórico)
--
-- ESTADO (los 4 baldes de Luis, mutuamente excluyentes: siempre suman el total del día):
--   facturado  · está en Facturacion_NP
--   armado     · armado y todavía sin facturar (TAP, o cargado al camión / remito controlado)
--   proceso    · armando (AP) o pickeando (EP / TP terminado sin armar)
--   pendiente  · programado para ese día y nadie lo tocó
--
-- ⚠ `ev` se limita a `p_desde - 60 días` igual que en `gv_ppp_avance_dias`: el rol `anon` corta a
-- los 3 s (statement_timeout) y `Registros_Produccion_Virgilio` es el log entero. Ver §3.ef.

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
  estado_orden int,
  -- v17.74 (Luis): el horario del pedido viaja con el pedido hasta Programacion
  clave          text,     -- order_id si es de la pagina, NP si es de ISIS
  pide_horario   boolean,  -- este cliente coordina horario (super, los 3 aparte, o retira)
  horario_fecha  date,
  horario_franja text,
  horario_origen text      -- 'cliente' (lo eligio en la pagina) | 'manual' (lo puso quien programa)
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
         '', '', regexp_replace(upper(btrim(f.np)), '\.0+$', ''), 'fact'
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
         '', '', regexp_replace(btrim(h.np), '\.0+$', ''), 'hist'
    from public."GV_PPP_Entregados_Historico" h
),
uni as (
  select distinct on (np) *
    from fuentes
   where np <> '' and fe is not null
   order by np, pri, m3 desc
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
  select d.fe, d.np, d.tanda, d.m3, d.cod, d.razon_social, d.localidad, d.zona, d.origen, d.clave,
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
       h.fecha, h.franja, h.origen
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
  'v17.66 (Luis) — una fila por NP programada entre dos fechas, con tanda y estado ya resuelto (facturado | armado | proceso | pendiente), para la tabla dia > tanda > NP de la pestana Programacion. Mismo universo y mismas fuentes que gv_ppp_avance_dias: si se toca una, tocar la otra.';

-- ── MEDICIÓN (lo que se corrió el 14/09) ───────────────────────────────────────────────────
-- 1) Los totales por día tienen que dar IGUAL que gv_ppp_avance_dias (que es lo que ya se
--    muestra hoy en "Avance del día"), y los 4 baldes tienen que sumar el total:
--
--    with a as (select * from public.gv_ppp_avance_dias(current_date - 10, current_date + 60)),
--         t as (select fecha, count(*) n, round(sum(m3),3) m3,
--                      count(*) filter (where estado='facturado') fac,
--                      count(*) filter (where estado='armado')    arm,
--                      count(*) filter (where estado='proceso')   pro,
--                      count(*) filter (where estado='pendiente') pen
--                 from public.gv_ppp_prog_arbol(current_date - 10, current_date + 60) group by 1)
--    select t.fecha, a.pedidos, t.n, a.m3, t.m3, t.fac+t.arm+t.pro+t.pen suma
--      from t join a on a.fecha = t.fecha where a.pedidos <> t.n or a.m3 <> t.m3;
--    -- vacío = cuadra
--
-- 2) Y como `anon`, que es quien la llama: `set local role anon; select count(*) from …`.

-- ── ROLLBACK ───────────────────────────────────────────────────────────────────────────────
-- drop function if exists public.gv_ppp_prog_arbol(date, date);
-- (función NUEVA; sólo la usa la pestaña Programación. Sin ella, el front cae a la vista vieja.)
