# Auditoría GP2 — 2026-08-31 (5 agentes en paralelo)

Revisión pedida por el usuario tras cargar los precios reales: normalización de Supabase
y código. **Todo lo que sigue está verificado con consultas a la base**, no es opinión.
Lo que se arregló ya está marcado ✅; lo que queda, con su SQL o su decisión pendiente.

---

## ✅ ARREGLADO EN ESTA PASADA

### 1. `carton_formato` estaba rota (la rompió esta misma sesión, el 31-08)

La tabla **ya existía** con 3 filas y semántica documentada en `REGLAS_OC_INSUMOS.md:25-33`:
`pliegos_multiplo` = **múltiplo del PEDIDO TOTAL** (C 12.000 · LOKE 16.000 · 8 30.000),
`codigo_multiplo` = 1.000, `min_codigo_x_multiplo` = 1.000.

La carga de categorías interpretó esos campos como "posiciones por pliego" y creó
**`Loke`** (duplicado case-sensitive de `LOKE` — el nombre es la PK y Postgres lo aceptó)
y **`Huevo`**, ambas con los tres campos mal. 28 cartones Chef quedaron apuntando a la
fila falsa y `LOKE`, la buena, quedó huérfana.

**Qué rompía**: `Compras/OC_GP2.html:264` valida `cantidad % codigo_multiplo`. Con
`codigo_multiplo = 16000`, cada código Chef exigía pedidos de 16.000 unidades — para el
Cartón 706 (2.249 uni/mes) eso es 7 meses de stock, y cualquier cantidad razonable
deshabilitaba el botón de crear OC.

**Fix**: los 28 componentes repuntados a `LOKE`, fila `Loke` borrada, `Huevo` corregida a
25.000/1.000/1.000. Quedan 4 formatos coherentes: C→32 cartones, LOKE→28, Huevo→10, 8→3.
Los precios no se tocaron.

**Pendiente de confirmar**: el múltiplo de pedido del formato Huevo (25.000) es `[deducido]`
del patrón y de que el usuario nombró "veinticinco mil". Confirmar con Gráfica Pol.

### 2. La OC mostraba y congelaba el precio del clavo inflado 153×

`oc_bundle` (CTE `pv`) y `crear_oc` leían `precio_proveedor.precio` **sin mirar la columna
nueva `precio_por_kg`**. El clavo PCP3 se cotiza a **USD 3,30 por kg** y pesa 6,53 g: la OC
lo mostraba como **USD 3,30 por unidad** (real: USD 0,0215), el subtotal y el total de la
barra lo multiplicaban así, `crear_oc` lo congelaba como foto histórica y **salía inflado en
la hoja impresa que se le manda al proveedor**.

**No llegó a hacer daño**: 0 órdenes abiertas y el clavo nunca se pidió. Verificado antes
de tocar nada.

**Fix aplicado** (migración `oc_respeta_precio_por_kg`): las dos funciones convierten a la
unidad de pedido (`precio * kg_x_uni`) cuando el flag está prendido, igual que ya hacía
`v_costo_componente`. Verificado: OC y valorización dan lo mismo (US$ 0,0215) y los flejes
siguen intactos ($3,58/kg, se piden en kg).

---

## ✅ SEGUNDA PASADA — arreglado sin esperar respuestas (2026-08-31, noche)

- **Los dos agujeros de escritura anónima, cerrados.** `inv_delta` revocada (había que
  sacarla de PUBLIC, no alcanzaba con revocar a anon). Y `GP2.empleado`: se crearon las
  RPC `empleado_guardar` / `empleado_activar` (SECURITY DEFINER, validan legajo único y
  campos obligatorios), se migró `Produccion/abm_GP2.html` a usarlas y recién ahí se
  revocaron las policies de INSERT/UPDATE. Verificado: anon ya no escribe, sigue leyendo,
  y la RPC frena un legajo duplicado. También se revocaron los GRANTs huérfanos de
  `ruta_confirmada` / `ruta_problema` / `devolucion_tallerista` (ninguna pantalla escribe
  ahí: todo pasa por RPC), se habilitó RLS en la única tabla que no lo tenía
  (`_bak_inventario_maximo_20260830`) y las dos policies `TO PUBLIC` volvieron al patrón
  de la casa (`TO anon, authenticated`).
