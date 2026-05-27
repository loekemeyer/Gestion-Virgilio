# Guía del Proyecto — Producción Virgilio

> Guía viva de referencia. Documenta **cómo funciona el programa** y **de dónde
> salen los datos**, para poder responder preguntas con precisión y sin inventar.
> **Mantener actualizada en cada cambio del proyecto** (ver § "Mantenimiento").
>
> Última actualización: 2026-05-27 · Versión app al documentar: **v1.58**
>
> Nota: v1.49 (de otra branch) agregó la **pantalla de Facturación** (botón 🧾,
> tick por NP, tabla `Facturacion_NP`) y **gráficos de productividad** (Chart.js:
> m³/h por operario por día, picking y pedido) con export **PDF** (jsPDF) en el
> monitor. En **v1.51**: los días sin datos ya no se grafican en 0 (quedan como
> hueco) y al **tocar/click en un punto** se abre la composición de ese promedio
> (las tandas con su m³ y tiempo que suman el m³/h).
>
> En **v1.52**: se **habilitó el QR de fichada** (`QR_DISABLED=false`, flujo
> Supabase verificado), el monitor **excluye legajos test 0/1** de conteos/gráficos,
> los botones 📊/📋 ya no aparecen en el celular del operario (el supervisor abre
> monitor/facturación por URL `?monitor` / `?monitor=fc`), más varios fixes de
> estética/CSS.
>
> En **v1.53**: compatibilidad con navegadores de TVs viejas (~2017+). Se quitó la
> sintaxis que rompía el parseo en esos navegadores (`?.`, `catch` sin binding,
> spread de objeto, `Promise.allSettled`). ⚠ El código usa `async/await` y arrow
> functions (ES2016-2017), así que **TVs de 2015-2016 todavía NO lo corren** — para
> esas haría falta una página de monitor aparte escrita en ES5.
>
> En **v1.55**: el logo de la app (`icon.svg`) se muestra en los headers del
> **Monitor Virgilio** y de **Facturación (ventas)** — clase `.hdr-logo`, escala con
> el título (em) así crece en modo TV. (En v1.54 se había puesto en la pantalla de
> legajo; se movió a los monitores.) Resto pendiente de detallar.
>
> En **v1.56**: los botones flotantes **📊 Monitor Virgilio** y **📋 Facturación
> (ventas)** vuelven a estar **siempre visibles** abajo a la izquierda, en cualquier
> pantalla y dispositivo (se revierte el ocultamiento de v1.52). Cualquiera puede
> abrir los monitores tocándolos.
>
> En **v1.57**: (a) **3er botón flotante ⚠ Inconsistencias** a la derecha del de
> Facturación (abre el monitor directo en esa pestaña; también por URL
> `?monitor=incons`). (b) El **Monitor Virgilio abre SIEMPRE en modo TV** (fondo
> azul, tablero completo), aunque la pantalla sea chica — ya no usa el popup blanco.
>
> En **v1.58**: (a) se **quitó la pestaña de Inconsistencias del Monitor Virgilio**
> (el modal ya no tiene pestañas); Inconsistencias se abre solo por su botón ⚠ y el
> título del modal cambia a "Inconsistencias". (b) **Responsive del monitor TV**: el
> tablero azul ahora **scrollea** si no entra (antes se recortaba con `overflow:hidden`)
> y **se apila en 1 columna en celular** (`@media max-width:760px`) → entra bien en la
> TV de 32" y en pantallas chicas.

---

## 0. Qué es

App web de una sola página (PWA, sin framework) para registrar la **producción
de un depósito** (picking, armado de pedidos, carga de camión, recepción, etc.).
La usan los **operarios** desde el celular tocando botones de acción, y los
**supervisores** desde un **monitor** que cruza esos eventos con la programación
de pedidos de un Google Sheet.

