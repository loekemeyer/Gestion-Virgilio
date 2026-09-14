/* =====================================================================
   gv_ppp_detalle_dia — QUÉ SALE cada día, pedido por pedido (v17.54 → v17.71)
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

   ── EL CAMIÓN: lo define la ZONA, y la regla ya estaba escrita ───────
   ⚠ La v17.62 agrupaba por NÚMERO DE TANDA y estaba MAL. Dueño (2026-09-14),
   mirando la pantalla: *"la zona uno se entrega con zona dos, así que no son
   dos camiones diferentes"*. Y tenía razón: la regla vive en la base desde la
   v13.60 y es `gv_ppp_web_camion(zona, sector)`:

     · por SECTOR si el barrio está mapeado (`GV_Barrios_Sector` →
       `GV_Sectores.camion`): A-H = Capital · J,K,L = GBA Sur · M = GBA Oeste ·
       N,P = GBA Norte;
     · si no, por número de zona: **1, 2 y 3 = Capital** · 4 = GBA Sur ·
       5 = GBA Oeste · 6 y 7 = GBA Norte.

   El sector sale de `gv_ppp_web_sector(zona, barrio, direccion)`, la misma
   función que usa el armado. O sea: NO se reimplementa nada, se llama a lo que
   ya decide el camión cuando se arma la tanda.

   **Y una serie de tanda que cruza DOS etiquetas queda como UN camión.** Es el
   contraejemplo que apareció al medir: el comentario de la v13.60 dice "misma
   que ISIS: D60 = zonas 4+5, D67 = 1+2+3, D69 = 5+6", y en los datos están
   D57 (09/09) y D69 (17/09), los dos GBA Oeste + GBA Norte. Agrupar sólo por
   etiqueta los habría partido en dos camiones que salieron juntos.

   Súper: camión propio por serie ("Súper D72") — nunca con clientes (v14.23).
   Retira: todo junto, no viaja.

   `camion` sigue siendo la serie de tanda (D67), pero ahora es SUBTÍTULO:
   el nombre del camión es `camion_key` (Capital, GBA Sur, …).

   ── EL TOPE DEL CAMIÓN ───────────────────────────────────────────────
   `camion_m3` = m³ del camión ENTERO (window sobre fecha + camion_key).
   `camion_tope` = `PPP_Web_Config.camion_m3_tope` (**6,00**), salvo que un SOLO
   pedido lo pase: ése viaja en un camión más grande, así que el tope de ese
   camión es el pedido.
   ⚠ El tope recién sirve con el camión bien agrupado: el 17/09, Capital da
   **7,02 m³** (E01 + E03 + E12) y se pasa. Con la agrupación por tanda de la
   v17.62 ninguno de los tres llegaba a 3,25 y el aviso nunca aparecía.

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
         coalesce(btrim(direccion), '')                    as direccion,
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
         coalesce(btrim(direccion), '')                    as direccion,
         coalesce(btrim(zona), '')                         as zona,
         'web'::text                                       as origen,
         case when lower(coalesce(empresa, '')) in ('chef', 'ch') then 'CH' else 'LK' end as empresa
    from public."PPP_Web_Programacion"
   where fecha_entrega is not null
     and nullif(btrim(coalesce(tanda, '')), '') is not null
), ped as (
  select * from isis union all select * from web
), ev as (
  select upper(btrim(r.texto)) as tanda, r.opcion, r.ts_cliente
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('EP','TP','AP','TAP')
     and coalesce(btrim(r.legajo), '') not in ('0','1') and btrim(coalesce(r.texto, '')) <> ''
), pick as (select distinct on (tanda) tanda, opcion from ev where opcion in ('EP','TP') order by tanda, ts_cliente desc
), arm as (select distinct on (tanda) tanda, opcion from ev where opcion in ('AP','TAP') order by tanda, ts_cliente desc
), salio as (
  select distinct regexp_replace(upper(btrim(split_part(r.texto, '|', 1))), '\.0+$', '') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo), '') not in ('0','1') and btrim(coalesce(r.texto, '')) <> ''
), fact as (
  select distinct regexp_replace(upper(btrim(f.np)), '\.0+$', '') as np from public."Facturacion_NP" f
), base as (
  select p.fecha, p.np, p.np_num, p.tanda, p.m3, p.cod, p.razon_social, p.localidad, p.zona, p.origen, p.empresa,
         (s.np is not null or a.opcion = 'TAP')                          as b_armado,
         (s.np is not null or a.opcion = 'TAP' or a.opcion = 'AP' or p2.opcion = 'TP') as b_pick,
         (fc.np is not null)                                             as b_fact,
         coalesce(substring(upper(p.tanda) from '^([A-Z]+-?[0-9]+)[A-Z]+$'), '—') as serie,
         (p.zona ~* 'super|coto|carrefour|chango|krikos')                as b_super,
         (p.zona ~* 'retira')                                            as b_retira,
         -- LA REGLA DEL CAMIÓN, la que ya usa el armado desde la v13.60
         public.gv_ppp_web_camion(p.zona, public.gv_ppp_web_sector(p.zona, p.localidad, p.direccion)) as etiqueta
    from ped p
    left join salio s  on s.np  = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
    left join fact  fc on fc.np = regexp_replace(upper(btrim(p.np)), '\.0+$', '')
    left join pick  p2 on p2.tanda = upper(p.tanda) and p.tanda <> '—'
    left join arm   a  on a.tanda  = upper(p.tanda) and p.tanda <> '—'
), serie_etq as (
  -- una serie de tanda que cruza DOS etiquetas es UN camión igual (ISIS arma así: "D69 = 5+6")
  select fecha, serie, string_agg(distinct etiqueta, ' + ' order by etiqueta) as etqs
    from base where not b_super and not b_retira and serie <> '—'
   group by fecha, serie
), conkey as (
  select b.*,
         case when b.b_retira then 'Retira'
              when b.b_super  then 'Súper ' || b.serie
              else coalesce(se.etqs, b.etiqueta, '(sin zona)') end as camion_key
    from base b
    left join serie_etq se on se.fecha = b.fecha and se.serie = b.serie
)
select fecha, np, np_num, tanda, m3, cod, razon_social, localidad, zona, origen,
       case when b_fact then 'Facturado' when b_armado then 'Armado'
            when b_pick then 'Pickeado'  else 'Sin armar' end            as estado,
       case when b_fact then 4 when b_armado then 3 when b_pick then 2 else 1 end as estado_orden,
       b_pick as pickeado, b_armado as armado, b_fact as facturado,
       empresa,
       serie                                                             as camion,
       case when b_retira then 'ret' when b_super then 'sup' else '' end  as ruta,
       case when b_retira then 'Retira' when b_super then 'Súper'
            else coalesce(substring(zona from '^(Zona\s*[0-9]+)'), nullif(btrim(zona), ''), 'Sin zona') end as zona_corta,
       camion_key,
       round(sum(m3) over (partition by fecha, camion_key), 3)            as camion_m3,
       greatest((select tope from cfg), round(max(m3) over (partition by fecha, camion_key), 3)) as camion_tope
  from conkey;

comment on view public.gv_ppp_detalle_dia is
  'Detalle de la PPP por dia: una fila por pedido + tics pickeado/armado/facturado + m3/tope del camion. camion_key = gv_ppp_web_camion(zona, sector) (Capital=Z1+2+3, GBA Sur=Z4, GBA Oeste=Z5, GBA Norte=Z6+7), y una serie de tanda que cruza dos etiquetas queda como UN camion (ISIS arma D69=5+6). Super y Retira aparte. Tope = PPP_Web_Config.camion_m3_tope (6) salvo que un solo pedido lo pase. v17.71.';

grant select on public.gv_ppp_detalle_dia to anon, authenticated;

-- El tope, como config (no hardcodeado):
--   insert into public."PPP_Web_Config" (clave, valor) values ('camion_m3_tope', 6.00)
--     on conflict (clave) do nothing;
