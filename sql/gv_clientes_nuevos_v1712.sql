-- ============================================================================
-- v17.12 (2026-09-14, pedido de Luis) — CLIENTE NUEVO → CUARENTENA
-- ============================================================================
-- Pedido: "tenemos la lógica para identificar clientes nuevos, no? Ponelos para que
-- caigan en cuarentena cuando caiga un pedido de ellos, con un badge Cliente nuevo".
--
-- La regla de "¿es nuevo?" ya estaba ESCRITA pero no implementada: docs/PLAN-BADGE-CLIENTE-NUEVO.md
-- (idea 9793, regla del dueño 2026-09-10). Acá se implementa tal cual, con el Hueco A
-- resuelto por la opción 1 que el propio plan recomendaba ("pagado y entregado" ≈ facturado):
--
--   Es NUEVO el cliente que cumple LAS DOS:
--     (a) código alto: cod >= 3800 en LK  /  cod >= 2300 en CH
--     (b) menos de 3 pedidos facturados en TODA su historia
--   …y (b) se cuenta sobre el CLIENTE REAL, no sobre el código: se unen por CUIT, por
--   `customer_grupos` (cambió de razón social) y por `clientes_lk_ch_links` (LK↔CH), con
--   cierre transitivo (WITH RECURSIVE), así que un código nuevo del mismo CUIT que uno viejo
--   con historia NO es nuevo.
--
-- DÓNDE VIVE CADA MITAD (y por qué)
--   · El CÁLCULO va en LK (kwkclwhmoygunqmlegrg): ahí están `sales_lines` (260k líneas de
--     historia real), el padrón de las dos empresas (`customers` + `chef_padron`) y los
--     vínculos. Gestión no tiene nada de eso: su historia propia arranca en 2026 y tratar
--     "sin entregas en 2026" como "cliente nuevo" marcaría a media cartera.
--   · El RESULTADO se espeja a Gestión en `public."GV_Clientes_Nuevos"`, que LK empuja por el
--     FDW `virgilio_db` con el rol `lk_ppp_reader` — mismo patrón que `lk_pedidos_match`
--     (`sync_pedidos_match_virgilio`). Gestión lee una tabla LOCAL: cero FDW en el camino
--     caliente, que es la lección ya escrita para el FDW de Chef.
--
-- MEDICIÓN DEL DÍA QUE SE HIZO (2026-09-14)
--   · Padrón: 1.275 clientes LK + 765 Chef. Con código alto: 492 + 311 = 803.
--   · Nuevos (código alto Y < 3 facturados): 228 LK + 140 Chef = 368. El cálculo tarda 693 ms.
--   · Pedidos web de los últimos 30 días de esos clientes: 12 (≈ 1 cada 2-3 días) — o sea que
--     la Cuarentena NO se inunda.
--   · `gv_cuarentena_ya_programado()` pasó de 12 a 17 filas (5 nuevas por este motivo).
--
-- ROLLBACK (todo reversible, nada se pisó)
--   LK:       select cron.unschedule('sync-clientes-nuevos-virgilio');
--             drop function public.sync_clientes_nuevos_virgilio();
--             drop view public.gv_clientes_nuevos_calc;
--             drop foreign table virgilio.gv_clientes_nuevos;
--   Virgilio: volver a aplicar sql/gv_cuarentena_ya_programado_v1657.sql y la versión previa de
--             gv_cuarentena_marcar (sql/gv_cuarentena_pago_planify_v1546.sql), y después
--             drop table public."GV_Clientes_Nuevos";
--   Apagón rápido SIN tocar código: `delete from public."GV_Clientes_Nuevos";` deja de marcar a
--   nadie por este motivo (el cron lo vuelve a llenar; para que no, desactivar el job 44 en LK).
-- ============================================================================


