-- ============================================================================
-- PPP Shadow Generator  ·  Flujo nuevo de pedidos (Fase 0-bis — modo sombra)
-- ============================================================================
-- QUÉ ES: reconstruye, desde los pedidos web, las NP que ISIS produciría, y las
--         COMPARA contra las que ISIS produjo de verdad. NO alimenta producción.
--         NO escribe nada. Es 100% de solo-lectura.
--
-- OBJETIVO: medir cuánto empata nuestro armado propio contra el de ISIS antes de
--           siquiera pensar en cortar. Mientras esto no de ~100% por semanas,
--           NO se toca la operación (ver docs/PLAN-PEDIDO-DIRECTO-3717.md, §7.1).
--
-- ⚠ ESTO CORRE EN EL PROYECTO **LK** (kwkclwhmoygunqmlegrg), NO EN VIRGILIO.
--   Es la decisión (B) que tomó el dueño el 2026-09-03. El motivo: la partición
--   depende del ORDEN de las líneas, ese orden vive en orders.sheets_payload, y
--   Virgilio NO lo ve — lo único que cruza es lk_pedidos_match.items_string, que
--   viene ordenada por código y por lo tanto ya perdió el orden original.
--   Verificado sobre el pedido 888: el carrito real arranca 512,511,584E,543…
--   y el items_string que llega a Virgilio arranca 057,246,280,315…
--
--   La alternativa (A) era mandarle a Virgilio los ítems en orden como columna
--   nueva. Se descartó: LK ya tiene TODO lo necesario del lado de acá, así que
--   (B) no obliga a tocar la sync que hoy corre en producción para una prueba.
--   Si algún día Virgilio tiene que partir pedidos por su cuenta, ahí sí hay que
--   hacer (A) — pero eso es la fase de implementación, no la de verificación.
--
-- FUENTES (todas ya en el proyecto LK):
--   - orders.sheets_payload  : el pedido web de Loekemeyer, CON el orden del carrito.
--   - chef_orders            : ídem Chef, por el FDW chef_db (ver nota de costo abajo).
--   - ppp_base_pedidos       : espejo de la base de ítems de ISIS. Trae `id`, y ese
--                              id CONSERVA el orden real de cada NP — es la pieza
--                              que hace posible comparar contenido. Verificado:
--                              la NP 97956 sale de acá como 512,511,584E,543,…,
--                              idéntica al payload.
--   - ppp_programacion       : espejo de la PPP real (NP, cod, m3, fecha).
--
-- ----------------------------------------------------------------------------
-- REGLA DE SPLIT (corregida el 2026-09-03; antes decía otra cosa y era falsa)
-- ----------------------------------------------------------------------------
--   Un pedido se parte en bloques con un tope de LÍNEAS por NP: 18 en Loekemeyer
--   y 15 en Chef. Pedido chico (<= tope) = 1 NP.
--
--   EL ORDEN DEL CORTE ES EL DEL PAYLOAD (el orden del carrito), NO el de código
--   de artículo. La Edge Function `procesar-pedidos-db`, que arma el Excel de las
--   12:30, no ordena nada: recorre las filas como vienen e ISIS numera los bloques
--   que recibe. Por eso acá se usa `with ordinality` y NO hay ningún ORDER BY por
--   artículo: reordenar es exactamente el bug que este archivo tenía.
--
-- ----------------------------------------------------------------------------
-- ⚠ ANTES DE LEER CUALQUIER RESULTADO: EL ESPEJO DE LA PPP ESTÁ VIEJO
-- ----------------------------------------------------------------------------
--   `sincronizar_ppp()` viene fallando desde el 2026-08-13 (21 corridas caídas al
--   momento de escribir esto). Medido el 2026-09-03:
--       ppp_base_pedidos en LK  → NP máxima 98392
--       PPP_Base_Pedidos en Virgilio → NP máxima 98684
--   O sea que el espejo está ~292 NP atrasado. Consecuencia directa sobre estas
--   vistas: los pedidos recientes NO tienen contra qué compararse y salen como
--   'sin_isis'. En la medición del 2026-09-03 el empate de contenido por semana
--   dio así:
--       15/06 100% · 22/06 86% · 29/06 97% · 06/07 100% · 13/07 86% · 20/07 84%
--       27/07 84% · 03/08 82% · 10/08 44% · 17/08 8% · 24/08 4% · 31/08 6%
--   El derrumbe de agosto NO es la lógica: es el espejo que dejó de actualizarse.
--   ARREGLAR EL CRON ANTES DE SACAR CONCLUSIONES. Con el espejo sano, la línea de
--   base real a superar es ese 82-100%.
--
-- LO QUE ESTA VERSIÓN **NO** MIDE: m3. LK no tiene `Volumen_Articulos` (el m3 por
--   caja) y `products` sólo trae `uxb`. El chequeo de m3 ya se había validado
--   aparte al 98,5% sobre 158 NP, y no es lo que estaba en duda: lo que estaba sin
--   probar era el CONTENIDO de cada NP, que es lo que estas vistas sí miden. Si se
--   quisiera el m3 acá, hay que espejar `Volumen_Articulos` (2.543 filas, chica).
--
-- PENDIENTE (bordes a cerrar en sombra antes de confiar):
--   1. Split por SUCURSAL de entrega: hoy no lo aplica. ~9% de cliente-día tienen
--      más de un pedido; hay que decidir si ISIS los junta o los separa.
--   2. "SIM-30999..." y direcciones mezcladas cliente/expreso (limpieza de dato).
--   3. Definir exactamente qué cuenta como "línea".
-- ============================================================================


