-- v22.47 (Luis, 2026-09-25) — el pedido partido es UNO también al revés: "si corresponde que estén en
-- cuarentena, deberían estar los dos. En cuarentena deberían aparecer agrupados en un solo item".
--   1. La excepción de REPOSICIÓN CHICA no se aplica a un pedido partido (la parte diferida suele
--      tener 1 código y zafaba sola con el original retenido). Las demás exenciones ya eran del
--      pedido entero (mismo pedido v20.52 usa pedido_origen; liberación = gv_cuarentena_liberados_familia).
--   2. gv_pedidos_partidos(): las partes diferidas, para que la pantalla agrupe (una fila).
-- Aplicado sobre la definición VIVA. marcar_calc: 414 ms (antes 366-373 ms).
do $$
declare v text; v2 text;
begin
  v := pg_get_functiondef('public.gv_cuarentena_marcar_calc(jsonb)'::regprocedure);
  if v !~ 'v22\.47-partido' then
    v2 := replace(v,
      'select r.empresa, r.order_id from public.gv_cuarentena_repo_seguro(p_pedidos) r',
      'select r.empresa, r.order_id from public.gv_cuarentena_repo_seguro(p_pedidos) r' || chr(10) ||
      '     -- v22.47-partido (Luis, 25/09): un pedido PARTIDO por importados no es una reposicion chica:' || chr(10) ||
      '     --   la parte diferida suele tener 1 codigo y zafaba sola mientras el original quedaba retenido.' || chr(10) ||
      '     --   Las dos partes son UN pedido: o quedan las dos en cuarentena o ninguna.' || chr(10) ||
      '     where not exists (select 1 from public.lk_pedidos_match pm' || chr(10) ||
      '                        where pm.empresa = r.empresa' || chr(10) ||
      '                          and ((pm.order_id::text = r.order_id and pm.pedido_origen is not null)' || chr(10) ||
      '                               or pm.pedido_origen::text = r.order_id))');
    if v2 = v then raise exception 'marcar_calc: repo no matchea'; end if;
    execute v2;
  end if;
end $$;

create or replace function public.gv_pedidos_partidos()
returns table(empresa text, order_id text, pedido_origen text)
language sql stable security definer
set search_path to 'public'
as $$
  -- v22.47 (Luis, 25/09): las partes diferidas de un pedido partido por importados, para que la
  -- pantalla de Cuarentena las agrupe con su original en UNA fila. LK y Chef.
  select m.empresa, m.order_id::text, m.pedido_origen::text
    from public.lk_pedidos_match m
   where m.pedido_origen is not null
     and (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio());
$$;
revoke all on function public.gv_pedidos_partidos() from public, anon;
grant execute on function public.gv_pedidos_partidos() to authenticated, service_role;
