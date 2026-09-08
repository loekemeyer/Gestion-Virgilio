-- ============================================================
--  Cobranzas — cargar los precios de CHEF en Virgilio
--
--  ✅ YA NO ES NECESARIO (v14.44, 2026-09-08). La Edge Function sync-precios-venta
--  ahora llena `precios_venta_chef` sola, todos los días, leyendo Chef con la
--  CHEF_KEY publishable (`supabase/functions/sync-precios-venta/index.ts`). Este
--  SELECT queda sólo como carga manual de emergencia si el cron falla. NO correrlo
--  en un día normal: pisaría los precios frescos con los del momento de la copia.
--
--  (Histórico) Antes SEGUÍA MANUAL (2026-08-28): la Edge Function sólo mergeaba
--  Chef dentro de `precios_venta` con "Chef gana", lo que ensuciaba las NP de LK
--  con códigos compartidos (809E). Ver §3.bi de docs/SUPABASE-GESTION-VIRGILIO.md.
--
--  Chef vive en OTRO proyecto Supabase (nkhzocgdpwtgrmwleihr) y Virgilio no
--  tiene FDW contra él, así que el sync es en dos pasos:
--
--  PASO 1 — Correr ESTE SELECT en el SQL Editor del proyecto CHEF
--           (nkhzocgdpwtgrmwleihr). Devuelve UNA fila con un texto: es un
--           INSERT enorme ya armado.
--  PASO 2 — Copiar ese texto y ejecutarlo en el SQL Editor de VIRGILIO
--           (hrxfctzncixxqmpfhskv). Rellena public.precios_venta_chef.
--
--  Se puede repetir cuando cambien los precios de Chef (hace upsert).
--  Si Chef además tiene línea Loeke en `loke_products`, descomentar el UNION.
-- ============================================================

-- ░░ PASO 1 — EJECUTAR EN EL PROYECTO CHEF (nkhzocgdpwtgrmwleihr) ░░
select 'insert into public.precios_venta_chef (cod, precio_unit, uxb, descripcion) values ' ||
  string_agg(
    '(' || quote_literal(btrim(cod)) || ',' || nullif(list_price,0)::text || ',' ||
    coalesce(uxb::text,'null') || ',' || quote_literal(coalesce(left(description,120),'')) || ')',
    ',') ||
  ' on conflict (cod) do update set precio_unit=excluded.precio_unit,' ||
  ' uxb=excluded.uxb, descripcion=excluded.descripcion, actualizado=now();' as ejecutar_en_virgilio
from (
  select cod, list_price, uxb, description
    from public.products
   where coalesce(list_price,0) > 0 and btrim(coalesce(cod,'')) <> ''
  -- union all
  -- select cod, list_price, uxb, description
  --   from public.loke_products
  --  where coalesce(list_price,0) > 0 and btrim(coalesce(cod,'')) <> ''
) t;

-- ░░ PASO 2 — pegar el resultado y ejecutarlo en VIRGILIO ░░
-- (queda automático: el texto ya trae el INSERT ... ON CONFLICT completo)

-- Verificación en Virgilio después de cargar:
--   select count(*) from public.precios_venta_chef;
--   select empresa, count(*) nps, round(sum(valor_lista)) valor
--     from public.cobranzas_resumen() group by empresa;   -- Chef ya deja de dar 0
