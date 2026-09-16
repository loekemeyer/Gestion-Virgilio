-- v19.06 (2026-09-16) — Barrido de grants: cerrar a `anon` las RPC que no usa nadie.
--
-- EL PROBLEMA (problema 354)
--   Postgres otorga `EXECUTE` a **PUBLIC** en CADA función nueva, y `anon` hereda de PUBLIC.
--   O sea: toda RPC nace ejecutable con la clave pública que está escrita en `index.html`.
--   Al 16/09 eran **216 de 369** `SECURITY DEFINER` en `public`, y sólo **10** tenían algún
--   chequeo de identidad adentro. Y son SECURITY DEFINER: corren como `postgres` y saltean RLS.
--
-- ⚠ LA TRAMPA QUE HACE QUE ESTO NO SE PUEDA BARRER A LO BRUTO
--   **Los operarios entran como `anon`**: su sesión es por legajo (localStorage
--   `vir_legajo_auth`), no Google. Sólo los supervisores son `authenticated`. Revocar en masa
--   deja a la planta sin picking, armado, carga ni recepción.
--
-- CÓMO SE DECIDIÓ QUÉ CERRAR (evidencia, no criterio)
--   1. Cruce del nombre de las 216 contra **todo el código** de 4 repos (874 archivos .js /
--      .html / .ts / .cjs / .json): `Gestion-Virgilio`, `pagina-LK-copia`, `paginach` y
--      `produccion-virgilio` (clonado para esto). → 123 aparecen, 88 no.
--   2. Cruce contra las llamadas REST **reales** de `edge_logs`, 5 días (11/09 al 16/09).
--   3. Sólo se cerró lo que falla LAS DOS pruebas, y encima por categoría demostrable.
--
-- ⚠ LO QUE ATAJÓ LA MEDICIÓN, Y QUE UN BARRIDO "OBVIO" HABRÍA ROTO
--   · **`es_supervisor_virgilio`** no aparece en el código ni en los logs… **pero la usan las
--     policies de RLS** de `storage.objects` (buckets `isis-lk` / `isis-ch`). Revocarla dejaba
--     a los supervisores sin las facturas. Se detecta así:
--       select p.proname from pg_policy pol, pg_proc p
--        where pg_get_expr(pol.polqual, pol.polrelid) ~* ('\m'||p.proname||'\s*\(');
--   · **`wa_dashboard_rango` y `wa_pipeline_log_reciente`** no se llamaron en 2 días, pero sí
--     el **11/09**: hay una pantalla que nadie abrió en la ventana corta. Por eso la ventana
--     se estiró a 5 días. **Dos días de logs no alcanzan para decir "no se usa".**
--   · El `sql/hardening_seguridad_20260828.sql` ya documentaba que `validar_login`,
--     `fichadaqr_ficho_hoy` y `cp_*` son de **apps EXTERNAS** (login, FichadaQR, portal de
--     proveedores) que entran como anon. Se respetaron.
--   · **Planify es un repo PRIVADO** que esta sesión no puede clonar, y varias
--     `planify_recruit_*` sí figuran en los logs. Las 9 que no figuran se dejaron abiertas:
--     sin poder leer ese front, "no aparece" no prueba nada.
--
-- LO QUE SE CERRÓ: 61 funciones, en tres tandas
--
--   A) 24 funciones de TRIGGER. Postgres **no chequea EXECUTE** para dispararlas y no se
--      pueden llamar como RPC (devuelven `trigger`): el grant a anon no hacía nada.
--      Probado de verdad, no leído: un INSERT en `Movimientos_Stock` **como anon** dentro de
--      una transacción abortada pasó sin "permission denied" → el trigger corrió.
--
--   B) 18: 10 que sólo dispara un cron (los 12 crons corren como `postgres`, verificado en
--      `cron.job.username`) + 8 helpers de SIMULACIÓN del pipeline de WhatsApp (`wa_sim_*`).
--      Probado: `select public.simular_ocs_automaticas()` sigue andando como postgres.
--
--   C) 18 sin UNA sola referencia en el código de los 4 repos ni UNA llamada en 5 días.
--
-- VERIFICADO DESPUÉS (como anon, que es como entra el operario)
--   gv_ppp_prog_arbol · gv_es_dia_habil · gv_ppp_atrasados · gv_importados_pedidos_curso ·
--   gv_imp_cargas  → las cinco contestan igual.
--   `select * from public.gv_endpoints_rotos;` → vacío.
--   Vistas sin `security_invoker` legibles por anon → vacío.
--
-- QUEDAN 155 abiertas, casi todas en uso real. Y **el schema `GP2` no se tocó**: sus bundles
-- (`inicio_bundle`, `tablet_bundle`, `oc_bundle`, `recepcion_bundle`…) son SECURITY DEFINER y
-- también están abiertos a anon. Es otra tanda.
--
-- ROLLBACK: `grant execute on function public.<nombre>(<args>) to public;` — devuelve el
-- estado original, que era `=X/postgres` (PUBLIC). Una línea por función.

