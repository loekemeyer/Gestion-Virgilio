-- v20.88 — Renombrar una tanda dejaba la PROGRAMACION WEB con el codigo viejo.
--
-- Salio de un caso real (Luis, 21/09). El pallet de El Gran Bazar (NP LK 0043) esta en el
-- deposito con un papel impreso que dice **E03F**, pero el sistema la llamaba **E12L**: el
-- codigo se habia renombrado en algun momento y el papel quedo con el nombre viejo. Luis:
-- *"en la programacion vas a renombrar la tanda actual E12L a E03F"* — manda el pallet.
--
-- Al hacerlo, `gv_ppp_tanda_renombrar` contesto **4 objetos tocados** y la PPP siguio
-- diciendo E12L. Renombra 18 tablas y se saltea justo la tabla MADRE de los pedidos web:
--
--   Registros_Produccion_Virgilio (incluidos los PKC y los `ref` con pipe) · Entregas_Virgilio
--   Facturacion_NP · Movimientos_Stock (con fusion de deltas) · GV_Tandas_Lock · Tandas_Lock
--   Faltantes_Avisados · Faltantes_Revisados · Etiquetas_Lio · Faltantes_Tareas
--   GV_Conciliacion_Facturacion · GV_PPP_Prog_Override · GV_Vehiculo_Propio · Comprobantes_ARCA
--   GV_PPP_Armados_Espera · PPP_Web_Tandas
--   ... y NO PPP_Web_Programacion.
--
-- Consecuencia: la tanda queda **partida en dos nombres segun desde donde se la mire**. El
-- stock, el picking, el armado y la factura viajan al codigo nuevo; la PPP -que es lo que ve
-- el que programa- se queda con el viejo.
--
-- ⚠ Es el mismo tipo de agujero que el del `ref` compuesto (v20.72) y el de los pases que
-- eligen fecha (v20.83): una lista de lugares donde hay que replicar algo, y uno que falta.
-- **Al agregar una tabla con columna `tanda`, agregarla tambien aca.**
--
-- Medido antes de aplicar: **0 tandas web habian quedado desincronizadas** por esto, asi que
-- no hay historico que reparar. El agujero mordia en el proximo renombre de una tanda web.
--
-- Probado CORRIENDOLO, no leyendolo (regla del repo): `gv_ppp_tanda_renombrar('D69H','ZZ9Z')`
-- dentro de una transaccion abortada devuelve **5** objetos en vez de 4 y deja la programacion
-- en ZZ9Z.
--
-- Rollback: sacar el update de abajo. Vuelve a andar igual, dejando la PPP desincronizada.
--
-- Se aplico con el loop mecanico del repo (pg_get_functiondef -> replace -> execute), asi que
-- el resto del cuerpo es el vivo. Lo que se agrego, justo despues del update de
-- GV_PPP_Prog_Override:

  update public."GV_PPP_Prog_Override"        set tanda = v_b where upper(btrim(coalesce(tanda,''))) = v_a;

  -- v20.88 (Luis, 21/09) — LA QUE FALTABA, y es la tabla MADRE de la programacion web.
  update public."PPP_Web_Programacion" w set tanda = v_b, actualizado_at = now()
   where upper(btrim(coalesce(w.tanda,''))) = v_a;

-- Centinela (GV_Reglas_Centinela): objeto `gv_ppp_tanda_renombrar`, patron `PPP_Web_Programacion`.
-- Chequeo: select * from public.gv_reglas_perdidas;   -- vacia = la regla sigue ahi
