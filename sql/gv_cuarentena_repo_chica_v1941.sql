-- v19.41 (Luis, 2026-09-17) — EXCEPCIÓN "reposición chica" en Cuarentena.
--
-- Luis: "si un cliente hizo un pedido, se le factura (tiene deuda) y en un plazo de 10 días desde
-- la facturación entra un pedido de ese mismo cliente de 1 item (un código nada más que pide)
-- debería quedar exceptuado de la cuarentena."
--
-- Es el caso del cliente que acaba de comprar, todavía no le venció la factura —por eso figura
-- con deuda— y pide una reposición chica de un solo código. Retenerlo es ruido: la deuda es la de
-- su propia compra reciente.
--
-- QUÉ EXIME Y QUÉ NO. Saca el motivo **`deuda`**, no los otros. Si además está *suspendido*,
-- *sin cta cte*, *excede el límite* o es *cliente nuevo*, el pedido **sigue retenido**: esos son
-- juicios distintos (y a un cliente nuevo hay que cobrarle el total por adelantado, v19.37). Si
-- `deuda` era el único motivo, el pedido sale de Cuarentena, que es lo pedido.
--
-- DE DÓNDE SALE CADA DATO
--   · ítems del pedido y fecha en que entró → `lk_pedidos_match` (la empuja LK cada 15 min, tiene
--     LK y Chef, `items_string` = "505x80,567x1"). Es la ÚNICA fuente viva de los ítems de un
--     pedido web dentro de Virgilio: los feeds `gv_pedidos_web_np_*` viven en los proyectos de las
--     páginas, no acá.
--   · última factura del cliente → `isis_lk.documentos` / `isis_ch.documentos` (`familia =
--     'factura_venta'`), que es la factura REAL parseada. La fuente de deuda
--     (`GV_Cuarentena_Fuente`) **no sirve**: su `raw` es {cod, deuda, razon_social}, sin fecha.
--   · el cliente se resuelve con `gv_cuarentena_ident` (Tierra del Fuego: NP de LK que se factura
--     en el ISIS de Chef), igual que el resto de la Cuarentena.
--
-- ⚠ El plazo se cuenta contra la FECHA DEL PEDIDO, no contra hoy: "entra un pedido dentro de los
-- 10 días desde la facturación". Si se contara contra hoy, la excepción se vencería sola mientras
-- el pedido espera en la pantalla y el mismo pedido cambiaría de estado de un día para el otro.
-- Medido el 17/09 sobre los pendientes con deuda y 1 código: con el criterio bueno califican 2
-- (LK 1449, facturado el mismo día; CH 217, 3 días) y quedan afuera 3 (44, 38 y 15 días). Con
-- `max(fecha)` sin el tope de la fecha del pedido, LK 1375 y LK 1354 daban "-2 días" — una factura
-- POSTERIOR al pedido — y se colaban.
--
-- ⚠ NP de ISIS: no se exime. Su única fuente de ítems, `GV_PPP_Base_Pedidos`, está congelada en
-- 2026-09-04 (es el espejo viejo), así que no hay con qué contar los códigos. Sin datos no se
-- exime nunca: el default es el lado seguro (retener).

-- 1) Config (todo editable sin tocar código)
insert into public."PPP_Web_Config" (clave, valor) values
  ('cuar_repo_activo', 1),      -- 0 = apagar la excepción entera
  ('cuar_repo_dias', 10),       -- plazo desde la factura
  ('cuar_repo_max_items', 1)    -- cuántos códigos distintos puede traer el pedido
on conflict (clave) do nothing;
insert into public."PPP_Web_Config" (clave, valor_texto) values
  ('cuar_repo_motivos', 'deuda')   -- qué motivos perdona (ver gv_cuarentena_repo_motivos)
on conflict (clave) do nothing;

