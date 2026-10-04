-- ============================================================================================
-- v26.51 (Luis, D24, 03/10/2026) — LO NO PICKEADO SE DESCUENTA: m³/h de picking y puntaje 1-10
--
-- Luis: "D24 debe descontar los m3 pickeados si algo no se pickeo".
--
-- Dos lugares acreditan trabajo de picking a un operario y los dos tomaban la tanda ENTERA:
--   · el m³/h de picking (TV, Mon. Admin y el monitor viejo): m³ de la tanda ÷ horas de picking,
--     con el m³ PROGRAMADO aunque se hubiera pickeado la mitad;
--   · el puntaje 1-10 (esquema D17): una línea confirmada con 0 cajas (artículo no pickeado) ganaba
--     parada + altura como si se hubiera levantado.
-- Medido el 03/10 sobre 60 días (334 tandas, 8.347 líneas de PKC): 834 líneas en 0 (10,0 % del m³
-- pedido no se pickeó; mediana por tanda 7,2 %, p90 21 %). Por operario, el m³/h baja 6,4 % (122)
-- a 17,5 % (277).
--
-- Qué cambia:
--   gv_picking_pickeado(p_tandas)  NUEVA, lectura, anon: por tanda, líneas, líneas en 0, cajas pedidas
--                                  y pickeadas, m³ pedido y pickeado y la FRACCIÓN (Σ reales×m³/caja ÷
--                                  Σ pedidas×m³/caja; sin volumen, por cajas; tope 1). Toma el ÚLTIMO
--                                  PKC de cada (tanda, código): un re-picking de otro día no cuenta dos veces.
--                                  La TV, el Mon. Admin (pintarHoras, popRitmo) y el monitor viejo
--                                  (fetchMonitorDayStats, showDayBreakdown) multiplican el m³ de la
--                                  tanda por esa fracción. FAIL-OPEN: si la RPC no contesta, m³ entero.
--   gv_picking_tanda_calc          lin: `where pk.re > 0` (la línea en 0 no cuenta como línea, parada ni
--                                  altura; sí sigue en gaps, que mide el tiempo). + lineas_cero, cajas_ped,
--                                  m3_frac. El tamaño esperado baja y con él el índice del que saltea.
--   GV_Picking_Tanda               + lineas_cero int · cajas_ped numeric · m3_frac numeric
--   gv_picking_tanda_refresh       upsert con las 3 columnas.
--   gv_picking_puntaje_operario    el detalle de cada tanda trae 'cero' y 'frac'. Misma firma.
--
-- CÓMO SE APLICA (misma limitación que la v26.50: execute_sql se cuelga con ALTER/DELETE de primer nivel):
--   1) gv_picking_instalar_v2651()  → ALTER TABLE + 2 centinelas, adentro de la función (CREATE + SELECT).
--   2) las 4 funciones de abajo. gv_picking_tanda_calc y gv_picking_puntaje_operario están en
--      scripts/reglas-protegidas.json: el hook pide el "sí" de Luis y el comentario
--      -- REGLA_CONFIRMADA_POR_USUARIO en la llamada.
--   3) select public.gv_picking_tanda_refresh(62);  → recalcula el caché (62 días, ~20 s).
--   4) chequeo: select * from public.gv_reglas_perdidas;  (vacía)
--
-- ROLLBACK:
--   volver a correr las secciones 3, 4 y 5 de sql/gv_picking_puntaje_v2650.sql (las funciones anteriores);
--   drop function if exists public.gv_picking_pickeado(text[]);
--   drop function if exists public.gv_picking_instalar_v2651();
--   delete from public."GV_Reglas_Centinela" where version = 'v26.51';
--   (las 3 columnas pueden quedar: nadie las lee si las funciones vuelven a la v26.50)
-- ============================================================================================

-- ─────────────────────────────── 1. columnas + centinelas (adentro de una función) ───────────────────────────────
create or replace function public.gv_picking_instalar_v2651()
returns text
language plpgsql security definer set search_path = public
as $fn$
begin
  alter table public."GV_Picking_Tanda" add column if not exists lineas_cero int;
  alter table public."GV_Picking_Tanda" add column if not exists cajas_ped numeric;
  alter table public."GV_Picking_Tanda" add column if not exists m3_frac numeric;
  insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
  select * from (values
    ('gv_picking_tanda_calc', 'funcion', 'where pk\.re > 0',
     'D24: una línea del picking confirmada con 0 cajas NO cuenta (ni línea, ni parada, ni altura): lo no pickeado se descuenta del puntaje', 'Luis', 'v26.51'),
    ('gv_picking_pickeado', 'funcion', 'least\(1, sum\(z\.re \* z\.m3c\)',
     'D24: el m³ que se le acredita al picking de un operario se prorratea por lo pickeado (Σ reales×m³ ÷ Σ pedidas×m³, tope 1)', 'Luis', 'v26.51')
  ) v(objeto, clase, patron, regla, quien_pidio, version)
  where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto = v.objeto and c.patron = v.patron);
  return 'ok';
