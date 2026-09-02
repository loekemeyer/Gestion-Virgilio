-- =====================================================================
-- sync_proyeccion_madre_push.sql — la proyeccion pasa de PULL a PUSH (propuesta 2496)
-- APLICADO 2026-09-02.
--
-- == POR QUE ==========================================================
-- Antes: Virgilio TIRABA por HTTP con la anon key de LK
-- (`refresh_proyeccion_madre()` -> GET a rest/v1/rpc/fn_proyeccion_oc_virgilio).
--
-- Un barrido de seguridad en LK le revoco el EXECUTE a `anon` sobre esa funcion. El GET
-- paso a devolver 401, `refresh_proyeccion_madre()` retornaba **-1 sin recargar**, y el
-- cron marcaba "succeeded". Resultado: `proyeccion_madre` CONGELADA del 12/08 al 02/09
-- —tres semanas— sin que nadie se enterara. Es exactamente el modo de falla que el
-- comentario de `sql/refresh_proyeccion_madre.sql` ya advertia que habia pasado antes.
--
-- Reabrir a `anon` habria expuesto la proyeccion a cualquiera con la anon key, que es
-- publica (va embebida en los .js). Se eligio EMPUJAR: reusa la credencial que YA existe
-- (rol `lk_ppp_reader` del FDW `virgilio_db`) y deja a Virgilio leyendo una tabla LOCAL,
-- o sea cero FDW en su camino caliente. Mismo patron y mismo motivo que
-- `sync_pedidos_match_virgilio()` (ver sql/lk_pedidos_match.sql).
--
-- == LADO VIRGILIO (este proyecto, hrxfctzncixxqmpfhskv) ==============
grant select, insert, update, delete on public.proyeccion_madre to lk_ppp_reader;

-- RLS esta activo y la unica policy era de lectura (pm_read). Sin policy propia el rol
-- pasa el grant pero lo frena RLS.
drop policy if exists pm_writer on public.proyeccion_madre;
create policy pm_writer on public.proyeccion_madre
  for all to lk_ppp_reader
  using (true) with check (true);

-- El cron viejo se dio de baja: lo reemplaza el de LK.
--   select cron.unschedule('refresh_proyeccion_madre');
-- `refresh_proyeccion_madre()` NO se borro: queda como fallback manual, pero solo anda
-- si alguien vuelve a abrirle el EXECUTE a anon en LK. No es el camino normal.
--
-- == LADO LK (kwkclwhmoygunqmlegrg) ===================================
-- create foreign table if not exists virgilio.proyeccion_madre (
--   cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric, actualizado timestamptz
-- ) server virgilio_db options (schema_name 'public', table_name 'proyeccion_madre');
--
-- create or replace function public.sync_proyeccion_madre_virgilio() returns integer
--  language plpgsql security definer set search_path to 'public' set statement_timeout to '120s'
-- as $fn$
-- declare v_n integer; v_calc integer;
-- begin
--   -- Calcula PRIMERO en una temporal: si el motor falla o da vacio se aborta sin tocar
--   -- Virgilio. Mejor una proyeccion vieja que una tabla vaciada.
--   create temp table _proy_tmp on commit drop as
--     select cod, proy_cajas_mes, uxb, proy_uni_mes from public.fn_proyeccion_oc_virgilio()
--     where proy_cajas_mes > 0 and coalesce(btrim(cod),'') <> '';
--   select count(*) into v_calc from _proy_tmp;
--   if v_calc = 0 then
--     raise exception 'sync_proyeccion_madre_virgilio: el motor devolvio 0 filas, no se toca Virgilio';
--   end if;
--   delete from virgilio.proyeccion_madre where cod is not null;  -- supautils bloquea DELETE pelado
--   insert into virgilio.proyeccion_madre (cod, proy_cajas_mes, uxb, proy_uni_mes, actualizado)
--   select upper(btrim(cod)), proy_cajas_mes, uxb, proy_uni_mes, now() from _proy_tmp;
--   get diagnostics v_n = row_count; return v_n;
-- end; $fn$;
--
-- revoke execute on function public.sync_proyeccion_madre_virgilio() from public, anon, authenticated;
-- select cron.schedule('sync-proyeccion-madre-virgilio', '20 9 * * 3',
--                      $$select public.sync_proyeccion_madre_virgilio();$$);
--
-- Cadencia: miercoles 09:20 UTC — la misma que tenia el pull (09:00), corrida 20 min.
--
-- == VERIFICACION 2026-09-02 ==========================================
-- El push produjo un resultado IDENTICO al pull: 408 filas, suma 19.792,49 caj/mes,
-- md5 del contenido b3d4ad71581fc2e85412d64808483d7d en los dos casos.
-- =====================================================================
