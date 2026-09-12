-- ============================================================================
-- v16.26 (2026-09-12) — RECREADA gv_importados_ordenes: el módulo de Importados
-- estaba CAÍDO y nadie lo había notado.
--
-- QUÉ PASÓ. La v16.20 (otro chat) hizo DROP + CREATE de la matview
-- vista_stock_procesada, porque una matview no admite `create or replace`. Recreó
-- las vistas que le colgaban —Stock_Saldos y gv_importados_stock_dep— pero
-- gv_importados_ordenes colgaba de gv_importados_stock_dep y NO se recreó: el
-- CASCADE se la llevó.
--
-- El front la pide desde la v16.04 (SUPABASE_IMPORTADOS_OC_ENDPOINT =
-- /rest/v1/gv_importados_ordenes), así que la pantalla de Importados venía
-- devolviendo 404 y quedando vacía.
--
-- POR QUÉ EL REPO NO ALCANZABA PARA RESTAURARLA. sql/gv_stock_vivo_menos_pedidos_v1608.sql
-- documenta el cambio pero dice "la definición completa está aplicada en la base"
-- en lugar de traer el CREATE. O sea que la única copia de la última versión estaba
-- en el objeto que se borró. Por eso este archivo SÍ trae la definición entera:
-- si el repo no la tiene, no existe.
--
-- VERIFICADO tras recrearla, contra los números que la v16.08 dejó anotados:
--   154 filas principal+activo · 18.173 cajas brutas · 1.351 pedidas · 17.130 disponibles
--   584E (el testigo del dueño): 15 cajas - 5 pedidas = 10 disponibles = 60 unidades
--   anon lee las 156 filas (que es como entra el front)
-- Todo idéntico, así que la restauración es fiel, no una aproximación.
-- ============================================================================

create or replace view public.gv_importados_ordenes
with (security_invoker = true) as
 WITH cfg AS (
         SELECT "Importados_Config".meses_objetivo
           FROM "Importados_Config"
          WHERE "Importados_Config".id = 1
        ), fam AS (
         SELECT gv_cod_stock("Equivalencias_Familia".cod_principal) AS ppal,
            gv_cod_stock("Equivalencias_Familia".cod_secundario) AS sec
           FROM "Equivalencias_Familia"
          WHERE NULLIF(btrim("Equivalencias_Familia".cod_principal), ''::text) IS NOT NULL AND NULLIF(btrim("Equivalencias_Familia".cod_secundario), ''::text) IS NOT NULL
        ), pe_raw AS (
         SELECT gv_cod_stock("GV_Proyeccion_Emp".cod) AS cod_norm,
            "GV_Proyeccion_Emp".empresa,
            "GV_Proyeccion_Emp".proy_cajas_mes
           FROM "GV_Proyeccion_Emp"
        ), pe AS (
         SELECT k.cod_norm,
            r.empresa,
            sum(r.proy_cajas_mes) AS proy_cajas_mes
           FROM ( SELECT DISTINCT pe_raw.cod_norm
                   FROM pe_raw
                UNION
                 SELECT fam.ppal
                   FROM fam) k
             JOIN pe_raw r ON r.cod_norm = k.cod_norm OR (r.cod_norm IN ( SELECT f.sec
                   FROM fam f
                  WHERE f.ppal = k.cod_norm))
          GROUP BY k.cod_norm, r.empresa
        ), partes AS (
         SELECT DISTINCT upper("Importados_Partes_Map".parte) AS cod
           FROM "Importados_Partes_Map"
        ), ch_rows AS (
         SELECT DISTINCT upper("Importados".cod_art) AS cod
           FROM "Importados"
          WHERE "Importados".principal AND "Importados".activo AND upper(COALESCE("Importados".marca, ''::text)) = 'CH'::text
        ), dup AS (
         SELECT gv_cod_stock("Importados".cod_art) AS cod_norm
           FROM "Importados"
          WHERE "Importados".principal AND "Importados".activo
          GROUP BY (gv_cod_stock("Importados".cod_art))
         HAVING count(*) > 1
        ), stk AS (
         SELECT i_1.id,
            COALESCE(sum(d.cajas_bruto), 0::numeric) AS cajas_bruto,
            COALESCE(sum(d.cajas_pedidas), 0::numeric) AS cajas_pedidas
           FROM "Importados" i_1
             LEFT JOIN gv_importados_stock_dep d ON d.cod_norm = gv_cod_stock(i_1.cod_art) AND (NOT (EXISTS ( SELECT 1
                   FROM dup
                  WHERE dup.cod_norm = gv_cod_stock(i_1.cod_art))) OR upper(COALESCE(i_1.marca, ''::text)) = 'CH'::text AND d.empresa = 'CH'::text OR upper(COALESCE(i_1.marca, ''::text)) <> 'CH'::text AND (d.empresa = ANY (ARRAY['LK'::text, 'MIXTO'::text])))
          GROUP BY i_1.id
        )
 SELECT i.id,
    i.cod_art,
    i.marca,
    i.proveedor,
    i.descripcion,
    i.fob_uni,
    i.uni_x_caja,
    i.principal,
    i.activo,
    i.notas,
    i.est_madre_seed,
    i.est_madre_override,
    i.pedido_manual,
    COALESCE(i.pedido_curso, 0::numeric) AS pedido_curso,
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'Chef'::text
            ELSE 'Loeke'::text
        END AS planta,
        CASE
            WHEN p.proy_cajas_mes IS NOT NULL THEN round(p.proy_cajas_mes * COALESCE(i.uni_x_caja, 1::numeric))
            ELSE NULL::numeric
        END AS est_madre_live,
    ( SELECT cfg.meses_objetivo
           FROM cfg) AS meses_objetivo,
    COALESCE(i.est_madre_override,
        CASE
            WHEN p.proy_cajas_mes IS NOT NULL THEN round(p.proy_cajas_mes * COALESCE(i.uni_x_caja, 1::numeric))
            ELSE NULL::numeric
        END, i.est_madre_seed, 0::numeric) AS est_madre_eff,
        CASE
            WHEN i.est_madre_override IS NOT NULL THEN 'override'::text
            WHEN p.proy_cajas_mes IS NOT NULL THEN 'live'::text
            ELSE 'seed'::text
        END AS est_madre_fuente,
    round(GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) * COALESCE(i.uni_x_caja, 0::numeric)) AS stock_actual,
    GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) AS stock_cajas,
    COALESCE(st.cajas_bruto, 0::numeric) AS stock_cajas_bruto,
    COALESCE(st.cajas_pedidas, 0::numeric) AS cajas_pedidas,
    round(COALESCE(st.cajas_pedidas, 0::numeric) * COALESCE(i.uni_x_caja, 0::numeric)) AS unidades_pedidas,
    COALESCE(si.stock_uni, 0::numeric) AS stock_insumos,
    pt.cod IS NOT NULL AS es_parte,
        CASE
            WHEN pt.cod IS NOT NULL AND si.cod IS NOT NULL THEN si.stock_uni
            ELSE round(GREATEST(COALESCE(st.cajas_bruto, 0::numeric) - COALESCE(st.cajas_pedidas, 0::numeric), 0::numeric) * COALESCE(i.uni_x_caja, 0::numeric)) + COALESCE(si.stock_uni, 0::numeric)
        END AS stock_total
   FROM "Importados" i
     LEFT JOIN stk st ON st.id = i.id
     LEFT JOIN pe p ON p.cod_norm = gv_cod_stock(i.cod_art) AND p.empresa =
        CASE
            WHEN upper(COALESCE(i.marca, ''::text)) = 'CH'::text THEN 'chef'::text
            ELSE 'lk'::text
        END
     LEFT JOIN partes pt ON pt.cod = upper(i.cod_art)
     LEFT JOIN gv_importados_stock_insumos si ON upper(si.cod) = upper(i.cod_art) AND i.principal AND i.activo AND (upper(COALESCE(i.marca, ''::text)) = 'CH'::text OR NOT (EXISTS ( SELECT 1
           FROM ch_rows c
          WHERE c.cod = upper(i.cod_art))));

