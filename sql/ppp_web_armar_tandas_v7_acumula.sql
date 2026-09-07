-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v13.67 (2026-09-07, lunes feriado) — LA TANDA ACUMULA ENTRE CORRIDAS HASTA 0,80 m³
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Dueño (vía el otro chat, 06/09 20:40): "la tanda tiene que ACUMULAR entre corridas hasta 0,80 m³ (el pedido
-- que cruza el tope entra igual, puede pasarse un poco) y ahí cerrarse y no recibir más pedidos". Confirmado
-- el 07/09: zonas automáticas siguen en 1,2,3; crons 71 y 73 vuelven a prenderse con esto aplicado.
--
-- Causa (hallazgo del otro chat, verificado sobre la función desplegada): `_open` —las tandas que pueden recibir
-- un cliente más— nacía vacía en cada corrida y sólo se llenaba con lo armado en esa corrida. Con el intradía
-- cada 15 min y umbral 0,001, cada pedido que caía solo se llevaba su propia tanda.
--
-- Cambios (migraciones ppp_web_armar_tandas_v7_acumula_v1367 + _v7b_acumula_fix_v1367):
--   1. _open se siembra con las tandas web del MISMO día y empresa que sigan abiertas (m³ < tope), de reparto
--      (sin súper/retira/expo), sin cliente 'solo' (GV_Clientes_Reglas) y que NINGÚN operario haya empezado
--      (sin PK/PKC/EP/TP/TAP/AP/CC/CCN en Registros_Produccion_Virgilio para ese código). Sus paradas van a
--      _open_stops (zona/sector/barrio) para que la compatibilidad por cercanía siga valiendo.
--   2. Una tanda abierta recibe al cliente aunque con él cruce el tope (antes: sólo si m3 + cliente <= tope).
--   3. Al cruzar el tope se marca cerrada y no recibe más.
--   Sin timeout (dueño: "no va a pasar, salvo zona distinta de 1, y eso se programa manual").
--
-- Probado sin escribir (gv_ppp_web_armar_pendientes_simular, lun 14 con p_forzar): ver §3.av de
-- docs/SUPABASE-GESTION-VIRGILIO.md. Rollback: reaplicar sql/gv_ppp_web_camion_del_dia.sql §3 (v6).
-- ═══════════════════════════════════════════════════════════════════════════════════════

create or replace function public.ppp_web_armar_tandas(
  p_empresa text, p_fecha date default current_date, p_filas jsonb default '[]'::jsonb,
  p_forzar_cods text[] default '{}'::text[], p_incluir_manuales boolean default false)
returns table (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int)
language plpgsql set search_path = public, pg_temp as $function$
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
  v_base   text;     -- v13.60: letra del camión que se reusa (puede ser la de ISIS, 'D')
  v_code   text;
  v_acum   numeric;
  v_cierra boolean;
  r_cli    record;
