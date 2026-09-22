-- v21.15 (Luis, 2026-09-22) - DE DONDE VIENE EL REGISTRO DE UNA TANDA QUE LO HEREDO
--
-- Al mover un pedido ARMADO a otra tanda (gv_ppp_pedido_llevar_registro, v21.10) viajan el
-- TP y el TAP, las filas de Entregas_Virgilio y la porcion de cajas de a_facturar. Lo que NO
-- viaja es el detalle por articulo del picking: los PKC, que son la orden que mueve el stock
-- (copiarlos re-pickea: medido, gondola -85 -> -194 y +106 cajas que no existen).
--
-- O sea que el detalle queda en la tanda VIEJA, y hasta hoy no habia forma de llegar ahi
-- desde la nueva: el rastro existia pero enterrado en el client_id de los eventos copiados
-- (mv_<nueva>_<TP|TAP>_<vieja>) y en el ref de los ajustes (<nueva>|MOV-<vieja>).
--
-- Esta vista lo saca a la superficie: una fila por (tanda que recibio, tanda de origen).
--
-- NO persiste nada: se calcula al leer, de los mismos rastros que ya escribe el movimiento.
-- Si manana cambia el formato del client_id o del ref, cambia aca y en ningun otro lado.

create or replace view public.gv_tanda_registro_heredado
with (security_invoker = true) as
with
-- (a) los cierres copiados. client_id = 'mv_<nueva>_<TP|TAP>_<vieja>'
_rh_ev as (
  select (regexp_match(r.client_id, '^mv_([^_]+)_(TP|TAP)_([^_]+)$'))[1] as tanda,
         (regexp_match(r.client_id, '^mv_([^_]+)_(TP|TAP)_([^_]+)$'))[3] as vino_de,
         r.opcion, r.legajo, r.ts_cliente, r.created_at
    from public."Registros_Produccion_Virgilio" r
   where r.client_id ~ '^mv_[^_]+_(TP|TAP)_[^_]+$'
     and r.opcion in ('TP','TAP')
),
_rh_ev_ag as (
  select tanda, vino_de,
         max(ts_cliente) filter (where opcion = 'TP')  as pickeado_el,
         max(legajo)     filter (where opcion = 'TP')  as pickeado_por,
         max(ts_cliente) filter (where opcion = 'TAP') as armado_el,
         max(legajo)     filter (where opcion = 'TAP') as armado_por,
         min(created_at)                               as copiado_el,
         count(*)                                      as eventos
    from _rh_ev group by 1, 2
),
-- (b) la porcion de cajas que viajo. ref de la ENTRADA = '<nueva>|MOV-<vieja>'
_rh_mov as (
  select upper(btrim(split_part(m.ref, '|', 1))) as tanda,
         upper(btrim(regexp_replace(split_part(m.ref, '|', 2), '^MOV-', ''))) as vino_de,
         sum(m.delta)                 as cajas,
         count(distinct m.cod_art)    as codigos,
         min(m.creado)                as movido_el,
         (array_agg(m.legajo order by m.id))[1] as movido_por
    from public."Movimientos_Stock" m
   where m.tipo = 'ajuste' and m.deposito = 'a_facturar' and m.delta > 0
     and split_part(m.ref, '|', 2) like 'MOV-%'
   group by 1, 2
),
-- (c) el par (tanda que recibio, tanda de origen). Full join: puede haber eventos sin cajas
--     (un pedido de 0 cajas entregadas) o cajas sin eventos (la tanda nueva ya tenia TP/TAP
--     propios, y el `not exists` de la funcion no los volvio a copiar).
_rh_par as (
  select coalesce(e.tanda, m.tanda)     as tanda,
         coalesce(e.vino_de, m.vino_de) as vino_de,
         e.pickeado_el, e.pickeado_por, e.armado_el, e.armado_por,
         coalesce(e.eventos, 0)         as eventos_copiados,
         coalesce(m.cajas, 0)           as cajas_movidas,
         coalesce(m.codigos, 0)         as codigos_movidos,
         coalesce(e.copiado_el, m.movido_el) as movido_el,
         coalesce(m.movido_por, e.pickeado_por) as movido_por
    from _rh_ev_ag e
    full outer join _rh_mov m on m.tanda = e.tanda and m.vino_de = e.vino_de
),
-- (d) donde esta el detalle del picking, de los dos lados
_rh_pkc as (
  select upper(btrim(split_part(r.texto, '|', 1))) as tanda, count(*) as pkc
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'PKC' and coalesce(r.texto,'') like '%|%'
   group by 1
),
-- (e) que pedidos tiene HOY la tanda que recibio
_rh_np as (
  select upper(btrim(coalesce(e.tanda,''))) as tanda,
         count(distinct e.np)               as nps,
         string_agg(distinct e.np, ', ' order by e.np) as np_lista,
         sum(coalesce(e.cajas_entregadas,0)) as cajas_entregadas
    from public."Entregas_Virgilio" e
   group by 1
)
select p.tanda,
       p.vino_de,
       n.np_lista,
       coalesce(n.nps, 0)              as nps,
       p.cajas_movidas,
       p.codigos_movidos,
       coalesce(n.cajas_entregadas, 0) as cajas_entregadas,
       p.pickeado_el,
       p.pickeado_por,
       p.armado_el,
       p.armado_por,
       p.movido_el,
       p.movido_por,
       p.eventos_copiados,
       coalesce(pn.pkc, 0)             as pkc_propios,
       coalesce(pv.pkc, 0)             as pkc_en_origen,
       -- la linea que contesta "donde esta el detalle del picking de esta tanda"
       case
         when coalesce(pn.pkc,0) > 0 and coalesce(pv.pkc,0) > 0
           then 'tiene picking propio (' || pn.pkc || ' codigos) Y heredo de ' || p.vino_de
                || ', donde hay ' || pv.pkc
         when coalesce(pn.pkc,0) > 0
           then 'tiene picking propio: ' || pn.pkc || ' codigos'
         when coalesce(pv.pkc,0) > 0
           then 'el detalle del picking (' || pv.pkc || ' codigos) esta en ' || p.vino_de
                || ' -- aca NO se volvio a levantar de la gondola'
         else 'sin detalle de picking en ninguna de las dos'
       end                             as donde_esta_el_detalle
  from _rh_par p
  left join _rh_np  n  on n.tanda  = p.tanda
  left join _rh_pkc pn on pn.tanda = p.tanda
  left join _rh_pkc pv on pv.tanda = p.vino_de
 where p.tanda is not null and p.vino_de is not null
 order by p.movido_el desc nulls last, p.tanda;

comment on view public.gv_tanda_registro_heredado is
  'v21.15 - Tandas que recibieron el registro de un pedido ya armado (v21.10). Una fila por '
  '(tanda que recibio, tanda de origen), con las cajas que viajaron y DONDE quedo el detalle '
  'por articulo del picking: los PKC NO se copian porque copiarlos re-pickea.';

alter view public.gv_tanda_registro_heredado set (security_invoker = true);

-- El centinela de la regla, para que nadie la borre sin enterarse.
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values ('gv_tanda_registro_heredado', 'vista', 'pkc_en_origen',
        'La vista que dice de que tanda heredo el registro un pedido movido ya armado, y '
        'donde quedo el detalle del picking (los PKC no viajan: copiarlos re-pickea).',
        'Luis', 'v21.15')
on conflict do nothing;
