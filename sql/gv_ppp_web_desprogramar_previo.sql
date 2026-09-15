-- ═══════════════════════════════════════════════════════════════════════════════════════
-- "ENVIAR A PROGRAMAR" — EL CÁLCULO DE QUÉ SE LLEVA POR DELANTE, ANTES DE APRETAR
-- Pedido de Luis, 2026-09-15
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- El botón ↩ de la tabla de Programación ya sacaba TODAS las NP del pedido —
-- `gv_ppp_web_desprogramar` resuelve el `order_id` y saca todas las que tengan tanda, de
-- cualquier tanda y cualquier fecha— pero el front **avisaba después**: el `confirm` hablaba
-- de una sola NP y recién el cartel del final decía "(3 NP del pedido)". Luis, textual:
--
--   · *"debería preguntar si se quieren enviar todas las NPs correspondientes a ese pedido"*
--   · *"cuando están «en proceso», «armado» o «facturado», avisar que se envían todas las NPs
--      juntas"*
--   · *"siempre que se quiera mandar una tanda deberían mandarse todas las tandas de ese
--      pedido a programar, me parece ahora que lo pienso"* ← ésta manda: van SIEMPRE todas.
--   · *"si alguna tanda fuera a quedar vacía por estos movimientos, debería desaparecer de
--      Programación"*
--
-- Esta función es el PREVIO: no escribe nada, sólo dice qué va a pasar para que el pop-up lo
-- muestre. El cálculo va al backend por el protocolo de siempre (es regla de negocio, no
-- pintura), y así el front no tiene que replicar cómo se resuelve el estado de una NP.
--
-- Devuelve un jsonb:
--   { es_isis, empresa, order_id, cod, cliente,
--     nps: [ {np_label, tanda, fecha_entrega, m3, estado, tocada} ],
--     n, hay_avanzada, estados_avanzados: [],
--     tandas_vacias: [],              -- las que quedan sin una sola NP → salen de Programación
--     bloqueo: null | '<motivo>' }    -- ya salió (Carga Camión / Recepción Remitos)
--
-- `bloqueo` repite la única guarda que tiene `gv_ppp_web_desprogramar`, para poder avisarlo
-- en el pop-up en vez de dejar que reviente al apretar.
-- ═══════════════════════════════════════════════════════════════════════════════════════

