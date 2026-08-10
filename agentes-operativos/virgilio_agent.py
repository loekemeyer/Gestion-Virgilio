"""
Auditor de Inconsistencias — Managed Agent operativo para Producción Virgilio
=============================================================================

Agente que cada mañana:
  1. Consulta los Registros del día en Supabase (tool local `consultar_datos`).
  2. Detecta inconsistencias (cierres huérfanos, aperturas sin cierre,
     solapamientos, faltantes de picking, legajos test, etc.).
  3. Correlaciona cada hallazgo con el evento que lo causó (legajo, ts, tanda).
  4. Manda un resumen curado por Telegram (tool local `enviar_telegram`).

Mismo esqueleto que el workshop (agent/environment/session/events). Lo único
que cambia respecto al SRE agent son: el SYSTEM_PROMPT, las CUSTOM_TOOLS y sus
backends. El loop de eventos (stream_reply/handle_tool) es idéntico.

⚠ Credenciales HOST-SIDE: las tools corren en ESTE proceso (handle_tool), nunca
dentro del sandbox. La `publishable key` de Supabase es la misma anon key que ya
está pública en tu PWA (index.html/sw.js) — no es secreta, pero igual la leemos
de env, no la hardcodeamos.

Uso:
    export ANTHROPIC_API_KEY=sk-ant-...
    export SUPABASE_URL=https://hrxfctzncixxqmpfhskv.supabase.co
    export SUPABASE_SERVICE_KEY=...                    # service role (recomendado; bypassa RLS)
    export TELEGRAM_CHAT_ID=-1002231959863             # grupo o privado del user
    pip install anthropic
    python virgilio_agent.py

Nota de seguridad: usá la SERVICE ROLE key (no la anon). El orquestrador es infra
confiable — la key vive host-side, nunca entra al sandbox — y así el agente puede
leer cualquier vista e insertar en telegram_outbox sin depender de policies anon.
(Verificado: telegram_outbox tiene RLS ON y sin policy 'anon' de insert, así que la
anon key NO alcanza para encolar Telegram.)
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request

import anthropic

client = anthropic.Anthropic()

MODEL = "claude-opus-5"  # bajá a "claude-sonnet-4-5" para menos costo

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://hrxfctzncixxqmpfhskv.supabase.co")
# Service role host-side (recomendado). Fallback a anon solo para lectura de vistas
# ya expuestas; para escribir en telegram_outbox hace falta la service key.
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_ANON_KEY", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "-1002231959863")

SYSTEM_PROMPT = """\
Sos un auditor de datos de Producción Virgilio (depósito). Trabajás sobre
Supabase (PostgREST). Tabla central: `Registros_Produccion_Virgilio`
  - opcion  = código de acción (TP, TAP, PKC, CG, CP, FJ, ...)
  - texto   = código de tanda/pedido
  - ts_cliente = timestamp del evento; ts_inicio NO nulo = evento de CIERRE
  - legajo  = operario. Legajos '0' y '1' (Pruebas) son TEST → EXCLUILOS.

Tu tarea, para el DÍA DE HOY (zona America/Argentina/Buenos_Aires, UTC-3):
1. Traé los eventos del día con `consultar_datos` (filtrá por ts_cliente del día).
   Podés paginar/filtrar por opcion. Excluí legajos 0 y 1.
2. Buscá estas CLASES de inconsistencia y cuantificá cada una:
   - Cierres huérfanos: un cierre (ts_inicio no nulo) sin su apertura previa.
   - Aperturas sin cierre al final del día.
   - Solapamientos: un mismo legajo con dos actividades productivas a la vez.
   - Picking con faltantes (PKC cuyo real < esperado) sin su seguimiento.
   - Duraciones imposibles (cierres con ts_inicio > ts_cliente, o >8h).
   - Cualquier `opcion` desconocida o `texto` vacío donde debería haber tanda.
3. Para CADA inconsistencia real, dame la evidencia concreta: legajo, ts, tanda,
   y qué regla viola. Podés usar bash/python del sandbox para agregaciones.
4. Si hay hallazgos, mandá UN mensaje por Telegram con `enviar_telegram`:
   un resumen corto (cuántas de cada clase) + hasta 10 casos con su evidencia.
   Si NO hay inconsistencias, mandá igual un "✅ Sin inconsistencias hoy".

