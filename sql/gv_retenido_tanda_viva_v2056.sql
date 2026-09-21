-- ════════════════════════════════════════════════════════════════════════════════════════
-- v20.56 (Luis, 2026-09-21) — UN PEDIDO RETENIDO NO VUELVE A UNA TANDA QUE AVANZÓ SIN ÉL
-- ════════════════════════════════════════════════════════════════════════════════════════
-- Pedido textual, mirando el desglose del badge de la PPP: *"esto me preocupa. estaban armados?
-- qué interacción tienen si vuelven a programación a su tanda y su tanda está armada/facturada/
-- entregada cuando estos no?"*.
--
-- ⚠ LO QUE SE MIDIÓ, Y ES EL PUNTO ENTERO:
--
--   `GV_PPP_Web_Retenido.ya_pickeada` / `ya_armada` son la **FOTO del momento en que se sacó el
--   pedido**, y la tanda sigue avanzando después. D69H decía `ya_armada = false` (del 15/09) y
--   el 21/09 ya tenía TAP. El chip de A Programar leía esos flags, así que le decía al
--   supervisor lo contrario de la realidad justo cuando más importaba.
--
--   Probado en transacción abortada con el caso real — LK 1448 devuelto a D69H para el 25/09:
--
--     movidas=3 · arbol=[{"np":"LK 0070","fecha":"2026-09-22","estado":"armado"},
--                        {"np":"LK 0083","fecha":"2026-09-22","estado":"armado"},
--                        {"np":"LK 0094","fecha":"2026-09-25","estado":"armado"},   ← nunca se pickeó
--                        {"np":"LK 0095","fecha":"2026-09-25","estado":"armado"},   ← nunca se pickeó
--                        {"np":"LK 0096","fecha":"2026-09-25","estado":"armado"}]   ← nunca se pickeó
--
--   Tres cosas, ninguna teórica:
--     1. las 3 NP salen del árbol como ARMADAS sin haberse pickeado nunca — su mercadería no
--        está en ese pallet, porque se sacaron ANTES del picking. El operario no las ve para
--        armar y se cargan al camión cajas que no existen;
--     2. la tanda queda en DOS DÍAS (22/09 y 25/09) → problema 338, dos camiones;
--     3. LK 0096 venía de **E52A**, no de D69H: la función tomaba UNA sola `tanda_previa`
--        (`limit 1`) y se la aplicaba a todas las NP del pedido.
--
-- ⚠ NO se tocó ningún dato: los 3 pedidos retenidos quedan como están. Esto es el guard.
-- ════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. la vista dice el estado VIVO de la tanda a la que volvería ───────────────────────
create or replace view public.gv_ppp_web_retenido
with (security_invoker = true) as
select t.empresa, t.order_id, t.np_idx, t.np, t.tanda_previa, t.fecha_previa,
       -- ⚠ EN VIVO. Los de la tabla son la foto de cuando se sacó el pedido.
       coalesce(e.pick, false)  as ya_pickeada,
       coalesce(e.arm,  false)  as ya_armada,
       t.motivo, t.por, t.creado_at,
       case when t.np is not null then public.gv_ppp_web_np_label(t.empresa, t.np, t.np_idx) end as np_label,
       coalesce(v.nps, 0) > 0   as tanda_viva,
       v.fecha                  as tanda_fecha,
       coalesce(v.nps, 0)       as tanda_nps,
       case when s.n  > 0                then 'salio'
            when f.n  > 0                then 'facturada'
            when coalesce(e.arm, false)  then 'armada'
            when coalesce(e.pick, false) then 'pickeada'
            when coalesce(v.nps, 0) > 0  then 'sin empezar'
            when public.gv_ppp_web_codigo_tomado(upper(btrim(t.tanda_previa))) then 'codigo tomado'
            else 'no existe' end         as tanda_estado
  from public."GV_PPP_Web_Retenido" t
  left join lateral (
    select bool_or(r.opcion in ('TP','EP')) pick, bool_or(r.opcion = 'TAP') arm
      from public."Registros_Produccion_Virgilio" r
     where upper(btrim(r.texto)) = upper(btrim(t.tanda_previa))
       and r.opcion in ('EP','TP','AP','TAP')
       and coalesce(btrim(r.legajo), '') not in ('0','1')) e on true
  left join lateral (
    select count(*) nps, min(w.fecha_entrega) fecha
      from public."PPP_Web_Programacion" w
     where upper(btrim(coalesce(w.tanda, ''))) = upper(btrim(t.tanda_previa))) v on true
  left join lateral (
    select count(*) n from public."Facturacion_NP" f2
     where upper(btrim(coalesce(f2.tanda, ''))) = upper(btrim(t.tanda_previa))) f on true
  left join lateral (
    select count(*) n from public."Registros_Produccion_Virgilio" r
     where upper(btrim(split_part(r.texto, '|', 1))) = upper(btrim(t.tanda_previa))
       and r.opcion in ('CCN','CRN')
       and coalesce(btrim(r.legajo), '') not in ('0','1')) s on true;

alter view public.gv_ppp_web_retenido set (security_invoker = true);

-- ── 2. el guard ─────────────────────────────────────────────────────────────────────────
create or replace function public.gv_ppp_web_tanda_reusar(
  p_empresa text, p_order_id bigint, p_fecha date, p_por text default null)
returns table(np_programadas integer, tanda text, fecha date)
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_emp text := lower(btrim(coalesce(p_empresa, 'lk')));
  v_n int := 0; v_tandas text; r record;
