-- v30.06 (Luis, 13/10/2026) — "que no se pierda dios mio, como que se pierde?"
--
-- La recepción de insumos PIDE el remito (o la factura, con sus fechas) y después NO quedaba
-- en ninguna parte: `_insDocState` del front se usaba para GP2 y `insDocCancel` lo ponía en
-- null al cerrar el modal. Peor: `insEnviar` leía el remito de ESE objeto para pasárselo a
-- GP2, que para entonces ya era null, así que las OC de bolsas se recibían con el remito vacío.
--
-- El papel ahora viaja en el MOVIMIENTO. `Movimientos_Stock` es una tabla COMPARTIDA con
-- Producción Virgilio, así que va como la regla manda: una columna nullable, con prefijo gv_,
-- sin default que reescriba y sin backfill.
--
-- Rollback (una línea, lo viejo sigue funcionando porque la columna es nullable):
--   alter table public."Movimientos_Stock" drop column gv_doc;
--   drop index if exists public.mov_stock_gv_doc_remito_idx;
--   -- y la vista vuelve a su versión anterior (sin remito / factura / doc_tipo / gv_doc)

alter table public."Movimientos_Stock" add column if not exists gv_doc jsonb;

comment on column public."Movimientos_Stock".gv_doc is
 'v30.06 (Luis, 13/10): el PAPEL con el que entro/salio la mercaderia. Hoy lo escribe la recepcion de insumos: {tipo: remito|factura|remito_factura, remito, fecha_remito, factura, fecha_factura, proveedor}. Nullable, sin default, sin backfill (tabla COMPARTIDA con Produccion Virgilio).';

-- se busca por el número del remito, no por el jsonb entero
create index if not exists mov_stock_gv_doc_remito_idx
  on public."Movimientos_Stock" ((gv_doc->>'remito')) where gv_doc is not null;

-- la lectura de recepciones lo expone (columnas AL FINAL: create or replace no deja meterlas en el medio)
create or replace view public.gv_insumo_recepcion_marca as
 SELECT m.id, m.creado, m.cod_art, i.nombre, i.categoria, m.delta, m.unidad, m.ubicacion,
    m.ref AS origen, m.legajo,
    NULLIF(btrim((regexp_match(COALESCE(m.descripcion, ''::text), '· marca ([^·]+)'::text))[1]), ''::text) AS marca,
    m.descripcion,
    m.gv_doc ->> 'remito'::text AS remito,
    m.gv_doc ->> 'factura'::text AS factura,
    m.gv_doc ->> 'tipo'::text AS doc_tipo,
    m.gv_doc
   FROM "Movimientos_Stock" m
     LEFT JOIN "Insumos" i ON i.cod = m.cod_art
  WHERE m.deposito = 'insumos'::text AND m.tipo = 'recepcion_insumo'::text;
-- ⚠ create or replace view BORRA las reloptions: el security_invoker se repone SIEMPRE
alter view public.gv_insumo_recepcion_marca set (security_invoker = true);

-- D1 (Luis): la recepción del remito 38880 es de Cervantes y los dos insumos son Mixto
update public."Movimientos_Stock"
   set ref = 'Cervantes',
       descripcion = regexp_replace(descripcion, ' · remito 38880', '') || ' · marca Mixto',
       gv_doc = jsonb_build_object('tipo','remito','remito','38880','proveedor','Cervantes')
 where client_id in ('rcp-38880-alambre6x275','rcp-38880-varilla205x400');

-- verificación
select cod_art, delta, unidad, origen, marca, remito, doc_tipo
  from public.gv_insumo_recepcion_marca order by id desc limit 3;
