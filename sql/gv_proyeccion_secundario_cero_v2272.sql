-- v22.72 (Luis, 25/09/2026): "Los secundarios cuentan proyeccion para su principal ... toda la
-- proyeccion del secundario se vuelca al principal. aplica para todos los lugares eso. si el 580E
-- tuvo demanda, no deberia aparecer ni en stocks ni en importados".
-- gv_proyeccion_articulo: la fila del SECUNDARIO pasa a proy_cajas_mes / proy_lk / proy_ch = 0.
-- proy_propia conserva su venta (es lo que el principal muestra en "incluye …").
-- El principal no cambia: ya sumaba al secundario (v22.68).
-- Aplicado sobre pg_get_viewdef (definicion viva), raise si no matchea; security_invoker re-puesto.
-- Backup: zz_backups."GV_Backup_gpa_def_20260925b". Medido: 17 secundarios en 0.
do $$ declare d text; n text; begin
 d := pg_get_viewdef('public.gv_proyeccion_articulo'::regclass,true);
 n := replace(d, E'pm.lk AS proy_lk,\n    pm.ch AS proy_ch,\n    pm.lk + pm.ch AS proy_cajas_mes,', E'0::numeric AS proy_lk,\n    0::numeric AS proy_ch,\n    0::numeric AS proy_cajas_mes,');
 if n = d then raise notice 'ya aplicado'; return; end if;
 execute 'create or replace view public.gv_proyeccion_articulo as '||n;
 execute 'alter view public.gv_proyeccion_articulo set (security_invoker = true)';
end $$;
-- chequeo: select cod, proy_cajas_mes, proy_propia, principal from gv_proyeccion_articulo where es_secundario;