create or replace function public.gv_ppp_web_desprogramar_previo(p_np text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_np    text := btrim(coalesce(p_np, ''));
  v_isis  boolean;
  v_emp   text;
  v_num   int;
  v_oid   bigint;
  v_nps   jsonb := '[]'::jsonb;
  v_cod   text;
  v_cli   text;
  v_bloq  text;
  v_vac   jsonb := '[]'::jsonb;
  v_av    jsonb := '[]'::jsonb;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede ver esto.' using errcode = '42501';
  end if;
  if v_np = '' then raise exception 'Falta la NP.'; end if;

  v_isis := v_np !~* '^(LK|CH)\s*\d+';

  if v_isis then
    -- Una NP de ISIS no tiene hermanas: no hay pedido de la página que la agrupe.
    v_np := regexp_replace(v_np, '\.0+$', '');
    select jsonb_agg(jsonb_build_object(
             'np_label', v_np, 'tanda', nullif(btrim(i.tanda), ''),
             'fecha_entrega', left(btrim(i.fecha_entrega::text), 10),
             'm3', i.m3, 'estado', 'isis', 'tocada', true)),
           max(btrim(i.cod)), max(i.razon_social)
      into v_nps, v_cod, v_cli
      from public.gv_ppp_programacion_diaria i
     where regexp_replace(btrim(i.np), '\.0+$', '') = v_np;
    v_nps := coalesce(v_nps, '[]'::jsonb);
  else
    v_emp := case when upper(left(v_np, 2)) = 'CH' then 'chef' else 'lk' end;
    v_num := (regexp_match(v_np, '(\d+)'))[1]::int;
    select n.order_id into v_oid
      from public."PPP_Web_NP" n where n.empresa = v_emp and n.np = v_num limit 1;
    if v_oid is null then raise exception 'No encuentro el pedido web de %.', v_np; end if;

    -- TODAS las NP del pedido que hoy tienen tanda: son las que se van a mover.
    select jsonb_agg(jsonb_build_object(
             'np_label', e.np_label, 'tanda', e.tanda, 'fecha_entrega', e.fecha_entrega,
             'm3', e.m3, 'estado', e.estado,
             'tocada', upper(replace(e.np_label, ' ', '')) = upper(replace(v_np, ' ', '')))
             order by e.np),
           max(e.cod_cliente), max(e.razon_social)
      into v_nps, v_cod, v_cli
      from public.gv_ppp_web_estado e
     where e.empresa = v_emp and e.order_id = v_oid
       and coalesce(nullif(btrim(e.tanda), ''), '') <> '';
    v_nps := coalesce(v_nps, '[]'::jsonb);

    -- La misma guarda que tiene gv_ppp_web_desprogramar: lo que ya salió no se saca.
    select string_agg(distinct upper(btrim(split_part(r.texto, '|', 1))), ', ')
      into v_bloq
      from public."Registros_Produccion_Virgilio" r
      join public."PPP_Web_Programacion" w
        on w.empresa = v_emp and w.order_id = v_oid
       and upper(btrim(split_part(r.texto, '|', 1)))
           = upper(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))
     where r.opcion in ('CCN', 'CRN') and not public.es_legajo_test(r.legajo);
  end if;

  -- Estados "más que pendiente" que se van a mover (para el aviso fuerte del pop-up).
  select coalesce(jsonb_agg(distinct x->>'estado'), '[]'::jsonb) into v_av
    from jsonb_array_elements(v_nps) x
   where coalesce(x->>'estado', '') not in ('programado', 'sin_programar');

  -- ¿Alguna tanda queda SIN UNA SOLA NP? Se cuenta lo que hay hoy en esa tanda (web + el
  -- espejo de ISIS: una tanda puede tener las dos cosas) y se le resta lo que se lleva esto.
  with van as (
    select distinct nullif(btrim(x->>'tanda'), '') t from jsonb_array_elements(v_nps) x
  ), total as (
    select v.t,
           (select count(*) from public."PPP_Web_Programacion" w
             where upper(btrim(coalesce(w.tanda, ''))) = upper(v.t))
         + (select count(*) from public.gv_ppp_programacion_diaria i
             where upper(btrim(coalesce(i.tanda, ''))) = upper(v.t)) as n_total,
           (select count(*) from jsonb_array_elements(v_nps) x
             where upper(btrim(coalesce(x->>'tanda', ''))) = upper(v.t)) as n_van
      from van v where v.t is not null
  )
  select coalesce(jsonb_agg(t order by t), '[]'::jsonb) into v_vac
    from total where n_total - n_van <= 0;

  return jsonb_build_object(
    'es_isis', v_isis, 'empresa', v_emp, 'order_id', v_oid,
    'cod', v_cod, 'cliente', v_cli,
    'nps', v_nps, 'n', jsonb_array_length(v_nps),
    'hay_avanzada', jsonb_array_length(v_av) > 0,
    'estados_avanzados', v_av,
    'tandas_vacias', v_vac,
    'bloqueo', v_bloq);
end
$function$;

revoke all on function public.gv_ppp_web_desprogramar_previo(text) from public, anon;
grant execute on function public.gv_ppp_web_desprogramar_previo(text) to authenticated, service_role;

-- ═══ PRUEBAS ═══════════════════════════════════════════════════════════════════════════
-- select jsonb_pretty(public.gv_ppp_web_desprogramar_previo('LK 0094'));
-- select jsonb_pretty(public.gv_ppp_web_desprogramar_previo('98704'));
-- ═══ ROLLBACK ══════════════════════════════════════════════════════════════════════════
-- drop function public.gv_ppp_web_desprogramar_previo(text);