-- 1) Ítems del pedido web, EN EL ORDEN DEL PAYLOAD.
--    `with ordinality` es la pieza clave: da la posición de cada ítem dentro del
--    array tal como vino. El código se normaliza con el mismo criterio que
--    padCodArt de la Edge Function (3 dígitos + letras) para poder comparar
--    contra ppp_base_pedidos.
create or replace view public.v_shadow_web_items as
select
  o.id                                                     as order_id,
  'lk'::text                                               as empresa,
  18                                                       as cap_lineas,
  coalesce(o.sheets_payload->>'cod_cliente',
           o.sheets_payload->>'codCliente')                as cod,
  (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
  lpad((regexp_match(it.value->>'cod_art', '\d+'))[1], 3, '0')
    || coalesce((regexp_match(it.value->>'cod_art', '[a-zA-Z]+'))[1], '')  as art,
  nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric    as cajas,
  it.ord                                                   as linea_rn   -- ORDEN DEL CARRITO
from public.orders o,
     lateral jsonb_array_elements(o.sheets_payload->'items') with ordinality as it(value, ord)
where o.sheets_payload is not null
  and jsonb_typeof(o.sheets_payload->'items') = 'array'
  and (it.value->>'cod_art') ~ '\d';


-- 1-bis) Lo mismo para CHEF. Va en una vista APARTE a propósito: chef_orders es
--        una tabla foránea (FDW chef_db) y leerla cuesta segundos. Separada, la
--        vista de Loekemeyer —que es el 86% del volumen— no paga ese costo.
--        El payload de Chef mezcla camelCase y snake_case en las claves de
--        cabecera, de ahí los coalesce.
create or replace view public.v_shadow_web_items_chef as
select
  o.id                                                     as order_id,
  'chef'::text                                             as empresa,
  15                                                       as cap_lineas,
  coalesce(o.sheets_payload->>'cod_cliente',
           o.sheets_payload->>'codCliente')                as cod,
  (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
  lpad((regexp_match(it.value->>'cod_art', '\d+'))[1], 3, '0')
    || coalesce((regexp_match(it.value->>'cod_art', '[a-zA-Z]+'))[1], '')  as art,
  nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric    as cajas,
  it.ord                                                   as linea_rn
from public.chef_orders o,
     lateral jsonb_array_elements(o.sheets_payload->'items') with ordinality as it(value, ord)
where o.sheets_payload is not null
  and jsonb_typeof(o.sheets_payload->'items') = 'array'
  and (it.value->>'cod_art') ~ '\d';


-- 2) NP propuestas: cada pedido se parte en bloques de `cap_lineas` líneas
--    CONTIGUAS en el orden del payload. `arts` sale EN ORDEN y es la firma que
--    después se compara contra ISIS.
create or replace view public.v_shadow_np_gen as
select
  i.order_id,
  i.empresa,
  i.cod,
  i.fecha,
  ceil(i.linea_rn::numeric / i.cap_lineas)      as np_idx,
  count(*)                                      as lineas,
  sum(i.cajas)                                  as cajas,
  string_agg(i.art, ',' order by i.linea_rn)    as arts
