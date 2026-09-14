-- v16.97 (2026-09-14) — AVANCE DEL DÍA: % listo (picking terminado) y % armado (TAP).
-- Pedido de Thomas: "que se vea en la PPP el porcentaje de estado de los pedidos para un solo
-- día — 85 % listo, 60 % armado — y que eso también se mande por Telegram [a las 16:00], cosa
-- que se puede ver si ya se llegó al total de lo que se tenía que armar para ese día con
-- antelación, no a último minuto"; y "que a las 16 le aparezca en Planify a Marianela, de la
-- misma manera que la recepción de remitos del tallerista al sector de Pagos, que le diga tal
-- porcentaje listo, cosa de que sea imposible que no lo vea, a pesar de que no lea Telegram o
-- que no se metan a la PPP".
--
-- Backend, no front (PROTOCOLO: la regla de negocio vive acá). El front lee el mismo número
-- por RPC para que la PPP, el Telegram y la tarea de Planify no puedan discrepar.
--
-- QUÉ ES CADA COSA
--   listo  = la tanda del pedido tiene el PICKING TERMINADO (último evento EP/TP de esa tanda
--            es TP). Incluye lo que ya está armando o armado: si se está armando, el picking
--            terminó. Es lo que la PPP llama "Picking ✓".
--   armado = la tanda tiene TAP (último evento AP/TAP es TAP), o el pedido ya está cargado al
--            camión (gv_ppp_en_salida) o entregado (gv_ppp_entregados): si salió, se armó,
--            aunque nadie haya tocado el TAP.
--   El % principal va por m³ (es el volumen de trabajo del día, la misma unidad del cupo); si
--   el día no tiene m³ cargados, cae a contar pedidos. Los dos porcentajes se devuelven igual.
--
-- UNIVERSO DEL DÍA = todos los pedidos con esa fecha de entrega, vengan de ISIS
-- (gv_ppp_programacion_diaria) o de la web (PPP_Web_Programacion), MÁS los que ya salieron de
-- la programación porque se cargaron (gv_ppp_en_salida) o se entregaron (gv_ppp_entregados).
-- Sin esos dos, el denominador se achicaría al despachar y el % mentiría: 10 de 20 entregados
-- y 10 sin armar daría 0 %, cuando el día va por la mitad.
-- Dedup por NP (las NP web ya vienen etiquetadas "LK 0057" en las cuatro fuentes).
--
-- Legajos 0 y 1 (Pruebas) no marcan estado, igual que en getActivityStatus() del front.
--
-- ROLLBACK al final del archivo.

-- ── 1. el cálculo, por rango de días (una fila por día) ────────────────────
-- % entero, con el tope del 99 mientras falte algo (ver la nota en el select de abajo).
create or replace function public.gv_pct(p_parte numeric, p_total numeric)
returns int language sql immutable parallel safe as $$
  select case when coalesce(p_total, 0) <= 0 then 0
              when p_parte >= p_total then 100
              else least(99, greatest(0, round(100 * p_parte / p_total)::int)) end;
$$;
grant execute on function public.gv_pct(numeric, numeric) to anon, authenticated, service_role;

