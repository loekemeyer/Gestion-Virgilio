-- ============================================================
-- v9.38 — vista_np_faltantes_secuencia: NP salteadas en la secuencia numérica
-- Proyecto Supabase: Control Partes Talleristas (hrxfctzncixxqmpfhskv)
--
-- Detecta NÚMEROS DE NP que faltan entre NPs que sí existen (huecos ≤5). Ej: si están
-- 98576 y 98578 pero no 98577 → 98577 aparece como faltante. Puede ser un pedido que no
-- se cargó a Virgilio, o una NP anulada en el ERP. Se usa en el módulo "Pedidos sin cargar
-- en PPP" (stkOpenNpFaltan), como sección aparte.
--
-- Universo de NP "existentes" = unión de todas las fuentes que conocen una NP:
--   PPP_Base_Pedidos ∪ PPP_Programacion_Diaria ∪ Facturacion_NP ∪ PPP_Entregados_Meta ∪ NP_Canceladas
-- Solo NP numéricas (se ignora ".0" final). Solo huecos de 1 a 5 faltantes (nxt-n entre 2 y 6),
-- para no marcar los saltos grandes entre series (44xxx Chef ↔ 98xxx Loeke).
-- ============================================================

create or replace view public.vista_np_faltantes_secuencia as
with nums as (
  select distinct (regexp_replace(btrim(np), '\.0+$', ''))::bigint n
  from (
    select pedido::text np from "PPP_Base_Pedidos"
    union select np::text from "PPP_Programacion_Diaria"
    union select np::text from "Facturacion_NP"
    union select np::text from "PPP_Entregados_Meta"
    union select np::text from "NP_Canceladas"
  ) u
  where regexp_replace(btrim(np), '\.0+$', '') ~ '^\d+$'
),
ordered as (select n, lead(n) over (order by n) nxt from nums)
select gs::text as np_faltante, n as anterior, nxt as siguiente
from ordered, lateral generate_series(n + 1, nxt - 1) gs
where nxt is not null and nxt - n between 2 and 6;

alter view public.vista_np_faltantes_secuencia set (security_invoker = on);
grant select on public.vista_np_faltantes_secuencia to anon, authenticated;
