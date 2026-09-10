# Agentes de GP2 — archivo, no configuración activa

Estos 5 agentes vivían en `.claude/agents/` del repo `Gestion-Productiva-2.0`. Se guardan acá,
**fuera de `.claude/`**, cuando ese admin se copió dentro de Gestión Virgilio (2026-09-10): así
se conserva el trabajo si aquel repo se apaga, sin que una sesión de ESTE repo los cargue
automáticamente como agentes propios.

| Agente | Para qué |
|---|---|
| `gp2-experto` | Contraparte de negocio: discute si una idea cierra, qué rompe, qué contradice. |
| `gp2-cirujano` | Ejecuta un cambio de producto/proceso en la base por toda la cadena normalizada. |
| `gp2-cargador-excel` | Mete planillas del usuario a la base con el protocolo de carga (nada inventado). |
| `gp2-auditor-costos` | Audita el motor de costos y la valorización, en solo lectura. |
| `gp2-verificador-ui` | Gate de UI antes de pushear: suite Playwright + reglas de pantalla. |

Leen `claude-admin--Gestion-Productiva-2.0.md` y `CONOCIMIENTO_GP2.md` (los dos acá al lado)
para saber del negocio: el conocimiento está en esos archivos, no adentro del agente.

**Para volver a usarlos**, hay que copiarlos a `.claude/agents/` de un repo — decisión
deliberada, no algo que pase solo.
