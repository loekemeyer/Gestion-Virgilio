-- v23.02 (problema 577): Stock_Config se escribe SÓLO con login de supervisor.
-- Antes: scfg_insert / scfg_update para anon con `true` → cualquiera con la clave pública
-- cambiaba la fecha de entrega del carrito LK, el mínimo de 25.000 USD o el cutoff del stock.
-- Las 9 escrituras vivas de index.html están en pantallas de supervisor y pasan a mandar el JWT
-- de la sesión (_scfgAuth → facAuthWriteHeaders). Las lecturas siguen abiertas (el operario lee
-- cutoff_ts, ratio de guardado, etc.). Las funciones que escriben (guardado_recalc_ratio,
-- gv_proy_config_guardar) son SECURITY DEFINER: no cambian.
-- ⚠ Producción Virgilio escribe los mismos ajustes con la anon: esos botones dejan de guardar.
--
-- Rollback:
--   create policy scfg_insert on public."Stock_Config" for insert to anon with check (true);
--   create policy scfg_update on public."Stock_Config" for update to anon using (true) with check (true);
--   grant insert, update, delete on public."Stock_Config" to anon;
--   drop policy scfg_sup_select on public."Stock_Config"; drop policy scfg_sup_insert on public."Stock_Config";
--   drop policy scfg_sup_update on public."Stock_Config"; drop policy scfg_sup_delete on public."Stock_Config";

drop policy if exists scfg_insert on public."Stock_Config";
drop policy if exists scfg_update on public."Stock_Config";
revoke insert, update, delete, truncate on public."Stock_Config" from anon;
revoke truncate on public."Stock_Config" from authenticated;

-- el upsert (on conflict do update) exige ver la fila existente también como authenticated
create policy scfg_sup_select on public."Stock_Config" for select to authenticated using (true);
create policy scfg_sup_insert on public."Stock_Config" for insert to authenticated
  with check (public.es_supervisor_virgilio());
create policy scfg_sup_update on public."Stock_Config" for update to authenticated
  using (public.es_supervisor_virgilio()) with check (public.es_supervisor_virgilio());
create policy scfg_sup_delete on public."Stock_Config" for delete to authenticated
  using (public.es_supervisor_virgilio());
