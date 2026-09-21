-- v20.42 (Luis, 2026-09-21), dos correcciones sobre la v20.41:
--   1. "Pone la regla de la E como te dije" -> importado es el codigo con E, y nada mas.
--      Se saca la union con la tabla `Importados` que habia puesto la v20.41.
--   2. "Solo monto sin importados que tengamos en falta del stock" -> no se descuenta todo lo
--      importado: se descuenta SOLO lo que hoy no se puede entregar, y caja por caja.
--      Si el pedido pide 10 cajas de un importado y hay 6 disponibles, se descuentan 4.
create or replace function public.gv_art_es_importado(p_cod text)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $function$
  select upper(btrim(coalesce(p_cod, ''))) ~ 'E';
$function$;

-- Cajas DISPONIBLES de un codigo, con el mismo criterio que el generador de OC (v19.85):
-- lo comprometido (separar_pedidos, a_facturar) NO cuenta, porque ya tiene dueno.
-- ⚠ Un dual vive en las dos gondolas y en `stocks_carga_rapida` son DOS filas ("437E LK" /
-- "437E CH"): la pila la elige la L del codigo (siempre LK, regla de Thomas) y, si no la tiene,
-- la empresa del pedido. Sumar las dos daria stock que a ese pedido no se le puede dar.
create or replace function public.gv_art_disponible(p_cod text, p_empresa text default 'lk')
returns numeric language sql stable set search_path to 'public', 'pg_temp' as $function$
  with base as (
    select regexp_replace(upper(btrim(coalesce(p_cod, ''))), '([0-9E])L$', '\1') as cod,
           case when upper(btrim(coalesce(p_cod, ''))) ~ '[0-9E]L$' then 'LK'
                when lower(coalesce(p_empresa, 'lk')) = 'chef' then 'CH' else 'LK' end as emp
  ),
  fila as (
    select s.* from public.stocks_carga_rapida s, base b
     where upper(btrim(s.cod)) = b.cod || ' ' || b.emp
    union all
    select s.* from public.stocks_carga_rapida s, base b
     where upper(btrim(s.cod)) = b.cod
       and not exists (select 1 from public.stocks_carga_rapida s2, base b2
                        where upper(btrim(s2.cod)) = b2.cod || ' ' || b2.emp)
  )
  select coalesce((select greatest(0,
             coalesce(f.terminado,0) + coalesce(f.a_guardar,0) + coalesce(f.racks,0)
           + coalesce(f.excedente,0) + coalesce(f.para_envasar,0) + coalesce(f.racks_ch,0))
           from fila f limit 1), 0);
$function$;

drop function if exists public.gv_clientes_nuevos_valor_lote(jsonb);

create function public.gv_clientes_nuevos_valor_lote(p_pedidos jsonb)
returns table(order_id text, empresa text, valor numeric, valor_con_iva numeric,
              valor_importados numeric, items_importados integer)
language sql security definer set search_path to 'public' as $function$
  with _vl_src as (
    select nullif(trim(e->>'order_id'), '')     as order_id,
           lower(coalesce(e->>'empresa','lk'))  as empresa,
           nullif(trim(e->>'cod'), '')          as cod,
           e->'items'                           as items,
           nullif(e->>'cond','')                as cond
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  _vl_it as (
    select s.order_id, s.empresa, s.cod as cod_cli, s.cond,
           nullif(trim(i.e->>'art'), '')                as art,
           coalesce((i.e->>'cajas')::numeric, 0)        as cajas,
           case when public.gv_art_es_importado(i.e->>'art')
                then greatest(0, coalesce((i.e->>'cajas')::numeric, 0)
                                 - public.gv_art_disponible(i.e->>'art', s.empresa))
                else 0 end                              as falta
      from _vl_src s
      left join lateral jsonb_array_elements(coalesce(s.items, '[]'::jsonb)) i(e) on true
  ),
  _vl_part as (
    select order_id, empresa, cod_cli, cond,
           coalesce(jsonb_agg(jsonb_build_object('art', art, 'cajas', cajas - falta))
                      filter (where art is not null and cajas - falta > 0), '[]'::jsonb) as items_ok,
           coalesce(jsonb_agg(jsonb_build_object('art', art, 'cajas', falta))
                      filter (where art is not null and falta > 0), '[]'::jsonb)         as items_falta,
           count(*) filter (where art is not null and falta > 0)::int                    as n_falta
      from _vl_it
     group by order_id, empresa, cod_cli, cond
  ),
  -- ⚠ MATERIALIZED a proposito (v19.95): sin eso el planner aplana el CTE, repite la llamada a
  -- gv_ppp_web_valor_items en cada columna de salida y se duplica el trabajo sin que nada avise.
  _vl_val as materialized (
    select s.order_id, s.empresa, s.n_falta,
           public.gv_ppp_web_valor_items(s.empresa, s.cod_cli, s.items_ok,    s.cond) as valor,
           public.gv_ppp_web_valor_items(s.empresa, s.cod_cli, s.items_falta, s.cond) as valor_falta
      from _vl_part s
     where s.order_id is not null
       and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
  )
  select v.order_id, v.empresa, round(v.valor, 2), round(v.valor * 1.21, 2),
         round(v.valor_falta, 2), v.n_falta
    from _vl_val v;
$function$;

revoke all on function public.gv_clientes_nuevos_valor_lote(jsonb) from public, anon;
grant execute on function public.gv_clientes_nuevos_valor_lote(jsonb) to authenticated;

-- ⚠ Una RPC NUEVA no la ve PostgREST hasta que recarga su cache de esquema: la primera llamada
-- vuelve 404 y, si el front se la come en un catch, la columna queda vacia para siempre.
notify pgrst, 'reload schema';

-- Probado con pedidos reales (no leido), antes y despues:
--   chef 229: 6 items, 2 con E, 1 EN FALTA -> monto $1.922.940, descontado $508.200
--             (la v20.41 descontaba los 2: $1.613.520, aunque uno tuviera stock)
--   chef 228 / 227 / 226 / 225: tienen E pero con stock -> no se descuenta nada
--   gv_art_disponible: 437E para chef = 14 y para lk = 286 (dos gondolas, dos pilas);
--                      438EL pedido de chef = 117 (la L manda a la pila de LK); 198E y 323E = 0.
