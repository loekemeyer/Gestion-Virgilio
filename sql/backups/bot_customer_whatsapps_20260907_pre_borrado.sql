-- BACKUP de public.bot_customer_whatsapps — proyecto LK (kwkclwhmoygunqmlegrg)
-- 2026-09-07 00:35 ART · las 5 filas que tenía la tabla, ANTES de vaciarla.
--
-- POR QUÉ SE BORRÓ. Dueño 07/09: las 5 son WhatsApp de PRUEBA, ninguna de un cliente real
-- ("fueron wpp de prueba" · "209 y 217 también son de prueba" · "borralos"). Dos de ellas además
-- tenían la razón social metida en la columna `empresa` ("Urriza Mariela", "Lin Xiuhui") y una
-- tenía `cod_cliente` en null — lo que figuraba como pendiente 6 en docs/PENDIENTES-PIPELINE-GESTION.md.
-- No se corrigieron: se borraron, porque el trigger `orders_notify_whatsapp` de LK le manda un
-- WhatsApp al cliente cuando carga un pedido usando esta tabla, y con estas filas un pedido real
-- de Urriza (4197), Lin Xiuhui (4260), Pro Tatiana (4234) o Torres Y Liva (288) le habría mandado
-- el aviso a un número de prueba.
--
-- RESTORE: ejecutar los 5 inserts de abajo en el proyecto LK.
-- Después de restaurar, poner el contador al día:
--   select setval(pg_get_serial_sequence('public.bot_customer_whatsapps','id'),
--                 (select max(id) from public.bot_customer_whatsapps));

insert into public.bot_customer_whatsapps (id, customer_id, whatsapp, is_primary, created_at, empresa, cod_cliente, permiso_ver_pedidos) values (209, '0835f54c-f4d9-4619-b814-8e00eaf5cb7f'::uuid, '5491162521635', true, '2026-05-15 19:38:46.899882+00'::timestamptz, 'LK', 4234, true);
insert into public.bot_customer_whatsapps (id, customer_id, whatsapp, is_primary, created_at, empresa, cod_cliente, permiso_ver_pedidos) values (217, '0059eb76-85d0-4d81-8e8e-2c86d7302c4c'::uuid, '5491131181594', true, '2026-06-03 17:43:53.912041+00'::timestamptz, 'LK', 288, true);
insert into public.bot_customer_whatsapps (id, customer_id, whatsapp, is_primary, created_at, empresa, cod_cliente, permiso_ver_pedidos) values (218, 'b836c23b-5931-45db-94f6-f26f07ac4517'::uuid, '5491126259898', true, '2026-06-03 17:57:03.704712+00'::timestamptz, 'Urriza Mariela', 4197, true);
insert into public.bot_customer_whatsapps (id, customer_id, whatsapp, is_primary, created_at, empresa, cod_cliente, permiso_ver_pedidos) values (220, '04f11bf3-5ab3-459d-be0e-f4c70a1f8da7'::uuid, '5491164880712', true, '2026-06-03 20:26:54.670608+00'::timestamptz, 'Lin Xiuhui', 4260, true);
insert into public.bot_customer_whatsapps (id, customer_id, whatsapp, is_primary, created_at, empresa, cod_cliente, permiso_ver_pedidos) values (222, '04f11bf3-5ab3-459d-be0e-f4c70a1f8da7'::uuid, '5491131181027', false, '2026-06-05 19:58:51.570192+00'::timestamptz, 'LK', null, false);
