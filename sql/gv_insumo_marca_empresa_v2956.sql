-- v29.56 (Luis, 13/10/2026) — auditoría del módulo de operarios: INSUMOS.
--
-- Pedido: *"se pide que se marque la empresa (LK o CH) cuando un operario recibe insumos.
-- esto no debería afectar nada (mismo insumo físicamente, mismo lugar físico) pero debería
-- quedar registro"*.
--
-- Estado medido ANTES: la marca se pedía SÓLO en la categoría «cajas» (v29.31, Thomas D26) y
-- quedaba en la descripción del movimiento (`· marca Loeke`). En fleje, plásticos, partes y
-- procesado no se pedía nada. Los 446 movimientos de insumos tienen `empresa = 'Mixto'` (lo
-- fuerza el trigger gv_insumo_unidad_base, regla v24.89): el insumo NO tiene empresa.
--
-- Qué cambia (front, index.html): el pop-up de cantidad de RECIBIR insumos pide la marca en
-- TODA categoría, obligatoria (el botón «Listo» queda deshabilitado y `insEnviar` frena).
-- Cajas sigue con Loeke/Chef; el resto suma «Mixto» (las dos). La marca NO parte el stock:
-- el movimiento sigue siendo el mismo insumo, el mismo lugar y `empresa = 'Mixto'`; sólo
-- queda escrita en la descripción. Al ENTREGAR no se pide.
--
-- Qué agrega la base: esta vista, para que ese registro sea CONSULTABLE (si el dato sólo vive
-- en un string de la descripción, no se puede agrupar).
--
-- ROLLBACK: drop view if exists public.gv_insumo_recepcion_marca;

create or replace view public.gv_insumo_recepcion_marca as
select m.id, m.creado, m.cod_art,
       i.nombre, i.categoria,
       m.delta, m.unidad, m.ubicacion, m.ref origen, m.legajo,
       nullif(btrim((regexp_match(coalesce(m.descripcion,''), '· marca ([^·]+)'))[1]), '') marca,
       m.descripcion
  from public."Movimientos_Stock" m
  left join public."Insumos" i on i.cod = m.cod_art
 where m.deposito = 'insumos' and m.tipo = 'recepcion_insumo';

alter view public.gv_insumo_recepcion_marca set (security_invoker = true);

comment on view public.gv_insumo_recepcion_marca is
 'v29.56 (Luis, 13/10): de qué empresa vino cada insumo recibido. La marca la pide el modal de Recibir insumos y queda en la descripción; NO parte el stock (el movimiento es empresa Mixto).';

-- Chequeo:
--   select coalesce(marca,'(sin marca)') marca, count(*) n, max(creado)::date ultimo
--     from public.gv_insumo_recepcion_marca group by 1 order by n desc;
-- Al 13/10: 74 recepciones, 0 con marca — la de cajas se exige desde el 09/10 (v29.31) y
-- desde entonces no entró ninguna caja; las de fleje del 13/10 son anteriores a este cambio.


-- ═══════════════════════════════════════════════════════════════════════════════
-- D7/D9 — NORMALIZAR las 18 líneas viejas en MC: ⛔ NO SE APLICA (Luis, 13/10, D9: "dejalo")
-- ═══════════════════════════════════════════════════════════════════════════════
-- El trigger gv_insumo_unidad_base (v24.69) convierte todo a la unidad BASE, pero es
-- BEFORE **INSERT** solamente: las líneas cargadas en MC ANTES de esa versión quedaron
-- así, y la vista vista_saldos_insumos_x_unidad agrupa POR UNIDAD, así que esos códigos
-- muestran dos saldos (Uni positivo + MC negativo). Último movimiento en MC: 2026-08-25.
--
-- ⚠ Un INSERT compensatorio NO sirve: la línea nueva con unidad 'MC' la convierte el
-- trigger y el saldo MC sigue ahí. Hay que reexpresar las filas viejas (UPDATE), que no
-- dispara ese trigger (sí el del saldo y el espejo GP2, que recalculan solos).
--
-- El saldo en unidad base NO CAMBIA: es exactamente lo que ya calcula hoy
-- gv_importados_stock_insumos con el factor (505C 98.000 · 439E 312 · 590E 0).
-- Lo que cambia es que cada código queda con UN solo número.
--
-- ⚠⚠ Queda escrito SOLO como referencia: Luis decidió el 13/10 dejar los saldos como están,
-- porque es cosmético (un solo número por código) y no cambia ninguna cuenta. NO ejecutar sin
-- un «sí» nuevo, y no volver a proponerlo.
--
-- D8 (Luis, 13/10: «dejalo»): las 45 «Cajas» de 546P NO se tocan — esa unidad no tiene
-- factor cargado en Insumos_Factores y no se inventa.

-- 1) BACKUP (protocolo; la clave de Movimientos_Stock es `id`)
-- create table zz_backups."GV_Backup_InsumoMC_20261013" as
--   select m.* from public."Movimientos_Stock" m
--    where m.deposito = 'insumos' and exists (
--      select 1 from public."Insumos_Factores" f
--       where upper(btrim(f.cod_art)) = upper(btrim(m.cod_art))
--         and lower(btrim(f.unidad))  = lower(btrim(m.unidad)) and not f.es_base);
-- alter table zz_backups."GV_Backup_InsumoMC_20261013" enable row level security;

-- 2) la normalización (18 filas: 546P 10 · H201Part 5 · 439E 1 · 505C 1 · 590E 1)
-- with f as (
--   select m.id, fx.factor, (select b.unidad from public."Insumos_Factores" b
--                             where upper(btrim(b.cod_art)) = upper(btrim(m.cod_art))
--                               and b.es_base limit 1) base
--     from public."Movimientos_Stock" m
--     join public."Insumos_Factores" fx
--       on upper(btrim(fx.cod_art)) = upper(btrim(m.cod_art))
--      and lower(btrim(fx.unidad))  = lower(btrim(m.unidad)) and not fx.es_base
--    where m.deposito = 'insumos')
-- update public."Movimientos_Stock" m
--    set delta = m.delta * f.factor,
--        unidad = f.base,
--        descripcion = left(coalesce(m.descripcion,'') || ' · normalizado v29.56: '
--                        || m.delta || ' ' || m.unidad || ' × ' || f.factor, 300)
--   from f where f.id = m.id and f.base is not null;

-- 3) VERIFICACIÓN (tiene que quedar UNA unidad por código y el mismo total convertido)
-- select cod_art, unidad, saldo from public.vista_saldos_insumos_x_unidad
--  where cod_art in ('505C','439E','546P','590E','H201Part') order by 1,2;
-- select cod, stock_uni from public.gv_importados_stock_insumos
--  where cod in ('505C','439E','590E') order by 1;   -- 98000 · 312 · 0, sin cambios

-- ROLLBACK de D7: restaurar delta/unidad/descripcion desde
--   zz_backups."GV_Backup_InsumoMC_20261013" por `id`.


-- ═══════════════════════════════════════════════════════════════════════════════
-- D10 (Luis, 13/10): la SALIDA de insumos NO lleva empresa — "solo el registro de la
-- entrada es importante". Medido sobre las 92 entregas (30/06 al 08/10): 92 de 92 con
-- empresa = 'Mixto' y 0 con marca en la descripción; lo único que queda es a quién se le
-- dio (ref: Cervantes 42 · Rafael 8 · Manolo 3 · Bryan 1, más 33 sin destino del 30/06 al
-- 07/08). El circuito es asimétrico a propósito. NO pedir la marca al entregar.
