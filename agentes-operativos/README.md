# Agentes Operativos — Producción Virgilio (Claude Managed Agents)

Suite de agentes que vigilan **la operación** (los datos de Supabase), a diferencia
del loop de `agente_propuestas` que vigila **el código**. Todos comparten la misma
cáscara (`virgilio_agent.py`): mismo cliente, mismas tools locales y el mismo loop de
eventos. Cada agente cambia solo su `SYSTEM_PROMPT` (y a veces suma una tool de escritura).

## Los agentes

| Archivo | Qué hace | Cadencia sugerida | Escribe |
|---|---|---|---|
| `virgilio_agent.py` | **Auditor de inconsistencias**: cierres huérfanos, aperturas sin cierre, solapamientos, PKC con faltantes, duraciones imposibles. | diaria 8:00 AR | no (solo Telegram) |
| `stock_negativo_agent.py` | **Forense de stock negativo**: síntoma (depósito < 0) → movimiento culpable, con evidencia (ts, ref, delta, legajo). | diaria / por webhook | no |
| `faltantes_agent.py` | **"¿Qué completar hoy?"**: prioriza faltantes con stock disponible (góndola/a guardar/excedente/racks), igual que v8.66. | 2–3 veces/día | opcional (`crear_tarea_faltante`, apagado por defecto) |
| `oc_auditor_agent.py` | **Auditor de abastecimiento**: artículos activos bajo mínimo sin OC en camino → propone OCs por proveedor. | semanal (lunes) | no |

## Cómo funciona (arquitectura común)

```
Agent (system+tools)  ── una vez, versionado
Environment (sandbox cloud, red limitada)  ── reusable
Session = Agent × Environment  ── una por corrida
Events (SSE):  agent.message / agent.custom_tool_use  ↔  user.message / user.custom_tool_result
```

- **Tools locales** (corren en TU proceso, `handle_tool`, nunca en el sandbox):
  - `consultar_datos(recurso, select, filtros, orden, limite)` → PostgREST GET (solo lectura).
  - `enviar_telegram(texto, dedup)` → insert en `telegram_outbox` (se despacha solo).
  - `crear_tarea_faltante(...)` → RPC `faltante_tarea_crear` (solo en el agente de faltantes).
- El **sandbox** (`agent_toolset_20260401`: bash/python) lo usa el agente para agregar
  miles de filas y correlacionar (ej. calcular el saldo acumulado de stock).

## Configuración

```sh
export ANTHROPIC_API_KEY=sk-ant-...
export SUPABASE_URL=https://hrxfctzncixxqmpfhskv.supabase.co
export SUPABASE_SERVICE_KEY=...          # service role, HOST-SIDE (recomendado)
export TELEGRAM_CHAT_ID=-1002231959863   # grupo o privado del user
pip install anthropic
```

> **Seguridad:** usá la *service role* key, no la anon. El orquestrador es infra
> confiable: la key vive host-side, **nunca entra al sandbox**, y bypassa RLS (así el
> agente lee cualquier vista e inserta en `telegram_outbox`, que tiene RLS sin policy anon).

## Correr a mano (probar)

```sh
python virgilio_agent.py        # auditor de inconsistencias
python stock_negativo_agent.py  # forense de stock negativo
python faltantes_agent.py       # qué completar hoy (solo propone)
python oc_auditor_agent.py      # auditor de OCs
```

Cada uno imprime una `trace URL` de la Consola para ver la investigación en vivo.

## Deployar en cron (scheduled deployments)

Se corre UNA vez por agente; después Anthropic dispara la sesión solo.

```python
import virgilio_agent as va          # (o el módulo del agente que quieras)

agent = va.setup_agent()             # o reusá un agent.id ya guardado
env   = va.setup_environment()

dep = va.client.beta.deployments.create(
    name="Auditor inconsistencias — 8:00 AR",
    agent={"type": "agent", "id": agent.id, "version": agent.version},
    environment_id=env.id,
    initial_events=[{"type": "user.message",
                     "content": [{"type": "text",
                                  "text": "Audita las inconsistencias de HOY y mandá el resumen por Telegram."}]}],
    schedule={"type": "cron", "expression": "0 8 * * *",
              "timezone": "America/Argentina/Buenos_Aires"},
)
print(dep.id, dep.schedule.upcoming_runs_at)
# Probar ya: va.client.beta.deployments.run(dep.id)
```

Cadencias sugeridas por agente:
- inconsistencias: `0 8 * * *`
- stock negativo: `0 8,14 * * *` (o por webhook cuando dispara el trigger de negativo)
- faltantes: `0 9,13,16 * * *`
- OCs: `0 8 * * 1` (lunes)

## Notas

- Los `Environment` son **reusables entre agentes** — en prod creá uno y referencialo
  por id en todos; acá cada archivo crea el suyo con nombre distinto para no chocar (409).
- El agente de faltantes trae la tool `crear_tarea_faltante` pero **por defecto solo
  propone** — solo crea tareas reales si el mensaje de arranque lo autoriza.
- Nada de esto se deployó ni mandó Telegrams reales todavía: el código está listo para
  que lo corras vos con tus keys.
