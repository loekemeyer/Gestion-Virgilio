# Plan Integración ERP ISIS — Idea 5547

**Ticket ISIS:** 1159666  
**Reunión:** agosto 2026 con Horacio Barbieri (Sistemas ISIS)  
**Plazo:** 3 semanas desde 16/8/2026  
**Estado:** pendiente — nada ejecutado  
**Artefacto de análisis:** https://claude.ai/code/artifact/3d7b6485-b065-4e3f-9388-eebdf49317a2

> **Contexto clave:** el informe de agosto 2026 SUPERSEDE el approach anterior
> (API `/api/ISISPedido` + Balcony). Todo pasa ahora por **JSON file exchange**.
> `docs/integracion-isis.md` hay que actualizarlo.

---

## Los 5 circuitos (del informe ISIS)

| # | Circuito | Prioridad |
|---|---|---|
| P1 | Facturación automática (stock_ok → factura) | Alta |
| P2 | Enviar JSON manual para faltantes (botón supervisor) | Alta |
| P3 | NP de ISIS → Virgilio | Media |
| P4 | Recepción → ISIS (remitos de compra) | Media |
| P5 | Completado automático | Baja |

---

## Piezas a construir — prompts para cada una

### PIEZA 1: RPC `generar_json_pedido(p_np bigint)`
**Repo:** Produccion-Virgilio (Supabase `hrxfctzncixxqmpfhskv`)  
**Tipo:** Backend (RPC nueva)

```
PROMPT COMPLETO:
---
Crear la RPC `generar_json_pedido(p_np bigint)` en Supabase (proyecto hrxfctzncixxqmpfhskv).

Debe devolver un JSON con la estructura acordada con ISIS (Ticket 1159666):

{
  "np": 98180,
  "razon_social": "CLIENTE S.A.",
  "tanda": "D29A",
  "fecha_entrega": "2026-08-15",
  "m3": 12.5,
  "empresa": "LK",           -- o "CH"
  "estado_picking": "completo",  -- "completo"|"parcial"|"sin_iniciar"
  "stock_ok": true,           -- true si TODO el pedido tiene stock cubierto
  "faltantes": [],            -- array de {articulo, cajas_falta}
  "items": [
    {
      "articulo": "438",
      "descripcion": "...",
      "cajas": 10,
      "stock_total": 25,
      "terminado": 10,
      "falta_global": 0,      -- lo que falta sumando TODOS los pedidos pendientes
      "ok": true
    }
  ]
}

Fuentes de datos:
- PPP_Programacion_Diaria: np, cod (artículo), cajas, tanda, fecha_entrega
- PPP_Entregados_Meta: np, m3, rs (razón social)
- Movimientos_Stock / vista_saldos_stock: stock terminado por artículo
- ppp_etapa_tanda o Registros_Produccion_Virgilio: estado del picking
- Para empresa: NP 9xxxx = LK, 4xxxx = CH

Para `falta_global`: cruzar stock disponible (terminado - ya asignado a otros
pedidos con prioridad por fecha_entrega) contra lo que pide cada pedido pendiente.
Es la pieza más compleja — puede ser una vista auxiliar `vista_falta_global`.

`stock_ok` = true cuando TODOS los items tienen ok=true (stock >= cajas).

SECURITY DEFINER, revocar EXECUTE a anon (solo se llama desde supervisor o
agente-local con service_role).

Archivo SQL: sql/integracion_isis.sql (nuevo).
Seguir protocolo de backups si se tocan tablas existentes.
Preguntar backend vs frontend ANTES de implementar (en este caso es backend, pero confirmar).
---
```

### PIEZA 2: Vista `vista_falta_global`
**Repo:** Produccion-Virgilio (Supabase `hrxfctzncixxqmpfhskv`)  
**Tipo:** Backend (vista nueva)

