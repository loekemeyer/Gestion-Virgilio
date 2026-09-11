-- ============================================================================
-- BACKUP 2026-09-11 — dos cambios pedidos por el dueño en Cuarentena (v14.94)
--   (1) Pérez Zárate S.R.L. (lk 4036, pedido 1380, NP 56) sacado de Programación
--       (tanda E12D, entrega 17/09). Se programó el 09/09 18:00, ANTES de que
--       existiera el dato de deuda (cargado 10/09 17:27). Deuda: $291.923,09.
--       Mecanismo: el mismo del resync (`ppp_web_resync`) — se borra SÓLO la fila
--       de PPP_Web_Programacion, con guarda "tanda sin arrancar" (E12D: 0 eventos
--       EP/TP/AP/TAP/CC). La NP 56 (PPP_Web_NP) y los 14 ítems (PPP_Web_Base,
--       np_label 'LK 0056') se DEJAN: se reusan al reprogramar. PPP_Web_Tanda_Items: 0 filas.
--   (2) gv_cuarentena_marcar: los SÚPER quedan exentos de la regla de deuda
--       (dueño: "Coto es súper. Los súper no se analiza si tiene o no tiene deuda").
--
-- Para rollback: correr la sección que corresponda.
-- ============================================================================


-- ─────────────── (1) ROLLBACK: volver a programar a Pérez Zárate en E12D ───────────────
-- Estado exacto de la fila borrada (to_jsonb antes del delete):
insert into public."PPP_Web_Programacion"
select * from jsonb_populate_record(null::public."PPP_Web_Programacion", $j$
{"m3":0.126,"np":56,"op":null,"zona":"Zona 1 - CABA Sur","cajas":29,"tanda":"E12D","barrio":"Soldati",
 "lineas":14,"np_idx":1,"empresa":"lk","np_total":null,"order_id":1380,
 "creado_at":"2026-09-09T18:00:15.141738-03:00","direccion":"Alem 385-Cordoba","prioridad":0,
 "creado_por":"sistema","m3_parcial":false,"agregado_en":null,"cod_cliente":"4036","es_agregado":false,
 "fecha_recep":null,"razon_social":"Perez Zarate S.R.L.","agregado_a_np":null,
 "fecha_entrega":"2026-09-17","observaciones":null,"actualizado_at":"2026-09-09T18:00:15.141738-03:00"}
$j$::jsonb)
on conflict do nothing;

-- Referencia (NO se borraron, siguen en la base):
--   PPP_Web_NP: {"np":56,"np_idx":1,"empresa":"lk","order_id":1380,"creado_at":"2026-09-09T18:00:14.883748-03:00"}
--   PPP_Web_Base (14 filas, np_label 'LK 0056', creado 2026-09-09T18:00:17): artículos y cajas =
--     026x1, 027x1, 031x1, 034x2, 502x3, 505x8, 513x2, 520x1, 521x1, 523x1, 550x3, 574Ex2, 581x2, 587x1


-- ─────────────── (2) ROLLBACK: gv_cuarentena_marcar SIN la exención de súper ───────────────
-- Definición previa (pg_get_functiondef, 2026-09-11 antes de v14.94):
CREATE OR REPLACE FUNCTION public.gv_cuarentena_marcar(p_pedidos jsonb)
 RETURNS TABLE(order_id text, empresa text, motivos text[])
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'), '') as cod
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  marca as (
    select p.order_id, p.empresa,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'busqueda'
            and f.cod = p.cod and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'deuda'
            and f.cod = p.cod and coalesce(f.deuda,0) > 1000 limit 1)
      ], null) as motivos
    from ped p
    where p.cod is not null and p.order_id is not null
  )
  select m.order_id, m.empresa, m.motivos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and lb.order_id = m.order_id);
$function$;
