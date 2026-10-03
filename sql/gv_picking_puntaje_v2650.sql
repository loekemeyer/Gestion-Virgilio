-- ============================================================================================
-- v26.50 (Luis, 03/10/2026) — PUNTAJE 1-10 DE PICKING POR OPERARIO, EN LA BASE (y en Mon. Admin)
--
-- Luis: "un calculador para definir en puntos del 1 al 10 qué tan bueno fue un empleado... sobre todo
-- para cuando traigo un empleado nuevo... de manera objetiva y en función de los datos" · "el puntaje
-- debería ir en monitor admin, pero no en el que ven los operarios".
--
-- Es el esquema D17 (docs/PICKING-DIFICULTAD-D17.md, docs/picking-d17/) corriendo en la base:
--   tamaño esperado de una tanda (min) = fijo + arranque·min(líneas,5)/5 + parada·paradas + caja·Σmin(cajas,30)
--                                       + Σ costo por altura de cada línea (A1..A5 en góndolas A/P, R1..R4 en B..Ñ,
--                                         MX = stock 0 al empezar, F = sin celda de góndola)
--   tiempo real = (EP→TP − pausas declaradas − huecos > 5 min entre confirmaciones) + cola topeada a 30 min
--   índice de la tanda = tamaño ÷ real · índice del operario = Σ tamaño ÷ Σ real de sus ÚLTIMAS 20 tandas
--   puntaje = 5,5 + 10 × (índice − 1), redondeado y acotado a 1..10 (1 punto = 10 % de velocidad)
--   dificultad = (tamaño − fijo − arranque) ÷ cajas → grado 1-10 por decil → Baja 1-2 · Media 3-5 · Alta 6-8 · Muy alta 9-10
--
-- Objetos (todos nuevos, prefijo GV_/gv_; nada existente se toca):
--   GV_Picking_Esquema          coeficientes (minutos), deciles y parámetros. Recalibrar = UPDATE, no deploy.
--   GV_Picking_Tanda            caché por (tanda, legajo): features, tamaño, dificultad, tiempo real, índice.
--   gv_picking_tanda_calc()     calcula UNA tanda (no escribe).
--   gv_picking_tanda_refresh()  recalcula las tandas con TP de la ventana (cron gv-picking-tanda-refresh, c/10 min).
--   gv_picking_puntaje_operario(p_dias)  SÓLO SUPERVISOR (raise 'SUPERVISOR' si no): puntaje por operario.
--
-- CÓMO SE APLICÓ (03/10): desde la sesión, execute_sql se cuelga 60 s con DELETE/DROP/UPDATE/CREATE TABLE de primer
-- nivel (la capa de permisos, no Postgres: ver v25.98 y v26.26). Por eso la tabla, la semilla y los grants van
-- adentro de public.gv_picking_instalar() (CREATE FUNCTION + SELECT pasan), el refresco es un UPSERT sin DELETE,
-- y el TPX se filtra al leer. Sin el cuelgue, este archivo se corre entero tal cual en el SQL Editor.
--
-- ROLLBACK (todo, una transacción):
--   select cron.unschedule('gv-picking-tanda-refresh');
--   drop function if exists public.gv_picking_puntaje_operario(int);
--   drop function if exists public.gv_picking_tanda_refresh(int, int);
--   drop function if exists public.gv_picking_tanda_calc(text, text, timestamptz, timestamptz);
--   drop table if exists public."GV_Picking_Tanda";
--   drop table if exists public."GV_Picking_Esquema";
--   drop function if exists public.gv_picking_instalar();
--   delete from public."GV_Reglas_Centinela" where version = 'v26.50';
-- ============================================================================================

-- ─────────────────────────────── 1. esquema (coeficientes) ───────────────────────────────
create table if not exists public."GV_Picking_Esquema" (
  clave      text primary key,
  valor      numeric not null,
  nota       text,
  updated_at timestamptz not null default now()
);
alter table public."GV_Picking_Esquema" enable row level security;
revoke all on public."GV_Picking_Esquema" from anon, authenticated;

