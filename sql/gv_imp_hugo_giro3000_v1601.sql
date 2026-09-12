-- v16.01 (2026-09-12) — el giro de 3.000 usd de Hugo Wong: 2.400 al barco, 600 al 323ES
-- Dueño, 12/09: "el giro de 3000usd mas reciente ... 2400usd fue para el pedido de barco
-- y 600 para el pedido de 323ES".
--
-- NO estaba cargado, y tampoco está en el extracto de NTL (que termina el 04/09/2026,
-- fila 184). O sea que es posterior al Excel que mandó, o salió por fuera de NTL.
-- La FECHA quedó en 12/09 y hay que confirmarla desde la pantalla (💵 Giros).
--
-- backup: create table public."GV_Imp_Pagos_bkp_20260912" as select * from public."GV_Imp_Pagos";

insert into public."GV_Imp_Pagos"
  (pedido_ref, proveedor, fecha, monto_usd, beneficiario, tipo, nota, creado_por)
values
  ('PI NY26-031438','Hugo Wong','2026-09-12', 2400, 'Hugo Wong','saldo',
   'Parte del giro de 3.000 usd (dueno 12/09): 2.400 al pedido de barco. FECHA A CONFIRMAR.','thomas_12092026'),
  ('323ES suelto','Hugo Wong','2026-09-12', 600, 'Hugo Wong','saldo',
   'Parte del giro de 3.000 usd (dueno 12/09): 600 al 323ES suelto = el FOB entero.','thomas_12092026');

-- Queda: 323ES suelto -> pagado 600 de 600, falta 0.
--        PI NY26-031438 -> pagado 16.441, pend giro directo 21.952, falta 247.
-- Criterio tomado: los 2.400 se suman a "pagado" y NO se descuentan del "pend. giro directo"
-- (es el cambio más chico y reversible). Si esos 2.400 salían de los 21.952 pendientes,
-- hay que bajar el pend. giro directo a 19.552 y la falta vuelve a 2.647.

-- rollback
-- delete from public."GV_Imp_Pagos" where creado_por = 'thomas_12092026';
