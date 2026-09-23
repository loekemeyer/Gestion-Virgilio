-- v21.87 (Luis, 2026-09-23) — PROGRAMACION AUTOMATICA POR GRUPO DE ZONAS
-- (el marcador dentro de la funcion dice "v21.80-grupo": es la llave de idempotencia, NO cambiarlo)
--
-- Reglas que definio Luis (forward-facing: lo ya programado no se toca):
--   1. UN GRUPO DE ZONAS POR DIA. El dia de un pedido lo da su GRUPO (el camion de
--      gv_ppp_web_camion: Capital Sur / Capital Centro-Oeste / GBA Sur / GBA Oeste / GBA Norte),
--      no el primer dia con cupo. Excepcion: si el pedido no entra en ningun dia de su plazo sin
--      mezclar grupos, gana el cliente (va igual, con flete aparte si hace falta).
--   2. El 4,30 m3 es PROMEDIO, no techo: colgarse del camion de su grupo NO mira el cupo.
--   3. "Ya va un camion a esa zona" se decide por GRUPO (Z2 ve el camion de Z3, Z6 el de Z7).
--   4. VENCIMIENTO: entrada + 14 dias corridos; por expreso, + 13. Hacia atras al dia con reparto.
--   5. Fecha minima: la de siempre (gv_ppp_web_dia_minimo, 4 habiles calculado al mediodia).
--   6. SE SACA la regla "mismo cliente = mismo dia": un cliente con sucursales en dos zonas va
--      en dos dias. Se apagan los pases (a1), (a2), (b00) y (d). Textual: "saca esa regla".
--   7. El orden de llegada deja de decidir: el pedido se cuelga del dia que su grupo ya tiene; si
--      no hay, abre el ULTIMO dia libre de su plazo, asi los pedidos que vienen atras se suman.
--
-- Interruptor: PPP_Web_Config.grupo_dia_activo (sin fila = PRENDIDO). Para volver a la logica
-- anterior sin redeploy:
--   insert into public."PPP_Web_Config"(clave, valor) values ('grupo_dia_activo', 0)
--   on conflict (clave) do update set valor = 0;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 1) El dia del pedido segun su grupo
-- ─────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.gv_ppp_web_dia_grupo(p_zona text, p_entrada date,
                                                       p_expreso boolean, p_min date)
returns date
language plpgsql
volatile   -- crea una temp table: no puede ser stable
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_grp   text := public.gv_ppp_web_camion(p_zona, null::text);
  v_lim   date := coalesce(p_entrada, current_date) + case when p_expreso then 13 else 14 end;
  v_hasta date;
  v_d     date;
  v_g     int := 0;
begin
  if v_grp is null or coalesce(p_zona, '') !~ '^\s*Zona\s*[0-9]+' then return null; end if;
  -- el ultimo dia permitido va hacia atras al dia con reparto
  while not public.gv_es_dia_con_reparto(v_lim) and v_g < 15 loop
    v_lim := v_lim - 1; v_g := v_g + 1;
  end loop;
  v_hasta := greatest(v_lim, p_min) + 15;

  drop table if exists _gdg_oc;
  create temp table _gdg_oc on commit drop as
  with z as (
    select w.fecha_entrega as dia, public.gv_ppp_web_camion(w.zona, null::text) as g
      from public."PPP_Web_Programacion" w
     where w.fecha_entrega between p_min and v_hasta
       and coalesce(nullif(btrim(w.tanda), ''), '') <> ''
       and coalesce(w.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and not public.gv_es_super(w.empresa, w.cod_cliente)
    union all
    select left(btrim(i.fecha_entrega::text), 10)::date, public.gv_ppp_web_camion(i.zona, null::text)
      from public.gv_ppp_programacion_diaria i
     where btrim(i.fecha_entrega::text) ~ '^\d{4}-\d{2}-\d{2}'
       and left(btrim(i.fecha_entrega::text), 10)::date between p_min and v_hasta
       and coalesce(nullif(btrim(i.tanda), ''), '') <> ''
       and coalesce(i.tipo, '') <> 'KRIKOS'
       and coalesce(i.zona, '') ~ '^\s*Zona\s*[0-9]+'
       and not public.gv_es_super_np(i.np, i.cod))
  select g2::date as dia,
         coalesce((select array_agg(distinct z.g) from z where z.dia = g2::date and z.g is not null), '{}') as grupos
    from generate_series(p_min, v_hasta, interval '1 day') g2
   where public.gv_es_dia_con_reparto(g2::date);

  -- (1) su grupo ya sale un dia dentro del plazo -> ese (el primero). No mira el cupo.
  select min(dia) into v_d from _gdg_oc where dia <= v_lim and v_grp = any(grupos);
  if v_d is not null then return v_d; end if;

  -- (2) dia LIBRE (sin ningun grupo de reparto) dentro del plazo -> el ULTIMO, para que los
  --     pedidos del mismo grupo que entren despues se sumen a ese camion.
  select max(dia) into v_d from _gdg_oc where dia <= v_lim and cardinality(grupos) = 0;
  if v_d is not null then return v_d; end if;

  -- (3) el plazo existe pero todos los dias tienen otro grupo -> gana el cliente: el dia del
  --     plazo con menos grupos (el primero). Es el segundo camion / flete.
  if p_min <= v_lim then
    select dia into v_d from _gdg_oc where dia <= v_lim order by cardinality(grupos), dia limit 1;
    if v_d is not null then return v_d; end if;
  end if;

  -- (4) ya vencido (la fecha minima cae despues del plazo) -> LO ANTES POSIBLE, aunque mezcle
  --     grupos (Luis: el rezagado no puede quedar trabado por la regla de una zona por dia).
  --     Dentro de los 2 primeros dias con reparto se prefiere uno de su grupo o libre.
  select dia into v_d from (select dia, grupos, row_number() over (order by dia) rn from _gdg_oc) q
   where rn <= 2
   order by (v_grp = any(grupos) or cardinality(grupos) = 0) desc, dia
   limit 1;
  return coalesce(v_d, p_min);
end
$function$;

revoke all on function public.gv_ppp_web_dia_grupo(text, date, boolean, date) from anon;

-- ─────────────────────────────────────────────────────────────────────────────────────────────
-- 2) El armador: se parchea sobre la definicion VIVA (varias sesiones la tocan), idempotente,
--    y con raise si algun marcador no esta. Marcador de aplicado: 'v21.80-grupo'.
-- ─────────────────────────────────────────────────────────────────────────────────────────────
do $patch$
declare
  v_def text := pg_get_functiondef('public.gv_ppp_web_armar_pendientes'::regproc);
  nl    text := chr(10);
  procedure_marks text[] := array[
    '  v_ret        text[];' || chr(10),
    '  -- (a1) v14.05',
    '  -- (a2) v13.93',
    '  -- (a3) v19.13',
    '  -- (b00) v20.27',
    '  -- (b0) v20.26',
    '  -- (b) zonas automaticas en cascada',
    '  -- (c) zonas manuales con camion',
    '  -- (b2) v15.67',
    '  -- (d) v15.52',
    '  -- (e) v21.39'];
  m text;
  v_g text;