Sé conciso y NO inventes: cada número debe salir de una consulta que hiciste.
Cerrá tu turno una vez enviado el Telegram.
"""

# ---------------------------------------------------------------------------
# Cliente PostgREST mínimo (host-side, stdlib) — lo usan los backends locales.
# ---------------------------------------------------------------------------
def _sb_request(method, path, params=None, body=None):
    url = SUPABASE_URL.rstrip("/") + "/rest/v1/" + path.lstrip("/")
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, safe="=.,*():")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("apikey", SUPABASE_KEY)
    req.add_header("Authorization", "Bearer " + SUPABASE_KEY)
    if body is not None:
        req.add_header("Content-Type", "application/json")
        req.add_header("Prefer", "return=minimal")
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read().decode() or ""
    return json.loads(raw) if raw.strip() else None


# ---------------------------------------------------------------------------
# Tools LOCALES (client-side). El agente las pide; ESTE proceso las resuelve.
# ---------------------------------------------------------------------------
CUSTOM_TOOLS = [
    {
        "type": "custom",
        "name": "consultar_datos",
        "description": (
            "Consulta SOLO LECTURA sobre una tabla o vista de Supabase (PostgREST). "
            "Ej.: recurso='Registros_Produccion_Virgilio', filtros=['opcion=eq.TP', "
            "'ts_cliente=gte.2024-06-01T00:00:00-03:00']. Sintaxis de filtro PostgREST: "
            "columna=<op>.<valor> con op in (eq,neq,gt,gte,lt,lte,like,ilike,in,not.is)."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "recurso": {"type": "string", "description": "Tabla o vista, ej. 'Registros_Produccion_Virgilio'"},
                "select": {"type": "string", "description": "Columnas, ej. 'legajo,opcion,texto,ts_cliente,ts_inicio' (default '*')"},
                "filtros": {"type": "array", "items": {"type": "string"}, "description": "Filtros PostgREST, ej. ['opcion=eq.PKC']"},
                "orden": {"type": "string", "description": "Orden, ej. 'ts_cliente.asc' (opcional)"},
                "limite": {"type": "integer", "description": "Máx filas (default 1000, tope 5000)"},
            },
            "required": ["recurso"],
        },
    },
    {
        "type": "custom",
        "name": "enviar_telegram",
        "description": (
            "Encola UN mensaje de Telegram (tabla telegram_outbox, se despacha solo). "
            "Usalo UNA vez al final con el resumen de la auditoría. Soporta Markdown."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "texto": {"type": "string", "description": "Cuerpo del mensaje (Markdown)"},
                "dedup": {"type": "string", "description": "Clave de deduplicación (opcional), ej. 'auditor_2024-06-01'"},
            },
            "required": ["texto"],
        },
    },
]


def _backend_consultar_datos(recurso, select="*", filtros=None, orden=None, limite=1000):
    params = {"select": select}
    for f in (filtros or []):
        if "=" in f:
            k, v = f.split("=", 1)
            params[k] = v
    if orden:
        params["order"] = orden
    params["limit"] = str(min(int(limite or 1000), 5000))
    rows = _sb_request("GET", urllib.parse.quote(recurso), params=params)
    return {"recurso": recurso, "filas": len(rows or []), "datos": rows or []}


def _backend_enviar_telegram(texto, dedup=None):
    row = {
        "chat_id": TELEGRAM_CHAT_ID,
        "text": texto,
        "parse_mode": "Markdown",
        "status": "pending",
    }
    if dedup:
        row["dedup_key"] = dedup
    _sb_request("POST", "telegram_outbox", body=row)
    return {"encolado": True, "chat_id": TELEGRAM_CHAT_ID, "chars": len(texto)}


_BACKENDS = {
    "consultar_datos": _backend_consultar_datos,
    "enviar_telegram": _backend_enviar_telegram,
}


# ===========================================================================
# 1) setup_agent
# ===========================================================================
def setup_agent():
    """Crea el agente auditor (una vez). agent_toolset para agregaciones locales
    en el sandbox + las 2 tools de datos/telegram que corre este proceso."""
    return client.beta.agents.create(
        name="Auditor Inconsistencias Virgilio",
        model=MODEL,
        system=SYSTEM_PROMPT,
        tools=[
            {"type": "agent_toolset_20260401"},  # bash/python para agregar/correlacionar
            *CUSTOM_TOOLS,
        ],
    )


# ===========================================================================
# 2) setup_environment
# ===========================================================================
def setup_environment():
    """Sandbox cloud. La red del sandbox no hace falta (los datos entran por la
    tool local), así que la cerramos: solo el orquestrador toca Supabase."""
    return client.beta.environments.create(
        name="virgilio-auditor-sandbox",
        config={"type": "cloud", "networking": {"type": "limited"}},
    )


# ===========================================================================
# 4) start_session  (sin file resource: los datos llegan por consultar_datos)
# ===========================================================================
def start_session(agent, env):
    return client.beta.sessions.create(
        agent={"type": "agent", "id": agent.id, "version": agent.version},
        environment_id=env.id,
        title="Auditoría de inconsistencias — hoy",
    )


# ===========================================================================
# 6) handle_tool  (idéntico patrón que el workshop)
# ===========================================================================
def handle_tool(event):
    name, args = event.name, dict(event.input or {})
    preview = {k: (v if not isinstance(v, str) or len(v) < 60 else v[:57] + "…") for k, v in args.items()}
    print(f"\n    · [local] {name}({preview})", flush=True)
    fn = _BACKENDS.get(name)
    if fn is None:
        return {"type": "user.custom_tool_result", "custom_tool_use_id": event.id,
                "content": [{"type": "text", "text": f"Tool desconocida: {name}"}], "is_error": True}
    try:
        out = fn(**args)
        return {"type": "user.custom_tool_result", "custom_tool_use_id": event.id,
                "content": [{"type": "text", "text": json.dumps(out, ensure_ascii=False)}]}
    except urllib.error.HTTPError as e:  # error de Supabase → se lo pasamos al agente
        detail = e.read().decode(errors="replace")[:500]
        return {"type": "user.custom_tool_result", "custom_tool_use_id": event.id,
                "content": [{"type": "text", "text": f"HTTP {e.code} en {name}: {detail}"}], "is_error": True}
    except Exception as e:  # noqa: BLE001
        return {"type": "user.custom_tool_result", "custom_tool_use_id": event.id,
                "content": [{"type": "text", "text": f"Error en {name}: {e}"}], "is_error": True}


# ===========================================================================
# 5) stream_reply  (loop de eventos, stream-first, idéntico al workshop)
# ===========================================================================
def stream_reply(session_id, user_text=None):
    to_send = None
    if user_text is not None:
        to_send = [{"type": "user.message", "content": [{"type": "text", "text": user_text}]}]
    while True:
        pending = []
        with client.beta.sessions.events.stream(session_id=session_id) as stream:
            if to_send:
                client.beta.sessions.events.send(session_id=session_id, events=to_send)
                to_send = None
            for event in stream:
                t = event.type
                if t == "agent.message":
                    for block in event.content:
                        if block.type == "text":
                            print(block.text, end="", flush=True)
                elif t == "agent.tool_use":
                    print(f"\n    · [sandbox] {event.name}", flush=True)
                elif t == "agent.custom_tool_use":
                    pending.append(event)
                elif t == "session.error":
                    print(f"\n    [session.error] {getattr(event, 'error', None)}", flush=True)
                elif t == "session.status_idle":
                    if event.stop_reason.type == "requires_action":
                        break
                    return
                elif t == "session.status_terminated":
                    return
        if not pending:
            return
        to_send = [handle_tool(ev) for ev in pending]


# ===========================================================================
# 7) delete_session
# ===========================================================================
def delete_session(session_id):
    client.beta.sessions.delete(session_id=session_id)


# ---------------------------------------------------------------------------
# main(): una corrida de auditoría. En prod esto lo dispara un
# scheduled deployment (cron 8:00 AR); acá lo corrés a mano para probar.
# ---------------------------------------------------------------------------
def main():
    if not SUPABASE_KEY:
        raise SystemExit("Falta SUPABASE_SERVICE_KEY en el entorno (service role, host-side).")

    print("· setup_agent()…", flush=True)
    agent = setup_agent()
    print("· setup_environment()…", flush=True)
    env = setup_environment()
    print("· start_session()…", flush=True)
    session = start_session(agent, env)
    print(f"  trace: https://platform.claude.com/workspaces/default/sessions/{session.id}\n")

    print("· auditando (stream_reply)…\n", flush=True)
    stream_reply(session.id, user_text="Audita las inconsistencias de HOY y mandá el resumen por Telegram.")

    print("\n\n· delete_session()…", flush=True)
    delete_session(session.id)
    print("· listo.")


if __name__ == "__main__":
    main()
