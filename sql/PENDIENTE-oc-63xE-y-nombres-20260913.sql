-- ============================================================================
-- PENDIENTE DE EJECUTAR — espera el "dale" de Thomas. NADA de esto se corrió.
-- v16.72 · 2026-09-13 · generador de OC: los 63xE sin configurar, 15 códigos sin nombre y
-- la capacidad duplicada de M34/M35/M36.
--
-- QUÉ LEE CADA TABLA QUE SE TOCA:
--   OC_Maximos          → `vista_generador_oc` (CTE cfg: proveedor, índice, activo, descripción, máximo)
--                         y el editor ⚙ de configuración del generador (`ocCfgSave`, index.html).
--                         PK (cod, linea). Ningún trigger.
--   vista_generador_oc  → el Generador de OC (`SUPABASE_GENERADOR_ENDPOINT`, index.html ~13505) y la
--                         vista `vista_faltante_catalogo` (dependiente de 2º nivel, ver abajo).
--   Capacidad_Sector    → NO se toca en este archivo: el bloque (c) es una PROPUESTA con números.
--
-- Medido el 13/09 (todo con SELECT, nada escrito):
--   · 630/631/634/635/636 tienen fila en OC_Maximos (CH, 'Carlos E', uni_x_caja 12, max 9/6/1.5/6/6).
--     630E/631E/634E/635E/636E NO tienen fila → salen "(sin proveedor)", descripción NULL, máximo 0.
--   · Los E existen en Capacidad_Sector (M34 630E 12 · M34 631E 12 · M35 634E 12 · M35 635E 5 · M36 636E 5)
--     y en Articulos_Cajas (CH, N_Caja 12, Uni_x_Caja 12/24/24/24/24). En Articulos_Cajas los SIN E
--     (630..636) están `Suspendido = true` y los E no: el E parece ser el código vigente.
--   · 'Log/ Fabr' existe en Talleristas_Contacto con es_proveedor_oc = true.
--   · vista_generador_oc.descripcion = COALESCE(OC_Maximos.descripcion, vista_saldos_stock.descripcion):
--     15 códigos salen NULL: 231, 232, 233, 441Z, 501B, 587C, 592E, 599EZ, 630E, 631E, 634E, 635E,
--     636E, 657, LIBRE. Nueve tienen nombre en Articulos_Cajas (231/232/233 Palo Amasar 30/40/50cm,
--     657 CUCHARON NYLON VERDE 1P, los cinco 63xE). Sin nombre en ningún lado: 441Z, 501B, 587C, 592E,
--     599EZ (tampoco en GV_UxB). LIBRE no es artículo: es la celda vacía de Capacidad_Sector (54 filas,
--     53 con cajas_max NULL; A83 tiene 72 y por eso entra al universo del generador).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- (0) BACKUP (RLS + sin escritura para anon, protocolo de CLAUDE.md)
-- ---------------------------------------------------------------------------
create table zz_backups."GV_Backup_oc_maximos_63xE_20260913" as
  select * from public."OC_Maximos" where upper(btrim(cod)) in ('630','631','634','635','636','630E','631E','634E','635E','636E');
alter table zz_backups."GV_Backup_oc_maximos_63xE_20260913" enable row level security;
revoke insert, update, delete, truncate on zz_backups."GV_Backup_oc_maximos_63xE_20260913" from anon, authenticated;
-- (la definición VIGENTE de vista_generador_oc está más abajo, en el bloque ROLLBACK)

