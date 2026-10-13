-- v29.48 — ARMADO POR DIFICULTAD (D5, Thomas 12/10: «dale a todo»)
-- Mismo molde que el picking (D17 + v29.47): un TAMAÑO esperado en minutos por tanda, calculado de lo que
-- se armó (esperado) y de lo que dice el pedido antes de armar (estimado), contra el tiempo real.
--
--   tamaño = arm_np × NP + arm_linea × líneas + arm_caja × cajas (hasta 30 por línea)
--          + arm_caja_extra × cajas de 30 a arm_tope_extra por línea + arm_super (si es súper)
--   real   = TAP − AP − pausas declaradas + cola hasta la próxima tarea (topeada a 30 min)
--
-- Coeficientes: NNLS sobre las tandas armadas en 75 días (sin APF), con el real de esta misma función
-- (docs/armado-dificultad/fit_armado.py). Viven en GV_Picking_Esquema con prefijo arm_: recalibrar = UPDATE.
-- ⚠ Una tanda FRENADA en armado (APF) no se mide: sus líos los cerraron dos personas.
-- ⚠ No hay huecos medibles: el armado manda TAL / ENT recién al terminar.
--
-- Rollback:
--   update cron.job … (ver el command viejo del 155 abajo) · drop de las funciones gv_armado_* y de
--   "GV_Armado_Tanda" / "GV_Armado_Estimado" · delete de GV_Picking_Esquema where clave like 'arm\_%'.

insert into public."GV_Picking_Esquema"(clave, valor, nota, updated_at) values
  ('arm_np',         1.4834, 'armado: min por NP (abrir el pedido, rótulo, cerrar)', now()),
  ('arm_linea',      0.8931, 'armado: min por línea (código de una NP)', now()),
  ('arm_caja',       0.3099, 'armado: min por caja, hasta arm_tope_linea por línea', now()),
  ('arm_caja_extra', 0.1527, 'armado: min por caja de arm_tope_linea a arm_tope_extra por línea (pallet)', now()),
  ('arm_tope_linea', 30,     'armado: cajas por línea en el término por caja', now()),
  ('arm_tope_extra', 330,    'armado: cajas por línea hasta donde cuenta la caja extra (un pallet de 4.000 no son 600 min)', now()),
  ('arm_super',      31.3093,'armado: min fijos si la tanda es de un súper (rótulos, etiquetas, pallet)', now())
on conflict (clave) do nothing;

create table if not exists public."GV_Armado_Tanda" (
  tanda text not null, legajo text not null, ep timestamptz, tp timestamptz,
  nps int, lineas int, cajas numeric, cajas30 numeric, extra numeric, super boolean,
  tamano numeric, grado int, nivel text,
  bruto_min numeric, pausa_min numeric, cola_min numeric, cola_tipo text, real_min numeric, indice numeric,
  calc_at timestamptz not null default now(),
  primary key (tanda, legajo)
);
alter table public."GV_Armado_Tanda" enable row level security;   -- sin policy: sólo las funciones

create table if not exists public."GV_Armado_Estimado" (
  tanda text primary key, nps int, m3 numeric, lineas int, cajas numeric, super boolean,
  tamano numeric, grado int, nivel text,
  tamano_inicial numeric, grado_inicial int, nivel_inicial text, m3_inicial numeric,
  estimado_inicial_at timestamptz not null default now(), estimado_at timestamptz not null default now(),
  reconstruido boolean not null default false
);
alter table public."GV_Armado_Estimado" enable row level security;

-- la cuenta del tamaño, UNA sola vez (la usan el cálculo post-armado y el estimador)
create or replace function public.gv_armado_tamano(p_nps numeric, p_lineas numeric, p_cajas30 numeric, p_extra numeric, p_super boolean)
returns numeric language sql stable security definer set search_path = public as $$
  with c as (select jsonb_object_agg(clave, valor) j from public."GV_Picking_Esquema" where clave like 'arm\_%')
  select coalesce((c.j->>'arm_np')::numeric, 0) * coalesce(p_nps, 0)
       + coalesce((c.j->>'arm_linea')::numeric, 0) * coalesce(p_lineas, 0)
       + coalesce((c.j->>'arm_caja')::numeric, 0) * coalesce(p_cajas30, 0)
       + coalesce((c.j->>'arm_caja_extra')::numeric, 0) * coalesce(p_extra, 0)
       + case when p_super then coalesce((c.j->>'arm_super')::numeric, 0) else 0 end
    from c