begin
  if not (es_supervisor_virgilio() or gv_es_supervisor_o_servicio()) then
    raise exception 'Solo un supervisor puede reprogramar un pedido.' using errcode = '42501';
  end if;
  if p_fecha is null then raise exception 'Falta el dia de entrega.'; end if;

  if not exists (select 1 from public."GV_PPP_Web_Retenido" t
                  where t.empresa = v_emp and t.order_id = p_order_id
                    and nullif(btrim(t.tanda_previa), '') is not null) then
    raise exception 'Ese pedido no quedo retenido con una tanda anterior: programalo como uno nuevo.';
  end if;

  for r in
    select distinct on (upper(btrim(t.tanda_previa))) upper(btrim(t.tanda_previa)) tanda,
           v.tanda_estado, v.tanda_fecha, v.tanda_viva
      from public."GV_PPP_Web_Retenido" t
      join public.gv_ppp_web_retenido v
        on v.empresa = t.empresa and v.order_id = t.order_id and v.np_idx = t.np_idx
     where t.empresa = v_emp and t.order_id = p_order_id
       and nullif(btrim(t.tanda_previa), '') is not null
  loop
    if r.tanda_estado in ('pickeada', 'armada', 'facturada', 'salio') then
      raise exception 'La tanda % ya esta %: la mercaderia de este pedido NO esta en ese pallet (se saco antes). Programalo en una tanda NUEVA.',
        r.tanda, r.tanda_estado using errcode = 'P0001';
    end if;
    if r.tanda_estado = 'codigo tomado' then
      raise exception 'El codigo de tanda % ya lo esta usando otra cosa. Programalo en una tanda NUEVA.',
        r.tanda using errcode = 'P0001';
    end if;
    if r.tanda_viva and r.tanda_fecha is not null and r.tanda_fecha <> p_fecha then
      raise exception 'La tanda % sale el % y vos elegiste el %. Una tanda no puede salir en dos dias: programalo el % o mandalo a una tanda NUEVA.',
        r.tanda, to_char(r.tanda_fecha, 'DD/MM'), to_char(p_fecha, 'DD/MM'),
        to_char(r.tanda_fecha, 'DD/MM') using errcode = 'P0001';
    end if;
  end loop;

  -- cada NP vuelve a SU tanda (antes: una sola `tanda_previa` con `limit 1` para todo el pedido)
  update public."PPP_Web_Programacion" w
     set tanda = upper(btrim(t.tanda_previa)), fecha_entrega = p_fecha, actualizado_at = now()
    from public."GV_PPP_Web_Retenido" t
   where t.empresa = v_emp and t.order_id = p_order_id and t.np_idx = w.np_idx
     and w.empresa = t.empresa and w.order_id = t.order_id
     and coalesce(nullif(btrim(w.tanda), ''), '') = ''
     and nullif(btrim(t.tanda_previa), '') is not null;
  get diagnostics v_n = row_count;

  select string_agg(distinct upper(btrim(t.tanda_previa)), ', ') into v_tandas
    from public."GV_PPP_Web_Retenido" t
   where t.empresa = v_emp and t.order_id = p_order_id
     and nullif(btrim(t.tanda_previa), '') is not null;

  delete from public."GV_PPP_Web_Retenido" t
   where t.empresa = v_emp and t.order_id = p_order_id;

  return query select v_n, v_tandas, p_fecha;
end;
$function$;

-- ── 3. centinelas de regla ──────────────────────────────────────────────────────────────
insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version)
values
 ('gv_ppp_web_tanda_reusar', 'funcion', 'tanda_estado',
  'Un pedido retenido NO vuelve a su tanda si esa tanda ya se pickeo, armo, facturo o salio: su mercaderia no esta en ese pallet. Se frena y va a una tanda nueva.',
  'Luis', 'v20.56'),
 ('gv_ppp_web_tanda_reusar', 'funcion', 'no puede salir en dos dias',
  'Si la tanda anterior sale otro dia que el elegido, se frena: una tanda en dos dias cae en dos camiones (problema 338).',
  'Luis', 'v20.56'),
 ('gv_ppp_web_tanda_reusar', 'funcion', 't\.np_idx = w\.np_idx',
  'Cada NP vuelve a SU tanda_previa. Antes se tomaba una sola con limit 1 y se le aplicaba a todas las NP del pedido.',
  'Luis', 'v20.56'),
 ('gv_ppp_web_retenido', 'vista', 'Registros_Produccion_Virgilio',
  'ya_pickeada / ya_armada se calculan EN VIVO. Los de la tabla son la foto del momento en que se saco el pedido y la tanda sigue avanzando despues.',
  'Luis', 'v20.56')
on conflict do nothing;

-- ⚠ `gv_ppp_avisos_detalle` también cambió en esta versión: el aviso del badge lee la VISTA
-- `gv_ppp_web_retenido` (estado de hoy) y no la tabla. La definición viva está en
-- `sql/gv_ppp_avisos_detalle_v2055.sql`, actualizada.

-- ── chequeo ─────────────────────────────────────────────────────────────────────────────
-- select np_label, tanda_previa, ya_pickeada, ya_armada, tanda_estado, tanda_fecha
--   from public.gv_ppp_web_retenido order by tanda_previa, np_label;
-- al 21/09: LK 0094/0095 -> D69H 'armada' · CH 0004, LK 0028, LK 0096 -> 'no existe'
-- select * from public.gv_reglas_perdidas;   -- vacía = todo bien
