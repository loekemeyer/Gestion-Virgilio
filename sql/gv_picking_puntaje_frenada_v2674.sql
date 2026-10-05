-- =====================================================================================
-- v26.74 (marcadores internos v26.68: llave de idempotencia, no cambiar) · Puntaje 1-10 de picking: una tanda FRENADA entra con la PARTE DE CADA UNO (Luis, 2026-10-05, D17)
-- Proyecto Gestión Virgilio (hrxfctzncixxqmpfhskv). APLICADO el 05/10 (el pedido es la autorización).
--
-- Luis: «que entre la parte de cada uno». Hasta la v26.67 una tanda con freno de picking quedaba
-- AFUERA del puntaje (centinela 304). Ahora cada TRAMO (EP → PKF del que frenó, EP → TP del que
-- terminó) se mide con la MISMA cuenta de siempre (gv_picking_tanda_calc: sus líneas, sus paradas, sus
-- alturas, su tiempo neto) y los tramos del mismo legajo se suman en UNA fila de GV_Picking_Tanda.
--
--   * el tramo que termina en un FRENO no lleva cola (≡ horas, v26.62); y lo que va del último PKC
--     al freno se topea en cola_tope_min (30), como la cola del TP: el freno por fichaje cae a la
--     hora del FJ y no se le puede cobrar al operario todo lo que hizo después;
--   * la dificultad sumada = promedio de la de cada tramo ponderado por cajas (es la misma cuenta:
--     (Σ tamaño − Σ fijo − Σ arranque) ÷ Σ cajas); el grado sale de los mismos deciles;
--   * cada tramo paga su costo fijo y su arranque: el que retoma vuelve a buscar el carro.
--
-- Una tanda SIN freno sigue exactamente igual (mismo camino de gv_picking_tanda_refresh).
-- La ventana de PKC de cada tramo no se solapa con la del vecino (v26.68-ventana en gv_picking_tanda_calc).
-- Centinela 304 reemplazado; nuevos 316-319.
-- =====================================================================================

-- 1) los tramos de un legajo en una tanda frenada, sumados ------------------------------
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10, D17)
create or replace function public.gv_picking_tanda_calc_frenada(p_tanda text, p_legajo text)
returns "GV_Picking_Tanda"
language plpgsql volatile security definer set search_path to 'public'
as $function$
-- v26.68-frenada (Luis, 05/10, D17): «que entre la parte de cada uno». Cada tramo (EP → PKF / EP → TP)
-- con la cuenta de siempre; el del FRENO sin cola y con la espera hasta el freno topeada como la cola.
-- v26.68-ventana: la ventana de PKC de cada tramo no se solapa con la del tramo vecino (de cualquier
-- legajo): si alguien retoma a los 2 min, el ±5 min de siempre contaría esas líneas en los dos tramos.
declare
  c jsonb; v_ctope numeric; v_dec numeric[];
  t record; x public."GV_Picking_Tanda"%rowtype; r public."GV_Picking_Tanda"%rowtype;
  v_last timestamptz; v_pz numeric; v_tail numeric; v_desde timestamptz; v_hasta timestamptz;
  v_dnum numeric := 0; v_dcaj numeric := 0; v_fnum numeric := 0; v_fped numeric := 0; v_n int := 0;
