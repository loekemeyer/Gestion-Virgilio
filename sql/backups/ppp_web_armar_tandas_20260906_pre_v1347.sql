-- BACKUP ppp_web_armar_tandas (4 args) tal como estaba en la base el 2026-09-06 antes de la v13.47
-- (v4 sectores + parches v13.23 cupo/ISIS + v13.25 where true). Para restaurar: dropear la de 5 args
-- (ver rollback en sql/gv_ppp_web_armar_pendientes.sql) y ejecutar este archivo.
-- Diferencias con la v5: v_letra := ppp_web_proxima_letra() (letra nueva por llamada), _cam.zn arranca
-- en 1, y el delete de zonas no automáticas no tiene la excepción p_incluir_manuales.
CREATE OR REPLACE FUNCTION public.ppp_web_armar_tandas(p_empresa text, p_fecha date DEFAULT CURRENT_DATE, p_filas jsonb DEFAULT '[]'::jsonb, p_forzar_cods text[] DEFAULT '{}'::text[])
 RETURNS TABLE(r_tanda text, r_zona text, r_np_count integer, r_m3 numeric, r_clientes integer)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tope   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_m3_max_mezcla'), 0.80);
  v_cupo   numeric := public.gv_ppp_web_cupo(p_fecha);   -- v13.23: cupo por dotación
  v_dias   int     := coalesce((select valor from public."PPP_Web_Config" where clave='dias_hasta_entrega'), 0)::int;
  v_saltar boolean := coalesce((select valor from public."PPP_Web_Config" where clave='saltar_fin_de_semana'), 1) <> 0;
  v_pref   text    := coalesce((select valor_texto from public."PPP_Web_Config" where clave='tanda_prefijo'), '');
  v_letra  int     := public.ppp_web_proxima_letra();
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

  delete from _sin_tanda where zona = '(sin zona)';
  delete from _sin_tanda where not public.gv_ppp_web_zona_automatica(zona);

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
        insert into _cam (camion, zn, ti)
        values (r_cli.camion, (select coalesce(max(zn), 0) + 1 from _cam), 0)
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
revoke all on function public.ppp_web_armar_tandas(text, date, jsonb, text[]) from public, anon;
grant execute on function public.ppp_web_armar_tandas(text, date, jsonb, text[]) to authenticated, service_role;
