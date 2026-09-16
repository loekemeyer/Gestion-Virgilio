-- v19.03 (2026-09-16) — Conciliación: las 6 RPC del módulo se cierran a `anon`.
--
-- QUÉ ESTABA MAL
--   Las 6 funciones gv_conciliacion_* eran SECURITY DEFINER con EXECUTE para PUBLIC (y por
--   herencia, para `anon`). Medido con `set role anon` el 16/09:
--
--     gv_conciliacion_lista(500,0,null,null)  ->  143 filas, con razón social
--     ("Extralimp S.A."), neto de Gestión ($3.142.920), neto de ISIS y el storage_path del PDF.
--
--   La anon key está escrita en index.html, que se sirve por GitHub Pages: cualquiera que la
--   copie leía la facturación del depósito. `gv_conciliacion_registrar` además ESCRIBE.
--
--   El PDF en sí NO se filtraba: los buckets isis-lk / isis-ch son privados y su policy exige
--   `authenticated` + `es_supervisor_virgilio()`. Lo que se escapaba era el NOMBRE del archivo
--   (que lleva el número de comprobante), no el contenido.
--
--   ⚠ No es un agujero de esta pantalla ni de la v18.88: es el **default de Postgres** —cada
--   función nueva nace con EXECUTE para PUBLIC— y nadie lo revocó nunca. Al 16/09 había
--   **219 de 366** funciones SECURITY DEFINER alcanzables por `anon` en este proyecto.
--
-- POR QUÉ NO ROMPE NADA (verificado antes de tocar, no supuesto)
--   | Dónde se buscó                          | Resultado          |
--   |-----------------------------------------|--------------------|
--   | cron.job (command)                      | ninguno la llama   |
--   | pg_proc.prosrc (otras funciones)        | ninguna            |
--   | vistas (pg_rewrite)                     | ninguna            |
--   | Edge Functions (las 8 del repo)         | ninguna            |
--   | repos pagina-LK-copia y paginach        | nada               |
--   | repo produccion-virgilio (clonado)      | nada               |
--   | código de Gestión                       | sólo index.html    |
--
--   Y en edge_logs de 24 h, quien las llama son navegadores Chrome — ningún n8n, script ni curl.
--   **La prueba que cierra el tema:** en esos mismos logs, `/storage/v1/object/sign/isis-lk/...`
--   devuelve **200**, y ese endpoint sólo funciona para `authenticated` + supervisor. O sea que
--   la pantalla ya entra con sesión de Google: sacarle el permiso a `anon` no la toca.
--
-- VERIFICADO DESPUÉS
--   set role anon         -> "permission denied for function gv_conciliacion_lista" (42501)
--   set role authenticated-> lista 143 · totales 3 · comparar 1 · detalle 1 · motivo ok
--                            (idéntico a antes del revoke)
--
-- ROLLBACK (deja todo como estaba: el grant de PUBLIC era `=X/postgres`)
--   grant execute on function public.gv_conciliacion_lista(integer,integer,text,text) to public;
--   grant execute on function public.gv_conciliacion_comparar(text)  to public;
--   grant execute on function public.gv_conciliacion_motivo(text)    to public;
--   grant execute on function public.gv_conciliacion_detalle(text)   to public;
--   grant execute on function public.gv_conciliacion_totales(text)   to public;
--   grant execute on function public.gv_conciliacion_registrar(text) to public;

revoke execute on function public.gv_conciliacion_lista(integer,integer,text,text) from public, anon;
revoke execute on function public.gv_conciliacion_comparar(text)  from public, anon;
revoke execute on function public.gv_conciliacion_motivo(text)    from public, anon;
revoke execute on function public.gv_conciliacion_detalle(text)   from public, anon;
revoke execute on function public.gv_conciliacion_totales(text)   from public, anon;
revoke execute on function public.gv_conciliacion_registrar(text) from public, anon;

-- CHEQUEO: anon en false, authenticated y service_role en true, las 6.
-- select p.proname,
--        has_function_privilege('anon', p.oid,'EXECUTE')          as anon,
--        has_function_privilege('authenticated', p.oid,'EXECUTE') as authenticated,
--        has_function_privilege('service_role', p.oid,'EXECUTE')  as service_role
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.proname like 'gv_conciliacion%' order by 1;

-- ⚠ LO QUE ESTO **NO** RESUELVE
--   `authenticated` es cualquiera con sesión de Google en este proyecto, no sólo un supervisor.
--   Hoy eso alcanza (a esta app sólo se loguean supervisores; los operarios usan la sesión por
--   legajo, que a nivel base es `anon`), pero el cierre fuerte sería meter el guard ADENTRO de
--   cada función, como ya hace el Storage:
--     if not public.es_supervisor_virgilio() then raise exception 'solo supervisores'; end if;
--   Ojo con la trampa ya documentada: el guard NO puede colgarse del FROM de una función SQL
--   —Postgres elimina la subconsulta y no se evalúa nunca—; va como `perform` en plpgsql.
--
--   Y quedan **213** funciones SECURITY DEFINER abiertas a `anon` en el resto del proyecto.
--   Eso es una tanda propia: inventariar cuáles llama el front de verdad y cerrar el resto.