begin
  select jsonb_object_agg(clave, valor) into c from public."GV_Picking_Esquema";
  v_ctope := coalesce((c->>'cola_tope_min')::numeric, 30);
  v_dec   := array[(c->>'decil_1')::numeric,(c->>'decil_2')::numeric,(c->>'decil_3')::numeric,(c->>'decil_4')::numeric,(c->>'decil_5')::numeric,
                   (c->>'decil_6')::numeric,(c->>'decil_7')::numeric,(c->>'decil_8')::numeric,(c->>'decil_9')::numeric];
  r.tanda := upper(btrim(p_tanda)); r.legajo := p_legajo;
  for t in
    select * from (
      select e.opcion, e.legajo::text leg, e.ts_inicio ep, e.ts_cliente tp,
             lag(e.ts_cliente) over w prev_tp, lead(e.ts_inicio) over w next_ep
        from public."Registros_Produccion_Virgilio" e
       where e.opcion in ('TP','PKF') and upper(btrim(e.texto)) = upper(btrim(p_tanda))
         and e.ts_inicio is not null and e.ts_cliente > e.ts_inicio
      window w as (order by e.ts_cliente)) z
     where z.leg = p_legajo
     order by z.tp
  loop
    -- frontera entre tramos vecinos: el fin del anterior, salvo que el siguiente empiece antes de los 5 min
    v_desde := case when t.prev_tp is null then t.ep - interval '5 min'
                    else greatest(t.ep - interval '5 min', least(t.prev_tp + interval '5 min', greatest(t.prev_tp, t.ep)) + interval '1 microsecond') end;
    v_hasta := case when t.next_ep is null then t.tp + interval '5 min'
                    else least(t.tp + interval '5 min', greatest(t.tp, t.next_ep)) end;
    perform set_config('gv.pkc_desde', v_desde::text, true);
    perform set_config('gv.pkc_hasta', v_hasta::text, true);
    x := public.gv_picking_tanda_calc(p_tanda, p_legajo, t.ep, t.tp);
    perform set_config('gv.pkc_desde', '', true);
    perform set_config('gv.pkc_hasta', '', true);
    if t.opcion = 'PKF' then
      select max(ts_cliente) into v_last from public."Registros_Produccion_Virgilio"
       where opcion = 'PKC' and upper(btrim(split_part(texto,'|',1))) = upper(btrim(p_tanda))
         and ts_cliente between v_desde and v_hasta;
      if v_last is not null and v_last < t.tp then
        select coalesce(sum(extract(epoch from least(ts_cliente, t.tp) - greatest(ts_inicio, v_last))), 0) / 60 into v_pz
          from public."Registros_Produccion_Virgilio"
         where legajo::text = p_legajo and opcion in ('AT','PB','Limp','PC','CT','Perm') and ts_inicio is not null
           and ts_cliente > v_last and ts_inicio < t.tp;
        v_tail := greatest(0, extract(epoch from t.tp - v_last) / 60 - coalesce(v_pz, 0));
        x.neto_sh := greatest(0, coalesce(x.neto_sh, 0) - greatest(0, v_tail - v_ctope));
      end if;
      x.cola_min := 0; x.real_min := x.neto_sh;
    end if;
    v_n := v_n + 1;
    r.ep := least(coalesce(r.ep, t.ep), t.ep); r.tp := greatest(coalesce(r.tp, t.tp), t.tp);
    r.lineas := coalesce(r.lineas, 0) + coalesce(x.lineas, 0);
    r.cajas := coalesce(r.cajas, 0) + coalesce(x.cajas, 0);
    r.cajas30 := coalesce(r.cajas30, 0) + coalesce(x.cajas30, 0);
    r.paradas := coalesce(r.paradas, 0) + coalesce(x.paradas, 0);
    r.esc := coalesce(r.esc, 0) + coalesce(x.esc, 0);
    r.n_mx := coalesce(r.n_mx, 0) + coalesce(x.n_mx, 0);
    r.n_f := coalesce(r.n_f, 0) + coalesce(x.n_f, 0);
    select coalesce(jsonb_object_agg(k, s), '{}'::jsonb) into r.nh
      from (select k, sum(v::numeric) s
              from (select * from jsonb_each_text(coalesce(r.nh, '{}'::jsonb))
                    union all select * from jsonb_each_text(coalesce(x.nh, '{}'::jsonb))) z(k, v) group by k) w;
    r.tamano := coalesce(r.tamano, 0) + coalesce(x.tamano, 0);
    r.bruto_min := coalesce(r.bruto_min, 0) + coalesce(x.bruto_min, 0);
    r.pausa_min := coalesce(r.pausa_min, 0) + coalesce(x.pausa_min, 0);
    r.huecos_min := coalesce(r.huecos_min, 0) + coalesce(x.huecos_min, 0);
    r.neto_sh := coalesce(r.neto_sh, 0) + coalesce(x.neto_sh, 0);
    r.cola_min := coalesce(r.cola_min, 0) + coalesce(x.cola_min, 0);
    r.real_min := coalesce(r.real_min, 0) + coalesce(x.real_min, 0);
    r.lineas_cero := coalesce(r.lineas_cero, 0) + coalesce(x.lineas_cero, 0);
    r.cajas_ped := coalesce(r.cajas_ped, 0) + coalesce(x.cajas_ped, 0);
    if x.dificultad is not null and coalesce(x.cajas, 0) > 0 then v_dnum := v_dnum + x.dificultad * x.cajas; v_dcaj := v_dcaj + x.cajas; end if;
    if coalesce(x.cajas_ped, 0) > 0 then v_fnum := v_fnum + coalesce(x.m3_frac, 1) * x.cajas_ped; v_fped := v_fped + x.cajas_ped; end if;
  end loop;
  if v_n = 0 then return r; end if;   -- sin tramos: tp null, el refresco la saltea
  r.dificultad := case when v_dcaj > 0 then v_dnum / v_dcaj end;
  r.grado := case when r.dificultad is null then 10 else 1 + (select count(*) from unnest(v_dec) d where d < r.dificultad) end;
  r.nivel := case when r.grado <= 2 then 'Baja' when r.grado <= 5 then 'Media' when r.grado <= 8 then 'Alta' else 'Muy alta' end;
  r.multiplicador := round(1 + 0.1 * (r.grado - 5), 1);
  r.m3_frac := case when v_fped > 0 then round(v_fnum / v_fped, 4) else 1 end;
  r.cola_tipo := 'frenada';
  r.indice := case when r.real_min > 0.5 then round(r.tamano / r.real_min, 3) end;
  r.calc_at := now();
  return r;
