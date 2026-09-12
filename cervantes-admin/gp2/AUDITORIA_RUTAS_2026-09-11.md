# Auditoría de rutas completas y de la base — 2026-09-11

**Pedido**: comprobar que cualquier artículo pueda recorrer todo su circuito productivo dentro de
GP2, corregir lo que lo corte, y de paso normalizar la base.

**Método**: no se leyó el código y se opinó. Se armó un arnés dentro de la base
(`"GP2".__sim_ruta` y `"GP2".__sim_articulo`, documentados en `GP2_MAPA.md`) que recorre cada ruta
**llamando a las RPC de producción de verdad** — `crear_recepcion_insumo`, `registrar_produccion`,
`crear_envio_ps` + `crear_entrega_ps`, `crear_envio_tallerista` + `crear_entrega_tallerista`,
`crear_envio_prov_at` + `crear_entrega_prov_at`, `recepcion_virgilio` — y termina con una excepción
centinela que **revierte todo**: no quedó escrito un solo movimiento de prueba (verificado contra el
conteo de `movimiento`, `recepcion_insumo`, `produccion`, `orden_compra` y `entrega_prov_at` antes y
después de cada barrido). Cuando un paso `insumo` pide algo que no se compra, el arnés simula
primero la ruta que lo produce, hasta 3 niveles.

---

## 1. Qué se probó

| | |
|---|---|
| Artículos | **189** |
| Rutas (ramas) | **861** |
| Pasos de ruta | 3.293 |
| Ruta más larga | 10 pasos |
| Receta más grande | 13 partes |

**Las cinco formas de ruta que existen en GP2, todas ejercitadas:**

| Forma | Artículos | Rutas |
|---|---|---|
| Completo: fleje → matriz → prov. servicio → tallerista | 69 | 504 |
| Insumo → tallerista | 59 | 165 |
| Comprado terminado (Prov. Art. Terminado) | 39 | 76 |
| Insumo → prov. servicio → tallerista | 18 | 78 |
| Fabricado: fleje → matriz → tallerista | 4 | 25 |

Cubre lo pedido: proveedor de insumos, proveedor de servicios, tallerista, proveedor de artículo
terminado, producción interna, productos con muchos componentes, componentes que convergen, rutas
de varias etapas, comprados terminados, fabricados completos y mixtos externo/interno.

## 2. Resultado

| | Antes | Después |
|---|---|---|
| Rutas que llegan hasta Virgilio | 719 de 861 | **861 de 861** |
| Artículos con alguna rama cortada | 66 | **0** |
| Suite de UI | 46/46 | **48/48** (2 tests nuevos) |
| Invariantes de `db/verificar.sql` | 1 en rojo | **0** (y 4 reglas nuevas) |

**Prueba de conservación** (`__sim_articulo`: todas las ramas + UNA entrega): los **189** dejan
exactamente las 120 unidades simuladas en Virgilio. 122 cierran perfecto (cada contraparte queda en
cero). El resto deja material colgado, casi todo por intermedios que el arnés simula rama por rama;
los descuadres **reales** de receta contra ruta son 7 artículos, en la idea **7324**
(re-contados el 2026-09-12: son **10** — ver la idea, que es la fuente al día).

---

## 3. Los cinco cortes, y qué enseña cada uno

### 3.1 La entrega del Prov. Art. Terminado no tocaba el stock — 38 artículos, 75 rutas

`crear_entrega_prov_at` sólo insertaba en `entrega_prov_at`, un **segundo libro** paralelo a
`movimiento`. Consecuencias: el artículo comprado terminado **nunca entraba al inventario de
Virgilio** (el paso 13 del circuito no ocurría para 1 de cada 5 artículos) y el cartón y la caja que
se le mandan al proveedor con `crear_envio_prov_at` **no se consumían nunca**: su stock en la
ubicación del proveedor crecía sin techo.