begin
  if strpos(v_def, 'v21.80-grupo') > 0 then
    raise notice 'ya aplicado'; return;
  end if;
  foreach m in array procedure_marks loop
    if strpos(v_def, m) = 0 then raise exception 'marcador no encontrado: %', m; end if;
  end loop;

  -- interruptor
  v_def := replace(v_def, '  v_ret        text[];' || nl,
    '  v_ret        text[];' || nl ||
    '  -- v21.80-grupo (Luis, 23/09): un grupo de zonas por dia. Sin fila = prendido.' || nl ||
    '  v_grupo      boolean := coalesce((select valor from public."PPP_Web_Config" where clave = ''grupo_dia_activo''), 1) <> 0;' || nl);

  -- (a1)+(a2): cliente ya programado -> apagados en modo grupo
  v_def := replace(v_def, '  -- (a1) v14.05',
    '  -- v21.80-grupo: (a1) y (a2) juntan al cliente en su dia -> apagados (Luis: "saca esa regla").' || nl ||
    '  if not v_grupo then' || nl || '  -- (a1) v14.05');
  v_def := replace(v_def, '  -- (a3) v19.13', '  end if; -- v21.80-grupo (a1)(a2)' || nl || nl || '  -- (a3) v19.13');

  -- (b00) ancla de cliente + (b0) ancla de zona + (b) cascada + (c) zonas manuales -> apagados
  v_def := replace(v_def, '  -- (b00) v20.27',
    '  -- v21.80-grupo: (b00), (b0), (b) y (c) eligen el dia por cliente, por numero de zona o por' || nl ||
    '  --   cupo. En modo grupo los reemplaza el pase (g), mas abajo.' || nl ||
    '  if not v_grupo then' || nl || '  -- (b00) v20.27');

  v_g :=
    '  end if; -- v21.80-grupo (b00)(b0)(b)(c)' || nl || nl ||
    '  -- (g) v21.80-grupo (Luis, 2026-09-23) -- UN GRUPO DE ZONAS POR DIA.' || nl ||
    '  --   El dia lo da gv_ppp_web_dia_grupo: el dia que su grupo ya sale dentro del plazo (sin mirar' || nl ||
    '  --   el cupo: el 4,30 es promedio); si no hay, el ULTIMO dia libre del plazo; si no hay libre,' || nl ||
    '  --   el de menos grupos (gana el cliente). Plazo: entrada + 14 dias, expreso + 13.' || nl ||
    '  --   Pedido por pedido, del mas viejo al mas nuevo: el primero de un grupo abre el dia y los' || nl ||
    '  --   que siguen en la MISMA corrida lo ven (ppp_web_armar_tandas ya escribio).' || nl ||
    '  --   El super queda afuera (va por (a3) con turno, o por la cascada de abajo si es auto_super).' || nl ||
    '  if v_grupo then' || nl ||
    '    for r in' || nl ||
    '      select o.oid, o.zona, o.expreso, o.filas, o.cods,' || nl ||
    '             coalesce(o.recep, (select min(m.fecha_pedido) from public.lk_pedidos_match m' || nl ||
    '                                 where m.empresa = p_empresa and m.order_id::text = o.oid),' || nl ||
    '                      current_date) as entrada' || nl ||
    '        from (' || nl ||
    '          select x->>''order_id'' as oid, min(x->>''zona'') as zona,' || nl ||
    '                 min(nullif(x->>''fecha_recep'','''')::date) as recep,' || nl ||
    '                 bool_or(coalesce(x->>''direccion'','''') ~* ''^\s*exp\.'') as expreso,' || nl ||
    '                 jsonb_agg(x) as filas, array_agg(distinct x->>''cod'') as cods' || nl ||
    '            from jsonb_array_elements(p_filas) x' || nl ||
    '           where coalesce(x->>''zona'','''') ~ ''^\s*Zona\s*[0-9]+''' || nl ||
    '             and not public.gv_es_super(p_empresa, x->>''cod'')' || nl ||
    '             and not exists (select 1 from public."PPP_Web_Programacion" g' || nl ||
    '                              where g.empresa = p_empresa and g.order_id = (x->>''order_id'')::bigint' || nl ||
    '                                and g.np_idx = (x->>''np_idx'')::int and coalesce(nullif(trim(g.tanda),''''),'''') <> '''')' || nl ||
    '           group by 1) o' || nl ||
    '       order by 6, 1' || nl ||
    '    loop' || nl ||
    '      v_fecha := public.gv_ppp_web_dia_grupo(r.zona, r.entrada, r.expreso, v_min);' || nl ||
    '      continue when v_fecha is null;' || nl ||
    '      delete from _gv_tmp where true;' || nl ||
    '      insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, v_fecha, r.filas, r.cods, true);' || nl ||
    '      insert into _gv_res' || nl ||
    '      select v_fecha, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes, r.cods from _gv_tmp t;' || nl ||
    '    end loop;' || nl || nl ||
    '    -- auto_super sin turno (INC): la cascada de siempre, SOLO para ellos' || nl ||
    '    v_fecha := coalesce(p_fecha, v_min); v_i := 0;' || nl ||
    '    loop' || nl ||
    '      v_i := v_i + 1;' || nl ||
    '      exit when v_i > 8;' || nl ||
    '      select count(*) into v_n from jsonb_array_elements(p_filas) x' || nl ||
    '       where public.gv_cliente_auto_super(p_empresa, x->>''cod'')' || nl ||
    '         and not exists (select 1 from public."PPP_Web_Programacion" g' || nl ||
    '                          where g.empresa = p_empresa and g.order_id = (x->>''order_id'')::bigint' || nl ||
    '                            and g.np_idx = (x->>''np_idx'')::int and coalesce(nullif(trim(g.tanda),''''),'''') <> '''');' || nl ||
    '      exit when v_n = 0;' || nl ||
    '      v_fecha := public.gv_ppp_web_proximo_dia_con_cupo(v_fecha);' || nl ||
    '      select count(*) into v_antes from _gv_res;' || nl ||
    '      delete from _gv_tmp where true;' || nl ||
    '      insert into _gv_tmp select * from public.ppp_web_armar_tandas(p_empresa, v_fecha,' || nl ||
    '        (select coalesce(jsonb_agg(x), ''[]''::jsonb) from jsonb_array_elements(p_filas) x' || nl ||
    '          where public.gv_cliente_auto_super(p_empresa, x->>''cod'')), ''{}'', false);' || nl ||
    '      insert into _gv_res' || nl ||
    '      select v_fecha, t.r_tanda, t.r_zona, t.r_np_count, t.r_m3, t.r_clientes, null::text[] from _gv_tmp t;' || nl ||
    '      exit when (select count(*) from _gv_res) = v_antes;' || nl ||
    '      v_fecha := v_fecha + 1;' || nl ||
    '    end loop;' || nl ||
    '  end if;' || nl || nl ||
    '  -- (b2) v15.67';
  v_def := replace(v_def, '  -- (b2) v15.67', v_g);

  -- (d) candado mismo cliente = mismo dia -> apagado
  v_def := replace(v_def, '  -- (d) v15.52',
    '  -- v21.80-grupo: (d) junta al cliente en un dia -> apagado (Luis: "saca esa regla").' || nl ||
    '  if not v_grupo then' || nl || '  -- (d) v15.52');
  v_def := replace(v_def, '  -- (e) v21.39', '  end if; -- v21.80-grupo (d)' || nl || nl || '  -- (e) v21.39');

  execute v_def;
end
$patch$;
