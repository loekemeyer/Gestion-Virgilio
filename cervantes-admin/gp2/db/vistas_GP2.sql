-- =====================================================================
-- VISTAS del schema GP2 (pg_get_viewdef, exacto) — export automatico 2026-09-05 desde Supabase (hrxfctzncixxqmpfhskv)
-- Respaldo/referencia. La fuente de verdad es la base; regenerar al cambiar el schema.
-- 13 vistas. Orden de creacion: las que dependen de otra van despues.
-- =====================================================================

-- ---------- v_consumo_componente ----------
create or replace view "GP2".v_consumo_componente as
 SELECT c.id AS componente_id,
    c.codigo,
    c.descripcion,
    c.sector_id,
    s.nombre AS sector,
    round(sum(d.uni_mes)) AS consumo_uni_mes,
    count(DISTINCT d.articulo_id) AS en_articulos
   FROM "GP2".v_consumo_demanda d
     JOIN "GP2".componente c ON c.id = d.componente_id
     LEFT JOIN "GP2".sector s ON s.id = c.sector_id
  GROUP BY c.id, c.codigo, c.descripcion, c.sector_id, s.nombre;
comment on view "GP2".v_consumo_componente is 'Consumo uni/mes por componente, todos los sectores. Sucesora de v_consumo_parte (que solo cubria la receta directa).';

-- ---------- v_consumo_demanda ----------
create or replace view "GP2".v_consumo_demanda as
 WITH RECURSIVE dem AS (
         SELECT a.id AS art_id,
            em.proy_uni_mes AS uni
           FROM "GP2".articulo a
             JOIN "GP2".est_madre em ON regexp_replace(em.cod, '^0+'::text, ''::text) = regexp_replace(a.codigo, '^0+'::text, ''::text)
          WHERE em.proy_uni_mes IS NOT NULL AND NOT a.discontinuado
        ), receta AS (
         SELECT ac.articulo_id AS art_id,
            ac.componente_id AS comp_id,
            d.uni * ac.cantidad AS qty
           FROM "GP2".articulo_componente ac
             JOIN dem d ON d.art_id = ac.articulo_id
        UNION ALL
         SELECT r.art_id,
            b.componente_hijo_id,
            r.qty * b.cantidad
           FROM receta r
             JOIN "GP2".componente_bom b ON b.componente_padre_id = r.comp_id
        ), seed AS (
         SELECT receta.art_id,
            receta.comp_id,
            sum(receta.qty) AS qty
           FROM receta
          GROUP BY receta.art_id, receta.comp_id
        ), arista AS (
         SELECT DISTINCT r.articulo_id AS art_id,
            rp.comp_salida_id AS sal,
            rp.comp_entrada_id AS ent
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
          WHERE rp.comp_entrada_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL AND r.articulo_id IS NOT NULL
        ), walk AS (
         SELECT seed.art_id,
            seed.comp_id,
            seed.comp_id AS seed
           FROM seed
        UNION
         SELECT a.art_id,
            a.ent,
            w_1.seed
           FROM walk w_1
             JOIN arista a ON a.art_id = w_1.art_id AND a.sal = w_1.comp_id
          WHERE NOT (EXISTS ( SELECT 1
                   FROM seed s2
                  WHERE s2.art_id = a.art_id AND s2.comp_id = a.ent))
        )
 SELECT w.art_id AS articulo_id,
    w.comp_id AS componente_id,
    sum(s.qty) AS uni_mes
   FROM walk w
     JOIN seed s ON s.art_id = w.art_id AND s.comp_id = w.seed
  GROUP BY w.art_id, w.comp_id;
comment on view "GP2".v_consumo_demanda is 'Consumo uni/mes por (articulo, componente) para TODA la cadena, caminando la ruta hacia atras desde la receta del articulo terminado. Reemplaza al parche "primer nodo con consumo" que sobrecontaba.';

-- ---------- v_consumo_fleje_kg ----------
create or replace view "GP2".v_consumo_fleje_kg as
 WITH paso AS (
         SELECT DISTINCT r.articulo_id AS art_id,
            rp.comp_entrada_id AS fleje_id,
            rp.comp_salida_id AS sal,
            m.partes_por_kilo_de_fleje AS ppk
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
             JOIN "GP2".componente ce ON ce.id = rp.comp_entrada_id AND ce.sector_id = 5
             JOIN "GP2".matriz m ON m.id = rp.matriz_id
          WHERE r.articulo_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL AND COALESCE(m.partes_por_kilo_de_fleje, 0::numeric) > 0::numeric
        )
 SELECT f.id AS componente_id,
    f.codigo,
    f.descripcion,
    round(sum(d.uni_mes / p.ppk), 1) AS consumo_kg_mes,
    count(*) AS piezas
   FROM paso p
     JOIN "GP2".v_consumo_demanda d ON d.articulo_id = p.art_id AND d.componente_id = p.sal
     JOIN "GP2".componente f ON f.id = p.fleje_id
  GROUP BY f.id, f.codigo, f.descripcion;