-- 1b) Qué motivos perdona. Default `deuda`; acepta también suspendido / sin_cta_cte /
--     cliente_nuevo. ⚠ `limite_credito` NO: ese motivo lo arma gv_cuarentena_limite (valoriza el
--     pedido y camina el crédito usado), no marcar_calc, así que ponerlo en el texto no haría
--     nada. Si hay que perdonarlo, se agrega el mismo CTE `repo` allá — cuesta ~300 ms más en la
--     función más cara de la pantalla, por eso no está de entrada.
create or replace function public.gv_cuarentena_repo_motivos()
returns text[]
language sql
stable
as $$
  select coalesce(
    (select array_agg(btrim(x)) from unnest(string_to_array(
       (select c.valor_texto from public."PPP_Web_Config" c where c.clave = 'cuar_repo_motivos'), ',')) x
      where btrim(x) <> ''),
    array['deuda']::text[]);
$$;
revoke execute on function public.gv_cuarentena_repo_motivos() from public, anon;
grant  execute on function public.gv_cuarentena_repo_motivos() to authenticated, service_role;

-- 2) El evaluador. Trabaja EN BLOQUE (un solo escaneo de facturas para todo el lote): fila por
--    fila cuesta ~95 ms por cliente y con 100 pedidos serían 9,5 s contra un statement_timeout
--    de 8 s. En bloque, 60 días de facturas de las dos empresas se agregan en ~160 ms.
create or replace function public.gv_cuarentena_repo_lote(p_pedidos jsonb)
returns table (
  empresa       text,
  order_id      text,
  exento        boolean,
  items         integer,
  fecha_pedido  date,
  fecha_factura date,
  dias          integer,
  motivo        text
)
language sql
stable
security definer
set search_path to 'public'
as $$
  with cfg as (
    select coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'cuar_repo_activo'), 1) <> 0 as activo,
           coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'cuar_repo_dias'), 10)::int as dias,
           coalesce((select c.valor from public."PPP_Web_Config" c where c.clave = 'cuar_repo_max_items'), 1)::int as max_items
  ),
  ped as (
    select nullif(trim(e->>'order_id'), '') as order_id,
           lower(coalesce(e->>'empresa','lk')) as empresa,
           id.empresa as emp_ev,
           id.cod     as cod_ev
      from jsonb_array_elements(coalesce(p_pedidos, '[]'::jsonb)) e
      cross join lateral public.gv_cuarentena_ident(
        lower(coalesce(e->>'empresa','lk')),
        nullif(trim(e->>'cod'), ''),
        coalesce(nullif(trim(e->>'order_id'), ''), '') !~* '^np') id
     where nullif(trim(e->>'order_id'), '') is not null
  ),
  -- ítems y fecha de entrada del pedido web (una NP de ISIS entra como 'npNNNNN' y no matchea)
  det as (
    select p.order_id, p.empresa, p.emp_ev, p.cod_ev,
           lp.fecha_pedido,
           array_length(string_to_array(nullif(btrim(lp.items_string), ''), ','), 1) as items
      from ped p
      left join public.lk_pedidos_match lp
        on lp.empresa = p.empresa
       and p.order_id ~ '^[0-9]+$'
       and lp.order_id = (p.order_id)::bigint
  ),
  lim as (   -- hasta dónde hay que mirar hacia atrás en las facturas
    select coalesce((select min(d.fecha_pedido) from det d), current_date) - (select dias from cfg) - 1 as desde
  ),
  fc as (
    select 'lk'::text as empresa, canon_cod(d.contraparte_codigo) as cod, d.fecha
      from isis_lk.documentos d, lim
     where d.familia = 'factura_venta' and d.contraparte_codigo is not null and d.fecha >= lim.desde
    union all
    select 'chef', canon_cod(d.contraparte_codigo), d.fecha
      from isis_ch.documentos d, lim
     where d.familia = 'factura_venta' and d.contraparte_codigo is not null and d.fecha >= lim.desde
  ),
  ev as (
    select d.*,
           (select max(f.fecha) from fc f
             where f.empresa = d.emp_ev and f.cod = canon_cod(d.cod_ev)
               and d.fecha_pedido is not null
               and f.fecha <= d.fecha_pedido
               and f.fecha >= d.fecha_pedido - (select dias from cfg)) as fc_en_plazo
      from det d
  )
  select e.empresa, e.order_id,
         ((select activo from cfg)
           and e.items is not null and e.items <= (select max_items from cfg)
           and e.fc_en_plazo is not null) as exento,
         e.items, e.fecha_pedido, e.fc_en_plazo,
         (e.fecha_pedido - e.fc_en_plazo)::int as dias,
         case when not (select activo from cfg)            then 'apagado'
              when e.fecha_pedido is null or e.items is null then 'sin_datos'
              when e.items > (select max_items from cfg)    then 'muchos_items'
              when e.fc_en_plazo is null                    then 'sin_factura_en_plazo'
              else 'reposicion' end as motivo
    from ev e
   where es_supervisor_virgilio() or gv_es_supervisor_o_servicio();
