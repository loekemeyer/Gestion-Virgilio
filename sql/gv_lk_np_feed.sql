-- =============================================================================
-- gv_lk_np_feed.sql — el feed de NP que consume el reporte de la página LK
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · 2026-09-07 · v14.14
-- =============================================================================
-- POR QUÉ.
-- El reporte diario/semanal/mensual que sale por Telegram desde el proyecto LK
-- (funciones `rep_*`) mostraba dos números de depósito —lo despachado por día y
-- lo pendiente de facturar— y los dos estaban mal:
--
--   1. Leía la tabla cruda `PPP_Programacion_Diaria`, así que NO veía ninguna NP
--      que arma Gestión desde la página (viven en `PPP_Web_Programacion`) y sí
--      contaba las filas que `GV_PPP_Prog_Override.oculto` esconde.
--   2. Filtraba las NP de Loekemeyer con `left(np,1) = '9'`. La NP web de Gestión
--      es un contador propio con etiqueta `LK 0001` (v13.70), así que la primera
--      facturación web se habría perdido sin avisar.
--   3. Revalorizaba la plata por su cuenta, sobre lo PEDIDO, y la corregía con un
--      ratio global de cajas. Medido contra el neto que ya calcula Gestión, daba
--      de +0,5% a +14,5% de más según el día.
--
-- QUÉ ES.
-- Una vista NUEVA, `gv_lk_np_feed`, con una fila por NP —ISIS y web juntas— que
-- expone lo que el reporte necesita y nada más. Es sólo lectura y la consume el
-- rol `lk_ppp_reader` por el FDW que LK ya tenía armado.
--
-- REGLAS QUE RESPETA (CLAUDE.md, base compartida con Producción):
--   * Objeto NUEVO con prefijo `gv_`. No se toca nada que use Producción.
--   * `security_invoker = true`, y por eso hacen falta los grants + policies de
--     abajo: sin ellos la vista corre con los permisos de quien la llama.
--   * Sólo `SELECT`, sólo para `lk_ppp_reader`. Revocada de `anon`/`authenticated`.
--   * Ningún trigger, ningún `update`, ningún `drop`.
--
-- DECISIÓN: `valor_lista` va SIN descuentos a propósito. El descuento por cliente
-- y el 0,98 del canal web viven en LK (`customers.dto_vol`, `app_settings`), que
-- es de donde salen; LK los aplica sobre este número. El neto de lo FACTURADO sí
-- viene calculado, porque ahí manda lo que se entregó y la lista de súper, que
-- Gestión ya resuelve en `gv_vista_facturacion_neto`.
-- =============================================================================

-- 1) Lecturas que necesita la vista (security_invoker). Todo SELECT.
grant select on public."Entregas_Virgilio"             to lk_ppp_reader;
grant select on public."PPP_Web_Base"                  to lk_ppp_reader;
grant select on public."PPP_Web_Config"                to lk_ppp_reader;  -- la lee gv_espejo_corte()
grant select on public."GV_PPP_Prog_Override"          to lk_ppp_reader;
grant select on public.clientes_dto                    to lk_ppp_reader;
grant select on public.precios_venta                   to lk_ppp_reader;
grant select on public.precios_venta_chef              to lk_ppp_reader;
grant select on public.cobranzas_cliente_cadena        to lk_ppp_reader;
grant select on public.cobranzas_super_cadena          to lk_ppp_reader;
grant select on public.cobranzas_precios_super         to lk_ppp_reader;
grant select on public.gv_ppp_base_pedidos             to lk_ppp_reader;
grant select on public.gv_ppp_programacion_diaria      to lk_ppp_reader;
grant select on public.gv_ppp_np_valor                 to lk_ppp_reader;
grant select on public.gv_vista_facturacion_neto       to lk_ppp_reader;
grant select on public.gv_vista_facturacion_neto_items to lk_ppp_reader;

