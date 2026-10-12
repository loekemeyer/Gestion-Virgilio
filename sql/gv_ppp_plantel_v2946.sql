-- v29.46 — PLANTEL DE LA SEMANA (PPP → 👷 Plantel)
-- Pedido: "cuántas horas necesito para pickear y cuántas para armar, y cuántas van fijo a otras
-- tareas (carga de camión…), para armar un plantel lógico de una semana entera, sin pasar los
-- 10 días hábiles de demora".
--
-- Tres piezas:
--   1) GV_Plantel_Dia      — caché por día de las horas reales (gv_monitor_horas_operario_dia,
--                            3,3 s por 28 días: no se puede recalcular en cada apertura) y del
--                            m³ pickeado / armado ese día (TP / TAP).
--   2) gv_plantel_dia_refrescar(desde, hasta) — llena la caché. Cron diario 04:50 ART (últimos 3 días).
--   3) gv_ppp_plantel(semana, semanas_hist, meta_habiles, dias_antes) — jsonb para la pantalla.
--
-- Rollback:
--   select cron.unschedule('gv-plantel-dia');
--   drop function if exists public.gv_ppp_plantel(int,int,int,int);
--   drop function if exists public.gv_plantel_dia_refrescar(date,date);
--   drop function if exists public.gv_habil_mas(date,int);
--   drop table if exists public."GV_Plantel_Dia";

create table if not exists public."GV_Plantel_Dia" (
  dia          date primary key,
  ops          int     not null default 0,
  hs_pick      numeric not null default 0,
  hs_arm       numeric not null default 0,
  hs_carga     numeric not null default 0,   -- CC + CR + RR (hs_prod − pick − arm)
  hs_mov       numeric not null default 0,   -- guardado, recepción, racks, insumos, mover…
  hs_noprod    numeric not null default 0,   -- baño, comida, permisos, cancelaciones
  hs_total     numeric not null default 0,   -- jornada (incluye tiempo muerto)
  m3_pick      numeric not null default 0,   -- m³ de las tandas con su 1.er TP ese día (pickeado)
  m3_arm       numeric not null default 0,   -- m³ de las tandas con su 1.er TAP ese día
  tandas_pick  int     not null default 0,
  tandas_arm   int     not null default 0,
  calculado_at timestamptz not null default now()
);
alter table public."GV_Plantel_Dia" enable row level security;
revoke insert, update, delete, truncate on public."GV_Plantel_Dia" from anon, authenticated;
grant select on public."GV_Plantel_Dia" to anon, authenticated;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'GV_Plantel_Dia' and policyname = 'gv_plantel_dia_sel') then
    create policy gv_plantel_dia_sel on public."GV_Plantel_Dia" for select using (true);
  end if;
end $$;

-- el n-ésimo día hábil DESPUÉS de d (n = 0 → d mismo si es hábil, si no el próximo)
create or replace function public.gv_habil_mas(p_d date, p_n int)
returns date language sql stable security definer set search_path = public as $$
  select g::date from generate_series(p_d + case when p_n <= 0 then 0 else 1 end,
                                      p_d + greatest(p_n, 0) * 3 + 40, interval '1 day') g
   where public.gv_es_dia_habil(g::date)
   order by g limit 1 offset greatest(p_n, 1) - 1
$$;

create or replace function public.gv_plantel_dia_refrescar(p_desde date default current_date - 3,
                                                           p_hasta date default current_date - 1)
