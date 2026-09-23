-- v21.66 (Luis, 2026-09-23, problema 514) — el armador automático descarta AL ENTRAR las NP que
-- ⚠ El marcador adentro de la función dice `(a000) v21.61` (así se aplicó): NO cambiarlo, es la llave que evita reaplicar.
-- ya tienen tanda.
--
-- Síntoma: desde el 23/09 10:20 la corrida de LK de gv_ppp_web_armar_pendientes se cortaba por
-- statement_timeout (57014, 8 s) en 3 de 4 vueltas y no programaba nada. Caso testigo: LK 1529
-- (Tegerina, liberado de cuarentena 09:02) figuraba "se arma solo → lun 5/10" y recién lo tomó la
-- vuelta de las 10:40.
-- Causa: el feed manda TODAS las NP vivas (LK ~185, Chef ~25) y casi todas ya tienen tanda. Cada
-- pase las descartaba recién al final, después de calcularles zona, sector, día del cliente, ancla
-- y cuarentena (~30 ms por NP tirados).
--
-- Medido en transacción abortada, misma entrada, versión actual vs nueva:
--   LK   118 NP: 6.156 ms -> 2.520 ms · mismas tandas y md5 de la programación idéntico
--   Chef  31 NP: 1.691 ms -> 1.103 ms · idéntico
-- El tope (armado_tope_pedidos) pasa a contar sólo pendientes.
-- También la usan gv_ppp_web_dia_salida (chip "se arma solo"), gv_ppp_web_armar_pendientes_simular
-- y gv_ppp_np_desarmar: pasan NP pendientes, así que no cambian de resultado.
--
-- Aplicado sobre pg_get_functiondef, idempotente, con raise si el ancla no matchea:
do $$
declare d text;
 v_anchor text := '  v_entraron := jsonb_array_length(coalesce(p_filas, ''[]''::jsonb));';
 v_new text := '  -- (a000) v21.61 (Luis, 2026-09-23, problema 514) -- LO YA PROGRAMADO NO ENTRA.
  --   (ver sql/gv_armado_descarta_programadas_v2166.sql)
  p_filas := coalesce((select jsonb_agg(x) from jsonb_array_elements(coalesce(p_filas,''[]''::jsonb)) x
     where not exists (select 1 from public."PPP_Web_Programacion" g
                        where g.empresa = p_empresa and g.order_id = (x->>''order_id'')::bigint
                          and g.np_idx = (x->>''np_idx'')::int and coalesce(nullif(trim(g.tanda),''''),'''') <> '''')), ''[]''::jsonb);
';
begin
  d := pg_get_functiondef('public.gv_ppp_web_armar_pendientes(text,date,jsonb,jsonb)'::regprocedure);
  if position('(a000) v21.61' in d) > 0 then raise notice 'ya aplicado'; return; end if;
  if position(v_anchor in d) = 0 then raise exception 'no matchea el ancla'; end if;
  execute replace(d, v_anchor, v_new || v_anchor);
end $$;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_ppp_web_armar_pendientes','funcion','\(a000\) v21\.61',
 'El armador descarta al entrar las NP que ya tienen tanda (sin eso la corrida de LK pasa los 8 s y no programa nada)','Luis','v21.61');

-- Chequeo: select * from public.gv_ppp_web_armado_salud;  select * from public.gv_reglas_perdidas;
-- Rollback: sacar el bloque (a000) de la función (pg_get_functiondef -> replace -> execute).
