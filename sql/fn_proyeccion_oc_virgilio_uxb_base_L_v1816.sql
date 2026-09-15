-- =====================================================================================
-- fn_proyeccion_oc_virgilio_uxb_base_L_v1816.sql — EL UXB DE LOS CODIGOS NNNL
-- Proyecto: LK (kwkclwhmoygunqmlegrg).  ✅ APLICADO el 2026-09-15.
-- Problema 218 de github_repo_problemas, segunda mitad (§1b del handoff del 15/09).
--
-- QUE ESTABA MAL
-- ---------------------------------------------------------------------------------
-- 513L es la variante con la que Chef le vende mercaderia de Loeke: mismo articulo que
-- 513, sin ficha propia en `products` ni en `loke_products`. `fn_proyeccion_oc_virgilio()`
-- calculaba  proy_uni_mes = proy_cajas * coalesce(p.uxb, lk.uxb, 1)  y para esos codigos
-- el coalesce caia en 1, o sea 12 o 24 veces por debajo de las unidades reales.
--
--   · proy_cajas_mes de los NNNL estaba BIEN (sale de sales_lines.boxes, ya viene en cajas)
--   · proy_uni_mes estaba MAL
--   · `vista_generador_oc` de Virgilio suma proy_uni_mes y divide por GV_UxB, asi que NO
--     era inmune: contaba 145,34 cj/mes donde la demanda real era 1.610,56.
--
-- EL ARREGLO. Si el codigo no tiene uxb propio, se resuelve el del codigo BASE pelando la
-- L, con la misma regla que `gv_cod_stock()` de Virgilio: '([0-9E])L$' -> '\1', o sea solo
-- si la L viene detras de un digito o de una E. El coalesce queda en capas:
--     uxb propio -> uxb del base -> 1
-- asi que un NNNL que algun dia tenga ficha propia sigue usando la suya.
--
-- MEDIDO el 2026-09-15 (461 filas antes y despues, no multiplica):
--   · 124 filas NNNL, las 124 sin uxb propio; 121 bases en products + 3 en loke_products
--   · despues del cambio: 0 NNNL sin uxb; 1.610,56 cj/mes -> 20.396 unidades (antes 1.610)
--   · en `vista_generador_oc`: 123 codigos suben, +1.464,45 cj/mes de proyeccion
--     (comparado contra zz_backups."GV_Backup_ProyeccionMadre_20260915", de Virgilio)
--
-- ⚠ ORDEN: esto va ANTES de fundir el CTE `proy` de `vista_stock_procesada` (v18.16), que
--   es justo lo que el archivo v18.11 dejaba para despues.
-- =====================================================================================

CREATE OR REPLACE FUNCTION public.fn_proyeccion_oc_virgilio()
 RETURNS TABLE(cod text, proy_cajas_mes numeric, uxb integer, proy_uni_mes numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '60s'
AS $function$
  with p6 as (select item, proy_cajas from public._fn_proy_window(6)),
       p12 as (select item, proy_cajas from public._fn_proy_window(12)),
       merged as (
         select coalesce(p6.item, p12.item) as item,
                case when coalesce(p6.proy_cajas, 0) > 0 then p6.proy_cajas
                     when coalesce(p12.proy_cajas, 0) > 0 then p12.proy_cajas
                     else 0 end as proy_cajas
         from p6 full join p12 on p12.item = p6.item
       ),
       conbase as (
         select item, proy_cajas, regexp_replace(item, '([0-9E])L$', '\1') as base
         from merged
       )
  select m.item as cod, m.proy_cajas as proy_cajas_mes,
         coalesce(p.uxb, lk.uxb, pb.uxb, lkb.uxb)::integer as uxb,
         round(m.proy_cajas * coalesce(p.uxb, lk.uxb, pb.uxb, lkb.uxb, 1))::numeric as proy_uni_mes
  from conbase m
  left join public.products p on regexp_replace(upper(p.cod),'^0+(?=.)','') = m.item
  left join public.loke_products lk on regexp_replace(upper(lk.cod),'^0+(?=.)','') = m.item
  left join public.products pb on m.base <> m.item
       and regexp_replace(upper(pb.cod),'^0+(?=.)','') = m.base
  left join public.loke_products lkb on m.base <> m.item
       and regexp_replace(upper(lkb.cod),'^0+(?=.)','') = m.base
  where m.proy_cajas > 0
  order by m.proy_cajas desc;
$function$;


-- VERIFICAR ===========================================================================
-- (a) ningun NNNL sin uxb, y el total de filas no cambia (esperado: 461 / 124 / 0)
with m as (select * from public.fn_proyeccion_oc_virgilio())
select count(*) filas, count(*) filter (where cod ~ '([0-9E])L$') filas_L,
       count(*) filter (where cod ~ '([0-9E])L$' and uxb is null) L_sin_uxb,
       sum(proy_uni_mes) filter (where cod ~ '([0-9E])L$') uni_L
from m;

-- (b) bajar el resultado a Virgilio (lo hace solo el cron 25, miercoles 09:20)
select public.sync_proyeccion_madre_virgilio();
-- ⚠ tarda mas de 60 s (va por FDW): desde el MCP se corta el cliente. Si hace falta
--    correrlo a mano, va por pg_cron y se borra despues:
--      select cron.schedule('gv-sync-proy-madre-oneshot','* * * * *',
--                           'select public.sync_proyeccion_madre_virgilio();');
--      select cron.unschedule('gv-sync-proy-madre-oneshot');


-- ROLLBACK ============================================================================
-- Volver al cuerpo viejo: mismo SELECT pero sin el CTE `conbase` ni los joins pb/lkb,
--   coalesce(p.uxb, lk.uxb) / coalesce(p.uxb, lk.uxb, 1), y `from merged m`.
-- Los datos ya bajados a Virgilio se restauran de
--   zz_backups."GV_Backup_ProyeccionMadre_20260915" (proyecto hrxfctzncixxqmpfhskv).
