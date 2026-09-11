-- v15.90 — la PPP dice QUÉ pasó con cada OC de súper de Krikos.
--
-- Complemento del importador automático, que vive en el proyecto de LK
-- (sql/krikos_auto_import.sql de pagina-lk-copia + Edge Function krikos-auto-import).
-- Acá sólo se agrandan la tabla espejo y el aviso de A Programar.
--
-- Regla del dueño (2026-09-11): "Siempre quiero que se cargue directo a PPP y si la
-- lógica del importe NO DA, QUE LO ACLARE MUY GRANDE EN PPP".

------------------------------------------------------------------------------
-- EN VIRGILIO (hrxfctzncixxqmpfhskv) — APLICADO
------------------------------------------------------------------------------
alter table public."GV_Krikos_OC"
  add column if not exists auto_estado text,   -- ok | parcial | no | salteada | null
  add column if not exists auto_aviso  text,   -- qué fue lo que no dio, en castellano
  add column if not exists auto_at     timestamptz,
  add column if not exists order_id    bigint; -- pedido de LK que se creó, si entró

-- Nada más cambia acá: la tabla ya tenía RLS prendida, la policy de lectura para anon
-- y la de escritura para lk_ppp_reader (sin ésa el sync inserta 0 filas SIN dar error).

------------------------------------------------------------------------------
-- EN LK (kwkclwhmoygunqmlegrg) — APLICADO
------------------------------------------------------------------------------
-- alter foreign table virgilio."GV_Krikos_OC"
--   add column if not exists auto_estado text, add column if not exists auto_aviso text,
--   add column if not exists auto_at timestamptz, add column if not exists order_id bigint;
--
-- create or replace function public.sync_krikos_oc_virgilio() ...
--   ahora manda también auto_estado / auto_aviso / auto_at / order_id, y el WHERE es:
--     (estado = 'pendiente' and order_id is null)          -- las que están esperando
--     or (auto_estado = 'parcial'                          -- las que entraron con algo
--         and auto_at > now() - interval '7 days')         --   que no dio: 7 días
--   Las que entraron limpias NO viajan: ya son un pedido normal en la PPP.

------------------------------------------------------------------------------
-- MEDICIÓN
------------------------------------------------------------------------------
-- En LK:       select public.sync_krikos_oc_virgilio();   → 6
-- En Virgilio: select count(*) from public."GV_Krikos_OC"; → 6
-- Detalle del importador y su medición: docs/SUPABASE-GESTION-VIRGILIO.md §3.cp

------------------------------------------------------------------------------
-- ROLLBACK
------------------------------------------------------------------------------
-- alter table public."GV_Krikos_OC" drop column if exists auto_estado,
--   drop column if exists auto_aviso, drop column if exists auto_at, drop column if exists order_id;
-- (Y volver sync_krikos_oc_virgilio a la versión de sql/gv_krikos_oc_v1585.sql.)
-- El front tolera las columnas vacías: sin auto_estado, el cartel se dibuja como en la v15.85.
