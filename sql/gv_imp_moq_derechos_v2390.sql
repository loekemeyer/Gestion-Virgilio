-- ══════════════════════════════════════════════════════════════════════════════
-- v23.90 — IMPORTADOS: MOQ por proveedor y DERECHOS por artículo
-- Pedido de Luis, 2026-09-29, sobre la v23.89:
--   "agregá al editor por proveedor MOQ (seteá el de todos en 1000 pero hacé que el
--    usuario lo pueda modificar y que impacte en el back el dato). Debería tener un
--    indicador en caso de que no se llegue al MOQ que diga que permite margen hasta
--    12 meses de cobertura … en caso de que sea más de 12 meses, que indique que está
--    fuera del target"
--   "derechos debería ser editable por artículo pero lo ponemos en el módulo de cada
--    importador «Configurar parámetros» que metemos ahora"
--
-- ── 1) MOQ ───────────────────────────────────────────────────────────────────
alter table public."GV_Imp_Proveedor"  add column if not exists moq            numeric;
alter table public."GV_Imp_Proveedor"  add column if not exists moq_meses_max  numeric;
alter table public."Importados_Config" add column if not exists moq            numeric;
alter table public."Importados_Config" add column if not exists moq_meses_max  numeric;

-- el general: 1.000 u y tope de 12 meses de cobertura (los dos, pedido de Luis)
update public."Importados_Config"
   set moq = coalesce(moq, 1000), moq_meses_max = coalesce(moq_meses_max, 12), actualizado = now()
 where id = 1;
-- y los 7 proveedores arrancan con 1.000, editable uno por uno desde el ⚙
update public."GV_Imp_Proveedor" set moq = 1000 where moq is null;

-- Las dos vistas suman `moq` / `moq_meses_max` (efectivo y propio) AL FINAL.
-- ⚠ CREATE OR REPLACE VIEW sólo deja AGREGAR columnas al final: meterlas en el medio da
--   «cannot change name of view column». El bloque completo se aplicó como está en §3.v2390
--   de docs/SUPABASE-GESTION-VIRGILIO.md.

-- Las RPC gv_imp_proveedor_guardar y gv_imp_nac_config_guardar se parchearon sobre
-- pg_get_functiondef (idempotente, con raise si el texto no matchea) agregando las dos
-- claves a sus listas de campos.

-- ── 2) DERECHOS POR ARTÍCULO ─────────────────────────────────────────────────
-- El % es la partida arancelaria del artículo, así que GANA sobre el del proveedor.
-- La cascada es: artículo → proveedor → general.
alter table public."Importados" add column if not exists derechos_pct numeric;

-- Se lee por una vista chica y aparte, a propósito: agregarle la columna a
-- gv_importados_ordenes obliga a reemplazar una vista con centinela y dependientes.
create or replace view public.gv_imp_articulo_cfg
with (security_invoker = true) as
select upper(btrim(cod_art)) as cod_art,
       max(derechos_pct) as derechos_pct,
       btrim(max(proveedor)) as proveedor
  from public."Importados"
 where activo and principal
 group by upper(btrim(cod_art));
alter view public.gv_imp_articulo_cfg set (security_invoker = true);

create or replace function public.gv_imp_articulo_derechos(p_cod text, p_pct numeric)
returns jsonb language plpgsql security definer set search_path to 'public' as $fn$
-- p_pct en TANTO POR UNO (0,35 = 35%). null = vuelve al % del proveedor.
-- Escribe todas las filas (marcas) de ese cod_art: el arancel es del artículo, no de la planta.
declare v_cod text; v_n int;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo supervisores';
  end if;
  v_cod := upper(nullif(btrim(p_cod), ''));
  if v_cod is null then raise exception 'Falta el codigo'; end if;
  if p_pct is not null and (p_pct < 0 or p_pct > 1) then
    raise exception 'Los derechos van en tanto por uno (0,35 = 35%%), no en porcentaje';
  end if;
  update public."Importados" set derechos_pct = p_pct, actualizado = now()
   where upper(btrim(cod_art)) = v_cod;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'El codigo % no esta en el maestro Importados', v_cod; end if;
  return jsonb_build_object('cod', v_cod, 'derechos_pct', p_pct, 'filas', v_n);
end $fn$;
revoke all on function public.gv_imp_articulo_derechos(text,numeric) from public, anon;
grant execute on function public.gv_imp_articulo_derechos(text,numeric) to authenticated, service_role;

-- ── Chequeo ──────────────────────────────────────────────────────────────────
-- select proveedor, moq, moq_meses_max, meses_objetivo, derechos_pct from public.gv_imp_proveedor_cfg order by orden;
-- select count(*) articulos, count(derechos_pct) con_arancel_propio from public.gv_imp_articulo_cfg;
-- select * from public.gv_reglas_perdidas;   -- vacía = todo bien

-- ── Rollback ─────────────────────────────────────────────────────────────────
-- alter table public."GV_Imp_Proveedor"  drop column if exists moq, drop column if exists moq_meses_max;
-- alter table public."Importados_Config" drop column if exists moq, drop column if exists moq_meses_max;
-- alter table public."Importados" drop column if exists derechos_pct;
-- drop view if exists public.gv_imp_articulo_cfg;
-- drop function if exists public.gv_imp_articulo_derechos(text,numeric);
-- (y volver las dos vistas y las dos RPC a la versión de sql/gv_imp_proveedor_config_v2389.sql)
