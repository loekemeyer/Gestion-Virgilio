#!/usr/bin/env bash
# Suite de smoke-tests. Correr antes de pushear cambios a index.html / sw.js.
set -e
cd "$(dirname "$0")/.."

echo "== node --check sw.js =="
node --check sw.js

echo "== checkhtml (sintaxis de los <script> inline) =="
node tests/checkhtml.cjs

echo "== smoke (Playwright headless) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/smoke.cjs

echo "== ocg-norm (regresión: cruce de códigos del generador de OCs) =="
PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}" node tests/ocg-norm.cjs

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

echo "== TODO OK =="