end
$fn$;
revoke all on function public.gv_picking_instalar_v2651() from public, anon, authenticated;
select public.gv_picking_instalar_v2651();

-- ─────────────────────────────── 2. lo pickeado de cada tanda (lectura, anon) ───────────────────────────────
create or replace function public.gv_picking_pickeado(p_tandas text[])
returns table (tanda text, lineas int, lineas_cero int, cajas_ped numeric, cajas_pick numeric,
               m3_ped numeric, m3_pick numeric, fraccion numeric)
language sql stable set search_path = public
as $fn$
  -- v26.51 (D24, Luis): por tanda, cuánto de lo pedido se pickeó. El ÚLTIMO PKC de cada (tanda, código).
  -- fraccion = Σ reales × m³/caja ÷ Σ pedidas × m³/caja (sin volumen: el promedio de la tanda; sin ninguno, por cajas), tope 1.
  with pk0 as (
    select upper(btrim(split_part(r.texto,'|',1))) tanda,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(split_part(r.texto,'|',2))), '\s+(LK|CH)$', ''), '([0-9E])L$', '\1'), '^0+(?=.)', '') ck,
           case when split_part(r.texto,'|',3) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto,'|',3)::numeric end esp,
           case when split_part(r.texto,'|',4) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(r.texto,'|',4)::numeric else 0 end re,
           r.ts_cliente t
      from public."Registros_Produccion_Virgilio" r
     where r.opcion = 'PKC'
       and upper(btrim(split_part(r.texto,'|',1))) = any (select upper(btrim(x)) from unnest(coalesce(p_tandas, '{}')) x)
  ),
  pk as (select distinct on (tanda, ck) * from pk0 order by tanda, ck, t desc),
  vol as (select regexp_replace(upper(btrim(codigo)), '^0+(?=.)', '') ck, max(m3) m3 from public.vista_volumen_articulo_resuelto group by 1),
  l as (select pk.tanda, pk.ck, greatest(coalesce(pk.esp, pk.re), pk.re) ped, pk.re, v.m3 from pk left join vol v on v.ck = pk.ck),
  z as (select l.*, coalesce(l.m3, avg(l.m3) over (partition by l.tanda), 0) m3c from l)
  select z.tanda, count(*)::int, (count(*) filter (where z.re = 0))::int, sum(z.ped), sum(z.re),
         round(sum(z.ped * z.m3c)::numeric, 3), round(sum(z.re * z.m3c)::numeric, 3),
         case when sum(z.ped * z.m3c) > 0 then round(least(1, sum(z.re * z.m3c) / sum(z.ped * z.m3c))::numeric, 4)
              when sum(z.ped) > 0 then round(least(1, sum(z.re) / sum(z.ped))::numeric, 4) else 1 end
    from z group by z.tanda
$fn$;
revoke all on function public.gv_picking_pickeado(text[]) from public;
grant execute on function public.gv_picking_pickeado(text[]) to anon, authenticated;

