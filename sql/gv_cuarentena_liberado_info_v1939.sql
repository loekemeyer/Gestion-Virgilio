-- v19.39 (Luis, 2026-09-17) — el badge "🚪 Liberado de cuarentena" de A Programar pasa a ser
-- clickeable y abre el log del pedido en SOLO LECTURA: por qué se liberó y quién lo hizo.
--
-- Lo que faltaba era el "quién / cuándo": gv_cuarentena_comentarios ya traía el hilo, pero la
-- aprobación en sí vive en GV_Cuarentena_Liberados (persona, liberado_por, liberado_at) y
-- gv_cuarentena_liberados() —la que usa la pantalla al cargar— sólo devuelve (empresa, order_id,
-- motivos). NO se la toca: cambiarle el RETURNS TABLE obliga a DROP + CREATE y la llaman dos
-- lugares del front. Esta función es nueva, aditiva, y se llama de a UN pedido, sólo al abrir el
-- pop-up (no suma peso a la carga de A Programar).
--
-- La clave se compara NORMALIZADA (gv_cuarentena_clave), por lo mismo que documenta
-- gv_cuarentena_comentarios: el mismo pedido de ISIS es `np98587` en A Programar y `98587` en el
-- log. Sin eso, el pop-up de una NP de ISIS salía sin datos de liberación.

create or replace function public.gv_cuarentena_liberado_info(
  p_empresa  text,
  p_order_id text
) returns table (
  empresa      text,
  order_id     text,
  motivos      text[],
  persona      text,
  liberado_por text,
  liberado_at  timestamptz
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select l.empresa, l.order_id, l.motivos, l.persona, l.liberado_por, l.liberado_at
    from public."GV_Cuarentena_Liberados" l
   where l.empresa = lower(p_empresa)
     and public.gv_cuarentena_clave(l.order_id)
       = public.gv_cuarentena_clave(nullif(btrim(p_order_id), ''))
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
   order by l.liberado_at desc nulls last
   limit 1;
$$;

revoke execute on function public.gv_cuarentena_liberado_info(text, text) from public, anon;
grant  execute on function public.gv_cuarentena_liberado_info(text, text) to authenticated, service_role;

-- ROLLBACK
-- drop function if exists public.gv_cuarentena_liberado_info(text, text);
