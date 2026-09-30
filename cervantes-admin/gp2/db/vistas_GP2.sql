-- =====================================================================
-- VISTAS del schema GP2 (pg_get_viewdef, exacto) — export automatico 2026-09-11 desde Supabase (hrxfctzncixxqmpfhskv)
-- Respaldo/referencia. La fuente de verdad es la base; regenerar al cambiar el schema.
-- 32 vistas (2026-09-26: + v_oc_virgilio_pendiente, v_oc_virgilio_partes, v_oc_virgilio_demanda, v_oc_virgilio_partes_tallerista; el orden de dependencia es pendiente -> demanda -> partes_tallerista). Orden de creacion: las que dependen de otra van despues.
-- =====================================================================

-- ---------- v_caj_contraparte ----------
create or replace view "GP2".v_caj_contraparte as
 WITH ing AS (
         SELECT m.ubic_destino_id AS ubicacion_id,
            m.comp_id AS componente_id,
            sum(COALESCE(m._delta_dest, 0::numeric)) AS uni,
            sum(m.cajones) AS cajones,
            count(*) AS n_envios,
            max(m.fecha) AS ultimo
           FROM "GP2".movimiento m
             JOIN "GP2".ubicacion u ON u.id = m.ubic_destino_id
          WHERE (u.tipo = ANY (ARRAY['proveedor_servicio'::text, 'tallerista'::text])) AND m.comp_transformado_id IS NULL AND COALESCE(m.cajones, 0::numeric) > 0::numeric AND COALESCE(m._delta_dest, 0::numeric) > 0::numeric
          GROUP BY m.ubic_destino_id, m.comp_id
        )
 SELECT ubicacion_id,
    componente_id,
    uni,
    cajones,
    n_envios,
    ultimo,
    uni / cajones AS uni_x_cajon_anotado
   FROM ing;
comment on view "GP2".v_caj_contraparte is 'CUANTO MIDE EL CAJON QUE ANOTO LOGISTICA, por (ubicacion de la contraparte, componente). uni_x_cajon_anotado = unidades enviadas / cajones anotados en movimiento.cajones, sobre los envios a esa contraparte de esa pieza. Sirve para decir el stock en poder del tercero EN LOS CAJONES QUE SE MANDARON y no en el cajon teorico de componente.uni_x_cajon [usuario 2026-09-21: "tiene que aparecer en su stock los cajones que escribe logistica, no los que se calcula a partir de los kg"]. Caso que lo motivo: CV1 a Guazzaroni, 1 cajon de 21 kg anotado contra un uni_x_cajon de 20 kg -> la recepcion decia 1,05 cajones. Solo mira movimientos con cajones anotados (> 0): donde nadie los anota (hoy los talleristas, que no tienen p_cajones) no hay fila y el que consulta cae al cajon del maestro.';

-- ---------- v_carton_sustituto_saldo ----------
create or replace view "GP2".v_carton_sustituto_saldo as
 WITH mov AS (
         SELECT COALESCE(m.ubic_destino_id, m.ubic_origen_id) AS ubicacion_id,
            m.sustituye_comp_id AS oficial_id,
            m.comp_id AS sustituto_id,
                CASE
                    WHEN m.tipo_mov = ANY (ARRAY['envio_prov_at'::text, 'envio_tallerista'::text]) THEN m.cantidad
                    ELSE - m.cantidad
                END AS q,
            m.fecha
           FROM "GP2".movimiento m
          WHERE m.sustituye_comp_id IS NOT NULL
        )
 SELECT ubicacion_id,
    oficial_id,
    sustituto_id,
    sum(q) AS saldo,
    min(fecha) AS desde
   FROM mov
  GROUP BY ubicacion_id, oficial_id, sustituto_id
 HAVING sum(q) > 0::numeric;
comment on view "GP2".v_carton_sustituto_saldo is 'Cartones sustitutos con saldo sin consumir, por ubicacion de destino. Lo usa recepcion_virgilio: al recibir el articulo terminado gasta primero el sustituto y el resto el carton oficial. Sale del ledger (movimiento.sustituye_comp_id), no de una tabla aparte.';

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
            sum(em.proy_uni_mes) AS uni
           FROM "GP2".articulo a
             JOIN LATERAL ( SELECT regexp_replace(a.codigo, '^0+'::text, ''::text) AS k
                UNION
                 SELECT regexp_replace(f.cod_secundario, '^0+'::text, ''::text) AS regexp_replace
                   FROM "GP2".articulo_familia f
                  WHERE regexp_replace(f.cod_principal, '^0+'::text, ''::text) = regexp_replace(a.codigo, '^0+'::text, ''::text)) k ON true
             JOIN "GP2".est_madre em ON regexp_replace(regexp_replace(em.cod, 'L$'::text, ''::text), '^0+'::text, ''::text) = k.k
          WHERE em.proy_uni_mes IS NOT NULL AND NOT a.discontinuado AND NOT (EXISTS ( SELECT 1
                   FROM "GP2".articulo_familia f2
                  WHERE regexp_replace(f2.cod_secundario, '^0+'::text, ''::text) = regexp_replace(a.codigo, '^0+'::text, ''::text)))
          GROUP BY a.id
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
            m.partes_por_kilo_de_fleje AS ppk,
            NULL::numeric AS kgxuni
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
             JOIN "GP2".componente ce ON ce.id = rp.comp_entrada_id AND ce.sector_id = 5
             JOIN "GP2".matriz m ON m.id = rp.matriz_id
          WHERE r.articulo_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL AND COALESCE(m.partes_por_kilo_de_fleje, 0::numeric) > 0::numeric
        UNION ALL
         SELECT DISTINCT r.articulo_id,
            rp.comp_entrada_id,
            rp.comp_salida_id,
            NULL::numeric AS "numeric",
                CASE
                    WHEN ce.unidad_medida = 'kg'::text AND ce.kg_x_uni = 1::numeric AND COALESCE(cs.kg_x_uni, 0::numeric) > 0::numeric THEN cs.kg_x_uni
                    ELSE ce.kg_x_uni
                END AS kg_x_uni
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
             JOIN "GP2".componente ce ON ce.id = rp.comp_entrada_id AND ce.sector_id = 5
             JOIN "GP2".componente cs ON cs.id = rp.comp_salida_id
             LEFT JOIN "GP2".matriz m ON m.id = rp.matriz_id
          WHERE r.articulo_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL AND rp.comp_salida_id <> rp.comp_entrada_id AND rp.tipo_paso <> 'ingreso'::text AND COALESCE(m.partes_por_kilo_de_fleje, 0::numeric) = 0::numeric AND COALESCE(ce.kg_x_uni, 0::numeric) > 0::numeric
        )
 SELECT f.id AS componente_id,
    f.codigo,
    f.descripcion,
    round(sum(
        CASE
            WHEN p.ppk IS NOT NULL THEN d.uni_mes / p.ppk
            ELSE d.uni_mes * p.kgxuni
        END), 1) AS consumo_kg_mes,
    count(*) AS piezas
   FROM paso p
     JOIN "GP2".v_consumo_demanda d ON d.articulo_id = p.art_id AND d.componente_id = p.sal
     JOIN "GP2".componente f ON f.id = p.fleje_id
  GROUP BY f.id, f.codigo, f.descripcion;
