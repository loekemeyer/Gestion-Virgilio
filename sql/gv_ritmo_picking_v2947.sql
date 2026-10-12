-- v29.47 — RITMO DE PICKING: tiempo ESTIMADO por dificultad (antes de pickear) vs REAL (Thomas, 12/10, D4)
-- "Si es un metro cúbico de un picking ultra difícil, el ritmo va a ser peor que uno promedio …
--  que figure cuántas son las horas y qué rendimiento tuvieron en horas reales, acorde al
--  esperado que habíamos estimado de manera inicial. Todo calculado en el back."
--
-- Piezas:
--   1) gv_picking_estimar(tandas[])   — el tamaño D17 (min) de una tanda SIN pickear, con las
--      líneas del pedido (PPP_Web_Base / gv_ppp_base_pedidos) y el stock de góndola de AHORA
--      (stocks_carga_rapida) para elegir la altura. Misma fórmula y coeficientes que
--      gv_picking_tanda_calc (GV_Picking_Esquema): fijo + arranque + paradas + cajas + alturas.
--   2) GV_Picking_Estimado — la foto: tamano_inicial (la PRIMERA estimación, no se pisa nunca)
--      y tamano (la última antes del TP). Cron 155 gv-picking-estimar cada 10 min (06–20 ART).
--   3) GV_Plantel_Operario_Dia — horas del monitor por operario y día (la llena
--      gv_plantel_dia_refrescar, que ahora arma GV_Plantel_Dia desde acá).
--   4) gv_ritmo_picking(desde, hasta) — por día y operario: estimado inicial, esperado D17 (con
--      lo que de verdad pickeó), real neto (sin pausas ni huecos), horas del monitor, índice y si
--      llegó. SÓLO SUPERVISOR (es rendimiento por persona). Mon. Admin no la ve la TV.
--   5) gv_ppp_plantel: la hora de picking de lo pendiente se corrige por SU dificultad
--      (min estimados por m³ de lo pendiente ÷ min por m³ de la historia).
--
-- Rollback: cabecera de sql/gv_ppp_plantel_v2946.sql +
--   select cron.unschedule('gv-picking-estimar');
--   (y las funciones/tablas nuevas de este archivo)

-- 1) ─── estimador ───────────────────────────────────────────────────────────────────────────
create or replace function public.gv_picking_estimar(p_tandas text[] default null)
returns table(tanda text, nps int, m3 numeric, lineas int, cajas numeric, cajas30 numeric, paradas int,
              esc int, n_mx int, n_f int, tamano numeric, dificultad numeric, grado int, nivel text)
