-- ═══════════════════════════════════════════════════════════════════════════════════════
-- v25.77 (Luis, 2026-10-01) — DOS REGLAS NUEVAS PARA EL ARMADO AUTOMÁTICO
--   1. Ninguna tanda se arma con más de 5 NP (`tanda_max_nps`). A mano se puede agregar más.
--   2. Una tanda pickea TODO de la MISMA góndola: o todo LK o todo CH, nunca mezclado.
--      Luis, textual: *"SOLO PICKEAN COSAS DE LK. no puede haber una tanda que pickee cosas de
--      LK y de CH. por eso la distincion de tierra del fuego. Cencosud siempre va a ir en su
--      propia tanda, por eso no jode"*.
--
-- GÓNDOLA DE PICKEO de una NP (no es la empresa de la NP, es de dónde sale la caja):
--   · empresa LK                         → LK   (con L = TdF o sin L, las dos de góndola LK)
--   · empresa CH con artículos con L      → LK   (Cencosud, TdF-chef: la L manda a góndola Loeke)
--   · empresa CH sin L (Dorinka, normal)  → CH
--   · empresa CH con L y sin L a la vez   → MIX  (toca las dos; va sola, no se junta con nadie)
-- La L vive en el artículo (PPP_Web_Base.articulo ~ '[0-9E]L$'); es el mismo criterio que
-- pkEmpresaArt / pkResolveArt del front. El armador por empresa YA separa LK de CH; esto agrega
-- la separación DENTRO de chef (Cencosud ya va solo por súper; el caso vivo es TdF-chef).
--
-- La góndola de cada fila NUEVA la calcula el Edge Function (gv-ppp-web-tandas-diarias) desde los
-- items del pedido y la manda en p_filas como `gondola`. Si falta (corrida vieja), default por
-- empresa: chef→CH, lk→LK (= comportamiento actual, no empeora). La góndola de una tanda YA
-- programada (las que _open puede reusar) se recalcula de PPP_Web_Base, que ya existe.
--
-- FORWARD-FACING: lo ya armado no se toca. Las tandas que hoy violan la regla las lista el
-- centinela de abajo (gv_ppp_tanda_gondola_mezclada / gv_ppp_tanda_mas_5_np) para separarlas a
-- mano con «Partir tanda».
--
-- ⚠ Traído de la definición VIVA (v18.28/v18.60/v18.87/v19.13/v19.52/v20.63), no del repo viejo.
-- Probado corriendo el armador con filas de prueba en transacción abortada (no leyéndolo).
-- Marcador de idempotencia: 'v25.77-tope5gondola'. Centinelas en GV_Reglas_Centinela.
-- ═══════════════════════════════════════════════════════════════════════════════════════

insert into public."PPP_Web_Config" (clave, valor) values ('tanda_max_nps', 5)
  on conflict (clave) do nothing;

create or replace function public.ppp_web_armar_tandas(
  p_empresa text,
  p_fecha date default current_date,
  p_filas jsonb default '[]'::jsonb,
  p_forzar_cods text[] default '{}',
  p_incluir_manuales boolean default false)
