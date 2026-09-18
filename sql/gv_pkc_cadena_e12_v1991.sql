-- v19.91 — Los escaneos vuelven a su tanda: la cadena de códigos reciclados E12 (problema 429)
-- ============================================================================================
-- REGLA DEL DUEÑO (Thomas, 2026-09-18): *"si armo un pedido y lo muevo a otra tanda o creo otra
-- tanda, el contenido de ese pedido (físico) sigue a ese pedido (registro en la PPP)"*.
--   → El escaneo de picking pertenece a la tanda donde está HOY su pedido.
--
-- QUÉ HABÍA PASADO. Cada código se reutilizó y sus PKC quedaron UNA GENERACIÓN ATRÁS: al
-- renombrar, el stock viajaba al nombre nuevo pero los eventos PKC se quedaban con el viejo
-- (problema 421, arreglado en la v19.80), y el cron 68 volvía a crear el picking con ese código.
-- Como el código liberado se reutilizó después para otra tanda, cada uno heredó el picking de su
-- inquilino anterior. Verificado artículo por artículo, no por parecido:
--
--   PKC bajo   →  son el picking de   evidencia
--   E12A (66)  →  E12S    las 7 NP de los remitos en papel (LK 0030/0036/0037/0039/0040/0044/0045)
--   E12E (62)  →  E37F    62 de 62 códigos, 0 sobrantes
--   E12I (37)  →  E12E    37 de 37 exactos (98605/98606/98607)
--   E12M (11)  →  E12A    LK 0029 Tegerina: 7 códigos exactos + el dual 437E; pide 47, pickeó 40
--   E12J (32)  →  E12G    32 de 32, 93 = 93
--   E12K  (8)  →  E12J    8 de 8, 20 = 20 contra el ENT de 98618
--
-- ⚠⚠ UN SOLO UPDATE CON EL MAPA, NO SEIS ENCADENADOS. E12A, E12E y E12J son origen Y destino a
-- la vez. En updates sucesivos, el `E12A → E12S` se habría llevado por delante los 11 PKC que
-- acababan de llegar de E12M. En una sola sentencia cada fila se evalúa contra su valor VIEJO.
--
-- ⚠⚠ SÓLO SE MUEVEN LOS EVENTOS DE CAMPO 1 (PKC, PSP, FGU, SSG, RAG), que NO llevan NP. El primer
-- intento movió también TAL, ENT y compañía porque `gv_evento_tanda` los resuelve — y ésos SÍ
-- llevan la NP, o sea que ya estaban en la tanda correcta. Se devolvieron desde el backup.
-- La regla del dueño habla del PEDIDO: el evento que ya nombra su pedido no se toca.
--
-- ⚠ El stock de picking se pone en CERO y lo reconstruye el cron desde los PKC ya reasignados.
-- `delta = 0` y no DELETE: `trigger_actualizar_saldo_stock` es AFTER INSERT OR UPDATE y no corre
-- en DELETE. Y el `pg_advisory_xact_lock(5768)` es el mismo del cron 68, para que no se meta.
--
-- Guardas: las 9 tandas tenían que quedar EXACTAS o no se commiteaba nada
-- (E12S 188 · E37F 107 · E12E 38 · E12A 40 · E12G 93 · E12J 20 · E12M/E12I/E12K 0).
-- Backups: zz_backups."GV_Backup_Eventos_Cadena_E12_20260918" (257) y
--          zz_backups."GV_Backup_MovStock_Cadena_E12_20260918" (1.724), las dos con RLS.

select pg_advisory_xact_lock(5768);

update public."Registros_Produccion_Virgilio" r
   set texto = public.gv_evento_set_tanda(r.opcion, r.texto, m.destino)
  from (values ('E12A','E12S'), ('E12E','E37F'), ('E12I','E12E'),
               ('E12M','E12A'), ('E12J','E12G'), ('E12K','E12J')) as m(origen, destino)
 where public.gv_evento_tanda(r.opcion, r.texto) = m.origen
   and public.gv_evento_set_tanda(r.opcion, r.texto, m.destino) is not null
   and public.gv_evento_tanda_campo(r.opcion) = 1;   -- ⚠ sólo los que NO llevan NP

update public."Movimientos_Stock" set delta = 0
 where tipo = 'picking' and delta <> 0
   and upper(btrim(ref)) in ('E12A','E12E','E12I','E12J','E12K','E12M','E12S','E37F','E12G');

select public.reconciliar_pipeline_stock_etapa1();

-- ============================================================================================
-- LO QUE QUEDÓ ABIERTO Y NO SE TOCÓ: 192 cajas que los armados drenaron de más
-- ============================================================================================
-- Con el picking ya en su lugar queda a la vista una TERCERA capa del mismo bug. `etapa2` es
-- INSERT-ONLY con guard (`not exists (separado de esa tanda+articulo)`): una vez que escribió el
-- `separado`, no lo recalcula nunca. Así que los armados de ayer y hoy drenaron lo que HABÍA
-- pickeado bajo ese código en ese momento — que era el picking del inquilino anterior:
--
--   tanda   drenó el armado   picking real   de más
--   E12E         114               38          76
--   E12J         100               20          80
--   E12K          46                0          46
--                                             ---
--                                             202
--
-- Esas cajas salieron de `separar_pedidos` y entraron a `a_facturar` + `terminado`, así que el
-- saldo total del depósito no cambia — pero el comprometido de esas tres tandas queda en
-- negativo (E12E −76, E12J −80, E12K −46) y hay cajas de más contadas como armadas.
-- NO se corrigió: toca `a_facturar`, o sea camino de facturación. Va con decisión aparte.
--
-- E12S, la de los remitos en papel, quedó EXACTA: 188 pickeado, 188 armado, 0 colgado.
--
-- Chequeo:
--   select * from public.gv_stock_picking_duplicado;   -- vacía
--   select * from public.gv_reglas_perdidas;           -- vacía