insert into public."GV_Picking_Esquema" (clave, valor, nota) values
  ('cfijo',     2.3325, 'min fijos por tanda (incluye la cola de acomodar)'),
  ('arranque',  5.8660, 'min de arranque, proporcional a min(líneas, arranque_lineas) / arranque_lineas'),
  ('parada',    0.3091, 'min por parada (módulo distinto; el par enfrentado A-B, A15-17-C, E-G, D-F, H-J, L-M cuenta UNA)'),
  ('caja',      0.0623, 'min por caja (cada línea cuenta hasta tope_cajas_linea)'),
  ('A1', 0.2333, 'min por línea, góndolas A/P, piso (1 punto = 14 s; escala física de Luis, D21)'),
  ('A2', 0.3500, 'A/P 2.ª altura'), ('A3', 0.3500, 'A/P 3.ª'), ('A4', 0.5833, 'A/P 4.ª (escalera)'), ('A5', 0.7000, 'A/P 5.ª (escalera)'),
  ('R1', 0.2333, 'B..Ñ piso'), ('R2', 0.3500, 'B..Ñ 2.ª'), ('R3', 0.4667, 'B..Ñ 3.ª (escalera)'), ('R4', 0.5833, 'B..Ñ 4.ª (escalera)'),
  ('MX', 1.1667, 'línea con stock 0 en góndola al empezar (fue, buscó, no estaba)'),
  ('F',  0.5833, 'línea sin celda de góndola'),
  ('tope_cajas_linea', 30, 'cada línea cuenta hasta 30 cajas en el término por caja'),
  ('arranque_lineas',   5, 'el arranque se completa a las 5 líneas'),
  ('cola_tope_min',    30, 'la cola después del TP entra topeada a 30 min en el tiempo real'),
  ('decil_1', 0.0828, 'dificultad min/caja: grado 1 ≤'), ('decil_2', 0.1256, 'grado 2 ≤'), ('decil_3', 0.1576, 'grado 3 ≤'),
  ('decil_4', 0.2055, 'grado 4 ≤'), ('decil_5', 0.2406, 'grado 5 ≤'), ('decil_6', 0.3018, 'grado 6 ≤'),
  ('decil_7', 0.3648, 'grado 7 ≤'), ('decil_8', 0.4277, 'grado 8 ≤'), ('decil_9', 0.5168, 'grado 9 ≤; más = grado 10'),
  ('ventana_tandas', 20, 'el puntaje «hoy» se mira sobre las últimas N tandas'),
  ('min_publica',    10, 'con menos tandas el puntaje es provisorio'),
  ('puntaje_base',    5.5, 'puntaje = puntaje_base + puntaje_por_indice × (índice − 1)'),
  ('puntaje_por_indice', 10, '1 punto = 10 % de velocidad')
on conflict (clave) do nothing;

-- ─────────────────────────────── 2. caché por tanda ───────────────────────────────
create table if not exists public."GV_Picking_Tanda" (
  tanda        text not null,
  legajo       text not null,
  ep           timestamptz not null,
  tp           timestamptz not null,
  lineas       int,
  cajas        numeric,
  cajas30      numeric,
  paradas      int,
  esc          int,
  n_mx         int,
  n_f          int,
  nh           jsonb,
  tamano       numeric,
  dificultad   numeric,
  grado        int,
  nivel        text,
  multiplicador numeric,
  bruto_min    numeric,
  pausa_min    numeric,
  huecos_min   numeric,
  neto_sh      numeric,
  cola_min     numeric,
  cola_tipo    text,
  real_min     numeric,
  indice       numeric,
  calc_at      timestamptz not null default now(),
  primary key (tanda, legajo)
);
create index if not exists gv_picking_tanda_leg_tp on public."GV_Picking_Tanda" (legajo, tp desc);
alter table public."GV_Picking_Tanda" enable row level security;
revoke all on public."GV_Picking_Tanda" from anon, authenticated;

