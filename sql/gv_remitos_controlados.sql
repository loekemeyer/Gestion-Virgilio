-- v30.96 (Luis, 15/10/2026): "dejale bien claro y fácil de encontrar los remitos controlados en una vista".
--
--   select * from public.gv_remitos_controlados order by controlado_at desc;
--
-- UN renglón por NP con el remito controlado (evento CRN) = el pedido está ENTREGADO o RETIRADO.
-- Es para CONSULTA. ⚠ NO es la fuente del bot de WhatsApp (repo loekemeyer/gestopclientes): el bot lee
-- gv_pedido_web_estado_pagina por FDW (entregado / entregado_at = primer CRN), vía bot_estado_pedidos_gv.
-- Ese contrato ya existía y ya recibe el CRN del retira (v30.95). v30.99: sin acceso anon (nadie la usa desde la app).
--
--   tipo           'retirado'  = el cliente lo retiró en Virgilio (Carga → Retira, desde v30.95,
--                                o una NP Retira controlada por Recepción Remitos antes de eso)
--                  'entregado' = lo llevó un fletero y el remito volvió (Recepción Remitos)
--   tipo_segun     de dónde sale el tipo: 'carga_retira' (el CRN lo dio Carga → Retira),
--                  'zona_retira' (la NP es Retira en la programación), 'recepcion_remitos'
--   controlado_at  el PRIMER CRN = cuándo se entregó / retiró
--   legajo / operario  quién lo controló (nombre por gv_legajo_nombre: último del plantel, si no Fichadas_Estructura)
--   fletero        el del último CCN (vacío en retira)
--   remito         nro de remito de ISIS (GV_NP_Remito), si se resolvió
--
-- Universo y datos del pedido: los de gv_ppp_entregados (sin legajos de prueba, NP resuelta).
-- Se excluyen los clientes de prueba (gv_es_cliente_prueba).
-- Medido al crear (15/10): 850 NP (806 entregados, 44 retirados), 850 con operario, 340 ms como anon.
create or replace function public.gv_legajo_nombre(p_legajo text)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select btrim(p.nombre) from public."GV_Plantel_Operario_Dia" p
      where btrim(p.legajo) = btrim(p_legajo) and coalesce(btrim(p.nombre), '') <> ''
      order by p.dia desc limit 1),
    (select btrim(s.nombre) from public."Fichadas_Estructura" s
      where s.tipo = 'emp' and btrim(s.leg) = btrim(p_legajo) and coalesce(btrim(s.nombre), '') <> '' limit 1),
    case when p_legajo like 'sup:%' then 'supervisor (' || substr(p_legajo, 5) || ')' end);
$$;
comment on function public.gv_legajo_nombre(text) is 'Nombre del operario por legajo (último del plantel; si no, Fichadas_Estructura). Sólo devuelve el nombre. v30.96.';
revoke all on function public.gv_legajo_nombre(text) from public;
grant execute on function public.gv_legajo_nombre(text) to authenticated;   -- v30.99: sin anon

create or replace view public.gv_remitos_controlados with (security_invoker = true) as
with crn as (
  select distinct on (regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', ''))
         regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         btrim(r.legajo) as legajo
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'CRN' and not public.es_legajo_test(r.legajo)
   order by regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', ''), r.ts_cliente
), retira_crn as (   -- alguna vez lo controló Carga -> Retira (v30.95)
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'CRN' and r.descripcion ilike '%Retira%'
), ccn as (
  select distinct on (regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', ''))
         regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np,
         nullif(btrim(split_part(r.texto, '|', 3)), '') as fletero,
         r.ts_cliente as cargado_at
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'CCN'
   order by regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', ''), r.ts_cliente desc
), prog as (
  select distinct on (btrim(g.np)) btrim(g.np) as np, g.es_retira
    from public.gv_np_prog_reparto g
   order by btrim(g.np), g.es_retira desc nulls last
), oper as (
  select l.legajo, public.gv_legajo_nombre(l.legajo) as nombre
    from (select distinct legajo from crn) l
)
select e.np,
       e.empresa,
       case when rc.np is not null or coalesce(p.es_retira, false) then 'retirado' else 'entregado' end as tipo,
       case when rc.np is not null then 'carga_retira'
            when coalesce(p.es_retira, false) then 'zona_retira'
            else 'recepcion_remitos' end as tipo_segun,
       e.controlado_at,
       (e.controlado_at at time zone 'America/Argentina/Buenos_Aires')::date as fecha,
       c.legajo,
       op.nombre as operario,
       e.cod_cliente,
       e.razon_social,
       e.tanda,
       rm.remito,
       cc.fletero,
       cc.cargado_at,
       e.m3,
       e.es_web
  from public.gv_ppp_entregados e
  join crn c on c.np = e.np
  left join retira_crn rc on rc.np = e.np
  left join ccn cc on cc.np = e.np
  left join prog p on p.np = e.np
  left join public."GV_NP_Remito" rm on rm.np = e.np
  left join oper op on op.legajo = c.legajo
 where not coalesce(public.gv_es_cliente_prueba(e.empresa, e.cod_cliente), false);

comment on view public.gv_remitos_controlados is
  'Remitos controlados (CRN): un renglón por NP entregada o retirada, para CONSULTA (tipo, controlado_at, operario, remito, fletero). NO es la fuente del bot de WhatsApp: el bot (repo gestopclientes) lee gv_pedido_web_estado_pagina por FDW. Sin acceso anon. v30.99.';
grant select on public.gv_remitos_controlados to authenticated;   -- v30.99: sin anon
