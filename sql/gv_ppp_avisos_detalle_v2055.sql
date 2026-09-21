-- ════════════════════════════════════════════════════════════════════════════════════════
-- v20.55 (Luis, 2026-09-21) — EL BADGE DE LA PPP DICE QUÉ SON ESOS AVISOS
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Pedido textual: *"el «4» del badge qué significa? Debería tener más info"*.
--
-- El badge contaba `gv_ppp_avisos` (una fila por TIPO con su conteo) y el desglose vivía sólo en
-- el `title` del `<span>` — un tooltip que en el monitor táctil no existe y en la compu hay que
-- adivinar que está ahí. Un número rojo que no dice de qué es no se mira: se ignora.
--
-- El `4` del 21/09 eran dos cosas distintas:
--   · 1 tanda con paradas de dos recorridos  → D69H, Capital + GBA Norte, martes 22/09
--   · 3 pedidos sacados a mano sin fecha     → LK 1448, LK 1358, CH 218
--
-- Esta vista devuelve UNA FILA POR COSA, con el dato concreto y qué hacer con él.
--
-- ⚠ El conteo tiene que dar EXACTAMENTE el del badge, o el pop-up desmiente al número que lo
-- abrió. Por eso agrupa igual que `gv_ppp_avisos`: por (día, camión) el súper mezclado, por
-- tanda las dos de tanda, por (empresa, order_id) los retenidos. Una tanda mezclada cuenta 1
-- aunque tenga 4 pedidos adentro. Chequeo al pie.
-- ════════════════════════════════════════════════════════════════════════════════════════

drop view if exists public.gv_ppp_avisos_detalle;

create view public.gv_ppp_avisos_detalle
with (security_invoker = true) as
-- 1 · un súper viajando con clientes comunes en el mismo camión
select 'super_mezclado'::text tipo, 1 orden,
       'Súper mezclado con clientes en el mismo camión'::text titulo,
       s.dia::date                                            fecha,
       ('Camión ' || s.cam)::text                             que,
       (count(*) filter (where s.que_es = 'super') || ' súper + ' ||
        count(*) filter (where s.que_es <> 'super') || ' cliente(s): ' ||
        string_agg(distinct coalesce(nullif(btrim(s.razon_social), ''), s.cod), ', '))::text detalle,
       'El súper no comparte camión con clientes comunes. Mover las NP comunes a otro camión.'::text accion
  from public.gv_ppp_super_mezclado s
 group by s.dia, s.cam
union all
-- 2 · una tanda con paradas de dos recorridos distintos
select 'tanda_dos_camiones', 2, 'Tanda con paradas de dos recorridos',
       t.fecha, ('Tanda ' || t.tanda),
       (t.nps || ' NP · ' || t.clientes || ' cliente(s) · ' || t.camiones || ' (' || t.zonas || ')'),
       'La tanda se parte por camión. Mover a otra tanda las NP del camión que no corresponde.'
  from public.gv_ppp_tanda_camion_mezclado t
union all
-- 3 · el mismo código de tanda saliendo dos días
select 'tanda_dos_dias', 3, 'Tanda con el mismo código en dos días',
       min(d.fecha), ('Tanda ' || d.tanda),
       ('sale el ' || string_agg(distinct to_char(d.fecha, 'DD/MM'), ' y el ') ||
        ' · ' || count(*) || ' NP'),
       'Una tanda no puede salir en dos días: cae en dos camiones. Renombrar una de las dos.'
  from public.gv_ppp_tanda_dos_dias d
 group by d.tanda
union all
-- 4 · pedidos que un supervisor sacó a mano de su tanda y todavía no tienen fecha nueva
select 'retenido_sin_fecha', 4, 'Pedidos sacados a mano, esperando fecha',
       min(r.fecha_previa),
       (upper(case when r.empresa = 'chef' then 'CH' else 'LK' end) || ' pedido ' || r.order_id),
       (count(*) || ' NP · salió de la tanda ' || string_agg(distinct r.tanda_previa, ', ') ||
        case when bool_or(r.ya_armada) then ' (YA ARMADA: no hay que volver a armarla)'
             when bool_or(r.ya_pickeada) then ' (YA PICKEADA: no hay que volver a pickearla)'
             else '' end ||
        ' · lo sacó ' || string_agg(distinct r.por, ', ')),
       'Está en A Programar esperando día. Al programarlo vuelve a su tanda anterior.'
  from public."GV_PPP_Web_Retenido" r
 group by r.empresa, r.order_id
union all
-- 5 · pedido web que se salió de lo que ese cliente compra siempre
select 'alerta_web', 5, 'Pedidos web anómalos sin revisar',
       a.creado_en::date, ('Pedido ' || a.order_id),
       (coalesce(nullif(btrim(a.cliente), ''), a.cod_cliente::text) ||
        ' · score ' || a.score || coalesce(' · ' || nullif(btrim(a.motivo), ''), '')),
       'Mirarlo en la PPP y marcarlo Revisado o Descartar.'
  from public."Alertas_Pedidos_Web" a
 where a.estado = 'pendiente';

alter view public.gv_ppp_avisos_detalle set (security_invoker = true);
grant select on public.gv_ppp_avisos_detalle to anon, authenticated;

-- ── chequeo: el detalle tiene que sumar lo MISMO que el badge ───────────────────────────
-- with a as (select tipo, n from public.gv_ppp_avisos where n > 0),
--      d as (select tipo, count(*)::int n from public.gv_ppp_avisos_detalle group by 1)
-- select coalesce(a.tipo, d.tipo) tipo, a.n badge, d.n detalle,
--        case when coalesce(a.n,0) = coalesce(d.n,0) then 'ok' else 'NO COINCIDE' end
--   from a full join d using (tipo);
-- al 21/09: tanda_dos_camiones 1=1 · retenido_sin_fecha 3=3 · total 4=4
