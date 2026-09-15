-- =====================================================================================
-- gv_ventas_clientes_mes_v1812.sql — "las ventas de los 5 mas importantes + una fila de
-- otros", para el desglose de un mes en el pop-up de Proyeccion (v18.12).
--
-- ✅ APLICADO el 2026-09-15 en los dos proyectos. Verificado 513 / 2026-05:
--    Osa Distribuidora 400 | Inc S.A. 183 | Patagonia 92 | Enrique Reyes 40 |
--    Horcada 40 | Otros 846  ->  suma 1.601, igual que la columna del pop-up.
--    El front (v18.13) ya lo llamaba, asi que el desglose de "factur." se encendio solo.
--
-- SON DOS FUNCIONES, EN DOS PROYECTOS:
--   1. LK (kwkclwhmoygunqmlegrg): `fn_ventas_clientes_mes_virgilio` — la que sabe. Las
--      ventas viven en `public.sales_lines` de LK; Virgilio no las tiene ni las alcanza
--      por FDW (no hay foreign tables hacia LK, se comprobo).
--   2. Virgilio (hrxfctzncixxqmpfhskv): `gv_ventas_clientes_mes_cod` — el envoltorio HTTP,
--      calcado de `ventas_mensuales_cod`, que es como ya viaja la serie mensual.
--
-- Los filtros son LOS MISMOS que los de `fn_ventas_mensuales_virgilio`, a proposito: si el
-- desglose no sumara exactamente el numero de la columna, el pop-up se contradice solo.
-- O sea: se excluyen los clientes '1' y '3878', se aplica `sales_item_remap` y se saltean
-- los `sales_excluded_items`.
--
-- El corte de los 5 + "Otros" lo hace el BACKEND (protocolo del CLAUDE.md: la regla de
-- negocio no va en el front) y ademas asi viajan 6 filas y no 137 (las que tuvo el 513 en
-- mayo). PROBADO en LK el 2026-09-15 corriendo el cuerpo a mano, 513 / 2026-05:
--   Osa Distribuidora 400 | Inc S.A. 183 | Patagonia 92 | Enrique Reyes 40 | Horcada 40
--   | Otros 846  ->  suma 1.601, exactamente lo que muestra la columna de ese mes.
-- =====================================================================================


-- 1) EN EL PROYECTO DE LK (kwkclwhmoygunqmlegrg) =======================================
create or replace function public.fn_ventas_clientes_mes_virgilio(
  p_cod text, p_mes text, p_empresa text default null)
returns table(cliente text, cajas numeric)
language sql
stable security definer
set search_path to 'public'
set statement_timeout to '30s'
as $function$
  with gate as (
    select 1
    where coalesce(nullif(current_setting('request.headers', true), '')::json ->> 'x-feed-secret', '')
        = coalesce((select value from app_settings where key = 'virgilio_feed_secret'), '__no_secret__')
  ),
  tgt as (
    select regexp_replace(upper(btrim(coalesce(p_cod, ''))), '^0+(?=.)', '') as cod,
           substr(btrim(coalesce(p_mes, '')), 1, 7)                          as mes,
           nullif(lower(btrim(coalesce(p_empresa, ''))), '')                 as emp
  ),
  -- ⚠ Se filtra por ITEM antes que por mes, y con `in` de literales, para que entre por
  -- `idx_sales_lines_item_invoice`. Normalizar el item_code con regexp_replace en el WHERE
  -- (que es lo que hace fn_ventas_mensuales_virgilio) inutiliza el indice: sales_lines tiene
  -- 236.272 filas y la primera version de esta consulta, filtrando por mes primero, se paso
  -- de los 60 s. Con el juego de candidatos vuelve en menos de un segundo.
  -- Los candidatos son el codigo y sus formas con ceros a la izquierda, mas los codigos que
  -- `sales_item_remap` manda a este (si no, se pierden las lineas remapeadas).
  cands as (
    select v from tgt, lateral (values (tgt.cod), ('0' || tgt.cod), ('00' || tgt.cod)) t(v)
    union
    select v from tgt join public.sales_item_remap r on r.to_code = tgt.cod,
         lateral (values (r.from_code), ('0' || r.from_code), ('00' || r.from_code)) t(v)
  ),
  base as (
    select sl.customer_code::text as customer_code, sl.empresa, sl.boxes::numeric as v
    from public.sales_lines sl, tgt
    where sl.item_code in (select v from cands)
      and sl.invoice_date ~ '^\d{4}-\d{2}-\d{2}'
      and substr(sl.invoice_date, 1, 7) = tgt.mes
      and sl.customer_code is not null
      and sl.customer_code not in ('1', '3878')
      and sl.empresa in ('lk', 'chef')
      and (tgt.emp is null or sl.empresa = tgt.emp)
      and not exists (select 1 from public.sales_excluded_items e
                       where e.item_code = regexp_replace(upper(sl.item_code), '^0+(?=.)', ''))
  ),
  -- el nombre sale del padron de la empresa que facturo: LK -> customers, Chef -> chef_customers.
  -- Si no esta, se muestra el codigo pelado antes que un "-" que no dice nada.
  connom as (
    select coalesce(
             nullif(btrim(case when b.empresa = 'chef' then cc.business_name else c.business_name end), ''),
             b.customer_code) as cliente,
           b.v
    from base b
    left join public.customers      c  on b.empresa = 'lk'   and c.cod_cliente::text  = b.customer_code
    left join public.chef_customers cc on b.empresa = 'chef' and cc.cod_cliente::text = b.customer_code
  ),
  agg as (select cliente, sum(v) as cajas from connom group by cliente),
  rk  as (select cliente, cajas, row_number() over (order by cajas desc, cliente) as rn from agg)
  select z.cliente, z.cajas
  from (
    select cliente, cajas, 0 as ord, cajas as k from rk where rn <= 5
    union all
    select 'Otros', sum(cajas), 1, 0::numeric from rk where rn > 5 having sum(cajas) > 0
  ) z, gate
  order by z.ord, z.k desc;
