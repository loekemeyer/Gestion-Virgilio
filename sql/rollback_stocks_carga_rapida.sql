-- ROLLBACK: stocks_carga_rapida
-- Fecha: 2026-08-13
-- Para revertir la creación de la tabla stocks_carga_rapida

DROP TABLE IF EXISTS public.stocks_carga_rapida;

-- Si se borró Stock_Saldos como parte del cambio, recrear con:
-- (Stock_Saldos NO se toca en este cambio, solo se agrega stocks_carga_rapida)
