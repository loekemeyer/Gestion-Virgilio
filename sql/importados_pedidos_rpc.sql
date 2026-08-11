-- ============================================================
-- v9.29 — Pedidos Importación: editar "en curso" + marcar llegada
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- El módulo "📦 Pedidos Importación" (panel supervisor) era SOLO LECTURA: calculaba
-- cuánto hay que pedir a los proveedores chinos con el motor v_importados_ordenes.
-- Ahora es operable:
--
--   (1) EDITAR EN CURSO — cuántas unidades ya están pedidas / en camino. Se guarda
--       en Importados.pedido_curso (el motor lo resta de "a pedir"). anon ya podía
--       UPDATE (policy imp_upd_anon), pero se hace por RPC para validar (>=0) y dejar
--       una sola vía controlada.
--
--   (2) MARCAR LLEGADA — el pedido llegó: esas unidades pasan a ser stock real. Se
--       inserta un movimiento en Importados_Mov_Stock (tipo='ingreso', +delta_uni) y
--       se descuenta esa cantidad de pedido_curso (piso 0). El INSERT en
--       Importados_Mov_Stock es solo-authenticated para anon, por eso va por función
--       SECURITY DEFINER (patrón append-only del resto del stock).
--
-- Se apunta por Importados.id (cod_art+marca es único entre los 150 principal+activos;
-- solo 2 códigos tienen >1 marca, y el front los maneja por fila).
-- ============================================================

-- (1) editar unidades en curso
create or replace function public.importados_set_curso(p_id bigint, p_uni numeric)
 returns numeric
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v numeric;
begin
  if p_id is null then raise exception 'id requerido'; end if;
  v := greatest(0, round(coalesce(p_uni, 0)));
  update public."Importados" set pedido_curso = v where id = p_id;
  if not found then raise exception 'Importado % no existe', p_id; end if;
  return v;
end
$function$;

-- (2) marcar llegada: +stock y -en curso
create or replace function public.importados_marcar_llegada(p_id bigint, p_uni numeric, p_legajo text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; llego numeric; nuevo_curso numeric;
begin
  if p_id is null then raise exception 'id requerido'; end if;
  llego := round(coalesce(p_uni, 0));
  if llego <= 0 then raise exception 'unidades llegadas debe ser > 0'; end if;
  select id, cod_art, marca, coalesce(pedido_curso, 0) as curso
    into r from public."Importados" where id = p_id;
  if not found then raise exception 'Importado % no existe', p_id; end if;
  insert into public."Importados_Mov_Stock" (ts, cod_art, marca, tipo, delta_uni, ref, legajo, creado)
    values (now(), r.cod_art, r.marca, 'ingreso', llego, 'llegada pedido importacion',
            nullif(btrim(coalesce(p_legajo, '')), ''), now());
  nuevo_curso := greatest(0, r.curso - llego);
  update public."Importados" set pedido_curso = nuevo_curso where id = p_id;
  return jsonb_build_object('cod', r.cod_art, 'marca', r.marca, 'llego', llego, 'nuevo_curso', nuevo_curso);
end
$function$;

revoke execute on function public.importados_set_curso(bigint, numeric) from public;
revoke execute on function public.importados_marcar_llegada(bigint, numeric, text) from public;
grant execute on function public.importados_set_curso(bigint, numeric) to anon, authenticated;
grant execute on function public.importados_marcar_llegada(bigint, numeric, text) to anon, authenticated;
