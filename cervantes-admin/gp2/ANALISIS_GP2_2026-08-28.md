# Analisis general del schema GP2 — 2026-08-28

> **Analogia base:** GP2 es la **casa nueva** que se esta construyendo al lado de
> **Gestion Productiva Entero** (la casa vieja, en produccion). Este informe compara
> las dos casas habitacion por habitacion, dice que partes de la casa nueva ya tienen
> luz y agua, y en que orden conviene terminar el resto.

---

## 0. Resumen ejecutivo

| | Casa vieja (Entero) | Casa nueva (GP2) |
|---|---|---|
| Tablas / vistas que toca el front | **69** (schema `public`) | **22** (schema `GP2`) |
| Donde vive la logica | En el JS de cada modulo | En **43 funciones SQL** del schema |
| Como lee un modulo | 5–15 `.from('Tabla')` + joins a mano en JS | **1 sola llamada**: `SB.rpc('<modulo>_bundle')` |
| Como calcula stock | Cada modulo rehace la cuenta (`inicial + compras − envios + entregas…`) | Tabla `inventario`, mantenida por trigger |
| Modulos HTML | ~61 paginas | **7** tocan GP2, **6** realmente conectadas |

**Diagnostico corto:** la estructura de la casa nueva esta bien pensada y los maestros
ya estan cargados (515 componentes, 84 articulos, 555 rutas, 2.346 pasos de ruta,
892 filas de inventario). Lo que falta es **la instalacion electrica**: de las 43
funciones que ya existen en la base, **solo 6 estan enchufadas a una pantalla**. Las
tablas transaccionales estan practicamente vacias (`movimiento` 7 filas, `produccion` 3,
`recepcion_insumo` 2, `pedido` 0), o sea: **GP2 hoy se puede mirar, pero todavia no se
puede operar**.

---

## 1. Como funciona GP2 (arquitectura en 3 capas)

### Capa 1 — Datos (22 tablas)

| Tabla | Filas | Rol |
|---|---:|---|
| `sector` | 12 | Tipos de sector: crudo, procesado, transito, afilado, fleje, plastico, bombilla, remache, garage, carton, caja, terminado |
| `ubicacion` | 32 | **Donde puede estar el stock**: sector propio, proveedor de servicio o tallerista. Trae `meses` = cobertura objetivo |
| `componente` | 515 | **Todo lo que se stockea**: cod, descripcion, sector, unidad de medida, kg_x_uni |
| `articulo` | 84 | Producto terminado: cod, familia, caja, uni_x_caja, `estadistica` (consumo/venta mensual) |
| `articulo_componente` | 505 | BOM articulo → componente (cantidad por unidad) |
| `componente_bom` | 32 | Sub-BOM componente → componente (los **GRJ** y armados intermedios) |
| `ruta` / `ruta_paso` | 555 / 2.346 | **Ruta productiva completa ya calculada**, paso a paso y ordenada |
| `inventario` | 892 | (componente × ubicacion) → `cant`, `min` |
| `movimiento` | 7 | **Libro unico de movimientos** (el corazon del sistema) |
| `matriz` | 115 | Matrices con `n`, descripcion, tipo, `ppk`, `primera` |
| `produccion` | 3 | Registro de produccion |
| `tallerista` / `tallerista_alias` | 12 / 8 | Talleristas + sus nombres alternativos |
| `proveedor_servicio` / `..._alias` | 8 / 6 | PS + sus nombres alternativos |
| `fleje_detalle` | 50 | Datos extra de flejes (proveedor, medida, cod ISIS) |
| `recepcion_insumo` | 2 | Compras de insumo |
| `familia` | 18 | Familias de articulo |
| `pedido` | 0 | Ordenes de compra nativas (**vacia**) |
| `_bak_ruta_paso_transitos`, `_bak_maxcomp_transitos` | 2.346 / 1 | Backups de una migracion — basura a limpiar |

### Capa 2 — Logica (43 funciones SQL)

- **Lectura — 24 `*_bundle()`**: cada una devuelve **un solo `jsonb`** con todo lo que
  una pantalla necesita. El front hace `Object.assign(D, r.data)` y renderiza.
  Ejemplo real del contenido de `movimientos_bundle`:
  `sect`, `ubic`, `art`, `comp`, `prov_serv`, `tall`, `mat`, `bom_art`, `bom_comp`,
  `rp` (rutas), `inv`, `c2a` (componente → articulo).
- **Escritura — 9 funciones**: `crear_envio_ps`, `crear_entrega_ps`,
  `crear_envio_tallerista`, `crear_recepcion_insumo`, `registrar_produccion`,
  `registrar_movimientos`, `abm_articulo_upsert`, `abm_articulo_baja`,
  `fleje_detalle_upsert`.
