-- v19.76 (2026-09-18, problema 413) — MOVER UNA NP DE TANDA NO PUEDE REESCRIBIR EL CAMPO 3 A CIEGAS.
--
-- QUÉ ESTABA MAL. `gv_ppp_nps_mover_a` (y su gemelo `gv_ppp_tanda_renombrar`) reescribían el
-- evento como  campo1 | campo2 | tanda_nueva,  dando por sentado que la tanda siempre vive en el
-- campo 3 y que el texto no tiene más de 3 campos. Ninguna de las dos cosas es cierta: de los 11
-- eventos que llevan la NP en el campo 1, la tanda está en el campo 3 en UNO solo (TAL).
--
--   opcion | texto                                             | tanda
--   -------+---------------------------------------------------+------
--   CCN    | NP|tanda|camion|orden                             |  2
--   CCR    | NP|tanda                                          |  2
--   CRN    | NP|tanda                                          |  2
--   FSS    | NP|tanda                                          |  2
--   CRA    | NP|tanda|razon_social                             |  2
--   FCO    | NP|tanda|cod×falto,…|razon_social                 |  2
--   ENT    | NP|tanda|cod:pedidas:entregadas:faltó,…|ENT       |  2
--   TAL    | NP|líos|tanda[|resumen[|clase]]                   |  3
--   FAL    | NP|cod|cajas|legajo|tanda|MANUAL                  |  5
--   NPD    | NP|cod|tipo|góndola|qty|sale|tanda                |  7
--   CP     | NP|cod|qty|GONDOLA\AGUARDAR|lío                   |  —  (no tiene tanda)
--
-- Resultado medido el 18/09: mover LK 0034/LK 0035 de E01G a E29D dejó el ENT como
-- "LK 0034|E01G|E29D" — el detalle por renglón pisado con el código de tanda, el marcador |ENT
-- comido y la tanda VIEJA intacta en el campo 2. 31 eventos rotos desde el 15/09 (26 ENT, 3 CP,
-- 1 FAL, 1 NPD). Y el ENT existe justamente para que el servidor NO tenga que adivinar el armado
-- (v17.85: reconstruirlo a mano acertaba 1.159 de 1.280 y erraba 6).
--
-- DE PASO SE ARREGLAN DOS COSAS MÁS QUE VENÍAN DEL MISMO `split_part(...,3)`:
--   · el TAL perdía `resumen` y `clase` (campos 4 y 5) en cada movida y en cada renombre;
--   · CCR / CRN / FSS / CCN de 2 campos NO se actualizaban nunca (el guard pedía campo 3 no
--     vacío), así que el control de remito y la carga de camión quedaban apuntando a la tanda
--     vieja después de mover la NP.
--
-- ⚠ LO QUE ESTE PARCHE **NO** TOCA, A PROPÓSITO: el evento **PKC** lleva la tanda en el campo 1
-- (`TANDA|cod|…`) y HOY no lo renombra nadie — ni `gv_ppp_tanda_renombrar` ni nada más (medido:
-- son las 4 únicas funciones que escriben en `Registros_Produccion_Virgilio`). El comentario de
-- la v19.69 dice "como los eventos también se renombran acá arriba, el reconciliador va a
-- recalcularlo como la suma de las dos", y para el PKC eso no pasa. Eso mueve STOCK, así que va
-- medido y aparte (problema 421), no de arrastre en este commit.

-- ---------------------------------------------------------------------------------------------
-- 1) En qué campo vive la tanda, por tipo de evento. NULL = ese evento no lleva tanda.
create or replace function public.gv_evento_tanda_campo(p_opcion text)
returns int language sql immutable as $$
  select case upper(btrim(coalesce(p_opcion, '')))
           when 'CCN' then 2 when 'CCR' then 2 when 'CRN' then 2 when 'FSS' then 2
           when 'CRA' then 2 when 'FCO' then 2 when 'ENT' then 2
           when 'TAL' then 3
           when 'FAL' then 5
           when 'NPD' then 7
           else null
         end;
$$;

-- 2) Qué tanda dice el evento (para poder filtrar por ella sin volver a hardcodear el campo 3).
create or replace function public.gv_evento_tanda(p_opcion text, p_texto text)
returns text language sql immutable as $$
  select case
           when public.gv_evento_tanda_campo(p_opcion) is null then null
           else nullif(upper(btrim(split_part(coalesce(p_texto, ''), '|',
                                              public.gv_evento_tanda_campo(p_opcion)))), '')
         end;
$$;

