-- BACKUP ppp_web_armar_tandas ANTES de la v4 (sectores + vecinos, idea 7317) — 2026-09-05
-- md5(pg_get_functiondef) en Supabase al momento del backup: 3b7ae2a5b202da62825f3c7ebbe4064d
-- Para volver: ejecutar este archivo entero (create or replace) y poner sectores_activos = 0.

create or replace function public.ppp_web_armar_tandas(
  p_empresa text,
  p_fecha date default current_date,
  p_filas jsonb default '[]'::jsonb,
  p_forzar_cods text[] default '{}')
returns table (r_tanda text, r_zona text, r_np_count int, r_m3 numeric, r_clientes int)
language plpgsql
as $function$
declare
  v_tope   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='tanda_m3_max_mezcla'), 0.80);
  v_cupo   numeric := coalesce((select valor from public."PPP_Web_Config" where clave='m3_max_dia'), 5.00);
  v_dias   int     := coalesce((select valor from public."PPP_Web_Config" where clave='dias_hasta_entrega'), 0)::int;
  v_saltar boolean := coalesce((select valor from public."PPP_Web_Config" where clave='saltar_fin_de_semana'), 1) <> 0;
  -- Vacio = codificacion historica de Virgilio. VER LA NOTA DEL ENCABEZADO.
  v_pref   text    := coalesce((select valor_texto from public."PPP_Web_Config" where clave='tanda_prefijo'), '');
  v_letra  int     := public.ppp_web_proxima_letra();
  v_fecha  date;
  v_usado  numeric;
  v_resta  numeric;
  v_acumsel numeric := 0;
  v_grupo  text;
  v_zn     int := 0;
  v_ti     int;
  v_code   text;
  v_acum   numeric;
  r_cli    record;
begin
  v_fecha := p_fecha + v_dias;
  if v_saltar then
    while extract(dow from v_fecha) in (0, 6) loop v_fecha := v_fecha + 1; end loop;
  end if;

  drop table if exists _sin_tanda;
  drop table if exists _sel;
  drop table if exists _asig;

  create temp table _sin_tanda on commit drop as
  select (x->>'order_id')::bigint as order_id,
         (x->>'np_idx')::int      as np_idx,
         nullif(x->>'np','')::int as np,
         coalesce(nullif(x->>'zona',''), '(sin zona)') as zona,
         public.gv_ppp_web_grupo_zona(coalesce(nullif(x->>'zona',''), '(sin zona)')) as grupo,
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

  -- ⚠ SOLO SE PROGRAMAN SOLAS LAS ZONAS DE `zonas_automaticas` (hoy: 1 y 2).
  --   Regla del dueño (2026-09-04): el resto —zonas 3+, Retira, Súper, Expo— lo
  --   programa una persona a mano. No se pierden ni se marcan: quedan SIN tanda,
  --   que es exactamente como llegan a la pantalla de la PPP Web para que alguien
  --   las agarre. Cada corrida las vuelve a mirar, así que el día que se agregue
  --   una zona a la lista entran solas sin tocar código:
  --
  --     update public."PPP_Web_Config" set valor_texto = '1,2,3'
  --      where clave = 'zonas_automaticas';
  --
  --   ⚠ Ojo con el nombre del grupo: la zona 2 se agrupa como 'Zonas 2+3' (esa
  --     regla no cambió). Con la 3 fuera del automático ese grupo queda con zona 2
  --     sola y el resumen igual dice 'Zonas 2+3'. Es sólo la etiqueta del resumen:
  --     la columna `zona` de cada NP guarda la zona REAL.
  delete from _sin_tanda where not public.gv_ppp_web_zona_automatica(zona);

  -- ── Cuanto queda de cupo para esa fecha ────────────────────────────────
  -- Cuenta las DOS empresas: el cupo es del deposito, no de una razon social.
  select coalesce(sum(m3), 0) into v_usado
    from public."PPP_Web_Programacion"
   where fecha_entrega = v_fecha and coalesce(nullif(trim(tanda),''),'') <> '';
  v_resta := greatest(v_cupo - v_usado, 0);

  -- ── Seleccion: quien entra hoy ─────────────────────────────────────────
  -- La unidad es el CLIENTE (no la NP): un cliente entra entero o no entra.
  -- Orden: prioritarios primero, despues el pedido mas viejo.
  create temp table _sel (cliente text primary key) on commit drop;
  for r_cli in
    select cliente, sum(m3) as m3_cli, bool_or(prioritario) as prio,
           min(fecha_recep) as desde
      from _sin_tanda
     group by cliente
     order by bool_or(prioritario) desc, min(fecha_recep), sum(m3) desc, cliente
  loop
    -- El prioritario entra siempre. El resto, mientras quede cupo. Y el primero
    -- entra aunque el solo se pase: un cliente no se parte ni se posterga
    -- eternamente por ser mas grande que el cupo de un dia.
    if r_cli.prio
       or v_acumsel = 0 and v_resta > 0
       or v_acumsel + r_cli.m3_cli <= v_resta then
      insert into _sel (cliente) values (r_cli.cliente) on conflict do nothing;
      v_acumsel := v_acumsel + r_cli.m3_cli;
    end if;
  end loop;

  delete from _sin_tanda s where not exists (select 1 from _sel where cliente = s.cliente);

  -- ── Armado de tandas con lo seleccionado ───────────────────────────────
  create temp table _asig (order_id bigint, np_idx int, tanda text) on commit drop;

  -- Se recorre por GRUPO de zona, no por zona: asi 2 y 3 caen en el mismo bucle
  -- y pueden compartir tanda, y el resto no. Retira es su propio grupo.
  for v_grupo in select distinct grupo from _sin_tanda order by 1 loop
    v_zn := v_zn + 1; v_ti := 0; v_acum := 0; v_code := null;
    for r_cli in
      select cliente, sum(m3) as m3_cli, bool_or(va_solo) as solo
        from _sin_tanda where grupo = v_grupo
       group by cliente order by sum(m3) desc, cliente
    loop
      -- Abre tanda nueva si: el cliente va solo por regla propia, si es Super
      -- (uno por cliente), si el cliente solo ya pasa el tope, o si sumarlo lo
      -- pasaria. Retira NO abre siempre: juntarlos es lo que hace que retiren
      -- el mismo dia.
      if v_grupo = 'Super' or r_cli.solo or r_cli.m3_cli >= v_tope
         or v_code is null or (v_acum + r_cli.m3_cli) > v_tope then
        -- Con prefijo: GV-01A (prueba). Sin prefijo: E01A (codificacion Virgilio).
        -- ⚠ VER LA NOTA DEL ENCABEZADO ANTES DE TOCAR ESTO.
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
    select a.tanda, min(s.grupo), count(*)::int, round(sum(s.m3), 3), count(distinct s.cliente)::int
      from _asig a join _sin_tanda s on s.order_id = a.order_id and s.np_idx = a.np_idx
     group by a.tanda order by a.tanda;
end
$function$;