-- ────────────────────────────────────────────────────────────────────────────
-- 1) GESTIÓN VIRGILIO (hrxfctzncixxqmpfhskv) — el espejo que lee la Cuarentena
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public."GV_Clientes_Nuevos" (
  empresa        text not null,
  cod            text not null,
  razon_social   text,
  pedidos        integer,
  actualizado_at timestamptz not null default now(),
  primary key (empresa, cod)
);
comment on table public."GV_Clientes_Nuevos" is
  'v17.12 (pedido de Luis, 2026-09-14) — clientes NUEVOS segun la regla del dueno (idea 9793): codigo alto (LK >= 3800 / CH >= 2300) Y menos de 3 pedidos facturados en toda su historia, contando la identidad cruzada (mismo CUIT, customer_grupos, clientes_lk_ch_links). Lo calcula LK (gv_clientes_nuevos_calc) y lo empuja por FDW el cron sync-clientes-nuevos-virgilio, mismo patron que lk_pedidos_match. Lo consume gv_cuarentena_marcar para el motivo cliente_nuevo.';

alter table public."GV_Clientes_Nuevos" enable row level security;
revoke insert, update, delete, truncate on public."GV_Clientes_Nuevos" from anon, authenticated;
grant select, insert, update, delete on public."GV_Clientes_Nuevos" to lk_ppp_reader;

-- Sin policy, con RLS prendida, `anon` ve 0 filas. El que escribe es LK por el FDW, así que
-- necesita SU policy (igual que `lk_pedidos_match`): los GRANT solos no alcanzan con RLS.
drop policy if exists "GV_Clientes_Nuevos_writer" on public."GV_Clientes_Nuevos";
create policy "GV_Clientes_Nuevos_writer" on public."GV_Clientes_Nuevos"
  as permissive for all to lk_ppp_reader using (true) with check (true);

-- Las dos funciones de Cuarentena suman el motivo `cliente_nuevo`. Van con DROP + CREATE y no
-- con CREATE OR REPLACE porque CAMBIA el tipo de retorno (se agrega `nuevo_pedidos`), y ojo:
-- el DROP se lleva los GRANT, así que se vuelven a poner abajo (quedaron como las hermanas:
-- authenticated + service_role, sin anon — el gate real está adentro de la función).

drop function if exists public.gv_cuarentena_marcar(jsonb);
create function public.gv_cuarentena_marcar(p_pedidos jsonb)
 returns table(order_id text, empresa text, motivos text[], deuda numeric, estado text, nuevo_pedidos integer)
 language sql
 security definer
 set search_path to 'public'
as $function$
  with ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           nullif(trim(e->>'cod'), '') as cod
    from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
  ),
  -- v14.94 (dueño 2026-09-11): "los súper no se analizan por deuda". Un cliente que figura en
  -- cobranzas_cliente_cadena (Coto, Carrefour, Chango Más…) queda EXENTO de la regla de deuda.
  -- Estado (suspendido / sin cta. cte.) y límite de crédito siguen aplicando igual.
  -- Ojo: en esa tabla Chef está como 'ch'; en GV_Cuarentena_Fuente como 'chef' → se normaliza.
  -- v15.04 (dueño 2026-09-11: "que diga ahí el motivo de la cuarentena: ej deuda $10000"):
  -- además del motivo se devuelve el MONTO de la deuda y el texto del estado.
  -- v15.46 (dueño 2026-09-11, botón "Ya pagó" para Viviana/cobranzas): tampoco va por deuda el
  -- cliente marcado como PAGADO después de la carga del reporte de deuda vigente
  -- (GV_Cuarentena_Pagados.pagado_at >= GV_Cuarentena_Fuente.cargado_at). Si más tarde se sube
  -- un reporte más nuevo y sigue debiendo, vuelve solo a cuarentena.
  -- v17.12 (pedido de Luis, 2026-09-14): motivo nuevo `cliente_nuevo`. El pedido de un CLIENTE
  -- NUEVO también se retiene, para que alguien lo mire antes de que salga. Quién es nuevo lo
  -- calcula LK (regla del dueño, idea 9793: código alto LK>=3800 / CH>=2300 Y menos de 3 pedidos
  -- facturados en toda su historia, uniendo identidad por CUIT / customer_grupos /
  -- clientes_lk_ch_links) y lo espeja el cron `sync-clientes-nuevos-virgilio` a GV_Clientes_Nuevos.
  -- "Ya pagó" NO lo levanta (no es deuda): se saca con "Enviar a Pedidos a programar".
  marca as (
    select p.order_id, p.empresa,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'busqueda'
            and f.cod = p.cod and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'deuda'
            and f.cod = p.cod and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod
                 and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.empresa and pg.cod = p.cod
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.empresa and cn.cod = p.cod limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'deuda'
          and f.cod = p.cod and coalesce(f.deuda,0) > 1000
          and not exists (
            select 1 from public.cobranzas_cliente_cadena cc
             where cc.cod_cliente = p.cod
               and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
          and not exists (
            select 1 from public."GV_Cuarentena_Pagados" pg
             where pg.empresa = p.empresa and pg.cod = p.cod
               and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'busqueda'
          and f.cod = p.cod and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.empresa and cn.cod = p.cod limit 1) as nuevo_pedidos
    from ped p
    where p.cod is not null and p.order_id is not null
  )
  select m.order_id, m.empresa, m.motivos, m.deuda, m.estado, m.nuevo_pedidos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and lb.order_id = m.order_id);
