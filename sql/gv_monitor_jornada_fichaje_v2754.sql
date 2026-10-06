-- v27.54 (Thomas, D5, 06/10/2026): la JORNADA arranca al FICHAR en la app (ingreso con el código de la TV),
-- no en el primer evento. Caso Franco Ortiz (237): ingresó 08:29, primera tarea 10:37 -> esas 2:08 ahora son
-- tiempo muerto (hs_total 8,56; prod 5,41 + no prod 1,02).
-- Parche idempotente sobre la definición viva de gv_monitor_horas_operario_dia y su copia gv_horas_operario_detalle_v2
-- (CTE jornada.primer). Huella re-congelada a a3847ed8..., centinela 337. El 15/09 del test no cambia (logins desde 30/09).
-- REGLA_CONFIRMADA_POR_USUARIO
do $q$ declare f text; d text; v text := 'select b.legajo, min(b.ts_cliente) as primer,';
 n text := 'select b.legajo, least(min(b.ts_cliente), (select min(l.created_at) from public."GV_Dispositivo_Login" l where l.tipo = ''operario'' and l.legajo = b.legajo and (l.created_at at time zone ''America/Argentina/Buenos_Aires'')::date = p_dia)) as primer,  -- v27.54-fichaje (Thomas D5): la jornada arranca al fichar en la app';
begin
 foreach f in array array['public.gv_monitor_horas_operario_dia(date)','public.gv_horas_operario_detalle_v2(date)'] loop
   d := pg_get_functiondef(f::regprocedure);
   if position('v27.54-fichaje' in d) > 0 then continue; end if;
   if (length(d) - length(replace(d, v, ''))) / length(v) <> 1 then raise exception 'no matchea en %', f; end if;
   execute replace(d, v, n);
 end loop;
end $q$;
-- Rollback: el mismo bloque con v y n intercambiados (y la huella al md5 anterior).
