# PREGUNTAS_ARQUITECTURA_GP2.md — para responder el martes

> Dudas que salieron de la auditoría de arquitectura del 2026-09-04 y que dependen de una regla
> del negocio (no se pueden deducir técnicamente). El loop NO se frenó por ninguna: se anotó y se
> siguió con otra cosa. Cada una trae qué se encontró, por qué hay duda, dos alternativas, la
> recomendación, el impacto y la pregunta concreta. Responder con el número y la letra alcanza
> ("1B", "2A"…).

---

## 1. ¿Se borran del repo las pantallas del programa viejo (schema `public`)?

**Problema encontrado.** El repo tiene **58 páginas del programa viejo** (2,4 MB con su JS; 56 pegan al schema `public`; lista completa en el **Anexo A** al final; la casa del vecino): `StockSC/StockSC.html`,
`Produccion/monitor.html`, `Facturas/index.html`, `Talleristas/Envios/EnviosTall.html`, etc.
Ninguna está linkeada desde el menú `GP2_MODULOS.html` salvo *Recepción Virgilio* (marcada "app
vieja"). Son un tercio del repo y casi todas escriben o leen tablas que GP2 no mira.

**Por qué existe una duda.** Técnicamente no puedo saber si alguien las abre por URL directa
(bookmark, tablet, el sector Pagos con `Facturas/index.html` según `PERFILES.md`) o si el programa
viejo corre desde OTRO deploy y estas son copias muertas.

**Alternativa A.** Borrarlas todas (quedan en git si hacen falta) menos las que el menú todavía
usa (*Entrega Virgilio*) y las 5 "bloqueadas" del menú que son la referencia para migrar
(Facturas, Control Remitos, Entrega Cervantes Fotos, Entrega Proveedores Cervantes, Chat Ventas).

**Alternativa B.** Dejarlas como están y sólo borrar backups/ejemplos/duplicados exactos.

**Recomendación.** A. Las pantallas viejas que tienen versión GP2 (StockSC, StockSP, monitor,
maestro, rendimiento, tiempos, abm, entrevistas, Disruptivas, ControlPS/EnviosPS/EntregaPS,
ControlTall/EnviosTall/Recepcion Cervantes, ControlAT/EnviosAT, StocksGeneral, StockTransito,
StockMovimiento, Despiece, Verificación, VerifMadres, Informes, Alertas, Faltante Partes,
Proporciones, ABM Artículos, StockFlejes/*.html viejos) son copias del vecino dentro de mi casa:
contradicen la regla de oro (no se copia la casa del vecino) y cada arreglo de UX se hace dos veces.

**Impacto.** Sólo archivos del repo (ninguna tabla). Hay que dejar un redirect en las 4 que la
tablet todavía linkea (ver pregunta 2).

**Pregunta concreta.** ¿A o B? Si A: ¿alguna de las viejas la usa alguien hoy por URL directa
(Pagos con `Facturas/index.html`, Thomas, la tablet)?

---

## 2. La tablet de logística (`envios-only.html`) sigue abriendo 4 pantallas VIEJAS

**Problema encontrado.** `envios-only.html` linkea `Prov Serv/Envios/EnviosPS.html`,
`Prov Serv/Entregas/EntregaPS.html`, `Talleristas/Envios/EnviosTall.html` y
`Talleristas/Recepcion/Recepcion Cervantes.html`, que escriben en `public` (`Envios a PS`,
`Entregas PS`, `Envios a Talleristas`, `Entregas Tallerista Virgilio`). Lo que se carga desde la
tablet **no entra a GP2** (salvo las entregas de Virgilio, que el trigger espeja). Desde la PC se
usan las `_GP2`, que escriben en `GP2.movimiento`. Dos libros distintos para el mismo movimiento.

**Por qué existe una duda.** No sé si la tablet sigue a propósito en el programa viejo (corrida
en paralelo hasta cargar el stock inicial real) o si quedó así por olvido cuando se hicieron las
pantallas GP2.

**Alternativa A.** La tablet pasa YA a las 4 pantallas GP2 (`EnviosPS_GP2`, `EntregaPS_GP2`,
`EnviosTalleristas_GP2`, `EntregasTalleristas_GP2`) — un cambio de 4 links + la lista del rol
`envios` en `auth-guard.js`.

**Alternativa B.** Sigue en las viejas hasta que el ledger GP2 tenga el stock inicial real.

**Recomendación.** A. El ledger GP2 ya recibe cargas reales desde las pantallas de PC (Fleje90,
Charcas, Eclipse, talleristas); tener la tablet en otro libro es la fuente de desfasaje más grande
que hay hoy. (Relevamiento ya se cambió: el usuario lo había decidido.)

**Impacto.** `envios-only.html`, `auth-guard.js`; y habilita borrar las 4 pantallas viejas + sus
JS/CSS (≈120 KB).

**Pregunta concreta.** ¿A o B?

---

## 3. Los 5 módulos con candado del menú: ¿se migran o se borran?

**Problema encontrado.** `GP2_MODULOS.html` tiene 5 botones bloqueados (🔒) cuyas pantallas
viejas siguen en el repo: *Lectura de Facturas Entrantes* (`Facturas/index.html`, 100 KB,
borra e inserta en `public."Entregas PS"`), *Entrega Proveedores Cervantes* (23 KB), *Ver
Cargas* (`ControlRemitos/`, 9 KB), *Entrega Cervantes Fotos* (47 KB) y *Chat Bot Ventas*
(`Ventas Chat/`, 51 KB, sin Supabase). 230 KB que ni se abren ni se migran.

**Por qué existe una duda.** Un candado significa "pendiente de migrar"; no sé si siguen en
plan o si ya se descartaron (Pagos podría estar usando `Facturas/index.html` por URL directa).

**Alternativa A.** Se migran a GP2 (cada una es un módulo nuevo: hay que diseñarlo).
**Alternativa B.** Se borran, y los 5 botones desaparecen del menú.

**Recomendación.** B para *Chat Bot Ventas* (es un stub sin datos) y *Entrega Cervantes Fotos*
(prototipo OCR). Para las 3 de Pagos/Remitos, decidir con el sector Pagos.

**Impacto.** Solo archivos + 5 líneas del menú.

**Pregunta concreta.** Por cada uno de los 5: ¿A, B, o "lo usa alguien hoy por URL"?

---

## 4. Documentos del programa viejo que CLAUDE.md todavía manda leer

**Problema encontrado.** `CLAUDE.md` tiene secciones enteras que describen la casa del vecino
(`public`): *Verificación - Trazado de Rutas* (tablas `Rutas_Confirmadas`/`Rutas_Problemas`),
*Patrón GRJ* (configura `Recepcion Cervantes.html` vieja), *Tablas Madre y Derivadas* (`SP Kg`,
`SC Kg`, `Despiece x Articulo`…), *Causa-Efecto*, y referencia archivos que no existen
(`ANALISIS_LOGICA_GP2.md`, los 3 HTML con `var D`). Además hay 3 puertos distintos para el
servidor local (5501 en CLAUDE.md, 5503 en `.vscode`, 5509 en `.claude/launch.json`).
`GP2_MAPA.md` (los contratos de los bundles, viva y útil) no la linkea nadie.

**Por qué existe una duda.** Si el programa viejo sigue operando desde este repo, esas
secciones siguen siendo instrucciones válidas para quien lo toque; si el vecino vive en otro
lado, son ruido que confunde a cada sesión nueva.

**Alternativa A.** CLAUDE.md queda solo GP2: se quitan las 4 secciones del vecino (quedan en
git y en `Tablas_Madre_y_Dependencias.xls`), se linkea `GP2_MAPA.md`, se unifica el puerto.
**Alternativa B.** Se dejan, marcadas "(programa viejo — solo si tocás `public`)".

**Recomendación.** A, junto con la respuesta a la pregunta 1.

**Impacto.** `CLAUDE.md`, `AUDITORIA_RUTAS_2026-04-18.md`, `Tablas_Madre_y_Dependencias.xls`.

**Pregunta concreta.** ¿A o B? ¿Y cuál es el puerto real del Live Server?

---

## 5. `PENDIENTES_UBICACIONES_2026-08-30.md` + `SQL_MAXIMOS_POR_UBICACIONES.sql`: ¿regla vigente?

**Problema encontrado.** El doc describe la regla *"sólo se nombra la primera ubicación
ocupada"* y el SQL define `maximos_sector_por_ubicaciones_ocupadas()`, que **no existe en la
base**. Lo que sí corre hoy es `recalcular_maximos_cajones()` (5 cajones por ubicación,
`parametro.max_cajones_x_ubicacion`, columnas `inventario.cajones_x_ubicacion/ubicaciones`).

**Por qué existe una duda.** No sé si la regla de "ubicaciones ocupadas" se descartó o si
quedó pendiente de aplicar.

**Alternativa A.** Se descartó: borrar los 2 archivos.
**Alternativa B.** Sigue pendiente: pasarla a `IDEAS-GP2.md` con código, y borrar los archivos.

**Recomendación.** B (la idea queda registrada, el SQL en git).

**Dato agregado el 2026-09-05 (ciclo 2s).** La columna `inventario.cajones_x_ubicacion` (154 valores
en Crudo/Procesado, "Max Caj Cerv" del Excel viejo) **no la lee nadie**: ninguna función, vista ni
pantalla (el máximo vigente sale de `parametro.max_cajones_x_ubicacion` = 5 para todos). Si A,
se borra la columna (con respaldo CSV en `db/`); si B, es el dato de entrada de la regla pendiente.

**Pregunta concreta.** ¿A o B? (y con eso, ¿se borra `cajones_x_ubicacion`?)

---

## 6. `MACRO_ENTREGAS_SUPABASE.bas` y `.nojekyll`

**Problema encontrado.** La macro VBA lee `public` desde el Excel "Control Partes
Talleristas" (¿sigue sincronizando?). `.nojekyll` sólo sirve para GitHub Pages y el deploy es
Vercel (`vercel.json`).

**Recomendación.** Borrar los dos (la macro real vive en el `.xlsm`, no acá).

**Pregunta concreta.** ¿El Excel sigue sincronizando desde `public`? ¿El deploy es solo Vercel?

---

## 7. ¿«CARLOS» en las entregas de Virgilio es Alex Escalante (2) o Carlos Aguirre (9)?

**Problema encontrado.** `contraparte_alias` tenía `'CARLOS' → 9 (Carlos Aguirre)` y también
`'Carlos' → 2 (Alex Escalante)`; el trigger que espeja las entregas de Virgilio compara en
mayúsculas, así que la segunda nunca matcheó (se borró en el ciclo 2; hoy manda la primera). En
`public."Entregas Tallerista Virgilio"` «CARLOS» entrega 535, 307, 335, 248, 635/636, 515, 395,
510, 580…; «AGUIRRE CARLOS RODOLFO» entrega 544 y 561 por separado. En GP2 el 510 y el 515 los
hacen **Alex Escalante / Martin Cornejo** (rutas y precios a nombre de Alex), el 544 lo hace
**Carlos Aguirre**, y el 580 figura de Carlos Aguirre aunque en Virgilio lo entrega «CARLOS».

**Alternativa A.** `'CARLOS' → 2` (Alex Escalante) y revisar la ruta del 580.
**Alternativa B.** Queda `'CARLOS' → 9` (Carlos Aguirre).

**Recomendación.** A: la evidencia de Virgilio (510/515) apunta a Alex; «Aguirre Carlos Rodolfo»
ya tiene su alias propio.

**Impacto.** Una fila de `contraparte_alias`; las entregas espejadas de «CARLOS» descuentan las
partes del tallerista equivocado mientras esté mal.

**Pregunta concreta.** ¿A o B? ¿Y el 580 lo envasa Alex o Carlos Aguirre?

---

## 8. Datos que el sistema no puede deducir (lista corta, una línea cada uno)

Cada uno tiene la consulta y el detalle en los informes de auditoría (`REFACTOR_GP2.md`).

1. **550**: la columna dice caja **A8** y la receta dice **A9** (el catálogo viejo también dice
   N° 22 = A9). ¿Cuál es? (recomendación: A9, corregir la columna).
2. **PA10 / PEP3** `[CONTRADICCIÓN 2026-09-08 — sin resolver]`: hoy el usuario dijo "las partes
   plásticas van en Sector Plástico, no Procesado" y "PA10 se compra". Pero **eso contradice su
   propia decisión textual del 2026-09-04** (§4p de `CONOCIMIENTO`, que fue una auto-corrección):
   *"dejalo en sector procesado, pero no va en orden de compra, porque eso sería plásticos que se
   mandan a serigrafear"*. Dato duro: **PA10 es el capuchón YA serigrafiado; el que se compra es
   `PA10B` (Capuchón ф8 S/Serig)**; ídem `PEP3` (Mango Pelador **c/Serig**), cuyo crudo es `PEP2`.
   Se aplicó el cambio de PA10 a Plástico-comprable y **se revirtió** al ver la contradicción
   (`refactor_20260908_revert_pa10_vuelve_a_procesado`): PA10 quedó en Procesado como el 04/09.
   **Falta que el usuario confirme:** ¿manda la decisión del 04/09 (PA10/PEP3 en Procesado, fuera de
   OC, porque son plástico que sale a serigrafiar) o la de hoy (van a Plástico)? De esto depende la
   cirugía del 586 (agregarle el paso de serigrafía Ximpa PEP2→PEP3).
3. **37 stocks negativos en talleristas** (IJUPA −1.896 en 11 piezas, Pettofrezza −1.200 en 12,
   W6 −2.400; +4 en Pedernera/Carlos −1.920 por la entrega 2308 repuesta el 05/09): son consumos
   de Virgilio sin envío ni stock inicial cargado. ¿Se releva el stock
   de esos dos talleristas y se carga como ajuste trazado, o se blanquea a 0? (recomendación:
   relevar; los negativos son la lista exacta de lo que hay que contar).
4. **574** está `discontinuado` pero la Est Madre le pide 1.060/mes (también 119: 150, 615: 24,
   809: 16). ¿Sigue discontinuado? Y 9 componentes `discontinuo` siguen en rutas vivas (A1C1,
   A9, BOM10, C12, GRJ13, I3B, IZ19A, L4B1, V20): ¿se sacan de la ruta o vuelven a activos?
5. ~~**GRJ1**: está en la receta del 500 y tiene inventario, pero ninguna ruta lo produce ni lo
   consume.~~ **RESUELTO 2026-09-08 [usuario]:** el 500 se arma con las partes sueltas, como el 510
   (sin intermedio de Garage). Se aplanó la receta del 500 a C1 + C10 + V9 + A11 + Pliego Ad 500 y
   se retiró GRJ1 por completo (BOM, inventario en 0, componente). Las rutas ya mandaban las partes
   por separado a Alex Escalante y Martin Cornejo. Costo del 500 sin cambios ($1.525,12).
6. ~~**863** tiene PEP8 en la receta y ninguna ruta lo toca.~~ **RESUELTO 2026-09-08 [usuario:
   "mismo caso que 564, ruta del fleje 27"]:** faltaba la ruta que construye el PEP8. Se replicó
   la del 564 (ruta 93: Fleje 27 `ID8` → matriz 85 → Guazzaroni → Maspoli → PEP8 → Martin Cornejo →
   863). Costo del 863 corregido de $909,73 a $1.620,57 (+$710,84: el mango pizza que faltaba
   costear). Migración `refactor_20260908_863_ruta_fleje27_pep8`.
7. ~~**Federico Realini** tiene dos legajos (274 inactivo, 401 activo).~~ **RESUELTO 2026-09-08
   [usuario: "borralo"]:** era error de carga. Se borró el legajo 274 (empleado id 20, inactivo);
   no tenía datos colgados (0 producción, 0 rollos) ni FK. Queda el 401 activo.
8. **Matriz «S/N» (117)** está en 2 rutas (ID5→W5) sin tiempo ni tipo; **138 (119)** dice tipo A
   (alimentador) y decía tipo_matriz B (balancín). ¿Cuál vale? (`tipo_matriz` ya se borró el
   04/09: nadie la leía; queda `tipo`).
9. **Mínimo > máximo en 80 filas** (X4 87.892 vs 20.020; V9 113.912 vs 10.581): NO se topea
   (el usuario ya lo decidió el 02/09, §2e-bis de `CONOCIMIENTO`); lo que sí hay que decidir son
   los parámetros `meses_minimo > meses_stock` de tres ubicaciones → **pregunta 27**.
10. **IE3, IC2 e IF12** (flejes) no tienen `kg_x_uni`: cualquier movimiento en unidades falla.
    ¿Peso por pieza? (dato físico).
11. **Z12, C13 y 1686** (crudo/procesado) no tienen `uni_x_cajon` (Z12 y C13 tampoco
    `kg_x_uni`): sin eso no se calcula el máximo de 5 cajones.
12. **`precio_proveedor.cod_prov` contradice `componente.proveedor`** en 6 códigos (797 Pat Bet
    Plast en 9 piezas de Pettofrezza; 2147 Pol en Vihal/Blist-Pack; 2339 Maspoli en PEP5 de
    Pintos; 2635 Aperam en IB7 de Hermac; 3810 Hermac en IA1 de Basconia; 3917 Tierra Nativa en
    IE13 «Importado»). ¿Quién cotiza y quién entrega?
13. **`proveedor_insumo.cod_prov` está vacío en 35 de 39**; los precios permiten deducir 18
    (Basconia 302, Brawin 419, Bella Vista 890, Vihal 1218, Szapiro 116, JL Metales 1744,
    Pettofrezza 1895, Mandelli 2224, Giser 3327, Suipacha 3808, Grudzien 4466, Cimarron 4444, Pol
    2147, Pat Bet Plast 797, Aperam 2635, Hermac 3810, AJ Adhesivos 697; ¿Pintos 2339?). ¿Se
    cargan así?
14. **`fleje_detalle.kg_uni_desp`** difiere de `componente.kg_x_uni` en 2 flejes (IE4 0,01463 vs
    0,01482; IE5 0,01603 vs 0,01642). ¿El kg oficial ya incluye el desperdicio (se borra la
    columna) o no (se conserva como `kg_x_uni_desp`)?
15. **`uni_x_articulo_x_caja`** (434 filas, copia del Excel «Cajas» de LK y CH): nadie la lee
    salvo `ControlAT_GP2`; es la única fuente del catálogo **CH** (18 códigos son otro producto
    en CH que en LK) y de las unidades por caja de 48 artículos de Prov AT que no están en
    `articulo`; contradice `articulo.articulos_por_caja` en 5 (508: 12 vs 6; 034/043/658/802: 12
    vs 24). ¿GP2 modela CH (columna `empresa` en `articulo`) o se descarta y se borra la tabla?
16. **`proveedor_at` (12) vs `tallerista`**: misma clase de contraparte (recibe cartón/cajas y
    entrega terminado a Virgilio) y 3 personas están en las dos (Maspoli, Pettofrezza, Tierra
    Nativa). Fusionarla en `tallerista` con `clase='prov_at'` saca una tabla y 2 FKs pero toca
    ~15 funciones. ¿Se hace? (recomendación: sí, en un ciclo propio).
17. **13 artículos entregados en Virgilio que no existen en GP2** (535 con 482 cajas históricas,
    727E, 877E, 599, 943, 948, 207, 584E, 590E, 590ES, 823, 817, 760): quedan en
    `virgilio_espejo_pend`. ¿Se dan de alta?
18. **071**: la ruta lleva la caja A4 y ahora la receta también (ciclo 2); el usuario dijo «al 071
    no le hagas cartón» (cartón ≠ caja). ¿La caja A4 va? Si no, se saca la fila. Además es el
    **único artículo activo sin Est Madre** `[dato 2026-09-05]`: sin demanda, sus partes no tienen
    máximo ni mínimo automático. ¿Se vende todavía?
19. **Cronograma de relevamiento «Bolsa Plást»** (2 fechas) no tiene `sector_id`, así que ese
    conteo no se puede abrir. ¿Es sector Plástico (6) o Cartón (10)?
20. **`recepcion_control` / `recepcion_control_rollo`** (pesaje por pallet con rollos) siguen en
    0 filas: ninguna recepción de Basconia/Hermac se controló todavía desde la pantalla. ¿El
    pesaje por pallet se usa de verdad? Si no se va a usar, son 2 tablas + 3 vistas + 3
    funciones para borrar.
21. **12 insumos comprables sin ningún precio** `[dato 2026-09-05]`: `BOM8B`, `CHAPA430` (la chapa
    de Eclipse: sin precio, el 1686 se costea sin material), `CV15`, `PB2`, `PC4`, `PCP2`,
    `PCP4A`, `PEP2`, `PEP9`, `PIEA`, `PIEB`, `W8`. Valorización los muestra con
    `faltan_precios` y la OC no los puede valuar. ¿Precios?
22. **44 precios de `precio_proveedor` sin componente** `[dato 2026-09-05]` (p.ej. las resinas de
    Beta Plásticos — AI, PE, PP — y "Batidor Pera LK Env"): son materiales que GP2 no modela
    (bolsas de inyección, idea 7243/7244) o códigos que no cruzaron. ¿Se crean los componentes o
    se borran esas filas?
23. **`componente.marca` tiene `LOEKE` (73 cartones y pliegos) y `LOKE` (8 cartones: H1A, H1C,
    H2C, H4C, I2B, I3B, I42, K5D — justo los de `carton_formato = 'LOKE'`)** `[dato 2026-09-05]`.
    Las pantallas muestran las marcas tal como están en la tabla (`test_marcas`), así que hoy se
    ven como dos marcas. ¿Es la misma marca escrita de dos formas (y se unifica a `LOEKE`), o
    `LOKE` es otra cosa? No se tocó.
24. **Dos clasificaciones que hoy son texto libre** `[dato 2026-09-05]`: `matriz.tipo` (A ×45,
    B ×58, D ×11, P ×1 — ninguna función ni pantalla lo lee) y `empleado.tipo` (`operario` ×N,
    `administrativo`; en el ABM de empleados es un campo de texto donde se puede escribir
    cualquier cosa). ¿Qué significan A/B/D/P y son los únicos? ¿Los tipos de empleado son sólo
    esos dos? Con la respuesta se cierran con CHECK y el ABM pasa a un desplegable; si nadie los
    usa, se borran.

---

## ~~28. La OC a Charcas y su gemela a Altrak: dos decisiones tuyas que se contradicen en el código~~

> **CONTESTADA 2026-09-08 — gana la ALTERNATIVA A.** El usuario, viendo IC3 e IC3V en la OC de
> flejes: *"estos dos items de ordenes de compra en flejes hay que sacarlos porque esas dos partes
> de charcas se tratan como proveedor de servicio"*. Aplicado: `oc_bundle` ya no lista lo que un PS
> produce (IC3/IC3V), así que **la OC del Fleje 90 va sólo a Altrak** (`FLEJE90_BRUTO`, rubro
> Alambre) y el corte entra por Entrega PS. Charcas sigue en la pantalla **sólo como vendedor de
> bombillas** (BOM10/EP10/LLF8, que sí le compramos), y `crear_oc` ya no dispara la gemela con esos
> items (antes una OC de bombillas a Charcas generaba una OC de alambre a Altrak que nadie pidió).
> Eclipse → Aperam queda como estaba. Sub-preguntas (2) y (3) siguen abiertas: la merma real del
> corte (hoy 0) y qué significa el precio 1,715 USD de IC3/IC3V. Ver `CONOCIMIENTO_GP2.md` §4z.

- **Problema.** El 04/09 dijiste (`CONOCIMIENTO_GP2.md`, §Altrak/Charcas): *"la OC del Fleje 90 va
  SOLO a Altrak (kg de FLEJE90_BRUTO). NO hay OC gemela a Charcas — el corte se registra por la
  recepción, no por OC"*, y *"merma del corte de Charcas: sin dato, asumir 0"*. Pero el código
  siguió vivo con el modelo anterior (la pantalla de OC pide a Charcas en paquetes y `crear_oc`
  dispara sola la OC gemela a Altrak), y la auditoría del 05/09 (ciclos 9–10) lo **arregló y
  generalizó** en vez de apagarlo: hoy la OC de Charcas se guarda en kg (antes sumaba paquetes
  como kg, bug real) y la gemela sale por una regla única para cualquier PS híbrido. El 2 % de
  Charcas era un default inventado el 01/09: ya quedó en 0 (tu decisión). Las dos docs vivas
  (`CONOCIMIENTO` vs `REGLAS_OC_INSUMOS`) se contradicen hasta que contestes.
- **Por qué es duda.** Las dos formas cierran con el stock: (A) OC directa a Altrak y el corte
  entra por la recepción de Charcas; (B) OC a Charcas en paquetes y la gemela a Altrak sale sola.
  Cambia quién pide qué y qué hoja recibe cada proveedor.
- **Alternativa A (tu decisión del 04/09).** Se apaga la gemela para Charcas (bandera
  `proveedor_servicio.oc_gemela = false`), la pantalla deja de ofrecer a Charcas como proveedor de
  OC y el alambre se pide a Altrak como cualquier insumo. Eclipse → Aperam queda como está (Fase
  4, decidido el 01/09), aunque hoy no se puede pedir Eclipse desde la pantalla
  (`sector.oc_pide=false` en Procesado).
- **Alternativa B (lo que hace el código hoy).** OC a Charcas en paquetes → gemela a Altrak por
  kg × (1 + 0 %). Faltaría: vínculo padre–hijo entre las dos OC (anular una no anula la otra y la
  huérfana cruza contra la próxima recepción de Altrak), redondeo al envase de Altrak (¿kg sueltos
  o rollo mínimo?), y que `FLEJE90_BRUTO` deje de aparecer para pedir a mano (doble pedido).
- **Recomendación.** A: es lo último que decidiste y es más simple (una OC menos, sin vínculo
  padre–hijo que inventar). B sólo si de verdad querés que Charcas reciba una hoja de pedido.
- **Impacto.** A: 1 bandera + esconder a Charcas en la pantalla (media hora). B: vínculo entre OC,
  cascada al anular, norma de envase de Altrak (medio día).
- **Preguntas concretas.** (1) ¿A o B? (2) Si B: ¿cuánto alambre se pierde de verdad al cortar
  (hoy 0) y Altrak vende kg sueltos o rollo/atado mínimo? (3) El precio 1,715 USD de IC3/IC3V está
  cargado con `cod_prov` de Altrak: ¿es por kg de alambre de Altrak o por unidad de fleje cortado
  por Charcas? Con eso se valoriza hoy la OC de Charcas, y `FLEJE90_BRUTO` / `CHAPA430` no tienen
  precio (las gemelas salen sin valorizar).

---

## 21. El sector 13 «Alambre»: ¿es un sector de insumo comprado?

**Problema encontrado.** El sector 13 se creó el 2026-09-04 para `FLEJE90_BRUTO` (lo compra
Altrak, entra por el flujo Altrak de Recepción Insumos). Tiene `tipo = 'crudo'` (el mismo tipo que
el Sector Crudo de piezas propias) y rubro de OC 5 (sube a Fleje en la OC), pero **no está entre
los sectores de insumo** (`sector.es_insumo`, que hasta hoy era una lista fija de ids 5..11 adentro
de `_es_sector_insumo`).

**Por qué existe una duda.** Con `es_insumo = false` la lista genérica de Recepción no lo
muestra, `crear_recepcion_insumo` lo rechaza ("no es un insumo") y los máximos automáticos lo
saltean; hoy funciona sólo porque Altrak tiene su flujo propio. No sé si eso es lo buscado (Altrak
es especial) o un descuido al crear el sector.

**Alternativa A.** `update sector set es_insumo = true, tipo = 'fleje' where id = 13`: pasa a ser
un insumo comprado como Fleje/Plástico (aparece en Recepción y en máximos automáticos).

**Alternativa B.** Dejarlo como está (sólo entra por Altrak) y que `tipo` quede en `crudo`.

**Alternativa C** (revisión del experto, 2026-09-05). Mover `FLEJE90_BRUTO` al **sector 5 Fleje** y
jubilar el sector 13: es exactamente lo que ya se hizo con su gemelo `CHAPA430` el 2026-09-04.
Con eso `es_insumo` ya es verdadero, no hace falta inventarle ubicación al sector (el stock del
bruto sigue en Charcas, como el usuario ya decidió) y la regla A de `db/verificar.sql` queda en 0.

**Recomendación.** C. B contradice lo que el usuario ya dijo ("Altrak tiene que estar en prov
insumo flejes" y "la OC del Fleje 90 va SOLO a Altrak", `CONOCIMIENTO_GP2.md` §1): el alambre
**es** comprable. A no cambia nada en la práctica: `FLEJE90_BRUTO` ya entra a `oc_bundle` por la
rama del proveedor, pero con **sugerido 0**, porque nada consume el bruto (el consumo está en
`IC3` 150 uni/mes e `IC3V` 15): lo que falta de verdad es derivar la demanda del alambre de
IC3 + IC3V + merma de corte, y eso es un dato del usuario.

**Impacto.** Una línea de datos; ninguna función (`es_insumo` es la columna que leen las 6).
Dato agregado el 2026-09-05 (ciclo 2s): el sector 13 **no tiene ubicación** propia. Su único
componente, `FLEJE90_BRUTO` (50 kg), vive en la ubicación de Resortes Charcas (`cargar_compra_mp`
lo manda ahí), pero `ubic_de_componente()` lo resuelve a Virgilio. Si A, hay que decidir también
dónde "vive" el alambre bruto (¿ubicación "Sector Alambre" o la de Charcas?) — `db/verificar.sql`
(regla A) va a marcar el sector insumo sin ubicación hasta que se resuelva.

**Pregunta concreta.** ¿A, B o C? (con C el stock del bruto sigue en Charcas y el sector 13 se
borra; con A hay que decidir además dónde "vive" el alambre).

---

## 22. `entrega_prov_at` es un segundo ledger: ¿se deja o se lleva a `movimiento`?

**Problema encontrado.** Las entregas de los proveedores de artículo terminado (125 filas:
proveedor, cod_art, cajas, remito, factura) viven en `entrega_prov_at`, no en `movimiento`: no
mueven stock GP2 (van directo a Virgilio) y guardan datos comerciales que el ledger no tiene.

**Por qué existe una duda.** Es conceptualmente el mismo evento que "el tallerista entregó",
pero con destino Virgilio y sin `componente` (el `cod_art` es texto libre de `articulo_prov_at`,
sin FK a `articulo`). Unificar exige que cada artículo AT exista como componente terminado.

**Alternativa A.** Dejarla como está: registro comercial, no de stock.

**Alternativa B.** Cada entrega es un `movimiento` tipo `entrega_prov_at` hacia la ubicación
Virgilio; remito/factura en `nota` o en una tabla chica de facturas.

**Recomendación.** A por ahora. B sólo si se quiere ver el stock de Virgilio completo (propio +
AT) en una sola pantalla. **Nota del experto (2026-09-05):** A cierra con dos cosas que el usuario
ya dijo — "Virgilio no se analiza, existe sólo para medir a los talleristas" (§3) y "no cargar
`GP2.inventario` de Virgilio a mano, se desincroniza en una semana" (§4o). B además obligaría a
inventar 57 componentes (sólo 27 de los 84 `cod_art` de `articulo_prov_at` existen como
`componente`) y degradaría el checklist de Pagos, que lee remito/factura/fecha de esta tabla vía
`v_recepcion_unificada`. Si algún día se quiere ver Virgilio entero, el camino ya elegido es la
vista sobre el libro de Virgilio (idea 7243), no un segundo ledger.

**Impacto.** A: nada. B: tabla, RPC, pantalla Entregas AT y el espejo de Virgilio.

**Pregunta concreta.** ¿A o B?

---

## 23. Una OC en `borrador` se puede "recibir"

**Problema encontrado.** `_aplicar_recepcion_a_oc` cruza lo recibido contra las OC `enviada` **y
también** `borrador` (primero las enviadas). Una OC que nunca se mandó al proveedor queda
`recibida` sola.

**Por qué existe una duda.** Puede ser un descuido o puede reflejar la práctica (nadie marca
"enviada" y la mercadería llega igual).

**Alternativa A.** Cruzar sólo contra `enviada`; el borrador es un papel de trabajo.

**Alternativa B.** Como hoy.

**Recomendación.** A, y que la pantalla de OC avise "hay OC en borrador de este proveedor" al
recibir. **Nota del experto (2026-09-05):** hoy hay 0 OC en borrador y 0 enviadas (1 anulada):
todavía no hay práctica que respetar, así que es barato ahora y caro en un mes. Y mejor que un
botón "enviada" que alguien tiene que acordarse: marcarla `enviada` sola **al imprimirla**
(imprimir es mandar).

**Impacto.** Una línea en la función (+ una en la impresión si se elige "enviada al imprimir").

**Pregunta concreta.** ¿A o B?

---

## 24. La alerta «stock bajo mínimo» está apagada desde agosto

**Problema encontrado.** `alertas_bundle` trae la alerta desactivada con un motivo viejo
("stock negativo irreal"). Hoy el inventario cierra con el ledger (0 desvíos).

**Por qué existe una duda.** Falta la regla: avisar por `cantidad < minimo` por ubicación de
sector (lo que ya muestra Faltantes) o por `cantidad < maximo` (lo que pide la OC), y a quién.

**Alternativa A.** Reactivar con `minimo`, sólo sectores de insumo, mostrando la cantidad de
renglones (no la lista).

**Alternativa B.** Dejarla apagada; Faltantes y la OC ya cubren el aviso.

**Recomendación.** A. **Nota del experto (2026-09-05):** ojo con dos cosas. (1) "Avisar por
mínimo" es una regla NUEVA, no una reactivación: el faltante de Crudo/Procesado ya es automático
**por 1 cajón** (§2e), no por mínimo. (2) Si se prende sin filtrar, las 56 filas legítimas de la
pregunta 27 (mínimo > máximo por lugar físico) quedan encendidas para siempre. Alternativa que no
mete ruido: avisar por lo **accionable** (renglones con sugerido > 0 en la OC, o la cobertura en
días de §2e), y respetar que Sector Movimiento no lleva mín/máx ni carteles (§2c-undecies).

**Impacto.** Sólo `alertas_bundle` y la pantalla de Inicio.

**Pregunta concreta.** ¿A o B?

---

## 25. `recalcular_minimos()` hoy cambiaría 48 mínimos

**Problema encontrado.** Es una herramienta manual sin llamador; la última corrida fue el
2026-09-02 (respaldo en `db/respaldo_inventario_minimo_20260902.csv`). El consumo de la Est
Madre se movió desde entonces: correrla hoy cambia 48 mínimos.

**Por qué existe una duda.** Los máximos sí se recalculan solos cuando cambia la Est Madre
(`trg_maximos_est_madre`); los mínimos no. No sé si eso fue una decisión (los mínimos los fija la
persona) o quedó a medio hacer.

**Alternativa A.** Colgar `recalcular_minimos` del mismo trigger que los máximos: mínimo y máximo
salen del mismo consumo y no se desfasan.

**Alternativa B.** Seguir corriéndola a mano cuando el usuario lo pida.

**Recomendación.** A.

**Impacto.** Una línea en `fn_recalc_maximos_insumos`; la primera corrida cambia 48 mínimos.
Dos datos más (2026-09-05): (1) el comentario de `inventario.minimo_origen` dice que la función
"no pisa la carga original del usuario (null)", pero **sí la pisa** cuando hay consumo > 0 (697
filas tienen origen null; la guarda que sí tiene `recalcular_maximos_insumos` con `'fisico'` acá
no existe) — si A, conviene agregar esa guarda primero; (2) como el trigger cuelga de `est_madre`,
que se sincroniza sola desde `public.proyeccion_madre`, los mínimos se moverían solos; si eso
incomoda, la variante es un job diario en vez del trigger.

**Pregunta concreta.** ¿A o B? Si B: ¿la corro ahora? Si A: ¿con la guarda de `'fisico'`?

---

## 26. La entrega del tallerista está escrita DOS veces

**Problema encontrado.** La pantalla Entregas Talleristas usa el motor JS (`gp2-motor.js` →
`recepcionTall` arma las filas y las manda por `registrar_movimientos`: la entrega como
*transformación* entrada→salida más `consumo_tall` por las otras líneas del BOM). En la base
existe la RPC `crear_entrega_tallerista` (misma regla de negocio, otra forma en el ledger: la
salida "nace" y TODAS las líneas del BOM son `consumo_tall`) **que ninguna pantalla llama**.

**Por qué existe una duda.** El inventario queda igual por los dos caminos; lo que cambia es
cómo se lee después el ledger, y la filosofía GP2 dice que el motor vive en la base.

**Alternativa A.** La pantalla llama la RPC por renglón (ya acepta `p_comp_entrada_id` para el
caso ambiguo y descuenta el BOM) y `recepcionTall` se borra del JS.

**Alternativa B.** Se borra la RPC y el JS queda como única implementación.

**Recomendación.** A, con `test_entregas_tall_gp2.js` reescrito al contrato de la RPC.

**Impacto.** Una pantalla, un test, ~80 líneas menos de JS (idea 7260).

**Pregunta concreta.** ¿A o B?

---

## 27. 80 renglones de inventario tienen el mínimo por ENCIMA del máximo

**Problema encontrado.** `[dato 2026-09-05]` En 80 filas de `inventario` el `minimo` es mayor que
el `maximo`: 30 en Sector Procesado, 30 en Crudo, 10 en Bombilla, 4 en Remache, 3 en Plástico,
2 en Cartón, 1 en Caja. Ejemplos: `Z23` mínimo 87.892 / máximo 11.630; `X1` 87.892 / 20.020;
`W6` 29.124 / 25.000. El mínimo sale de `recalcular_minimos` (consumo de la Est Madre × meses) y
el máximo de la regla "5 cajones por ubicación" (`maximo_origen = cinco_cajones`) o de la Est
Madre — dos reglas que nadie cruzó.

**Por qué existe una duda — corregida el mismo día.** El usuario YA decidió esto el 2026-09-02
(`CONOCIMIENTO_GP2.md` §2e-bis): *"mínimo > máximo puede ser correcto: no es un dato para
arreglar, es la planta, y el que compra tiene que saberlo"* y *"topearla sería tapar la señal"*.
O sea: **no se topa el mínimo al máximo** (la primera versión de esta pregunta proponía eso y
contradecía esa decisión; queda anulada). Lo que sí salió al desarmar las 80 filas por causa
`[dato 2026-09-05]` es que **no son un problema sino tres**:

1. **56 filas `cinco_cajones`** (Crudo/Procesado): el lugar físico es más chico que el consumo.
   Es la planta; se dejan y el que compra lo ve.
2. **10 filas de Bombilla son una contradicción de parámetros**: la ubicación Sector Bombilla
   tiene `meses_minimo = 4` y `meses_stock = 3`, así que **todo** componente con consumo da
   mínimo > máximo por aritmética (BOM8: 12.784 / 10.668 = 4/3 exacto). No es la planta, es un
   parámetro mal puesto. Y no es sólo Bombilla: Crudo y Procesado también tienen
   `meses_minimo 2 > meses_stock 1` (ahí no se nota porque el máximo es "5 cajones", no meses).
3. **14 filas sueltas** (Procesado 4 con máximo de Est Madre, Plástico 3, Remache 4 con máximo
   `fisico`, Cartón 2, Caja 1): el pliego `Pliego Ad 506` tiene mínimo 67.872 (4 meses) contra
   máximo 8.484 (6 meses) — consumos que difieren 12×, huele a unidad de pliego, no a negocio.

**Alternativa A.** Corregir los parámetros: `ubicacion.meses_minimo ≤ meses_stock` en Bombilla,
Crudo y Procesado (¿4→3? ¿o `meses_stock` 3→4?), recalcular mínimos y máximos juntos (pregunta
25 A), y mirar una por una las 14 sueltas. Las 56 de cinco cajones no se tocan.

**Alternativa B.** Dejar todo como está (el que compra sabe).

**Recomendación.** A. El invariante que sí sirve para `db/verificar.sql` no es "mínimo ≤ máximo"
(marcaría 56 filas legítimas para siempre) sino **"ninguna ubicación con `meses_minimo >
meses_stock`"** — hoy da 3.

**Impacto.** Tres filas de `ubicacion` (parámetros del usuario) + una corrida de mínimos/máximos +
14 filas a mano. Faltantes y la OC dejan de contradecirse en Bombilla/insumos; en Crudo/Procesado
siguen "gritando" a propósito.

**Pregunta concreta.** ¿A o B? Si A: en Bombilla, Crudo y Procesado, ¿bajo `meses_minimo` o subo
`meses_stock`?

---

## Anexo A — las 58 páginas del programa viejo (para las preguntas 1, 2 y 3)

`[dato 2026-09-05]` Todo `.html` del repo que no es `_GP2` ni parte de GP2 (menú, login, tablet,
calculadoras, `Programa`, `Validacion_Stock`, `OrdenProduccion`, `control-cajas/remaches`), con el
peso de su JS propio y si toca la casa del vecino. Ninguna la linkea el menú GP2 salvo
*Recepción Virgilio* ("app vieja"); la tablet linkea 4 (pregunta 2).

| Página | KB (con su JS) | Base | JS propio |
|---|---|---|---|
| `Alertas/index.html` | 15 | pega a `public` | app.js |
| `Compras/cajas.html` | 50 | pega a `public` |  |
| `Control Envios y Entregas/exportar.html` | 26 | pega a `public` | exportar.js |
| `Control Envios y Entregas/index.html` | 26 | pega a `public` | app.js |
| `Control Envios y Entregas/stock.html` | 33 | pega a `public` | stock.js |
| `ControlRemitos/index.html` | 9 | pega a `public` | controlRemitos.js |
| `Despiece x Articulo/index-inverso.html` | 33 | pega a `public` | app-inverso.js |
| `Despiece x Articulo/index.html` | 27 | pega a `public` | app.js |
| `Despiece/Despiece.html` | 49 | pega a `public` | Despiece.js |
| `Disruptivas/index.html` | 20 | pega a `public` | disruptivas.js |
| `Facturas/EntregaProveedoresCervantes.html` | 22 | pega a `public` |  |
| `Facturas/index.html` | 97 | pega a `public` |  |
| `Informes/index.html` | 134 | pega a `public` | informes.js |
| `Preavisos/index.html` | 10 | pega a `public` |  |
| `Produccion/InformesVirgilio/index.html` | 123 | pega a `public` | calculo.js, renderer.js |
| `Produccion/ProblemasMatrices/index.html` | 15 | pega a `public` |  |
| `Produccion/RegistroApp/index.html` | 124 | pega a `public` | app.js |
| `Produccion/abm.html` | 16 | pega a `public` |  |
| `Produccion/entrevistas.html` | 44 | pega a `public` |  |
| `Produccion/import.html` | 21 | pega a `public` |  |
| `Produccion/maestro.html` | 76 | pega a `public` |  |
| `Produccion/monitor.html` | 46 | pega a `public` |  |
| `Produccion/monitor2.html` | 15 | pega a `public` |  |
| `Produccion/rendimiento.html` | 49 | pega a `public` | rendimiento.js |
| `Produccion/tiempos.html` | 71 | pega a `public` |  |
| `Prov Art Terminado/Control/ControlAT.html` | 26 | pega a `public` | ControlAT.js |
| `Prov Art Terminado/Entregas/EntregasAT.html` | 1 | pega a `public` |  |
| `Prov Art Terminado/Envios/EnviosAT.html` | 11 | pega a `public` | EnviosAT.js |
| `Prov Serv/Control/ControlPS.html` | 43 | pega a `public` | ControlPS.js |
| `Prov Serv/Entregas/EntregaPS.html` | 53 | pega a `public` | EntregaPS.js |
| `Prov Serv/Envios/EnviosPS.html` | 82 | pega a `public` | EnviosPS.js |
| `StockFlejes/bombillas.html` | 18 | pega a `public` | bombillas.js |
| `StockFlejes/cajas.html` | 44 | pega a `public` | cajas.js |
| `StockFlejes/cartones.html` | 39 | pega a `public` | cartones.js |
| `StockFlejes/flejes.html` | 37 | pega a `public` | stock-flejes.js |
| `StockFlejes/garage.html` | 11 | pega a `public` | garage.js |
| `StockFlejes/index.html` | 1 | sin base |  |
| `StockFlejes/plasticos.html` | 26 | pega a `public` | plasticos.js |
| `StockFlejes/recepcion.html` | 108 | pega a `public` |  |
| `StockFlejes/remaches.html` | 21 | pega a `public` | remaches.js |
| `StockMovimiento/StockMovimiento.html` | 16 | pega a `public` | StockMovimiento.js |
| `StockSC/StockSC.html` | 28 | pega a `public` | StockSC.js |
| `StockSP/StockSP.html` | 38 | pega a `public` | StockSP.js |
| `StockTransitoPS/index.html` | 15 | pega a `public` | StockTransitoPS.js |
| `Stocks General/StocksGeneral.html` | 45 | pega a `public` | StocksGeneral.js |
| `Talleristas/ABM Articulos/ABMArticulosTall.html` | 14 | pega a `public` | ABMArticulosTall.js |
| `Talleristas/Control Tall/ControlTall.html` | 101 | pega a `public` | ControlTall.js |
| `Talleristas/Envios/EnviosTall.html` | 78 | pega a `public` | EnviosTall.js |
| `Talleristas/Faltante Partes Tallerista/index.html` | 123 | pega a `public` | ControlTall.js, faltante.js |
| `Talleristas/Proporciones/index.html` | 13 | pega a `public` | proporciones.js |
| `Talleristas/Recepcion/Devolucion Cervantes.html` | 29 | pega a `public` |  |
| `Talleristas/Recepcion/Entrega Cervantes Fotos.html` | 45 | pega a `public` |  |
| `Talleristas/Recepcion/Recepcion Cervantes.html` | 51 | pega a `public` |  |
| `Talleristas/Recepcion/Recepcion Virgilio.html` | 25 | pega a `public` |  |
| `Ventas Chat/index.html` | 15 | sin base | chatbot.js |
| `VerifMadres/VerifMadres.html` | 12 | pega a `public` | VerifMadres.js |
| `Verificacion/verificacion.html` | 42 | pega a `public` | verificacion.js |
| `calcular-cajones.html` | 17 | pega a `public` |  |

58 páginas, 2409 KB en total; 56 pegan a `public`.

---

## Cómo responder

Con el número y la letra alcanza ("1B", "21A"...). Lo que se responda se aplica en la sesión
siguiente y se tacha acá.
