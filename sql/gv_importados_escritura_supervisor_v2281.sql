-- v22.81 — El maestro de importados (Importados / Importados_Volumen) se escribe sólo con login
-- de SUPERVISOR. Auditoría: github_repo_problemas, "Importados e Importados_Volumen se pueden
-- modificar sin login (anon y usuarios anonimos)".
--
-- Por qué supervisor y no "cualquier usuario logueado": el proyecto tiene usuarios ANÓNIMOS
-- (signInAnonymously, 449 al 25/09) y un anónimo tiene el rol `authenticated`. Una política
-- "to authenticated using (true)" la abre cualquiera con la clave publicable (que está en este
-- repo público). es_supervisor_virgilio() mira el mail del JWT (3 fijos + Supervisores_Virgilio):
-- un anónimo no tiene mail → false.
--
-- La lectura NO cambia (anon sigue leyendo: el portal LK y Gestión leen con la clave publicable).
-- Las RPC SECURITY DEFINER (importados_set_curso, importados_marcar_llegada, gv_importados_resync)
-- no pasan por la RLS: no cambian con esto (pendiente aparte).

-- ── Estado ANTERIOR (backup, para volver atrás) ─────────────────────────────────────────────
-- Importados:
--   imp_read      SELECT  to anon, authenticated  using (true)                 ← se mantiene
--   imp_upd_anon  UPDATE  to anon, authenticated  using (true) with check (true)
--   imp_write     ALL     to authenticated        using (true) with check (true)
-- Importados_Volumen:
--   impvol_sel    SELECT  to anon                 using (true)                 ← se mantiene
--   impvol_ins    INSERT  to anon                 with check (true)
--   impvol_upd    UPDATE  to anon                 using (true) with check (true)
-- Grants de anon en las dos tablas: INSERT, REFERENCES, SELECT, TRIGGER, UPDATE.

-- ── Paso A (aplicado 2026-09-25, aditivo: no cambia nada mientras sigan las viejas) ──────────
create policy imp_write_supervisor on public."Importados"
  for all to authenticated
  using (public.es_supervisor_virgilio())
  with check (public.es_supervisor_virgilio());

create policy impvol_sel_auth on public."Importados_Volumen"
  for select to authenticated using (true);          -- el upsert (on conflict) necesita ver la fila

create policy impvol_ins_supervisor on public."Importados_Volumen"
  for insert to authenticated
  with check (public.es_supervisor_virgilio());

create policy impvol_upd_supervisor on public."Importados_Volumen"
  for update to authenticated
  using (public.es_supervisor_virgilio())
  with check (public.es_supervisor_virgilio());

-- ── Paso C (después de publicar v22.81, que escribe con el JWT: _impEscribir) ───────────────
drop policy if exists imp_upd_anon on public."Importados";
drop policy if exists imp_write    on public."Importados";
drop policy if exists impvol_ins   on public."Importados_Volumen";
drop policy if exists impvol_upd   on public."Importados_Volumen";
revoke insert, update, delete on public."Importados"         from anon;
revoke insert, update, delete on public."Importados_Volumen" from anon;

-- ── Verificación ─────────────────────────────────────────────────────────────────────────────
-- select tablename, policyname, cmd, roles, qual, with_check from pg_policies
--  where schemaname='public' and tablename in ('Importados','Importados_Volumen') order by 1,2;
-- Un PATCH con la clave publicable como Bearer tiene que volver [] (0 filas) y no cambiar nada.

-- ── Volver atrás (sólo si hace falta) ────────────────────────────────────────────────────────
-- grant insert, update on public."Importados", public."Importados_Volumen" to anon;
-- create policy imp_upd_anon on public."Importados" for update to anon, authenticated using (true) with check (true);
-- create policy imp_write    on public."Importados" for all to authenticated using (true) with check (true);
-- create policy impvol_ins   on public."Importados_Volumen" for insert to anon with check (true);
-- create policy impvol_upd   on public."Importados_Volumen" for update to anon using (true) with check (true);
