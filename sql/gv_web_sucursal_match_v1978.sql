-- v19.78 — Los pedidos web de LK salían "sin expreso" (problema 418)
--
-- SÍNTOMA (Thomas, 18/09): el ABM de la página muestra, debajo de la sucursal "Brc Onelli" de
-- Multi Bazar 4042, "Entrega: Pergamino 2820 | Zona: Soldati" — y el control igual la contaba
-- como "sucursal sin expreso".
--
-- TRES CAUSAS, todas en el feed `v_pedidos_web` del proyecto LK (kwkclwhmoygunqmlegrg):
--
--  (a) El feed lee `direccion_expreso`, VACÍA en 669 de las 1.583 sucursales con `zona_expreso`
--      cargada. Lo que muestra el ABM es `direccion_entrega`, que el feed NUNCA leía. Donde
--      existen las dos, 848 de 914 (92,8 %) tienen la misma calle y altura: o sea, en un pedido
--      con intermediario `direccion_entrega` ES la dirección del expreso. Chef ya lo resolvía
--      así desde la v13.43 (`gv_pedidos_web_np_chef`, `l_intermediario`); LK se quedó sin esa
--      regla. Acá se le copia la MISMA, con la misma lista de provincias.
--
--  (b) El cruce pedido → sucursal era por TEXTO EXACTO del nombre:
--         btrim(lower(d.label)) = btrim(lower(payload->>'sucursal_entrega'))
--      Si no coincide letra por letra vuelven en NULL las tres columnas de expreso *y también*
--      la provincia — que es la que decide Tierra del Fuego → ISIS de Chef (regla v13.77).
--      Medido: 23 pedidos / 19 sucursales distintas en 120 días.
--
--  (c) El cliente se buscaba SÓLO por `cod_cliente` de texto contra `customers`. `orders` ya
--      tiene `customer_id` (uuid) y en 2 pedidos el código del payload apuntaba a un cliente
--      que no existe mientras el uuid estaba bien. Ahora el uuid es el FALLBACK: el código
--      sigue ganando cuando resuelve, así que no cambia ni un pedido de los que ya andaban.
--
-- EL CRUCE NUEVO es una escalera con puntaje, y NUNCA elige entre empatados (salvo en los
-- niveles exactos, donde el empate ya lo desempataba el orden viejo por zona/slot):
--   0 · igual exacto (lo de antes)
--   1 · igual normalizado (sin acentos, sin puntuación, minúsculas) → "David Luque 440-B? General Paz"
--   2 · igual normalizado sacándole el prefijo "<Razón Social> "    → "Multi Bazar S.R.L — Brc Onelli"
--   3 · la LOCALIDAD de la sucursal es el resto del label           → "Poy Ignacio — ROJAS"
--   4 · el cliente tiene UNA sola sucursal cargada                  → "Oriental Party SRL Casa Albert"
-- Los niveles 3 y 4 exigen candidato ÚNICO. "Retira" no entra al nivel 4: no es una sucursal.
--
-- MEDIDO ANTES / DESPUÉS (180 días, 1.072 pedidos):
--   · sucursales del interior sin dirección de expreso ....... 25 → 0   (41 pedidos → 0)
--   · pedidos que recuperan zona/localidad/provincia ......... +15
--   · pedidos que recuperan el cliente ....................... +2
--   · pedidos que CAMBIAN de sucursal teniendo match antes ... 0   <- la prueba de que no rompe
--   · gv_pedidos_web_np_lk(30 días) .......................... 1,14 s -> 1,04 s
--
-- LO QUE **NO** SE TOCA: la columna `direccion` (lo que dice el remito). Chef, cuando no hay
-- intermediario, la pisa con `direccion_entrega`; LK sigue mostrando el label de la sucursal.
-- Cambiar eso movería la dirección de TODOS los pedidos locales y no es lo que se reportó.
--
-- ⚠ Chef NO necesita el cambio: se midió y tiene 0 pedidos sin match en 180 días, y su feed
--   ya usa `direccion_entrega`.
--
-- ROLLBACK: sql/backups/v_pedidos_web_20260918_pre_v1978.sql (la definición anterior completa).
--           Lo nuevo se saca con:
--             drop view public.gv_web_sucursal_sin_match;
--             drop function public.gv_web_norm_lab(text);