**Corrección**: `crear_entrega_prov_at` delega en `recepcion_virgilio(origen_tipo='proveedor_at')`,
que es el **mismo motor** que ya cierra la ruta del tallerista y consume la **receta completa** del
artículo desde la ubicación del proveedor. No se inventó un motor nuevo ni palabras nuevas de
`tipo_mov`: usa `recepcion_virgilio` / `consumo_virgilio`, así que ninguna pantalla tuvo que
aprender nada.

Verificado con el artículo 575: entran 120 cartones y 10 cajas, se consumen exactamente, salen 120
artículos a Virgilio, y **el único delta en toda la base es ese +120**.

### 3.2 Las piezas importadas no se podían recepcionar — 16 artículos, 17 rutas

`C13`, `D1`, `Z23A` y `Z23B` se **compran hechas** pero viven en Sector Procesado. "Qué se puede
comprar" se decidía por el **sector**, así que no aparecían en la pantalla de Recepción ni las
aceptaba la RPC: esas rutas no podían ni empezar.

**Corrección**: la regla es una propiedad del **componente**, no del sector —
`_es_comprable(comp_id)` = sector de insumo **o** `estado_compra='importado'` **o** lo entrega un PS
híbrido. La usan `crear_recepcion_insumo` y `recepcion_bundle` (que además tenía los dos PS
híbridos hardcodeados por nombre). En la pantalla de Recepción hay un rubro **Importados**.

### 3.3 La entrega de PS sólo aceptaba kilos — 18 rutas

Los 11 `Pliego Ad` (el adhesivado de AJ Adhesivos), `C12` y `V18D` **se cuentan, no se pesan**, y no
tienen `kg_x_uni`: `to_canonical` cortaba y la entrega era imposible. **No era un dato faltante**:
un pliego adhesivado se entrega en unidades y la API no tenía forma de decirlo.

**Corrección**: `crear_entrega_ps` recibe `p_unidad` (default `'kg'`, así que las pantallas que
pesan no cambian), `envios_ps_bundle` expone `sp_um` y `sp_kgxuni`, y la pantalla marca la fila
«se cuenta: cargar UNIDADES» con teclado numérico.

### 3.4 Blist-Pack SA quedó sin ubicación de stock — artículos 555 y 764

El alta del tallerista (2026-09-11) no creó su fila en `ubicacion`, así que `ubic_de` devolvía null
y `crear_envio_tallerista` abortaba.

**Corrección estructural**: trigger `fn_ubicacion_de_contraparte` sobre `tallerista`,
`proveedor_at`, `proveedor_servicio` y `sector`: **toda contraparte nueva nace con su ubicación** si
`ubic_de` no la resuelve. Antes sólo `alta_proveedor_servicio` lo hacía y cualquier alta por
migración lo salteaba.

### 3.5 Cinco entregas de Prov AT rechazadas con un mensaje falso

La función usaba la **descripción** del catálogo como chequeo de existencia. Cinco filas la tenían
vacía (193, 231, 232, 233, 591) y la entrega se rechazaba diciendo «el artículo no está asignado a
ese proveedor», que era mentira. Ahora se chequea por existencia de la fila y la descripción cae a
`articulo.descripcion`; además se completaron las 4 que tenían artículo en GP2 (copiando la del
artículo, sin inventar).

---

## 4. Números que no cerraban entre pantallas

