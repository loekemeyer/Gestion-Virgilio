-- ⚠ v13.22: v_desde ahora es gv_ppp_web_dia_minimo(p_ahora) (anticipación mínima), ver sql/gv_ppp_web_anticipacion.sql; el cuerpo de abajo es el de v13.21.
-- gv_ppp_web_dia_salida(p_filas, p_ahora) · "qué día va a poder salir" cada pedido de "A Programar".
-- v13.21 (2026-09-06 noche) · dueño: "en A Programar debe aparecer para qué día va a poder salir el
-- pedido, no la primera (fecha de recepción, sin sentido)". Migración `gv_ppp_web_dia_salida_v1321`.
-- Regla (la misma que usan el job de las 00:01 y el intradía para las zonas automáticas):
--   · Retira            → sin día (lo pasa a buscar el cliente).                       motivo 'retira'
--   · Súper             → sin día (camión propio, lo programa el supervisor).            motivo 'super'
--   · zona automática   → si es antes del corte (intradia_corte_hora) y lo pendiente de las zonas
--     (zonas_automaticas) automáticas llega al umbral (intradia_umbral_m3): proximo_dia_entrega(ahora), puede
--                         ser hoy ('intradia'); si no, el job de mañana 00:01 → próximo hábil con
--                         cupo desde mañana ('job').
--   · resto (manual)    → el próximo día (≥ hoy si es antes del corte, si no ≥ mañana) en que ya hay
--                         un camión a esa zona, web (PPP_Web_Programacion) o ISIS
--                         (gv_ppp_programacion_diaria, canilla cerrada) ('camion'); si no hay
--                         ninguno, null ('sin_camion'). Sin zona → null ('sin_zona').
-- Entrada: [{zona, m3}] = las filas de "A Programar". Salida: una fila por entrada, por índice.
-- Grants: authenticated y service_role (anon no). Prueba abajo.

create or replace function public.gv_ppp_web_dia_salida(p_filas jsonb, p_ahora timestamptz default now())
returns table(r_idx integer, r_dia date, r_motivo text, r_detalle text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_local  timestamp := p_ahora at time zone 'America/Argentina/Buenos_Aires';
  v_corte  time := coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'intradia_corte_hora'), '12:00')::time;
  v_umbral numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'intradia_umbral_m3'), 0.80);
  v_auto   text[] := string_to_array(coalesce((select valor_texto from public."PPP_Web_Config" where clave = 'zonas_automaticas'), '1,2'), ',');
  v_desde  date := case when v_local::time < v_corte then v_local::date else v_local::date + 1 end;
  v_manana timestamptz := ((v_local::date + 1)::timestamp + time '00:01') at time zone 'America/Argentina/Buenos_Aires';
  v_dia_intra date := public.gv_ppp_web_proximo_dia_entrega(p_ahora);
  v_dia_job   date := public.gv_ppp_web_proximo_dia_entrega(v_manana);
begin
  return query
  with f as (
    select (x.ord - 1)::int as idx,
           btrim(x.v->>'zona') as zona,
           coalesce(nullif(x.v->>'m3','')::numeric, 0) as m3,
           (regexp_match(btrim(x.v->>'zona'), '^Zona\s*([0-9]+)'))[1] as zn
      from jsonb_array_elements(coalesce(p_filas, '[]'::jsonb)) with ordinality as x(v, ord)
  ),
  pend_auto as (
    select coalesce(sum(m3), 0) as m3 from f where zn = any(v_auto)
  ),
  camiones as (
    select (regexp_match(btrim(w.zona), '^Zona\s*([0-9]+)'))[1] as zn, w.fecha_entrega as dia, upper(btrim(w.tanda)) as tanda
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega >= v_desde and coalesce(nullif(btrim(w.tanda),''),'') <> '' and w.zona is not null
    union all
    select (regexp_match(btrim(i.zona), '^Zona\s*([0-9]+)'))[1], left(btrim(i.fecha_entrega::text), 10)::date, upper(btrim(i.tanda))
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date >= v_desde
       and coalesce(nullif(btrim(i.tanda),''),'') <> '' and i.zona is not null
  ),
  manual as (
    select f.idx, c.dia, string_agg(distinct c.tanda, ' · ' order by c.tanda) as tandas
      from f
      join camiones c on c.zn = f.zn
       and c.dia = (select min(c2.dia) from camiones c2 where c2.zn = f.zn)
     where f.zn is not null and not (f.zn = any(v_auto))
     group by f.idx, c.dia
  )
  select f.idx,
         case
           when f.zona ilike 'retira%' then null
           when f.zona ilike 's_per%' or f.zona ilike 'súper%' or f.zona ilike 'super%' then null
           when f.zn = any(v_auto) then
             case when v_local::time < v_corte and (select m3 from pend_auto) >= v_umbral then v_dia_intra else v_dia_job end
           else m.dia
         end as r_dia,
         case
           when f.zona ilike 'retira%' then 'retira'
           when f.zona ilike 's_per%' or f.zona ilike 'súper%' or f.zona ilike 'super%' then 'super'
           when f.zn = any(v_auto) then
             case when v_local::time < v_corte and (select m3 from pend_auto) >= v_umbral then 'intradia' else 'job' end
           when m.dia is not null then 'camion'
           when f.zn is null then 'sin_zona'
           else 'sin_camion'
         end as r_motivo,
         case
           when f.zn = any(v_auto) then 'Zona automática: se arma sola para el próximo día hábil con cupo'
           when m.dia is not null then 'Ya hay camión a la zona ' || f.zn || ': ' || m.tandas
           when f.zona ilike 'retira%' then 'Lo pasa a buscar el cliente'
           when f.zona ilike 's_per%' or f.zona ilike 'súper%' or f.zona ilike 'super%' then 'Súper: camión propio, lo programa el supervisor'
           when f.zn is null then 'Sin zona: revisar barrio'
           else 'No hay camión previsto a la zona ' || f.zn || ' en los próximos días: programar a mano'
         end as r_detalle
    from f
    left join manual m on m.idx = f.idx
   order by f.idx;
end $$;
revoke all on function public.gv_ppp_web_dia_salida(jsonb, timestamptz) from public, anon;
grant execute on function public.gv_ppp_web_dia_salida(jsonb, timestamptz) to authenticated, service_role;

-- Prueba (2026-09-06, lunes 07/09 09:00 simulado):
--   select * from public.gv_ppp_web_dia_salida('[{"zona":"Zona 1 - CABA Sur","m3":0.5},{"zona":"Zona 4 - GBA Sur","m3":0.3},
--     {"zona":"Zona 6 - GBA Norte","m3":0.2},{"zona":"Retira","m3":0.1},{"zona":"Súper","m3":2},{"zona":"","m3":0.1}]'::jsonb,
--     '2026-09-07 09:00-03');
--   → zona 1: 07/09 intradia · zona 4: 08/09 camion (D60A · D60B · D60C · D60F) · zona 6: 14/09 camion (D69C)
--     · Retira: null retira · Súper: null super · '': null sin_zona.  A las 13:00: zona 1 → 08/09 job.
-- Rollback: drop function public.gv_ppp_web_dia_salida(jsonb, timestamptz);  (el front vuelve a mostrar "🚚 …")