comment on view "GP2".v_consumo_fleje_kg is 'Kg/mes de fleje. Igual que v_consumo_fleje_kg pero tomando la demanda atribuida por articulo (v_consumo_demanda) en vez del consumo entero del primer nodo aguas abajo.';

-- ---------- v_consumo_prov_at ----------
create or replace view "GP2".v_consumo_prov_at as
 SELECT re.proveedor_at_id,
    ac.componente_id,
    sum(d.uni_mes * re.pct / 100::numeric) AS uni_mes,
    bool_or(re.es_supuesto) AS tiene_supuesto
   FROM "GP2".v_reparto_at_efectivo re
     JOIN "GP2".articulo_componente ac ON ac.articulo_id = re.articulo_id
     JOIN "GP2".componente c ON c.id = ac.componente_id AND (c.sector_id = ANY (ARRAY[10::bigint, 11::bigint])) AND NOT COALESCE(c.discontinuado, false)
     JOIN "GP2".v_consumo_demanda d ON d.articulo_id = re.articulo_id AND d.componente_id = ac.componente_id
  GROUP BY re.proveedor_at_id, ac.componente_id;
comment on view "GP2".v_consumo_prov_at is 'Consumo uni/mes de carton y caja por (prov AT, componente), con la demanda del articulo repartida por v_reparto_at_efectivo. El espejo de v_consumo_tallerista para el proveedor de articulo terminado.';

-- ---------- v_consumo_tallerista ----------
create or replace view "GP2".v_consumo_tallerista as
 WITH pasos AS (
         SELECT DISTINCT r.articulo_id,
            rp.comp_entrada_id,
            rp.comp_salida_id,
            rp.tallerista_id
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
          WHERE rp.tallerista_id IS NOT NULL AND rp.comp_entrada_id IS NOT NULL AND r.articulo_id IS NOT NULL
        )
 SELECT p.tallerista_id,
    p.comp_entrada_id AS componente_id,
    sum(d.uni_mes * re.pct / 100::numeric) AS uni_mes,
    bool_or(re.es_supuesto) AS tiene_supuesto
   FROM pasos p
     JOIN "GP2".v_consumo_demanda d ON d.articulo_id = p.articulo_id AND d.componente_id = p.comp_entrada_id
     JOIN "GP2".v_reparto_efectivo re ON re.articulo_id = p.articulo_id AND re.comp_salida_id = p.comp_salida_id AND re.tallerista_id = p.tallerista_id
  GROUP BY p.tallerista_id, p.comp_entrada_id;
comment on view "GP2".v_consumo_tallerista is 'Consumo uni/mes por (tallerista, componente que recibe), con la demanda del articulo repartida por v_reparto_efectivo. El equivalente de v_consumo_componente pero del lado del tallerista.';

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

-- ---------- v_componente_muerto ----------
-- Un componente esta MUERTO cuando pertenece a algun articulo DISCONTINUADO (por ruta o receta)
-- y NO pertenece a ningun articulo ACTIVO (ni por ruta ni por receta). Si se usa en un activo,
-- no aparece aca y se conserva. [2026-09-24, dueno: la regla vale para insumo, prov AT, prov
-- servicio y tallerista, envio y recepcion; del programa no se hace nada mas con estos componentes.]
create or replace view "GP2".v_componente_muerto as
 SELECT id AS comp_id
   FROM "GP2".componente c
  WHERE ((EXISTS ( SELECT 1
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
             JOIN "GP2".articulo a ON a.id = r.articulo_id
          WHERE a.discontinuado AND (rp.comp_entrada_id = c.id OR rp.comp_salida_id = c.id))) OR (EXISTS ( SELECT 1
           FROM "GP2".articulo_componente ac
             JOIN "GP2".articulo a ON a.id = ac.articulo_id
          WHERE a.discontinuado AND ac.componente_id = c.id))) AND NOT (EXISTS ( SELECT 1
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
             JOIN "GP2".articulo a ON a.id = r.articulo_id
          WHERE NOT COALESCE(a.discontinuado, false) AND (rp.comp_entrada_id = c.id OR rp.comp_salida_id = c.id))) AND NOT (EXISTS ( SELECT 1
           FROM "GP2".articulo_componente ac
             JOIN "GP2".articulo a ON a.id = ac.articulo_id
          WHERE NOT COALESCE(a.discontinuado, false) AND ac.componente_id = c.id));
comment on view "GP2".v_componente_muerto is 'Componentes que solo pertenecen a articulos discontinuados (ni ruta ni receta de un activo los usa). Los bundles de envio/recepcion/OC (tallerista, PS, prov AT, insumos, tablet) los excluyen para que no se pueda operar con ellos. 2026-09-24.';