-- ─────────────────────────────── 3. cálculo de UNA tanda (v26.50 + D24) ───────────────────────────────
create or replace function public.gv_picking_tanda_calc(p_tanda text, p_legajo text, p_ep timestamptz, p_tp timestamptz)
returns public."GV_Picking_Tanda"
-- v26.51 (D24): + lineas_cero · cajas_ped · m3_frac; las líneas en 0 no entran a lin/agg/par (sí a gaps: siguen marcando el tiempo)
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
           case when split_part(texto,'|',3) ~ '^[0-9]+(\.[0-9]+)?$' then split_part(texto,'|',3)::numeric end esp,
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
           esp, re, coalesce(emp6, substring(crudo from '\s+(LK|CH)$')) emp, t
      from pk0
  ),
  vol as (select regexp_replace(upper(btrim(codigo)), '^0+(?=.)', '') ck, max(m3) m3 from public.vista_volumen_articulo_resuelto group by 1),
  pkv as (select pk.*, greatest(coalesce(pk.esp, pk.re), pk.re) ped, v.m3 from pk left join vol v on v.ck = pk.ck),
  cero as (  -- v26.51 (D24, Luis 03/10): lo NO pickeado se descuenta. Líneas en 0, cajas pedidas y la fracción (en m³) de lo pickeado
    select count(*) filter (where z.re = 0) n0, sum(z.ped) ped,
           case when sum(z.ped * z.m3c) > 0 then least(1, sum(z.re * z.m3c) / sum(z.ped * z.m3c))
                when sum(z.ped) > 0 then least(1, sum(z.re) / sum(z.ped)) else 1 end frac
      from (select p.*, coalesce(p.m3, avg(p.m3) over (), 0) m3c from pkv p) z
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
     where pk.re > 0   -- v26.51 (D24, Luis): una línea con 0 cajas pickeadas NO cuenta (ni línea, ni parada, ni altura)
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
  select agg.n, agg.cajas, agg.cajas30, par.n, agg.esc, agg.n_mx, agg.n_f, agg.nh, agg.alt_min, pausa.m, huecos.m,
         cero.n0, cero.ped, round(cero.frac::numeric, 4)
    into r.lineas, r.cajas, r.cajas30, r.paradas, r.esc, r.n_mx, r.n_f, r.nh, v_arr, r.pausa_min, r.huecos_min,
         r.lineas_cero, r.cajas_ped, r.m3_frac
    from agg, par, pausa, huecos, cero;

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

-- ─────────────────────────────── 4. refresco (cron) — upsert con las 3 columnas ───────────────────────────────
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
      real_min = excluded.real_min, indice = excluded.indice, calc_at = excluded.calc_at,
      lineas_cero = excluded.lineas_cero, cajas_ped = excluded.cajas_ped, m3_frac = excluded.m3_frac;   -- v26.51
    v_n := v_n + 1;
  end loop;
  return v_n;
end
$fn$;
revoke all on function public.gv_picking_tanda_refresh(int, int) from public, anon, authenticated;
revoke all on function public.gv_picking_tanda_calc(text, text, timestamptz, timestamptz) from public, anon, authenticated;

-- ─────────────────────────────── 5. puntaje por operario — el detalle trae 'cero' y 'frac' ───────────────────────────────
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
  with g as (   -- sólo tandas con picking (líneas), de un turno (EP→TP ≤ 12 h, real ≤ 4 h) y cuyo TP sigue vivo (un TPX la saca sin borrar el caché)
    select t.*, row_number() over (partition by t.legajo order by t.tp desc) rn,
           row_number() over (partition by t.legajo order by t.tp) rn_asc
      from public."GV_Picking_Tanda" t
     where t.tp >= now() - make_interval(days => p_dias) and t.real_min between 0.5 and 240 and t.tamano > 0
       and coalesce(t.lineas, 0) > 0 and t.bruto_min <= 720
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
                   'cajas', g.cajas, 'lineas', g.lineas, 'paradas', g.paradas, 'esc', g.esc, 'cola', round(g.cola_min, 1),
                   'cero', g.lineas_cero, 'frac', g.m3_frac) order by g.tp desc) d
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

-- ─────────────────────────────── 6. chequeo ───────────────────────────────
-- APLICADO el 04/10/2026 (Luis: «no esperes mi sí para aplicar algo que ya te pedí yo»), en dos mitades
-- porque el MCP corta a los 60 s:
--   select public.gv_picking_tanda_refresh(62, 31);   -- 198 tandas
--   select public.gv_picking_tanda_refresh(31, 0);    -- 158 tandas
-- ⚠ El gv_picking_puntaje_operario VIVO traía un filtro de turno que el repo no tenía (otra sesión):
--   real_min between 0.5 and 240 · coalesce(lineas,0) > 0 · bruto_min <= 720. Se trajo la definición viva
--   y se conservó acá (regla «traer la definición viva»).
-- Y los DECILES del grado se recalibraron sobre la dificultad nueva (sin las líneas en 0 la dificultad
-- media bajó de 0,290 a 0,260 y la distribución por grado dejó de ser pareja: 21 a 41 tandas por decil):
--   with g as (select dificultad from public."GV_Picking_Tanda"
--               where tp >= now() - interval '60 days' and real_min between 0.5 and 240 and tamano > 0
--                 and coalesce(lineas, 0) > 0 and bruto_min <= 720 and dificultad is not null),
--    d as (select percentile_cont(array[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9]) within group (order by dificultad) p from g),
--    nv as (select 'decil_' || i clave, round((p[i])::numeric, 4) valor from d, generate_series(1, 9) i),
--    u as (update public."GV_Picking_Esquema" e set valor = nv.valor from nv
--           where e.clave = nv.clave and e.valor is distinct from nv.valor returning e.clave, e.valor)
--   select * from u;
--   -- y después, otra vez el refresh de las dos mitades para que grado y nivel tomen los deciles nuevos.
-- select * from public.gv_reglas_perdidas;   -- vacía
-- select * from public.gv_reglas_perdidas;                                   -- vacía
-- select * from public.gv_picking_pickeado(array['E31A','F54A']);           -- la fracción de cada tanda
-- select tanda, legajo, lineas, lineas_cero, cajas, cajas_ped, m3_frac, grado from public."GV_Picking_Tanda" order by tp desc limit 20;
