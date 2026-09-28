-- v23.16 (Luis, 2026-09-28) — «Ya programados y el cliente está en cuarentena» aplica las
-- MISMAS excepciones que la Cuarentena y el armador (gv_cuarentena_marcar_calc):
--   · reposición chica (v19.44)  -> gv_cuarentena_repo_seguro, salvo pedido partido (v22.47)
--   · mismo pedido (v20.52)      -> gv_cuarentena_mismo_pedido_seguro
-- Caso: LK 0258 (web LK 1562, Garbarino, LK 4210): 1 código (506 x 1), 3 días después de su
-- factura del 25/09 -> exento por reposición chica; el armador lo programó bien (F10A) y el
-- recuadro lo marcaba igual con la deuda de $1.014.542.
-- Se aplica sobre pg_get_functiondef (varias sesiones tocan estas funciones), idempotente,
-- y falla con raise si el texto no matchea.
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_cuarentena_ya_programado()'::regprocedure);
  if d ~ 'v23\.16-exc' then raise notice 'ya aplicado'; return; end if;

  n := replace(d,
$a$  marca as (
    select p.*,$a$,
$b$  -- v23.16-exc: mismas excepciones que gv_cuarentena_marcar_calc (sólo pedidos web).
  lote as (
    select coalesce(jsonb_agg(distinct jsonb_build_object(
             'order_id', p.order_id::text, 'empresa', p.empresa, 'cod', p.cod)), '[]'::jsonb) j
      from prog p where p.origen = 'web' and p.order_id is not null and p.cod is not null
  ),
  repo as (
    select r.empresa, r.order_id from lote, public.gv_cuarentena_repo_seguro(lote.j) r
     where not exists (select 1 from public.lk_pedidos_match pm
                        where pm.empresa = r.empresa
                          and ((pm.order_id::text = r.order_id and pm.pedido_origen is not null)
                               or pm.pedido_origen::text = r.order_id))
  ),
  mismo as (
    select m2.empresa, m2.order_id from lote, public.gv_cuarentena_mismo_pedido_seguro(lote.j) m2
  ),
  marca as (
    select p.*,$b$);
  if n = d then raise exception 'v23.16: no matcheó el CTE marca'; end if;
  d := n;

  n := replace(d,
$a$             where not public.gv_cuarentena_exento(m.emp_ev, m.cod_ev, x)) as motivos_ok
      from marca m$a$,
$b$             where not public.gv_cuarentena_exento(m.emp_ev, m.cod_ev, x)
               and not (m.order_id is not null and x = any (public.gv_cuarentena_repo_motivos())
                        and (exists (select 1 from repo rp where rp.empresa = m.empresa and rp.order_id = m.order_id::text)
                          or exists (select 1 from mismo mp where mp.empresa = m.empresa and mp.order_id = m.order_id::text)))
           ) as motivos_ok
      from marca m$b$);
  if n = d then raise exception 'v23.16: no matcheó el filtro de exc'; end if;

  execute n;
end $$;

-- Centinela
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_cuarentena_ya_programado', 'funcion', 'gv_cuarentena_repo_seguro',
        'el recuadro «Ya programados en cuarentena» aplica reposición chica y mismo pedido, como marcar_calc',
        'Luis', 'v23.16')
on conflict do nothing;

-- Rollback: volver a crear la función desde sql/gv_cuarentena_ya_programado_v1657.sql + parches
-- posteriores, o sacar las dos inserciones de arriba sobre pg_get_functiondef.