$$;

revoke execute on function public.gv_cuarentena_repo_lote(jsonb) from public, anon;
grant  execute on function public.gv_cuarentena_repo_lote(jsonb) to authenticated, service_role;

-- 3) El filtro en gv_cuarentena_marcar_calc (respaldo de la versión previa en
--    sql/backups/gv_cuarentena_marcar_calc_pre_v1941_20260917.sql). El cambio son dos piezas:
--      repo as (select empresa, order_id from gv_cuarentena_repo_lote(p_pedidos) where exento)
--    y, en el CTE `exc`, una condición más al filtro de motivos:
--      and not (rp.order_id is not null and x = any (public.gv_cuarentena_repo_motivos()))
--    Se aplicó con CREATE OR REPLACE (misma firma: la llama el front en cada carga).
--    ⚠ La función se evalúa UNA vez para todo el lote (set-returning en el FROM del join), no por
--    fila: fila por fila son ~95 ms por cliente contra las facturas y con 100 pedidos no entra en
--    el statement_timeout de 8 s. Medido con 160 pedidos: marcar_calc entera 200 ms.

-- 4) Centinela: qué pedidos pendientes están exentos hoy y cuáles no, con el porqué.
create or replace view public.gv_cuarentena_repo_hoy
with (security_invoker = true) as
  select r.*, lp.cod_cliente, lp.items_string
    from public.gv_cuarentena_repo_lote(
          (select coalesce(jsonb_agg(jsonb_build_object(
                    'order_id', m.order_id::text, 'empresa', m.empresa, 'cod', m.cod_cliente)), '[]'::jsonb)
             from public.lk_pedidos_match m
            where m.status = 'pendiente' and m.fecha_pedido >= current_date - 30)) r
    left join public.lk_pedidos_match lp
      on lp.empresa = r.empresa and lp.order_id = (r.order_id)::bigint;

revoke select on public.gv_cuarentena_repo_hoy from anon;   -- la lee el MCP / un supervisor, no la app

-- MEDICIÓN (2026-09-17, con los 160 pedidos pendientes de los últimos 20 días)
--   motivo                 | n   | exentos
--   muchos_items           | 150 | 0
--   sin_factura_en_plazo   |   8 | 0
--   reposicion             |   2 | 2   ← LK 1449 (607Ex20, facturado el mismo día)
--                                        CH 217 (609x20, facturado 3 días antes)
--   Los dos habían entrado a Cuarentena con motivo `deuda` (GV_Cuarentena_Log), y el CH 217 tuvo
--   que liberarlo alguien a mano el 17/09 12:07. Eso es exactamente el trabajo que esto ahorra.

-- ROLLBACK
-- drop view if exists public.gv_cuarentena_repo_hoy;
-- drop function if exists public.gv_cuarentena_repo_motivos();
-- drop function if exists public.gv_cuarentena_repo_lote(jsonb);
-- delete from public."PPP_Web_Config" where clave like 'cuar_repo%';
-- (y volver gv_cuarentena_marcar_calc a la versión previa, respaldada en sql/backups/)