language plpgsql stable security definer set search_path = public as $$
declare
  c jsonb; v_tope numeric; v_karr numeric; v_dec numeric[];
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  select jsonb_object_agg(e.clave, e.valor) into c from public."GV_Picking_Esquema" e;
  if c is null then raise exception 'GV_Picking_Esquema vacía'; end if;
  v_tope := coalesce((c->>'tope_cajas_linea')::numeric, 30);
  v_karr := coalesce((c->>'arranque_lineas')::numeric, 5);
  v_dec  := array[(c->>'decil_1')::numeric,(c->>'decil_2')::numeric,(c->>'decil_3')::numeric,(c->>'decil_4')::numeric,(c->>'decil_5')::numeric,
                  (c->>'decil_6')::numeric,(c->>'decil_7')::numeric,(c->>'decil_8')::numeric,(c->>'decil_9')::numeric];
  return query
  with _e_np as materialized (
    select upper(btrim(ar.tanda)) tnd, ar.np, coalesce(ar.m3, 0) m3np, lower(coalesce(ar.empresa, '')) empr
      from public.gv_ppp_prog_arbol(v_hoy - 60, v_hoy + 90) ar
     where coalesce(ar.tanda, '') <> ''
       and ((p_tandas is null and ar.estado = 'pendiente') or upper(btrim(ar.tanda)) = any (p_tandas))
  ),
  _e_it0 as (
    select n.tnd, upper(btrim(w.articulo)) crudo, coalesce(w.cajas, 0)::numeric caj, n.empr
      from _e_np n join public."PPP_Web_Base" w on w.np_label = n.np
    union all
    select n.tnd, upper(btrim(b.articulo)), coalesce(b.cajas, 0)::numeric, n.empr
      from _e_np n join public.gv_ppp_base_pedidos b on b.pedido::text = n.np
     where not exists (select 1 from public."PPP_Web_Base" w2 where w2.np_label = n.np)
  ),
  _e_it as (
    select x.tnd,
           regexp_replace(regexp_replace(regexp_replace(x.crudo, '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           case when x.crudo ~ '[0-9E]L$' then 'LK'
                when x.crudo ~ '\s+(LK|CH)$' then substring(x.crudo from '\s+(LK|CH)$')
                when x.empr in ('chef', 'ch') then 'CH' else 'LK' end emp,
           sum(x.caj) re
      from _e_it0 x group by 1, 2, 3 having sum(x.caj) > 0
  ),
  _e_cods as (select distinct i.ck, i.emp from _e_it i),
  _e_cel as (
    select p.ck, p.emp, l.empresa lemp, substr(l.sector, 1, 1) g,
           regexp_replace(l.sector, '^\D+', '')::int num, coalesce(gi.cajas_max, 0) cap
      from _e_cods p
      join public."GV_Lugar_Item" gi on regexp_replace(upper(btrim(gi.cod)), '^0+(?=.)', '') = p.ck and coalesce(gi.activo, true)
      join public."GV_Lugar" l on l.sector = gi.sector and l.tipo = 'gondola' and coalesce(l.activo, true)
     where l.sector ~ '^[A-ZÑ][0-9]+$'
  ),
  _e_cel2 as (
    select * from (select z.*, bool_or(z.lemp = z.emp) over (partition by z.ck, z.emp) tiene from _e_cel z) q
     where not q.tiene or q.lemp = q.emp
  ),
  _e_capa as (
    select q.ck, q.emp, q.g, ((q.num - 1) % (case when q.g in ('A','P') then 5 else 4 end)) + 1 altura,
           sum(q.cap) cap, min((q.num - 1) / (case when q.g in ('A','P') then 5 else 4 end) + 1) modulo
      from _e_cel2 q group by 1, 2, 3, 4
  ),
  _e_una as (select q.ck, q.emp, count(distinct q.altura) nalt from _e_capa q group by 1, 2),
  _e_stk as (
    select p.ck, p.emp, coalesce(sum(s.terminado), 0) s
      from _e_cods p
      left join public.stocks_carga_rapida s
        on regexp_replace(upper(btrim(s.cod_base)), '^0+(?=.)', '') = p.ck
       and upper(btrim(s.linea)) in (select distinct c2.lemp from _e_cel2 c2 where c2.ck = p.ck and c2.emp = p.emp)
     group by 1, 2
  ),
  _e_asig as (
    select ca.*, coalesce(sum(ca.cap) over (partition by ca.ck, ca.emp order by ca.altura desc, ca.g
                   rows between unbounded preceding and 1 preceding), 0) arriba
      from _e_capa ca
  ),
  _e_eleg as (
    select distinct on (a.ck, a.emp) a.ck, a.emp, a.g, a.altura, a.modulo
      from _e_asig a join _e_stk s on s.ck = a.ck and s.emp = a.emp
     where s.s > a.arriba order by a.ck, a.emp, a.altura, a.g
  ),
  _e_baja as (select distinct on (q.ck, q.emp) q.ck, q.emp, q.g, q.altura, q.modulo from _e_asig q order by q.ck, q.emp, q.altura, q.g),
  _e_lin as (
    select i.tnd, i.ck, i.re,
           case when b.ck is null then 'F'
                when u.nalt = 1 then (case when b.g in ('A','P') then 'A' else 'R' end) || least(b.altura, case when b.g in ('A','P') then 5 else 4 end)::text
                when coalesce(s.s, 0) <= 0 or e.ck is null then 'MX'
                else (case when e.g in ('A','P') then 'A' else 'R' end) || least(e.altura, case when e.g in ('A','P') then 5 else 4 end)::text end clase,
           coalesce(e.g, b.g) g, coalesce(e.modulo, b.modulo) modulo
      from _e_it i
      left join _e_baja b on b.ck = i.ck and b.emp = i.emp
      left join _e_una  u on u.ck = i.ck and u.emp = i.emp
      left join _e_stk  s on s.ck = i.ck and s.emp = i.emp
      left join _e_eleg e on e.ck = i.ck and e.emp = i.emp
  ),
  _e_par as (
    select l.tnd, count(distinct case l.g
             when 'A' then case when l.modulo <= 14 then 'AB:' || l.modulo else 'AC:' || (l.modulo - 14) end
             when 'B' then 'AB:' || l.modulo  when 'C' then 'AC:' || l.modulo
             when 'E' then 'EG:' || l.modulo  when 'G' then 'EG:' || l.modulo
             when 'D' then 'DF:' || l.modulo  when 'F' then 'DF:' || l.modulo
             when 'H' then 'HJ:' || l.modulo  when 'J' then 'HJ:' || l.modulo
             when 'L' then 'LM:' || l.modulo  when 'M' then 'LM:' || l.modulo
             else l.g || ':' || l.modulo end) filter (where l.g is not null)::int n
      from _e_lin l group by 1
  ),
  _e_agg as (
    select l.tnd, count(*)::int n, sum(l.re) caj, sum(least(l.re, v_tope)) caj30,
           count(*) filter (where l.clase in ('A4','A5','R3','R4'))::int esc,
           count(*) filter (where l.clase = 'MX')::int nmx, count(*) filter (where l.clase = 'F')::int nf,
           coalesce(sum((c->>l.clase)::numeric), 0) alt
      from _e_lin l group by 1
  ),
  _e_tam as (
    select a.*, coalesce(pr.n, 0) par,
           (c->>'cfijo')::numeric + (c->>'arranque')::numeric * least(a.n, v_karr) / v_karr
             + (c->>'parada')::numeric * coalesce(pr.n, 0) + (c->>'caja')::numeric * a.caj30 + a.alt tam
      from _e_agg a left join _e_par pr on pr.tnd = a.tnd
  ),
  _e_m3 as (select n.tnd, count(*)::int nps, sum(n.m3np) m3 from _e_np n group by 1)
  select t.tnd, m.nps, round(m.m3, 3), t.n, t.caj, t.caj30, t.par, t.esc, t.nmx, t.nf, round(t.tam, 2),
         round(case when t.caj > 0 then (t.tam - (c->>'cfijo')::numeric - (c->>'arranque')::numeric * least(t.n, v_karr) / v_karr) / t.caj end, 4),
         x.gr,
         case when x.gr <= 2 then 'Baja' when x.gr <= 5 then 'Media' when x.gr <= 8 then 'Alta' else 'Muy alta' end
    from _e_tam t join _e_m3 m on m.tnd = t.tnd
    cross join lateral (select case when t.caj > 0 then 1 + (select count(*)::int from unnest(v_dec) d
                          where d < (t.tam - (c->>'cfijo')::numeric - (c->>'arranque')::numeric * least(t.n, v_karr) / v_karr) / t.caj)
                          else 10 end gr) x;
end $$;
grant execute on function public.gv_picking_estimar(text[]) to anon, authenticated;


-- 5) ─── gv_ppp_plantel con la hora de picking por dificultad ─────────────────────────────────
create or replace function public.gv_ppp_plantel(p_semana int default 1, p_semanas int default 4,
                                                 p_meta int default 10, p_dias_antes int default 2)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_lun date; v_ini date; v_fin date; v_hab int; v_hab_antes int;
  v_hist_desde date; v_hist_hasta date;
  h record; v_dem numeric; v_back jsonb; v_pend record;
  v_rpick numeric; v_rarm numeric; v_m3dia_pick numeric; v_m3dia_arm numeric;
  v_a_pick numeric; v_a_arm numeric; v_b numeric;
  v_dias jsonb;
  v_est_hist numeric; v_f numeric; v_hpm3 numeric; v_ob_min numeric; v_h_ob numeric; v_h_na numeric; v_h_pick numeric;
begin
  v_lun := date_trunc('week', v_hoy)::date + 7 * greatest(least(coalesce(p_semana, 1), 4), 0);
  v_ini := case when coalesce(p_semana, 1) <= 0 then v_hoy else v_lun end;
  v_fin := v_lun + 4;
  select count(*)::int into v_hab from generate_series(v_ini, v_fin, interval '1 day') g where public.gv_es_dia_habil(g::date);
  select count(*)::int into v_hab_antes from generate_series(v_hoy, v_ini - 1, interval '1 day') g where public.gv_es_dia_habil(g::date);
  v_hist_hasta := v_hoy - 1;
  v_hist_desde := v_hoy - 7 * greatest(coalesce(p_semanas, 4), 1);

  select count(*) filter (where ops > 0) dias, coalesce(sum(ops), 0) ops_dias,
         coalesce(sum(hs_pick), 0) hpick, coalesce(sum(hs_arm), 0) harm, coalesce(sum(hs_carga), 0) hcarga,
         coalesce(sum(hs_mov), 0) hmov, coalesce(sum(hs_noprod), 0) hnoprod, coalesce(sum(hs_total), 0) htotal,
         coalesce(sum(m3_pick), 0) m3pick, coalesce(sum(m3_arm), 0) m3arm, max(calculado_at) calc
    into h
    from public."GV_Plantel_Dia" where dia between v_hist_desde and v_hist_hasta and ops > 0;

  v_rpick := case when h.hpick > 0 then h.m3pick / h.hpick end;
  v_rarm  := case when h.harm  > 0 then h.m3arm  / h.harm  end;
  v_m3dia_pick := case when h.dias > 0 then h.m3pick / h.dias else 0 end;
  v_m3dia_arm  := case when h.dias > 0 then h.m3arm  / h.dias else 0 end;

  -- lo que entra: m³ por fecha del pedido (web), en las semanas completas de la historia
  select coalesce(sum(p.m3), 0) / greatest(coalesce(p_semanas, 4), 1) into v_dem
    from public."PPP_Web_Programacion" p
    left join public.lk_pedidos_match lp on lp.empresa = p.empresa and lp.order_id::text = p.order_id::text
   where coalesce(lp.fecha_pedido::date, p.creado_at::date) >= date_trunc('week', v_hoy)::date - 7 * greatest(coalesce(p_semanas, 4), 1)
     and coalesce(lp.fecha_pedido::date, p.creado_at::date) <  date_trunc('week', v_hoy)::date;

  -- lo pendiente: programado, sin pickear (pendiente) o sin terminar de armar (pendiente + proceso).
  -- Calendario de hábiles UNA vez (gv_es_dia_habil por fila costaba 2,9 s).
  with cal as materialized (
    select g::date d, row_number() over (order by g)::int i
      from generate_series(v_hoy - 150, v_hoy + 150, interval '1 day') g where public.gv_es_dia_habil(g::date)
  ), a as (
    select ar.np, ar.tanda, ar.m3, ar.estado, ar.fecha, ar.fecha_pedido,
           (select min(c.i) from cal c where c.d > ar.fecha_pedido) + p_meta - 1 i_salida
      from public.gv_ppp_prog_arbol(v_hoy - 60, v_hoy + 90) ar
     where ar.estado in ('pendiente', 'proceso') and coalesce(ar.m3, 0) > 0
  ), b as (
    select a.*, (select c.d from cal c where c.i = a.i_salida - greatest(p_dias_antes, 0)) limite_armado,
           -- v29.47: los minutos estimados por dificultad (D17) de su tanda, prorrateados por m³
           (select ge.tamano * a.m3 / nullif(ge.m3, 0) from public."GV_Picking_Estimado" ge
             where ge.tanda = upper(btrim(a.tanda))) est_min
      from a
  )
  select coalesce(sum(m3) filter (where estado = 'pendiente'), 0) m3_pick,
         coalesce(sum(m3), 0) m3_arm,
         count(*) nps, count(distinct tanda) tandas,
         coalesce(sum(m3) filter (where estado = 'pendiente' and limite_armado <= v_fin), 0) oblig_pick,
         coalesce(sum(m3) filter (where limite_armado <= v_fin), 0) oblig_arm,
         coalesce(sum(est_min) filter (where estado = 'pendiente' and limite_armado <= v_fin), 0) oblig_pick_min,
         coalesce(sum(m3) filter (where estado = 'pendiente' and limite_armado <= v_fin and est_min is null), 0) oblig_pick_sin_est,
         coalesce(sum(m3) filter (where estado = 'pendiente' and limite_armado <= v_fin and est_min is not null), 0) oblig_pick_con_est,
         coalesce(sum(m3) filter (where limite_armado < v_hoy), 0) m3_vencido,
         count(*) filter (where limite_armado < v_hoy) nps_vencidas,
         min(fecha_pedido) pedido_mas_viejo,
         (select count(*) from cal c where c.d > min(b.fecha_pedido) and c.d <= v_hoy) habiles_mas_viejo,
         max(fecha) ultima_fecha_prog,
         jsonb_agg(jsonb_build_object('semana', date_trunc('week', limite_armado)::date,
                                      'm3', m3, 'pick', estado = 'pendiente') ) det
    into v_pend from b;

  select coalesce(jsonb_agg(jsonb_build_object('semana', s, 'm3_arm', m3a, 'm3_pick', m3p) order by s), '[]'::jsonb)
    into v_back
    from (select (x->>'semana')::date s, round(sum((x->>'m3')::numeric), 2) m3a,
                 round(coalesce(sum((x->>'m3')::numeric) filter (where (x->>'pick')::boolean), 0), 2) m3p
            from jsonb_array_elements(coalesce(v_pend.det, '[]'::jsonb)) x group by 1) z;

  -- semana futura: lo que se hace antes, al ritmo de hoy, sale primero de lo obligatorio
  v_a_pick := greatest(v_pend.oblig_pick - v_hab_antes * v_m3dia_pick, 0);
  v_a_arm  := greatest(v_pend.oblig_arm  - v_hab_antes * v_m3dia_arm, 0);
  v_b := v_dem * v_hab / 5.0;

  -- v29.47 — PICKING POR DIFICULTAD. Minutos estimados (D17, antes de pickear) de lo obligatorio, × F:
  -- F = horas reales de picking del monitor ÷ minutos estimados de las tandas pickeadas en la historia
  -- (el mismo estimador de los dos lados: corrige pausas, huecos, cola y el sesgo del modelo).
  select coalesce(sum(e.tamano_inicial), 0) into v_est_hist
    from public."GV_Picking_Estimado" e
   where e.tanda in (select t.tanda from public."GV_Picking_Tanda" t
                      where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_hist_desde and v_hist_hasta);
  v_f := case when v_est_hist > 0 then h.hpick * 60 / v_est_hist end;
  v_hpm3 := case when h.m3pick > 0 then h.hpick / h.m3pick end;                 -- h por m³ medido (sin dificultad)
  v_ob_min := greatest(v_pend.oblig_pick_min
                       - v_hab_antes * (case when h.dias > 0 then v_est_hist / h.dias else 0 end), 0);   -- lo que se hace antes
  v_h_ob := case when v_f is not null then v_ob_min * v_f / 60
                      + coalesce(v_pend.oblig_pick_sin_est, 0) * coalesce(v_hpm3, 0) end;          -- sin estimado: al promedio
  v_h_na := v_b * coalesce(v_hpm3, 0);                                                            -- lo que entra: al promedio
  v_h_pick := greatest(coalesce(v_h_ob, v_a_pick * coalesce(v_hpm3, 0)), v_h_na);

  select coalesce(jsonb_agg(jsonb_build_object('dia', g::date, 'habil', public.gv_es_dia_habil(g::date)) order by g), '[]'::jsonb)
    into v_dias from generate_series(v_lun, v_fin, interval '1 day') g;

  return jsonb_build_object(
    'hoy', v_hoy, 'lunes', v_lun, 'desde', v_ini, 'hasta', v_fin, 'habiles', v_hab, 'dias', v_dias,
    'habiles_antes', v_hab_antes, 'meta', p_meta, 'dias_antes', p_dias_antes,
    'hist', jsonb_build_object('desde', v_hist_desde, 'hasta', v_hist_hasta, 'dias', h.dias,
        'ops_dia', round(case when h.dias > 0 then h.ops_dias::numeric / h.dias end, 1),
        'hs_pick', round(h.hpick, 1), 'hs_arm', round(h.harm, 1), 'hs_carga', round(h.hcarga, 1),
        'hs_mov', round(h.hmov, 1), 'hs_noprod', round(h.hnoprod, 1), 'hs_total', round(h.htotal, 1),
        'm3_pick', round(h.m3pick, 2), 'm3_arm', round(h.m3arm, 2),
        'ritmo_pick', round(v_rpick, 3), 'ritmo_arm', round(v_rarm, 3),
        'carga_dia', round(case when h.dias > 0 then h.hcarga / h.dias end, 2),
        'mov_dia', round(case when h.dias > 0 then h.hmov / h.dias end, 2),
        'util_persona_dia', round(case when h.ops_dias > 0 then (h.hpick + h.harm + h.hcarga + h.hmov) / h.ops_dias end, 2),
        'jornada_persona_dia', round(case when h.ops_dias > 0 then h.htotal / h.ops_dias end, 2),
        'm3_dia_pick', round(v_m3dia_pick, 2), 'm3_dia_arm', round(v_m3dia_arm, 2),
        'calculado', h.calc),
    'demanda_semana', round(v_dem, 2),
    'pendiente', jsonb_build_object('m3_pick', round(v_pend.m3_pick, 2), 'm3_arm', round(v_pend.m3_arm, 2),
        'nps', v_pend.nps, 'tandas', v_pend.tandas, 'm3_vencido', round(v_pend.m3_vencido, 2),
        'nps_vencidas', v_pend.nps_vencidas, 'pedido_mas_viejo', v_pend.pedido_mas_viejo,
        'habiles_mas_viejo', v_pend.habiles_mas_viejo, 'ultima_fecha_prog', v_pend.ultima_fecha_prog,
        'por_semana_limite', v_back),
    'semana', jsonb_build_object(
        'oblig_pick', round(v_a_pick, 2), 'oblig_arm', round(v_a_arm, 2), 'no_acumular', round(v_b, 2),
        'm3_pick', round(greatest(v_a_pick, v_b), 2), 'm3_arm', round(greatest(v_a_arm, v_b), 2),
        'horas_pick', round(v_h_pick, 2), 'horas_pick_oblig', round(v_h_ob, 2), 'horas_pick_noacum', round(v_h_na, 2),
        'factor_real', round(v_f, 3), 'oblig_pick_min_est', round(v_ob_min, 1),
        'min_m3_est_oblig', round(v_pend.oblig_pick_min / nullif(v_pend.oblig_pick_con_est, 0), 1),
        'min_m3_est_hist', round(v_est_hist / nullif(h.m3pick, 0), 1),
        'oblig_pick_sin_est_m3', round(v_pend.oblig_pick_sin_est, 2))
  );
end $$;
grant execute on function public.gv_ppp_plantel(int, int, int, int) to anon, authenticated;

-- 2) ─── la foto del estimado ─────────────────────────────────────────────────────────────────
create table if not exists public."GV_Picking_Estimado" (
  tanda text primary key,
  nps int, m3 numeric, lineas int, cajas numeric, paradas int, esc int, n_mx int, n_f int,
  tamano numeric, grado int, nivel text,                                              -- la ÚLTIMA antes del TP
  tamano_inicial numeric, grado_inicial int, nivel_inicial text, m3_inicial numeric,  -- la PRIMERA (no se pisa)
  estimado_inicial_at timestamptz not null default now(),
  estimado_at timestamptz not null default now(),
  reconstruido boolean not null default false   -- true = tanda ya pickeada al 12/10, estimada después (backfill)
);
alter table public."GV_Picking_Estimado" enable row level security;   -- sin policy: sólo las funciones

create or replace function public.gv_picking_estimar_snapshot()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public."GV_Picking_Estimado" as g (tanda, nps, m3, lineas, cajas, paradas, esc, n_mx, n_f, tamano, grado, nivel,
         tamano_inicial, grado_inicial, nivel_inicial, m3_inicial, estimado_inicial_at, estimado_at)
  select e.tanda, e.nps, e.m3, e.lineas, e.cajas, e.paradas, e.esc, e.n_mx, e.n_f, e.tamano, e.grado, e.nivel,
         e.tamano, e.grado, e.nivel, e.m3, now(), now()
    from public.gv_picking_estimar(null) e
   where not exists (select 1 from public."GV_Picking_Tanda" t where t.tanda = e.tanda)
  on conflict (tanda) do update set nps = excluded.nps, m3 = excluded.m3, lineas = excluded.lineas, cajas = excluded.cajas,
     paradas = excluded.paradas, esc = excluded.esc, n_mx = excluded.n_mx, n_f = excluded.n_f,
     tamano = excluded.tamano, grado = excluded.grado, nivel = excluded.nivel, estimado_at = now()
   where not g.reconstruido;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.gv_picking_estimar_snapshot() from public, anon, authenticated;

-- backfill (12/10): las tandas pickeadas en 35 días, estimadas con sus líneas y el stock de hoy → reconstruido = true
-- insert … select … from public.gv_picking_estimar((select array_agg(tanda) from GV_Picking_Tanda tp ≥ hoy−35)) … reconstruido true  (182 tandas)

select cron.schedule('gv-picking-estimar', '8-58/10 9-23 * * *',   -- jobid 155
  $c$do $b$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_picking_estimar_snapshot')::bigint) then
       perform public.gv_picking_estimar_snapshot(); end if; end $b$;$c$);

-- 3) ─── horas del monitor por operario y día ───────────────────────────────────────────────
create table if not exists public."GV_Plantel_Operario_Dia" (
  dia date not null, legajo text not null, nombre text,
  hs_pick numeric not null default 0, hs_arm numeric not null default 0, hs_carga numeric not null default 0,
  hs_mov numeric not null default 0, hs_noprod numeric not null default 0, hs_total numeric not null default 0,
  calculado_at timestamptz not null default now(), primary key (dia, legajo)
);
alter table public."GV_Plantel_Operario_Dia" enable row level security;   -- sin policy: sólo las funciones
-- gv_plantel_dia_refrescar: ahora borra y rearma GV_Plantel_Operario_Dia del día (execute 'de'||'lete …', por el MCP)
-- y GV_Plantel_Dia sale de esa foto (mismas columnas que v29.46). Definición viva: pg_get_functiondef.

