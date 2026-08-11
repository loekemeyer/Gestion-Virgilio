-- ============================================================
-- v9.14 — PARTES importadas + regla "SUPER"
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- 1) PARTES: un código del maestro Importados que NO es producto de venta sino
--    una parte que se mete dentro de un terminado nacional. Su demanda = SUMA de
--    la proyección de los terminados que la usan (no de "ventas de la parte").
-- 2) SUPER: equivalente primario/secundario SOLO para super. Un código super
--    (505i) es el mismo producto que su base (505), pero es el código con el que
--    los supermercados lo piden. Su proyección se PLIEGA sobre la base.
-- ============================================================

-- ---------- Mapa parte -> terminados ----------
CREATE TABLE IF NOT EXISTS "Importados_Partes_Map" (
  parte     text NOT NULL,
  terminado text NOT NULL,
  creado    timestamptz DEFAULT now(),
  PRIMARY KEY (parte, terminado)
);
ALTER TABLE "Importados_Partes_Map" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ipm_sel ON "Importados_Partes_Map";
CREATE POLICY ipm_sel ON "Importados_Partes_Map" FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS ipm_all ON "Importados_Partes_Map";
CREATE POLICY ipm_all ON "Importados_Partes_Map" FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO "Importados_Partes_Map" (parte, terminado) VALUES
 ('523C','523'),
 ('1546903','546'),
 ('1000900','520'),('1000900','521'),('1000900','530'),('1000900','531'),
 ('1000900','581'),('1000900','735'),('1000900','730'),('1000900','731'),('1000900','104'),
 ('505C','505'),('505C','586'),('505C','099'),('505C','713'),('505C','123'),('505C','114'),('505C','186')
ON CONFLICT (parte, terminado) DO NOTHING;

-- ---------- Regla SUPER ----------
CREATE TABLE IF NOT EXISTS "Equivalencias_Super" (
  super_cod      text PRIMARY KEY,   -- código que usan los super (ej. 505I)
  base_cod       text NOT NULL,      -- producto real / base (ej. 505)
  empresa        text,
  descripcion    text,
  nota           text,
  actualizado_en timestamptz DEFAULT now()
);
ALTER TABLE "Equivalencias_Super" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS eqsuper_sel ON "Equivalencias_Super";
CREATE POLICY eqsuper_sel ON "Equivalencias_Super" FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS eqsuper_all ON "Equivalencias_Super";
CREATE POLICY eqsuper_all ON "Equivalencias_Super" FOR ALL TO authenticated USING (true) WITH CHECK (true);

INSERT INTO "Equivalencias_Super" (super_cod, base_cod, empresa, descripcion, nota) VALUES
 ('505I','505','LK','Pelador Mgo Plastico','Los super piden el 505 bajo el código 505i (mismo producto).')
ON CONFLICT (super_cod) DO UPDATE
  SET base_cod=EXCLUDED.base_cod, descripcion=EXCLUDED.descripcion,
      nota=EXCLUDED.nota, actualizado_en=now();

-- Proyección madre con el super PLEGADO sobre su base (canónica).
CREATE OR REPLACE VIEW vista_proyeccion_super AS
WITH sup AS (
  SELECT ltrim(upper(btrim(super_cod)),'0') AS s, btrim(base_cod) AS base_cod
  FROM "Equivalencias_Super"
)
SELECT coalesce(x.base_cod, p.cod) AS cod,
       round(sum(p.proy_uni_mes),0) AS proy_uni_mes
FROM proyeccion_madre p
LEFT JOIN sup x ON x.s = ltrim(upper(btrim(p.cod)),'0')
GROUP BY coalesce(x.base_cod, p.cod);
ALTER VIEW vista_proyeccion_super SET (security_invoker = on);
GRANT SELECT ON vista_proyeccion_super TO anon, authenticated;

-- Demanda por parte = Σ proyección (plegada) de sus terminados + detalle.
CREATE OR REPLACE VIEW vista_importados_partes AS
SELECT m.parte AS cod,
       round(sum(coalesce(p.proy,0))::numeric,0) AS proy_uni_mes,
       jsonb_agg(jsonb_build_object('cod', m.terminado,
                                    'proy', round(coalesce(p.proy,0)::numeric,0))
                 ORDER BY m.terminado) AS detalle
FROM "Importados_Partes_Map" m
LEFT JOIN LATERAL (
  SELECT max(proy_uni_mes) AS proy FROM vista_proyeccion_super p
  WHERE ltrim(upper(btrim(p.cod)),'0') = ltrim(upper(btrim(m.terminado)),'0')
) p ON true
GROUP BY m.parte;
ALTER VIEW vista_importados_partes SET (security_invoker = on);
GRANT SELECT ON vista_importados_partes TO anon, authenticated;
