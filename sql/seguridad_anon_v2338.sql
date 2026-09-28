-- =============================================================================
-- v23.38 (2026-09-28) — Seguridad: lo que la clave pública (anon) podía hacer y no
-- hacía falta. Auditoría completa en el repo GP2: SEGURIDAD_ANON_GESTION_VIRGILIO_2026-09-28.md.
-- Se va 1 x 1 con el dueño; cada bloque dice si está APLICADO o PENDIENTE.
-- =============================================================================

-- 1) APLICADO 28/09. diag_ins dejaba a anon SUBIR archivos a CUALQUIER bucket
--    (with check = true): isis-lk / isis-ch (facturas), reportes, planify_page
--    (público = hosting de phishing con el dominio del proyecto). Su compañera diag_del
--    es sólo de planify_diag_priv, así que ése era el bucket buscado. El agente de ISIS
--    sube con la service key (como agente-local/nc_ingest.py), que no pasa por RLS.
--    Verificado: anon rechazado en isis-lk/planify_page/cuarentena, acepta planify_diag_priv.
drop policy if exists diag_ins on storage.objects;
create policy diag_ins on storage.objects for insert to anon
  with check (bucket_id = 'planify_diag_priv');
-- rollback: drop policy diag_ins on storage.objects;
--           create policy diag_ins on storage.objects for insert to anon with check (true);

-- 2a) APLICADO 28/09. remitos: nadie borra fotos (recepcion.js sólo sube).
drop policy if exists remitos_delete on storage.objects;
-- rollback: create policy remitos_delete on storage.objects for delete
--             to anon, authenticated using (bucket_id = 'remitos');

-- 2b) APLICADO 28/09 (dueño: con UPDATE abierto cualquiera "borra" pisando la foto con un
--     archivo vacío). Verificado: anon actualiza 0 filas y sigue pudiendo subir.
--     COSTO ACEPTADO: una tablet < v23.38 sube con upsert (exige UPDATE) → ve "No se pudo
--     subir la foto… No se grabó nada" y no cierra la recepción hasta tocar "Actualizar".
drop policy if exists remitos_update on storage.objects;
-- rollback: create policy remitos_update on storage.objects for update to anon, authenticated
--             using (bucket_id = 'remitos') with check (bucket_id = 'remitos');

-- 2c) PENDIENTE — remitos_select. Probado en SQL: un INSERT ... RETURNING sin política
--     SELECT falla por RLS. Si Storage sube con RETURNING, sacarla rompe TODAS las subidas.
--     Se prueba contra el Storage real antes de tocarla.
-- drop policy if exists remitos_select on storage.objects;