```
PROMPT COMPLETO:
---
Crear vista `vista_falta_global` en Supabase (proyecto hrxfctzncixxqmpfhskv).

Objetivo: para cada artículo, cuánto falta globalmente considerando TODOS los
pedidos pendientes (no facturados) contra el stock disponible.

Columnas:
- cod (artículo)
- stock_terminado (de vista_saldos_stock.terminado)
- total_pedido (suma de cajas de todos los pedidos pendientes en PPP_Programacion_Diaria
  que NO estén en PPP_Pedidos_Entregados/ppp_facturacion)
- falta_global = GREATEST(0, total_pedido - stock_terminado)

"Pendiente" = está en PPP_Programacion_Diaria y NO en ppp_facturacion (misma
lógica que usa el dashboard de LK: PPP menos facturadas).

OJO: el stock es event-sourced (Movimientos_Stock). Usar la vista existente
vista_saldos_stock que ya lo resuelve — no recalcular.

No tocar tablas existentes. Vista de solo lectura.
Archivo SQL: sql/integracion_isis.sql (mismo archivo que la RPC).
---
```

### PIEZA 3: Derivar `stock_ok` por NP + dos disparadores de facturación
**Repo:** Produccion-Virgilio (Supabase `hrxfctzncixxqmpfhskv`)  
**Tipo:** Backend (incluido en la RPC `generar_json_pedido`)

```
PROMPT COMPLETO:
---
Dentro de `generar_json_pedido`, derivar `stock_ok`:

stock_ok = true CUANDO para CADA item del pedido:
  vista_saldos_stock.terminado(cod) >= PPP_Programacion_Diaria.cajas(np, cod)

Es un ALL() sobre los items. Si alguno tiene stock < cajas → stock_ok = false
y ese item va al array `faltantes[]` con { articulo, cajas_falta }.

`falta_global` es dato informativo (stock vs TODOS los pedidos pendientes), NO
decide si se factura.

DOS DISPARADORES de facturación (definidos por el usuario 2026-08-25):

1. AUTOMÁTICO — cuando el operario termina de armar el pedido (picking completo)
   y stock_ok = true (cero faltantes) → generar JSON + enviar a ISIS automático.
   Trigger: el evento de picking completo en Registros_Produccion_Virgilio.

2. MANUAL — botón de la operadora administrativa en el módulo de facturación.
   Al hacer clic en un pedido con faltantes: genera JSON con SOLO lo que hay
   (los items con stock). Los faltantes NO se incluyen en la factura — se
   pierden (el cliente tendría que hacer otro pedido). Es factura PARCIAL.

NO persistir stock_ok — se calcula en vivo cada vez que se genera el JSON.
---
```

### PIEZA 4: Botón de facturación manual (operadora administrativa)
**Repo:** Produccion-Virgilio (index.html)  
**Tipo:** Frontend

```
PROMPT COMPLETO:
---
Módulo de facturación para la operadora administrativa en Produccion-Virgilio.

Flujo (definido por el usuario 2026-08-25):
1. La operadora ve los pedidos pendientes que tienen faltantes (stock_ok=false).
2. Para cada pedido, ve los artículos con stock y los faltantes.
3. Al hacer clic/tilde en un pedido: genera JSON con SOLO los items que tienen
   stock (factura parcial). Los faltantes quedan afuera — no se entregan más.
4. El JSON se guarda en `isis_json_pendientes` (tipo='pedido_parcial') y se
   envía a ISIS.
5. Feedback visual: "Factura enviada — X artículos de Y (Z faltantes descartados)"

NOTA: los pedidos completos (cero faltantes) se envían AUTOMÁTICAMENTE cuando
el picking termina — no pasan por este botón. Este módulo es solo para cerrar
pedidos con faltantes.

Estilo: seguir el patrón visual del panel supervisor existente.
Preguntar al usuario si quiere este módulo en la sección existente o en una nueva.
---
```

### PIEZA 5: Tabla staging `isis_json_pendientes`
**Repo:** Produccion-Virgilio (Supabase `hrxfctzncixxqmpfhskv`)  
**Tipo:** Backend (tabla nueva + RPC)

