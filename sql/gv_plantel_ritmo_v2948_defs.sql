-- v29.48 — definiciones VIVAS (pg_get_functiondef, 12/10) de lo que tocaron D5 · D6 · D7.
-- D7: gv_picking_tanda_calc y gv_picking_estimar suman caja_extra (GV_Picking_Esquema 0,0061 min por caja
--     por encima de 30 por línea; ajuste sobre 386 tandas: MAE 3.436 → 3.418 min, E84A 6 → 30 min contra 32 reales).
--     El caché se ajustó una vez (GV_Picking_Tanda: 83 tandas · GV_Picking_Estimado: 49), llave
--     GV_Picking_Esquema.caja_extra_aplicado. Los grados siguen siendo deciles (34 a 46 tandas por grado).
-- D6: gv_ppp_sin_programar() + gv_ppp_plantel suma lo de A Programar y Cuarentena (pendiente.sin_programar).
-- D5: gv_ppp_plantel con horas_arm por dificultad y gv_ritmo_armado (copia de gv_ritmo_picking sobre GV_Armado_*).
-- REGLA_CONFIRMADA_POR_USUARIO (Thomas 12/10, «dale a todo»: D5, D6, D7)

CREATE OR REPLACE FUNCTION public.gv_picking_tanda_calc(p_tanda text, p_legajo text, p_ep timestamp with time zone, p_tp timestamp with time zone)
 RETURNS "GV_Picking_Tanda"
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
       -- v26.68-ventana (D17): en un tramo de tanda FRENADA, gv_picking_tanda_calc_frenada fija la ventana exacta
       -- (gv.pkc_desde / gv.pkc_hasta) para que un PKC no caiga en dos tramos; sin eso, ±5 min como siempre
       and ts_cliente between coalesce(nullif(current_setting('gv.pkc_desde', true), '')::timestamptz, p_ep - interval '5 min')
                          and coalesce(nullif(current_setting('gv.pkc_hasta', true), '')::timestamptz, p_tp + interval '5 min')
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
            -- v29.48-cajaextra (D7, Thomas 12/10): la caja por encima del tope de la línea también cuesta (pallet entero)
            + coalesce((c->>'caja_extra')::numeric, 0) * greatest(coalesce(r.cajas, 0) - coalesce(r.cajas30, 0), 0)
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
$function$
;

