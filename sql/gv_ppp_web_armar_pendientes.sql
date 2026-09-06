-- ═══════════════════════════════════════════════════════════════════════════════════════
-- "MANDÁ DIRECTO A PROGRAMACIÓN SI YA ESTÁ. NO MÁS EN A PROGRAMAR" · v13.47 (2026-09-06 domingo)
-- Migración: gv_ppp_web_armar_pendientes_v1347
--
-- Dueño (domingo 06/09, 15:50, viendo A Programar con 4 pedidos que decían "se arma solo →
-- lun 14/9" y "hay camión el lun 14/9 · programalo"): *"Mandá directo a Programación si ya
-- está. No más en A Programar."*
--
-- Hasta acá el job (00:01) y el intradía (cada 15 min) armaban UNA fecha por corrida
-- (`ppp_web_armar_tandas(p_fecha)`): lo que no entraba por cupo quedaba en A Programar con
-- un pronóstico ("→ lun 14/9") hasta la corrida que cayera en ese día. Y las zonas manuales
-- (4/5/6/7) NUNCA se armaban solas aunque hubiera camión a la zona ese día: el chip decía
-- "hay camión el vie 11/9 · programalo" y esperaba a una persona.
--
-- Desde v13.47, en cada corrida, TODO lo que tiene un día previsible se programa YA:
--   · zona automática (1/2/3) → cascada: el primer día con cupo, y lo que no entra al
--     siguiente día con cupo, y así (hasta 8 días armados por corrida).
--   · zona manual (4/5/6/7) → si hay camión a esa zona (tanda web o de ISIS) desde el día
--     mínimo, se arma para ESE día (entra como prioritario: el camión ya va; no espera cupo).
--   · Retira, Súper y sin zona → siguen a mano (no hay día previsible).
-- Lo único que queda en A Programar es lo que de verdad no tiene dónde ir.
--
-- Además: NUMERACIÓN DE TANDAS COMO PRODUCCIÓN. `ppp_web_armar_tandas` tomaba una letra
-- NUEVA por llamada (E01A el domingo, F01A Chef, la próxima corrida G01A…). Con varias
-- fechas por corrida se quemaba el abecedario en un mes. Ahora sigue la cuenta de camión
-- dentro de la misma letra (E01A → E02A → E03A…, como D56A…D71A de Producción) y pasa de
-- letra recién en el camión 99.
--
-- Objetos (todos nuestros; Producción no los llama — grep 0 en el repo de Producción):
--   gv_ppp_web_proximo_dia_con_cupo(p_desde)      nueva
--   gv_ppp_web_proximo_dia_entrega(p_ahora)       ahora delega en la de arriba (misma regla)
--   gv_ppp_web_dia_camion(p_zona, p_desde)         nueva: primer día ≥ p_desde con camión a la zona
--   gv_ppp_web_letra_y_camion()                    nueva: letra vigente + último nº de camión
--   ppp_web_armar_tandas(…, p_incluir_manuales)    firma nueva (5 args; se dropea la de 4)
--   gv_ppp_web_armar_pendientes(…)                 nueva: la cascada + manuales; la llama la Edge Fn
--   gv_ppp_web_armar_pendientes_simular(…)         nueva: lo mismo sin escribir (rollback por excepción)
-- Rollback al final.
-- ═══════════════════════════════════════════════════════════════════════════════════════

-- ── 1. próximo día hábil con cupo a partir de una fecha ─────────────────────────────────
create or replace function public.gv_ppp_web_proximo_dia_con_cupo(p_desde date)
returns date language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_d     date := coalesce(p_desde, current_date);
  v_usado numeric;
  v_i     int := 0;
begin
  loop
    v_i := v_i + 1;
    if public.gv_es_dia_habil(v_d) then
      select coalesce(sum(m3), 0) into v_usado
        from public."PPP_Web_Programacion"
       where fecha_entrega = v_d and coalesce(nullif(trim(tanda), ''), '') <> '';
      v_usado := v_usado + public.gv_ppp_web_m3_isis(v_d);
      if v_usado < public.gv_ppp_web_cupo(v_d) then return v_d; end if;
    end if;
    v_d := v_d + 1;
    exit when v_i > 120;
  end loop;
  return v_d;
end $$;
revoke all on function public.gv_ppp_web_proximo_dia_con_cupo(date) from public, anon;
grant execute on function public.gv_ppp_web_proximo_dia_con_cupo(date) to authenticated, service_role;

-- La de siempre (job 00:01 / intradía / A Programar) = la misma regla desde el día mínimo.
create or replace function public.gv_ppp_web_proximo_dia_entrega(p_ahora timestamptz default now())
returns date language sql stable security definer set search_path = public, pg_temp as $$
  select public.gv_ppp_web_proximo_dia_con_cupo(public.gv_ppp_web_dia_minimo(p_ahora));
$$;

-- ── 2. ¿qué día hay camión a una zona? (misma regla que gv_ppp_web_dia_salida) ──────────
-- Camión = tanda web con fecha o tanda de ISIS (gv_ppp_programacion_diaria) de la MISMA zona
-- numérica, desde p_desde. Sólo zonas "Zona N": Retira/Súper/sin zona → null.
create or replace function public.gv_ppp_web_dia_camion(p_zona text, p_desde date)
returns date language sql stable security definer set search_path = public, pg_temp as $$
  with zn as (select (regexp_match(btrim(coalesce(p_zona, '')), '^Zona\s*([0-9]+)'))[1] as n)
  select min(dia) from (
    select w.fecha_entrega as dia
      from public."PPP_Web_Programacion" w, zn
     where zn.n is not null
       and w.fecha_entrega >= p_desde
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and (regexp_match(btrim(coalesce(w.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date
      from public.gv_ppp_programacion_diaria i, zn
     where zn.n is not null
       and btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date >= p_desde
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and (regexp_match(btrim(coalesce(i.zona, '')), '^Zona\s*([0-9]+)'))[1] = zn.n
  ) d;
$$;
revoke all on function public.gv_ppp_web_dia_camion(text, date) from public, anon;
grant execute on function public.gv_ppp_web_dia_camion(text, date) to authenticated, service_role;

-- ── 3. letra vigente + último camión (numeración como Producción) ───────────────────────
-- Mira las mismas tres tablas que ppp_web_proxima_letra(). Devuelve la letra más alta usada
-- y el mayor NN bajo esa letra. Si NN ya es 99, pasa a la letra siguiente con NN = 0.
create or replace function public.gv_ppp_web_letra_y_camion(out letra int, out camion int)
language plpgsql stable set search_path = public, pg_temp as $$
declare r record;
begin
  select public.ppp_web_letra_idx(m[1]) as idx, (m[2])::int as nn
    into r
    from (
      select regexp_match(tanda, '^([A-Z]+)([0-9]+)[A-Z]+$') as m from public."PPP_Programacion_Diaria" where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
      union all
      select regexp_match(tanda, '^([A-Z]+)([0-9]+)[A-Z]+$') from public."PPP_Web_Programacion" where tanda ~ '^[A-Z]+[0-9]+[A-Z]+$'
      union all
      select regexp_match(codigo, '^([A-Z]+)([0-9]+)[A-Z]+$') from public."PPP_Web_Tandas" where codigo ~ '^[A-Z]+[0-9]+[A-Z]+$' and estado <> 'descartada'
    ) t
   order by public.ppp_web_letra_idx(m[1]) desc, (m[2])::int desc
   limit 1;
  if not found or r.idx is null then letra := 0; camion := 0; return; end if;
  if r.nn >= 99 then letra := r.idx + 1; camion := 0;
  else letra := r.idx; camion := r.nn; end if;
end $$;
revoke all on function public.gv_ppp_web_letra_y_camion() from public, anon;
grant execute on function public.gv_ppp_web_letra_y_camion() to authenticated, service_role;

-- ── 4. ppp_web_armar_tandas v5: + p_incluir_manuales, numeración continua ──────────────
-- Cuerpo = el de la base al 2026-09-06 (v4 sectores + parches v13.23 cupo/ISIS y v13.25
-- where true) con tres cambios marcados "v13.47".
drop function if exists public.ppp_web_armar_tandas(text, date, jsonb, text[]);

create or replace function public.ppp_web_armar_tandas(
  p_empresa text,
  p_fecha date default current_date,
  p_filas jsonb default '[]'::jsonb,
  p_forzar_cods text[] default '{}',
  p_incluir_manuales boolean default false)
returns table (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int)
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  v_tope   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_m3_max_mezcla'), 0.80);
  v_cupo   numeric := public.gv_ppp_web_cupo(p_fecha);   -- v13.23: cupo por dotación
  v_dias   int     := coalesce((select valor from public."PPP_Web_Config" where clave='dias_hasta_entrega'), 0)::int;
  v_saltar boolean := coalesce((select valor from public."PPP_Web_Config" where clave='saltar_fin_de_semana'), 1) <> 0;
  v_pref   text    := coalesce((select valor_texto from public."PPP_Web_Config" where clave='tanda_prefijo'), '');
  -- v13.47: la letra vigente y el último camión (E01A → E02A…), no una letra nueva por llamada
  v_letra  int;
  v_zn0    int;
  v_sect   boolean := coalesce((select valor from public."PPP_Web_Config" where clave='sectores_activos'), 1) <> 0;
  v_fecha  date;
  v_usado  numeric;
  v_resta  numeric;
  v_acumsel numeric := 0;
  v_grupo  text;
  v_zn     int := 0;
  v_ti     int;
  v_code   text;
  v_acum   numeric;
  v_cierra boolean;
  r_cli    record;
begin
  -- Con prefijo (GV-…) la letra no se usa; sin prefijo, se sigue la cuenta de Producción.
  select lc.letra, lc.camion into v_letra, v_zn0 from public.gv_ppp_web_letra_y_camion() lc;
  if v_pref <> '' then v_zn0 := 0; end if;
  v_zn := v_zn0;

  v_fecha := p_fecha + v_dias;
  if v_saltar then
    while extract(dow from v_fecha) in (0, 6) loop v_fecha := v_fecha + 1; end loop;
  end if;

  drop table if exists _sin_tanda;
  drop table if exists _sel;
  drop table if exists _asig;
  drop table if exists _open;
  drop table if exists _open_stops;
  drop table if exists _cam;

  create temp table _sin_tanda on commit drop as
  select (x->>'order_id')::bigint as order_id,
         (x->>'np_idx')::int      as np_idx,
         nullif(x->>'np','')::int as np,
         coalesce(nullif(x->>'zona',''), '(sin zona)') as zona,
         public.gv_ppp_web_grupo_zona(coalesce(nullif(x->>'zona',''), '(sin zona)')) as grupo,
         public.gv_ppp_web_sector(coalesce(nullif(x->>'zona',''), '(sin zona)'),
                                  nullif(x->>'barrio',''), nullif(x->>'direccion','')) as sector,
         public.gv_ppp_web_barrio_norm(nullif(x->>'barrio',''), nullif(x->>'direccion','')) as bnorm,
         coalesce(nullif(x->>'cod',''), nullif(x->>'razon_social',''), '?') as cliente,
         nullif(x->>'razon_social','') as razon_social,
         nullif(x->>'direccion','')    as direccion,
         nullif(x->>'barrio','')       as barrio,
         coalesce(nullif(x->>'fecha_recep','')::date, current_date) as fecha_recep,
         coalesce(nullif(x->>'m3','')::numeric, 0)    as m3,
         coalesce((x->>'m3_parcial')::boolean, false) as m3_parcial,
         nullif(x->>'lineas','')::int                 as lineas,
         nullif(x->>'cajas','')::numeric              as cajas,
         exists (select 1 from public."GV_Clientes_Reglas" g
                  where g.regla = 'solo' and g.empresa = p_empresa
                    and g.cod_cliente = nullif(x->>'cod','')) as va_solo,
         (exists (select 1 from public."GV_Clientes_Reglas" g
                   where g.regla = 'prioritario' and g.empresa = p_empresa
                     and g.cod_cliente = nullif(x->>'cod',''))
          or coalesce(nullif(x->>'cod','') = any(p_forzar_cods), false)) as prioritario
    from jsonb_array_elements(p_filas) x
   where not exists (
           select 1 from public."PPP_Web_Programacion" g
            where g.empresa = p_empresa
              and g.order_id = (x->>'order_id')::bigint
              and g.np_idx   = (x->>'np_idx')::int
              and coalesce(nullif(trim(g.tanda),''), '') <> '');

  -- Sin zona no se programa: falta el barrio y la elige una persona.
  delete from _sin_tanda where zona = '(sin zona)';

  -- Solas se programan las zonas de `zonas_automaticas` (1, 2 y 3). v13.47: con
  -- p_incluir_manuales = true entran también las "Zona N" manuales (4/5/6/7) — lo usa
  -- gv_ppp_web_armar_pendientes para el día en que ya hay camión a esa zona. Retira, Súper y
  -- Expo nunca: no tienen día previsible.
  delete from _sin_tanda
   where not public.gv_ppp_web_zona_automatica(zona)
     and not (p_incluir_manuales and zona ~ '^\s*Zona\s*[0-9]+');

  -- ── Cuánto queda de cupo para esa fecha (las DOS empresas + ISIS) ───────────
  select coalesce(sum(m3), 0) into v_usado
    from public."PPP_Web_Programacion"
   where fecha_entrega = v_fecha and coalesce(nullif(trim(tanda),''),'') <> '';
  v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);   -- v13.23: ISIS cuenta
  v_resta := greatest(v_cupo - v_usado, 0);

  -- ── Selección: quién entra hoy (por CLIENTE; prioritarios primero, después el más viejo)
  create temp table _sel (cliente text primary key) on commit drop;
  for r_cli in
    select cliente, sum(m3) as m3_cli, bool_or(prioritario) as prio,
           min(fecha_recep) as desde
      from _sin_tanda
     group by cliente
     order by bool_or(prioritario) desc, min(fecha_recep), sum(m3) desc, cliente
  loop
    if r_cli.prio
       or v_acumsel = 0 and v_resta > 0
       or v_acumsel + r_cli.m3_cli <= v_resta then
      insert into _sel (cliente) values (r_cli.cliente) on conflict do nothing;
      v_acumsel := v_acumsel + r_cli.m3_cli;
    end if;
  end loop;

  delete from _sin_tanda s where not exists (select 1 from _sel where cliente = s.cliente);

  create temp table _asig (order_id bigint, np_idx int, tanda text) on commit drop;

  if v_sect then
    alter table _sin_tanda add column camion text;
    update _sin_tanda set camion = public.gv_ppp_web_camion(zona, sector) where true;   -- v13.25: pg_safeupdate
    create temp table _open (code text primary key, camion text, m3 numeric, cerrada boolean, seq int) on commit drop;
    create temp table _open_stops (code text, zona text, sector text, bnorm text) on commit drop;
    create temp table _cam (camion text primary key, zn int, ti int) on commit drop;

    for r_cli in
      select cliente, sum(m3) as m3_cli, bool_or(va_solo) as solo,
             bool_or(grupo = 'Super') as es_super,
             min(camion) as camion, min(sector) as sector
        from _sin_tanda
       group by cliente
       order by min(camion) collate "C", min(sector) collate "C", sum(m3) desc, cliente
    loop
      v_code := null;
      v_cierra := r_cli.es_super or r_cli.solo or r_cli.m3_cli >= v_tope;
      if not v_cierra then
        select o.code into v_code
          from _open o
         where not o.cerrada
           and o.m3 + r_cli.m3_cli <= v_tope
           and not exists (
                 select 1
                   from _open_stops st
                   join _sin_tanda s on s.cliente = r_cli.cliente
                  where st.code = o.code
                    and not public.gv_ppp_web_compat(st.zona, st.sector, st.bnorm,
                                                     s.zona, s.sector, s.bnorm))
         order by (exists (select 1 from _open_stops st
                            where st.code = o.code and st.sector = r_cli.sector)) desc,
                  o.m3 desc, o.seq
         limit 1;
      end if;
      if v_code is null then
        -- v13.47: el número de camión sigue desde el último usado (v_zn0), no desde 01
        insert into _cam (camion, zn, ti)
        values (r_cli.camion, (select coalesce(max(zn), v_zn0) + 1 from _cam), 0)
        on conflict (camion) do nothing;
        select c.zn, c.ti into v_zn, v_ti from _cam c where c.camion = r_cli.camion;
        v_code := case when v_pref <> '' then v_pref
                       else public.ppp_web_letra(v_letra) end
                  || lpad(v_zn::text, 2, '0') || public.ppp_web_letra(v_ti);
        update _cam set ti = ti + 1 where camion = r_cli.camion;
        insert into _open (code, camion, m3, cerrada, seq)
        values (v_code, r_cli.camion, 0, v_cierra, (select count(*) from _open));
      end if;
      insert into _asig (order_id, np_idx, tanda)
      select s.order_id, s.np_idx, v_code from _sin_tanda s where s.cliente = r_cli.cliente;
      insert into _open_stops (code, zona, sector, bnorm)
      select v_code, s.zona, s.sector, s.bnorm from _sin_tanda s where s.cliente = r_cli.cliente;
      update _open set m3 = m3 + r_cli.m3_cli where code = v_code;
    end loop;
  else
  for v_grupo in select distinct grupo from _sin_tanda order by 1 loop
    v_zn := v_zn + 1; v_ti := 0; v_acum := 0; v_code := null;
    for r_cli in
      select cliente, sum(m3) as m3_cli, bool_or(va_solo) as solo
        from _sin_tanda where grupo = v_grupo
       group by cliente order by sum(m3) desc, cliente
    loop
      if v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope
         or v_code is null or (v_acum + r_cli.m3_cli) > v_tope then
        v_code := case when v_pref <> '' then v_pref
                       else public.ppp_web_letra(v_letra) end
                  || lpad(v_zn::text, 2, '0') || public.ppp_web_letra(v_ti);
        v_ti := v_ti + 1; v_acum := 0;
      end if;
      insert into _asig (order_id, np_idx, tanda)
      select s.order_id, s.np_idx, v_code
        from _sin_tanda s where s.grupo = v_grupo and s.cliente = r_cli.cliente;
      v_acum := v_acum + r_cli.m3_cli;
      if v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope then
        v_code := null; v_acum := 0;
      end if;
    end loop;
  end loop;
  end if;

  insert into public."PPP_Web_Programacion"
    (empresa, order_id, np_idx, np, cod_cliente, razon_social, direccion, barrio,
     tanda, zona, fecha_entrega, m3, m3_parcial, lineas, cajas)
  select p_empresa, s.order_id, s.np_idx, s.np,
         s.cliente, s.razon_social, s.direccion, s.barrio,
         a.tanda, s.zona, v_fecha, s.m3, s.m3_parcial, s.lineas, s.cajas
    from _sin_tanda s join _asig a on a.order_id = s.order_id and a.np_idx = s.np_idx
  on conflict (empresa, order_id, np_idx) do update
     set tanda = excluded.tanda, zona = excluded.zona,
         fecha_entrega = excluded.fecha_entrega,
         m3 = excluded.m3, m3_parcial = excluded.m3_parcial,
         lineas = excluded.lineas, cajas = excluded.cajas;

  return query
    select a.tanda,
           case when v_sect then string_agg(distinct s.zona, ' + ' order by s.zona) else min(s.grupo) end,
           count(*)::int, round(sum(s.m3), 3), count(distinct s.cliente)::int
      from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx
     group by a.tanda order by a.tanda;
end
$function$;
revoke all on function public.ppp_web_armar_tandas(text, date, jsonb, text[], boolean) from public, anon;
grant execute on function public.ppp_web_armar_tandas(text, date, jsonb, text[], boolean) to authenticated, service_role;

-- ── 5. la cascada: todo lo que tiene día previsible se programa en esta corrida ─────────
-- p_forzar: [{cod, fecha}] — clientes que tienen que entrar un día dado (Chef encadenado al
-- día en que entró la misma razón social por LK). Devuelve una fila por tanda con la fecha y
-- los códigos de cliente que entraron (la Edge Function encadena Chef con eso).
create or replace function public.gv_ppp_web_armar_pendientes(
  p_empresa text,
  p_fecha date default null,
  p_filas jsonb default '[]'::jsonb,
  p_forzar jsonb default '[]'::jsonb)
returns table (r_fecha date, r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int, r_cods text[])
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  v_min    date := public.gv_ppp_web_dia_minimo();
  v_fecha  date;
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
    -- en dos pasos: _asig/_sin_tanda las crea la llamada, así que se leen en la sentencia siguiente
    delete from _gv_tmp where true;
    insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, r.f, p_filas, r.cods, false);
    insert into _gv_res
    select r.f, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes,
           (select array_agg(distinct s.cliente) from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx where a.tanda = t.r_tanda)
      from _gv_tmp t;
  end loop;

  -- (b) zonas automáticas en cascada: primer día con cupo desde p_fecha (o el día mínimo),
  --     lo que no entra al siguiente con cupo, hasta 8 días por corrida.
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
    -- sin progreso (nada entró) → no insistir: evita un bucle si algo raro deja cupo "libre"
    exit when (select count(*) from _gv_res) = v_antes;
    v_fecha := v_fecha + 1;
  end loop;

  -- (c) zonas manuales con camión: al primer día ≥ día mínimo con camión a esa zona
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
revoke all on function public.gv_ppp_web_armar_pendientes(text, date, jsonb, jsonb) from public, anon;
grant execute on function public.gv_ppp_web_armar_pendientes(text, date, jsonb, jsonb) to authenticated, service_role;

-- Probar sin escribir: corre todo y deshace con una excepción (mismo truco que gv_ppp_web_armar_simular).
create or replace function public.gv_ppp_web_armar_pendientes_simular(
  p_empresa text,
  p_fecha date default null,
  p_filas jsonb default '[]'::jsonb,
  p_forzar jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $function$
declare v_out jsonb;
begin
  begin
    select coalesce(jsonb_agg(jsonb_build_object('fecha', t.r_fecha, 'tanda', t.r_tanda, 'zona', t.r_zona,
             'np', t.r_np_count, 'm3', t.r_m3, 'clientes', t.r_clientes, 'cods', t.r_cods) order by t.r_fecha, t.r_tanda), '[]'::jsonb)
      into v_out
      from public.gv_ppp_web_armar_pendientes(p_empresa, p_fecha, p_filas, p_forzar) t;
    raise exception using errcode = 'GVS01', message = 'GV_SIMULACION';
  exception
    when sqlstate 'GVS01' then return v_out;
  end;
end
$function$;
revoke all on function public.gv_ppp_web_armar_pendientes_simular(text, date, jsonb, jsonb) from public, anon;
grant execute on function public.gv_ppp_web_armar_pendientes_simular(text, date, jsonb, jsonb) to authenticated, service_role;

-- ── 6. el intradía corre TODOS los días 06:00–20:45 ART (antes lun–vie 07:00–18:45) ─────
-- El dueño programa un domingo a la tarde y quiere ver los pedidos irse de A Programar. La
-- fecha objetivo la sigue eligiendo el backend (siempre hábil), así que correr en fin de
-- semana no programa para fin de semana.
select cron.alter_job(73, schedule := '*/15 9-23 * * *');

-- ═══ ROLLBACK ═══════════════════════════════════════════════════════════════════════════
-- select cron.alter_job(73, schedule := '*/15 10-21 * * 1-5');
-- drop function public.gv_ppp_web_armar_pendientes_simular(text, date, jsonb, jsonb);
-- drop function public.gv_ppp_web_armar_pendientes(text, date, jsonb, jsonb);
-- drop function public.ppp_web_armar_tandas(text, date, jsonb, text[], boolean);
--   → restaurar la de 4 args desde sql/backups/ppp_web_armar_tandas_20260906_pre_v1347.sql
-- drop function public.gv_ppp_web_letra_y_camion();
-- drop function public.gv_ppp_web_dia_camion(text, date);
-- gv_ppp_web_proximo_dia_entrega: volver al cuerpo de sql/gv_ppp_web_anticipacion.sql (+ ISIS y cupo, v13.23).
-- drop function public.gv_ppp_web_proximo_dia_con_cupo(date);
-- Y redeployar la Edge Function v13 (llamaba a ppp_web_armar_tandas con 4 args).