end
$function$;
revoke all on function public.gv_picking_tanda_calc_frenada(text, text) from public, anon, authenticated;

-- 1b) gv_picking_tanda_calc: la ventana de PKC la puede fijar el llamador (sólo calc_frenada) ----
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10, D17). Sobre la definición VIVA, idempotente.
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_picking_tanda_calc(text,text,timestamptz,timestamptz)'::regprocedure);
  if d like '%v26.68-ventana%' then raise notice 'ya estaba'; return; end if;
  n := replace(d, $a$       and ts_cliente between p_ep - interval '5 min' and p_tp + interval '5 min'
  ),
  pk as ($a$, $a$       -- v26.68-ventana (D17): en un tramo de tanda FRENADA, gv_picking_tanda_calc_frenada fija la ventana exacta
       -- (gv.pkc_desde / gv.pkc_hasta) para que un PKC no caiga en dos tramos; sin eso, ±5 min como siempre
       and ts_cliente between coalesce(nullif(current_setting('gv.pkc_desde', true), '')::timestamptz, p_ep - interval '5 min')
                          and coalesce(nullif(current_setting('gv.pkc_hasta', true), '')::timestamptz, p_tp + interval '5 min')
  ),
  pk as ($a$);
  if n = d or n not like '%v26.68-ventana%' then raise exception 'gv_picking_tanda_calc: el texto no matcheó'; end if;
  execute n;
end $p$;

