-- v14.59 (2026-09-09) — Descontar la OC al recibir mercadería.
--
-- PROBLEMA: al recibir, el módulo escribía en "Entregas Tallerista Virgilio" /
-- "Entregas Prov AT" / Movimientos_Stock / Control_Modo_OP, pero NUNCA tocaba
-- "Ordenes_Compra".cantidad_recibida. La vista/RPC oc_vigentes_por_proveedor calcula
-- pend = cantidad - cantidad_recibida, así que las cantidades a recibir no bajaban nunca
-- (0 de 729 OCs con cantidad_recibida > 0) y la operadora las seguía imprimiendo.
--
-- SOLUCIÓN: gv_oc_aplicar_recepcion(nombre_ent, items) — la llama el front (recepcion.js)
-- después de una recepción exitosa (best-effort). Descuenta en CASCADA sobre las filas de
-- la fecha más nueva del proveedor+código (igual a como oc_vigentes_por_proveedor agrega lo
-- que ve el operario), llenando cada fila hasta su `cantidad` (nunca la pasa: si la pasara,
-- la fila se cae de la vista y el total queda mal) y marcando estado='recibida' la que se
-- completa. El EXCEDENTE real (lo recibido por encima de lo pedido) NO entra a la OC: se
-- avisa aparte al dueño (botón a Tomás), que decide si entra a góndola.
--
-- Match idéntico a oc_vigentes_por_proveedor: norm_nombre + alias (Pettofrezza→Rafael) +
-- split del proveedor por /,+,&," y "; norm_cod para el código.
--
-- SECURITY DEFINER (la recepción corre como anon/authenticated, que no tiene UPDATE directo
-- sobre Ordenes_Compra). Grant execute a anon, authenticated.
--
-- BACKUP previo: tabla public."GV_Backup_Ordenes_Compra_20260909" (729 filas, snapshot).
-- ROLLBACK: ver docs/ROLLBACK-PRODUCCION.md.

create or replace function public.gv_oc_aplicar_recepcion(nombre_ent text, items jsonb)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  clave_ent text;
  alias_map jsonb := '[{"de":"pettofrezza","a":"rafael"}]'::jsonb;
  it jsonb;
  r record;
  v_cod text;
  v_qty int;
  v_rem int;
  v_apl int;
  v_maxfecha date;
  n_updated int := 0;
begin
  clave_ent := norm_nombre(nombre_ent);
  for i in 0 .. jsonb_array_length(alias_map) - 1 loop
    if clave_ent like '%' || (alias_map->i->>'de') || '%' then
      clave_ent := alias_map->i->>'a'; exit;
    end if;
  end loop;
  if clave_ent = '' then return 0; end if;

  for it in select value from jsonb_array_elements(coalesce(items, '[]'::jsonb)) loop
    v_cod := norm_cod(it->>'cod');
    v_qty := round(coalesce((it->>'cajas')::numeric, 0))::int;
    if v_cod = '' or v_qty <= 0 then continue; end if;
    v_rem := v_qty;
    v_maxfecha := null;

    for r in
      select o.id, o.cantidad, coalesce(o.cantidad_recibida, 0) as rec, o.fecha
      from public."Ordenes_Compra" o
      where norm_cod(o.codigo) = v_cod
        and o.fecha >= (current_date - 120)
        and lower(coalesce(o.estado, '')) <> 'recibida'
        and (o.cantidad - coalesce(o.cantidad_recibida, 0)) > 0
        and (
          (case
             when (select bool_or(norm_nombre(o.proveedor) like '%' || (a->>'de') || '%')
                   from jsonb_array_elements(alias_map) a)
               then (select a->>'a' from jsonb_array_elements(alias_map) a
                     where norm_nombre(o.proveedor) like '%' || (a->>'de') || '%' limit 1)
             else norm_nombre(o.proveedor)
           end) = clave_ent
          or exists (
            select 1
            from unnest(string_to_array(
                   regexp_replace(
                     regexp_replace(trim(coalesce(o.proveedor, '')), '\s+y\s+', '/', 'gi'),
                     '[,+&]', '/', 'g'),
                   '/')) as raw_parte
            cross join lateral (
              select case
                when (select bool_or(norm_nombre(raw_parte) like '%' || (a->>'de') || '%')
                      from jsonb_array_elements(alias_map) a)
                  then (select a->>'a' from jsonb_array_elements(alias_map) a
                        where norm_nombre(raw_parte) like '%' || (a->>'de') || '%' limit 1)
                else norm_nombre(raw_parte)
              end as parte_norm
            ) pn
            where parte_norm = clave_ent
               or (length(parte_norm) >= length(clave_ent)
                   and length(parte_norm) - length(clave_ent) <= 2
                   and starts_with(parte_norm, clave_ent))
               or (length(clave_ent) >= length(parte_norm)
                   and length(clave_ent) - length(parte_norm) <= 2
                   and starts_with(clave_ent, parte_norm))
          )
        )
      order by o.fecha desc, o.id desc
    loop
      if v_maxfecha is null then v_maxfecha := r.fecha; end if;
      exit when r.fecha < v_maxfecha;   -- solo la fecha más nueva (lo que ve el operario)
      exit when v_rem <= 0;
      v_apl := least(v_rem, r.cantidad - r.rec);
      if v_apl <= 0 then continue; end if;
      update public."Ordenes_Compra"
        set cantidad_recibida = r.rec + v_apl,
            estado = case when r.rec + v_apl >= r.cantidad then 'recibida' else estado end,
            fecha_entrega_real = coalesce(fecha_entrega_real, current_date)
      where id = r.id;
      v_rem := v_rem - v_apl;
      n_updated := n_updated + 1;
    end loop;
  end loop;
  return n_updated;
end;
$function$;

revoke all on function public.gv_oc_aplicar_recepcion(text, jsonb) from public;
grant execute on function public.gv_oc_aplicar_recepcion(text, jsonb) to anon, authenticated;