$function$;

revoke all on function public.fn_ventas_clientes_mes_virgilio(text, text, text) from public;
grant execute on function public.fn_ventas_clientes_mes_virgilio(text, text, text) to anon, authenticated, service_role;


-- 2) EN EL PROYECTO DE VIRGILIO (hrxfctzncixxqmpfhskv) =================================
-- La clave publishable y el x-feed-secret NO se escriben en este archivo: el repo se
-- publica por GitHub Pages. Se leen del cuerpo de `ventas_mensuales_cod`, que ya los
-- tiene, asi que ademas no se pueden desincronizar.
do $wrap$
declare
  v_src text; v_k text; v_s text; v_sql text;
begin
  select p.prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ventas_mensuales_cod';
  if v_src is null then raise exception 'no existe public.ventas_mensuales_cod: de ahi salen la clave y el secret'; end if;

  v_k := (regexp_match(v_src, 'k constant text := ''([^'']+)'''))[1];
  v_s := (regexp_match(v_src, 's constant text := ''([^'']+)'''))[1];
  if v_k is null or v_s is null then raise exception 'no pude leer la clave/secret de ventas_mensuales_cod'; end if;

  v_sql := format($f$
create or replace function public.gv_ventas_clientes_mes_cod(
  p_cod text, p_mes text, p_empresa text default null)
returns table(cliente text, cajas numeric)
language plpgsql
stable security definer
set search_path to 'public'
as $fn$
declare
  resp public.http_response; v_cod text; v_mes text; v_url text; v_emp text;
  k constant text := %L;
  s constant text := %L;
begin
  v_cod := regexp_replace(upper(btrim(coalesce(p_cod, ''''))), '[^A-Z0-9]', '', 'g');
  v_mes := substr(btrim(coalesce(p_mes, '''')), 1, 7);
  if v_cod = '''' or v_mes !~ '^[0-9]{4}-[0-9]{2}$' then return; end if;
  v_emp := case lower(btrim(coalesce(p_empresa, '''')))
             when 'lk' then 'lk' when 'chef' then 'chef' when 'ch' then 'chef' else '' end;
  v_url := 'https://kwkclwhmoygunqmlegrg.supabase.co/rest/v1/rpc/fn_ventas_clientes_mes_virgilio'
        || '?p_cod=' || v_cod || '&p_mes=' || v_mes
        || case when v_emp <> '''' then '&p_empresa=' || v_emp else '''' end;
  begin
    resp := public.http(('GET', v_url,
      array[ public.http_header('apikey', k), public.http_header('Authorization', 'Bearer ' || k),
             public.http_header('x-feed-secret', s) ],
      null, null)::public.http_request);
  exception when others then return; end;
  if resp is null or resp.status <> 200 then return; end if;
  return query select x.cliente, x.cajas
                 from jsonb_to_recordset(resp.content::jsonb) as x(cliente text, cajas numeric);
end $fn$;
$f$, v_k, v_s);

  execute v_sql;
  execute 'revoke all on function public.gv_ventas_clientes_mes_cod(text, text, text) from public';
  execute 'grant execute on function public.gv_ventas_clientes_mes_cod(text, text, text) to anon, authenticated';
end $wrap$;


-- 3) VERIFICAR ========================================================================
-- Tiene que devolver hasta 6 filas y su suma tiene que dar IGUAL que el mes en la columna.
select * from public.gv_ventas_clientes_mes_cod('513', '2026-05', null);

-- el cotejo (esperado: las dos columnas iguales)
select (select sum(cajas) from public.gv_ventas_clientes_mes_cod('513', '2026-05', null)) as desglose,
       (select cajas from public.ventas_mensuales_cod('513', 12, null) where mes = '2026-05') as columna;


-- 4) ROLLBACK =========================================================================
-- drop function if exists public.gv_ventas_clientes_mes_cod(text, text, text);          -- Virgilio
-- drop function if exists public.fn_ventas_clientes_mes_virgilio(text, text, text);     -- LK
-- El front aguanta que no existan: contesta 404 y el desglose lo dice.
