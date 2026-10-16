-- ============================================================================
-- v32.09 · «A Costos VIGENTES» ENTERO en línea (pedido 16/10: "quiero que todo esté en línea")
--
-- Hasta acá la macro subía sólo «Lista de Precios » y lista_precios_subir copiaba las
-- otras hojas de la foto anterior: Costos, Cajas, Talleristas, etc. seguían como el
-- 07/09. Ahora la macro, al guardar, hace:
--   1) lista_precios_subir (igual que siempre: foto nueva + diff + aviso a Telegram);
--   2) planilla_hojas_cargar, en tandas, con TODAS las demás hojas del libro, sobre
--      la MISMA foto que devolvió el paso 1.
--
-- planilla_hojas_cargar REEMPLAZA cada hoja que recibe (borra sus filas en esa foto
-- y carga las nuevas): una fila borrada en el Excel desaparece también de la base.
-- Las hojas que no manda quedan como las heredó el paso 1.
--
-- Candados: el mismo token de la macro ("GP2".planilla_token) o una sesión autorizada
-- de GP2; sólo escribe en la foto VIGENTE y si tiene menos de 15 minutos (no se puede
-- reescribir una foto vieja). No toca «Lista de Precios » (esa la carga el paso 1).
--
-- Nadie más lee "GP2".planilla_fila (medido 16/10: sólo las vistas v_planilla_costo /
-- v_planilla_precio y el diff de la Lista de Precios, que no cambian).
--
-- Rollback: drop function if exists "GP2".planilla_hojas_cargar(integer, jsonb, text);
-- ============================================================================

create or replace function "GP2".planilla_hojas_cargar(
  p_snapshot_id integer, p_filas jsonb, p_token text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'GP2', 'pg_temp'
as $function$
declare
  v_ok boolean; v_hojas int; v_filas int;
begin
  if p_token is null or not exists (select 1 from "GP2".planilla_token t where t.token = p_token) then
    perform "GP2"._exigir_autorizado();
  end if;

  select s.vigente and s.subido_en > now() - interval '15 minutes' into v_ok
    from "GP2".planilla_snapshot s where s.id = p_snapshot_id;
  if not coalesce(v_ok, false) then
    raise exception 'la foto % no es la vigente o tiene más de 15 minutos', p_snapshot_id;
  end if;

  if p_filas is null or jsonb_typeof(p_filas) <> 'object' then
    raise exception 'p_filas tiene que ser {"hoja": [[fila,{celdas},bloque,formulas], ...]}';
  end if;
  if p_filas ? 'Lista de Precios ' then
    raise exception 'la Lista de Precios se sube con lista_precios_subir';
  end if;

  delete from "GP2".planilla_fila f
   where f.snapshot_id = p_snapshot_id
     and f.hoja in (select jsonb_object_keys(p_filas));

  v_filas := "GP2".planilla_cargar(p_snapshot_id, p_filas);
  select count(*) into v_hojas from jsonb_object_keys(p_filas);

  return jsonb_build_object('ok', true, 'snapshot', p_snapshot_id, 'hojas', v_hojas, 'filas', v_filas);
end $function$;

revoke all on function "GP2".planilla_hojas_cargar(integer, jsonb, text) from public;
grant execute on function "GP2".planilla_hojas_cargar(integer, jsonb, text) to anon, authenticated;

-- ============================================================================
-- Cierre de lectura (problema 884): planilla_fila / planilla_snapshot tenían policy
-- SELECT true para anon, y las dos vistas no eran security_invoker. Con la clave
-- pública cualquiera leía precios de proveedores y costos. Lectores reales: 0
-- (16/10: 0 pedidos REST en 24 h, ningún front). Queda: authenticated autorizado de GP2.
-- Rollback: alter policy p_gp2_select on "GP2".planilla_fila to anon, authenticated using (true);
--           (ídem planilla_snapshot) + grant select ... to anon.
-- ============================================================================
alter policy p_gp2_select on "GP2".planilla_fila     to authenticated using ("GP2"._autorizado());
alter policy p_gp2_select on "GP2".planilla_snapshot to authenticated using ("GP2"._autorizado());
revoke select on "GP2".planilla_fila, "GP2".planilla_snapshot,
                 "GP2".v_planilla_costo, "GP2".v_planilla_precio from anon;
alter view "GP2".v_planilla_costo  set (security_invoker = true);
alter view "GP2".v_planilla_precio set (security_invoker = true);