-- 2) el refresco: también PKF, y la tanda frenada por tramos --------------------------------
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10, D17)
create or replace function public.gv_picking_tanda_refresh(p_dias integer default 3, p_hasta_dias integer default 0)
returns integer
language plpgsql security definer set search_path to 'public'
as $function$
declare v_n int := 0; t record; r public."GV_Picking_Tanda"%rowtype;
begin
  -- Recalcula (upsert) las tandas con TP de la ventana. Un TP anulado (TPX) no se borra de acá:
  -- gv_picking_puntaje_operario sólo cuenta las filas cuyo TP sigue existiendo.
  -- v26.68 (D17): también el PKF (el tramo del que frenó). Una tanda con freno de picking se mide
  -- por tramos y se suma por legajo (gv_picking_tanda_calc_frenada); sin freno, como siempre.
  for t in
    select distinct on (upper(btrim(texto)), legajo::text) upper(btrim(texto)) tanda, legajo::text leg, opcion op, ts_inicio ep, ts_cliente tp
      from public."Registros_Produccion_Virgilio"
     where opcion in ('TP','PKF') and ts_inicio is not null and ts_cliente > ts_inicio
       and legajo::text not in ('0','1') and legajo::text !~ '^sup:'
       and ts_cliente >= now() - make_interval(days => p_dias) and ts_cliente < now() - make_interval(days => p_hasta_dias)
     order by upper(btrim(texto)), legajo::text, ts_cliente desc
  loop
    if exists (select 1 from public."GV_Tanda_Freno" fz where fz.tanda = t.tanda and fz.fase = 'picking') then
      r := public.gv_picking_tanda_calc_frenada(t.tanda, t.leg);
      if r.tp is null then continue; end if;
    elsif t.op <> 'TP' then
      continue;
    else
      r := public.gv_picking_tanda_calc(t.tanda, t.leg, t.ep, t.tp);
    end if;
    insert into public."GV_Picking_Tanda" as g select r.*
    on conflict (tanda, legajo) do update set
      ep = excluded.ep, tp = excluded.tp, lineas = excluded.lineas, cajas = excluded.cajas, cajas30 = excluded.cajas30,
      paradas = excluded.paradas, esc = excluded.esc, n_mx = excluded.n_mx, n_f = excluded.n_f, nh = excluded.nh,
      tamano = excluded.tamano, dificultad = excluded.dificultad, grado = excluded.grado, nivel = excluded.nivel,
      multiplicador = excluded.multiplicador, bruto_min = excluded.bruto_min, pausa_min = excluded.pausa_min,
      huecos_min = excluded.huecos_min, neto_sh = excluded.neto_sh, cola_min = excluded.cola_min, cola_tipo = excluded.cola_tipo,
      real_min = excluded.real_min, indice = excluded.indice, calc_at = excluded.calc_at,
      lineas_cero = excluded.lineas_cero, cajas_ped = excluded.cajas_ped, m3_frac = excluded.m3_frac;   -- v26.51
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$function$;

-- 3) el puntaje: la frenada entra; el «TP vivo» acepta el PKF del que frenó ---------------
-- Se aplica sobre la definición VIVA (pg_get_functiondef), idempotente; falla si el texto no matchea.
-- REGLA_CONFIRMADA_POR_USUARIO (Luis, 05/10, D17)
do $p$
declare d text; n text;
begin
  d := pg_get_functiondef('public.gv_picking_puntaje_operario(integer)'::regprocedure);
  if d like '%v26.68-frenada%' then raise notice 'ya estaba'; return; end if;
  n := replace(d, $a$                    where e.opcion = 'TP' and e.ts_cliente = t.tp and e.legajo::text = t.legajo and upper(btrim(e.texto)) = t.tanda)
       -- v26.62-frenada: una tanda FRENADA (dos operarios o dos tramos) se mide aparte, no en el puntaje
       and not exists (select 1 from public."GV_Tanda_Freno" fz where fz.tanda = t.tanda and fz.fase = 'picking')$a$,
                  $a$                    where e.opcion in ('TP','PKF') and e.ts_cliente = t.tp and e.legajo::text = t.legajo and upper(btrim(e.texto)) = t.tanda)
       -- v26.68-frenada (D17, Luis): una tanda FRENADA entra con la parte de cada uno (sus tramos, gv_picking_tanda_calc_frenada)$a$);
  n := replace(n, $a$'cero', g.lineas_cero, 'frac', g.m3_frac)$a$, $a$'cero', g.lineas_cero, 'frac', g.m3_frac, 'frenada', g.cola_tipo = 'frenada')$a$);
  if n = d or n not like '%v26.68-frenada%' or n not like '%''frenada'', g.cola_tipo = ''frenada''%' or n like '%fz.fase = ''picking''%' then
    raise exception 'gv_picking_puntaje_operario: el texto no matcheó';
  end if;
  execute n;
