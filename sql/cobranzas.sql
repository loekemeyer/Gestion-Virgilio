-- ============================================================
--  Módulo Cobranzas — valorizar una NP sin ver la factura
--  Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
--  OBJETIVO: que Virgilio sepa cuánta plata se le facturó a cada NP /
--  cliente sin tener la factura a la vista, cruzando el detalle de líneas
--  (PPP_Base_Pedidos: artículo × cajas) con la lista de precios.
--
--  DOS NIVELES DE PRECIO (a propósito):
--   1) VALOR DE LISTA — lo que resuelve ESTE archivo, en la base, al toque
--      y en lote. Sale de `precios_venta` (snapshot de la lista general de
--      LK: products.list_price + loke_products). NO aplica descuento por
--      cliente (dto_vol) porque ese dato es comercialmente sensible y NO
--      debe vivir en Virgilio: `precios_venta` es anon-readable, copiar el
--      padrón de descuentos de LK acá lo filtraría. Sirve para el tablero
--      de cobranzas (orden de magnitud, cobertura, faltantes).
--   2) NETO EXACTO por NP — lo resuelve la Edge Function `arca-wsfe`
--      (acción `preciar`), que lee LK EN VIVO con service_role y aplica
--      neto = list_price × (1 − dto_vol) × (1 − 2%) + IVA 21%. Ese es el
--      importe facturable real; se pide por NP cuando hace falta el número
--      fino (emisión / conciliación).
--
--  EMPRESA por NP: 9xxxx = Loekemeyer, 4xxxx = Chef (numeraciones
--  independientes). La lista de Chef NO está cargada en Virgilio (vive en
--  otro Supabase), así que las NP de Chef salen marcadas
--  `lista_no_disponible` en vez de valorizadas con la lista de LK (que
--  daría un número equivocado: mismo código = otro artículo en cada empresa).
--
--  ⚠ precio 8888 en la lista = placeholder (sin precio real) → NO valoriza.
-- ============================================================

-- ── 1) Normalización canónica de código ─────────────────────────────
--  El match articulo↔lista tiene que ser insensible a mayúsculas, espacios
--  y ceros a la izquierda: en los pedidos aparecen `948e`/`948E`, `029`/`29`.
--  Mismo criterio que el norm_cod del proyecto web.
create or replace function public.cob_norm_cod(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(upper(btrim(coalesce(p,''))), '^0+(?=.)', ''), '')
$$;

-- ── 2) Empresa de una NP por su numeración ──────────────────────────
create or replace function public.cob_empresa_np(p_np text)
returns text language sql immutable as $$
  select case left(regexp_replace(coalesce(p_np,''),'\D','','g'),1)
           when '9' then 'lk'
           when '4' then 'ch'
           else 'otro'
         end
$$;

