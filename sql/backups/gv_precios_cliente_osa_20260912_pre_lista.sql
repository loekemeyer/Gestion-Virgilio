-- Backup de public."GV_Precios_Cliente" (Osa 2533) ANTES de pasar de NETO a LISTA — 2026-09-12.
-- Protocolo del CLAUDE.md: backup antes de tocar datos. Eran 4 filas, cargadas en la v15.83
-- con el precio NETO y es_final = true (no se les aplicaba ningun descuento).
--
-- Restore exacto:
update public."GV_Precios_Cliente" set precio_unit = 1260, es_final = true where empresa='lk' and cod_cliente='2533' and cod='102E';
update public."GV_Precios_Cliente" set precio_unit =  520, es_final = true where empresa='lk' and cod_cliente='2533' and cod='103';
update public."GV_Precios_Cliente" set precio_unit = 1610, es_final = true where empresa='lk' and cod_cliente='2533' and cod='106E';
update public."GV_Precios_Cliente" set precio_unit =  660, es_final = true where empresa='lk' and cod_cliente='2533' and cod='198E';
-- (uxb: 198E tenia 12; los otros tres, null. La nota original decia "Precio pactado con Fede
--  (Chemello/Osa), 11/09/2026. Neto, ya incluye todos los dtos de LK; +IVA aparte.")
--
-- POR QUE SE CAMBIA (Thomas, 12/09): "esos precios son lo que el paga considerando su 16 de
-- descuento y el 2 de descuento. En funcion de eso se calcula el precio de lista de el. El
-- precio de 1.260 es lo neto que el me va a pagar mas IVA."
-- O sea el pactado es el NETO, y lo que hay que guardar es la LISTA, para que la cascada
-- (dto_vol 16% de clientes_dto + 2% de factor_web) aterrice sola en ese neto.
-- Los valores nuevos son los de la FACTURA REAL del 09/09 (GV_Precio_Facturado_Cache):
--   102E 1.530 · 103 632 · 106E 1.956 · 198E 802, todos con dto 16%.
-- Coinciden al peso con el calculo neto / 0,84 / 0,98 (1.530,61 · 631,68 · 1.955,78 · 801,75),
-- asi que Gestion queda diciendo lo mismo que ISIS emite.
