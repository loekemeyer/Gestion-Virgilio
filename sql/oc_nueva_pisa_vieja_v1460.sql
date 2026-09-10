-- v14.60 (2026-09-09) — "La nueva pisa la vieja".
--
-- Regla del dueño: para un mismo proveedor+código, la OC de fecha MÁS NUEVA es la única viva.
-- Las más viejas quedan muertas y NO deben reaparecer (ni en la pantalla del operario ni al
-- recibir). Antes, al completar la OC nueva, la vista caía a mostrar una OC vieja pendiente.
--
-- Toca DOS funciones para que ambas usen el mismo criterio ("fecha más nueva manda"):
--
-- (1) oc_vigentes_por_proveedor (lo que ve el operario): max_fecha se calcula sobre las OCs
--     NO cerradas/anuladas, INCLUYENDO las 'recibida' (para que una OC nueva ya recibida tape
--     a las viejas). Se sacó el filtro por fila (cantidad-recibida)>0 y la exclusión de
--     'recibida' del pre-filtro. El HAVING sum(pend)>0 hace que un código con la OC nueva
--     completa deje de figurar; las viejas nunca están en max_fecha → no reaparecen.
--     (Sub-efecto: una OC 'cerrada' ya no figura como vigente, cosa que antes sí pasaba.)
--
-- (2) gv_oc_aplicar_recepcion (descuento al recibir): fija max_fecha igual que la vista
--     (incluyendo 'recibida') y aplica SOLO a esa fecha. Si la OC nueva ya no tiene lugar, lo
--     recibido es EXCEDENTE (va al aviso a Tomás), nunca descuenta una OC vieja.
--
-- Match idéntico en las dos: norm_nombre + alias (Pettofrezza→Rafael) + split del proveedor
-- por /,+,&," y "; norm_cod para el código.
--
-- BACKUP de datos previo: public."GV_Backup_Ordenes_Compra_20260909" (729 filas).
-- ROLLBACK (incluida la definición vieja de oc_vigentes_por_proveedor): docs/ROLLBACK-PRODUCCION.md.

create or replace function public.oc_vigentes_por_proveedor(nombre_ent text)
 returns TABLE(cod text, fecha date, ped bigint, rec bigint, pend bigint)
 language plpgsql
 stable
as $function$
DECLARE
  clave_ent text;
  alias_map jsonb := '[{"de":"pettofrezza","a":"rafael"}]'::jsonb;
BEGIN
  clave_ent := norm_nombre(nombre_ent);
  FOR i IN 0 .. jsonb_array_length(alias_map) - 1 LOOP
    IF clave_ent LIKE '%' || (alias_map->i->>'de') || '%' THEN
      clave_ent := alias_map->i->>'a'; EXIT;
    END IF;
  END LOOP;
  IF clave_ent = '' THEN RETURN; END IF;

  RETURN QUERY
  WITH oc_filtrada AS (
    SELECT norm_cod(o.codigo) AS cod_n, o.cantidad, o.cantidad_recibida,
           o.fecha AS oc_fecha, o.proveedor
    FROM "Ordenes_Compra" o
    WHERE o.fecha >= (current_date - 120)
      AND lower(coalesce(o.estado, '')) NOT IN ('cerrada','anulada')
      AND nullif(trim(o.codigo), '') IS NOT NULL
  ),
  oc_match AS (
    SELECT f.*
    FROM oc_filtrada f
    WHERE (
      (SELECT
        CASE
          WHEN (SELECT bool_or(nn LIKE '%' || (a->>'de') || '%')
                FROM jsonb_array_elements(alias_map) a)
          THEN (SELECT a->>'a' FROM jsonb_array_elements(alias_map) a
                WHERE nn LIKE '%' || (a->>'de') || '%' LIMIT 1)
          ELSE nn
        END
       FROM (SELECT norm_nombre(f.proveedor) AS nn) x
      ) = clave_ent
    )
    OR EXISTS (
      SELECT 1
      FROM unnest(
        string_to_array(
          regexp_replace(
            regexp_replace(trim(coalesce(f.proveedor, '')), '\s+y\s+', '/', 'gi'),
            '[,+&]', '/', 'g'
          ), '/'
        )
      ) AS raw_parte
      CROSS JOIN LATERAL (
        SELECT
          CASE
            WHEN (SELECT bool_or(norm_nombre(raw_parte) LIKE '%' || (a->>'de') || '%')
                  FROM jsonb_array_elements(alias_map) a)
            THEN (SELECT a->>'a' FROM jsonb_array_elements(alias_map) a
                  WHERE norm_nombre(raw_parte) LIKE '%' || (a->>'de') || '%' LIMIT 1)
            ELSE norm_nombre(raw_parte)
          END AS parte_norm
      ) pn
      WHERE (
        parte_norm = clave_ent
        OR (length(parte_norm) >= length(clave_ent)
            AND length(parte_norm) - length(clave_ent) <= 2
            AND starts_with(parte_norm, clave_ent))
        OR (length(clave_ent) >= length(parte_norm)
            AND length(clave_ent) - length(parte_norm) <= 2
            AND starts_with(clave_ent, parte_norm))
      )
    )
  ),
  max_fecha AS (
    SELECT cod_n, max(oc_fecha) AS mf
    FROM oc_match
    WHERE cod_n != ''
    GROUP BY cod_n
  )
  SELECT m.cod_n AS cod,
         m.mf AS fecha,
         sum(o.cantidad)::bigint AS ped,
         sum(coalesce(o.cantidad_recibida, 0))::bigint AS rec,
         (sum(o.cantidad) - sum(coalesce(o.cantidad_recibida, 0)))::bigint AS pend
  FROM max_fecha m
  JOIN oc_match o ON o.cod_n = m.cod_n AND o.oc_fecha = m.mf
  GROUP BY m.cod_n, m.mf
  HAVING sum(o.cantidad) - sum(coalesce(o.cantidad_recibida, 0)) > 0;
END;
$function$;

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
        and lower(coalesce(o.estado, '')) not in ('cerrada','anulada')
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
      exit when r.fecha < v_maxfecha;   -- SOLO la OC de fecha más nueva; las viejas no se tocan
      exit when v_rem <= 0;
      v_apl := least(v_rem, r.cantidad - r.rec);
      if v_apl <= 0 then continue; end if;   -- fila ya completa (o recibida): no toca, sigue
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
