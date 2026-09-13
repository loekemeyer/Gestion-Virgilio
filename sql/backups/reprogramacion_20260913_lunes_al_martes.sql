-- BACKUP · reprogramación del lunes 14/09 al martes 15/09 — ANTES de ejecutar
-- 2026-09-13 (domingo) ~23:00 ART · proyecto Virgilio (hrxfctzncixxqmpfhskv)
--
-- POR QUÉ. Norma del dueño: "todo se factura el día anterior, así que también debe estar armado".
-- Al domingo a la noche, para el lunes 14 la PPP tenía 39 NP: 6 facturadas (D67A Milera/Ganem, D68A Andser)
-- y 33 que NO van a salir el lunes: 5 armadas sin facturar (D67B, D67E), 4 en armado (D67F) y 24 sin ni un
-- evento de picking (D67G–D67M, D68I, E01A, E20A). Ninguna es súper (los súper se miran aparte).
-- Dueño: "todo lo que facturó el viernes es lo único que sale el lunes. Mañana a las 16 hs va a facturar lo
-- aún no facturado + lo que armen el lunes. Eso para el martes." → las 33 pasan al 15/09.
-- Las 6 facturadas NO se tocan. Las ISIS ya tenían override 10/09 → 14/09 (movidas desde la app el 10/09).
--
-- RESTORE: ejecutar todo lo de abajo (vuelve las 33 al lunes 14/09).
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-14'::date, nota = 'v13.87 2026-09-10 09:59 · movida desde la app a 14/09' where np in ('44607','44608','98605','98606','98607','98617','98669','98670','98671','98672','98673','98674','98675','98676','98677','98678','98679','98684');
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-14'::date, nota = 'v13.87 2026-09-10 10:00 · movida desde la app a 14/09' where np in ('98618','98623','98635','98664');
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-14'::date, nota = 'v13.87 2026-09-10 10:02 · movida desde la app a 14/09' where np in ('98686','98687','98688','98689','98690','98691','98692');
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-14'::date where empresa = 'lk' and (order_id, np_idx) in ((1375,1),(1344,1),(1344,2),(1394,1));
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-14'::date where empresa = 'lk' and codigo = 'E20A';

-- ── PASO 2 (mismo domingo, ~23:30) · el martes 15 quedaba en 12,5 m³ (10,3 sin súper) y el cupo de picking es
-- 6 m³/día. Dueño: "reprograma para más adelante, dejá 6 m³ por día (o algo similar); salvo miércoles para el
-- de 9,3 m³ (D71A Matiz)". Sólo se tocó el martes: queda Capital sectores A/B + lo ya tocado (D67B/E/F) = 5,1 m³.
--   · Capital C–H + E03C (D67G D67H D67I D67K D67L D67M E01E E03C E03D, 3,8 m³) → jueves 17.
--   · GBA Sur chicas (D68B D68C D68D D68H D68I, 1,3 m³) → miércoles 16, mismo camión GBA Sur que D71A.
-- RESTORE del paso 2 (vuelve todo al martes 15):
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-15'::date, nota = 'v16.90 2026-09-13 · dueño: "lo que facturó el viernes es lo único que sale el lunes; lo demás para el martes" (no armada/facturada al domingo): 2026-09-14 → 2026-09-15' where np in ('98676','98677','98678','98679','98605','98606','98607','98617','98623','98635','98664','98618','98686','98687','98688','98689','98690','98691','98692');
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-15'::date, nota = 'v13.87 2026-09-10 12:07 · movida desde la app a 15/09' where np in ('98626','98627','98640','98641','98655','98656');
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-15'::date, nota = 'v13.87 2026-09-10 12:08 · movida desde la app a 15/09' where np in ('44618');
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-15'::date where empresa = 'lk' and btrim(tanda) in ('E01E','E03C','E03D','D68I');
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-15'::date where empresa = 'lk' and codigo in ('E01E','E03C','E03D','D68I') and fecha_entrega in ('2026-09-16','2026-09-17');