| Qué | Cuánto estaba mal | Corrección |
|---|---|---|
| **Costo de los plásticos** | `2465` Alto Impacto **+34,5 %** (5.433,90 vs 4.040 $/kg), `2425` PS HF555 **+23,2 %**, `2455` ABS y `2485` Nylon c/Carga también | Había **dos reglas** del "precio vigente": la OC usa el proveedor asignado al componente, `v_costo_componente` sólo ordenaba por fecha e id — con empate de fecha ganaba el último cargado. Ahora la vista usa el mismo desempate. **Verificado: los 6 plásticos dan idéntico en la OC y en Valorización** |
| **"Pedido para llegar al máximo"** | **54 de 342** componentes daban distinto entre la OC y Valorización (A11: 32.417 vs 52.227) | Estaba definido dos veces sobre universos distintos de inventario: una tomaba la ubicación de reposición, la otra sumaba todas y arrastraba los stocks negativos de talleristas y PS. Ahora es una sola vista, `v_reposicion`. **Los 342 coinciden** |
| **Prorrateo de faltantes** | **59 pares** (artículo, componente) mal; `IF2` en el 504 consume 8,067 por unidad y el JS usaba **1** | El navegador reimplementaba la explosión de la Est Madre y le ponía cantidad 1 a todo intermedio de ruta. Ahora sale de `v_consumo_demanda` por `faltantes_bundle.aporte` |
| **Columnas de Stock por Sector** | **5 columnas** sumaban por palabras que la base nunca escribe (`produccion`, `envio_prov`, `envio_tall`, `recepcion_prov`, `recepcion_tall`): daban 0 para siempre. Faltaban `envio_prov_at` y los 2.040 uni de `recepcion_virgilio`/`consumo_virgilio` del Sector Procesado | El vocabulario pasó de CHECK a **tabla** (`GP2.tipo_movimiento`, con FK desde `movimiento`), los bundles la sirven en `tipos_mov`, y `test_vocabulario_mov.js` rechaza cualquier palabra inventada en el JS |
| **Control AT** | **18 códigos** salían "ambiguos" sin unidades; los ambiguos de verdad son **9** | La pantalla indexaba `uni_x_articulo_x_caja` sólo por código y mezclaba Chef con Loeke. Ahora usa la clave completa |

---

## 5. Cambios en la base

**Nada se borró.** Ni una tabla, ni una columna, ni una fila de negocio.

**Estructuras nuevas**
- Tabla `tipo_movimiento` (19 filas): el vocabulario del ledger deja de ser un CHECK de literales y
  `movimiento.tipo_mov` pasa a tener **FK** contra ella. El contenido está versionado en
  `db/vocabulario_GP2.sql`, porque es parte del contrato con las pantallas.
- Vista `v_reposicion`: única definición de "dónde se repone cada componente". Verificada fila por
  fila contra el lateral que tenía `oc_bundle` (0 diferencias) antes de reemplazarlo.
- Funciones `_es_comprable(comp_id)`, `reprocesar_espejo_virgilio(ids, dry_run)`, el arnés
  `__sim_ruta` / `__sim_exec` / `__sim_articulo` y su tabla de apoyo `__sim_base`. Ninguna con
  EXECUTE para `anon` salvo `reprocesar_espejo_virgilio`.
- Trigger `fn_ubicacion_de_contraparte` sobre 4 tablas.

**Integridad** (todas con **0 filas en contra** antes de aplicarlas)
- **10 UNIQUE**: `articulo.codigo` (el más grave: todo el schema lo usa como clave de cruce y no
  tenía ninguno), `matriz.n_matriz`, `sector.nombre`, `tallerista.nombre`,
  `lower(btrim(proveedor_servicio.nombre))`, `proveedor_insumo.cod_prov` (sin él,
  `v_material_precio_proveedor` puede duplicar filas y romper el ranking del proveedor más barato),
  `articulo_componente(art, comp)`, `componente_bom(padre, hijo)`, `ruta_paso(ruta, orden)`
  *deferrable*, `planilla_snapshot(vigente)`, `orden_compra_item(oc, componente)`.
- **15 NOT NULL**, casi todos en `movimiento` e `inventario`: una fila de ledger con `comp_id` o
  `cantidad` en null pasaba el CHECK, entraba, y el trigger la procesaba con `_delta` nulo — una
  fila fantasma que rompe la conservación.
- **4 CHECK** de vocabulario: `sector.tipo` (el que `programa_bundle` serializa y con el que
  `Programa.html` elige el ícono de cada nodo), `empleado.tipo`, `matriz.tipo`, `componente.marca`.