-- ---------------------------------------------------------------------------
-- (a) los 5 INSERT en OC_Maximos para 630E..636E
--     Columnas NOT NULL de OC_Maximos: cod, linea, max_cajas (default 0), activo (default true),
--     actualizado (default now()), indice (default 1.5), llenar_gondola (default false).
--     descripcion = la del código SIN E en Articulos_Cajas (pedido de Thomas).
--     uni_x_caja: se copia el de la fila sin E (12), que es también lo que dice GV_UxB para 630E.
--     ⚠ Articulos_Cajas dice 24 para 631E/634E/635E/636E y GV_UxB también 24 (origen "absorbido del
--       fallback") — patrón master×2 de §3.dk. Se deja 12 como en las filas sin E y se marca la duda:
--       el generador NO usa OC_Maximos.uni_x_caja para el cálculo (usa vista_uni_x_caja), así que
--       este número no mueve ninguna OC; sólo se muestra en el editor ⚙.
-- ---------------------------------------------------------------------------
insert into public."OC_Maximos" (cod, descripcion, linea, max_cajas, proveedor, uni_x_caja, activo, indice, prop_prov1, llenar_gondola)
values
  ('630E', 'Cucharon ac inox c/mgo Ch',  'CH', 0, 'Log/ Fabr', 12, true, 1.5, 100, false),
  ('631E', 'Espumadera ac inox c/Mgo',   'CH', 0, 'Log/ Fabr', 12, true, 1.5, 100, false),
  ('634E', 'Cuchara calada ac inox c/m', 'CH', 0, 'Log/ Fabr', 12, true, 1.5, 100, false),
  ('635E', 'Espatula lisa ac inox c/m',  'CH', 0, 'Log/ Fabr', 12, true, 1.5, 100, false),
  ('636E', 'Espatula de ac inox c/mgo',  'CH', 0, 'Log/ Fabr', 12, true, 1.5, 100, false)
on conflict (cod, linea) do nothing;          -- espera 5 filas

-- verificación
select cod, linea, descripcion, proveedor, max_cajas, uni_x_caja, activo, indice, prop_prov1
  from public."OC_Maximos" where upper(btrim(cod)) in ('630E','631E','634E','635E','636E') order by cod;

-- ---------------------------------------------------------------------------
-- (b) vista_generador_oc: Articulos_Cajas como 4ª fuente de nombre (OC_Maximos → vista_saldos_stock →
--     GV_UxB → Articulos_Cajas) y 'LIBRE' fuera del universo.
--
--     CREATE COMPLETO (pg_get_viewdef del 13/09 + el cambio), security_invoker = true como lo tenía.
--     Mismas columnas, mismo orden y tipos → CREATE OR REPLACE conserva el OID, los grants y los
--     dependientes; NO hace falta DROP CASCADE. Igual se corrió el barrido TRANSITIVO de CLAUDE.md:
--
--       with recursive dep as (
--         select c.oid, c.relname, c.relkind, 1 lvl from pg_class c where c.oid = 'public.vista_generador_oc'::regclass
--         union
--         select c.oid, c.relname, c.relkind, dep.lvl + 1
--           from dep join pg_depend d on d.refobjid = dep.oid join pg_rewrite r on r.oid = d.objid
--           join pg_class c on c.oid = r.ev_class and c.oid <> dep.oid)
--       select lvl, relkind, relname from dep where lvl > 1 order by lvl, relname;
--       → lvl 2 · v · vista_faltante_catalogo   (única dependiente; lee cod, tiene_prov_real, proveedor,
--                                                 pr2, proveedor2, activo — ninguna cambia)
--
--     Grants vigentes (se conservan solos con CREATE OR REPLACE): anon/authenticated/service_role
--     tienen TODO (insert/update/delete/truncate/references/trigger además de select) — sobre una vista
--     no-updatable no sirven de nada, pero se dejan iguales porque el pedido es "grants iguales".
--
--     Medido con el SELECT equivalente antes de escribir: recuperan nombre 231, 232, 233, 657, 630E,
--     631E, 634E, 635E, 636E (9); siguen NULL 441Z, 501B, 587C, 592E, 599EZ (5, sin nombre en ningún
--     lado); LIBRE desaparece del universo (A83 72 cajas ya no cuenta como artículo).
-- ---------------------------------------------------------------------------
create or replace view public.vista_generador_oc
with (security_invoker = true) as
 WITH fam AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim("Equivalencias_Familia".cod_secundario)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS sec,
                regexp_replace(regexp_replace(regexp_replace(upper(btrim("Equivalencias_Familia".cod_principal)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS ppal
           FROM "Equivalencias_Familia"
        ), stk_raw AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim(vista_saldos_stock.cod_art)), '^0+(?=.)'::text, ''::text), ' +(LK|CH)$'::text, ''::text), '·.*$'::text, ''::text) AS codn,
                sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.separar_pedidos, 0::numeric) + COALESCE(vista_saldos_stock.a_facturar, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS stock,
                sum(COALESCE(vista_saldos_stock.terminado, 0::numeric) + COALESCE(vista_saldos_stock.a_guardar, 0::numeric) + COALESCE(vista_saldos_stock.racks, 0::numeric) + COALESCE(vista_saldos_stock.excedente, 0::numeric) + COALESCE(vista_saldos_stock.para_envasar, 0::numeric) + COALESCE(vista_saldos_stock.racks_ch, 0::numeric)) AS fin_dep,
                max(vista_saldos_stock.descripcion) AS descripcion
           FROM vista_saldos_stock
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(vista_saldos_stock.cod_art)), '^0+(?=.)'::text, ''::text), ' +(LK|CH)$'::text, ''::text), '·.*$'::text, ''::text))
        ), stk AS (
         SELECT COALESCE(f.ppal, sr.codn) AS codn,
                sum(sr.stock) AS stock,
                sum(sr.fin_dep) AS fin_dep,
                max(sr.descripcion) AS descripcion
           FROM stk_raw sr
             LEFT JOIN fam f ON f.sec = sr.codn
          GROUP BY (COALESCE(f.ppal, sr.codn))
        ), proy_raw AS (
         SELECT regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text) AS codn,
                sum(COALESCE(proyeccion_madre.proy_uni_mes, 0::numeric)) AS uni,
                max(COALESCE(proyeccion_madre.proy_cajas_mes, 0::numeric)) AS cajas
           FROM proyeccion_madre
          WHERE btrim(proyeccion_madre.cod) ~ '^[0-9]'::text
          GROUP BY (regexp_replace(regexp_replace(regexp_replace(upper(btrim(proyeccion_madre.cod)), '^0+(?=.)'::text, ''::text), 'L$'::text, ''::text), '^546E$'::text, '546'::text))
        ), gux AS (
         SELECT gv_cod_stock("GV_UxB".cod) AS c,
                max("GV_UxB".uxb) AS u
           FROM "GV_UxB"
          WHERE "GV_UxB".uxb > 0::numeric
          GROUP BY (gv_cod_stock("GV_UxB".cod))
        ), proy AS (
         SELECT COALESCE(f.ppal, pr.codn) AS codn,
                sum(CASE WHEN gx.u > 0::numeric THEN pr.uni / gx.u ELSE pr.cajas END) AS proy
           FROM proy_raw pr
             LEFT JOIN fam f ON f.sec = pr.codn
             LEFT JOIN gux gx ON gx.c = pr.codn
          GROUP BY (COALESCE(f.ppal, pr.codn))
        ), cap AS (
         -- v16.72: 'LIBRE' es la celda vacía de Capacidad_Sector, no un artículo
         SELECT regexp_replace(upper(btrim("Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text) AS codn,
                sum(COALESCE("Capacidad_Sector".cajas_max, 0::numeric)) AS cap
           FROM "Capacidad_Sector"
          WHERE upper(btrim(COALESCE("Capacidad_Sector".cod, ''::text))) <> 'LIBRE'::text
          GROUP BY (regexp_replace(upper(btrim("Capacidad_Sector".cod)), '^0+(?=.)'::text, ''::text))
        ), cfg AS (
         SELECT DISTINCT ON ((regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)'::text, ''::text)))
                regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)'::text, ''::text) AS codn,
                upper(btrim("OC_Maximos".cod)) AS cod_cfg,
                "OC_Maximos".descripcion,
                "OC_Maximos".linea,
                NULLIF(btrim(COALESCE("OC_Maximos".proveedor, ''::text)), ''::text) AS proveedor,
                COALESCE("OC_Maximos".prop_prov1, 100::numeric) AS pr1,
                NULLIF(btrim(COALESCE("OC_Maximos".proveedor2, ''::text)), ''::text) AS proveedor2,
                COALESCE("OC_Maximos".prop_prov2, 0::numeric) AS pr2,
                CASE WHEN COALESCE("OC_Maximos".indice, 0::numeric) > 0::numeric THEN "OC_Maximos".indice ELSE 1.5 END AS indice,
                COALESCE("OC_Maximos".activo, true) AS activo,
                COALESCE("OC_Maximos".llenar_gondola, false) AS llenar_gondola
           FROM "OC_Maximos"
          WHERE NULLIF(btrim("OC_Maximos".cod), ''::text) IS NOT NULL
          ORDER BY (regexp_replace(upper(btrim("OC_Maximos".cod)), '^0+(?=.)'::text, ''::text)), (COALESCE("OC_Maximos".activo, true)) DESC NULLS LAST
        ), pickeadas AS (
         SELECT DISTINCT upper(btrim("Registros_Produccion_Virgilio".texto)) AS tanda
           FROM "Registros_Produccion_Virgilio"
          WHERE "Registros_Produccion_Virgilio".opcion = 'TP'::text AND NULLIF(btrim(COALESCE("Registros_Produccion_Virgilio".texto, ''::text)), ''::text) IS NOT NULL
        ), pend_np AS (
         SELECT DISTINCT btrim(p.np) AS np
           FROM "GV_PPP_Programacion_Diaria" p
          WHERE NOT (btrim(p.np) IN (SELECT btrim("Facturacion_NP".np) AS btrim FROM "Facturacion_NP"))
            AND NOT (upper(btrim(COALESCE(p.tanda, ''::text))) IN (SELECT pickeadas.tanda FROM pickeadas))
        ), dem_raw AS (
         SELECT regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)'::text, ''::text) AS codn,
                sum(COALESCE(b.cajas, 0::numeric)) AS pedidos
           FROM gv_demanda_pedidos b
             JOIN pend_np n ON btrim(b.pedido) = n.np
          WHERE NULLIF(btrim(b.articulo), ''::text) IS NOT NULL
          GROUP BY (regexp_replace(upper(btrim(b.articulo)), '^0+(?=.)'::text, ''::text))
        ), dem AS (
         SELECT COALESCE(f.ppal, dr.codn) AS codn,
                sum(dr.pedidos) AS pedidos
           FROM dem_raw dr
             LEFT JOIN fam f ON f.sec = dr.codn
          GROUP BY (COALESCE(f.ppal, dr.codn))
        ), ncaja AS (
         SELECT DISTINCT ON (t.codn) t.codn, t.n_caja
           FROM ( SELECT regexp_replace(upper(btrim("Articulos_Cajas"."Cod_Art")), '^0+(?=.)'::text, ''::text) AS codn,
                         "Articulos_Cajas"."N_Caja" AS n_caja,
                         count(*) AS c
                    FROM "Articulos_Cajas"
                   WHERE "Articulos_Cajas"."N_Caja" IS NOT NULL
                   GROUP BY (regexp_replace(upper(btrim("Articulos_Cajas"."Cod_Art")), '^0+(?=.)'::text, ''::text)), "Articulos_Cajas"."N_Caja") t
          ORDER BY t.codn, t.c DESC, t.n_caja
        ), nom_ux AS (
         -- v16.72: 3ª fuente de nombre — GV_UxB (curado primero, el más reciente después)
         SELECT DISTINCT ON (gv_cod_stock(u.cod)) gv_cod_stock(u.cod) AS codn, btrim(u.descripcion) AS descripcion
           FROM "GV_UxB" u
          WHERE NULLIF(btrim(COALESCE(u.descripcion, ''::text)), ''::text) IS NOT NULL
          ORDER BY gv_cod_stock(u.cod), COALESCE(u.curado, false) DESC, u.actualizado DESC NULLS LAST
        ), nom_ac AS (
         -- v16.72: 4ª fuente de nombre — Articulos_Cajas (no suspendido primero)
         SELECT DISTINCT ON (regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)'::text, ''::text))
                regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)'::text, ''::text) AS codn,
                btrim(a."Descripcion") AS descripcion
           FROM "Articulos_Cajas" a
          WHERE NULLIF(btrim(COALESCE(a."Descripcion", ''::text)), ''::text) IS NOT NULL
          ORDER BY (regexp_replace(upper(btrim(a."Cod_Art")), '^0+(?=.)'::text, ''::text)), COALESCE(a."Suspendido", false) ASC, a.id DESC
        ), universo AS (
         SELECT stk.codn FROM stk WHERE stk.fin_dep > 0::numeric
         UNION
         SELECT proy.codn FROM proy WHERE proy.proy > 0::numeric
         UNION
         SELECT dem.codn FROM dem
         UNION
         SELECT cap.codn FROM cap WHERE cap.cap > 0::numeric
         UNION
         SELECT cfg.codn FROM cfg
        ), base AS (
         SELECT u.codn,
                COALESCE(c.cod_cfg, u.codn) AS cod,
                COALESCE(c.descripcion, s.descripcion, nx.descripcion, na.descripcion) AS descripcion,   -- v16.72
                c.linea,
                COALESCE(c.proveedor, '(sin proveedor)'::text) AS proveedor,
                c.proveedor IS NOT NULL AS tiene_prov_real,
                COALESCE(c.pr1, 100::numeric) AS pr1,
                c.proveedor2,
                COALESCE(c.pr2, 0::numeric) AS pr2,
                COALESCE(c.indice, 1.5) AS indice,
                COALESCE(c.activo, true) AS activo,
                c.codn IS NOT NULL AS en_config,
                COALESCE(c.llenar_gondola, false) AS llenar_gondola,
                COALESCE(s.stock, 0::numeric) AS stock,
                COALESCE(pr.proy, 0::numeric) AS proy,
                COALESCE(cp.cap, 0::numeric) AS cap,
                COALESCE(d.pedidos, 0::numeric) AS pedidos,
                COALESCE(ux.uni_x_caja, 0::numeric) AS uni_x_caja,
                nc.n_caja
           FROM universo u
             LEFT JOIN stk s ON s.codn = u.codn
             LEFT JOIN proy pr ON pr.codn = u.codn
             LEFT JOIN cap cp ON cp.codn = u.codn
             LEFT JOIN dem d ON d.codn = u.codn
             LEFT JOIN cfg c ON c.codn = u.codn
             LEFT JOIN ncaja nc ON nc.codn = u.codn
             LEFT JOIN vista_uni_x_caja ux ON ux.codn = u.codn
             LEFT JOIN nom_ux nx ON nx.codn = u.codn
             LEFT JOIN nom_ac na ON na.codn = u.codn
        ), conmax AS (
         SELECT b.codn, b.cod, b.descripcion, b.linea, b.proveedor, b.tiene_prov_real, b.pr1, b.proveedor2, b.pr2,
                b.indice, b.activo, b.en_config, b.llenar_gondola, b.stock, b.proy, b.cap, b.pedidos, b.uni_x_caja, b.n_caja,
                CASE
                    WHEN COALESCE(b.llenar_gondola, false) AND b.cap > 0::numeric THEN b.cap
                    WHEN b.proy > 0::numeric THEN LEAST(ceil(b.proy * b.indice), COALESCE(NULLIF(b.cap, 0::numeric), 1000000000::numeric))
                    WHEN b.tiene_prov_real THEN COALESCE(NULLIF(b.cap, 0::numeric), 0::numeric)
                    ELSE 0::numeric
                END AS maximo
           FROM base b
        )
 SELECT codn, cod, descripcion, linea, proveedor, tiene_prov_real, pr1, proveedor2, pr2, indice, activo, en_config,
        stock, proy, cap, pedidos, uni_x_caja, n_caja, maximo,
        GREATEST(0::numeric, ceil(maximo + pedidos - stock))::integer AS total,
        llenar_gondola
   FROM conmax cm
  WHERE NOT (EXISTS (SELECT 1 FROM fam f2 WHERE f2.sec = cm.codn))
    AND cm.codn <> 'LIBRE'::text;                                                                          -- v16.72

-- verificación
select cod, descripcion, proveedor, cap, maximo, total from public.vista_generador_oc
 where codn in ('231','232','233','441Z','501B','587C','592E','599EZ','630E','631E','634E','635E','636E','657','LIBRE')
 order by cod;                                                       -- espera 14 filas (sin LIBRE), 9 con nombre nuevo
select count(*) as sin_nombre from public.vista_generador_oc where descripcion is null;   -- espera 5
select * from public.gv_endpoints_rotos;                              -- espera vacío

-- ---------------------------------------------------------------------------
-- (c) CAPACIDAD DUPLICADA M34 / M35 / M36 — PROPUESTA, NO SE DECIDE ACÁ
--
--     La CTE `cap` agrupa por código y trata 630 y 630E como códigos distintos, así que cada
--     góndola cuenta dos veces: M34 = 630 12 + 630E 12 + 631 12 + 631E 12 + 632 12 = 60 ·
--     M35 = 633 12 + 634 12 + 634E 12 + 635 5 + 635E 5 = 46 · M36 = 613 5 + 636 5 + 636E 5 + 637 5 +
--     858 12 = 32. Hoy (13/09) el generador ve cap 630=12, 630E=12, 631=12, 631E=12, 634=12,
--     634E=12, 635=5, 635E=5, 636=5, 636E=5.
--
--     Opción A — `cap` suma por código BASE (sin la E): cap 630=24, 631=24, 634=24, 635=10, 636=10; las
--        filas E desaparecen de cap (se unen al base).
--        Efecto medido sobre lo que sugiere hoy: sólo cambia 631 (proy 0 → máximo = cap): máximo 12 →
--        24, total 14 → 26 (+12 cajas). 630/634/635/636 tienen proy > 0 y el máximo lo fija
--        ceil(proy × 1.5) = 1, no la cap → sin cambio. Los 63xE con la fila de (a) quedan con cap 0 y
--        máximo 0 (nunca sugieren), igual que hoy.
--     Opción B — bajar `cajas_max` de las filas E a 0 (o borrarlas) en Capacidad_Sector: M34 = 36,
--        M35 = 29, M36 = 22. Nada cambia en 630..636. Los E quedan con cap 0 y máximo 0.
--        ⚠ Capacidad_Sector es tabla madre (CLAUDE.md): se toca sólo con el "dale".
--     Opción C — el E ES el código vigente (Articulos_Cajas: 630..636 `Suspendido = true`, los E no):
--        pasar la configuración de OC_Maximos del sin-E al E (max 9/6/1.5/6/6, 'Carlos E') y poner
--        `activo = false` en 630..636. Entonces cap 630E = 12 etc. y el generador sugiere por el E.
--        ⚠ 630 y 631 tienen HOY 2 cajas pedidas cada uno en NPs pendientes (dem) → el sin-E se sigue
--        vendiendo; si se apaga, esas 2 cajas no se compran. Hace falta que Thomas diga si 630 y 630E
--        son el mismo artículo (misma góndola, mismo stock) o dos.
--     Lo que se vea que corresponda se escribe en otro PENDIENTE; acá no hay UPDATE para (c).
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- ROLLBACK
-- ---------------------------------------------------------------------------
-- delete from public."OC_Maximos" where upper(btrim(cod)) in ('630E','631E','634E','635E','636E') and linea = 'CH';
-- vista: volver a la definición del 13/09 = la misma de arriba SIN: el WHERE de `cap`, las CTE nom_ux /
-- nom_ac y sus dos LEFT JOIN, `COALESCE(c.descripcion, s.descripcion)` en base, y sin `AND cm.codn <> 'LIBRE'`.
-- (fuente de la vieja: pg_get_viewdef('public.vista_generador_oc'::regclass, true) tomado el 13/09
--  antes de aplicar — o git show 1f75687:sql/ si alguien la guardó; el texto vigente está en
--  docs/SUPABASE-GESTION-VIRGILIO.md §3.dx como referencia).
