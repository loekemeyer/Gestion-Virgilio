-- v27.69 (Thomas, 07/10/2026): un ingreso a la app NO es llegada a VIRGILIO si después se fue a trabajar a CERVANTES.
-- Caso 277 (Jhonny) 07/10: ingresó 08:27 en la app (una sola app para las dos plantas), registró «Cajón 1» y
-- «Movimiento» en Cervantes a las 08:28, y el monitor de Virgilio lo marcó «sin arrancar» con alarma a las 08:33.
--  · gv_alerta_inactivo_servidor: si tiene un registro en Cervantes desde su última actividad en Virgilio →
--    accion 'en Cervantes' (no avisa y cierra la alerta viva).
--  · gv_monitor_ingresos: un ingreso seguido de un registro en Cervantes no sale como «entró · sin arrancar».
--  · gv_monitor_horas_operario_dia: el ingreso sólo adelanta la jornada de Virgilio si entre el ingreso y su
--    primer registro en Virgilio no registró nada en Cervantes.
-- Marcador v27.69-cerv. Idempotente. REGLA_CONFIRMADA_POR_USUARIO
do $q$ declare d text;
 v_al1 text := 'elsif r.abierta then accion := ''tarea abierta'';';
 n_al1 text := 'elsif exists (select 1 from public."Registros Produccion Cervantes" cv where cv.legajo::text = r.leg and cv.created_at >= v_desde and cv.created_at >= r.ult - interval ''1 minute'' and cv.created_at <= v_now) then accion := ''en Cervantes'';  -- v27.69-cerv
    elsif r.abierta then accion := ''tarea abierta'';';
 v_al2 text := 'accion in (''termino el dia'',''tarea abierta'',''trabajando'')';
 n_al2 text := 'accion in (''termino el dia'',''tarea abierta'',''trabajando'',''en Cervantes'')';
 v_in text := 'and l.created_at >= p_desde';
 n_in text := 'and l.created_at >= p_desde and not exists (select 1 from public."Registros Produccion Cervantes" cv where cv.legajo::text = btrim(l.legajo::text) and cv.created_at >= l.created_at and cv.created_at < p_hasta) /* v27.69-cerv */';
 v_mon text := '/* v27.68-clavetv */ and l.legajo = b.legajo';
 n_mon text := '/* v27.68-clavetv */ and l.legajo = b.legajo and not exists (select 1 from public."Registros Produccion Cervantes" cv where cv.legajo::text = b.legajo and cv.created_at >= l.created_at and cv.created_at < (select min(b2.ts_cliente) from base b2 where b2.legajo = b.legajo)) /* v27.69-cerv */';
 f text;
begin
 foreach f in array array['public.gv_alerta_inactivo_servidor(boolean,timestamptz)','public.gv_alerta_inactivo_servidor(boolean)'] loop
   d := pg_get_functiondef(f::regprocedure);
   if position('v27.69-cerv' in d) > 0 then continue; end if;
   if (length(d)-length(replace(d,v_al1,'')))/length(v_al1) <> 1 or (length(d)-length(replace(d,v_al2,'')))/length(v_al2) <> 1
     then raise exception 'alarma no matchea: %', f; end if;
   execute replace(replace(d, v_al1, n_al1), v_al2, n_al2);
 end loop;
 d := pg_get_functiondef('public.gv_monitor_ingresos(timestamptz,timestamptz)'::regprocedure);
 if position('v27.69-cerv' in d) = 0 then
   if (length(d)-length(replace(d,v_in,'')))/length(v_in) <> 1 then raise exception 'ingresos no matchea'; end if;
   execute replace(d, v_in, n_in); end if;
 d := pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure);
 if position('v27.69-cerv' in d) = 0 then
   if (length(d)-length(replace(d,v_mon,'')))/length(v_mon) <> 1 then raise exception 'monitor no matchea'; end if;
   execute replace(d, v_mon, n_mon); end if;
end $q$;
-- Rollback: el mismo bloque con v_* y n_* intercambiados.
