-- =====================================================================
--  `vista_nc_loeke_chef` deja de leer la tabla `Planimetria` — v17.77 (2026-09-14)
--
--  Primer paso real para poder retirar `Planimetria`. **NO alcanza para retirarla:**
--  quedan dos lectores más, y uno de ellos no se puede tocar todavía (ver el final).
--
-- ─────────────────────────────────────────────────────────────────────
--  EL BARRIDO: quién dependía DE VERDAD de `Planimetria`
-- ─────────────────────────────────────────────────────────────────────
--  La tarea 3284 de Planify decía "migrar `vista_nc_loeke_chef`". Barriendo en serio
--  (vistas por `pg_depend` transitivo, funciones por `prosrc`, triggers, FK en los dos
--  sentidos, policies propias y ajenas, crons, constraints, publicaciones, grants, y
--  `grep` sobre el repo) aparecieron **cuatro** lectores, no uno — y cinco falsos positivos:
--
--  | Quién | Qué pasa |
--  |---|---|
--  | `vista_nc_loeke_chef` | se migra acá |
--  | `gv_codigos_multigrafia` | **todavía no** (ver abajo) |
--  | `loadPlanimetriaRemote()` de `index.html` | fallback vivo — se saca en esta misma v17.77 |
--  | `pmapViejaFetch()` de `index.html` | **NO se puede sacar**: es el rescate del problema 156 |
--  | `racks_plani_mover`, `racks_plani_ingreso`, `racks_plani_ingreso_nacional`, `racks_plani_descontar`, `registrar_baja_racks` | **FALSOS POSITIVOS** |
--
--  ⚠ Las cinco funciones de racks usan **`Racks_Planimetria`**, que es OTRA tabla. Un
--  `prosrc ~ 'Planimetria'` las matchea porque `Racks_Planimetria` contiene la palabra.
--  Medido contando ocurrencias: las cinco tienen `veces_racks = veces_total`, o sea
--  **cero** menciones de `Planimetria` sola. La única función que sí la toca es
--  `planimetria_autoorden()`, que es el trigger de la propia tabla (`trg_planimetria_autoorden`),
--  o sea su maquinaria interna, no un consumidor: se va con ella.
--
-- ─────────────────────────────────────────────────────────────────────
--  QUÉ HACÍA ACÁ `Planimetria`, Y POR QUÉ EL DESTINO **NO** ES `GV_Lugar_Item`
-- ─────────────────────────────────────────────────────────────────────
--  El CTE `split` no preguntaba *dónde está* un artículo: preguntaba **si es DUAL**.
--  Buscaba códigos que en la tabla vieja aparecían con sufijo ` LK` **y** con ` CH`,
--  porque ahí la empresa viajaba pegada al código.
--
--  El modelo nuevo no guarda el sufijo: `GV_Lugar_Item.cod` está canonizado por
--  `trg_canon_gv_lugar_item_cod` (v17.51) y la empresa vive en `GV_Lugar.empresa`
--  (**0 filas** de `GV_Lugar_Item` tienen sufijo ` LK`/` CH`). Reproducir `split` sobre
--  el mapa obliga a agrupar por código y exigir que la celda exista en las dos empresas
--  — y **eso da un resultado distinto**:
--
--  | Fuente | Códigos duales que devuelve |
--  |---|---|
--  | `Planimetria` (lo que usaba) | **4** — 437E, 438E, 439E, 809E |
--  | `GV_Lugar` + `GV_Lugar_Item` | **5** — agrega **396** ← falso positivo |
--  | **`codigos_duales`** | **4** — 437E, 438E, 439E, 809E ← **idéntico** |
--
--  El `396` no es dual: está en A65 por Loeke y en una celda de Chef, y el mapa no
--  distingue eso de un artículo que se vende por las dos. Meterlo acá habría agregado
--  notas de crédito de un artículo que no corresponde — y esta vista es plata.
--
--  Así que el destino correcto es **`codigos_duales`**, que es exactamente el padrón de
--  duales y lo que la pregunta pedía desde el principio. La vista ya lo asumía sin
--  decirlo: su propio `WHERE` trata aparte a `437E, 438E, 439E` con una condición fija.
--
-- ─────────────────────────────────────────────────────────────────────
--  MEDICIÓN (antes y después, misma base, misma transacción)
-- ─────────────────────────────────────────────────────────────────────
--    `split` vieja vs nueva ....... 4 = 4 códigos, los mismos, 0 de diferencia
--    filas de la vista ............ 2 antes · 2 después
--    md5 del contenido ordenado ... **idéntico**
--
--  Se conservan `security_invoker = true` y los grants (los trae el `CREATE OR REPLACE`,
--  que no cambia la lista de columnas).
--
-- ─────────────────────────────────────────────────────────────────────
--  ⚠ POR QUÉ `Planimetria` TODAVÍA NO SE PUEDE RETIRAR
-- ─────────────────────────────────────────────────────────────────────
--  (1) **`pmapViejaFetch()`** — el panel "lo que quedó en la planimetría vieja" del 🗺️ Mapa
--      de góndolas lee la tabla para listar los **16 códigos que viven SÓLO ahí** y dejar
--      traerlos de a uno con un click (`pmapViejaTraer`). **Es el único camino de rescate
--      del problema 156**: si se saca ese panel, esos 16 quedan enterrados en una tabla que
--      no lee nadie. Sale recién cuando el depósito diga qué hacer con cada uno.
--  (2) **`gv_codigos_multigrafia`** — el centinela barre 16 tablas buscando códigos con
--      varias grafías, y `Planimetria` es **la que más aporta: 16 de las 30 filas**
--      (27/027, 31/031, 66/066 — el mismo `66` que duplicó el picking de D72C).
--      Sacar ese bloque mientras la tabla **siga existiendo y `anon` siga teniendo
--      INSERT/UPDATE sobre ella** es perder vigilancia sobre una tabla viva. Se saca
--      **junto con** el retiro de la tabla, no antes. (`GV_Lugar_Item` ya está en la lista
--      del centinela y hoy reporta 0: lo cubre su trigger de canonización desde la v17.51.)
--
--  Orden que queda, entonces: resolver los 16 del problema 156 → sacar `pmapVieja*` del
--  front → sacar el bloque de `gv_codigos_multigrafia` → recién ahí retirar `Planimetria`
--  (con su trigger `trg_planimetria_autoorden` y su función `planimetria_autoorden()`).
--
--  Rollback: volver el CTE `split` a la versión de `Planimetria`; está en el historial de
--  git y en `pg_get_viewdef` de antes de este commit. La única diferencia es ese CTE.
-- =====================================================================