```
PROMPT COMPLETO:
---
Crear tabla `isis_json_pendientes` en Supabase (proyecto hrxfctzncixxqmpfhskv):

CREATE TABLE isis_json_pendientes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tipo text NOT NULL,          -- 'pedido_completo' | 'faltantes' | 'recepcion'
  np bigint,                   -- NULL si es consolidado (faltantes)
  payload jsonb NOT NULL,      -- el JSON generado
  creado_en timestamptz DEFAULT now(),
  enviado_en timestamptz,      -- NULL hasta que el agente-local lo baje
  enviado_por text              -- 'agente-local' o 'manual'
);

RLS: desactivar para anon, solo service_role y authenticated con chequeo de admin.

RPC `marcar_json_enviado(p_id bigint)`: pone enviado_en = now(). La llama el
agente-local después de bajar y dejar el archivo.

RPC `json_pendientes_sin_enviar()`: devuelve los que tienen enviado_en IS NULL,
ordenados por creado_en. La llama el agente-local para saber qué bajar.

SECURITY DEFINER en ambas, revocar anon.
Protocolo de backups NO aplica (tabla nueva, no hay datos que perder).
---
```

### PIEZA 6: Módulo descarga en agente-local
**Repo:** Produccion-Virgilio (agente-local/)  
**Tipo:** Python (agente-local existente)

```
PROMPT COMPLETO:
---
Agregar módulo al agente-local (agente-local/) que DESCARGUE JSONs de Supabase
y los deje en una carpeta donde ISIS los pueda leer.

Hoy el agente-local SOLO sube (vigila carpetas → parsea PDFs → Supabase).
Agregar el flujo inverso:

1. Poll periódico (cada 60s) a `json_pendientes_sin_enviar()` vía service_role
2. Por cada JSON pendiente:
   a. Escribir archivo en carpeta configurada (ej: C:\ISIS\entrada\)
   b. Nombre: `{tipo}_{np}_{id}.json` (ej: pedido_completo_98180_42.json)
   c. Llamar `marcar_json_enviado(id)` para que no se baje dos veces
3. Loguear cada descarga

Configuración en el .env del agente-local:
- ISIS_JSON_OUTPUT_DIR: carpeta destino
- POLL_INTERVAL_SECONDS: default 60

Mantener el patrón existente del agente-local (asyncio, logging, dedup).
Leer agente-local/README.md antes de tocar nada.
---
```

### PIEZA 7: Auditoría LK/Chef en tablas de producción
**Repo:** Produccion-Virgilio (Supabase `hrxfctzncixxqmpfhskv`)  
**Tipo:** Backend (auditoría)

```
PROMPT COMPLETO:
---
Auditar TODAS las tablas involucradas en la integración ISIS para verificar
que discriminan correctamente LK vs Chef:

Tablas a revisar:
- PPP_Programacion_Diaria → ¿tiene columna empresa? NP 9xxxx=LK, 4xxxx=CH
- PPP_Entregados_Meta → idem
- Ordenes_Compra → ¿tiene columna empresa?
- Movimientos_Stock → ¿discrimina por empresa?
- vista_saldos_stock → idem

El informe ISIS dice explícitamente "dos empresas desde el diseño".

Para cada tabla listar:
1. ¿Tiene columna empresa? Si no, ¿se puede derivar de la NP?
2. ¿Los datos actuales tienen las dos empresas o solo LK?
3. ¿Hay que agregar columna o alcanza con derivar?

NO ejecutar cambios — solo reportar hallazgos.
Usar execute_sql con project_id hrxfctzncixxqmpfhskv para consultar.
---
```

### PIEZA 8: Actualizar documentación
**Repo:** Produccion-Virgilio