-- ---------- v_control_pallet ----------
create or replace view "GP2".v_control_pallet as
 WITH p AS (
         SELECT max(parametro.valor) FILTER (WHERE parametro.clave = 'tara_pallet_min'::text) AS tmin,
            max(parametro.valor) FILTER (WHERE parametro.clave = 'tara_pallet_max'::text) AS tmax,
            max(parametro.valor) FILTER (WHERE parametro.clave = 'tol_ctrl_pct'::text) AS tolpct
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
                WHEN abs(ctl.peso_balanza - ri.cantidad) <= GREATEST(ri.cantidad * COALESCE(p.tolpct, 5::numeric) / 100.0, 0.5) THEN 'ok'::text
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
             JOIN "GP2".componente cc9 ON cc9.id = precio_proveedor.componente_id
             LEFT JOIN "GP2".proveedor_insumo pi9 ON pi9.nombre = cc9.proveedor
          WHERE precio_proveedor.componente_id IS NOT NULL AND precio_proveedor.precio IS NOT NULL
          ORDER BY precio_proveedor.componente_id, (pi9.cod_prov IS NOT NULL AND precio_proveedor.cod_prov = pi9.cod_prov) DESC, precio_proveedor.fecha_lista DESC NULLS LAST, precio_proveedor.id DESC
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
                            ELSE cb_1.precio * LEAST(COALESCE(ipa.cantidad, 1::numeric), 1::numeric)
                        END AS val
                   FROM wd
                     JOIN comprado cb_1 ON cb_1.id = wd.ent
                     LEFT JOIN "GP2".matriz m ON m.id = wd.matriz_id
                     LEFT JOIN insumo_por_art ipa ON ipa.art_id = wd.comp_id AND ipa.insumo_id = wd.ent) x
          GROUP BY x.comp_id
        ), lab AS (
         SELECT y.comp_id,
            COALESCE(sum(
                CASE
                    WHEN m.tiempo_unidad = 'kg'::text THEN m.tiempo_historico * cm.kg_x_uni
                    ELSE m.tiempo_historico
                END), 0::numeric) AS segundos,
            count(*) FILTER (WHERE COALESCE(m.tiempo_historico, 0::numeric) <= 0::numeric) AS sin_tiempo
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
        ), insumox AS (
         SELECT y.art_id AS comp_id,
            COALESCE(sum(
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM edges e
                      WHERE e.ent = y.insumo_id)) THEN GREATEST(y.cantidad - 1::numeric, 0::numeric) * pc.precio
                    ELSE y.cantidad * pc.precio
                END) FILTER (WHERE pc.moneda = 'USD'::text), 0::numeric) AS usd,
            COALESCE(sum(
                CASE
                    WHEN (EXISTS ( SELECT 1
                       FROM edges e
                      WHERE e.ent = y.insumo_id)) THEN GREATEST(y.cantidad - 1::numeric, 0::numeric) * pc.precio
                    ELSE y.cantidad * pc.precio
                END) FILTER (WHERE pc.moneda = 'ARS'::text), 0::numeric) AS ars,
            count(*) FILTER (WHERE pc.precio IS NULL AND NOT (EXISTS ( SELECT 1
                   FROM edges e
                  WHERE e.sal = y.insumo_id)) AND NOT (EXISTS ( SELECT 1
                   FROM edges e
                  WHERE e.ent = y.insumo_id))) AS sin_precio
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
comment on view "GP2".v_costo_componente is 'Costo por componente (material + servicios + mano de obra). El precio de un insumo sale del proveedor ASIGNADO al componente (componente.proveedor), igual que en oc_bundle/crear_oc; si no hay, el mas nuevo por fecha_lista. Unica regla de precio en la base (2026-09-11).';

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
    ((i.maximo IS NOT NULL) AND (i.cantidad < i.maximo)) AS faltante_auto,
    u2.caj AS umbral_cajones,
    COALESCE(cp.consumo_uni_mes, 0::numeric) > 0::numeric AND i.maximo IS NOT NULL AND (i.maximo / (cp.consumo_uni_mes / 30.0)) < 30::numeric AS ubicacion_corta
   FROM "GP2".componente c
     JOIN "GP2".sector s ON s.id = c.sector_id
     JOIN "GP2".inventario i ON i.componente_id = c.id AND i.ubicacion_id = "GP2".ubic_de('sector'::text, c.sector_id)
     LEFT JOIN "GP2".v_consumo_componente cp ON cp.componente_id = c.id
     CROSS JOIN umbral u2
  WHERE c.sector_id = ANY (ARRAY[1::bigint, 2::bigint]);
comment on view "GP2".v_faltante_estado is 'Faltantes de Crudo/Procesado. faltante_auto = stock < maximo (usuario 2026-09-29; antes < 1 cajon). ubicacion_corta = el maximo no cubre 30 dias de consumo (con el tope de 5 cajones pasa en las piezas de mucho consumo).';

-- ---------- v_hace_articulo ----------
create or replace view "GP2".v_hace_articulo as
 SELECT DISTINCT r.articulo_id,
    'proveedor_at'::text AS tipo,
    rp.proveedor_at_id AS ref_id
   FROM "GP2".ruta_paso rp
     JOIN "GP2".ruta r ON r.id = rp.ruta_id
  WHERE rp.tipo_paso = 'proveedor_at'::text AND rp.proveedor_at_id IS NOT NULL AND r.articulo_id IS NOT NULL AND (EXISTS ( SELECT 1
           FROM "GP2".proveedor_at p
          WHERE p.id = rp.proveedor_at_id AND COALESCE(p.activo, true)))
UNION
 SELECT DISTINCT a.id AS articulo_id,
    'proveedor_at'::text AS tipo,
    apa.proveedor_at_id AS ref_id
   FROM "GP2".articulo_prov_at apa
     JOIN "GP2".articulo a ON a.codigo = apa.cod_art
  WHERE COALESCE(apa.activo, true) AND NOT COALESCE(a.discontinuado, false) AND (EXISTS ( SELECT 1
           FROM "GP2".proveedor_at p
          WHERE p.id = apa.proveedor_at_id AND COALESCE(p.activo, true)))
UNION
 SELECT DISTINCT r.articulo_id,
    'tallerista'::text AS tipo,
    rp.tallerista_id AS ref_id
   FROM "GP2".ruta_paso rp
     JOIN "GP2".ruta r ON r.id = rp.ruta_id
     JOIN "GP2".componente c ON c.id = rp.comp_salida_id AND c.sector_id = 12
  WHERE rp.tipo_paso = 'tallerista'::text AND rp.tallerista_id IS NOT NULL AND r.articulo_id IS NOT NULL;
