-- =============================================================================
-- entregas_virgilio_gv_empresa.sql — empresa como COLUMNA en Entregas_Virgilio
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · v14.48 (2026-09-08) · Fase 2 (parte A)
-- =============================================================================
-- Para qué: que la empresa viaje como columna también río abajo del pipeline web.
-- Entregas_Virgilio no la tenía; se deriva de la NP. Columna GENERADA STORED = se llena
-- sola (existentes + futuras), read-only (no la escribe ningún writer → no cambia el
-- comportamiento de nadie, no hace falta trigger). Guarda la empresa COMERCIAL de la línea
-- (la de la NP: lk/chef), misma convención que PPP_Web_*.empresa.
--
-- gv_empresa_de_np_texto es IMMUTABLE (requisito de columna generada).
-- Medido (08/09): 8438 lk + 1414 chef, 0 nulls.
--
-- ⚠ Tabla COMPARTIDA con Producción. Cambio ADITIVO y reversible (Producción no la usa
-- y de todos modos ignora la columna nueva). Anotado en docs/ROLLBACK-PRODUCCION.md.
-- Rollback: alter table public."Entregas_Virgilio" drop column gv_empresa;
-- =============================================================================
alter table public."Entregas_Virgilio"
  add column gv_empresa text
  generated always as (public.gv_empresa_de_np_texto(np)) stored;

-- Chequeo:
--   select gv_empresa, count(*) from public."Entregas_Virgilio" group by 1;