-- 2) Las tablas de arriba tienen RLS prendida: sin policy propia el grant no alcanza.
--    Mismo patrón que las policies `lk_ppp_reader_sel` que ya existían.
create policy lk_ppp_reader_sel on public."Entregas_Virgilio"        for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public."PPP_Web_Base"             for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public."PPP_Web_Config"           for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public."GV_PPP_Prog_Override"     for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public.clientes_dto               for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public.precios_venta              for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public.precios_venta_chef         for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public.cobranzas_cliente_cadena   for select to lk_ppp_reader using (true);
create policy lk_ppp_reader_sel on public.cobranzas_super_cadena     for select to lk_ppp_reader using (true);
-- `cobranzas_precios_super` es una VISTA sin security_invoker: corre como su dueño,
-- así que con el grant alcanza y sus tablas base no necesitan nada.

-- 3) El feed.
create or replace view public.gv_lk_np_feed
with (security_invoker = true) as
with prog as (
  select regexp_replace(btrim(g.np), '\.0+$', '')                  as np,
         case when btrim(g.np) ~ '^4' then 'chef' else 'lk' end    as empresa,
         false                                                     as es_web,
         g.cod                                                     as cod_cliente,
         g.razon_social,
         g.tanda,
         g.zona,
         nullif(left(g.fecha_entrega, 10), '')::date               as fecha_entrega,
         g.m3
    from public.gv_ppp_programacion_diaria g          -- la vista, no la tabla cruda:
                                                       -- respeta el override que oculta
                                                       -- las NP de ISIS duplicadas
  union all
  select public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx),
         lower(w.empresa), true,
         w.cod_cliente, w.razon_social, w.tanda, w.zona,
         w.fecha_entrega, w.m3
    from public."PPP_Web_Programacion" w
), fac as (
  select regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np,
         max(f.fecha_salida)                             as fecha_salida,
         max(f.tanda)                                    as tanda,
         sum(f.m3)                                       as m3
    from public."Facturacion_NP" f
   where f.np is not null
   group by 1
), nps as (
  select np from prog
  union
  select np from fac
)
select n.np,
       coalesce(p.empresa,
                case when n.np ~ '^4' or n.np ~ '^CH ' then 'chef' else 'lk' end) as empresa,
       coalesce(p.es_web, n.np ~ '^(LK|CH) ')      as es_web,
       p.cod_cliente,
       p.razon_social,
       coalesce(p.tanda, f.tanda)                  as tanda,
       p.zona,
       p.fecha_entrega,
       coalesce(p.m3, f.m3)                        as m3,
       (f.np is not null)                          as facturada,
       f.fecha_salida,
       nt.neto                                     as neto_facturado,
       nt.neto_original                            as neto_pedido,
       nt.cajas_ped,
       nt.cajas_ent,
       nt.cajas_falto,
       v.valor_lista,
       v.cajas                                     as cajas_prog,
       v.lineas_sin_precio
  from nps n
  left join prog p                              on p.np  = n.np
  left join fac  f                              on f.np  = n.np
  left join public.gv_vista_facturacion_neto nt on nt.np = n.np
  left join public.gv_ppp_np_valor v            on v.np  = n.np;

comment on view public.gv_lk_np_feed is
  'Feed de NP (ISIS + web) para el reporte diario/semanal/mensual de la pagina LK. Solo lectura, lo consume el rol lk_ppp_reader por FDW.';

revoke all on public.gv_lk_np_feed from public, anon, authenticated;
grant select on public.gv_lk_np_feed to lk_ppp_reader, service_role;

-- =============================================================================
-- MEDICIÓN (2026-09-07)
--   1.312 filas: 1.167 facturadas + 145 pendientes; 29 web (25 LK + 4 Chef).
--   Últimos 30 días de facturación: 402 NP, 0 sin neto.
--   Más viejo que eso hay huecos de neto (Entregas_Virgilio no llega): no importa,
--   LK guarda su propia foto diaria en rep_despacho_diario.
--   Costo: gv_vista_facturacion_neto 634 ms + gv_ppp_np_valor 311 ms. Corre 1×/día.
--
-- ROLLBACK
--   drop view public.gv_lk_np_feed;
--   drop policy lk_ppp_reader_sel on public."Entregas_Virgilio";       -- y las otras 8
--   revoke select on public."Entregas_Virgilio" from lk_ppp_reader;    -- y los otros 14
--   (del lado LK: drop foreign table virgilio.gv_lk_np_feed; ver el repo pagina-LK-copia,
--    sql/reporte_deposito_gestion.sql)
-- =============================================================================
