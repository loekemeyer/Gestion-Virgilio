-- BACKUP · 2026-09-07 · fila del pedido 1354 (Osa Distribuidora) ANTES de juntarla a la D66B.
-- Contexto: la regla v14.05 dice que si la tanda que el cliente ya tiene ese día está intacta,
-- el pedido va ADENTRO. La D66B (ISIS, 09/09) no tiene ningún evento de operario, así que el
-- 1354 —que estaba en una tanda propia D66G del mismo día y mismo camión 66— se junta ahí.
-- El dueño dijo "me da igual", así que se aplicó la regla: un camión, una tanda.
--
-- Estado exacto de la fila antes del cambio:
--   order_id 1354 · np_idx 1 · np 24 · cod 2533 · "Osa Distribuidora SRLChemelo"
--   tanda D66G · Zona 1 - CABA Sur · fecha_entrega 2026-09-09 · m3 0,026 · 1 línea · 5 cajas
--
-- ROLLBACK: ejecutar el update de abajo.
update public."PPP_Web_Programacion"
   set tanda = 'D66G'
 where empresa = 'lk' and order_id = 1354 and np_idx = 1;