comment on view "GP2".v_consumo_fleje_kg is 'Kg/mes de fleje. Igual que v_consumo_fleje_kg pero tomando la demanda atribuida por articulo (v_consumo_demanda) en vez del consumo entero del primer nodo aguas abajo.';

-- ---------- v_contraparte_parte ----------
create or replace view "GP2".v_contraparte_parte as
 SELECT 'proveedor_servicio'::text AS tipo,
    rp.proveedor_id AS ref_id,
    rp.comp_entrada_id AS comp_id,
    'entrada'::text AS lado
   FROM "GP2".ruta_paso rp
  WHERE rp.tipo_paso = 'proveedor_servicio'::text AND rp.proveedor_id IS NOT NULL AND rp.comp_entrada_id IS NOT NULL
UNION
 SELECT 'proveedor_servicio'::text AS tipo,
    rp.proveedor_id AS ref_id,
    rp.comp_salida_id AS comp_id,
    'salida'::text AS lado
   FROM "GP2".ruta_paso rp
  WHERE rp.tipo_paso = 'proveedor_servicio'::text AND rp.proveedor_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL
UNION
 SELECT 'tallerista'::text AS tipo,
    rp.tallerista_id AS ref_id,
    rp.comp_entrada_id AS comp_id,
    'entrada'::text AS lado
   FROM "GP2".ruta_paso rp
  WHERE rp.tipo_paso = 'tallerista'::text AND rp.tallerista_id IS NOT NULL AND rp.comp_entrada_id IS NOT NULL
UNION
 SELECT 'tallerista'::text AS tipo,
    rp.tallerista_id AS ref_id,
    rp.comp_salida_id AS comp_id,
    'salida'::text AS lado
   FROM "GP2".ruta_paso rp
  WHERE rp.tipo_paso = 'tallerista'::text AND rp.tallerista_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL;
comment on view "GP2".v_contraparte_parte is 'Que componente ENTRA (lado=entrada: se le manda) y SALE (lado=salida: devuelve hecho) por cada contraparte (tipo + ref_id), derivado de ruta_paso. Unica definicion (2026-09-05).';

-- ---------- v_control_pallet ----------
create or replace view "GP2".v_control_pallet as
 WITH p AS (
         SELECT max(parametro.valor) FILTER (WHERE parametro.clave = 'tara_pallet_min'::text) AS tmin,
            max(parametro.valor) FILTER (WHERE parametro.clave = 'tara_pallet_max'::text) AS tmax,
            max(parametro.valor) FILTER (WHERE parametro.clave = 'tol_ctrl_peso_pct'::text) AS tolpct
           FROM "GP2".parametro
        ), r AS (
         SELECT recepcion_control_rollo.control_id,
            sum(recepcion_control_rollo.cantidad) AS rollos,
            sum(recepcion_control_rollo.cantidad::numeric * recepcion_control_rollo.kg_por_rollo) AS kg,
            count(*) AS tipos
           FROM "GP2".recepcion_control_rollo
          GROUP BY recepcion_control_rollo.control_id
        )
 SELECT ctl.id AS control_id,
    ctl.recepcion_id,
    ctl.nro_pallet,
    ctl.peso_balanza,
    ctl.controlado_por,
    ctl.controlado_en,
    COALESCE(r.rollos, 0::bigint) AS rollos,
    COALESCE(r.kg, 0::numeric) AS kg_rollos,
    COALESCE(r.tipos, 0::bigint) AS tipos_de_peso,
    ctl.peso_balanza - COALESCE(r.kg, 0::numeric) AS sobrante_kg,
    p.tmin AS sobrante_min,
    p.tmax AS sobrante_max,
        CASE
            WHEN COALESCE(pi.modo_control, 'ninguno'::text) = 'peso_total'::text THEN
            CASE
                WHEN abs(ctl.peso_balanza - ri.cantidad) <= GREATEST(ri.cantidad * COALESCE(p.tolpct, 2::numeric) / 100.0, 0.5) THEN 'ok'::text
                ELSE 'peso distinto al remito'::text
            END
            WHEN COALESCE(r.rollos, 0::bigint) = 0 THEN 'sin rollos cargados'::text
            WHEN (ctl.peso_balanza - COALESCE(r.kg, 0::numeric)) < p.tmin THEN 'sobrante bajo'::text
            WHEN (ctl.peso_balanza - COALESCE(r.kg, 0::numeric)) > p.tmax THEN 'sobrante alto'::text
            ELSE 'ok'::text
        END AS estado
   FROM "GP2".recepcion_control ctl
     JOIN "GP2".recepcion_insumo ri ON ri.id = ctl.recepcion_id
     LEFT JOIN "GP2".proveedor_insumo pi ON pi.nombre = ri.proveedor
     LEFT JOIN r ON r.control_id = ctl.id
     CROSS JOIN p;

