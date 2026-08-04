-- =====================================================================
-- insumos_categoria.sql — categoría + ubicación del catálogo de Insumos (idea 7917).
--
-- Problema: el modal de Recepción/Entrega de Insumos (RI/EI) listaba los 108 códigos
-- PLANOS ordenados por código, y la única forma de llegar a uno era el buscador de
-- texto. Los flejes —la mitad del listado— se llaman por su MEDIDA ("121 X 1,20"),
-- así que el operario tenía que saber de memoria que ese es el código `22`.
--
-- Solución: el catálogo pasa a tener `categoria` (las 6 de la botonera + 'depurar') y
-- `ubicacion` (el rack físico, informativo). La categoría se dedujo de la ubicación que
-- ya estaba cargada en Movimientos_Stock:
--     V01-V16 / R01-R18 (racks de insumos) → fleje
--     AF* / Q34                            → plastico
--     942P-948P                            → inox
-- El resto se asignó a mano (mangos / espirales / cajas) y todo lo que quedó afuera
-- —duplicados del formato viejo `sector·descripción` que el conteo del 31/07 dio de
-- baja— quedó en 'depurar', fuera del listado por defecto.
--
-- ⚠ `sector` NO se puede reusar para la ubicación: en la app, `sector` no nulo significa
--   "insumo SIN código, identificado por sector + descripción" (se dibuja con 📍).
--
-- Aplicado como migración `insumos_categoria_y_ubicacion` (2026-08-04, v7.05).
-- Consumido por index.html: insFetchCatalogo / INS_CATS / insRender / insSetCat.
-- =====================================================================

alter table public."Insumos" add column if not exists categoria text;
alter table public."Insumos" add column if not exists ubicacion text;

comment on column public."Insumos".categoria is
  'Categoría de la botonera de RI/EI: fleje | plastico | inox | mangos | espirales | cajas | depurar (idea 7917)';
comment on column public."Insumos".ubicacion is
  'Ubicación física (rack/sector del depósito de insumos), sólo informativa para el operario';

create index if not exists insumos_categoria_idx on public."Insumos" (categoria);

