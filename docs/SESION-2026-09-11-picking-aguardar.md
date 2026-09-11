# Sesión 2026-09-11 — Picking: completar desde "a guardar" (idea 4259, v15.38)

Resumen para retomar en otra sesión. Todo esto YA está hecho y desplegado en `main`.

---

## 1. De dónde salió (el problema)

Arrancó investigando un síntoma que reportó el operario: **"artículos 546/587/502 en el
picking los manda a buscar al sector de excedentes, pero no hay stock ahí"**.

Investigando se llegó a la causa real, distinta del síntoma:

- El **picking descuenta SIEMPRE de góndola** (la reconciliación de eventos PKC hace
  `separar_pedidos +N / terminado −N`, con excedente-primero si hay).
- Si el operario agarra una caja que **físicamente está en "a guardar"** (mercadería recién
  recibida que nadie bajó a góndola), el sistema igual la descuenta de **góndola** → **góndola
  queda en negativo** y **a_guardar queda inflado**.
- **Caso testigo:** art **395**, NP **98613**, tanda **D68F** (2026-09-10, legajo 277). El
  operario pickeó 1 de 395 con góndola en 0; entraron 67 a `a_guardar` (recepción 37999) que no
  se bajaron a góndola → góndola de 395 quedó en **−1**. El sistema hasta tiró la alerta SSG
  ("picking sin stock en góndola"), o sea el dato estaba bien: la góndola en el sistema estaba
  vacía porque la recepción no se guardó.

También se aclararon cosas del flujo:
- El pop-up viejo (evento **RAG**, idea 5703) avisaba "faltó, hay en racks/a_guardar" pero era
  **solo informativo** ("Entendido") y **no descontaba** → dependía de que el operario después
  fuera al módulo aparte **Completar Pedido (CP)**.
- **"Ver módulo operarios"** en el admin usa el **legajo de PRUEBA (1)**: `enqueueReport` frena
  todo evento de prueba → **no persiste nada** (ni eventos ni stock). Sirve para probar la UI
  sin ensuciar datos. Se probó una tanda E03D así y no dejó rastro.

---

## 2. Qué se decidió construir (pedido del dueño, textual)

Ajuste al pipeline de picking, en 2 fases:

**Fase 1 — picking código por código (como hoy):** el sistema manda a **excedente (primero) →
góndola**. El operario agarra de esos dos lugares, cargando cantidad. (Excedente = góndola donde
un código está de más porque su góndola original está llena.)

**Fase 2 — al terminar de agarrar todo, ANTES de "Terminé el picking":** el sistema mira los
**faltantes** (pedido > puesto) que tienen stock **SOLO en "a guardar"** (racks NO; el excedente
ya se usó en fase 1) y salta un **pop-up**: *"faltaron N de tal código, hay en a guardar, andá a
buscarlas — ¿cuántas agarraste?"*. El operario marca cuántas.

**El movimiento cuando marca N (confirmado por el dueño):**
```
a_guardar        −N
separar_pedidos  +N   (queda en "Pickeados" y sigue el pipeline: armado TAP → a_facturar → facturado)
```
**Góndola NO se toca.** Eso arregla el negativo tipo 395.

Decisiones tomadas (regla "no preguntar, razonar"):
- **Backend manda, front espeja.**
- El pop-up **reemplaza** al viejo (RAG). **Racks queda fuera** del flujo.
- El operario **sigue cargando cantidad** en el picking normal (no se cambió a "hay/no hay").

---

## 3. Qué se implementó (v15.38)

### Backend (proyecto Virgilio `hrxfctzncixxqmpfhskv`) — YA aplicado
- **Índice** `mov_stock_aguardar_dedup` (parcial `WHERE tipo='aguardar'`) en `Movimientos_Stock`.
- **Función** `public.gv_reconciliar_aguardar()` (SECURITY DEFINER, revocada a anon/authenticated):
  lee el **último evento PKA por (tanda, art)** = total absoluto agarrado de a_guardar, y hace
  UPSERT idempotente de `a_guardar −q / separar_pedidos +q` con **`tipo='aguardar'`**. Clampea por
  artículo al a_guardar disponible (excluyendo sus propias filas), con ventana por tanda → **nunca
  deja a_guardar negativo**.