-- ── PASO 3 (miércoles 16) · quedaba en 16,6 m³ sin súper: GBA Sur 10,6 (D71A Matiz 9,25 + chicas 1,3), GBA Norte
-- 4,3 y GBA Oeste 1,8. Dueño: "el miércoles poné 4 m³ + el pedido grande; primero los pedidos más viejos".
-- Se ordenó por fecha de pedido (fecha_recep) y se llenó hasta ~4 m³: quedan D69B D69G (26/08), D69C (27/08), D68B E11A
-- (28/08), D68C D68D (31/08), D68H (02/09), D69E D69F (04/09), D68I (09/09), E15A (10/09) = 3,97 m³ + Matiz.
-- Salen al viernes 18 las dos de Norte que no entraban: D69D (Orfali, 2,66 m³, pedido 03/09) y E17A (Benitez, 0,77, 08/09).
-- RESTORE del paso 3 (vuelve D69D y E17A al miércoles 16):
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-16'::date where btrim(tanda) in ('D69D','E17A') and fecha_entrega = '2026-09-18';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-16'::date where codigo in ('D69D','E17A') and fecha_entrega = '2026-09-18';

-- ── PASO 4 (jueves 17 y viernes 18) · el jueves quedaba en 10,1 m³ (Capital, 32 paradas). Mismo criterio: 6 m³ por
-- día, primero los pedidos más viejos, tandas enteras. Jueves = D67H D67K D67I D67G D67L D67M E01E E03A E03C E03D
-- E12C (pedidos 26/08–08/09) = 5,56 m³ / 18 paradas. Viernes = Norte (D69D E17A) + Capital E12A E12D E12E = 6,23.
-- Lunes 21 = E12F E12G E12H (pedidos 09/09–11/09) = 2,83.
-- RESTORE del paso 4 (vuelve las 5 tandas al jueves 17):
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-17'::date where btrim(tanda) in ('E12D','E12E') and fecha_entrega = '2026-09-18';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-17'::date where codigo in ('E12D','E12E') and fecha_entrega = '2026-09-18';
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-17'::date where btrim(tanda) in ('E12F','E12G','E12H') and fecha_entrega = '2026-09-21';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-17'::date where codigo in ('E12F','E12G','E12H') and fecha_entrega = '2026-09-21';

-- ── PASO 5 · el aviso "cliente con entregas en días distintos de la misma semana" marcó 4 clientes partidos por
-- los pasos 2–4. Se juntan sin salir de ~6 m³/día: Dapelo entero el martes (D67G D67L D67M vuelven con D67E/F),
-- E03B al jueves con E03C/E03D (compensa); Aloe Dario + Bazar Mandarin juntos el jueves (E12D del viernes y
-- E12F del lunes 21 se suman a E12C); E03A al viernes (compensa). Andser queda partido a propósito: 98637 está
-- facturada para el lunes y LK 0052 (0,03 m³) no está armada → el dueño decide.
-- RESTORE del paso 5:
update public."GV_PPP_Prog_Override" set fecha_entrega = '2026-09-17'::date, nota = regexp_replace(nota, '^v16\.90 2026-09-13 · Dapelo va junto[^A]*Antes: ', '') where np in ('98676','98677','98678','98679','98686','98687','98688','98689','98690','98691','98692') and fecha_entrega = '2026-09-15';
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-15'::date where btrim(tanda) = 'E03B' and fecha_entrega = '2026-09-17';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-15'::date where codigo = 'E03B' and fecha_entrega = '2026-09-17';
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-18'::date where btrim(tanda) = 'E12D' and fecha_entrega = '2026-09-17';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-18'::date where codigo = 'E12D' and fecha_entrega = '2026-09-17';
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-21'::date where btrim(tanda) = 'E12F' and fecha_entrega = '2026-09-17';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-21'::date where codigo = 'E12F' and fecha_entrega = '2026-09-17';
update public."PPP_Web_Programacion" set fecha_entrega = '2026-09-17'::date where btrim(tanda) = 'E03A' and fecha_entrega = '2026-09-18';
update public."PPP_Web_Tandas" set fecha_entrega = '2026-09-17'::date where codigo = 'E03A' and fecha_entrega = '2026-09-18';