- Se sirve desde **GitHub Pages**: `https://loekemeyer.github.io/Produccion-Virgilio/`
- Repo: `loekemeyer/produccion-virgilio` · se publica desde la branch **`main`**
  (lo que llega a `main` queda online en ~1 min; cada pantalla lo ve al refrescar).
- Branch de desarrollo actual: **`claude/fix-virgilio-production-GoGCS`**.

---

## 1. Archivos del repo

| Archivo | Rol |
|---|---|
| `index.html` | **La app completa** (~6.600 líneas): pantalla de operario + monitor + toda la lógica JS/CSS. Es el archivo central. |
| `sw.js` | Service Worker. **NO cachea HTML/assets**: sólo hace Background Sync de la cola offline (IndexedDB). `SW_VERSION = "v1.52-vir"`. |
| `manifest.json` | Manifiesto PWA. |
| `fichada.html` / `fichada.js` / `fichada-config.js` / `fichada-totp.js` / `fichada.css` | Sistema de **fichada por QR rotativo (TOTP)**. La página `fichada.html` se abre escaneando el QR y registra el **ingreso**. |
| `fichadas-monitor.html` | Tablero **independiente** "Monitor Fichadas Esnaola" (lee de `Fichadas_Historico` y sincroniza otro Google Sheet distinto). No está enlazado desde `index.html`. |
| `monitor/index.html` | Shim de **redirección**: da la URL limpia `/Produccion-Virgilio/monitor` → redirige a `/?monitor=tv` (para colgar la Smart TV). |
| `qrcode.js` | Librería vendorizada para generar QR. |
| `icon.svg` | Ícono. |

---

## 2. Pantallas y navegación

Todo vive en `index.html`, alternando con la clase `.hidden` (no hay router):

- **Pantalla de legajo** (`#legajoScreen`): **login obligatorio con Google**
  (Supabase Auth, provider Google del proyecto `hrxfctzncixxqmpfhskv`). Arranca
  mostrando sólo el botón "Iniciar sesión con Google" (`#authBlock`). Tras loguear,
  el módulo de auth decide el **rol** por email y muestra la pantalla acorde:
  - **Supervisor** (emails en `SUPERVISOR_EMAILS`: `loekemeyer.n8n@gmail.com`,
    `loekemeyer.logistica@gmail.com`): ve `#supervisorPanel` con **4 botones grandes
    centrados** (📊 Monitor de operarios, 📋 Facturación, ⚠ Inconsistencias,
    📈 Análisis de productividad). No necesita estar en `Empleados` ni tiene legajo.
    (Los antiguos botones flotantes de abajo se eliminaron.)
  - **Operario** (email cargado en `Empleados`): se resuelve `email → {Legajo, Empleado}`
    (`select=Legajo,Empleado`). Ya **no se tipea el legajo** y **salta directo a la
    grilla de opciones** (EP/TP/...) vía `goToOptions()`. El **nombre** se muestra en
    `#userTag` arriba a la izquierda (persistente, también en opciones). El `#legajoInput`
    queda oculto (`display:none`) pero conserva el Legajo, así todo el código que lee
    `legajoInput.value` (~15 lugares: envíos, historial) sigue funcionando sin cambios.
    El `#legajoEntry` (saludo "Hola, {nombre}" + Continuar + Salir) queda como pantalla
    de "volver" (botón ← de opciones) y para el logout. **No** ve nada de supervisor.
  - **No autorizado** (ni supervisor ni en `Empleados`): `signOut()` inmediato +
    aviso "no autorizada". No se le da acceso usable.
  - **Gate de monitores:** `requireSupervisor()` protege `openMonitor/openFacturacion/
    openInconsistencias/openAnalisis` (vía `window.__isSupervisor`), así no se entra
    por la URL directa. El auto-open por URL (`?monitor=tv/fc/incons`) ya no corre en
    `load`: se difiere a `maybeAutoOpenMonitor()`, que el módulo de auth llama sólo si
    el email es supervisor. O sea **la TV de pared también requiere sesión supervisor**
    (se loguea una vez con logistica; la sesión persiste y reabre el monitor sola).
  - La sesión la persiste `supabase-js` en `localStorage`. El cliente de auth es un
    `<script type="module">` al final del `index.html` que importa
    `@supabase/supabase-js@2` desde CDN (jsdelivr). El `redirectTo` preserva el query
    (`?monitor=tv`) para que la TV vuelva a la misma URL tras el login.
  - **Para autorizar a un operario nuevo:** cargar su `email` en `Empleados`. Para un
    supervisor nuevo: agregar el email a `SUPERVISOR_EMAILS` en `index.html`.
  - **Requisitos de config (fuera del código):** provider Google habilitado en
    Supabase Auth · la URL de GitHub Pages (`https://loekemeyer.github.io/tv-v/`)
    en la allowlist de *Redirect URLs* · consent screen de Google OAuth en
    producción (o el operario como test user) · el `email` del empleado cargado
    en `Empleados` (hoy sólo ~9 de 58 lo tienen).
  - La allowlist es a nivel app (chequeo contra `Empleados`/`SUPERVISOR_EMAILS` +
    `signOut`). Una cuenta de Google ajena que complete el OAuth igual crea una fila
    transitoria en `auth.users`, pero queda deslogueada y sin acceso. El login es una
    **puerta de UI**, no el candado de los datos (la app lee/escribe con la clave
    pública anon igual que antes; el blindaje real de datos sería RLS).
  - El límite de "sólo 2 mails" del otro programa que usa el mismo proyecto Auth
    es lógica de *esa* app, **no** una restricción de Supabase (no hay hook ni
    trigger en el esquema `auth`): no afecta a esta app.