from public.v_shadow_web_items i
group by i.order_id, i.empresa, i.cod, i.fecha,
         ceil(i.linea_rn::numeric / i.cap_lineas);


-- 3) La NP real de ISIS, con sus artículos EN EL ORDEN REAL (por `id`).
create or replace view public.v_shadow_np_isis as
select
  b.pedido                                      as np,
  count(*)                                      as lineas,
  sum(b.cajas)                                  as cajas,
  string_agg(b.articulo, ',' order by b.id)     as arts
from public.ppp_base_pedidos b
group by b.pedido;


-- 4) LA COMPARACIÓN QUE IMPORTA: contenido, bloque por bloque.
--    Se matchea por FIRMA (la secuencia ordenada de artículos), no por un vínculo
--    pedido→NP: si el bloque que generamos existe tal cual como NP en ISIS, la
--    partición es correcta. Es más fuerte que contar NP o cajas, que son
--    independientes del orden y por eso daban 'ok' aun con la regla equivocada.
create or replace view public.v_shadow_ppp_compare as
select
  g.order_id,
  g.empresa,
  g.cod,
  g.fecha,
  g.np_idx,
  g.lineas,
  g.cajas,
  i.np                                          as np_isis,
  case
    when i.np is not null                then 'ok_contenido'   -- mismo bloque, mismo orden
    when exists (select 1 from public.v_shadow_np_isis x
                  where x.arts like '%' || split_part(g.arts, ',', 1) || '%')
                                         then 'difiere'        -- ISIS tiene el art, en otro reparto
    else 'sin_isis'                                            -- no hay NP para comparar
  end                                           as estado,
  g.arts                                        as arts_gen,
  i.arts                                        as arts_isis
from public.v_shadow_np_gen g
left join public.v_shadow_np_isis i on i.arts = g.arts;


-- ----------------------------------------------------------------------------
-- Consultas de control (correr a mano)
-- ----------------------------------------------------------------------------
--
--   -- (0) PRIMERO: ¿el espejo está al día? Si el máximo de acá va muy por detrás
--   --     del de Virgilio, todo lo de abajo miente. Ver la nota de arriba.
--   select max(pedido::bigint) from public.ppp_base_pedidos where pedido ~ '^\d+$';
--
--   -- (1) Empate de CONTENIDO por semana (la métrica que vale):
--   select date_trunc('week', fecha)::date as semana,
--          count(*)                                          as bloques,
--          count(*) filter (where estado = 'ok_contenido')    as ok,
--          round(100.0 * count(*) filter (where estado = 'ok_contenido')
--                / nullif(count(*), 0), 1)                    as pct
--   from public.v_shadow_ppp_compare
--   group by 1 order by 1;
--
--   -- (2) Los que NO empatan, para mirarlos de a uno:
--   select order_id, np_idx, lineas, arts_gen, arts_isis
--   from public.v_shadow_ppp_compare
--   where estado = 'difiere' order by fecha desc limit 50;
--
--   -- (3) Chef (paga el FDW, correr sola y con paciencia):
--   select count(*) from public.v_shadow_web_items_chef;
-- ----------------------------------------------------------------------------