- **$175 M de pedido inventado, fuera.** Los tres máximos de fleje cargados en piezas en
  ubicaciones de tallerista (C3, E4, E5) quedaron en NULL — un fleje se stockea en kg y
  esos números tenían `maximo_origen` NULL, o sea que nadie los derivó. Y se borraron los
  10 placeholders de 1 USD de `precio_servicio`: ahora un servicio sin precio da NULL y
  **cuenta en `faltan_precios`**, en vez de inventar $1.535. El pedido bajó de $2.783 M a
  **$2.608 M**.
- **El aviso de Valorización dice la verdad.** El banner fijo de "precios de regulación"
  (que ya mentía: 241 de 278 filas tienen precio real) se reemplazó por uno que sale de
  los datos: cuenta cuántos componentes declaran falta de precio, de kg o de tiempo, y se
  esconde solo cuando no falta nada.
- **El test que habría atrapado el bug del clavo, agregado.** `tests/ui/test_oc.js` ahora
  tiene un insumo cotizado por kg y comprado por unidad, y falla si el precio vuelve a
  llegar sin convertir. Suite completa: **29/29 en verde.**
- **Migración retroactiva de cartones** aplicada (idempotente, no cambió nada en
  producción): ahora `carton_formato`, `carton_categoria` y las columnas de `componente`
  están en el historial, con la semántica correcta documentada en la propia migración.