-- ---------- v_costo_componente ----------
create or replace view "GP2".v_costo_componente as
 WITH RECURSIVE par AS (
         SELECT ( SELECT parametro.valor
                   FROM "GP2".parametro
                  WHERE parametro.clave = 'costo_segundo_pesos'::text) AS costo_seg,
            ( SELECT parametro.valor
                   FROM "GP2".parametro
                  WHERE parametro.clave = 'tipo_cambio_usd_pesos'::text) AS tc
        ), pc AS (
         SELECT DISTINCT ON (precio_proveedor.componente_id) precio_proveedor.componente_id,
                CASE
                    WHEN precio_proveedor.precio_por_kg THEN precio_proveedor.precio * (( SELECT c9.kg_x_uni
                       FROM "GP2".componente c9
                      WHERE c9.id = precio_proveedor.componente_id))
                    ELSE precio_proveedor.precio
                END AS precio,
                CASE
                    WHEN upper(COALESCE(precio_proveedor.moneda, 'USD'::text)) ~~ '%US%'::text OR upper(COALESCE(precio_proveedor.moneda, 'USD'::text)) = 'USD'::text THEN 'USD'::text
                    ELSE 'ARS'::text
                END AS moneda
           FROM "GP2".precio_proveedor
          WHERE precio_proveedor.componente_id IS NOT NULL AND precio_proveedor.precio IS NOT NULL
          ORDER BY precio_proveedor.componente_id, precio_proveedor.fecha_lista DESC NULLS LAST, precio_proveedor.id DESC
        ), comprado AS (
         SELECT c_1.id,
            c_1.sector_id,
            pc.precio,
            pc.moneda
           FROM "GP2".componente c_1
             LEFT JOIN pc ON pc.componente_id = c_1.id
          WHERE ((EXISTS ( SELECT 1
                   FROM "GP2".sector s9
                  WHERE s9.id = c_1.sector_id AND s9.es_insumo)) OR pc.precio IS NOT NULL AND NOT (EXISTS ( SELECT 1
                   FROM "GP2".ruta_paso rp2
                  WHERE rp2.comp_salida_id = c_1.id AND (rp2.tipo_paso = ANY (ARRAY['matriz'::text, 'proveedor_servicio'::text, 'tallerista'::text]))))) AND (c_1.estado_compra IS NULL OR (c_1.estado_compra = ANY (ARRAY['importado'::text, 'compra'::text])))
        ), edges AS (
         SELECT DISTINCT rp.comp_entrada_id AS ent,
            rp.comp_salida_id AS sal,
            rp.tipo_paso,
            rp.matriz_id,
            rp.proveedor_id
           FROM "GP2".ruta_paso rp
          WHERE rp.comp_entrada_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL AND rp.comp_entrada_id <> rp.comp_salida_id AND (rp.tipo_paso = ANY (ARRAY['matriz'::text, 'proveedor_servicio'::text, 'tallerista'::text]))
        ), selfsrv AS (
         SELECT DISTINCT rp.comp_salida_id AS comp,
            rp.proveedor_id
           FROM "GP2".ruta_paso rp
          WHERE rp.tipo_paso = 'proveedor_servicio'::text AND rp.proveedor_id IS NOT NULL AND rp.comp_entrada_id = rp.comp_salida_id
        ), fabricado AS (
         SELECT c_1.id,
            c_1.kg_x_uni
           FROM "GP2".componente c_1
          WHERE NOT (c_1.id IN ( SELECT comprado.id
                   FROM comprado))
        ), w AS (
         SELECT f.id AS comp_id,
            e.ent,
            e.sal,
            e.tipo_paso,
            e.matriz_id,
            e.proveedor_id,
            f.kg_x_uni AS kg_ref,
            1 AS depth
           FROM fabricado f
             JOIN edges e ON e.sal = f.id
        UNION
         SELECT w.comp_id,
            e.ent,
            e.sal,
            e.tipo_paso,
            e.matriz_id,
            e.proveedor_id,
            COALESCE(ce.kg_x_uni, w.kg_ref) AS "coalesce",
            w.depth + 1
           FROM w
             JOIN "GP2".componente ce ON ce.id = w.ent
             JOIN edges e ON e.sal = w.ent
          WHERE w.depth < 40 AND NOT (w.ent IN ( SELECT comprado.id
                   FROM comprado))
        ), wd AS (
         SELECT w.comp_id,
            w.ent,
            w.sal,
            w.tipo_paso,
            w.matriz_id,
            w.proveedor_id,
            max(w.kg_ref) AS kg_ref
           FROM w
          GROUP BY w.comp_id, w.ent, w.sal, w.tipo_paso, w.matriz_id, w.proveedor_id
        ), mat AS (
         SELECT x.comp_id,
            COALESCE(sum(x.val) FILTER (WHERE x.moneda = 'USD'::text), 0::numeric) AS usd,
            COALESCE(sum(x.val) FILTER (WHERE x.moneda = 'ARS'::text), 0::numeric) AS ars,
            count(*) FILTER (WHERE x.precio IS NULL) AS sin_precio,
            count(*) FILTER (WHERE x.precio IS NOT NULL AND x.val IS NULL) AS sin_kg
           FROM ( SELECT wd.comp_id,
                    cb_1.precio,
                    cb_1.moneda,
                        CASE
                            WHEN cb_1.sector_id = 5 THEN cb_1.precio * COALESCE(wd.kg_ref, 1::numeric / NULLIF(m.partes_por_kilo_de_fleje, 0::numeric))
                            ELSE cb_1.precio
                        END AS val
                   FROM wd
                     JOIN comprado cb_1 ON cb_1.id = wd.ent
                     LEFT JOIN "GP2".matriz m ON m.id = wd.matriz_id) x
          GROUP BY x.comp_id
        ), lab AS (
         SELECT y.comp_id,
            COALESCE(sum(
                CASE
                    WHEN m.tiempo_unidad = 'kg'::text THEN m.tiempo_historico * cm.kg_x_uni
                    ELSE m.tiempo_historico
                END), 0::numeric) AS segundos,
            count(*) FILTER (WHERE m.tiempo_historico IS NULL) AS sin_tiempo
           FROM ( SELECT wd.comp_id,
                    wd.matriz_id,
                    max(wd.sal) AS sal
                   FROM wd
                  WHERE wd.tipo_paso = 'matriz'::text AND wd.matriz_id IS NOT NULL
                  GROUP BY wd.comp_id, wd.matriz_id) y
             JOIN "GP2".matriz m ON m.id = y.matriz_id
             LEFT JOIN "GP2".componente cm ON cm.id = y.sal
          GROUP BY y.comp_id
        ), nodos AS (
         SELECT f.id AS comp_id,
            f.id AS nodo
           FROM fabricado f
        UNION
         SELECT wd.comp_id,
            wd.ent
           FROM wd
        UNION
         SELECT wd.comp_id,
            wd.sal
           FROM wd
        ), srv AS (
         SELECT z.comp_id,
            COALESCE(sum(COALESCE(pz.precio_kg * cz.kg_x_uni, pz.precio_uni, ts.precio_kg * cz.kg_x_uni, ts.precio_uni)) FILTER (WHERE COALESCE(pz.moneda, ts.moneda) = 'USD'::text), 0::numeric) AS usd,
            COALESCE(sum(COALESCE(pz.precio_kg * cz.kg_x_uni, pz.precio_uni, ts.precio_kg * cz.kg_x_uni, ts.precio_uni)) FILTER (WHERE COALESCE(pz.moneda, ts.moneda) = 'ARS'::text), 0::numeric) AS ars,
            count(*) FILTER (WHERE COALESCE(pz.precio_kg * cz.kg_x_uni, pz.precio_uni, ts.precio_kg * cz.kg_x_uni, ts.precio_uni) IS NULL) AS sin_precio
           FROM ( SELECT DISTINCT wd.comp_id,
                    wd.sal AS pieza,
                    wd.proveedor_id
                   FROM wd
                  WHERE wd.tipo_paso = 'proveedor_servicio'::text AND wd.proveedor_id IS NOT NULL
                UNION
                 SELECT n.comp_id,
                    s_1.comp,
                    s_1.proveedor_id
                   FROM nodos n
                     JOIN selfsrv s_1 ON s_1.comp = n.nodo) z
             LEFT JOIN "GP2".precio_servicio_pieza pz ON pz.proveedor_servicio_id = z.proveedor_id AND pz.componente_id = z.pieza
             LEFT JOIN "GP2".componente cz ON cz.id = z.pieza
             LEFT JOIN "GP2".tarifa_servicio ts ON ts.proveedor_servicio_id = z.proveedor_id AND ts.proceso = pz.proceso
          GROUP BY z.comp_id
        ), bomx AS (
         SELECT b.componente_padre_id AS comp_id,
            COALESCE(sum(b.cantidad * pc.precio) FILTER (WHERE pc.moneda = 'USD'::text), 0::numeric) AS usd,
            COALESCE(sum(b.cantidad * pc.precio) FILTER (WHERE pc.moneda = 'ARS'::text), 0::numeric) AS ars,
            count(*) FILTER (WHERE pc.precio IS NULL) AS sin_precio
           FROM "GP2".componente_bom b
             JOIN "GP2".componente ch ON ch.id = b.componente_hijo_id
             LEFT JOIN pc ON pc.componente_id = ch.id
          WHERE (EXISTS ( SELECT 1
                   FROM "GP2".sector s9
                  WHERE s9.id = ch.sector_id AND s9.es_insumo AND s9.id <> 5)) AND NOT (EXISTS ( SELECT 1
                   FROM edges e
                  WHERE e.ent = b.componente_hijo_id AND e.sal = b.componente_padre_id))
          GROUP BY b.componente_padre_id
        ), insumo_por_art AS (
         SELECT x.art_id,
            x.insumo_id,
            max(x.cantidad) AS cantidad
           FROM ( SELECT rp_ins.comp_entrada_id AS insumo_id,
                    rp_ins.cantidad,
                    ( SELECT rp2.comp_salida_id
                           FROM "GP2".ruta_paso rp2
                          WHERE rp2.ruta_id = rp_ins.ruta_id AND rp2.comp_salida_id IS NOT NULL AND rp2.tipo_paso <> 'virgilio'::text
                          ORDER BY rp2.orden DESC
                         LIMIT 1) AS art_id
                   FROM "GP2".ruta_paso rp_ins
                  WHERE rp_ins.tipo_paso = 'insumo'::text AND rp_ins.comp_entrada_id IS NOT NULL) x
          WHERE x.art_id IS NOT NULL
          GROUP BY x.art_id, x.insumo_id
        ), insumox AS (
         SELECT y.art_id AS comp_id,
            COALESCE(sum(y.cantidad * pc.precio) FILTER (WHERE pc.moneda = 'USD'::text), 0::numeric) AS usd,
            COALESCE(sum(y.cantidad * pc.precio) FILTER (WHERE pc.moneda = 'ARS'::text), 0::numeric) AS ars,
            count(*) FILTER (WHERE pc.precio IS NULL AND NOT (EXISTS ( SELECT 1
                   FROM edges e
                  WHERE e.sal = y.insumo_id))) AS sin_precio
           FROM insumo_por_art y
             LEFT JOIN pc ON pc.componente_id = y.insumo_id
          GROUP BY y.art_id
        ), talpieza AS (
         SELECT DISTINCT ON (n.comp_id, n.comp) n.comp_id,
            n.comp,
            COALESCE(pt.precio_kg * cpt.kg_x_uni, pt.precio_uni) AS precio,
                CASE
                    WHEN upper(COALESCE(pt.moneda, 'ARS'::text)) ~~ '%US%'::text THEN 'USD'::text
                    ELSE 'ARS'::text
                END AS moneda
           FROM ( SELECT DISTINCT n0.comp_id,
                    t.comp,
                    t.tallerista_id
                   FROM "GP2".ruta_paso rp0
                     JOIN LATERAL ( SELECT rp0.comp_salida_id AS comp,
                            rp0.tallerista_id) t ON true
                     JOIN ( SELECT nodos.comp_id,
                            nodos.nodo
                           FROM nodos) n0 ON n0.nodo = t.comp
                  WHERE rp0.tipo_paso = 'tallerista'::text AND rp0.tallerista_id IS NOT NULL AND rp0.comp_salida_id IS NOT NULL) n
             JOIN "GP2".precio_tallerista pt ON pt.tallerista_id = n.tallerista_id AND pt.componente_id = n.comp
             LEFT JOIN "GP2".componente cpt ON cpt.id = pt.componente_id
          ORDER BY n.comp_id, n.comp, (COALESCE(pt.precio_kg * cpt.kg_x_uni, pt.precio_uni)) DESC NULLS LAST
        ), talx AS (
         SELECT tp.comp_id,
            COALESCE(sum(tp.precio) FILTER (WHERE tp.moneda = 'USD'::text), 0::numeric) AS usd,
            COALESCE(sum(tp.precio) FILTER (WHERE tp.moneda = 'ARS'::text), 0::numeric) AS ars
           FROM talpieza tp
          GROUP BY tp.comp_id
        )
 SELECT c.id AS comp_id,
    c.codigo,
    c.descripcion,
    c.sector_id,
    s.nombre AS sector,
    s.tipo AS sector_tipo,
        CASE
            WHEN cb.id IS NOT NULL THEN 'precio'::text
            ELSE 'ruta'::text
        END AS origen,
        CASE
            WHEN cb.id IS NOT NULL THEN
            CASE
                WHEN cb.moneda = 'USD'::text THEN COALESCE(cb.precio, 0::numeric)
                ELSE 0::numeric
            END
            ELSE COALESCE(mat.usd, 0::numeric) + COALESCE(bx.usd, 0::numeric) + COALESCE(ix.usd, 0::numeric)
        END AS material_usd,
        CASE
            WHEN cb.id IS NOT NULL THEN
            CASE
                WHEN cb.moneda = 'ARS'::text THEN COALESCE(cb.precio, 0::numeric)
                ELSE 0::numeric
            END
            ELSE COALESCE(mat.ars, 0::numeric) + COALESCE(bx.ars, 0::numeric) + COALESCE(ix.ars, 0::numeric)
        END AS material_pesos,
        CASE
            WHEN cb.id IS NOT NULL THEN 0::numeric
            ELSE COALESCE(srv.usd, 0::numeric) + COALESCE(tx.usd, 0::numeric)
        END AS servicios_usd,
        CASE
            WHEN cb.id IS NOT NULL THEN 0::numeric
            ELSE COALESCE(srv.ars, 0::numeric) + COALESCE(tx.ars, 0::numeric)
        END AS servicios_pesos,
        CASE
            WHEN cb.id IS NOT NULL THEN 0::numeric
            ELSE COALESCE(lab.segundos, 0::numeric)
        END AS segundos_matriz,
        CASE
            WHEN cb.id IS NOT NULL THEN 0::numeric
            ELSE round(COALESCE(lab.segundos, 0::numeric) * COALESCE(par.costo_seg, 0::numeric), 4)
        END AS mano_obra_pesos,
        CASE
            WHEN par.tc IS NULL THEN NULL::numeric
            ELSE round(
            CASE
                WHEN cb.id IS NOT NULL THEN
                CASE
                    WHEN cb.moneda = 'USD'::text THEN COALESCE(cb.precio, 0::numeric)
                    ELSE 0::numeric
                END
                ELSE COALESCE(mat.usd, 0::numeric) + COALESCE(bx.usd, 0::numeric) + COALESCE(ix.usd, 0::numeric) + COALESCE(srv.usd, 0::numeric) + COALESCE(tx.usd, 0::numeric)
            END * par.tc +
            CASE
                WHEN cb.id IS NOT NULL THEN
                CASE
                    WHEN cb.moneda = 'ARS'::text THEN COALESCE(cb.precio, 0::numeric)
                    ELSE 0::numeric
                END
                ELSE COALESCE(mat.ars, 0::numeric) + COALESCE(bx.ars, 0::numeric) + COALESCE(ix.ars, 0::numeric) + COALESCE(srv.ars, 0::numeric) + COALESCE(tx.ars, 0::numeric) + round(COALESCE(lab.segundos, 0::numeric) * COALESCE(par.costo_seg, 0::numeric), 4)
            END, 2)
        END AS total_pesos,
        CASE
            WHEN cb.id IS NOT NULL THEN (cb.precio IS NULL)::integer::bigint
            ELSE COALESCE(mat.sin_precio, 0::bigint) + COALESCE(srv.sin_precio, 0::bigint) + COALESCE(bx.sin_precio, 0::bigint) + COALESCE(ix.sin_precio, 0::bigint)
        END AS faltan_precios,
        CASE
            WHEN cb.id IS NOT NULL THEN 0::bigint
            ELSE COALESCE(mat.sin_kg, 0::bigint)
        END AS faltan_kg,
        CASE
            WHEN cb.id IS NOT NULL THEN 0::bigint
            ELSE COALESCE(lab.sin_tiempo, 0::bigint)
        END AS faltan_tiempos
   FROM "GP2".componente c
     JOIN "GP2".sector s ON s.id = c.sector_id
     CROSS JOIN par
     LEFT JOIN comprado cb ON cb.id = c.id
     LEFT JOIN mat ON mat.comp_id = c.id AND cb.id IS NULL
     LEFT JOIN lab ON lab.comp_id = c.id AND cb.id IS NULL
     LEFT JOIN srv ON srv.comp_id = c.id AND cb.id IS NULL
     LEFT JOIN bomx bx ON bx.comp_id = c.id AND cb.id IS NULL
     LEFT JOIN insumox ix ON ix.comp_id = c.id AND cb.id IS NULL
     LEFT JOIN talx tx ON tx.comp_id = c.id AND cb.id IS NULL;

