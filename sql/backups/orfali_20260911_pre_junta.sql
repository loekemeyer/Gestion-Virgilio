-- BACKUP 2026-09-11 — antes de juntar los dos pedidos de Orfali Alfredo Luciano (4188, zona 6).
-- Estaban en dos días distintos: LK 0053 solo en E13A el 15/09 (1 caja del art. 321, 0,019 m³) y
-- LK 0002 en D69D el 16/09 (1,184 m³). Orden de Thomas: "los dos pedidos de orfali tienen que
-- salir si o si juntos". Ninguna de las dos tandas tenía eventos de operario ni filas en
-- PPP_Web_Tanda_Items al momento del cambio.
--
-- RESTORE (deja todo como estaba):
update public."PPP_Web_Programacion" set tanda='D69D', fecha_entrega='2026-09-16', zona='Zona 6 - GBA Norte', actualizado_at='2026-09-10 12:10:50.584445-03' where empresa='lk' and order_id=1341 and np_idx=1;   -- Orfali Alfredo Luciano NP 2
update public."PPP_Web_Programacion" set tanda='E13A', fecha_entrega='2026-09-15', zona='Zona 6 - GBA Norte', actualizado_at='2026-09-09 13:45:16.359624-03' where empresa='lk' and order_id=1376 and np_idx=1;   -- Orfali Alfredo Luciano NP 53
