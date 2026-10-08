-- v28.56 (Luis, 08/10/2026, D6 "dale"): el optimizador de las 18:00 (gv_ppp_optimizar_camiones)
-- no junta un camión con otro del mismo grupo si el DÍA destino (entero: todo lo de gv_ppp_detalle_dia)
-- queda por encima del cupo (PPP_Web_Config.dia_cupo_m3; sin fila = 4,30 m³). Idempotente, sobre la def viva.
-- Centinela 372. Rollback: sacar la línea "and (select coalesce(sum(o2.m3), 0) ... <= v_cupo".
-- REGLA_CONFIRMADA_POR_USUARIO
do $w$ declare d text; n text; begin
 d := pg_get_functiondef('public.gv_ppp_optimizar_camiones(boolean,integer)'::regprocedure);
 if d ~ 'v28.56-cupo' then raise notice 'ya'; return; end if;
 n := replace(d, 'v_min date; k int := 0;', 'v_min date; k int := 0; v_cupo numeric := coalesce((select valor from public."PPP_Web_Config" where clave = ''dia_cupo_m3''), 4.30); /* v28.56-cupo */');
 n := replace(n, '               and public.gv_es_dia_con_reparto(o.fecha)
',
 '               and public.gv_es_dia_con_reparto(o.fecha)
               -- v28.56-cupo (Luis 08/10): no junta si el dia destino se pasa del cupo (dia entero)
               and (select coalesce(sum(o2.m3), 0) from _opt_t o2 where o2.fecha = o.fecha) + c.m3 <= v_cupo
');
 if n = d or (length(n) - length(d)) < 150 then raise exception 'no matcheo: %', length(n)-length(d); end if;
 execute n;
end $w$;
