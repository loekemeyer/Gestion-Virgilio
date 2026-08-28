-- ✅ APLICADO 2026-08-28 (migración `stock_saldos_view`).
-- Crea Stock_Saldos como vista sobre vista_stock_procesada (matview, refresh cada 2-5 min).
-- Soluciona el fetch silencioso fallido en index.html:15560 (v10.42).
-- Columnas expuestas: cod_base, familia_principal, es_secundario, stock_total.
-- Uso: sumar stock de códigos SECUNDARIOS dentro de su familia PRINCIPAL
--   para que un principal con stock en el secundario no aparezca como faltante.

create or replace view public."Stock_Saldos" as
select cod_base, familia_principal, es_secundario, stock_total
from public.vista_stock_procesada;

grant select on public."Stock_Saldos" to anon, authenticated;
