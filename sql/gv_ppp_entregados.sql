-- =============================================================================
-- gv_ppp_entregados.sql — CONTROL DE REMITO = PEDIDO ENTREGADO, SOLO (2026-09-05, v12.95)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUEVA gv_, sólo lectura
-- =============================================================================
-- LO QUE PIDIÓ EL DUEÑO: "cuando ya el pedido se controla el remito, ya tiene que
-- pasar directamente a Pedidos Entregados, sin que nadie toque nada. Hoy requiere en
-- Producción que se corrija en el Excel para que se corrija en el espejo (la PPP).
-- En Gestión tiene que hacerse de manera automática."
--
-- CÓMO ERA. La PPP de Gestión (copia de Producción) sacaba un pedido de Programación
-- sólo cuando la operadora lo borraba del Excel de ISIS (la fila quedaba con el badge
-- "🚮 SACAR" mientras tanto), y "Pedidos Entregados" mostraba únicamente lo que estaba
-- FACTURADO con CIERRE (vista_ppp_pedidos_entregados) y además confirmado. Los CRN
-- (evento "Control Remito NP" que emite Control Remitos por cada NP controlada) se
-- leían 60 días para atrás y se guardaban en localStorage del navegador.
--
-- CÓMO ES. Esta vista es la fuente durable: TODA NP con un CRN —de ISIS (98694) o
-- web ("LK 1350", "LK 1350-2")— con tanda, cliente, m³, fecha programada, fecha de
-- carga (CCN), cajas (Entregas_Virgilio), primer control y si está facturada. El front
-- (v12.95): Programación la ESCONDE, Pedidos Entregados la MUESTRA, aunque no esté
-- facturada ni cerrada ni borrada del Excel. Es superconjunto de gv_ppp_web_entregados
-- (v12.87), que queda por compatibilidad.
--
-- Qué NP entran: sólo las que Gestión conoce (PPP_Web_Programacion para las web;
-- programación / facturación / entregados del espejo para las de ISIS, todas por las
-- vistas gv_ con la canilla). Un CRN de una NP que no está en ningún lado no aparece
-- (0 al crearla: los 821 CRN históricos resolvieron todos).
--
-- NO TOCA PRODUCCIÓN: lee Registros_Produccion_Virgilio, Entregas_Virgilio,
-- Facturacion_NP y las vistas gv_ppp_*. Sin trigger, sin escritura.
--
-- ROLLBACK: drop view public.gv_ppp_entregados; front v12.94.
-- =============================================================================

create or replace view public.gv_ppp_entregados
with (security_invoker = true) as
with crn as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         max(nullif(upper(btrim(split_part(r.texto, '|', 2))), '')) as tanda_crn,
         min(r.ts_cliente) as controlado_at,
         count(*) as n_crn
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CRN' and not public.es_legajo_test(r.legajo)
  group by 1
),
web as (
  select public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np, p.empresa, p.tanda,
         p.cod_cliente as cod, p.razon_social as rs, p.m3, p.fecha_entrega::text as fecha_entrega
  from public."PPP_Web_Programacion" p
),
isis as (
  select np, tanda, cod, rs, m3, fecha_entrega, prio from (
    select regexp_replace(btrim(np), '\.0+$', '') np, tanda, cod, razon_social rs, m3, left(fecha_entrega, 10) fecha_entrega, 1 prio from public.gv_ppp_programacion_diaria
    union all
    select regexp_replace(btrim(np), '\.0+$', ''), tanda, cod_cliente, razon_social, m3, fecha_salida::text, 2 from public."Facturacion_NP"
    union all
    select regexp_replace(btrim(np), '\.0+$', ''), tanda, cod, rs, m3, left(fecha_entrega, 10), 3 from public.gv_ppp_entregados_meta
  ) x
),
ccn as (
  select regexp_replace(upper(btrim(split_part(texto, '|', 1))), '\.0+$', '') np,
         max((ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) fecha_carga
  from public."Registros_Produccion_Virgilio" where opcion = 'CCN' group by 1
),
ent as (
  select regexp_replace(upper(btrim(np)), '\.0+$', '') np,
         sum(cajas_pedidas) cajas_pedidas, sum(cajas_entregadas) cajas_entregadas, sum(cajas_falto) cajas_falto
  from public."Entregas_Virgilio" group by 1
),
fact as (select distinct regexp_replace(upper(btrim(np)), '\.0+$', '') np from public."Facturacion_NP")
select c.np,
       coalesce(w.empresa, case when c.np ~ '^9' then 'lk' when c.np ~ '^4' then 'chef' end) as empresa,
       (w.np is not null) as es_web,
       coalesce(w.tanda, i.tanda, c.tanda_crn) as tanda,
       coalesce(w.cod, i.cod) as cod_cliente,
       coalesce(w.rs, i.rs) as razon_social,
       coalesce(w.m3, i.m3) as m3,
       coalesce(w.fecha_entrega, i.fecha_entrega) as fecha_entrega,
       cc.fecha_carga,
       c.controlado_at,
       c.n_crn,
       e.cajas_pedidas, e.cajas_entregadas, e.cajas_falto,
       (f.np is not null) as facturada
from crn c
left join web w on w.np = c.np
left join lateral (select * from isis i where i.np = c.np order by i.prio limit 1) i on true
left join ccn cc on cc.np = c.np
left join ent e on e.np = c.np
left join fact f on f.np = c.np
where w.np is not null or i.np is not null;

-- Los privilegios por defecto del proyecto le dan TODO a anon sobre cada objeto nuevo.
revoke all on public.gv_ppp_entregados from anon, authenticated;
grant select on public.gv_ppp_entregados to anon, authenticated;
