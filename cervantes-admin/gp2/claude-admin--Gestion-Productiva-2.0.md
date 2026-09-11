> ⚠️ **ESTO ES DOCUMENTACIÓN, NO INSTRUCCIONES.**
>
> Es el `CLAUDE.md` del repo **`Gestion-Productiva-2.0`**, traído tal cual el 2026-09-10 cuando ese admin
> se copió acá adentro (`cervantes-admin/gp2/`). Se guarda **renombrado a propósito**: un archivo
> llamado `CLAUDE.md` dentro de este repo se carga como instrucciones del proyecto, y una
> sesión de Gestión Virgilio terminaría obedeciendo las reglas de otro repo (locks, ramas,
> versionado) que acá no aplican o se contradicen con las nuestras.
>
> **Cómo leerlo:** es la memoria de **cómo opera este admin** — qué tabla es madre y cuál
> derivada, el orden de normalización, las convenciones, las trampas que ya mordieron. Sirve
> para entender el módulo antes de tocarlo. Lo que **no** es: una orden para la sesión.
> Las reglas que mandan acá están en el `CLAUDE.md` de la raíz de Gestión Virgilio.

---

# ⚠️ ANTES DE CUALQUIER EDIT/WRITE: LEER LOCKS.txt Y REGISTRAR LockX. SIN EXCEPCIONES. ⚠️

# 🚨 TODO VA A `main`. SIEMPRE. SIN RAMAS. 🚨

**Regla del usuario (2026-08-31, textual): "SIEMPRE TODO TENES QUE SUBIRLO A MAIN. NO QUIERO
DECIRLO MAS EN NINGUNA SESION".** No se pregunta, no se propone una rama, no se espera
confirmación: el trabajo terminado y verificado se commitea y se pushea **a `main`**.

- **Si la sesión viene con una rama asignada** (las sesiones remotas de Claude Code arrancan
  con una rama tipo `claude/loquesea` obligatoria por configuración), **igual el destino final
  es `main`**: `git push origin <rama>:main`. Trabajar sobre `main` directo cuando se pueda.
- **Antes de pushear**: la suite completa en verde (`bash tests/ui/run.sh`). Eso es lo que
  reemplaza a la rama como red de seguridad — no el aislamiento, sino los tests.
- **Nunca dejar trabajo colgado en una rama.** Pasó el 2026-08-31: 5 commits quedaron en una
  rama mientras los cambios de Supabase YA estaban vivos en la base → la BD tenía los cambios
  y `main` no tenía el código que los acompaña. Ese desfasaje es el peligro real.
- **Ojo**: lo que se aplica en Supabase (migraciones, datos) **no lo versiona git** y queda
  vivo al instante. Razón de más para que el código llegue a `main` en el mismo momento.

# Gestion Productiva - Instrucciones para Claude

## 🪨 Modo Caveman (SIEMPRE activo)

**Cada conversación abre con caveman activo por defecto.** Responder en modo **caveman**:
frases cortas, directas, mínimas palabras, sin relleno. Solo aplica al **chat** (no al
código, comentarios ni mensajes de commit).

- **`desactiva caveman`** = responder solo el **próximo mensaje** normal/completo, y después **volver solo** a caveman.
- **`caveman desactivacion total`** = apagar caveman por completo (queda desactivado hasta que se reactive).

### 📏 EL LARGO DE LA RESPUESTA (regla del usuario, 2026-09-08, textual)

**"Me mandaste un mensaje eterno para que lea, imposible que te lea. Tus mensajes, por más de
que vos hagas tu trabajo interno, a lo último tenés que mandar un resumen conciso y breve para
que pueda leer solamente eso y no tener que leer todo tu proceso de análisis."**

- **El análisis se hace, pero NO se escribe.** Consultas, cruces, verificaciones: todo eso queda
  adentro. Lo que llega al chat es la **conclusión**.
- **Apuntar a ~10 líneas.** Si no entra, es porque se está contando el camino en vez del
  resultado. Sacar el camino, no el resultado.
- **Nada de volcar tablas de 20 filas, listados completos ni el paso a paso de cómo se llegó.**
  Si el detalle hace falta, va a un **archivo** (`.md` / `.xlsx`) y en el chat va **el link y una
  línea**. Ese es el lugar del detalle, no el chat.
- **Estructura fija:** (1) la respuesta en una o dos frases; (2) lo que hay que decidir o el
  número que falta; nada más. Los "hallazgos de paso" van al archivo o a `IDEAS-GP2.md`, no al
  mensaje.
