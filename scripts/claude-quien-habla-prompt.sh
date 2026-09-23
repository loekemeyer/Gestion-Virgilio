#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# HOOK UserPromptSubmit — INSISTE con "¿quién sos?" en CADA mensaje, hasta que
# haya una confirmación POSITIVA del usuario.
#
# Thomas, 2026-09-23: *"que hasta que no tengas confirmación positiva del usuario
# preguntes quién es"*.
#
# El `SessionStart` (scripts/claude-quien-habla.sh) avisa UNA vez y se puede pasar
# por alto sin que nada lo note. Éste corre en cada mensaje y no se calla hasta que
# alguien conteste.
#
# ⚠ NO BLOQUEA (Thomas dijo que no): el trabajo sigue. Lo que espera es la
# ATRIBUCIÓN — no se carga una tarea de Planify ni se registra un problema a nombre
# de alguien adivinado.
#
# ⚠ La confirmación la detecta el HOOK, no el modelo: lee el prompt y busca un
# nombre del padrón con una forma de presentación ("soy X", "habla X", "te escribe
# X", o el nombre solo, que es como se contesta "¿quién sos?"). Así no depende de
# que el modelo se acuerde de anotar nada.
#
# ⚠ Un nombre mencionado de pasada NO cuenta: "Luis pidió que…" lo escribe
# cualquiera. Por eso se exige la forma de presentación o el mensaje corto.
#
# ⚠ La salida va en JSON. Medido el 23/09: la salida de un hook en TEXTO PLANO la
# corre el CLI, la anota como `success` y LA DESCARTA ("Hook output does not start
# with {, treating as plain text"). Los dos hooks de caveman estuvieron muertos
# dos días por eso.
# ---------------------------------------------------------------------------
set -uo pipefail

payload="$(cat 2>/dev/null || true)"
sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -z "$sid" ] && sid="sin-sesion"
marca="${TMPDIR:-/tmp}/claude-quien-habla-${sid}"

[ -f "$marca" ] && exit 0          # ya contestó: no se pregunta más

prompt="$(printf '%s' "$payload" \
  | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\(.*\)","session_id".*/\1/p')"
[ -z "$prompt" ] && prompt="$(printf '%s' "$payload" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
low="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -d '\r')"

# Padrón de Planify (nombre reconocible -> employee_id). Thomas es la excepción:
# no usa Planify, sus pedidos van al 20 con el prefijo "Th ".
nombres="thomas|tomas|tomás|luis|marianela|mariane|gaston|gastón|elias|elías|nazareno|angely|viviana|vivi|alan|diego|nora|juan cruz|pablo|martin|martín|romina|ivan|iván|jhonny|yanina|melany|franco|damian|damián"

quien=""
if printf '%s' "$low" | grep -Eq "(^|[^a-záéíóúñ])(soy|habla|te escribe|escribe|aca|acá|aquí|aqui) +($nombres)([^a-záéíóúñ]|$)"; then
  quien="$(printf '%s' "$low" | grep -Eo "(soy|habla|te escribe|escribe|aca|acá|aquí|aqui) +($nombres)" | head -1 | awk '{print $NF}')"
elif [ "$(printf '%s' "$low" | wc -w)" -le 3 ] && printf '%s' "$low" | grep -Eq "(^|[^a-záéíóúñ])($nombres)([^a-záéíóúñ]|$)"; then
  # respuesta corta a "¿quién sos?": "luis", "soy yo, marianela", "thomas"
  quien="$(printf '%s' "$low" | grep -Eo "($nombres)" | head -1)"
fi

emit() { printf '%s' "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"$1\"}}"; }

if [ -n "$quien" ]; then
  printf '%s\n' "$quien" > "$marca"
  emit "IDENTIDAD CONFIRMADA en este mensaje: **$quien**. No volver a preguntar en esta sesion. Ruteo de Planify: si es Thomas -> employee_id 20 (Tomas Beviglia) con el nombre antepuesto por 'Th '; cualquier otro -> su propio employee_id, sin prefijo."
  exit 0
fi

emit "TODAVIA NO SABES QUIEN ESCRIBE, y el mail de la cuenta NO cuenta como respuesta: es de la CUENTA, no de la persona (por ese mail escriben Thomas, Luis, Marianela, Elias y otros). NO frenes ni interrumpas el trabajo con la pregunta: hace lo que te pidieron. Lo unico que espera es la ATRIBUCION -- no cargues una tarea de Planify ni registres un problema a nombre de nadie adivinado. Y ANTES DE CERRAR la respuesta, sumalo a las decisiones pendientes del final, textual: 'Confirmame quien sos (Thomas, Luis, Marianela, Gaston, Elias...) para dejar la tarea en la agenda correcta'. Este aviso se repite en cada mensaje hasta que haya confirmacion."