-- ---------------------------------------------------------------------
-- Backfill. Los 65 operativos, uno por uno (revisable; no un regex que se equivoque
-- en silencio). Los que NO estaban en el catálogo —62 de los 65— se INSERTAN: el modal
-- sólo agregaba los códigos fuera de catálogo cuando su saldo era ≠ 0, así que un fleje
-- que llegaba a 0 DESAPARECÍA de RI/EI y había que re-crearlo para poder recibirlo
-- (`4`, `10` y `25` estaban exactamente así).
-- ---------------------------------------------------------------------
with cat(cod, categoria) as (values
  -- 🧵 fleje y alambre (32) — racks V*/R*, se miden en kg
  ('2','fleje'),('4','fleje'),('5','fleje'),('7','fleje'),('10','fleje'),('13','fleje'),
  ('17','fleje'),('19','fleje'),('20','fleje'),('22','fleje'),('24','fleje'),('25','fleje'),
  ('41','fleje'),('44','fleje'),('45','fleje'),('56','fleje'),('62','fleje'),('63','fleje'),
  ('64','fleje'),('69','fleje'),('72','fleje'),('74','fleje'),('81','fleje'),('92','fleje'),
  ('93','fleje'),('94','fleje'),('1645','fleje'),('2565','fleje'),('2615','fleje'),
  ('2745','fleje'),('46B','fleje'),('90','fleje'),
  -- 🧪 plástico (9) — sector AF*, en Bolsas
  ('PP','plastico'),('ABS','plastico'),('AI','plastico'),('PE','plastico'),('PS','plastico'),
  ('NV','plastico'),('NR','plastico'),('N25','plastico'),('EBA','plastico'),
  -- 🍴 partes inox (11)
  ('942P','inox'),('943P','inox'),('944P','inox'),('945P','inox'),('948P','inox'),
  ('TENEDOR AC. INOX.','inox'),('2955','inox'),('1685','inox'),('2815','inox'),
  ('4626','inox'),('1546903','inox'),
  -- 🪵 mangos (3)
  ('967H','mangos'),('666','mangos'),('4496','mangos'),
  -- 🌀 espirales (2) — en MC
  ('007','espirales'),('2805','espirales'),
  -- 📦 cajas y embalaje (8)
  ('0037','cajas'),('0087','cajas'),('0107','cajas'),('0127','cajas'),('0137','cajas'),
  ('0157','cajas'),('CAJAS·NUMERO 1','cajas'),('FLEJE PROLIPROPILENO·SUNCHOS 12 MM','cajas')
), mov as (
  select cod_art,
    -- la descripción más corta y no-vacía, salteando las que dejó el conteo del 31/07
    (array_agg(descripcion order by length(descripcion), descripcion)
       filter (where coalesce(trim(descripcion),'') <> ''
               and descripcion not ilike 'baja de stock%'
               and descripcion not ilike 'retira entrada%'))[1] as descripcion,
    -- la ubicación MÁS RECIENTE; descarta la basura ('unidad' es una unidad que
    -- alguien cargó en el campo de ubicación, y 942P→"942P" no aporta nada)
    (array_agg(ubicacion order by ts desc)
       filter (where coalesce(trim(ubicacion),'') <> ''
               and ubicacion <> cod_art and lower(ubicacion) <> 'unidad'))[1] as ubicacion
  from public."Movimientos_Stock" where deposito = 'insumos' group by cod_art
)
insert into public."Insumos" (cod, nombre, categoria, ubicacion, creado_por)
select c.cod, m.descripcion, c.categoria, m.ubicacion, 'sistema·7917'
from cat c left join mov m on m.cod_art = c.cod
where not exists (select 1 from public."Insumos" i where i.cod = c.cod);

update public."Insumos" set nombre = 'Tenedor Ac. Inox' where cod = 'TENEDOR AC. INOX.' and nombre is null;
update public."Insumos" set categoria = 'inox'  where cod = '1546903' and categoria is null;
update public."Insumos" set categoria = 'cajas' where cod in ('CAJAS·NUMERO 1','FLEJE PROLIPROPILENO·SUNCHOS 12 MM') and categoria is null;

-- Códigos viejos que sólo existían como movimiento: entran al catálogo YA marcados,
-- para que la app no los muestre "sin categoría". Los dos últimos arrastran saldo real
-- y son doble conteo del mismo fleje (605 = 664 kg, idéntico al fleje 7).
insert into public."Insumos" (cod, nombre, categoria, creado_por) values
  ('505C','Cuchilla china (viejo → 2955)','depurar','sistema·7917'),
  ('CB01','Mariposa mgo plano (viejo → 4626)','depurar','sistema·7917'),
  ('H201','Cabezal (viejo → 2815)','depurar','sistema·7917'),
  ('H201 PART','Espiral TN (viejo → 2805)','depurar','sistema·7917'),
  ('ESPIRAL CHINO','Espiral chino (viejo → 007)','depurar','sistema·7917'),
  ('605','60 x 2.1 (duplicado del fleje 7)','depurar','sistema·7917'),
  ('695','11 x 0.9 (duplicado del fleje 20)','depurar','sistema·7917')
on conflict (cod) do nothing;

-- todo lo que quedó sin categoría es duplicado del formato viejo `sector·descripción`
-- o un código que el conteo del 31/07 dio de baja: fuera de la botonera.
update public."Insumos" set categoria = 'depurar' where categoria is null;

-- control: 108 códigos, 0 sin categoría
-- select categoria, count(*) from public."Insumos" group by categoria order by 2 desc;

