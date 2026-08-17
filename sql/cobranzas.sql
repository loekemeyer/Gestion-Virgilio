-- ============================================================
--  Módulo Cobranzas — valorizar una NP sin ver la factura
--  Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
--  OBJETIVO: que Virgilio sepa cuánta plata se le facturó a cada NP /
--  cliente sin tener la factura a la vista, cruzando el detalle de líneas
--  (PPP_Base_Pedidos: artículo × cajas) con la lista de precios.
--
--  DOS NIVELES DE PRECIO (a propósito):
--   1) VALOR DE LISTA — en la base, al toque y en lote (este archivo). Sale
--      de `precios_venta` (LK: products+loke_products) y `precios_venta_chef`
--      (Chef). NO aplica dto por cliente: `precios_venta*` son anon-readable
--      y copiar el padrón de descuentos de LK acá lo filtraría.
--   2) NETO EXACTO por NP — Edge Function `arca-wsfe` acción `preciar`, lee
--      LK EN VIVO (service_role): list_price×(1−dto_vol)×(1−2%)+IVA 21%.
--
--  EMPRESA por NP: 9xxxx = Loekemeyer, 4xxxx = Chef. Numeraciones
--  INDEPENDIENTES: el mismo código es OTRO artículo en cada empresa, por eso
--  los precios de Chef viven en `precios_venta_chef` (tabla aparte) y NO se
--  mezclan con los de LK.
--
--  ⚠ precio 8888 = placeholder (sin precio real) → NO valoriza.
--
--  CLASIFICACIÓN DEL FALTANTE (regla del dueño): que un artículo no tenga
--  precio de lista casi nunca es un hueco a cargar (`cob_estado_articulo`):
--    · discontinuado — `Articulos_Discontinuados` o `OC_Maximos.activo=false`.
--    · especial      — código de 5 dígitos = artículo de UN solo cliente.
--    · loke          — código que empieza con 1 = lista Loke, no se ofrece a cualquiera.
--    · sin_precio     — lo único realmente a cargar.
--
--  ALIAS DE CÓDIGO (`cobranzas_alias`): cuando el código ACTIVO en los
--  pedidos difiere del que tiene el precio cargado por grafía (misma pieza,
--  otra escritura). NO se resuelve con un fallback automático de la "E"
--  porque hay pares NNN/NNNE que son productos DISTINTOS con precio distinto
--  (p.ej. 323 Rallador Cilíndrico $1355 vs 323E Rallador Mini $1295). Solo
--  los pares confirmados a mano entran acá.
-- ============================================================

-- ── 1) Normalización canónica de código ─────────────────────────────
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

-- ── 4) Tablas de precio ─────────────────────────────────────────────
--  LK: public.precios_venta (ya existe, de plata_perdida.sql).
--  Chef: tabla aparte (código Chef ≠ código LK).
create table if not exists public.precios_venta_chef (
  cod text primary key, precio_unit numeric, uxb integer, descripcion text,
  actualizado timestamptz default now()
);
alter table public.precios_venta_chef enable row level security;
drop policy if exists pvc_sel on public.precios_venta_chef;
create policy pvc_sel on public.precios_venta_chef for select to anon, authenticated using (true);
drop policy if exists pvc_wr on public.precios_venta_chef;
create policy pvc_wr on public.precios_venta_chef for all to authenticated using (true) with check (true);

-- Alias de código (código de pedido → código con precio). Editable a mano.
create table if not exists public.cobranzas_alias (
  empresa text not null default 'lk',
  cod_prod text not null,
  cod_precio text not null,
  nota text,
  primary key (empresa, cod_prod)
);
alter table public.cobranzas_alias enable row level security;
drop policy if exists ca_sel on public.cobranzas_alias;
create policy ca_sel on public.cobranzas_alias for select to anon, authenticated using (true);
drop policy if exists ca_wr on public.cobranzas_alias;
create policy ca_wr on public.cobranzas_alias for all to authenticated using (true) with check (true);

-- Correcciones confirmadas por el dueño (2026-08-17):
--   580 es el código ACTIVO; el precio vive bajo 580E (mismo artículo, Batidor Mini).
--   (574: el activo es 574E; ambos ya están cargados a $2770, no hace falta alias.)
insert into public.cobranzas_alias (empresa, cod_prod, cod_precio, nota) values
  ('lk','580','580E','activo 580, precio bajo 580E')
on conflict (empresa, cod_prod) do update set cod_precio=excluded.cod_precio, nota=excluded.nota;

-- ── 5) Vista única de precios efectivos por empresa (directo + alias) ─
create or replace view public.cobranzas_precios as
with base as (
  select 'lk'::text empresa, public.cob_norm_cod(cod) nc, precio_unit, uxb
    from public.precios_venta      where precio_unit>0 and precio_unit<>8888
  union all
  select 'ch', public.cob_norm_cod(cod), precio_unit, uxb
    from public.precios_venta_chef where precio_unit>0 and precio_unit<>8888
)
select empresa, nc, precio_unit, uxb from base
union all
select a.empresa, public.cob_norm_cod(a.cod_prod), b.precio_unit, b.uxb
from public.cobranzas_alias a
join base b on b.empresa=a.empresa and b.nc=public.cob_norm_cod(a.cod_precio)
where not exists (select 1 from base b2 where b2.empresa=a.empresa and b2.nc=public.cob_norm_cod(a.cod_prod));
grant select on public.cobranzas_precios to anon, authenticated;

