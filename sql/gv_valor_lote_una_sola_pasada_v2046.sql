-- v20.46 (2026-09-21) — el monto de Clientes Nuevos / Cuarentena volvia "—": la RPC tardaba 11,8 s
-- contra el statement_timeout de 8 s del rol authenticated, el front cortaba y el catch dejaba el guion.
--
-- Causa medida: gv_art_libre(art, empresa) se llamaba UNA VEZ POR (codigo, empresa) y cada llamada
-- evaluaba entera la vista gv_demanda_programada_pendiente. Con 8 pedidos eso eran 11.864 ms.
--
-- Fix: la demanda programada se calcula UNA SOLA VEZ (_vl_prog, materialized) y el libre sale de ahi.
-- La logica de reparto (greedy por fecha/hora/order_id) no cambia: medido 0 / 6 / 10 / 10 / 10
-- faltantes en los 5 pedidos de 10 cajas de 437E de Chef con 14 libres, igual que la v20.44.
--
--   antes:  Execution Time 11864.265 ms   (lote de 8 pedidos)
--   ahora:  Execution Time   503.436 ms   (mismo lote, con items reales)
--
-- Rollback: reaplicar sql/gv_importado_escaso_reparto_v2044.sql (la version con gv_art_libre).

CREATE OR REPLACE FUNCTION public.gv_clientes_nuevos_valor_lote(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, valor numeric, valor_con_iva numeric, valor_importados numeric, items_importados integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with _vl_src as (
    select nullif(trim(e->>'order_id'), '')     as order_id,
           lower(coalesce(e->>'empresa','lk'))  as empresa,
           nullif(trim(e->>'cod'), '')          as cod,
           e->'items'                           as items,
           nullif(e->>'cond','')                as cond
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
     where nullif(trim(e->>'order_id'), '') is not null
  ),
  _vl_ord as materialized (
    select s.order_id, s.empresa,
           coalesce(m.fecha_pedido, '9999-12-31'::date) as f_ped,
           coalesce(m.hora_pedido, '99:99')             as h_ped
      from _vl_src s
      left join public.lk_pedidos_match m
             on m.empresa = s.empresa and m.order_id::text = s.order_id
  ),
  _vl_it as (
    select s.order_id, s.empresa, s.cod as cod_cli, s.cond,
           nullif(trim(i.e->>'art'), '')                  as art,
           coalesce((i.e->>'cajas')::numeric, 0)          as cajas,
           public.gv_cod_stock(i.e->>'art')               as codn,
           case when upper(btrim(coalesce(i.e->>'art',''))) ~ '[0-9E]L$' then 'LK'
                when s.empresa = 'chef' then 'CH' else 'LK' end as emp,
           public.gv_art_es_importado(i.e->>'art')        as imp,
           o.f_ped, o.h_ped
      from _vl_src s
      join _vl_ord o on o.order_id = s.order_id and o.empresa = s.empresa
      left join lateral jsonb_array_elements(coalesce(s.items, '[]'::jsonb)) i(e) on true
  ),
  -- UNA sola pasada por la demanda programada (v20.46). Llamarla por codigo costaba 11,8 s
  -- contra el statement_timeout de 8 s del rol authenticated: el front cortaba y mostraba "-".
  _vl_prog as materialized (
    select d.codn, d.emp, sum(d.cajas) as cajas, min(d.np) as np_muestra
      from public.gv_demanda_programada_pendiente d
     group by d.codn, d.emp
  ),
  -- Las NP del lote que YA estan programadas: sus cajas ya se contaron arriba, no compiten.
  _vl_yaprog as materialized (
    select distinct s.order_id, s.empresa
      from _vl_src s
      join public."PPP_Web_Programacion" w
        on w.empresa = s.empresa and w.order_id::text = s.order_id
      join public.gv_demanda_programada_pendiente d
        on d.np = public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)
  ),
  _vl_libre as (
    select distinct it.codn, it.emp, it.art, it.empresa,
           greatest(0, public.gv_art_disponible(it.art, it.empresa)
                     - coalesce((select p.cajas from _vl_prog p
                                  where p.codn = it.codn and p.emp = it.emp), 0)) as libre
      from _vl_it it
     where it.imp and it.art is not null
  ),
  _vl_rep as (
    select it.*,
           coalesce((select max(l.libre) from _vl_libre l
                      where l.codn = it.codn and l.emp = it.emp), 0) as libre,
           exists (select 1 from _vl_yaprog y
                    where y.order_id = it.order_id and y.empresa = it.empresa) as ya_prog
      from _vl_it it
  ),
  _vl_greedy as (
    select r.*,
           sum(case when r.imp and not r.ya_prog then r.cajas else 0 end)
             over (partition by r.codn, r.emp
                   order by r.f_ped, r.h_ped, r.order_id
                   rows between unbounded preceding and 1 preceding) as tomado_antes
      from _vl_rep r
  ),
  _vl_falta as (
    select g.order_id, g.empresa, g.cod_cli, g.cond, g.art, g.cajas,
           case when not g.imp or g.ya_prog or g.art is null then 0
                else greatest(0, g.cajas - greatest(0, g.libre - coalesce(g.tomado_antes, 0)))
           end as falta
      from _vl_greedy g
  ),
  _vl_part as (
    select order_id, empresa, cod_cli, cond,
           coalesce(jsonb_agg(jsonb_build_object('art', art, 'cajas', cajas - falta))
                      filter (where art is not null and cajas - falta > 0), '[]'::jsonb) as items_ok,
           coalesce(jsonb_agg(jsonb_build_object('art', art, 'cajas', falta))
                      filter (where art is not null and falta > 0), '[]'::jsonb)         as items_falta,
           count(*) filter (where art is not null and falta > 0)::int                    as n_falta
      from _vl_falta
     group by order_id, empresa, cod_cli, cond
  ),
  -- MATERIALIZED a proposito (v19.95): sin eso el planner aplana el CTE, repite la llamada a
  -- gv_ppp_web_valor_items en cada columna de salida y se duplica el trabajo sin que nada avise.
  _vl_val as materialized (
    select s.order_id, s.empresa, s.n_falta,
           public.gv_ppp_web_valor_items(s.empresa, s.cod_cli, s.items_ok,    s.cond) as valor,
           public.gv_ppp_web_valor_items(s.empresa, s.cod_cli, s.items_falta, s.cond) as valor_falta
      from _vl_part s
     where es_supervisor_virgilio() or gv_es_supervisor_o_servicio()
  )
  select v.order_id, v.empresa, round(v.valor, 2), round(v.valor * 1.21, 2),
         round(v.valor_falta, 2), v.n_falta
    from _vl_val v;
$function$;

notify pgrst, 'reload schema';
