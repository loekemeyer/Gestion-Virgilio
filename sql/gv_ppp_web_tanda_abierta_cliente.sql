-- =============================================================================
-- gv_ppp_web_tanda_abierta_cliente.sql — "si esa tanda todavía no se tocó, va ahí"
-- v14.05 · 2026-09-07 · Proyecto Virgilio (hrxfctzncixxqmpfhskv)
-- =============================================================================
-- LA REGLA, CORREGIDA POR EL DUEÑO (07/09), textual:
--
--   *"Por el único motivo que pedí que el agregado de Osa se programe en una tanda
--    nueva y no se incorpore a una actual, es porque la primera de Osa es pedido de
--    ISIS y el agregado, del nuevo formato. Sólo en caso que ya se haya pickeado (o
--    pasos posteriores), esa norma se mantiene en el futuro; si todavía ni se pickeó,
--    el agregado se agrega a la tanda actual del cliente."*
--
--   O sea: **el corte es "¿ya se tocó?", no "¿es de ISIS o es web?"**.
--
-- Qué cambia respecto de la v13.93. La v13.93 (bloque (a2)) ya llevaba el pedido al
-- DÍA en que el cliente ya tenía camión, pero siempre abriendo una tanda NUEVA — así
-- nació la D66G del 1354 de Osa al lado de la D66B. Con esta versión, si la tanda que
-- el cliente ya tiene ese día está INTACTA, el pedido entra a ESA tanda; si ya la
-- empezaron, recién ahí se abre la tanda nueva (que es el comportamiento v13.93).
--
-- QUÉ CUENTA COMO "TOCADA": que exista en `Registros_Produccion_Virgilio` algún evento
--   EP · TP  (picking: empezar / terminar)
--   AP · TAP (armado: armar pedido / armado terminado)
-- con esa tanda en el campo `texto`. Ese campo tiene formatos mezclados —código pelado,
-- `np|tanda`, `np|lío|tanda|…`— así que se miran los tres primeros segmentos del `|`.
-- CC/CCN (carga camión) no hace falta mirarlos: no hay carga sin armado previo.
--
-- QUÉ MIRA COMO "TANDA DEL CLIENTE ESE DÍA": las dos programaciones, web
-- (`PPP_Web_Programacion`) e ISIS (`gv_ppp_programacion_diaria`), porque el caso que lo
-- motivó es justamente una tanda de ISIS. Sólo reparto (`Zona N`), sin KRIKOS, y con la
-- NP del prefijo que corresponde a la empresa (9xxxx = LK, 4xxxx = Chef).
--
-- SE ENGANCHA EN: bloque (a1) de `gv_ppp_web_armar_pendientes`, ANTES del (a2). Lo que
-- se programa acá queda con tanda, y (a2), (b) y (c) lo saltean solos por su filtro de
-- "no programado".
--
-- MEDIDO AL DEPLOYAR (07/09):
--   gv_ppp_web_tanda_abierta_cliente('lk','2533','2026-09-09') → 'D66B'  (Osa, intacta)
--   gv_ppp_web_tanda_abierta_cliente('lk','4274','2026-09-04') → null    (D56D ya pickeada)
--   gv_ppp_web_tanda_abierta_cliente('lk','9999','2026-09-09') → null    (no existe)
--
-- ROLLBACK: `sql/backups/gv_ppp_web_armar_pendientes_20260907_pre_a1.sql` devuelve
-- `gv_ppp_web_armar_pendientes` a la v13.93; la función de acá se puede dropear
-- (`drop function public.gv_ppp_web_tanda_abierta_cliente(text,text,date);`) — no la
-- llama nadie más. Grep 0 en el repo de Producción para los dos nombres.
-- =============================================================================

-- ── 1) el helper ─────────────────────────────────────────────────────────────
create or replace function public.gv_ppp_web_tanda_abierta_cliente(
  p_empresa text, p_cod text, p_fecha date)
returns text
language sql
stable
set search_path to 'public'
as $fn$
  with cand as (
    -- tandas web del cliente ese día
    select upper(btrim(w.tanda)) as tanda
      from public."PPP_Web_Programacion" w
     where w.empresa = p_empresa
       and btrim(coalesce(w.cod_cliente,'')) = btrim(coalesce(p_cod,''))
       and w.fecha_entrega = p_fecha
       and coalesce(nullif(btrim(w.tanda),''),'') <> ''
       and coalesce(w.zona,'') ~ '^\s*Zona\s*[0-9]+'
    union
    -- tandas de ISIS del cliente ese día (el caso Osa)
    select upper(btrim(i.tanda))
      from public.gv_ppp_programacion_diaria i
     where btrim(coalesce(i.cod,'')) = btrim(coalesce(p_cod,''))
       and coalesce(nullif(btrim(i.tanda),''),'') <> ''
       and coalesce(i.tipo,'') <> 'KRIKOS'
       and coalesce(i.zona,'') ~ '^\s*Zona\s*[0-9]+'
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text),10)::date = p_fecha
       and ((p_empresa = 'lk'   and btrim(i.np) ~ '^9')
         or (p_empresa = 'chef' and btrim(i.np) ~ '^4'))
  )
  select min(c.tanda)
    from cand c
   where not exists (
     select 1 from public."Registros_Produccion_Virgilio" r
      where r.opcion in ('EP','TP','AP','TAP')
        and (   upper(btrim(split_part(r.texto,'|',1))) = c.tanda
             or upper(btrim(split_part(r.texto,'|',2))) = c.tanda
             or upper(btrim(split_part(r.texto,'|',3))) = c.tanda)
   );
