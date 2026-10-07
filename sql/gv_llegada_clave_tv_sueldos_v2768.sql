-- v27.68 (Thomas, 07/10/2026): DOS RELOJES DISTINTOS
--  1) MONITOR y ALARMA: la llegada cuenta SÓLO si entró con el código de la TV
--     (GV_Dispositivo_Login.metodo in ('clave_tv','nombre'); 'nombre' = «No estoy en la lista», que también
--     pasa por el código). Un legajo tipeado (celular viejo) o una sesión guardada NO es llegada.
--     Toca: gv_monitor_horas_operario_dia (jornada.primer), gv_monitor_ingresos (TV / Mon. Admin / index),
--     gv_alerta_inactivo_servidor (CTE ing).
--  2) LIQUIDACIÓN DE SUELDOS (gv_horas_operario_detalle_v2, xlsx de horas): la jornada arranca en el PRIMER
--     REGISTRO PRODUCTIVO, no en la llegada: se saca el login de v27.54 y se toma el primer evento que no es
--     automático, anulado (X) ni Terminar Día.
-- Parche idempotente sobre las definiciones vivas. Huella del monitor re-congelada. Centinelas 340-343.
-- REGLA_CONFIRMADA_POR_USUARIO
do $q$ declare d text; n text;
 v_mon text := 'where l.tipo = ''operario'' and l.legajo = b.legajo';
 n_mon text := 'where l.tipo = ''operario'' and l.metodo in (''clave_tv'',''nombre'') /* v27.68-clavetv */ and l.legajo = b.legajo';
 v_sue text := 'select b.legajo, least(min(b.ts_cliente), (select min(l.created_at) from public."GV_Dispositivo_Login" l where l.tipo = ''operario'' and l.legajo = b.legajo and (l.created_at at time zone ''America/Argentina/Buenos_Aires'')::date = p_dia)) as primer,  -- v27.54-fichaje (Thomas D5): la jornada arranca al fichar en la app';
 n_sue text := 'select b.legajo, coalesce(min(b.ts_cliente) filter (where b.opcion !~ ''X$'' and b.opcion not in (''FJ'',''PUB'',''AUB'',''ENT'',''RSP'',''ROC'',''RAG'',''FGU'',''FSS'',''IMPT'',''TAL'',''GST'',''MGR'',''PKM'',''SSG'',''PSP'',''NPD'',''PKAX'')), min(b.ts_cliente)) as primer,  -- v27.68-sueldo1er (Thomas): para sueldos la jornada arranca en el primer registro productivo, no en la llegada';
 v_al text := 'where l.tipo = ''operario'' and l.created_at >= v_desde';
 n_al text := 'where l.tipo = ''operario'' and l.metodo in (''clave_tv'',''nombre'') /* v27.68-clavetv */ and l.created_at >= v_desde';
 v_in text := 'where l.tipo = ''operario'' and l.created_at >= p_desde';
 n_in text := 'where l.tipo = ''operario'' and l.metodo in (''clave_tv'',''nombre'') /* v27.68-clavetv */ and l.created_at >= p_desde';
begin
 d := pg_get_functiondef('public.gv_monitor_horas_operario_dia(date)'::regprocedure);
 if position('v27.68-clavetv' in d) = 0 then
   if (length(d)-length(replace(d,v_mon,'')))/length(v_mon) <> 1 then raise exception 'monitor no matchea'; end if;
   execute replace(d, v_mon, n_mon); end if;
 d := pg_get_functiondef('public.gv_horas_operario_detalle_v2(date)'::regprocedure);
 if position('v27.68-sueldo1er' in d) = 0 then
   if (length(d)-length(replace(d,v_sue,'')))/length(v_sue) <> 1 then raise exception 'sueldos no matchea'; end if;
   execute replace(d, v_sue, n_sue); end if;
 d := pg_get_functiondef('public.gv_alerta_inactivo_servidor(boolean,timestamptz)'::regprocedure);
 if position('v27.68-clavetv' in d) = 0 then
   if (length(d)-length(replace(d,v_al,'')))/length(v_al) <> 1 then raise exception 'alarma no matchea'; end if;
   execute replace(d, v_al, n_al); end if;
 d := pg_get_functiondef('public.gv_monitor_ingresos(timestamptz,timestamptz)'::regprocedure);
 if position('v27.68-clavetv' in d) = 0 then
   if (length(d)-length(replace(d,v_in,'')))/length(v_in) <> 1 then raise exception 'ingresos no matchea'; end if;
   execute replace(d, v_in, n_in); end if;
end $q$;
-- Rollback: el mismo bloque con v_* y n_* intercambiados.
-- También la sobrecarga vieja gv_alerta_inactivo_servidor(boolean) (sin llamador) con el mismo reemplazo.
-- Huella: update "GV_Huella_Objeto" set md5_esperado='74a2aeae0486cd7006f2f54f5f2c734d', version='v27.68'
--         where objeto='gv_monitor_horas_operario_dia';
-- Centinelas v27.68 (4 filas): patrón l\.metodo in \('clave_tv','nombre'\) en monitor, ingresos y alarma;
--   min\(b\.ts_cliente\) filter \(where b\.opcion !~ 'X\$' en gv_horas_operario_detalle_v2.
-- Medido 06/10: Franco (237) entró tipeando el legajo (08:29) → ya no cuenta como llegada; monitor y sueldo
--   quedan iguales (6,43 h). Hoy (07/10) la TV muestra 8, 94 y 104; el 277 (legajo tipeado) no.
