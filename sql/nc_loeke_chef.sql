-- ============================================================
-- v9.21 — NC Loeke→Chef en Facturación
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- Regla de negocio (definida con el dueño):
--   Los artículos IMPORTADOS POR CHEF (proveedores Ownland/Kangli/Fujian/Frontier)
--   que son "home Loeke" (se venden normalmente desde la góndola Loeke, ej. Coladores
--   437E/438E/439E) — cuando los compra un cliente de CHEF (NP 44xxx) se facturan por
--   Chef. Para eso hay que hacer NOTA DE CRÉDITO a Loeke y pasar el stock a Chef.
--   El nativo-Chef (809E Corta Queso, default CH) NO necesita NC. Lo importado por
--   Tierra Nativa (Becky/Hugo Wong/Zhixin, ej. 957E) tampoco.
--
-- La operadora ve, en el módulo Facturación, una FILA por cada NC pendiente con un
-- botón "✓ NC hecha". Al confirmar se registra acá y la fila desaparece. Es un
-- checklist aparte: NO afecta la carga del camión ni el cierre de jornada.
-- ============================================================

-- Registro de NCs ya confirmadas por la operadora
CREATE TABLE IF NOT EXISTS "NC_Loeke_Chef_Hechas" (
  np             text NOT NULL,
  cod            text NOT NULL,
  confirmado_por text,
  confirmado_en  timestamptz DEFAULT now(),
  PRIMARY KEY (np, cod)
);
ALTER TABLE "NC_Loeke_Chef_Hechas" ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS nch_sel ON "NC_Loeke_Chef_Hechas";
CREATE POLICY nch_sel ON "NC_Loeke_Chef_Hechas" FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS nch_ins ON "NC_Loeke_Chef_Hechas";
CREATE POLICY nch_ins ON "NC_Loeke_Chef_Hechas" FOR INSERT TO authenticated WITH CHECK (true);
DROP POLICY IF EXISTS nch_del ON "NC_Loeke_Chef_Hechas";
CREATE POLICY nch_del ON "NC_Loeke_Chef_Hechas" FOR DELETE TO authenticated USING (true);

-- Vista de NCs PENDIENTES (derivada del maestro; excluye las ya confirmadas)
CREATE OR REPLACE VIEW vista_nc_loeke_chef AS
WITH chef_imp AS (   -- importados por Chef
  SELECT DISTINCT ltrim(upper(btrim(cod_art)),'0') AS base
  FROM "Importados"
  WHERE activo AND btrim(proveedor) IN ('Ownland','Kangli','Fujian','Frontier')
),
split AS (           -- códigos partidos por empresa (tienen góndola LK y CH)
  SELECT ltrim(upper(replace(replace(btrim(cod),' LK',''),' CH','')),'0') AS base
  FROM "Planimetria"
  WHERE upper(btrim(cod)) LIKE '% LK' OR upper(btrim(cod)) LIKE '% CH'
  GROUP BY 1
  HAVING bool_or(upper(btrim(cod)) LIKE '% LK') AND bool_or(upper(btrim(cod)) LIKE '% CH')
),
home_chef AS (       -- nativos Chef (default CH) → NO necesitan NC (ej. 809E)
  SELECT ltrim(upper(btrim(cod_pedido)),'0') AS base FROM "Equivalencias_Codigos"
  WHERE upper(btrim(cod_real)) LIKE '% CH' AND upper(btrim(cod_pedido)) NOT LIKE '%L'
),
candidatos AS (
  SELECT s.base FROM split s JOIN chef_imp c ON c.base=s.base
  WHERE s.base NOT IN (SELECT base FROM home_chef)
)
SELECT btrim(b.pedido) AS np,
       k.base AS cod,
       (SELECT i.descripcion FROM "Importados" i
         WHERE ltrim(upper(btrim(i.cod_art)),'0')=k.base AND i.descripcion IS NOT NULL LIMIT 1) AS descripcion,
       sum(coalesce(b.cajas,0)) AS cajas
FROM "PPP_Base_Pedidos" b
JOIN candidatos k
  ON k.base = ltrim(upper(regexp_replace(upper(btrim(b.articulo)),'([0-9E])L$','\1')),'0')  -- pela la L final (438EL=438E)
WHERE b.pedido ~ '^[0-9]+$' AND b.pedido::bigint < 90000   -- NP de Chef
  AND NOT EXISTS (SELECT 1 FROM "NC_Loeke_Chef_Hechas" h
                   WHERE btrim(h.np)=btrim(b.pedido) AND ltrim(upper(btrim(h.cod)),'0')=k.base)
GROUP BY btrim(b.pedido), k.base
HAVING sum(coalesce(b.cajas,0)) > 0;

ALTER VIEW vista_nc_loeke_chef SET (security_invoker = on);
GRANT SELECT ON vista_nc_loeke_chef TO anon, authenticated;
