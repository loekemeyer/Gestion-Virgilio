-- ============================================================================
-- PPP Shadow Generator  ·  Flujo nuevo de pedidos (Fase 0-bis — modo sombra)
-- ============================================================================
-- QUÉ ES: genera la PPP (NPs armadas + m3) DIRECTO desde los pedidos web, para
--         COMPARARla contra la PPP real que hoy produce ISIS. NO alimenta
--         producción. NO escribe nada. Es 100% de solo-lectura.
--
-- OBJETIVO: medir cuánto empata nuestro armado propio contra el de ISIS antes de
--           siquiera pensar en cortar. Mientras esto no de ~100% por semanas,
--           NO se toca la operación (ver docs/PLAN-PEDIDO-DIRECTO-3717.md, §7.1).
--
-- ESTADO: NO deployado a Supabase. Los .sql de este repo se corren a mano en el
--         editor; este todavía no. Y OJO: tal como está AHORA no corre entero,
--         a propósito — v_shadow_web_items depende de un dato que Virgilio
--         todavía no tiene (ver "TODO BLOQUEANTE"). Abajo queda la variante
--         vieja comentada, que sí corre y sirve SOLO para contar.
--
-- FUENTES (todas ya en el proyecto Virgilio, hrxfctzncixxqmpfhskv):
--   - lk_pedidos_match  : el pedido web (cod, fecha, sucursal, items_string).
--   - Volumen_Articulos : m3 por caja de cada artículo.
--   - PPP_Programacion_Diaria + PPP_Base_Pedidos : la PPP real de ISIS (para comparar).
--
-- ----------------------------------------------------------------------------
-- REGLA DE SPLIT (corregida el 2026-09-03; antes decía otra cosa y era falsa)
-- ----------------------------------------------------------------------------
--   Un pedido se parte en bloques con un tope de LÍNEAS por NP: 18 en Loekemeyer
--   y 15 en Chef. Pedido chico (<= tope) = 1 NP.
--
--   EL ORDEN DEL CORTE ES EL DEL PAYLOAD (el orden del carrito), NO el de código
--   de artículo. La Edge Function `procesar-pedidos-db`, que arma el Excel de las
--   12:30, NO ORDENA NADA: recorre sheets_payload.items tal como viene y corta
--   mientras no cambie (N° Pedido, Sucursal de Entrega). ISIS numera los bloques
--   que recibe. Probado sobre los únicos casos que distinguen las dos reglas —los
--   pedidos cuyo payload NO viene ya ordenado por código—: LK orders.id=888
--   (41 ítems → 1-18 / 19-36 / 37-41 DEL PAYLOAD) y Chef chef_orders.id=165
--   (28 ítems → 1-15 / 16-28).
--
--   Este archivo decía "en orden de código de artículo" y numeraba con
--   row_number() over (order by art). Estaba mal por partida doble: por la regla,
--   y porque se alimentaba de items_string.
--
-- ----------------------------------------------------------------------------
-- POR QUÉ items_string NO SIRVE PARA ESTO (la parte que hay que entender)
-- ----------------------------------------------------------------------------
--   lk_pedidos_match.items_string se arma en LK, en la vista v_pedidos_match, YA
--   ORDENADO POR CÓDIGO y con las cajas sumadas por código repetido ('026x1,
--   027x1,…,404Ex3'). Es exactamente lo que esa vista necesita —una firma estable
--   del pedido para matchearlo—, pero como efecto colateral DESTRUYE el orden en
--   que las líneas viajaron al Excel.
--
--   O sea: partir items_string en bloques de 18 no reproduce la partición de ISIS
--   salvo en los pedidos que ya venían ordenados por código (el 95%, que es
--   justamente por qué el error pasó desapercibido tanto tiempo). Sobre el
--   histórico, 145 de 801 NP de PPP_Base_Pedidos (18,1%) NO están en orden de
--   código: ahí items_string da otro reparto.
--
--   CONSECUENCIA: alimentado de items_string, este generador puede comparar
--   CUÁNTAS NP y CUÁNTAS CAJAS (las dos cosas son independientes del orden), y
--   NUNCA QUÉ ARTÍCULO CAE EN CADA NP. La comparación de contenido —que es la
--   que el plan necesita antes del piloto— exige el payload crudo.
--
-- ----------------------------------------------------------------------------
-- ⚠ TODO BLOQUEANTE (decisión que no se toma acá)
-- ----------------------------------------------------------------------------
--   El payload vive en LK (orders.sheets_payload) y Virgilio HOY NO LO VE: lo
--   único que cruza es lk_pedidos_match, que no lleva los ítems en orden. Para
--   que v_shadow_web_items (abajo) corra hace falta UNA de estas dos cosas, y las
--   dos son decisión del dueño del plan, no de este archivo:
--
--     (A) Agregar los ítems EN ORDEN como columna jsonb a v_pedidos_match +
--         lk_pedidos_match, con la misma sync de 15 min que ya existe
--         (sql/pedidos_match_virgilio.sql en el repo de LK). Es el mismo tipo de
--         cambio que la columna condicion_pago_code que espera la decisión D11.
--         La columna asumida acá se llama items_json y es
--         jsonb = [{"cod_art": "...", "cajas": n, "uxb": n}, ...] en el orden del
--         payload. Nombre y forma a confirmar al implementarlo.
--
--     (B) Desplegar la parte de v_shadow_web_items DEL LADO DE LK, donde
--         orders.sheets_payload está a mano, y espejar sólo el resultado chico
--         (order_id, ordinal, art, cajas) a Virgilio. Mismo patrón que ppp_etapa.
--
--   Mientras no exista ninguna de las dos, se puede desplegar la VARIANTE
--   SOLO-CANTIDAD del final del archivo, dejando bien dicho en el tablero que el
--   'ok' que devuelve NO valida contenido.
--
-- VALIDACIÓN AL ESCRIBIR (2026-09-02, read-only sobre datos reales, con la
--   variante vieja, o sea SOLO cantidad):
--     - Mismo número de NPs generadas : 89/89  (100%)
--     - Mismas cajas totales          : 86/89  (97%)
--     - m3 dentro del 5%              : validado aparte al 98,5% (158 NPs)
--   Ninguna de las tres mide el contenido de cada NP.
--
-- PENDIENTE (bordes a cerrar en sombra antes de confiar):
--   1. Contenido tramo a tramo contra PPP_Base_Pedidos ORDENADA POR id (que es
--      lo que conserva el orden real de ISIS). Bloqueado por el TODO de arriba.
--   2. Split por SUCURSAL de entrega: hoy no lo aplica. ~9% de cliente-día
--      tienen más de un pedido; hay que decidir si ISIS los junta o los separa.
--   3. "SIM-30999..." y direcciones mezcladas cliente/expreso (limpieza de dato).
--   4. Definir exactamente qué cuenta como "línea".
-- ============================================================================


-- 1) Pedidos web parseados a ítems (art, cajas), EN EL ORDEN DEL PAYLOAD.
--    'with ordinality' es la pieza clave: da la posición de cada ítem dentro del
--    array TAL COMO VINO. No hay ningún ORDER BY sobre el artículo, y no lo tiene
--    que haber: reordenar acá es el bug que este archivo tenía.
--    ⚠ NO CORRE hasta que exista lk_pedidos_match.items_json (ver TODO arriba).
create or replace view public.v_shadow_web_items as
select
  m.order_id,
  m.cod_cliente                                    as cod,
  m.fecha_pedido                                   as fecha,
  m.empresa,
  case when m.empresa = 'chef' then 15 else 18 end as cap_lineas,
  -- el payload de Chef viene en camelCase en las claves de cabecera; las de ítem
  -- son snake en las dos, pero el coalesce no cuesta nada y evita un hueco mudo.
  coalesce(it.value->>'cod_art', it.value->>'codArt')          as art,
  nullif(coalesce(it.value->>'cajas', it.value->>'Cajas'), '')::numeric as cajas,
  it.ord                                           as linea_rn   -- ORDEN DEL CARRITO
