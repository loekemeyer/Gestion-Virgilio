-- v19.86 — Picking colgado de E12M y E12I: 78 cajas que volvieron a góndola (problema 429)
-- ============================================================================================
-- Secuela del bug del PKC (problema 421, arreglado en la v19.80). Estas dos tandas quedaron con
-- picking anotado y CERO pedidos: sus NP se habían mudado a otra tanda y el stock se fue con
-- ellas, pero los eventos PKC se quedaron con el código viejo y el cron 68 volvía a crear el
-- picking cada 10 minutos. O sea: 78 cajas contadas dos veces y descontadas de góndola.
--
-- CÓMO SE IDENTIFICÓ CADA PAR — el patrón es siempre el mismo, y se ve en los segundos:
--   E12M · PSP 17/09 11:39:33  ←→  E12A · EP 17/09 11:39:30   (3 s, mismo legajo 104)
--   E12I · PKC 17/09 09:22:54  ←→  E12E · EP 17/09 09:22:28
-- El `EP` (texto = la tanda sola) viajó con el renombre; el `PSP`/`PKC` (tanda en el campo 1) se
-- quedó. Un solo operario, un solo picking, dos códigos. Las cajas ya estaban contadas del otro
-- lado: E12E las consumió al armarse el 18/09 y E12A las tiene en sus 193.
--
-- MECANISMO: el de `gv_anular_picking_virgilio` (v18.71), que es el correcto y ya estaba probado.
-- NO se usó la función tal cual porque exige un `EP` con ese legajo y ese texto, y estas dos ya
-- no lo tienen — viajó con el renombre; devuelve `sin_ep`.
--
--   1. PKC -> PKCX.  ⚠ NO se borra la fila: el `client_id` es lo único que impide que el reenvío
--      de la cola offline del celular RESUCITE el evento (hay un UNIQUE sobre esa columna y el
--      front postea con Prefer: resolution=ignore-duplicates). Pasó el 15/09 con E25A, borrado a
--      las 16:56 y reinsertado a las 17:17. Con PKCX la fila sigue ocupando su client_id, el
--      reenvío choca, y ninguno de los consumidores la cuenta (todos filtran por opcion='PKC').
--   2. Movimientos_Stock: `delta = 0`, no DELETE. `trigger_actualizar_saldo_stock` es
--      AFTER INSERT OR UPDATE y NO corre en DELETE, así que borrando quedaría
--      `stocks_carga_rapida` inflado. Con el UPDATE el saldo se recalcula solo.
--   3. `gv_tanda_lock_anular` para las dos, envuelto en begin/exception.
--
-- Se corrió como un bloque único con tres guardas que lo abortaban solo: 0 cajas restantes en
-- E12M/E12I, la góndola subiendo EXACTAMENTE 77 y separar_pedidos bajando EXACTAMENTE 78.
-- Resultado verificado corriendo `reconciliar_pipeline_stock()` de verdad después: no vuelven.
-- 48 PKC anulados, 66 filas de stock a cero.
--
-- Backups: zz_backups."GV_Backup_Eventos_E12M_E12I_20260918" (49 eventos) y
--          zz_backups."GV_Backup_MovStock_E12M_E12I_20260918" (144 movimientos), las dos con RLS.

update public."Registros_Produccion_Virgilio"
   set opcion = 'PKCX',
       descripcion = 'Picking anulado: duplicado del renombre de tanda (los PKC quedaron con el '
                  || 'codigo viejo, problema 421). Estas cajas ya estan contadas en E12A / E12E. v19.80'
 where opcion = 'PKC' and upper(btrim(split_part(texto,'|',1))) in ('E12M','E12I');

update public."Movimientos_Stock" set delta = 0
 where tipo = 'picking' and upper(btrim(ref)) in ('E12M','E12I') and delta <> 0;

select public.gv_tanda_lock_anular('E12M','picking','104');
select public.gv_tanda_lock_anular('E12I','picking','104');

-- ============================================================================================
-- gv_stock_picking_duplicado v19.86 — un duplicado YA ARMADO no es un duplicado pendiente
-- ============================================================================================
-- El centinela que salió con la v19.80 marcaba 3 pares, pero dos de ellos (E12E/E37F y
-- E12J/E12G) ya estaban RESUELTOS: al armarse la tanda fantasma, su `separado` cancela el
-- picking duplicado y devuelve a góndola lo que no se usó. Medido el 18/09:
--   E12E: -114 separar_pedidos, +37 a_facturar, +77 góndola  → neto 0
--   E12J: -100 separar_pedidos, +19 a_facturar, +81 góndola  → neto 0
-- Y contra el evento ENT, el armado salió bien: E12E armó 38 de 44 pedidas, E12J 20 de 20.
-- Sin la condición `neto_fantasma > 0` el centinela los marcaba para siempre y quedaba en rojo —
-- el mismo defecto que tenía `gv_stock_empresa_fantasma` antes de la v19.77. Un centinela que
-- vive en rojo no lo mira nadie.
--
-- Queda en 1: E12A/E12S (193 cajas, neto 193, y E12A sigue programada el 21/09 con una sola NP
-- de 47 cajas). Ése espera el conteo físico del pallet: es el único dato que no está en la base.
--
-- La definición completa de la vista está arriba en sql/gv_evento_tanda_campo_pkc_v1980.sql,
-- con estos dos agregados: el CTE `neto`, la condición del WHERE y la columna `neto_fantasma`.