grant select on public.gv_importados_ordenes to anon, authenticated;

comment on view public.gv_importados_ordenes is
  'v16.26 — RECREADA: el DROP CASCADE de la matview en la v16.20 se la habia llevado y la pantalla de Importados devolvia 404. Motor de pedidos de importacion; stock_actual = deposito real menos lo ya pedido, con piso 0.';


-- ============================================================================
-- CENTINELA para que esto no vuelva a pasar en silencio.
--
-- La vista se borró por un DROP CASCADE y NADIE se enteró hasta que alguien miró
-- la pantalla. Un objeto que el front pide y que no existe da 404 y la pantalla
-- queda vacía, sin error visible en ningún lado.
--
--   select * from public.gv_endpoints_rotos;   -- 0 filas = todos los endpoints existen
--
-- La lista se mantiene A MANO: si el front estrena un endpoint, se agrega acá.
-- ============================================================================
create or replace view public.gv_endpoints_rotos with (security_invoker = true) as
select e.objeto, e.pantalla
from (values
  ('gv_importados_ordenes','Importados'),
  ('gv_importados_stock_dep','Importados'),
  ('gv_importados_stock_insumos','Importados'),
  ('vista_stock_procesada','Stock'),
  ('vista_saldos_stock','Stock'),
  ('Stock_Saldos','Stock'),
  ('gv_uxb_lk','Facturacion'),
  ('gv_uxb_emp','Facturacion'),
  ('vista_facturacion_neto_items','Facturacion'),
  ('vista_plata_perdida','Cobranzas'),
  ('vista_facturable_anticipado','Facturacion'),
  ('gv_ppp_programacion_diaria','PPP'),
  ('gv_ppp_base_pedidos','PPP'),
  ('gv_ppp_entregados_meta','PPP'),
  ('vista_generador_oc','Compras'),
  ('vista_uni_x_caja','Compras'),
  ('vista_uxb_articulo','Facturacion'),
  ('vista_volumen_articulo_resuelto','m3')
) e(objeto, pantalla)
where to_regclass('public.'||quote_ident(e.objeto)) is null;
grant select on public.gv_endpoints_rotos to anon, authenticated, service_role;