create or replace function public.gv_ppp_avance_dias(p_desde date, p_hasta date)
returns table (
  fecha           date,
  pedidos         int,
  m3              numeric,
  pick_ped        int,
  pick_m3         numeric,
  arm_ped         int,
  arm_m3          numeric,
  curso_ped       int,
  sin_ped         int,
  pct_listo       int,
  pct_armado      int,
  pct_listo_ped   int,
  pct_armado_ped  int,
  pct_listo_m3    int,
  pct_armado_m3   int,
  base            text
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
with fuentes as (
  select 1 as pri,
         regexp_replace(btrim(p.np), '\.0+$', '')            as np,
         upper(btrim(coalesce(p.tanda, '')))                 as tanda,
         coalesce(p.m3, 0)::numeric                          as m3,
         nullif(left(btrim(p.fecha_entrega), 10), '')::date  as fe
    from public.gv_ppp_programacion_diaria p
   where left(btrim(coalesce(p.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
  union all
  select 2,
         public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         upper(btrim(coalesce(w.tanda, ''))),
         coalesce(w.m3, 0)::numeric,
         w.fecha_entrega
    from public."PPP_Web_Programacion" w
   where w.tanda is not null and btrim(w.tanda) <> ''
  union all
  select 3,
         regexp_replace(btrim(s.np), '\.0+$', ''),
         upper(btrim(coalesce(s.tanda, ''))),
         coalesce(s.m3, 0)::numeric,
         case when left(btrim(coalesce(s.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(s.fecha_entrega), 10)::date end
    from public.gv_ppp_en_salida s
  union all
  select 4,
         regexp_replace(btrim(e.np), '\.0+$', ''),
         upper(btrim(coalesce(e.tanda, ''))),
         coalesce(e.m3, 0)::numeric,
         case when left(btrim(coalesce(e.fecha_entrega, '')), 10) ~ '^\d{4}-\d{2}-\d{2}$'
              then left(btrim(e.fecha_entrega), 10)::date end
    from public.gv_ppp_entregados e
),
uni as (   -- una fila por NP: manda la programación viva; si ya no está, en salida / entregados
  select distinct on (np) np, tanda, m3, fe
    from fuentes
   where np <> '' and fe is not null
   order by np, pri, m3 desc
),
dia as (select * from uni where fe between p_desde and p_hasta),
ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP', 'TP', 'AP', 'TAP')
     and coalesce(btrim(r.legajo), '') not in ('0', '1')
     and btrim(coalesce(r.texto, '')) <> ''
     and r.ts_cliente >= (p_desde - interval '60 days')
),
pick as (
  select distinct on (tanda) tanda, opcion from ev
   where opcion in ('EP', 'TP') order by tanda, ts_cliente desc
),
arm as (
  select distinct on (tanda) tanda, opcion from ev
   where opcion in ('AP', 'TAP') order by tanda, ts_cliente desc
),
salio as (   -- cargado al camión o entregado = armado sí o sí
  select regexp_replace(btrim(np), '\.0+$', '') as np from public.gv_ppp_en_salida
  union
  select regexp_replace(btrim(np), '\.0+$', '') from public.gv_ppp_entregados
),
est as (
  select d.fe, d.m3,
         case
           when s.np is not null            then 'armado'
           when a.opcion = 'TAP'            then 'armado'
           when a.opcion = 'AP'             then 'armando'
           when p.opcion = 'TP'             then 'picking'
           when p.opcion = 'EP'             then 'pickeando'
           else 'sin'
         end as est
    from dia d
    left join salio s on s.np = d.np
    left join pick  p on p.tanda = d.tanda and d.tanda <> ''
    left join arm   a on a.tanda = d.tanda and d.tanda <> ''
),
agg as (
  select fe,
         count(*)::int                                                            as pedidos,
         round(sum(m3), 3)                                                        as m3,
         count(*) filter (where est in ('armado','armando','picking'))::int       as pick_ped,
         round(coalesce(sum(m3) filter (where est in ('armado','armando','picking')), 0), 3) as pick_m3,
         count(*) filter (where est = 'armado')::int                              as arm_ped,
         round(coalesce(sum(m3) filter (where est = 'armado'), 0), 3)             as arm_m3,
         count(*) filter (where est in ('armando','picking','pickeando'))::int    as curso_ped,
         count(*) filter (where est = 'sin')::int                                 as sin_ped
    from est group by fe
)
select g.fecha,
       coalesce(a.pedidos, 0), coalesce(a.m3, 0),
       coalesce(a.pick_ped, 0), coalesce(a.pick_m3, 0),
       coalesce(a.arm_ped, 0), coalesce(a.arm_m3, 0),
       coalesce(a.curso_ped, 0), coalesce(a.sin_ped, 0),
       -- pct_listo / pct_armado: por m³ si el día tiene m³; si no, por pedidos.
       -- ⚠ 100 % SÓLO si de verdad está todo: 15 de 16 pedidos redondeaba a 100 y el aviso
       --   de las 16 diría "ya está" con uno sin armar. Mientras falte algo, tope en 99.
       case when coalesce(a.m3, 0) > 0 then public.gv_pct(a.pick_m3, a.m3)
            when coalesce(a.pedidos, 0) > 0 then public.gv_pct(a.pick_ped, a.pedidos)
            else 0 end,
       case when coalesce(a.m3, 0) > 0 then public.gv_pct(a.arm_m3, a.m3)
            when coalesce(a.pedidos, 0) > 0 then public.gv_pct(a.arm_ped, a.pedidos)
            else 0 end,
       public.gv_pct(a.pick_ped, a.pedidos),
       public.gv_pct(a.arm_ped,  a.pedidos),
       public.gv_pct(a.pick_m3,  a.m3),
       public.gv_pct(a.arm_m3,   a.m3),
       case when coalesce(a.m3, 0) > 0 then 'm3' else 'pedidos' end
  from (select generate_series(p_desde, p_hasta, interval '1 day')::date as fecha) g
  left join agg a on a.fe = g.fecha
 order by 1;
$$;

comment on function public.gv_ppp_avance_dias(date, date) is
  'v16.97 — avance por día de entrega: % listo (picking terminado) y % armado (TAP o ya salido). Lo usan la PPP, el Telegram de las 16 y la tarea de Planify.';

-- un solo día (lo que llama el front y el aviso de las 16)
create or replace function public.gv_ppp_avance_dia(p_fecha date default null)
returns table (
  fecha date, pedidos int, m3 numeric, pick_ped int, pick_m3 numeric, arm_ped int, arm_m3 numeric,
  curso_ped int, sin_ped int, pct_listo int, pct_armado int, pct_listo_ped int, pct_armado_ped int,
  pct_listo_m3 int, pct_armado_m3 int, base text
)
language sql
stable
set search_path to 'public', 'pg_temp'
as $$
  select * from public.gv_ppp_avance_dias(
    coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date),
    coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date));
$$;

grant execute on function public.gv_ppp_avance_dias(date, date) to anon, authenticated, service_role;
grant execute on function public.gv_ppp_avance_dia(date)        to anon, authenticated, service_role;

-- ── 2. el texto del aviso (uno solo para Telegram y Planify) ───────────────
create or replace function public.gv_ppp_avance_texto(p_fecha date default null, p_corto boolean default false)
returns text
language plpgsql
stable
set search_path to 'public', 'pg_temp'
as $$
declare
  v_f date := coalesce(p_fecha, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
  a   record;
begin
  select * into a from public.gv_ppp_avance_dia(v_f);
  if a.pedidos = 0 then
    return 'No hay pedidos programados para el ' || to_char(v_f, 'DD/MM') || '.';
  end if;
  if p_corto then
    return a.pct_listo || ' % listo · ' || a.pct_armado || ' % armado';
  end if;
  return
    a.pct_listo || ' % LISTO (picking terminado) · ' || a.pct_armado || ' % ARMADO' || E'\n' ||
    'Entrega del ' || to_char(v_f, 'DD/MM') || ': ' || a.pedidos || ' pedido' ||
      case when a.pedidos = 1 then '' else 's' end ||
      ' · ' || trim(to_char(a.m3, 'FM9990.00')) || ' m³ en total.' || E'\n' ||
    'Armado: ' || trim(to_char(a.arm_m3, 'FM9990.00')) || ' de ' || trim(to_char(a.m3, 'FM9990.00')) ||
      ' m³ (' || a.arm_ped || ' de ' || a.pedidos || ' pedidos).' || E'\n' ||
    'Picking terminado: ' || trim(to_char(a.pick_m3, 'FM9990.00')) || ' m³ (' || a.pick_ped ||
      ' pedidos).' || E'\n' ||
    'Falta armar: ' || trim(to_char(greatest(a.m3 - a.arm_m3, 0), 'FM9990.00')) || ' m³ — ' ||
      (a.pedidos - a.arm_ped) || ' pedido' || case when (a.pedidos - a.arm_ped) = 1 then '' else 's' end ||
      ' (' || a.curso_ped || ' en curso, ' || a.sin_ped || ' sin empezar).';
end $$;

grant execute on function public.gv_ppp_avance_texto(date, boolean) to anon, authenticated, service_role;

-- ── 3. las 16:00: Telegram + tarea en el Planify de Marianela Becker (38) ──
-- Telegram al grupo de siempre (tg_enqueue → telegram_outbox → tg_outbox_flush, dedup por día)
-- y tarea de Planify por planify.planify_aviso_diario, el mismo camino que el aviso de
-- Facturación de las 16:00 (cron 84) — así Marianela lo ve aunque no mire Telegram ni la PPP.
-- p_forzar: correrla a mano fuera de hora / en un dia no habil (para probar).
create or replace function public.gv_avance_dia_16h(p_forzar boolean default false)
returns text
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_hoy   date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  a       record;
  v_txt   text;
  v_task  bigint;
begin
  if not p_forzar and not public.gv_es_dia_habil(v_hoy) then return 'dia no habil'; end if;
  select * into a from public.gv_ppp_avance_dia(v_hoy);
  if a.pedidos = 0 then return 'sin pedidos'; end if;   -- sin pedidos del día no hay nada que avisar
  v_txt := public.gv_ppp_avance_texto(v_hoy, false);

  perform public.tg_enqueue(
    '📊 SON LAS 16:00 — AVANCE DEL DÍA' || E'\n' || v_txt || E'\n' ||
    'Si falta armado, todavía hay tiempo: a último minuto no se llega.',
    'gv_avance16_' || v_hoy::text);
  perform public.tg_outbox_flush();

  v_task := planify.planify_aviso_diario(
    p_employee_id => 38,                               -- Marianela Becker
    p_clave       => 'avance16',
    p_name        => 'Avance del día: ' || a.pct_listo || ' % listo · ' || a.pct_armado || ' % armado',
    p_note        => 'Hora: 16:00' || E'\n' || v_txt,
    p_kicker      => 'SON LAS 16:00 — AVANCE DEL DÍA',
    p_hora        => '16:00');

  return 'ok · ' || a.pct_listo || '% listo · ' || a.pct_armado || '% armado · planify task ' ||
         coalesce(v_task::text, '(ya estaba)');
end $$;

revoke all on function public.gv_avance_dia_16h(boolean) from public, anon, authenticated;
grant execute on function public.gv_avance_dia_16h(boolean) to service_role;

-- cron: 16:00 ART = 19:00 UTC, lunes a viernes (el feriado lo corta gv_es_dia_habil)
select cron.unschedule('gv-avance-dia-16h') where exists (select 1 from cron.job where jobname = 'gv-avance-dia-16h');
select cron.schedule('gv-avance-dia-16h', '0 19 * * 1-5', $$select public.gv_avance_dia_16h()$$);

-- ── rollback ──────────────────────────────────────────────────────────────
-- select cron.unschedule('gv-avance-dia-16h');
-- drop function public.gv_avance_dia_16h(boolean);
-- drop function public.gv_ppp_avance_texto(date, boolean);
-- drop function public.gv_ppp_avance_dia(date);
-- drop function public.gv_ppp_avance_dias(date, date);
-- y en el front: sacar pppRefreshAvance / _pppAvanceHtml de index.html (v16.97).
