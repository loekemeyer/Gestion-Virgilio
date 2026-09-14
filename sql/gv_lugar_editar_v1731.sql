/* gv_lugar_item_guardar / gv_lugar_item_sacar / gv_lugar_orden — v17.31
   (pedido de Thomas, 2026-09-14: "que se pueda en el nuevo módulo de Mapa de góndolas
   editar los lugares, artículos, etc y que tenga efecto en la data en el backend")

   UNA sola puerta de escritura para la planimetría de góndola. Antes había tres, y las
   tres escribían distinto:

     · Editor de Planimetría → tabla "Planimetria"      ← el picking dejó de leerla en la
       v15.77, así que lo cargado ahí NO tenía efecto. Sus funciones de escritura se
       borraron en la v17.26 (problema 85) y la pantalla se retira en esta versión.
     · 📍 Lugares del depósito → POST/DELETE a GV_Lugar_Item, sin tocar Capacidad_Sector.
     · Importador de capacidad  → Capacidad_Sector, sin tocar GV_Lugar_Item.

   Las dos últimas son la fábrica de las divergencias del problema 84: sacar un código de
   un lugar lo borraba del mapa y le dejaba la capacidad colgada (`solo_capacidad`), y
   cargarlo con cajas lo ponía en el mapa sin capacidad (`solo_mapa`).

   ⚠ Por qué se escriben LAS DOS tablas y no sólo GV_Lugar_Item: `Capacidad_Sector` sigue
   siendo la que leen el generador de OC (`vista_generador_oc`, `capMap`), el aviso de
   "no entra en góndola" de recepción (`gondola_return_check`), el conteo cíclico y
   `aceptar_conteo`. Mientras esos cinco no se muden a `gv_planimetria_celda`, escribir
   sólo el mapa dejaría al generador comprando contra una capacidad vieja. El espejo es
   exacto: mismo (sector, cod), mismo número, y si el código se saca del lugar, se saca de
   las dos. El día que migren, se borra el bloque del espejo y nada más.

   SECURITY INVOKER a propósito: las policies `gv_lugar_item_write` y `cap_write` ya dan
   ALL a `authenticated`, así que la RPC no amplía permisos — sólo ordena la escritura.
   `anon` no puede ejecutarlas. */

create or replace function public.gv_lugar_item_guardar(
  p_sector    text,
  p_cod       text,
  p_clase     text default 'articulo',
  p_cajas_max numeric default null
) returns table (sector text, cod text, clase text, cajas_max numeric, empresa text)
language plpgsql
as $$
-- las columnas de salida se llaman igual que las de la tabla (sector, cod, clase…):
-- sin esto, el `insert ... (sector, cod, ...)` no sabe si es la columna o el parámetro.
#variable_conflict use_column
declare
  v_key text := upper(btrim(coalesce(p_sector, '')));
  v_sec text;
  v_emp text;
  v_cod text := public.canon_cod_art_val(p_cod);   -- 66 → 066, misma grafía que el maestro
begin
  if v_key = '' then raise exception 'Falta el lugar.'; end if;
  if coalesce(btrim(v_cod), '') = '' then raise exception 'Falta el código.'; end if;
  if coalesce(p_clase, '') not in ('articulo', 'insumo') then
    raise exception 'Clase inválida: % (va articulo o insumo)', p_clase;
  end if;
  if p_cajas_max is not null and p_cajas_max < 0 then
    raise exception 'La capacidad no puede ser negativa (%).', p_cajas_max;
  end if;

  select l.sector, l.empresa into v_sec, v_emp
    from public."GV_Lugar" l where upper(btrim(l.sector)) = v_key;
  if v_sec is null then
    raise exception 'El lugar % no existe. Los lugares se dan de alta en GV_Lugar.', p_sector;
  end if;

  insert into public."GV_Lugar_Item" (sector, cod, clase, cajas_max, activo, created_at, updated_at)
  values (v_sec, v_cod, p_clase, p_cajas_max, true, now(), now())
  on conflict (sector, cod, clase) do update
    set cajas_max = excluded.cajas_max, activo = true, updated_at = now();

  -- espejo (ver el encabezado)
  insert into public."Capacidad_Sector" (sector, cod, cajas_max, empresa)
  values (v_sec, v_cod, p_cajas_max, v_emp)
  on conflict (sector, cod) do update
    set cajas_max = excluded.cajas_max,
        empresa   = coalesce(excluded.empresa, public."Capacidad_Sector".empresa);

  return query select v_sec, v_cod, p_clase, p_cajas_max, v_emp;
end $$;

create or replace function public.gv_lugar_item_sacar(
  p_sector text,
  p_cod    text,
  p_clase  text default 'articulo'
) returns table (sacados_mapa int, sacados_capacidad int)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_key text := upper(btrim(coalesce(p_sector, '')));
  v_cod text := public.canon_cod_art_val(p_cod);
  v_m int := 0;
  v_c int := 0;
begin
  if v_key = '' or coalesce(btrim(v_cod), '') = '' then
    raise exception 'Falta el lugar o el código.';
  end if;

  -- se borra por el código tal cual está guardado Y por su forma canónica: en el mapa
  -- conviven las dos grafías (066 y 66) desde antes del canon.
  delete from public."GV_Lugar_Item"
   where upper(btrim(sector)) = v_key
     and public.gv_cod_stock(cod) = public.gv_cod_stock(v_cod)
     and clase = coalesce(p_clase, 'articulo');
  get diagnostics v_m = row_count;

  delete from public."Capacidad_Sector"
   where upper(btrim(sector)) = v_key
     and public.gv_cod_stock(cod) = public.gv_cod_stock(v_cod);
  get diagnostics v_c = row_count;

  return query select v_m, v_c;
end $$;

/* El orden del RECORRIDO del lugar (por dónde pasa primero el pickeador). Vive en
   GV_Lugar y hasta ahora no se podía tocar desde la app: el único editor que dejaba
   escribir un `orden` era el de la tabla "Planimetria", que ya nadie lee. */
create or replace function public.gv_lugar_orden(
  p_sector text,
  p_orden  int
) returns table (sector text, orden int)
language plpgsql
as $$
#variable_conflict use_column
declare v_key text := upper(btrim(coalesce(p_sector, '')));
begin
  if p_orden is not null and p_orden < 0 then
    raise exception 'El orden no puede ser negativo (%).', p_orden;
  end if;
  update public."GV_Lugar" l set orden = p_orden, updated_at = now()
   where upper(btrim(l.sector)) = v_key;
  if not found then raise exception 'El lugar % no existe.', p_sector; end if;
  return query select l.sector, l.orden from public."GV_Lugar" l where upper(btrim(l.sector)) = v_key;
end $$;

revoke all on function public.gv_lugar_item_guardar(text, text, text, numeric) from public, anon;
revoke all on function public.gv_lugar_item_sacar(text, text, text)            from public, anon;
revoke all on function public.gv_lugar_orden(text, int)                        from public, anon;
grant execute on function public.gv_lugar_item_guardar(text, text, text, numeric) to authenticated;
grant execute on function public.gv_lugar_item_sacar(text, text, text)            to authenticated;
grant execute on function public.gv_lugar_orden(text, int)                        to authenticated;

notify pgrst, 'reload schema';