- **Pantalla de opciones** (`#optionsScreen`): la grilla de botones de acción +
  botón rojo **"Terminar Día"** (dispara el `FJ`).
- **Botones flotantes**: 📅 historial de días anteriores · 📊 **monitor** del supervisor.
- **Monitor**: se abre con 📊 o automáticamente con `?monitor=tv` (o si la pantalla
  mide ≥1600 px). La URL `/Produccion-Virgilio/monitor` entra directo en modo TV.
  Tiene **dos pestañas**: **Monitor** (tablero de tandas) e **Inconsistencias**
  (hoja de alertas, ver § 12).

---

## 3. Modelo de datos (Supabase)

- Proyecto Supabase: **`Control Partes Talleristas`** · id **`hrxfctzncixxqmpfhskv`**
  · región `sa-east-1` · Postgres 17. (La base es **compartida** con otros
  sistemas: tiene ~90 tablas; abajo sólo las que usa esta app.)
- URL: `https://hrxfctzncixxqmpfhskv.supabase.co`
- Key en el cliente: `sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT`
  (**publishable / pública por diseño**; RLS permite INSERT de producción/fichadas
  y los SELECT que el monitor necesita). La misma trinca está en `sw.js`,
  `fichada-config.js` y `fichadas-monitor.html`.
- Acceso desde Claude: usar la **herramienta MCP `execute_sql`** con
  `project_id = hrxfctzncixxqmpfhskv` (no requiere red del sandbox).

### Tablas que usa la app

**`Registros_Produccion_Virgilio`** — el **log de eventos de producción** (la tabla
clave para casi todo). Cada fila = una acción de un operario:

| Columna | Tipo | Notas |
|---|---|---|
| `id` | uuid | |
| `client_id` | text | id de la cola offline; en `FJ` es determinístico `fj_<legajo>_<YYYY-MM-DD>` |
| `legajo` | text | número de operario (texto) |
| `opcion` | text | **código de acción** (ver § 4) |
| `descripcion` | text | texto legible de la acción ("Empecé Picking", …) |
| `texto` | text | dato capturado: **código de tanda/pedido** o cantidad o (en FJ) un JSON de conteos. Siempre `.trim().toUpperCase()` |
| `ts_cliente` | timestamptz | momento del evento (cierre, si es un cierre) |
| `ts_inicio` | timestamptz | **sólo en eventos de cierre** = momento de apertura → `duración = ts_cliente − ts_inicio` |
| `created_at` | timestamptz | insert en servidor |