end $p$;

-- 4) centinelas (APLICADOS el 05/10: 304 actualizado, 316-319 nuevos) ------------------------
-- update public."GV_Reglas_Centinela" set patron = $p$e\.opcion in \('TP','PKF'\) and e\.ts_cliente = t\.tp$p$,
--   regla = 'D17: una tanda de picking FRENADA entra en el puntaje con la parte de cada uno (el TP vivo acepta el PKF del que frenó)',
--   quien_pidio = 'Luis (D17)', version = 'v26.68' where id = 304;
-- insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
--  ('gv_picking_tanda_calc_frenada','funcion', $p$x\.cola_min := 0; x\.real_min := x\.neto_sh$p$, 'D17: el tramo que termina en un FRENO no lleva cola; la espera hasta el freno se topea como la cola', 'Luis (D17)', 'v26.68'),
--  ('gv_picking_tanda_refresh','funcion', $p$gv_picking_tanda_calc_frenada\(t\.tanda, t\.leg\)$p$, 'D17: una tanda con freno de picking se mide por tramos y se suma por legajo', 'Luis (D17)', 'v26.68'),
--  ('gv_picking_tanda_calc','funcion', $p$current_setting\('gv\.pkc_desde', true\)$p$, 'D17: la ventana de PKC de un tramo de tanda frenada la fija calc_frenada, sin solaparse con el tramo vecino', 'Luis (D17)', 'v26.68'),
--  ('gv_picking_tanda_calc_frenada','funcion', $p$set_config\('gv\.pkc_desde', '', true\)$p$, 'D17: la ventana se limpia después de cada tramo (no se filtra al resto del refresco)', 'Luis (D17)', 'v26.68');

-- PRUEBA (05/10, transacción abortada con raise): F13E (104, 25 líneas, 188 cajas) partida en dos tramos con
-- el que retoma 1 MINUTO después del freno → A 13 líneas / 40 cajas · B 12 / 148 · A+B = 25 / 188 = la original
-- (sin el v26.68-ventana daba 17 + 12 = 29: las líneas del que retomó se contaban también en el que frenó).
-- La tanda sin freno quedó igual (F13E 25 líneas · real 22,6 · índice 1,573) y la ventana quedó limpia tras el cálculo.
-- Con legajos reales (104 frena, 277 termina) el puntaje trae ZZ99Z en el detalle de los DOS, con 'frenada': true.

-- Chequeo:
--   select tanda, legajo, lineas, tamano, real_min, indice, cola_tipo from public."GV_Picking_Tanda" where cola_tipo = 'frenada';
--   select * from public.gv_reglas_perdidas;   -- vacía

-- ROLLBACK:
--   gv_picking_puntaje_operario: reaplicar el replace al revés (opcion = 'TP' + el not exists de GV_Tanda_Freno) o
--     el CREATE completo de sql/gv_picking_puntaje_v2650.sql con el filtro de turno vivo y la línea v26.62-frenada.
--   gv_picking_tanda_refresh: el CREATE de sql/gv_picking_no_pickeado_v2651.sql (sólo TP).
--   gv_picking_tanda_calc: replace al revés de 1b) (vuelve el ±5 min fijo; sin calc_frenada no hay GUC fijado, así que es inocuo dejarlo).
--   drop function public.gv_picking_tanda_calc_frenada(text, text);   -- (SQL Editor: el MCP se cuelga con DROP)
--   delete from public."GV_Picking_Tanda" where cola_tipo = 'frenada';   -- las filas sumadas
