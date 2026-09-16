-- v18.72 (2026-09-16) — el armado anulado tampoco revive, y ahora SÍ suelta el lock nuevo.
--
-- Mismo arreglo que el picking en la v18.71, más un bug propio que había quedado de la v18.65.
--
-- ############################################################################################
-- 1. No se BORRA el evento: AP -> APX
-- ############################################################################################
-- `Registros_Produccion_Virgilio` tiene un UNIQUE sobre `client_id` y el front postea con
-- `Prefer: resolution=ignore-duplicates`. Ese unique es lo que impide que un reenvío de la cola
-- offline del celular duplique el evento — pero sólo mientras la fila exista. Al borrarla, su
-- client_id queda libre, no hay contra qué chocar, y el reenvío entra como evento nuevo: el
-- armado anulado REVIVE. Es exactamente lo que pasó con E25A el 15/09 (borrado 16:56,
-- reinsertado 17:17 por el celular de JC al fichar FJ).
--
-- Con `APX` la fila conserva su client_id, el reenvío se descarta, y ningún consumidor la
-- cuenta: todos filtran `opcion = 'AP'` por igualdad exacta.
--
-- ############################################################################################
-- 2. ⚠ Y soltaba el lock EQUIVOCADO — bug introducido por mí en la v18.65
-- ############################################################################################
-- La función llamaba a `tanda_liberar`, que borra de la tabla VIEJA `Tandas_Lock`. Desde que
-- el lock por etapas vive en `GV_Tandas_Lock` (v18.65), anular un armado **no lo soltaba**: la
-- tanda quedaba `tomada` para siempre y nadie más podía agarrarla.
--
-- El front ya llamaba aparte a `gv_tanda_lock_anular`, así que en el camino feliz no se notaba.
-- Pero si esa llamada no llegaba —sin red, la pestaña cerrada, el operario que sale de la app
-- justo ahí— el lock quedaba colgado sin forma de soltarlo, porque ya no hay TTL que lo limpie.
-- Ahora la RPC suelta los dos: el nuevo y el viejo.

create or replace function public.anular_armado_virgilio(p_legajo text, p_tanda text, p_motivo text default null)
returns text language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ts timestamptz; v_leg text; v_tanda text; v_tal int; v_ent int; v_etl int; v_nota text;
begin
  v_leg   := btrim(coalesce(p_legajo, ''));
  v_tanda := upper(btrim(coalesce(p_tanda, '')));
  if v_leg = '' or v_tanda = '' then return 'faltan_datos'; end if;

  select id, created_at into v_id, v_ts
    from public."Registros_Produccion_Virgilio"
   where opcion = 'AP' and legajo = v_leg
     and upper(btrim(coalesce(texto, ''))) = v_tanda
     and created_at > now() - interval '72 hours'
   order by created_at desc limit 1;
  if v_id is null then return 'sin_ap'; end if;

  if exists (select 1 from public."Registros_Produccion_Virgilio"
              where opcion = 'TAP' and upper(btrim(coalesce(texto, ''))) = v_tanda
                and created_at >= v_ts) then
    return 'ya_cerrado';
  end if;

  -- El asistente no escribe nada mientras se arma: líos (TAL), Entregas y TAP salen todos
  -- juntos al tocar «Terminar». Esto es para el caso raro en que «Terminar» grabó a medias.
  select count(*) into v_tal from public."Registros_Produccion_Virgilio"
   where opcion = 'TAL' and upper(split_part(btrim(coalesce(texto,'')), '|', 3)) = v_tanda
     and created_at >= v_ts;
  select count(*) into v_ent from public."Entregas_Virgilio"
   where upper(btrim(coalesce(tanda,''))) = v_tanda and creado >= v_ts;
  if v_tal > 0 or v_ent > 0 then return 'tiene_registros'; end if;

  insert into public."GV_Tanda_Anulada" (tanda, fase, legajo, motivo, ts_evento)
  values (v_tanda, 'armado', v_leg, nullif(btrim(coalesce(p_motivo,'')),''), v_ts);

  update public."Etiquetas_Lio" set estado = 'anulada'
   where upper(btrim(coalesce(tanda,''))) = v_tanda
     and coalesce(estado,'') = 'pendiente' and creado_en >= v_ts;
  get diagnostics v_etl = row_count;

  v_nota := 'anulado ' || to_char(now() at time zone 'America/Argentina/Buenos_Aires','DD/MM HH24:MI')
            || coalesce(' · ' || nullif(btrim(coalesce(p_motivo,'')),''), '');
  update public."Registros_Produccion_Virgilio"
     set opcion = 'APX', descripcion = 'Armado anulado · ' || v_nota
   where id = v_id;

  begin perform public.gv_tanda_lock_anular(v_tanda, 'armado', v_leg); exception when others then null; end;
  begin perform public.tanda_liberar(v_tanda, 'armado', v_leg); exception when others then null; end;
  return 'ok';
end $$;

-- Prueba del ciclo completo contra la base (tanda ZZ77Z, todo borrado después):
--   1. entra el AP y se reserva el armado ....... lock 'tomada'
--   2. anular_armado_virgilio(...) .............. 'ok'
--   3. el celular REENVÍA el AP (on conflict do nothing, que es lo que manda el front)
--        opcion ............................ APX   (no revivió)
--        AP vivos de esa tanda ............. 0
--        lock .............................. (libre)   ← antes quedaba 'tomada' para siempre
--        registro en GV_Tanda_Anulada ...... 1
--
-- Rollback: volver el DELETE y `tanda_liberar` (ver v18.50 en el historial de git).