-- ---------- v_faltante_estado ----------
create or replace view "GP2".v_faltante_estado as
 WITH umbral AS (
         SELECT COALESCE(( SELECT parametro.valor
                   FROM "GP2".parametro
                  WHERE parametro.clave = 'faltante_cajones_umbral'::text), 1::numeric) AS caj
        )
 SELECT c.id AS componente_id,
    c.codigo,
    c.descripcion,
    c.sector_id,
    s.nombre AS sector,
    i.cantidad AS stock_uni,
    c.uni_x_cajon,
        CASE
            WHEN c.uni_x_cajon > 0::numeric THEN round(i.cantidad / c.uni_x_cajon, 2)
            ELSE NULL::numeric
        END AS cajones_stock,
    COALESCE(cp.consumo_uni_mes, 0::numeric) AS consumo_uni_mes,
    i.maximo,
    i.maximo_origen,
        CASE
            WHEN COALESCE(cp.consumo_uni_mes, 0::numeric) > 0::numeric THEN round(i.cantidad / (cp.consumo_uni_mes / 30.0), 1)
            ELSE NULL::numeric
        END AS cobertura_dias,
        CASE
            WHEN COALESCE(cp.consumo_uni_mes, 0::numeric) > 0::numeric AND i.maximo IS NOT NULL THEN round(i.maximo / (cp.consumo_uni_mes / 30.0), 1)
            ELSE NULL::numeric
        END AS cobertura_llena_dias,
    c.uni_x_cajon > 0::numeric AND i.cantidad < (u2.caj * c.uni_x_cajon) AS faltante_auto,
    u2.caj AS umbral_cajones,
    COALESCE(cp.consumo_uni_mes, 0::numeric) > 0::numeric AND i.maximo IS NOT NULL AND (i.maximo / (cp.consumo_uni_mes / 30.0)) < 30::numeric AS ubicacion_corta
   FROM "GP2".componente c
     JOIN "GP2".sector s ON s.id = c.sector_id
     JOIN "GP2".inventario i ON i.componente_id = c.id AND i.ubicacion_id = "GP2".ubic_de('sector'::text, c.sector_id)
     LEFT JOIN "GP2".v_consumo_componente cp ON cp.componente_id = c.id
     CROSS JOIN umbral u2
  WHERE c.sector_id = ANY (ARRAY[1::bigint, 2::bigint]);

