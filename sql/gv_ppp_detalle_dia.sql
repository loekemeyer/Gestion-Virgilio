/* =====================================================================
   gv_ppp_detalle_dia — QUÉ SALE cada día, pedido por pedido (v17.54 → v17.59)
   ---------------------------------------------------------------------
   Pedidos del dueño (2026-09-14), en orden:
     1. "debe poder clickear sobre el día y ver la composición de lo que sale ese
        día. Cuando entra que vea ordenado x número de NP"            → v17.54
     2. "que diga el estado del pedido: Pickeado; Armado; Facturado"
        … "o sin armar"                                               → v17.56
     3. "que a la derecha figure con tics: Pickeado; Armado; Facturado.
        Sólo figura el tic si ya fue pickeado/armado/facturado"       → v17.59
     4. "que esté separado por camión" · "que pueda filtrar por LK o CH" → v17.59

   Es el detalle de `gv_ppp_resumen_dias` (§3.ff): las MISMAS dos fuentes, el
   mismo criterio, una fila por pedido en vez de una por día. Si los números de
   las dos vistas no coinciden, una de las dos está mal — se arman igual a
   propósito.

   Orden: `np_num` (el número pelado de la NP) ascendente. Las NP web son un
   contador propio de 4 dígitos (v13.70) y las de ISIS tienen 5, así que la web
   queda primero. `np` es la etiqueta que ve el operario ("LK 0028", "98704"),
   armada con `gv_ppp_web_np_label` — la MISMA función que usa el front.

   ── LOS TRES TICS ────────────────────────────────────────────────────
   `pickeado`, `armado` y `facturado` son BOOLEANOS INDEPENDIENTES: el front
   pone un ✓ en cada columna donde haya true, nada donde no. Las reglas NO son
   nuevas, son las de `gv_ppp_avance_dias` (`sql/gv_ppp_avance_dia.sql`), la
   función que ya alimenta los % de la PPP, el Telegram de las 16:00 y la tarea
   de Planify de Marianela. Se repiten acá con las mismas fuentes para que un
   pedido no pueda figurar armado en un lado y sin armar en el otro:

     · picking  → el ÚLTIMO evento EP/TP de la TANDA. TP = picking terminado.
     · armado   → el ÚLTIMO evento AP/TAP de la TANDA. TAP = armado terminado.
     · salió    → la NP tiene CCN (cargada al camión) o CRN (remito controlado):
                  si salió, se armó, aunque falte el TAP.
     · facturado→ la NP está en `Facturacion_NP`.
     · legajos 0 y 1 (Pruebas) no marcan estado, igual que en el front.

     armado    = TAP de la tanda, o la NP ya salió
     pickeado  = TP de la tanda, o AP sin TAP (si se está armando, pickeado ya
                 está), o armado — es MONÓTONO: no se puede armar sin pickear
     facturado = independiente: puede haber factura sin TAP registrado, y en ese
                 caso se ve el tic de Fact sin el de Arm. Es la verdad del dato,
                 no un error de la vista.

   `estado` / `estado_orden` (Sin armar 1 · Pickeado 2 · Armado 3 · Facturado 4)
   quedan para ordenar o filtrar por estado sin tener que mirar los tres tics.

   ── CAMIÓN Y EMPRESA ─────────────────────────────────────────────────
   `camion` = el NÚMERO de la tanda (letra + número): D72B y D72C viajan en el
   camión D72. Es la misma regla que `_pppTandaNum()` de la PPP. ⚠ NO es el
   "Camión 1 / 2 / 3" del supervisor: ése se numera por orden de pantalla
   (v13.13) y depende de la ruta y las zonas, así que se dejó el código de la
   tanda, que el operario ya lee en las cajas y no puede contradecir a la PPP.

   `empresa` = 'LK' / 'CH', para el filtro. Web: la que trae la fila. ISIS: la
   misma regla que `empresaDeNp()` del front — NP > 90000 = Loekemeyer.

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
         'isis'::text                                      as origen,
         -- empresaDeNp() del front: NP > 90000 = Loekemeyer, si no Chef
         case when coalesce(nullif(regexp_replace(coalesce(np, ''), '\D', '', 'g'), '')::numeric, 0) > 90000
              then 'LK' else 'CH' end                      as empresa
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
         'web'::text                                       as origen,
         case when lower(coalesce(empresa, '')) in ('chef', 'ch') then 'CH' else 'LK' end as empresa
    from public."PPP_Web_Programacion"
   where fecha_entrega is not null
     and nullif(btrim(coalesce(tanda, '')), '') is not null
), ped as (
  select * from isis
  union all
  select * from web
), ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP', 'TP', 'AP', 'TAP')
     and coalesce(btrim(r.legajo), '') not in ('0', '1')
     and btrim(coalesce(r.texto, '')) <> ''
), pick as (
  select distinct on (tanda) tanda, opcion from ev where opcion in ('EP', 'TP') order by tanda, ts_cliente desc
), arm as (
  select distinct on (tanda) tanda, opcion from ev where opcion in ('AP', 'TAP') order by tanda, ts_cliente desc
), salio as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN', 'CRN')
     and coalesce(btrim(r.legajo), '') not in ('0', '1')
     and btrim(coalesce(r.texto, '')) <> ''
), fact as (
  select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f
), base as (
  select p.fecha, p.np, p.np_num, p.tanda, p.m3, p.cod, p.razon_social, p.localidad, p.zona, p.origen, p.empresa,
         (s.np is not null or a.opcion = 'TAP')                          as b_armado,
         (s.np is not null or a.opcion = 'TAP' or a.opcion = 'AP' or p2.opcion = 'TP') as b_pick,
         (fc.np is not null)                                             as b_fact
    from ped p
    left join salio s  on s.np  = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
    left join fact  fc on fc.np = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
    left join pick  p2 on p2.tanda = upper(p.tanda) and p.tanda <> '—'
    left join arm   a  on a.tanda  = upper(p.tanda) and p.tanda <> '—'
)
select fecha, np, np_num, tanda, m3, cod, razon_social, localidad, zona, origen,
       case when b_fact then 'Facturado' when b_armado then 'Armado'
            when b_pick then 'Pickeado'  else 'Sin armar' end            as estado,
       case when b_fact then 4 when b_armado then 3 when b_pick then 2 else 1 end as estado_orden,
       b_pick   as pickeado,
       b_armado as armado,
       b_fact   as facturado,
       empresa,
       -- camión = el NÚMERO de la tanda (letra + número), la misma regla que _pppTandaNum() de la PPP:
       -- D72B y D72C viajan en el mismo camión D72.
       coalesce(substring(upper(tanda) from '^([A-Z]+-?[0-9]+)[A-Z]+$'), '—') as camion
  from base;

comment on view public.gv_ppp_detalle_dia is
  'Detalle de la PPP por dia: una fila por pedido (NP, cliente, tanda, m3, camion, empresa) + los tres tics pickeado/armado/facturado, ISIS + web. Reglas de estado = gv_ppp_avance_dias; camion = numero de tanda (_pppTandaNum); empresa = etiqueta LK/CH o NP>90000. Lo abre el boton PPP de la botonera del operario al tocar un dia. Ordenar por np_num. v17.59.';

grant select on public.gv_ppp_detalle_dia to anon, authenticated;