**`Fichadas_Virgilio`** — ingresos por QR: `legajo`, `email`, `tipo` (= `"ingreso"`),
`ts_cliente`, `client_id`, `user_agent`, `ip_hint`, `created_at`. (Hoy está
**muy poco usada** — pocos registros — porque el QR in-app está deshabilitado; ver § 9.)

**`Fichadas_Historico`** — espejo de marcas: `ts_evento`, `evento`
(`Entrada` / `Salida` / `Comida Inicia` / `Comida Termina`), `email`, `legajo`,
`empresa`, `imported_at`.

**`Empleados`** — maestro: `Legajo`, `Empleado` (nombre), `email`, `Num_Tel`,
`Activo`, `Sede`, `hora_entrada`, `hora_salida`, `tipo`. Sirve para resolver
legajo↔nombre y legajo↔email.

**`Auditoria_Produccion_Virgilio`** — auditoría de envíos (intentos, motivos,
user_agent, ts_inicio/ts_cliente).

---

## 4. Códigos de acción (`opcion`)

Definidos en `index.html` (objeto `desc`, ~línea 1531). Los botones se arman en
3 filas:

| Código | Descripción | Grupo | ¿Captura `texto`? |
|---|---|---|---|
| `EP` | Empecé Picking | CORE (inicio) | Sí — código de tanda (ej. `A12B`) |
| `TP` | Fin Picking | CORE (cierre) | Sí — código de tanda |
| `AP` | Empecé Armado Pedido | CORE (inicio) | Sí — código de pedido |
| `TAP` | Terminé Armado Pedido | CORE (cierre) | Sí — código de pedido |
| `CR` | Control Remitos | TOGGLE | No |
| `CC` | Inicio/Fin Carga Camión | TOGGLE | Sí, al cerrar (Nro) |
| `RT` | Recepción Mercadería | TOGGLE | Sí, al cerrar (cantidad) |
| `MG` | Guardado a Góndola | TOGGLE | No |
| `RI` | Recepción Insumos | TOGGLE | Sí, al cerrar (cantidad) |
| `EI` | Entrega Insumos | TOGGLE | Sí, al cerrar (cantidad) |
| `AT` | Atendí Timbre | TOGGLE / tiempo muerto | No |
| `PB` | Paré Baño | TOGGLE / tiempo muerto | No |
| `Limp` | Limpieza | TOGGLE / tiempo muerto | No |
| `Perm` | Permiso de Salida | TOGGLE | No |
| `PC` | Paré Comida | TOGGLE / tiempo muerto | No |
| `CT` | Conteo | TOGGLE / tiempo muerto | No |
| `FJ` | Fin de Jornada | (botón "Terminar Día") | `texto` = JSON con los conteos del día |

**Grupos (constantes en `index.html`):**
- `CORE_CODES = [EP, TP, AP, TAP]` — el trabajo medible (picking / armado).
- `TOGGLE_CODES = [CR, CC, RT, MG, RI, EI, AT, PB, Limp, PC, Perm, CT]` — abren y cierran.
- `DEAD_TIME_CODES = [AT, PB, Limp, PC, CT]` — mientras están abiertos **bloquean todo**.
- `ALWAYS_ALLOWED_CODES = [PB, PC]` — nunca se bloquean.
- `CLOSE_NEEDS_INPUT_CODES = [CC, RT, RI, EI]` — piden dato al cerrar.
- `SURVIVING_TOGGLES = [CR, MG]` — sobreviven la medianoche; el resto se autocierra.
- `AUTO_CLOSE_CODES = [AT, PB, Limp, PC, CT, Perm, CC, RT, RI, EI]` — se autocierran a las **17:00** (`WORKDAY_END_HOUR_AR = 17`) del día si quedaron abiertos.