-- ---------- v_nivel_stock ----------
create or replace view "GP2".v_nivel_stock as
 SELECT i.id AS inv_id,
    i.componente_id,
    i.ubicacion_id,
    c.sector_id,
    COALESCE(
        CASE
            WHEN c.sector_id = 5 THEN fk.consumo_kg_mes
            ELSE cp.consumo_uni_mes
        END, 0::numeric) AS consumo_mes,
    u.meses_stock,
    u.meses_minimo,
    round(COALESCE(
        CASE
            WHEN c.sector_id = 5 THEN fk.consumo_kg_mes
            ELSE cp.consumo_uni_mes
        END, 0::numeric) * u.meses_stock) AS max_calc,
    round(COALESCE(
        CASE
            WHEN c.sector_id = 5 THEN fk.consumo_kg_mes
            ELSE cp.consumo_uni_mes
        END, 0::numeric) * u.meses_minimo) AS min_calc,
    "GP2"._es_sector_insumo(u.ref_id) AS es_insumo,
    i.maximo,
    i.maximo_origen,
    i.minimo,
    i.minimo_origen
   FROM "GP2".inventario i
     JOIN "GP2".ubicacion u ON u.id = i.ubicacion_id AND u.tipo = 'sector'::text
     JOIN "GP2".componente c ON c.id = i.componente_id AND c.sector_id = u.ref_id
     LEFT JOIN "GP2".v_consumo_fleje_kg fk ON fk.componente_id = c.id AND c.sector_id = 5
     LEFT JOIN "GP2".v_consumo_componente cp ON cp.componente_id = c.id AND c.sector_id <> 5;
