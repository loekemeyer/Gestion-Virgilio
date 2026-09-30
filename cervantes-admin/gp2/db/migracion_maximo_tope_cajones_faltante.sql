-- 2026-09-29 · Dos ajustes sobre migracion_maximo_consumo_sectores.sql (mismo dia):
-- 1) Tope: en Crudo/Procesado el maximo = min(consumo x meses_stock, max_cajones_x_ubicacion x uni_x_cajon).
--    Usuario (Thomas): "El maximo de sector crudo y sector procesado no puede exceder los 5 cajones".
--    28 piezas lo pasaban (D1 21,4 cajones). Sin uni_x_cajon no hay tope (Z12, C13, Z31).
-- 2) Faltante automatico = stock < maximo (antes: stock < 1 cajon). Usuario: "Menor al maximo".
-- Definiciones completas en db/funciones_GP2.sql (recalcular_maximos_consumo_meses) y db/vistas_GP2.sql
-- (v_faltante_estado). Se aplicaron con create or replace + revoke, y despues:
--   select "GP2".recalcular_maximos_consumo_meses();   -- {"actualizados": 28, "tope_cajones": 5}
--   select "GP2".recalcular_maximo_mp_ps();
revoke execute on function "GP2".recalcular_maximos_consumo_meses() from public, anon, authenticated;