-- ---------------------------------------------------------------------
-- ⏳ PENDIENTE (no se hace acá a propósito): netear los 13 saldos NEGATIVOS del
-- depósito 'insumos' (505C·CUCHILLA CHINA −16.000, H201PART·… −14.000, 4600·ALTO
-- IMPACTO −925, PP 2630·POLIPROPILENO −900, etc. — lista completa en
-- docs/INSUMOS-CATEGORIAS.md). Cambia SALDOS DE STOCK: el asiento de ajuste tiene que
-- ir contra el código real y la equivalencia de cada par la confirma el dueño.
-- Mientras tanto quedan en 'depurar', a la vista pero fuera del listado por defecto.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- v7.11 — TAXONOMÍA DEFINITIVA (la fijó el usuario). De 6 categorías a 5:
--   plastico         "Plásticos"           → todos en Bolsas
--   fleje            "Flejes y alambres"   → todos en Kg
--   importados       "Importados"          → ex `inox` + `espirales`; unidad LIBRE
--   partes_plasticas "Partes plásticas"    → ex `mangos`;              unidad LIBRE
--   cajas            "Cajas"               → Paquetes / Uni
-- "Unidad libre" = la categoría NO preselecciona ninguna: el operario tiene que
-- elegir, y sin unidad el movimiento no se manda. Arrancar en "Uni" a ciegas es lo
-- que venía partiendo los saldos.
-- ---------------------------------------------------------------------
update public."Insumos" set categoria = 'importados'       where categoria in ('inox','espirales');
update public."Insumos" set categoria = 'partes_plasticas' where categoria = 'mangos';

-- ⏳ La taxonomía todavía vive en dos lados: acá y en `INS_CATS` (index.html). El
-- módulo para manejarla desde Stock y Compras —junto con el orden de los insumos y
-- la revisión de los `NUEVO·` que dan de alta los operarios— es la idea 5572.

-- ---------------------------------------------------------------------
-- v7.14 (idea 5572) — ver la migración `insumos_identidad_temporal_y_admin`:
--   · Insumos.orden (orden manual dentro de la categoría; NULL = automático)
--   · secuencia insumos_tmp_seq + nuevo_insumo_tmp()  → identidad TMP-NNNN
--   · insumo_identificar() / insumo_editar() / insumo_alta()
-- Todas SECURITY DEFINER con validación adentro: el anon key sigue sin UPDATE
-- directo sobre Insumos ni sobre Movimientos_Stock.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- v7.17 (idea 5572) — ver la migración `insumos_categorias_y_unidades_editables`:
-- las categorías y las unidades dejan de estar hardcodeadas en index.html y pasan a
-- `Insumos_Categorias` (clave, nombre, emoji, unidades[], orden, activa) y
-- `Insumos_Unidades` (nombre, orden, activa), que el admin edita desde
-- Stock y Compras → Insumos. `unidades` de la categoría = las PERMITIDAS:
--   1 sola → unidad fija · varias → el operario elige · vacío → cualquiera activa.
-- ABM por insumo_cat_guardar / insumo_cat_borrar / insumo_unidad_guardar.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- v7.19 (idea 5572) — ver `insumos_identificar_depurar_y_fusion`:
-- `insumo_identificar` acepta también los 'depurar' y, si el código destino YA existe,
-- FUSIONA (mueve los movimientos y borra la fila vieja) → así se netean los negativos.
-- La fusión sólo sale desde 'depurar', nunca desde un TMP-. `insumo_borrar` elimina del
-- catálogo un viejo SIN movimientos. Un insumo en uso no se toca por ninguna de las dos.
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- v7.22 (idea 5572) — ver `insumos_alta_codigo_unico_y_borrar`:
-- `insumo_alta` ya NO usa `on conflict do nothing` (creaba la sensación de haber dado
-- de alta algo que no se creó): falla si el código ya está en uso. `insumo_borrar` saca
-- del catálogo aunque haya movimientos —son historia— pero exige saldo 0; el front lo
-- deja en 0 con un asiento antes de llamarla.
-- ---------------------------------------------------------------------
