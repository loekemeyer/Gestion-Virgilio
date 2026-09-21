-- v20.90 — «A Programar» NO ofrece un pedido que ya salió, ya se facturó o ya se canceló.
--
-- Luis, 2026-09-21: «no me tires el historico, fijate en lo que hay programado ahora che.
-- de ahora en adelante» · «sacamos eso de "desprogramada", no? osea, no hay pedidos que
-- puedan volver A programar, no?».
--
-- QUÉ ESTABA MAL
-- --------------
-- `gv_ppp_isis_sin_tanda` es la lista de «A Programar» del lado ISIS: NP sin tanda. Tenía
-- cuatro guards (facturada, entregada, cancelada) pero TODOS colgaban de un `or
-- o.desprogramada`: si alguien había marcado la NP como desprogramada en
-- `GV_PPP_Prog_Override`, los guards se apagaban y el pedido volvía a ofrecerse para
-- programar aunque ya estuviera facturado y entregado.
--
-- Desde la v20.80 (Thomas: «una vez programados o se eliminan o se reprograman para otra
-- fecha») NO hay puerta que mande un pedido de vuelta a A Programar, así que `desprogramada`
-- ya no recibe filas nuevas — pero las viejas seguían apagando los guards.
--
-- Y faltaba un guard: **CCN / CRN**. Un pedido puede haber salido en el camión (CCN) o
-- tener el remito controlado (CRN) sin que su NP esté todavía en `Facturacion_NP` ni en
-- `GV_PPP_Entregados_Historico`. Ese es el caso que hay que frenar «de ahora en adelante»:
-- no el histórico, sino lo que está saliendo hoy.
--
-- LA REGLA
-- --------
--   una NP que ya se facturó, ya salió (CCN/CRN), ya está en el histórico de entregados o
--   está cancelada NO aparece en A Programar, diga lo que diga `desprogramada`.
--
-- `desprogramada` y `tanda_previa` siguen leyéndose para lo que sí sirven (el retorno del
-- retenido a su tanda, `gv_ppp_web_retenido`); lo que se saca es que apaguen los guards.
--
-- IMPACTO MEDIDO (21/09, antes de aplicar): 0 NP salen de la lista hoy — la única NP que
-- «A Programar» estaba mostrando no toca ninguno de los cuatro guards. O sea que el cambio
-- no le saca nada al supervisor: cierra la puerta para adelante.
--
-- ⚠ `create or replace view` BORRA las reloptions: el `alter view ... set
--   (security_invoker = true)` del final NO es opcional. Sin él la vista corre como
--   `postgres` y saltea la RLS.

create or replace view public.gv_ppp_isis_sin_tanda as
with d as (
  select regexp_replace(btrim(p.np), '\.0+$', '')                        as np,
         btrim(coalesce(p.cod, ''))                                      as cod,
         p.razon_social, p.tipo, p.fecha_recep, p.direccion, p.barrio,
         coalesce(p.zona, '')                                            as zona,
         coalesce(p.m3, 0::numeric)                                      as m3,
         case when btrim(coalesce(p.fecha_entrega, '')) ~ '^\d{4}-\d{2}-\d{2}'
                then left(btrim(p.fecha_entrega), 10)::date end          as fecha_entrega,
         coalesce(o.desprogramada, false)                                as desprogramada,
         nullif(btrim(coalesce(o.tanda_previa, '')), '')                 as tanda_previa
    from public.gv_ppp_programacion_diaria p
    left join public."GV_PPP_Prog_Override" o
           on o.np = regexp_replace(btrim(p.np), '\.0+$', '')
   where coalesce(nullif(btrim(p.tanda), ''), '') = ''
     and regexp_replace(btrim(coalesce(p.np, '')), '\.0+$', '') ~ '^\d{1,18}$'
)
select d.np, d.cod, d.razon_social, d.tipo, d.fecha_recep, d.fecha_entrega,
       d.zona, d.barrio, d.direccion, d.m3,
       coalesce(b.lineas, 0)          as lineas,
       coalesce(b.cajas, 0::numeric)  as cajas,
       public.gv_es_super_np(d.np, d.cod)
         or d.zona ~* 'super|coto|carrefour|chango|krikos'   as es_super,
       case when left(d.np, 1) = '4' then 'chef' else 'lk' end as empresa,
       d.tanda_previa,
       exists (select 1 from public."Registros_Produccion_Virgilio" r
                where r.opcion = 'TAL' and not public.es_legajo_test(r.legajo)
                  and regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') = d.np)
                                                             as ya_armada,
       coalesce(public.gv_ppp_tanda_tocada(d.tanda_previa), false) as ya_pickeada
  from d
  left join lateral (
       select count(*)::int as lineas,
              coalesce(sum(coalesce(bp.cajas, 0::numeric)), 0::numeric) as cajas
         from public."GV_PPP_Base_Pedidos" bp
        where regexp_replace(btrim(bp.pedido), '\.0+$', '') = d.np) b on true
 -- v20.90: los cuatro guards YA NO cuelgan de `desprogramada`.
 where not exists (select 1 from public."Facturacion_NP" f
                    where regexp_replace(btrim(coalesce(f.np, '')), '\.0+$', '') = d.np)
   and not exists (select 1 from public."GV_PPP_Entregados_Historico" e
                    where regexp_replace(btrim(coalesce(e.np, '')), '\.0+$', '') = d.np)
   -- v20.90: guard nuevo. Ya salió en el camión (CCN) o el remito está controlado (CRN).
   and not exists (select 1 from public."Registros_Produccion_Virgilio" r2
                    where r2.opcion = any (array['CCN','CRN'])
                      and not public.es_legajo_test(r2.legajo)
                      and regexp_replace(upper(btrim(split_part(r2.texto, '|', 1))), '\.0+$', '') = d.np)
   and not exists (select 1 from public."NP_Canceladas" c
                    where regexp_replace(btrim(coalesce(c.np, '')), '\.0+$', '') = d.np);

alter view public.gv_ppp_isis_sin_tanda set (security_invoker = true);

-- CENTINELA: que ningún guard vuelva a colgarse de `desprogramada`.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('public.gv_ppp_isis_sin_tanda', 'vista',
        'CCN',
        'A Programar no ofrece una NP que ya salio (CCN/CRN); el guard no cuelga de desprogramada',
        'Luis', 'v20.90')
on conflict do nothing;

-- CHEQUEOS
--   select * from public.gv_reglas_perdidas;    -- vacia = el guard sigue puesto
--   select * from public.gv_endpoints_rotos;    -- vacia = la vista se lee
--   select count(*) from public.gv_ppp_isis_sin_tanda;
