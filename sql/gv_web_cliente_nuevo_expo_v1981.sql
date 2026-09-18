-- v19.81 — Los pedidos de CLIENTE NUEVO salían sin cliente, sin zona y sin expreso (problema 425)
--
-- Thomas, 18/09, despues de la v19.78: *"¿pero el pedido de esos clientes sin ficha en customers
-- no entró desde la página?"* y *"si vinieron de la página tenemos los datos del cliente, ¿no?"*
--
-- Las dos veces tenia razon, y la segunda es la que arregla esto.
--
-- LO QUE SE MIDIO
--
--  · Los 6 pedidos entraron por la pagina: `orders.auth_user_id` cargado, con el login por CUIT
--    (`<cuit>@cuit.loekemeyer`). Cinco los hizo el usuario de **Loekemeyer SRL (cod 1)** — o sea
--    un vendedor cargando por el cliente— con un `cod_cliente` distinto en cada pedido.
--  · Ese codigo NO esta en `customers` ni `orders.customer_id`, asi que `v_pedidos_web` no tenia
--    contra que cruzar: el pedido salia sin razon social, sin localidad, sin provincia, sin zona
--    y sin expreso. Y como la provincia es la que decide Tierra del Fuego -> ISIS de Chef
--    (regla v13.77), esa regla tampoco se le podia aplicar.
--  · **Pero el dato estaba**: el alta de cliente nuevo lo guarda en `expo_clientes_pendientes`
--    (14 filas), con razon social, CUIT, localidad, provincia y un `direcciones_entrega` jsonb
--    cuyo `titulo` es EXACTAMENTE el `sucursal_entrega` que viaja en el pedido, y que ademas
--    trae el `expreso` por sucursal (CONSACO VIARA -> "logistica md").
--  · Solo 3 de esas 14 llegaron a `customers`, y `estado='cargado_erp'` no garantiza nada:
--    4284, 4290 y 4301 estan en `cargado_erp` y NO estan en `customers`.
--
-- EL CAMBIO: `expo_clientes_pendientes` como TERCERA fuente del cliente, detras de las dos que
-- ya estaban (cod_cliente -> customers, y desde la v19.78 orders.customer_id). Solo entra cuando
-- las dos fallan (`c.id is null`), asi que la ficha real siempre gana y no cambia ni un pedido
-- de los que ya andaban. La sucursal se cruza dentro del jsonb con la MISMA escalera de la
-- v19.78, sobre `titulo` (y `localidad` en el nivel 3).
--
-- ⚠ DE ESA FUENTE **NO** SE TOMA UNA DIRECCION DE EXPRESO. El `direccion` del jsonb es el
--   domicilio DEL CLIENTE, no el del expreso. Tomarlo como `direccion_expreso` mandaria el
--   camion a Aguilares (Tucuman) en vez de al deposito del expreso en Capital — exactamente el
--   error que la v19.78 vino a arreglar del otro lado. Se toman localidad, provincia y el
--   NOMBRE del expreso, nada mas.
--
-- MEDIDO ANTES / DESPUES (1.072 pedidos):
--   · pedidos de cliente nuevo que recuperan cliente/localidad/provincia ...... 4 de 6
--   · pedidos que recuperan localidad (total, v19.78 + v19.81) ................ +19
--   · pedidos que recuperan razon social ..................................... +6
--   · regresiones (zona / localidad / razon social) ........................... 0
--   · filas de v_pedidos_web / _np / _dif ..................... 17.782 / 1.570 / 17.782 (iguales)
--   · gv_pedidos_web_np_lk(30 dias) .......................... 1,04 s -> 1,40 s
--
-- LOS 2 QUE NO SE PUDIERON:
--   · 4317 (15/09, "Arribeños 2979 - Nuñez") — no tiene fila en `expo_clientes_pendientes`; la
--     ultima fila de esa tabla es del 22/08, asi que esa alta no paso por ahi.
--   · 4299 (20/08, "Montevideo 2123 - Berizo") — el alta figura con el codigo **4298**
--     (Alejandro Javier De La Casa), con esa misma direccion. El pedido dice 4299. Uno de los
--     dos numeros esta mal y lo tiene que decidir una persona: NO se adivina.
--
-- ROLLBACK: sql/backups/v_pedidos_web_20260918_pre_v1978.sql vuelve al feed anterior a las dos
--           versiones. Para volver solo esta, sacar el join a `expo_clientes_pendientes`, el
--           lateral `dirx` y los COALESCE que los usan (marcados "v19.81").