from public.lk_pedidos_match m,
     lateral jsonb_array_elements(m.items_json) with ordinality as it(value, ord)
where jsonb_typeof(m.items_json) = 'array'
  and jsonb_array_length(m.items_json) > 0;


-- 2) NPs propuestas: cada pedido se parte en chunks de 'cap_lineas' líneas
--    CONTIGUAS en el orden del payload.
--    Número de NP propio = order_id + índice de chunk (interno; a ISIS no le importa).
create or replace view public.v_shadow_np_gen as
select
  i.cod,
  i.fecha,
  i.empresa,
  i.order_id,
  ceil(i.linea_rn::numeric / i.cap_lineas)              as np_idx,
  (i.order_id::text || '-' || ceil(i.linea_rn::numeric / i.cap_lineas)::text) as np_shadow,
  count(*)                                              as lineas,
  sum(i.cajas)                                          as cajas,
  round(sum(i.cajas * coalesce(v.m3, 0)), 3)            as m3,
  bool_or(v.codigo is null or v.m3 is null)             as tiene_art_sin_volumen,
  -- los códigos del bloque, EN ORDEN: es lo que hace falta para comparar
  -- contenido contra PPP_Base_Pedidos ordenada por id (pendiente 1).
  string_agg(i.art, ',' order by i.linea_rn)            as arts
from public.v_shadow_web_items i
left join public."Volumen_Articulos" v on v.codigo = i.art
group by i.cod, i.fecha, i.empresa, i.order_id,
         ceil(i.linea_rn::numeric / i.cap_lineas);


