-- =============================================================================
-- v15.91 (2026-09-11) — Las DOS funciones que todavía leían `vista_saldos_stock` sin agrupar
-- Migración aplicada: `gv_saldos_group_by_funciones_v1589`
-- =============================================================================
-- Barrido a raíz del bug de Corregir códigos (§3.cj.2): la **v15.71** le cambió el GRANO a
-- `vista_saldos_stock` — pasó de una fila por código a **una fila por (cod_art, empresa)**, y
-- hoy hay **292 códigos con dos filas**. El front (index.html, recepcion.js) ya se había
-- corregido entonces ("ACUMULA, no pisa") y las otras 5 vistas dependientes agregan bien;
-- faltaban estas dos funciones:
--
-- 1) `public.gondola_return_check(jsonb)` — el chequeo de "¿devolver a góndola?" de Recepción.
--    Su CTE `gond` no agrupaba: duplicaba las filas del resultado y tomaba el `terminado` de
--    UNA empresa (muchas veces 0) en vez del total → el aviso de **exceso de góndola** no
--    saltaba cuando tenía que saltar.
--
-- 2) `public.aceptar_conteo(bigint,text)` — el fallback cuando `Conteo_Stock.stock_sistema` es
--    null hacía `SELECT COALESCE(terminado,0)+COALESCE(excedente,0) INTO … ` **sin agregado**:
--    se quedaba con una fila cualquiera, y con ese número calcula el delta del ajuste que
--    **escribe** en `Movimientos_Stock`. Riesgo de inflar/desinflar stock.
--    **Sin daño histórico**: los 2 conteos aceptados hasta hoy tenían `stock_sistema` cargado.
--
-- PRUEBA (después de aplicar):
--   select * from public.gondola_return_check('[{"cod":"505","cajas":5000},{"cod":"513","cajas":5000}]');
--   → 1 fila por código (antes 2), con gond = 2719 (505) y 2162 (513) = el TOTAL.
--     Antes una de las dos filas de cada código traía gond = 0.
--   Sin negativos en la vista hoy, así que `check_stock_anomalias` y `generar_reporte_agentes`
--   (que miran fila por fila) no se tocaron: ahí el corte por empresa es información, no ruido.
--
-- OBJETOS COMPARTIDOS: las dos son de `public.*` y se reemplazan con la MISMA firma y el mismo
-- resultado (sólo se corrige el saldo leído). Anotado en `docs/ROLLBACK-PRODUCCION.md`.
-- ROLLBACK: correr `sql/backups/funciones_vista_saldos_stock_20260911_pre_v1589.sql`.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.gondola_return_check(p_items jsonb)
 RETURNS TABLE(cod text, cajas integer, cap numeric, gond numeric, proy numeric, razon text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH items AS (
    SELECT
      norm_cod(elem->>'cod') AS cod_n,
      (elem->>'cajas')::int AS cajas
    FROM jsonb_array_elements(p_items) AS elem
    WHERE norm_cod(elem->>'cod') <> ''
  ),
  cap AS (
    SELECT norm_cod(c.cod) AS cod_n, sum(COALESCE(c.cajas_max, 0)) AS capacidad
    FROM "Capacidad_Sector" c
    WHERE norm_cod(c.cod) IN (SELECT cod_n FROM items)
    GROUP BY norm_cod(c.cod)
  ),
  gond AS (
    -- v15.91: SUM + GROUP BY. `vista_saldos_stock` da una fila por (cod_art, empresa) desde la
    -- v15.71; sin agrupar este CTE duplicaba las filas del join y además tomaba el saldo de
    -- UNA empresa (muchas veces 0) en vez del total del código.
    SELECT norm_cod(s.cod_art) AS cod_n, sum(COALESCE(s.terminado, 0)) AS terminado
    FROM vista_saldos_stock s
    WHERE norm_cod(s.cod_art) IN (SELECT cod_n FROM items)
    GROUP BY norm_cod(s.cod_art)
  ),
  proy AS (
    SELECT norm_cod(p.cod) AS cod_n, sum(COALESCE(p.proy_cajas_mes, 0)) AS proy_cajas_mes
    FROM proyeccion_madre p
    WHERE norm_cod(p.cod) IN (SELECT cod_n FROM items)
    GROUP BY norm_cod(p.cod)
  )
  SELECT
    i.cod_n AS cod,
    i.cajas,
    COALESCE(c.capacidad, 0) AS cap,
    COALESCE(g.terminado, 0) AS gond,
    COALESCE(p.proy_cajas_mes, 0) AS proy,
    CASE
      WHEN COALESCE(c.capacidad, 0) > 0
        AND COALESCE(p.proy_cajas_mes, 0) < 50
        AND (COALESCE(g.terminado, 0) + i.cajas) > COALESCE(c.capacidad, 0) * 1.2
      THEN 'exceso_baja_rotacion'
      WHEN COALESCE(c.capacidad, 0) > 0
        AND (COALESCE(g.terminado, 0) + i.cajas) > COALESCE(c.capacidad, 0) * 1.2
      THEN 'exceso_gondola'
      WHEN COALESCE(p.proy_cajas_mes, 0) < 50
        AND COALESCE(p.proy_cajas_mes, 0) > 0
      THEN 'baja_rotacion'
      ELSE NULL
    END AS razon
  FROM items i
  LEFT JOIN cap c ON c.cod_n = i.cod_n
  LEFT JOIN gond g ON g.cod_n = i.cod_n
  LEFT JOIN proy p ON p.cod_n = i.cod_n
  WHERE COALESCE(c.capacidad, 0) > 0
    AND (
      (COALESCE(g.terminado, 0) + i.cajas) > COALESCE(c.capacidad, 0) * 1.2
      OR
      (COALESCE(p.proy_cajas_mes, 0) < 50 AND COALESCE(p.proy_cajas_mes, 0) > 0)
    );
$function$;

CREATE OR REPLACE FUNCTION public.aceptar_conteo(p_conteo_id bigint, p_admin_legajo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_conteo RECORD; v_cod_norm text; v_contado numeric; v_stock_al_conteo numeric; v_dif_original numeric; v_emp text;
BEGIN
  SELECT * INTO v_conteo FROM "Conteo_Stock" WHERE id = p_conteo_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'Conteo no encontrado'); END IF;
  IF v_conteo.estado <> 'pendiente' THEN RETURN jsonb_build_object('ok', false, 'error', 'Conteo ya procesado (' || v_conteo.estado || ')'); END IF;
  v_cod_norm := UPPER(TRIM(v_conteo.cod));
  v_contado := COALESCE(CASE WHEN v_conteo.deposito = 'insumos' THEN v_conteo.cantidad ELSE v_conteo.cajas END, 0);
  IF v_conteo.stock_sistema IS NOT NULL THEN
    v_stock_al_conteo := v_conteo.stock_sistema;
  ELSE
    IF v_conteo.deposito = 'insumos' THEN
      SELECT COALESCE(SUM(delta) FILTER (WHERE unidad = v_conteo.unidad), 0) INTO v_stock_al_conteo FROM "Movimientos_Stock" WHERE cod_art = v_cod_norm AND deposito = 'insumos';
    ELSE
      -- v15.91: SUM. `vista_saldos_stock` da una fila por (cod_art, empresa) desde la v15.71;
      -- el SELECT sin agregado se quedaba con una sola fila y el ajuste de stock salía mal.
      SELECT COALESCE(SUM(COALESCE(terminado,0) + COALESCE(excedente,0)), 0) INTO v_stock_al_conteo FROM vista_saldos_stock WHERE cod_art = v_cod_norm;
    END IF;
    v_stock_al_conteo := COALESCE(v_stock_al_conteo, 0);
  END IF;
  v_dif_original := v_contado - v_stock_al_conteo;
  IF v_dif_original = 0 THEN
    UPDATE "Conteo_Stock" SET estado = 'aceptado', procesado_por = p_admin_legajo, procesado_en = now() WHERE id = p_conteo_id;
    RETURN jsonb_build_object('ok', true, 'mensaje', 'Conteo aceptado (stock coincide, sin ajuste)', 'delta', 0, 'contado', v_contado, 'stock_al_conteo', v_stock_al_conteo);
  END IF;
  IF v_conteo.deposito <> 'insumos' AND nullif(btrim(v_conteo.sector),'') IS NOT NULL THEN
    SELECT empresa INTO v_emp FROM "Capacidad_Sector" WHERE upper(btrim(sector)) = upper(btrim(v_conteo.sector)) LIMIT 1;
  END IF;
  INSERT INTO "Movimientos_Stock" (cod_art, deposito, delta, tipo, ref, legajo, unidad, empresa)
  VALUES (v_cod_norm, v_conteo.deposito, v_dif_original, 'ajuste',
    'conteo #' || p_conteo_id || ' | contado ' || v_contado || ' vs sistema ' || v_stock_al_conteo || ' (dif ' || (CASE WHEN v_dif_original > 0 THEN '+' ELSE '' END) || v_dif_original || ')',
    p_admin_legajo, CASE WHEN v_conteo.deposito = 'insumos' THEN v_conteo.unidad ELSE NULL END, v_emp);
  UPDATE "Conteo_Stock" SET estado = 'aceptado', procesado_por = p_admin_legajo, procesado_en = now() WHERE id = p_conteo_id;
  RETURN jsonb_build_object('ok', true, 'mensaje', 'Conteo aceptado, stock ajustado', 'delta', v_dif_original, 'contado', v_contado, 'stock_al_conteo', v_stock_al_conteo);
END;
$function$;