- **7 FK**: `orden_compra.proveedor`, `recepcion_insumo.proveedor`, `produccion.legajo`,
  `rollo_evento.legajo`, `rollo_uso.legajo`, `entrega_prov_at(prov, cod_art)`, y la de
  `movimiento.tipo_mov`. Todas con `on update cascade`: el riesgo real era el **renombre** — hoy
  renombrar un proveedor cascadeaba a `componente` pero dejaba las OC y las recepciones apuntando al
  nombre viejo, en silencio.
- `registrar_movimientos` **valida**: cantidad > 0 (salvo `ajuste`, que puede ser negativo), al
  menos una ubicación, el mismo componente no entra y sale del mismo lugar (**pero sí si hay
  transformación**: una matriz convierte `I4` en `I6` sin sacar la pieza del Sector Crudo, y hay 2
  movimientos reales así), y `comp_transformado_id` va con `cantidad_transformada`. **Verificado
  contra los 421 movimientos existentes: ninguno sería rechazado.**

**Datos corregidos**
- 58 pasos de ruta que decían cantidad 1 cuando la receta decía otra cosa (47 cajas que pedían hasta
  36 veces de más, 7 flejes en kg, y 4 al revés: la receta pedía 2 y la ruta 1).
- 4 descripciones vacías del catálogo de Prov AT, copiadas del artículo.

**Documentación de modelo** (comentarios de columna, para que la próxima sesión no "arregle" un dato
que está bien): `uni_x_articulo_x_caja.descripcion` es una copia vieja que **nadie lee**;
`articulo_prov_at.descripcion` difiere a propósito (es el nombre con el que el proveedor factura);
`produccion.nombre_matriz` y `nombre_empleado` son snapshots deliberados; y el comentario de
`inventario.maximo` documentaba una fórmula muerta (la migración del 2026-08-30 quedó revertida —
pregunta 5, sin responder).

**Invariantes nuevos en `db/verificar.sql`**: `AA` (un paso de insumo no puede contradecir la
receta), `AB` (ninguna ruta arranca en el aire: lo que entra se compra o lo produce otra ruta),
`AC` (ningún `tipo_mov` fuera del catálogo). Más dos consultas informativas: la cola del espejo de
Virgilio y los 13 pares de receta sin rama.

---

## 6. Lo que queda pendiente y necesita al usuario

Están cargadas como ideas en `IDEAS-GP2.md` (se activan diciendo el código). Ordenadas por impacto:

| Código | Qué | Por qué no se hizo solo |
|---|---|---|
| **7313** | Reprocesar el espejo de Virgilio: **14 entregas, 7.692 unidades** que nunca entraron al stock (207 ×2, 395, 535 ×3, 735, 760, 817, 823, 856, 922, 943E, 945E) | Mueve stock de verdad. La RPC ya existe y corre **en seco** por defecto |
| **7324** | 7 artículos con una parte en la receta que ninguna rama les lleva. Incluye el **547, que tiene dos `A4`**: la Caja N°10 (bien) y el "Mgo Plano 501 Serig" del Sector Procesado con cantidad de caja — el código existe en los dos sectores | Es un DELETE sobre la receta y los otros 6 necesitan que el usuario diga quién manda qué |
| **7314** | 9 códigos de `uni_x_articulo_x_caja` con dos "unidades por caja" contradictorias (12 vs 24, 24 vs 36, 12 vs 60) | No hay forma de deducir cuál es el bueno |
| **7316** | "Entrega de tallerista" tiene **dos motores**: el JS (`gp2-motor.js`) y `crear_entrega_tallerista`, que **ninguna pantalla llama** y descuenta por `componente_bom`, que no tiene ni un artículo terminado | O la RPC pasa a ser el único motor o se borra: es una decisión de arquitectura |
| **7317** | `crear_oc` no valida **ninguna** regla de cartón: múltiplos, mínimos, pliegos de 100, piso de bolsa. Todo vive en `OC_GP2.html` y la RPC tiene EXECUTE para `anon` | Todavía no hay ninguna OC de cartón creada: es el momento, pero es un proyecto |
| **7320** | 141 filas de inventario en negativo (112 componentes, −255.375 uni) | Es el stock inicial de talleristas que nunca se cargó (pregunta 8.3). El libro y el inventario cierran exacto: no es un error del motor |
| **7315, 7318, 7319, 7321, 7322, 7323** | Copias de la conversión kg↔uni, `matriz.tipo` vs `maquina`, la marca `LOKE` viva en 10 artículos, `ruta_paso.cantidad` que nadie lee, el artículo sin FK a su componente terminado, y 9 entregas de Virgilio de códigos que GP2 no modela | Chicas o bloqueadas por una decisión |

