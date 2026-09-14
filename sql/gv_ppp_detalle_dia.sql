/* =====================================================================
   gv_ppp_detalle_dia — QUÉ SALE cada día, pedido por pedido (v17.54 → v17.62)
   ---------------------------------------------------------------------
   Pedidos del dueño (2026-09-14), en orden:
     1. "debe poder clickear sobre el día y ver la composición de lo que sale ese
        día. Cuando entra que vea ordenado x número de NP"            → v17.54
     2. "que diga el estado del pedido: Pickeado; Armado; Facturado"
        … "o sin armar"                                               → v17.56
     3. "que a la derecha figure con tics: Pickeado; Armado; Facturado.
        Sólo figura el tic si ya fue pickeado/armado/facturado"       → v17.59
     4. "que esté separado por camión" · "que pueda filtrar por LK o CH" → v17.59
     5. "la lógica del camión no tiene que ser sólo por el número de tanda,
        sino x la zona"                                               → v17.62
     6. "con topes de lo que entra en un camión (6 m³)" … "salvo pedidos más
        grandes, que se mandan en camiones más grandes"               → v17.62

   Es el detalle de `gv_ppp_resumen_dias` (§3.ff): las MISMAS dos fuentes, el
   mismo criterio, una fila por pedido en vez de una por día. Si los números de
   las dos vistas no coinciden, una de las dos está mal.

   Orden: `np_num` (el número pelado de la NP) ascendente. Las NP web son un
   contador propio de 4 dígitos (v13.70) y las de ISIS tienen 5, así que la web
   queda primero. `np` es la etiqueta que ve el operario ("LK 0028", "98704"),
   armada con `gv_ppp_web_np_label` — la MISMA función que usa el front.

   ── LOS TRES TICS ────────────────────────────────────────────────────
   `pickeado`, `armado` y `facturado` son BOOLEANOS INDEPENDIENTES: el front
   pone un ✓ donde haya true. Las reglas NO son nuevas, son las de
   `gv_ppp_avance_dias` (`sql/gv_ppp_avance_dia.sql`), la función que ya alimenta
   los % de la PPP, el Telegram de las 16:00 y la tarea de Planify de Marianela:

     · picking  → el ÚLTIMO evento EP/TP de la TANDA. TP = picking terminado.
     · armado   → el ÚLTIMO evento AP/TAP de la TANDA. TAP = armado terminado.
     · salió    → la NP tiene CCN (cargada al camión) o CRN (remito controlado):
                  si salió, se armó, aunque falte el TAP.
     · facturado→ la NP está en `Facturacion_NP`.
     · legajos 0 y 1 (Pruebas) no marcan estado, igual que en el front.

     armado    = TAP de la tanda, o la NP ya salió
     pickeado  = TP, o AP sin TAP (si se está armando, pickeado ya está), o armado
                 — es MONÓTONO: no se puede armar sin pickear
     facturado = independiente: hay NP facturadas sin TAP registrado, y ahí se ve
                 el tic de Fact sin el de Arm. Es la verdad del dato.

   ── EL CAMIÓN: NO alcanza el número de tanda, la ZONA manda ──────────
   `camion_key` es la clave de agrupación, y sigue la misma lógica que
   `_pppCamiones()` de la PPP del supervisor:

     Retira  → 'RET'. No viaja: va solo, todo junto, y no es un camión.
     Súper   → 'SUP:<nº de tanda>'. Un camión por súper, NUNCA con clientes
               (regla del dueño v14.23) y "2 súper diferentes, 2 camiones" (v13.20).
     Resto   → el número de tanda. Ojo: eso YA contempla la zona, porque el armado
               arma la tanda por cercanía (v13.07) y un camión hace zonas VECINAS.
               Medido el 14/09: de 39 camiones, 8 llevan 2-3 zonas y todas son
               vecinas (Zona 1+2, Zona 5+6+7). Partirlos por zona inventaría
               camiones que no existen; por eso la zona va en la ETIQUETA
               (`zona_corta` → "Zona 1 + Zona 2"), no en la clave.
     Sin tanda → 'Z:<zona>'.

   `camion` sigue siendo el número de tanda (D72B y D72C → D72). ⚠ NO es el
   "Camión 1 / 2 / 3" del supervisor: ése se numera por orden de pantalla (v13.13)
   y depende de ruta y zonas; replicarlo sería una segunda numeración que puede
   contradecir a la PPP.

   ── EL TOPE DEL CAMIÓN ───────────────────────────────────────────────
   `camion_m3` = m³ del camión ENTERO (window sobre fecha + camion_key).
   `camion_tope` = `PPP_Web_Config.camion_m3_tope` (**6,00**), salvo que un SOLO
   pedido lo pase: ése viaja en un camión más grande, así que el tope de ese
   camión es el pedido. Sin esa excepción, el pedido de 9,25 m³ del 16/09
   figuraría eternamente "pasado de tope" y el aviso dejaría de mirarse.
   Para cambiar el tope: `update public."PPP_Web_Config" set valor = <n> where
   clave = 'camion_m3_tope';` — no hay que tocar código.

   `empresa` = 'LK' / 'CH', para el filtro. Web: la que trae la fila. ISIS: la
   misma regla que `empresaDeNp()` del front — NP > 90000 = Loekemeyer.

   Objeto con prefijo gv_ y `security_invoker = true` (protocolo).
   Rollback:  drop view public.gv_ppp_detalle_dia;
   ===================================================================== */