- **Triggers — 4**: `fn_movimiento_calc` + `fn_movimiento_aplicar` (un INSERT en
  `movimiento` actualiza `inventario` solo), `fn_espejo_produccion` y
  `fn_espejo_entrega_tallerista` (aparentan ser el **puente GP2 → tablas viejas**).
- **Helpers — 6**: `to_canonical` (convierte kg/cajon/millar a unidad canonica),
  `inv_delta`, `_es_sector_insumo`, `partes_por_ps`, `partes_por_tallerista`.

### Capa 3 — UI

Identica al entero (HTML/JS vanilla, sin build), con **un solo cambio**:

```js
createClient(URL, ANON_KEY, { db: { schema: 'GP2' } });
...
const r = await SB.rpc('programa_bundle');   // 1 llamada, no 12
Object.assign(D, r.data);
```

---

## 2. Mapa de traduccion: casa vieja → casa nueva

Esta es la tabla mas util del informe. **Antes de tocar cualquier modulo de GP2,
buscar aca de donde viene.**

| Entero (`public`) | GP2 | Que se gano |
|---|---|---|
| `SP Kg`, `SC Kg`, `SectorPlasticos`, `Flejes`, `Remaches SP`, `Remaches SC`, `Garage`, `Cajas`, `Sector Carton`, `Sector Bombilla` | **`componente`** + `sector` + `fleje_detalle` | 10 tablas de pesos → 1. Se elimina el orden de busqueda de `resolver_pesos_por_sector` (SP Kg → SC Kg → Plasticos → Flejes → Remaches, "el primero que encuentre gana") |
| `Despiece x Articulo`, `Partes x Tallerista` | **`articulo_componente`** | Desaparece la cadena madre→derivada con triggers de sincronizacion de pesos |
| `GRJ_COMPONENTES` / `GRJ_PESOS` **hardcodeados en `Recepcion Cervantes.html`** | **`componente_bom`** | Los GRJ dejan de vivir en dos lugares que hay que mantener sincronizados a mano |
| `Causa-Efecto` + `Partes x PS` + el DFS de `verificacion.js` (40 KB de JS) | **`ruta` + `ruta_paso`** | El trazado se calcula **una vez en la base**; `Verificacion_GP2.html` son 10 KB |
| `Envios a PS`, `Entregas PS`, `Envios a Talleristas`, `Entregas Tallerista Virgilio`, `StockMovimiento`, `Recepcion_Insumos`, `Ajustes Online PS` | **`movimiento`** (+ `recepcion_insumo`) | Un solo libro mayor. Todo movimiento de stock tiene la misma forma |
| Stock recalculado a mano en 6 modulos | **`inventario`** (via trigger) | Un solo numero de stock, imposible que dos pantallas discrepen |
| `Matrices` (+ `Matrices_audit`) | **`matriz`** | — |
| `db_n8n_espejo` | **`produccion`** | — |
| `E. Madre LK` / `E. Madre CH` | **`articulo.estadistica`** | Deja de ser tabla aparte por linea |
| Nombres sueltos: `"Martin, Carlos"`, `"Daniel / Jade"`, `"Maspoli 2"`, `Renombres_Sectores.md`, `Codigos_ISIS_Map` | **`tallerista_alias` / `proveedor_servicio_alias`** | Los alias son datos, no reglas escondidas en el codigo |
| `Ordenes_Compra` (importadas de PDF) | **`pedido`** (vacia) | Es exactamente el "FUTURO" que declara `CLAUDE.md`: OC generadas por el sistema |

**Sin equivalente todavia en GP2** (ver seccion 4): `Empleados`, `Rutas_Confirmadas`,
`Rutas_Problemas`, `partes_excluidas_por_tallerista`, `cajas_excluidas_por_tallerista`,
`Proveedores`, `Precios_Proveedores`, `Preavisos`, `Pendientes`, `Control_Carga_Remitos`,
`Relevamientos_Cajas`, `Entrevistas`, `Proporcion_Articulo_Tallerista`,
`Tall_ProvAT_PS`, `peso_cajones`.

---

## 3. Que esta enchufado hoy