---

## 5. Cómo se registran los eventos (semántica clave)

- **`ts_cliente`** = momento del evento. **`ts_inicio`** se completa **sólo cuando
  el evento es un cierre**. Entonces: **una fila con `ts_inicio` no nulo ES el
  cierre de una acción pareada**, y su duración = `ts_cliente − ts_inicio`.
- **Picking**: `EP` (abre, `ts_inicio` nulo) → `TP` (cierra, `ts_inicio` = apertura).
  Uno abierto por vez por legajo.
- **Armado**: `AP` (abre) → `TAP` (cierra). En el monitor la columna de armado se
  rotula **"Pedido Separado"** ("separado" = armado completo).
- **Toggles** (CR, CC, …): 1er toque abre (`ts_inicio` nulo), 2do toque cierra
  (`ts_inicio` = apertura). Son **mismo código** las dos veces.
- **`FJ` (Fin de Jornada)**: una sola fila por legajo/día (upsert por
  `client_id = fj_<legajo>_<día>`); `texto` guarda el JSON de conteos del día.
- Verificado en datos: `EP`/`AP`/`FJ` nunca traen `ts_inicio`; `TP`/`TAP` y los
  toggles lo traen ~la mitad de las filas (= sus cierres). No hay duraciones
  negativas (`ts_cliente < ts_inicio` = 0 casos).

---

## 6. Flujo de negocio

- **Tanda**: unidad de trabajo, un código de lote que el operario tipea en `texto`
  (ej. `C10B`, `C15A`, `A57B`; a veces numérico como `46112`). Viene de la
  programación del Google Sheet (filas con `Op = SI`).
- **NP**: número de pedido. Una tanda agrupa **uno o más NP**, cada uno con Razón
  Social y **m³** propios (se ven en el modal de detalle de tanda).
- **Camión**: se deriva del código de tanda (`tandaCamion()`): `C03A` y `C03B`
  → camión "03". El monitor agrupa por camión en "Total por día".
- **Secuencia esperada de un pedido/tanda**: `EP→TP` (picking) y `AP→TAP`
  (armado/separado); `CC` es la carga de camión (evento aparte).

---

## 7. De dónde salen los metros cúbicos (m³)

> **CRÍTICO: los m³ NO están en Supabase.** Salen de un **Google Sheet**. Por eso
> no se pueden calcular desde un entorno sin acceso a Google (p. ej. el sandbox de
> Claude, que tiene Google fuera de la allowlist). La **app sí** los muestra
> porque corre en el navegador.

- Documento Sheet: `1-16YXe0xq6x9i-Yhk5cm5V3VqvQ0PWZtcDbm8OeeKW0`.
- **Histórico** (todos los pedidos entregados): hoja "PPP Excel Pedidos Entregados
  2026", `gid=2146771217`. Se mapea **`Tanda` → m³ sumando la columna `Mt3` (col G)**.
- **Programación diaria**: `gid=1947169223` (cols `Tanda`, `M3`, `Op`, `Fecha
  Entrega`, `N° NP`, `Razon Social`).
- **⚠ NO usar la columna H "Mt3 FC"**: pese al nombre, NO son m³ — son códigos
  chicos (zonas) que inflan los totales. **Sólo col G "Mt3".**
- Para resolver los m³ de una tanda: primero el sheet de programación, si no está,
  el histórico, si no, 0. `monitorParseM3` entiende coma decimal (`"0,289"` → 0.289).
- El monitor ya calcula y muestra **m³ de picking / m³ de armado / total / m³ por
  hora por operario** en el modal **"Rendimiento del día"** (`showDayBreakdown`).

---

## 8. Cómo se calculan horas / jornada

En `showDayBreakdown` (monitor, por operario por día):

- **Jornada** = `(FJ − ingreso) − comida`, donde `ingreso` viene de
  `Fichadas_Virgilio (tipo=ingreso)`, `FJ` del evento `FJ`, y `comida` = suma de
  duraciones de `PC` (cap de sanidad: sólo si `0 < dur < 8 h`).