comment on view "GP2".v_hace_articulo is 'Quien produce o entrega el ARTICULO TERMINADO: prov AT (por su paso de ruta o por el padron articulo_prov_at) y tallerista (paso cuya salida es sector 12). Es el denominador del reparto: "mas de un prov AT o tallerista que haga un articulo" [usuario 2026-09-23].';

-- ---------- v_material_inyector ----------
create or replace view "GP2".v_material_inyector as
 WITH pct AS (
         SELECT COALESCE(( SELECT parametro.valor
                   FROM "GP2".parametro
                  WHERE parametro.clave = 'inyeccion_desperdicio_pct'::text), 0::numeric) AS p
        ), bolsa AS (
         SELECT COALESCE(( SELECT parametro.valor
                   FROM "GP2".parametro
                  WHERE parametro.clave = 'material_plastico_kg_x_bolsa'::text), 25::numeric) AS kg
        ), iny AS (
         SELECT pi.id AS prov_id,
            pi.nombre AS proveedor,
            u.id AS ubic_id
           FROM "GP2".proveedor_insumo pi
             JOIN "GP2".ubicacion u ON u.tipo = 'inyector'::text AND u.ref_id = pi.id
        ), req AS (
         SELECT o.proveedor,
            c.material_id,
            sum((oi.cantidad - COALESCE(oi.recibido, 0::numeric)) *
                CASE
                    WHEN oi.unidad = 'kg'::text THEN 1::numeric
                    ELSE COALESCE(c.kg_x_uni, 0::numeric)
                END) AS kg_producto
           FROM "GP2".orden_compra o
             JOIN "GP2".orden_compra_item oi ON oi.oc_id = o.id
             JOIN "GP2".componente c ON c.id = oi.componente_id
          WHERE (o.estado = ANY (ARRAY['borrador'::text, 'enviada'::text])) AND c.material_id IS NOT NULL AND oi.cantidad > COALESCE(oi.recibido, 0::numeric)
          GROUP BY o.proveedor, c.material_id
        ), calc AS (
         SELECT i.prov_id,
            i.proveedor,
            i.ubic_id,
            m.id AS material_id,
            m.codigo AS material_codigo,
            m.descripcion AS material,
            round(COALESCE(r.kg_producto, 0::numeric) * (1::numeric + pct.p / 100::numeric), 2) AS kg_requerido_oc,
            COALESCE(inv.cantidad, 0::numeric) AS kg_en_inyector,
            COALESCE(invv.cantidad, 0::numeric) AS kg_en_virgilio,
            pct.p AS desperdicio_pct
           FROM iny i
             CROSS JOIN "GP2".componente m
             CROSS JOIN pct
             LEFT JOIN req r ON r.proveedor = i.proveedor AND r.material_id = m.id
             LEFT JOIN "GP2".inventario inv ON inv.componente_id = m.id AND inv.ubicacion_id = i.ubic_id
             LEFT JOIN "GP2".inventario invv ON invv.componente_id = m.id AND invv.ubicacion_id = "GP2".ubic_de('sector'::text, 14::bigint)
          WHERE m.sector_id = 14
        )
 SELECT calc.prov_id,
    calc.proveedor,
    calc.ubic_id,
    calc.material_id,
    calc.material_codigo,
    calc.material,
    calc.kg_requerido_oc,
    calc.kg_en_inyector,
    calc.kg_en_virgilio,
    calc.desperdicio_pct,
    GREATEST(0::numeric, calc.kg_requerido_oc - calc.kg_en_inyector) AS kg_a_enviar,
    ceil(GREATEST(0::numeric, calc.kg_requerido_oc - calc.kg_en_inyector) / bolsa.kg)::integer AS bolsas_a_enviar,
    bolsa.kg AS kg_x_bolsa
   FROM calc
     CROSS JOIN bolsa
  WHERE calc.kg_requerido_oc > 0::numeric OR calc.kg_en_inyector <> 0::numeric;
comment on view "GP2".v_material_inyector is 'Materia prima plastica por inyector: kg que necesita para sus OC abiertas (borrador/enviada, pendiente x kg_x_uni x (1+desperdicio)), kg que ya tiene en su ubicacion, kg en Virgilio y lo que hay que ENVIARLE (en kg y en bolsas de material_plastico_kg_x_bolsa). Solo pares con algo que decir. [usuario 2026-09-10: el inyector tiene que tener lo que necesite para su OC]';

-- ---------- v_material_precio_proveedor ----------
create or replace view "GP2".v_material_precio_proveedor as
 WITH tc AS (
         SELECT COALESCE(( SELECT parametro.valor
                   FROM "GP2".parametro
                  WHERE parametro.clave = 'tipo_cambio_usd_pesos'::text), 0::numeric) AS valor
        )
 SELECT c.id AS componente_id,
    c.codigo,
    c.descripcion AS material,
    c.proveedor AS proveedor_asignado,
    pi.nombre AS proveedor,
    pp.cod_prov,
    pp.producto,
    pp.precio,
    pp.moneda,
    pp.fecha_lista,
    round(
        CASE
            WHEN upper(COALESCE(pp.moneda, 'USD'::text)) ~~ '%US%'::text THEN pp.precio * tc.valor
            ELSE pp.precio
        END, 2) AS precio_ars_kg,
    rank() OVER (PARTITION BY c.id ORDER BY (
        CASE
            WHEN upper(COALESCE(pp.moneda, 'USD'::text)) ~~ '%US%'::text THEN pp.precio * tc.valor
            ELSE pp.precio
        END), pp.fecha_lista DESC NULLS LAST, pp.id DESC) AS orden
   FROM "GP2".precio_proveedor pp
     JOIN "GP2".componente c ON c.id = pp.componente_id AND c.sector_id = 14
     JOIN "GP2".proveedor_insumo pi ON pi.cod_prov = pp.cod_prov AND pi.activo
     CROSS JOIN tc
  WHERE pp.precio IS NOT NULL AND pp.precio > 0::numeric;
comment on view "GP2".v_material_precio_proveedor is 'Materia prima plastica: precio por kg de CADA proveedor, llevado a pesos al dolar oficial del dia (parametro tipo_cambio_usd_pesos) y rankeado (orden 1 = el mas barato). recalcular_proveedor_material() asigna ese al componente [usuario 2026-09-10: al que sea mas barato por material].';