-- 3) El texto con la tanda cambiada, conservando TODOS los demás campos.
--    NULL = no hay nada que cambiar (el evento no lleva tanda, el texto es más corto que el campo
--    que corresponde, o ya dice esa tanda). Que devuelva NULL es lo que usan los llamadores como
--    filtro: así no se toca una fila de más.
create or replace function public.gv_evento_set_tanda(p_opcion text, p_texto text, p_tanda text)
returns text language plpgsql immutable as $$
declare
  v_i int := public.gv_evento_tanda_campo(p_opcion);
  v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_p text[];
begin
  if v_i is null or v_t = '' or coalesce(btrim(p_texto), '') = '' then return null; end if;
  v_p := string_to_array(p_texto, '|');
  if coalesce(array_length(v_p, 1), 0) < v_i then return null; end if;
  if upper(btrim(coalesce(v_p[v_i], ''))) = v_t then return null; end if;
  v_p[v_i] := v_t;
  return array_to_string(v_p, '|');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 4) Los dos llamadores. Cambia SÓLO el update de `Registros_Produccion_Virgilio`; el resto es la
--    definición viva del 18/09 traída con pg_get_functiondef, tal cual.
create or replace function public.gv_ppp_nps_mover_a(p_nps text[], p_tanda text, p_fecha date, p_nota text default null)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare
  v_nps text[]; v_t text := upper(btrim(coalesce(p_tanda, '')));
  v_esp date := public.gv_ppp_espera_fecha();
  v_fe date := case when p_fecha = public.gv_ppp_espera_fecha() then null else p_fecha end;
  v_web int := 0; v_isis int := 0;
begin
  select array_agg(distinct regexp_replace(upper(btrim(x)), '\.0+$', ''))
    into v_nps from unnest(coalesce(p_nps, array[]::text[])) x where btrim(coalesce(x, '')) <> '';
  if v_nps is null or array_length(v_nps, 1) = 0 then return 0; end if;

  -- ⚠ UN SOLO UPDATE para todas las NP: el trigger `gv_web_cliente_un_solo_dia` es AFTER ROW y
  -- corre al final del statement, así que con las hermanas ya movidas no salta. Moviéndolas de a
  -- una rebotaba con "los pedidos de un cliente no pueden salir en días distintos" por un estado
  -- intermedio que duraba una fila (medido el 17/09 con LK 0009 + LK 0010 de Emilio Martinez).
  update public."PPP_Web_Programacion" w
     set tanda = v_t, fecha_entrega = v_fe, actualizado_at = now()
   where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = any (v_nps);
  get diagnostics v_web = row_count;

  insert into public."GV_PPP_Prog_Override" (np, tanda, fecha_entrega, nota)
  select n, v_t, v_fe, p_nota from unnest(v_nps) n
   where not exists (select 1 from public."PPP_Web_Programacion" w
                      where upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))) = n)
  on conflict (np) do update set tanda = excluded.tanda, fecha_entrega = excluded.fecha_entrega,
                                 nota = coalesce(excluded.nota, public."GV_PPP_Prog_Override".nota);
  get diagnostics v_isis = row_count;

  update public."Facturacion_NP" f set tanda = v_t
   where regexp_replace(upper(btrim(f.np)), '\.0+$', '') = any (v_nps);
  update public."Entregas_Virgilio" e set tanda = v_t
   where regexp_replace(upper(btrim(e.np)), '\.0+$', '') = any (v_nps);

  -- v19.76 (problema 413) — la tanda se escribe en EL CAMPO QUE LE TOCA A CADA EVENTO, y el resto
  -- del texto queda como estaba. Antes esto era `campo1|campo2|v_t` y pisaba el detalle del ENT,
  -- el chofer del CCN, la razón social del CRA/FCO y los campos 4-5 del TAL. `gv_evento_set_tanda`
  -- devuelve NULL cuando no hay nada que cambiar, y ese NULL es el filtro.
  update public."Registros_Produccion_Virgilio" r
     set texto = public.gv_evento_set_tanda(r.opcion, r.texto, v_t)
   where regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') = any (v_nps)
     and public.gv_evento_set_tanda(r.opcion, r.texto, v_t) is not null;

  if p_fecha = v_esp then
    insert into public."GV_PPP_Armados_Espera" (np, tanda, empresa, por, motivo, creado_en)
    select n, v_t, public.gv_emp_de_np(n), null, p_nota, now() from unnest(v_nps) n
    on conflict (np) do update set tanda = excluded.tanda, creado_en = now();
  else
    delete from public."GV_PPP_Armados_Espera" e where e.np = any (v_nps);
  end if;
  return v_web + v_isis;
end $function$;