```
PROMPT COMPLETO:
---
Actualizar docs del repo Produccion-Virgilio:

1. `docs/integracion-isis.md`: Agregar sección "Agosto 2026 — JSON exchange"
   que documente que el approach cambió de API /api/ISISPedido a JSON file
   exchange. Referir al Ticket 1159666. NO borrar el histórico de julio
   (sirve como contexto de por qué se descartó).

2. `docs/cruce-oc-isis.md`: Agregar nota de que P4 (recepción) del informe
   de agosto se relaciona con esta idea (5795) pero va por otro canal.

3. `GUIA-PROYECTO.md`: Si se crean tablas/vistas/RPCs nuevas, documentarlas
   según el protocolo del CLAUDE.md.

4. Verificar que el CLAUDE.md no necesite actualizarse con las nuevas tablas.

Commitear a main con mensaje descriptivo.
---
```

---

## Dependencias externas (lo que falta de ISIS)

Estas piezas NO se pueden construir hasta que ISIS responda:

1. **Transporte:** ¿carpeta compartida, URL, o API? → define si el agente-local
   escribe a disco o hace POST
2. **P3 — NP de vuelta:** ¿cómo devuelve ISIS el número de NP? → define ingesta
3. **P4 — Mapeo códigos:** ¿códigos proveedor/artículo de ISIS son los mismos que
   en Virgilio? → define si hace falta tabla de equivalencias
4. **Formato de respuesta de ISIS** (si mandan JSON de confirmación)

---

## Orden sugerido de construcción

1. **Pieza 7** (auditoría LK/Chef) — primero saber el estado real
2. **Pieza 2** (vista_falta_global) — base para todo lo demás
3. **Pieza 1** (RPC generar_json_pedido) — el corazón
4. **Pieza 5** (tabla staging) — donde se guardan los JSONs
5. **Pieza 4** (botón UI) — para que el supervisor lo use
6. **Pieza 6** (agente-local) — el puente al on-premise
7. **Pieza 8** (docs) — al final, cuando todo esté definido

---

## Bloqueantes de ISIS resueltos vs pendientes

| Pregunta | Estado |
|---|---|
| ¿JSON como formato? | ✅ Acordado |
| ¿Estructura del JSON? | ✅ Ejemplo en informe (pedido 98180) |
| ¿ISIS desarrolla consumo? | ✅ Prometido |
| ¿Transporte cloud→on-premise? | ⚠ Ya se puede decidir — ver "Transporte" abajo |
| ¿Formato respuesta ISIS→app? | ❌ Sin definir |
| ¿Mapeo códigos proveedor? | ❌ Sin definir |
| ¿NP de vuelta? | ❌ Sin definir |

### Decisiones del usuario (2026-08-25)

| Pregunta | Decisión |
|---|---|
| ¿Criterio del `ok`? | **Por pedido** — `stock >= cajas` para cada item del pedido. `falta_global` es informativo. |
| ¿Faltantes? | **Factura parcial** — se factura lo que hay, los faltantes se descartan (no se entregan más). |
| ¿Quién dispara? | **Dos triggers:** (1) automático al completar picking sin faltantes, (2) clic manual de la operadora para cerrar con faltantes. |


---

## Transporte cloud → on-premise: ya se puede decidir (2026-08-25)

El mensaje de Horacio del 25/8 (requisitos para usar la API del ISIS on-premise:
Windows Server + IIS + IP pública + **abrir el puerto** + firewall/AV, sin soporte de
QSA) aplica **solo si NOSOTROS llamamos al ISIS**.

En las tres alternativas del informe (§11) el que consulta es **ISIS**, y una request
**saliente** desde su LAN **no necesita nada de eso**: ni servidor nuevo, ni IP fija, ni
puertos abiertos, ni superficie de ataque.

**Recomendado — Alternativa B (ISIS consulta una API nuestra):**
- Edge Function en Supabase con **token**: `GET` de pendientes + `POST` de acuse.
- Da gratis lo que pide el §18 del informe: qué se recibió, qué se procesó, cuándo,
  resultado, errores, reintentos, control de duplicados.
- ISIS hace polling con la frecuencia que quiera. Nada expuesto del lado del depósito.

