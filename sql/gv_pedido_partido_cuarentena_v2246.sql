-- v22.46 (Luis, 2026-09-25) — PEDIDO PARTIDO POR IMPORTADOS: para el cliente es UNO. LK y Chef.
--
-- Caso: Solia (LK 151). Pedido 1545; la página lo partió y sacó 1546 (606E x3, espera reingreso,
-- lk_pedidos_match.pedido_origen = 1545). Los dos entraron a Cuarentena por DEUDA REAL
-- ($3.421.315,29: facturas del 17/08 y 10/09, NP 98427/98428/98613/98614 — no de este pedido).
-- 1545 quedó retenido (bien). 1546 lo programó SOLO el armador (F01A, 06/10) a las 16:55,
-- 7 minutos después de entrar a Cuarentena, sin aprobación humana:
--   el pase (a0) aparta los DIFERIDOS en v_dif ANTES del filtro de cuarentena (a0d), y el
--   pase (b2) los programaba sin pasar por ese filtro. De ahí la alerta "retenido y programado".
--
-- Aplicado sobre la definición VIVA (idempotente; raise si el texto no matchea):
--   1. gv_cuarentena_liberados_familia: la aprobación de una parte vale para todo el pedido
--      (origen + partes diferidas), en las dos direcciones. Misma forma que Liberados.
--   2. gv_cuarentena_marcar_calc la lee MATERIALIZADA una vez (leída por fila costaba 6x:
--      366 -> 2.177 ms); gv_cuarentena_ya_programado la lee en su left join (42 ms).
--   3. El armador pasa los DIFERIDOS por el mismo filtro de cuarentena (fail-closed igual).
-- ⚠ Primer intento (función gv_pedido_familia con `= any(...)` dentro del lateral): la
--   marcación pasó de 366 ms a 10 s — se revirtió a los ~2 minutos. No volver a esa forma.
-- La mitad "cliente nuevo = 3 pedidos" vive en LK: sql/gv_clientes_nuevos_calc_hijo_v2246_LK.sql
--
-- Probado corriendo el armador en transacción abortada (LK 1546, zona 5):
--   antes:   sin aprobar -> programado 1 · aprobar 1545 no liberaba 1546
--   después: sin aprobar -> programado 0 · aprobar 1545 -> 1546 libre y programado el 06/10
--            · la alerta "retenido y programado" de 1546 desaparece al aprobar 1545.

-- 1 ─────────────────────────────────────────────────────────────────────────────────────
create or replace view public.gv_cuarentena_liberados_familia with (security_invoker = true) as
select l.empresa, l.order_id, l.motivos, l.liberado_por, l.liberado_at, l.persona
  from public."GV_Cuarentena_Liberados" l
union all
select l.empresa, fam.order_id::text, l.motivos, l.liberado_por, l.liberado_at, l.persona
  from public."GV_Cuarentena_Liberados" l
  join public.lk_pedidos_match m
    on m.empresa = l.empresa
   and (m.order_id::text = public.gv_cuarentena_clave(l.order_id)
        or m.pedido_origen::text = public.gv_cuarentena_clave(l.order_id))
  join public.lk_pedidos_match fam
    on fam.empresa = m.empresa
   and (fam.order_id = coalesce(m.pedido_origen, m.order_id) or fam.pedido_origen = coalesce(m.pedido_origen, m.order_id))
 where (m.pedido_origen is not null or exists (select 1 from public.lk_pedidos_match h
                                               where h.empresa = m.empresa and h.pedido_origen = m.order_id))
   and fam.order_id::text <> public.gv_cuarentena_clave(l.order_id);
revoke all on public.gv_cuarentena_liberados_familia from anon, authenticated;
grant select on public.gv_cuarentena_liberados_familia to service_role;

