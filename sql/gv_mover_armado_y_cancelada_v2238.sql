-- v22.38 (Luis, 24/09) — dos cambios, aplicados sobre la definición viva (idempotentes).
-- (1) gv_np_mover_guard: el freno general (np_mover_frenado) ya NO frena una NP ARMADA cuando
--     su registro viaja con ella (gv_ppp_pedido_mover prende gv.pedido_lleva_registro y copia
--     TP/TAP + su porción de a_facturar a la tanda nueva, v21.05). Lo pickeado sin armar sigue
--     frenado. Probado en transacción abortada: LK 0100 (facturado, E29C) -> tanda nueva E18F
--     con TP/TAP, stock total sin cambio; CH 0027 -> E69A entera.
-- (2) gv_ppp_prog_arbol: una NP web cancelada (GV_PPP_Web_NP_Cancelada) no vuelve por
--     Facturacion_NP con su fecha de salida vieja. Caso LK 0035: cancelada 24/09 16:41 y aparecía
--     en Pedidos atrasados el 17/09. Impacto: árbol 843 -> 842, atrasados 1 -> 0.
do $p$ declare d text; n text; begin
  d := pg_get_functiondef('public.gv_np_mover_guard(text[],text,text)'::regprocedure);
  if d !~ 'v22\.38-armado' then
    n := replace(d, $a$where x.tanda is not null and (x.tiene_picking or x.tiene_armado)) then$a$,
      $b$where x.tanda is not null
                    -- v22.38-armado (Luis, 24/09): el ARMADO se mueve si el registro viaja con el pedido
                    -- (gv_ppp_pedido_mover prende gv.pedido_lleva_registro). Lo PICKEADO sin armar sigue frenado.
                    and ((x.tiene_picking and not x.tiene_armado)
                         or (x.tiene_armado and coalesce(current_setting('gv.pedido_lleva_registro', true), '') <> '1'))) then$b$);
    if n = d then raise exception 'guard: no matcheó'; end if;
    execute n;
  end if;
  d := pg_get_functiondef('public.gv_ppp_prog_arbol'::regproc);
  if d !~ 'v22\.38-cancel' then
    n := replace(d, $a$    from public."NP_Canceladas" c
),$a$, $b$    from public."NP_Canceladas" c
  union
  -- v22.38-cancel (Luis, 24/09): una NP web CANCELADA no vuelve por Facturacion_NP con su
  -- fecha de salida vieja (LK 0035: cancelada, aparecia en Pedidos atrasados el 17/09).
  select upper(btrim(wc.np_label)) from public."GV_PPP_Web_NP_Cancelada" wc
   where nullif(btrim(coalesce(wc.np_label, '')), '') is not null
),$b$);
    if n = d then raise exception 'arbol: no matcheó'; end if;
    execute n;
  end if;
end $p$;
-- Rollback: zz_backups."GV_Backup_Funciones_20260924" (objetos gv_np_mover_guard / gv_ppp_prog_arbol).