**Plan B — Alternativa A (carpeta, Pieza 6):** el agente-local baja los JSON y los deja
en `C:\ISIS\entrada\`. También es cero-puertos y es lo más simple para ellos, pero
depende de que la PC esté prendida y el acuse hay que inventarlo (mover/marcar archivos).

Queda como **Pieza 6-bis** por si ISIS prefiere leer disco antes que hacer HTTP.

---

## Riesgos / huecos detectados al releer el informe (2026-08-25)

Ninguno de estos está en el informe de ISIS ni cubierto por las piezas de arriba.

### 1. ✅ RESUELTO — Criterio del `ok`: por pedido (definido 2026-08-25)

**Decisión del usuario:** `ok` se calcula **por pedido**, no global.
`ok = true` cuando para CADA item del pedido `stock_terminado >= cajas_pedido`.
`falta_global` se mantiene como dato informativo en el JSON, pero **no decide**
si se factura o no. Aclararle a ISIS que el campo es informativo.

El ejemplo que vio ISIS (550 con `ok:false` por falta global) **no aplica** como
criterio de facturación — se usará el criterio por pedido.

### 2. ⛔ Equivalencias de código — la auto-facturación puede facturar el artículo equivocado

Ya documentado en la guía (v5.10): la factura debe ir con el código **real** (437E), no
con el del pedido (029). Hoy hay un agente que se lo avisa a Marianela por Telegram
justamente porque la facturación es manual.

Si ISIS auto-factura el pedido **tal como está cargado**, factura el código viejo. El
JSON tiene que llevar el artículo **realmente preparado** (o el mapeo), y hay que definir
si ISIS corrige la línea del pedido antes de facturar. **No está en el informe.**

### 3. ✅ RESUELTO — Faltantes: factura parcial (definido 2026-08-25)

**Decisión del usuario:** factura parcial. Cuando la operadora administrativa hace clic,
se factura **solo lo que hay** en ese momento. Los artículos faltantes **no se entregan
más** (se pierden, salvo que el cliente haga otro pedido). No se espera a completar.

Ejemplo: pedido con 10 artículos, solo hay 9 → clic → se factura 9. El décimo queda
afuera.

### 4. ⚠ Cutover del CAE: quién emite

Hoy la app emite Factura A por **PV 11** (`arca-wsfe`, prod). Si ISIS pasa a facturar,
hay que **apagar la emisión propia el mismo día** o se emite CAE dos veces por la misma
venta. Definir si PV 11 queda de respaldo (era la idea de julio) y quién lo apaga.

### 5. ⚠ Trazabilidad: falta el estado del lado ISIS

La tabla `isis_json_pendientes` (Pieza 5) solo sabe qué se **bajó** (`enviado_en`). No
sabe si ISIS lo **procesó**, si generó factura, con qué número/CAE, o si falló. Sin eso
no hay forma de garantizar que una NP no se facture dos veces — que es exactamente lo
que pide el §17 del informe.

Agregar a la Pieza 5: `procesado_en`, `resultado` (ok/error), `nro_comprobante`, `cae`,
`error_detalle`, y clave única por `(tipo, np, empresa)`.

### 6. ℹ El JSON de ejemplo no lleva `empresa`

El §14 exige contemplar las **dos empresas** desde el diseño, pero el ejemplo enviado
(98180/98187) no trae el campo. El Plan ya lo agrega (LK/CH derivada de la NP, misma
regla que usan los PDF: 9xxxx→LK, 4xxxx→CH). Falta **confirmarle a ISIS el nombre del
campo** y que lo acepte.

### 7. ℹ Aclararle a ISIS qué es `falta_global`

En el informe figura como "Cantidad faltante" a secas, lo que invita a leerlo como
faltante **del pedido**. Es un número **global** (todos los pedidos pendientes vs stock).
Si ISIS lo usa para decidir por línea, va a bloquear facturas que sí se pueden hacer.
