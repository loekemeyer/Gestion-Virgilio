"""
Forense de Stock Negativo — Managed Agent operativo para Producción Virgilio
============================================================================

Gemelo del SRE agent del workshop, pero sobre TUS datos:
  síntoma (un depósito quedó en negativo)  ->  causa raíz (el MOVIMIENTO culpable).

Reusa la MISMA cáscara que virgilio_agent.py: cliente, tools locales
(consultar_datos / enviar_telegram), handle_tool, stream_reply, environment,
session, delete. Lo ÚNICO propio es el system prompt y el setup_agent.

Datos (verificados):
  vista_saldos_stock(cod_art, descripcion, terminado, excedente, separar_pedidos,
                     a_facturar, a_guardar, racks, insumos, para_envasar, racks_ch)
  Movimientos_Stock(id, ts, cod_art, descripcion, deposito, delta, tipo, ref,
                    legajo, creado, ubicacion, unidad, client_id)   (~25k filas)

Uso (mismas env vars que virgilio_agent.py):
    export ANTHROPIC_API_KEY=...  SUPABASE_URL=...  SUPABASE_SERVICE_KEY=...  TELEGRAM_CHAT_ID=...
    python stock_negativo_agent.py
"""

import virgilio_agent as va  # reusa client, CUSTOM_TOOLS, handle_tool, stream_reply, etc.

client = va.client

FORENSE_PROMPT = """\
Sos un forense de stock de Producción Virgilio. Un depósito quedó en NEGATIVO
(imposible físicamente) y hay que encontrar el MOVIMIENTO exacto que lo causó.

Modelo de datos (Supabase / PostgREST, tools locales):
- `vista_saldos_stock`: 1 fila por artículo con el saldo por depósito. Columnas de
  depósito: terminado (góndola), excedente, separar_pedidos, a_facturar, a_guardar,
  racks, racks_ch, insumos, para_envasar.
- `Movimientos_Stock`: el log event-sourced. Columnas: ts, cod_art, deposito, delta
  (+ suma / − resta), tipo, ref (tanda/pedido), legajo, ubicacion. El saldo de un
  depósito = suma de `delta` de sus movimientos, ordenados por ts.

Procedimiento:
1. Detectá los negativos: consultá `vista_saldos_stock` una vez por columna de
   depósito con filtro `<col>=lt.0` (ej. filtros=['terminado=lt.0']). Juntá todos
   los (cod_art, deposito, saldo) que dan < 0. Si no hay ninguno, avisá y terminá.
2. Para CADA sospechoso, traé sus movimientos:
   consultar_datos('Movimientos_Stock',
                   select='ts,deposito,delta,tipo,ref,legajo,ubicacion',
                   filtros=['cod_art=eq.<COD>'], orden='ts.asc', limite=5000).
   Usá bash/python del sandbox para computar el saldo ACUMULADO por depósito y
   encontrar el PRIMER movimiento en el que ese depósito cruza por debajo de 0.
3. Ese movimiento es el culpable. Reportá: cod_art, deposito, ts, delta, tipo, ref
   (tanda/pedido), legajo, y el saldo antes/después del cruce. Explicá en una frase
   la causa probable (ej. "se descontó picking sin haber cargado el inicial").
4. Mandá UN Telegram con `enviar_telegram`: resumen (cuántos negativos) + hasta 10
   culpables con su evidencia. Si no hay negativos: "✅ Sin stock negativo".

No inventes números: cada saldo debe salir de los movimientos que trajiste.
Cerrá tu turno una vez enviado el Telegram.
"""


def setup_agent():
    """Crea el agente forense (una vez). Mismas 2 tools + el sandbox para agregar
    los ~miles de movimientos por artículo y calcular el saldo acumulado."""
    return client.beta.agents.create(
        name="Forense Stock Negativo Virgilio",
        model=va.MODEL,
        system=FORENSE_PROMPT,
        tools=[{"type": "agent_toolset_20260401"}, *va.CUSTOM_TOOLS],
    )


def setup_environment():
    """Sandbox propio (los environments son reusables entre agentes, pero le damos
    nombre distinto para no chocar con el del auditor). En prod: crealo una vez."""
    return client.beta.environments.create(
        name="virgilio-forense-sandbox",
        config={"type": "cloud", "networking": {"type": "limited"}},
    )


def main():
    if not va.SUPABASE_KEY:
        raise SystemExit("Falta SUPABASE_SERVICE_KEY en el entorno (service role, host-side).")

    print("· setup_agent()…", flush=True)
    agent = setup_agent()
    print("· setup_environment()…", flush=True)
    env = setup_environment()
    print("· start_session()…", flush=True)
    session = va.start_session(agent, env)      # reusa la de virgilio_agent (sin resources)
    print(f"  trace: https://platform.claude.com/workspaces/default/sessions/{session.id}\n")

    print("· investigando (stream_reply)…\n", flush=True)
    va.stream_reply(session.id, user_text=(
        "Encontrá qué depósitos quedaron en negativo y, para cada uno, el movimiento "
        "exacto que lo causó. Mandá el resumen por Telegram."
    ))

    print("\n\n· delete_session()…", flush=True)
    va.delete_session(session.id)
    print("· listo.")


if __name__ == "__main__":
    main()
