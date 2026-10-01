-- ============================================================================
-- v25.65 — columna PEDIDOS en el pop-up de Proyección (Stock y Compras)
--
-- Pedido del usuario (01/10/2026): "entre Vtas y Entregas quiero que esté la
-- columna de PEDIDOS". Pedidos = cajas que PIDIERON los clientes en el mes
-- (fecha del pedido), no las facturadas (Vtas) ni las que trajo el proveedor
-- (Entregas). En esta app "pedidos" son siempre los de clientes; las de compra
-- se llaman OC.
--
-- Fuente: `lk_pedidos_match` (la empuja LK cada 5 min: pedidos web de LK y de
-- Chef, con los ítems tal cual viajaron a ISIS). Es local: no hay HTTP ni FDW.
--
-- Mismos criterios que la columna Vtas (`ventas_mensuales_cod`), para que se
-- puedan comparar renglón contra renglón:
--   * el principal SUMA a su familia (Equivalencias_Familia: 029 -> 437E);
--   * la "L" es el mismo código de LK (505L de un pedido de Chef = 505 de LK);
--   * p_empresa 'lk' / 'chef' filtra; null = las dos.
--
-- `cubierto` = ese mes ya había pedidos web registrados para TODAS las empresas
-- en las que se pide ese código. false => "s/d", NO un cero: antes de eso los
-- pedidos entraban tipeados en ISIS y no quedaron en ningún lado. Se calcula
-- solo: primer mes ENTERO con datos (al 01/10: LK desde 2026-04, Chef desde
-- 2026-07). Un código que se pide en las dos empresas (702E) toma la más tardía.
--
-- La normalización del código va ESCRITA ADENTRO (es la de gv_cod_stock): esa
-- función tiene SET search_path, no se inlinea, y llamarla por cada ítem de cada
-- pedido costaba 874 ms (regla v20.62/v20.78).
--
-- ⚠ Se aplicó en la base con el comentario 'v25.54 - …' (ese número lo tomó otra sesión en
-- main; sale en la v25.65 — de la v25.56 a la v25.64 las tomaron otras sesiones). Objeto NUEVO, no toca nada existente. Rollback:
--   drop function if exists public.gv_pedidos_mensuales_cod(text, integer, text);
-- ============================================================================
create or replace function public.gv_pedidos_mensuales_cod(
  p_cod text, p_meses integer default 12, p_empresa text default null)
returns table(mes text, cajas numeric, cubierto boolean)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
with par as (
  select public.gv_cod_stock(p_cod) as cod,
         case lower(btrim(coalesce(p_empresa, '')))
           when 'lk' then 'lk' when 'chef' then 'chef' when 'ch' then 'chef' end as emp,
         date_trunc('month', (now() at time zone 'America/Argentina/Buenos_Aires'))::date as mes_hoy,
         greatest(coalesce(p_meses, 12), 1) as n
),
fam as materialized (   -- el principal + sus secundarios (mismo criterio que ventas_mensuales_cod)
  select par.cod as c from par where par.cod <> ''
  union
  select public.gv_cod_stock(f.cod_secundario)
    from public."Equivalencias_Familia" f, par
   where public.gv_cod_stock(f.cod_principal) = par.cod
     and nullif(btrim(f.cod_secundario), '') is not null
),
crudo as materialized (   -- una fila por (pedido, código), código normalizado como gv_cod_stock
  select m.empresa, m.fecha_pedido,
         upper(btrim(x.r[1])) as cod_raw,
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           upper(btrim(x.r[1])), '·.*$', ''), '\s+(LK|CH|LOKE)$', ''), '^0+(?=.)', ''),
           '([0-9E])L$', '\1') as cod,
         (x.r[2])::numeric as cajas
    from public.lk_pedidos_match m
    cross join lateral unnest(string_to_array(coalesce(m.items_string, ''), ',')) as t(item)
    cross join lateral (select regexp_match(btrim(t.item), '^(.+)x([0-9]+(?:\.[0-9]+)?)$') as r) x
   where m.fecha_pedido is not null and x.r is not null
),
it as materialized (      -- sólo la familia, con la empresa del ARTÍCULO (la L es LK)
  select date_trunc('month', c.fecha_pedido)::date as m,
         case when c.empresa = 'lk' or c.cod_raw ~ '[0-9E]L$' then 'lk' else 'chef' end as emp_art,
         c.cajas
    from crudo c
   where c.cod in (select fam.c from fam)
),
ini as (   -- primer mes ENTERO con pedidos registrados, por empresa
  select e.emp,
         (date_trunc('month', min(m.fecha_pedido))
           + case when min(m.fecha_pedido) > date_trunc('month', min(m.fecha_pedido))::date
                  then interval '1 month' else interval '0' end)::date as desde
    from (values ('lk'), ('chef')) e(emp)
    left join public.lk_pedidos_match m on m.empresa = e.emp
   group by e.emp
),
emps as (  -- en qué empresas se mira: la del filtro, o todas en las que se pide el código
  select coalesce(par.emp, i.emp_art) as emp
    from par left join (select distinct emp_art from it) i on par.emp is null
  union
  select 'lk' from par where par.emp is null and not exists (select 1 from it)
),
cub as (
  select max(ini.desde) as desde, bool_and(ini.desde is not null) as ok
    from emps join ini on ini.emp = emps.emp
),
agg as (
  select it.m, sum(it.cajas) as cajas
    from it, par
   where par.emp is null or it.emp_art = par.emp
   group by it.m
),
meses as (
  select (par.mes_hoy - make_interval(months => g))::date as m
    from par, generate_series(0, (select n from par) - 1) g
)
select to_char(me.m, 'YYYY-MM'),
       coalesce(agg.cajas, 0),
       coalesce((select cub.ok and me.m >= cub.desde from cub), false)
  from meses me
  left join agg on agg.m = me.m
 order by 1;
$function$;

comment on function public.gv_pedidos_mensuales_cod(text, integer, text) is
  'v25.54 - cajas PEDIDAS por clientes por mes (fecha del pedido) para el pop-up de Proyeccion. Fuente lk_pedidos_match (web LK + Chef). Suma la familia y la L va a LK, igual que ventas_mensuales_cod. cubierto=false => s/d (antes de los pedidos web).';

grant execute on function public.gv_pedidos_mensuales_cod(text, integer, text) to anon, authenticated;
