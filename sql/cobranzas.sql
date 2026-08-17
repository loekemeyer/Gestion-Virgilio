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
--  `lista_no_disponible`.
--
--  ⚠ precio 8888 en la lista = placeholder (sin precio real) → NO valoriza.
--
--  CLASIFICACIÓN DEL FALTANTE (regla del dueño, 2026-08-17): que un artículo
--  no tenga precio de lista casi nunca es un hueco a cargar. Se separa el
--  faltante en cuatro motivos (`cob_estado_articulo`):
--    · discontinuado — está en `Articulos_Discontinuados` o `OC_Maximos.activo=false`.
--    · especial      — código de 5 dígitos = artículo de UN solo cliente ("no van").
--    · loke          — código que empieza con 1 = lista Loke, no se ofrece a cualquiera.
--    · sin_precio     — lo único realmente a cargar en LK.
-- ============================================================

-- ── 1) Normalización canónica de código ─────────────────────────────
--  Match insensible a mayúsculas, espacios y ceros a la izquierda: en los
--  pedidos aparecen `948e`/`948E`, `029`/`29`. Mismo criterio que el
--  norm_cod del proyecto web.
create or replace function public.cob_norm_cod(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(upper(btrim(coalesce(p,''))), '^0+(?=.)', ''), '')
$$;

-- ── 2) Empresa de una NP por su numeración ──────────────────────────
create or replace function public.cob_empresa_np(p_np text)
returns text language sql immutable as $$
  select case left(regexp_replace(coalesce(p_np,''),'\D','','g'),1)
           when '9' then 'lk' when '4' then 'ch' else 'otro' end
$$;

-- ── 3) Por qué un artículo no tiene precio de lista ─────────────────
create or replace function public.cob_estado_articulo(p_cod text)
returns text language sql stable set search_path=public as $$
  select case
    when exists (select 1 from public."Articulos_Discontinuados" d
                 where public.cob_norm_cod(d.cod)=public.cob_norm_cod(p_cod))
      or exists (select 1 from public."OC_Maximos" o
                 where o.activo=false and public.cob_norm_cod(o.cod)=public.cob_norm_cod(p_cod))
      then 'discontinuado'
    when length(regexp_replace(coalesce(public.cob_norm_cod(p_cod),''),'\D','','g'))=5 then 'especial'
    when left(coalesce(public.cob_norm_cod(p_cod),''),1)='1' then 'loke'
    else 'sin_precio'
  end
$$;