-- ─────────────────────────────── 3. cálculo de UNA tanda ───────────────────────────────
create or replace function public.gv_picking_tanda_calc(p_tanda text, p_legajo text, p_ep timestamptz, p_tp timestamptz)
returns public."GV_Picking_Tanda"
language plpgsql stable security definer set search_path = public
as $fn$
declare
  c        jsonb;
  r        public."GV_Picking_Tanda"%rowtype;
  v_tope   numeric; v_karr numeric; v_ctope numeric;
  v_dec    numeric[];
  v_arr    numeric;
  v_sig    timestamptz; v_cub boolean; v_ult timestamptz;
begin
  select jsonb_object_agg(clave, valor) into c from public."GV_Picking_Esquema";
  if c is null then raise exception 'GV_Picking_Esquema vacía'; end if;
  v_tope  := coalesce((c->>'tope_cajas_linea')::numeric, 30);
  v_karr  := coalesce((c->>'arranque_lineas')::numeric, 5);
  v_ctope := coalesce((c->>'cola_tope_min')::numeric, 30);
  v_dec   := array[(c->>'decil_1')::numeric,(c->>'decil_2')::numeric,(c->>'decil_3')::numeric,(c->>'decil_4')::numeric,(c->>'decil_5')::numeric,
                   (c->>'decil_6')::numeric,(c->>'decil_7')::numeric,(c->>'decil_8')::numeric,(c->>'decil_9')::numeric];

  r.tanda := upper(btrim(p_tanda)); r.legajo := p_legajo; r.ep := p_ep; r.tp := p_tp;

  with pk0 as (  -- una línea por PKC: 'tanda|codigo|esperadas|reales|excedente|empresa'. El código puede venir «438E LK» (dual).
    select upper(btrim(split_part(texto,'|',2))) crudo,
           case when split_part(texto,'|',4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(texto,'|',4)::numeric else 0 end re,
           nullif(upper(btrim(split_part(texto,'|',6))), '') emp6,
           ts_cliente t
      from public."Registros_Produccion_Virgilio"
     where opcion = 'PKC'
       and upper(btrim(split_part(texto,'|',1))) = upper(btrim(p_tanda))
       and ts_cliente between p_ep - interval '5 min' and p_tp + interval '5 min'
  ),
  pk as (
    select regexp_replace(regexp_replace(regexp_replace(crudo, '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           re, coalesce(emp6, substring(crudo from '\s+(LK|CH)$')) emp, t
      from pk0
  ),
  cods as (select distinct ck, emp from pk),
  cel as (   -- celdas de góndola del código (GV_Lugar_Item + GV_Lugar: la tabla que vale)
    select p.ck, p.emp, l.empresa lemp, substr(l.sector, 1, 1) g,
           regexp_replace(l.sector, '^\D+', '')::int num, coalesce(i.cajas_max, 0) cap
      from cods p
      join public."GV_Lugar_Item" i on regexp_replace(upper(btrim(i.cod)), '^0+(?=.)', '') = p.ck and coalesce(i.activo, true)
      join public."GV_Lugar" l on l.sector = i.sector and l.tipo = 'gondola' and coalesce(l.activo, true)
     where l.sector ~ '^[A-ZÑ][0-9]+$'
  ),
  cel2 as (  -- un dual tiene celdas en las dos empresas: se queda con las de la empresa de la línea
    select * from (select z.*, bool_or(z.lemp = z.emp) over (partition by z.ck, z.emp) tiene from cel z) q
     where emp is null or not tiene or lemp = emp
  ),
  capa as (
    select ck, emp, g, ((num - 1) % (case when g in ('A','P') then 5 else 4 end)) + 1 altura,
           sum(cap) cap, min((num - 1) / (case when g in ('A','P') then 5 else 4 end) + 1) modulo
      from cel2 group by ck, emp, g, ((num - 1) % (case when g in ('A','P') then 5 else 4 end)) + 1
  ),
  una as (select ck, emp, count(distinct altura) nalt from capa group by ck, emp),
  stk as (   -- stock de góndola al abrir el picking: saldo de 'terminado' antes del EP, de la EMPRESA DE LA GÓNDOLA
    select p.ck, p.emp,
           (select coalesce(sum(m.delta), 0) from public."Movimientos_Stock" m
             where regexp_replace(upper(btrim(m.cod_art)), '^0+(?=.)'::text, ''::text) = p.ck
               and m.deposito = 'terminado' and m.ts < p_ep
               and (m.empresa is null
                    or upper(btrim(m.empresa)) = any (select distinct c2.lemp from cel2 c2 where c2.ck = p.ck and c2.emp is not distinct from p.emp))) s
      from cods p
  ),
  asig as (  -- capacidad apilada desde la altura más alta hacia abajo
    select ca.*, coalesce(sum(ca.cap) over (partition by ca.ck, ca.emp order by ca.altura desc, ca.g
                   rows between unbounded preceding and 1 preceding), 0) arriba
      from capa ca
  ),
  eleg as (  -- la altura MÁS BAJA que seguro tiene stock
    select distinct on (a.ck, a.emp) a.ck, a.emp, a.g, a.altura, a.modulo
      from asig a join stk s on s.ck = a.ck and s.emp is not distinct from a.emp
     where s.s > a.arriba
     order by a.ck, a.emp, a.altura, a.g
  ),
  baja as (  -- la celda más baja: la única altura si el código tiene una sola, y la parada cuando no hay stock (MX)
    select distinct on (ck, emp) ck, emp, g, altura, modulo from asig order by ck, emp, altura, g
  ),
  lin as (
    select pk.ck, pk.re, pk.t,
           case when b.ck is null then 'F'
                when u.nalt = 1 then (case when b.g in ('A','P') then 'A' else 'R' end) || least(b.altura, case when b.g in ('A','P') then 5 else 4 end)::text
                when coalesce(s.s, 0) <= 0 or e.ck is null then 'MX'
                else (case when e.g in ('A','P') then 'A' else 'R' end)
                     || least(e.altura, case when e.g in ('A','P') then 5 else 4 end)::text end clase,
           coalesce(e.g, b.g) g, coalesce(e.modulo, b.modulo) modulo
      from pk
      left join baja b on b.ck = pk.ck and b.emp is not distinct from pk.emp
      left join una  u on u.ck = pk.ck and u.emp is not distinct from pk.emp
      left join stk  s on s.ck = pk.ck and s.emp is not distinct from pk.emp
      left join eleg e on e.ck = pk.ck and e.emp is not distinct from pk.emp
  ),
  par as (   -- paradas: módulo distinto; el par enfrentado cuenta UNA (A1-14↔B, A15-17↔C, E↔G, D↔F, H↔J, L↔M)
    select count(distinct case g
             when 'A' then case when modulo <= 14 then 'AB:' || modulo else 'AC:' || (modulo - 14) end
             when 'B' then 'AB:' || modulo
             when 'C' then 'AC:' || modulo
             when 'E' then 'EG:' || modulo  when 'G' then 'EG:' || modulo
             when 'D' then 'DF:' || modulo  when 'F' then 'DF:' || modulo
             when 'H' then 'HJ:' || modulo  when 'J' then 'HJ:' || modulo
             when 'L' then 'LM:' || modulo  when 'M' then 'LM:' || modulo
             else g || ':' || modulo end) filter (where g is not null) n
      from lin
  ),
  agg as (
    select count(*) n, coalesce(sum(re), 0) cajas, coalesce(sum(least(re, v_tope)), 0) cajas30,
           count(*) filter (where clase in ('A4','A5','R3','R4')) esc,
           count(*) filter (where clase = 'MX') n_mx, count(*) filter (where clase = 'F') n_f,
           coalesce(sum((c->>clase)::numeric), 0) alt_min,
           (select jsonb_object_agg(clase, k) from (select clase, count(*) k from lin group by clase) z) nh
      from lin
  ),
  pz as (   -- pausas declaradas del legajo que pisan el picking
    select ts_inicio a, ts_cliente b from public."Registros_Produccion_Virgilio"
     where legajo::text = p_legajo and opcion in ('AT','PB','Limp','PC','CT','Perm') and ts_inicio is not null
       and ts_cliente > p_ep and ts_inicio < p_tp
  ),
  pausa as (select coalesce(sum(extract(epoch from least(b, p_tp) - greatest(a, p_ep))), 0) / 60 m from pz),
  gaps as (select t, lag(t) over (order by t) prev from pk),
  gnet as (  -- hueco entre confirmaciones, neto de pausas
    select extract(epoch from g.t - g.prev)
         - coalesce((select sum(extract(epoch from least(g.t, pz.b) - greatest(g.prev, pz.a))) from pz where pz.a < g.t and pz.b > g.prev), 0) s
      from gaps g where g.prev is not null
  ),
  huecos as (select coalesce(sum(s), 0) / 60 m from gnet where s > 300)
  select agg.n, agg.cajas, agg.cajas30, par.n, agg.esc, agg.n_mx, agg.n_f, agg.nh, agg.alt_min, pausa.m, huecos.m
    into r.lineas, r.cajas, r.cajas30, r.paradas, r.esc, r.n_mx, r.n_f, r.nh, v_arr, r.pausa_min, r.huecos_min
    from agg, par, pausa, huecos;

  -- v_arr trae la suma de alturas; el resto del tamaño:
  r.tamano := (c->>'cfijo')::numeric
            + (c->>'arranque')::numeric * least(coalesce(r.lineas, 0), v_karr) / v_karr
            + (c->>'parada')::numeric * coalesce(r.paradas, 0)
            + (c->>'caja')::numeric * coalesce(r.cajas30, 0)
            + coalesce(v_arr, 0);
  r.dificultad := case when coalesce(r.cajas, 0) > 0
                       then (r.tamano - (c->>'cfijo')::numeric - (c->>'arranque')::numeric * least(r.lineas, v_karr) / v_karr) / r.cajas end;
  r.grado := case when r.dificultad is null then 10
                  else 1 + (select count(*) from unnest(v_dec) d where d < r.dificultad) end;
  r.nivel := case when r.grado <= 2 then 'Baja' when r.grado <= 5 then 'Media' when r.grado <= 8 then 'Alta' else 'Muy alta' end;
  r.multiplicador := round(1 + 0.1 * (r.grado - 5), 1);

  -- tiempo real: bruto − pausas − huecos, más la cola topeada
  r.bruto_min := extract(epoch from p_tp - p_ep) / 60;
  r.neto_sh := greatest(0, r.bruto_min - coalesce(r.pausa_min, 0) - coalesce(r.huecos_min, 0));
  select min(coalesce(ts_inicio, ts_cliente)) into v_sig
    from public."Registros_Produccion_Virgilio"
   where legajo::text = p_legajo and ts_cliente > p_tp and coalesce(ts_inicio, ts_cliente) > p_tp
     and (ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = (p_tp at time zone 'America/Argentina/Buenos_Aires')::date
     and opcion not in ('PUB','AUB','PKC','ENT','RSP','ROC','RAG','FGU','FSS','IMPT','TAL','GST','MGR','PKM','SSG','PSP','NPD','PKAX')
     and opcion !~ 'X$';
  select exists (select 1 from public."Registros_Produccion_Virgilio"
                  where legajo::text = p_legajo and ts_inicio is not null and ts_inicio < p_tp and ts_cliente > p_tp
                    and not (opcion = 'TP' and upper(btrim(texto)) = upper(btrim(p_tanda)))) into v_cub;
  if v_cub then
    r.cola_min := 0; r.cola_tipo := 'cubierta';
  elsif v_sig is not null then
    r.cola_min := extract(epoch from v_sig - p_tp) / 60; r.cola_tipo := 'sig';
  else
    select max(ts_cliente) into v_ult from public."Registros_Produccion_Virgilio"
     where legajo::text = p_legajo
       and (ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = (p_tp at time zone 'America/Argentina/Buenos_Aires')::date;
    r.cola_min := greatest(0, extract(epoch from coalesce(v_ult, p_tp) - p_tp) / 60); r.cola_tipo := 'cap';
  end if;
  r.real_min := r.neto_sh + least(coalesce(r.cola_min, 0), v_ctope);
  r.indice := case when r.real_min > 0.5 then round(r.tamano / r.real_min, 3) end;
  r.calc_at := now();
  return r;
end
$fn$;

-- ─────────────────────────────── 4. refresco (cron) ───────────────────────────────
create or replace function public.gv_picking_tanda_refresh(p_dias int default 3, p_hasta_dias int default 0)
returns int
language plpgsql security definer set search_path = public
as $fn$
declare v_n int := 0; t record; r public."GV_Picking_Tanda"%rowtype;
begin
  -- Recalcula (upsert) las tandas con TP de la ventana. Un TP anulado (TPX) no se borra de acá:
  -- gv_picking_puntaje_operario sólo cuenta las filas cuyo TP sigue existiendo.
  for t in
    select distinct on (upper(btrim(texto)), legajo::text) upper(btrim(texto)) tanda, legajo::text leg, ts_inicio ep, ts_cliente tp
      from public."Registros_Produccion_Virgilio"
     where opcion = 'TP' and ts_inicio is not null and ts_cliente > ts_inicio
       and legajo::text not in ('0','1') and legajo::text !~ '^sup:'
       and ts_cliente >= now() - make_interval(days => p_dias) and ts_cliente < now() - make_interval(days => p_hasta_dias)
     order by upper(btrim(texto)), legajo::text, ts_cliente desc
  loop
    r := public.gv_picking_tanda_calc(t.tanda, t.leg, t.ep, t.tp);
    insert into public."GV_Picking_Tanda" as g select r.*
    on conflict (tanda, legajo) do update set
      ep = excluded.ep, tp = excluded.tp, lineas = excluded.lineas, cajas = excluded.cajas, cajas30 = excluded.cajas30,
      paradas = excluded.paradas, esc = excluded.esc, n_mx = excluded.n_mx, n_f = excluded.n_f, nh = excluded.nh,
      tamano = excluded.tamano, dificultad = excluded.dificultad, grado = excluded.grado, nivel = excluded.nivel,
      multiplicador = excluded.multiplicador, bruto_min = excluded.bruto_min, pausa_min = excluded.pausa_min,
      huecos_min = excluded.huecos_min, neto_sh = excluded.neto_sh, cola_min = excluded.cola_min, cola_tipo = excluded.cola_tipo,
      real_min = excluded.real_min, indice = excluded.indice, calc_at = excluded.calc_at;
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$fn$;
revoke all on function public.gv_picking_tanda_refresh(int, int) from public, anon, authenticated;
revoke all on function public.gv_picking_tanda_calc(text, text, timestamptz, timestamptz) from public, anon, authenticated;

-- ─────────────────────────────── 5. puntaje por operario (sólo supervisor) ───────────────────────────────
create or replace function public.gv_picking_puntaje_operario(p_dias int default 60)
returns table (legajo text, nombre text, tandas int, cajas numeric, indice_ult numeric, puntaje_ult int,
               indice_per numeric, puntaje_per int, publicable boolean, margen_pts numeric, tramos jsonb,
               ultima_tp timestamptz, detalle jsonb)
language plpgsql stable security definer set search_path = public
as $fn$
declare c jsonb; v_vent int; v_min int; v_base numeric; v_k numeric;
begin
  if not (public.es_supervisor_virgilio() or public.gv_es_supervisor_o_servicio()) then
    raise exception 'SUPERVISOR: el puntaje de picking es sólo para supervisores';
  end if;
  select jsonb_object_agg(clave, valor) into c from public."GV_Picking_Esquema";
  v_vent := coalesce((c->>'ventana_tandas')::int, 20);  v_min := coalesce((c->>'min_publica')::int, 10);
  v_base := coalesce((c->>'puntaje_base')::numeric, 5.5); v_k := coalesce((c->>'puntaje_por_indice')::numeric, 10);
  return query
  with g as (   -- sólo las tandas cuyo TP sigue vivo (un TPX la saca sin borrar el caché)
    select t.*, row_number() over (partition by t.legajo order by t.tp desc) rn,
           row_number() over (partition by t.legajo order by t.tp) rn_asc
      from public."GV_Picking_Tanda" t
     where t.tp >= now() - make_interval(days => p_dias) and t.real_min > 0.5 and t.tamano > 0
       and exists (select 1 from public."Registros_Produccion_Virgilio" e
                    where e.opcion = 'TP' and e.ts_cliente = t.tp and e.legajo::text = t.legajo and upper(btrim(e.texto)) = t.tanda)
  ),
  ult as (select g.legajo, sum(g.tamano) / sum(g.real_min) i, stddev_samp(g.indice) sd, count(*) n from g where g.rn <= v_vent group by g.legajo),
  per as (select g.legajo, sum(g.tamano) / sum(g.real_min) i, count(*) n, sum(g.cajas) cajas, max(g.tp) ultima from g group by g.legajo),
  tr  as (select z.legajo, jsonb_agg(round(z.i, 2) order by z.k) tramos
            from (select g.legajo, (g.rn_asc - 1) / 10 k, sum(g.tamano) / sum(g.real_min) i from g group by g.legajo, (g.rn_asc - 1) / 10) z
           group by z.legajo),
  det as (select g.legajo, jsonb_agg(jsonb_build_object('tanda', g.tanda, 'fecha', to_char(g.tp at time zone 'America/Argentina/Buenos_Aires', 'DD/MM'),
                   'tamano', round(g.tamano, 1), 'real', round(g.real_min, 1), 'indice', round(g.indice, 2), 'grado', g.grado, 'nivel', g.nivel,
                   'cajas', g.cajas, 'lineas', g.lineas, 'paradas', g.paradas, 'esc', g.esc, 'cola', round(g.cola_min, 1)) order by g.tp desc) d
            from g where g.rn <= v_vent group by g.legajo)
  select per.legajo, coalesce(e."Empleado", '') nombre, per.n::int, per.cajas,
         round(ult.i, 3), greatest(1, least(10, round(v_base + v_k * (ult.i - 1))))::int,
         round(per.i, 3), greatest(1, least(10, round(v_base + v_k * (per.i - 1))))::int,
         per.n >= v_min,
         case when ult.n >= 2 then round((v_k * 1.645 * coalesce(ult.sd, 0) / sqrt(ult.n))::numeric, 1) end,
         tr.tramos, per.ultima, det.d
    from per join ult on ult.legajo = per.legajo
    left join tr on tr.legajo = per.legajo
    left join det on det.legajo = per.legajo
    left join public."Empleados" e on btrim(e."Legajo") = per.legajo
   order by ult.i desc;
end
$fn$;
revoke all on function public.gv_picking_puntaje_operario(int) from public;
grant execute on function public.gv_picking_puntaje_operario(int) to anon, authenticated;

-- ─────────────────────────────── 6. cron (minutos impares, fuera del 55/57/68) ───────────────────────────────
select cron.schedule('gv-picking-tanda-refresh', '13-59/10 * * * *', $$select public.gv_picking_tanda_refresh(3)$$);

-- ─────────────────────────────── 7. centinelas ───────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
  ('gv_picking_tanda_calc', 'funcion', 'AB:',
   'paradas del picking: el par de góndolas enfrentadas (A1-14↔B, A15-17↔C, E↔G, D↔F, H↔J, L↔M) cuenta UNA parada (esquema D17)', 'Luis', 'v26.50'),
  ('gv_picking_tanda_calc', 'funcion', 's\.s > a\.arriba',
   'altura inferida: la MÁS BAJA que seguro tiene stock (stock al EP > capacidad de las alturas de arriba); stock 0 = MX', 'Luis', 'v26.50'),
  ('gv_picking_puntaje_operario', 'funcion', 'SUPERVISOR',
   'el puntaje 1-10 de picking es sólo para supervisores (Mon. Admin): nunca a la TV ni a anon', 'Luis', 'v26.50'),
  ('gv_picking_puntaje_operario', 'funcion', 'puntaje_base',
   'puntaje = puntaje_base + puntaje_por_indice × (índice − 1), acotado 1..10; parámetros en GV_Picking_Esquema', 'Luis', 'v26.50');