create or replace view public.vista_nc_loeke_chef with (security_invoker = true) as
 WITH chef_imp AS (
         SELECT DISTINCT ltrim(upper(btrim("Importados".cod_art)), '0'::text) AS base
           FROM "Importados"
          WHERE "Importados".activo AND (btrim("Importados".proveedor) = ANY (ARRAY['Ownland'::text, 'Kangli'::text, 'Fujian'::text, 'Frontier'::text]))
        ), split AS (
         -- v17.77 — ANTES: códigos que en la tabla `Planimetria` aparecían con ' LK' Y con
         -- ' CH'. Eso no era una pregunta de ubicación sino de IDENTIDAD: "¿este código es
         -- dual?". `codigos_duales` es el padrón de eso y devuelve exactamente los mismos 4
         -- (437E, 438E, 439E, 809E). Reproducirlo sobre GV_Lugar/GV_Lugar_Item daba 5:
         -- agregaba el 396, que está en celdas de las dos empresas sin ser dual.
         SELECT DISTINCT ltrim(upper(btrim(codigos_duales.cod)), '0'::text) AS base
           FROM codigos_duales
          WHERE COALESCE(btrim(codigos_duales.cod), ''::text) <> ''::text
        ), home_chef AS (
         SELECT ltrim(upper(btrim("Equivalencias_Codigos".cod_pedido)), '0'::text) AS base
           FROM "Equivalencias_Codigos"
          WHERE upper(btrim("Equivalencias_Codigos".cod_real)) ~~ '% CH'::text AND upper(btrim("Equivalencias_Codigos".cod_pedido)) !~~ '%L'::text
        UNION
         SELECT ltrim(upper(btrim(x.cod)), '0'::text) AS ltrim
           FROM "GV_NC_Loeke_Chef_Excluidos" x
        ), candidatos AS (
         SELECT s.base
           FROM split s
             JOIN chef_imp c ON c.base = s.base
          WHERE NOT (s.base IN ( SELECT home_chef.base
                   FROM home_chef))
        ), base_rows AS (
         SELECT btrim(b.pedido) AS np,
            k.base AS cod,
            ( SELECT i.descripcion
                   FROM "Importados" i
                  WHERE ltrim(upper(btrim(i.cod_art)), '0'::text) = k.base AND i.descripcion IS NOT NULL
                 LIMIT 1) AS descripcion,
            sum(COALESCE(b.cajas, 0::numeric)) AS cajas,
            max(btrim(b.cliente)) AS cliente_base
           FROM "GV_PPP_Base_Pedidos" b
             JOIN candidatos k ON k.base = ltrim(upper(regexp_replace(upper(btrim(b.articulo)), '([0-9E])L$'::text, '\1'::text)), '0'::text)
          WHERE b.pedido ~ '^[0-9]+$'::text AND b.pedido::bigint < 90000 AND (NOT (k.base = ANY (ARRAY['437E'::text, '438E'::text, '439E'::text])) OR upper(btrim(b.articulo)) ~ 'L$'::text) AND NOT (EXISTS ( SELECT 1
                   FROM "NC_Loeke_Chef_Hechas" h
                  WHERE btrim(h.np) = btrim(b.pedido) AND ltrim(upper(btrim(h.cod)), '0'::text) = k.base))
          GROUP BY (btrim(b.pedido)), k.base
         HAVING sum(COALESCE(b.cajas, 0::numeric)) > 0::numeric
        )
 SELECT np,
    cod,
    descripcion,
    cajas,
    COALESCE(( SELECT NULLIF(btrim(pr.razon_social), ''::text) AS "nullif"
           FROM gv_ppp_prog_rs pr
          WHERE regexp_replace(pr.np, '\.0+$'::text, ''::text) = r.np
         LIMIT 1), ( SELECT NULLIF(btrim(fn.razon_social), ''::text) AS "nullif"
           FROM "Facturacion_NP" fn
          WHERE regexp_replace(fn.np, '\.0+$'::text, ''::text) = r.np
         LIMIT 1), NULLIF(cliente_base, ''::text)) AS razon_social
   FROM base_rows r;