| Funcion SQL en GP2 | Pantalla que la usa | Estado |
|---|---|---|
| `programa_bundle` | `Programa/Programa.html` | ✅ vivo |
| `faltantes_bundle` | `Faltantes/Faltantes.html` | ✅ vivo |
| `verificacion_bundle` | `Verificacion/Verificacion_GP2.html` | ✅ vivo |
| `despiece_bundle` | `Despiece x Articulo/Despiece_GP2.html` | ✅ vivo |
| `produccion_bundle` | `Produccion/rendimiento_GP2.{html,js}` | ✅ vivo |
| — (INSERT directo a `movimiento`) | `Movimientos/Registrar_Movimiento.html` | ⚠️ **escribe vivo, lee congelado** |
| `movimientos_bundle` | *nadie* | ❌ |
| `stock_bundle` | *nadie* | ❌ |
| `inicio_bundle` | *nadie* | ❌ |
| `alertas_bundle` | *nadie* | ❌ |
| `control_ps_bundle` | *nadie* | ❌ |
| `control_talleristas_bundle` | *nadie* | ❌ |
| `envios_tallerista_bundle` | *nadie* | ❌ |
| `entregas_tallerista_bundle` | *nadie* | ❌ |
| `faltante_partes_tallerista_bundle` | *nadie* | ❌ |
| `proporciones_bundle` | *nadie* | ❌ |
| `flejes_bundle` | *nadie* | ❌ |
| `recepcion_insumos_bundle` | *nadie* | ❌ |
| `abm_articulos_bundle` + `abm_articulo_upsert/baja` | *nadie* | ❌ |
| `produccion_maestro_bundle` | *nadie* | ❌ |
| `informes_bundle`, `informes_matriz_bundle` | *nadie* | ❌ |
| `disruptivas_bundle` | *nadie* | ❌ |
| `verifmadres_bundle` | *nadie* | ❌ |
| `partes_por_ps`, `partes_por_tallerista` | *nadie* | ❌ |
| `crear_envio_ps`, `crear_entrega_ps`, `crear_envio_tallerista`, `crear_recepcion_insumo`, `registrar_produccion`, `registrar_movimientos` | *nadie* | ❌ |

**El trabajo pendiente no es de base de datos, es de front-end.** La base ya sabe
responder casi todas las preguntas; no hay pantallas que se las hagan.

---

## 4. Problemas concretos detectados

### 4.1 Movimientos lee una foto vieja — **prioridad maxima**
`Movimientos/Registrar_Movimiento.html` pesa **388 KB** porque tiene un volcado JSON
congelado del schema (`var D={"sect":…}` con 471 componentes, 848 filas de inventario,
555 rutas). Escribe en vivo (`SB.from('movimiento').insert(...)`) pero lee de esa foto.
Consecuencia: **cada movimiento que se carga vuelve mas vieja la foto**, y las
sugerencias/validaciones que muestra la pantalla se desalinean del stock real que ella
misma acaba de mover. La funcion `movimientos_bundle()` ya existe para arreglarlo.

### 4.2 `registrar_movimientos()` esta muerta
Existe una RPC transaccional para grabar movimientos en lote, pero el front hace INSERT
directo a la tabla. Funciona (los triggers aplican igual), pero se pierde la validacion
y el manejo de errores que la RPC presumiblemente hace. Hay que decidir: **usar la RPC o
borrarla**, no dejar las dos.

### 4.3 No existe `empleado`
El propio codigo lo dice: *"No existe tabla Empleados en GP2: el nombre del operario
viene embebido en produccion."* Sin tabla de empleados no hay `Activo`, no hay legajo
canonico, y todo lo que dependa de operarios (maestro, tiempos, informes, disruptivas,
premios) queda a medias.

### 4.4 Verificacion no puede guardar el resultado
El modulo viejo persiste el trabajo humano en `Rutas_Confirmadas` y `Rutas_Problemas`
(confirmar ruta, marcar problema, "revisar despues"). `verificacion_bundle` solo **lee**
`ruta`/`ruta_paso`. Migrar Verificacion sin esas dos tablas **hace perder el historial de
revision**, que es justamente el valor del modulo.

### 4.5 Falta el circuito de talleristas del lado escritura
Hay `crear_envio_tallerista`, pero **no hay `crear_entrega_tallerista`** — o sea, el
flujo mas usado del sistema (Recepcion Cervantes / Recepcion Virgilio, con GRJ y
descuento de componentes) no tiene puerta de entrada en GP2. Tampoco hay equivalente de
Devolucion Cervantes ni de Prov. Art. Terminado (Envios/Entregas/Control).

### 4.6 Doble verdad sin regla escrita
`fn_espejo_produccion` y `fn_espejo_entrega_tallerista` sugieren que **algunos** flujos
de GP2 se espejan a las tablas viejas — pero solo 2 de N. Mientras convivan las dos
casas hace falta una regla explicita por flujo: *quien manda, quien espeja, y en que
direccion*. Sin eso, el dia que alguien opere en las dos, los numeros se separan.
*(No pude leer el cuerpo de los triggers: las consultas SQL de introspeccion quedaron
bloqueadas por aprobacion de herramienta. **Verificar antes de confiar en este punto.**)*

