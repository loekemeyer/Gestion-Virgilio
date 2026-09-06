# Runbook — "no llegó nada de los operarios" (eventos perdidos / stock desfasado)

> Escrito el domingo 2026-09-06 a pedido del dueño (*"pensá cuáles son los puntos de control que hay que
> hacer si sucede esto"*), después de una **falsa alarma**: dije que "el viernes no llegó ningún evento" y
> el día sin eventos era el sábado 5/9 (el 4/9 era viernes y llegó todo). Por eso el control 0 existe.

## Cómo funciona hoy (lo que hace que casi nunca se pierda nada)

- Cada acción del celular (EP/TP, AP/TAP, PKC por artículo, CC/CCN, CR/CRN, MG, RR…) se **encola** en el
  celular (`localStorage` `legajo_queue_virgilio_v1` + IndexedDB `registro-prod-virgilio`) y se manda a
  `Registros_Produccion_Virgilio`. Reintento cada 3 s, al volver la red, al abrir la app y por Background
  Sync. **Sin tope de intentos**: un evento sólo sale de la cola cuando el servidor contesta 201 o 409.
- `client_id` es UNIQUE en la tabla → reenviar nunca duplica. El `ts_cliente` es la hora real de la
  acción, no la del envío: un evento que llega 3 días tarde cae en el día correcto.
- El **stock no lo escribe el celular** para picking/armado: lo rearma el cron `reconciliar-pipeline-stock`
  (jobid 68, cada 10 min) desde los eventos PKC/TP (etapa 1) y TAP + `Entregas_Virgilio` (etapa 2), y
  drena `a_facturar` con los tics de `Facturacion_NP` (etapas 3/4; web: jobid 74). O sea: **si los eventos
  llegan, aunque sea tarde, el stock se rearma solo.**
- Lo que el celular sí escribe directo: `Entregas_Virgilio` (al terminar el armado, cola `vir_entregas_pend`),
  `Movimientos_Stock` para MG/RR/CP/racks (cola `vir_stock_pend`). También con `client_id` idempotente.
- Envíos que fallan quedan en `Auditoria_Produccion_Virgilio` (`motivo = network | server_NNN`), y el agente
  `error_envio` avisa los que **nunca** llegaron (anti-join contra la tabla real).

## Controles, en orden

### 0. ¿Es un día hábil y trabajado? ¿Qué día de la semana es?
```sql
select d::date, to_char(d, 'TMDay') dia,
  (select count(*) from public."Registros_Produccion_Virgilio" r
    where (r.ts_inicio at time zone 'America/Argentina/Buenos_Aires')::date = d::date and r.legajo not in ('0','1','')) eventos_operarios,
  (select count(*) from public."Movimientos_Stock" m where (m.ts at time zone 'America/Argentina/Buenos_Aires')::date = d::date) movs_stock,
  (select count(*) from public."Facturacion_NP" f where (f.facturado_at at time zone 'America/Argentina/Buenos_Aires')::date = d::date) tics_fac
from generate_series(current_date - 7, current_date, interval '1 day') d;
```
Un sábado, domingo, feriado (`GV_Dias_No_Habiles`, `planify.feriados`) o día sin trabajo da 0 y **no es un
incidente**. Cruzar con remitos/facturas de ISIS del mismo día: si ISIS tampoco tiene nada, no se trabajó.

### 1. ¿Los celulares intentaron mandar? (¿red o app?)
- Edge logs de Supabase, POST a `/rest/v1/Registros_Produccion_Virgilio` por User-Agent Android en el
  horario de trabajo (herramienta `query_logs`, `source = 'edge_logs'`). Cero = los celulares no tuvieron
  red o nadie usó la app. Con 4xx/5xx = la app mandó y el servidor rechazó → mirar el error.
- `Auditoria_Produccion_Virgilio` del día: `motivo = network` = sin señal; `server_5xx/4xx` = problema
  nuestro (ejemplo real: 2026-08, trigger PKC pasaba el `statement_timeout` → 500 en cada PKC; los 131
  eventos llegaron solos al destrabar).
- `errores_cliente` (crashes JS) y `reporte_agentes` categoría `error_app`.

### 2. Celulares primero, antes de tocar nada
En cada celular de operario (hoy 8, 104, 237, 277, 94): abrir la app **con WiFi** y mirar el badge de
versión abajo a la derecha:
- `vX.YY ✓` → nada en cola.
- `vX.YY ⏳ N` → N eventos pendientes por falta de red: se mandan solos; dejar la app abierta.
- `vX.YY ⚠ N` → rechazados por el servidor: **no borrar la app**, tocar el cartel rojo para reintentar y
  avisar. Se ve el motivo en `Auditoria_Produccion_Virgilio`.
- Si pasaron de Producción a Gestión: la cola vive en el **origen** de cada app; hay que abrir la app que se
  usó ese día (Producción) para vaciarla. Gestión no la ve.
Después: esperar 10 min (cron 68) y verificar por tanda: eventos (EP/TP/PKC/AP/TAP) → `Entregas_Virgilio`
→ `Movimientos_Stock` (`tipo picking/separado` con `ref = tanda`).

### 3. Sólo si las colas están vacías o el celular se borró: reconstruir
Fuente: **composición de cada factura de ISIS** (lo que salió) + **conteo físico de lo armado sin
facturar** (lo que está en la zona de armado). Lo pedido = `PPP_Base_Pedidos`; faltante = pedido − real.
Se reconstruye **con eventos, no tocando saldos**, así el cron rearma el stock por el camino normal:
1. `Registros_Produccion_Virgilio`: `EP`/`TP` (texto = tanda, `ts_inicio` = hora real de inicio,
   `ts_cliente` = fin), `PKC` por artículo (`texto = TANDA|ART|esperado|real`, `client_id =
   pkc_<legajo>_<tanda>_<art>_<día>`), `AP`/`TAP`; todo con la fecha real y el legajo real (nunca 0/1).
2. `Entregas_Virgilio` por NP y artículo (`cajas_pedidas`, `cajas_entregadas`, `cajas_falto`, `tanda`,
   `fecha_salida`): dispara la etapa 2 sola (trigger por statement).
3. Tics de `Facturacion_NP` de lo facturado (fecha real) → etapas 3/4 drenan `a_facturar`.
4. Verificar con `vista_stock_vs_pedidos` (separar_pedidos / a_facturar no deben quedar colgados) y
   `vista_facturacion_faltantes`.
Antecedentes con SQL de ejemplo: `sql/backfill_entregas_virgilio_20260831.sql` y
`sql/backfill_faltantes_entregas_20260831.sql`. Siempre: backup antes, OK explícito del dueño, anotar en
`docs/SUPABASE-GESTION-VIRGILIO.md`.

### 4. Cruce factura ISIS ↔ app, por NP
Cajas por artículo en la FC de ISIS contra `Entregas_Virgilio.cajas_entregadas` de la NP (y contra
`vista_facturacion_faltantes`). Cualquier diferencia es error de stock o de facturación. Hoy es a mano
(foto/planilla → SQL); es candidato a pantalla ("Cruce FC ISIS").

### 5. Lo que NO hacer
- No ajustar saldos a mano (`tipo = ajuste`) para "arreglar" lo que falta: se pierde la trazabilidad y el
  cron no lo entiende. Ajuste manual sólo para diferencias físicas comprobadas (conteo).
- No borrar la app ni los datos del celular con la cola llena: es el único escenario real de pérdida.
- No declarar el incidente sin el control 0.

## Pendiente (a decidir por el dueño)
- Alerta automática `gv-alerta-sin-eventos` (cron lun–vie 10:30 ART, Telegram si un día hábil no tiene
  eventos de operarios). Hoy el monitor marca "operario en silencio" por persona pero no avisa por Telegram.
- Pantalla de cruce FC ISIS ↔ app.