## 7. Riesgos detectados

1. **`ubic_de_componente` manda a Virgilio cualquier sector sin ubicación.** El `coalesce` está
   pensado para los terminados (sector 12) pero atrapa a cualquier sector que no tenga la suya. Hoy
   no rompe nada (el único caso, `FLEJE90_BRUTO` del Sector Alambre, va por otro camino), pero es
   una mina: un sector nuevo sin ubicación manda su stock a Virgilio sin avisar.
2. **El artículo y su componente terminado sólo se relacionan por el paso `virgilio`.** Una ruta sin
   ese paso deja al artículo sin componente y el circuito no cierra (idea 7322).
3. **La pantalla de Entregas de Tallerista no cierra artículos**: excluye el sector 12 a propósito y
   `componente_bom` no tiene ningún terminado. El artículo se cierra cuando la entrega se carga **en
   Virgilio** y el espejo la cruza. Si Virgilio no la carga, no entra al stock — que es exactamente
   lo que dejó 23 entregas en la cola.

## 8. Cómo verificar todo esto

```sql
-- las 861 rutas, de punta a punta (no escribe nada)
with s as (select r.id, "GP2".__sim_ruta(r.id, 120) res from "GP2".ruta r)
select count(*) rutas, count(*) filter (where (res->>'ok')::boolean) ok from s;   -- 861 / 861

-- la prueba de conservación, artículo por artículo
with s as (select a.id, "GP2".__sim_articulo(a.id, 120) r from "GP2".articulo a)
select count(*) filter (where (r->>'ok')::boolean) cierran_perfecto from s;

-- lo que el espejo de Virgilio podría recuperar, sin escribir
select "GP2".reprocesar_espejo_virgilio(null, true);
```
Más `db/verificar.sql` entera (cada fila tiene que dar `n = 0`) y `bash tests/ui/run.sh` (48/48).

## 9. Trazabilidad

Los 12 problemas están en `github_repo_problemas` con su causa raíz y el commit donde se
arreglaron (11 corregidos, 1 abierto):

```sql
select titulo, estado, severidad, commit_sha from github_repo_problemas.v_problemas
 where sesion_id = 'session_019X2GnRcnZFv8xq8DJMHxuS' order by detectado_en;
```

---

# Segunda parte — lógica duplicada, permisos y normalización (misma fecha)

Con las 861 rutas ya cerrando, el trabajo siguió por el **objetivo 2**: sacar la lógica
repetida, cerrar los permisos y normalizar. Ocho commits, todos a `main`, suite en verde
antes de cada push.

## 10. Lo que se corrigió, por gravedad