- Como hoy casi no hay fichadas de ingreso, la jornada suele quedar incompleta.
  La métrica robusta y usada para reportes es **horas trabajadas = primera acción
  → `FJ` (o última acción si no hay FJ), menos la comida (`PC`)**.
- Zona horaria: **`America/Argentina/Buenos_Aires`, UTC-3 fijo** (Argentina no
  tiene horario de verano). Los límites de día son `T00:00:00-03:00` /
  `T23:59:59-03:00`.

---

## 9. Fichada / QR (TOTP)

- `fichada-config.js`: `hmacSecret`, `tokenPeriodSec = 30`, `tokenTolerance = 1`
  (acepta el bucket actual ±1). El secreto está en JS público → "disuasivo, no
  barrera criptográfica".
- `fichada-totp.js`: token = `<bucket>.<sig16hex>` con HMAC-SHA256 sobre
  `floor(now/1000/30)`; `verifyToken` con comparación de tiempo constante.
- El QR in-app **está habilitado** (`QR_DISABLED = false`, desde v1.52). El monitor/TV
  muestra el QR rotativo abajo-derecha (sólo con el monitor abierto). El operario lo
  escanea → abre `fichada.html?t=<token>` → pone su email → registra el **ingreso** en
  `Fichadas_Virgilio` (`tipo:"ingreso"`) + espejo a `Fichadas_Historico`
  (`evento:"Entrada"`). El legajo se resuelve por email contra `Empleados`; si el email
  no está cargado, igual ficha con `legajo=null` y el monitor lo marca "sin legajo".
  Flujo verificado: RLS deja al rol `anon` insertar en ambas tablas.
- `PC` y `FJ` se mandan desde la app principal y se espejan a `Fichadas_Historico`
  (`FJ→"Salida"`, `PC` abre→`"Comida Inicia"`, `PC` cierra→`"Comida Termina"`).

---

## 10. Versionado y cache

- `index.html`: `APP_VERSION = "v1.46"`. Badge en pantalla `#versionBadge`:
  `"v1.46 ✓"` (sin cola), `"v1.46 ⏳ N"` (pendientes), `"v1.46 ⚠ N"` (error).
  **Sirve para confirmar qué versión cargó cada pantalla.**
- `sw.js`: `SW_VERSION = "v1.46-vir"`. **No precachea nada**; el handler de `fetch`
  está vacío. Usa `skipWaiting()` + `clients.claim()`. La página hace
  `reg.update()` cada 60 s con `updateViaCache:"none"`.
- Por eso, el problema de "la TV muestra una versión vieja" es **cache HTTP del
  navegador/TV**, no del SW. Subir la versión y refrescar (o forzar recarga en la
  TV) lo resuelve.

---

## 11. Cómo responder preguntas con SQL (recetas validadas)

Usar MCP `execute_sql` con `project_id = hrxfctzncixxqmpfhskv`. Ventana de día en
hora Argentina: `ts_cliente >= 'YYYY-MM-DD 00:00:00-03'`.

**Horas trabajadas + pedidos por legajo (rango de días):**
```sql
with ev as (
  select nullif(trim(legajo),'') legajo,
         (ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date dia,
         opcion, upper(trim(coalesce(texto,''))) tanda, ts_cliente, ts_inicio
  from "Registros_Produccion_Virgilio"
  where ts_cliente >= '2026-05-22 00:00:00-03' and ts_cliente < '2026-05-27 00:00:00-03'),
perday as (
  select legajo, dia, min(ts_cliente) first_ts, max(ts_cliente) last_ts,
    max(ts_cliente) filter (where opcion='FJ') fj_ts,
    coalesce(sum(extract(epoch from (ts_cliente-ts_inicio)))
      filter (where opcion='PC' and ts_inicio is not null and ts_cliente>ts_inicio
              and (ts_cliente-ts_inicio) < interval '8 hours'),0) comida_seg
  from ev where legajo is not null group by legajo, dia)
select legajo, count(*) dias,
  round(sum(extract(epoch from (coalesce(fj_ts,last_ts)-first_ts)) - comida_seg)/3600.0,2) horas
from perday group by legajo order by horas desc;
```