-- ── 6) Valorizar UNA NP ─────────────────────────────────────────────
create or replace function public.cobranzas_valorizar_np(p_np text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp text := public.cob_empresa_np(p_np); v_rs text; v_cod text; v_res jsonb; v_hay_ch boolean;
begin
  select max(razon_social), max(cod) into v_rs, v_cod
  from public."PPP_Programacion_Diaria"
  where regexp_replace(coalesce(np,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g');

  if v_emp = 'ch' then
    select exists(select 1 from public.cobranzas_precios where empresa='ch') into v_hay_ch;
  end if;

  with lineas as (
    select b.articulo, sum(b.cajas) as cajas, px.precio_unit, px.uxb,
           (px.precio_unit is not null) as con_precio,
           case when px.precio_unit is not null then null
                else public.cob_estado_articulo(b.articulo) end as motivo
    from public."PPP_Base_Pedidos" b
    left join public.cobranzas_precios px
           on px.empresa=v_emp and px.nc=public.cob_norm_cod(b.articulo)
    where regexp_replace(coalesce(b.pedido,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g')
    group by b.articulo, px.precio_unit, px.uxb
  )
  select jsonb_build_object('np',p_np,'empresa',v_emp,'cod_cliente',v_cod,'cliente',v_rs,
    'lista_no_disponible', (v_emp='ch' and not coalesce(v_hay_ch,false)),
    'valor_lista', coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric,2),0),
    'estimado_con_iva', coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric*0.98*1.21,2),0),
    'cajas', coalesce(sum(cajas),0), 'lineas_total', count(*),
    'lineas_con_precio', count(*) filter (where con_precio),
    'sin_precio_real',   count(*) filter (where motivo='sin_precio'),
    'especiales',        count(*) filter (where motivo='especial'),
    'loke_sin_precio',   count(*) filter (where motivo='loke'),
    'discontinuados',    count(*) filter (where motivo='discontinuado'),
    'cobertura_pct', round(100.0*count(*) filter (where con_precio)/nullif(count(*),0),1),
    'cobertura_util_pct', round(100.0*count(*) filter (where con_precio)/nullif(count(*) filter (where con_precio or motivo='sin_precio'),0),1),
    'a_cargar', coalesce(jsonb_agg(articulo) filter (where motivo='sin_precio'),'[]'::jsonb),
    'detalle', coalesce(jsonb_agg(jsonb_build_object('articulo',articulo,'cajas',cajas,'precio_unit',precio_unit,'uxb',uxb,'motivo',motivo,
                 'valor_lista', case when con_precio then round((precio_unit*uxb*cajas)::numeric,2) end)
                 order by (case when con_precio then precio_unit*uxb*cajas else 0 end) desc),'[]'::jsonb),
    'nota','valor_lista = lista sin dto (incluye alias). Neto exacto: arca-wsfe/preciar.') into v_res
  from lineas;
  return v_res;
end $$;

-- ── 7) Resumen de cobranzas de las NP en curso ──────────────────────
create or replace function public.cobranzas_resumen()
returns table (np text, empresa text, cod_cliente text, cliente text, cajas numeric,
  valor_lista numeric, lineas_total bigint, lineas_sin_precio bigint, sin_precio_real bigint,
  cobertura_pct numeric, lista_no_disponible boolean)
language sql security definer set search_path = public as $$
  with prog as (
    select regexp_replace(coalesce(np,''),'\D','','g') as npk, max(np) np, max(cod) cod, max(razon_social) rs
    from public."PPP_Programacion_Diaria" group by 1
  ),
  hay as (select empresa, count(*)>0 tiene from public.cobranzas_precios group by empresa),
  lin as (
    select regexp_replace(coalesce(b.pedido,''),'\D','','g') as npk,
           sum(b.cajas) cajas, count(*) lineas,
           count(*) filter (where px.precio_unit is not null) con_precio,
           count(*) filter (where px.precio_unit is null and public.cob_estado_articulo(b.articulo)='sin_precio') sin_precio_real,
           sum(case when px.precio_unit is not null then px.precio_unit*px.uxb*b.cajas end) valor
    from public."PPP_Base_Pedidos" b
    left join public.cobranzas_precios px
           on px.empresa=public.cob_empresa_np(b.pedido) and px.nc=public.cob_norm_cod(b.articulo)
    group by 1
  )
  select p.np, public.cob_empresa_np(p.np), p.cod, p.rs, coalesce(l.cajas,0),
         round(coalesce(l.valor,0)::numeric,2),
         coalesce(l.lineas,0), coalesce(l.lineas,0)-coalesce(l.con_precio,0), coalesce(l.sin_precio_real,0),
         round(100.0*coalesce(l.con_precio,0)/nullif(l.lineas,0),1),
         (public.cob_empresa_np(p.np)='ch' and not coalesce((select tiene from hay where empresa='ch'),false))
  from prog p left join lin l using (npk)
  order by coalesce(l.valor,0) desc nulls last;
$$;

-- Permisos
grant execute on function public.cob_norm_cod(text)            to anon, authenticated;
grant execute on function public.cob_empresa_np(text)          to anon, authenticated;
grant execute on function public.cob_estado_articulo(text)     to anon, authenticated;
grant execute on function public.cobranzas_valorizar_np(text)  to anon, authenticated;
grant execute on function public.cobranzas_resumen()           to anon, authenticated;

-- --------------------------------------------------------------
-- SYNC precios (sin FDW, manual — patrón de plata_perdida.sql):
--   · LK:   correr el generador de plata_perdida.sql / cobranzas ampliado a
--           products ∪ loke_products; upsert en public.precios_venta.
--   · Chef: correr sql/cobranzas_chef_sync.sql EN EL PROYECTO CHEF
--           (nkhzocgdpwtgrmwleihr) y ejecutar el INSERT resultante acá,
--           contra public.precios_venta_chef.
--
--   Estado 2026-08-17: LK 231 códigos (7 placeholder). Chef sin cargar.
--   Backup previo de precios_venta en public.precios_venta_backup_20260817.
-- --------------------------------------------------------------
