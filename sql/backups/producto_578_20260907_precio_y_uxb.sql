-- BACKUP + CAMBIO · public.products (proyecto LK, kwkclwhmoygunqmlegrg) — 2026-09-07
--
-- QUÉ SE PIDIÓ. Dueño 07/09: *"578, 12 x caja. precio por ahora ponele $1000"*.
--
-- EL CASO. El pedido web 1354 de Osa Distribuidora (cód 2533) lleva 5 cajas del artículo
-- **578 Descarozador De Aceitunas**. El artículo estaba dado de baja desde siempre en el catálogo
-- (`active = false`), con `list_price = 0` y `uxb = 1`, y —lo importante— NO figuraba en
-- `precios_venta` de Virgilio, que es de donde `gv_ppp_np_valor` saca el valor. Resultado: la NP
-- `LK 0024` llegaba a Facturación valorizada en **$0**.
--
-- POR QUÉ ALCANZA CON TOCAR EL PRECIO (y no hay que activar el artículo). La Edge Function
-- `sync-precios-venta` (Virgilio) lee `products` de LK **sin filtrar por `active`**: el único
-- filtro es `list_price > 0`. Así que poniéndole precio entra a `precios_venta` igual, y el
-- artículo SIGUE FUERA de la web. Eso era la duda del dueño: activarlo lo habría publicado para
-- los ~1200 clientes del portal, no sólo para Osa. **No se activó.**
--
-- ESTADO ANTERIOR (esto es el backup — un solo registro):
--
--   cod = '578'
--   description = 'Descarozador De Aceitunas'
--   category    = 'Cortadores'
--   active      = false
--   list_price  = 0
--   uxb         = 1
--   id          = '3d7deb07-96b7-45de-b8b3-f85bb1c49058'
--
-- ROLLBACK (en LK):
--   update public.products set list_price = 0, uxb = 1 where cod = '578';
--   -- y después refrescar la lista de Virgilio, que si no se queda con el precio viejo:
--   -- (en VIRGILIO) select net.http_post(
--   --   url := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/sync-precios-venta',
--   --   headers := '{"Content-Type":"application/json"}'::jsonb, body := '{}'::jsonb);
--   -- ⚠ el 578 queda igual en precios_venta con precio 0 → el upsert lo saltea (filtra > 0).
--   --   Para sacarlo del todo: delete from public.precios_venta where cod = '578';
--
-- VERIFICADO DESPUÉS DEL CAMBIO:
--   precios_venta 578 → precio_unit 1000 · uxb 12 · actualizado 2026-09-07 11:09
--   gv_ppp_np_valor 'LK 0024' → valor_lista 60000 · lineas_sin_precio 0
--   (5 cajas × 12 unidades × $1.000 = $60.000)
--
-- PENDIENTE DEL DUEÑO: el precio es provisorio ("por ahora ponele $1000"). Cuando pase el real,
-- se cambia igual que acá y se vuelve a correr el sync.

-- ===== LO QUE SE EJECUTÓ =====

-- 1) en LK (kwkclwhmoygunqmlegrg)
update public.products
   set list_price = 1000, uxb = 12
 where cod = '578';
-- active queda en false a propósito: NO se publica en la web.

-- 2) en VIRGILIO (hrxfctzncixxqmpfhskv) — traer el precio a la lista que usa Gestión
select net.http_post(
  url     := 'https://hrxfctzncixxqmpfhskv.supabase.co/functions/v1/sync-precios-venta',
  headers := '{"Content-Type":"application/json"}'::jsonb,
  body    := '{}'::jsonb
);

-- 3) verificación
select cod, precio_unit, uxb, descripcion, actualizado from public.precios_venta where cod = '578';
select np, valor_lista, lineas_sin_precio from public.gv_ppp_np_valor where np = 'LK 0024';
