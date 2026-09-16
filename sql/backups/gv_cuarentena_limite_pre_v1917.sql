-- =====================================================================================
-- BACKUP previo a la v19.17 (`sql/gv_excepcion_cuarentena_todos_v1917.sql`).
-- Tomado el 2026-09-16 con `pg_get_functiondef` de la base viva (hrxfctzncixxqmpfhskv).
-- Es la versión v17.74, sin tocar desde entonces.
--
-- QUÉ DESARMA: la v19.17 le agrega al CTE `ped` una condición —
--   and not public.gv_cuarentena_exento(id.empresa, id.cod, 'limite_credito')
-- — para que un cliente exento no se mida nunca contra el límite de crédito.
--
-- Las otras dos funciones que toca la v19.17 (`gv_cuarentena_marcar_calc` y
-- `gv_cuarentena_ya_programado`) tienen su versión v19.16 completa en
-- `sql/gv_excepcion_cuarentena_v1916.sql` §5, y la ORIGINAL (pre-v19.16) en
-- `sql/backups/gv_cuarentena_exento_pre_v1916.sql`.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.gv_cuarentena_limite(p_pendientes jsonb)
 RETURNS TABLE(order_id text, empresa text, exceso numeric, limite numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- v15.04 (dueño 2026-09-11): además de marcar, devuelve POR CUÁNTO se pasa del límite
  -- ("Excede crédito por $100.000") y cuál es el límite. La lógica de greedy no cambió.
  -- v17.74 (Thomas, 2026-09-14): el pedido de la página LK que se factura por Chef mide contra
  -- el LÍMITE DE CRÉDITO DE CHEF y con el código de Chef (gv_cuarentena_ident / GV_Cliente_Isis).
  -- El crédito YA USADO se remapea igual, así que las NP web de LK de ese cliente y las NP de
  -- Chef del mismo cliente suman a la misma cuenta. Las NP de ISIS no se remapean: llevan el
  -- código de su propio ISIS. La valorización va con el par remapeado: gv_ppp_web_valor_items
  -- cotiza los artículos con L contra la lista de LK pelando la L, que es el precio real.
  -- La columna `empresa` que sale sigue siendo la del PEDIDO ('lk'): es la clave que usa el front.
  with recursive
  ped as (
    select nullif(trim(e->>'order_id'),'') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'),'') as cod,
           id.empresa as emp_ev,
           id.cod     as cod_ev,
           coalesce(e->>'fecha_recep','') as fecha_recep,
           public.gv_ppp_web_valor_items(id.empresa, id.cod, e->'items', nullif(e->>'cond','')) as monto
    from jsonb_array_elements(coalesce(p_pendientes,'[]'::jsonb)) e
    cross join lateral public.gv_cuarentena_ident(
      lower(coalesce(e->>'empresa','lk')),
      nullif(trim(e->>'cod'),''),
      coalesce(nullif(trim(e->>'order_id'),''), '') !~* '^np') id
    where (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
      and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                       where lb.empresa = lower(coalesce(e->>'empresa','lk'))
                         and lb.order_id = nullif(trim(e->>'order_id'),''))
  ),
  lim as (
    select f.empresa, f.cod, max(f.limite_credito) as limite
    from public."GV_Cuarentena_Fuente" f
    where f.tipo='busqueda' and coalesce(f.limite_credito,0) > 0
    group by f.empresa, f.cod
  ),
  cl as (
    select distinct p.emp_ev as empresa, p.cod_ev as cod
    from ped p join lim l on l.empresa=p.emp_ev and l.cod=p.cod_ev
    where p.cod_ev is not null
  ),
  npcod0 as (
    select regexp_replace(np::text,'\D','','g') as np, empresa, btrim(cod_cliente) as cod, true as es_web
      from public."PPP_Web_Programacion" where np is not null
    union
    select regexp_replace(np::text,'\D','','g') as np, gv_empresa_de_np_texto(np::text) as empresa, btrim(cod) as cod, false
      from public."GV_PPP_Programacion_Diaria" where np is not null and cod is not null
  ),
  npcod as (
    select n.np, id.empresa, id.cod
      from npcod0 n
      cross join lateral public.gv_cuarentena_ident(n.empresa, n.cod, n.es_web) id
  ),
  base_np as (
    select regexp_replace(bp.pedido::text,'\D','','g') as np,
           jsonb_agg(jsonb_build_object('art', bp.articulo, 'cajas', bp.cajas)) as items
    from public."GV_PPP_Base_Pedidos" bp
    where regexp_replace(bp.pedido::text,'\D','','g') not in
          (select regexp_replace(np::text,'\D','','g') from public."Facturacion_NP" where np is not null)
    group by 1
  ),
  base as (
    select m.empresa, m.cod,
           sum(public.gv_ppp_web_valor_items(m.empresa, m.cod, b.items, '8')) as usado
    from base_np b
    join npcod m on m.np = b.np
    join cl on cl.empresa = m.empresa and cl.cod = m.cod
    group by m.empresa, m.cod
  ),
  pend as (
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.monto, l.limite,
           row_number() over (partition by p.emp_ev, p.cod_ev order by p.fecha_recep, p.order_id) as rn
    from ped p join lim l on l.empresa = p.emp_ev and l.cod = p.cod_ev
    where p.order_id is not null and p.cod_ev is not null
  ),
  walk as (
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.rn, p.monto, p.limite,
           (coalesce(b.usado,0) + p.monto > p.limite) as cuar,
           case when coalesce(b.usado,0) + p.monto > p.limite then coalesce(b.usado,0)
                else coalesce(b.usado,0) + p.monto end as usado,
           (coalesce(b.usado,0) + p.monto - p.limite) as exceso
    from pend p
    left join base b on b.empresa = p.emp_ev and b.cod = p.cod_ev
    where p.rn = 1
    union all
    select p.empresa, p.emp_ev, p.cod_ev, p.order_id, p.rn, p.monto, p.limite,
           (w.usado + p.monto > p.limite),
           case when w.usado + p.monto > p.limite then w.usado else w.usado + p.monto end,
           (w.usado + p.monto - p.limite)
    from walk w join pend p on p.emp_ev = w.emp_ev and p.cod_ev = w.cod_ev and p.rn = w.rn + 1
  )
  select order_id, empresa, round(exceso::numeric, 2) as exceso, round(limite::numeric, 2) as limite
  from walk where cuar;
$function$;
