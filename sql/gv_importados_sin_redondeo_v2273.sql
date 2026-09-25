-- v22.73 (Luis, 25/09/2026): "el redondeo me hace ruido".
-- Importados convertia la proyeccion a UNIDADES con round(...) entero, asi que al
-- volver a cajas no coincidia con Stock (ej. 870E: 8,25 vs 8,33 caj/mes).
-- Ahora redondea a 2 decimales: Importados en cajas == gv_proyeccion_articulo.
-- Medido: 103 importados con proyeccion, 0 diferencias.
-- Aplicado sobre la definicion VIVA de las dos vistas (conserva security_invoker):
do $$
declare v text; d text;
begin
  foreach v in array array['public.gv_importados_ordenes','public.v_importados_ordenes'] loop
    d := pg_get_viewdef(v::regclass, true);
    d := regexp_replace(d, 'round\(p\.proy_cajas_mes \* (COALESCE\([^()]*\))\)',
                           'round(p.proy_cajas_mes * \1, 2)', 'g');
    execute format('create or replace view %s with (security_invoker = true) as %s', v, d);
  end loop;
end $$;
-- Rollback: recrear desde zz_backups."GV_Backup_imp_views_20260925c" (definiciones previas).
