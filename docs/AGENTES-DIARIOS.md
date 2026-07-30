# Agentes diarios de Producción Virgilio

Loop autónomo de **propuestas** (no implementa solo) en dos etapas: los agentes
tiran ideas cada 2 h y un curador decide qué te llega. Todos los días a las
**8:00 AR** te llega **una sola lista definitiva** por Telegram con códigos de 4
dígitos. Vos elegís qué código encarar pasándoselo a cualquier chat de Claude.

## Las piezas

1. **Agentes de ideas** (`.claude/agents/`, corren **cada 2 h**, solo proponen):
   - `mejoras-virgilio` → mejoras y funcionalidades nuevas.
   - `revisor-logica` → bugs, casos borde, inconsistencias de lógica.
   Guardan cada idea nueva en `agente_propuestas` como `pendiente` / `enviado_en=null`.

2. **Curador** (`curador-telegram`, corre **8:00 AR**, solo decide): parado sobre el
   repo y sobre todo la **`GUIA-PROYECTO.md`** (lo que pediste), revisa TODO lo
   acumulado sin enviar, descarta ruido/duplicados/lo que contradice la guía, y arma
   **la lista definitiva** del día. Es el filtro entre el ruido y tu atención.

3. **Tabla `agente_propuestas`** (Supabase `hrxfctzncixxqmpfhskv`): `codigo` (4
   dígitos, PK), `agente` (`mejoras`|`logica`), `titulo`, `detalle`, `impacto`,
   `esfuerzo`, `ubicacion`, `estado` (`pendiente`|`aprobada`|`hecha`|`descartada`),
   `creado_en`, `enviado_en`, `curador_nota`. RLS activa, sin acceso anon.
   Código libre: `select public.nuevo_codigo_propuesta();`

4. **Telegram**: reusa el bot `@Faltantes_Virgilio_bot` (token en Vault), manda al
   **privado** del usuario. Envío:
   `select public.tg_enqueue('<msg>', '<dedup>', '<CHAT_ID_PRIVADO>', 'HTML');`
   `select public.tg_outbox_flush();`

5. **Dos tareas programadas (Routines)**:
   - `0 */2 * * *` (cada 2 h) → sesión que corre los 2 agentes de ideas. Sin Telegram.
   - `0 11 * * *` (08:00 AR) → sesión que corre el curador y manda la lista definitiva.

## Flujo

- **Cada 2 h**: sesión nueva → corre `mejoras-virgilio` y `revisor-logica` →
  inserta ideas nuevas (dedup contra lo ya pendiente). No molesta al usuario.
- **8:00 AR**: sesión nueva → corre `curador-telegram` sobre lo `pendiente` y
  `enviado_en is null` → descarta lo que no vale (`estado='descartada'` +
  `curador_nota`), arma la lista definitiva, la manda por Telegram y marca las
  enviadas con `enviado_en=now()`.

## Cómo lo usás vos

- Te llega el Telegram a las 8, ej:
  `🤖 Virgilio — lista del día (3)`
  `4837 [mejoras·alto] Confirmación de tanda con doble-tap`
  `2915 [logica·alto] Cierre TAP queda abierto si se pierde señal`
  `6203 [mejoras·medio] Filtro por zona en el monitor`
- Abrís cualquier chat de Claude sobre este repo y escribís **`hacé el 4837`**.
  Claude lee la fila `4837`, ya sabe de qué hablás, y la implementa.
- Los cambios van **a `main` solo con tu aprobación**. Al terminar → `estado='hecha'`.

## Mantenimiento

- Cambiar cadencia: editar el cron de la Routine correspondiente.
- Pausar: deshabilitar la/s Routine/s.
- Cambiar el chat destino: actualizar `CHAT_ID_PRIVADO` en el prompt de la Routine
  de las 8:00 (el `chat_id` no es secreto; el token vive en el Vault).
