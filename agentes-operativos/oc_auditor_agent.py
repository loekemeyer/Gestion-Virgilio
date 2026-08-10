"""
Auditor de Abastecimiento (OCs) — Managed Agent semanal para Producción Virgilio
================================================================================

Reusa la cáscara de virgilio_agent.py (solo lectura + Telegram). Cruza mínimos vs
stock vs pedidos vs recepción/venta y marca artículos ACTIVOS bajo mínimo SIN OC
pendiente, proponiendo las OCs a generar.

Datos (verificados):
  OC_Maximos(cod, descripcion, linea, max_cajas, proveedor, uni_x_caja, activo, indice, ...)
  vista_stock_vs_pedidos(cod, stock_total, terminado, ..., pedidos_ped, nps_ped)
  vista_generador_oc(...)         # la que usa el módulo "Generar OCs"
  vista_recepcion_mensual / vista_venta_mensual   # abastecimiento vs venta
  Ordenes_Compra(...)             # OCs históricas (pedido vs recibido)

Uso (mismas env vars que virgilio_agent.py). python oc_auditor_agent.py
"""

import virgilio_agent as va

client = va.client

OC_PROMPT = """\
Sos el auditor de abastecimiento (compras) de Producción Virgilio. Objetivo semanal:
detectar artículos que hay que REPONER y que NO tienen OC en camino, y proponer las OCs.

Datos (Supabase / PostgREST, solo lectura):
- `OC_Maximos`: config de compras. cod, max_cajas (objetivo), proveedor, uni_x_caja,
  `activo` (bool). Si activo=false el artículo está DISCONTINUADO → ignoralo.
- `vista_stock_vs_pedidos`: cod, stock_total, pedidos_ped (demanda), nps_ped, y los
  saldos por depósito. Faltante ~ pedidos_ped − stock_total.
- `vista_generador_oc`: la vista que el módulo "Generar OCs" usa para sugerir compras
  (traé unas filas con select='*' limite=5 para ver su forma exacta).
- `Ordenes_Compra`: OCs históricas (para ver qué ya está pedido y aún no llegó).
- `vista_recepcion_mensual` / `vista_venta_mensual`: contexto de abastecimiento vs venta.

Procedimiento:
1. Traé `OC_Maximos` activos (filtros=['activo=eq.true']).
2. Traé `vista_stock_vs_pedidos` y `vista_generador_oc` (unas filas primero para ver columnas).
3. Marcá artículos ACTIVOS donde el stock no cubre la demanda / está bajo el mínimo y
   NO haya una OC pendiente reciente en `Ordenes_Compra`. Calculá cuántas cajas pedir
   para llegar a max_cajas (objetivo), redondeando por uni_x_caja / master si aplica.
4. Agrupá por proveedor. Para cada artículo: cod, descripción, stock, demanda, cajas a
   pedir, proveedor.
5. Mandá UN Telegram con `enviar_telegram`: resumen por proveedor + top de artículos a
   reponer (hasta 15). Si nada urgente: "✅ Abastecimiento OK esta semana".

No inventes cifras: cada número sale de una consulta. Cerrá tras enviar el Telegram.
"""


def setup_agent():
    return client.beta.agents.create(
        name="Auditor OCs Virgilio",
        model=va.MODEL,
        system=OC_PROMPT,
        tools=[{"type": "agent_toolset_20260401"}, *va.CUSTOM_TOOLS],  # solo consultar + telegram
    )


def setup_environment():
    return client.beta.environments.create(
        name="virgilio-oc-sandbox",
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
    session = va.start_session(agent, env)
    print(f"  trace: https://platform.claude.com/workspaces/default/sessions/{session.id}\n")
    print("· auditando abastecimiento (stream_reply)…\n", flush=True)
    va.stream_reply(session.id, user_text=(
        "Revisá el abastecimiento: qué artículos activos hay que reponer (bajo mínimo, "
        "sin OC en camino) y proponé las OCs por proveedor. Mandá el resumen por Telegram."
    ))
    print("\n\n· delete_session()…", flush=True)
    va.delete_session(session.id)
    print("· listo.")


if __name__ == "__main__":
    main()
