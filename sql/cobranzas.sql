-- ============================================================
--  Módulo Cobranzas — valorizar una NP sin ver la factura
--  Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
--  OBJETIVO: que Virgilio sepa cuánta plata se le facturó a cada NP / cliente
--  sin tener la factura a la vista, cruzando el detalle (PPP_Base_Pedidos:
--  artículo × cajas) con la lista de precios que corresponda.
--
--  TRES LISTAS, EN ESTE ORDEN DE PRIORIDAD por NP:
--   1) SÚPER — si el cliente de la NP es una cadena de supermercado con lista
--      especial cargada (cobranzas_cliente_cadena → precios_super_lk). Precio
--      final negociado, SIN descuento por cliente; algunas cadenas tienen
--      item_discount (Diarco 10%).
--   2) EMPRESA — lista normal de la empresa de la NP: LK (precios_venta) o
--      Chef (precios_venta_chef). Numeraciones INDEPENDIENTES: el mismo código
--      es otro artículo en cada empresa, por eso Chef va en tabla aparte.
--   3) LK (fallback) — para NP de Chef cuyos artículos son productos LOEKE
--      vendidos vía Chef (código de fábrica LK, no está en el catálogo Chef).
--
--  valor_lista = precio de lista SIN dto por cliente. El NETO exacto por NP
--  (con dto_vol del cliente + 2% web + IVA) sale online de la Edge Function
--  arca-wsfe acción `preciar`.
--
--  EMPRESA por NP: 9xxxx = Loekemeyer, 4xxxx = Chef.
--  ⚠ precio 8888 = placeholder (sin precio real) → NO valoriza.
--
--  CLASIFICACIÓN DEL FALTANTE (`cob_estado_articulo`): que un artículo no
--  tenga precio casi nunca es un hueco a cargar → discontinuado
--  (Articulos_Discontinuados / OC_Maximos.activo=false), especial (5 dígitos =
--  1 solo cliente), loke (empieza con 1 = lista Loke) o sin_precio (lo único
--  a cargar).
--
--  ALIAS (`cobranzas_alias`): código activo de pedido → código con precio
--  cuando difieren por grafía (NO se toca la "E" automático: 323≠323E).
-- ============================================================

-- ── Helpers ─────────────────────────────────────────────────────────
create or replace function public.cob_norm_cod(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(upper(btrim(coalesce(p,''))), '^0+(?=.)', ''), '')
$$;

create or replace function public.cob_empresa_np(p_np text)
returns text language sql immutable as $$
  select case left(regexp_replace(coalesce(p_np,''),'\D','','g'),1)
           when '9' then 'lk' when '4' then 'ch' else 'otro' end
$$;

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

-- ── Tablas de precio ────────────────────────────────────────────────
-- LK normal: public.precios_venta (de plata_perdida.sql).
-- Chef normal:
create table if not exists public.precios_venta_chef (
  cod text primary key, precio_unit numeric, uxb integer, descripcion text, actualizado timestamptz default now()
);
-- Listas de supermercado (espejo de precios_super del proyecto LK):
create table if not exists public.precios_super_lk (
  super_key text not null, cod text not null, price numeric not null, primary key (super_key, cod)
);
-- Config por cadena (item_discount, y si va con lista general en vez de especial):
create table if not exists public.cobranzas_super_cadena (
  super_key text primary key, label text, item_discount numeric not null default 0,
  usa_lista_general boolean not null default false
);
-- Mapeo cliente → cadena (de precios_super.cadena.cod_cliente_lk / cod_cliente_chef en LK):
create table if not exists public.cobranzas_cliente_cadena (
  empresa text not null, cod_cliente text not null, super_key text not null, primary key (empresa, cod_cliente)
);
-- uxb de todo el padrón LK (products ∪ loke_products), para valorizar cajas de
-- artículos que solo están en la lista de súper (no en la lista normal):
create table if not exists public.cob_uxb_lk (cod text primary key, uxb integer);
-- Alias de código:
create table if not exists public.cobranzas_alias (
  empresa text not null default 'lk', cod_prod text not null, cod_precio text not null, nota text,
  primary key (empresa, cod_prod)
);

