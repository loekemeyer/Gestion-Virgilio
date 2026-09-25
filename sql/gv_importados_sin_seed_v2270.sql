-- v22.70 (Luis, 25/09/2026): "los sin proyeccion, dejalos sin proyeccion. no le pongas una
-- proyeccion a mano. ya no va mas eso".
-- gv_importados_ordenes y v_importados_ordenes: est_madre_eff = coalesce(override, live, 0).
-- Se saca i.est_madre_seed del coalesce (era el valor inicial cargado a mano cuando no habia
-- venta) y la fuente pasa de 'seed' a 'sin proyeccion'. La columna est_madre_seed sigue en la
-- tabla y en la vista (historia), pero ya no decide nada.
-- Aplicado sobre pg_get_viewdef (definicion viva) con replace() y raise si no matchea;
-- security_invoker re-puesto. Backup: zz_backups."GV_Backup_imp_views_20260925".
-- Medido: live 105 filas / 58.713 uni · override 2 / 672 · sin proyeccion 49 / 0.
do $$ declare v text; d text; n text; begin
 foreach v in array array['gv_importados_ordenes','v_importados_ordenes'] loop
  d := pg_get_viewdef(('public.'||v)::regclass,true);
  n := replace(d, 'END, i.est_madre_seed, 0::numeric) AS est_madre_eff', 'END, 0::numeric) AS est_madre_eff');
  n := replace(n, 'ELSE ''seed''::text', 'ELSE ''sin proyeccion''::text');
  if n = d then raise notice 'ya aplicado en %', v; continue; end if;
  execute 'create or replace view public.'||v||' as '||n;
  execute 'alter view public.'||v||' set (security_invoker = true)';
 end loop; end $$;
-- Rollback: recrear desde zz_backups."GV_Backup_imp_views_20260925".def
