-- Backup previo a dar de baja la linea Acacia no repuesta (991E, 994E, 995E, 999E).
-- Proyecto LK kwkclwhmoygunqmlegrg, tabla public.products.
-- Tomado 2026-09-11. Tarea Planify 3105 (Luis Rial Otero).
-- Restore: correr estas 4 sentencias.

update public.products set active=true  where cod='991E'; -- Espatula Corta Torta Mgo Acacia
update public.products set active=false where cod='994E'; -- Pelador Mgo Acacia
update public.products set active=false where cod='995E'; -- Rallador Mgo Acacia
update public.products set active=false where cod='999E'; -- Pica Ajo Mgo Acacia

-- Estado al momento del backup:
--  cod   active  list_price  uxb
--  991E  true    4155        12
--  994E  false   3395        12
--  995E  false   4015        12
--  999E  false   8375        12