$function$;
revoke all on function public.gv_cuarentena_marcar(jsonb) from public, anon;
grant execute on function public.gv_cuarentena_marcar(jsonb) to authenticated, service_role;


drop function if exists public.gv_cuarentena_ya_programado();
create function public.gv_cuarentena_ya_programado()
 returns table(origen text, empresa text, np text, order_id bigint, tanda text, fecha_entrega date, cod text, razon_social text, motivos text[], deuda numeric, estado text, picking_empezado boolean, nuevo_pedidos integer)
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  -- v16.57 (problema 14) — La Cuarentena sólo mira lo que TODAVÍA NO tiene tanda:
  -- gv_cuarentena_marcar / _limite corren adentro del armado, sobre los pendientes. Si el
  -- reporte de deuda llega DESPUÉS de que el pedido ya recibió tanda, el pedido sigue viaje.
  -- Esto lo saca a la luz: los mismos motivos, aplicados a lo YA programado y todavía frenable.
  -- No retira nada: retirar un pedido de una tanda ya armada es una decisión operativa.
  -- v17.12 (pedido de Luis, 2026-09-14): mismos motivos = también `cliente_nuevo` (GV_Clientes_Nuevos).
  with prog as (
    select 'web'::text as origen, w.empresa,
           public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx) as np,
           w.order_id, w.tanda, w.fecha_entrega, btrim(w.cod_cliente) as cod, w.razon_social
      from public."PPP_Web_Programacion" w
     where w.np is not null and w.fecha_entrega >= current_date
    union all
    select 'isis', case when (regexp_replace(coalesce(d.np,''),'\D','','g'))::bigint > 90000
                        then 'lk' else 'chef' end,
           btrim(d.np), null::bigint, d.tanda,
           nullif(btrim(d.fecha_entrega),'')::date, btrim(d.cod), d.razon_social
      from public.gv_ppp_programacion_diaria d
     where nullif(regexp_replace(coalesce(d.np,''),'\D','','g'),'') is not null
       and nullif(btrim(d.fecha_entrega),'')::date >= current_date
  ),
  marca as (
    select p.*,
      array_remove(array[
        (select case when f.estado ilike '%suspend%' then 'suspendido'
                     when f.estado ilike '%sin%cta%' then 'sin_cta_cte'
                     when f.suspendido is true then 'suspendido' end
           from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'busqueda'
            and f.cod = p.cod and f.suspendido is true limit 1),
        (select 'deuda' from public."GV_Cuarentena_Fuente" f
          where f.empresa = p.empresa and f.tipo = 'deuda'
            and f.cod = p.cod and coalesce(f.deuda,0) > 1000
            and not exists (
              select 1 from public.cobranzas_cliente_cadena cc
               where cc.cod_cliente = p.cod
                 and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
            and not exists (
              select 1 from public."GV_Cuarentena_Pagados" pg
               where pg.empresa = p.empresa and pg.cod = p.cod
                 and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
          limit 1),
        (select 'cliente_nuevo' from public."GV_Clientes_Nuevos" cn
          where cn.empresa = p.empresa and cn.cod = p.cod limit 1)
      ], null) as motivos,
      (select round(f.deuda, 2) from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'deuda' and f.cod = p.cod
          and coalesce(f.deuda,0) > 1000
          and not exists (select 1 from public.cobranzas_cliente_cadena cc
                           where cc.cod_cliente = p.cod
                             and lower(cc.empresa) in (p.empresa, case p.empresa when 'chef' then 'ch' when 'ch' then 'chef' else p.empresa end))
          and not exists (select 1 from public."GV_Cuarentena_Pagados" pg
                           where pg.empresa = p.empresa and pg.cod = p.cod
                             and pg.pagado_at >= coalesce(f.cargado_at, '-infinity'::timestamptz))
        limit 1) as deuda,
      (select nullif(trim(f.estado), '') from public."GV_Cuarentena_Fuente" f
        where f.empresa = p.empresa and f.tipo = 'busqueda'
          and f.cod = p.cod and f.suspendido is true limit 1) as estado,
      (select cn.pedidos from public."GV_Clientes_Nuevos" cn
        where cn.empresa = p.empresa and cn.cod = p.cod limit 1) as nuevo_pedidos
    from prog p
   where p.cod is not null
  )
  select m.origen, m.empresa, m.np, m.order_id, m.tanda, m.fecha_entrega, m.cod, m.razon_social,
         m.motivos, m.deuda, m.estado,
         exists (select 1 from public."Registros_Produccion_Virgilio" r
                  where btrim(r.texto) = btrim(m.tanda) and nullif(btrim(m.tanda),'') is not null),
         m.nuevo_pedidos
  from marca m
  where array_length(m.motivos, 1) >= 1
    and (es_supervisor_virgilio() or gv_es_supervisor_o_servicio())
    and not exists (select 1 from public."GV_Cuarentena_Liberados" lb
                     where lb.empresa = m.empresa and lb.order_id = coalesce(m.order_id::text, m.np))
    and not exists (select 1 from public."Facturacion_NP" fn where btrim(fn.np) = m.np)
  order by m.fecha_entrega, m.empresa, m.np;
$function$;
revoke all on function public.gv_cuarentena_ya_programado() from public, anon;
grant execute on function public.gv_cuarentena_ya_programado() to authenticated, service_role;


-- ────────────────────────────────────────────────────────────────────────────
-- 2) LK (kwkclwhmoygunqmlegrg) — el cálculo y el empuje
--    (copia gemela en el repo pagina-LK-copia: sql/gv_clientes_nuevos.sql)
-- ────────────────────────────────────────────────────────────────────────────
/*
create or replace view public.gv_clientes_nuevos_calc
with (security_invoker = true) as
with recursive base as (
  select 'lk'::text empresa, c.cod_cliente::text cod,
         nullif(regexp_replace(coalesce(c.cuit,''),'\D','','g'),'') cuit, c.business_name rs
    from public.customers c
  union all
  select 'chef', btrim(p.cod_cliente),
         nullif(regexp_replace(coalesce(p.cuit,''),'\D','','g'),''), p.business_name
    from public.chef_padron p
),
nodo as (select empresa, cod, max(cuit) cuit, max(rs) rs from base where cod ~ '^\d+$' group by 1,2),
-- MATERIALIZED no es opcional: `arista` se referencia desde el término recursivo, y sin eso
-- Postgres la inlinea y la recalcula en CADA iteración (misma lección que `sugerir_customer_grupos`).
arista as materialized (
  select a.empresa e1, a.cod c1, b.empresa e2, b.cod c2
    from nodo a join nodo b on a.cuit = b.cuit and length(a.cuit)=11 and (a.empresa,a.cod) <> (b.empresa,b.cod)
  union
  select g1.empresa, g1.cod_cliente, g2.empresa, g2.cod_cliente
    from public.customer_grupos g1 join public.customer_grupos g2
      on g1.grupo_id=g2.grupo_id and g1.empresa=g2.empresa and g1.cod_cliente <> g2.cod_cliente
  union
  select l1.empresa, l1.cod_cliente, l2.empresa, l2.cod_cliente
    from public.clientes_lk_ch_links l1 join public.clientes_lk_ch_links l2
      on l1.link_id=l2.link_id and (l1.empresa,l1.cod_cliente) <> (l2.empresa,l2.cod_cliente)
),
alto as (select empresa, cod, rs from nodo where cod::bigint >= case when empresa='lk' then 3800 else 2300 end),
alcance as (
  select a.empresa, a.cod, a.empresa m_emp, a.cod m_cod from alto a
  union
  select al.empresa, al.cod, ar.e2, ar.c2 from alcance al join arista ar on ar.e1 = al.m_emp and ar.c1 = al.m_cod
),
cnt as (
  -- "pedido facturado" = fecha de factura distinta. `sales_lines` no guarda número de
  -- comprobante, así que la fecha es el mejor proxy que hay; se excluyen los códigos
  -- administrativos (sales_excluded_items) y las devoluciones (boxes <= 0), como todo el
  -- resto de los reportes de clientes.
  select al.empresa, al.cod,
         count(distinct (s.empresa, s.invoice_date)) pedidos,
         count(*) filter (where s.customer_code is not null) lineas,
         count(distinct (al.m_emp, al.m_cod)) codigos
    from alcance al
    left join public.sales_lines s
      on s.customer_code = al.m_cod and lower(s.empresa) = al.m_emp
     and s.boxes > 0 and s.item_code not in (select item_code from public.sales_excluded_items)
   group by 1,2
)
select c.empresa, c.cod, a.rs as razon_social, c.pedidos, c.codigos, (c.pedidos < 3) as es_nuevo
  from cnt c join alto a on a.empresa = c.empresa and a.cod = c.cod;

revoke all on public.gv_clientes_nuevos_calc from anon, authenticated;

create foreign table if not exists virgilio.gv_clientes_nuevos (
  empresa text, cod text, razon_social text, pedidos integer, actualizado_at timestamptz
) server virgilio_db options (schema_name 'public', table_name 'GV_Clientes_Nuevos');

create or replace function public.sync_clientes_nuevos_virgilio()
returns integer language plpgsql security definer set search_path to 'public'
as $$
declare v_n integer;
begin
  create temp table _cn on commit drop as
    select empresa, cod, razon_social, pedidos from public.gv_clientes_nuevos_calc where es_nuevo;
  select count(*) into v_n from _cn;
  if v_n = 0 then
    raise notice 'sync_clientes_nuevos_virgilio: 0 filas, no se pisa nada';
    return 0;
  end if;
  -- Reemplazo total (la lista es chica, ~370 filas). Si el cálculo da 0 NO se pisa nada: una
  -- lista vacía por un error de datos dejaría a todos los clientes como "no nuevos" en silencio.
  -- Y ojo: en una tabla foránea NO se puede usar `insert ... on conflict do update`.
  delete from virgilio.gv_clientes_nuevos where empresa is not null;
  insert into virgilio.gv_clientes_nuevos (empresa, cod, razon_social, pedidos, actualizado_at)
  select empresa, cod, razon_social, pedidos, now() from _cn;
  return v_n;
end;
$$;
revoke all on function public.sync_clientes_nuevos_virgilio() from public, anon, authenticated;

select cron.schedule('sync-clientes-nuevos-virgilio', '40 * * * *',
  $c$select public.sync_clientes_nuevos_virgilio();$c$);   -- job 44, cada hora al :40
*/

-- Chequeos
--   select count(*), max(actualizado_at) from public."GV_Clientes_Nuevos";              -- Virgilio
--   select * from public.gv_cuarentena_ya_programado() where 'cliente_nuevo' = any(motivos);
--   select * from public.gv_clientes_nuevos_calc where es_nuevo order by cod;           -- LK
