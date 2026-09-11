-- ══════════════════════════════════════════════════════════════════════════
-- Precios de LÍNEA LOKE pactados con Fede (Chemello / Osa) — 2026-09-11
-- ══════════════════════════════════════════════════════════════════════════
-- Los pasó el dueño textualmente: *"Te paso artículos de Loke que te van a quedar muy
-- competitivos… los que no te estoy pasando es el mismo precio que tenés en Loekemeyer
-- (por todos tus dtos) y ya no podemos ir más abajo de ese precio. Todos van con packaging
-- (azul oscuro) de Loke. Estos precios ya incluyen todos los dtos que tenés en LK y son
-- netos +IVA."*
--
-- → **`es_final = true`**: el precio YA trae los descuentos, así que NO se le aplica el
--   dto_vol del cliente (Osa tiene 16 %) ni el 2 % web. Es neto; el IVA va aparte y el
--   sistema trabaja sin IVA, así que entra tal cual.
--
-- Cliente: **Osa Distribuidora SRL "Chemelo" (LK 2533)**, osadistri@gmail.com, vend 7.
--   "Fede" = Federico Chemello. En el padrón de LK hay DOS códigos de la misma familia:
--   2533 (Osa Distribuidora SRL, dto 0,16) y **1431 Chemello Federico Agustín**
--   (osabazar@hotmail.com, dto 0,12). Se cargó el 2533 porque es el que tiene las líneas
--   sin valorizar y los cuatro códigos exactos. Si el 1431 lleva la MISMA lista, repetir
--   el insert cambiando cod_cliente (ver abajo).
--
-- El `uxb` sale solo de cob_uxb_lk (12) para 102E, 103 y 106E. **198E va con uxb = 12
-- escrito a mano**: ese código no está en products ni en loke_products de LK (vive sólo en
-- item_precios), así que no llega a cob_uxb_lk y sin esto la línea se valorizaba por unidad
-- en vez de por caja ($91.080 en vez de $1.092.960 en la NP 98650).
--
-- ⚠ La lista del catálogo de LK está lejos de estos precios (11/09). Lo que le cotizaría
--    el portal a Osa hoy, contra lo pactado:
--      102E  $905,52 → $1.260  (+39 %)
--      103   $382,79 → $520    (+36 %)
--      106E  $1.078,39 → $1.610 (+49 %)
--      198E  $913,75 → $660    (−28 %)
--    O sea que si Fede pide por la web ve otros números de los que se le van a facturar.
--    Queda avisado; corregir la lista de LK es decisión del dueño.
-- ══════════════════════════════════════════════════════════════════════════

insert into public."GV_Precios_Cliente"
  (empresa, cod_cliente, cod, precio_unit, uxb, es_final, nota, actualizado_por)
values
 ('lk','2533','102E', 1260, null, true, 'Abrelata Mariposa. Precio pactado con Fede (Chemello/Osa), 11/09/2026. Neto, ya incluye todos los dtos de LK; +IVA aparte. Va con packaging Loke azul oscuro.', 'thomas'),
 ('lk','2533','106E', 1610, null, true, 'Sacacorcho Doble Impulso. Precio pactado con Fede (Chemello/Osa), 11/09/2026. Neto, ya incluye todos los dtos de LK; +IVA aparte. Va con packaging Loke azul oscuro.', 'thomas'),
 ('lk','2533','103',   520, null, true, 'Abrelata Uña Inox. Precio pactado con Fede (Chemello/Osa), 11/09/2026. Neto, ya incluye todos los dtos de LK; +IVA aparte. Va con packaging Loke azul oscuro.', 'thomas'),
 ('lk','2533','198E',  660,   12, true, 'Pelador Dentado. Precio pactado con Fede (Chemello/Osa), 11/09/2026. Neto, ya incluye todos los dtos de LK; +IVA aparte. Va con packaging Loke azul oscuro. uxb 12 cargado a mano: 198E no está en products/loke_products de LK (sólo en item_precios), así que no llega a cob_uxb_lk; el 12 sale de v_item_precio de LK.', 'thomas')
on conflict (empresa, cod_cliente, cod) do update
  set precio_unit = excluded.precio_unit, uxb = excluded.uxb, es_final = excluded.es_final,
      nota = excluded.nota, actualizado = now(), actualizado_por = excluded.actualizado_por;

-- Si el mismo precio vale también para Chemello Federico Agustín (LK 1431):
--   insert into public."GV_Precios_Cliente" (empresa, cod_cliente, cod, precio_unit, uxb, es_final, nota, actualizado_por)
--   select 'lk','1431', cod, precio_unit, uxb, es_final, nota, actualizado_por
--     from public."GV_Precios_Cliente" where empresa='lk' and cod_cliente='2533'
--   on conflict (empresa, cod_cliente, cod) do nothing;

-- ── Verificación (NP 98650, Osa) ──────────────────────────────────────────
-- select cod, cajas_ent, uxb, precio_lista, dto_vol, factor_web, importe_ent
--   from public.vista_facturacion_neto_items
--  where cod_cliente = '2533' and cod in ('102E','103','106E','198E') order by cod;
--   102E  200 cj × 12 × 1.260 = $3.024.000
--   103   236 cj × 12 ×   520 = $1.472.640   (faltaron 64 cj = $399.360)
--   106E  200 cj × 12 × 1.610 = $3.864.000
--   198E  138 cj × 12 ×   660 = $1.092.960   (faltaron 362 cj = $2.867.040)
-- select * from public.facturacion_neto_lote(array['98650']);  → $9.453.600, 0 sin precio