-- ── 4) Valorizar UNA NP (valor de lista) ────────────────────────────
create or replace function public.cobranzas_valorizar_np(p_np text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp text := public.cob_empresa_np(p_np); v_rs text; v_cod text; v_res jsonb;
begin
  select max(razon_social), max(cod) into v_rs, v_cod
  from public."PPP_Programacion_Diaria"
  where regexp_replace(coalesce(np,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g');

  if v_emp = 'ch' then
    select jsonb_build_object('np',p_np,'empresa','ch','cod_cliente',v_cod,'cliente',v_rs,
             'lista_no_disponible',true,'nota','Lista de Chef no cargada en Virgilio (vive en otro proyecto).',
             'cajas',coalesce(sum(cajas),0),'lineas',coalesce(count(*),0)) into v_res
    from public."PPP_Base_Pedidos"
    where regexp_replace(coalesce(pedido,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g');
    return v_res;
  end if;

  with lineas as (
    select b.articulo, sum(b.cajas) as cajas, pv.precio_unit, pv.uxb, pv.descripcion,
           (pv.precio_unit is not null and pv.precio_unit>0 and pv.precio_unit<>8888) as con_precio,
           case when (pv.precio_unit is not null and pv.precio_unit>0 and pv.precio_unit<>8888) then null
                else public.cob_estado_articulo(b.articulo) end as motivo
    from public."PPP_Base_Pedidos" b
    left join public.precios_venta pv on public.cob_norm_cod(pv.cod)=public.cob_norm_cod(b.articulo)
    where regexp_replace(coalesce(b.pedido,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g')
    group by b.articulo, pv.precio_unit, pv.uxb, pv.descripcion
  )
  select jsonb_build_object('np',p_np,'empresa','lk','cod_cliente',v_cod,'cliente',v_rs,
    'valor_lista', coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric,2),0),
    'estimado_con_iva', coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric*0.98*1.21,2),0),
    'cajas', coalesce(sum(cajas),0), 'lineas_total', count(*),
    'lineas_con_precio', count(*) filter (where con_precio),
    'sin_precio_real',   count(*) filter (where motivo='sin_precio'),
    'especiales',        count(*) filter (where motivo='especial'),
    'loke_sin_precio',   count(*) filter (where motivo='loke'),
    'discontinuados',    count(*) filter (where motivo='discontinuado'),
    'cobertura_pct', round(100.0*count(*) filter (where con_precio)/nullif(count(*),0),1),
    -- cobertura útil: ignora especiales / loke / discontinuados (no son huecos a cargar)
    'cobertura_util_pct', round(100.0*count(*) filter (where con_precio)/nullif(count(*) filter (where con_precio or motivo='sin_precio'),0),1),
    'a_cargar', coalesce(jsonb_agg(articulo) filter (where motivo='sin_precio'),'[]'::jsonb),
    'detalle', coalesce(jsonb_agg(
                 jsonb_build_object('articulo',articulo,'descripcion',descripcion,'cajas',cajas,
                   'precio_unit',precio_unit,'uxb',uxb,'motivo',motivo,
                   'valor_lista', case when con_precio then round((precio_unit*uxb*cajas)::numeric,2) end)
                 order by (case when con_precio then precio_unit*uxb*cajas else 0 end) desc),'[]'::jsonb),
    'nota','valor_lista = lista sin dto. cobertura_util ignora especiales/loke/discontinuados. Neto exacto: arca-wsfe/preciar.') into v_res
  from lineas;
  return v_res;
end $$;

-- ── 5) Resumen de cobranzas de las NP en curso ──────────────────────
--  `sin_precio_real` = solo los faltantes que SÍ habría que cargar en LK
--  (excluye especiales/loke/discontinuados). Chef → valor_lista NULL.
create or replace function public.cobranzas_resumen()
returns table (
  np text, empresa text, cod_cliente text, cliente text, cajas numeric,
  valor_lista numeric, lineas_total bigint, lineas_sin_precio bigint, sin_precio_real bigint,
  cobertura_pct numeric, lista_no_disponible boolean
)
language sql security definer set search_path = public as $$
  with prog as (
    select regexp_replace(coalesce(np,''),'\D','','g') as npk, max(np) np, max(cod) cod, max(razon_social) rs
    from public."PPP_Programacion_Diaria" group by 1
  ),
  lin as (
    select regexp_replace(coalesce(b.pedido,''),'\D','','g') as npk, sum(b.cajas) cajas, count(*) lineas,
           count(*) filter (where pv.precio_unit is not null and pv.precio_unit>0 and pv.precio_unit<>8888) con_precio,
           count(*) filter (where (pv.precio_unit is null or pv.precio_unit<=0 or pv.precio_unit=8888)
                              and public.cob_estado_articulo(b.articulo)='sin_precio') sin_precio_real,
           sum(case when pv.precio_unit is not null and pv.precio_unit>0 and pv.precio_unit<>8888
                    then pv.precio_unit*pv.uxb*b.cajas end) valor
    from public."PPP_Base_Pedidos" b
    left join public.precios_venta pv on public.cob_norm_cod(pv.cod)=public.cob_norm_cod(b.articulo)
    group by 1
  )
  select p.np, public.cob_empresa_np(p.np) as empresa, p.cod, p.rs, coalesce(l.cajas,0),
         case when public.cob_empresa_np(p.np)='ch' then null else round(coalesce(l.valor,0)::numeric,2) end,
         coalesce(l.lineas,0), coalesce(l.lineas,0)-coalesce(l.con_precio,0), coalesce(l.sin_precio_real,0),
         case when public.cob_empresa_np(p.np)='ch' then null
              else round(100.0*coalesce(l.con_precio,0)/nullif(l.lineas,0),1) end,
         (public.cob_empresa_np(p.np)='ch')
  from prog p left join lin l using (npk)
  order by (case when public.cob_empresa_np(p.np)='ch' then null else coalesce(l.valor,0) end) desc nulls last;
$$;

-- Permisos: la app usa la anon key (mismo criterio que precios_venta,
-- que ya es anon-readable). Valor de LISTA no es dato sensible.
grant execute on function public.cob_norm_cod(text)            to anon, authenticated;
grant execute on function public.cob_empresa_np(text)          to anon, authenticated;
grant execute on function public.cob_estado_articulo(text)     to anon, authenticated;
grant execute on function public.cobranzas_valorizar_np(text)  to anon, authenticated;
grant execute on function public.cobranzas_resumen()           to anon, authenticated;

-- --------------------------------------------------------------
-- SYNC precios_venta desde LK — products ∪ loke_products.
--   Correr EN LK (kwkclwhmoygunqmlegrg) y ejecutar el INSERT resultante acá.
--   (mismo patrón que plata_perdida.sql; sin FDW, manual)
--
--   select 'insert into public.precios_venta (cod, precio_unit, uxb, descripcion) values ' ||
--     string_agg('(' || quote_literal(btrim(cod)) || ',' || nullif(list_price,0)::text || ',' ||
--                coalesce(uxb::text,'null') || ',' || quote_literal(coalesce(left(description,120),'')) || ')', ',') ||
--     ' on conflict (cod) do update set precio_unit=excluded.precio_unit, uxb=excluded.uxb,'
--     ' descripcion=excluded.descripcion, actualizado=now();'
--   from (
--     select cod, list_price, uxb, description from products      where coalesce(list_price,0)>0 and btrim(coalesce(cod,''))<>''
--     union all
--     select cod, list_price, uxb, description from loke_products where coalesce(list_price,0)>0 and btrim(coalesce(cod,''))<>''
--   ) t;
--
--   Estado 2026-08-17: 231 códigos (products + loke_products, 7 placeholder 8888).
--   Backup previo en public.precios_venta_backup_20260817.
-- --------------------------------------------------------------