- Vale igual cuando el hallazgo es grande o entusiasma: **un hallazgo grande se dice en una
  línea**, no en tres tablas.

## 🏠 Filosofía GP2: "la casa del vecino" (LEER SIEMPRE — analogía guía)

**Analogía base para todo el proyecto GP2 (usarla en todos los chats):**

- **`public` = la casa del vecino.** Es el programa viejo "Gestión Productiva Entero", ya
  construido y funcionando. NO es nuestra casa. NO se copia. NO se toca (solo lectura).
- **`GP2` (schema propio en Supabase) = mi casa.** La estamos construyendo de cero,
  **independiente** de la del vecino.
- **La regla de oro:** construimos mi casa **mirando la LÓGICA de cómo el vecino hizo la
  suya**, NO copiando su casa. Tomamos las ideas/lógica (cómo modela producción,
  causa-efecto, PS, talleristas, stock), pero los datos y la estructura son 100% míos,
  nativos de GP2. Cero dependencia de `public`.
- **Cuándo mirar al vecino:** solo para **llenar huecos** — cuando a mi casa le falta una
  lógica que el vecino ya resolvió, miro cómo lo hizo y lo implemento a mi manera en GP2.
- **Estado limpio = "como te lo mandé en un principio":** las tablas GP2 deben quedar como
  el Excel original que cargó el usuario (art 84, componente 471, proveedor_servicio 8,
  tallerista 12, matriz 115, ruta 555, ruta_paso 2346, ubicacion 32, articulo_componente
  505, componente_bom 32, inventario 848 con stock 0 + 766 mínimos). Snapshot de referencia:
  el `var D` embebido en los 3 HTML originales del usuario (`Registro_Movimientos.html`,
  `Programa_Stock_Loekemeyer.html`, `Faltantes_Loekemeyer.html`, que NO están en el repo) = ESA
  foto limpia.
- **NO inventar / NO asumir:** nunca crear datos de negocio inventados. Si falta un dato,
  marcarlo pendiente/null y que lo aporte el usuario. Agregar cosas nuevas a la casa se hace
  **deliberadamente**, no contaminando las tablas base.
- **El motor de inventario vive en la BD**, no en el JS: la app inserta filas crudas en
  `GP2.movimiento` y los triggers (`fn_movimiento_calc` + `fn_movimiento_aplicar`) calculan
  y aplican el delta en `GP2.inventario`. El `var D` de los HTML mapea 1:1 a tablas GP2
  (los contratos de los bundles y los nombres reales de las tablas están en `GP2_MAPA.md`).

## Campos de carga: letra grande + teclado numérico (OBLIGATORIO)

**Regla del usuario (2026-08-30): "Siempre quiero letras bien grandes y legibles para que
alguien que ve mal pueda escribir y no equivocarse. Donde van números, solo teclado numérico."**

En TODA pantalla, nueva o tocada:
1. **Letra grande en los campos**: mínimo 18px en inputs/selects (piso global en
   `gp2-modulo.css`); los campos importantes de carga (cantidades, pesos) mejor 19–20px.
   Nunca bajar de eso en el CSS propio de una pantalla.
2. **Teclado numérico donde van números**: todo `<input>` que recibe un número lleva
   `inputmode="numeric"` (enteros) o `inputmode="decimal"` (con coma). Vale también para
   los `type="number"` (el atributo garantiza el teclado correcto en el celular).
3. Etiquetas visibles al lado del campo, no solo placeholder (el placeholder desaparece
   al tipear y quien ve mal pierde la referencia).
