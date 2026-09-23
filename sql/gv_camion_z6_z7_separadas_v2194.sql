-- v21.94 (Luis, 23/09): "si, separalas tambien" -> Z6 y Z7 son camiones distintos.
-- Z6 = GBA Norte, Z7 = GBA Norte Lejos. La zona manda sobre el sector (N y P estan los dos en GBA Norte
-- en GV_Sectores). Idempotente, sobre la definicion VIVA.
do $t$ declare d text; begin
  d := pg_get_functiondef('public.gv_ppp_web_camion(text,text)'::regprocedure);
  if position($x$when '7' then 'GBA Norte Lejos'$x$ in d) > 0 then return; end if;
  d := replace(d, $x$when '3' then 'Capital Oeste' end$x$,
                  $x$when '3' then 'Capital Oeste' when '6' then 'GBA Norte' when '7' then 'GBA Norte Lejos' end$x$);
  if position($x$when '7' then 'GBA Norte Lejos'$x$ in d) = 0 then raise exception 'no matchea'; end if;
  execute d;
end $t$;
-- Medido en transaccion abortada: gv_ppp_tanda_camion_mezclado 1 -> 1 (ninguna tanda nueva mezclada).
-- Centinela PENDIENTE del si de Luis:
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
-- values ('gv_ppp_web_camion','funcion','GBA Norte Lejos','Z6 y Z7 son camiones distintos','Luis','v21.94');