-- El feed, con las tres fuentes de cliente ------------------------------------------------
create or replace view public.v_pedidos_web as
 WITH base AS (
         SELECT o.id AS order_id,
            o.created_at,
            o.sheets_payload,
            o.enviado_a_compras_at,
            COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text) AS cod_cliente,
            COALESCE(c.business_name, ep.business_name) AS razon_social,          -- v19.81
            COALESCE(c.cuit, ep.cuit) AS cuit,                                    -- v19.81
            COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text) AS sucursal_entrega,
            COALESCE(dir.localidad, dirx.localidad) AS localidad,                 -- v19.81
            COALESCE(dir.provincia, dirx.provincia) AS provincia,                 -- v19.81
            dir.zona_expreso,
            COALESCE(dir.nombre_expreso, dirx.expreso) AS nombre_expreso,         -- v19.81
            dir.direccion_expreso,
            dir.direccion_entrega,
            ( btrim(COALESCE(COALESCE(dir.nombre_expreso, dirx.expreso), ''::text)) <> ''::text
              OR (COALESCE(dir.provincia, dirx.provincia) IS NOT NULL AND lower(btrim(COALESCE(dir.provincia, dirx.provincia))) NOT IN
                  ('buenos aires'::text, 'caba'::text, 'capital federal'::text,
                   'ciudad autonoma de buenos aires'::text, 'ciudad autónoma de buenos aires'::text,
                   'ciudad de buenos aires'::text)) ) AS intermediario,
            COALESCE(ov.isis_empresa,
                CASE
                    WHEN COALESCE(COALESCE(dir.provincia, dirx.provincia), ''::text) ~~* '%tierra del fuego%'::text THEN 'chef'::text
                    ELSE 'lk'::text
                END) AS isis_empresa
           FROM orders o
             LEFT JOIN customers c0 ON c0.cod_cliente::text = COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text)
             LEFT JOIN customers c1 ON c1.id = o.customer_id
             LEFT JOIN LATERAL ( SELECT COALESCE(c0.id, c1.id) AS id,
                                        COALESCE(c0.business_name, c1.business_name) AS business_name,
                                        COALESCE(c0.cuit, c1.cuit) AS cuit ) c ON true
             -- v19.81: tercera fuente, solo si las dos anteriores fallaron
             LEFT JOIN expo_clientes_pendientes ep
                    ON c.id IS NULL
                   AND ep.cod_cliente::text = COALESCE(o.sheets_payload ->> 'cod_cliente'::text, o.sheets_payload ->> 'codCliente'::text)
             LEFT JOIN gv_isis_override ov ON ov.cuit = regexp_replace(COALESCE(COALESCE(c.cuit, ep.cuit), ''::text), '\D'::text, ''::text, 'g'::text)
             LEFT JOIN LATERAL (
                 SELECT z.raw, z.nrm,
                        CASE WHEN z.nrs IS NOT NULL AND z.nrm LIKE z.nrs || ' %'
                             THEN NULLIF(btrim(substr(z.nrm, length(z.nrs) + 1)), ''::text)
                             ELSE z.nrm END AS sin_rs
                   FROM ( SELECT COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text) AS raw,
                                 public.gv_web_norm_lab(COALESCE(o.sheets_payload ->> 'sucursal_entrega'::text, o.sheets_payload ->> 'sucursalEntrega'::text)) AS nrm,
                                 public.gv_web_norm_lab(COALESCE(c.business_name, ep.business_name)) AS nrs ) z
                 ) lab ON true
             LEFT JOIN LATERAL (
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
             -- v19.81: la misma escalera, pero adentro del jsonb del alta de cliente nuevo
             LEFT JOIN LATERAL (
                 SELECT y.localidad, y.provincia, y.expreso
                   FROM ( SELECT x.*, min(x.sc) OVER () AS sc_min, count(*) OVER (PARTITION BY x.sc) AS n_sc
                            FROM ( SELECT e.value ->> 'localidad'::text AS localidad,
                                          e.value ->> 'provincia'::text AS provincia,
                                          NULLIF(btrim(e.value ->> 'expreso'::text), ''::text) AS expreso,
                                          e.ord,
                                          CASE
                                            WHEN btrim(lower(e.value ->> 'titulo'::text)) = btrim(lower(lab.raw)) THEN 0
                                            WHEN public.gv_web_norm_lab(e.value ->> 'titulo'::text) = lab.nrm THEN 1
                                            WHEN lab.sin_rs IS NOT NULL AND public.gv_web_norm_lab(e.value ->> 'titulo'::text) = lab.sin_rs THEN 2
                                            WHEN lab.sin_rs IS NOT NULL AND public.gv_web_norm_lab(e.value ->> 'localidad'::text) = lab.sin_rs THEN 3
                                            WHEN lab.nrm IS NOT NULL AND lab.nrm !~ '^retira'::text AND count(*) OVER () = 1 THEN 4
                                            ELSE 9
                                          END AS sc
                                     FROM jsonb_array_elements(COALESCE(ep.direcciones_entrega, '[]'::jsonb)) WITH ORDINALITY e(value, ord) ) x ) y
                  WHERE y.sc = y.sc_min AND y.sc < 9 AND (y.sc <= 2 OR y.n_sc = 1)
                  ORDER BY y.sc, y.ord
                 LIMIT 1) dirx ON true
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

-- El centinela, ahora mirando las DOS fuentes -------------------------------------------
-- ⚠ Se recrea con DROP porque `create or replace view` no deja renombrar una columna
--   (`sucursales_del_abm` -> `sucursales_cargadas`). Verificado antes: 0 vistas dependientes
--   y 0 funciones que la nombren.
drop view if exists public.gv_web_sucursal_sin_match;
create view public.gv_web_sucursal_sin_match as
with l as (
  select o.id as order_id,
         (o.created_at at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
         coalesce(o.sheets_payload->>'cod_cliente', o.sheets_payload->>'codCliente') as cod_cliente,
         c.id as cid, ep.cod_cliente as ep_cod, ep.direcciones_entrega as ep_dirs,
         coalesce(c.business_name, ep.business_name) as razon_social,
         z.raw, z.nrm,
         case when z.nrs is not null and z.nrm like z.nrs || ' %'
              then nullif(btrim(substr(z.nrm, length(z.nrs)+1)),'') else z.nrm end as sin_rs
    from public.orders o
    left join public.customers c0 on c0.cod_cliente::text = coalesce(o.sheets_payload->>'cod_cliente', o.sheets_payload->>'codCliente')
    left join public.customers c1 on c1.id = o.customer_id
    cross join lateral (select coalesce(c0.id, c1.id) as id,
                               coalesce(c0.business_name, c1.business_name) as business_name) c
    left join public.expo_clientes_pendientes ep
           on c.id is null and ep.cod_cliente::text = coalesce(o.sheets_payload->>'cod_cliente', o.sheets_payload->>'codCliente')
    cross join lateral (
      select coalesce(o.sheets_payload->>'sucursal_entrega', o.sheets_payload->>'sucursalEntrega') as raw,
             public.gv_web_norm_lab(coalesce(o.sheets_payload->>'sucursal_entrega', o.sheets_payload->>'sucursalEntrega')) as nrm,
             public.gv_web_norm_lab(coalesce(c.business_name, ep.business_name)) as nrs) z
   where o.sheets_payload is not null and jsonb_typeof(o.sheets_payload->'items') = 'array'
),
sc as (
  select l.*,
    coalesce((select min(case
        when btrim(lower(d.label)) = btrim(lower(l.raw)) then 0
        when public.gv_web_norm_lab(d.label) = l.nrm then 1
        when l.sin_rs is not null and public.gv_web_norm_lab(d.label) = l.sin_rs then 2
        when l.sin_rs is not null and public.gv_web_norm_lab(d.localidad) = l.sin_rs then 3
        when (select count(*) from public.customer_delivery_addresses d2 where d2.customer_id = l.cid) = 1 then 4
        else 9 end)
      from public.customer_delivery_addresses d where d.customer_id = l.cid), 9) as sc_abm,
    coalesce((select min(case
        when btrim(lower(e.value->>'titulo')) = btrim(lower(l.raw)) then 0
        when public.gv_web_norm_lab(e.value->>'titulo') = l.nrm then 1
        when l.sin_rs is not null and public.gv_web_norm_lab(e.value->>'titulo') = l.sin_rs then 2
        when l.sin_rs is not null and public.gv_web_norm_lab(e.value->>'localidad') = l.sin_rs then 3
        when jsonb_array_length(coalesce(l.ep_dirs,'[]'::jsonb)) = 1 then 4
        else 9 end)
      from jsonb_array_elements(coalesce(l.ep_dirs,'[]'::jsonb)) e), 9) as sc_expo
    from l
)
select sc.order_id, sc.fecha, sc.cod_cliente, sc.razon_social, sc.raw as sucursal_del_pedido,
       case when sc.cid is null and sc.ep_cod is null
              then 'el codigo de cliente no esta ni en customers ni en el alta de cliente nuevo'
            else 'el nombre de la sucursal no coincide con ninguna cargada' end as motivo,
       coalesce((select string_agg(d.label, ' | ' order by d.slot)
                   from public.customer_delivery_addresses d where d.customer_id = sc.cid),
                (select string_agg(e.value->>'titulo', ' | ')
                   from jsonb_array_elements(coalesce(sc.ep_dirs,'[]'::jsonb)) e)) as sucursales_cargadas
  from sc
 where coalesce(btrim(sc.raw),'') <> ''
   and sc.nrm !~ '^retira'
   and least(sc.sc_abm, sc.sc_expo) >= 9;

alter view public.gv_web_sucursal_sin_match set (security_invoker = true);
revoke select on public.gv_web_sucursal_sin_match from anon;

comment on view public.gv_web_sucursal_sin_match is
 'v19.81 (problemas 418 y 425): pedidos web de LK cuya sucursal de entrega NO se puede cruzar, ni contra el ABM (customers + customer_delivery_addresses) ni contra el alta de cliente nuevo (expo_clientes_pendientes). Cada fila = un pedido que sale sin expreso, sin localidad y sin provincia, o sea que tampoco se le puede aplicar la regla de Tierra del Fuego. Vacia = todo bien.';

-- Chequeo:
--   select motivo, count(*) from public.gv_web_sucursal_sin_match group by 1;
-- Al 18/09 quedan 11: 9 de nombre que no coincide (la ultima del 07/08) y 2 sin ficha en
-- ninguna de las dos fuentes (4317 y 4299, los dos descritos arriba).
--
-- Y este otro, que ahora dice algo que antes estaba tapado:
--   select order_id, cod_cliente, localidad, provincia from public.v_pedidos_web
--    where provincia is not null and lower(btrim(provincia)) not in ('buenos aires','caba')
--      and direccion_expreso is null;
-- Da 1: el pedido 1233 de Jesus Salvador Rojas (4292), Aguilares (Tucuman). Ahora se sabe que
-- es del interior y que NADIE le cargo expreso en el alta — antes ni siquiera se sabia la
-- provincia. Eso lo decide una persona, no el feed.
