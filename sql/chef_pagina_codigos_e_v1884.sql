-- Códigos E de Chef en la PÁGINA CH — v18.84, 2026-09-16
-- Pedido de Thomas: "en el programa GV que ya estén, y corregir en Página CH.
--                    salvo los que tengamos stock hoy sin la E"
--
-- 📄 GEMELO en el repo de la página: `paginach/sql/codigos_e_630_631_v20260916.sql`
-- (mismo contenido; se dejó también allá porque es donde vive el SQL de ese proyecto).
--
-- ⚠ ESTE ARCHIVO NO SE CORRIÓ. Va ejecutado a mano en el SQL Editor del proyecto
-- Supabase de CHEF (nkhzocgdpwtgrmwleihr), que NO está en el MCP de esta cuenta.
-- (El FDW `chef_db` de LK entra como `loke_reader`, o sea SOLO LECTURA: el UPDATE
--  contesta `permission denied for table products`. Por eso queda acá y no aplicado.)
--
-- ── Qué se corrige y qué NO ────────────────────────────────────────────────────
-- Stock medido en Gestión el 2026-09-16 (`public.vista_saldos_stock`, terminado +
-- excedente + racks + …):
--
--   630 → 0      ✅ se pasa a 630E
--   631 → 0      ✅ se pasa a 631E
--   634 → 24     ⛔ NO se toca (hay stock sin la E: 12 terminado + 12 excedente)
--   635 → 11     ⛔ NO se toca (11 terminado)
--   636 → 20     ⛔ NO se toca (4 terminado + 16 excedente)
--
-- Los tres que quedan se corrigen recién cuando ese stock llegue a 0. Volver a
-- correr la medición antes:
--
--   -- en GESTIÓN (hrxfctzncixxqmpfhskv)
--   select cod_art, coalesce(terminado,0)+coalesce(excedente,0)+coalesce(separar_pedidos,0)
--        + coalesce(a_facturar,0)+coalesce(a_guardar,0)+coalesce(racks,0)
--        + coalesce(racks_ch,0)+coalesce(para_envasar,0) total
--     from public.vista_saldos_stock
--    where upper(btrim(cod_art)) in ('634','635','636');
--
-- El bulto NO cambia: **todos van x12** (Thomas, 16/09). Ya es lo que dice `uxb` en la
-- página, `OC_Maximos`, y ahora también `Articulos_Cajas` (los 631E/634E/635E/636E estaban
-- cargados en 24 y se corrigieron — ver §3.hz de docs/SUPABASE-GESTION-VIRGILIO.md).
--
-- ── Por qué RENOMBRAR y no crear un producto nuevo ────────────────────────────
-- Es el mismo artículo con otro código. `order_items` de la página referencia
-- `product_id` (uuid), no el texto del código, así que renombrar no rompe ningún
-- pedido viejo, y el producto conserva precio, imágenes, orden de catálogo,
-- ranking y categoría. Es un UPDATE de una columna: se deshace igual de fácil.
--
-- Aguas abajo no hay que tocar nada más: `public.precios_venta_chef` de Gestión es
-- un espejo del catálogo de Chef (se actualizó hoy 11:30), así que el precio pasa
-- solo a figurar bajo el código nuevo.
--
-- ═══ 1) BACKUP — correr y GUARDAR el resultado antes de tocar nada ═════════════
select id, cod, description, uxb, list_price, active, category, subcategory,
       orden_catalogo, ranking, badge_status
  from public.products
 where cod in ('630','631','634','635','636','630E','631E','634E','635E','636E')
 order by cod;
-- Al 2026-09-16 tiene que devolver 5 filas, todas SIN la E (ninguna 630E…636E).

-- ═══ 2) EL CAMBIO ═════════════════════════════════════════════════════════════
-- El `and cod = '...'` es a propósito: si alguien ya lo renombró, el UPDATE toca
-- 0 filas en vez de pisar otra cosa.
update public.products set cod = '630E'
 where id = 'd006e49c-4064-4efb-8869-c05986d06a29' and cod = '630';   -- Cucharón Ac. Inox.
update public.products set cod = '631E'
 where id = '6215de36-16d2-435b-bb68-6aea8daaa151' and cod = '631';   -- Espumadera Ac. Inox.

-- ═══ 3) VERIFICACIÓN ══════════════════════════════════════════════════════════
select cod, description, uxb, list_price, active from public.products
 where id in ('d006e49c-4064-4efb-8869-c05986d06a29','6215de36-16d2-435b-bb68-6aea8daaa151');
-- Esperado: 630E Cucharón Ac. Inox. · 631E Espumadera Ac. Inox.

-- ═══ 4) ROLLBACK (si hiciera falta) ═══════════════════════════════════════════
-- update public.products set cod = '630' where id = 'd006e49c-4064-4efb-8869-c05986d06a29';
-- update public.products set cod = '631' where id = '6215de36-16d2-435b-bb68-6aea8daaa151';

-- ═══ 5) Cuando 634/635/636 lleguen a stock 0 ══════════════════════════════════
-- update public.products set cod = '634E' where id = 'd91ef2e8-8ad2-49bf-892b-2919891003f6' and cod = '634';  -- Cuchara Calada
-- update public.products set cod = '635E' where id = '3b749e49-8bce-4875-bfd0-c94e0810ecd4' and cod = '635';  -- Espátula Lisa
-- update public.products set cod = '636E' where id = '199505b7-8c05-4d60-9943-de628cb6f8c4' and cod = '636';  -- Espátula Calada