-- ---------- v_nivel_stock ----------
create or replace view "GP2".v_nivel_stock as
 SELECT i.id AS inv_id,
    i.componente_id,
    i.ubicacion_id,
    c.sector_id,
    COALESCE(
        CASE
            WHEN c.sector_id = 5 AND c.unidad_medida = 'kg'::text THEN fk.consumo_kg_mes
            ELSE cp.consumo_uni_mes
        END, 0::numeric) AS consumo_mes,
    u.meses_stock,
    round(COALESCE(
        CASE
            WHEN c.sector_id = 5 AND c.unidad_medida = 'kg'::text THEN fk.consumo_kg_mes
            ELSE cp.consumo_uni_mes
        END, 0::numeric) * u.meses_stock) AS max_calc,
    "GP2"._es_sector_insumo(u.ref_id) AS es_insumo,
    i.maximo,
    i.maximo_origen
   FROM "GP2".inventario i
     JOIN "GP2".ubicacion u ON u.id = i.ubicacion_id AND u.tipo = 'sector'::text
     JOIN "GP2".componente c ON c.id = i.componente_id AND c.sector_id = u.ref_id
     LEFT JOIN "GP2".v_consumo_fleje_kg fk ON fk.componente_id = c.id AND c.sector_id = 5 AND c.unidad_medida = 'kg'::text
     LEFT JOIN "GP2".v_consumo_componente cp ON cp.componente_id = c.id AND NOT (c.sector_id = 5 AND c.unidad_medida = 'kg'::text);
comment on view "GP2".v_nivel_stock is 'Consumo mensual (Est Madre explotada) por fila de inventario de SECTOR y el nivel que sale de el: max_calc = consumo x meses_stock. Unica definicion (2026-09-05); la usa recalcular_maximos_insumos. El 2026-09-14 se le sacaron meses_minimo, min_calc, minimo y minimo_origen: el minimo se borro de la base y recalcular_minimos con el.';

-- ---------- v_nivel_stock_prov_at ----------
create or replace view "GP2".v_nivel_stock_prov_at as
 SELECT i.id AS inv_id,
    i.componente_id,
    i.ubicacion_id,
    u.ref_id AS proveedor_at_id,
    COALESCE(cp.uni_mes, 0::numeric) AS consumo_mes,
    COALESCE(u.meses_stock, 1::numeric) AS meses_stock,
    round(COALESCE(cp.uni_mes, 0::numeric) * COALESCE(u.meses_stock, 1::numeric)) AS max_calc,
    COALESCE(cp.tiene_supuesto, false) AS tiene_supuesto,
    i.maximo,
    i.maximo_origen
   FROM "GP2".inventario i
     JOIN "GP2".ubicacion u ON u.id = i.ubicacion_id AND u.tipo = 'proveedor_at'::text
     LEFT JOIN "GP2".v_consumo_prov_at cp ON cp.proveedor_at_id = u.ref_id AND cp.componente_id = i.componente_id;
comment on view "GP2".v_nivel_stock_prov_at is 'max_calc = consumo repartido x meses_stock de la ubicacion del prov AT (default 1 mes). La usa recalcular_maximos_prov_at. Gemela de v_nivel_stock_tallerista. OJO 2026-09-23: las 12 ubicaciones de prov AT tienen meses_stock NULL y 0 filas de inventario, asi que hoy la vista sale vacia y el 1 mes lo pone el coalesce.';

-- ---------- v_nivel_stock_tallerista ----------
create or replace view "GP2".v_nivel_stock_tallerista as
 SELECT i.id AS inv_id,
    i.componente_id,
    i.ubicacion_id,
    u.ref_id AS tallerista_id,
    COALESCE(ct.uni_mes, 0::numeric) AS consumo_mes,
    u.meses_stock,
    round(COALESCE(ct.uni_mes, 0::numeric) * u.meses_stock) AS max_calc,
    COALESCE(ct.tiene_supuesto, false) AS tiene_supuesto,
    i.maximo,
    i.maximo_origen
   FROM "GP2".inventario i
     JOIN "GP2".ubicacion u ON u.id = i.ubicacion_id AND u.tipo = 'tallerista'::text
     LEFT JOIN "GP2".v_consumo_tallerista ct ON ct.tallerista_id = u.ref_id AND ct.componente_id = i.componente_id;
comment on view "GP2".v_nivel_stock_tallerista is 'max_calc = consumo repartido x meses_stock de la ubicacion del tallerista. La usa recalcular_maximos_talleristas.';