-- 1) Normalizador del nombre de sucursal -------------------------------------------------
create or replace function public.gv_web_norm_lab(p text)
returns text language sql stable parallel safe
set search_path to 'public'
as $$
  select nullif(btrim(regexp_replace(lower(public.unaccent(coalesce(p,''))), '[^a-z0-9]+', ' ', 'g')), '')
$$;

comment on function public.gv_web_norm_lab(text) is
 'v19.78: normaliza el nombre de una sucursal para cruzar el label del pedido contra customer_delivery_addresses.label: sin acentos, minusculas, toda puntuacion -> espacio simple. Ver problema 418.';

-- 2) El feed -----------------------------------------------------------------------------
create or replace view public.v_pedidos_web as
 WITH base AS (
         SELECT o.id AS order_id,
            o.created_at,
            o.sheets_payload,
            o.enviado_a_compras_at,
            COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text) AS cod_cliente,
            c.business_name AS razon_social,
            c.cuit,
            COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text) AS sucursal_entrega,
            dir.localidad,
            dir.provincia,
            dir.zona_expreso,
            dir.nombre_expreso,
            dir.direccion_expreso,
            dir.direccion_entrega,
            -- v19.78: MISMA condición que gv_pedidos_web_np_chef (v13.43)
            ( btrim(COALESCE(dir.nombre_expreso, ''::text)) <> ''::text
              OR (dir.provincia IS NOT NULL AND lower(btrim(dir.provincia)) NOT IN
                  ('buenos aires'::text, 'caba'::text, 'capital federal'::text,
                   'ciudad autonoma de buenos aires'::text, 'ciudad autónoma de buenos aires'::text,
                   'ciudad de buenos aires'::text)) ) AS intermediario,
            COALESCE(ov.isis_empresa,
                CASE
                    WHEN COALESCE(dir.provincia, ''::text) ~~* '%tierra del fuego%'::text THEN 'chef'::text
                    ELSE 'lk'::text
                END) AS isis_empresa
           FROM orders o
             -- v19.78 (c): el código manda; el uuid de orders.customer_id es el fallback
             LEFT JOIN customers c0 ON c0.cod_cliente::text = COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text)
             LEFT JOIN customers c1 ON c1.id = o.customer_id
             LEFT JOIN LATERAL ( SELECT COALESCE(c0.id, c1.id) AS id,
                                        COALESCE(c0.business_name, c1.business_name) AS business_name,
                                        COALESCE(c0.cuit, c1.cuit) AS cuit ) c ON true
             LEFT JOIN gv_isis_override ov ON ov.cuit = regexp_replace(COALESCE(c.cuit, ''::text), '\D'::text, ''::text, 'g'::text)
             LEFT JOIN LATERAL ( -- v19.78 (b): el label del pedido, normalizado y sin el prefijo de la razón social
                 SELECT z.raw, z.nrm,
                        CASE WHEN z.nrs IS NOT NULL AND z.nrm LIKE z.nrs || ' %'
                             THEN NULLIF(btrim(substr(z.nrm, length(z.nrs) + 1)), ''::text)
                             ELSE z.nrm END AS sin_rs
                   FROM ( SELECT COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text) AS raw,
                                 public.gv_web_norm_lab(COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text)) AS nrm,
                                 public.gv_web_norm_lab(c.business_name) AS nrs ) z
                 ) lab ON true
             LEFT JOIN LATERAL ( -- v19.78 (b): escalera de match, con candidato ÚNICO en los niveles 3 y 4
                 SELECT y.localidad, y.provincia, y.zona_expreso, y.nombre_expreso,
                        y.direccion_expreso, y.direccion_entrega
                   FROM ( SELECT x.*, min(x.sc) OVER () AS sc_min, count(*) OVER (PARTITION BY x.sc) AS n_sc
                            FROM ( SELECT d.localidad, d.provincia, d.zona_expreso, d.nombre_expreso,
                                          d.direccion_expreso, d.direccion_entrega, d.slot,
                                          CASE
                                            WHEN btrim(lower(d.label)) = btrim(lower(lab.raw)) THEN 0
                                            WHEN public.gv_web_norm_lab(d.label) = lab.nrm THEN 1
                                            WHEN lab.sin_rs IS NOT NULL AND public.gv_web_norm_lab(d.label) = lab.sin_rs THEN 2
                                            WHEN lab.sin_rs IS NOT NULL AND public.gv_web_norm_lab(d.localidad) = lab.sin_rs THEN 3
                                            WHEN lab.nrm IS NOT NULL AND lab.nrm !~ '^retira'::text AND count(*) OVER () = 1 THEN 4
                                            ELSE 9
                                          END AS sc
                                     FROM customer_delivery_addresses d
                                    WHERE d.customer_id = c.id ) x ) y
                  WHERE y.sc = y.sc_min AND y.sc < 9 AND (y.sc <= 2 OR y.n_sc = 1)
                  ORDER BY y.sc, (btrim(COALESCE(y.zona_expreso, ''::text)) <> ''::text) DESC, y.slot
                 LIMIT 1) dir ON true
          WHERE o.sheets_payload IS NOT NULL AND jsonb_typeof(o.sheets_payload -> 'items'::text) = 'array'::text
        )
 SELECT 'lk'::text AS empresa,
    b.order_id,
    it.ord::integer AS linea_rn,
    b.cod_cliente,
    b.razon_social,
    (b.created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'::text)::date AS fecha_pedido,
    to_char((b.created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'::text), 'HH24:MI:SS'::text) AS hora_pedido,
    b.created_at,
    b.sucursal_entrega,
    b.sheets_payload ->> 'vend'::text AS vend,
    COALESCE(b.sheets_payload ->> 'condicion_pago_code'::text, b.sheets_payload ->> 'condicionPagoCode'::text) AS condicion_pago_code,
    COALESCE(b.sheets_payload ->> 'numOC'::text, b.sheets_payload ->> 'numero_oc'::text, b.sheets_payload ->> 'numeroOC'::text) AS numero_oc,
    b.sheets_payload ->> 'observaciones'::text AS observaciones,
    (
        CASE
            WHEN char_length((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]) < 3 THEN lpad((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1], 3, '0'::text)
            ELSE (regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]
        END || COALESCE((regexp_match(it.value ->> 'cod_art'::text, '[a-zA-Z]+'::text))[1], ''::text)) ||
        CASE
            WHEN b.isis_empresa = 'chef'::text AND (
            CASE
                WHEN char_length((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]) < 3 THEN lpad((regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1], 3, '0'::text)
                ELSE (regexp_match(it.value ->> 'cod_art'::text, '\d+'::text))[1]
            END || COALESCE((regexp_match(it.value ->> 'cod_art'::text, '[a-zA-Z]+'::text))[1], ''::text)) !~* 'L$'::text THEN 'L'::text
            ELSE ''::text
        END AS art,
    NULLIF(COALESCE(it.value ->> 'cajas'::text, it.value ->> 'Cajas'::text), ''::text)::numeric AS cajas,
    NULLIF(it.value ->> 'uxb'::text, ''::text)::numeric AS uxb,
    COALESCE(NULLIF(it.value ->> 'cajas'::text, ''::text), '0'::text)::numeric * COALESCE(NULLIF(it.value ->> 'uxb'::text, ''::text), '0'::text)::numeric AS uni,
    b.enviado_a_compras_at,
    b.localidad,
    b.provincia,
    NULLIF(btrim(b.zona_expreso), ''::text) AS zona_expreso,
    NULLIF(btrim(b.nombre_expreso), ''::text) AS nombre_expreso,
    -- v19.78 (a): con intermediario y sin `direccion_expreso` cargada, la dirección del expreso
    -- es la que el ABM guarda en `direccion_entrega`. Sin intermediario, sigue NULL.
    CASE WHEN b.intermediario
         THEN COALESCE(NULLIF(btrim(b.direccion_expreso), ''::text), NULLIF(btrim(b.direccion_entrega), ''::text))
         ELSE NULLIF(btrim(b.direccion_expreso), ''::text)
    END AS direccion_expreso,
    b.isis_empresa,
        CASE
            WHEN b.isis_empresa = 'chef'::text THEN ( SELECT p.cod_cliente
               FROM chef_padron p
              WHERE NULLIF(regexp_replace(COALESCE(p.cuit, ''::text), '\D'::text, ''::text, 'g'::text), ''::text) IS NOT NULL AND regexp_replace(COALESCE(p.cuit, ''::text), '\D'::text, ''::text, 'g'::text) = regexp_replace(COALESCE(b.cuit, ''::text), '\D'::text, ''::text, 'g'::text)
              ORDER BY p.cod_cliente
             LIMIT 1)
            ELSE b.cod_cliente
        END AS cod_isis
   FROM base b
     CROSS JOIN LATERAL jsonb_array_elements(b.sheets_payload -> 'items'::text) WITH ORDINALITY it(value, ord)
  WHERE (it.value ->> 'cod_art'::text) ~ '\d'::text;

alter view public.v_pedidos_web set (security_invoker = true);

-- 3) El centinela ------------------------------------------------------------------------
-- Un camino que falla en silencio es el que nos costó esto: el pedido salía sin expreso y
-- nadie se enteraba. Esta vista dice, pedido por pedido, cuál NO se pudo cruzar y por qué.
create or replace view public.gv_web_sucursal_sin_match as
with l as (
  select o.id as order_id,
         (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
         coalesce(o.sheets_payload->>'cod_cliente', o.sheets_payload->>'codCliente') as cod_cliente,
         c.id as cid, c.business_name as razon_social,
         z.raw, z.nrm,
         case when z.nrs is not null and z.nrm like z.nrs || ' %'
              then nullif(btrim(substr(z.nrm, length(z.nrs)+1)),'') else z.nrm end as sin_rs
    from public.orders o
    left join public.customers c0 on c0.cod_cliente::text = coalesce(o.sheets_payload->>'cod_cliente', o.sheets_payload->>'codCliente')
    left join public.customers c1 on c1.id = o.customer_id
    cross join lateral (select coalesce(c0.id, c1.id) as id,
                               coalesce(c0.business_name, c1.business_name) as business_name) c
    cross join lateral (
      select coalesce(o.sheets_payload->>'sucursal_entrega', o.sheets_payload->>'sucursalEntrega') as raw,
             public.gv_web_norm_lab(coalesce(o.sheets_payload->>'sucursal_entrega', o.sheets_payload->>'sucursalEntrega')) as nrm,
             public.gv_web_norm_lab(c.business_name) as nrs) z
   where o.sheets_payload is not null and jsonb_typeof(o.sheets_payload->'items') = 'array'
)
select l.order_id, l.fecha, l.cod_cliente, l.razon_social, l.raw as sucursal_del_pedido,
       case when l.cid is null then 'el codigo de cliente no esta en customers'
            else 'el nombre de la sucursal no coincide con ninguna del ABM' end as motivo,
       (select string_agg(d.label, ' | ' order by d.slot)
          from public.customer_delivery_addresses d where d.customer_id = l.cid) as sucursales_del_abm
  from l
 where coalesce(btrim(l.raw),'') <> ''
   and l.nrm !~ '^retira'
   and coalesce((select min(case
             when btrim(lower(d.label)) = btrim(lower(l.raw)) then 0
             when public.gv_web_norm_lab(d.label) = l.nrm then 1
             when l.sin_rs is not null and public.gv_web_norm_lab(d.label) = l.sin_rs then 2
             when l.sin_rs is not null and public.gv_web_norm_lab(d.localidad) = l.sin_rs then 3
             when (select count(*) from public.customer_delivery_addresses d2 where d2.customer_id = l.cid) = 1 then 4
             else 9 end)
        from public.customer_delivery_addresses d where d.customer_id = l.cid), 9) >= 9;

alter view public.gv_web_sucursal_sin_match set (security_invoker = true);
-- `v_pedidos_web` no la lee `anon` (sólo `authenticated`): el centinela va igual de cerrado.
revoke select on public.gv_web_sucursal_sin_match from anon;

comment on view public.gv_web_sucursal_sin_match is
 'v19.78 (problema 418): pedidos web de LK cuya sucursal de entrega NO se puede cruzar contra el ABM. Cada fila = un pedido que sale SIN expreso, SIN localidad y SIN provincia (o sea, tampoco se le puede aplicar la regla de Tierra del Fuego). Vacia = todo bien.';

-- Chequeo:
--   select motivo, count(*) from public.gv_web_sucursal_sin_match group by 1;
-- Al 18/09 quedan 15, todas de pedidos ya entregados:
--   · 9 "el nombre de la sucursal no coincide" (el último es del 07/08) — se arreglan en el
--     ABM, renombrando la sucursal como la nombró el pedido, o no se arreglan: son históricos.
--   · 6 "el codigo de cliente no esta en customers" (4317, 4312, 4302, 4299, 4292, 4286):
--     pedidos con `cliente_nuevo`, cuyo código todavía no tiene ficha en `customers`.
