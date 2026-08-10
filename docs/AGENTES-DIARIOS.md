# Agentes de Producción Virgilio (uso manual)

> **Los loops automáticos fueron eliminados** (2026-08-10) para bajar consumo de
> tokens. Los subagentes siguen definidos en `.claude/agents/` y se invocan a
> mano cuando hace falta.

## Agentes disponibles

Se invocan desde cualquier chat de Claude sobre este repo, por nombre:

- `mejoras-virgilio` — audita el repo y propone backlog de mejoras.
- `revisor-logica` — busca bugs, casos borde, inconsistencias de estado.
- `auditor-consistencia` — CSS/JS muerto, patrones repetidos, funciones sin uso.
- `auditor-supabase` — RLS, advisors, permisos anon.
- `guardian-stock` — invariantes del stock event-sourced.
- `guardian-tests` — corre y mantiene los smoke-tests.
- `revisor-render` — audita estética/layout headless (móvil ≤460px + monitor).
- `keeper-guia` — mantiene `GUIA-PROYECTO.md` al día.
- `curador-telegram` — cuando hay ideas acumuladas, arma la lista definitiva y
  la manda por Telegram al privado (bot `@Faltantes_Virgilio_bot`).

## Flujo cuando se invoca un agente

- Cada idea nueva → fila en `agente_propuestas` (`estado='pendiente'`).
- Si se implementa y verifica (`node --check` + smoke headless), queda
  `estado='lista'` con rama **`idea/<código>`**. **Nunca** se toca `main`.
- El usuario confirma en el chat (número de 4 díg o checklist con `:`) y ahí se
  mergea a `main` directo.

## Tabla `agente_propuestas` (Supabase `hrxfctzncixxqmpfhskv`)
`codigo` (4 díg, PK) · `agente` · `titulo` · `detalle` · `impacto` · `esfuerzo` ·
`ubicacion` · `estado` (`pendiente`|`lista`|`aprobada`|`hecha`|`descartada`) ·
`rama` · `creado_en` · `desarrollada_en` · `enviado_en` · `curador_nota`.
RLS activa, sin acceso anon. Código libre: `select public.nuevo_codigo_propuesta();`

## Telegram (si se invoca `curador-telegram`)
Reusa el bot `@Faltantes_Virgilio_bot` (token en Vault), manda al **privado**:
`select public.tg_enqueue('<msg>','<dedup>','<CHAT_ID_PRIVADO>','HTML');`
`select public.tg_outbox_flush();`

## Histórico (loops eliminados)

Hasta el 2026-08-10 corrían dos Routines automáticas:
- `30 */2 * * *` → todos los agentes proponen + desarrollan hasta 5 ideas por
  corrida.
- `0 11 * * *` (08:00 AR) → curador manda lista definitiva por Telegram.

Se eliminaron porque disparaban ~96 auditorías/día del repo grande con Opus, lo
que llevó el consumo semanal del ~60% al ~99%. Si en algún momento se quisieran
volver a activar, están documentadas en el git log.
