-- v21.60 (Luis, 2026-09-23) — el FRENO GENERAL de mover NP sueltas (`np_mover_frenado` = 1)
-- ⚠ El marcador adentro de la función dice `v21.59` (así se aplicó): NO cambiarlo, es la llave que evita reaplicar.
-- frena SOLO la NP cuya tanda tiene trabajo hecho (picking o armado). Una NP PENDIENTE se mueve
-- sola a otra tanda: no hay cajas ni registro de armado que dejar atrás.
-- Luis: "sacá la traba de mover NPs individuales sólo para las que están pendientes sin nada armado".
--
-- Primer caso: LK 0156 (Matiz SA, 3,09 m³) E74A 06/10 -> E78A jue 24/09, vía
-- gv_ppp_pedido_mover('LK 0156','2026-09-24',null,'Luis (Claude)'); E74A queda con LK 0098.
--
-- Aplicado sobre pg_get_functiondef (idempotente, con raise si el texto no matchea):
do $$
declare d text; d2 text;
 v_old text := $o$if v_ex is null and coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'np_mover_frenado'), 0) >= 1 then$o$;
 v_new text := $n$-- v21.59 (Luis, 2026-09-23) - el freno general frena SOLO la NP cuya tanda tiene trabajo hecho
  -- (picking o armado). Una NP PENDIENTE (tanda sin nada) se mueve sola: no hay cajas ni registro
  -- que dejar atras. Primer caso: LK 0156 (Matiz) E74A -> E78A.
  if v_ex is null and coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'np_mover_frenado'), 0) >= 1
     and exists (select 1 from unnest(coalesce(p_nps, array[]::text[])) n
                   cross join lateral public.gv_np_trabajo_hecho(n) x
                  where x.tanda is not null and (x.tiene_picking or x.tiene_armado)) then$n$;
begin
  d := pg_get_functiondef('public.gv_np_mover_guard(text[],text,text)'::regprocedure);
  if position('v21.59' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  if position(v_old in d) = 0 then raise exception 'no matchea el texto del freno'; end if;
  d2 := replace(d, v_old, v_new);
  d2 := replace(d2, 'v20.96 - Un pedido no se saca de su tanda.',
    'v21.59 - Un pedido ya pickeado o armado no se saca de su tanda (los pendientes si se mueven).');
  execute d2;
end $$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_np_mover_guard','funcion','x\.tiene_picking or x\.tiene_armado\)\) then',
        'El freno general (np_mover_frenado) frena SOLO la NP cuya tanda tiene picking o armado; la pendiente se mueve sola',
        'Luis','v21.59');

-- Prueba (23/09, freno = 1): guard(['LK 0098'] pendiente) -> PASA · guard(['LK 0101'] armada) -> FRENA,
-- también con gv.pedido_lleva_registro = '1'. gv_reglas_perdidas = 0.
-- Rollback: volver a la condición sin el `and exists (...)` (frena toda NP suelta).
