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

-- ─────────────────────────────────────────────────────────────────────────────
-- ADENDA · 2026-09-07, más tarde: la v14.09 de la OTRA sesión renombró las tandas
-- para que ningún número de camión quedara en dos días (D66B → E09A, D66G → E09B).
-- Ese renombre volvió a SEPARAR el 1354: quedó solo en E09B, al lado de la E09A del
-- mismo cliente, mismo día y mismo camión 09. Se volvió a aplicar la regla v14.05
-- (la E09A no tiene ningún evento de operario):
--
--   update public."PPP_Web_Programacion" set tanda = 'E09A'
--    where empresa='lk' and order_id=1354 and np_idx=1 and upper(btrim(tanda))='E09B';
--
-- Verificado después: ningún número de camión en dos días distintos de hoy en
-- adelante (0 filas), o sea que no se rompió lo que arregló la v14.09.
--
-- ROLLBACK de la adenda:
--   update public."PPP_Web_Programacion" set tanda = 'E09B'
--    where empresa='lk' and order_id=1354 and np_idx=1;
