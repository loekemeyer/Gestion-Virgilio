# Agentes diarios de Producción Virgilio

Loop autónomo de **propuestas** (no implementa solo). Todos los días ~8:00 AR una
sesión nueva de Claude corre dos agentes auditores y te manda **un** resumen por
Telegram con códigos de 4 dígitos. Vos elegís qué código encarar pasándoselo a
cualquier chat de Claude.

## Las piezas

1. **Agentes** (`.claude/agents/`, solo proponen, no editan):
   - `mejoras-virgilio` → mejoras y funcionalidades nuevas.
   - `revisor-logica` → bugs, casos borde, inconsistencias de lógica.

2. **Tabla `agente_propuestas`** (Supabase `hrxfctzncixxqmpfhskv`): backlog con
   `codigo` (4 dígitos, PK), `agente` (`mejoras`|`logica`), `titulo`, `detalle`,
   `impacto`, `esfuerzo`, `ubicacion`, `estado`
   (`pendiente`|`aprobada`|`hecha`|`descartada`), `creado_en`. RLS activa, sin
   acceso anon (es interna). Código libre: `select public.nuevo_codigo_propuesta();`

3. **Telegram**: reusa el bot `@Faltantes_Virgilio_bot` (token en Supabase Vault)
   pero manda al **privado** del usuario (chat distinto al grupo Faltantes). Envío:
   `select public.tg_enqueue('<msg>', '<dedup>', '<CHAT_ID_PRIVADO>', 'HTML');`
   seguido de `select public.tg_outbox_flush();`

4. **Tarea programada** (Routine, cron diario ~11:00 UTC = 8:00 AR): dispara la
   sesión que orquesta todo (ver prompt abajo).

## Flujo diario

1. La Routine abre una sesión nueva en el repo (rama `main`, solo lectura para auditar).
2. Corre `mejoras-virgilio` y `revisor-logica`.
3. Por cada ítem nuevo (que no exista ya en `agente_propuestas`): pide un código con
   `nuevo_codigo_propuesta()` e inserta la fila con `estado='pendiente'`.
4. Arma un mensaje corto y lo manda por Telegram con `tg_enqueue` + `tg_outbox_flush`.
5. **No toca código.** Solo propone.

## Cómo lo usás vos

- Te llega el Telegram, ej:
  `🤖 Virgilio — 3 propuestas nuevas`
  `4837 [mejoras·alto] Confirmación de tanda con doble-tap`
  `2915 [logica·alto] Cierre TAP queda abierto si se pierde señal`
  `6203 [mejoras·medio] Filtro por zona en el monitor`
- Abrís cualquier chat de Claude sobre este repo y escribís **`hacé el 4837`**.
  Claude lee la fila `4837`, ya sabe de qué funcionalidad hablás, y la implementa.
- Los cambios van **a `main` solo con tu aprobación**. Al terminar, la propuesta
  queda `estado='hecha'`.

## Mantenimiento

- Cambiar horario/frecuencia: editar la Routine (cron).
- Pausar: deshabilitar la Routine.
- Cambiar el chat de destino: actualizar el `CHAT_ID_PRIVADO` en el prompt de la
  Routine (el `chat_id` no es secreto; el token sí, y vive en el Vault).