comment on view "GP2".v_nivel_stock is 'Consumo mensual (Est Madre explotada) por fila de inventario de SECTOR y los niveles que salen de el: max_calc = consumo x meses_stock, min_calc = consumo x meses_minimo. Unica definicion (2026-09-05); la usan recalcular_maximos_insumos y recalcular_minimos.';

-- ---------- v_recepcion_control ----------
create or replace view "GP2".v_recepcion_control as
 WITH a AS (
         SELECT v_control_pallet.recepcion_id,
            count(*) AS pallets_pesados,
            sum(v_control_pallet.rollos) AS rollos_contados,
            sum(v_control_pallet.kg_rollos) AS kg_rollos,
            sum(v_control_pallet.peso_balanza) AS peso_balanza_total,
            count(*) FILTER (WHERE v_control_pallet.estado <> 'ok'::text) AS pallets_con_problema,
            string_agg(DISTINCT v_control_pallet.estado, ', '::text) FILTER (WHERE v_control_pallet.estado <> 'ok'::text) AS problemas
           FROM "GP2".v_control_pallet
          GROUP BY v_control_pallet.recepcion_id
        )
 SELECT ri.id AS recepcion_id,
    ri.fecha,
    ri.proveedor,
    ri.remito,
    c.codigo,
    c.descripcion,
    ri.cantidad AS kg_remito,
    ri.rollos AS rollos_remito,
    ri.pallets AS pallets_remito,
    COALESCE(a.pallets_pesados, 0::bigint) AS pallets_pesados,
    COALESCE(a.rollos_contados, 0::numeric) AS rollos_contados,
    COALESCE(a.kg_rollos, 0::numeric) AS kg_rollos,
    a.peso_balanza_total,
    COALESCE(ri.rollos, 0)::numeric - COALESCE(a.rollos_contados, 0::numeric) AS rollos_sin_clasificar,
    COALESCE(ri.pallets, 0) - COALESCE(a.pallets_pesados, 0::bigint) AS pallets_sin_pesar,
    COALESCE(a.kg_rollos, 0::numeric) - ri.cantidad AS dif_kg_vs_remito,
    COALESCE(a.pallets_con_problema, 0::bigint) AS pallets_con_problema,
    a.problemas,
        CASE
            WHEN c.sector_id <> 5 THEN 'ok'::text
            WHEN a.recepcion_id IS NULL THEN 'sin controlar'::text
            WHEN ri.pallets IS NOT NULL AND (COALESCE(ri.pallets, 0) - COALESCE(a.pallets_pesados, 0::bigint)) <> 0 THEN 'faltan pallets por pesar'::text
            WHEN ri.rollos IS NOT NULL AND (COALESCE(ri.rollos, 0)::numeric - COALESCE(a.rollos_contados, 0::numeric)) <> 0::numeric THEN 'rollos sin clasificar'::text
            WHEN COALESCE(a.pallets_con_problema, 0::bigint) > 0 THEN a.problemas
            ELSE 'ok'::text
        END AS estado
   FROM "GP2".recepcion_insumo ri
     JOIN "GP2".componente c ON c.id = ri.componente_id
     LEFT JOIN a ON a.recepcion_id = ri.id;

