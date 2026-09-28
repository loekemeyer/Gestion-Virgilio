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

-- 2b) PENDIENTE — recién cuando NINGÚN equipo de recepción corra una versión < v23.38
--     (la app NO se actualiza sola: muestra el botón "Actualizar" y espera). Hasta
--     v23.37 la foto se subía con upsert, que exige SELECT + UPDATE; desde v23.38 sólo
--     INSERT. Borrarlas antes deja sin foto a las tablets viejas.
-- drop policy if exists remitos_update on storage.objects;
-- drop policy if exists remitos_select on storage.objects;
