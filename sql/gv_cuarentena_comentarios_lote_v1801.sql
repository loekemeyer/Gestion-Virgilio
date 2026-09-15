-- v18.01 — Cuarentena · cuántos comentarios tiene cada pedido RETENIDO (Luis, 2026-09-15:
-- "agregales la opción de poner comentarios").
--
-- La tabla de "Ya programados y el cliente está en cuarentena" ya muestra el 📖 con el contador:
-- se lo calcula `gv_cuarentena_ya_programado()` fila por fila. Los pedidos que TODAVÍA no tienen
-- tanda no pasan por esa función (los marca `gv_cuarentena_marcar`, que no sabe de comentarios),
-- así que la lista de Cuarentena no tenía de dónde sacar el número. Esto lo trae en UNA vuelta de
-- red para toda la lista, en vez de una llamada por pedido.
--
-- La clave es la misma de siempre: (empresa, order_id) NORMALIZADO con `gv_cuarentena_clave` —
-- el mismo pedido de ISIS se llama `np98587` en A Programar y `98587` en el log.
--
-- ROLLBACK: `drop function public.gv_cuarentena_comentarios_lote(jsonb);` — sólo se apaga el
-- contador del librito, el log y los comentarios siguen igual.

create or replace function public.gv_cuarentena_comentarios_lote(p_pedidos jsonb)
 returns table(empresa text, clave text, n integer)
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select p.empresa, p.clave,
         (select count(*)::int from public."GV_Cuarentena_Comentarios" c
           where c.empresa = p.empresa
             and public.gv_cuarentena_clave(c.order_id) = public.gv_cuarentena_clave(p.clave))
    from (select distinct lower(coalesce(e->>'empresa','lk')) as empresa,
                 nullif(btrim(e->>'clave'), '')               as clave
            from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e) p
   where p.clave is not null
     and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio());
$function$;

revoke all on function public.gv_cuarentena_comentarios_lote(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_comentarios_lote(jsonb) to authenticated, service_role;