- **Cron** `gv-reconciliar-aguardar` (jobid **81**, `*/2 * * * *`).
- **Evento nuevo** `opcion='PKA'` en `Registros_Produccion_Virgilio`, `texto='TANDA|ART|N'`.
- **Por qué `tipo='aguardar'` y no `'picking'`:** la reconciliación de picking
  (`reconciliar_pipeline_stock_etapa1`, rama B.3) recalcula `terminado` mirando SOLO `tipo='picking'`.
  Con tipo propio, estas filas NO vuelven a descontar góndola.
- SQL fuente: `sql/gv_reconciliar_aguardar.sql`.

### Front (`index.html`) — en `main`
- `pkFetchAGuardar(arts)` — saldo de a_guardar por art (como `pkFetchExcedente` pero a_guardar).
- `pkPrepAGuardar` / `pkAGuardarCardHtml` / `pkAGuardarConfirm` / `pkAGuardarSkip` — el paso nuevo
  en la pantalla de cierre del picking (`pkRenderDone`), antes de "Terminé el picking".
- `pkEmitAGuardar` — emite el evento **PKA** (respeta legajo de prueba y cola offline).
- `faltantesDeTanda` — ahora **RESTA** lo completado por PKA → el armado (evento FAL) y la
  facturación ven el faltante **NETO**.
- El pop-up viejo RAG se **desactivó** en `stockBajaPicking` (quedó `if (false && enDeposito.length)`).
- CSS `.pk-ag*` para la tarjeta.

### Versión
- `APP_VERSION`/`SW_VERSION` = **v15.38** (arrancó como v14.81 pero `main` se movió mucho durante
  la sesión —de v14.80 a v15.37 por otros pushes— así que salió v15.38).

---

## 4. Cómo se probó ("funciona y no rompe nada")

- **Backend, aislado con rollback:** evento PKA de prueba `ZZTEST2|321|3` → `gv_reconciliar_aguardar()`
  bajó 321 de a_guardar 50→47 y separar_pedidos 0→3. Re-correr = idempotente (47/3). Clamp probado
  con 395 (a_guardar 0 → q=0, no negativo). Todo el rastro de prueba borrado; 321 volvió a 50/0.
- **Suite de tests** (`tests/run.sh`): al escribir esto daba **126/128**. Las 2 fallas
  (`fac-excel-isis`, `imp-tabla`) **ya existían antes** del cambio y eran ajenas.
  **⚠ Ya están arregladas — v15.40, commit `aae24d4`, otra sesión.** No eran bugs de la app:
  eran los dos tests que habían quedado desactualizados. `imp-tabla` clavaba 14 columnas cuando
  Importados ya tiene 15 (sumó Reingreso) y buscaba botones que hoy son "Baches"; ahora compara
  el `colgroup` contra el `thead`, que es el bug que de verdad quería cazar. `fac-excel-isis`
  exigía la leyenda "2% Descuento Web" en el Excel a ISIS, pero desde la v14.57 esa columna sale
  **sólo** si la condición de pago (col J) es 8-13 o 18, y ninguna NP del fixture tenía condición;
  se le agregó una NP web (LK 0001, condición 8) y ahora chequea las dos mitades de la regla.
  **Estado al 11/09 (revisado por Luis): suite completa en verde, 118 bloques, 0 fallas, y CI de
  `main` en verde desde el run 404.**
- Se **actualizaron 2 tests** que probaban el pop-up viejo: `pk-racks-aguardar.cjs` (reescrito al
  flujo nuevo) y `fgu-faltante-gondola.cjs` (la verificación de racks→RAG ahora comprueba que RAG
  está desactivado).
- checkhtml 0 errores, dead-handlers 0 muertos, smoke sin pageerrors.

---

## 5. Cómo verificarlo en producción

