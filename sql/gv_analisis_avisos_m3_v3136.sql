-- v31.36 (Thomas) — dos correcciones del Análisis Productivo, aplicadas sobre la definición VIVA
-- con replace() (como gv_analisis_cola_abierta.sql), porque varias sesiones parchean estas funciones.
--
--  #2  m³ del Análisis = m³ PICKEADO (vista_tanda_m3 = COALESCE(ISIS, web, histórico) × fracción),
--      no la suma cruda de PPP_Web_Programacion + GV_PPP_Programacion_Diaria (sin fracción ni
--      fallback), que inflaba o daba 0 en tandas con picking parcial. En gv_analisis_lista (CTE m3)
--      y en gv_analisis_tanda (cabecera.m3 y v_m3, que alimenta m³/h).
--
--  #3  El contador de avisos de la TARJETA (alerta) contaba EVENTOS; el detalle muestra 1 aviso por
--      TIPO (relámpago / imposible / faltó, cada uno agrupando sus códigos). Medido: 8 de 22 tandas
--      con aviso diferían (36%). Ahora paso.n = tipos de paso presentes (bool_or relámpago + bool_or
--      imposible) y alerta = least(n_falto,1) + n_paso. Medido tras el fix: 22/22 coinciden.
--      El badge NO se toca: cuenta TANDAS con aviso (presencia), no avisos por tanda.

-- #2a — m3 de la lista
do $$
declare d text;
begin
  d := pg_get_functiondef('public.gv_analisis_lista(integer,text,text)'::regprocedure);
  d := regexp_replace(d,
    'select u\.tanda, \(select coalesce\(sum\(w\.m3\), 0\) from public\."PPP_Web_Programacion" w\s+where upper\(btrim\(w\.tanda\)\) = u\.tanda\)\s+\+ \(select coalesce\(sum\(d\.m3\), 0\) from public\."GV_PPP_Programacion_Diaria" d\s+where upper\(btrim\(d\.tanda\)\) = u\.tanda\) m3',
    'select u.tanda, (select v.m3 from public.vista_tanda_m3 v where upper(btrim(v.tanda)) = u.tanda limit 1) m3');
  -- #3 — avisos de la tarjeta: tipos presentes, no eventos
  d := replace(d,
    'select s.tanda, count(*) n from public.gv_picking_paso s',
    'select s.tanda, (bool_or(coalesce(s.real_final, 0) >= 3 and (select extract(epoch from s.primera_conf - coalesce((select max(m.ts_cliente) from public."GV_Picking_Paso_Evento" m where m.evento = ''mostrado'' and upper(btrim(m.tanda)) = s.tanda and m.paso = s.paso and m.legajo = s.legajo and m.ts_cliente <= s.primera_conf), s.primera_vez))) < 2)::int + bool_or(coalesce(s.real_final, 0) >= 5 and (select extract(epoch from s.primera_conf - coalesce((select max(m.ts_cliente) from public."GV_Picking_Paso_Evento" m where m.evento = ''mostrado'' and upper(btrim(m.tanda)) = s.tanda and m.paso = s.paso and m.legajo = s.legajo and m.ts_cliente <= s.primera_conf), s.primera_vez))) / nullif(s.real_final, 0) < 1)::int) n from public.gv_picking_paso s');
  d := replace(d, '''alerta'', f.n_falto + f.n_paso', '''alerta'', least(f.n_falto, 1) + f.n_paso');
  execute d;
end $$;

-- #2b — m3 del detalle (cabecera y v_m3)
do $$
declare d text;
begin
  d := pg_get_functiondef('public.gv_analisis_tanda(text,text)'::regprocedure);
  d := replace(d, '''m3'', round(coalesce(sum(w.m3), 0), 3)',
                  '''m3'', round((select v.m3 from public.vista_tanda_m3 v where upper(btrim(v.tanda)) = v_t limit 1), 3)');
  d := replace(d, 'count(*)::int, coalesce(sum(w.m3), 0)',
                  'count(*)::int, (select v.m3 from public.vista_tanda_m3 v where upper(btrim(v.tanda)) = v_t limit 1)');
  execute d;
end $$;

-- verificación: select * from public.gv_reglas_perdidas;  (debe dar 0 filas)