-- ---------- v_recepcion_unificada ----------
create or replace view "GP2".v_recepcion_unificada as
 SELECT 'insumo'::text AS origen,
    ri.id,
    ri.fecha AS fecha_recepcion,
    ri.remito,
    ri.proveedor AS nombre_prov,
    pi.cod_prov,
    c.codigo AS cod_isis,
    COALESCE(c.descripcion, ri.proveedor, ''::text) AS descripcion,
    ri.cantidad,
    COALESCE(ri.unidad, 'uni'::text) AS unidad,
    NULL::text AS numero_factura,
    NULL::date AS fecha_factura,
    COALESCE(ri.controlado, false) AS controlado
   FROM "GP2".recepcion_insumo ri
     LEFT JOIN "GP2".componente c ON c.id = ri.componente_id
     LEFT JOIN "GP2".proveedor_insumo pi ON pi.nombre = ri.proveedor
UNION ALL
 SELECT 'tallerista'::text AS origen,
    ea.id,
    COALESCE(ea.fecha_rto::timestamp with time zone, ea.creado_en) AS fecha_recepcion,
    ea.remito,
    pa.nombre AS nombre_prov,
    pa.cod_prov,
    ea.cod_art AS cod_isis,
    COALESCE(ea.descripcion, ''::text) AS descripcion,
    ea.cantidad_cajas::numeric AS cantidad,
    'cajas'::text AS unidad,
    ea.numero_factura,
    ea.fecha_factura,
    ea.numero_factura IS NOT NULL AS controlado
   FROM "GP2".entrega_prov_at ea
     LEFT JOIN "GP2".proveedor_at pa ON pa.id = ea.proveedor_at_id;