| # | Qué estaba mal | Alcance medido | Cómo se verificó |
|---|---|---|---|
| 10.1 | 14 entregas del espejo de Virgilio nunca entraron al stock | **7.692 unidades**, movimientos 69922–69967 | Virgilio 67.616 → 75.308; invariante libro-vs-inventario en 0 |
| 10.2 | El artículo 547 tenía en la receta un mango que su ruta nunca produce | 1 línea (`A4` del Sector Procesado, 1/12) | El costo no se movió ($1.193,13); el 547 ahora cierra en la prueba de conservación |
| 10.3 | Cuatro funciones que **escriben** estaban al alcance de la clave pública | `planilla_cargar`, `planilla_snapshot_nuevo`, `reprocesar_espejo_virgilio`, `crear_entrega_tallerista` | invariantes C y M en 0 tras mover los 4 a la lista de internas |
| 10.4 | `crear_oc` no validaba **ninguna** regla de cartón | 10 funciones de JS que la RPC ignoraba | 13 casos comparados JS vs base, mensaje por mensaje |
| 10.5 | Ni el pedido mínimo en kg del proveedor de materia prima | 5 proveedores con mínimo (Indarnyl 400 kg el mayor) | 4 casos más, los 17 idénticos |
| 10.6 | «El componente terminado de este artículo» estaba definido dos veces | 189 artículos | `c2a` byte a byte igual; conservación 189/189 en 120 uni |
| 10.7 | La pantalla de Pintores dependía de la mayúscula de una palabra | 3 PS visibles, 14 de 15 filas fuera del catálogo | bundle idéntico; un PS nuevo en minúscula pasa de invisible a visible (3→4) |
| 10.8 | Seis proveedores de bombillas no hacían match con su sector | 6 de 47 | los 8 sectores devuelven la misma lista de proveedores byte a byte |
| 10.9 | La recepción tenía **dos** listas de insumos y sólo dibujaba una | 348 componentes | 0 diferencias contra `componente`; los tests dejan la consulta vieja en vacío a propósito |

## 11. El método que se repitió (y conviene repetir)

**Bajar una regla del navegador a la base sin romperla** — se usó dos veces (cartón y mínimo
del proveedor) y quedó como molde en `tests/ui/test_oc_reglas_js_vs_db.js`:

1. **Port literal, no reinterpretación.** Mismo orden de chequeos: en cartón, el
   `pedido_minimo` corta antes que el múltiplo de familia, y el múltiplo por código se mira
   antes que el mínimo por código (es un `else if` en el JS).
2. **Los mismos datos de los dos lados.** El test usa `comp_id` reales, así que el mismo caso
   corre en el navegador y en la base.
3. **El esperado sale de la base, no de la cabeza.** Los 17 esperados son la salida real de
   `select "GP2"._oc_validar_carton(...)` / `_oc_validar_minimo_proveedor(...)`.
4. **La pantalla no se toca.** Sigue avisando en vivo; la que manda es la de la base.

**Antes de revocar un permiso, mirar los `.md` de integración, no sólo el código.** Cinco RPC
que ninguna pantalla de este repo llama —`material_virgilio_bundle`, `oc_pendientes_virgilio`,
`enviar_material_virgilio`, `recibir_oc_virgilio`, `traslado_virgilio`— las llama un cliente
**externo** con la clave anon, y el contrato está en `INTEGRACION_GESTION_VIRGILIO.md`.
Revocarlas habría roto esa integración sin que ningún test se enterara.

**Cuando un dato es computable, la respuesta no es una columna nueva.** La idea 7322 pedía
`articulo.componente_terminado_id`; lo que hacía falta era **una sola puerta**
(`comp_terminado_de`), como `ubic_de` para las ubicaciones. Una columna habría sido la tercera
copia del mismo hecho.

## 12. Invariantes nuevos de esta segunda parte

| Invariante | Qué vigila | Hoy |
|---|---|---|
| `AD_articulo_sin_componente_terminado` | que todo artículo resuelva su componente terminado | 0 |
| `AE_paso_virgilio_y_codigo_dan_distinto` | que los dos criterios viejos sigan coincidiendo | 0 |
| `C` / `M` (ampliados) | las 4 funciones de mantenimiento fuera del alcance de `anon` | 0 / 0 |

