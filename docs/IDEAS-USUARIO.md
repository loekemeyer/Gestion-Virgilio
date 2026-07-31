# Ideas del usuario — Producción Virgilio

Proyección en el repo de las ideas que **escribe el usuario** en cualquier chat.
Cada idea queda acá (durable, versionada) y además en la tabla `agente_propuestas`
(Supabase) para entrar al mismo circuito que las de los agentes: se desarrolla sola
en su rama `idea/<código>`, se recuerda en el Telegram de las 8 **todos los días
hasta que el usuario la active**, y se mergea a `main` cuando el usuario dice el número.

- `[ ]` = pendiente / esperando activación · `[x]` = activada (mergeada a main) ·
  `~~tachada~~` = descartada.
- El código de 4 dígitos es el mismo que en la tabla y en el Telegram.

> Este archivo es un espejo legible. La fuente operativa es la tabla
> `agente_propuestas`. Al registrar o activar una idea del usuario se actualizan
> los dos. No borres entradas: se tildan o se tachan.

## Ideas

- [ ] **1108** (2026-07-31) — Que las columnas de depósito (A facturar / A guardar / etc.) se puedan **abrir aunque digan 0**, si el artículo tuvo movimientos ahí alguna vez — _lista en `claude/mercaderia-estancada-definition-wxis06` (falta mergear a main)_
- [ ] **3989** (2026-07-31) — Un **`+`** en cada recepción del pop-up que muestre la **entrega completa**: día que llegó, de qué prov/tall, qué códigos entregó y cuántas cajas de cada uno — _lista en `claude/mercaderia-estancada-definition-wxis06` (falta mergear a main)_
- [ ] **2415** (2026-07-31) — En el pop-up de movimientos por artículo (📦 A guardar) mostrar las **siglas y el legajo de quien recibió** — _lista en `claude/mercaderia-estancada-definition-wxis06` (falta mergear a main)_
- [ ] **1730** (2026-07-31) — Redefinir **ESTANCADO**: es cuando de lo que llegó se guardó una **parte** (entre góndola y excedente) pero **no la totalidad** (llegan 14, guardan 10, quedan 4 → eso es estancado). Una recepción nueva intacta **no** es estancado (caso cod 824) — _lista en `claude/mercaderia-estancada-definition-wxis06` (backend ya aplicado en Supabase)_

<!-- Nuevas entradas se agregan ARRIBA de esta línea, formato:
- [ ] **CÓDIGO** (AAAA-MM-DD) — texto de la idea — _estado_
-->
