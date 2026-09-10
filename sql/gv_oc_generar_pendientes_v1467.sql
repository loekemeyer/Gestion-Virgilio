-- v14.67 (2026-09-10) — Guarda anti-doble-generación de OCs (backend).
--
-- Problema: el generador (index.html `ocgGenerar`) hacía un POST crudo a Ordenes_Compra.
-- Si se corría dos veces el mismo día (doble click / dos supervisores / recarga), insertaba
-- TODAS las líneas de nuevo → cada artículo aparecía DOS veces en la OC (pedido duplicado,
-- el impreso al tallerista pedía el doble). Pasó el 2026-09-09: dos corridas (14:25 y 15:40),
-- 109 filas duplicadas en 15 proveedores. Backup + borrado en GV_Backup_OC_dup_20260909.
--
-- Fix: el front deja de hacer POST directo y llama a esta RPC. La RPC es IDEMPOTENTE por día:
-- para cada (fecha, proveedor, codigo) borra primero la línea pendiente SIN recepción que ya
-- exista ese día y recién ahí inserta la nueva → re-generar refresca las cantidades en vez de
-- duplicar. Las líneas que YA tienen recepción o están cerradas/recibidas NO se tocan ni se
-- re-insertan (no se pisa lo recibido, no se duplica sobre una recibida).
--
-- Match del código por norm_cod (misma normalización que oc_vigentes_por_proveedor / v14.60).
-- SECURITY DEFINER + grant SOLO a authenticated (generar OCs es acción de supervisor con sesión).
--
-- ROLLBACK: docs/ROLLBACK-PRODUCCION.md. Para volver al POST crudo, revertir el front y
--   `drop function public.gv_oc_generar_pendientes(jsonb);`

create or replace function public.gv_oc_generar_pendientes(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  r        jsonb;
  v_fecha  date;
  v_prov   text;
  v_cod    text;
  v_codn   text;
  n_ins    int := 0;
begin
  for r in select value from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    v_fecha := nullif(r->>'fecha','')::date;
    v_prov  := nullif(trim(r->>'proveedor'), '');
    v_cod   := nullif(trim(r->>'codigo'), '');
    v_codn  := norm_cod(coalesce(v_cod,''));

    -- sin proveedor / fecha / código no se genera (igual que el front, que ya los filtra)
    if v_fecha is null or v_prov is null or v_codn = '' then
      continue;
    end if;

    -- Si ya hay una línea de ese día+proveedor+código CON recepción o cerrada/recibida,
    -- no se toca ni se duplica: la regeneración salta ese artículo.
    if exists (
      select 1 from public."Ordenes_Compra" o
      where o.fecha = v_fecha
        and o.proveedor = v_prov
        and norm_cod(o.codigo) = v_codn
        and (coalesce(o.cantidad_recibida,0) > 0
             or lower(coalesce(o.estado,'')) in ('cerrada','anulada','recibida'))
    ) then
      continue;
    end if;

    -- Borra la línea pendiente SIN recepción de ese día (si existe) → evita el duplicado
    delete from public."Ordenes_Compra" o
    where o.fecha = v_fecha
      and o.proveedor = v_prov
      and norm_cod(o.codigo) = v_codn
      and coalesce(o.cantidad_recibida,0) = 0
      and lower(coalesce(o.estado,'')) not in ('cerrada','anulada','recibida');

    insert into public."Ordenes_Compra"
      (proveedor, fecha, rubro, codigo, descripcion, cantidad, cantidad_recibida,
       unidad, estado, oc_max, oc_pedidos, oc_stock, oc_proy, oc_uni_caja, oc_ncaja)
    values
      (v_prov, v_fecha, nullif(r->>'rubro',''), v_cod, nullif(r->>'descripcion',''),
       coalesce((r->>'cantidad')::numeric, 0)::int, 0,
       nullif(r->>'unidad',''), coalesce(nullif(r->>'estado',''),'pendiente'),
       nullif(r->>'oc_max','')::numeric, nullif(r->>'oc_pedidos','')::numeric,
       nullif(r->>'oc_stock','')::numeric, nullif(r->>'oc_proy','')::numeric,
       nullif(r->>'oc_uni_caja','')::numeric, nullif(r->>'oc_ncaja','')::int);

    n_ins := n_ins + 1;
  end loop;
  return n_ins;
end;
$function$;

revoke all on function public.gv_oc_generar_pendientes(jsonb) from public;
grant execute on function public.gv_oc_generar_pendientes(jsonb) to authenticated;