Y dos **informativas** (no son invariantes: dan > 0 por datos que faltan):
`uni_x_caja_LK_contradice_articulo` = 1 (el 508: 6 en `articulo`, 12 en la otra tabla) y
`proveedor_servicio_proceso_fuera_del_catalogo` = 14.

## 13. Lo que queda, y qué necesita

Todo lo actionable sin el usuario quedó hecho. Lo que sigue abierto espera **un dato de
negocio**, y está en `IDEAS-GP2.md` con su código:

- **7324**: **re-diagnosticada el 2026-09-12 por la sesión paralela y ahí manda ella**: no son
  6 artículos ni un solo problema, son **12 filas en 10 artículos y cuatro problemas
  distintos**. Lo que decía este informe (7, y después 6 al arreglar el 547) se le escapaba un
  patrón. El detalle vivo está en `IDEAS-GP2.md`; lo que sigue valiendo de acá es que el 547
  era real y se arregló.
- **7314 / 7330 / 7335**: los 9 códigos con dos «unidades por caja» contradictorias, el 508
  (6 o 12) y el 553, que nombra dos bombillas distintas.
- **7331**: FAAT dice `Templado, Cementado` en una sola celda y Guazzaroni dice `Niquelado`
  cuando además hace pulido y zincado; y antes de normalizar hay que darles su fila a Rec
  Color y a Daniel.
- **7316**: decidir si el motor de la entrega de tallerista vive en el JS (hoy) o en la base.
- **7303**: Master Bach, 2 % o 4 %, adentro de los kilos o arriba.
- **7320**: 141 filas de inventario en negativo — se cierra con un relevamiento por tallerista.

## 14. Performance: los 28 bundles, medidos

Medición del 2026-09-11 (cache caliente, todas las tablas de GP2 tienen menos de 5.000 filas,
así que los índices no son el problema en ninguna). Sólo dos pasaban de 300 ms:

| ms | bundle | tamaño de la respuesta |
|---:|---|---:|
| 832 → **294** | `faltantes_bundle` | 622 kB |
| 401 | `despiece_verif_bundle` | 891 kB |
| 303 | `abm_articulos_bundle` | 151 kB |
| 179 | `oc_bundle` | 263 kB |
| 143 | `movimientos_bundle` | 600 kB |
| 113 | `valorizacion_bundle` | 281 kB |
| 98 | `talleristas_bundle` | 141 kB |
| 82 | `programa_bundle` | 608 kB |
| 60 | `recepcion_bundle` | 170 kB |
| ≤ 50 | los otros 19 | — |

**`faltantes_bundle` llamaba a `movimientos_bundle` cuatro veces.** Se arma como
`with m as (select movimientos_bundle() j)` y después usa `j` cuatro veces en el `select`.
PostgreSQL **inlinea** una CTE de una sola referencia, así que la función se evaluaba **una vez
por uso**. Medido: 4 llamadas sueltas = 582 ms, el bundle = 478 ms, con la CTE `MATERIALIZED` =
183 ms, y el resultado **idéntico** (comparado con `=` sobre el jsonb entero). Es la clase de
bug que no se ve en ningún plan de índices: la función se llama de más.

**En `despiece_verif_bundle` la misma idea NO sirve** y se sacó: 5 corridas con `MATERIALIZED`
dan 390–412 ms y 5 sin dan 398–413 ms. Los ~400 ms son el piso de armar y serializar 891 kB.
Bajarlo de verdad es mandar menos, y eso es un cambio de la pantalla (idea 7333). Se sacó el
`MATERIALIZED` en vez de dejarlo: un comentario que dice "sin esto el join se rehace 861 veces"
sería **falso**, y un comentario falso cuesta más que 0 ms ganados.

**Bloat:** `__sim_base`, la tabla de apoyo del simulador de rutas, pesaba **15 MB con 0 filas**
—más que todo el resto del schema junto— por llenarse y revertirse cientos de veces. Un
`vacuum full` la dejó en 16 kB: el schema `GP2` entero pasó de ~25 MB a **9,9 MB**.