$$;

create or replace function public.gv_armado_tanda_calc(p_tanda text, p_legajo text, p_ap timestamptz, p_tap timestamptz)
returns public."GV_Armado_Tanda" language plpgsql stable security definer set search_path = public as $$
declare
  r public."GV_Armado_Tanda"%rowtype; c jsonb; v_t30 numeric; v_tx numeric; v_ctope numeric;
  v_sig timestamptz; v_cub boolean; v_ult timestamptz;
begin
  select jsonb_object_agg(clave, valor) into c from public."GV_Picking_Esquema";
  v_t30 := coalesce((c->>'arm_tope_linea')::numeric, 30);
  v_tx := coalesce((c->>'arm_tope_extra')::numeric, 330);
  v_ctope := coalesce((c->>'cola_tope_min')::numeric, 30);
  r.tanda := upper(btrim(p_tanda)); r.legajo := p_legajo; r.ep := p_ap; r.tp := p_tap;

  select count(distinct e.np)::int, count(*) filter (where e.cajas_entregadas > 0)::int,
         coalesce(sum(e.cajas_entregadas), 0),
         coalesce(sum(least(e.cajas_entregadas, v_t30)) filter (where e.cajas_entregadas > 0), 0),
         coalesce(sum(least(greatest(e.cajas_entregadas - v_t30, 0), v_tx - v_t30)) filter (where e.cajas_entregadas > 0), 0),
         coalesce(bool_or(public.gv_es_super(coalesce(e.gv_empresa, case when e.np ~* '^CH' then 'chef' else 'lk' end), e.cod_cliente)), false)
    into r.nps, r.lineas, r.cajas, r.cajas30, r.extra, r.super
    from public."Entregas_Virgilio" e
   where upper(btrim(e.tanda)) = r.tanda;
  r.tamano := public.gv_armado_tamano(r.nps, r.lineas, r.cajas30, r.extra, r.super);

  r.bruto_min := extract(epoch from p_tap - p_ap) / 60;
  select coalesce(sum(extract(epoch from least(x.ts_cliente, p_tap) - greatest(x.ts_inicio, p_ap))), 0) / 60 into r.pausa_min
    from public."Registros_Produccion_Virgilio" x
   where x.legajo::text = p_legajo and x.opcion in ('AT','PB','Limp','PC','CT','Perm') and x.ts_inicio is not null
     and x.ts_cliente > p_ap and x.ts_inicio < p_tap;
  -- la cola hasta la próxima tarea: el mismo criterio que el picking (v26.43)
  select min(coalesce(x.ts_inicio, x.ts_cliente)) into v_sig
    from public."Registros_Produccion_Virgilio" x
   where x.legajo::text = p_legajo and x.ts_cliente > p_tap and coalesce(x.ts_inicio, x.ts_cliente) > p_tap
     and (x.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = (p_tap at time zone 'America/Argentina/Buenos_Aires')::date
     and x.opcion not in ('PUB','AUB','PKC','ENT','RSP','ROC','RAG','FGU','FSS','IMPT','TAL','GST','MGR','PKM','SSG','PSP','NPD','PKAX')
     and x.opcion !~ 'X$';
  select exists (select 1 from public."Registros_Produccion_Virgilio" x
                  where x.legajo::text = p_legajo and x.ts_inicio is not null and x.ts_inicio < p_tap and x.ts_cliente > p_tap
                    and not (x.opcion = 'TAP' and upper(btrim(x.texto)) = r.tanda)) into v_cub;
  if v_cub then r.cola_min := 0; r.cola_tipo := 'cubierta';
  elsif v_sig is not null then r.cola_min := extract(epoch from v_sig - p_tap) / 60; r.cola_tipo := 'sig';
  else
    select max(x.ts_cliente) into v_ult from public."Registros_Produccion_Virgilio" x
     where x.legajo::text = p_legajo
       and (x.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date = (p_tap at time zone 'America/Argentina/Buenos_Aires')::date;
    r.cola_min := greatest(0, extract(epoch from coalesce(v_ult, p_tap) - p_tap) / 60); r.cola_tipo := 'cap';
  end if;
  r.real_min := greatest(0, r.bruto_min - coalesce(r.pausa_min, 0)) + least(coalesce(r.cola_min, 0), v_ctope);
  r.indice := case when r.real_min > 0.5 then round(r.tamano / r.real_min, 3) end;
  r.calc_at := now();
  return r;
end $$;

create or replace function public.gv_armado_tanda_refresh(p_dias int default 3, p_hasta_dias int default 0)
returns int language plpgsql security definer set search_path = public as $$
declare v_n int := 0; t record; r public."GV_Armado_Tanda"%rowtype;
begin
  for t in
    select distinct on (upper(btrim(x.texto))) upper(btrim(x.texto)) tanda, x.legajo::text leg, x.ts_inicio ap, x.ts_cliente tap
      from public."Registros_Produccion_Virgilio" x
     where x.opcion = 'TAP' and x.ts_inicio is not null and x.ts_cliente > x.ts_inicio
       and x.legajo::text not in ('0','1') and x.legajo::text !~ '^sup:'
       and x.ts_cliente >= now() - make_interval(days => p_dias) and x.ts_cliente < now() - make_interval(days => p_hasta_dias)
       and not exists (select 1 from public."Registros_Produccion_Virgilio" f where f.opcion = 'APF' and upper(btrim(f.texto)) = upper(btrim(x.texto)))
     order by upper(btrim(x.texto)), x.ts_cliente     -- el PRIMER TAP (un 2.º TAP de la misma tanda no es otro armado)
  loop
    r := public.gv_armado_tanda_calc(t.tanda, t.leg, t.ap, t.tap);
    insert into public."GV_Armado_Tanda" as g select r.*
    on conflict (tanda, legajo) do update set ep = excluded.ep, tp = excluded.tp, nps = excluded.nps, lineas = excluded.lineas,
      cajas = excluded.cajas, cajas30 = excluded.cajas30, extra = excluded.extra, super = excluded.super, tamano = excluded.tamano,
      bruto_min = excluded.bruto_min, pausa_min = excluded.pausa_min, cola_min = excluded.cola_min, cola_tipo = excluded.cola_tipo,
      real_min = excluded.real_min, indice = excluded.indice, calc_at = excluded.calc_at;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- el ESTIMADO antes de armar: líneas del pedido (PPP_Web_Base / base de ISIS) por NP y código
create or replace function public.gv_armado_estimar(p_tandas text[] default null)
returns table(tanda text, nps int, m3 numeric, lineas int, cajas numeric, cajas30 numeric, extra numeric, super boolean, tamano numeric)
language plpgsql stable security definer set search_path = public as $$
declare c jsonb; v_t30 numeric; v_tx numeric;
  v_hoy date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  select jsonb_object_agg(e.clave, e.valor) into c from public."GV_Picking_Esquema" e;
  v_t30 := coalesce((c->>'arm_tope_linea')::numeric, 30);
  v_tx := coalesce((c->>'arm_tope_extra')::numeric, 330);
  return query
  with _a_np as materialized (
    select upper(btrim(ar.tanda)) tnd, ar.np, coalesce(ar.m3, 0) m3np, lower(coalesce(ar.empresa, '')) empr, ar.cod
      from public.gv_ppp_prog_arbol(v_hoy - 60, v_hoy + 90) ar
     where coalesce(ar.tanda, '') <> ''
       and ((p_tandas is null and ar.estado in ('pendiente', 'proceso')) or upper(btrim(ar.tanda)) = any (p_tandas))
  ),
  _a_it0 as (
    select n.tnd, n.np, upper(btrim(w.articulo)) crudo, coalesce(w.cajas, 0)::numeric caj
      from _a_np n join public."PPP_Web_Base" w on w.np_label = n.np
    union all
    select n.tnd, n.np, upper(btrim(b.articulo)), coalesce(b.cajas, 0)::numeric
      from _a_np n join public.gv_ppp_base_pedidos b on b.pedido::text = n.np
     where not exists (select 1 from public."PPP_Web_Base" w2 where w2.np_label = n.np)
  ),
  _a_it as (
    select x.tnd, x.np, regexp_replace(regexp_replace(x.crudo, '\s+(LK|CH)$', ''), '^0+(?=.)', '') ck, sum(x.caj) re
      from _a_it0 x group by 1, 2, 3 having sum(x.caj) > 0
  ),
  _a_l as (
    select i.tnd, count(*)::int n, sum(i.re) caj, sum(least(i.re, v_t30)) c30,
           sum(least(greatest(i.re - v_t30, 0), v_tx - v_t30)) ext
      from _a_it i group by 1
  ),
  _a_t as (
    select n.tnd, count(distinct n.np)::int nps, sum(n.m3np) m3,
           coalesce(bool_or(public.gv_es_super(case when n.empr in ('chef','ch') then 'chef' else 'lk' end, n.cod)), false) sup
      from _a_np n group by 1
  )
  select t.tnd, t.nps, round(t.m3, 3), l.n, l.caj, l.c30, l.ext, t.sup,
         round(public.gv_armado_tamano(t.nps, l.n, l.c30, l.ext, t.sup), 2)
    from _a_t t join _a_l l on l.tnd = t.tnd;
end $$;

create or replace function public.gv_armado_estimar_snapshot()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public."GV_Armado_Estimado" as g (tanda, nps, m3, lineas, cajas, super, tamano,
         tamano_inicial, m3_inicial, estimado_inicial_at, estimado_at)
  select e.tanda, e.nps, e.m3, e.lineas, e.cajas, e.super, e.tamano, e.tamano, e.m3, now(), now()
    from public.gv_armado_estimar(null) e
   where not exists (select 1 from public."GV_Armado_Tanda" t where t.tanda = e.tanda)
  on conflict (tanda) do update set nps = excluded.nps, m3 = excluded.m3, lineas = excluded.lineas, cajas = excluded.cajas,
     super = excluded.super, tamano = excluded.tamano, estimado_at = now()
   where not g.reconstruido;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.gv_armado_tamano(numeric,numeric,numeric,numeric,boolean) from public, anon, authenticated;
revoke all on function public.gv_armado_tanda_calc(text,text,timestamptz,timestamptz) from public, anon, authenticated;
revoke all on function public.gv_armado_tanda_refresh(int,int) from public, anon, authenticated;
revoke all on function public.gv_armado_estimar(text[]) from public, anon, authenticated;
revoke all on function public.gv_armado_estimar_snapshot() from public, anon, authenticated;

-- ─── cron: el 155 (gv-picking-estimar) ahora también refresca el armado ───────────────────────────
-- command anterior: do $b$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_picking_estimar_snapshot')::bigint) then
--                     perform public.gv_picking_estimar_snapshot(); end if; end $b$;
select cron.alter_job(155, command := $c$do $b$ begin if pg_try_advisory_xact_lock(hashtext('cron:gv_picking_estimar_snapshot')::bigint) then
       perform public.gv_picking_estimar_snapshot();
       perform public.gv_armado_tanda_refresh(2, 0);      -- v29.48: armado por dificultad
       perform public.gv_armado_estimar_snapshot(); end if; end $b$;$c$);

-- backfill (12/10): gv_armado_tanda_refresh(90) = 476 tandas · GV_Armado_Estimado reconstruido = true para las
-- tandas con TAP en 40 días (estimadas con sus líneas de pedido) · 39 vivas sin armar.
-- Coeficientes finales (UPDATE de GV_Picking_Esquema, NNLS 426 tandas medibles con el real de gv_armado_tanda_calc):
--   arm_np 5,0628 · arm_linea 0,6068 · arm_caja 0,3515 · arm_caja_extra 0,0757 · arm_super 30,4257
--   corr 0,845 · MAE 17,5 min (CV 17,8) sobre una mediana de 50 min · esperado/real 1,005.
--   Estimado ANTES de armar (líneas del pedido) contra el real: corr 0,848 · 1,021 (159 tandas de 35 días).
