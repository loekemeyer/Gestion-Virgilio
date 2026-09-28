-- v23.24 (Luis, 2026-09-28) — pedido web con código de cliente que NO EXISTE en el padrón → no se
-- programa solo (ni a mano: gv_ppp_web_tanda_programar/_reusar usan la misma función). Problema 588.
-- Casos: Capo (LK 1548/1549, cargados con 4318; el alta es 4286) y Chaverim (LK 1452, cargado con
-- 4317; el alta es 4285). El pedido nace con un código provisorio y el alta queda con otro: sin código
-- conocido no hay cliente_nuevo ni deuda, y el armador lo programaba como cliente sano.
-- Padrón = GV_Clientes_Direcciones ∪ GV_Clientes_Nuevos (un alta del día puede estar sólo en el 2.º).
-- Súper y clientes de prueba no entran. Una fila en gv_cuarentena_liberados_familia lo levanta.
-- El motivo nuevo es 'cliente_sin_padron'. Se aplica sobre pg_get_functiondef, idempotente.
do $$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_cuarentena_retiene_lote(text,jsonb)'::regprocedure);
  if d ~ 'cliente_sin_padron' then raise notice 'ya aplicado'; return; end if;
  n := replace(d,
$a$  return query
    select m.order_id::bigint, coalesce(m.motivos, array[]::text[])
      from public.gv_cuarentena_marcar_calc(v_ped) m
     where m.order_id ~ '^[0-9]+$';$a$,
$b$  -- v23.24 (Luis, 28/09): el código del pedido tiene que existir en el padrón (problema 588).
  return query
    with _sp_calc as (
      select m.order_id::bigint as oid, coalesce(m.motivos, array[]::text[]) as mot
        from public.gv_cuarentena_marcar_calc(v_ped) m
       where m.order_id ~ '^[0-9]+$'
    ), _sp_desc as (
      select distinct (e->>'order_id')::bigint as oid, array['cliente_sin_padron']::text[] as mot
        from jsonb_array_elements(v_ped) e
       where not exists (select 1 from public."GV_Clientes_Direcciones" dd
                          where dd.empresa = e->>'empresa' and btrim(dd.cod) = e->>'cod')
         and not exists (select 1 from public."GV_Clientes_Nuevos" nn
                          where nn.empresa = e->>'empresa' and btrim(nn.cod) = e->>'cod')
         and not public.gv_es_super(e->>'empresa', e->>'cod')
         and not public.gv_es_cliente_prueba(e->>'empresa', e->>'cod')
         and not exists (select 1 from public.gv_cuarentena_liberados_familia lb
                          where lb.empresa = e->>'empresa'
                            and public.gv_cuarentena_clave(lb.order_id) = public.gv_cuarentena_clave(e->>'order_id'))
    )
    select coalesce(c.oid, s.oid), coalesce(c.mot, array[]::text[]) || coalesce(s.mot, array[]::text[])
      from _sp_calc c full join _sp_desc s on s.oid = c.oid;$b$);
  if n = d then raise exception 'v23.24: no matcheó el return query de gv_cuarentena_retiene_lote'; end if;
  execute n;
end $$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_cuarentena_retiene_lote', 'funcion', 'cliente_sin_padron',
        'un pedido web con código de cliente que no existe en el padrón no se programa solo', 'Luis', 'v23.24')
on conflict do nothing;
-- Rollback: recrear la función con el return query original (select … from gv_cuarentena_marcar_calc(v_ped)).
