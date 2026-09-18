#!/bin/bash
# ---------------------------------------------------------------------------
# ESTO SE PEGA EN EL "SCRIPT DE CONFIGURACION" DEL ENTORNO DE CLAUDE CODE WEB.
#
# Donde: claude.ai/code -> el icono de nube con el nombre del entorno (fila de
# arriba del cuadro de mensaje; no hay URL directa) -> pasar el mouse por el
# entorno -> el engranaje de la derecha -> "Editar entorno de nube" -> campo
# "Script de configuracion" -> Guardar cambios. Aplica a las sesiones NUEVAS.
#
# Corre como root en Ubuntu 24.04, ANTES de que arranque Claude Code, una vez
# por entorno (despues se cachea; se vuelve a correr si se cambia este texto).
# Tiene que salir con exit 0 o la sesion no arranca: por eso el "|| true".
#
# Que hace: deja la allow list en ~/.claude/settings.json, que es el UNICO
# lugar cuya allow list no necesita que el workspace este "trusted" — o sea que
# vale para TODOS los repos, tambien en los contenedores remotos, que nacen
# vacios. Mergea: nunca pisa lo que ya este.
#
# PRECEDENCIA: deny > ask > allow. Por eso "Bash" pelado en ALLOW deja correr
# toda la terminal sin preguntar, pero git push, curl y wget siguen preguntando
# porque estan en ASK, y rm -rf no pasa ni preguntando porque esta en DENY.
# (Medido: con "Bash" en allow y "Bash(curl:*)" en ask, el curl queda denegado.)
#
# QUE SIGUE PREGUNTANDO, a proposito:
#   - mcp__Supabase__apply_migration / deploy_edge_function: estructura y deploy.
#     (execute_sql SI esta permitida desde el 18/09: preguntaba en cada select y
#     era el 90 % de los carteles. La regla del 26/08 —los datos no se tocan sin
#     permiso explicito— la sostiene el CLAUDE.md, no el dialogo.)
#   - git push, curl y wget (lista ASK).
#   - Todo lo que este en DENY, que ni preguntando pasa.
#
# El por que completo esta en CLAUDE.md, regla "por que Claude pide permiso
# para TODO".
# ---------------------------------------------------------------------------
python3 - <<'PY' || true
import json, os
ALLOW = [
    # leer, buscar, editar, escribir
    "Read", "Glob", "Grep", "Edit", "Write", "NotebookEdit",
    # subagentes y tareas
    "Agent", "TaskCreate", "TaskUpdate", "TaskGet", "TaskList", "TaskOutput", "TaskStop",
    "Skill", "TodoWrite",
    # documentacion
    "WebFetch", "WebSearch",
    # TODA la terminal (git, node, npm, python, tests...). Lo peligroso va en DENY.
    "Bash",
    # Supabase: el SQL (Thomas, 18/09: en este laburo es casi todo) y lo que LEE.
    # ⚠ Que no pregunte NO cambia la regla del 26/08: los datos no se tocan sin
    # permiso explicito. Eso lo sostiene el CLAUDE.md, no el dialogo.
    "mcp__Supabase__execute_sql",
    "mcp__Supabase__list_tables", "mcp__Supabase__list_migrations",
    "mcp__Supabase__list_projects", "mcp__Supabase__get_project",
    "mcp__Supabase__get_project_url", "mcp__Supabase__get_publishable_keys",
    "mcp__Supabase__list_edge_functions", "mcp__Supabase__get_edge_function",
    "mcp__Supabase__list_extensions", "mcp__Supabase__get_advisors",
    "mcp__Supabase__query_logs", "mcp__Supabase__search_docs",
    "mcp__Supabase__generate_typescript_types",
    # GitHub: solo lo que LEE
    "mcp__github__get_file_contents", "mcp__github__get_commit",
    "mcp__github__list_commits", "mcp__github__list_branches",
    "mcp__github__list_tags", "mcp__github__list_issues",
    "mcp__github__list_pull_requests", "mcp__github__pull_request_read",
    "mcp__github__issue_read", "mcp__github__search_code",
    "mcp__github__search_issues", "mcp__github__search_pull_requests",
    "mcp__github__search_commits", "mcp__github__get_me",
    "mcp__github__actions_list", "mcp__github__actions_get",
    "mcp__github__get_job_logs", "mcp__github__get_check_run",
]
ASK = [
    # esto SI pregunta, una vez por comando y por sesion: es lo que sale
    # para afuera (push) o toca la red a mano (curl). Regla del CLAUDE.md.
    "Bash(git push:*)", "Bash(curl:*)", "Bash(wget:*)",
]
DENY = [
    "Bash(rm -rf:*)", "Bash(rm -fr:*)", "Bash(sudo rm:*)",
    "Bash(git push --force:*)", "Bash(git push -f:*)",
    "Bash(git push --force-with-lease:*)",
    "Bash(git reset --hard:*)", "Bash(psql:*)", "Bash(supabase db:*)",
    "Read(./.env)", "Read(./.env.*)",
]
p = os.path.expanduser("~/.claude/settings.json")
os.makedirs(os.path.dirname(p), exist_ok=True)
try:
    d = json.load(open(p))
except Exception:
    d = {}
perm = d.setdefault("permissions", {})
# Modo de arranque de la sesion. "auto" = corre todo con chequeo en segundo plano,
# que es lo que existe justamente contra la lluvia de carteles. Las reglas de ASK
# siguen preguntando igual (a proposito). Solo vale desde ~/.claude/settings.json:
# en el .claude/settings.json de un repo, "auto" se ignora.
perm["defaultMode"] = "auto"
for clave, lista in (("allow", ALLOW), ("ask", ASK), ("deny", DENY)):
    actual = perm.setdefault(clave, [])
    actual.extend(x for x in lista if x not in actual)
json.dump(d, open(p, "w"), indent=2)
print("permisos de Claude:", len(perm["allow"]), "allow /", len(perm["ask"]),
      "ask /", len(perm["deny"]), "deny / modo", perm["defaultMode"], "->", p)
PY