-- ---------- v_rollo_evolucion ----------
create or replace view "GP2".v_rollo_evolucion as
 SELECT e.id,
    e.fecha,
    e.componente_id,
    c.codigo,
    e.kg_por_rollo,
    e.delta,
    e.motivo,
    e.legajo,
    emp.nombre AS operario,
    e.nota,
    sum(e.delta) OVER (PARTITION BY e.componente_id, e.kg_por_rollo ORDER BY e.fecha, e.id) AS saldo
   FROM "GP2".rollo_evento e
     JOIN "GP2".componente c ON c.id = e.componente_id
     LEFT JOIN "GP2".empleado emp ON emp.legajo = e.legajo;

-- ---------- v_rollo_saldo ----------
create or replace view "GP2".v_rollo_saldo as
 SELECT e.componente_id,
    c.codigo,
    c.descripcion,
    e.kg_por_rollo,
    sum(e.delta) AS rollos,
    sum(e.delta)::numeric * e.kg_por_rollo AS kg_total,
    sum(e.delta) FILTER (WHERE e.delta > 0) AS ingresos,
    - sum(e.delta) FILTER (WHERE e.delta < 0) AS egresos,
    max(e.fecha) AS ultimo_mov
   FROM "GP2".rollo_evento e
     JOIN "GP2".componente c ON c.id = e.componente_id
  GROUP BY e.componente_id, c.codigo, c.descripcion, e.kg_por_rollo;

-- ---------- v_tara_pallet_real ----------
create or replace view "GP2".v_tara_pallet_real as
 SELECT rc.id AS control_id,
    ri.proveedor,
    rc.controlado_en,
    rc.peso_balanza - COALESCE(( SELECT sum(cr.cantidad::numeric * cr.kg_por_rollo) AS sum
           FROM "GP2".recepcion_control_rollo cr
          WHERE cr.control_id = rc.id), 0::numeric) AS tara
   FROM "GP2".recepcion_control rc
     JOIN "GP2".recepcion_insumo ri ON ri.id = rc.recepcion_id
  WHERE (EXISTS ( SELECT 1
           FROM "GP2".recepcion_control_rollo cr
          WHERE cr.control_id = rc.id));
comment on view "GP2".v_tara_pallet_real is 'Tara real por pallet pesado (balanza - suma de rollos). Alimenta la tara aprendida del bundle de recepcion.';
