-- v28.98: la apertura RKI/IRI/MGI/MDI cuenta como tarea abierta aunque traiga ts_inicio
-- (celulares v28.48-v28.97 la mandaban con ts_inicio y sonaba la alarma con el operario adentro, caso 104 09/10).
-- Aplicado sobre pg_get_functiondef, idempotente (marcador v28.98-abre).
do $$ declare d text; n text; begin
 d := pg_get_functiondef('public.gv_alerta_inactivo_servidor(boolean,timestamptz)'::regprocedure);
 if d ~ 'v28.98-abre' then return; end if;
 n := replace(d, 'where a.ts_inicio is null and a.ts_cliente > v_now - interval ''12 hours''',
   'where (a.ts_inicio is null or a.opcion in (''RKI'',''IRI'',''MGI'',''MDI'')) /* v28.98-abre */ and a.ts_cliente > v_now - interval ''12 hours''');
 if n = d then raise exception 'no matcheo'; end if;
 execute n;
end $$;
-- Rollback: el mismo replace al revés.