-- 3) Comparación por cliente-día: lo que generaríamos nosotros vs la PPP de ISIS.
--    'estado' = ok cuando coincide número de NPs y cajas.
--    ⚠ ESTO NO VALIDA CONTENIDO. El número de tramos y el total de cajas son
--      INDEPENDIENTES del orden en que se parte, así que un 'ok' acá es condición
--      necesaria y NO suficiente (plan §7.1, riesgo 30). La comparación de
--      contenido va contra PPP_Base_Pedidos ordenada por id y es el pendiente 1.
create or replace view public.v_shadow_ppp_compare as
with nuestro as (
  select cod, fecha,
         count(*)         as nps_gen,
         sum(cajas)       as cajas_gen,
         round(sum(m3),2) as m3_gen,
         bool_or(tiene_art_sin_volumen) as falta_volumen
  from public.v_shadow_np_gen
  group by cod, fecha
),
np_m3 as (  -- m3 real de ISIS: uno por NP
  select np, cod, max(m3) as m3
  from public."PPP_Programacion_Diaria"
  where np ~ '^9'
  group by np, cod
),
np_fecha as (  -- fecha y cajas de cada NP real, desde la base de ítems
  select pedido as np, min(fecha::date) as fecha, sum(cajas) as cajas
  from public."PPP_Base_Pedidos"
  group by pedido
),
isis as (
  select m.cod, f.fecha,
         count(*)         as nps_isis,
         sum(f.cajas)     as cajas_isis,
         round(sum(m.m3),2) as m3_isis
  from np_m3 m
  join np_fecha f on f.np = m.np
  group by m.cod, f.fecha
)
select
  coalesce(n.cod, i.cod)                              as cod,
  coalesce(n.fecha, i.fecha)                          as fecha,
  n.nps_gen,   i.nps_isis,
  n.cajas_gen, i.cajas_isis,
  n.m3_gen,    i.m3_isis,
  n.falta_volumen,
  case
    when n.cod is null then 'solo_isis'        -- ISIS tiene NP y no hay pedido web (canal no-web)
    when i.cod is null then 'solo_web'         -- hay pedido web y ISIS todavía no lo armó
    when n.nps_gen = i.nps_isis
     and abs(coalesce(n.cajas_gen,0) - coalesce(i.cajas_isis,0)) <= 0.01 then 'ok_cantidad'
    when n.nps_gen = i.nps_isis then 'ok_nps_dif_cajas'
    else 'revisar'
  end                                                 as estado
from nuestro n
full outer join isis i on i.cod = n.cod and i.fecha = n.fecha;


-- ----------------------------------------------------------------------------
-- VARIANTE SOLO-CANTIDAD (desplegable HOY, sin el TODO bloqueante)
-- ----------------------------------------------------------------------------
-- Es la vista original, la que se alimenta de items_string. Sirve para el tablero
-- de "cuántas NP y cuántas cajas" y NADA MÁS: el row_number va por código porque
-- items_string ya viene ordenado por código, así que el reparto de artículos entre
-- bloques NO es el de ISIS. Descomentar SOLO si se asume eso, y no llamar 'ok' a
-- su resultado (por eso el estado de arriba se llama 'ok_cantidad').
--
-- create or replace view public.v_shadow_web_items as
-- select
--   m.order_id,
--   m.cod_cliente                                    as cod,
--   m.fecha_pedido                                   as fecha,
--   m.empresa,
--   case when m.empresa = 'chef' then 15 else 18 end as cap_lineas,
--   split_part(btrim(t.tok), 'x', 1)                 as art,
--   nullif(split_part(btrim(t.tok), 'x', 2), '')::numeric as cajas,
--   row_number() over (
--     partition by m.order_id
--     order by split_part(btrim(t.tok), 'x', 1)      -- ⚠ NO es el orden real
--   )                                                as linea_rn
-- from public.lk_pedidos_match m,
--      lateral regexp_split_to_table(m.items_string, ',') as t(tok)
-- where nullif(btrim(m.items_string), '') is not null
--   and btrim(t.tok) ~ '^[^x]+x[0-9]';


-- ----------------------------------------------------------------------------
-- Consultas de control (correr a mano):
--
--   -- Tablero de empate en CANTIDAD (no en contenido):
--   select estado, count(*) from public.v_shadow_ppp_compare group by estado order by 2 desc;
--
--   -- Los casos a mirar de cerca:
--   select * from public.v_shadow_ppp_compare where estado = 'revisar' order by fecha desc;
--
--   -- Contenido tramo a tramo (pendiente 1): lo generado contra el orden REAL de
--   -- ISIS. Requiere v_shadow_web_items alimentada del payload (TODO bloqueante).
--   -- with isis as (
--   --   select pedido as np,
--   --          string_agg(articulo, ',' order by id) as arts
--   --   from public."PPP_Base_Pedidos" group by pedido)
--   -- select g.order_id, g.np_idx, g.arts as arts_gen, i.arts as arts_isis
--   -- from public.v_shadow_np_gen g join isis i on ...  -- el vínculo order_id → np
--   --                                                   -- sale de lk_pedidos_match
--   -- where g.arts is distinct from i.arts;
-- ----------------------------------------------------------------------------