create or replace function public.gv_ppp_tanda_renombrar(p_vieja text, p_nueva text, p_por text default null)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare v_a text := upper(btrim(coalesce(p_vieja, ''))); v_b text := upper(btrim(coalesce(p_nueva, ''))); v_n int := 0;
begin
  if v_a = '' or v_b = '' or v_a = v_b then return 0; end if;
  update public."Registros_Produccion_Virgilio" r set texto = v_b where upper(btrim(r.texto)) = v_a;
  get diagnostics v_n = row_count;

  -- v19.76 (problema 413) — ídem `gv_ppp_nps_mover_a`: el campo de la tanda depende del evento.
  -- El `campo1|campo2|v_b` de antes acertaba sólo con el TAL, y aun ahí le comía el resumen y la
  -- clase (campos 4 y 5).
  update public."Registros_Produccion_Virgilio" r
     set texto = public.gv_evento_set_tanda(r.opcion, r.texto, v_b)
   where public.gv_evento_tanda(r.opcion, r.texto) = v_a
     and public.gv_evento_set_tanda(r.opcion, r.texto, v_b) is not null;

  update public."Entregas_Virgilio" e set tanda = v_b where upper(btrim(e.tanda)) = v_a;
  update public."Facturacion_NP" f set tanda = v_b where upper(btrim(f.tanda)) = v_a;

  -- v19.69 (problema 407) — EL STOCK DEL PIPELINE NO SE PUEDE RENOMBRAR A CIEGAS.
  -- `mov_stock_pipeline_dedup` es único por (ref, cod_art, empresa, deposito, tipo) para
  -- picking/separado/facturado: es el guard que impide el doble picking. Al fusionar una tanda
  -- dentro de OTRA ya pickeada, el `set ref = v_b` de toda la vida chocaba contra ese índice y la
  -- RPC entera devolvía 400, o sea que juntar dos tandas armadas era imposible.
  -- Lo que corresponde es FUSIONAR: el `delta` es el total pickeado de la tanda para ese artículo
  -- (lo escribe `reconciliar_stock_articulo_rt` desde los eventos PKC).
  -- ⚠ Primero el DELETE y después el UPDATE: `trigger_actualizar_saldo_stock` recalcula el saldo
  -- del código desde cero pero NO corre en DELETE, así que al revés dejaría el saldo inflado.
  -- ⚠ v19.76: el PKC lleva la tanda en el CAMPO 1 y hoy no lo renombra nadie, así que la frase
  -- "como los eventos también se renombran acá arriba" NO vale para el PKC. Medido y abierto
  -- aparte (problema 421): tocarlo mueve stock. Detalle: sql/gv_ppp_tanda_fusion_stock_v1969.sql
  create temp table if not exists _tr_fus (id_dest bigint primary key, suma numeric) on commit drop;
  delete from _tr_fus where true;
  insert into _tr_fus (id_dest, suma)
  select d.id, sum(v.delta)
    from public."Movimientos_Stock" v
    join public."Movimientos_Stock" d
      on d.tipo = v.tipo and d.deposito = v.deposito
     and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
     and coalesce(d.empresa, '') = coalesce(v.empresa, '')
     and upper(btrim(coalesce(d.ref, ''))) = v_b
     and d.tipo in ('picking', 'separado', 'facturado')
   where upper(btrim(coalesce(v.ref, ''))) = v_a
     and v.tipo in ('picking', 'separado', 'facturado')
   group by d.id;

  delete from public."Movimientos_Stock" v
   where upper(btrim(coalesce(v.ref, ''))) = v_a
     and v.tipo in ('picking', 'separado', 'facturado')
     and exists (select 1 from public."Movimientos_Stock" d
                  where d.tipo = v.tipo and d.deposito = v.deposito
                    and upper(btrim(d.cod_art)) = upper(btrim(v.cod_art))
                    and coalesce(d.empresa, '') = coalesce(v.empresa, '')
                    and upper(btrim(coalesce(d.ref, ''))) = v_b
                    and d.tipo in ('picking', 'separado', 'facturado'));

  update public."Movimientos_Stock" d set delta = d.delta + f.suma
    from _tr_fus f where d.id = f.id_dest;

  update public."Movimientos_Stock" m set ref = v_b where upper(btrim(coalesce(m.ref, ''))) = v_a;

  update public."GV_PPP_Armados_Espera" e set tanda = v_b where upper(btrim(coalesce(e.tanda, ''))) = v_a;
  update public."PPP_Web_Tandas" t set codigo = v_b
   where upper(btrim(t.codigo)) = v_a
     and not exists (select 1 from public."PPP_Web_Tandas" x where upper(btrim(x.codigo)) = v_b);
  delete from public."PPP_Web_Tandas" t where upper(btrim(t.codigo)) = v_a;
  return v_n;
end $function$;
