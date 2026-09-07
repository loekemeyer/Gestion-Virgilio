-- Backup 2026-09-07 ANTES de borrar el pedido de PRUEBA 1352 (Muller y Muller S.R.L., cod 862, cargado a mano el
-- 06/09 20:30 para probar el circuito; nunca salió a ISIS ni disparó WhatsApp). Dueño 07/09: "Sí, borralo".
-- Restore Virgilio (hrxfctzncixxqmpfhskv): ejecutar estos tres inserts. LK (kwkclwhmoygunqmlegrg): ver el bloque de abajo.

insert into public."PPP_Web_NP" (empresa, np, order_id, np_idx, creado_at)
values ('lk', 1352, 1352, 1, '2026-09-06 20:30:11.660509-03') on conflict do nothing;

insert into public."PPP_Web_Base" (empresa, order_id, np_idx, np_label, articulo, cajas, creado_at)
values ('lk', 1352, 1, 'LK 1352', '505', 100, '2026-09-06 20:30:12.062785-03') on conflict do nothing;

insert into public."PPP_Web_Programacion" (empresa, order_id, np_idx, np, cod_cliente, razon_social, direccion, barrio, tanda, zona, fecha_entrega, op, observaciones, m3, m3_parcial, lineas, cajas, creado_por, creado_at, actualizado_at, fecha_recep, es_agregado, agregado_a_np, agregado_en, prioridad, np_total)
values ('lk', 1352, 1, 1352, '862', 'Muller Y Muller S.R.L.', 'Exp. Fontana — PEDRO BALLINA  4060, Pompeya (De L Americas 4384- Parana)', 'Pompeya', 'E03B', 'Zona 1 - CABA Sur', '2026-09-15', null, null, 0.24, false, 1, 100, 'sistema', '2026-09-06 20:30:11.85244-03', '2026-09-06 20:40:59.916696-03', null, false, null, null, 0, null)
on conflict (empresa, order_id, np_idx) do nothing;

-- LK: orders id=1352 y order_items order_id=1352 — filas completas más abajo (se agregan al tomar el backup).

-- ── LK (kwkclwhmoygunqmlegrg) ──────────────────────────────────────────────────────────
insert into public.orders (id, created_at, auth_user_id, customer_id, status, payment_method, payment_discount, web_discount, subtotal, total, sheets_sent, sheets_payload, is_promo, extra_discount, enviado_a_compras_at, placed_by_auth_user_id, customer_code)
values (1352, '2026-09-06 23:21:52.752393+00', '53b9c36e-d66d-43a1-af57-edd7f39e0c5b', '88f046d9-2c3f-4bfe-99f1-568e483f960b', 'pendiente', 'Pago Contado: 25% Dto', 0.25, 0.02, 1640880, 1206046.8, true,
 '{"d":"OK","lc":"OK","pp":"3","mode":"new","vend":"1","deuda":0,"items":[{"uxb":12,"cajas":100,"cod_art":"505","cod_original":null}],"source":"Web","is_promo":false,"cod_cliente":"862","order_total":1206046.8,"credit_limit":79000000,"order_number":"1352","payment_term":3,"cliente_nuevo":"","observaciones":"PEDIDO DE PRUEBA - BORRAR","condicion_pago":"Pago Contado: 25% Dto","extra_discount":0,"sucursal_entrega":"De L Americas 4384- Parana","condicion_pago_code":8}'::jsonb,
 false, 0, null, null, '862')
on conflict (id) do nothing;

insert into public.order_items (id, order_id, product_id, cajas, uxb, unit_list_price, unit_your_price, line_total, created_at, loke_product_id, is_loke, source)
values (18876, 1352, '7b0848ef-1ea5-4dba-b865-27d4a53a6b73', 100, 12, 0, 0, 0, '2026-09-06 23:22:38.743059+00', null, false, 'catalogo')
on conflict (id) do nothing;
-- ⚠ sheets_sent = true para que retry-sheets NO lo empuje al Google Sheet → ERP.
