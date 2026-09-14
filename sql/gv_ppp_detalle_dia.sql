/* =====================================================================
   gv_ppp_detalle_dia — QUÉ SALE cada día, pedido por pedido (v17.54 / v17.56)
   ---------------------------------------------------------------------
   Dueño (2026-09-14): "debe poder clickear sobre el día y ver la composición
   de lo que sale ese día. Cuando entra que vea ordenado x número de NP".
   Y después: "que diga el estado del pedido: Pickeado; Armado; Facturado"
   … "o sin armar".

   Es el detalle de `gv_ppp_resumen_dias` (§3.ff): las MISMAS dos fuentes, el
   mismo criterio, una fila por pedido en vez de una por día. Si los números de
   las dos vistas no coinciden, una de las dos está mal — se arman igual a
   propósito.

   Orden: `np_num` (el número pelado de la NP) ascendente. Las NP web son un
   contador propio de 4 dígitos (v13.70) y las de ISIS tienen 5, así que la web
   queda primero. `np` es la etiqueta que ve el operario ("LK 0028", "98704"),
   armada con `gv_ppp_web_np_label` — la MISMA función que usa el front.

   ── EL ESTADO (v17.56) ───────────────────────────────────────────────
   Las reglas NO son nuevas: son las de `gv_ppp_avance_dias`
   (`sql/gv_ppp_avance_dia.sql`), la función que ya alimenta los % de la PPP, el
   Telegram de las 16:00 y la tarea de Planify de Marianela. Se repiten acá con
   las mismas fuentes para que un pedido no pueda figurar "armado" en un lado y
   "sin armar" en el otro:

     · picking  → el ÚLTIMO evento EP/TP de la TANDA. TP = picking terminado.
     · armado   → el ÚLTIMO evento AP/TAP de la TANDA. TAP = armado terminado.
     · salió    → la NP tiene CCN (cargada al camión) o CRN (remito controlado):
                  si salió, se armó, aunque falte el TAP.
     · facturado→ la NP está en `Facturacion_NP`.
     · legajos 0 y 1 (Pruebas) no marcan estado, igual que en el front.

   El dueño pidió CUATRO etiquetas, así que los cinco estados internos de la
   función caen así:

     Facturado  ← la NP está facturada (gana sobre todo lo demás: es lo más
                  lejos que llegó el pedido)
     Armado     ← 'armado'   (TAP de la tanda, o la NP ya salió)
     Pickeado   ← 'picking'  (TP de la tanda) y también 'armando' (AP sin TAP):
                  si se está armando, pickeado ya está
     Sin armar  ← 'sin' y 'pickeando' (EP sin TP): mientras el picking no esté
                  terminado, para el depósito ese pedido no está listo

   `estado_orden` (1 sin armar · 2 pickeado · 3 armado · 4 facturado) está para
   poder ordenar o filtrar por estado sin parsear el texto.

   Objeto con prefijo gv_ y `security_invoker = true` (protocolo).
   Rollback:  drop view public.gv_ppp_detalle_dia;
   ===================================================================== */
create or replace view public.gv_ppp_detalle_dia
with (security_invoker = true) as
with isis as (
  select left(fecha_entrega, 10)::date                     as fecha,
         np                                                as np,
         nullif(regexp_replace(coalesce(np, ''), '\D', '', 'g'), '')::numeric as np_num,
         coalesce(nullif(btrim(coalesce(tanda, '')), ''), '—')                as tanda,
         coalesce(m3, 0)                                   as m3,
         coalesce(btrim(cod), '')                          as cod,
         coalesce(btrim(razon_social), '')                 as razon_social,
         coalesce(nullif(btrim(coalesce(barrio, '')), ''), btrim(coalesce(direccion, ''))) as localidad,
         coalesce(btrim(zona), '')                         as zona,
         'isis'::text                                      as origen
    from public.gv_ppp_programacion_diaria
   where fecha_entrega ~ '^\d{4}-\d{2}-\d{2}'
), web as (
  select fecha_entrega                                     as fecha,
         case when np is null
              then (case when lower(coalesce(empresa, '')) in ('chef', 'ch') then 'CH' else 'LK' end
                    || ' pedido ' || order_id::text)
              else public.gv_ppp_web_np_label(empresa, np, np_idx) end        as np,
         coalesce(np, order_id)::numeric                   as np_num,
         coalesce(nullif(btrim(coalesce(tanda, '')), ''), '—')                as tanda,
         coalesce(m3, 0)                                   as m3,
         coalesce(btrim(cod_cliente), '')                  as cod,
         coalesce(btrim(razon_social), '')                 as razon_social,
         coalesce(nullif(btrim(coalesce(barrio, '')), ''), btrim(coalesce(direccion, ''))) as localidad,
         coalesce(btrim(zona), '')                         as zona,
         'web'::text                                       as origen
    from public."PPP_Web_Programacion"
   where fecha_entrega is not null
     and nullif(btrim(coalesce(tanda, '')), '') is not null
), ped as (
  select * from isis
  union all
  select * from web
), ev as (        -- eventos de picking/armado POR TANDA (mismo filtro que gv_ppp_avance_dias)
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP', 'TP', 'AP', 'TAP')
     and coalesce(btrim(r.legajo), '') not in ('0', '1')
     and btrim(coalesce(r.texto, '')) <> ''
), pick as (
  select distinct on (tanda) tanda, opcion from ev where opcion in ('EP', 'TP') order by tanda, ts_cliente desc
), arm as (
  select distinct on (tanda) tanda, opcion from ev where opcion in ('AP', 'TAP') order by tanda, ts_cliente desc
), salio as (     -- cargada al camión (CCN) o remito controlado (CRN) = salió, o sea armada sí o sí
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN', 'CRN')
     and coalesce(btrim(r.legajo), '') not in ('0', '1')
     and btrim(coalesce(r.texto, '')) <> ''
), fact as (
  select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f
)
select p.fecha, p.np, p.np_num, p.tanda, p.m3, p.cod, p.razon_social, p.localidad, p.zona, p.origen,
       case when fc.np is not null                              then 'Facturado'
            when s.np is not null or a.opcion = 'TAP'           then 'Armado'
            when a.opcion = 'AP'  or p2.opcion = 'TP'           then 'Pickeado'
            else 'Sin armar' end                                                as estado,
       case when fc.np is not null                              then 4
            when s.np is not null or a.opcion = 'TAP'           then 3
            when a.opcion = 'AP'  or p2.opcion = 'TP'           then 2
            else 1 end                                                          as estado_orden
  from ped p
  left join salio s  on s.np  = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
  left join fact  fc on fc.np = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
  left join pick  p2 on p2.tanda = upper(p.tanda) and p.tanda <> '—'
  left join arm   a  on a.tanda  = upper(p.tanda) and p.tanda <> '—';

comment on view public.gv_ppp_detalle_dia is
  'Detalle de la PPP por dia: una fila por pedido (NP, cliente, tanda, m3, estado), ISIS + web. Estado = Sin armar | Pickeado | Armado | Facturado, con las reglas de gv_ppp_avance_dias. Lo abre el boton PPP de la botonera del operario al tocar un dia. Ordenar por np_num. v17.56.';

grant select on public.gv_ppp_detalle_dia to anon, authenticated;