-- ---------- v_oc_virgilio_pendiente ----------
create or replace view "GP2".v_oc_virgilio_pendiente as
 WITH oc AS (
         SELECT o.id,
            o.fecha,
            o.proveedor,
            o.codigo,
            o.cantidad,
            o.cantidad_recibida,
            o.unidad,
            o.estado,
            o.oc_uni_caja,
            regexp_replace(regexp_replace(upper(btrim(o.codigo)), '\s+(LK|CH)$'::text, ''::text), '^0+(?=.)'::text, ''::text) AS codb,
            upper(btrim(o.proveedor)) AS provn
           FROM "GP2".oc_virgilio o
          WHERE o.fecha >= (CURRENT_DATE - 120) AND (lower(COALESCE(o.estado, ''::text)) <> ALL (ARRAY['cerrada'::text, 'anulada'::text])) AND NULLIF(btrim(o.codigo), ''::text) IS NOT NULL
        ), res AS (
         SELECT oc.id,
            oc.fecha,
            oc.proveedor,
            oc.codigo,
            oc.cantidad,
            oc.cantidad_recibida,
            oc.unidad,
            oc.estado,
            oc.oc_uni_caja,
            oc.codb,
            oc.provn,
            ct.tipo,
            ct.ref_id
           FROM oc
             LEFT JOIN LATERAL ( SELECT x.tipo,
                    x.ref_id
                   FROM ( SELECT 1 AS pri,
                            'proveedor_at'::text AS tipo,
                            p.id AS ref_id
                           FROM "GP2".proveedor_at p
                          WHERE COALESCE(p.activo, true) AND (upper(btrim(p.nombre)) = ANY (ARRAY[oc.provn, oc.provn || ' SA'::text]))
                        UNION ALL
                         SELECT 2,
                            a_1.tipo,
                            a_1.ref_id
                           FROM "GP2".contraparte_alias a_1
                          WHERE a_1.alias = oc.provn AND a_1.ref_id IS NOT NULL
                        UNION ALL
                         SELECT 3,
                            'tallerista'::text,
                            t.id
                           FROM "GP2".tallerista t
                          WHERE t.activo AND upper(btrim(t.nombre)) = oc.provn
                        UNION ALL
                         SELECT 4,
                            'tallerista'::text,
                            t.id
                           FROM "GP2".tallerista t
                          WHERE t.activo AND upper(btrim(t.nombre)) ~~ (oc.provn || '%'::text)) x
                  ORDER BY x.pri, x.ref_id
                 LIMIT 1) ct ON true
        ), vig AS (
         SELECT r.id,
            r.fecha,
            r.proveedor,
            r.codigo,
            r.cantidad,
            r.cantidad_recibida,
            r.unidad,
            r.estado,
            r.oc_uni_caja,
            r.codb,
            r.provn,
            r.tipo,
            r.ref_id,
            max(r.fecha) OVER (PARTITION BY r.tipo, r.ref_id, r.codb) AS mf
           FROM res r
        )
 SELECT v.tipo,
    v.ref_id,
    a.id AS articulo_id,
    v.codb AS codigo,
    v.fecha,
    max(v.proveedor) AS proveedor_virgilio,
    sum(v.cantidad) AS cajas_ped,
    sum(COALESCE(v.cantidad_recibida, 0)) AS cajas_rec,
    sum(v.cantidad - COALESCE(v.cantidad_recibida, 0)) AS cajas_pend,
    sum((v.cantidad - COALESCE(v.cantidad_recibida, 0))::numeric *
        CASE
            WHEN lower(COALESCE(v.unidad, ''::text)) ~~ 'uni%'::text THEN 1::numeric
            ELSE COALESCE(a.articulos_por_caja::numeric, v.oc_uni_caja, 1::numeric)
        END) AS uni_pend,
    string_agg(DISTINCT v.unidad, ','::text) AS unidad
   FROM vig v
     LEFT JOIN "GP2".articulo a ON regexp_replace(a.codigo, '^0+(?=.)'::text, ''::text) = v.codb
  WHERE v.fecha = v.mf
  GROUP BY v.tipo, v.ref_id, a.id, v.codb, v.fecha
 HAVING sum(v.cantidad - COALESCE(v.cantidad_recibida, 0)) > 0;
comment on view "GP2".v_oc_virgilio_pendiente is 'Lo que cada contraparte le debe a Gestión Virgilio según su O.C. vigente: por (contraparte, código) manda la O.C. de fecha MÁS NUEVA no cerrada/anulada de los últimos 120 días ("la nueva pisa la vieja", misma regla que oc_vigentes_por_proveedor allá); pendiente = cantidad − recibida. El proveedor de la O.C. se resuelve a contraparte GP2 ACTIVA, en este orden: nombre de proveedor_at (con o sin " SA"), contraparte_alias, nombre exacto de tallerista, nombre de tallerista que empieza así ("Martin C" → Martin Cornejo); tipo null = no se pudo resolver ("Carlos E", "Log/ Fabr"). uni_pend = cajas × articulos_por_caja del artículo GP2 (o la caja de la O.C.); si la O.C. está en Uni, ya son unidades. articulo_id null = el código no es un artículo GP2. 2026-09-26.';

-- ---------- v_oc_virgilio_partes ----------
create or replace view "GP2".v_oc_virgilio_partes as
 SELECT p.tipo,
    p.ref_id,
    ac.componente_id,
    sum(p.uni_pend * ac.cantidad) AS uni_requeridas,
    count(DISTINCT p.articulo_id) AS articulos
   FROM "GP2".v_oc_virgilio_pendiente p
     JOIN "GP2".articulo_componente ac ON ac.articulo_id = p.articulo_id
     JOIN "GP2".componente c ON c.id = ac.componente_id AND NOT COALESCE(c.discontinuado, false)
  WHERE p.tipo = 'proveedor_at'::text AND (c.sector_id = ANY (ARRAY[10::bigint, 11::bigint]))
  GROUP BY p.tipo, p.ref_id, ac.componente_id;
comment on view "GP2".v_oc_virgilio_partes is 'Partes que hay que tener en poder del PROV. DE ART. TERMINADO para que cumpla su O.C. de Virgilio: uni_pend de cada artículo pendiente × receta (articulo_componente), solo cartón y caja (sectores 10 y 11), que es lo que GP2 le manda. Es el techo del Enviar de la Tablet para el prov AT (sugerido = techo − lo que ya tiene) [usuario 2026-09-26: "para los proveedores de artículo terminado solamente tenemos que mandarle partes para que puedan hacer lo que les pide su orden de compra"]. Sin O.C. vigente = 0, como antes.';

