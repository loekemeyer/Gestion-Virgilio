#!/bin/bash
# ---------------------------------------------------------------------------
# ESTO SE PEGA EN EL "SETUP SCRIPT" DEL ENTORNO DE CLAUDE CODE WEB.
#
# Donde: claude.ai/code -> el icono de nube con el nombre del entorno (fila de
# arriba del cuadro de mensaje; no hay URL directa) -> pasar el mouse por el
# entorno -> el engranaje de la derecha -> campo "Setup script" -> Update.
#
# Corre como root en Ubuntu 24.04, ANTES de que arranque Claude Code, una vez
# por entorno (despues se cachea; se vuelve a correr si se cambia este texto).
# Tiene que salir con exit 0 o la sesion no arranca: por eso el "|| true".
#
# Que hace: deja la allow list de lectura/edicion en ~/.claude/settings.json,
# que es el UNICO lugar cuya allow list no necesita que el workspace este
# "trusted" — o sea que vale para TODOS los repos, tambien en los contenedores
# remotos, que nacen vacios. Mergea: nunca pisa lo que ya este.
# git push, curl, rm y el SQL de Supabase NO estan: esos siguen preguntando.
#
# El por que completo esta en CLAUDE.md, regla "por que Claude pide permiso
# para TODO".
# ---------------------------------------------------------------------------
python3 - <<'PY' || true
import json, os
BASE = [
    "Read", "Glob", "Grep", "Edit", "Write", "NotebookEdit",
    "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
    "Bash(git show:*)", "Bash(git branch:*)", "Bash(git fetch:*)",
    "Bash(git add:*)", "Bash(git commit:*)",
    "Bash(ls:*)", "Bash(mkdir:*)", "Bash(node --check:*)",
]
p = os.path.expanduser("~/.claude/settings.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except Exception:
    d = {}
allow = d.setdefault("permissions", {}).setdefault("allow", [])
allow.extend(x for x in BASE if x not in allow)
json.dump(d, open(p, "w"), indent=2)
print("permisos de Claude listos:", len(allow), "entradas en", p)
PY