-- Chequeo:
--   select * from public.gv_stock_picking_duplicado;   -- al 18/09: sólo E12A/E12S
--   select * from public.gv_reglas_perdidas;           -- vacía

-- CREATE completo de la vista, tal como quedó aplicada (el repo tiene la definición, no "está en la base"):
create or replace view public.gv_stock_picking_duplicado
with (security_invoker = true) as
with st as (
  select upper(btrim(m.ref)) tanda, upper(btrim(m.cod_art)) art, sum(m.delta) q, min(m.ts) primer_mov
    from public."Movimientos_Stock" m
   where m.tipo = 'picking' and m.deposito = 'separar_pedidos'
     and upper(btrim(coalesce(m.ref, ''))) ~ '^[A-Z][0-9]{2}[A-Z]$'
     and m.ts >= now() - interval '90 days'
   group by 1, 2 having sum(m.delta) <> 0
), pk as (
  select upper(btrim(split_part(r.texto, '|', 1))) tanda, count(*) n
    from public."Registros_Produccion_Virgilio" r where r.opcion = 'PKC' group by 1
), tot as (
  select tanda, count(*) cods, sum(q) cajas, min(primer_mov) primer_mov from st group by 1
), neto as (   -- v19.86: picking MENOS lo que ya se armó
  select upper(btrim(m.ref)) tanda, sum(m.delta) q
    from public."Movimientos_Stock" m
   where m.deposito = 'separar_pedidos' and m.tipo in ('picking', 'separado')
     and upper(btrim(coalesce(m.ref, ''))) ~ '^[A-Z][0-9]{2}[A-Z]$'
   group by 1
)
select f.tanda as tanda_fantasma, v.tanda as tanda_viva, tf.cods as codigos, tf.cajas as cajas,
       tf.primer_mov as fantasma_desde, tv.primer_mov as viva_desde,
       (select coalesce(sum(m2.delta), 0) from public."Movimientos_Stock" m2
         where m2.tipo = 'picking' and m2.deposito = 'terminado'
           and upper(btrim(m2.ref)) = f.tanda) as gondola_de_mas,
       'El picking de una misma tanda esta contado DOS veces, con dos codigos. Pasa al renombrar o '
       'fusionar una tanda: hasta la v19.80 los eventos PKC se quedaban con el codigo viejo porque '
       'gv_evento_tanda_campo no declaraba PKC, y el cron 68 volvia a insertar las filas con ese '
       'codigo (y encima pisaba la fusion, porque la etapa1 hace DO UPDATE SET delta). Firma: la '
       'tanda viva no tiene NINGUN PKC, el fantasma si, y el fantasma sigue COLGADO (si ya se armo, '
       'su separado cancelo el duplicado solo y no hay nada que reclamar).'::text as que_significa,
       round(100.0 * count(*) / tf.cods) as pct_solape,
       exists (select 1 from public."PPP_Web_Programacion" w where upper(btrim(w.tanda)) = f.tanda)
    or exists (select 1 from public."GV_PPP_Programacion_Diaria" d where upper(btrim(d.tanda)) = f.tanda)
                                          as fantasma_programado,
       (select q from neto where neto.tanda = f.tanda) as neto_fantasma
  from st v
  join st f  on f.art = v.art and f.q = v.q and f.tanda <> v.tanda
  join tot tv on tv.tanda = v.tanda
  join tot tf on tf.tanda = f.tanda
 where coalesce((select n from pk where pk.tanda = v.tanda), 0) = 0
   and coalesce((select n from pk where pk.tanda = f.tanda), 0) > 0
   and coalesce((select q from neto where neto.tanda = f.tanda), 0) > 0
 group by f.tanda, v.tanda, tf.cods, tf.cajas, tf.primer_mov, tv.primer_mov, tv.cods
having count(*) >= 3
   and 100.0 * count(*) / tv.cods >= 80
   and 100.0 * count(*) / tf.cods >= 80;

alter view public.gv_stock_picking_duplicado set (security_invoker = true);