-- ---------- v_oc_virgilio_demanda ----------
create or replace view "GP2".v_oc_virgilio_demanda as
 WITH RECURSIVE dem AS (
         SELECT p.articulo_id AS art_id,
            sum(p.uni_pend) AS uni
           FROM "GP2".v_oc_virgilio_pendiente p
          WHERE p.articulo_id IS NOT NULL
          GROUP BY p.articulo_id
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
    sum(s.qty) AS uni
   FROM walk w
     JOIN seed s ON s.art_id = w.art_id AND s.comp_id = w.seed
  GROUP BY w.art_id, w.comp_id;
comment on view "GP2".v_oc_virgilio_demanda is 'La O.C. VIGENTE de Gestión Virgilio explotada por artículo y componente: lo que falta entregar de cada artículo (v_oc_virgilio_pendiente.uni_pend, sin importar a quién esté emitida) baja por la receta, el BOM y las rutas igual que v_consumo_demanda baja la Est. Madre. Es la demanda "por O.C." que usan los techos de la Tablet para la gente que trabaja contra orden (prov AT y talleristas O.C.; el Garage NO: va por O.C. de insumos, corrección del dueño del mismo día). 2026-09-26.';

-- ---------- v_oc_virgilio_partes_tallerista ----------
create or replace view "GP2".v_oc_virgilio_partes_tallerista as
 WITH pasos AS (
         SELECT DISTINCT r.articulo_id,
            rp.tallerista_id,
            rp.comp_entrada_id,
            rp.comp_salida_id
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
          WHERE rp.tipo_paso = 'tallerista'::text AND rp.tallerista_id IS NOT NULL AND rp.comp_entrada_id IS NOT NULL AND r.articulo_id IS NOT NULL
        ), sel AS (
         SELECT p.articulo_id,
            p.tallerista_id,
            p.comp_entrada_id,
            p.comp_salida_id
           FROM pasos p
             JOIN "GP2".tallerista t ON t.id = p.tallerista_id
          WHERE t.pedido_por_oc_virgilio
        )
 SELECT s.tallerista_id,
    s.comp_entrada_id AS componente_id,
    sum(d.uni * COALESCE(re.pct, 100::numeric) / 100::numeric) AS uni_requeridas,
    count(DISTINCT s.articulo_id) AS articulos
   FROM sel s
     JOIN "GP2".v_oc_virgilio_demanda d ON d.articulo_id = s.articulo_id AND d.componente_id = s.comp_entrada_id
     LEFT JOIN "GP2".v_reparto_efectivo re ON re.articulo_id = s.articulo_id AND re.comp_salida_id = s.comp_salida_id AND re.tallerista_id = s.tallerista_id
  GROUP BY s.tallerista_id, s.comp_entrada_id;
comment on view "GP2".v_oc_virgilio_partes_tallerista is 'Partes que hay que tener en poder del TALLERISTA O.C. (tallerista.pedido_por_oc_virgilio: Carlos Aguirre, Blist-Pack) para cumplir la O.C. vigente de Virgilio: demanda por O.C. del artículo en esa entrada (v_oc_virgilio_demanda) × el % del tallerista (v_reparto_efectivo). Techo del Enviar de la Tablet para esas filas. OJO 2026-09-26: los pasos que entregan en Sector GARAGE (Cornejo GRJ5/GRJ6, Escalante GRJ10) estuvieron acá unas horas y el dueño lo corrigió: "los que llenan garage se tienen que llenar por orden de compra de INSUMOS, no por orden de compra de artículo terminado" — el garage no se rige por la O.C. de Virgilio.';

-- ---------- v_planilla_costo ----------
create or replace view "GP2".v_planilla_costo as
 SELECT snapshot_id,
    fila,
    datos ->> 'A'::text AS cod,
    datos ->> 'B'::text AS familia,
    datos ->> 'C'::text AS fabricante,
    datos ->> 'D'::text AS descripcion,
    "GP2".planilla_num(datos ->> 'E'::text) AS compra_3ros,
    "GP2".planilla_num(datos ->> 'F'::text) AS material,
    "GP2".planilla_num(datos ->> 'G'::text) AS remaches,
    "GP2".planilla_num(datos ->> 'H'::text) AS tratamientos,
    "GP2".planilla_num(datos ->> 'I'::text) AS tallerista,
    "GP2".planilla_num(datos ->> 'J'::text) AS plastico_mango,
    "GP2".planilla_num(datos ->> 'K'::text) AS envasado_terceros,
    "GP2".planilla_num(datos ->> 'L'::text) AS carton,
    "GP2".planilla_num(datos ->> 'M'::text) AS cajas,
    "GP2".planilla_num(datos ->> 'N'::text) AS cod_y_precinto,
    "GP2".planilla_num(datos ->> 'O'::text) AS costo_sin_aporte,
    "GP2".planilla_num(datos ->> 'P'::text) AS aporte_produccion,
    formulas ->> 'K'::text AS formula_envasado,
    formulas
   FROM "GP2".planilla_fila f
  WHERE hoja = 'Costos'::text AND datos ? 'D'::text AND COALESCE(datos ->> 'A'::text, ''::text) <> 'Cod'::text;
comment on view "GP2".v_planilla_costo is 'Costeo por articulo de la planilla madre. envasado_terceros trae ademas su formula, que es la que dice de que proveedores se compone.';

-- ---------- v_planilla_precio ----------
create or replace view "GP2".v_planilla_precio as
 SELECT snapshot_id,
    fila,
    bloque AS proveedor,
    datos ->> 'B'::text AS cod_prov,
    datos ->> 'E'::text AS cod_isis,
    datos ->> 'F'::text AS moneda,
    "GP2".planilla_num(datos ->> 'G'::text) AS precio_proveedor,
    "GP2".planilla_num(datos ->> 'H'::text) AS precio_ipc_al_dia,
    "GP2".planilla_fecha(datos ->> 'I'::text) AS fecha_lista,
    datos ->> 'J'::text AS cod_art,
    datos ->> 'K'::text AS producto,
    "GP2".planilla_num(datos ->> 'L'::text) AS tomado_en_costos,
    datos ->> 'M'::text AS rubro,
    "GP2".planilla_fecha(datos ->> 'N'::text) AS ultima_compra,
    datos ->> 'O'::text AS detalle
   FROM "GP2".planilla_fila f
  WHERE hoja = 'Lista de Precios '::text AND (datos ->> 'B'::text) ~ '^[0-9]+$'::text AND datos ? 'K'::text;
comment on view "GP2".v_planilla_precio is 'Lista de precios de la planilla madre, con el proveedor tomado del encabezado de su bloque.';

-- ---------- v_preaviso_estado ----------
create or replace view "GP2".v_preaviso_estado as
 SELECT p.id,
    p.tipo_contraparte,
    p.contraparte_id,
    COALESCE(t.nombre, ps.nombre, pa.nombre) AS contraparte,
    p.comp_id,
    c.codigo AS comp_cod,
    c.descripcion AS comp_desc,
    p.cantidad,
    p.unidad,
    p.fecha_promesa,
    p.estado,
    p.nota,
    p.creado_en,
    p.fecha_promesa - (now() AT TIME ZONE 'America/Argentina/Buenos_Aires'::text)::date AS dias,
    COALESCE(( SELECT sum(m.cantidad) AS sum
           FROM "GP2".movimiento m
          WHERE m.comp_id = p.comp_id AND m.ubic_origen_id = "GP2".ubic_de(p.tipo_contraparte, p.contraparte_id) AND m.fecha >= p.creado_en), 0::numeric) AS entregado_desde
   FROM "GP2".preaviso p
     JOIN "GP2".componente c ON c.id = p.comp_id
     LEFT JOIN "GP2".tallerista t ON p.tipo_contraparte = 'tallerista'::text AND t.id = p.contraparte_id
     LEFT JOIN "GP2".proveedor_servicio ps ON p.tipo_contraparte = 'proveedor_servicio'::text AND ps.id = p.contraparte_id
     LEFT JOIN "GP2".proveedor_at pa ON p.tipo_contraparte = 'proveedor_at'::text AND pa.id = p.contraparte_id;
comment on view "GP2".v_preaviso_estado is 'Los preavisos con su contraparte, los dias que faltan (negativo = vencido) y cuanto de esa pieza entrego esa contraparte desde que lo prometio. Solo lectura.';

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

-- ---------- v_reparto_at_efectivo ----------
create or replace view "GP2".v_reparto_at_efectivo as
 WITH hacen AS (
         SELECT h_1.articulo_id,
            h_1.tipo,
            h_1.ref_id,
            rp.pct
           FROM "GP2".v_hace_articulo h_1
             LEFT JOIN "GP2".reparto_prov_at rp ON h_1.tipo = 'proveedor_at'::text AND rp.articulo_id = h_1.articulo_id AND rp.proveedor_at_id = h_1.ref_id
        ), n AS (
         SELECT hacen.articulo_id,
            count(*) AS n_hacen,
            count(hacen.pct) AS n_con_pct,
            COALESCE(sum(hacen.pct), 0::numeric) AS suma_pct
           FROM hacen
          GROUP BY hacen.articulo_id
        )
 SELECT h.articulo_id,
    h.ref_id AS proveedor_at_id,
    round(
        CASE
            WHEN n.n_con_pct = n.n_hacen OR n.suma_pct >= 100::numeric THEN h.pct * 100::numeric / NULLIF(n.suma_pct, 0::numeric)
            WHEN h.pct IS NOT NULL THEN h.pct
            ELSE (100::numeric - n.suma_pct) / (n.n_hacen - n.n_con_pct)::numeric
        END, 4) AS pct,
    h.pct IS NULL AND n.n_hacen > 1 AS es_supuesto,
    n.n_hacen
   FROM hacen h
     JOIN n ON n.articulo_id = h.articulo_id
  WHERE h.tipo = 'proveedor_at'::text;
comment on view "GP2".v_reparto_at_efectivo is 'Porcentaje del volumen de un articulo que entrega cada prov AT. El % dictado en reparto_prov_at manda; el resto se reparte en partes iguales entre los que hacen el articulo (prov AT y talleristas del terminado), o sea 50/50 cuando son dos y nadie dicto nada [usuario 2026-09-23]. es_supuesto = ese default, no un dato.';

-- ---------- v_reparto_efectivo ----------
create or replace view "GP2".v_reparto_efectivo as
 WITH pasos AS (
         SELECT DISTINCT r.articulo_id,
            rp.comp_salida_id,
            rp.tallerista_id
           FROM "GP2".ruta_paso rp
             JOIN "GP2".ruta r ON r.id = rp.ruta_id
          WHERE rp.tallerista_id IS NOT NULL AND rp.comp_salida_id IS NOT NULL AND r.articulo_id IS NOT NULL
        ), con_pct AS (
         SELECT p.articulo_id,
            p.comp_salida_id,
            p.tallerista_id,
            rt.pct
           FROM pasos p
             LEFT JOIN "GP2".reparto_tallerista rt ON rt.articulo_id = p.articulo_id AND rt.comp_salida_id = p.comp_salida_id AND rt.tallerista_id = p.tallerista_id
        ), n AS (
         SELECT con_pct.articulo_id,
            con_pct.comp_salida_id,
            count(*) AS n_tall,
            count(con_pct.pct) AS n_con_fila,
            COALESCE(sum(con_pct.pct), 0::numeric) AS suma_pct
           FROM con_pct
          GROUP BY con_pct.articulo_id, con_pct.comp_salida_id
        )
 SELECT c.articulo_id,
    c.comp_salida_id,
    c.tallerista_id,
        CASE
            WHEN n.n_con_fila = n.n_tall AND n.suma_pct > 0::numeric THEN round(c.pct * 100::numeric / n.suma_pct, 4)
            ELSE round(100.0 / n.n_tall::numeric, 4)
        END AS pct,
    n.n_con_fila <> n.n_tall AND n.n_tall > 1 AS es_supuesto,
    n.n_tall
   FROM con_pct c
     JOIN n ON n.articulo_id = c.articulo_id AND n.comp_salida_id = c.comp_salida_id;
comment on view "GP2".v_reparto_efectivo is 'Porcentaje del volumen de cada paso (articulo + comp_salida) que hace cada tallerista. Sale de reparto_tallerista, NORMALIZADO sobre los talleristas que siguen haciendo el paso (borrar una ruta no puede dejar al otro con la mitad). Si ninguno tiene fila, o solo algunos, va en partes iguales y lo marca es_supuesto: eso lo tiene que dictar el dueno.';

-- ---------- v_reposicion ----------
create or replace view "GP2".v_reposicion as
 SELECT DISTINCT ON (c.id) c.id AS componente_id,
    i.ubicacion_id,
    iu.nombre AS ubic_nombre,
    iu.meses_stock,
    i.cantidad,
    i.maximo,
    i.maximo_origen,
    GREATEST(0::numeric, round(COALESCE(i.maximo, 0::numeric) - COALESCE(i.cantidad, 0::numeric))) AS sugerido
   FROM "GP2".componente c
     JOIN "GP2".inventario i ON i.componente_id = c.id
     JOIN "GP2".ubicacion iu ON iu.id = i.ubicacion_id
  WHERE NOT c.discontinuado
  ORDER BY c.id, (
        CASE
            WHEN iu.id = "GP2".ubic_de('sector'::text, c.sector_id) OR c.sector_id = 12 AND iu.id = "GP2".ubic_de('virgilio'::text) THEN 0
            WHEN iu.tipo = 'sector'::text THEN 1
            WHEN iu.tipo = 'proveedor_servicio'::text THEN 2
            ELSE 3
        END), i.cantidad DESC NULLS LAST, i.ubicacion_id;
comment on view "GP2".v_reposicion is 'Que hay que reponer: sugerido = maximo - stock, por componente y su ubicacion principal. Excluye los componentes discontinuados (2026-09-13).';

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
