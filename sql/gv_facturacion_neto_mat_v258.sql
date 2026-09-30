-- D14 (Thomas 30/09): Facturación → Conciliación se cortaba por timeout.
-- gv_vista_cruce_facturacion calculaba el neto de TODAS las NP (1.114) en cada lectura
-- (gv_vista_facturacion_neto = 1,4-1,7 s; bajo carga pasaba los 8 s: 72 timeouts 08:56-09:28 ART).
-- Ahora lee una foto materializada del neto (refresco c/10 min, minutos impares) y
-- calcula EN VIVO sólo las NP que todavía no están en la foto (el filtro = ANY(ARRAY(...))
-- baja por el GROUP BY, mismo patrón que facturacion_neto_lote v22.44).
-- Costo aceptado: una NP ya fotografiada cuyo armado cambia se ve con el neto viejo hasta 10 min.
-- ROLLBACK: correr el bloque "ROLLBACK" del final.

create materialized view if not exists public.gv_facturacion_neto_mat as
  select np, neto, cajas_ent, items_sin_precio from public.gv_vista_facturacion_neto;
create unique index if not exists gv_facturacion_neto_mat_np on public.gv_facturacion_neto_mat(np);
revoke all on public.gv_facturacion_neto_mat from anon, authenticated;

create or replace view public.gv_vista_cruce_facturacion with (security_invoker = true) as
 WITH base AS (
         SELECT f.np, f.tanda, f.fecha_salida, f.razon_social AS rs_virgilio, f.cod_cliente,
            gv_empresa_de_np_texto(f.np) AS empresa,
            n.neto AS neto_calculado, n.cajas_ent, n.items_sin_precio
           FROM "Facturacion_NP" f
             LEFT JOIN (
               SELECT m.np, m.neto, m.cajas_ent, m.items_sin_precio FROM gv_facturacion_neto_mat m
               UNION ALL
               SELECT v.np, v.neto, v.cajas_ent, v.items_sin_precio FROM gv_vista_facturacion_neto v
                WHERE v.np = ANY (ARRAY(SELECT f2.np FROM "Facturacion_NP" f2
                                         WHERE NOT EXISTS (SELECT 1 FROM gv_facturacion_neto_mat m2 WHERE m2.np = f2.np)))
             ) n ON n.np = f.np
        ), asig AS (
         SELECT a_1.np, a_1.doc_id, a_1.candidatos FROM "GV_Cruce_FC_Asig" a_1
        ), doc AS (
         SELECT 'lk'::text AS empresa, d_1.id, d_1.comprobante_id, d_1.fecha, d_1.total, d_1.subt_gravado,
            d_1.total_cajas, d_1.storage_path, d_1.cae
           FROM isis_lk.documentos d_1 WHERE d_1.familia = 'factura_venta'::text
        UNION ALL
         SELECT 'chef'::text AS text, d_1.id, d_1.comprobante_id, d_1.fecha, d_1.total, d_1.subt_gravado,
            d_1.total_cajas, d_1.storage_path, d_1.cae
           FROM isis_ch.documentos d_1 WHERE d_1.familia = 'factura_venta'::text
        )
 SELECT b.np, b.tanda, b.fecha_salida, b.rs_virgilio, b.cod_cliente, b.empresa, b.neto_calculado,
    b.cajas_ent, b.items_sin_precio, d.id AS doc_id, d.comprobante_id, d.fecha AS doc_fecha,
    d.total::numeric AS factura_total, d.subt_gravado::numeric AS factura_neto,
    d.total_cajas::numeric AS factura_cajas, d.storage_path, d.cae,
    COALESCE(a.candidatos, 0)::bigint AS candidatos_cercanos,
        CASE WHEN d.id IS NOT NULL THEN d.subt_gravado - b.neto_calculado ELSE NULL::numeric END AS diff,
        CASE WHEN d.id IS NOT NULL AND b.neto_calculado IS NOT NULL AND b.neto_calculado <> 0::numeric
             THEN round((d.subt_gravado - b.neto_calculado) / b.neto_calculado * 100::numeric, 2)
             ELSE NULL::numeric END AS diff_pct,
        CASE WHEN b.neto_calculado IS NULL THEN 'sin_neto'::text
             WHEN d.id IS NULL THEN 'sin_factura'::text
             WHEN abs(COALESCE(d.subt_gravado, 0::numeric) - b.neto_calculado) <= GREATEST(50::numeric, b.neto_calculado * 0.01) THEN 'ok'::text
             ELSE 'diff'::text END AS estado,
    (EXISTS ( SELECT 1 FROM cobranzas_cliente_cadena cc
          WHERE cc.cod_cliente = b.cod_cliente AND cc.empresa = b.empresa)) AS es_super
   FROM base b
     LEFT JOIN asig a ON a.np = b.np
     LEFT JOIN doc d ON d.empresa = b.empresa AND d.id = a.doc_id;
alter view public.gv_vista_cruce_facturacion set (security_invoker = true);

-- cron: refresco cada 10 min en minutos impares (5,15,...,55; no choca con el 55 de stock, que es par)
select cron.schedule('gv-facturacion-neto-mat', '5-55/10 * * * *',
  'refresh materialized view concurrently public.gv_facturacion_neto_mat');


-- Y las dos RPC de la pantalla leen la vista MATERIALIZED: con parametros el planner armaba
-- otro plan (9,2 s contra 0,23 s de la vista entera). Medido como authenticated despues:
-- totales 290 ms · resumen 271 ms (antes 9.234 / ~8.000). Salida identica (EXCEPT ALL 0/0).
--   gv_cruce_facturacion_totales:  with v as materialized (select * from public.gv_vista_cruce_facturacion) ...
--   gv_cruce_facturacion_resumen:  with vv as materialized (select * from public.gv_vista_cruce_facturacion) ...
-- (cuerpo completo aplicado el 30/09; traer la definicion viva con pg_get_functiondef antes de tocarlas)

/* ROLLBACK
select cron.unschedule('gv-facturacion-neto-mat');
-- recrear gv_vista_cruce_facturacion con: LEFT JOIN gv_vista_facturacion_neto n ON n.np = f.np
-- (definición anterior en docs/SUPABASE-GESTION-VIRGILIO.md §3.v258)
drop materialized view public.gv_facturacion_neto_mat;
-- funciones: sacar el 'with ... as materialized' y volver a 'from public.gv_vista_cruce_facturacion'
-- definicion vieja de la vista: zz_backups."GV_Backup_CruceFac_def_20260930"
*/
