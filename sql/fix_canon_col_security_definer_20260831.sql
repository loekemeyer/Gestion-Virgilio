-- Fix aplicado 2026-08-31 en Supabase (proyecto Virgilio hrxfctzncixxqmpfhskv).
-- Migraciones: fix_canon_col_security_definer + fix_canon_col_revoke_rpc.
--
-- CONTEXTO
-- Desde 2026-08-28 (commit 5193af5, idea 7411) los INSERTs de `anon` en
-- `Entregas_Virgilio` — y en las otras 9 tablas con el mismo trigger — fallaban
-- con `42501 permission denied for function canon_cod_art_val`. Motivo: las
-- trigger fns `fn_canon_col_*` corrían SECURITY INVOKER y llamaban a
-- `canon_cod_art_val(text)`, que tiene `REVOKE EXECUTE FROM public, anon,
-- authenticated`. Los operarios armaban las tandas pero `Entregas_Virgilio`
-- quedaba vacía (encima el `.catch` de `_compSaveEntregas` tragaba silencioso
-- todo 4xx — corregido en front v12.18). Recién se cantó al deployar v12.17
-- que filtra el listado de Facturación por `_facCajas.has(np)`.
--
-- FIX
-- 1) Las 5 `fn_canon_col_*` pasan a SECURITY DEFINER SET search_path = public:
--    corren como postgres (owner), que sí tiene EXECUTE sobre canon_cod_art_val,
--    y se blinda contra search_path hijack.
-- 2) Se REVOKE EXECUTE ON las 5 trigger fns a public/anon/authenticated: los
--    triggers no chequean EXECUTE del rol invocador al dispararse (es interno)
--    así que los inserts de anon siguen funcionando; y se cierra la superficie
--    RPC `/rest/v1/rpc/fn_canon_col_*` que quedaba abierta al ser SECURITY
--    DEFINER (WARN del advisor).
--
-- El DDL previo del backup está en `sql/backups/backup_fn_canon_col_20260831.sql`.

ALTER FUNCTION public.fn_canon_col_cod_art()         SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.fn_canon_col_cod()             SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.fn_canon_col_cod_art_quoted()  SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.fn_canon_col_codigo()          SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.fn_canon_col_articulo()        SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION public.fn_canon_col_cod_art()        FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_canon_col_cod()            FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_canon_col_cod_art_quoted() FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_canon_col_codigo()         FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_canon_col_articulo()       FROM public, anon, authenticated;

-- Verificación: insert como anon en Entregas_Virgilio + limpieza inmediata.
DO $$
DECLARE
  test_id bigint;
BEGIN
  SET LOCAL ROLE anon;
  INSERT INTO public."Entregas_Virgilio"
    (fecha_salida, cod_cliente, np, cod_art, cajas_pedidas, cajas_entregadas, cajas_falto, tanda)
    VALUES ('2026-08-31','FIXTEST','FIXTEST_NP','FIXTEST_COD',1,1,0,'FIXTEST_TANDA')
  RETURNING id INTO test_id;
  RESET ROLE;
  DELETE FROM public."Entregas_Virgilio" WHERE id = test_id;
  RAISE NOTICE 'OK: insert como anon funciona (id=%, borrado)', test_id;
END $$;
