-- ✅ APLICADO 2026-08-28 (migración `es_legajo_test_fase_b_vistas`).
-- Fase B de es_legajo_test: 7 vistas reemplazaron el chequeo ad-hoc
--   legajo <> ALL (ARRAY['0','1'])
-- por la función centralizada es_legajo_test().
--
-- Vistas actualizadas (en orden de riesgo):
--   1. vista_tanda_status            (pat_std)
--   2. vista_faltante_demanda        (pat_trim)
--   3. vista_faltante_real           (pat_rleg → r.legajo)
--   4. vista_correcciones_pedido_rich (pat_std)
--   5. vista_productividad_semanal   (pat_std)
--   6. vista_productividad_diaria    (pat_std)
--   7. vista_faltantes_sin_completar (pat_ctrim)
--
-- La migración usó un DO block con replace() dinámico sobre pg_views.definition
-- para garantizar que la lógica de la vista no cambie salvo el filtro de legajo.
-- Fase C (UPDATE Empleados.tipo): pendiente — requiere backup + permiso explícito.

do $outer$
declare
  vname text;
  def   text;
  n     int := 0;
  pat_std   text := $p$COALESCE("Registros_Produccion_Virgilio".legajo, ''::text) <> ALL (ARRAY['0'::text, '1'::text])$p$;
  pat_trim  text := $p$TRIM(BOTH FROM "Registros_Produccion_Virgilio".legajo) <> ALL (ARRAY['0'::text, '1'::text])$p$;
  pat_rleg  text := $p$TRIM(BOTH FROM r.legajo) <> ALL (ARRAY['0'::text, '1'::text])$p$;
  pat_ctrim text := $p$COALESCE(TRIM(BOTH FROM "Registros_Produccion_Virgilio".legajo), ''::text) <> ALL (ARRAY['0'::text, '1'::text])$p$;
  rep_rpv   text := $r$NOT es_legajo_test("Registros_Produccion_Virgilio".legajo)$r$;
  rep_rleg  text := $r2$NOT es_legajo_test(r.legajo)$r2$;
begin
  foreach vname in array array[
    'vista_tanda_status',
    'vista_faltante_demanda',
    'vista_faltante_real',
    'vista_correcciones_pedido_rich',
    'vista_productividad_semanal',
    'vista_productividad_diaria',
    'vista_faltantes_sin_completar'
  ] loop
    select definition into strict def
    from pg_views
    where schemaname = 'public' and viewname = vname;

    def := replace(def, pat_std,   rep_rpv);
    def := replace(def, pat_trim,  rep_rpv);
    def := replace(def, pat_rleg,  rep_rleg);
    def := replace(def, pat_ctrim, rep_rpv);

    execute format('create or replace view public.%I as %s', vname, def);
    n := n + 1;
    raise notice 'ok: %', vname;
  end loop;
  raise notice 'Fase B completa: % vistas actualizadas', n;
end $outer$;
