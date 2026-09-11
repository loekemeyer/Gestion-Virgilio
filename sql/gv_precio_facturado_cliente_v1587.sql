-- ══════════════════════════════════════════════════════════════════════════
-- v15.87 (2026-09-11) — EL PRECIO SALE DE LA FACTURA: último precio realmente
-- facturado a cada cliente por cada artículo (ISIS parseado)
-- ══════════════════════════════════════════════════════════════════════════
-- Thomas: *"Ya tendrías que tener los precios de todo lo que te falta, porque ya tenés
-- parseadas las facturas. Revisá una factura anterior de Cencosud, que en la NP 44617 está
-- pidiendo el código 106E. No puede ser que te falte el precio si ya se lo ha facturado."*
--
-- Tenía razón. Los esquemas **`isis_lk`** e **`isis_ch`** tienen las facturas de ISIS
-- parseadas CON DETALLE POR ÍTEM: `documento_items` (código, cantidad, precio_unit, dto_1,
-- dto_2, importe) — **314.529 líneas** sobre 40.083 documentos, desde 2019. Nadie las estaba
-- usando para valorizar; `vista_cruce_facturacion` sólo miraba el TOTAL del documento.
--
-- ── Dos cosas que hay que saber para leer esa tabla ───────────────────────
-- 1. **Cencosud factura con la L**: `102EL`, `106EL`, `123L` (artículo de Loeke vendido por
--    Chef, regla v13.71), mientras que en `Entregas_Virgilio` el mismo pedido viene SIN la L
--    (`102E`, `106E`, `123`). Por eso hay que pelar la L de los DOS lados para machear.
-- 2. **`precio_unit` NO es confiable**: en 64.622 de 252.300 líneas (25,6 %) no cuadra con el
--    importe. El caso típico es que venga el precio POR CAJA (ratio exacto ×12) — p. ej. la
--    FC-A-0005-00000389 trae 29.700 para el 102EL cuando el unitario es 2.475. Además la
--    `descripcion` viene corrida (el código del renglón anterior pegado adelante).
--    **El precio se DESPEJA del importe**, que sí cierra siempre:
--        precio = importe / (cantidad × (1 − dto_1/100) × (1 − dto_2/100))
--    Verificado: 468 × 2.475 × 0,84 = 972.972 = el importe de la factura, exacto.
--
-- ── Objetos ──────────────────────────────────────────────────────────────
--   public.gv_precio_facturado_cliente   — vista: por (empresa, cod_cliente, cod_canon) el
--        ÚLTIMO precio facturado. `precio_neto` = importe/cantidad (lo que realmente se
--        cobró, con los descuentos ya aplicados) y `precio_bruto` = antes de los descuentos.
--        78.845 combinaciones. Cuesta 2.765 ms, así que NO se usa en vivo.
--   public."GV_Precio_Facturado_Cache"   — la misma tabla materializada (78.845 filas), que
--        es lo que leen las vistas de Facturación. RLS prendida, revocada de anon.
--   public.gv_refrescar_precio_facturado() — la rellena. Cron `gv-precio-facturado-diario`
--        (jobid 82, 09:25 UTC = 06:25 ART).
--
-- ── Dónde entra en la cascada de precios ─────────────────────────────────
--   1. lista de SÚPER (cobranzas_precios_super)
--   2. GV_Precios_Cliente (precio pactado a mano)
--   3. lista de la empresa de la NP (precios_venta_chef)
--   4. lista de LK (precios_venta)
--   5. **GV_Precio_Facturado_Cache** ← este, el último antes de "sin precio"
--   Va ÚLTIMO a propósito: así no mueve ni un número de lo que hoy ya se valoriza, sólo
--   rellena los huecos. Se usa `precio_neto`, o sea SIN dto_vol y SIN el 2 % (es lo que la
--   factura cobró), igual que un `GV_Precios_Cliente.es_final`.
--   **Si algún día se quiere que la factura MANDE sobre las listas** —tiene sentido: es lo
--   que realmente se le cobró a ese cliente— es mover este escalón arriba del 3. Eso sí
--   movería números ya en pantalla, así que es decisión del dueño.
--
-- ── Medido (11/09) ───────────────────────────────────────────────────────
--   vista_facturacion_neto_items : 85 → **7** líneas sin precio (resuelve 78)
--   vista_facturable_anticipado  : 12 → **0**
--   vista_plata_perdida          : 14 → **5**
--   Ninguna línea que YA tenía precio se movió: 0 de LK contra el snapshot.
--   Caso testigo NP 44617 (Cencosud): antes el 106E salía sin precio; ahora va a $1.806 y la
--   NP cierra en **$3.106.008** con 0 códigos sin precio. Cencosud queda con
--   102E $2.079 · 106E $1.806 · 123 $1.062,60 (netos, el 16 % ya aplicado).
--   `facturacion_neto_lote` de 3 NP: 601 ms.
--
-- ROLLBACK:
--   drop view public.gv_precio_facturado_cliente cascade;
--   drop table public."GV_Precio_Facturado_Cache" cascade;
--   drop function public.gv_refrescar_precio_facturado();
--   select cron.unschedule('gv-precio-facturado-diario');
--   + recrear las tres vistas con sql/gv_precios_cliente_v1582.sql (estado anterior).
-- ══════════════════════════════════════════════════════════════════════════

