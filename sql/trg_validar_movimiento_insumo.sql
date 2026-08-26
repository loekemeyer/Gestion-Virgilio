-- Trigger: validaciones de integridad para movimientos de insumos
-- Creado v11.77 (2026-08-26)
-- 1. Signo coherente: recepcion_insumo → delta≥0, entrega_insumo → delta≤0
-- 2. Unidad default: si viene NULL y el insumo tiene base en Insumos_Factores, asignarla

CREATE OR REPLACE FUNCTION trg_validar_movimiento_insumo()
RETURNS trigger AS $$
DECLARE
  v_base text;
BEGIN
  IF NEW.deposito <> 'insumos' THEN RETURN NEW; END IF;

  -- Signo coherente con tipo
  IF NEW.tipo = 'recepcion_insumo' AND NEW.delta < 0 THEN
    RAISE EXCEPTION 'recepcion_insumo no puede tener delta negativo (%)', NEW.delta;
  END IF;
  IF NEW.tipo = 'entrega_insumo' AND NEW.delta > 0 THEN
    RAISE EXCEPTION 'entrega_insumo no puede tener delta positivo (%)', NEW.delta;
  END IF;

  -- Si unidad es NULL y el insumo tiene unidad base, asignarla
  IF NEW.unidad IS NULL OR btrim(NEW.unidad) = '' THEN
    SELECT f.unidad INTO v_base
    FROM "Insumos_Factores" f
    WHERE f.cod_art = NEW.cod_art AND f.es_base = true
    LIMIT 1;
    IF v_base IS NOT NULL THEN
      NEW.unidad := v_base;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_mov_insumo ON "Movimientos_Stock";
CREATE TRIGGER trg_validar_mov_insumo
  BEFORE INSERT ON "Movimientos_Stock"
  FOR EACH ROW
  EXECUTE FUNCTION trg_validar_movimiento_insumo();