returns int language plpgsql security definer set search_path = public as $$
declare d date; n int := 0;
begin
  for d in select g::date from generate_series(p_desde, p_hasta, interval '1 day') g loop
    insert into public."GV_Plantel_Dia" as t (dia, ops, hs_pick, hs_arm, hs_carga, hs_mov, hs_noprod, hs_total,
                                              m3_pick, m3_arm, tandas_pick, tandas_arm, calculado_at)
    select d, h.ops, h.pick, h.arm, h.carga, h.mov, h.noprod, h.total,
           coalesce(m.m3_pick, 0), coalesce(m.m3_arm, 0), coalesce(m.t_pick, 0), coalesce(m.t_arm, 0), now()
      from (select count(*)::int ops,
                   coalesce(sum(x.hs_pick), 0) pick, coalesce(sum(x.hs_arm), 0) arm,
                   coalesce(sum(greatest(x.hs_prod - x.hs_pick - x.hs_arm, 0)), 0) carga,
                   coalesce(sum(x.hs_mov), 0) mov, coalesce(sum(x.hs_noprod), 0) noprod,
                   coalesce(sum(x.hs_total), 0) total
              from public.gv_monitor_horas_operario_dia(d) x
             where x.legajo not in ('0', '1') and x.legajo !~ '^sup:' and coalesce(x.hs_total, 0) > 0) h
      left join (
        select sum(v.m3) filter (where e.opcion = 'TP')  m3_pick,
               sum(v.m3) filter (where e.opcion = 'TAP') m3_arm,
               count(*) filter (where e.opcion = 'TP')::int  t_pick,
               count(*) filter (where e.opcion = 'TAP')::int t_arm
          from (select opcion, upper(btrim(texto)) tanda,
                       min((coalesce(ts_inicio, ts_cliente) at time zone 'America/Argentina/Buenos_Aires')::date) d1
                  from public."Registros_Produccion_Virgilio"
                 where opcion in ('TP', 'TAP') and legajo not in ('0', '1')
                   and ts_cliente >= (d - 40)::timestamp and ts_cliente < (d + 2)::timestamp
                 group by 1, 2) e
          join public.vista_tanda_m3 v on upper(btrim(v.tanda)) = e.tanda
         where e.d1 = d) m on true
    on conflict (dia) do update set ops = excluded.ops, hs_pick = excluded.hs_pick, hs_arm = excluded.hs_arm,
      hs_carga = excluded.hs_carga, hs_mov = excluded.hs_mov, hs_noprod = excluded.hs_noprod,
      hs_total = excluded.hs_total, m3_pick = excluded.m3_pick, m3_arm = excluded.m3_arm,
      tandas_pick = excluded.tandas_pick, tandas_arm = excluded.tandas_arm, calculado_at = now();
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.gv_plantel_dia_refrescar(date, date) from public, anon, authenticated;

/* gv_ppp_plantel — todo lo que muestra la pantalla, en una llamada.
   p_semana:      0 = esta semana (desde hoy), 1 = la próxima, 2 = la siguiente.
   p_semanas:     cuántas semanas de historia para los ritmos y las horas fijas (4).
   p_meta:        días hábiles máximos de demora, del pedido a la salida (10).
   p_dias_antes:  hábiles entre el armado y la salida (armar → facturar → salir = 2).

   Lo que hay que hacer en la semana sale de DOS cuentas, y se toma la mayor:
     · NO VENCER: lo pendiente (programado, sin pickear / sin armar) cuyo límite de armado
       (fecha del pedido + meta hábiles − días antes) cae antes del fin de la semana. Para
       una semana futura se le descuenta lo que se va a hacer antes, al ritmo de hoy.
     · NO ACUMULAR: lo que entra por semana (m³ de pedidos por fecha del pedido, promedio).
   Horas = m³ ÷ m³/h medido. Las tareas fijas (carga + remitos, movimiento) son el promedio
   por día hábil × los hábiles de la semana. Personas = horas ÷ (horas útiles por persona por
   día × hábiles). Las horas útiles son las medidas (prod + mov por persona-día), no la jornada. */
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
    select a.*, (select c.d from cal c where c.i = a.i_salida - greatest(p_dias_antes, 0)) limite_armado from a
  )
  select coalesce(sum(m3) filter (where estado = 'pendiente'), 0) m3_pick,
         coalesce(sum(m3), 0) m3_arm,
         count(*) nps, count(distinct tanda) tandas,
         coalesce(sum(m3) filter (where estado = 'pendiente' and limite_armado <= v_fin), 0) oblig_pick,
         coalesce(sum(m3) filter (where limite_armado <= v_fin), 0) oblig_arm,
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
        'm3_pick', round(greatest(v_a_pick, v_b), 2), 'm3_arm', round(greatest(v_a_arm, v_b), 2))
  );
end $$;
grant execute on function public.gv_ppp_plantel(int, int, int, int) to anon, authenticated;

select public.gv_plantel_dia_refrescar(current_date - 63, current_date - 1);

-- cron diario 04:50 ART (07:50 UTC), anti-solape
select cron.schedule('gv-plantel-dia', '50 7 * * *',
  $c$do $b$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_plantel_dia_refrescar')::bigint) then
       perform public.gv_plantel_dia_refrescar(current_date - 3, current_date - 1); end if; end $b$;$c$);