- **UI (sin ensuciar):** admin → **"Ver módulo operarios"** (legajo prueba) → hacé un picking de
  una tanda con un faltante de un código que tenga stock en **a guardar** → aparece el paso nuevo.
  En prueba **no descuenta** (no persiste, por diseño).
- **Real:** un operario con un faltante real marca cuántas agarró de a_guardar → en ~2 min el cron
  `gv-reconciliar-aguardar` descuenta a_guardar (no góndola).
- El badge de versión abajo debe decir **v15.38** (o superior si hubo más pushes).

---

## 6. Rollback (si hiciera falta)

Documentado en `docs/ROLLBACK-PRODUCCION.md` §1.x. Resumen:
```sql
select cron.unschedule('gv-reconciliar-aguardar');
drop function if exists public.gv_reconciliar_aguardar();
delete from public."Movimientos_Stock" where tipo='aguardar';   -- deshace lo que ya escribió
drop index if exists public.mov_stock_aguardar_dedup;
-- (opcional) delete from public."Registros_Produccion_Virgilio" where opcion='PKA';
```
Front: reactivar el pop-up viejo cambiando `if (false && enDeposito.length)` por `if (enDeposito.length)`
y sacar `pkAGuardarCardHtml()` del cierre del picking.

---

## 7. Docs y registro (dónde quedó todo)

- `sql/gv_reconciliar_aguardar.sql` — el SQL del backend.
- `docs/SUPABASE-GESTION-VIRGILIO.md` §3.cc — detalle, pruebas, rollback.
- `docs/ROLLBACK-PRODUCCION.md` §1.x — rollback del objeto compartido.
- `docs/IDEAS-USUARIO.md` — idea **4259** marcada `[x]` hecha.
- Tabla `agente_propuestas`: código **4259**, `estado='hecha'`.
- Commits en `main` (repo `loekemeyer/Gestion-Virgilio`), v15.38.

---

## 8. Lo que quedó pendiente / próximos pasos

- El dueño dijo **"seguimos con el resto de los ajustes del pipeline"** en otra sesión —
  ESTE archivo es para arrancar esa charla. Faltó definir qué otros ajustes quiere.
- **Deuda vieja NO tocada:** el pop-up nuevo cubre **a_guardar**; **racks** ya no dispara ningún
  aviso (por pedido del dueño). Si algún día se quiere avisar de racks, es un flujo aparte.
- **No es magia:** el negativo tipo 395 se evita **si el operario marca 0 en góndola** cuando la
  góndola está físicamente vacía y **completa desde a_guardar** en el paso nuevo. Si igual pone la
  cantidad en el paso normal (porque encontró la caja cerca de la góndola), sigue descontando
  góndola. El fix de fondo real sería que la recepción se **baje a góndola** (evento guardado), que
  es un tema operativo, no de la app.
- ~~Las 2 fallas de tests preexistentes (`fac-excel-isis`, `imp-tabla`)~~ → ✅ **cerrado**:
  arregladas en la v15.40 (`aae24d4`) y verificado el 11/09 (suite entera verde, CI de `main`
  verde). Detalle en §4. **No quedan tests rotos.**

---

## 9. Contexto útil para la próxima sesión

- Sesión de Claude: https://claude.ai/code/session_01PtbXVnznWz75nqeZ43eduS
- Proyecto Supabase Virgilio: `hrxfctzncixxqmpfhskv`. Consultar con MCP `execute_sql`.
- Tabla central de eventos: `Registros_Produccion_Virgilio` (`opcion`=código, `texto`=datos).
- Stock event-sourced en `Movimientos_Stock`; saldos en la vista `vista_saldos_stock`
  (deps: terminado=góndola, excedente, separar_pedidos=Pickeados, a_facturar, a_guardar, racks…).
- El repo se despliega SOLO con push a `main` (GitHub Pages). Muy activo: `main` se mueve seguido
  por otras sesiones → si vas a pushear, rebasá sobre lo último y bumpeá la versión al número que
  siga.