-- RLS (anon-readable; valor de LISTA no es sensible):
do $$ declare t text;
begin
  foreach t in array array['precios_venta_chef','precios_super_lk','cobranzas_super_cadena',
                           'cobranzas_cliente_cadena','cob_uxb_lk','cobranzas_alias'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_sel on public.%I', t, t);
    execute format('create policy %I_sel on public.%I for select to anon, authenticated using (true)', t, t);
    execute format('drop policy if exists %I_wr on public.%I', t, t);
    execute format('create policy %I_wr on public.%I for all to authenticated using (true) with check (true)', t, t);
  end loop;
end $$;

-- Config de cadenas (item_discount / usa_lista_general):
insert into public.cobranzas_super_cadena (super_key,label,item_discount,usa_lista_general) values
 ('abastecedor','El Abastecedor (Tecnolar)',0,false),('alberdi','Alberdi',0,false),
 ('cencosud','Cencosud (Jumbo/Disco/Vea)',0,false),('coto','Coto',0,false),('dia','Día',0,false),
 ('diarco','Diarco',0.10,false),('dorinka','Dorinka (Walmart)',0,false),('inc','Carrefour (INC)',0,false),
 ('laanonima','La Anónima',0.19,false),('libertad','Libertad',0,false),('messina','Messina Hnos',0,true),
 ('toledo','Supermercados Toledo',0,false),
 -- v12.37: distribuidoras/clientes con lista propia (no supermercado, mismo mecanismo). Listas
 -- cargadas a mano desde Excel del ERP, no espejan de LK. item_discount=0.
 ('gm','Distribuidora GM S.R.L.',0,false),
 -- 'gigot' = Gigot Cosméticos (el ERP la llama "34 Lista Gigot"); el cliente la llama "Matiz".
 -- cod lk 5000. Lista parcial (2 ítems, códigos 5 dígitos). cod 5000 no factura por Virgilio hoy.
 ('gigot','Gigot Cosméticos (Matiz)',0,false)
on conflict (super_key) do update set label=excluded.label, item_discount=excluded.item_discount, usa_lista_general=excluded.usa_lista_general;

-- Mapeo cliente → cadena (cod_cliente_lk 9xxxx / cod_cliente_chef 4xxxx):
insert into public.cobranzas_cliente_cadena (empresa,cod_cliente,super_key) values
 ('lk','4051','abastecedor'),('lk','2320','alberdi'),('lk','801','coto'),('lk','3947','dia'),
 ('lk','4112','diarco'),('lk','1651','inc'),('lk','771','laanonima'),('lk','325','libertad'),
 ('lk','1573','messina'),('lk','1947','toledo'),('ch','2444','cencosud'),('ch','2686','dorinka'),
 ('lk','4080','gm'),('lk','5000','gigot')
on conflict (empresa,cod_cliente) do update set super_key=excluded.super_key;

-- v12.37: lista de Distribuidora GM (super_key 'gm'). Origen: Excel del ERP
-- (vta_listaprecios.xls), precio POR CAJA. precios_super_lk guarda POR UNIDAD, así que
-- se divide por el uxb que usará la valorización (cob_uxb_lk → cobranzas_precios → precios_venta).
-- Verificado contra ISIS: NP 97890 pasó de -42% (lista general) a -6,6% (lista GM; la lista
-- parece ~6% desactualizada respecto de la fecha de la FC). NO espeja de LK: es carga manual.
insert into public.precios_super_lk (super_key, cod, price)
select 'gm', g.cod, round(g.pcaja / coalesce(u.uxb, cp.uxb, pv.uxb, 1)::numeric, 6)
from (values
 ('026',20700),('027',18000),('029',55680),('030',79680),('031',11640),
 ('101',17190),('102E',13200),('103',5580),('104',9840),('106E',15720),
 ('108',13140),('110',19440),('111',16920),('112',120500),('113',82320),
 ('114',8790),('115',11940),('116',14400),('119',17400),('121',17040),
 ('123',9480),('315',19680),('395',13020),('501',17880),('502',18240),
 ('504',10170),('508',17340),('510',6000),('516',59500),('523',57660),
 ('529E',19680),('544',12840),('546',18900),('561',29940),('562',15840),
 ('581',10380),('587',12060)) g(cod,pcaja)
left join (select public.cob_norm_cod(cod) nc, max(uxb) uxb from public.cob_uxb_lk group by 1) u
       on u.nc = public.cob_norm_cod(g.cod)
left join lateral (select uxb from public.cobranzas_precios p where p.empresa='lk' and p.nc=public.cob_norm_cod(g.cod) limit 1) cp on true
left join public.precios_venta pv on public.canon_cod(pv.cod)=public.canon_cod(g.cod)
where g.pcaja > 0
on conflict (super_key,cod) do update set price=excluded.price;

-- v12.37: lista de Gigot Cosméticos (Matiz), super_key 'gigot'. Origen: Excel del ERP
-- ("34 Lista Gigot"), precio POR CAJA → por unidad. Lista PARCIAL (2 ítems). cod lk 5000 no
-- factura por Virgilio hoy, así que no tiene efecto todavía; queda preparada. Mismo cálculo de uxb.
insert into public.precios_super_lk (super_key, cod, price)
select 'gigot', g.cod, round(g.pcaja / coalesce(u.uxb, cp.uxb, pv.uxb, 1)::numeric, 6)
from (values ('55215Z',23880),('55289',20280)) g(cod,pcaja)
left join (select public.cob_norm_cod(cod) nc, max(uxb) uxb from public.cob_uxb_lk group by 1) u
       on u.nc = public.cob_norm_cod(g.cod)
left join lateral (select uxb from public.cobranzas_precios p where p.empresa='lk' and p.nc=public.cob_norm_cod(g.cod) limit 1) cp on true
left join public.precios_venta pv on public.canon_cod(pv.cod)=public.canon_cod(g.cod)
where g.pcaja > 0
on conflict (super_key,cod) do update set price=excluded.price;

-- Alias confirmados por el dueño (2026-08-17):
insert into public.cobranzas_alias (empresa, cod_prod, cod_precio, nota) values
  ('lk','580','580E','activo 580, precio bajo 580E')
on conflict (empresa, cod_prod) do update set cod_precio=excluded.cod_precio, nota=excluded.nota;

-- ── Vistas de precios efectivos ─────────────────────────────────────
-- Lista normal por empresa (directo + alias):
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

-- Lista de súper (precio × (1-item_discount); uxb del padrón LK):
create or replace view public.cobranzas_precios_super as
select s.super_key, s.nc, (s.price * (1 - coalesce(c.item_discount,0)))::numeric as precio_unit,
       coalesce(u.uxb, pv.uxb) as uxb
from (select super_key, public.cob_norm_cod(cod) nc, price from public.precios_super_lk) s
join public.cobranzas_super_cadena c on c.super_key=s.super_key and not c.usa_lista_general
left join (select public.cob_norm_cod(cod) nc, max(uxb) uxb from public.cob_uxb_lk group by 1) u on u.nc=s.nc
left join lateral (select uxb from public.cobranzas_precios p where p.empresa='lk' and p.nc=s.nc limit 1) pv on true;

grant select on public.cobranzas_precios, public.cobranzas_precios_super to anon, authenticated;

-- ── Valorizar UNA NP ────────────────────────────────────────────────
create or replace function public.cobranzas_valorizar_np(p_np text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_emp text := public.cob_empresa_np(p_np); v_rs text; v_cod text; v_cad text; v_res jsonb;
begin
  select max(razon_social), max(cod) into v_rs, v_cod
  from public."PPP_Programacion_Diaria"
  where regexp_replace(coalesce(np,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g');

  -- cadena de súper del cliente (si aplica lista especial)
  select cc.super_key into v_cad
  from public.cobranzas_cliente_cadena cc
  join public.cobranzas_super_cadena sc on sc.super_key=cc.super_key and not sc.usa_lista_general
  where cc.empresa=v_emp and cc.cod_cliente=btrim(coalesce(v_cod,''));

  with lineas as (
    select b.articulo, sum(b.cajas) as cajas, px.precio_unit, px.uxb, px.origen,
           (px.precio_unit is not null) as con_precio,
           case when px.precio_unit is not null then null else public.cob_estado_articulo(b.articulo) end as motivo
    from public."PPP_Base_Pedidos" b
    left join lateral (
      select precio_unit, uxb, origen from (
        select ps.precio_unit, ps.uxb, ('super:'||v_cad) origen, 1 prio
          from public.cobranzas_precios_super ps
          where v_cad is not null and ps.super_key=v_cad and ps.nc=public.cob_norm_cod(b.articulo) and ps.precio_unit is not null
        union all
        select p.precio_unit, p.uxb, p.empresa, 2
          from public.cobranzas_precios p
          where p.nc=public.cob_norm_cod(b.articulo) and p.empresa in (v_emp,'lk')
      ) q order by prio, (origen=v_emp) desc limit 1
    ) px on true
    where regexp_replace(coalesce(b.pedido,''),'\D','','g') = regexp_replace(coalesce(p_np,''),'\D','','g')
    group by b.articulo, px.precio_unit, px.uxb, px.origen
  )
  select jsonb_build_object('np',p_np,'empresa',v_emp,'cod_cliente',v_cod,'cliente',v_rs,'cadena',v_cad,
    'valor_lista', coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric,2),0),
    'estimado_con_iva', coalesce(round(sum(case when con_precio then precio_unit*uxb*cajas end)::numeric*0.98*1.21,2),0),
    'cajas', coalesce(sum(cajas),0), 'lineas_total', count(*),
    'lineas_con_precio', count(*) filter (where con_precio),
    'via_lista_lk', count(*) filter (where con_precio and origen='lk' and v_emp='ch'),
    'via_lista_super', count(*) filter (where con_precio and origen like 'super:%'),
    'sin_precio_real', count(*) filter (where motivo='sin_precio'),
    'cobertura_pct', round(100.0*count(*) filter (where con_precio)/nullif(count(*),0),1),
    'a_cargar', coalesce(jsonb_agg(articulo) filter (where motivo='sin_precio'),'[]'::jsonb),
    'detalle', coalesce(jsonb_agg(jsonb_build_object('articulo',articulo,'cajas',cajas,'precio_unit',precio_unit,'uxb',uxb,
                 'origen',origen,'motivo',motivo,
                 'valor_lista', case when con_precio then round((precio_unit*uxb*cajas)::numeric,2) end)
                 order by (case when con_precio then precio_unit*uxb*cajas else 0 end) desc),'[]'::jsonb),
    'nota','valor_lista sin dto. Supers con lista especial; Chef con fallback a lista LK. Neto exacto LK: arca-wsfe/preciar.') into v_res
  from lineas;
  return v_res;
end $$;

-- ── Resumen de cobranzas de las NP en curso ─────────────────────────
create or replace function public.cobranzas_resumen()
returns table (np text, empresa text, cod_cliente text, cliente text, cajas numeric,
  valor_lista numeric, lineas_total bigint, lineas_sin_precio bigint, sin_precio_real bigint,
  cobertura_pct numeric, via_lista_lk bigint, cadena text)
language sql security definer set search_path = public as $$
  with prog as (
    select regexp_replace(coalesce(np,''),'\D','','g') as npk, max(np) np, max(cod) cod, max(razon_social) rs
    from public."PPP_Programacion_Diaria" group by 1
  ),
  npc as (
    select p.npk, public.cob_empresa_np(p.np) emp, cc.super_key cad
    from prog p
    left join public.cobranzas_cliente_cadena cc
      on cc.empresa=public.cob_empresa_np(p.np) and cc.cod_cliente=btrim(coalesce(p.cod,''))
    left join public.cobranzas_super_cadena sc on sc.super_key=cc.super_key
    where sc.super_key is null or not sc.usa_lista_general
  ),
  px as (
    select regexp_replace(coalesce(b.pedido,''),'\D','','g') as npk, b.articulo, b.cajas,
           n.emp, pr.precio_unit, pr.uxb, pr.origen
    from public."PPP_Base_Pedidos" b
    join npc n on n.npk=regexp_replace(coalesce(b.pedido,''),'\D','','g')
    left join lateral (
      select precio_unit, uxb, origen from (
        select ps.precio_unit, ps.uxb, 'super' origen, 1 prio
          from public.cobranzas_precios_super ps
          where n.cad is not null and ps.super_key=n.cad and ps.nc=public.cob_norm_cod(b.articulo) and ps.precio_unit is not null
        union all
        select p.precio_unit, p.uxb, p.empresa, 2
          from public.cobranzas_precios p
          where p.nc=public.cob_norm_cod(b.articulo) and p.empresa in (n.emp,'lk')
      ) q order by prio, (origen=n.emp) desc limit 1
    ) pr on true
  ),
  lin as (
    select npk, sum(cajas) cajas, count(*) lineas,
           count(*) filter (where precio_unit is not null) con_precio,
           count(*) filter (where precio_unit is not null and origen='lk' and emp='ch') via_lk,
           count(*) filter (where precio_unit is null and public.cob_estado_articulo(articulo)='sin_precio') sin_precio_real,
           sum(case when precio_unit is not null then precio_unit*uxb*cajas end) valor
    from px group by npk
  )
  select p.np, public.cob_empresa_np(p.np), p.cod, p.rs, coalesce(l.cajas,0),
         round(coalesce(l.valor,0)::numeric,2),
         coalesce(l.lineas,0), coalesce(l.lineas,0)-coalesce(l.con_precio,0), coalesce(l.sin_precio_real,0),
         round(100.0*coalesce(l.con_precio,0)/nullif(l.lineas,0),1), coalesce(l.via_lk,0), n.cad
  from prog p left join lin l using (npk) left join npc n using (npk)
  order by coalesce(l.valor,0) desc nulls last;
$$;

grant execute on function public.cob_norm_cod(text)            to anon, authenticated;
grant execute on function public.cob_empresa_np(text)          to anon, authenticated;
grant execute on function public.cob_estado_articulo(text)     to anon, authenticated;
grant execute on function public.cobranzas_valorizar_np(text)  to anon, authenticated;
grant execute on function public.cobranzas_resumen()           to anon, authenticated;

-- --------------------------------------------------------------
-- SYNC de precios (sin FDW, manual — patrón de plata_perdida.sql):
--   · LK normal  → public.precios_venta (products ∪ loke_products).
--   · Chef       → public.precios_venta_chef (sql/cobranzas_chef_sync.sql,
--                  correr en el proyecto Chef nkhzocgdpwtgrmwleihr).
--   · Súper      → public.precios_super_lk + cobranzas_super_cadena +
--                  cobranzas_cliente_cadena (de precios_super.* del proyecto LK).
--   · uxb        → public.cob_uxb_lk (products ∪ loke_products, todo uxb).
--
--   Estado 2026-08-17: LK 231, Chef 101, súper 483 (9 cadenas), uxb ~260.
--   Cobertura NP en curso: LK ~100%, Chef 98,8%. Supers en curso: Diarco, INC.
--   Backup de precios_venta en public.precios_venta_backup_20260817.
-- --------------------------------------------------------------
