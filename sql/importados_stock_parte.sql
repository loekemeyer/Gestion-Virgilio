-- ============================================================
-- v9.25 — STOCK DE PARTE cuenta como stock del TERMINADO importado
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- Caso: los 94xE (cubiertos ac. inox) se IMPORTAN, pero Log/Fabr los ARMA a partir
-- de la parte 94xP. El stock de 94xP (en 'insumos', en unidades) es "94xE en parte",
-- así que cuenta como stock del 94xE al decidir cuánto importar.
--   a pedir(94xE) = objetivo - (stock 94xE + stock 94xP) - en curso
-- Los 94xE siguen en el maestro Importados (se importan); esto SOLO suma stock.
-- ============================================================

CREATE TABLE IF NOT EXISTS "Importados_Stock_Parte" (
  terminado text NOT NULL,   -- código importado que se pide (ej. 942E)
  parte     text NOT NULL,   -- parte cuyo stock cuenta como stock del terminado (ej. 942P)
  creado    timestamptz DEFAULT now(),
  PRIMARY KEY (terminado, parte)
);
ALTER TABLE "Importados_Stock_Parte" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS isp_sel ON "Importados_Stock_Parte";
CREATE POLICY isp_sel ON "Importados_Stock_Parte" FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS isp_all ON "Importados_Stock_Parte";
CREATE POLICY isp_all ON "Importados_Stock_Parte" FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO "Importados_Stock_Parte" (terminado, parte) VALUES
 ('942E','942P'),('943E','943P'),('944E','944P'),('945E','945P'),('948E','948P')
ON CONFLICT DO NOTHING;

-- Por terminado, stock (unidades) de sus partes = saldo neto en el stock principal
-- (Movimientos_Stock). Los duplicados '...(2)COPIA' netean 0 y no matchean (match exacto normalizado).
CREATE OR REPLACE VIEW vista_importados_stock_parte AS
SELECT sp.terminado AS cod,
       round(sum(coalesce(mv.saldo,0)),0) AS stock_parte,
       string_agg(DISTINCT sp.parte, ', ' ORDER BY sp.parte) AS partes
FROM "Importados_Stock_Parte" sp
LEFT JOIN LATERAL (
  SELECT sum(m.delta) AS saldo FROM "Movimientos_Stock" m
  WHERE ltrim(upper(btrim(m.cod_art)),'0') = ltrim(upper(btrim(sp.parte)),'0')
) mv ON true
GROUP BY sp.terminado;
ALTER VIEW vista_importados_stock_parte SET (security_invoker = on);
GRANT SELECT ON vista_importados_stock_parte TO anon, authenticated;

-- El front (ocgFetchImportados) suma stock_parte al stock del terminado antes de calcular
-- lo a pedir, y lo muestra en el módulo Pedidos Importación (badge 🔧+N).
