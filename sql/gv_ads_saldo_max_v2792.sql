-- v27.92 (Luis, D3, 07/10/2026): ADS saldo N = disponible - greatest(comprometido N, Est. Madre * N/30).
-- Antes restaba los dos (contaba dos veces la demanda ya pedida). Medido: quiebres 39/61/88 -> 32/46/67.
-- Aplicado sobre pg_get_functiondef (idempotente, marcador v27.92-max) + fila en GV_Reglas_Centinela.
-- Rollback: reemplazar en gv_ads_stock2 "- greatest(coalesce(c.cNN,0), s.proy * NN / 30.0)" por
--           "- coalesce(c.cNN,0) - s.proy * NN / 30.0" (NN = 10/20/30) y borrar la fila del centinela.
do $x$ declare d text; n int; begin
 d := pg_get_functiondef('public.gv_ads_stock2()'::regprocedure);
 if d ~ 'v27.92-max' then return; end if;
 d := replace(d, 'round(s.term + s.rk + s.ag + s.ex - coalesce(c.c10,0) - s.proy * 10 / 30.0, 0)', 'round(s.term + s.rk + s.ag + s.ex - greatest(coalesce(c.c10,0), s.proy * 10 / 30.0), 0) /*v27.92-max*/');
 d := replace(d, 'round(s.term + s.rk + s.ag + s.ex - coalesce(c.c20,0) - s.proy * 20 / 30.0, 0)', 'round(s.term + s.rk + s.ag + s.ex - greatest(coalesce(c.c20,0), s.proy * 20 / 30.0), 0)');
 d := replace(d, 'round(s.term + s.rk + s.ag + s.ex - coalesce(c.c30,0) - s.proy * 30 / 30.0, 0)', 'round(s.term + s.rk + s.ag + s.ex - greatest(coalesce(c.c30,0), s.proy * 30 / 30.0), 0)');
 n := (length(d) - length(replace(d,'greatest(coalesce(c.c','')))/length('greatest(coalesce(c.c');
 if n <> 3 then raise exception 'no matcheo: %', n; end if;
 execute d;
 insert into public."GV_Reglas_Centinela"(objeto,clase,patron,regla,quien_pidio,version)
 values ('gv_ads_stock2','funcion','greatest\(coalesce\(c\.c10','ADS saldo = disponible - el mayor entre comprometido y Est. Madre del horizonte (no la suma)','Luis','v27.92');
end $x$;
