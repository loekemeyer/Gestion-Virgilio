-- v18.70 (2026-09-15) — gv_anular_picking_virgilio: anular un picking deja de poder borrar
-- el stock de otro, y la ventana pasa de 24 h a 3 días.
--
-- ============================================================================================
-- Lo que estaba mal, y es de datos, no cosmético
-- ============================================================================================
-- La versión vieja (`anular_picking_virgilio`, que sigue usando Producción Virgilio) hacía:
--
--     update "Movimientos_Stock" set delta = 0
--      where tipo = 'picking' and upper(trim(ref)) = v_tanda and delta <> 0;
--
-- **Sin filtrar por legajo ni por fecha.** Los eventos PKC, en cambio, sí se borraban acotados
-- al operario y desde su EP (`legajo = v_leg and created_at >= v_ts`). O sea que la propia
-- función ya sabía cómo acotar, y en el renglón del stock no lo hacía.
--
-- Por qué eso puede romper: existen los **EP fantasma**, tandas ya pickeadas que alguien
-- reabre por error. Medidos: 6 en 120 días. Anular uno de ésos con la versión vieja ponía en
-- cero el picking **bueno** — en D30A eran 36 movimientos de una tanda que además ya estaba
-- armada, y en C69C 32.
--
-- La ventana de 24 h no era un guard pensado: era un amortiguador que tapaba esto por
-- casualidad, dejando afuera justo el caso que hay que poder limpiar («quedó abierto desde
-- ayer» — pasó con D71A el 15/09, que hubo que resolver a mano por SQL).
--
-- ============================================================================================
-- Lo que hace la nueva
-- ============================================================================================
--   1. Busca el último EP del legajo+tanda dentro de **3 días** (era 24 h).
--   2. Pregunta si la tanda YA tiene TP o TAP, de quien sea y cuando sea:
--        · SÍ  → es una reapertura por error. Borra el EP (y los PKC de ese legajo desde ahí)
--                y **no toca una sola fila de stock** → devuelve 'ep_fantasma_limpiado'.
--        · NO  → anulación normal, y el `delta = 0` va acotado a **ese legajo y desde ese EP**.
--   3. Suelta el lock con `gv_tanda_lock_anular` (v18.65), que lo deja LIBRE de verdad.
--
-- Ampliar la ventana es seguro recién ahora: lo que protege ya no es la fecha, es el guard.
--
-- ⚠ Función NUEVA con prefijo `gv_`, no un replace: `anular_picking_virgilio` la llama el front
-- de Producción Virgilio (`index.html:8832` de ese repo). Producción sigue con la suya.

create or replace function public.gv_anular_picking_virgilio(p_legajo text, p_tanda text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_leg   text := btrim(coalesce(p_legajo,''));
  v_tanda text := upper(btrim(coalesce(p_tanda,'')));
  v_id uuid; v_ts timestamptz; v_hecho boolean;
begin
  if v_leg = '' or v_tanda = '' then return 'faltan_datos'; end if;

  select r.id, coalesce(r.ts_cliente, r.created_at) into v_id, v_ts
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'EP' and r.legajo = v_leg
     and upper(btrim(coalesce(r.texto,''))) = v_tanda
     and coalesce(r.ts_cliente, r.created_at) > now() - interval '3 days'
   order by coalesce(r.ts_cliente, r.created_at) desc limit 1;
  if v_id is null then return 'sin_ep'; end if;

  select exists (
    select 1 from public."Registros_Produccion_Virgilio" c
     where c.opcion in ('TP','TAP')
       and upper(btrim(split_part(coalesce(c.texto,''),'|',1))) = v_tanda
       and not public.es_legajo_test(c.legajo)) into v_hecho;

  if v_hecho then
    delete from public."Registros_Produccion_Virgilio"
     where opcion = 'PKC' and legajo = v_leg
       and upper(btrim(coalesce(texto,''))) like v_tanda || '|%'
       and coalesce(ts_cliente, created_at) >= v_ts;
    delete from public."Registros_Produccion_Virgilio" where id = v_id;
    begin perform public.gv_tanda_lock_anular(v_tanda, 'picking', v_leg); exception when others then null; end;
    return 'ep_fantasma_limpiado';
  end if;

  delete from public."Registros_Produccion_Virgilio"
   where opcion = 'PKC' and legajo = v_leg
     and upper(btrim(coalesce(texto,''))) like v_tanda || '|%'
     and coalesce(ts_cliente, created_at) >= v_ts;
  delete from public."Registros_Produccion_Virgilio" where id = v_id;

  update public."Movimientos_Stock" set delta = 0
   where tipo = 'picking' and upper(btrim(ref)) = v_tanda and delta <> 0
     and coalesce(legajo,'') = v_leg and ts >= v_ts;

  begin perform public.gv_tanda_lock_anular(v_tanda, 'picking', v_leg); exception when others then null; end;
  return 'ok';
end $$;
revoke execute on function public.gv_anular_picking_virgilio(text,text) from public;
grant execute on function public.gv_anular_picking_virgilio(text,text) to anon, authenticated;

-- ============================================================================================
-- Prueba contra la base, con un EP fantasma simulado sobre D71A (pickeada Y armada ese día,
-- 333 cajas del 55219 movidas):
--                                     antes    después
--   movimientos de picking de D71A ..... 2         2      ← intactos
--   cajas movidas ...................... 666       666    ← intactas
--   EP de D71A ......................... 2         1      ← se fue sólo el fantasma
--   55219 en a_facturar ................ 333       333    ← intacto
--   resultado ...................................... 'ep_fantasma_limpiado'
--
-- Y se limpiaron los dos fantasma reales que quedaban, con el mismo criterio y sin tocar
-- stock (backup en zz_backups."GV_Backup_EP_fantasma_20260915"):
--   C69C (leg 104, 10/07) → queda 1 EP, 32 movimientos intactos
--   D30A (leg 122, 12/08) → queda 1 EP, 36 movimientos intactos
--
-- Rollback:
--   drop function public.gv_anular_picking_virgilio(text,text);
--   ... y en index.html volver la llamada a rpc/anular_picking_virgilio.