- **La regla de oro del costeo, garantizada por el modelo** (era el hallazgo #6). Se creó
  la maestra `GP2.proceso` (con FK desde `precio_servicio_pieza`) y `GP2.tarifa_servicio`
  (proveedor + proceso + precio): las 6 tarifas que estaban repetidas en 33 filas ahora
  viven una sola vez, y la fila por pieza solo dice qué proceso le toca. Pedernera se
  queda por pieza porque cobra distinto cada una. **Verificado con una foto de los 538
  costos antes y después: 0 cambiaron.** Y la prueba de que ahora sirve: subir el niquelado
  de $2.606 a $3.000 revaloriza **31 componentes con un solo UPDATE** (se probó en una
  transacción con rollback).

**Verificación final con los advisors oficiales de Supabase**: 576 hallazgos en todo el
proyecto, y **ninguno menciona GP2**. Los 43 de nivel ERROR (41 vistas security-definer y
2 tablas sin RLS) son todos del schema `public` — la casa del vecino, que no se toca — y
los 4 de `search_path` mutable son de `relevamiento_cervantes` e `isis_*`. El schema GP2
quedó limpio.

**Lo que NO se tocó, a propósito**: los 34 tiempos de matriz en cero. Iba a pasarlos a
NULL para que el semáforo los detecte, pero `registrar_evento_prod` lee
`matriz.tiempo_historico` para calcular **el premio del operario**, y 0 y NULL no se
comportan igual en esa cuenta. No vale la pena arriesgar la plata de la gente por
encender un aviso: queda como pendiente, y el arreglo de fondo es medir esas matrices.

---

## 🔴 EL PEDIDO A MÁXIMO ESTÁ INFLADO 3,3× — dos causas, las dos verificadas

El pedido daba **$2.783 millones** contra $23,0 M de stock (120×). Ese ratio era la señal.
Dos cosas explican el 87%:

### A. La matriz 501 vale el 70% del pedido de toda la fábrica — ✅ RESUELTO (se mide en KG)

`GP2.matriz` id 118, N° 501, **`tiempo_historico` = 7.650 segundos POR PIEZA** (2 h 07 min).
**Todas las demás matrices juntas suman 513 segundos.**

Contamina Z23 (Cuchilla Pela Afilada), 505, 513 y 713:

| | Hoy | Sin la 501 |
|---|---|---|
| Z23 costo unitario | $15.349,70 | $46,70 (×329) |
| Z23 en el pedido | **$1.943.855.309** | $6.293.909 |

**El 98,6% de toda la mano de obra del pedido es esta única matriz.** Sacarla baja el total
de $2.783 MM a ~$845 MM.

**Causa raíz**: el dato viene igual de la casa del vecino (`public."Matrices"` N° 501), pero
ahí se llama **"Piedra (TP)"**, no "Afilado Cuchilla". En `db_n8n_espejo` esa matriz tiene
438 registros con 3.833 "Uni" (~8,7 Uni por registro, 6,7 h de reloj cada uno): **su "Uni"
no es una pieza, es un lote**. Si la Uni fuera el cajón (2.326 piezas), el tiempo real sería
~3,29 s/pieza.

**RESUELTO — `[usuario 2026-08-31]`: *"501 es la matriz del afilado de cuchillas. Se mide
en kg, no en uni como el resto"*.** El dato nunca estuvo mal: le faltaba decir **en qué se
mide**. Los 7.650 segundos son **por kilo procesado**.

Se agregó **`matriz.tiempo_unidad`** (`'uni'` por defecto, `'kg'` en la 501) y el motor
multiplica por el peso vivo de la pieza que sale del paso. Z23: 7.650 × 0,0043 kg = 32,9 s
de afilado + 1,3 s de las otras matrices = **34,2 s** → $68,39 de mano de obra.

| | Antes | Ahora |
|---|---|---|
| Z23 y 505 | $15.349,70 | **$115,49** |
| 513 y 713 | $15.508,50 | **$274,29** |
| **Pedido a máximo** | $2.608 M | **$678 M** |
| **Stock valorizado** | $23,0 M | **$13,9 M** |

Verificado con snapshot de los 538 costos: cambiaron **exactamente esos 4 componentes** y
ninguno más. **La regla de la sección 2c queda así**: `tiempo_historico` es segundos por
pieza *salvo que `tiempo_unidad` diga otra cosa* — antes de dar por malo un tiempo raro,
preguntar en qué unidad se mide.

### B. El pedido cuenta el mismo requerimiento hasta 5 veces

`v_valor_pedido` hace `sum(greatest(0, maximo − cantidad))` sobre **todas** las filas de
`inventario`, sin mirar el tipo de ubicación. Z23 tiene 5 filas: Sector Procesado + tres
talleristas + Virgilio. "Llenar al máximo" hoy significa llenar mi estantería **y** la de
los tres talleristas **y** la de Virgilio, todas a tope a la vez.

**$1.556.505.334 — el 56% del pedido** sale de esas ubicaciones extra (talleristas $1.441,9 MM,
Virgilio $677,4 MM). Y los máximos de tallerista/Virgilio tienen **`maximo_origen` NULL**: no
salieron ni de la Est Madre ni de la regla de 5 cajones, son números heredados sin dueño.

**RESUELTO `[usuario 2026-08-31]`: va TODO EL CIRCUITO** (sector propio + talleristas +
Virgilio), y el nombre correcto del indicador es **"Máximo por sector"** — no "tope" ni
"pedido a máximo". Del total: $476 M sector propio, $114 M Virgilio, $89 M talleristas.
Queda la pregunta vieja de si conviene reponer
lo que está en poder de terceros? Hoy la vista ni siquiera expone `ubicacion_tipo` (a
diferencia de `v_valor_stock`), así que las pantallas no pueden cortar.

### C. Tres flejes con el máximo cargado en piezas, no en kg ($124,1 M) — ✅ RESUELTO

| Fleje | Dónde | Máximo | Valor |
|---|---|---|---|
| C3 Fleje N°90 (alambre filtros) | Tallerista IJUPA | 25.200 | $66.339.756 |
| E4 Fleje N°31 | Tallerista Alex Escalante | 9.000 | $28.873.350 |
| E5 Fleje N°32 | Tallerista Alex Escalante | 9.000 | $28.873.350 |

Los flejes se stockean y costean **en kg** (los máximos legítimos del Sector Fleje son 2.954,
3.890, 2.333 kg). 25.200 kg de alambre en lo de un tallerista no existe: son unidades de
pieza heredadas, con `maximo_origen` NULL, y ninguno figura en `v_consumo_fleje_kg_v2`.
Cierra con lo ya sabido de que E4/E5 entran directo al armado del batidor.

---

## 🔴 CRÍTICO — PENDIENTE (necesita datos o decisión del usuario)

### 3. Dos agujeros de escritura anónima

La clave anon viaja en el HTML, así que lo que protege es RLS + escritura solo por RPC
`SECURITY DEFINER`. Dos excepciones reales:

- **`GP2.empleado`**: policies de INSERT y UPDATE `TO {anon, authenticated}` con
  `WITH CHECK (true)`. Cualquiera con la URL puede crear legajos, renombrar gente o
  desactivar la planta entera. Y `legajo` cruza con `public.db_n8n_espejo` (premios).
  **OJO: no se puede revocar sin más** — `Produccion/abm_GP2.html:209-210` y `:224`
  escriben ahí directo. Primero hay que migrar esa pantalla a una RPC.
- **`GP2.inv_delta(bigint,bigint,numeric)`**: RPC `SECURITY DEFINER` ejecutable por anon
  que escribe `inventario.cantidad` **salteando `movimiento`** (sin auditoría, sin
  validar signo ni ubicación). **Ninguna pantalla la llama** (grep del repo: 0 usos).
  Revocarla es una línea y no rompe nada:
  `revoke execute on function "GP2".inv_delta(bigint,bigint,numeric) from anon, authenticated;`

Antecedente: en `agente_propuestas` se abrió escritura anon por error el 30-08 y se
revirtió a los 74 segundos. Acá nunca se revirtió.

### 4. 13 placeholders de 1 USD todavía mandan el costo — $ 47,8 M/mes de costo ficticio

Son **37 filas** con placeholder (no 17 como decía CONOCIMIENTO), y en las 37 el
placeholder es el precio **vigente**. De esas: 12 en `fabricacion` y 10 en `discontinuo`
quedan inertes (el motor las costea por ruta o en cero, correcto). **Las 13 con
`estado_compra` NULL sí contaminan**: valen $1.535 la pieza.

11 de ellas tienen consumo real → **$ 47.856.695/mes de costo inventado**, que es **el
doble del valor de todo el stock** ($ 23,0 M). Los peores:

| Código | Descripción | Consumo/mes | $/mes ficticio |
|---|---|---|---|
| C13 | Corta Queso Bastidor c/Cilindro | 5.655 | 8.680.425 |
| BOM13 | Filtro p/Bombilla | 5.064 | 7.773.240 |
| BOM14 | Precinto p/Bombilla | 5.064 | 7.773.240 |
| GRJ5 | Bombilla Resorte Trad 558 | 2.123 | 6.517.610 |
| BOM8 / BOM12 | Resorte y Caño de bombilla | 3.163 c/u | 4.855.205 c/u |

Cualquier número de valorización o costo de artículo para 557/558/546 hoy es basura.
**Regla que sale de acá: lo que neutraliza un placeholder es marcar el `estado_compra`,
no borrar la fila.** Los precios reales son pendiente del usuario (Cimarrón y el bastidor
importado).

### 5. 34 matrices con `tiempo_historico = 0` y el semáforo no las ve

34 matrices usadas en rutas tienen el tiempo en **0** (una más en NULL). Resultado: 23
componentes de Crudo/Procesado tienen **mano de obra $ 0** — la regla de $2/segundo
simplemente no se aplica en esas cadenas (Z2B, Z3B, J10, J12, F9, F10, K7, L8…).

**Lo grave es que la vista miente**: `v_costo_componente.faltan_tiempos` cuenta solo
`IS NULL`, así que da **0** y la pantalla dice "todo bien". Fix de una línea en la vista:
`count(*) FILTER (WHERE coalesce(m.tiempo_historico,0) <= 0)`. El arreglo de fondo es
cargar los 34 tiempos.

---

## 🟠 IMPORTANTE

### 6. La regla de oro del costeo NO está garantizada por el modelo

`precio_servicio_pieza.proceso` **no participa del join** de `v_costo_componente` (el join
es por `proveedor_servicio_id + componente_id`). Es una etiqueta de texto libre, sin FK, y
los valores ya divergen: `precio_servicio_pieza.proceso` en minúscula (`niquelado`) vs
`proveedor_servicio.proceso` en Title Case (`Niquelado`), más `'Templado, Cementado'` que
son dos procesos en una celda.

O sea: `UPDATE ... WHERE proceso = 'Niquelado'` no actualiza nada. El "sube el niquelaje,
un update y todo se revaloriza" depende hoy de adivinar la capitalización. **Falta una
maestra `GP2.proceso` con FK.**

Lo mismo con la tarifa: **33 de 68 filas de `precio_servicio_pieza` son redundantes** (el
niquelado de Guazzaroni está repetido en 17 filas). Falta `tarifa_servicio(proveedor,
proceso, unidad, precio)` como capa por defecto, dejando `precio_servicio_pieza` solo para
las excepciones reales (Pedernera cromado tiene 35 tarifas distintas: ahí sí es por pieza).

### 7. El precio del cartón sigue cocinado en 73 filas

4 tarifas ($89 / $66,75 / $42,72 / $35,60) repetidas en 73 filas de `precio_proveedor`.
`carton_formato` **no tiene columna de precio**, así que la frase "sube el pliego y se
recalculan las 4 tarifas" hoy **no es cierta**: el formato es una etiqueta, el precio sigue
por componente. Falta `precio_pliego` + `posiciones_x_pliego` en la maestra y que la vista
lo lea. (Nota: hay 3 cartones en formato C con $79 — los pelapapas, descuento por volumen.)

### 8. `precio_proveedor` no sabe quién es el proveedor

No tiene FK a `proveedor_insumo`: el proveedor vive en `cod_prov` (text sin destino) y
embebido en el texto de `producto`. Mientras siga así, "la tarifa vive en el proveedor" no
se puede implementar: no se puede pedir "la lista de Basconia" sin parsear strings.

**Bug latente**: los 9 precios de Recicor están cargados como referencia
(`componente_id NULL`) con fecha más nueva que los vigentes de Corrugadora del Plata. El
día que alguien los vincule a un componente, **las 9 cajas cambian de proveedor solas y en
silencio** (el único desempate es `fecha_lista DESC`). Hoy el discriminador es una
mayúscula en `rubro` (`caja` vigente vs `Caja` referencia): convención invisible.

### 9. Monedas: dos criterios distintos dentro de la misma vista

`v_costo_componente` normaliza defensivo en compras (`upper(...) LIKE '%US%'` else ARS)
pero compara **estricto** en servicios (`= 'USD'` / `= 'ARS'`). Un valor fuera de esos dos
en `precio_servicio*` **desaparece del costo en silencio**. Hoy no pasa (87/87 en 'ARS'),
pero `precio_proveedor` ya tiene un tercer valor: 11 filas en `'Peso'` (cartones viejos sin
componente, hoy inocuas). Falta maestra de monedas o un CHECK.

### 10. Cinco flejes redondos que la OC no está pidiendo (~478 kg/mes)

C3, E4, E5, E13 y E1 tienen consumo real en unidades pero `consumo_kg_mes = 0` → máximo
null → la OC los ignora. El peso **está cargado** en `fleje_detalle.kg_x_uni`; lo que falla
es que `v_consumo_fleje_kg_v2` necesita la matriz de corte para convertir, y estos entran
directo al armado (mismo patrón ya anotado de GRJ10). E4 y E5 tienen stock 0.

### 11. La receta que no cierra con la ruta deja 5 componentes en consumo 0

Si la receta lista un componente que **no es el último de la ruta**, todo lo que viene
después queda en cero (la vista siembra desde la receta y camina hacia atrás). Casos:
E6-M194 (570, 858), D5-M78 y D6-M78 (507), B1-M78 y B2-M78 (707). No aparecen en Faltantes
ni en Orden de Producción, y el costeo se saltea la mano de obra de las matrices 78 y 194.

### 12. Discontinuados que siguen en artículos activos

C12 y BOM10 (en 515 con 334 uni/mes y 615 con 46), el Cartón 516 (en 516 con 333 uni/mes) y
V18C (hijo de M1, 3.763 uni/mes). Se costean en **$ 0**, así que esos artículos salen
subvaluados. Y el artículo **574 está `discontinuado=true` pero tiene 936 uni/mes en la Est
Madre** — contradicción abierta: o la Est Madre está vieja o el flag está mal.

### 13. La normalización de cartones se aplicó sin migración

`carton_formato`, `carton_categoria` y las columnas `componente.carton_formato/categoria`
existen en la base pero **no tienen migración** (las tablas de precios del 30-08 sí la
tienen). Un rebuild desde migraciones no las tendría. Falta la migración retroactiva.

### 14. El respaldo `db/` quedó viejo

Export del 29-08: 84 funciones / 7 vistas / 41 tablas, contra **100 / 15 / 49** vivas. Falta
todo el motor de costos. Hay que regenerarlo.

---

## 🟠 IMPORTANTE — del motor de costos

### 15. Los 88 terminados pierden todo su material

**366 pasos productivos tienen `comp_entrada_id = NULL`** y el motor los descarta. Es el
patrón "Insumo X → Art": el insumo va en un paso `insumo` (salida NULL) y el armado en un
paso `tallerista` (entrada NULL), así que **el eslabón insumo→terminado nunca se forma**.

| Artículo | Motor | Por receta | Falta |
|---|---|---|---|
| 550 / 546 | $0,00 | $6.234 / $1.837 | −100% |
| 557 / 558 | $69,00 | $3.075,92 | −98% |
| 708 / 508 | ~$1.160 | ~$4.420 | −74% |
| 031/034/836/867/120 | $9,50 | ~$2.700 | −99,6% |

No afecta el pedido (los terminados no aportan), pero ensucia $4,09 M del stock. **El
arreglo de fondo es el que ya está en la sección 2c**: el costo del artículo sale de la
RECETA (que tiene las cantidades), no del walk. Es la puerta natural a la unificación con
el otro repo de costos.

### 16. El fallback de 1 USD inventa $49 M y no avisa

`precio_servicio` (el precio plano) **quedó entero en 1 USD de regulación**: nunca se pisó,
porque los precios reales fueron a `precio_servicio_pieza`. Solo 3 pares caen ahí, pero
pesan: **Z22 Llavero Pie $29,7 M · B12 $15,5 M · V18D $3,9 M**. Un pintado a $1.535 es ~10×
lo real ($127–305 de Jade). Agravante: los tres son en pesos pero el fallback los mete en
la **columna dólares**, así que suben solos si sube el dólar.

Y el motor dice `faltan_precios = 0`: muestra $3.215,51 con cara de dato bueno. **Mejor un
cero honesto con aviso que un número inventado.**

### 17. Cinco raíces huérfanas costando $0 en Sector Procesado

**D1** (Espiral Sacacorcho), **Z23A** (Cuch China), **Z23B** (Cuchilla Laser), **Z25A** y
**Z25B** (Argollas): cero pasos que las produzcan, cero precio, `estado_compra` NULL. Son
piezas **compradas** que viven en Procesado — el mismo caso que C13, pero sin precio para
que la regla las agarre. Aparecen en 17 rutas de sacacorchos y llaveros costando cero.
Ojo: **D1 existe además como Fleje N°28** ($4.850,60) — la trampa del código repetido, viva.

### 18. `v_valor_stock` y `valorizacion_bundle` dan totales distintos

La RPC filtra terminados; las vistas no. Según por dónde entres, la fábrica vale **$23,0 M
o $19,0 M**. No es doble conteo físico, es criterio inconsistente: debería vivir en un solo
lugar.

### 19. Las cantidades N→1 valen $7,7 M — real pero no urgente

Medido: el **tocho E4** es el único que pesa hoy ($1.452 → $5.570 el tocho; +$6,7 M de
pedido en E4 y +$1,0 M en J1). El peso lo delata solo: 477 g / 5 g = 95 arandelas. El
**pliego skin** y el **blister de untar** dan **$0 de impacto hoy**, porque el motor no
costea desde receta — el error aparecerá recién cuando se costee el artículo.

**Hallazgo lateral en la receta del 519**: el blister ×2 está a medias — E7 ×2 y W5 ×2, pero
el mango PEP5 quedó en ×1 (dos hojas, un mango). Y el **719** (el mismo cuchillo en marca
Chef) no tiene el ×2 en ningún componente. Eso **sí** afecta hoy el consumo, los máximos y
el volumen del pedido de PEP5/E7/W5. **Pregunta al usuario**: ¿el blister de 2 es solo del
519 o también del 719/551/878? ¿Y van dos mangos o uno?

### 20. N1/N2, doble matriz de soldado: $441.480

Confirmado con número. La matriz 183 ("Soldar Ahuecapapa/Ahuecafruta", genérica) y la
362/363 ("Soldado Ahueca Fruta/Papa", específica) **son la misma operación anotada dos
veces**: 23,6 s en vez de ~13. Sacar la 183 de las rutas de N1/N2.

---

## 🟡 MENOR (anotado, sin urgencia)

- **`carton_categoria` nació muerta**: 5 filas, 0 componentes asignados. Ganó
  `carton_formato`. Dos mecanismos para lo mismo, del mismo día.
- **El banner de Valorización miente**: sigue diciendo "precios de regulación, todo vale
  1 USD" cuando 241 de 278 filas ya tienen precio real (`Valorizacion_GP2.html:51-52`).
- **Los discontinuados se valorizan en $0 sin aviso** (`faltan_precios = 0`): hoy inocuo
  porque ninguno tiene stock, pero es una bomba silenciosa.
- **Un componente sin código** (id 522, "Cartón 506"): el índice único es parcial
  (`WHERE codigo IS NOT NULL`), así que los NULL se escapan.
- **44 componentes de Tránsito sin `kg_x_uni`** (el 100%) y 54 matrices sin
  `partes_por_kilo_de_fleje`: en esa intersección no hay ni peso ni fallback.
- **El máximo de 5 cajones tiene 2 pendientes, no 1**: se sumó C13 a Z12.
- **3 rutas huérfanas sin artículo** (35, 151, 152); la 151 tiene dos pasos completamente
  vacíos. Son los únicos 4 pasos anómalos de 2.432.
- **5 remaches huérfanos totales** (CV10, CV11, CV14, CV16, V11): sin estado, sin receta,
  sin ruta, sin BOM. Y los pares CV→V de niquelado siguen sin crearse.
- **`est_madre.cod` va sin ceros a la izquierda** y `articulo.codigo` con ceros: un join
  literal pierde 10 artículos y 17.434 uni/mes. Las vistas ya normalizan; cuidado en
  queries nuevas.
- **21 pares de rutas comparten nombre** pero ninguna es duplicado real (distinto
  tallerista o distintas matrices). El nombre no discrimina la variante.
- **`movimiento.ubic_origen_id` está 100% NULL** en las 58 filas: verificar si es diseño o
  hueco de trazabilidad.
- **Las 15 vistas son security-definer de hecho** (sin `security_invoker`): hoy inocuo
  porque todas las tablas base son legibles por anon.
- **Cascada de recálculo**: `proyeccion_madre → est_madre → recalcular_maximos_insumos`
  recalcula el walk completo **una vez por fila** (369 filas × ~30 ms) cada miércoles.
- **12 funciones sin llamador** en el repo, y 2 trigger-functions sin trigger
  (`fn_espejo_produccion`, `fn_espejo_entrega_tallerista`).
- **La suite (29 tests) pasa 29/29 pero quedó ciega**: todos stubean Supabase, así que un
  cambio de schema no los toca. `test_oc.js` no tiene `precio_por_kg` en el stub — por eso
  el bug del clavo pasó sin despeinarse.

---

## Lo que está SANO (para que quede constancia)

- **Integridad referencial impecable**: 0 huérfanos en recetas, BOM, inventario y rutas;
  0 duplicados de (código, sector); 0 stock negativo; 85/85 artículos con receta, rutas,
  cartón y caja.
- **El JS no duplica el motor de costos**: Valorización solo re-suma lo que devuelve la
  vista y nunca inventa un tipo de cambio.
- **Las 96 funciones tienen `search_path` fijo** y anon no tiene CREATE en ningún schema:
  el vector de escalada por SECURITY DEFINER está cerrado por partida doble.
- **Cero SQL dinámico** en las funciones: sin superficie de inyección.
- **El cron del dólar está sano e intacto** (jobid 65, 09:10 UTC).
- **`oc_bundle` filtra `estado_compra is null`**: los discontinuados no aparecen en la OC.
- **Los joins del front van por `id`, no por código.**
- **Las tablas de precios nuevas tienen las UNIQUE y FKs correctas.**

---

## Cosas verificadas que están BIEN (hallazgos negativos, valen tanto como los positivos)

- **Las rutas alternativas NO duplican el material.** Era lo más difícil de descartar. G7
  (registrado con y sin el aplastado M77): US$0,046167 kg × 3,22 = **US$0,14866**, y la
  vista devuelve exactamente eso. Los 10 casos donde un fleje aparece dos veces son dos
  piezas distintas del mismo fleje convergiendo (pinza fiambre derecha por matriz 62 e
  izquierda por 64) — ahí contar dos veces es lo correcto.
- **Las tres cirugías de la vista conviven bien**, verificadas una por una: servicio exacto
  por pieza (tocho E4: FAAT $15,21 + Guazzaroni $5,86 + Scorrano $1.406, exacto), el CTE de
  talleristas (557/558 = $69 de Gentile, sin duplicar entre nodos) y la regla de "comprado"
  ampliada (único caso: C13, que antes daba $0).
- **La precedencia de precios funciona como pediste**: tarifa por kg de la pieza × peso vivo
  → precio por unidad de la pieza → plano del proveedor.
- **Performance sin problema**: `v_costo_componente` 20,4 ms, `v_valor_pedido` 21,8 ms. El
  walk converge en 8 iteraciones. Nada que optimizar.
- **La trampa del código repetido también muerde al auditor**: agrupar por `codigo` en vez
  de `id` generó 21 falsos positivos de doble conteo (E10 es Fleje N°15 **y** Sacafuente
  Pizzero a la vez). Agrupar siempre por `id`.

---

## Orden sugerido

1. **Lo que cambia la foto** (necesita datos del usuario): el tiempo real de la matriz 501
   —saca $1.938 M de humo, el 70% del pedido— y decidir si el pedido a máximo incluye las
   ubicaciones de terceros (otros $1.556 M, el 56%). Con esos dos el pedido queda en el
   orden de **$700–850 M**, que ya es un número con el que se puede discutir.
2. **Tres filas, $124 M**: los máximos de C3/E4/E5 en talleristas, cargados en piezas
   cuando el fleje va en kg.
3. **Hoy, sin depender de nadie**: revocar `inv_delta` (una línea, no rompe nada). Decidir
   qué hacer con `empleado` (requiere migrar `abm_GP2.html` a RPC primero).
4. **Cuando haya datos**: los 13 placeholders con estado NULL (5 filas resuelven el 80%:
   C13, BOM8, BOM12, BOM13, BOM14), los 34 tiempos de matriz, y los precios de las 5 raíces
   huérfanas (D1, Z23A, Z23B, Z25A, Z25B).
5. **Cuando se toque costos**: maestra de `proceso` + `tarifa_servicio` (mata 33 filas
   redundantes y es lo que hace verdadera la regla de oro), precio del pliego en
   `carton_formato` (mata 70 más), FK de proveedor en `precio_proveedor`, que el fallback
   de servicio sea NULL en vez de 1 USD, y costear los terminados por receta.
6. **Higiene**: migración retroactiva de cartones, regenerar `db/`, arreglar el semáforo
   `faltan_tiempos` (que cuente el 0, no solo el NULL), sacar el banner viejo de
   Valorización, unificar el criterio de terminados entre vista y RPC.