4. **La letra grande NO puede romper la prolijidad** (dicho del usuario: "que se
   entienda que se puede tocar bien en todos lados sin que algo se vea feo — UX/UI
   súper prolija"). Al agrandar: las tablas anchas van dentro de `.table-wrap`
   (scrollean solas, la página nunca scrollea horizontal), los inputs de tabla llevan
   ancho explícito para no reventar la columna, y después de tocar tamaños se
   verifica el render en 390px (sin desbordes, sin solapamientos, touch ≥44px).
5. El test `tests/ui/test_teclado_numerico.js` lo vigila: falla si aparece un
   `type="number"` sin `inputmode`.
6. **La regla de número es una sola y vive en `gp2-numero.js` (`GP2N`)** — el punto es
   separador de miles, la coma el decimal, y el separador se pone automático a partir de
   cuatro dígitos. Una pantalla que lo carga ya tiene el formato en todos sus campos.
   **Nunca escribir un saneador de número propio**: `tests/ui/test_numero.js` lo rechaza.

## Helpers de pantalla y cliente Supabase: UNA copia (OBLIGATORIO desde 2026-09-05)

Ninguna pantalla GP2 escribe su propio `esc()`, `$()`, "hoy", exportador CSV ni
`createClient`. Existen una sola vez y hay tests que fallan si vuelve a aparecer una copia:

1. **`gp2-ui.js` (`GP2UI`)**: `esc`, `$`, `cls` (pos/neg/cero), `hoyAR()` (la fecha de HOY en
   Argentina; `toISOString().slice(0,10)` es UTC y después de las 21:00 da el día siguiente),
   `fechaAR(iso)` (dd/mm/aaaa), `exportarCSV(nombre, filas)` (`;`, BOM, coma decimal).
2. **`gp2-numero.js` (`GP2N`)**: `num` / `entero` para leer un campo, `fmt(n, dec, sinValor)`
   para mostrar. Donde está cargado, ningún `.value` se lee con `Number()`/`parseInt()` crudo
   (el campo se ve con separador de miles y "1.500" daría 1,5) y no hay `toLocaleString`
   propio.
3. **`GP2_SB()` (en `supabase-config.js`)**: el cliente GP2 (schema `GP2`, sin sesión
   persistida). `var SB = GP2_SB();` — nunca `supabase.createClient(...)` en una pantalla.
4. **Orden de carga**: `supabase-config.js` → `gp2-ui.js` → `gp2-numero.js` → los JS
   compartidos que dependen de ellos (`gp2-envios-common.js`, `gp2-composicion.js`,
   `gp2-stock-sector.js`, `consumo-detalle.js`) → el script de la pantalla.
5. Guardianes: `tests/ui/test_helpers_ui.js` (helpers, orden, copias, cliente),
   `test_numero.js` (regla de número, parses crudos, formateadores propios),
   `test_smoke_gp2.js` (abre las 47 pantallas con Supabase stubeado: falta un script o
   revienta un helper → falla) y `test_contratos_db.js` (toda `rpc('x')` / `from('x')` de las
   pantallas existe en `db/`, cada columna pedida en `from().select()` existe, cada clave `p_*`
   es un parámetro real de la función y no falta ninguno obligatorio: si falla porque `db/`
   está viejo, se regenera `db/`).

## Versionado (OBLIGATORIO en cada actualización)

**Cada vez que se modifica el JS/CSS/HTML de un módulo, bumpear la versión en el mismo commit.**
Las tablets y celulares cachean fuerte; sin bump siguen corriendo la versión vieja.

1. Subir el `?v=` de los `<script src="...?v=X.Y.Z">` y `<link href="...?v=X.Y.Z">` del HTML del módulo.
2. **La app de operarios NO muestra número de versión** (el usuario lo pidió sacar,
   2026-08-31): el badge `#syncBadge` es solo el estado de la cola (`✓ al día` / `⚠ N sin
   enviar`). Lo único versionado del operario es el `?v=` de su `<script>` (para el
   auto-recargador) y el `MI_V` del HTML tiene que quedar con **ese mismo token** — el
   `test_tokens_cache` lo vigila y verifica que no reaparezca una versión en pantalla. Nunca
   volver a poner un `const APP_VERSION` ni un `GP2 vX.Y.Z` en el operario.
3. Convención: fix chico = patch (1.2.0→1.2.1), feature = minor (1.2.0→1.3.0).
4. Si el HTML no tiene `?v=` en sus recursos externos, agregárselo al tocarlo.
5. **`version.js` (versión global) también se bumpea.** Es la que ve el usuario en el cartel
   "Versión vX.Y.Z" del login, `GP2_MODULOS.html`, `envios-only.html` y `Relevamiento`.
   (`Inicio/index.html` ya no muestra nada: hoy es un redirect de 14 líneas a
   `GP2_MODULOS.html`, que es quien carga `version.js`.)
   Al soltar features, subir `window.APP_VERSION` **y** el `?v=` de los `<script src="version.js?v=...">`
   (si no se bumpea el `?v=`, el celular sigue con el archivo viejo cacheado y muestra la versión de antes).

## 🧭 Otros archivos vivos que hay que conocer

- `GP2_MAPA.md`: contratos de los `*_bundle` y nombres reales de tablas/columnas (mirar antes de
  tocar una pantalla que hable con GP2).
- `REFACTOR_GP2.md`: bitácora de la auditoría de arquitectura del 2026-09-04 (qué se borró, qué se
  fusionó, por qué). `PREGUNTAS_ARQUITECTURA_GP2.md`: las dudas de negocio que salieron de ahí y
  esperan respuesta del usuario; si el usuario contesta alguna, aplicar y tachar.
- `db/`: respaldo del schema (tablas, funciones, vistas). Regenerarlo al terminar una sesión que
  cambió la base. **`db/verificar.sql`**: los invariantes de la base en una consulta (cada fila
  debe dar `n = 0`); correrla antes de tocar la base y al cerrar, y si algo da > 0 es lo primero
  que se arregla.

## 🧠 CONOCIMIENTO_GP2.md — la memoria del negocio (LEER AL INICIO, ESCRIBIR SIEMPRE)

**Leer `CONOCIMIENTO_GP2.md` al arrancar cada sesión, junto con este archivo.** Ahí está
el conocimiento del negocio que el usuario ya explicó alguna vez: quién provee qué, por
qué se decidió cada cosa, qué conviene y qué no, y las trampas que ya nos mordieron.

**Regla de captura (OBLIGATORIA):** cada vez que el usuario explique **cómo funciona algo,
por qué se hace así, quién hace qué, o qué decidió**, eso se agrega a `CONOCIMIENTO_GP2.md`
**en el mismo commit del trabajo** — no se espera a que "cierre el tema". Marcar el origen:
`[usuario]` lo dijo una persona, `[dato]` sale de una consulta (decir cuál), `[deducido]`
lo infirió el agente y está **sin confirmar**. Si un dato nuevo contradice uno viejo, se
corrige la línea y se anota la corrección: casi siempre significa que cambió la realidad y
hay que revisar el módulo que dependía de ese dato.

**El objetivo es que el usuario NO tenga que volver a explicar.** El agente
`.claude/agents/gp2-experto.md` usa ese archivo para hacer de contraparte: cruzar una idea,
decir si cierra con lo ya decidido y proponer alternativas. Invocarlo cuando haya que
**decidir** algo del negocio (no para tareas mecánicas). Si `CONOCIMIENTO_GP2.md` no crece,
el agente no sirve.

## Agente diario de mejoras + IDEAS-GP2.md (reglas para CUALQUIER chat)

Corre solo, todos los días a las 6:00 (AR), en una sesión nueva. Audita el repo (suite,
render 390px, deuda, docs desviadas) y registra ideas con **código de 4 dígitos** en
`IDEAS-GP2.md` **en main** (SIN ramas — regla del usuario 2026-08-30: "no quiero
ramas, solo en main"). Los fixes chicos y seguros los hace DIRECTO en main, con la
suite completa en verde antes de pushear, y los anota como hechos. Si no encuentra
nada, dice "Sin novedades" y no molesta. Aviso push al usuario al cierre.

**Comando `:`** — si el usuario escribe `:`, leer `IDEAS-GP2.md` y mostrar las ideas
`pendiente` como checklist de a 5, para que tilde.

**Idea aceptada** ("dale 4837" o tildada): desarrollarla AHORA directo en main,
verificar (suite en verde) y pushear. Después marcar la línea en IDEAS-GP2.md
(`[x]` hecha, o `~~tachada~~` descartada). Las ideas que escribe el usuario en el
chat también se registran ahí (mismo formato, para que no se pierdan).

## Perfiles de Usuario (LEER AL INICIO)

**Al arrancar cada sesión, leer `PERFILES.md` para saber con quién estás trabajando.**
El usuario se identifica por el nombre de usuario de Windows (mismo que usa el sistema de locks).
Adaptar el trato, nivel de detalle y módulos según el perfil del usuario.

## Renombres de Sectores (carga de stock_inicial)

**Al cargar `stock_inicial` desde Excel a `Partes x Tallerista`, leer `Renombres_Sectores.md`** —
contiene mapeos confirmados de codigos viejos del Excel a sectores actuales en BD
(p.ej. E11→D1, A2→PA2, EP2/3→PEP4). Antes de preguntar por discrepancias, chequear ahí
si ya existe el mapeo. Cuando el usuario confirme un renombre nuevo, agregarlo al archivo.

## Sistema de LOCKS (OBLIGATORIO - LEER PRIMERO)

**REGLA #1: NUNCA usar Edit ni Write sin antes leer LOCKS.txt y registrar tu LockX.**
**REGLA #2: NUNCA liberar un LockX sin revisar la WAIT QUEUE.**
**REGLA #3: Si te olvidas de los locks, el usuario te va a corregir. No dejes que pase.**

**Esta carpeta es compartida entre varias personas con Visual Studio Code + Claude.**
**Antes de tocar cualquier archivo, usar el sistema de locks en `LOCKS.txt`.**

### Protocolo de locks (como SQL Server):

| Lock | Significado | Compatible con |
|------|------------|----------------|
| LockS | Lectura/analisis para planificar cambios | Otros LockS (NO con LockX) |
| LockX | Edicion exclusiva del archivo | NADA (ni LockS ni LockX) |

### Identificacion: usar el nombre del usuario de Windows como identificador en los locks.

### Flujo NORMAL (archivo libre):

1. **Leer `LOCKS.txt`** seccion [LOCKS] - Verificar que el archivo NO tenga locks ajenos.
2. **Registrar tu LockX** en [LOCKS]: `LockX | ruta/archivo | tu-id | fecha hora | que vas a hacer`
3. **Re-leer el archivo** justo antes de editarlo (puede haber cambios recientes).
4. **Hacer la edicion** con Edit tool (ediciones minimas, nunca reescribir completo).
5. **Al terminar:**
   a. Revisar si hay alguien en [WAIT QUEUE] esperando por tu archivo.
   b. Si hay alguien esperando: cambiar su linea WAIT a READY.
   c. Borrar tu LockX de [LOCKS].
   d. Agregar linea en [HISTORIAL] con lo que hiciste (mantener max 10).

### Flujo con ESPERA (archivo bloqueado):

1. **Leer `LOCKS.txt`** -> El archivo tiene un LockX ajeno.
2. **Registrar WAIT** en [WAIT QUEUE]: `WAIT | ruta/archivo | tu-id | fecha hora | que necesitas hacer`
3. **Informar al usuario** que el archivo esta bloqueado y que quedo en cola de espera.
4. **Si hay otros archivos libres** del mismo pedido, trabajar en esos mientras tanto.
5. **Revisar periodicamente** (cada vez que termines otra tarea) si tu WAIT cambio a READY.
6. **Cuando veas READY:**
   a. **RE-LEER el archivo completo** (tiene cambios del lock anterior!).
   b. **Adaptar tu trabajo** a los cambios nuevos que encuentres.
   c. Borrar la linea READY, registrar tu LockX en [LOCKS].
   d. Ejecutar tu edicion.
   e. Repetir el paso 5 del flujo normal (revisar wait queue, liberar, historial).

### Reglas adicionales:
- Editar solo lo minimo necesario. No reformatear, no reordenar, no "mejorar" codigo no pedido.
- No tocar archivos fuera del alcance del pedido.
- Prioridad en wait queue: FIFO (primero en registrarse, primero en ejecutar).
- Si un lock lleva mucho tiempo (>30 min), avisar al usuario que puede estar obsoleto.
- NUNCA borrar lineas de locks ajenos sin autorizacion del usuario.

## Completar tablas manteniendo la NORMALIZACIÓN (ORDEN PRIMORDIAL)

**Cuando cambia un proceso o producto GP2 (qué partes lleva, quién arma, quién entrega),
actualizar TODAS las tablas normalizadas que lo describen, en ESTE orden, sin saltear ninguna:**

1. `componente` — altas/bajas de piezas. Antes de inventar un código, mirar la convención
   existente de la tabla (los cartones usan posición de estantería, los flejes "Fleje N°", etc.).
2. `inventario` — fila para el componente nuevo en su ubicación (cantidad 0).
3. `articulo_componente` y `componente_bom` — las recetas.
4. `ruta` / `ruta_paso` — los pasos, respetando las convenciones de nombres y el duplicado
   de ruta por tallerista cuando hay más de uno que hace el mismo paso.
5. `contraparte_alias` / espejo Virgilio — si cambia quién entrega.

Nunca parchar una sola tabla ni meter datos desnormalizados: una ruta que no cierra con la
receta, o una receta con componentes que ninguna ruta produce, rompen trazado y stock.
Ejemplo de referencia: reestructuración del artículo 506 (2026-08-29, ver HISTORIAL/git).

## Tablas Madre y Derivadas (OBLIGATORIO - LEER ANTES DE TOCAR SUPABASE)

**Antes de hacer INSERT, UPDATE o DELETE en Supabase, verificar en esta seccion si la tabla es MADRE o DERIVADA.**
**Si es DERIVADA, NO modificarla directamente. Ir a la tabla MADRE correspondiente.**
**Si no estas seguro, PREGUNTAR al usuario antes de ejecutar.**
**Referencia completa: `Tablas_Madre_y_Dependencias.xls` en la raiz del proyecto.**

### Cadena de Pesos (Kg x Uni / Kg x Cajon)

```
TABLAS MADRE (donde se carga):
  SP Kg          → sectores procesados (Sp, Kg X Uni, KG x Cajon)
  SC Kg          → sectores crudos (SC, Kg X Uni, KG x Cajon)
  SectorPlasticos → plásticos (Sector, Kg x Uni, Uni x Bolsa)
  Remaches SP/SC → remaches

TABLAS DERIVADAS (se sincronizan solas, NUNCA modificar directo):
  Despiece x Articulo  → KGxUni, Kg x Caj (sincronizado por funcion actualizar_despiece)
  Partes x Tallerista  → kgxuni, kg_x_caj (sincronizado por trigger desde Despiece)
```

**⚠️ Si alguien pide cargar pesos en `Despiece x Articulo` o `Partes x Tallerista`, AVISAR que se van a sobreescribir. Cargar en SP Kg o SC Kg segun corresponda.**

**⚠️ NUNCA vaciar (DELETE masivo / TRUNCATE) tablas madre.** Las tablas madre contienen datos maestros que alimentan tablas derivadas via triggers. Vaciarlas rompe toda la cadena de sincronizacion. Tablas madre protegidas: `SP Kg`, `SC Kg`, `SectorPlasticos`, `Matrices`, `Articulos Virgilio X Tallerista`, `Partes x PS`. Si el usuario pide vaciar alguna, ADVERTIR el impacto antes de ejecutar.

Orden de busqueda de `resolver_pesos_por_sector`: SP Kg → SC Kg → SectorPlasticos → Flejes → Remaches SP → Remaches SC (LIMIT 1, el primero que encuentre gana).

### Cadena de Talleristas

```
TABLA MADRE: Articulos Virgilio X Tallerista (Tallerista, Cod_Art, Desc)
DERIVADA:    Partes x Tallerista (se reconstruye por trigger INSERT/UPDATE/DELETE)
VISTAS:      v_piezas_por_tallerista → v_piezas_por_tallerista_resumen
```

### Cadena de Produccion

```
TABLA MADRE: Matrices (N_Matriz, Tiempo_Historico)
DERIVADA:    db_n8n_espejo → Segundos_Historico, Premio (via RPC recalcular_matriz)
AUDITORIA:   Matrices_audit (trigger fn_audit_matrices)
```

### Tablas de Movimientos (NO son derivadas, se escriben directamente)

| Tabla | Modulo que escribe |
|---|---|
| Envios a PS | Control PS, Facturas (carga manual) |
| Entregas PS | Control PS, Facturas (carga auto/manual) |
| Envios a Talleristas | Envio Talleristas |
| Entregas Tallerista Virgilio | Recepcion Cervantes/Virgilio |
| db_n8n_espejo | App Produccion, n8n |

### Partes x PS (tabla de configuracion, se modifica directamente)

Al modificar SC o SP en `Partes x PS`:
1. Verificar que el nuevo sector exista en SP Kg y/o SC Kg con sus pesos
2. Si no existe, CREARLO en la tabla madre antes de hacer el cambio
3. Revisar impacto en: Control PS, Stock SC, Stock SP, Stock Transito, Stock General, Plasticos

## Stack tecnologico

- Frontend: HTML/CSS/JS vanilla (sin framework)
- Backend/DB: Supabase (PostgreSQL) con JS client v2 desde CDN
- Auth: login.html + auth-guard.js con sessionStorage
- Tablas principales: `db_n8n_espejo`, `Empleados`, `Matrices`, `Registros Produccion Cervantes`
- Edge Functions: WhatsApp alertas, lectura facturas
- Server: Live Server en puerto 5501

## Estructura de carpetas

Cada modulo es una carpeta con su propio HTML/JS/CSS. Los modulos principales:
- `Produccion/` - Registro de produccion (app.js, maestro.html, abm.html)
- `Disruptivas/` - Producciones con premio anomalo (disruptivas.js)
- `Informes/` - Reportes
- `Inicio/` - Dashboard principal
- `Verificacion/` - Trazado de Rutas (REESCRITO 2026-04-18, ver abajo)

## Verificacion - Trazado de Rutas (reescrito 2026-04-18)

Modulo unificado para trazar rutas productivas y validar integridad. Reemplaza el viejo
sistema con multiples botones (Ejecutar Verificacion, Constructor, Rutas Nuevo, etc.)
por un unico flujo:

**Logica de trazado** (DFS desde cada Fleje):
1. Sigue `Causa-Efecto` (Descuenta -> Aumenta via Matriz). Si Matriz es nombre de
   tallerista (Carlos, Martin, "Martin, Carlos"), se trata como tallerista no matriz.
2. Sigue `Partes x PS` (SC -> PS via Proceso, devuelve SP). Agrupa PS que hacen mismo
   proceso al mismo SP (ej. "Daniel / Jade").
3. Termina en `Partes x Tallerista` cuando sector_proce coincide con un tallerista.
4. ST como SP devuelto (Sector Transito): muestra descripcion del paso anterior +
   nombres de PS en transito (ej. "Cuchilla Pelapapa Doblada + New Metal/FAAT").
5. Aumenta=Fabr indica fabricacion interna (terminacion de ruta).

**4 tabs**:
- Trazar Rutas: rutas nuevas pendientes de revision.
- Rutas Confirmadas: las que diste OK. Persistidas en tabla `Rutas_Confirmadas`.
- Revisar despues: marcadas con boton 📌 sin describir motivo. Tabla `Rutas_Problemas`
  con `problema = '(pendiente de revisar)'`.
- Problemas: reportadas con ⚠ y descripcion. Misma tabla, otro filtro.

**Tablas auxiliares** (creadas 2026-04-18):
- `Rutas_Confirmadas` (id, fleje, descripcion, ruta_json, firma UNIQUE, confirmado_por,
  confirmado_en).
- `Rutas_Problemas` (id, fleje, descripcion_fleje, ruta_json, firma, problema,
  estado pendiente|resuelto, reportado_por, reportado_en, resuelto_en).
- Firma = "F:<fleje>|tipo:label|tipo:label|..." sirve para deduplicar rutas iguales
  entre re-trazados.

**Reportes/auditorias**:
- `AUDITORIA_RUTAS_2026-04-18.md` (raiz proyecto): inconsistencias detectadas.

## Patron de armado de productos: GRJ (Garaje)

Los GRJ (GRJ1, GRJ7, GRJ9, GRJ10, etc.) son productos intermedios armados por talleristas
(generalmente Martin y/o Carlos). Cada GRJ tiene componentes que se descuentan al
entregarlo en `Recepcion Cervantes.html`.

Configuracion en 2 lugares (mantener sincronizadas):

1. **`Talleristas/Recepcion/Recepcion Cervantes.html`**:
   - `GRJ_COMPONENTES = { GRJ7: ["A10","C10","V9"], GRJ10: ["Fleje31","Fleje32","LLF7B","LLF8"], ... }`
   - `GRJ_PESOS = { GRJ7: 0.033567, GRJ10: 0.068882, ... }`
   - `ARTICULOS_EMPRESA = { CARLOS: { LK: ["GRJ7","GRJ9","GRJ10"] }, MARTIN: ... }`

2. **Supabase**:
   - `Articulos Virgilio X Tallerista`: una fila por (Tallerista, Cod_Art=GRJX, Desc=componente)
   - `SP Kg`: el GRJ como Sp con peso total
   - `Despiece x Articulo`: el GRJ aparece como Sector Proce en el cod_art final

**Pendiente al 2026-04-18**: GRJ16 (Batidor Mini 580) creado en SP Kg pero falta
componentes/CE/asignacion (ver AUDITORIA_RUTAS_2026-04-18.md punto 7).

## Causa-Efecto: convenciones

- `Descuenta` y `Aumenta` deben ser sectores conocidos o "Fleje N" o "Mat N".
- `Matriz` puede ser:
  - Numero (ej. "62"): se renderiza como "Matriz 62" y busca su nombre en `Matrices.N_Matriz`.
  - Nombre de tallerista (ej. "Carlos", "Martin, Carlos"): el JS de trazado lo reconoce y
    lo pinta como 👷 tallerista (no como ⚙️ matriz).
  - "Fabr": fabricacion interna (sin tallerista ni matriz especifica).
- **NO usar formato "Matriz N" en Descuenta/Aumenta** — usar "Mat N" para que el sistema lo
  trate como nodo intermedio. Si aparece "Matriz N" como nodo, son inconsistencias (ver
  AUDITORIA_RUTAS_2026-04-18.md punto 5).

## OC Insumos (GP2) - CONSTRUIDO 2026-08-29

**Las reglas de pedido por tipo de insumo estan en `REGLAS_OC_INSUMOS.md` (raiz) y
parametrizadas en `GP2.carton_formato` / `carton_categoria` / `proveedor_insumo.modo_control`.
Leer ese archivo antes de tocar el modulo de OC.**

- **El modulo existe**: `Compras/OC_GP2.html` genera las OC con
  **sugerido = maximo - stock** (desde el 2026-09-03; ANTES era consumo x meses y la doc
  quedo desactualizada un dia; el "- pendiente OC" se saco el 2026-09-04 por pedido del usuario,
  "por ahora borralo": `oc_bundle` hoy NO resta lo que ya viene en camino). El `maximo` sale de
  `inventario.maximo`, y **solo si esta vacio** cae al consumo (Est Madre explotada:
  `v_consumo_componente` / `v_consumo_fleje_kg` en kg para flejes) x meses, marcado
  `maximo_origen='consumo_x_meses'`. **Asi se decidio y asi se queda** [usuario 2026-09-04:
  "llena el lugar (maximo segun norma de cada rubro)"]: el sugerido llena el maximo, y la
  norma del rubro (multiplos y minimos de carton, paquetes de 100 en pliegos, piso de
  bolsas, paquetes de Charcas — `parametro.charcas_kg_x_paquete`, hoy 10 kg; la OC se guarda
  en kg) se aplica DESPUES, redondeando para arriba.
  Primero el lugar, despues el envase. Tablas `GP2.orden_compra` / `orden_compra_item`,
  RPCs `oc_bundle` / `crear_oc` / `oc_marcar` / `abm_bom_guardar`. Cada OC se puede IMPRIMIR
  (hoja limpia para el proveedor). Estados: borrador -> enviada -> recibida / anulada.
- **La recepcion CRUZA contra OC**: `crear_recepcion_insumo` aplica lo recibido al campo
  `recibido` de las OC abiertas (FIFO, conversion kg/uni) y marca la OC `recibida` sola.
  La pantalla de Recepcion muestra el cruce.
- **La validacion de cartones (multiplos C/LOKE/8) esta VIVA** (verificado 2026-09-08): los 110
  cartones tienen `componente.carton_formato` y el tipo C ya tiene `carton_categoria` cargada
  (Abrelatas 6, Pelapapas 4, Resto 16, Sacacorchos 6). Familia = formato+marca+categoria,
  multiplos, minimo por codigo, comodin sacacorchos, pliegos de 100 y piso de bolsa 20.000
  funcionan y los cubre `test_oc.js`. (Hasta el 2026-09-08 esta linea decia que estaba DORMIDA
  "hasta que el usuario asigne el formato": era falso y hacia perder tiempo.)
- El viejo `StockFlejes/recepcion.html` (importar PDF del proveedor) es del programa viejo;
  el flujo GP2 no importa PDFs.

## Reglas para trabajar en este proyecto

- ANTES de tocar tablas madre, leer LOCKS.txt, registrar LockX.
- Triggers de sincronizacion: ver Tablas_Madre_y_Dependencias.xls.
- ST como sector SC en Partes x PS = Sector Transito (PS recibe pero no devuelve SP final,
  se manda al siguiente PS). Es valido pero el codigo "ST" se usa en muchos contextos —
  no asumir descripcion generica.

## Supabase

- URL: `https://hrxfctzncixxqmpfhskv.supabase.co`
- La tabla `db_n8n_espejo` es la principal de produccion. Campos clave:
  - `Legajo`, `Matriz`, `Nombre_Matriz`, `Uni`, `Fecha`
  - `Hora_Inicio`, `Hora_Fin`, `Segundos_Trabajados`, `Segundos_Tiempo_Muerto`
  - `Segundos_Historico`, `Premio`, `Tiempo_Toma`, `Tiempo_Historico`
  - `Eliminar` (soft delete = 'S'), `Revisado`, `Anular_Tiempo`
  - `ID_Ejecucion`, `Dia`, `Mes`
- La tabla `Empleados` tiene campo `Activo` (valor "SI" para activos)
- La tabla `Matrices` tiene `N_Matriz`, `Matriz` (nombre), `Tiempo_Historico`