-- 4) ─── Ritmo de picking (Monitor → Ritmo) ─────────────────────────────────────────────────
-- esperado = tamaño D17 con lo que de verdad pickeó · estimado inicial = la 1.ª foto antes de pickear,
-- prorrateada por legajo en una tanda frenada · real = neto (sin pausas ni huecos > 5 min, cola ≤ 30)
-- · monitor = horas de picking de gv_monitor_horas_operario_dia (hoy en vivo). índice = esperado ÷ real.
create or replace function public.gv_ritmo_picking(p_desde date default null, p_hasta date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_desde date := coalesce(p_desde, (now() at time zone 'America/Argentina/Buenos_Aires')::date - 13);
  v_hasta date := least(coalesce(p_hasta, (now() at time zone 'America/Argentina/Buenos_Aires')::date), (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  v_filas jsonb; v_dias jsonb; v_tot jsonb; v_ops jsonb;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: el ritmo por operario es sólo para supervisores';
  end if;
  if v_hasta - v_desde > 62 then v_desde := v_hasta - 62; end if;

  with _r_pt as (
    select t.tanda, t.legajo, (t.tp at time zone 'America/Argentina/Buenos_Aires')::date dia,
           t.tamano, t.real_min, t.lineas, t.cajas, t.grado, t.nivel,
           (t.real_min between 0.5 and 240 and t.lineas > 0 and t.bruto_min <= 720) medible
      from public."GV_Picking_Tanda" t
     where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_desde and v_hasta
       and t.legajo not in ('0', '1')
  ), _r_sum as (select p.tanda, sum(p.tamano) tam_t from _r_pt p group by 1),
  _r_x as (
    select p.*, e.tamano_inicial * p.tamano / nullif(s.tam_t, 0) est_ini, coalesce(e.reconstruido, true) recon,
           e.tamano_inicial is not null tiene_ini
      from _r_pt p join _r_sum s using (tanda)
      left join public."GV_Picking_Estimado" e on e.tanda = p.tanda
  ), _r_mon as (
    select o.dia, o.legajo, o.nombre, o.hs_pick from public."GV_Plantel_Operario_Dia" o
     where o.dia between v_desde and v_hasta and o.dia < v_hoy
    union all
    select v_hoy, x.legajo, x.nombre, x.hs_pick from public.gv_monitor_horas_operario_dia(v_hoy) x
     where v_hoy between v_desde and v_hasta and x.legajo not in ('0', '1') and x.legajo !~ '^sup:'
  ), _r_g as (
    select coalesce(x.dia, m.dia) dia, coalesce(x.legajo, m.legajo) legajo,
           max(m.nombre) nombre, max(m.hs_pick) hs_mon,
           count(x.tanda) tandas, count(x.tanda) filter (where x.medible) medibles,
           sum(x.tamano) filter (where x.medible) esperado, sum(x.real_min) filter (where x.medible) real_,
           sum(x.est_ini) filter (where x.medible and x.tiene_ini) est_ini,
           sum(x.real_min) filter (where x.medible and x.tiene_ini) real_ini,
           bool_or(x.recon) filter (where x.tiene_ini) recon
      from _r_x x full join _r_mon m on m.dia = x.dia and m.legajo = x.legajo
     group by 1, 2
  ), _r_f as (
    select g.*, coalesce(g.nombre, (select max(e."Empleado") from public."Empleados" e where e."Legajo"::text = g.legajo)) nom
      from _r_g g where g.tandas > 0 or coalesce(g.hs_mon, 0) > 0.05
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'dia', f.dia, 'legajo', f.legajo, 'nombre', f.nom, 'tandas', f.tandas, 'medibles', f.medibles,
           'est_ini_min', round(f.est_ini, 1), 'esperado_min', round(f.esperado, 1), 'real_min', round(f.real_, 1),
           'real_ini_min', round(f.real_ini, 1), 'mon_min', round(f.hs_mon * 60, 1),
           'indice', round(f.esperado / nullif(f.real_, 0), 3), 'indice_ini', round(f.est_ini / nullif(f.real_ini, 0), 3),
           'perdida_min', round(f.hs_mon * 60 - f.real_, 1), 'indice_mon', round(f.esperado / nullif(f.hs_mon * 60, 0), 3),
           'llego', (f.esperado / nullif(f.real_, 0)) >= 1, 'reconstruido', f.recon)
           order by f.dia desc, f.esperado desc nulls last), '[]'::jsonb)
    into v_filas from _r_f f;

  select coalesce(jsonb_agg(d order by (d->>'dia') desc), '[]'::jsonb) into v_dias
    from (select jsonb_build_object('dia', z.dia, 'ops', count(*) filter (where (z.x->>'tandas')::int > 0),
                 'tandas', sum((z.x->>'tandas')::int),
                 'est_ini_min', round(sum((z.x->>'est_ini_min')::numeric), 1), 'esperado_min', round(sum((z.x->>'esperado_min')::numeric), 1),
                 'real_min', round(sum((z.x->>'real_min')::numeric), 1), 'real_ini_min', round(sum((z.x->>'real_ini_min')::numeric), 1),
                 'mon_min', round(sum((z.x->>'mon_min')::numeric), 1),
                 'indice', round(sum((z.x->>'esperado_min')::numeric) / nullif(sum((z.x->>'real_min')::numeric), 0), 3),
                 'indice_ini', round(sum((z.x->>'est_ini_min')::numeric) / nullif(sum((z.x->>'real_ini_min')::numeric), 0), 3),
                 'indice_mon', round(sum((z.x->>'esperado_min')::numeric) / nullif(sum((z.x->>'mon_min')::numeric), 0), 3)) d
            from (select (x->>'dia')::date dia, x from jsonb_array_elements(v_filas) x) z group by z.dia) q;

  select jsonb_build_object('tandas', sum((x->>'tandas')::int),
           'est_ini_min', round(sum((x->>'est_ini_min')::numeric), 1), 'esperado_min', round(sum((x->>'esperado_min')::numeric), 1),
           'real_min', round(sum((x->>'real_min')::numeric), 1), 'real_ini_min', round(sum((x->>'real_ini_min')::numeric), 1),
           'mon_min', round(sum((x->>'mon_min')::numeric), 1),
           'indice', round(sum((x->>'esperado_min')::numeric) / nullif(sum((x->>'real_min')::numeric), 0), 3),
           'indice_ini', round(sum((x->>'est_ini_min')::numeric) / nullif(sum((x->>'real_ini_min')::numeric), 0), 3),
           'indice_mon', round(sum((x->>'esperado_min')::numeric) / nullif(sum((x->>'mon_min')::numeric), 0), 3))
    into v_tot from jsonb_array_elements(v_filas) x;

  select coalesce(jsonb_agg(o order by (o->>'esperado_min')::numeric desc nulls last), '[]'::jsonb) into v_ops
    from (select jsonb_build_object('legajo', z.leg, 'nombre', max(z.x->>'nombre'), 'dias', count(*),
                 'tandas', sum((z.x->>'tandas')::int),
                 'est_ini_min', round(sum((z.x->>'est_ini_min')::numeric), 1), 'esperado_min', round(sum((z.x->>'esperado_min')::numeric), 1),
                 'real_min', round(sum((z.x->>'real_min')::numeric), 1), 'real_ini_min', round(sum((z.x->>'real_ini_min')::numeric), 1),
                 'mon_min', round(sum((z.x->>'mon_min')::numeric), 1),
                 'perdida_min', round(sum((z.x->>'mon_min')::numeric) - coalesce(sum((z.x->>'real_min')::numeric), 0), 1),
                 'indice', round(sum((z.x->>'esperado_min')::numeric) / nullif(sum((z.x->>'real_min')::numeric), 0), 3),
                 'indice_ini', round(sum((z.x->>'est_ini_min')::numeric) / nullif(sum((z.x->>'real_ini_min')::numeric), 0), 3),
                 'indice_mon', round(sum((z.x->>'esperado_min')::numeric) / nullif(sum((z.x->>'mon_min')::numeric), 0), 3),
                 'dias_llego', count(*) filter (where (z.x->>'llego')::boolean),
                 'dias_medidos', count(*) filter (where z.x->>'llego' is not null)) o
            from (select x->>'legajo' leg, x from jsonb_array_elements(v_filas) x) z group by z.leg) q;
  return jsonb_build_object('desde', v_desde, 'hasta', v_hasta, 'hoy', v_hoy, 'filas', v_filas, 'dias', v_dias,
                            'operarios', v_ops, 'total', v_tot);
end $$;
revoke all on function public.gv_ritmo_picking(date, date) from public, anon;
grant execute on function public.gv_ritmo_picking(date, date) to authenticated;