-- ── PASO 6 · RENUMERACIÓN: la app cuenta un camión por NÚMERO de tanda (v13.07) y el dueño fijó "máximo 2 camiones
-- por día". Sólo se renumeran tandas SIN eventos (ninguna tocada). Luján E11A queda aparte (kangoo propia, decisión
-- del 11/09). Súper y Retira no cuentan.
--   Mar 15: camión D67 (D67B E F G J L M + D68J→D67N) · camión E01 (E01A B C F + E03E→E01G + E20A→E01H)
--   Mié 16: camión D71 GBA Sur (D71A + D68B→D71B D68C→D71C D68D→D71D D68H→D71E D68I→D71F) · camión D69 Norte+Oeste
--           (D69B C E F G + E15A→D69H) · E11A Luján kangoo
--   Jue 17: camión E03 Capital Sur (E03B E03C + E12D→E03F E12F→E03G) · camión E12 resto (E12C + D67H→E12I D67I→E12J
--           D67K→E12K E01E→E12L E03D→E12M)
--   Vie 18: camión E17 Norte (E17A + D69D→E17B) · camión E12 Capital (E12A E12E + E03A→E12N)
-- RESTORE del paso 6 (vuelve los códigos originales):
update public."GV_PPP_Prog_Override" set tanda = 'D68J' where np = '98694' and tanda = 'D67N';
update public."GV_PPP_Prog_Override" set tanda = null where np in ('98626','98627') and tanda = 'D71B';
update public."GV_PPP_Prog_Override" set tanda = null where np in ('98640','98641') and tanda = 'D71C';
update public."GV_PPP_Prog_Override" set tanda = null where np in ('98655','98656') and tanda = 'D71D';
update public."GV_PPP_Prog_Override" set tanda = null where np = '44618' and tanda = 'D71E';
update public."GV_PPP_Prog_Override" set tanda = null where np in ('98605','98606','98607','98617') and tanda = 'E12I';
update public."GV_PPP_Prog_Override" set tanda = null where np in ('98623','98635','98664') and tanda = 'E12J';
update public."GV_PPP_Prog_Override" set tanda = null where np = '98618' and tanda = 'E12K';
update public."PPP_Web_Programacion" set tanda = 'E03E' where btrim(tanda) = 'E01G';
update public."PPP_Web_Programacion" set tanda = 'E20A' where btrim(tanda) = 'E01H';
update public."PPP_Web_Programacion" set tanda = 'D68I' where btrim(tanda) = 'D71F';
update public."PPP_Web_Programacion" set tanda = 'E15A' where btrim(tanda) = 'D69H';
update public."PPP_Web_Programacion" set tanda = 'E12D' where btrim(tanda) = 'E03F';
update public."PPP_Web_Programacion" set tanda = 'E12F' where btrim(tanda) = 'E03G';
update public."PPP_Web_Programacion" set tanda = 'E01E' where btrim(tanda) = 'E12L';
update public."PPP_Web_Programacion" set tanda = 'E03D' where btrim(tanda) = 'E12M';
update public."PPP_Web_Programacion" set tanda = 'D69D' where btrim(tanda) = 'E17B';
update public."PPP_Web_Programacion" set tanda = 'E03A' where btrim(tanda) = 'E12N';
update public."PPP_Web_Tandas" set codigo = 'E20A' where codigo = 'E01H';
update public."PPP_Web_Tandas" set codigo = 'E15A' where codigo = 'D69H';
update public."PPP_Web_Tandas" set codigo = 'E03E' where codigo = 'E01G';
update public."PPP_Web_Tandas" set codigo = 'D68I' where codigo = 'D71F';
update public."PPP_Web_Tandas" set codigo = 'E12D' where codigo = 'E03F';
update public."PPP_Web_Tandas" set codigo = 'E12F' where codigo = 'E03G';
update public."PPP_Web_Tandas" set codigo = 'E01E' where codigo = 'E12L';
update public."PPP_Web_Tandas" set codigo = 'E03D' where codigo = 'E12M';
update public."PPP_Web_Tandas" set codigo = 'D69D' where codigo = 'E17B';
update public."PPP_Web_Tandas" set codigo = 'E03A' where codigo = 'E12N';