CREATE OR REPLACE FUNCTION public.gv_picking_estimar(p_tandas text[] DEFAULT NULL::text[])
 RETURNS TABLE(tanda text, nps integer, m3 numeric, lineas integer, cajas numeric, cajas30 numeric, paradas integer, esc integer, n_mx integer, n_f integer, tamano numeric, dificultad numeric, grado integer, nivel text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
             + (c->>'parada')::numeric * coalesce(pr.n, 0) + (c->>'caja')::numeric * a.caj30 + a.alt
             + coalesce((c->>'caja_extra')::numeric, 0) * greatest(a.caj - a.caj30, 0) tam   -- v29.48-cajaextra (D7)
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
end $function$
;

CREATE OR REPLACE FUNCTION public.gv_ppp_sin_programar()
 RETURNS TABLE(empresa text, order_id bigint, cod text, fecha_pedido date, m3 numeric, sin_m3 integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- v29.48 (D6, Thomas 12/10): los pedidos de la página que todavía NO tienen tanda — A Programar y
  -- Cuarentena —, con su m³. Mismo universo que A Programar: desde gestion_desde, sin cancelados,
  -- anulados ni clientes de prueba, y sin lo que gv_pedidos_web_excluidos saca (ya está en ISIS).
  with par as (select coalesce((select nullif(valor_texto,'')::date from public."PPP_Web_Config" where clave = 'gestion_desde'), date '9999-12-31') gdesde),
  m as (
    select x.empresa, x.order_id, x.cod_cliente, x.fecha_pedido, x.items_string
      from public.lk_pedidos_match x, par
     where x.fecha_pedido >= par.gdesde
       and not exists (select 1 from public."GV_Web_Cancelados" wc where wc.empresa = x.empresa and wc.order_id = x.order_id)
       and not exists (select 1 from public."GV_Pedidos_Anulados" pa where pa.empresa = x.empresa and pa.order_id = x.order_id)
       and not exists (select 1 from public."GV_Clientes_Prueba" pr
                        where lower(btrim(pr.empresa)) in (x.empresa, case x.empresa when 'chef' then 'ch' end)
                          and regexp_replace(btrim(pr.cod), '^0+', '') = regexp_replace(btrim(coalesce(x.cod_cliente, '')), '^0+', ''))
       and not exists (select 1 from public."PPP_Web_Programacion" p
                        where p.empresa = x.empresa and p.order_id::text = x.order_id::text and coalesce(btrim(p.tanda), '') <> '')
  ),
  ex as (select e.empresa, e.order_id from public.gv_pedidos_web_excluidos(
           (select coalesce(jsonb_agg(jsonb_build_object('empresa', m.empresa, 'order_id', m.order_id, 'cod', m.cod_cliente,
                                                         'fecha_recep', m.fecha_pedido)), '[]'::jsonb) from m)) e),
  it as (
    select m.empresa, m.order_id,
           regexp_replace(regexp_replace(regexp_replace(upper(btrim(z.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', ''), '^0+(?=.)', '') ck,
           (z.r[2])::numeric cajas
      from m
      cross join lateral unnest(string_to_array(coalesce(m.items_string, ''), ',')) t(item)
      cross join lateral (select regexp_match(btrim(t.item), '^(.+)x([0-9]+(?:\.[0-9]+)?)$') r) z
     where z.r is not null),
  vol as (select regexp_replace(upper(btrim(codigo)), '^0+(?=.)', '') ck, max(m3) m3 from public.vista_volumen_articulo_resuelto group by 1)
  select m.empresa, m.order_id, m.cod_cliente, m.fecha_pedido,
         round(coalesce((select sum(it.cajas * v.m3) from it join vol v on v.ck = it.ck where it.empresa = m.empresa and it.order_id = m.order_id), 0), 3),
         (select count(*)::int from it left join vol v on v.ck = it.ck where it.empresa = m.empresa and it.order_id = m.order_id and v.m3 is null)
    from m
   where not exists (select 1 from ex where ex.empresa = m.empresa and ex.order_id = m.order_id)
$function$
;

CREATE OR REPLACE FUNCTION public.gv_ppp_plantel(p_semana integer DEFAULT 1, p_semanas integer DEFAULT 4, p_meta integer DEFAULT 10, p_dias_antes integer DEFAULT 2)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_lun date; v_ini date; v_fin date; v_hab int; v_hab_antes int;
  v_hist_desde date; v_hist_hasta date;
  h record; v_dem numeric; v_back jsonb; v_pend record;
  v_rpick numeric; v_rarm numeric; v_m3dia_pick numeric; v_m3dia_arm numeric;
  v_a_pick numeric; v_a_arm numeric; v_b numeric;
  v_dias jsonb;
  v_est_hist_a numeric; v_fa numeric; v_hpm3a numeric; v_ob_min_a numeric; v_h_ob_a numeric; v_h_na_a numeric; v_h_arm numeric;
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
  ), a0 as (
    select ar.np::text np, ar.tanda::text tanda, ar.m3::numeric m3, ar.estado::text estado, ar.fecha::date fecha,
           ar.fecha_pedido::date fecha_pedido, false sp
      from public.gv_ppp_prog_arbol(v_hoy - 60, v_hoy + 90) ar
     where ar.estado in ('pendiente', 'proceso') and coalesce(ar.m3, 0) > 0
    union all
    -- v29.48-sinprog (D6, Thomas 12/10): también lo que espera en A Programar y en Cuarentena (sin tanda
    -- ni fecha): su plazo corre igual desde la fecha del pedido y hay que pickearlo y armarlo entero.
    select 'web ' || upper(s.empresa) || ' ' || s.order_id, null::text, s.m3, 'pendiente', null::date, s.fecha_pedido, true
      from public.gv_ppp_sin_programar() s where s.m3 > 0
  ), a as (
    select a0.*, (select min(c.i) from cal c where c.d > a0.fecha_pedido) + p_meta - 1 i_salida from a0
  ), b as (
    select a.*, (select c.d from cal c where c.i = a.i_salida - greatest(p_dias_antes, 0)) limite_armado,
           -- v29.47: los minutos estimados por dificultad (D17) de su tanda, prorrateados por m³
           (select ge.tamano * a.m3 / nullif(ge.m3, 0) from public."GV_Picking_Estimado" ge
             where ge.tanda = upper(btrim(a.tanda))) est_min,
           -- v29.48-armdif (D5): lo mismo con el modelo de ARMADO
           (select ga.tamano * a.m3 / nullif(ga.m3, 0) from public."GV_Armado_Estimado" ga
             where ga.tanda = upper(btrim(a.tanda))) est_arm
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
         coalesce(sum(est_arm) filter (where limite_armado <= v_fin), 0) oblig_arm_min,
         coalesce(sum(m3) filter (where limite_armado <= v_fin and est_arm is null), 0) oblig_arm_sin_est,
         coalesce(sum(m3) filter (where limite_armado <= v_fin and est_arm is not null), 0) oblig_arm_con_est,
         coalesce(sum(m3) filter (where limite_armado < v_hoy), 0) m3_vencido,
         count(*) filter (where limite_armado < v_hoy) nps_vencidas,
         min(fecha_pedido) pedido_mas_viejo,
         (select count(*) from cal c where c.d > min(b.fecha_pedido) and c.d <= v_hoy) habiles_mas_viejo,
         max(fecha) ultima_fecha_prog,
         count(*) filter (where sp) sp_n, coalesce(sum(m3) filter (where sp), 0) sp_m3,
         coalesce(sum(m3) filter (where sp and limite_armado < v_hoy), 0) sp_venc,
         count(*) filter (where sp and limite_armado < v_hoy) sp_n_venc,
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

  -- v29.48-armdif — ARMADO POR DIFICULTAD, mismo esquema que el picking. F = horas de armado del monitor ÷
  -- minutos estimados de las tandas con su 1.er TAP en la historia (frenadas incluidas: sus horas están en el monitor).
  select coalesce(sum(e.tamano_inicial), 0) into v_est_hist_a
    from public."GV_Armado_Estimado" e
   where e.tanda in (select upper(btrim(x.texto)) from public."Registros_Produccion_Virgilio" x
                      where x.opcion = 'TAP' and x.legajo::text not in ('0','1')
                      group by 1
                     having (min(x.ts_cliente) at time zone 'America/Argentina/Buenos_Aires')::date between v_hist_desde and v_hist_hasta);
  v_fa := case when v_est_hist_a > 0 then h.harm * 60 / v_est_hist_a end;
  v_hpm3a := case when h.m3arm > 0 then h.harm / h.m3arm end;
  v_ob_min_a := greatest(v_pend.oblig_arm_min - v_hab_antes * (case when h.dias > 0 then v_est_hist_a / h.dias else 0 end), 0);
  v_h_ob_a := case when v_fa is not null then v_ob_min_a * v_fa / 60 + coalesce(v_pend.oblig_arm_sin_est, 0) * coalesce(v_hpm3a, 0) end;
  v_h_na_a := v_b * coalesce(v_hpm3a, 0);
  v_h_arm := greatest(coalesce(v_h_ob_a, v_a_arm * coalesce(v_hpm3a, 0)), v_h_na_a);

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
        'por_semana_limite', v_back,
        'sin_programar', jsonb_build_object('pedidos', v_pend.sp_n, 'm3', round(v_pend.sp_m3, 2),
            'm3_vencido', round(v_pend.sp_venc, 2), 'pedidos_vencidos', v_pend.sp_n_venc)),
    'semana', jsonb_build_object(
        'oblig_pick', round(v_a_pick, 2), 'oblig_arm', round(v_a_arm, 2), 'no_acumular', round(v_b, 2),
        'm3_pick', round(greatest(v_a_pick, v_b), 2), 'm3_arm', round(greatest(v_a_arm, v_b), 2),
        'horas_pick', round(v_h_pick, 2), 'horas_pick_oblig', round(v_h_ob, 2), 'horas_pick_noacum', round(v_h_na, 2),
        'factor_real', round(v_f, 3), 'oblig_pick_min_est', round(v_ob_min, 1),
        'min_m3_est_oblig', round(v_pend.oblig_pick_min / nullif(v_pend.oblig_pick_con_est, 0), 1),
        'min_m3_est_hist', round(v_est_hist / nullif(h.m3pick, 0), 1),
        'oblig_pick_sin_est_m3', round(v_pend.oblig_pick_sin_est, 2),
        'horas_arm', round(v_h_arm, 2), 'horas_arm_oblig', round(v_h_ob_a, 2), 'horas_arm_noacum', round(v_h_na_a, 2),
        'factor_real_arm', round(v_fa, 3), 'oblig_arm_min_est', round(v_ob_min_a, 1),
        'min_m3_est_oblig_arm', round(v_pend.oblig_arm_min / nullif(v_pend.oblig_arm_con_est, 0), 1),
        'min_m3_est_hist_arm', round(v_est_hist_a / nullif(h.m3arm, 0), 1),
        'oblig_arm_sin_est_m3', round(v_pend.oblig_arm_sin_est, 2))
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.gv_ritmo_armado(p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
-- v29.48 (D5): el MISMO cálculo que gv_ritmo_picking (copiado de su definición viva), sobre el armado:
-- esperado = tamaño del modelo de armado con lo que se armó · estimado inicial = la 1.ª foto antes de armar ·
-- real = AP→TAP − pausas + cola ≤ 30 · monitor = horas de armado de gv_monitor_horas_operario_dia.
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
      from public."GV_Armado_Tanda" t
     where (t.tp at time zone 'America/Argentina/Buenos_Aires')::date between v_desde and v_hasta
       and t.legajo not in ('0', '1')
  ), _r_sum as (select p.tanda, sum(p.tamano) tam_t from _r_pt p group by 1),
  _r_x as (
    select p.*, e.tamano_inicial * p.tamano / nullif(s.tam_t, 0) est_ini, coalesce(e.reconstruido, true) recon,
           e.tamano_inicial is not null tiene_ini
      from _r_pt p join _r_sum s using (tanda)
      left join public."GV_Armado_Estimado" e on e.tanda = p.tanda
  ), _r_mon as (
    select o.dia, o.legajo, o.nombre, o.hs_arm from public."GV_Plantel_Operario_Dia" o
     where o.dia between v_desde and v_hasta and o.dia < v_hoy
    union all
    select v_hoy, x.legajo, x.nombre, x.hs_arm from public.gv_monitor_horas_operario_dia(v_hoy) x
     where v_hoy between v_desde and v_hasta and x.legajo not in ('0', '1') and x.legajo !~ '^sup:'
  ), _r_g as (
    select coalesce(x.dia, m.dia) dia, coalesce(x.legajo, m.legajo) legajo,
           max(m.nombre) nombre, max(m.hs_arm) hs_mon,
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
end $function$
;

revoke all on function public.gv_ppp_sin_programar() from public, anon, authenticated;
grant execute on function public.gv_ritmo_armado(date,date) to anon, authenticated;
insert into public."GV_Picking_Esquema"(clave, valor, nota, updated_at)
values ('caja_extra', 0.0061, 'min por caja POR ENCIMA de tope_cajas_linea en cada línea (pallet entero; v29.48, ajustado sobre 386 tandas)', now())
on conflict (clave) do nothing;
