-- =============================================================================
-- gv_ppp_en_salida.sql — CARGADO AL CAMIÓN = EN SALIDA (2026-09-05, v13.02, idea 4459)
-- Proyecto Virgilio (hrxfctzncixxqmpfhskv) · vista NUEVA gv_, sólo lectura
-- =============================================================================
-- LO QUE PIDIÓ EL DUEÑO: "si hay pedidos que ya se cargaron a un camión, tienen que
-- salir de la Programación y pasar a En Salida, y no verse más en Programación".
-- Decisión: backend (misma forma que gv_ppp_entregados, v12.95).
--
-- CÓMO ERA. "En Salida" mostraba los FACTURADOS con cierre (vista_ppp_pedidos_entregados)
-- que todavía no estaban confirmados, incluyendo lo facturado sin cargar; y lo cargado
-- al camión (CCN) seguía en Programación con el badge "SIN CONTROLAR" hasta el CRN.
--
-- CÓMO ES. Esta vista = toda NP con evento CCN (carga camión por NP, legajo real), SIN
-- CRN (control de remito) y sin un FSS ("sin salida", volvió al depósito) posterior a la
-- última carga. Trae tanda, cliente, m³, fecha programada, zona/barrio/dirección, fecha y
-- hora de carga y si está facturada. Front (v13.02): Programación la ESCONDE, En Salida la
-- LISTA. Con el CRN la NP pasa a gv_ppp_entregados y sale de acá sola.
--
-- Qué NP entran: sólo las que Gestión conoce (PPP_Web_Programacion para las web;
-- programación / facturación / entregados del espejo, por las vistas gv_ con la canilla).
--
-- Medido al crearla (05/09): 844 NP con CCN → 23 sin CRN (todas facturadas), 14 de ellas
-- todavía en gv_ppp_programacion_diaria (esas son las que dejan de verse en Programación).
--
-- NO TOCA PRODUCCIÓN: sólo lee. Sin trigger, sin escritura.
-- ROLLBACK: drop view public.gv_ppp_en_salida; front v13.01.
-- =============================================================================

create or replace view public.gv_ppp_en_salida
with (security_invoker = true) as
with ccn as (
  select regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         max(nullif(upper(btrim(split_part(r.texto, '|', 2))), '')) as tanda_ccn,
         min(r.ts_cliente) as cargado_at,
         max(r.ts_cliente) as ultima_carga_at,
         max((r.ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date) as fecha_carga,
         count(*) as n_ccn
  from public."Registros_Produccion_Virgilio" r
  where r.opcion = 'CCN' and not public.es_legajo_test(r.legajo)
  group by 1
),
fss as (
  select regexp_replace(upper(btrim(split_part(texto, '|', 1))), '\.0+$', '') as np, max(ts_cliente) as fss_at
  from public."Registros_Produccion_Virgilio" where opcion = 'FSS' group by 1
),
crn as (
  select distinct regexp_replace(upper(btrim(split_part(texto, '|', 1))), '\.0+$', '') as np
  from public."Registros_Produccion_Virgilio" where opcion = 'CRN'
),
web as (
  select public.gv_ppp_web_np_label(p.empresa, p.np, p.np_idx) as np, p.empresa, p.tanda,
         p.cod_cliente as cod, p.razon_social as rs, p.m3, p.fecha_entrega::text as fecha_entrega,
         p.zona, p.barrio, p.direccion
  from public."PPP_Web_Programacion" p
),
isis as (
  select np, tanda, cod, rs, m3, fecha_entrega, zona, barrio, direccion, prio from (
    select regexp_replace(btrim(np), '\.0+$', '') np, tanda, cod, razon_social rs, m3, left(fecha_entrega, 10) fecha_entrega, zona, barrio, direccion, 1 prio from public.gv_ppp_programacion_diaria
    union all
    select regexp_replace(btrim(np), '\.0+$', ''), tanda, cod_cliente, razon_social, m3, fecha_salida::text, null, null, null, 2 from public."Facturacion_NP"
    union all
    select regexp_replace(btrim(np), '\.0+$', ''), tanda, cod, rs, m3, left(fecha_entrega, 10), null, null, null, 3 from public.gv_ppp_entregados_meta
  ) x
),
fact as (select distinct regexp_replace(upper(btrim(np)), '\.0+$', '') np from public."Facturacion_NP")
select c.np,
       coalesce(w.empresa, case when c.np ~ '^9' then 'lk' when c.np ~ '^4' then 'chef' end) as empresa,
       (w.np is not null) as es_web,
       coalesce(w.tanda, i.tanda, c.tanda_ccn) as tanda,
       coalesce(w.cod, i.cod) as cod_cliente,
       coalesce(w.rs, i.rs) as razon_social,
       coalesce(w.m3, i.m3) as m3,
       coalesce(w.fecha_entrega, i.fecha_entrega) as fecha_entrega,
       coalesce(w.zona, i.zona) as zona,
       coalesce(w.barrio, i.barrio) as barrio,
       coalesce(w.direccion, i.direccion) as direccion,
       c.fecha_carga, c.cargado_at, c.n_ccn,
       (f.np is not null) as facturada
from ccn c
left join crn k on k.np = c.np
left join fss s on s.np = c.np
left join web w on w.np = c.np
left join lateral (select * from isis i where i.np = c.np order by i.prio limit 1) i on true
left join fact f on f.np = c.np
where k.np is null
  and (s.fss_at is null or s.fss_at < c.ultima_carga_at)
  and (w.np is not null or i.np is not null);

revoke all on public.gv_ppp_en_salida from anon, authenticated;
grant select on public.gv_ppp_en_salida to anon, authenticated;