create or replace view public.gv_precio_facturado_cliente
with (security_invoker = true) as
with li as (
  select 'lk'::text as empresa, regexp_replace(d.contraparte_codigo, '\D', '', 'g') as cc,
         d.fecha, i.codigo_articulo, i.cantidad, i.importe, i.dto_1, i.dto_2
  from isis_lk.documentos d
  join isis_lk.documento_items i on i.documento_id = d.id
  where d.familia = 'factura_venta' and d.contraparte_codigo is not null
    and i.codigo_articulo is not null and coalesce(i.cantidad,0) > 0 and coalesce(i.importe,0) > 0
  union all
  select 'chef', regexp_replace(d.contraparte_codigo, '\D', '', 'g'),
         d.fecha, i.codigo_articulo, i.cantidad, i.importe, i.dto_1, i.dto_2
  from isis_ch.documentos d
  join isis_ch.documento_items i on i.documento_id = d.id
  where d.familia = 'factura_venta' and d.contraparte_codigo is not null
    and i.codigo_articulo is not null and coalesce(i.cantidad,0) > 0 and coalesce(i.importe,0) > 0
),
calc as (
  select empresa, cc,
    -- la L final = artículo de Loeke facturado por la otra empresa; el pedido lo trae sin L
    public.canon_cod(case when upper(btrim(codigo_articulo)) ~ '[0-9E]L$'
                         then regexp_replace(upper(btrim(codigo_articulo)), 'L$', '')
                         else codigo_articulo end) as cod_canon,
    fecha,
    round(importe / cantidad, 4) as precio_neto,
    round(importe / nullif(cantidad * (1 - coalesce(dto_1,0)/100) * (1 - coalesce(dto_2,0)/100), 0), 4) as precio_bruto,
    coalesce(dto_1,0) + coalesce(dto_2,0) as dto_pct,
    cantidad
  from li
)
select distinct on (empresa, cc, cod_canon)
  empresa, cc as cod_cliente, cod_canon, fecha as fecha_factura,
  precio_neto, precio_bruto, dto_pct, cantidad as cantidad_factura
from calc
where precio_neto > 0
order by empresa, cc, cod_canon, fecha desc, cantidad desc;

revoke all on public.gv_precio_facturado_cliente from anon, authenticated;

create table if not exists public."GV_Precio_Facturado_Cache" (
  empresa          text    not null,
  cod_cliente      text    not null,
  cod_canon        text    not null,
  fecha_factura    date,
  precio_neto      numeric not null,
  precio_bruto     numeric,
  dto_pct          numeric,
  cantidad_factura numeric,
  refrescado_at    timestamptz not null default now(),
  primary key (empresa, cod_cliente, cod_canon)
);
alter table public."GV_Precio_Facturado_Cache" enable row level security;
revoke all on public."GV_Precio_Facturado_Cache" from anon, authenticated;

create or replace function public.gv_refrescar_precio_facturado()
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  -- el WHERE no es decorativo: supautils bloquea DELETE sin WHERE para no-superusuarios
  delete from public."GV_Precio_Facturado_Cache" where cod_cliente is not null;
  insert into public."GV_Precio_Facturado_Cache"
    (empresa, cod_cliente, cod_canon, fecha_factura, precio_neto, precio_bruto, dto_pct, cantidad_factura)
  select empresa, cod_cliente, cod_canon, fecha_factura, precio_neto, precio_bruto, dto_pct, cantidad_factura
  from public.gv_precio_facturado_cliente;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.gv_refrescar_precio_facturado() from anon, authenticated;

-- select cron.schedule('gv-precio-facturado-diario', '25 9 * * *',
--   $$select public.gv_refrescar_precio_facturado();$$);   -- jobid 82, hecho el 11/09

-- Las tres vistas de Facturación suman `pfc` como último escalón de la cascada; la
-- definición vigente de cada una se saca con:
--   select pg_get_viewdef('public.vista_facturacion_neto_items'::regclass, true);

-- ── Verificación ─────────────────────────────────────────────────────────
-- select * from public.facturacion_neto_lote(array['44617']);   → $3.106.008, 0 sin precio
-- select empresa, cod_cliente, cod_canon, precio_neto, precio_bruto, dto_pct
--   from public."GV_Precio_Facturado_Cache"
--  where empresa='chef' and cod_cliente='2444' and cod_canon in ('102E','106E','123');
