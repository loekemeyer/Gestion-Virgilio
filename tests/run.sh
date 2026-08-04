#!/usr/bin/env bash
# Suite de smoke-tests. Correr antes de pushear cambios a index.html / sw.js.
set -e
cd "$(dirname "$0")/.."

echo "== node --check sw.js =="
node --check sw.js

echo "== checkhtml (sintaxis de los <script> inline) =="
node tests/checkhtml.cjs

echo "== version-sync (APP_VERSION == SW_VERSION base — evita PWA cacheando app vieja) =="
node tests/version-sync.cjs

echo "== smoke (Playwright headless) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/smoke.cjs

echo "== ocg-norm (regresión: cruce de códigos del generador de OCs) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ocg-norm.cjs

echo "== stock-cutoff (regresión: stockComputeSaldos con cutoff/asOf, inicial siempre base) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/stock-cutoff.cjs

echo "== stock-idempotent (regresión: stockMove con client_id + ignore-duplicates; reintento no duplica) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/stock-idempotent.cjs

echo "== mon-silencio (regresión: operarios 'en silencio' en vivo — excluye FJ/PC/PB/prueba) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/mon-silencio.cjs

echo "== prod-compute (regresión: motor de Rendimiento — armM3/pickM3/tiempos, exclusión 0/1, factor faltantes) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/prod-compute.cjs

echo "== dead-handlers (regresión: ningún onclick/oninput llama a una función inexistente = botón muerto) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/dead-handlers.cjs

echo "== ap-resume (regresión: 'Seguir armado' retoma sin re-mandar AP) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ap-resume.cjs

echo "== ep-ppp-warn (regresión: EP de tanda fuera del PPP avisa antes de arrancar) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ep-ppp-warn.cjs

echo "== racks-propuesta (regresión: MG 'De los racks' propone para aprobar, no mueve stock) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/racks-propuesta.cjs

echo "== ssg-switch (regresión: switch admin del aviso 'picking sin stock') =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ssg-switch.cjs

echo "== fac-npc (regresión: aviso faltantes en Facturación + consulta NP/Líos) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/fac-npc.cjs

echo "== fac-falta-filter (regresión: chip + filtro 'solo con faltante' en Facturación) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/fac-falta-filter.cjs

echo "== falt-tareas (regresión: pop-up + asignación atómica de faltante que llegó) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/falt-tareas.cjs

echo "== comp-doblearmado (regresión: candado anti doble-armado de tanda) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/comp-doblearmado.cjs

echo "== tanda-lock (regresión: exclusividad picking/armado — no empiezan dos la misma) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/tanda-lock.cjs

echo "== cp-focus (regresion: Cargar las cajas abre el CP enfocado en la NP) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/cp-focus.cjs

echo "== pk-forzar-gondola (regresión: forzar góndola c/ excedente + confirm solo con líos pendientes) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/pk-forzar-gondola.cjs

echo "== dual-ubic-mg-draft (regresión: ubicación Loeke/Chef por NP + MG guarda borrador sin Cerrar) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/dual-ubic-mg-draft.cjs

echo "== fac-block-recuperable (regresión v6.21: bloqueo del tilde si el faltante se puede completar) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/fac-block-recuperable.cjs

echo "== mva-quien (regresión v6.66: 👤 siglas + legajo del que hizo/recibió cada movimiento) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/mva-quien.cjs

echo "== pk-scan (regresión v6.83 / idea 8243: lectora de código de barras detrás del switch) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/pk-scan.cjs

echo "== emp-np (regresión v6.85 / idea 9020: empresa por NP → sufijo LK/CH en el picking) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/emp-np.cjs

echo "== etl-lio (idea 5290 / v6.89: etiquetas de lío al cerrar cada lío, switch + legajo 0/1) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/etl-lio.cjs

echo "== ins-categorias (idea 7917 / v7.05: botonera de categorías en RI/EI) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ins-categorias.cjs

echo "== ssg-carrera-cron (v7.06: SSG no avisa si el cron ya descontó el picking de la tanda) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ssg-carrera-cron.cjs

echo "== stk-envasar-col (v7.06: la tabla de Stock muestra p/envasar y racks CH) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/stk-envasar-col.cjs

echo "== ssg-familia-empresa (v7.06: SSG suma la familia LK/CH del código partido) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ssg-familia-empresa.cjs

echo "== act-legajo0 (v7.06: getActivityStatus ignora legajo 0/1 → no tandas fantasma) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/act-legajo0.cjs

echo "== rcp-oc (v7.07: OC vigente en los botones de recepción + evento ROC por exceso +20%) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/rcp-oc.cjs

echo "== TODO OK =="
