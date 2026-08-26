-- Trigger: normalizar unidad de insumos a base usando Insumos_Factores
-- Creado v11.77 (2026-08-26)
-- Si el insumo tiene factor de conversión y la unidad no es la base,
-- convierte delta*factor y cambia unidad a base. Cubre cualquier vía de insert.

CREATE OR REPLACE FUNCTION trg_normalizar_unidad_insumo()
RETURNS trigger AS $$
DECLARE
  v_factor numeric;
  v_base   text;
BEGIN
  IF NEW.deposito <> 'insumos' OR NEW.unidad IS NULL OR TRIM(NEW.unidad) = '' THEN
    RETURN NEW;
  END IF;

  -- Si la unidad ya es base, no convertir
  IF EXISTS (
    SELECT 1 FROM "Insumos_Factores"
    WHERE cod_art = NEW.cod_art
      AND lower(trim(unidad)) = lower(trim(NEW.unidad))
      AND es_base = true
  ) THEN
    RETURN NEW;
  END IF;

  -- Buscar factor de la unidad no-base y la unidad base
  SELECT f.factor, b.unidad
  INTO v_factor, v_base
  FROM "Insumos_Factores" f
  JOIN "Insumos_Factores" b ON b.cod_art = f.cod_art AND b.es_base = true
  WHERE f.cod_art = NEW.cod_art
    AND lower(trim(f.unidad)) = lower(trim(NEW.unidad))
    AND f.es_base = false;

  IF v_factor IS NOT NULL AND v_base IS NOT NULL THEN
    NEW.delta  := NEW.delta * v_factor;
    NEW.unidad := v_base;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS normalizar_unidad_insumo ON "Movimientos_Stock";
CREATE TRIGGER normalizar_unidad_insumo
  BEFORE INSERT ON "Movimientos_Stock"
  FOR EACH ROW
  EXECUTE FUNCTION trg_normalizar_unidad_insumo();