create or replace view public.gv_ppp_detalle_dia
with (security_invoker = true) as
with cfg as (
  select coalesce((select valor from public."PPP_Web_Config" where clave = 'camion_m3_tope'), 6.00) as tope
), isis as (
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
         (fc.np is not null)                                             as b_fact,
         coalesce(substring(upper(p.tanda) from '^([A-Z]+-?[0-9]+)[A-Z]+$'), '—') as cam_tanda,
         (p.zona ~* 'super|coto|carrefour|chango|krikos')                as b_super,
         (p.zona ~* 'retira')                                            as b_retira
    from ped p
    left join salio s  on s.np  = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
    left join fact  fc on fc.np = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
    left join pick  p2 on p2.tanda = upper(p.tanda) and p.tanda <> '—'
    left join arm   a  on a.tanda  = upper(p.tanda) and p.tanda <> '—'
), conkey as (
  select b.*,
         case when b_retira        then 'RET'
              when b_super         then 'SUP:' || cam_tanda
              when cam_tanda = '—' then 'Z:' || coalesce(nullif(btrim(zona), ''), 'Sin zona')
              else cam_tanda end as camion_key
    from base b
)
select fecha, np, np_num, tanda, m3, cod, razon_social, localidad, zona, origen,
       case when b_fact then 'Facturado' when b_armado then 'Armado'
            when b_pick then 'Pickeado'  else 'Sin armar' end            as estado,
       case when b_fact then 4 when b_armado then 3 when b_pick then 2 else 1 end as estado_orden,
       b_pick   as pickeado,
       b_armado as armado,
       b_fact   as facturado,
       empresa,
       cam_tanda                                                         as camion,
       case when b_retira then 'ret' when b_super then 'sup' else '' end  as ruta,
       case when b_retira then 'Retira' when b_super then 'Súper'
            else coalesce(substring(zona from '^(Zona\s*[0-9]+)'), nullif(btrim(zona), ''), 'Sin zona') end as zona_corta,
       camion_key,
       round(sum(m3) over (partition by fecha, camion_key), 3)            as camion_m3,
       greatest((select tope from cfg), round(max(m3) over (partition by fecha, camion_key), 3)) as camion_tope
  from conkey;

comment on view public.gv_ppp_detalle_dia is
  'Detalle de la PPP por dia: una fila por pedido (NP, cliente, tanda, m3, camion, empresa) + los tres tics pickeado/armado/facturado + m3/tope del camion, ISIS + web. Estado = reglas de gv_ppp_avance_dias; camion_key = Retira aparte, un camion por Super, el resto por numero de tanda (que ya agrupa zonas vecinas); tope = PPP_Web_Config.camion_m3_tope (6), salvo que un solo pedido lo pase (va en camion mas grande). Lo abre el boton PPP de la botonera del operario. Ordenar por np_num. v17.62.';

grant select on public.gv_ppp_detalle_dia to anon, authenticated;

-- El tope, como config (no hardcodeado):
--   insert into public."PPP_Web_Config" (clave, valor) values ('camion_m3_tope', 6.00)
--     on conflict (clave) do nothing;