**Pedidos completados por día** (picking = `TP`, armado = `TAP`, distintos):
```sql
select (ts_cliente at time zone 'America/Argentina/Buenos_Aires')::date dia,
  count(distinct upper(trim(texto))) filter (where opcion='TP'  and trim(coalesce(texto,''))<>'') pickeados,
  count(distinct upper(trim(texto))) filter (where opcion='TAP' and trim(coalesce(texto,''))<>'') armados
from "Registros_Produccion_Virgilio"
where ts_cliente >= now() - interval '7 days' group by 1 order by 1;
```

**m³** → **no se pueden** desde SQL (ver § 7). Mirar el monitor ("Rendimiento del
día") o exportar el Sheet.

**Notas de datos:** legajos `1` (= "Pruebas") y `0` son test/basura, excluirlos.
Operarios reales vistos recientemente: 104 (Jhonny Moncayo), 237 (Franco Ortiz),
8 (Farias Juan Hilario), 270 (Matias Insaurralde), 260 (Tomas Valdes), 94 (Isidro Tevez).

---

## 12. Reglas de inconsistencia (qué es "correcto" vs anómalo)

Una inconsistencia = lo que el operario registró no condice con cómo debería
operar el sistema. **Implementado (v1.47)** como la pestaña **Inconsistencias**
del monitor: selector de día (hoy + 6 anteriores), severidad **ALTA** (rojo) /
**media** (ámbar), badge con el conteo y auto-refresco cada 20 s. Excluye los
legajos test `0` y `1`. Reglas y umbrales (en `index.html`, sección "HOJA DE
INCONSISTENCIAS"):

**A. Tareas sin cerrar / duración absurda**
- `EP` sin su `TP` (mismo legajo/tanda/día) → picking sin cerrar.
- `AP` sin su `TAP` → armado sin cerrar.
- Toggle abierto sin cerrar al fin del día.
- Cierre con duración disparatada (visto: `TP` hasta ~65 h, `TAP` hasta ~121 h →
  se olvidaron de cerrar). Umbral sugerido: picking/armado > ~6–8 h.

**B. Secuencia inválida**
- `TP` sin `EP` previo / `TAP` sin `AP` previo (mismo legajo/tanda/día).
- Evento de producción con `ts_cliente` posterior al `FJ` del día.
- `FJ` duplicado en el día (no debería: usa upsert determinístico).
- Jornada con actividad pero **sin `FJ`** (día ya cerrado).

**C. Pedido inválido o duplicado**
- Código de tanda/pedido (`texto` de EP/TP/AP/TAP) que **no está en la planilla PPP**
  (la app ya lo detecta: banner "Tandas trabajadas que NO están en PPP — alguien se
  equivocó").
- Misma tanda completada (`TP` o `TAP`) por **dos legajos** distintos el mismo día.

**D. Tiempos anómalos**
- `PC` (comida) muy larga (> ~75 min) o **más de una** por día.
- Hueco de inactividad largo entre eventos (> ~60 min) dentro de la jornada.
- Jornada excesiva (> ~12 h).

---

## 13. Mantenimiento de esta guía

- **Actualizar este archivo cuando cambie el proyecto**: nuevos códigos de
  `opcion`, cambios de flujo, nuevas tablas/columnas, cambios en el origen de los
  m³, nueva versión, etc.
- Al subir una versión, actualizar `APP_VERSION` y `SW_VERSION` y la línea de
  versión del encabezado de esta guía.
- Si se agrega una pantalla/pestaña (p. ej. la **hoja de inconsistencias**),
  documentarla en § 2 y sus reglas en § 12.
