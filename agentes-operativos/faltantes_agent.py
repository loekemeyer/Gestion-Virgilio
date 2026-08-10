"""
Triage de Faltantes — "¿Qué completar hoy?" — Managed Agent para Producción Virgilio
====================================================================================

Reusa la cáscara de virgilio_agent.py y agrega UNA tool de escritura opcional
(`crear_tarea_faltante`). Por defecto solo PROPONE por Telegram; crea tareas reales
únicamente si el mensaje de arranque lo pide explícitamente.

Lógica (misma que v8.66 del panel "Completar Pedido — faltante que llegó"):
  faltante = Entregas_Virgilio.cajas_falto>0 y NP NO facturada (no está en Facturacion_NP),
  y solo cuenta si hay stock para completarlo:
      disponible = terminado (góndola) + a_guardar + excedente + racks  > 0   (vista_saldos_stock)
  (separar_pedidos y a_facturar NO cuentan: ya están comprometidos.)

Datos (verificados):
  Entregas_Virgilio(id, fecha_salida, cod_cliente, np, cod_art, cajas_pedidas,
                    cajas_entregadas, cajas_falto, tanda, creado)
  Facturacion_NP(np, ...)   ·   vista_saldos_stock(cod_art, terminado, a_guardar, excedente, racks, ...)
  RPC faltante_tarea_crear(p_np, p_cod_cliente, p_razon_social, p_tanda, p_articulos jsonb, p_cajas, p_creado_por)

Uso (mismas env vars que virgilio_agent.py). python faltantes_agent.py
"""

import virgilio_agent as va

client = va.client

# --- tool de escritura opcional: crea una tarea de faltante (pop-up a operarios) ---
CREAR_TAREA_TOOL = {
    "type": "custom",
    "name": "crear_tarea_faltante",
    "description": (
        "Crea una tarea de 'Completar Pedido' para una NP (les salta el pop-up a los "
        "celulares de Virgilio). Usalo SOLO si el pedido del usuario lo autoriza; si no, "
        "limitate a proponer por Telegram. p_articulos es una lista [{cod, falto}]."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "np": {"type": "string"},
            "cod_cliente": {"type": "string"},
            "razon_social": {"type": "string"},
            "tanda": {"type": "string"},
            "articulos": {"type": "array", "items": {
                "type": "object",
                "properties": {"cod": {"type": "string"}, "falto": {"type": "number"}},
                "required": ["cod", "falto"],
            }},
            "cajas": {"type": "integer"},
        },
        "required": ["np", "articulos", "cajas"],
    },
}


def _backend_crear_tarea_faltante(np, articulos, cajas, cod_cliente="", razon_social="", tanda=""):
    va._sb_request("POST", "rpc/faltante_tarea_crear", body={
        "p_np": np, "p_cod_cliente": cod_cliente, "p_razon_social": razon_social,
        "p_tanda": tanda, "p_articulos": articulos, "p_cajas": int(cajas or 0),
        "p_creado_por": "0",
    })
    return {"tarea_creada": True, "np": np, "cajas": cajas}


# registramos el backend en la cáscara compartida (handle_tool lo busca en va._BACKENDS)
va._BACKENDS["crear_tarea_faltante"] = _backend_crear_tarea_faltante

TOOLS = [*va.CUSTOM_TOOLS, CREAR_TAREA_TOOL]

TRIAGE_PROMPT = """\
Sos el asistente de "¿Qué completar hoy?" de Producción Virgilio. Tu objetivo:
priorizar qué pedidos con faltante SE PUEDEN completar ahora (porque llegó stock).

Datos (Supabase / PostgREST, tools locales):
- `Entregas_Virgilio`: faltantes por NP. Un faltante real = cajas_falto>0.
  Columnas: fecha_salida, cod_cliente, np, cod_art, cajas_falto, tanda.
- `Facturacion_NP`: NPs ya facturadas → EXCLUILAS (esas no se completan).
- `vista_saldos_stock`: saldo por artículo. Disponible para completar =
  terminado + a_guardar + excedente + racks. (separar_pedidos y a_facturar NO cuentan.)

Procedimiento:
1. Traé faltantes: consultar_datos('Entregas_Virgilio',
      select='np,cod_cliente,cod_art,cajas_falto,tanda,fecha_salida',
      filtros=['cajas_falto=gt.0'], orden='fecha_salida.asc', limite=5000).
2. Traé las NPs facturadas: consultar_datos('Facturacion_NP', select='np') y excluílas.
3. Para los cod_art que aparecen, traé sus saldos: consultar_datos('vista_saldos_stock',
      select='cod_art,terminado,a_guardar,excedente,racks',
      filtros=['cod_art=in.(<lista>)']). OJO: algunos códigos terminan en 'E' (importados);
      si no matchea exacto, probá la BASE del código (sin la 'E' final).
4. Un faltante es COMPLETABLE si disponible>0. Armá la lista, priorizada por fecha_salida
   (lo que sale antes primero). Para cada NP: artículos, cajas que faltan, y de dónde
   sale el stock (góndola/a guardar/excedente/racks).
5. Mandá UN Telegram con `enviar_telegram`: top de NPs completables (hasta 12) con su
   detalle. Si el usuario NO pidió crear tareas, NO uses crear_tarea_faltante: solo proponé.

No inventes: cada "disponible" sale de vista_saldos_stock. Cerrá tras enviar el Telegram.
"""


def setup_agent():
    return client.beta.agents.create(
        name="Triage Faltantes Virgilio",
        model=va.MODEL,
        system=TRIAGE_PROMPT,
        tools=[{"type": "agent_toolset_20260401"}, *TOOLS],
    )


def setup_environment():
    return client.beta.environments.create(
        name="virgilio-faltantes-sandbox",
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
    print("· triaje (stream_reply)…\n", flush=True)
    va.stream_reply(session.id, user_text=(
        "Decime qué pedidos con faltante se pueden COMPLETAR hoy (hay stock) y mandá "
        "el resumen priorizado por Telegram. No crees tareas, solo proponé."
    ))
    print("\n\n· delete_session()…", flush=True)
    va.delete_session(session.id)
    print("· listo.")


if __name__ == "__main__":
    main()