-- 2 y 3 ──────────────────────────────────────────────────────────────────────────────────
do $$
declare v text; v2 text;
begin
  v := pg_get_functiondef('public.gv_cuarentena_marcar_calc(jsonb)'::regprocedure);
  if v !~ '_lbf as materialized' then
    v2 := replace(v, '  with ped as (', '  -- v22.46 (Luis, 25/09): la aprobacion es de la FAMILIA del pedido partido (pedido_origen), LK y Chef.' || chr(10) || '  --   Materializada una vez: leida por fila dentro del lateral costaba 6x (366 -> 2.177 ms).' || chr(10) || '  with _lbf as materialized (select * from public.gv_cuarentena_liberados_familia),' || chr(10) || '  ped as (');
    v2 := replace(v2, 'from public."GV_Cuarentena_Liberados" lb', 'from _lbf lb');
    if (length(v2)-length(replace(v2,'from _lbf lb','')))/12 <> 2 or v2 !~ '_lbf as materialized' then raise exception 'marcar no matchea'; end if;
    execute v2;
  end if;

  v := pg_get_functiondef('public.gv_cuarentena_ya_programado()'::regprocedure);
  if v !~ 'gv_cuarentena_liberados_familia' then
    v2 := replace(v, 'left join public."GV_Cuarentena_Liberados" lb', 'left join public.gv_cuarentena_liberados_familia lb');
    if v2 = v then raise exception 'ya_prog no matchea'; end if;
    execute v2;
  end if;

  v := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if v !~ 'v22\.46-dif' then
    v2 := replace(v, '  -- (a0e) v21.67 (Luis, 2026-09-23)',
      '  -- (a0d2) v22.46-dif (Luis, 25/09) -- LO DIFERIDO TAMBIEN PASA POR CUARENTENA. v_dif se aparta' || chr(10) ||
      '  --   en (a0), antes de (a0d), y el pase (b2) lo programaba sin mirarla: LK 1546 (Solia, deuda' || chr(10) ||
      '  --   3,4 M, retenido) salio solo a F01A. Mismo criterio y mismo fail-closed que (a0d).' || chr(10) ||
      '  if jsonb_array_length(coalesce(v_dif, ''[]''::jsonb)) > 0 then' || chr(10) ||
      '    v_ret := coalesce((select array_agg(distinct _cq_d.order_id::text)' || chr(10) ||
      '                         from public.gv_cuarentena_retiene_lote(p_empresa, v_dif) _cq_d), ''{}'');' || chr(10) ||
      '    if coalesce(array_length(v_ret, 1), 0) > 0 then' || chr(10) ||
      '      v_dif := coalesce((select jsonb_agg(x) from jsonb_array_elements(v_dif) x' || chr(10) ||
      '                          where not ((x->>''order_id'') = any (v_ret))), ''[]''::jsonb);' || chr(10) ||
      '    end if;' || chr(10) ||
      '  end if;' || chr(10) || chr(10) ||
      '  -- (a0e) v21.67 (Luis, 2026-09-23)');
    if v2 = v then raise exception 'armador: el ancla (a0e) no matchea, no se aplica'; end if;
    execute v2;
  end if;
end $$;

-- Centinelas (PENDIENTE del "sí" de Luis: es un INSERT)
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_ppp_web_armar_pendientes','funcion','gv_cuarentena_retiene_lote\(p_empresa, v_dif\)','lo diferido no se programa solo si el cliente esta en cuarentena sin aprobar','Luis','v22.46'),
--  ('gv_cuarentena_marcar_calc','funcion','_lbf as materialized \(select \* from public\.gv_cuarentena_liberados_familia','la aprobacion de cuarentena es de la familia del pedido partido (pedido_origen)','Luis','v22.46'),
--  ('gv_cuarentena_ya_programado','funcion','left join public\.gv_cuarentena_liberados_familia lb','aprobado el pedido original, la parte diferida sale de retenido y programado','Luis','v22.46');

-- Rollback:
--   marcar_calc: replace '_lbf lb' -> 'public."GV_Cuarentena_Liberados" lb' y sacar el CTE _lbf.
--   ya_programado: replace 'public.gv_cuarentena_liberados_familia lb' -> 'public."GV_Cuarentena_Liberados" lb'.
--   armador: sacar el bloque (a0d2).