### 4.7 Suciedad y riesgos menores
- `_bak_ruta_paso_transitos` (2.346 filas) y `_bak_maxcomp_transitos` viven en el schema
  productivo. Mover a otro schema o dropear.
- `fleje_detalle_upsert` esta **duplicada** (una de 6 args y otra de 8). PostgREST
  resuelve por nombre de argumento, pero es una bomba de tiempo. Dejar una sola.
- La **anon key** y el schema `GP2` estan en el HTML de cada pantalla. Es el mismo patron
  del entero, pero como GP2 va a concentrar *todo* el stock en dos tablas
  (`inventario`, `movimiento`), conviene **verificar RLS y grants** antes de que entre en
  produccion. *(Tampoco pude verificarlo — consulta bloqueada.)*
- `LOCKS.txt` acumula 187 KB de `[HISTORIAL]` cuando `CLAUDE.md` dice "mantener max 10".

---

## 5. Plan sugerido para "hacer andar" GP2

Ordenado por dependencia, no por dificultad. Cada paso deja algo usable.

**Paso 0 — Congelar el contrato.** Documentar en un `GP2_MAPA.md` la forma de cada
`*_bundle` (hoy solo se deduce leyendo el JS). Sin esto, cada pantalla nueva se escribe
adivinando.

**Paso 1 — Arreglar Movimientos.** Reemplazar el volcado de 388 KB por
`await SB.rpc('movimientos_bundle')` y decidir INSERT-directo vs `registrar_movimientos`.
Es el corazon: **todo el stock de GP2 depende de esta pantalla**.

**Paso 2 — Cerrar el circuito de stock.** Las RPC de escritura ya existen; falta UI:
`crear_recepcion_insumo` (compras), `crear_envio_ps` / `crear_entrega_ps`,
`crear_envio_tallerista`, y **crear la que falta**: `crear_entrega_tallerista`.
Recien con esto `movimiento` e `inventario` empiezan a tener datos reales.

**Paso 3 — `stock_bundle` → pantalla unica de stock.** De un saque reemplaza StockSC,
StockSP, StockTransitoPS, Stocks General, StockFlejes y StockMovimiento. Es el mayor
retorno por hora de trabajo de todo el plan.

**Paso 4 — Tabla `empleado`.** Crearla, apuntar `produccion.legajo`, y recien despues
migrar maestro / tiempos / informes / disruptivas.

**Paso 5 — Talleristas y PS completos.** `control_talleristas_bundle`,
`control_ps_bundle`, `envios_tallerista_bundle`, `entregas_tallerista_bundle`,
`faltante_partes_tallerista_bundle`, `proporciones_bundle`. Aca hay que resolver las
exclusiones por tallerista (`partes_excluidas_por_tallerista`), que hoy no tienen lugar.

**Paso 6 — Verificacion completa.** Agregar `ruta_confirmada` y `ruta_problema` y migrar
el historial existente. Sin esto no se puede apagar el modulo viejo.

**Paso 7 — `pedido` (OC nativas).** Es el objetivo declarado en `CLAUDE.md`: dejar de
importar PDFs y que el sistema decida que comprar. GP2 ya tiene lo necesario
(`inventario.min`, `ubicacion.meses`, `articulo.estadistica`) — es la funcionalidad que
**la casa vieja no puede dar** y que justifica la mudanza.

**Paso 8 — Limpieza.** Dropear `_bak_*`, unificar `fleje_detalle_upsert`, revisar RLS,
podar `LOCKS.txt`.

---

## 6. Como validar cada paso (regla de paridad)

Para cada modulo migrado, antes de darlo por bueno:

1. Abrir el modulo **viejo** y el **nuevo** con el mismo filtro (mismo dia, mismo
   articulo, mismo tallerista).
2. Comparar los totales de las columnas que importan (stock, kg, unidades, faltante).
3. Criterio de aceptacion: **diferencia cero, o diferencia explicada por escrito**.
4. Recien ahi se apaga el boton viejo en `Inicio/index.html`.

Esta regla es la traduccion practica de la analogia: **no se demuele una habitacion de la
casa vieja hasta que la equivalente en la casa nueva da el mismo numero.**

---

## Nota de alcance

Este informe se armo con: inventario de tablas y conteo de filas de `GP2`, listado
completo de sus 43 funciones, lectura de los 7 modulos del repo que apuntan a GP2, y el
volcado JSON embebido en `Registrar_Movimiento.html` (que revela la forma exacta de un
bundle). **No se pudo inspeccionar**: columnas y foreign keys detalladas, cuerpo de las
funciones y triggers, y estado de RLS/politicas — las consultas de introspeccion
quedaron bloqueadas por aprobacion de herramienta a mitad del analisis. Los puntos 4.6 y
4.7 estan marcados como *a verificar* por ese motivo.