begin
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
  drop table if exists _ex;

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

  delete from _sin_tanda where zona = '(sin zona)';

  -- Solas se programan las zonas de `zonas_automaticas` (1, 2 y 3). v13.47: con
  -- p_incluir_manuales = true entran también las "Zona N" manuales (4/5/6/7) — lo usa
  -- gv_ppp_web_armar_pendientes para el día en que ya hay camión a esa zona. Retira, Súper y
  -- Expo nunca: no tienen día previsible.
  delete from _sin_tanda
   where not public.gv_ppp_web_zona_automatica(zona)
     and not (p_incluir_manuales and zona ~ '^\s*Zona\s*[0-9]+');

  select coalesce(sum(m3), 0) into v_usado
    from public."PPP_Web_Programacion"
   where fecha_entrega = v_fecha and coalesce(nullif(trim(tanda),''),'') <> '';
  v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);   -- v13.23: ISIS cuenta
  v_resta := greatest(v_cupo - v_usado, 0);

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
    create temp table _cam (camion text primary key, zn int, ti int, base text) on commit drop;

    -- v13.60: los camiones que YA van ese día (web + ISIS; sin súper ni retira) se cargan en _cam
    -- con su letra, su número y la próxima letra de tanda libre. Una tanda nueva para la misma
    -- etiqueta de camión (Capital / GBA Sur / …) entra ahí (E01F, D68G), no abre otro camión.
    if v_pref = '' then
      create temp table _ex (tanda text, base text, nn int, ti int, camion text) on commit drop;
      insert into _ex (tanda, base, nn, ti, camion)
      select t.tanda, mm.m[1], (mm.m[2])::int, public.ppp_web_letra_idx(mm.m[3]),
             public.gv_ppp_web_camion(t.zona, public.gv_ppp_web_sector(t.zona, t.barrio, t.direccion))
        from (
          select upper(btrim(w.tanda)) as tanda, w.zona, w.barrio, w.direccion
            from public."PPP_Web_Programacion" w
           where w.fecha_entrega = v_fecha and coalesce(nullif(btrim(w.tanda),''),'') <> ''
          union all
          select upper(btrim(i.tanda)), i.zona, i.barrio, i.direccion
            from public.gv_ppp_programacion_diaria i
           where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
             and left(btrim(i.fecha_entrega::text), 10)::date = v_fecha
             and coalesce(nullif(btrim(i.tanda),''),'') <> ''
             and coalesce(i.tipo,'') <> 'KRIKOS'
        ) t
        cross join lateral (select regexp_match(t.tanda, '^([A-Z]+)([0-9]+)([A-Z]+)$') as m) mm
       where mm.m is not null
         and coalesce(t.zona,'') !~* 'super|retira|expo';
      insert into _cam (camion, zn, ti, base)
      select q.camion, q.nn, q.ti_next, q.base
        from (
          select e.camion, e.base, e.nn,
                 (select max(x.ti) + 1 from _ex x where x.base = e.base and x.nn = e.nn) as ti_next,
                 row_number() over (partition by e.camion order by count(*) desc, e.base desc, e.nn desc) as rk
            from _ex e
           group by e.camion, e.base, e.nn
        ) q
       where q.rk = 1;
    end if;

    -- v13.67 (dueño: "la tanda tiene que acumular hasta 0,80 y ahí cerrarse"): las tandas web del MISMO día y
    -- empresa que sigan abiertas (m³ < tope, sin súper ni cliente 'solo') y que NINGÚN operario haya empezado
    -- (sin PK/PKC/EP/TP/TAP/AP/CC/CCN en el log) entran a _open y pueden recibir un cliente más.
    insert into _open (code, camion, m3, cerrada, seq)
    select q.code, q.camion, q.m3, false, row_number() over (order by q.m3 desc, q.code) - 1
      from (
        select upper(btrim(w.tanda)) as code,
               min(public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as camion,
               sum(coalesce(w.m3, 0)) as m3,
               bool_and(coalesce(w.zona,'') !~* 'super|retira|expo') as reparto,
               bool_or(exists (select 1 from public."GV_Clientes_Reglas" g
                                where g.regla = 'solo' and g.empresa = p_empresa and g.cod_cliente = w.cod_cliente)) as tiene_solo
          from public."PPP_Web_Programacion" w
         where w.empresa = p_empresa
           and w.fecha_entrega = v_fecha
           and coalesce(nullif(btrim(w.tanda),''),'') <> ''
           and upper(btrim(w.tanda)) ~ '^[A-Z]+[0-9]+[A-Z]+$'
         group by upper(btrim(w.tanda))
      ) q
     where q.m3 < v_tope and q.reparto and not q.tiene_solo
       and not exists (select 1 from public."Registros_Produccion_Virgilio" r
                        where split_part(r.texto, '|', 1) = q.code
                          and r.opcion in ('PK','PKC','EP','TP','TAP','AP','CC','CCN')
                          and r.legajo not in ('0','1'))
    on conflict (code) do nothing;
    insert into _open_stops (code, zona, sector, bnorm)
    select upper(btrim(w.tanda)), w.zona,
           public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion),
           public.gv_ppp_web_barrio_norm(w.barrio, w.direccion)
      from public."PPP_Web_Programacion" w
      join _open o on o.code = upper(btrim(w.tanda))
     where w.empresa = p_empresa and w.fecha_entrega = v_fecha;

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
        -- v13.67: una tanda abierta (m³ < tope) recibe al cliente aunque con él cruce el tope
        -- ("el pedido que cruza entra igual, puede pasarse un poco"); ahí se cierra.
        select o.code into v_code
          from _open o
         where not o.cerrada
           and o.m3 < v_tope
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
        -- v13.47: el número de camión sigue desde el último usado (v_zn0), no desde 01.
        -- v13.60: si ya hay camión a esa etiqueta ese día (_cam precargada), no entra acá.
        insert into _cam (camion, zn, ti, base)
        values (r_cli.camion,
                greatest(coalesce((select max(c.zn) from _cam c
                                    where c.base is null or c.base = public.ppp_web_letra(v_letra)), 0),
                         v_zn0) + 1,
                0, null)
        on conflict (camion) do nothing;
        select c.zn, c.ti, c.base into v_zn, v_ti, v_base from _cam c where c.camion = r_cli.camion;
        loop
          v_code := case when v_pref <> '' then v_pref
                         else coalesce(v_base, public.ppp_web_letra(v_letra)) end
                    || lpad(v_zn::text, 2, '0') || public.ppp_web_letra(v_ti);
          exit when not public.gv_ppp_web_codigo_tomado(v_code);   -- v13.60: nunca un código que exista
          v_ti := v_ti + 1;
        end loop;
        update _cam set ti = v_ti + 1 where camion = r_cli.camion;
        insert into _open (code, camion, m3, cerrada, seq)
        values (v_code, r_cli.camion, 0, v_cierra, (select count(*) from _open));
      end if;
      insert into _asig (order_id, np_idx, tanda)
      select s.order_id, s.np_idx, v_code from _sin_tanda s where s.cliente = r_cli.cliente;
      insert into _open_stops (code, zona, sector, bnorm)
      select v_code, s.zona, s.sector, s.bnorm from _sin_tanda s where s.cliente = r_cli.cliente;
      -- v13.67: al cruzar el tope la tanda se cierra y no recibe más
      update _open set m3 = m3 + r_cli.m3_cli, cerrada = cerrada or (m3 + r_cli.m3_cli >= v_tope) where code = v_code;
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
