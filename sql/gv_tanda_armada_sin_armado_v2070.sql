-- v20.70 — CENTINELA: una tanda ARMADA cuyos pedidos de hoy no tienen armado propio
--
-- Luis, 2026-09-21: *"1) nunca se pickeo pero figura como armado? como, por que?"* · y al
-- entenderlo: *"Que quede registrada en el sistema como su estado real … Agrega el centinela"*.
--
-- POR QUÉ PASA, y es estructural: **EP, TP, AP y TAP son eventos de la TANDA, no del pedido**
-- (`texto = 'D69H'`, sin NP). Una vez que la tanda tiene TAP queda armada **para siempre**, sin
-- importar qué pedidos tenga adentro después. El único registro por NP es `Entregas_Virgilio`.
-- Nada relaciona una cosa con la otra, así que una tanda puede quedar marcada como armada con
-- los pedidos de otro adentro.
--
-- EL CASO D69H, medido el 21/09:
--
--   10/09 10:03  nace desde el panel con LK 0058 (Arguello, Villa Ballester, Zona 6)
--   11/09 12:15  se le suma LK 0070 (Valimar, Villa Lynch, Zona 6)
--   14/09 16:54  se le suma LK 0083 (Lin Chuang, Nuñez, Zona 2)   <- acá se mezcla el camión
--   15/09 13:00  se le suman 3 NP de Silvano (San Miguel)
--   15/09 14:03  las 3 de Silvano salen a A Programar ("D69H mezclaba Zona 2 con Zona 6")
--   16/09 13:07  picking: 41 segundos, UN solo PKC -> D69H|550|10
--   16/09 14:26  armado:  1 sola fila -> LK 0058, 10 pedidas, 0 entregadas, 10 faltó
--   después      LK 0058 sale de la tanda (hoy está en A Programar, sin fecha)
--
-- Resultado: D69H decía "armada" y adentro tenía **62 cajas sin pickear** (LK 0070, 22 cajas y
-- 9 líneas; LK 0083, 40 cajas y 6 líneas), y salía el miércoles 23.
--
-- LO QUE SE HIZO CON D69H (21/09, Luis): sus eventos se anularon con el patrón del repo
-- —TAP->TAPX, AP->APX, TP->TPX, EP->EPX, PKC->PKCX— y quedó **pendiente**, para pickearla y
-- armarla entera. **No se borró ni una fila**: borrar libera el `client_id` y la cola offline
-- del celular resucita el evento (v18.71/72, caso E25A del 15/09). Los 3 movimientos de stock de
-- D69H ya estaban en `delta = 0`, así que no hubo ninguna caja que devolver.
-- Backups: zz_backups."GV_Backup_Eventos_D69H_20260921" y "GV_Backup_MovStock_D69H_20260921".
--
-- ⚠ La fila de `Entregas_Virgilio` de LK 0058 se DEJÓ: dice 0 entregadas / 10 faltó, o sea que
-- no factura nada, y es historia de lo que pasó ese día.

create or replace view public.gv_tanda_armada_sin_armado as
with armadas as (
  select upper(btrim(r.texto)) as tanda,
         max(r.ts_cliente at time zone 'America/Argentina/Buenos_Aires') as tap
    from public."Registros_Produccion_Virgilio" r
   where r.opcion = 'TAP' and coalesce(btrim(r.legajo),'') not in ('0','1')
     and btrim(coalesce(r.texto,'')) <> ''
   group by 1),
 salidos as (
  -- lo que ya salió no se mira: su armado es historia y puede haber sido con otro código
  select regexp_replace(upper(btrim(split_part(r.texto,'|',1))),'\.0+$','') as np
    from public."Registros_Produccion_Virgilio" r
   where r.opcion in ('CCN','CRN') and coalesce(btrim(r.legajo),'') not in ('0','1')
     and btrim(coalesce(r.texto,'')) <> '' group by 1)
select upper(btrim(w.tanda))                                   as tanda,
       w.fecha_entrega                                         as sale,
       a.tap                                                   as armada_el,
       public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)   as np,
       w.razon_social, coalesce(w.zona,'') as zona, w.m3,
       (select count(*) from public."PPP_Web_Base" b
         where b.empresa = w.empresa
           and upper(btrim(b.np_label)) = upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx)))) as lineas_del_pedido,
       'la tanda figura ARMADA pero este pedido no tiene una sola linea en Entregas_Virgilio'::text as motivo
  from public."PPP_Web_Programacion" w
  join armadas a on a.tanda = upper(btrim(w.tanda))
 where coalesce(nullif(btrim(w.tanda),''),'') <> ''
   and w.fecha_entrega is not null and w.fecha_entrega >= current_date
   and not exists (select 1 from public."Entregas_Virgilio" e
                    where upper(btrim(coalesce(e.tanda,''))) = upper(btrim(w.tanda))
                      and upper(btrim(e.np)) = upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))))
   and not exists (select 1 from salidos s
                    where s.np = upper(btrim(public.gv_ppp_web_np_label(w.empresa, w.np, w.np_idx))))
 order by w.fecha_entrega, 1, 4;

alter view public.gv_tanda_armada_sin_armado set (security_invoker = true);
grant select on public.gv_tanda_armada_sin_armado to anon, authenticated;

insert into public."GV_Reglas_Centinela" (objeto, clase, patron, regla, quien_pidio, version) values
 ('gv_tanda_armada_sin_armado','vista','Entregas_Virgilio',
  'TAP y EP/TP son eventos de la TANDA, no del pedido: una tanda queda armada para siempre aunque despues le cambien los pedidos de adentro. El unico registro por NP es Entregas_Virgilio, y esta vista marca la NP que esta en una tanda armada sin una sola linea propia. Caso D69H (21/09): su TAP era de LK 0058, que ya no estaba, y sus 2 pedidos (62 cajas) iban a salir sin pickear.',
  'Luis','v20.70');

-- ── CHEQUEOS ─────────────────────────────────────────────────────────────────────────────────
--   select * from public.gv_tanda_armada_sin_armado;   -- vacia = todo bien
--   select * from public.gv_reglas_perdidas;           -- vacia = la regla sigue puesta
--
-- Y se probo ROMPIENDOLO, en transaccion abortada: devolviendo el TAP de D69H, el centinela
-- caza sus 2 NP (LK 0070 y LK 0083) y **anon ve las 2 filas** — o sea que no miente por RLS,
-- que es la trampa de la v20.45 (una vista security_invoker sobre una tabla con RLS devuelve
-- MENOS filas en vez de dar error).