returns table(r_tanda text, r_zona text, r_np_count integer, r_m3 numeric, r_clientes integer)
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
-- v25.77-tope5gondola
declare
  v_tope   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_m3_max_mezcla'), 0.80);
  v_maxnp  int     := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_max_nps'), 5)::int;   -- v25.77: tope de NP por tanda
  v_cupo   numeric := public.gv_ppp_web_cupo(p_fecha);
  v_dias   int     := coalesce((select valor from public."PPP_Web_Config" where clave='dias_hasta_entrega'), 0)::int;
  v_saltar boolean := coalesce((select valor from public."PPP_Web_Config" where clave='saltar_fin_de_semana'), 1) <> 0;
  v_pref   text    := coalesce((select valor_texto from public."PPP_Web_Config" where clave='tanda_prefijo'), '');
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
  v_base   text;
  v_code   text;
  v_acum   numeric;
  v_nacum  int := 0;    -- v25.77: NP acumuladas en la tanda (modo no-sectores)
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
         nullif(x->>'fecha_recep','')::date as fecha_recep_real,
         -- v25.77: góndola de pickeo de la NP (la calcula el Edge desde los items). Sin el dato,
         -- default por empresa (= comportamiento actual).
         coalesce(nullif(upper(x->>'gondola'),''), case when lower(p_empresa)='chef' then 'CH' else 'LK' end) as gondola,
         coalesce(nullif(x->>'m3','')::numeric, 0)    as m3,
         coalesce((x->>'m3_parcial')::boolean, false) as m3_parcial,
         nullif(x->>'lineas','')::int                 as lineas,
         nullif(x->>'cajas','')::numeric              as cajas,
         exists (select 1 from public."GV_Clientes_Reglas" g
                  where g.regla in ('solo', 'auto_super') and g.empresa = p_empresa
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

  delete from _sin_tanda s where public.gv_es_super(p_empresa, s.cliente)
                             and not public.gv_cliente_auto_super(p_empresa, s.cliente);

  delete from _sin_tanda
   where not public.gv_ppp_web_zona_automatica(zona)
     and not (p_incluir_manuales and zona ~ '^\s*Zona\s*[0-9]+')
     and not public.gv_cliente_auto_super(p_empresa, cliente)
     and not (zona ~* 'retira'
              and public.gv_web_retiro_pactado(p_empresa, order_id) is not null);

  select coalesce(sum(m3), 0) into v_usado
    from public."PPP_Web_Programacion"
   where fecha_entrega = v_fecha and coalesce(nullif(trim(tanda),''),'') <> '';
  v_usado := v_usado + public.gv_ppp_web_m3_isis(p_fecha);
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
    update _sin_tanda set camion = public.gv_ppp_web_camion(zona, sector) where true;
    -- v25.77: _open lleva la góndola de la tanda y cuántas NP tiene, para no mezclar góndola
    -- ni pasar el tope de NP al reusar.
    create temp table _open (code text primary key, camion text, m3 numeric, cerrada boolean, seq int, nps int, gondola text) on commit drop;
    create temp table _open_stops (code text, zona text, sector text, bnorm text) on commit drop;
    create temp table _cam (camion text primary key, zn int, ti int, base text) on commit drop;

    if v_pref = '' then
      create temp table _ex (tanda text, base text, nn int, ti int, camion text) on commit drop;
      insert into _ex (tanda, base, nn, ti, camion)
      select t.tanda, mm.m[1], (mm.m[2])::int, public.ppp_web_letra_idx(mm.m[3]),
             public.gv_ppp_web_camion(t.zona, public.gv_ppp_web_sector(t.zona, t.barrio, t.direccion))
        from (
          select upper(btrim(w.tanda)) as tanda, w.zona, w.barrio, w.direccion
            from public."PPP_Web_Programacion" w
           where w.fecha_entrega = v_fecha and coalesce(nullif(btrim(w.tanda),''),'') <> ''
                 and not public.gv_es_super(w.empresa, w.cod_cliente)
          union all
          select upper(btrim(i.tanda)), i.zona, i.barrio, i.direccion
            from public.gv_ppp_programacion_diaria i
           where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
             and left(btrim(i.fecha_entrega::text), 10)::date = v_fecha
             and coalesce(nullif(btrim(i.tanda),''),'') <> ''
             and coalesce(i.tipo,'') <> 'KRIKOS'
                 and not public.gv_es_super_np(i.np, i.cod)
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

    -- v13.67 + v25.77 (góndola/nps): tandas web del MISMO día/empresa que siguen abiertas y que
    -- NINGÚN operario empezó. Ahora traen también la góndola (de PPP_Web_Base) y el nº de NP.
    insert into _open (code, camion, m3, cerrada, seq, nps, gondola)
    select q.code, q.camion, q.m3, false, row_number() over (order by q.m3 desc, q.code) - 1, q.nps, q.gondola
      from (
        select upper(btrim(w.tanda)) as code,
               min(public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as camion,
               sum(coalesce(w.m3, 0)) as m3,
               bool_and(coalesce(w.zona,'') !~* 'super|retira|expo') as reparto,
               count(distinct w.order_id::text || '|' || w.np_idx::text) as nps,
               -- v25.77: góndola de la tanda desde los artículos (PPP_Web_Base)
               case when lower(p_empresa) <> 'chef' then 'LK'
                    when bool_or(gl.lk_art) and not bool_or(gl.ch_art) then 'LK'
                    when bool_or(gl.ch_art) and not bool_or(gl.lk_art) then 'CH'
                    when bool_or(gl.lk_art) and bool_or(gl.ch_art) then 'MIX'
                    else 'CH' end as gondola,
               count(distinct public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as ncam,
               bool_or(exists (select 1 from public."GV_Clientes_Reglas" g
                                where g.regla = 'solo' and g.empresa = p_empresa and g.cod_cliente = w.cod_cliente)) as tiene_solo,
               bool_or(public.gv_es_super(w.empresa, w.cod_cliente)) as tiene_super
          from public."PPP_Web_Programacion" w
          left join lateral (
                 select bool_or(b.articulo ~ '[0-9E]L$') as lk_art,
                        bool_or(b.articulo !~ '[0-9E]L$') as ch_art
                   from public."PPP_Web_Base" b
                  where b.empresa = w.empresa and b.order_id = w.order_id
                    and coalesce(b.np_idx, 1) = w.np_idx
               ) gl on true
         where w.empresa = p_empresa
           and w.fecha_entrega = v_fecha
           and coalesce(nullif(btrim(w.tanda),''),'') <> ''
           and upper(btrim(w.tanda)) ~ '^[A-Z]+[0-9]+[A-Z]+$'
         group by upper(btrim(w.tanda))
      ) q
     where q.m3 < v_tope and q.reparto and not q.tiene_solo and q.ncam = 1 and not q.tiene_super
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
             bool_or(grupo in ('Super', 'Retira')) as es_super,
             camion, min(sector) as sector,
             gondola, count(*) as nnp          -- v25.77
        from _sin_tanda
       group by cliente, camion, gondola        -- v25.77: + góndola, así no caen en la misma bolsa
       order by camion collate "C", min(sector) collate "C", sum(m3) desc, cliente
    loop
      v_code := null;
      v_cierra := r_cli.es_super or r_cli.solo or r_cli.m3_cli >= v_tope;
      if not v_cierra then
        select o.code into v_code
          from _open o
         where not o.cerrada
           and o.m3 < v_tope
           and o.camion = r_cli.camion
           and o.gondola = r_cli.gondola              -- v25.77: misma góndola o no se suma
           and o.nps + r_cli.nnp <= v_maxnp           -- v25.77: no pasar el tope de NP
           and not exists (
                 select 1
                   from _open_stops st
                   join _sin_tanda s on s.cliente = r_cli.cliente and s.camion = r_cli.camion and s.gondola = r_cli.gondola
                  where st.code = o.code
                    and not public.gv_ppp_web_compat(st.zona, st.sector, st.bnorm,
                                                     s.zona, s.sector, s.bnorm))
         order by (exists (select 1 from _open_stops st
                            where st.code = o.code and st.sector = r_cli.sector)) desc,
                  o.m3 desc, o.seq
         limit 1;
      end if;
      if v_code is null then
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
          exit when not public.gv_ppp_web_codigo_tomado(v_code);
          v_ti := v_ti + 1;
        end loop;
        update _cam set ti = v_ti + 1 where camion = r_cli.camion;
        insert into _open (code, camion, m3, cerrada, seq, nps, gondola)
        values (v_code, r_cli.camion, 0, v_cierra, (select count(*) from _open), 0, r_cli.gondola);
      end if;
      insert into _asig (order_id, np_idx, tanda)
      select s.order_id, s.np_idx, v_code from _sin_tanda s where s.cliente = r_cli.cliente and s.camion = r_cli.camion and s.gondola = r_cli.gondola;
      insert into _open_stops (code, zona, sector, bnorm)
      select v_code, s.zona, s.sector, s.bnorm from _sin_tanda s where s.cliente = r_cli.cliente and s.camion = r_cli.camion and s.gondola = r_cli.gondola;
      update _open set m3 = m3 + r_cli.m3_cli, nps = nps + r_cli.nnp,
             cerrada = cerrada or (m3 + r_cli.m3_cli >= v_tope) or (nps + r_cli.nnp >= v_maxnp)
       where code = v_code;
    end loop;
  else
  for v_grupo in select distinct grupo || '~' || gondola from _sin_tanda order by 1 loop   -- v25.77: + góndola (sep ASCII)
    v_zn := v_zn + 1; v_ti := 0; v_acum := 0; v_nacum := 0; v_code := null;
    for r_cli in
      select cliente, sum(m3) as m3_cli, bool_or(va_solo) as solo, count(*) as nnp   -- v25.77: + nnp
        from _sin_tanda where grupo || '~' || gondola = v_grupo
       group by cliente order by sum(m3) desc, cliente
    loop
      if split_part(v_grupo,'~',1) = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope
         or v_code is null or (v_acum + r_cli.m3_cli) > v_tope
         or (v_nacum + r_cli.nnp) > v_maxnp then                         -- v25.77: tope de NP
        v_code := case when v_pref <> '' then v_pref
                       else public.ppp_web_letra(v_letra) end
                  || lpad(v_zn::text, 2, '0') || public.ppp_web_letra(v_ti);
        v_ti := v_ti + 1; v_acum := 0; v_nacum := 0;
      end if;
      insert into _asig (order_id, np_idx, tanda)
      select s.order_id, s.np_idx, v_code
        from _sin_tanda s where s.grupo || '~' || s.gondola = v_grupo and s.cliente = r_cli.cliente;
      v_acum := v_acum + r_cli.m3_cli; v_nacum := v_nacum + r_cli.nnp;
      if split_part(v_grupo,'~',1) = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope then
        v_code := null; v_acum := 0; v_nacum := 0;
      end if;
    end loop;
  end loop;
  end if;

  insert into public."PPP_Web_Programacion"
    (empresa, order_id, np_idx, np, cod_cliente, razon_social, direccion, barrio,
     tanda, zona, fecha_entrega, fecha_recep, m3, m3_parcial, lineas, cajas)
  select p_empresa, s.order_id, s.np_idx, s.np,
         s.cliente, s.razon_social, s.direccion, s.barrio,
         a.tanda, s.zona, v_fecha, s.fecha_recep_real, s.m3, s.m3_parcial, s.lineas, s.cajas
    from _sin_tanda s join _asig a on a.order_id = s.order_id and a.np_idx = s.np_idx
  on conflict (empresa, order_id, np_idx) do update
     set tanda = excluded.tanda, zona = excluded.zona,
         fecha_entrega = excluded.fecha_entrega,
         fecha_recep = coalesce(public."PPP_Web_Programacion".fecha_recep, excluded.fecha_recep),
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

-- ⚠ APLICAR con check_function_bodies OFF (la validación expande gv_ppp_programacion_diaria y
--   cuelga): envolver cada CREATE grande en  do $w$ begin set local check_function_bodies=off;
--   execute $d$ <create> $d$; end $w$;  y agregar -- REGLA_CONFIRMADA_POR_USUARIO (regla protegida).

-- ── 2. el AGREGADO al cliente: tampoco pasa el tope de NP ───────────────────────────────
create or replace function public.gv_ppp_web_tanda_abierta_cliente(p_empresa text, p_cod text, p_fecha date, p_zona text)
 returns text language sql stable set search_path to 'public'
as $function$
  with cam as (
    select public.gv_ppp_web_camion(p_zona, null) as c
     where coalesce(p_zona, '') ~ '^\s*Zona\s*[0-9]+'
  ),
  cand as (
    select upper(btrim(w.tanda)) as tanda, public.gv_ppp_web_camion(w.zona, null) as c
      from public."PPP_Web_Programacion" w
     where w.empresa = p_empresa
       and btrim(coalesce(w.cod_cliente, '')) = btrim(coalesce(p_cod, ''))
       and w.fecha_entrega = p_fecha
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
  ),
  mismo_camion as (
    select c.tanda
      from cand c
      left join cam on true
     group by c.tanda, cam.c
    having cam.c is null
        or count(*) filter (where c.c is distinct from cam.c) = 0
  )
  select min(m.tanda) from mismo_camion m
   where not exists (
     select 1 from public."Registros_Produccion_Virgilio" r
      where r.opcion in ('EP','TP','AP','TAP')
        and (   upper(btrim(split_part(r.texto, '|', 1))) = m.tanda
             or upper(btrim(split_part(r.texto, '|', 2))) = m.tanda
             or upper(btrim(split_part(r.texto, '|', 3))) = m.tanda))
     -- v25.77: y con menos de tanda_max_nps NP (no se agrega a una tanda que ya llegó al tope)
     and (select count(*) from public."PPP_Web_Programacion" w2
           where w2.empresa = p_empresa and upper(btrim(w2.tanda)) = m.tanda
             and w2.fecha_entrega = p_fecha)
         < coalesce((select valor from public."PPP_Web_Config" where clave='tanda_max_nps'), 5)::int;
$function$;

-- ── 3. la FUSIÓN: no junta góndolas distintas ni pasa el tope de NP ─────────────────────
create or replace function public.gv_ppp_web_fusionar_tandas(
  p_empresa text, p_desde date default null, p_simular boolean default true, p_por text default 'fusion-auto')
returns table(r_fecha date, r_camion text, r_destino text, r_absorbida text,
              r_m3_absorbida numeric, r_m3_antes numeric, r_m3_despues numeric)
language plpgsql security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_obj   numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'tanda_m3_fusion'), 0.80);
  v_max   numeric := coalesce((select valor from public."PPP_Web_Config" where clave = 'tanda_m3_max_mezcla'), 1.00);
  v_maxnp int     := coalesce((select valor from public."PPP_Web_Config" where clave = 'tanda_max_nps'), 5)::int;   -- v25.77
  v_desde date    := coalesce(p_desde, current_date + 1);
  r_d record; r_v record; v_m3 numeric; v_nps int;   -- v25.77: v_nps acumuladas en el destino
  v_cap int := coalesce((select valor from public."PPP_Web_Config" where clave = 'tanda_fusion_max_corrida'), 1)::int;
  v_hechas int := 0;
begin
  drop table if exists _fu_t; drop table if exists _fu_s;
  create temp table _fu_t on commit drop as
  select upper(btrim(w.tanda)) as code, w.fecha_entrega as f,
         min(public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as camion,
         count(distinct public.gv_ppp_web_camion(w.zona, public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion))) as ncam,
         sum(coalesce(w.m3, 0)) as m3,
         count(distinct w.order_id::text || '|' || w.np_idx::text) as nps,                       -- v25.77
         -- v25.77: góndola de la tanda desde los artículos (PPP_Web_Base)
         case when lower(p_empresa) <> 'chef' then 'LK'
              when bool_or(gl.lk_art) and not bool_or(gl.ch_art) then 'LK'
              when bool_or(gl.ch_art) and not bool_or(gl.lk_art) then 'CH'
              when bool_or(gl.lk_art) and bool_or(gl.ch_art) then 'MIX'
              else 'CH' end as gondola,
         bool_and(coalesce(w.zona, '') !~* 'super|retira|expo') as reparto,
         bool_or(public.gv_es_super(w.empresa, w.cod_cliente)) as tiene_super,
         bool_or(exists (select 1 from public."GV_Clientes_Reglas" g
                          where g.regla = 'solo' and g.empresa = p_empresa and g.cod_cliente = w.cod_cliente)) as tiene_solo,
         false as absorbida
    from public."PPP_Web_Programacion" w
    left join lateral (select bool_or(b.articulo ~ '[0-9E]L$') as lk_art, bool_or(b.articulo !~ '[0-9E]L$') as ch_art
                         from public."PPP_Web_Base" b
                        where b.empresa = w.empresa and b.order_id = w.order_id and coalesce(b.np_idx,1) = w.np_idx) gl on true
   where w.empresa = p_empresa and w.fecha_entrega >= v_desde
     and coalesce(nullif(btrim(w.tanda), ''), '') <> '' and upper(btrim(w.tanda)) ~ '^[A-Z]+[0-9]+[A-Z]+$'
   group by 1, 2;

  delete from _fu_t t
   where not t.reparto or t.tiene_super or t.tiene_solo or t.ncam <> 1 or t.gondola = 'MIX'   -- v25.77: una tanda MIX no se fusiona
      or public.gv_es_dia_sin_reparto(t.f)
      or t.code in (select code from _fu_t group by code having count(*) > 1)
      or exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where split_part(r.texto, '|', 1) = t.code
                    and r.opcion in ('PK', 'PKC', 'EP', 'TP', 'TAP', 'AP', 'CC', 'CCN') and r.legajo not in ('0', '1'))
      or exists (select 1 from public."Movimientos_Stock" m where upper(btrim(m.ref)) = t.code);

  create temp table _fu_s on commit drop as
  select upper(btrim(w.tanda)) as code, w.zona,
         public.gv_ppp_web_sector(w.zona, w.barrio, w.direccion) as sector,
         public.gv_ppp_web_barrio_norm(w.barrio, w.direccion) as bnorm
    from public."PPP_Web_Programacion" w
    join _fu_t t on t.code = upper(btrim(w.tanda)) and t.f = w.fecha_entrega
   where w.empresa = p_empresa;

  for r_d in select t.code, t.f, t.camion, t.gondola from _fu_t t order by t.f, t.camion, t.m3 desc, t.code loop
    continue when (select t.absorbida from _fu_t t where t.code = r_d.code);
    v_m3 := (select t.m3 from _fu_t t where t.code = r_d.code);
    v_nps := (select t.nps from _fu_t t where t.code = r_d.code);
    loop
      exit when v_m3 >= v_obj;
      select v.code, v.m3, v.nps into r_v
        from _fu_t v
       where v.f = r_d.f and v.camion = r_d.camion and v.gondola = r_d.gondola   -- v25.77: misma góndola
         and not v.absorbida and v.code <> r_d.code
         and v_m3 + v.m3 <= v_max
         and v_nps + v.nps <= v_maxnp                                            -- v25.77: no pasar el tope de NP
         and not exists (select 1 from _fu_s a join _fu_s b on b.code = v.code
                          where a.code = r_d.code
                            and not public.gv_ppp_web_compat(a.zona, a.sector, a.bnorm, b.zona, b.sector, b.bnorm))
       order by v.m3 desc, v.code limit 1;
      exit when not found;
      update _fu_t set absorbida = true where code = r_v.code;
      r_fecha := r_d.f; r_camion := r_d.camion; r_destino := r_d.code; r_absorbida := r_v.code;
      r_m3_absorbida := round(r_v.m3, 3); r_m3_antes := round(v_m3, 3);
      v_m3 := v_m3 + r_v.m3; v_nps := v_nps + r_v.nps;
      r_m3_despues := round(v_m3, 3);
      update _fu_t set m3 = v_m3, nps = v_nps where code = r_d.code;
      if not p_simular then
        perform public.gv_ppp_tanda_renombrar(r_v.code, r_d.code, p_por);
        v_hechas := v_hechas + 1;
        if v_hechas >= v_cap then return next; return; end if;
      end if;
      return next;
    end loop;
  end loop;
end $function$;
revoke execute on function public.gv_ppp_web_fusionar_tandas(text, date, boolean, text) from public, anon;
grant  execute on function public.gv_ppp_web_fusionar_tandas(text, date, boolean, text) to authenticated, service_role;

-- ── 4. centinelas de lo que ya está mal hoy (para que lo separe Marianela con «Partir tanda») ──
create or replace view public.gv_ppp_tanda_mas_5_np as
  select upper(btrim(w.tanda)) tanda, w.fecha_entrega, count(*) nps,
         string_agg(distinct w.empresa, ',') empresas, round(sum(coalesce(w.m3,0)),3) m3
    from public."PPP_Web_Programacion" w
   where w.fecha_entrega >= current_date and coalesce(nullif(btrim(w.tanda),''),'') <> ''
   group by 1,2
  having count(*) > coalesce((select valor from public."PPP_Web_Config" where clave='tanda_max_nps'),5)::int;
alter view public.gv_ppp_tanda_mas_5_np set (security_invoker = true);
grant select on public.gv_ppp_tanda_mas_5_np to authenticated, service_role;

create or replace view public.gv_ppp_tanda_gondola_mezclada as
  with b as (
    select upper(btrim(w.tanda)) tanda, w.fecha_entrega, w.empresa, w.order_id, w.np_idx,
           bool_or(x.articulo ~ '[0-9E]L$') lk, bool_or(x.articulo !~ '[0-9E]L$') ch
      from public."PPP_Web_Programacion" w
      left join public."PPP_Web_Base" x on x.empresa=w.empresa and x.order_id=w.order_id and coalesce(x.np_idx,1)=w.np_idx
     where w.fecha_entrega >= current_date and coalesce(nullif(btrim(w.tanda),''),'') <> ''
     group by 1,2,3,4,5
  ), g as (
    select tanda, fecha_entrega,
           bool_or(empresa='lk' or lk) toca_lk,
           bool_or(empresa='chef' and ch) toca_ch,
           string_agg(distinct empresa,',') empresas, count(*) nps
      from b group by 1,2
  )
  select tanda, fecha_entrega, empresas, nps from g where toca_lk and toca_ch;
alter view public.gv_ppp_tanda_gondola_mezclada set (security_invoker = true);
grant select on public.gv_ppp_tanda_gondola_mezclada to authenticated, service_role;

-- ── 5. centinelas de que la regla no se borre del armador (gv_reglas_perdidas) ──────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
select * from (values
  ('ppp_web_armar_tandas','funcion','tanda_max_nps','una tanda del armado automatico no se arma con mas de tanda_max_nps NP (5); a mano se puede agregar mas','Luis','v25.77'),
  ('ppp_web_armar_tandas','funcion','o\.gondola = r_cli\.gondola','una tanda pickea TODO de una sola gondola (LK o CH): el armado no junta gondolas distintas','Luis','v25.77'),
  ('gv_ppp_web_fusionar_tandas','funcion','v\.gondola = r_d\.gondola','la fusion no junta tandas de gondola distinta ni pasa el tope de NP','Luis','v25.77')
) v(objeto,clase,patron,regla,quien_pidio,version)
where not exists (select 1 from public."GV_Reglas_Centinela" c where c.objeto=v.objeto and c.patron=v.patron);