$fn$;

comment on function public.gv_ppp_web_tanda_abierta_cliente(text,text,date) is
  'v14.05 — tanda que el cliente ya tiene ese día (web o ISIS) y que ningún operario tocó todavía (sin EP/TP/AP/TAP). NULL si no hay o si ya se empezó. La usa el bloque (a1) de gv_ppp_web_armar_pendientes.';

revoke all on function public.gv_ppp_web_tanda_abierta_cliente(text,text,date) from public, anon;
grant execute on function public.gv_ppp_web_tanda_abierta_cliente(text,text,date) to authenticated, service_role;

-- ── 2) el bloque (a1) dentro del armador ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.gv_ppp_web_armar_pendientes(p_empresa text, p_fecha date DEFAULT NULL::date, p_filas jsonb DEFAULT '[]'::jsonb, p_forzar jsonb DEFAULT '[]'::jsonb)
 RETURNS TABLE(r_fecha date, r_tanda text, r_zona text, r_np_count integer, r_m3 numeric, r_clientes integer, r_cods text[])
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_min    date := public.gv_ppp_web_dia_minimo();
  v_fecha  date;
  v_techo  date;
  v_i      int := 0;
  v_n      int;
  v_antes  int;
  r        record;
begin
  drop table if exists _gv_res;
  drop table if exists _gv_tmp;
  create temp table _gv_res (r_fecha date, r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int, r_cods text[]) on commit drop;
  create temp table _gv_tmp (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int) on commit drop;

  -- (a) forzados con fecha (Chef de una razón social que entró por LK ese día)
  for r in
    select nullif(x->>'fecha','')::date as f, array_agg(distinct x->>'cod') as cods
      from jsonb_array_elements(coalesce(p_forzar, '[]'::jsonb)) x
     where nullif(x->>'fecha','') is not null and nullif(x->>'cod','') is not null
     group by 1 order by 1
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.f, p_filas, r.cods, false);
    insert into _gv_res
    select r.f, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  -- el techo de la ventana "para atras": el dia que el automatico elegiria por su cuenta.
  v_techo := public.gv_ppp_web_proximo_dia_con_cupo(coalesce(p_fecha, v_min));

  -- (a1) v14.05 — LA TANDA QUE EL CLIENTE YA TIENE ESE DIA, SI TODAVIA NO SE TOCO.
  --   Dueno (07/09): "solo en caso que ya se haya pickeado (o pasos posteriores) [se abre
  --   tanda nueva]; si todavia ni se pickeo, el agregado se agrega a la tanda actual del
  --   cliente". El corte es "¿ya se toco?", no "¿es de ISIS o es web?".
  --   Se escribe DIRECTO en PPP_Web_Programacion con esa tanda: ppp_web_armar_tandas no
  --   sirve aca porque su _open solo mira tandas WEB del dia, y la del caso es de ISIS.
  --   Va antes de (a2): lo que queda con tanda aca, (a2)/(b)/(c) lo saltean solos.
  for r in
    select s.d, s.tanda_ab, jsonb_agg(s.x) as filas, array_agg(distinct s.x->>'cod') as cods
      from (
        select dc.d,
               public.gv_ppp_web_tanda_abierta_cliente(p_empresa, x->>'cod', dc.d) as tanda_ab,
               x
          from jsonb_array_elements(p_filas) x
          cross join lateral (select public.gv_ppp_web_dia_cliente(p_empresa, x->>'cod', current_date + 1, v_techo - 1) as d) dc
         where coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
           and nullif(btrim(coalesce(x->>'cod','')),'') is not null
           and dc.d is not null
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                              and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '')
      ) s
     where s.tanda_ab is not null
     group by s.d, s.tanda_ab
     order by s.d
  loop
    insert into public."PPP_Web_Programacion"
      (empresa, order_id, np_idx, np, cod_cliente, razon_social, direccion, barrio,
       tanda, zona, fecha_entrega, m3, m3_parcial, lineas, cajas)
    select p_empresa, (x->>'order_id')::bigint, (x->>'np_idx')::int, nullif(x->>'np','')::int,
           coalesce(nullif(x->>'cod',''), nullif(x->>'razon_social',''), '?'),
           nullif(x->>'razon_social',''), nullif(x->>'direccion',''), nullif(x->>'barrio',''),
           r.tanda_ab, coalesce(nullif(x->>'zona',''), '(sin zona)'), r.d,
           coalesce(nullif(x->>'m3','')::numeric, 0),
           coalesce((x->>'m3_parcial')::boolean, false),
           nullif(x->>'lineas','')::int, nullif(x->>'cajas','')::numeric
      from jsonb_array_elements(r.filas) x
    on conflict (empresa, order_id, np_idx) do update
       set tanda = excluded.tanda, zona = excluded.zona,
           fecha_entrega = excluded.fecha_entrega,
           m3 = excluded.m3, m3_parcial = excluded.m3_parcial,
           lineas = excluded.lineas, cajas = excluded.cajas;

    insert into _gv_res
    select r.d, r.tanda_ab,
           (select string_agg(distinct coalesce(nullif(x->>'zona',''),'(sin zona)'), ' + ')
              from jsonb_array_elements(r.filas) x),
           (select count(*)::int from jsonb_array_elements(r.filas) x),
           (select round(coalesce(sum(coalesce(nullif(x->>'m3','')::numeric,0)),0), 3)
              from jsonb_array_elements(r.filas) x),
           (select count(distinct x->>'cod')::int from jsonb_array_elements(r.filas) x),
           r.cods;
  end loop;

  -- (a2) v13.93 — EL CLIENTE YA TIENE CAMION ANTES pero la tanda YA SE TOCO: tanda nueva
  --   ese mismo dia. Dos definiciones textuales del dueno (07/09):
  --     - "tiene que buscar para atras, no para adelante" -> la ventana va desde manana
  --       hasta el dia ANTERIOR al que elegiria el automatico (v_techo - 1), asi la regla
  --       adelanta el pedido y nunca lo demora;
  --     - pisa el colchon Y el cupo: es el unico modo que resuelve el caso, porque el 9
  --       estaba a la vez dentro del colchon de 4 dias y pasado de cupo (7,03 m3 contra 6).
  --       El cupo mide PICKING, y sumarle 26 litros a un cliente que ya tiene 4 m3
  --       armandose ese dia es casi gratis y ahorra un camion.
  --   Como pisa cada cosa, sin codigo nuevo: la fecha explicita saltea el colchon (lo
  --   aplica el llamador, no ppp_web_armar_tandas), y pasar el cod en p_forzar_cods lo
  --   marca `prioritario`, que es la rama del filtro de cupo que entra siempre. Con
  --   p_incluir_manuales = true vale para TODAS las zonas (la v13.47 ya hacia esto pero
  --   por ZONA; esta es por CLIENTE).
  for r in
    select d, jsonb_agg(x) as filas, array_agg(distinct x->>'cod') as cods
      from (
        select public.gv_ppp_web_dia_cliente(p_empresa, x->>'cod', current_date + 1, v_techo - 1) as d, x
          from jsonb_array_elements(p_filas) x
         where coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
           and nullif(btrim(coalesce(x->>'cod','')),'') is not null
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                              and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '')
      ) s
     where d is not null
     group by d order by d
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d, r.filas, r.cods, true);
    insert into _gv_res
    select r.d, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  -- (b) zonas automaticas en cascada: primer dia con cupo desde p_fecha (o el dia minimo),
  --     lo que no entra al siguiente con cupo, hasta 8 dias por corrida.
  v_fecha := coalesce(p_fecha, v_min);
  loop
    v_i := v_i + 1;
    exit when v_i > 8;
    select count(*) into v_n
      from jsonb_array_elements(p_filas) x
     where public.gv_ppp_web_zona_automatica(x->>'zona')
       and not exists (select 1 from public."PPP_Web_Programacion" g
                        where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                          and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '');
    exit when v_n = 0;
    v_fecha := public.gv_ppp_web_proximo_dia_con_cupo(v_fecha);
    select count(*) into v_antes from _gv_res;
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, v_fecha, p_filas, '{}', false);
    insert into _gv_res
    select v_fecha, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
    exit when (select count(*) from _gv_res) = v_antes;
    v_fecha := v_fecha + 1;
  end loop;

  -- (c) zonas manuales con camion: al primer dia >= dia minimo con camion a esa zona
  for r in
    select d, jsonb_agg(x) as filas, array_agg(distinct x->>'cod') as cods
      from (
        select public.gv_ppp_web_dia_camion(x->>'zona', v_min) as d, x
          from jsonb_array_elements(p_filas) x
         where coalesce(x->>'zona','') ~ '^\s*Zona\s*[0-9]+'
           and not public.gv_ppp_web_zona_automatica(x->>'zona')
           and not exists (select 1 from public."PPP_Web_Programacion" g
                            where g.empresa = p_empresa and g.order_id = (x->>'order_id')::bigint
                              and g.np_idx = (x->>'np_idx')::int and coalesce(nullif(trim(g.tanda),''),'') <> '')
      ) s
     where d is not null
     group by d order by d
  loop
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.d, r.filas, r.cods, true);
    insert into _gv_res
    select r.d, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  return query select * from _gv_res order by 1, 2;
end
$function$;