-- ── 3) Valorizar UNA NP (valor de lista) ────────────────────────────
--  Devuelve el detalle por línea + los totales. `valor_lista` es sin IVA
--  y sin dto por cliente; `estimado_con_iva` aplica el 2% web y el 21% de
--  IVA como referencia rápida (el neto fino sale de arca-wsfe/preciar).
create or replace function public.cobranzas_valorizar_np(p_np text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp   text := public.cob_empresa_np(p_np);
  v_rs    text;
  v_cod   text;
  v_res   jsonb;
begin
  -- encabezado (cliente) desde la programación
  select max(razon_social), max(cod)
    into v_rs, v_cod
  from public."PPP_Programacion_Diaria"
  where regexp_replace(coalesce(np,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g');

  if v_emp = 'ch' then
    -- Chef: no hay lista cargada en Virgilio
    select jsonb_build_object(
             'np', p_np, 'empresa', 'ch', 'cod_cliente', v_cod, 'cliente', v_rs,
             'lista_no_disponible', true,
             'nota', 'Lista de Chef no cargada en Virgilio (vive en otro proyecto).',
             'cajas', coalesce(sum(cajas),0),
             'lineas', coalesce(count(*),0)
           )
      into v_res
    from public."PPP_Base_Pedidos"
    where regexp_replace(coalesce(pedido,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g');
    return v_res;
  end if;

  with lineas as (
    select b.articulo,
           sum(b.cajas)                       as cajas,
           pv.precio_unit,
           pv.uxb,
           pv.descripcion,
           (pv.precio_unit is not null and pv.precio_unit > 0 and pv.precio_unit <> 8888) as con_precio
    from public."PPP_Base_Pedidos" b
    left join public.precios_venta pv
           on public.cob_norm_cod(pv.cod) = public.cob_norm_cod(b.articulo)
    where regexp_replace(coalesce(b.pedido,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g')
    group by b.articulo, pv.precio_unit, pv.uxb, pv.descripcion
  )
  select jsonb_build_object(
           'np', p_np,
           'empresa', 'lk',
           'cod_cliente', v_cod,
           'cliente', v_rs,
           'valor_lista',       coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric,2),0),
           'estimado_con_iva',  coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric * 0.98 * 1.21,2),0),
           'cajas',             coalesce(sum(cajas),0),
           'lineas_total',      count(*),
           'lineas_sin_precio', count(*) filter (where not con_precio),
           'cobertura_pct',     round(100.0*count(*) filter (where con_precio)/nullif(count(*),0),1),
           'sin_precio',        coalesce(jsonb_agg(articulo) filter (where not con_precio), '[]'::jsonb),
           'detalle', coalesce(jsonb_agg(
                        jsonb_build_object('articulo',articulo,'descripcion',descripcion,'cajas',cajas,
                          'precio_unit',precio_unit,'uxb',uxb,
                          'valor_lista', case when con_precio then round((precio_unit*uxb*cajas)::numeric,2) end)
                        order by (case when con_precio then precio_unit*uxb*cajas else 0 end) desc), '[]'::jsonb),
           'nota', 'valor_lista = precio de lista sin dto por cliente. Neto exacto: arca-wsfe/preciar.'
         )
    into v_res
  from lineas;

  return v_res;
end $$;

-- ── 4) Resumen de cobranzas de las NP en curso ──────────────────────
--  Una fila por NP de la programación con su valor de lista y cobertura,
--  para el tablero. Chef sale con valor_lista NULL y lista_no_disponible.
create or replace function public.cobranzas_resumen()
returns table (
  np text, empresa text, cod_cliente text, cliente text,
  cajas numeric, valor_lista numeric, lineas_total bigint,
  lineas_sin_precio bigint, cobertura_pct numeric, lista_no_disponible boolean
)
language sql
security definer
set search_path = public
as $$
  with prog as (
    select regexp_replace(coalesce(np,''),'\D','','g') as npk,
           max(np) np, max(cod) cod, max(razon_social) rs
    from public."PPP_Programacion_Diaria"
    group by 1
  ),
  lin as (
    select regexp_replace(coalesce(b.pedido,''),'\D','','g') as npk,
           sum(b.cajas) cajas,
           count(*) lineas,
           count(*) filter (where pv.precio_unit is not null and pv.precio_unit>0 and pv.precio_unit<>8888) con_precio,
           sum(case when pv.precio_unit is not null and pv.precio_unit>0 and pv.precio_unit<>8888
                    then pv.precio_unit*pv.uxb*b.cajas end) valor
    from public."PPP_Base_Pedidos" b
    left join public.precios_venta pv
           on public.cob_norm_cod(pv.cod) = public.cob_norm_cod(b.articulo)
    group by 1
  )
  select p.np,
         public.cob_empresa_np(p.np) as empresa,
         p.cod, p.rs,
         coalesce(l.cajas,0),
         case when public.cob_empresa_np(p.np)='ch' then null else round(coalesce(l.valor,0)::numeric,2) end,
         coalesce(l.lineas,0),
         coalesce(l.lineas,0) - coalesce(l.con_precio,0),
         case when public.cob_empresa_np(p.np)='ch' then null
              else round(100.0*coalesce(l.con_precio,0)/nullif(l.lineas,0),1) end,
         (public.cob_empresa_np(p.np)='ch')
  from prog p
  left join lin l using (npk)
  order by (case when public.cob_empresa_np(p.np)='ch' then null else coalesce(l.valor,0) end) desc nulls last;
$$;

-- Permisos: la app usa la anon key (mismo criterio que precios_venta,
-- que ya es anon-readable). Valor de LISTA no es dato sensible.
grant execute on function public.cob_norm_cod(text)              to anon, authenticated;
grant execute on function public.cob_empresa_np(text)            to anon, authenticated;
grant execute on function public.cobranzas_valorizar_np(text)    to anon, authenticated;
grant execute on function public.cobranzas_resumen()             to anon, authenticated;

-- --------------------------------------------------------------
-- SYNC precios_venta desde LK — ampliado a loke_products.
--   Correr EN LK (kwkclwhmoygunqmlegrg) y ejecutar el INSERT resultante acá.
--   (mismo patrón que plata_perdida.sql; sin FDW, manual)
--
--   select 'insert into public.precios_venta (cod, precio_unit, uxb, descripcion) values ' ||
--     string_agg('(' || quote_literal(btrim(cod)) || ',' || coalesce(nullif(list_price,0)::text,'null') || ',' ||
--                coalesce(uxb::text,'null') || ',' || quote_literal(coalesce(left(description,120),'')) || ')', ',') ||
--     ' on conflict (cod) do update set precio_unit=excluded.precio_unit, uxb=excluded.uxb,'
--     ' descripcion=excluded.descripcion, actualizado=now();'
--   from (
--     select cod, list_price, uxb, description from products where coalesce(list_price,0)>0 and btrim(coalesce(cod,''))<>''
--     union all
--     select cod, list_price, uxb, description from loke_products where coalesce(list_price,0)>0 and btrim(coalesce(cod,''))<>''
--   ) t;
--
--   Estado 2026-08-17: 230 códigos (214 products + 16 loke_products).
-- --------------------------------------------------------------