-- A) TRIGGERS -------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and has_function_privilege('anon', p.oid, 'EXECUTE')
       and p.prorettype = 'trigger'::regtype
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
end $$;

-- B) SÓLO CRON + SIMULACIÓN -----------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and has_function_privilege('anon', p.oid, 'EXECUTE')
       and p.proname = any (array[
         'detectar_faltantes_llegaron','enviar_digest_agentes','generar_ocs_automaticas',
         'guardado_alerta_cervantes','gv_refrescar_precio_facturado','notificar_picking_sin_base',
         'simular_ocs_automaticas','wa_cuits_facturados_dia','wa_np_snapshot_run','gp2_matriz_racha_sync',
         'wa_sim_cleanup','wa_sim_cleanup_all','wa_sim_dest_phone','wa_sim_factura_np',
         'wa_sim_factura_paths','wa_sim_insert_documento','wa_sim_paths','wa_sim_seed_order'])
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
end $$;

-- C) SIN UN SOLO USO (0 en código de 4 repos, 0 llamadas en 5 días) --------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prosecdef
       and has_function_privilege('anon', p.oid, 'EXECUTE')
       and p.proname = any (array[
         'asignar_fleje_operario','costos_despiece','costos_despiece_resumen','costos_sync_produccion',
         'descontar_kg_fleje','faltante_tarea_cancelar','gv_fac_rs_np','gv_importado_bache_embarque',
         'gv_oc_recompute_recibido','gv_pedido_horario_borrar','gv_ppp_en_salida_desmarcar',
         'gv_ppp_web_cupo_dias','gv_ppp_web_tanda_avisos','oc_backfill_valores','refresh_stock_view',
         'wa_factura_grupo','wa_grupo_completo_check','wa_grupos_dia_cuit'])
  loop
    execute format('revoke execute on function %s from public, anon', r.sig);
  end loop;
end $$;

-- CHEQUEOS
-- select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname='public' and p.prosecdef and has_function_privilege('anon', p.oid,'EXECUTE');
-- -- 216 antes -> 155 después
--
-- -- ninguna función de trigger debería quedar con el grant:
-- select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname='public' and p.prosecdef and has_function_privilege('anon', p.oid,'EXECUTE')
--    and p.prorettype='trigger'::regtype;   -- 0
--
-- -- y lo que usa una policy NUNCA se revoca: este barrido tiene que salir vacío o
-- -- nombrar sólo funciones que siguen abiertas.
-- select p.proname, has_function_privilege('anon', p.oid,'EXECUTE') as anon
--   from pg_policy pol
--   cross join lateral (select pg_get_expr(pol.polqual, pol.polrelid) || ' ' ||
--                              coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid),'') as txt) e
--   join pg_proc p on p.pronamespace = 'public'::regnamespace
--    and e.txt ~* ('\m' || p.proname || '\s*\(');
