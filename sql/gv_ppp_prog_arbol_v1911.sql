-- gv_ppp_prog_arbol_v1911.sql — el override de fecha también vale para las ramas `fact` y `hist` · v19.11 (2026-09-16)
--
-- POR QUÉ. El árbol de Programación tiene cuatro fuentes y las dos últimas no viven en ninguna tabla de
-- programación: `Facturacion_NP` (origen `fact`) y `GV_PPP_Entregados_Historico` (`hist`). Una NP que ya salió
-- de la programación viva y sólo figura facturada seguía apareciendo en el árbol con su `fecha_salida`, y NO
-- había forma de cambiarle el día: `GV_PPP_Prog_Override` sólo lo respetaba la rama de ISIS (a través de la
-- vista `gv_ppp_programacion_diaria`). Con el botón «Cambiar de día» por tanda (v19.11) eso se nota: la tanda
-- D53C de Pedidos atrasados (NP 98507, 01/09) es justamente una `fact`.
--
-- QUÉ CAMBIA. Las ramas 3 y 4 hacen `coalesce(override.fecha_entrega, <la fecha de siempre>)`. Nada más: la
-- tanda, los m³ y el resto salen de donde salían. El `fuera` (oculto / desprogramada / cancelada) no se toca.
--
-- IMPACTO MEDIDO ANTES DE APLICAR (16/09): de las filas que GANAN el `distinct on (np)`, 1.164 son `fact` y
-- 1.687 `hist`, y **ninguna** tenía fila en `GV_PPP_Prog_Override` con `fecha_entrega`. O sea: el cambio no
-- mueve una sola fila de lo que hoy se ve; sólo habilita los movimientos nuevos. Verificado después con
-- `except all` en los dos sentidos contra la definición vieja sobre 2026-09-01..2026-12-31: 0 y 0.
--
-- Rollback: `sql/backups/gv_ppp_tanda_mover_gv_ppp_prog_arbol_20260916_pre_v1911.sql`.

CREATE OR REPLACE FUNCTION public.gv_ppp_prog_arbol(p_desde date, p_hasta date)
 RETURNS TABLE(fecha date, tanda text, np text, np_num numeric, cod text, razon_social text, localidad text, zona text, zona_corta text, empresa text, origen text, m3 numeric, estado text, estado_orden integer, clave text, pide_horario boolean, horario_fecha date, horario_franja text, horario_origen text, barrio text, fecha_pedido date)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
         nullif(btrim(coalesce(p.barrio, '')), '')                         as barrio,
         case when left(btrim(coalesce(p.fecha_recep, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(p.fecha_recep), 10)::date end                as fecha_pedido,
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
  -- v19.11: `ovf` — una NP que ya sólo figura facturada se puede reprogramar por el override.
  select 3,
         regexp_replace(upper(btrim(f.np)), '\.0+$', ''),
         upper(btrim(coalesce(f.tanda, ''))),
         coalesce(f.m3, 0)::numeric,
         coalesce(ovf.fecha_entrega, f.fecha_salida),
         coalesce(btrim(f.cod_cliente), ''),
         coalesce(btrim(f.razon_social), ''),
         '', '', regexp_replace(upper(btrim(f.np)), '\.0+$', ''), null::text, null::date, 'fact'
    from public."Facturacion_NP" f
    left join public."GV_PPP_Prog_Override" ovf
      on ovf.np = regexp_replace(upper(btrim(f.np)), '\.0+$', '')
   where f.fecha_salida is not null
  union all
  select 4,
         regexp_replace(btrim(h.np), '\.0+$', ''),
         upper(btrim(coalesce(h.tanda, ''))),
         coalesce(h.m3, 0)::numeric,
         coalesce(ovh.fecha_entrega,
                  case when left(btrim(coalesce(h.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
                       then left(btrim(h.fecha_entrega), 10)::date end),
         coalesce(btrim(h.cod), ''),
         coalesce(btrim(h.rs), ''),
         '', '', regexp_replace(btrim(h.np), '\.0+$', ''), null::text, null::date, 'hist'
    from public."GV_PPP_Entregados_Historico" h
    left join public."GV_PPP_Prog_Override" ovh
      on ovh.np = regexp_replace(btrim(h.np), '\.0+$', '')
),
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
salio as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1')
     and btrim(coalesce(r.texto, '')) <> ''
),
fact as (select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f),
est as (
  select d.fe, d.np, d.tanda, d.m3, d.cod, d.razon_social, d.localidad, d.zona, d.origen, d.clave, d.barrio, d.fecha_pedido,
         (fc.np is not null)                          as b_fact,
         (s.np is not null or a.opcion = 'TAP')       as b_arm,
         (a.opcion = 'AP' or p.opcion in ('TP','EP')) as b_curso
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
       e.cod, e.razon_social, e.localidad, e.zona,
       case when e.zona ~* 'retira'                                    then 'Retira'
            when public.gv_es_super_np(e.np, e.cod)
              or e.zona ~* 'super|coto|carrefour|chango|krikos'        then 'Súper'
            else coalesce(substring(e.zona, '^(Zona\s*[0-9]+)'), nullif(btrim(e.zona), ''), 'Sin zona') end,
       case when upper(e.np) like 'LK%' then 'LK'
            when upper(e.np) like 'CH%' then 'CH'
            when coalesce(nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric, 0) > 90000 then 'LK'
            else 'CH' end,
       e.origen, e.m3,
       case when e.b_fact then 'facturado' when e.b_arm then 'armado'
            when e.b_curso then 'proceso' else 'pendiente' end,
       case when e.b_fact then 4 when e.b_arm then 3 when e.b_curso then 2 else 1 end,
       e.clave,
       public.gv_pide_horario_np(e.np, e.cod, e.zona),
       h.fecha, h.franja, h.origen,
       e.barrio, e.fecha_pedido
  from est e
  left join public."GV_Pedido_Horario" h
    on h.empresa = public.gv_emp_de_np(e.np)
   and h.clave in (e.clave, regexp_replace(upper(btrim(e.np)), '\.0+$', ''))
 order by e.fe, coalesce(nullif(e.tanda, ''), '—'),
          nullif(regexp_replace(e.np, '\D', '', 'g'), '')::numeric nulls last, e.np;
$function$;
