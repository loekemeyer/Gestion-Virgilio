# CONOCIMIENTO_GP2 — memoria del negocio

> **Qué es esto.** El conocimiento del negocio que hoy vive en la cabeza del usuario,
> escrito para que no haya que volver a explicarlo. Cada vez que el usuario cuenta **cómo
> funciona algo, por qué se hace así, o qué decidió**, entra acá en el mismo commit.
>
> **Para qué.** Para que el agente `gp2-experto` (ver `.claude/agents/gp2-experto.md`)
> pueda hacer de contraparte: cruzar una idea, decir si cierra o no con lo que ya sabemos,
> y proponer alternativas — en vez de que el usuario tenga que re-explicar el contexto
> cada vez.
>
> **Regla de oro (igual que en CLAUDE.md): esto es conocimiento REPORTADO, no inventado.**
> Cada afirmación dice de dónde salió: `[usuario]` lo dijo una persona, `[dato]` sale de
> una consulta a la base (con la consulta o la tabla), `[deducido]` lo infirió el agente y
> **está sin confirmar**. Nunca borrar el origen. Si algo cambia, se corrige la línea y se
> deja la fecha nueva — la historia fina está en git.

---

## 0. Cómo trabaja el usuario (reglas de laburo, no de negocio)

### 🚨 TODO SE SUBE A `main`. SIEMPRE. SIN RAMAS.
`[usuario 2026-08-31, textual]` *"SIEMPRE TODO TENES QUE SUBIRLO A MAIN. NO QUIERO DECIRLO
MAS EN NINGUNA SESION."* Ya lo había dicho el 2026-08-30 (*"no quiero ramas, solo en main"*)
y hubo que repetirlo: **no volver a preguntarlo ni a proponer una rama.**

- Si la sesión arranca con una rama asignada por configuración, el destino final sigue siendo
  `main`: `git push origin <rama>:main`.
- La red de seguridad **no es la rama, es la suite**: `bash tests/ui/run.sh` en verde antes de
  pushear.
- **Por qué le importa tanto**: lo que se aplica en **Supabase queda vivo al instante y git no
  lo versiona**. Si el código se queda en una rama, la base tiene los cambios y `main` no
  tiene las pantallas que los acompañan. Pasó el 2026-08-31 con 5 commits (golpes, pinza de
  fiambre, matriz 62, pesaje, 506 con skin) mientras las migraciones ya estaban corriendo en
  producción. **Ese desfasaje es el riesgo real, no el de pushear a main.**

Está también arriba de todo en `CLAUDE.md`.

---

### Si CONOCIMIENTO ya lo aprueba, se hace `[usuario 2026-09-02]`

Dicho textual: *"Si encontras cosas para resolver que conocimientos aprueba, dale curso"*.

Cuando una auditoría (propia o de un agente) encuentra algo para arreglar, **no se pregunta
si el arreglo ya está decidido en este archivo**. Se aplica y se avisa después.

**Se aplica solo** cuando el arreglo se apoya en algo ya escrito acá: un patrón fijado
(crudo → niquelado, gemelos LK/Chef, el paso de tallerista que declara su entrada,
`estado_compra='fabricacion'` para un intermedio que sale de un proceso propio), una regla
de pantalla de la casa (letra grande, `inputmode`, `.table-wrap`, 390px), un test que quedó
viejo respecto de la pantalla, o un número que se deduce de un dato ya confirmado.

**Se anota y NO se toca** cuando hace falta un dato de negocio que no tenemos (un precio,
una tarifa, un tiempo de matriz), cuando contradice algo ya documentado — ahí primero se
revisa cuál de los dos está viejo — o cuando mueve plata en muchos artículos a la vez: eso
lo mira el usuario antes.

La contracara de esta regla es que **este archivo tiene que estar al día**: si algo se
decidió y no está escrito acá, nadie le puede dar curso.

## 0-bis. Los agentes de GP2 (creados el 2026-08-31)

Además de `gp2-experto` (que **discute** ideas de negocio, no ejecuta) el repo tiene 4
agentes que **ejecutan** tareas concretas, en `.claude/agents/*.md`. Cada uno arranca leyendo
CLAUDE.md y CONOCIMIENTO_GP2.md, así que evoluciona con este archivo.

| Agente | Cuándo se invoca solo | Modelo | Puede escribir |
|---|---|---|---|
| **`gp2-cirujano`** | Cambio de producto/proceso que toca la cadena normalizada (recetas, rutas, alias). Snapshot antes / diff después. | opus | sí — schema + código |
| **`gp2-auditor-costos`** | Un número de plata huele mal, después de cargar precios/tiempos, o barrido periódico. Devuelve hallazgos + arreglo propuesto. | opus | **NO — solo lectura** |
| **`gp2-cargador-excel`** | Cargar planilla del usuario a la base (precios, pesos, `uni_x_golpe`, maestros). Matcheo por id; lo dudoso devuelve como preguntas, no lo escribe. | sonnet | sí — schema |
| **`gp2-verificador-ui`** | **SIEMPRE antes de pushear a main** si se tocó HTML/JS/CSS (es el gate que exige la sección "Versionado" de CLAUDE.md). Corre la suite + reglas de pantalla. | sonnet | **NO — solo lectura** |

Reglas comunes que ya viven adentro:
- Nada de decidir por su cuenta: las dudas se devuelven en una sección **PREGUNTAS
  BLOQUEANTES** de su reporte final, para que la sesión principal las eleve al usuario.
- Los códigos NO son únicos (`A10`/`C10`/`B4`...): todo por `id`, todo `where` filtra
  también por sector.
- Snapshot de costos en tabla real `_bak_YYYYMMDD` (no temp, porque cada `execute_sql` es
  conexión nueva).
- En SQL crudo, el schema **siempre** entre comillas: `"GP2"`.

## 1. Proveedores: quién provee qué

### Inyección plástica — son tres
`[usuario 2026-08-29]` Los inyectores son **Pat Bet Plast**, **Pettofrezza Rafael** y
**Kollplast**. Principalmente dos.

- **Pat Bet Plast** se escribe así, literal. `[dato: public.Partes_Plasticas]`
- **Pettofrezza Rafael** es **la misma persona** que el tallerista que arma 15 terminados
  y que el proveedor de artículo terminado que figura como "Pettofrezza". `[usuario]`
  Un mismo nombre puede tener **varios roles** en GP2 — no asumir que un nombre = un rol.
- **Kollplast** no existía en GP2 ni en la base del vecino: es alta nueva. `[dato]`
- **Becker Sandra Nora NO hace inyección plástica.** Es proveedor de **servicio**
  (pintura / serigrafía de piezas metálicas). `[usuario, corrigiendo un dato previo]`
- **Becker Sandra Nora ES "Jade".** `[usuario 2026-08-30]` El mismo pintor con dos nombres:
  GP2 lo tiene como *Becker Sandra Nora* (el nombre formal) y en la casa del vecino figura
  como *Jade* (como se lo nombra todos los días). No son dos proveedores. Otra vuelta de la
  trampa de siempre: **el mismo nombre escrito distinto en las dos casas**.
- **El reparto YA ESTÁ HECHO** `[usuario 2026-09-02, verificado en la base]`. La nota vieja
  decía "PENDIENTE: repartir los 29 plásticos, hoy están todos bajo Pat Bet Plast" y **eso
  ya no es cierto**. Foto real de `GP2.componente` del Sector Plástico (37 piezas):
  - **Pat Bet Plast (19)**: PA1, PA2, PA7A, PA7B, PA8A, PA8B, PA9, PA10B, PA12, PA13,
    PA18, PA19, PB6, PB8A, PB8B, PC7, PC10, PC11, PC16.
  - **Pettofrezza Rafael (12)**: PA4, PA5, PB5, PC1A, PC1B, PC8, PC13, PC14, PC15A, PC15B,
    PEP1, PEP4.
  - **Máspoli SRL (3)**: PC12, PEP7, PEP8.
  - Y los tres que no son plástico inyectado aunque vivan en esa zona (el sector es la
    zona física, ver §1-bis): **PEP5** mango de madera → Pintos, **PCP3** clavo →
    Trefilados Industriales, **D9** clavo niquelado → sin proveedor porque no se compra
    (sale del niquelado de Guazzaroni).
  - **Kollplast se quedó sin piezas asignadas**: figura como inyector pero no tiene ninguna.
    Pendiente menor: confirmar si le corresponde alguna o si por ahora no le compramos.

### `D1` (Espiral Sacacorcho): lo importado con su margen a la vista `[usuario 2026-09-02]`

Dicho textual: *"D1: costo TN 0.067usd. Vende a LK a 0.24usd"*.

- **El precio que carga GP2 es USD 0,24 por unidad** — lo que **paga Loekemeyer**. Es el
  número que va a `precio_proveedor` y el que usa el motor de costos.
- Los **USD 0,067 son el costo de la contraparte**, no el nuestro. Se anota igual porque es
  el único caso donde tenemos las dos puntas: **nos lo venden a 3,6 veces su costo**. Si
  algún día se discute importar directo, ese es el número de la conversación.
- D1 está como `estado_compra = 'importado'` y **ninguna ruta lo produce**: entra comprado y
  va a los **6 sacacorchos** (520, 521, 530, 531, 581, 730), 1 por unidad.
- **Impacto**: los 6 suben **$368,40** cada uno y quedan con `faltan_precios = 0`. En el
  **581** pesa fuerte — pasa de $331,20 a $699,60, o sea que **el espiral es más de la mitad
  del costo del sacacorchos**.
- **"TN" es Tierra Nativa SA** `[usuario 2026-09-02]`, `cod_prov` **3917**. D1 ya quedó
  asignado a ella, con el `cod_prov` en la fila de precio.

### Tierra Nativa SA (3917): nos VENDE, no arma `[usuario 2026-09-02]`

Dicho textual: *"Tierra nativa (Prov art importados y 231,232,233,234,591). Prov 3917"*.

- Es **proveedor de artículos TERMINADOS IMPORTADOS**: nos vende **231, 232, 233, 234 y
  591** ya hechos. Cargados en `GP2.articulo_prov_at`. **Sólo el 234 tiene descripción**
  (*Palo de Amasar Francés 40 cm*, sale del despiece del vecino); los otros cuatro quedaron
  en null a propósito — el usuario los tiene que dictar, no se inventan.
- Además nos vende **insumos importados sueltos**: el espiral de sacacorchos **D1**.
- **Rol dual mal cargado**: estaba **sólo** en `GP2.tallerista` (id 12, con el 3917 ya
  puesto, cero rutas y cero precios). Ese rol es el equivocado — no arma nada. Se dio de
  alta donde corresponde (`proveedor_at`, y también `proveedor_insumo` porque
  `componente.proveedor` es FK contra esa tabla). **La fila de tallerista sigue existiendo**:
  no se borra sin que el usuario lo confirme, pero ensucia el listado de talleristas.
- **RESUELTO 2026-09-04** `[usuario: "no quiero que aparezca más Tierra Nativa SA en
  tallerista... envío y en control"]`: `GP2.tallerista.activo = false` para el id 12. La
  fila **no se borró** (sigue el historial y el `cod_prov`), pero `talleristas_bundle`
  filtra `where t.activo`, así que **desaparece de Envío Talleristas y de Control
  Talleristas** — y de cualquier pantalla que use ese bundle. Se verificó antes de tocar:
  0 pasos de ruta, 0 movimientos y 0 de stock en su ubicación, así que no esconde nada.
  Mismo mecanismo que Maspoli SRL (id 7). **Blist-Pack (13) sigue visible.**
- Es otra vuelta de la regla de siempre: **un mismo nombre puede tener varios roles**, y hay
  que fijarse en cuál es el que de verdad cumple antes de cargarlo.

### No todo insumo se compra
`[usuario 2026-08-29]` Una parte sin proveedor no siempre es un dato que falta: puede ser
una **decisión ya tomada**. Por eso `componente.estado_compra`:

- **`fabricacion`** — se hace adentro. Los **resortes C9 (Resorte U Crom), D14, I2 e I3**
  se fabrican (confirmado también por sus rutas: los producen las matrices 47 y 69, FAAT,
  Guazzaroni y Pedernera). Los **GRJ del Garage** también.
- **`discontinuo`** — ya no se usa: **BOM10** (Resorte Bicónico) y **C12** (Paleta Batidor
  Resorte).
- Los que **sí se compran** pero todavía no tienen proveedor: **EP10** y **LLF8**
  (Resorte Batidor Mini y Batidor Pera; LLF8 se compra igual que EP10) y los remaches
  V4, V10, V14, V18D, CV13, CV18D. Los **remaches se compran todos**. `[usuario]`
- **V13 → Electronica Mandelli** y **W8 → Imel**. `[dato: public."Remaches SP/SC"]`
- **`PB8B` (Inser. Neg. Batidor Calado): se COMPRA a Pat Bet Plast (plástico crudo) y
  DESPUÉS se CALA en fábrica.** `[usuario 2026-09-02]` O sea el proveedor **Pat Bet Plast
  está BIEN** (sí se compra, sí va en Recepción). Lo que le falta al modelo es el **paso
  de calado interno** (una ruta/proceso propio sobre el plástico comprado) — hoy figura
  como plástico comprado a secas, sin ese paso `[deducido: GP2.componente]`. No es
  `fabricacion` pura ni compra directa a secas: es **compra + proceso propio** (patrón
  parecido al crudo→niquelado de los remaches, pero acá el proceso lo hacemos nosotros).
- **`PC1A` (Mgo Pelapapa 505 Calado): se COMPRA a Pettofrezza Rafael (crudo) y lo CALA
  Esther** (proveedor de servicio, proceso Calado). `[usuario 2026-09-02]` El proveedor de
  compra **Pettofrezza Rafael está BIEN**; falta modelar el paso de **calado de Esther (PS)**.
  Mismo patrón compra+proceso que PB8B, pero acá el proceso lo hace un PS, no nosotros.
  Se confirmó que Esther no estaba en `GP2.proveedor_servicio` (eran 12 PS) y se la **dio de
  alta el 2026-09-02** (`id 14`, proceso *Calado*, migración `alta_ps_esther_calado`;
  `cod_prov` queda null hasta que el usuario lo aporte) `[dato: GP2.proveedor_servicio]`.
  **Esther cala los DOS mangos, no solo el 505** `[usuario 2026-09-02]`: **PC1A** (Mgo
  Pelapapa 505 Calado) y **PC1B** (Mgo Pelapapa 123) — "el mango que se usa para 505 y para
  123". Los dos se compran a Pettofrezza Rafael y los dos pasan por el calado de Esther.
  **Falta todavía la ruta**: el paso `proveedor_servicio` crudo → calado no está cargado
  (ni para PC1A ni para PC1B), y sin tarifa de Esther el costo de ese calado sigue en 0.
  **Traba concreta**: hoy NO existe un componente "crudo" (sin calar) separado de PC1A/PC1B,
  y sin ese par crudo→calado no se puede trazar el paso sin inventar un componente nuevo.
- **`PCP3` (Clavo 505): se compra a Trefilados Industriales.** `[usuario 2026-09-02]` Compra
  directa (sin proceso). **Ya aplicado** `[dato: GP2, verificado 2026-09-02]`: Trefilados
  Industriales está en el maestro `proveedor_insumo` (rubro *Sector Plástico*) y PCP3
  (`id 256`) lo tiene asignado en `componente.proveedor`. **Que esté en Sector Plástico
  siendo un clavo metálico ESTÁ BIEN** `[usuario 2026-09-02]`: el sector es la **zona
  física** donde vive la pieza, no el material del que está hecha — en la zona de plásticos
  también hay cosas que no son plásticas, y el clavo es una de ellas (ver §1-bis). No se
  toca. Lo que sí quedó abierto es el **precio**, más abajo.
- **`PEP5` (Mango Madera): se compra a Eduardo Pintos.** `[usuario 2026-09-02]` En la base
  ya figura con proveedor **"Pintos"** = **Eduardo Pintos** (el que hace la madera). Ya está
  bien asignado; se anota el nombre completo. **Decisión 2026-09-02: NO se renombra el
  maestro** `proveedor_insumo` "Pintos" → "Eduardo Pintos" `[deducido, revisado con el repo]`.
  Motivo: "Pintos" es el nombre de todos los días y aparece con ese string en la casa del
  vecino y en el código que la lee — `Talleristas/Control Tall/ControlTall.js` (rol dual
  Maspoli/Pintos), `Facturas/EntregaProveedoresCervantes.html` (`SECTOR_SC_POR_PROV`),
  `StockFlejes/recepcion.html` y `tests/ui/test_entregas_at.js`. Renombrarlo solo en GP2
  vuelve a abrir la trampa de siempre (el mismo proveedor escrito distinto en las dos
  casas). Si algún día se renombra, se renombra en los dos lados y en el mismo commit.

Marcar el estado **saca la parte de la Orden de Compra** y deja de contarla como faltante.
NO se usa el campo `proveedor` para esto: la OC agrupa por proveedor y terminaría
ofreciendo comprarle a un proveedor llamado "Discontinuo". Se marca desde la misma
pantalla de Inyectores, con los botones **Se fabrica** / **Discontinuo**.

### 1-bis. El sector es la ZONA FÍSICA, no el material `[usuario 2026-09-02]`

*"El sector es sector plástico… si está en la zona de sector plásticos, pero además de haber
cosas plásticas hay cosas que no son plásticas, por eso es que está ahí. Es correcto que eso
esté ahí."*

`GP2.sector` (y la `ubicacion` tipo *sector*) dice **dónde está guardada** la pieza en la
planta, no de qué está hecha. Que en *Sector Plástico* haya un clavo de acero o un mango de
madera **no es un error de carga**: es que ese cajón está en esa zona. **Nunca "corregir" un
sector por el material de la pieza** — se corrige solo si la pieza cambió de lugar físico.
Esto vale para todo el sistema: Recepción Insumos agrupa por sector (el chip *Plásticos*
muestra el clavo, y está bien), y el rubro del proveedor sale del mismo lado.

### El clavo 505 se NIQUELA antes de ir al tallerista `[usuario 2026-09-02, aplicado]`

El usuario preguntó *"¿el clavo primero se niquela o va directo al tallerista?"*. Se
niquela. La cadena real es:

```
PCP3 (clavo crudo, comprado) → Guazzaroni (niquelado) → D9 (clavo niq.) → tallerista → Virgilio
```

`[dato: public."Partes x PS" id 237]` — PS *Guazzaroni*, parte *"Clavos 505"*, **SC `PCP3`
→ SP `D9`**, proceso *Niquelado*, `KG x Uni 0,00653` (el mismo peso que tiene GP2). Y en
`public."Despiece x Articulo"` cada uno de los 7 artículos lleva **dos** líneas: `PCP3
"Clavos 505"` y `D9 "Clavos Niq."`, 1 por unidad. Es el mismo patrón que los remaches
(`CV9 → Guazzaroni → V9`), tal como anticipaba la nota que arrastraba el precio.

**Dónde se usa**: 7 artículos, 1 clavo por unidad — **099, 108, 123, 505, 513, 586, 713**.
**8 rutas** (el 505 tiene dos, una por tallerista): IJUPA arma 108/513/713, Lucho
123/505/099/586, Danica García la segunda del 505.

**Lo que se aplicó el 2026-09-02** (migraciones `clavo_505_paso_niquelado_patron_remaches`,
`d9_mismo_sector_que_el_crudo`, `clavo_tallerista_declara_entrada_d9`,
`clavo_stock_talleristas_pcp3_a_d9`, `precio_clavo_505_proveedor_trefilados`):

- **`D9` (Clavo 505 Niq.) creado** con `kg_x_uni 0,00653` y `estado_compra 'fabricacion'`
  (no se compra: se compra el crudo). Vive en el **mismo sector que su crudo**, Sector
  Plástico — igual que `CV9` y `V9`, que están los dos en Sector Remache.
- Las **8 rutas pasan de 3 pasos a 4**: `ingreso PCP3` → `proveedor_servicio PCP3→D9
  (Guazzaroni)` → `tallerista` → `virgilio`. Se renombraron a `Insumo D9 -> Art N` (con eso
  muere el `CLV505`, que no existía como componente en ningún lado).
- **`articulo_componente` ahora apunta a D9**, no a PCP3: el artículo lleva el clavo
  niquelado, igual que los remaches listan `V9` y no `CV9`.
- **El stock de tallerista pasó de PCP3 a D9** por `GP2.movimiento` (transformación en la
  misma ubicación): IJUPA tenía −4.908 y ese rojo es del niquelado, que es lo que consume.
  Los mínimos (Danica 15.000, Lucho 27.108, IJUPA 20.892) también se movieron a D9. El
  crudo PCP3 queda solo en Sector Plástico (720 uni), que es donde entra.
- **Costo**: el niquelado son **$17,02 por clavo** (0,00653 kg × $2.606/kg, tarifa
  Guazzaroni). Los 7 artículos suben ese monto, salvo el **505**, que además **dejaba de
  contar el clavo dos veces** (tenía dos rutas y el CTE viejo sumaba una por ruta): pasa de
  $493,57 a $477,51. Los otros: 099 $267,59→$284,61 · 108 $276,21→$293,23 ·
  123 $175,99→$193,01 · 513 $403,70→$420,72 · 586 $300,71→$317,73 · 713 $391,45→$408,47.
- **Precio**: la fila (`id 234`) pasa a nombre de **Trefilados Industriales** `[usuario]`.
  Los **USD 3,30 por kg quedan marcados como NO confirmados** — venían de la fila vieja a
  nombre de Altrak y el usuario dijo que el costo no lo sabe. `cod_prov` a null (el 3789 era
  de Altrak).

### ⚠ El paso de tallerista tiene que declarar QUÉ ENTRA `[hallazgo 2026-09-02]`

`v_costo_componente` arma el grafo de la ruta en el CTE `edges`, y **solo toma los pasos que
tienen `comp_entrada_id` Y `comp_salida_id`**. Si el paso `tallerista` viene con la entrada
en null, la cadena se corta ahí: **lo que entró al tallerista nunca llega al costo del
artículo**. Las rutas de fleje lo declaran bien (ruta 44: `tallerista` entrada `A8` → salida
`103`), pero el patrón "Insumo X → Art Y" de los crudos niquelados quedó con la entrada
vacía.

Por eso, al pasar el clavo a ese patrón, los 7 artículos perdían el clavo entero. Se
arregló declarando la entrada (`D9`) en el paso de tallerista de las 8 rutas.

**Lo mismo le pasaba a 52 rutas de 12 remaches** (`V1, V2, V3, V4, V5, V6, V7, V8, V9,
V12, V13, V18D`): su crudo y su niquelado no entraban en el costo del artículo.
**Arreglado el 2026-09-02** (idea 7210, autorizada por el usuario; migración
`remaches_tallerista_declara_entrada`): la entrada del paso de tallerista pasa a ser la
pieza que sale del paso de servicio de esa misma ruta — el remache ya niquelado, que es
lo que el tallerista realmente recibe. **35 artículos subieron, ninguno bajó**, entre
**+$5,92 y +$45,14** cada uno (~+$913 en total). Quedan **0 rutas** con la entrada en
null en ese patrón.

**Regla para adelante:** toda ruta nueva tiene que declarar `comp_entrada_id` en el paso
de tallerista. Si queda en null, el costo de lo que entra se pierde en silencio — no
falla nada, simplemente el artículo sale más barato de lo que es.

### Resto de los rubros
- **Cartones → Talleres Gráficos Pol**, siempre el mismo, los 85. `[usuario]`
- **Cajas → Corrugadora del Sur**, siempre el mismo, las 9. `[usuario]`
- **Flejes →** cada uno tiene el suyo (Basconia, Aperam, Hermac, Brawin, Szapiro,
  JL Metales, Altrak). `[dato: GP2.fleje_detalle]`. **EstaMetal salió de circulación**
  `[usuario 2026-09-01]`: se filtra del listado de proveedores y sus insumos ya no
  aparecen en Recepción; la data cruda del componente queda en la BD para no perder
  historial, si se quiere purgar pasa por gp2-cirujano.

### Recepción de flejes: qué informa cada proveedor en el remito `[usuario 2026-09-01]`
El popup de Recepción Insumos arma los campos según el proveedor (además del **KG
total** que va siempre):

### Altrak → Charcas → Cervantes/Virgilio (Fleje 90 corto/largo) `[usuario 2026-09-02..04, CORREGIDO 2026-09-04 contra BD]`
Altrak vende **una sola varilla**: `FLEJE90_BRUTO` (id 583, kg, prov Altrak,
sector 13 Alambre, ubic 13 Prov. Serv. Charcas) — el alambre entero antes de
cortar. Charcas es **prov_servicio**: **solo corta el alambre a medida** (no le
da forma), cobra el servicio de corte (ISIS único **4596**, ~$9,50 al 2026-08-05).
Diferencia clave con Eclipse: Eclipse **da forma** (corta+dobla) → SP; Charcas
**solo corta** → sigue siendo fleje.

**Un mismo alambre, dos MEDIDAS de corte** `[usuario 2026-09-04]`:
- **CORTO → `IC3` (id 214)** — kg, prov Resortes Charcas, sector 5 (Fleje),
  `kg_x_uni=0,0083`. Se **guarda en Cervantes** (Sector Fleje). Lo usan los
  arts **031, 120, 836**.
- **LARGO → `IC3V` (id 373)** — kg, prov Resortes Charcas, sector 5,
  `kg_x_uni=0,0134`. **Va directo a Virgilio** (se guarda allá; IJUPA lo va a
  buscar para armar). Lo usan los arts **034, 867**.
- Los códigos siguen la **estantería**, no el número del fleje (I=insumo + C3;
  IC3V = variante Virgilio/largo). El nombre real es "Fleje N° 90".

**⚠️ CORRECCIÓN 2026-09-04 — reemplaza el modelo viejo IF90/IF90B/ALAM_FILTRO:**
antes esto se modelaba como `IF90`/`IF90B` (Filtro Café / Gastronómico) +
`ALAM_FILTRO`. Se remodeló a **corto/largo**:
- `ALAM_FILTRO` → renombrado **`FLEJE90_BRUTO`** (mismo id 583).
- `IF90` (id 372) era **duplicado de IC3** (mismo kg_x_uni 0,0083, misma prov, 0
  recetas, marcado "duplicado de IC3 - no usar"): **ELIMINADO** (componente +
  inventario + movimientos, con el trigger apagado, sin mover saldos). El corto
  quedó vivo en **IC3 con sus 480 kg**.
- `IF90B` (id 373) → repurposeado a **`IC3V`** (largo, `kg_x_uni` 0,0134 — antes
  0,01162).

**Rutas Fleje 90 (5, todas "Filtros de café", corregidas 2026-09-04 contra receta):**
cada ruta es `ingreso fleje → Charcas (prov serv, corta) → IJUPA (arma) → Virgilio (entrega Art)`.
La **receta** (`articulo_componente`) manda qué fleje usa cada art — la ruta es
sospechosa hasta cruzarla contra la receta, gana la receta:
- CORTO (IC3): 031 (ruta 206), 120 (205), 836 (207).
- LARGO (IC3V): 034 (209), 867 (208).
Las 206/208/209 estaban mal cargadas (206 apuntaba al dup IF90; 208 cargada como
corto siendo largo; 209 ingresaba con corto) → repuntadas a IC3/IC3V para
coincidir con la receta. Charcas queda como **prov_servicio** en las 5.

**Pantallas / flujos:**
El Fleje 90 va en **2 pasos** `[usuario 2026-09-04]`:
- **1) Recepción de Altrak** — en **Recepción Insumos → Flejes → Altrak** `[usuario
  "altrak tiene que estar en prov insumo flejes", opción B 2026-09-04]`. Altrak es
  proveedor de insumo (fleje); aparece en el rubro Flejes con un flujo propio (`irAltrak`)
  que pide **kg + % corto/largo** y llama `cargar_compra_mp('Altrak', p_kg, p_remito, p_fecha,
  p_pct_corto)`. Suma `FLEJE90_BRUTO` al stock de Charcas (ubic 13). **Acá se decide el
  % corto/largo** (ej. 30/70, **varía por entrega** según stock/pedido); ese % fija **lo
  que Charcas tiene que entregar de cada medida** (se guarda como objetivo en
  `recepcion_insumo.rollos_json`). Se **jubiló** la pantalla `Compra Altrak → Charcas`
  (`AltrakCharcas_GP2.html`, sin link en el menú).
- **2) Recepción de Charcas** — RPC `cargar_recepcion_charcas`: cuando Charcas
  corta y entrega, registra el corte (corto IC3 → Cervantes / largo IC3V → Virgilio),
  suma kg en el destino y descuenta del bruto en Charcas. **Acá se genera el stock
  real** de IC3/IC3V. Pantalla: `Prov Serv/CharcasEclipse/CharcasEclipse_GP2.html`.

**Charcas y Eclipse NO reciben Envío** `[usuario 2026-09-04: "charcas no puede aparecer
en envío prov serv porque no le enviamos; ahí le entra directo cuando cargamos la recepción
insumo de Altrak"]`. Son prov_servicio **híbridos**: la MP les llega directo del proveedor
externo (Altrak/Aperam), no por Envío desde Cervantes. Se marcan con
`proveedor_servicio.hibrido = true` (Charcas id 1, Eclipse id 13) y `envios_ps_bundle` los
**excluye** de Prov Serv → Envíos. Su entrega se registra en CharcasEclipse, no en Entregas PS normal.

**cod_prov Charcas = 3605** `[usuario 2026-09-02]`. **cod_prov Altrak = 3711** `[usuario 2026-09-03]`.

**OC — DECIDIDO 2026-09-04, pendiente de implementar en `OC_GP2.html`** `[usuario]`:
la OC del Fleje 90 va **SOLO a Altrak** (kg de `FLEJE90_BRUTO`). **NO hay OC gemela
a Charcas** — el corte se registra por la recepción, no por OC. (Reemplaza el
modelo anterior "OC a Charcas dispara gemela a Altrak".) Merma del corte de
Charcas: **sin dato, asumir 0** hasta que el usuario lo aporte (el 28% era de
Aperam/Eclipse, NO de Altrak).

### Aperam → Eclipse → Cervantes (misma lógica Altrak/Charcas) `[usuario 2026-09-01, calibrado con remito real 2026-09-02]`
Aperam entrega la **chapa 430** (1250×2500×0,8 mm) directo en **Eclipse**
(proveedor de servicio: corte chapa). Eclipse corta y entrega el insumo
**1686** (descorazonador) en Cervantes (remito en unidades, en cajas que
se pesan para confirmar).

**Números calibrados con remito real `[usuario + factura Aperam 2026-09-02]`:**
- Aperam: **4 chapas = 74,92 kg** de balanza → **18,73 kg/chapa real**
  (el teórico por densidad×volumen daría 19,25 kg → la laminación viene
  ~2,7% por debajo del nominal, dentro de la tolerancia normal del 430).
- Eclipse: **3940 uni = 55 kg netos** de pieza → **985 uni/chapa real**
  (el "760 uni/chapa" que yo tenía asentado antes era estimación
  incorrecta; el número que manda es el del remito).
- `kg_x_uni(1686) = 0,01376` (queda como está) `[usuario, "el que estaba
  en la tabla"]`. El empírico crudo daría 0,01396 (55/3940); GP2 subestima
  el peso de pieza en ~1,4% y ese punto se compensa vía el desperdicio.
- **Desperdicio Eclipse: 40,28 % de la chapa** `[act. 2026-09-08]` — `proveedor_servicio.desperdicio_pct`
  del PS Eclipse. Recalibrado con la compra real: Aperam 59,28 kg de chapa → Eclipse entregó 35,4 kg
  de producto → recorte 23,88 kg = 23,88/59,28 = **40,28 %**. (Antes figuraba 28 %, y en una tanda
  intermedia 67,46 % "sobre el producto"; se unificó a **% de la chapa** porque se razona en KG.)

**Cómo lo usa `crear_oc`:** OC gemela (regla única) — kg de chapa 430 en la OC gemela a Aperam =
`Σ (kg de producto pedido) / (1 − desperdicio_pct/100)` (DIVISIÓN, porque el % es de la chapa).
Con 40,28: producto / 0,5972 = producto × 1,6746. Aperam vende chapas enteras (redondeo hacia arriba).

**Provisorio, revisar con próximos 2–3 remitos**: la tolerancia de laminación del 430 varía chapa
por chapa; el 40,28 % puede moverse. Ajustar `proveedor_servicio.desperdicio_pct` de Eclipse cuando
haya más muestras (siempre como % de la chapa).

### Convención código de flejes: prefijo `I` (Insumo) `[usuario 2026-09-02]`
Todos los flejes en `GP2.componente` llevan **prefijo `I`** antepuesto — `I` =
Insumo. **Aplica a los 88 flejes de la base**, distribuidos en 2 sectores:

- **Sector 5 "Sector Fleje" (55)** — migración `flejes_prefijo_i_insumo`:
  `A1 → IA1, A10 → IA10, B3 → IB3, F90 → IF90, F90B → IF90B`, etc.
- **Sector 3 "Sector Transito" (33)** — migración `flejes_transito_prefijo_i`:
  variantes del mismo fleje después de pasar por una matriz.
  `A10-M365 → IA10-M365, B3-M32 → IB3-M32, F3-M37 → IF3-M37`, etc. Se filtró
  por `descripcion ILIKE '%fleje%'` para no tocar los 10 no-flejes del sector 3
  (Rompenuez, Cuchilla, Varilla, Destapa) que comparten el patrón `código-Mn`.

La regla **aplica solo a flejes por ahora** (otros insumos —cartones, cajas,
plásticos, remaches, bombillas— mantienen su convención sin prefijo). Motivo:
distinguir a simple vista los códigos de flejes en cualquier contexto.

**Renombre seguro** — verificado antes de aplicar: todas las tablas relacionadas
usan `componente_id` (FK bigint), no `codigo` como string; `fleje_detalle.n_fleje`
es dato descriptivo (número del vecino, no FK); cero hardcodes de códigos de fleje
en RPCs, vistas, triggers o frontend GP2; ningún esquema fuera de GP2 referencia
`GP2.componente` (ni vía función, ni vía FK). Verificación final: cero componentes
en toda la base con `descripcion ILIKE '%fleje%'` cuyo código no empiece con `I`.

### Prov Servicios "híbridos" (Charcas / Eclipse) `[usuario 2026-09-02]`
Charcas y Eclipse son prov_servicio pero **no siguen el flujo PS normal**
(Envío desde Cervantes → Entrega desde el PS). La MP les llega **directo
del proveedor externo** (alambre Altrak → Charcas, chapa Aperam → Eclipse)
y por eso **no hay Envío**: la carga se hace en las pantallas Pagos
(`Compra Altrak → Charcas`, `Compra Aperam → Eclipse`), y el stock queda
depositado en la ubicación del PS.

- **Pantalla dedicada**: `Prov Serv/CharcasEclipse/CharcasEclipse_GP2.html`
  (grupo PS del menú, "Charcas y Eclipse"). Muestra stock MP del PS
  seleccionado + registra Entrega + historial últimas 20. Fase A del rework
  aplicado el 2026-09-02 (versión menú v1.17.0).
- **OC** (⚠️ divergen desde 2026-09-04): **Eclipse** sí lleva OC gemela a Aperam
  (`crear_oc` rama Eclipse). **Charcas NO**: la OC va SOLO a Altrak, sin gemela
  (ver bloque "OC — DECIDIDO 2026-09-04" arriba). Pendiente implementar en `OC_GP2.html`.
- **Stock online** visible en la pantalla nueva: kg de `FLEJE90_BRUTO` en
  Charcas (ubic 13) y kg de CHAPA430 en Eclipse (ubic 48).
- **Fase B aplicada 2026-09-02**: se sacaron los rubros Filtros/Cortados de
  `RecepcionInsumos_GP2.html` (v3.36.0). Ya no hay entrada duplicada — la
  carga de F90/F90B/1686 vive únicamente en la pantalla dedicada. Los
  helpers `esFiltroCharcas()`/`esCortadoEclipse()` quedaron como stubs
  (return false) para no romper llamadas remanentes. Las RPCs
  `cargar_recepcion_charcas`/`cargar_recepcion_eclipse` siguen desplegadas
  en Supabase — solo cambia quién las llama (ahora la pantalla nueva).

**Paridad Altrak/Charcas ↔ Aperam/Eclipse `[dato 2026-09-02, act. 2026-09-04]`:** los dos
modelos son gemelos estructurales. Igual: ubicación tipo `proveedor_servicio`
(Charcas 13 / Eclipse 48), MP en kg (`FLEJE90_BRUTO` Altrak sector 13 Alambre /
`CHAPA430` Aperam sector 5 Fleje desde 2026-09-04), RPC de compra (`cargar_compra_mp('Altrak'|'Aperam', ...)`, una sola desde el
2026-09-05: el PS que recibe sale de `proveedor_servicio.mp_componente_id`), RPC de recepción (`cargar_recepcion_charcas`
/ `cargar_recepcion_eclipse`), parámetro de desperdicio.
**Ambos entran igual (desde 2026-09-04, "misma forma"):** la MP se recibe por
Recepción Insumos → Flejes (Altrak = provderor propio con panel; chapa Aperam =
ruteo por ítem `CHAPA430` → panel `stepChapa`), la ENTREGA del corte va por Entrega PS
(faseCharcas IC3/IC3V, faseEclipse 1686), y en Control PS el `consumo` de la MP bruta
NO cuenta como "entregado" (se corta, no se entrega) — el "entregado" es la `compra`
del producto cortado atribuida al PS. Los módulos "Pagos" (AltrakCharcas / AperamEclipse)
quedaron JUBILADOS (legacy sin link).
**Desperdicio del corte de chapa (Eclipse) `[dato/usuario 2026-09-04]`:** medido con
la última compra real — Aperam entregó 3 chapas = 59,28 kg (39,52 LK + 19,76 CH),
Eclipse devolvió 2.440 uni de 1686 que pesan 35,4 kg (11,8 kg/813 u LK + 23,6 kg/1627 u CH),
se corta TODO → recorte 23,88 kg. Peso real del 1686 = 35,4/2.440 = **0,014508 kg/u**
(los dos lotes coincidían; el `kg_x_uni` viejo 0,01376 estaba 5% bajo, se corrigió).
Desperdicio = recorte/chapa = 23,88/59,28 = **40,28 % de la chapa** `[usuario 2026-09-08: "usar
el 40 porque lo que usamos son los KG"]`. Se guarda ese 40,28 en `GP2.proveedor_servicio.desperdicio_pct`
del PS Eclipse (una sesión lo movió de `parametro.eclipse_desperdicio_pct`, vestigial — NO usar ese).
**Convención (OBLIGATORIA, las DOS funciones que lo usan):** `desperdicio_pct` es % **de la chapa**,
así que la chapa sale con **DIVISIÓN**: `chapa = producto / (1 − desperdicio_pct/100)` (NO `× (1+…)`).
Lo usan `cargar_recepcion_eclipse` (chapa consumida) y `crear_oc` (OC gemela de chapa) — las dos con ÷.
Con 40,28: 35,4 / (1−0,4028) = 59,28 = mismo resultado que el viejo × 1,6746, pero el número que se
razona/guarda es el 40 en KG. Regla de rinde:
**1 kg de chapa 430 ≈ 41,2 uni de 1686** (50 kg → ~2.058 uni). El 1686 no está en
recetas/BOM/rutas, así que cambiar su peso no arrastra costeo.
**⚠️ La entrega de Eclipse se carga en KG DE ENTREGA `[usuario 2026-09-08]`:** los prov serv
se cargan en KG (peso de lo que entregan). La entrega de Eclipse (Entrega PS → faseEclipse,
v1.6.1) toma las **unidades como referencia** (lo que dice el remito, suman el 1686 al stock)
y un campo **`Kg de entrega` manual** = **peso total de las unidades entregadas** (el 1686). La
**chapa consumida se DERIVA** = `kg_entrega / (1 − desperdicio/100)` (desperdicio % de la chapa).
`cargar_recepcion_eclipse(…, p_kg_entrega)` usa ese peso como producto (si no viene, cae al teórico
`uni × kg_x_uni`) y saca la chapa con `proveedor_servicio.desperdicio_pct` (40,28). Validado con la compra real: entrega
11,8 kg → 19,76 kg chapa (1 chapa Aperam) y 23,6 → 39,52 (2 chapas) — calzan justo. El panel
muestra en vivo la chapa a descontar. (Ojo: NO es "kg de chapa consumida"; es el peso del producto.)
**El 1686 se GUARDA EN KG `[usuario 2026-09-08: "no estamos guardando en unidades... son los KG
los que cargamos"]`:** los prov serv que procesan **metal por peso** trabajan/cobran en KG (se pesa
lo enviado/recibido; tarifa $/kg): Guazzaroni niquelado, Jade pintado, FAAT templado, Pedernera
cromado, Charcas (fleje) y Eclipse (chapa). **NO todos: los de cartón** (AJ Adhesivos, adhesivado)
van en **unidades** — se cuentan cartones, no se pesan `[usuario 2026-09-08: "los de cartones como
aj no son en KG"]`. Para Eclipse, las unidades del remito son solo referencia (lo que declara el proveedor).
Por eso `cargar_recepcion_eclipse` inserta el movimiento del 1686 en **kg** (`v_kg_producto`, no
`p_unidades`), `componente."1686".unidad_medida='kg'`, y las uni van a `rollos_json.uni_referencia`.
Igual que Charcas guarda el corte en kg de balanza. Así Control PS de Eclipse queda TODO en kg
(chapa enviada vs producto entregado, comparable). El 1686 es huérfano (0 recetas/OC) → sin ripple.
**⚠️ Ya NO son gemelos en la OC** (desde 2026-09-04): Eclipse mantiene OC gemela
a Aperam; Charcas va SOLO a Altrak, sin gemela. `proveedor_insumo.modo_control` = `peso_total`
en ambos `[usuario 2026-09-02: "los paquetes se pesan"]` — semántico, el
HTML detecta por rubro (Filtros/Cortados) no por modo_control. **Ojo**:
hoy ninguno de los dos popups pide un peso separado; asumen `paq × 10` y
`uni × kg_x_uni`. Distinto por diseño: sector del producto final (031/034
en 12 Filtros; 1686 en 2 Procesado); Aperam sigue en Recepción de Flejes
(entrega dual chapa+flejes), Altrak no (100% va a Charcas). **Pendiente
menor**: `Charcas.rubro='Bombillas'` (debería ser 'Filtros' o 'Sector
Procesado'); `Aperam.rubro=NULL` (Altrak tiene 'Sector Alambre'). Ambos
cosméticos, no afectan lógica.

**Cruce con la casa del vecino (para no volver a discutirlo)
`[dato 2026-09-02, SQL sobre public]`:** el descorazonador vive en
`public."SP Kg"` como **`Z32 "Descarozador de Manzana"`** (no como "1686",
código nuevo de GP2) con `Kg X Uni = 0,0144` y `KG x Cajon = 10` (prov
"PENDIENTE (nacional)"); y en `public."Despiece x Articulo"` con el mismo
0,0144 (usado en el costeo de los artículos 395 y 709 del vecino). GP2
usa 0,01376 por indicación del usuario — el 0,0144 del vecino queda como
valor histórico desactualizado; **no se toca `public`** (regla "casa del
vecino"). El `KG x Cajon = 10` del vecino no es un cajón estándar de 30
kg, es exactamente **la caja que arma Eclipse** `[usuario 2026-09-02]`.

- **Componentes:** `CHAPA430` (kg, prov Aperam, **sector 5 Fleje desde el 2026-09-04** —
  antes decía sector 13 Alambre; corregido `[dato 2026-09-05]` —, vive en
  ubic 48 Eclipse) + `1686` **descorazonador** (uni, prov Eclipse, **sector 2
  Procesado = SP**, vive en ubic 2). `[usuario 2026-09-01: "el insumo
  entregado es descorazonador, tiene sector es SP"]`.
- **Pantalla Pagos:** `Compras/AperamEclipse_GP2.html` carga kg de chapa
  cuando llega la factura de Aperam → suma stock en Eclipse.
- **Recepción operario:** rubro nuevo "**Cortados**" → 1686 con proveedor
  Eclipse → RPC `cargar_recepcion_eclipse` suma uni en Cortados + descuenta
  chapa en Eclipse.
- **OC gemela:** OC a Eclipse dispara OC gemela a Aperam por
  `Σ (uni × kg_x_uni) / (1 − desperdicio/100)` kg de chapa (÷, el % es de la chapa).
- **Aperam sigue apareciendo como proveedor de flejes en Recepción Insumos**
  (a diferencia de Altrak que salió del listado): la chapa 430 es un flujo
  nuevo, los flejes que ya entregaba siguen igual.

**Revisión final `[usuario 2026-09-01]`:** TODOS los proveedores de fleje piden
**solo `Kg total`**, con dos excepciones:
- **Hermac** → `Kg total` + **`Paquetes`** (entero, se guarda en `p_pallets`).
- **Importado** → sin cambios (nunca tuvo campo extra; queda como los demás).

Los demás (Basconia, Aperam, Brawin, Szapiro, JL Metales, Altrak, EstaMetal
—que ya está oculto—) solo Kg total. Basconia y Altrak fuerzan `kg` en
`abrirPopup` aunque el fleje tenga UM `unidad` en el componente; el resto
respeta la UM canónica.

El campo Pallets del remito se sacó: el paso 2 arma 1 pallet por default y el
operario suma con "+ pallet" si el remito trajo más. Ver `fieldsFleje(prov)` en
`StockFlejes/RecepcionInsumos_GP2.html`.
- **Importado** (marcador, no es una empresa): la **Cremallera (E13)** y los insumos del
  **corta queso PB1 cilindro y V20 tornillo** **ya no se fabrican, se importan**.
  `[usuario 2026-08-29]`. **Z19A (alambre corta queso) NO va en Importados**
  `[usuario 2026-09-01, corrección al anterior]` — está `estado_compra=discontinuo`
  con `proveedor=null`, no aparece en OC ni en Recepción Insumos.
  El tornillo se importa **ya niquelado**: el código **CV20** ("p/Niquelar") **no se compra
  más** y el paso de niquelado en Guazzaroni se sacó de las rutas 382/577/589, que ahora
  entran el V20 comprado y van derecho al tallerista. `[usuario 2026-08-29]`
- **Garage (GRJ*)**: no llevan proveedor, los arman los talleristas. Además el sector se
  está vaciando: hoy quedan 3 códigos (`[usuario + dato]`). **Un GRJ se jubila cuando el
  tallerista arma las partes sueltas en vez de un sub-armado previo** `[usuario 2026-09-08]`:
  se aplana la receta del terminado (las partes del BOM del GRJ pasan a la receta) y el GRJ
  se borra. Ejemplo: **GRJ1 (Abrelata Uña Pie 500)** se retiró el 2026-09-08 — el 500 quedó
  como el 510 (receta plana: C1 + C10 + V9 + A11 + Pliego Ad 500, sin intermedio). Las rutas
  ya mandaban las partes por separado a Alex Escalante y Martin Cornejo, así que no cambiaron;
  el costo del 500 tampoco ($1.525,12, sale de la ruta, no de la receta).
- **Una parte de la receta sin ruta que la produzca = artículo subcosteado** `[dato 2026-09-08,
  pregunta 8.6]`. El **863** tenía `PEP8` (Mango Madera Pizza Ø9) en la receta pero ninguna de sus
  rutas lo construía → su costo no incluía el mango. Se replicó la ruta del **564** (que sí lo
  arma: Fleje 27 `ID8` → matriz 85 → Guazzaroni → **Maspoli** → PEP8 → Martin Cornejo → art).
  Costo del 863 corregido $909,73 → $1.620,57. Regla: el costo del terminado sale de las **rutas**,
  no de la receta; una parte de la receta sin ruta productora no suma su costo (a diferencia de
  GRJ1, que costaba $0 y no cambió nada al sacarlo). `db/verificar.sql` no lo detecta hoy — vale
  revisar recetas cuyos componentes no aparecen como `comp_salida` de ninguna ruta del artículo.
- **Clonar un artículo NO es solo copiar receta y rutas: hay que copiar la tarifa de armado**
  `[dato 2026-09-08]`. Al dar de alta el **760** como clon del **550** (el gemelo 7xx que faltaba,
  "igual al 550"), el 760 daba $600,84 vs $651,84 del 550 — $51 menos. La diferencia era la
  **tarifa del tallerista por armar el terminado** (`precio_tallerista` de Danica García para el
  550 = $51 ARS), que va por `componente_id` del terminado: el clon no la tenía. Copiándola, el
  760 quedó en $651,84 = 550. Lección para toda alta que clona un terminado: componente + articulo
  + receta + rutas + inventario **+ precio_tallerista/precio_servicio_pieza del armado**.
- **Bombillas — la bolsa** `[usuario 2026-09-08]`: el 550 y el 760 llevan una **bolsa** que se
  compra a **Papelera Nueve de Julio** (nuevo proveedor de insumo, rubro Sector Cartón); componente
  `BOLSA550`, descripción **"Bolsa 550/760"**, sector Cartón, sin precio por ahora. Va sólo en el
  550 y el 760 (no en las otras bombillas). El 550/760 se arman con filtro (BOM13) + precinto
  (BOM14) + cartón 550 (CCG6B) + caja + bolsa, por **Danica García**, y entregan en Virgilio.
  **Se trata "como las de Vihal"** `[usuario 2026-09-08, elección]`: `carton_formato = 'Bolsa'`
  (el formato 'Bolsa' *significa* "es bolsa, no cartón" → múltiplo 1, sin redondeo que sume de
  más, piso 20.000 de la familia). **`marca` queda NULL a propósito**: la comparten el 550 (LOEKE)
  y el 760 (CHEF), no lleva una sola marca — con marca vacía `famLabel` muestra "Formato Bolsa"
  limpio (sin "(sin marca)"). Carga **manual** en la OC: sin `maximo` no hay sugerido automático, y
  el piso 20.000 sólo **avisa**, no fuerza. Suma una **3ª familia Bolsa** (`Bolsa|(sin marca)`),
  aparte de las dos de Vihal (LOEKE/CHEF); es de otro proveedor, no se mezclan.
- **Una ruta "GRJ como insumo" es falsa cuando el GRJ lo arma un tallerista** `[dato 2026-09-08]`:
  557/762/558/763 tenían una ruta "Insumo GRJ6/GRJ5 → art (Gentile)" **además** de las rutas del
  caño (BOM12) y el resorte (BOM8) que van a **Martín Cornejo**. El GRJ NO se compra: Martín lo arma
  de caño+resorte, y las rutas de las partes ya trazan todo el camino
  (caño/resorte → Martín → GRJ → Gentile → art). La ruta "GRJ insumo" era un duplicado que ensuciaba
  el trazado; **borrarla no cambia el costo** (test de reversa: 1.795,56 → 1.795,56). Regla: si un
  intermedio (GRJ) lo fabrica un tallerista de sus partes, NO va también como ruta de insumo — se
  costea/traza por las rutas de las partes.

### El proveedor vive en UN solo lugar
`[dato 2026-08-30]` `componente.proveedor` es la **única fuente**. Antes el proveedor del
fleje estaba **duplicado** en `fleje_detalle.proveedor` y las lecturas hacían
`coalesce(fd, c)` — o sea que ganaba `fleje_detalle`. Como la pantalla escribe en
`componente.proveedor`, **cambiar el proveedor de un fleje no tenía efecto en la OC**: la
pantalla mostraba el nuevo y la orden seguía saliendo al viejo, en silencio, en los 50
flejes. Reproducido y arreglado.

Además `componente.proveedor` ahora tiene **FK a `proveedor_insumo`** (`ON UPDATE
CASCADE`): antes era texto libre, así que un tipeo creaba un proveedor fantasma sin que
nada avisara. Renombrar un proveedor ahora propaga solo.

`fleje_detalle.proveedor` **se borró** (2026-08-30, autorizado): guardaba el mismo dato.
Antes se migraron sus tres puntas: `flejes_bundle` lee el del componente,
`fleje_detalle_upsert` (la pantalla de Flejes) escribe en `componente.proveedor` y avisa
con un mensaje claro si el proveedor no existe, y la huérfana `recepcion_insumos_bundle`
se eliminó. Un proveedor nuevo se da de alta desde Inyectores → "+ Proveedor".

### Cómo se administra (no se toca la base a mano)
`[usuario 2026-08-29]` Quién hace cada parte se cambia desde la pantalla
**`Compras/Inyectores_GP2.html`** y eso **escribe en Supabase** (`componente.proveedor`,
vía RPC `asignar_proveedor_parte`). Los inyectores cambian seguido, así que el dato tiene
que ser editable desde el programa, no por migración. Esa asignación es **lo que separa la
OC**: cada proveedor recibe una orden sólo con sus partes.

---

## 1-ter. Las cajas: son 13, no 9 (2026-09-04)

`[dato: planilla del usuario "Conteo Cajas VACIO", hoja "Relevamiento VACIO" A1:H18]` El
relevamiento vacío de cajas —el papel que se imprime para contar— tiene **13 cajas**, todas
de **Corrugadora del Plata** (único proveedor vigente; Recicor está sólo como precio de
referencia sin vincular). **GP2 tenía 9**: faltaban las cajas **N°8 (`A7`), N°15 (`A9B`),
N°16 (`A7B`) y N°27 (`Z9`)** — no existían ni como componente, ni en inventario, ni con
precio, así que **no aparecían en Recepción de Insumos**: si llegaban en un remito, no había
dónde cargarlas.

**Cargadas 3 el 2026-09-04** en Sector Caja (11) con su fila de inventario en 0 y el precio
de la lista jul-26 que trae la propia planilla (344,26 / 289,62 / 481,66 ARS por unidad —
los mismos valores que ya tenían cargadas las otras 9, o sea es la misma lista). Ids nuevos:
604 (N°15), 605 (N°16), 606 (N°27). **En Recepción de Insumos hay 12 cajas.** También se
completó `proveedor_insumo.cod_prov = '69587'` de Corrugadora (estaba en null; el cód. ISIS
del proveedor sólo vivía en `precio_proveedor`, y la pantalla de Recepciones lo mostraba
vacío).

**La caja N°8 (`A7`) NO va: es discontinua** `[usuario 2026-09-04]`. Sigue en el papel del
relevamiento, pero no entra más. **No existe en GP2 y no hay que cargarla**: se creó por
error en esta misma sesión y se borró entera (componente, inventario y precio). Se marcó
`estado_compra='discontinuo'` primero, pero **eso no alcanzaba**: `relevamiento_abrir` toma
TODOS los componentes del sector sin mirar `estado_compra`, así que igual iba a aparecer para
contar. Queda anotado acá para que la próxima auditoría del relevamiento no la vuelva a
cargar como "faltante".

**⚠ Hoy el relevamiento cuenta lo discontinuo** `[dato 2026-09-04, sin decidir]`. Hay **14
componentes con `estado_compra='discontinuo'`** en sectores que se relevan (`C12`, `BOM10`,
`IF12`, `IZ19A`, `GRJ13`, `V20`, `V18C`, `I3B`, `CV16`, `CV17`, `ID7`, `A1C1`, `L4B1` y el
`A9` del Sector Procesado) y `relevamiento_abrir` los mete igual en la hoja de conteo. Puede
estar bien (queda stock viejo que hay que vaciar) o ser ruido para el operario — **lo decide
el usuario**; no se tocó la RPC.

**Para qué son las que faltaban** `[usuario 2026-09-04]`:
- **Caja N°27 (`Z9`)** → envasa las **cucharas de madera**.
- **Caja N°15 (`A9B`)** → envasa los **palos de amasar**.
- N°16 (`A7B`): uso todavía **sin declarar** — preguntar, no deducir.

**Ni las cucharas de madera ni los palos de amasar existen como artículo en GP2**
`[dato: los 84 artículos, ninguna familia se les parece]`. Por eso las 3 cajas quedan
**huérfanas**: ningún `articulo.componente_caja_id` las apunta, así que no tienen consumo y
la OC no las va a pedir sola hasta que se carguen esos artículos con sus rutas. Pendiente
acordado con el usuario ("después agregamos a las rutas").

**El código `A7` no llegó a quedar repetido** porque la N°8 se borró, pero el choque estaba:
`A7` es también el "Mgo Plano 701 Crom." del Sector Procesado (id 82). Es el mismo patrón de
los cuatro choques ya conocidos (`A1`, `A4`, `A8`, `A9` — ver la trampa de 2026-09-03): la
numeración de cajas y la de piezas procesadas se pisan. Si alguna vez entra una caja con
código ya usado, se carga igual con el código real del relevamiento (no se inventa uno) y
vale la regla de siempre: unir por `componente.id`, nunca por `codigo`.

**Falta un dato del usuario**: los **cód. ISIS LK/CH por caja** (0027/0047 para la N°1,
etc.) que trae el relevamiento no se guardan en ningún campo de GP2, y las **medidas** de
las 3 cajas nuevas tampoco (las otras 9 las tienen en `precio_proveedor.producto`, tipo
"Caja Nº 1 (240*167*113)"; las nuevas dicen "medidas pendientes").

---

## 1-quater. Flejes: la planilla vigente tiene 54 y GP2 recibía 48 (2026-09-04)

`[dato: planilla del usuario "Conteo Gral FLEJES y Alambre VACIO", hoja "Pedido Flejes"
A1:AP69 — de la 70 para abajo es discontinuo]` Los **7 proveedores están todos y activos**
(Basconia 24 flejes, Aperam 13, Brawin 7, Hermac 6, Szapiro 2, Altrak 1, JL Metales 1).
Alami aparece con hoja de OC vieja pero **no tiene flejes vigentes**.

**Lo grave no era lo que faltaba, sino lo que ya está mal enrutado.** Cruzando cada
descripción de fleje contra las rutas cargadas:

- **El fleje 28 estaba escondido y se consume todos los días** `[hallazgo, ARREGLADO
  2026-09-04 por orden del usuario: "destraba el fleje n°28"]`. `ID1` (Hermac, 10 x 2 m)
  alimenta rutas **activas**: `ID1` → `LL7A` Vástago Pelapapa (art 587) y `ID1-M375` → `L8`
  Vástagos Cortos → `F2` Vástago Canelón (arts 570 y 858). Estaba marcado
  `estado_compra='importado'`, y como `recepcion_bundle` sólo muestra los de
  `estado_compra is null`, **no había dónde recepcionarlo**: entraba el remito de Hermac y no
  se podía cargar. Se le puso `estado_compra=null`; ya aparece en Recepción y la OC lo pide
  (máximo 292 kg). **Lección general: `estado_compra` esconde el insumo de la pantalla, así
  que un fleje que alguna ruta consume NUNCA puede tener estado.**
- **La arandela chica sale del fleje de la grande** `[hallazgo 2026-09-04, SIN RESOLVER]`.
  `K9` "Arandela Chica Afila **Inox**" se produce en 3 rutas (afiladores 97, 114, 504) desde
  el **fleje 10** (`IF2`, Basconia laminado, 77 x 1,25), que es el de la arandela **grande**
  (`K11` → zincado → `F7`; cada afilador tiene las dos rutas en paralelo). La planilla tiene
  un **fleje 12** con la misma medida 77 x 1,25 pero **Aperam inox 430**, sector F2B, llamado
  exactamente "Arandela Chica Afila" — y **no existe en GP2**. Si la chica inox sale del 12,
  hoy se está costeando inox a precio de laminado en tres artículos. Falta que el usuario lo
  confirme.
- **Fleje 59 vs 95: son el MISMO fleje, el 95 se descarta** `[usuario 2026-09-04: "SÍ, N°59
  hace Vast. C Pizza / Flech. Ahueca" + 2026-09-09: "el 95 sacalo"]`. Las dos piezas salen del
  **fleje 59** (`IB7`, **Aperam**, 60 x 2): `L15` Vástago Corta Pizza Chico (arts 116, 559,
  562, 859, 862) y `N3` Flechita Ahueca vía matriz M361 (arts 542, 543, 720, 722). El **fleje
  95** de la planilla (Aperam, mismo sector B7, misma medida y misma descripción) es el mismo
  fleje con otro número: **no se compra por separado y no se carga**.
- **El corta queso tiene dos entradas y una es huérfana** `[hallazgo, SIN RESOLVER]`. Los
  arts 119, 574 y 809 tienen ruta desde el **fleje 80** (`IE3`, Brawin Ø4 x 380 → `A9`
  cromado, hoy discontinuo) y otra desde `IZ19A` "Alambre Corta Queso", que está **sin n° de
  fleje, sin proveedor y marcado discontinuo**. La planilla vigente tiene un **fleje 78**
  (Brawin, sector E7, Ø4 x 118) que no existe en GP2. **[Probable] `IZ19A` es el 78** y quedó
  huérfano en la migración: conviene unificarlo, no crear otro.
- **Fleje 47 (Espiral Doble Aleta, Szapiro): la planilla y la ruta se contradicen**
  `[SIN RESOLVER]`. La pieza es `D1` Espiral Sacacorcho, que entra como **insumo importado**
  en 7 rutas (104, 520, 521, 530, 531, 581, 730) por la decisión del 2026-09-02. Coherente
  con que `IF12` esté discontinuo — pero ojo, en GP2 `IF12` se llama **"Fleje N° 49"**,
  mientras la planilla lo numera **47** en el mismo sector F12. O la planilla quedó vieja, o
  se sigue comprando alambre a Szapiro y la ruta miente.
- **Fleje 91 (Estribo Bombilla, Basconia): NO va** `[usuario 2026-09-04: "estribo bombilla es
  discontinuo"]`. No se carga. Concuerda con lo que muestran las rutas: **ninguna bombilla
  usa fleje**, todas arrancan de piezas ya compradas (`BOM12` caño de Metalúrgica Giser,
  `BOM8` resorte de Grudzien, `BOM10` de Resortes Charcas, `BOM13`/`BOM14` de Cimarrón).
- **El fleje 90 partido en bruto/corto/largo está bien**: la planilla lo pone en Altrak y GP2
  lo tiene como `FLEJE90_BRUTO` (Altrak) + `IC3`/`IC3V` (Charcas corta). No es un faltante.

**Sobran respecto de la planilla, y está bien**: `ID7` (fleje 50, EstaMetal, discontinuo),
`IZ19A`, y los tres sin número que sí se reciben — `CHAPA430` (Aperam → Eclipse), `IC3V`
(fleje 90 largo) y `IE13` (Cremallera, importado).

---

## 1-quinquies. Plásticos: la planilla tiene 61 partes y GP2 recibía 23 (2026-09-04)

`[dato: planilla del usuario "Conteo y Pedido Sector Plastico VACIO", hoja "Pedido VACIO"
A1:AU105 — de la 106 para abajo es discontinuo]` Es **el sector más desfasado de los cuatro
auditados**. La planilla tiene 10 bloques de proveedor y 61 partes; en Recepción de Insumos
aparecían 23.

**Cargado el 2026-09-04 por orden del usuario** (`"agregame los proveedores… con las
respectivas partes. y agrega esas partes al sector plastico"`): 4 proveedores nuevos —
**JL Matriceria, Ing. Barbetta Alberto, Packaging y Servicios, CC Galvanoquimica** (todos
`rubro='Sector Plástico'`, activos) — y **8 partes** en Sector Plástico (6) con inventario en
0, ids 607-614:

| código | qué es | proveedor | uni x bolsa |
|---|---|---|---|
| `PC4` | Cierra Bolsas Blanc. | JL Matriceria | 1.400 |
| `PEP9` | Cuchillo de Untar Blanc | JL Matriceria | 1.250 |
| `PIEA` | Rueda Recta 50A36.20 945*48*70 | Ing. Barbetta Alberto | — |
| `PIEB` | Rueda Recta 710*48*50.8 | Ing. Barbetta Alberto | — |
| `PCP4A` | Cintas Adhesivas 48x100 | Packaging y Servicios | — |
| `PCP2` | Plancha de Niquel | CC Galvanoquimica | — |
| `PB2` | Cuchara Ny | Pettofrezza Rafael | 200 |
| `PEP2` | Mango Pelador 586 S/M | Pettofrezza Rafael | 350 |

**Telleria NO se dio de alta** `[usuario 2026-09-04: "con respecto a telleria, las partes que
están en el archivo agregaselas a pettofrezza, (excepto pep1 que ya está)"]`. Sus dos partes
nuevas (`PB2`, `PEP2`) quedaron a nombre de **Pettofrezza Rafael**, y `PEP1` no se tocó
(ya existía, también con Pettofrezza). O sea: **lo que la planilla llama Telleria, en GP2 es
Pettofrezza.**

**Ojo con dos de las altas**: las ruedas de Barbetta y la plancha de níquel **no son
plásticos** (son abrasivo y baño de galvánica), pero van al Sector Plástico porque es donde
el usuario los cuenta y los pide. `PCP2` quedó en `unidad`, aunque la planilla la maneja en
kg — **si se va a pesar, hay que corregir la unidad**. El `uni_x_cajon` de las cuatro sin
valor quedó vacío a propósito: en esos bloques la planilla corre las columnas y el número no
es confiable. Sin ese factor el relevamiento las marca en rojo.

**Lo que sigue faltando (26 partes)** — no se cargó nada de esto:
- **La familia entera de utensilios de nylon `PV*` (9)**: Pisa Papa, Cucharón, Espátula Lisa,
  Cuchara Fideos, Cuchara Calada, Espátula Calada, Corta Torta, Picos Reposteros, Pela
  Naranjas. Todos de Pat Bet Plast en NY reciclado. **GP2 no conoce esta familia**, igual que
  no conoce las cucharas de madera ni los palos de amasar.
- **8 altas más de Pat Bet Plast**: `PA3` Muñeco Antiderrame, `PA15` Capuchón ф10, `PA16`
  Mangos ф10 LK, `PA17` Mangos Cuch y P Torta, `PB1` Cilindro Corta Queso, `PC6` Ojales
  Neg/Blanco, `PEST1` Insertos Mgo Madera, `PEST2` Insertos Pisa Papas.
- **Desdobles pendientes**: `PC2A`/`PC2B` (mangos pelapapa **s/calar**; GP2 sólo tiene los
  calados `PC1A`/`PC1B`) y `PEP4A`/`PEP4B` (afila caladas azul y blanca; GP2 tiene un solo
  `PEP4` sin color).
- **Renombres, no faltantes** (confirmar y tachar): `PB8` = `PB8A`, `PB7` = `PB8B`, `PC15`
  está desdoblado en `PC15A`/`PC15B`. El `PA10` de la planilla existe pero en **Sector
  Procesado** (es el capuchón serigrafiado); el crudo del inyector es `PA10B`.

**Tres conflictos de proveedor sin resolver** `[SIN RESOLVER]`:
1. `PCP3` **Clavo 505**: la planilla lo pone en **Martin Facciolo**, GP2 en **Trefilados
   Industriales**.
2. `PA17` Mangos Cuch y P Torta es de **Pat Bet** en la planilla, pero GP2 tiene `PA4`/`PA5`
   (Mang Cuch Unt Rojo/Chef) a nombre de **Pettofrezza**. Si son la misma pieza, el costo
   sale del inyector equivocado.
3. El bloque de Pettofrezza se titula **"Rodar"** en la planilla. Nombre que GP2 no conoce.

**Máspoli está bien como está**: sus 3 mangos (`PC12`, `PEP7`, `PEP8`) figuran en
`fabricacion` y por eso no salen en Recepción — es fasonero (se le manda la virola `D13` y
devuelve el mango), entra por el circuito de tallerista, no por compra de insumo. La planilla
los pide como compra; son dos miradas del mismo hecho, no un error.

**Discrepancia de factor detectada de paso** `[dato]`: para `PEP1` la planilla dice **280 uni
por bolsa** y GP2 tiene `uni_x_cajon = 800`. Uno de los dos está mal y el relevamiento cuenta
por ese número.

## 1-sexies. Remaches: 15 de 22, y lo que falta son discontinuos vivos (2026-09-04)

`[dato: planilla "Conteo Remaches VACIO", hoja "Conteo VACIO" A7:AL49]` **El sector mejor
parado.** 5 proveedores, 22 partes; en Recepción aparecen 15 y **el mecanismo funciona como
debe**: se compra el crudo `CV*` y el `V*` niquelado queda en `fabricacion` sin precio propio
(su costo es crudo + baño). Que los `V*` no estén en Recepción **no es un faltante**.

- **Proveedores**: están Bella Vista, Tornillos Suipacha, Electrónica Mandelli e Imel (la
  planilla lo llama "Fijaciones Imel"). **`Dilmax` se dio de alta el 2026-09-04**
  (`rubro='Sector Remache'`) con sus dos fluidos, por orden del usuario.
- **`CV15` Rem Tapón Hierro (12 x 2,75) — CARGADO** `[usuario 2026-09-04: "rem tapon hierro
  agregalo v15c"]`. Era el único faltante real del sector. Componente **617** en Sector
  Remache, proveedor Bella Vista, `kg_x_uni = 0,0008`, inventario en 0. **Sin precio**: la
  planilla trae 0 en Prec x KG. Se cargó primero como `V15C` (el código del sector crudo de
  la planilla) y se **renombró a `CV15`** en el momento `[usuario: "si renombra para que
  quede parejo"]`: **todos los crudos de remache llevan prefijo `CV`**, y la parejidad del
  maestro pesa más que copiar el código del Excel.
  **⚠ Discrepancia de envase que quedó a la vista**: se cargó con `uni_x_cajon = 2500`, o sea
  la **bolsa de 2 kg que dice la planilla**, pero **los 12 crudos `CV*` de GP2 tienen todos
  bolsa de 20 kg** (`kg_x_uni × uni_x_cajon = 20` en los doce), mientras la misma planilla les
  pone 2 o 10 kg. Uno de los dos números está mal y el relevamiento cuenta por ése.
- **Existen pero marcados discontinuos, y la planilla vigente los pide**: `CV16` Vástago
  Sacafuente 5,2 x 100, `CV17` Cremallera Doble Aleta, `V18C` (que además **se llama "Vastago
  Alu"** cuando la planilla dice Vástago Pisapapas 8 x 97) y `V20` Tornillo Corta Queso —
  este último con proveedor **"Importado"** mientras la planilla lo pide a **Tornillos
  Suipacha**.
- **Los 2 de Dilmax no son remaches, pero viven en Sector Remache** `[usuario 2026-09-04:
  "agrega a dilmax y sus correspondientes partes"]`. `EST1` Aceite de Corte D-91 (id 615) y
  `EST2` Soluble SOL-MEC ST20 (id 616), con inventario en 0 y el precio por litro de la
  planilla ($ 5.815,105 y $ 6.092,455). Van al sector 8 por el mismo criterio que las ruedas
  de Barbetta en plásticos: **el insumo vive donde el usuario lo cuenta y lo pide**, no donde
  dice la química.
  **⚠ Truco de unidad que hay que respetar**: son litros, pero se cargaron como
  `unidad_medida='unidad'` con `uni_x_cajon=20`, o sea **1 "unidad" = 1 litro y 1 envase = 20
  litros**. No se puso `'litro'` porque la pantalla de Recepción sólo entiende `kg` y
  `unidad`: cualquier otro valor cae al default del rubro, que en Remaches es **kg** — y el
  operario habría cargado litros creyendo que pesa. Si algún día se agrega `litro` de verdad,
  hay que tocar `RUBRO_UM`/`UMBY` en `StockFlejes/RecepcionInsumos_GP2.html`.
- **La planilla se contradice sola en el Tornillo Sacafuente**: está bajo el bloque
  "Fijaciones Imel" pero su columna Proveedor dice "Bella Vista"; GP2 lo tiene como `CV18D`
  a nombre de **Tornillos Suipacha**. Tres respuestas para una pieza.
- **⚠ Códigos de sector pisados entre planillas**: `EST1`/`EST2` son el aceite y el soluble en
  la planilla de remaches, y los Insertos Mgo Madera / Pisa Papas en la de plásticos. Si
  algún día se cargan los dos, no se distinguen por sector.

## 1-septies. Bombillas: 5 de 17, y dos códigos pisados (2026-09-04)

`[dato: planilla "Conteo Bombilla VACIO", hoja "Conteo VACIO" A1:AO65 — el resto es
discontinuo]` 10 bloques de proveedor y 17 partes. En Recepción aparecían 5: `BOM12` Caño
Inox 140 (Giser), `BOM8` Resorte p/Bombilla Niq (Grudzien), `EP10` Resorte Mini Batidor y
`LLF8` Resorte Batidor Pera (Charcas), y el `Z32`/1686 de Eclipse.

**Proveedores**: ya estaban Metalúrgica Giser, Bella Vista, Casa Landau, Resortes Charcas,
Eclipse y **Grudzien Claudia Laura — que la planilla llama "Resortes Alfredo"** (otro alias
para la lista de nombres dobles).

**`Melinox` y `Rueda` se dieron de alta el 2026-09-04** `[usuario: "agrega melinox y
rueda"]`, rubro `Bombillas`, con sus partes en Sector Bombilla e inventario en 0:
- **`Z22` Pala de Torta** (id 618, Melinox), `kg_x_uni = 0,037333`, 300 uni por bolsa, precio
  **$ 1.100 por unidad**. **⚠ El código `Z22` queda repetido a propósito**: el otro es el
  "Llavero Pie" (id 135, Sector Procesado). Se respetó el código del maestro del usuario en
  vez de inventar uno — vale la regla de siempre: unir por `componente.id`, nunca por
  `codigo`.
- **`BOM8B` Tela Manga Repostera** (id 619, Rueda). **Se cuenta por ROLLO**: la unidad de
  stock es el rollo (`unidad_medida='unidad'` = 1 rollo) y, según la planilla, **1 rollo rinde
  950 unidades**. Sin precio (la planilla no lo trae) y sin `uni_x_cajon`, porque no hay
  envase por encima del rollo.

**Siguen sin existir (3 proveedores)**: `Alambres Rumbo`, `Colodis Kufo` y **`Ruffo`** — el
caño inox dice **"Giser/Ruffo"**, o sea dos proveedores para la misma pieza y GP2 sólo conoce
a Giser.

**Partes que siguen faltando (10)**:
- **No existen (6)**: `BOM5` Buje Bombilla Bronce y `BOM6` Adorno Bombilla Bronce (Giser),
  `BOM11` Tapita Aluminio (Bella Vista), `Z2S` Aro p/Llavero Grande y `Z2SB` Argolla
  p/Llavero Chica (Casa Landau), `AA6/AE10` Rallador Cilíndrico 14 cm (Colodis Kufo), `BOM4`
  Resorte p/Bombilla Autolimpiante (Grudzien).
- **`BOM10` Resorte Bicónico** (Charcas) existe pero está **discontinuo**, y la planilla lo
  pide con ~500 uni/mes de consumo. O el consumo es viejo o el discontinuo está mal.
- **`BOM14` es un código pisado** `[dato, YA NOS FRENÓ ANTES]`: en la planilla es el **Caño
  Inox 170 mm de Giser**; en GP2 es el **Precinto p/Bombilla de Cimarrón**. Por esto se había
  abortado la carga de factores del 2026-09-04 anterior.
- **`Z19A` Alambre Corta Queso está mal ubicado** `[CORRECCIÓN]`: en GP2 es `IZ19A`, en
  **Sector Fleje**, sin proveedor y discontinuo. **No es el fleje 78 de Brawin** como se
  supuso en la auditoría de flejes de este mismo día: es el alambre de **Alambres Rumbo** y
  vive en la planilla de bombillas. El fleje 78 sigue siendo un faltante aparte.

## 1-undecies. Los utensilios de nylon: la primera familia entera que entra a GP2 (2026-09-09)

`[usuario 2026-09-09: "toda la familia nylon se compra a Pat Bet Plast, excepto la cuchara 33
centímetros, y se manda a tallerista Fábrica para que envase, excepto el pisa papa nylon que
ensambla y envasa Rafael Pettofrezza"]`. Era la familia que faltaba desde la auditoría de
plásticos (idea 7246) y **es el molde para las que vienen**: cucharas de madera, palos de
amasar, coladores, exportación.

**La regla del negocio, corta**: la parte de nylon **se compra hecha** a Pat Bet Plast y el
tallerista sólo **envasa**. No hay matriz, ni proceso, ni proveedor de servicio en el medio —
por eso la ruta tiene tres pasos y no diez.

**Las 6 partes** (Sector Plástico, Pat Bet Plast, inventario en 0, ids 636-641): `PV1` Pisa
Papa (500 uni x bolsa) · `PV2` Cucharón · `PV3` Espátula Lisa · `PV5` Cuchara Fideos · `PV6`
Cuchara Calada · `PV7` Espátula Calada (250 uni x bolsa las cinco). Todas en **NY reciclado**.

**La cuchara de 33 cm es la excepción y ya estaba**: es el `PB2` "Cuchara Ny" (Ny con carga,
200 uni x bolsa) que se cargó el 2026-09-04 **a nombre de Pettofrezza** — venía de la hoja de
Telleria y el usuario la reasignó. Encaja con que "toda la familia se compra a Pat Bet **menos
la cuchara 33**".

**Los 14 artículos** (ids 120-133), con su parte y las unidades por caja que muestra la web:

| LOEKE | CHEF | parte | uni x caja |
|---|---|---|---|
| 355 Pisa Papas | 789 Pisa Papas | `PV1` | 24 |
| 392 Cucharón | 845 Cucharón | `PV2` | 24 |
| 394 Espátula Lisa | 842 Espátula Lisa | `PV3` | 24 |
| 391 Cuchara Fideos | 844 Cuchara Fideos | `PV5` | 24 |
| 390 Cuchara Calada | 843 Cuchara Calada | `PV6` | 24 |
| 393 Espátula Calada | 846 Espátula Calada | `PV7` | 24 |
| 248 Cuchara 33 cm | 908 Cuchara 33 cm | `PB2` | 12 |

**Quién envasa**: los 12 utensilios simples van a **Fábrica**; los dos pisa papas, a
**Pettofrezza Rafael**, que además **ensambla**.

**El pisa papa es el único con más de una parte** `[usuario: "copiá el modelo del 315, que usa
todas las partes, excepto el disco con vástago, porque esa sería la parte de nylon"]`. Sus 3
rutas replican al 315 cambiando el disco `M1` por el `PV1`: `PV1` → Pettofrezza · `PC11`
Mangos ф8 → Pettofrezza · `PA10B` Capuchón → **Ximpa serigrafía** → `PA10` → Pettofrezza.

**Decisiones que tomó el agente y hay que confirmar** `[deducido]`:
- Familia nueva **"Utensilios de nylon"** para los 12, pero los **dos pisa papas fueron a la
  familia "Pisa papas"** que ya existía, para que queden junto al 121/315/609.
- El paso de serigrafía de Ximpa en el capuchón salió de copiar el 315 al pie de la letra: si
  el capuchón del nylon va sin serigrafiar, ese paso sobra.

**Los cartones: 12 de 14 estaban en la planilla de Gráfica Pol** `[dato 2026-09-09, cruce de
la hoja "Pedido VACIO" del Conteo Cartones]`. Se cargaron los 12 (Sector Cartón, Talleres
Gráficos Pol, inventario en 0) con su receta y su ruta de tres pasos, igual que la parte:

| LOEKE (formato **8**, 2.500 uni x paq) | CHEF (formato **Huevo**, 1.000 uni x paq) |
|---|---|
| `A1A` → 248 · `K6B` → 390 · `K6C` → 391 | `R3A` → 789 · `R2C` → 842 · `R1B` → 843 |
| `K7A` → 392 · `K7B` → 393 · `K7C` → 394 | `Q3A` → 844 · `Q3B` → 845 · `R1A` → 846 |

**El "Corb8" de la planilla es el formato `8` de GP2**, y el de CHEF es `Huevo` — los dos
formatos ya existían. Ningún código chocó con los de GP2.

**Dos artículos quedaron sin cartón porque la planilla no los tiene**: el **355** (Pisa Papas
LOEKE) y el **908** (Cuchara 33 cm CHEF). El resto de su familia sí lo tiene, así que
probablemente falte el renglón en el Excel, no el cartón.

**Aparecieron dos artículos de nylon más que no están en las capturas del usuario** `[dato]`:
el **389** "Espumadera Nylon con Mgo" (cartón `K6A`, LOEKE, formato Huevo) y el **456**
"Espátula Lisa Nylon Mgo" (CHEF, 1.000 uni x paq, **el cartón figura sin código**). Los dos
llevan mango, como el pisa papa.

**Las cajas: los 14 ya la tienen** `[usuario 2026-09-09, planilla de Est. Madre LOEKE con la
columna "N° Caja" + "para el caso de Chef, usá la misma caja que usa el gemelo"]`. **Caja
N°7** (`A6`) para los pisa papas, los cucharones y las cucharas fideos (355/789, 392/845,
391/844); **Caja N°12** (`A2`) para las espátulas, las cucharas caladas y las cucharas de 33
(393/846, 394/842, 390/843, 248/908). Cada una con su ruta y la fracción que corresponde
(1/24, o 1/12 en las cucharas de 33). **La caja NO va en `articulo_componente`**: vive en
`articulo.componente_caja_id` y en la ruta, igual que en el 315.

**Ojo con el nombre de la cuchara de fideos**: en LOEKE el 391 se llama **"Cuchara Pulpo"** y
en CHEF el 844 igual — es la misma pieza que la planilla de plásticos llama "Cuchara Fideos"
(`PV5`).

**Cartón del 355 y del 908: creados según gemelo** `[usuario 2026-09-09: "creá los cartones que
faltan según gemelos"]`. La planilla no los traía; el formato lo dicta el gemelo, no la marca:
`F3C` "Cartón 355" (LOEKE, **Huevo** como el R3A del gemelo 789, y como el 315) y `Q3D`
"Cartón 908" (CHEF, **formato 8** como el A1A del gemelo 248). Los dos de Pol, con receta y
ruta.

**La caja va también en el BOM, no sólo en la ruta** `[usuario 2026-09-09 + confirmado contra
el 315]`. Cada uno de los 14 tiene ahora la caja en `articulo_componente` con **cantidad =
1 / uni_x_caja** (0,0417 los de 24, 0,0833 los de 12) — además de `componente_caja_id` y el
paso de ruta. Regla general: **una caja rinde N artículos, así que cada artículo consume
1/N de caja**; eso es lo que va al BOM. El cartón va con cantidad 1 (uno por artículo).

**Lo que quedó pendiente y hace falta para que la cuenta cierre**:
3. **`456` Espátula Lisa Nylon C/Mango y `389` Espumadera Nylon con Mgo NO se cargaron**: son
   los dos que llevan mango y no se sabe qué parte usan.
4. Las 6 partes y los 12 cartones están **sin precio**, y las partes sin `kg_x_uni`, así que
   hoy entran al costo en $0.

## 1-decies. Cartones: 74 de 161, y casi todo lo que falta es cartón de un artículo que no existe (2026-09-08)

`[dato: planilla "Conteo Cartones VACIO", hoja "Pedido VACIO"]` 229 renglones, **161 códigos
de cartón distintos**; GP2 tiene **74**. Pero el número asusta más de lo que es: **de los 87
que faltan, 77 son el cartón de un artículo que GP2 tampoco tiene** (cucharas de madera,
coladores, ralladores, utensilios de nylon e inox, tapones de vino, pinceles). No son altas
sueltas: entran cuando entren esas familias — la misma decisión de la idea 7244.

**Los que sí son faltantes duros — el artículo está vivo y no tiene su cartón (6)**:
`A1D` Bolsa Filtro Café LOKE (art 120, Envases Vihal) · `D5A` Corta Queso Blandos (546) ·
`E2B` Sacacorcho Mgo Ergonómico (581) · `G6A` Filtro Para Bombillas (550) · `H2A` Sac Cabo
Ergonómico Nylon (104) · `P1A` Filtro de Bombilla CH (760) — los cinco últimos de Talleres
Gráficos Pol.

**Insumos del sector que GP2 no conoce (14)**, todos de uso general y no de un artículo:
5 precintos negros (N° 8 a 16, **Precinter**, por 20.000), 5 etiquetas y el ribbon
(**Sumatik**, por 8.000), film stretch y fleje de polipropileno (**Packaging y Servicios**),
y las 4 bolsas de filtro de café de los arts 031, 034, 836 y 867 (Envases Vihal y Papelera 9
de Julio) — esos cuatro artículos están vivos y ninguno tiene su bolsa.

**Proveedores de cartón**: ya están Talleres Gráficos Pol, Papelera Nueve de Julio, Envases
Vihal y Packaging y Servicios. **Faltan `Precinter`, `Sumatik` y `Cia Integral Etiquetas`** —
este último es sólo el proveedor: sus tres piezas (`C3A`, `H4C`, `T4A`, las etiquetas de los
afiladores 504, 114 y 97) **ya existen en GP2 pero sin quién las provee**.

**`AJ Adhesivos` aparece VENDIENDO el pliego** `[SIN RESOLVER]`: en GP2 existe sólo como
`proveedor_servicio` (adhesivado), y acá figura como proveedor de los pliegos de abrelatas y
bombillas. Sus códigos `A2A` / `V3A` son los `Pliego Ad 500` y `Pliego Ad 506` de GP2 — o sea
renombre, no alta; el de "Bombilla Chef" (`A1C`) no tiene equivalente. Falta decidir si además
se da de alta como proveedor de insumo.

## 1-nonies. Control de Partes: cómo se llaman las hojas y quién es cada una (2026-09-08)

`[usuario 2026-09-08 + dato: los dos Excel "AA Control Partes Talleristas" y "Control Partes
Prov de Servicios"]` **Las hojas del control de partes usan apodos, no los nombres de GP2.**
Traducción confirmada:

| hoja del Excel | es en GP2 | cómo se supo |
|---|---|---|
| Martin | Martin Cornejo (tallerista 6) | alias `MARTIN` |
| Poly | **IJUPA** (tallerista 10) | `[usuario]` + alias `POLY` |
| **Carlos** | **Alex Escalante** (tallerista 2) | `[usuario 2026-09-08]` |
| **Pedernera** (en el Excel de TALLERISTAS) | **Carlos Aguirre** (tallerista 9) | `[usuario 2026-09-08]` |
| Garcia | Danica Garcia (1) · Lucho | Lucho (5) · Rafael | Pettofrezza (11) | alias |
| German | Cavallero German (4) | alias `GERMAN` |
| **Yabran** | **Gentile Norberto** (tallerista 8) | alias `OSCAR`; la hoja dice "OSCAR" en el encabezado y lista los mismos GRJ que Gentile tiene en sus rutas |
| Ester | **Ester**, que en GP2 es `proveedor_servicio` 14 (Calado), no tallerista | dato |
| Ximpa | **Hernandez Julio** (`proveedor_servicio` 8, Serigrafiado). La hoja dice **"NO SE LE MANDA MÁS"** | dato |
| Pedernera (en el Excel de PS) | Pedernera Ilario (`proveedor_servicio` 6, Cromado) | alias |
| Pintura y Serigrafia | una sola hoja para **varios** PS: Jade, Rec Color, Daniel (pintado) y Ximpa (serigrafiado) | dato |

**⚠ El alias `CARLOS` de `contraparte_alias` apunta al tallerista equivocado** `[hallazgo
2026-09-08]`: hoy dice `CARLOS → 9 (Carlos Aguirre)`, pero el usuario aclaró que **la hoja
"Carlos" es Alex Escalante** y que el Carlos Aguirre del control es la hoja "Pedernera". El
alias `AGUIRRE CARLOS RODOLFO → 9` sí está bien. Mientras `CARLOS` apunte a 9, cualquier
importación desde esas planillas le carga a Aguirre lo que hace Escalante. **No se tocó**:
lo decide el usuario.

**Contrapartes del Excel que NO existen en GP2**: talleristas **Ezequiel** (su hoja arranca
con el título "German", así que puede ser una copia), **Edwin**, **Nacho** y **Ruben** (la
hoja más grande de las cuatro, 48 códigos); proveedores de servicio **New Metal**,
**Chormium**, **Gaston Almafuerte** (los tres hacen lo mismo que Mabra: el pavonado
`X5 → Y1`) y **Valeria** (hace la horqueta del corta queso: `V15C` Tornillo Corta Queso +
`VCCQ` Varilla Cuerpo).

**⚠ `V15C` en el maestro viejo es el Tornillo Corta Queso de Valeria**, no el Rem Tapón
Hierro: el Excel de remaches usa `V15C` para los dos. Por suerte el tapón se cargó el
2026-09-04 como **`CV15`** (renombre pedido por el usuario), así que no hay colisión activa
— pero si algún día entra el tornillo de Valeria, va con `V15C`.

**Los cajones no existen en GP2** `[dato]`: `CAJ1` (Cajón Plástico s/Calado), `CAJ2` (Cajón
Plástico Calado) y `CAJ3` (Cajón Metálico) están en **9 de las 14 hojas de talleristas** —
se cuentan y se mandan como cualquier otra parte, porque son el envase con el que va y viene
el trabajo. GP2 no los conoce, así que no se pueden enviar ni contar.

## 1-octies. Garage: la numeración GRJ está corrida entre la planilla y GP2 (2026-09-04)

`[dato: planilla "Relevamiento Garage VACIO", hoja "Pedido Garage VACIO"]` 17 renglones. **No
se cargó nada: está bloqueado por la numeración.** Tres códigos son dos cosas distintas al
mismo tiempo:

| código | en la planilla del usuario | en GP2 |
|---|---|---|
| `GRJ13` | Cepillo Limpia Mamadera (Gilardi) | Bowls 330ml (Cimarrón, discontinuo) |
| `GRJ14` | Cepillo Limpia Vajilla (Gilardi) | Bombilla Pico de Loro (Cimarrón) |
| `GRJ15` | Pintura Azul Mate (Ortiz Yanina) | Bombilla Plana Ancha (Cimarrón) |

Y del otro lado, los **`GRJ18`/`GRJ19`** de la planilla (Bombilla Pico de Loro y Bombilla
Plana Chata) **son los que GP2 llama `GRJ14`/`GRJ15`**: las mismas bombillas con dos números.
Cargar por código acá mezcla un cepillo con una bombilla. **Lo decide el usuario** (idea
7248): o se renumeran las bombillas de GP2 a 18/19, o las tres partes nuevas entran con otro
código.

**Coinciden y están bien**: `GRJ1`, `GRJ4`, `GRJ5`, `GRJ6`, `GRJ7` (la planilla lo llama
`GRJ7/8`) y `GRJ10`. Los que están en `fabricacion` no salen en Recepción y eso es correcto:
los arma un tallerista, no se compran.

**Contrapartes**: están Martin Cornejo, Alex Escalante, Pettofrezza Rafael y Cimarrón (la
planilla lo llama "Cooperativa Cimarron"). **No existen `Gilardi Esther` (3847)** ni
**`Ortiz Yanina` (4288)**. **Pintos** existe sólo como proveedor de insumo y acá es tallerista
de garage. Y **Tierra Nativa**, desactivada como tallerista el mismo día por pedido del
usuario, es la que hace `GRJ16` y `GRJ17` — hay que decidir por dónde entran.

**Faltan 7 partes**: `GRJ9` Abrelata Uña Ac Inox, `GRJ12`/`GRJ12B` Ñoqueras (que en la
planilla de plásticos son `PGRJ12`/`PGRJ12B` — mismo bicho, dos códigos), `GRJ16`
Despolvillador de Yerba, **`GRJ17` Palo de Amasar Francés 40 cm** (el que va en la caja N°15),
`GRJ20` Set Tapers, más los dos cepillos y la pintura que están trabados por la numeración.
**Sobra** en GP2 el `GRJ10A` Batidor Pera Mini, que la planilla vigente no lista.

---

## 2. Materiales y procesos: la lógica del inoxidable

`[usuario 2026-08-29]` **Regla estratégica: conviene pasar partes de fleje laminado a
inoxidable.** El ahorro no es sólo el material, es todo lo que se evita:

1. El **tratamiento de cromado** en sí.
2. El **transporte de ida** al cromador (Pedernera, en la isla).
3. El **transporte de vuelta** a buscarlo.
4. El tiempo que la pieza está fuera de la fábrica.

Además, en Argentina **el fleje normal puede costar más caro que el inoxidable**, así que
el cambio puede convenir incluso mirando sólo el material. `[usuario]`

**La excepción — lo que se pinta va en fleje normal.** La pintura necesita el material
común como base, así que una pieza destinada a pintura no se pasa a inoxidable.
`[usuario]`

**Pero la excepción NO es por pieza, es por destino** `[usuario 2026-08-29]`: una misma
pieza puede comprarse en **los dos materiales a la vez** — inoxidable para las unidades
que iban a cromado, y fleje laminado para las que se pintan. Lo que decide si se puede es
el **mínimo de compra del proveedor**: si el mínimo da, conviene partir la compra en dos
materiales; si no da, hay que elegir uno. Ejemplo dado: el **destapador** podría llevar
inox para la versión cromada y laminado para la pintada.

Por eso las 4 piezas que hoy van a cromado **y** a pintura (G7, H11, I1, I6) no quedan
descartadas: son candidatas a compra partida, sujeto al mínimo del proveedor.

Ejemplo dado: **el cuerpo del 510** antes se hacía en fleje laminado y hoy se hace en
inoxidable. `[usuario]`

### Qué dice la base hoy
`[dato 2026-08-29, GP2.ruta_paso + public."Partes x PS"]`
- **Cromado → Pedernera Ilario: 38 partes.** Éstas son **las candidatas** a inoxidable.
- **Pintado → Jade (15), Daniel (14), Rec Color (4) = 33 partes.** Las unidades que se
  pintan van en fleje normal — pero la pieza puede igual tener una parte de su compra en
  inox si además va a cromado y el mínimo del proveedor lo permite (ver regla de arriba).
  `[corregido 2026-08-29: antes decía que quedaban descartadas]`
- Otros procesos: Niquelado → Guazzaroni (24), Zincado → Guazzaroni (6), Cementado y
  Templado → FAAT, Serigrafiado → Ximpa, Adhesivado → AJ Adhesivos.
- Ya hay **13 componentes con "inox" en la descripción**: la migración empezó de hecho.

### Las 34 candidatas concretas (las que hoy van a Pedernera a cromar)
`[dato 2026-08-29: GP2.ruta_paso, pasos con proveedor_servicio = Pedernera Ilario]`
La mayoría son **Sector Crudo** y el código lo dice solo ("p/Cromar"):

G4 Cpo Sacacorcho 521 · G7 Pieza Abierta Rompenuez · G15 Mariposita Abrelata ·
H1 Manija Redonda · H11 Varilla c/Cuchilla · H16 Super Mariposita · I1 Destapador Pie ·
I6 Mango Plano 502 · I11 Mgo Plano 701 · J7 Destapa C. LK · J10 y J12 3 en 1 ·
J15 Cabezal doblado · K8 Sacatapita · K14 Vástago Corta Pizza Gastr ·
L8 Vástagos Cortos · L15 Vástago Corta Pizza Chico · LL7A Vástago Pelapapa ·
M6 y M8 Mango Pelapapa (LK / CH) · N1 Ahuecafruta · N2 Ahuecapapa · N7 Pinza Corta ·
W2 y W7 Engranaje (grande / chico) · Z2B y Z3B Pza Grande Sacaf Art · Z4 Pza Chica ·
Z36 Sacafuente Pizzero · C12 Paleta Batidor · I2 Resorte U · E3-M234 Fleje N°80 ·
GRJ10 y GRJ10A Batidor Pera.

**Las más pesadas primero** (más kg = más ahorro de material por pieza): Z36 Sacafuente
Pizzero (0,119 kg), GRJ10/GRJ10A (0,098), N7 Pinza Corta (0,068), H1 Manija Redonda
(0,049), G7 Rompenuez (0,046), G4 Sacacorcho (0,045).

**Cuatro tienen ADEMÁS un paso de pintura** (G7 Rompenuez, H11 Varilla c/Cuchilla,
I1 Destapador Pie, I6 Mango Plano 502): son las candidatas a **compra partida** — inox
para lo que va a cromar, laminado para lo que va a pintar, si el mínimo del proveedor da.
`[usuario 2026-08-29, confirmado; corrige el "no se pasan" que estaba deducido]`

### Lo que falta para poder decidirlo con números
`[deducido — hueco real, hay que cargarlo]` Para calcular el ahorro pieza por pieza faltan
tres datos que **hoy no están en GP2**:
1. **Precio por kg del fleje laminado vs. el inoxidable** (por proveedor y medida).
   `GP2.precio_proveedor` sólo tiene **11 precios de cartón**, y ninguno atado a un
   componente.
2. **Cuánto cobra el cromado** (Pedernera) por pieza o por kg.
3. **Costo del flete** ida y vuelta a la isla.

Con esos tres, el cálculo por pieza es directo:
`ahorro = (costo_cromado + flete_prorrateado) - (precio_inox - precio_laminado) x kg_pieza`
y sale el ranking de las 34 candidatas por ahorro anual usando el consumo de la Est Madre.


## 2b. Quién pinta: no hay un pintor por parte

`[usuario 2026-08-30]` **A una misma parte la pueden pintar varios.** Es la diferencia de
fondo con los inyectores, donde cada parte tiene **un** proveedor. Por eso pintura necesita
una relación de muchos a muchos, no un campo.

`[dato 2026-08-30, public."Partes x PS" donde Proceso = pintado]` Y no es un caso raro, es
**la regla**: de las 11 partes pintadas del vecino, **ninguna la pinta uno solo**. Cuatro
las hacen los tres (G13, G2, I6, J2) y siete las hacen Daniel + Jade.

**Renombrado 2026-08-30**: `proveedor_servicio.nombre` id 5 pasó de "Becker Sandra
Nora" a **"Jade"** (elección del usuario: "lo que sea mejor para la normalización"). El
nombre legal quedó como alias en `contraparte_alias` (tipo proveedor_servicio, ref 5)
así el espejo Virgilio sigue matcheando por cualquiera de los dos. La ubicación 17
también: "Prov. Serv. Jade".

**Quiénes pintan** `[usuario 2026-08-30]`:
- **Jade** (= Becker Sandra Nora, ver arriba) y **Daniel**, que son los dos que trabajan.
- **Rec Color** existe y hay que tenerlo contemplado, pero *"creo que no le mandamos nada"*.
  Está dado de alta como proveedor y **sin partes asignadas**: aparece en la botonera para
  poder sumarlo con un toque el día que haga falta.

**El reparto NO es partir cada parte: es repartir el TRABAJO.**
`[usuario 2026-08-30, corrigiendo lo que había dicho antes]` Primero se anotó "partes
iguales" y se implementó mal: se dividía el consumo de **cada** parte entre sus pintores
(media Uña a uno, media Uña al otro). El usuario lo corrigió con un ejemplo que lo deja
claro:

> *"Si a uno le mando quince cajones a pintar de uña, entonces al otro le mando diez
> cajones a pintar de sacacorcho. Pero darle las dos cosas a los dos no tendría sentido."*

O sea: **la parte va entera a un pintor**. Lo que se empareja es el **total de cajones del
mes** de cada uno. Por eso la tabla guarda dos cosas distintas: las filas dicen quién
*puede* pintar cada parte, y la marcada con `asignado` dice quién la *tiene* este mes.

**Se mide en CAJONES, no en unidades** `[deducido del ejemplo del usuario]`: así se manda a
pintar y así lo piensa él. Sale de `consumo ÷ componente.uni_x_cajon`.

**Lo propone el programa** `[usuario 2026-08-30]`: reparte solo, dando la parte más pesada
al pintor menos cargado, y la persona corrige lo que no le cierre. Con los números reales
propone Uña (7,5 cajones) a Jade y Sacacorcho + Mango (8,3) a Daniel — que es exactamente
el ejemplo que dio el usuario, sin habérselo dicho.

### El consumo de una parte que se pinta no está donde uno lo busca
`[dato 2026-08-30]` `v_consumo_parte` **no sirve** para las partes pintadas: esa vista sólo
cubre componentes que están **directo en la receta** del artículo, y lo que se pinta es
intermedio (entra a un paso de ruta y sale como otra pieza). Medido: de las 12 partes
pintadas, **cero** aparecen ahí.

**CORREGIDO el mismo día**: el primer parche ("sumar el consumo de las salidas") estaba
MAL — sobrecontaba cuando dos ramas convergen en la misma salida. El caso que lo destapó
lo vio EL USUARIO: K2 y K5 mostraban el mismo consumo (2.784). K2 (Chef) rinde 46/mes y
heredaba entero el número de B4, que era casi todo de K5 (LK). Hoy el consumo de
cualquier parte, pintada o no, se lee de `v_consumo_componente` (ver sección 3b), que
atribuye por artículo. `pintores_bundle()` ya la usa. Las 12 partes tienen número.

### B4 eran dos piezas distintas metidas en una fila (partido 2026-08-30)
`[usuario 2026-08-30]` "No llegan al mismo lugar, porque uno tiene marca y el otro no."
B4 "Cpo Sacacorcho Pint Azul LK/CH" mezclaba: (a) el cuerpo pintado **LK** que Martin
arma directo en 530/531, y (b) el cuerpo pintado **sin marca** que sigue a serigrafía de
Hernandez Julio y recién ahí es Chef (B7 → 730/731). Se partió: **B4 = LK** (rutas
69/70), **B4B = "Cpo Sacacorcho Pint Azul S/marca CH"** (rutas 72/73, con la fila de
inventario en lo de Hernandez que antes tenía B4). Código B4B elegido por el usuario.
La pista para detectar otros casos así: descripción con "LK/CH" + inventario en una
ubicación que sólo toca una de las ramas. Se barrió toda la tabla: el único otro "LK/CH"
es Z1A (Pza Chica Sacaf Art), y ése SÍ es compartido de verdad (la marca la lleva la
pieza grande Z2A/Z3A) — no se toca.

---

## 3b. Consumo de TODA la cadena: v_consumo_demanda / v_consumo_componente (2026-08-30)

`[dato 2026-08-30]` Vistas nuevas en GP2. **`v_consumo_parte` NO se tocó** (es el corte
del walk de `v_consumo_fleje_kg` de producción; cambiarla cascadea a OC y a
`inventario.maximo` vía triggers). Lo nuevo convive:

- **`v_consumo_demanda`** (articulo, componente, uni_mes): la demanda de la Est Madre
  explotada por receta (`articulo_componente` + `componente_bom`) y caminada HACIA ATRÁS
  por las rutas **del mismo artículo**. Reglas que costaron sangre:
  - **Atribuir por artículo, no "parar en el primer nodo con consumo"**: eso sobrecontaba
    60x (K2 = 46, no 2.784).
  - **El walk se corta al llegar a otro componente de receta del mismo artículo**: la
    receta de 508 lista D13 (virola) Y PC12 (mango que la contiene); sin el corte, la
    virola se contaba doble.
  - `UNION` sin ALL en el walk: dedupe de rutas duplicadas por tallerista y corte de ciclos.
  - Joins por `id`, nunca por `codigo` (B4 y B7 existen como parte Y como fleje).
- **`v_consumo_componente`**: la plana por componente (suma sobre artículos). Cobertura
  vs la vieja: crudo 4→76, fleje 3→51, tránsito 0→38, procesado 75→81. De los 230 que ya
  tenían número, 229 idénticos; el único que cambia es D13 822→1.264 y está BIEN (la
  vieja no veía las virolas que viajan adentro de los mangos de 564/708).
- **`v_consumo_fleje_kg_v2`** (desde el 2026-09-05 se llama `v_consumo_fleje_kg`, la vieja ya
  no existe): kg de fleje con la demanda atribuida. vs la vieja: 43/45
  iguales; A11 32,8→22,7 (la vieja le colgaba demanda del cuerpo C15 que no sale de ese
  fleje) y D8 4,3→6,6 (le faltaban las virolas de 564/708). Las dos diferencias son
  errores de la vieja.

**Repuntado 2026-08-30 (mismo día)**: `v_punto_stock`, `oc_bundle` y
`recalcular_maximos_insumos` ya usan las vistas nuevas. El recálculo corrió: 19 máximos
derivados cambiaron (2 flejes corregidos + 13 remaches y 4 bombillas que estaban en 0).
Las vistas viejas quedan sin consumidores, solo como referencia.

**El consumo es TOCABLE** `[usuario 2026-08-30]`: "quiero poder tocar donde figura lo
que hay que enviar y su sustento contra el consumo de los artículos que lo utilizan".
RPC `consumo_detalle(p_comp_id)` + `consumo-detalle.js` (helper compartido en la raíz):
tocar el número abre el desglose por artículo (proyección del artículo y cuánto le pide
a la parte, en kg si es fleje). Cableado en Pintores, OC, Punto de Stock y Orden de
Producción. Si una pantalla nueva muestra consumo, se le cablea el mismo helper.

**Las pantallas de Envíos/Entregas comparten UN helper (2026-08-30, v1.50.0)** `[dato]`:
`gp2-envios-common.js` en la raíz (namespace `GP2EE`) junta lo que estaba copy-pasteado
en Envíos/Recepción Tallerista, Envíos/Entrega PS, Entregas Prov AT y los Controles:
cliente Supabase GP2, esc/num/fmt es-AR, buffer de carga en localStorage por contraparte
(sobrevive F5; lo registrado sale del buffer ítem por ítem, así un reintento no duplica),
fases fase0/fase1/fase3 con `#btnVolver`, grilla de contrapartes, popup de tandas y
celdas de carga. Una pantalla nueva de envío/entrega se cablea a `GP2EE`, no se copia.
**LA REGLA DE NÚMERO DE LA CASA, y vive en UN archivo (2026-09-03, v1.67.0)** `[usuario]`:
textual, *"si hay un punto, el punto para el separador de mil; la coma para los decimales"*
y *"en cada lugar que ponga cuatro dígitos, que se ponga automático un separador de miles"*.
O sea, sin adivinar nunca: **`1.234` son mil doscientos treinta y cuatro** (no uno coma dos
tres cuatro), `12,5` son doce y medio, `999` se queda quieto y `1000` se ve `1.000`. **Esto
reemplaza la regla del 2026-09-01** (*"los inputs numéricos con coma o punto que ambos pongan
punto"*), que era al revés.

Vive en **`gp2-numero.js` (namespace `GP2N`)**, en la raíz, suelto y sin dependencias:
`GP2N.num()` (texto→número), `GP2N.entero()`, `GP2N.conMiles()` (formatea lo tipeado),
`GP2N.autoMiles(input)` y `GP2N.autoMilesEn(nodo)`. **Una pantalla que lo carga ya tiene el
formato en todos sus campos numéricos sin hacer nada**: se engancha sola al enfocar, así que
también agarra las tablas que se repintan. Un campo lleva coma o no **según su teclado**, que
es la convención que ya estaba en CLAUDE.md — `inputmode="decimal"` lleva coma,
`inputmode="numeric"` son enteros (`data-dec="si"/"no"` lo fuerza si hace falta).

Existe porque la regla estaba escrita **seis veces y ninguna igual** (idea 7217) y cada
pantalla contestaba distinto qué era `"1.234"`: `GP2EE.num` decidía *"el último separador es
el decimal"*, el `parseNumTol` de Altrak/Aperam adivinaba según cuántos puntos hubiera, el
popup de tandas leía los cajones con `Number()` crudo (que hace de `"1.000"` un 1) y Recepción
Cervantes borraba la coma tecla por tecla. **Regla nueva: una pantalla NO escribe su propio
parser de número — carga `gp2-numero.js`.** El test `tests/ui/test_numero.js` lo vigila: falla
si aparece un `.value = ...replace(/\D/g...)` o un `parseFloat(...replace(',','.'))` en una
pantalla GP2 o en un JS que esas pantallas carguen.

**El parser de número quedó UNO SOLO (corrección 2026-09-03)** `[dato]`: el modo
`GP2EE.num(v,"simple")` (el que leía "1.234,5" como 1,2345) se ELIMINÓ el 2026-08-30 —
`num()` acepta el parámetro `modo` y lo ignora, y todas las pantallas cableadas a `GP2EE`
usan la regla buena: el último separador es el decimal. Lo que sigue vivo es OTRO
problema, y está FUERA de `GP2EE`: las pantallas que NO usan el helper tienen su propio
saneador local de `input`, y varios son destructivos. El peor ya mordió: en
`Recepcion Cervantes.html` los campos de kg hacían `replace(/[^\d.]/g,"")` **al tipear**,
así que la coma que ofrece el teclado es-AR se borraba tecla por tecla y "12,5" quedaba
125 (x10), "250,75" quedaba 25075 (x100) — datos de producción inflados en silencio.
Arreglado 2026-09-03 normalizando la coma a punto ANTES de sanear. Regla: **un saneador
de `input` nunca borra la coma, la traduce**; y si la pantalla es de envío/entrega, va
cableada a `GP2EE.num` en vez de tener parser propio.

**Orden de Producción repuntada a DEMANDA (2026-08-30, v1.49.0)** `[dato]`: el módulo
`OrdenProduccion/` calculaba `faltante = máximo físico − stock` (llenar la estantería):
proponía ~2,8 millones de unidades en pantalla (~3,7M sumando todos los destinos crudo +
procesado) cuando la Est Madre proyecta ~196.000 uni/mes. Ahora usa la RPC
`orden_produccion_bundle()` (SECURITY DEFINER, un solo viaje: pasos de matriz
deduplicados, matrices, componentes y destinos) y el faltante es
`greatest(0, round(consumo_uni_mes × ubicacion.meses_stock − stock))` — mismo patrón que
`oc_bundle()` para insumos, con `v_consumo_componente`. El total en pantalla baja a
~420.000 uni (574.423 sumando todos los destinos). El máximo físico y el stock siguen
como contexto, el stock se puede pisar a mano, y el consumo es tocable (sustento por
artículo). Un destino sin consumo conocido dice "sin consumo" y no aporta faltante — no
se inventa.

**Barrido de accesibilidad de TODAS las pantallas (2026-09-03, v1.66.0)** `[dato]`: una
auditoría global encontró que la regla de letra grande estaba rota en varios frentes a la
vez, y ninguno lo agarraba la suite. Lo que se aprendió:

- **`gp2-claro.css` se pisaba a sí mismo.** El bloque "LETRA +1" (2026-08-31) escribió
  `input, select, textarea, button { font-size:17px !important }` DESPUÉS del piso de 18px
  y con la misma especificidad, así que ganaba el 17 en las 13 pantallas que cargan ese
  CSS. Y encima se tocó el archivo sin bumpear el `?v=`, así que las tablets seguían con
  la versión de antes del "letra +1" — el clásico "no veo los cambios". **Regla: cuando se
  toca la tipografía, los campos SUBEN, nunca bajan; y todo cambio de CSS compartido bumpea
  su token en las páginas que lo cargan.**
- **El cluster `Produccion/` (abm, entrevistas, tiempos, monitor, rendimiento) no carga
  `gp2-modulo.css` ni `gp2-claro.css`**, así que nada le levantaba los campos: estaban en
  13px con 36px de alto. Una pantalla sin el CSS de la casa hay que revisarla a mano.
- **La app de operarios tenía 8 reglas con `color:#fff` sobre fondos casi blancos**
  (`#e7ebf8`, `#e7f8ed`, `#f8e7e7`): botón Continuar, cajas seleccionadas, Terminar Día.
  Contraste ≈1,2:1, ilegible en la tablet del galpón. Vino de un pase masivo que aclaró
  los fondos sin tocar los textos. **Regla: fondo pálido = ESTADO (una caja elegida), y
  ahí el texto va oscuro; un BOTÓN de acción va sólido con texto blanco.** Mismo bug
  aparecía en `ControlPS_GP2` (botón Guardar) y en `ABM_Articulos_GP2` (dos inputs).
- **`.seg-btn` estaba copiado idéntico en 9 pantallas de stock** (Flejes ×6, SC, SP,
  Movimiento) y en las 9 medía 38px. Se unificó en `gp2-modulo.css` a 44px: ahora se toca
  una vez. Lo mismo vale para cualquier regla que aparezca 3+ veces igual.
- **Los guardias de la suite tenían agujeros y por eso nada de esto saltaba**:
  `test_teclado_numerico` sólo miraba el piso en `gp2-modulo.css` (no el resto del CSS ni
  los `type="text"` que piden números), y la regex de `test_tokens_cache` no incluía el
  espacio, así que **toda ruta con carpeta espaciada** (`Control Tall/`, `Prov Serv/`,
  `Stocks General/`) se salteaba sin avisar — `ControlTall.css` convivía con dos tokens y
  el test decía OK. Los dos se ampliaron: el de campos ahora parsea todo el CSS de las
  pantallas GP2 y el de tokens lee el atributo `src=`/`href=` completo.

**Cuando dos talleristas hacen la MISMA pieza, se paga UNA sola vez (2026-09-03)** `[usuario]`:
textual, *"uno u otro, no x2 de costo"*. El CTE `talx` de `v_costo_componente` sumaba las
tarifas de todas las rutas que producen una pieza, así que un artículo cuyo armado hacen
dos talleristas lo pagaba dos veces. Corregido: ahora se elige **una tarifa por pieza** (se
toma la más cara, para no subestimar) y recién después se suman las piezas **distintas** de
la cadena, que sí deben sumar. Afectaba 6 piezas: 315 y 609 (Pettofrezza $140 / Cavallero
$85), 505 (Danica / Lucho $33), 510 (Alex / Martin $27,14), 500 y GRJ7 (Martin / Alex $8,99).
**La regla vale para cualquier caso nuevo**: dos talleristas alternativos para la misma
pieza no son dos pasos, son una elección.

**El armado de tochos del 504 se estaba cobrando dos veces (2026-09-03)** `[usuario]`:
mismo criterio que arriba. La ruta 37 (*Fleje 10 → Art 504*) pasa primero por **Lucho**
(F7 → **J1**, *Tochos Zinc p/Rectificar*) y después por **Martin** (E4 → 504, el afilado).
Pero al cargar las tarifas del Excel el 2026-09-02 la línea *"Afila Cuchillos 504 Arm
Tochos"* se sumó **además** adentro del precio de Martin ($131,46 + $194,25 = $325,71),
cuando ese mismo trabajo ya estaba cobrado en el J1 de Lucho ($173,817). Se queda el de
Lucho — que es quien la ruta dice que hace los tochos — y **Martin vuelve a $131,46**, igual
que en sus gemelos 097 y 114. El 504 baja de $2.626,49 a $2.432,24. **Trampa a recordar**:
cuando una línea del Excel describe un paso que en GP2 es un COMPONENTE aparte, no se
suma al precio del artículo — se carga en ese componente.

**El consumo sale de la RECETA, no de la RUTA (2026-09-03)** `[dato]` — la trampa más cara
encontrada hasta ahora. `v_consumo_demanda` arma el consumo con
`articulo_componente.cantidad` (y `componente_bom`), y después **camina la ruta hacia atrás
sin multiplicar por la cantidad de cada paso**. O sea: `ruta_paso.cantidad` **no participa
del consumo**, solo del costo (CTE `insumox`). Consecuencia real: el `Pliego Ad 506` tenía
1/12 en la ruta y **1 en la receta**, así que la Est Madre pedía 16.968 pliegos/mes en vez
de 1.414 — **$15,5M/mes** de pedido fantasma, ~$85,6M sobre los 6 meses de la OC. El
usuario confirmó el 2026-09-03: **el pliego del 506 rinde 12** (*"1 12"*). Corregido en la
receta. **Regla: cuando una parte rinde N unidades, la división va en LAS DOS —
`articulo_componente.cantidad` y `ruta_paso.cantidad` — o el consumo y el costo dicen cosas
distintas.** Quedan 8 desacuerdos receta≠ruta sin resolver (ver ideas 7223 y 6116).

**Los flejes van en KILOS, sin excepción (2026-09-03)** `[usuario: "4 Dale"]`: `IC3`
(*Fleje N° 90*, el alambre galvanizado Ø 1,63 mm de Altrak con el que se hacen los filtros
de café), `IE13` e `IZ19A` eran los únicos **3 de los 50 flejes** con
`componente.unidad_medida = 'unidad'`. Como se compran, se reciben y se cotizan **por kilo**
(IC3: USD 1,715/kg), el inventario guardaba unidades mientras el precio era de kilo, y
`v_valor_stock` y la valorización de la OC multiplicaban una cosa por la otra: **IC3 figuraba
con $27,3 millones de stock cuando valía ~$226.000**, y $50,3M/mes de consumo. Pasados a kg.
Dos cosas que valen como regla:

- **El costo de los ARTÍCULOS ya estaba bien y no se movió ni un peso.** El CTE `mat` de
  `v_costo_componente` convierte solo para `sector_id = 5` (031 y 836 = $333,02; 034 y 867 =
  $362,00). Lo único que estaba mal era el **costo unitario del fleje en sí**, que es lo que
  usan el stock valorizado y la OC. Si un número de plata huele mal, mirar **por dónde entra
  la parte**: el mismo dato puede estar bien por un camino y mal por el otro.
- **Para reexpresar un stock NO se toca `inventario` a mano ni se inventa un ajuste.** Se
  cambia `unidad_medida` y después se *toca* el movimiento (`update movimiento set cantidad =
  cantidad`): `to_canonical` lo reconvierte con la unidad nueva y `fn_movimiento_aplicar`
  revierte el delta viejo y aplica el nuevo. El movimiento sigue diciendo la verdad de lo que
  se cargó ("480 unidades") y el inventario queda en kg (3,984). El motor de inventario vive
  en la BD: se le habla por `movimiento`, nunca por `UPDATE inventario`.

**Las 81 recepciones de insumos que había eran TODAS de prueba (2026-09-03)** `[usuario:
"eliminalas todas, fueron todas de prueba"]`: nacieron con el módulo (29/08 al 02/09) y se
veían las tandas repetidas (*Caja N°1* cuatro veces a 10.000, *Cartón 510* seis veces en el
mismo minuto). Borradas. **El remito NO tiene nada que ver**: 74 de las 81 no lo tenían y
eso me sirvió para encontrarlas, pero es una huella, no la causa — el campo es **opcional a
propósito** (`placeholder="Opcional"`) porque el remito no siempre está a mano cuando entra
la mercadería. Que sea opcional no fue lo que generó las pruebas. **Cómo se borra una recepción**: primero el
`movimiento` — `fn_movimiento_aplicar` corre también en DELETE, así que el trigger revierte
el stock solo — y después la fila de `recepcion_insumo` (`recepcion_control` y
`recepcion_control_rollo` caen por CASCADE). Ninguna OC tenía `recibido <> 0`, así que no
hubo cruce que deshacer. **Un solo rojo quedó**: `IA1` a −40,88 kg, porque el movimiento 1373
del 31/08 (fabricación de 40,876 kg de IA1 → 1.250 uni de `J2`) consumió ese stock de prueba.
Ese movimiento **no se borró a propósito**: `J2` tiene una cadena entera colgando (envío a
Jade, entrega de vuelta a Procesado y los dos ajustes del blanqueo de negativos del 02/09),
y borrarlo reabriría negativos ya limpiados. Se blanqueó con un `ajuste` trazado, mismo
patrón que las ideas 7204 y 7212. **El stock valorizado total baja de ~$116M a $9,54M** — y
ese $9,54M es el número que hay que creerle.

**Prov AT quedó entero en GP2 (2026-09-03, v1.68.0)** `[usuario: "que no escriba en public,
que migre, y que vaya todo directo al esquema GP2"]`: el módulo estaba partido al medio.
**Envíos** ya escribía en GP2 (`crear_envio_prov_at`) y el **Control** ya leía GP2, pero
**Entregas** — la pantalla donde el proveedor devuelve el artículo terminado — seguía
escribiendo en `public."Entregas Prov AT"`, la casa del vecino. O sea: lo que se cargaba por
una punta no se veía por la otra.

Pantalla nueva `Prov Art Terminado/Entregas/EntregasAT_GP2.html` + RPCs
`entregas_prov_at_bundle()` y `crear_entrega_prov_at()`. **No se copió NADA de `public`** —
las tablas GP2 ya tenían todo lo necesario (`proveedor_at` 11 activos, `articulo_prov_at` 91
artículos, `entrega_prov_at` con sus 125 filas). Detalles que hay que respetar si se toca:

- **La fecha que importa es `fecha_rto`**, no `dia_mes`. `fecha_rto` es la que lee
  `v_recepcion_unificada`, o sea el checklist del sector de **Pagos**. `dia_mes` es texto
  `DD/MM/YY` y se sigue escribiendo solo para no romper lo que ya lo mira.
- **La descripción se toma del maestro** (`articulo_prov_at`), no de lo que mande la pantalla:
  si mañana cambia ahí, no quedan entregas viejas con el nombre de antes.
- La pantalla vieja **no la linkeaba nadie**, pero se dejó como **redirect** al GP2 para que un
  bookmark viejo no termine escribiendo en `public` sin que nadie se entere. El original quedó
  un tiempo al lado como `_legacy_EntregasAT.*.bak`; `[2026-09-04]` esas copias se borraron del
  árbol en la auditoría de arquitectura (están en git si hacen falta).

**Las pantallas del programa viejo también entraron en regla (2026-09-03, v1.69.0)**
`[usuario: "7014, dale"]`: el barrido de accesibilidad del 2026-09-03 había dejado afuera a
propósito las ~26 pantallas del programa anterior, que seguían con campos de 11 a 16px y
botones de 24 a 40px. Ahora están todas al piso de la casa: campos ≥18px, táctil ≥44px, y
ninguna desborda a 390px. Dos cosas que se aprendieron barriendo:

- **No alcanza con buscar selectores que nombren la etiqueta.** El primer pase miró reglas del
  tipo `input`/`select`/`textarea` y se le escaparon las que estilan el campo **por clase o
  por id** (`.search-input`, `.date-input`) y, peor, las que lo escriben **directo en el
  `style=""` del tag** (`#fechaDevolucion`, `#fechaEnvio`). Al revisar tamaños hay que mirar
  el **render**, no solo el CSS: por eso el chequeo real es abrir la pantalla a 390px y medir
  el `computedStyle`, que es lo que hace el script de verificación.
- **Subir la letra puede desbordar la página.** `Produccion/import.html` empezó a desbordar
  5px cuando los campos pasaron a 19px, porque tenía un `width: 90px` fijo. Se arregla con
  una media query a 480px, no bajando la letra otra vez.

Quedaron afuera a propósito los `_backup_*` y los `_legacy_*.bak`, que eran fotos congeladas
(`[2026-09-04]` ya no existen: se borraron en la auditoría de arquitectura).

**Hacia dónde va la carga: UN módulo de Recepciones y UNO de Entregas (2026-09-03)** `[usuario]`:
textual, *"las recepciones ya sean de prov de servicio o de insumo deberían ir en un mismo
módulo 'Recepciones Cervantes', lo mismo con las entregas"*. Es una decisión de **forma del
sistema**, no una tarea: hoy lo que entra a Cervantes vive en 5 pantallas (tallerista, PS,
Prov AT, insumos y devolución) y lo que sale en 3 (tallerista, PS, Prov AT), todas con el
mismo esqueleto `GP2EE` y distinto nombre. **Al armar una pantalla nueva de carga, tenerlo en
cuenta**: la contraparte se elige primero y la pantalla se adapta, en vez de crear otra
pantalla por contraparte. El modelo ya existe y funciona: `ControlEnvios_GP2` es el historial
unificado y distingue con `?origen=tall|ps|provat`. Ojo con dos cosas: la **base sigue
separada a propósito** (cada contraparte tiene su RPC y su tabla; lo que se unifica es la
pantalla), y **Recepción de Insumos tiene pasos que ninguna otra tiene** (pesaje de pallets,
control de cartones, cruce FIFO contra las OC abiertas) que no se pueden aplanar al mínimo
común. Anotada como idea **7225**, para hablarla antes de empezar.

**Máspoli es PROVEEDOR DE SERVICIO, no tallerista (2026-09-03, v1.73.0)** `[usuario]`:
textual, *"lo quiero empezar a tratar como un proveedor de servicio, y que ya no aparezca más
dentro de recepción de insumos de plásticos"*. **Reemplaza lo anotado el 2026-09-02** (*"sus
3 mangos se compran, van a `precio_proveedor`"*), que era el modelo de cuando figuraba como
tallerista. Le mandamos la virola **D13** (niquelada por Guazzaroni) y devuelve el mango
(**PC12**, **PEP7**, **PEP8**), cobrando el trabajo.

- **Estaba cargado TRES veces y con dos escrituras distintas**, y por eso no aparecía en las
  búsquedas: `Maspoli SRL` **sin acento** en `tallerista`, `Maspoli` en `proveedor_at` y
  **`Máspoli SRL` CON acento** en `proveedor_insumo`. Un `ilike '%aspoli%'` no encuentra
  `Máspoli`. **Al buscar una contraparte, buscar por las dos escrituras** (o por `cod_prov`,
  que acá era 2339 en las tres).
- **Máspoli NO inyecta: le agrega a la virola el mango de MADERA, y la madera la pone él**
  `[usuario 2026-09-03]`. Lo de "inyectado" lo deduje mal el mismo día, arrastrado por que sus
  3 salidas están en el Sector Plástico — pero `PEP8` se llama literalmente *"Mango Madera
  Pizza Ø9"*. El proceso es **`armado de mango`**. Que la madera la ponga él es lo que hace
  que la ruta cierre sin una entrada de madera: está adentro de la tarifa.
- **Los $683,72 pasaron de precio de material a tarifa de servicio** (`precio_servicio_pieza`). Y los 3 mangos fueron a
  `estado_compra = 'fabricacion'`: **si sólo se les sacaba el precio quedaban como "comprados
  sin precio", o sea en $0**, porque el CTE `comprado` de `v_costo_componente` mete TODO el
  sector 6. Mismo recurso que con los filtros de café.
- **Resultado: los 3 mangos y los 4 artículos (508, 518, 564, 708) suben $27,17.** Esos $27,17
  son la virola D13 que ahora sí entra al costo — antes se perdía, porque el mango era
  "comprado" y la cadena no caminaba hacia atrás. El cambio no sólo reordena: **arregla un
  costo que estaba mal**.
- Para sacarlo de las listas de tallerista se agregó **`tallerista.activo`**. No se filtró por
  "no tiene piezas configuradas", que era lo automático, porque eso también hacía desaparecer
  a **Blist-Pack** y **Tierra Nativa SA**, que son altas nuevas todavía sin rutas y tienen que
  seguir a la vista. **Corrección 2026-09-04**: Tierra Nativa SA **ya no va a la vista** —
  el usuario la sacó de tallerista (`activo=false`, ver §Tierra Nativa arriba). Blist-Pack
  sigue visible. El criterio de fondo no cambia: **quién se ve lo decide el flag, no la
  ausencia de rutas.**
- **Corrección 2026-09-08 `[usuario, textual: "a Blist-Pack quiero que lo tomemos como prov de
  servicio no como tallerista"]`: Blist-Pack pasó de tallerista a proveedor de servicio**
  (PS id 20, proceso **`blisteado`** — alta nueva en la tabla catálogo `proceso`). Hace un
  **servicio** (blister/envasado) sobre artículos terminados, no arma como un tallerista. Estaba
  casi sin cablear (0 rutas, 0 stock, 0 movimientos): sólo tenía identidad + 11 precios por pieza
  de los terminados que blistea (506 a $193,05; 557/558/654/658/659/758/759/762/763/769 a
  $147,97, ARS). La cirugía movió esos 11 de `precio_tallerista` → `precio_servicio_pieza`
  (proceso `blisteado`), repuntó la ubicación 45 (`tallerista`→`proveedor_servicio`, "Prov. Serv.
  Blist-Pack") y el alias `BLIST-PACK`, y borró el tallerista 13. **`Blist-Pack SA` (proveedor de
  insumo, cod_prov 3227, el del pliego adhesivado skin) es OTRO sombrero y no se tocó.**
  **Pendiente:** Blist-Pack (PS) **no está en ninguna ruta**, así que el costo del blisteo todavía
  NO entra en el costo de esos 11 artículos (el costo sale de la ruta); falta agregar el paso de
  blisteo a sus rutas para que se costee.

**La columna de inventario se llama MÁXIMO, no mínimo (2026-09-03)** `[usuario]`: *"quiero que
la columna de mínimo en inventario se pase a llamar máximo"*, y la razón que dio es la que
importa: **"el mínimo/máximo es lo que tendría que haber en cada ubicación/sector según la
demanda"**. O sea `inventario.minimo` (consumo mensual × `ubicacion.meses_minimo`) **no es un
piso, es el nivel objetivo**. La otra columna, la que se llamaba "Máximo", es otra cosa —
la **capacidad física** del lugar (5 cajones en crudo/procesado) — y pasó a titularse
**"Capacidad"** para que no queden dos "Máximo" y se entienda que no miden lo mismo. Es un
cambio de TÍTULO: las dos columnas de la base siguen como estaban, con sus nombres, y esto
explica de una vez el `minimo > maximo` de 77 filas que la idea 7211 dejó abierto — no es un
error, es que lo que consumís no entra en el lugar donde lo guardás.

**En el ENVÍO a un PS va una fila por PIEZA; en la ENTREGA, una por par (2026-09-03)**
`[usuario: "no tiene que aparecer 3 veces. es la misma virola"]`: lo destapó Máspoli, que
recibe una sola virola `D13` y devuelve tres mangos distintos. La pantalla de Envío mostraba
**una fila por cada salida**, o sea la misma virola tres veces. **No era sólo feo**:
`crear_envio_ps` recibe únicamente `p_comp_sc_id` — el SP no se usa para nada al enviar — así
que cargar las tres filas registraba **tres envíos de la misma virola**. Ahora la pantalla
agrupa por pieza enviada, lista las salidas al costado y **suma el sugerido** de cada una (hay
que mandar para todas); si a alguna le falta el máximo físico, el total dice "—" en vez de
quedar corto sin avisar. **En Entregas es al revés y sigue por par**: `crear_entrega_ps` sí
recibe `p_comp_sp_id`, porque al recibir hay que decir cuál de los tres mangos volvió.

**`RULETA` no va a ningún artículo y está bien (2026-09-03)** `[usuario]`: la ruta 35
(*Fleje 8 → Art* , sin artículo) termina en `RULETA` y ahí corta porque **la ruleta es para
afilar las piedras**, no es una parte de nada. No es una ruta rota: es una herramienta. Las
otras dos rutas sin `articulo_id` son la 632 (produce el pliego adhesivado, un intermedio) y
ya ninguna más — las 10 del 581 y el 104 lo recuperaron.

**El `articulo_id` de la ruta y la receta son DOS cosas, y hacen falta las dos (2026-09-03)**
`[dato]`: al 581 y a su clon 104 se les puso el `articulo_id` que les faltaba `[usuario:
"sacale el null y ponele el articulo ID, porque están continuos"]`, y **igual siguen sin pedir
nada**: tienen **0 filas en `articulo_componente`**. Es la otra cara de lo aprendido con el
pliego del 506 — el consumo se arma con la RECETA y después camina la ruta. Y la receta **no
se puede derivar de los pasos `insumo`**: en el 580, que es el hermano sano, la receta dice
`A11 + G7A + GRJ10A` mientras sus rutas entran por `A11 + EP10 + G7A`. La receta lista lo que
el artículo lleva (incluido un GRJ ya armado) y las rutas las entradas de cada cadena. **No
son lo mismo y no se deducen una de la otra.**

**HAY CODIGOS DE COMPONENTE REPETIDOS: nunca joinear por `codigo` (2026-09-03)** `[dato]` —
me mordió el mismo día. **Cuatro códigos existen dos veces**, y en los cuatro choca una pieza
del Sector Procesado con una Caja: **`A1`** (Mgo Plano 501 Pint. / Caja N°1), **`A4`** (Mgo
Plano 501 Serig / Caja N°10), **`A8`** (Cuerpo Uña CH Serigr. / Caja N°2) y **`A9`** (Cpo Mango
Alambre Corta Queso Crom. / Caja N°22). Cargando la receta del 581 hice el join por código y me
llevé **las dos filas**. **Regla: unir por `componente.id`, y si hay que resolver desde un
código, desambiguar por sector.** La numeración de cajas y la de piezas procesadas se pisan.

**Los remaches: cuál se compra crudo y cuál se compra hecho (2026-09-03)** `[usuario]`. El
patrón bueno es **`CV9` → Guazzaroni → `V9`**: se le compra el remache **crudo a Bella Vista**,
Guazzaroni lo niquela, y el niquelado queda en `estado_compra='fabricacion'` **sin precio
propio**, porque su costo es el crudo más el baño.

- **El sacacorcho va por ahí** `[usuario: "el CV11 agregalo en Bellavista y sacá el V11. El V11
  es después de mandarlo a niquelar a Guazzaroni"]`. Las rutas del **581** y del **104**
  entraban con `insumo V11` directo, o sea el remache se compraba ya niquelado **y el niquelado
  no se pagaba**. Corregido al patrón CV9/V9: el V11 pasa de $28,66 a $30,57.
- **El canelón NO** `[usuario: "el CV10 eliminalo porque el que se compra es el V10, remache
  aluminio canelón"]`. Ese se compra ya hecho: `CV10` era un alta de más y se dio de baja.
  **No todos los `CVxx` existen: sólo los que efectivamente se mandan a niquelar.**
- Al pasar `V11` a niquelado entra a la lista de piezas de Guazzaroni con la tarifa en `NULL`,
  igual que TODAS las suyas: hueco conocido, queda marcado y no inventado.

**Un GRJ armado reemplaza a sus componentes en la receta, no se suma (2026-09-03)** `[usuario:
"GRJ1 se usa para el quinientos"]`: la receta del **500** tenía `C1 + C10 + V9` sueltos, que son
**exactamente el BOM del `GRJ1`**. Se reemplazaron por el GRJ1, igual que el **506** lleva
`GRJ7` en vez de `A10 + C10 + V9`. **Si se dejan los dos, el armado se cuenta dos veces.** El
costo del 500 no se movió ni un peso, que es la prueba de que el reemplazo era exacto. La
receta quedó `A11 + GRJ1 + Pliego Ad 500`, calcada del 506.

**La receta del 581 y del 104 (2026-09-03)** `[usuario, con la pantalla a la vista: "por ahora
mandale así"]`: **Caja N°22 (1/12) + su cartón + `D1` Espiral Sacacorcho + `PB8A` Mgo Sacac
Plast + `V11` Remache Sacacorcho**, todos ×1 salvo la caja. En la receta va el remache
**niquelado** (`V11`), que es lo que el artículo lleva; el crudo `CV11` y el baño son pasos de
la ruta. Los dos tenían rutas y Est Madre pero **cero receta**, así que no pedían nada. Ahora
piden 7 partes cada uno (581: 2.532 uni/mes · 104: 3.162). **De paso se corrigió un error del
clonado del 2026-09-02**: las rutas del 104 entraban con `CCE2B`, que es el **Cartón 581**. El
104 lleva su propio cartón, `K5D`, que no existía en GP2 y se dio de alta **sin precio** — por
eso su costo baja a $672,86 y queda con `faltan_precios: 1`.

**EL PLIEGO NUNCA VA CON CANTIDAD 1 EN LA RECETA (2026-09-03)** `[usuario]`: textual, *"en el
BOM no pongas un pliego por artículo, sino que cada pliego se usa para varios artículos"*. **El
rinde sale de `componente.carton_formato`** y el precio lo confirma, que es la forma rápida de
chequear que un pliego está bien cargado:

| formato | posiciones | precio unitario |
|---|---|---|
| `C` | 12 | $89 |
| `LOKE` | 16 | $66,75 |
| `Huevo` | 25 | $42,72 |
| `8` | 30 | $35,60 |
| `Pliego` (ex-Bombilla) | **16** | skin $915 el pliego |

En la receta va **`1/posiciones`**. **Los 12 artículos que llevan pliego quedaron uniformes el
2026-09-03** `[usuario: "los pliegos de bombilla todos, el 557 al 769 vienen de dieciséis. Y el
pliego del 506 y el 500 vienen de doce"]`: **500 y 506 a 1/12** ($917 el pliego → $76,42 por
artículo) y los **diez de bombilla a 1/16** ($915 → $57,19). El `Pliego Ad 500` estaba con
precio $89 y cantidad 1, o sea con el precio POR POSICIÓN: pasó al pliego entero, como todos.
Eso cierra la idea 6116.

**Y ojo con el número: los de bombilla son 16, no 25.** Lo tenía anotado mal en dos lados y
cargué 1/25 antes de que el usuario me corrigiera. La pista estaba: la idea 7223 marcaba que en
el 557/558 la **receta** decía 1/25 y la **ruta** 1/16 — **tenía razón la ruta**. Cuando receta y
ruta no coinciden, mirar cuál de las dos se cargó con el dato del usuario.

**Copiar un precio "de un gemelo" es copiar del MISMO FORMATO (2026-09-03)** `[dato]` — me
equivoqué el mismo día. Al `C1B` (Cartón 574) le puse $89 porque era el precio más repetido de
los cartones, pero **C1B es formato `Huevo`**, o sea 25 posiciones, y ese formato vale **$42,72**;
los $89 son del formato `C`. El gemelo del que hay que copiar es uno de su misma columna de la
tabla de arriba, no cualquiera. En cambio el `K5D` (Cartón 104) **sí** iba a $89, porque su
gemelo exacto es el Cartón 581, que es formato C.

**Los códigos duplicados NO se renumeran (2026-09-03)** `[usuario: "los componentes que te mandé
son los que ya existen, no los dupliques"]`: los cuatro pares `A1`, `A4`, `A8` y `A9` (una pieza
de Procesado y una Caja en cada uno) **se quedan como están**. Lo que hay que hacer es
**desambiguar por sector** cada vez que se resuelva un componente desde su código — y mejor,
unir por `componente.id`.

**Un insumo se paga UNA vez, aunque el artículo tenga varias rutas (2026-09-03)** `[usuario:
"uno u otro, no x2 de costo"]` — es la misma regla que se aplicó a los talleristas a la mañana,
y el CTE **`insumox`** tenía el mismo agujero: sumaba una vez **por cada ruta**, así que un
artículo con dos rutas alternativas (el mismo trabajo hecho por dos talleristas) **pagaba sus
insumos dos veces**. Eran **16 casos en 6 artículos**, y no era poca plata:

| Artículo | Antes | Ahora | |
|---|---|---|---|
| **609** | $1.198,35 | $725,28 | −$473,07 |
| **315** | $867,57 | $559,89 | −$307,68 |
| **505** | $514,32 | $358,36 | −$155,96 |
| **500** | $557,31 | $441,82 | −$115,49 |
| **510** | $334,22 | $231,31 | −$102,91 |

**~$1.155 que se estaban cobrando de más.** Ahora `insumox` arma una fila por (artículo, insumo)
tomando la cantidad mayor, igual que `talx` toma la tarifa más cara. **Regla general: cuando dos
rutas alternativas describen el mismo trabajo, todo lo que comparten se cuenta una sola vez** —
el insumo, el armado del tallerista, el servicio. Si aparece otro CTE que sume por ruta, tiene
el mismo bug.

**CADA ARTICULO LLEVA UN CARTON O UN PLIEGO — uno, y sólo uno (2026-09-03)** `[usuario]`:
textual, *"chequea que cada artículo tenga un cartón o pliego. No estaría bien que alguno no
tenga o tenga cartón + pliego"*. **Es una regla de integridad y hoy se cumple**: de los 99
artículos, **ninguno lleva los dos** y todos llevan uno, con una sola excepción — el **071**,
que **va sin cartón a propósito** `[usuario 2026-09-03: "al 071 no le hagas cartón"]`. O sea que
la regla es "uno o ninguno, nunca los dos": si un artículo no lleva cartón ni pliego **no hay que
inventarle uno**, hay que preguntar.

El chequeo hay que hacerlo **por receta Y por ruta**, porque son dos cosas distintas (la receta
manda el consumo, la ruta manda el costo) y pueden no coincidir. Así apareció el **516**: tenía
el cartón `L4B1` en la receta pero **ninguna ruta lo declaraba**, o sea el consumo lo pedía y el
costo no lo pagaba. La causa era que la ruta 323 (*Insumo CART516 → Art 516*) **existía sin su
paso 1**, el que declara el cartón: arrancaba directo en el paso del tallerista, mientras sus
hermanas sí lo tenían. Se buscó el patrón en todo el proyecto y **era la única ruta con ese
agujero**. Corregida, el 516 sube $89.

La consulta que lo verifica, por si hay que repetirla: contar los componentes del Sector Cartón
que cada artículo declara en `articulo_componente` y en `ruta_paso` (pasos `insumo`/`ingreso`),
y pedir que las dos cuentas den **exactamente 1**.

**El nombre que se ve NO es la llave del proceso (2026-09-03)** `[usuario]` — pidió prolijidad en
Envío/Entrega a Proveedores de Servicio: *"el de AJ, que en realidad es AJ Adhesivos nomás sin la
barra, y el de Máspoli, que dice armado de mango. No tiene mayúscula ninguno de los dos... y en
vez de armado de mango, armado mango"*. Quedaron **`AJ Adhesivos · Adhesivado`** y **`Maspoli SRL
· Armado Mango`**. Lo importante para la próxima vez: hay **dos lugares** con el proceso y no son
lo mismo —

- **`proveedor_servicio.nombre` y `.proceso`** = el **rótulo** que muestra la pantalla. Texto
  libre, va en mayúscula y como lo quiera leer el usuario.
- **`GP2.proceso`** = el **catálogo canónico**, en minúscula, con FK desde
  `precio_servicio_pieza.proceso` y usado para cruzar con `tarifa_servicio`. **Ese no se toca por
  una cuestión de estética**: cambiarlo rompe el FK (lo probé y la base lo rechazó, bien hecho).

**Blist-Pack es el 3227** `[usuario 2026-09-03]`. Era el único tallerista sin `cod_prov`, y por eso
en Envíos/Entregas a talleristas aparecía sin código mientras los demás sí lo mostraban.

**EL CLAVO 505 NO SE CUENTA: VIENE EN CAJAS Y SE PESA (2026-09-03)** `[usuario]` — *"que tire por
default kg y borra unidades en el caso de Trefilados Industriales Clavo 505"* y *"en el caso del
control de este componente que me deje poner cant de cajas y kg por caja"*. Es **un dato del
componente con dos consecuencias**, y quedó como tal: la columna nueva
**`componente.recibe_en_cajas`** (hoy sólo el `PCP3`, el único insumo de Trefilados).

- **Recepción**: se carga siempre en **kg** y **no se muestra el toggle Kg/Unidades** — el mismo
  criterio que ya valía para los flejes: si la casa sabe la unidad, el toggle sólo se presta a
  equivocarse.
- **Control**: aparecen **Cajas** y **Kg por caja**, que multiplican y completan los kg
  controlados (el campo de kg sigue mandando: se puede escribir a mano).

**Lo que NO se tocó, y es importante: `componente.unidad_medida` sigue en `unidad`.** El stock
del plástico vive en **unidades** (hoy 153.859 uni de clavo) y el trigger del movimiento convierte
los kg del remito con `kg_x_uni` (0,00653 kg cada clavo). Cambiar la UM canónica para que la
pantalla arranque en kg habría roto esa conversión: **la unidad del REMITO y la unidad del STOCK
son dos cosas distintas**.

**LA UNIDAD DEL REMITO NO ES LA DEL STOCK, Y CADA RUBRO TIENE LA SUYA (2026-09-03)** `[usuario]`
— *"en recepción de bombillas que tire por default unidades (que no aparezca kg) y que en el
control ponga kg y me haga el pasaje a unidades con el kg por uni"*. Bombillas y remaches son el
mismo caso y ahora se comportan igual: **se reciben CONTANDO unidades** (sin toggle: el kg no
aparece) y el **stock del sector vive en unidades**. El **control es por peso** (se pesa la
caja), así que ahí el operario ve las dos caras: los kg que pesó y **a cuántas unidades
equivalen**, contra las declaradas.

> **Corregido el mismo día — ver § 4f.** Acá decía que "el movimiento viaja en kg cuando el
> componente tiene `kg_x_uni`". Ya no: esos remitos se **guardan en unidades**. El paso por kg
> era un rodeo (la unidad canónica del inventario de esos sectores ya es `unidad`, así que el
> trigger lo volvía a dividir) y encima dejaba sin poder recibirse a los componentes sin
> `kg_x_uni`. Lo que sigue valiendo tal cual es lo de arriba: **la unidad del remito y la del
> stock son cosas distintas**, y el clavo, que se pesa, se sigue guardando en kg.

La regla general que queda, y que ya se aplicó a flejes, cartones, remaches, bombillas y al clavo:
**si la casa sabe en qué unidad viene el remito de ese insumo, el toggle Kg/Unidades no se
muestra.** El toggle sólo sirve donde de verdad puede venir de las dos formas; en todo lo demás es
una invitación a equivocarse.

**PUSHEAR A LA RAMA ADEMÁS DE A MAIN GASTA EL DOBLE DE DEPLOYS (2026-09-03)** `[dato]` — el
usuario avisó que no veía los cambios en `gesti-n-productiva-2-0.vercel.app`: producción estaba
clavada en un commit viejo y **los dos últimos no habían generado ninguna fila** en Vercel. La
lista de Deployments lo explicaba: cada commit aparecía **dos veces** — un *Preview* por la rama
`claude/...` y un *Production* por `main`. El plan es **Hobby**, con tope diario de deploys, y a
doble consumo se agota a la mitad de camino; cuando se agota, Vercel simplemente **deja de tomar
los pushes**, sin error visible en el proyecto.

**La regla: se pushea SOLO a `main`** (que ya era la regla de la casa por otro motivo). Si la
sesión viene con una rama asignada, `git push origin HEAD:main` y nada más — no pushear también la
rama. Y del lado de Vercel conviene dejar los Preview Deployments limitados a `main`.

Para diagnosticarlo rápido la próxima vez: abrir **`/version.js` directo en el navegador**. Si el
archivo servido tiene una versión vieja, el problema es el deploy y no la caché del celular.

## 3c-bis. Accesibilidad de carga: letra grande + teclado numérico (2026-08-30)

`[usuario 2026-08-30]` Dicho textual: *"Siempre quiero letras bien grandes y legibles
para que alguien que ve mal pueda escribir y no equivocarse. Donde van números, solo
teclado numérico."* Y la aclaración: *"la letra grande no tiene que romper la visual...
UX/UI súper prolija"*. La regla operativa completa vive en `CLAUDE.md` (sección
"Campos de carga"); acá lo importante del negocio: **hay gente del depósito que ve mal
y carga datos igual** — cualquier pantalla nueva se diseña para esa persona. Piso de
18px en `gp2-modulo.css`, `inputmode` en todo campo numérico (51 arreglados de una),
y el guard `test_teclado_numerico.js` para que no vuelva a pasar.

## 3c-ter. La tara del pallet se aprende sola (2026-08-30)

`[usuario 2026-08-30]` *"Una vez que empecemos a tener datos de carga de cuánto pesa
cada pallet, vamos a poder ir asumiéndolo para calcular mejor, no solamente tomando el
dato de 4 kilos."* Implementado en la BD (regla: el motor vive en la base):
`v_tara_pallet_real` saca la tara verdadera de cada pesaje guardado (balanza − suma de
rollos) y `recepcion_tara()` la promedia — por proveedor primero (n≥5), global después
(n≥5), filtrando taras fuera de 1–15 kg. El auto-cálculo del kg por rollo la usa en ese
orden y recién sin datos cae al punto medio del parámetro 4–8. No hay nada que
mantener a mano: cada pesaje que se guarda mejora el próximo cálculo.

## 2c-vicies. "Fábrica" no cobra tarifa: va por tiempo de matriz (2026-09-02)

`[usuario 2026-09-02]` *"hay que fijarse el tiempo de las matrices para el armado y
envasado y calcularlas a $2 por segundo"*.

**Fábrica es la única contraparte interna**, y por eso **no lleva `precio_tallerista`**: su
costo sale de los **tiempos de matriz × `costo_segundo_pesos`** (hoy **$2**). Ya funciona
así — sus 8 artículos tienen la mano de obra calculada y `faltan_tiempos = 0`:

| Artículos | Segundos | Mano de obra |
|---|---|---|
| 507 / 707 | 34,27 | $68,54 |
| 542 / 543 / 720 / 722 | 23,60 | $47,20 |
| 570 / 858 | 43,21 | $86,42 |

**Sus 8 filas "sin tarifa de tallerista" NO son deuda** — igual que las 3 de Máspoli, que
van por precio de material. Al contar cuánto falta de la idea 6117, estas 11 no cuentan.

**Lo que sí falta es tiempo en las matrices.** De las **115 matrices, 18 que están en uso
tienen `tiempo_historico` en 0 o null**, así que ese trabajo se hace y no se cobra. Las
más caras por cantidad de rutas: **69** Doblado Resorte (6 rutas), **182** Estampado Flecha
de Ahueca, **360** Corte Ahueca, **361** Corte Flechita Ahueca y **64** Corte Pinza Fiambre
(4 cada una). Cuatro de ellas caen justo en las cadenas de Fábrica. Ver idea **7213**.

## 2c-novodecies. Filtros de café: el alambre NO es el filtro (2026-09-02)

`[usuario 2026-09-02]` *"cuando entrega charcas va a IF90 y de ahí va a ijupa que después
entrega en virgilio"*. La cadena real de los artículos **031** y **034**:

```
IC3 (Fleje 90) → Resortes Charcas CORTA → IF90 (alambre cortado)
               → IJUPA ARMA → 031 (filtro terminado) → Virgilio
```

**Lo que había estaba mal en dos lugares**: el paso de Charcas devolvía `IC3` (o sea no
producía nada) y era **IJUPA** quien "producía" `IF90`. Con eso el **alambre ocupaba el
lugar del terminado** y el artículo 031 se quedaba sin componente propio.

**De dónde salió el error, que es la parte que conviene recordar:** la migración que creó
el alambre el 2026-09-02 **reusó el componente 372, que era "31 Terminado"**, y lo renombró
a F90 → IF90. Renombrar un componente existente en vez de crear uno nuevo **le robó la
identidad al terminado**. Si una pieza nueva aparece en la cadena, se crea; no se recicla
la que ya estaba ocupando otro rol.

Se recuperaron los componentes `031` y `034` (sector 12, como sus gemelos Chef 836 y 867),
se reescribieron los 4 pasos de las rutas de fleje y los 8 de las rutas de insumo, y la
tarifa de IJUPA se mudó del alambre al terminado.

**El alambre lleva `estado_compra = 'fabricacion'`**, igual que D9 y V9. Sin eso, al vivir
en sector 5 (Fleje) el motor lo tomaba por comprado, **cortaba la cadena de material** y el
filtro quedaba con material en 0. Es la misma regla de siempre: **una pieza intermedia que
sale de un proceso propio no es "comprada", aunque viva en un sector de insumo.**

**La prueba de que quedó bien**: 031 = **$333,02** y 034 = **$362,00**, *exactamente* los
mismos números que sus gemelos Chef 836 y 867, que llegan por otro camino. Cuando dos
gemelos LK/Chef dan igual, la cadena cierra.

Fleco menor: 031/034 y el alambre quedan con `faltan_precios = 1` mientras los gemelos
tienen 0, aunque el costo total da idéntico. No cambia ningún número; hay que mirarlo.

## 2c-sexdecies. Hay talleristas que cobran POR KILO (2026-09-02)

`[usuario 2026-09-02]` Sobre el $775,01 de la Cuchilla Pelapapa Cerrada en el Excel de
Martin: *"es x Kg"*. **No todas las tarifas de tallerista son por unidad.**

Eso era una trampa cara: `precio_tallerista` sólo tenía `precio_uni`, así que cargar ese
número tal cual habría multiplicado el costo de esa pieza **por 200**. Un número que parece
absurdo al lado de sus vecinos (775 contra 8,99) casi siempre es **otra unidad**, no un
error de tipeo — vale la pena frenar y preguntar.

- Se agregó **`precio_tallerista.precio_kg`**, igual que ya lo tenía `precio_servicio_pieza`.
- El trigger **`trg_precio_tallerista_kg`** calcula solo `precio_uni = precio_kg ×
  componente.kg_x_uni`, que es lo que lee `v_costo_componente` (la vista suma `precio_uni`,
  no sabe de kilos). Si la pieza no tiene `kg_x_uni`, la carga **falla con un mensaje
  claro** en vez de guardar un costo en cero.
- Ejemplo cargado: **X4** a $775,01/kg × 0,00492 kg = **$3,81 por unidad**.
- **Ojo**: si después cambia el `kg_x_uni` de la pieza, el `precio_uni` guardado queda
  viejo. Hay que volver a tocar la fila (un `UPDATE precio_kg = precio_kg` alcanza, el
  trigger recalcula).

En el mismo Excel hay otras dos líneas por kilo. **Puntas 523 Afilado ($4.830) ya no se
hace más** `[usuario 2026-09-02]` — línea muerta, no se carga. Queda sólo *Puntas 520
Afilado (KG)* $3.361,18, que todavía no se puede cargar porque no está claro sobre qué
componente de GP2 cae.

## 2c-septdecies. El Excel de costos arrastra quién hacía el trabajo ANTES (2026-09-02)

El bloque de un tallerista en `A Costos VIGENTES` **no es la lista de lo que hace hoy**:
tiene renglones de trabajos que ya se mudaron a otro. En el de Martin aparecían cuatro que
GP2 tenía en otro lado, y el usuario confirmó que **GP2 está bien y el Excel viejo**
`[usuario 2026-09-02: "todos esos ahora es pettofrezza y fabrica, ya no martin"]`:

| Línea del Excel de Martin | Precio | Quién lo hace hoy |
|---|---|---|
| 523 Sacacorcho Doble Aleta AyE | $44,81 | **Pettofrezza** |
| 551 Cuchillo Untar x 2 Plast AyE | $61,17 | **Pettofrezza** |
| 507-707 Rompenueces AyE | $45,43 | **Fábrica** |
| 570 Pala Canelones AyE | $84,77 | **Fábrica** |

También caen ahí **57 Destapacorona** ($49,35, hoy de **Danica**) y **546 Cortaqueso**
($110, hoy de **Lucho**).

**Regla al cargar tarifas desde ese Excel:** el bloque dice el precio, pero **quién hace la
pieza lo dice GP2**. Si no coinciden, se frena y se pregunta — no se carga la tarifa a
nombre del que figura en la hoja. Y **esos precios no se trasladan solos al nuevo
tallerista**: cada uno cobra lo suyo, así que hay que buscarlos en el bloque propio de
Pettofrezza y de Fábrica.

## 2c-octodecies. Artículo 104 (Sac Ergo LOKE) = clon del 581 (2026-09-02)

`[usuario 2026-09-02]` *"104 es igual con mismos componentes que 581"*. En el Excel los dos
comparten un solo renglón — *"581/104 Sac. Cabo Plástico AyE $60,35"* — y en el vecino son
**104 = Sac Ergo LOKE** y **581 = Sac Plast LK**.

GP2 no tenía el 104. Se clonó el 581 tal cual: componente terminado (sector 12), artículo
(familia Sacacorchos, 12 por caja A9) y **las 5 rutas** — `D1 + PB8A + V11 + CCE2B + A9 a
1/12`, todas armadas por Martin y entregadas a Virgilio — más la tarifa de $60,35. Quedó
con el **mismo costo que el 581: $759,95**, sin precios faltantes.

**Detalle que hay que saber para clonar rutas:** `GP2.ruta.articulo_id` **viene en NULL** en
estas rutas. La convención de la casa es identificarlas por el **nombre** (`Insumo X -> Art
N`) y por sus pasos, no por esa FK. Un clon filtrado por `articulo_id` no copia nada.

## 2c. Costos y valorización: el motor de precios (2026-08-30)

`[usuario 2026-08-30]` Dicho textual: *"Quiero que yo te suba los precios de los insumos
y en función de ese precio me calcules cuánto vale mi stock y cuánto es lo que me genera
pedido para llenar al máximo. Para empezar considerá que todo vale un dólar. Los costos
del sector crudo: si lleva el fleje que vale un dólar el kilo, cotizalo a valor de
cuántos gramos pesa la pieza; y agregale un aporte por mano de obra a razón de DOS PESOS
POR SEGUNDO de demora por matriz. En sector procesado, si lleva pintado, agregale el
costo del pintado. Por ahora todos los precios un dólar para regular... después paso los
precios reales y cambiamos todo; la lógica es la misma."*

Y el remarque: *"si para que una parte llegue a sector crudo necesita que se ejecuten
dos matrices, hay que sumar los tiempos de las dos."*

**Los precios de hoy son de REGULACIÓN, no reales**: todo insumo comprado vale 1 USD
(flejes POR KG, el resto por unidad) y las cajas $ 1.000 ARS fijos (`[usuario]`: *"inventale
un valor, prefiero que sea un valor fijo para todos, cosa que pueda chequear"* — las
listas de cajas vienen en pesos). Los placeholder están marcados
`PLACEHOLDER 1 USD (regulacion)` / `PLACEHOLDER $1000 (regulacion)` en
`precio_proveedor.producto` y `precio_servicio.origen` para pisarlos limpio con las
listas reales sin tocar precios verdaderos. Lo ÚNICO real desde el día uno: la mano de
obra **$ 2 por segundo de matriz** (`parametro.costo_segundo_pesos`) `[usuario]` y el
**dólar oficial del cron** (`parametro.tipo_cambio_usd_pesos` + historia en
`GP2.tipo_cambio`, lo mantiene pg_cron desde dolarapi.com — NO tocarlos a mano).

**Monedas SIEMPRE separadas** `[usuario]`: material y servicios en US$, mano de obra (y
cajas) en $. Las pantallas muestran "US$ X + $ Y" y ADEMÁS el combinado en pesos usando
el dólar del cron — nunca un tipo de cambio inventado.

### La lógica de costos por sector (para la unificación futura)

`[usuario 2026-08-30]` **Objetivo final: esto se unifica con otro repo de costos; el
costo del ARTÍCULO tiene que surgir de sus componentes considerando la producción
completa.** La cascada, sector por sector (motor: `v_costo_componente` +
`v_valor_stock` / `v_valor_pedido`, RPC `valorizacion_bundle`):

1. **Fleje (5)**: vale su precio POR KG (`precio_proveedor`). Su stock está en kg, así
   que valor stock = kg × precio directo.
2. **Insumo comprado (plástico 6, bombilla 7, remache 8, cartón 10, caja 11)**: vale su
   precio por unidad. USD → columna dólares; ARS → columna pesos. Los marcados
   `estado_compra` fabricacion/discontinuo NO llevan precio de compra: se costean por
   su ruta (los resortes fabricados) o quedan en cero con aviso (discontinuos).
3. **Crudo (1) y tránsito (3)**: material = precio_kg del fleje × kg de la pieza
   (el `kg_x_uni` más cercano al corte; si la cadena no tiene kg cargado, cae a
   1/`partes_por_kilo_de_fleje` de la matriz de corte, que incluye scrap) + mano de
   obra = Σ `tiempo_historico` de TODAS las matrices de la cadena × $/seg (dos matrices
   = se suman las dos; verificado K5: 1,2+1,8+1,8 = 4,8 s → $ 9,60).
4. **Procesado (2)**: costo del componente de entrada + el precio del servicio del PS
   (`precio_servicio` por pieza: pintado, cromado, niquelado, temple...). Un servicio
   sobre la misma pieza (temple FAAT L13→L13) también suma.
5. **Armados con convergencia** (H11 = varilla H7 + cuchilla I16): las ramas SUMAN
   (material de cada fleje + su cadena). Rutas alternativas del mismo fleje (G7 se
   registró con y sin el paso de aplastado M77) NO duplican: la mano de obra se
   deduplica por matriz y el corte se cuenta una vez.
6. **GRJ / BOM (`componente_bom`)**: los hijos comprados no-fleje (remaches, bombillas)
   suman × cantidad encima de lo que trae la ruta.
7. **Terminado (12)**: queda AFUERA de la valorización de stock (el costo del artículo
   final es la unificación futura: receta `articulo_componente` + `componente_bom` ×
   costo de cada componente, más los pasos propios).

**Valor de stock** = stock × costo, por componente y ubicación. **MÁXIMO POR SECTOR** =
Σ por ubicación de greatest(0, máximo − stock) × costo. `[usuario 2026-08-31]` **Se llama
así: "máximo por sector"** — NO "tope" ni "pedido a máximo". Y suma **todo el circuito**
(sector propio + talleristas + Virgilio), no solo lo propio: de los $678 M, $476 M son del
sector propio, $114 M Virgilio y $89 M talleristas.

### Semántica verificada y trampas

- `[dato 2026-08-30: public.db_n8n_espejo]` **`matriz.tiempo_historico` = SEGUNDOS POR
  PIEZA** (no por golpe): en el espejo, `Segundos_Historico = Uni × Tiempo_Historico`
  EXACTO en todas las filas revisadas, y `Segundos_Trabajados` (reloj real) da la misma
  magnitud. GP2.matriz coincide 100% con `public."Matrices"`.
- `[dato]` **`matriz.uni_x_golpe` está vacío** (113 en 0 y 2 en null) — pero **no es un
  campo inútil: es el que falta para leer bien los tiempos**. Ver §2c-quater (golpe ≠ unidad).
- `[dato]` **N1/N2 (Ahuecafruta/Ahuecapapa) tienen DOS matrices de soldado** para el
  mismo armado (183 genérica + 362/363 específica): el motor suma ambas (~$ 21 de más
  si en realidad es una sola). Si es data duplicada del vecino, corregir las rutas.
- `[dato]` **GRJ10/GRJ10A: los flejes E4/E5 entran DIRECTO al armado** (sin matriz de
  corte), así que no hay forma de repartir el kg entre los dos flejes: cada uno toma el
  kg total del GRJ (sobreconta material). Sector en vaciamiento; se corrige cargando
  kg reales por hijo cuando importe.
- `[dato]` El precio vigente de un componente = la fila más nueva de `precio_proveedor`
  por `fecha_lista` (después por id). **La OC guarda la foto histórica del precio al
  crearla** (`orden_compra_item.precio_uni/moneda` via `crear_oc`): si el precio cambia
  después, la OC vieja no se mueve.

## 2c-bis. Precios REALES cargados (2026-08-31): quién pasa lista, en qué moneda y unidad

Fuente: `Copia_de_A_Costos_VIGENTES.xlsx`, hoja "Lista de Precios " (bloques por
proveedor; col E = Cod ISIS, col G = último $ del proveedor, col I = fecha de lista).
`[usuario]` **Todos los precios son SIN IVA.** 98 placeholders de regulación pisados en
`precio_proveedor` + tabla nueva `GP2.precio_servicio_pieza` (85 precios de servicio
exactos por pieza; la vista de costos usa el exacto y cae al plano si no hay).

### Quién cotiza cómo (aprendido del archivo)

- **Flejes → USD POR KG.** `[dato]` Basconia (lista vieja, ago-2025), Aperam inox
  (jun-26), Hermac (jul-26), Brawin redondos (may-26), Szapiro, JL Metales (aluminio
  ganchito, caro: 10,50), Altrak (alambre galvanizado 1,715). **El matcheo es por
  `fleje_detalle.cod_isis`**, nunca por descripción. Un mismo isis puede estar en dos
  listas (0455 cuchilla abrelata: Basconia 3,60 vs Hermac 6,27) — gana el de
  `componente.proveedor`.
- **Tratamientos → PESOS POR KG** `[dato, verificado exacto contra la hoja Tratamientos]`:
  Pedernera cromado (46 precios distintos por pieza, $1.084–20.192/kg — pieza chica =
  kg más caro; su lista trae los GRAMOS de cada pieza en la col "Cod Art"), FAAT
  temple/cementado ($3.084–3.336/kg), Guazzaroni niquelado $2.606 / zincado y pulido
  $1.172, New Metal temple $5.500 (más caro que FAAT), Industermic zincado $671 (LA
  MITAD que Guazzaroni), MABRA pavonado $1.300 (vs Industermic $1.880). En
  `precio_servicio_pieza` están convertidos a $/pieza (kg de lista o `kg_x_uni` GP2).
- **Pintado y serigrafía → PESOS POR PIEZA** `[dato]`: Jade $127–305 (jul-26),
  Rec Color $203–225 (sep-26, más caro que Jade), Ximpa serigrafía $18–24.
  **Daniel (pintor) NO tiene lista en el archivo.**
- **Remaches Barres Daniel (Bella Vista) → PESOS POR UNIDAD** (jul-26), del remache
  CRUDO. `[usuario]` **Guazzaroni los niquela** → los V* niquelados pasaron a
  `estado_compra='fabricacion'` (cuestan CV* crudo + niquelado; la OC compra el crudo).
  Excepciones compradas niqueladas: **V13 ojal de Mandelli** y V20 (ver trampas).
- **Cajas → Corrugadora del Plata, PESOS POR UNIDAD** (jul-26). `[usuario]` **"del
  Plata" y "del Sur" son EL MISMO proveedor** (siempre se confundieron los nombres).
  **Recicor cotiza las mismas 9 cajas ~19% más barato** (ago-26) — cargadas como
  referencia sin vincular, la vigente es del Plata por decisión del usuario.
- **Plásticos: la lista de Pat Bet Plast es INYECCIÓN SOLA, SIN material** `[dato:
  hoja Plasticos]`. El precio real de la pieza = pellet × gramos (+4% desperdicio) +
  inyección — está calculado en la hoja "Plasticos" col "Total Mat e Inyeccion", y ESO
  es lo cargado `[usuario: "las dos"]`. Pellets ("la bolsa plástica") cargados aparte
  sin vincular, $/kg de los 3 proveedores activos: `[dato]` conviene partido —
  **Santa Rosa gana en PP/PS/AI** (cotiza en pesos: PP $3.065 ≈ US$2,00),
  **Indarnyl en nylon y ABS**, **Beta sólo en PE**.
- **Pliego adhesivado (skin) → Blist-Pack SA (3227), PESOS POR PLIEGO** (ago-26): las
  notas "12 bocas"/"20 bocas" de su lista indican posiciones por pliego. Skin Bombilla
  $147,97 (25 posiciones `[usuario]`, cargado en PLIEGO557/558). No confundir con el
  ENVASADO de Gentile/Oscar ($69/uni, `precio_tallerista`).
- **Cartones Grafica Pol: el precio va POR FORMATO de cartón, NO por familia de
  artículo** `[usuario, corrigiendo la primera propuesta]`: hay formatos baratos (8 =
  skin uña $64,75; huevo $48; corbata ocho $43) y caros (Medida B Chef $106,67;
  extractor $238). La hoja " Cartones" tiene el mapeo artículo→tipo (col A/C, ojo:
  numeración Loeke 1-18 y Chef 19-36 SE PISAN, desambigua la zona de filas). Pendiente
  de validar y cargar (85 placeholders).

### Decisiones tomadas con el usuario (2026-08-31)

- **Cremallera → importada vía Tierra Nativa, código 523C, USD 1,10/u** (ene-26).
  Cargada en E13 (entra como insumo de armado del 523/723, no la toca el ×kg de
  flejes). **CV17 (cremallera p/niquelar de Barres) → discontinuo.**
- **V18C Vástago Alu → discontinuo** ("el remache de aluminio no va más").
- **Skin 500 → discontinuo** ("ya no van más"). **CORRECCIÓN 2026-08-31: el Skin 506 SÍ va**
  `[usuario]` — ver §2c-septies. Quedó como discontinuo por esta línea y se revivió.
- **Mandelli cotiza el ojal POR MILLAR** ($15.366,73 = $15,37/u) `[usuario confirmó]`.
- **Charcas sobre el Fleje 90 = CORTE de alambre para FILTROS DE CAFÉ, $9,50/u**
  `[dato: las 5 rutas de C3+Charcas terminan en 031/034/120/836/867]` — NO es el
  resorte de $110 (esos eran EP10/LLF8, resortes de batidores).
- **El tocho de afiladores = 90 arandelas enroscadas en un tornillo largo** `[usuario]`.
  Scorrano rectifica el tocho entero: $1.406 POR TOCHO (cargado así; el stock de
  J1/E4 se cuenta en tochos, 60 por cajón).

### Trampas nuevas (nos mordieron o casi)

- **El motor de costos camina rutas SIN CANTIDADES**: en un armado N→1 (90 arandelas →
  1 tocho; 25 posiciones → 1 pliego; los kg de GRJ ya anotados) cuenta UN hijo. Hoy el
  tocho E4 vale ~$1.454 cuando el real es ~$5.700 — impacto chico (6 tochos en stock)
  pero ES EL pendiente estructural: cantidad por paso en `ruta_paso`. `[deducido, medido]`
- **Kollplast vs Pat Bet, misma pieza, otro precio**: Pirolo $51,76 vs $20,07 (×2,5),
  Buje $20,48 vs $21,06. Todo quedó cargado con Pat Bet (así está `componente.proveedor`);
  revisar al repartir los inyectores. `[dato]`
- **A9 (mango alambre corta queso): la lista de Pedernera dice 21 g, GP2 tiene 39 g** —
  el precio exacto usa los gramos de la lista. `[dato, sin resolver]`
- **La lista de un proveedor puede seguir mostrando lo que ya no se le compra**: Pat Bet
  lista el cilindro PB1 (discontinuado), Suipacha el tornillo cortaqueso (¿importado?),
  Barres la cremallera. La lista dice qué VENDE, no qué le COMPRAMOS.
- **Fechas de lista MUY dispares** (Basconia ago-25 vs Aperam jun-26): el "precio
  vigente" puede tener un año. La fecha real quedó en `fecha_lista` de cada fila.

### REGLA DE ORO del costeo (2026-08-31, dicho textual del usuario)

`[usuario]` *"Yo quiero que registres el peso del clavo y cuánto vale el niquelaje:
si el día de mañana cambia, no vas a cambiar el precio del clavo, vas a cambiar el
precio del niquelaje. Lo mismo en los demás rubros."* Y la macro: *"poder valorizar
mi stock en cada punto de su estadío al valor actual"* — cada posición = cantidad ×
costo del estadío, armado EN VIVO.

**El peso vive en el componente (`kg_x_uni`), la tarifa vive en el proveedor, el
costo se CALCULA — nunca se guarda cocinado.** Implementado:
- `precio_proveedor.precio_por_kg` (bool): el precio es $/kg y la vista lo multiplica
  por el peso vivo. Primer caso: PCP3 clavo = Altrak USD 3,30/kg × 6,53 g.
- `precio_servicio_pieza.precio_kg` + `proceso`: tarifas $/kg por proceso (Guazzaroni
  niquelado $2.606 / zincado y pulido $1.172, FAAT temple $3.336 / cementado $3.084,
  MABRA pavonado $1.300, Pedernera cromado: tarifa propia por pieza) × peso vivo.
  Sube el niquelaje → UN update por proceso, todo se revaloriza solo.
- Consecuencia: **si un costo da raro, se corrige el PESO del componente, no el
  precio.** Dudas abiertas: A9 (GP2 39 g vs lista Pedernera 21 g) y W7P (GP2 0,7 g
  vs lista 2,2 g — huele a error de carga; el crudo W7 dice 2,1 g).
- Verificado en vivo: V1 remache niquelado = crudo Barres $4,45 + $2.606/kg × 0,35 g
  = $5,36. Los V* pasaron a `fabricacion` (patrón crudo → Guazzaroni → niquelado).

### Cartones: cómo se compran de verdad (2026-08-31, archivo Conteo_Pedido_Cartones)

- **El precio va por FORMATO físico, y la hoja "Costos" col "Carton" es LA referencia
  por artículo** (la hoja " Cartones" tiene mapeos viejos/errados: 544 decía $89 y va
  $43 corbata ocho; 515/542/543/559/562/570 van $48 huevo).
- **Cartones COMPARTIDOS**: la OC pide por grupos "Carton Cod. 519D" (059/551/597),
  "Cod. 570D" (055/312/318/518/533), "Cod. 546D", "Cod. 562D" (564)... — varios
  artículos, UN SKU físico. En GP2 hay un componente cartón por artículo: para precio
  da igual, para la OC habrá que normalizar algún día.
- **Bolsas**: 031 = Vihal $63; 034 y 867 = $63 y ADEMÁS comparten el cartón del 544
  (falta referenciarlo en receta). 516 va EN BOLSA (sin cartón propio). Hay dos bolsas
  de filtro: Vihal $63 (19×5cm) y Cabral $39,32.
- **Cuchillos de untar: blister ×2 por cartón** `[usuario]` — todo el costo ×2 salvo
  el cartón. Los precios cargados son POR UNIDAD; el ×2 va en la receta (y el motor
  aún no multiplica cantidades — mismo pendiente del tocho/pliego).
- Decisiones puntuales del usuario: 587 = $89 (NO como sus hermanos peladores 79),
  580 = $43 (como 544, aunque hoja Costos diga 89), 099/713 = $72,85 (factura
  Pelapapas Chef, no los $89 de la hoja), 120 = $35,50 (el cartón que él recordaba).
- **LA FÓRMULA DEL PLIEGO** `[usuario 2026-08-31, cierre]`: *"los cartones deberían
  costar todos lo mismo considerando su múltiplo"* — el pliego vale ~$1.068 ($89 × 12)
  y el precio unitario = pliego ÷ posiciones. El pedido mínimo delata las posiciones
  (12.000 → 12 por pliego, etc.). **Toda la marca Chef pasó a 16 por pliego → $66,75**
  (salvo los de 25 → $42,72 y 30 → $35,60 — de ahí el $35,50 del 120). Esto PISÓ las
  "Medidas A/B/C" ($63,09/$106,67/$79,57) que eran precios de may-2024, y el
  "Pelapapas Chef" $72,85/$89: los 28 cartones Chef quedaron a $66,75.
- 706 y 700 ya NO van en skin `[usuario]`: cartón Chef común $66,75. El 546 va formato
  huevo $48 (NO los $89 de la hoja Costos). El 550 va $89 y **1 cartón por unidad**
  (la receta tenía ÷25 de la sesión bombillas — corregida a ×1, pendiente #2 del
  handoff saldado). El 516 va SUELTO (ni bolsa ni cartón, solo caja) → discontinuo.
- **CERRADO 85/85**: 81 con precio real + 4 discontinuados (574, 119, Skin 506, 516).
- **POR CATEGORÍA, no por precio suelto** `[usuario, cierre del día]`: los formatos
  viven en la tabla maestra `GP2.carton_formato` y cada cartón apunta con
  `componente.carton_formato`: **C** = 12/pliego $89 · **Loke** = 16/pliego $66,75
  (aunque lo use Chef) · **Huevo** = 25/pliego $42,72 · **8** = 30/pliego $35,60.
  Sube el pliego → se recalculan las 4 tarifas y listo. Asignados: C×29, Loke×28,
  Huevo×10, 8×3. Sin formato quedaron 15: los pelapapas $79 (¿categoría propia o
  es C con tirada de 30.000?), las bolsas ($63) y los pliegos skin ($147,97) —
  preguntar. OJO: `codigo_multiplo`/`min_codigo_x_multiplo` de la tabla maestra se
  cargaron con el pedido mínimo (12.000/16.000/25.000/30.000) y 1 — semántica a
  confirmar, la puso esta sesión `[deducido]`.
- `[usuario 2026-09-01]` **Bolsa de cartón embolsado** = paquete de paquetes. Cada
  bolsa tiene N paquetes según el formato (todos los paquetes = 250 uni): **Huevo**
  2000 uni/bolsa = 8 paq · **8** 3000 uni/bolsa = 12 paq · **C** 1000 uni/bolsa = 4
  paq · **LOKE** 1000 uni/bolsa = 4 paq. Guardado en columna nueva
  `GP2.carton_formato.uni_x_bolsa` (Pliego/Bolsa = NULL, no son cartón formal). En
  Recepción: **el remito se anota en PAQUETES** (lo que dice el proveedor), pero **el
  control físico se cuenta en BOLSAS** (más rápido que contar paquete por paquete).
  La RPC `guardar_control_cartones` acepta `bolsas` o `paquetes` por ítem y calcula
  `total_uni = bolsas*uni_x_bolsa` cuando aplica.

### Auditoría del 2026-08-31 (5 agentes) — ver `AUDITORIA_GP2_2026-08-31.md`

Hallazgos que cambian reglas de la casa (el detalle completo, con queries y números, está
en ese archivo):

- `[dato]` **`carton_formato.pliegos_multiplo` = múltiplo del PEDIDO TOTAL** (12.000 /
  16.000 / 25.000 / 30.000), NO posiciones por pliego. Está en `REGLAS_OC_INSUMOS.md` y lo
  usa `OC_GP2.html` para validar. Esta sesión lo interpretó mal y creó `Loke` (duplicado
  case-sensitive de `LOKE` — el nombre es la PK) rompiendo la validación de 38 cartones.
  **Corregido el mismo día.** Lección: antes de cargar una maestra, leer para qué la usa la
  OC, no solo cómo se llaman los campos.
- `[dato]` **Lo que neutraliza un placeholder es marcar `estado_compra`, no borrar la
  fila.** Los 37 placeholders vivos: 22 inertes (fabricacion/discontinuo), **13 con estado
  NULL que SÍ contaminan** a $1.535 la pieza → $47,8 M/mes de costo ficticio, el doble del
  valor de todo el stock. Los peores: C13, BOM13, BOM14, BOM8, BOM12, GRJ5.
- `[dato]` **`v_costo_componente.faltan_tiempos` no detecta el tiempo en CERO**, solo NULL.
  Hay 34 matrices en 0 usadas en rutas → 23 componentes con mano de obra $0 y el semáforo
  diciendo "todo bien". No usar ese contador como garantía hasta arreglarlo.
- `[dato 2026-08-31, RESUELTO el mismo día]` **La REGLA DE ORO ahora SÍ está garantizada
  por el modelo.** Antes `precio_servicio_pieza.proceso` era texto libre que ni siquiera
  participaba del join, y la tarifa del niquelado estaba repetida en 17 filas. Ahora:
  maestra **`GP2.proceso`** (11 procesos, con FK desde `precio_servicio_pieza`) y
  **`GP2.tarifa_servicio`** (proveedor + proceso + precio, UNIQUE) con las 6 tarifas planas
  que estaban repetidas en 33 filas. La fila por pieza quedó diciendo QUÉ proceso le toca;
  el PRECIO sale de la tarifa. **Precedencia en la vista**: tarifa por kg de la pieza →
  precio por unidad de la pieza → tarifa por kg del proceso → tarifa por unidad → plano.
  Pedernera se queda con tarifa por pieza (cobra distinto cada una, 35 tarifas), Jade y
  Ximpa por unidad. **Probado**: subir el niquelado de $2.606 a $3.000 revaloriza **31
  componentes de una sola vez** (V1 pasa de $0,912 a $1,05 = 3.000 × 0,35 g), y la
  migración no movió ni un peso (0 de 538 componentes cambiaron de costo).
- `[dato]` **El precio del cartón sigue cocinado en 73 filas**: `carton_formato` no tiene
  columna de precio, así que "sube el pliego y se recalculan las 4 tarifas" todavía no es
  verdad. Falta `precio_pliego` + `posiciones_x_pliego`.
- `[dato]` **`precio_proveedor` no tiene FK al proveedor** (solo `cod_prov` text sin
  destino). Trampa activa: los 9 precios de Recicor son referencia con fecha MÁS NUEVA que
  los vigentes del Plata; si alguien los vincula a un componente, las 9 cajas cambian de
  proveedor solas. Hoy el único discriminador es una mayúscula en `rubro`.
- `[dato]` **Dos agujeros de escritura anónima**: `GP2.empleado` (policies INSERT/UPDATE
  `TO anon` — no se puede cerrar sin migrar antes `Produccion/abm_GP2.html`, que escribe
  directo) y `GP2.inv_delta` (RPC anon que escribe inventario salteando `movimiento`, sin
  auditoría; ninguna pantalla la llama).
- `[dato]` **Si la receta lista un componente que no es el último de la ruta, todo lo que
  sigue queda en consumo 0** (la vista siembra desde la receta y camina hacia atrás).
  Casos: E6-M194 (570/858), D5/D6-M78 (507), B1/B2-M78 (707).
- `[dato]` **Los flejes redondos sin matriz de corte no convierten a kg** → máximo null →
  **la OC no los pide**: C3, E4, E5, E1 (~478 kg/mes). El peso está cargado en
  `fleje_detalle`; la vista podría usarlo directo cuando no hay matriz.
- `[dato]` **La suite de tests quedó ciega**: 29/29 pasan, pero todos stubean Supabase. El
  bug del clavo en la OC pasó sin despeinarse porque el stub no tiene `precio_por_kg`.
- `[usuario 2026-08-31, RESUELTO]` **LA MATRIZ 501 (afilado de cuchillas) SE MIDE EN KG,
  no en unidades como el resto.** Dicho textual: *"501 es la matriz del afilado de
  cuchillas. Se mide en kg, no en uni como el resto"*. Sus 7.650 segundos son **por KILO
  procesado**, no por pieza — por eso Z23/505/513/713 costaban 329 veces de más y
  arrastraban el 70% del pedido de toda la fábrica.
  **El dato no estaba mal: le faltaba decir en qué se mide.** Ahora la matriz lo declara:
  columna **`matriz.tiempo_unidad`** (`'uni'` por defecto, `'kg'` en la 501) y el motor
  multiplica por el peso vivo de la pieza que sale del paso. Z23: 7.650 × 0,0043 kg = 32,9 s
  de afilado + 1,3 s de las otras matrices = 34,2 s → $68,39 de mano de obra, y el costo
  pasa de **$15.349,70 a $115,49**. Verificado con snapshot: cambiaron exactamente esos 4
  componentes y ninguno más de los 538.
  **El máximo por sector cayó de $2.608 M a $678 M** y el stock de $23,0 M a $13,9 M.
  Regla que deja: antes de dar por malo un tiempo raro, preguntar **en qué unidad se mide**.
- `[dato]` **`inventario.maximo` no significa lo mismo en toda ubicación.** Solo los de
  `maximo_origen` est_madre / cinco_cajones / fisico tienen dueño; los de tallerista y
  Virgilio están en NULL, heredados. `v_valor_pedido` los suma todos → cuenta el mismo
  requerimiento hasta 5 veces: **$1.556 M, el 56% del pedido**. Decisión pendiente: ¿el
  máximo por sector incluye reponer lo que está en poder de terceros? SÍ: va todo el circuito.
- `[dato]` **Un fleje puede tener el máximo cargado en PIEZAS**: C3 (25.200 en IJUPA), E4 y
  E5 (9.000 en Alex) — el fleje se stockea en kg y sus máximos legítimos son ~2.900 kg.
  Regla: si un fleje tiene máximo en ubicación de tallerista, sospechar.
- `[dato]` **El patrón de ruta "Insumo X → Art" no lo ve el motor de costos**: el paso de
  tallerista guarda `comp_entrada_id = NULL` (366 pasos, 88 terminados). Los terminados hay
  que costearlos por RECETA, no por walk — que es lo que ya dice la cascada de 2c.
- `[dato]` **`precio_servicio` (el plano) quedó entero en 1 USD** — nunca se pisó, porque
  (`[2026-09-04]` la tabla `precio_servicio` se borró: estaba vacía y el motor usa
  `precio_servicio_pieza` + `tarifa_servicio`)
  los reales fueron a `precio_servicio_pieza`. Vale $49 M de pedido inventado en Z22, B12 y
  V18D, y mete pesos en la columna dólares.
- `[dato, verificado]` **Las rutas alternativas NO duplican el material** (G7 con y sin M77
  da US$0,14866 exacto). Los casos de "fleje contado dos veces" son dos piezas distintas
  del mismo fleje y están bien.
- `[usuario 2026-08-31, RESUELTO]` **TODOS los cuchillos de untar van en blister de 2**:
  los de mango de madera (519 Loeke / 719 Chef) y los de mango plástico (551 / 878). Se
  duplican hoja, arandela y mango; el **cartón y la caja NO**, porque el blister es uno
  solo. Estaba a medias: el 519 tenía dos hojas con un solo mango y el 719 no tenía el ×2
  en ningún componente. Corregidas las 4 recetas. La verificación cierra sola: E8 consume
  1.990/mes y sus dos mangos (PA4 rojo 1.420 + PA5 Chef 570) suman exactamente eso.
  **`[usuario 2026-08-31]` LAS DOS HOJAS SON DE ACERO INOXIDABLE** — lo plástico o de
  madera es el MANGO, nunca la hoja. Y son piezas distintas de verdad, con **distinto
  fleje y distinta matriz** `[dato, verificado]`:
  · **E7** (mango madera, 6,5 g) sale del **Fleje N° 41 / B2** — Aperam inox 430 **1 × 84**
    US$ 2,26/kg — por la matriz **348 "Corte Cuch Untar Mgo Madera"**.
  · **E8** (mango plástico, 11,3 g) sale del **Fleje N° 74 / F10** — Aperam inox 430
    **0,80 × 64** US$ 2,33/kg — pasa por la 347 y después por la **119 "Estampado
    Cuchillo Untar"** (3,2 s).
  O sea: misma familia de material (inox 430 de Aperam) pero otra medida de fleje, otro
  peso y otra matriz. **Nunca llamarle "hoja plástica" a E8.**
- `[dato 2026-08-31, arreglado]` **El modelo de seguridad quedó parejo**: la única
  escritura anon que quedaba (`GP2.empleado`) pasó por RPC — `empleado_guardar` /
  `empleado_activar`, SECURITY DEFINER, validan legajo único — y `Produccion/abm_GP2.html`
  las usa. `inv_delta` revocada (ojo: el EXECUTE estaba en **PUBLIC**, revocar a anon no
  alcanzaba). **Regla: una pantalla nueva NUNCA escribe una tabla directo, va por RPC.**
- `[dato 2026-08-31]` **`registrar_evento_prod` lee `matriz.tiempo_historico` para calcular
  el PREMIO del operario.** Por eso los 34 tiempos en cero NO se pasaron a NULL aunque eso
  encendería el semáforo de la valorización: 0 y NULL no se comportan igual en esa cuenta
  y el riesgo cae sobre la plata de la gente. El arreglo de fondo es medir esas matrices.
- `[dato]` **5 raíces huérfanas en Sector Procesado** costando $0: D1 (Espiral Sacacorcho),
  Z23A, Z23B, Z25A, Z25B. Son compradas sin precio ni estado — el caso C13 sin resolver.
  Ojo que **D1 existe además como Fleje N°28**.

### Placeholders que quedan (17 vivos, listados — no inventar)

Flejes D7 (EstaMetal sin lista), F12, Z19A · C13 bastidor importado (sin precio aún) ·
remaches CV13/CV14/CV16/CV18D y V10/V11/V14 (**OJO V10 y V11: no tienen ruta
CV→V de niquelado — falta crearla y marcarlos fabricacion como sus hermanos**) ·
BOM12/BOM8/BOM13/BOM14 + GRJ5/GRJ6 (Cimarrón, sesión bombillas) · servicios: B12/Z22
llavero pie (ningún pintor lo lista — pendiente por decisión del usuario) · pesos
dudosos A9 (21 vs 39 g) y W7P (0,7 vs 2,2 g). Modelado pendiente: partir el clavo
niquelado (patrón remaches), cantidades por paso en armados N→1, cartones
compartidos para la OC.

## 2c-ter. Alimentador vs balancín: un tiempo no se lee solo (2026-08-31)

`[usuario 2026-08-31]` Dicho textual: *"Necesito separar qué matrices se hacen en el
alimentador y qué matrices se hacen en balancín. El balancín tarda entre 6 a 10 segundos
por matriz como mínimo, y el alimentador es un golpe por segundo. Cuando me envíes un
tiempo, decime si es de alimentador o de balancín."*

**El dato ya existía en la casa del vecino y no lo teníamos**: `public."Matrices"` tiene
la columna `Tipo_Matriz` con una letra por matriz. Los promedios confirman que la letra
significa lo que parece `[dato, verificado]`:

| Letra | Máquina | Matrices en GP2 | Segundos promedio |
|---|---|---|---|
| **A** | **Alimentador** (un golpe por segundo) | 43 | **1,53** (máx 3) |
| **B** | **Balancín** | 59 | **7,41** |
| **D** | **Balancín** también `[usuario]` | 11 | 13,16 (6,2 a 21,5) |
| **P** | **Piedra** — es la 501, y en el vecino se llama "Piedra (TP)" | 1 | por kg, ver arriba |

Copiado a GP2 en `matriz.tipo` (la letra; la columna `tipo_matriz` duplicada se borró el 2026-09-04) y `matriz.maquina`
(`alimentador` / `balancin` / `piedra`, con CHECK). **No se inventó nada: es el dato del
vecino con el mapeo que dio el usuario.** En el vecino hay además 90 matrices tipo `E` y
22 tipo `T` que GP2 no usa.

**Para qué sirve**: un tiempo de balancín y uno de alimentador **no se comparan entre sí**.
Al informar un tiempo hay que decir de cuál es. Y el patrón que se ve: **se corta en
alimentador y se da forma en balancín** — las de "Corte" son casi todas A (la 348 Corte
Cuch Untar Mgo Madera, la 347, la 62), las de estampado/doblado/aplastado son B (la 119
Estampado Cuchillo Untar).

`[dato]` **Los 34 tiempos en cero se explican por acá**: 20 son de alimentador y 14 de
balancín, y varias nunca registraron producción. La **348**, por ejemplo, no tiene **ni un
registro** en ninguna de las cuatro tablas de producción del vecino (espejo de este año,
espejo histórico, Registros Históricos y Registros Producción Cervantes): su tiempo está
en 0 porque nunca se midió, no porque se haya perdido.

`[dato]` La única matriz sin clasificar es la **`S/N`** ("Corte Arandela Cuchillitos", 2
pasos de ruta): no tiene número y no existe en el vecino.

## 2c-quater. GOLPE ≠ UNIDAD: la trampa que puede duplicar todos los tiempos (2026-08-31)

`[usuario 2026-08-31]` Dicho textual: *"Hay matrices que expulsan más de una unidad. El
segundo por unidad, lógicamente, tiene que ser segundos por unidad, y el segundo y pico que
me dijeron yo entiendo que es por el GOLPE, no por la unidad."*

**Son tres cosas distintas y hay que no confundirlas nunca:**

| Concepto | Qué es | Dónde vive |
|---|---|---|
| **segundos por golpe** | lo que tarda la máquina en dar un golpe | **no está en la base** — es lo que dicen los operarios ("un segundo y pico") |
| **unidades por golpe** | cuántas piezas salen de ese golpe (1, 2, 4…) | `matriz.uni_x_golpe` — **cargado el 2026-08-31** (abajo) |
| **segundos por unidad** | `seg_x_golpe ÷ uni_x_golpe` | `matriz.tiempo_historico` ← **es lo que usa el costo** |

**La trampa**: `tiempo_historico` está verificado como **segundos por UNIDAD** (§2c: en el
espejo, `Segundos_Historico = Uni × Tiempo_Historico` exacto). Si alguien carga ahí un
tiempo **por golpe** de una matriz que saca 2 piezas por golpe, **el costo de mano de obra
de esa pieza sale al doble** y nada avisa. Es el mismo tipo de error que la 501 (un número
correcto en la unidad equivocada).

`[dato 2026-08-31]` **`uni_x_golpe` YA ESTÁ CARGADO** (antes estaba vacío: 113 matrices en
0 y 2 en null; en el vecino sigue vacío, 373 en 0 + 38 en null). Salió del archivo que pasó
el usuario, `Conteo_Gral_FLEJES_y_Alambre.xls`, hoja **"Consumo KG x Art"**, columna
**"Uni x Golpe"** (col. 14). El dato del Excel viene por *(fleje, pieza)* y se ancló a la
**matriz que corta ese fleje**, que es donde está el contador. Quedaron **17 matrices con
factor > 1** y 98 en 1:

| Factor | Matrices |
|---|---|
| **4** | m16 Corte Arandela manguito (fleje 38 / D4) |
| **3** | m71 Arandela Grande Afila (10 / F2) · m344 Arandela Base (74 / F10) · mS/N Arandela Cuchillitos (38 / D5) |
| **5** | m72 Arandela Chica Afila (10-11 / F2) — **resuelto abajo**: la hoja buena dice 5, el bloque del final está corrupto |
| **2** | m7 Cuchilla Abrelatas (2/C7) · m20 Engranaje Gr (3/B8) · m21 Buje 501 (4/C9) · m22 Arandela fina 501 (5/D6) · m15 Arandela fina 502 (5/D6) · m14 Engranaje chico (8/A10) · m40 Sacatapita (25/C1) · m60 Pinza Fideos (39/A4) · **m64 Pinza Fiambre (40/A4)** · **m348 Corte Cuch Untar Mgo Madera (41/B2)** · m66 Pinza Ensalada (45/F5) · m29 Corte Uña (57/B4) · m116 Corte de Aleta (92/C2) |

**Cómo leer la columna sin equivocarse**: la hoja tiene DOS columnas parecidas, *"Uni x Art
Term"* (col. 13, cuántas piezas lleva el artículo) y *"Uni x Golpe"* (col. 14). Coinciden en
215 filas y difieren en 85 — no son la misma cosa. Ejemplo que lo separa: *Hoja C Untar Mgo
Plast* (F10) lleva **2 por artículo** (blíster de 2) pero sale **1 por golpe**; *Hojita Cuch
Mad* (B2) lleva 2 y también sale 2 por golpe. El bloque final de la hoja (filas de kits, sin
sector) tiene la col. 13 pisada con el valor de golpe — **no usar ese bloque**.

**Caso 348 RESUELTO**: saca **2 unidades por golpe**. Entonces el *"segundo y pico"* que le
dijeron al usuario es **por golpe** → **≈ 0,6–0,75 s por unidad**, que es lo que va en
`tiempo_historico`. Sigue sin cargarse hasta que el usuario confirme el número exacto, pero
ahora ya se sabe por cuánto hay que dividir.

**Pinza de fiambre: GP2 la tenía mal modelada y se corrigió** — ver §2c-quinquies.

**Arandela chica de afilar (m72): queda en 5, y el archivo lo demuestra.** El Excel se
contradice — la hoja principal dice *8 por artículo / 5 por golpe* y el bloque del final
dice *3 / 3* para los mismos artículos (504 y 97). **Gana la hoja principal**, por dos
pruebas:

1. **El bloque del final tiene la columna 13 pisada.** Se ve con la arandela **grande**, que
   va justo al lado: la hoja principal dice *6 por artículo / 3 por golpe*, y el bloque del
   final dice *3 / 3*. Ese 6 → 3 es un dato que sabemos que está mal, y demuestra que ahí la
   columna "Uni x Art Term" quedó pisada con el valor de golpe. El 3 de la chica en ese
   bloque es, muy probablemente, el mismo 3 arrastrado de la grande.
2. **La hoja principal cierra sola.** `KG x Uni c/Desp = Peso Neto ÷ (1 − Desperdicio)`, y da
   exacto en las dos: grande 0,00495 ÷ (1 − 0,2703) = **0,0067835** ✓ y chica 0,00172 ÷
   (1 − 0,28234) = **0,0023967** ✓. El bloque del final **no tiene ni peso neto ni
   desperdicio** (columnas vacías): no se puede verificar nada de ahí.

**Regla que deja**: cuando el Excel de flejes diga dos cosas distintas, ganar la fila que
tenga **peso neto y desperdicio cargados** — es la que se puede verificar con la cuenta.

### La app YA pide GOLPES (2026-08-31)

`[usuario 2026-08-31]` Dicho textual: *"Yo quiero que ellos anoten golpes, que es lo que
dice el contador que tienen en la matriz que está puesta, o en el alimentador o en el
balancín. Entonces, en función de la cantidad de golpes que ellos hagan para calcular las
unidades que fabricaron, se multiplica automáticamente con un factor que vos tengas
normalizado dentro de tu base."*

Es la **regla de oro** aplicada a la producción: el operario anota el dato **crudo** que ve
(golpes del contador) y el factor vive **en la base, en un solo lugar**. El día que se
cambia una matriz se toca `matriz.uni_x_golpe` y no hay que reeducar a nadie ni corregir
registros viejos.

- **App de operarios** (`Operarios_GP2.html`): el botón **C (Cajón)** ahora dice *"Ingresa
  los GOLPES del contador"* y debajo del campo se ve en vivo *"Matriz 348: cada golpe saca 2
  unidades. 240 golpes = 480 unidades."* En las matrices de factor > 1 pide **confirmación**
  antes de mandar (es donde vive el riesgo de que tipeen unidades por costumbre).
- **Registro Producción** (`Registro_GP2.html`): campo **Golpes del contador** + campo
  **Unidades producidas** de sólo lectura que se calcula solo.
- **BD**: `registrar_evento_prod` y `registrar_produccion` aceptan `golpes` y hacen
  `uni = golpes × matriz.uni_x_golpe`. `produccion` guarda **las tres cosas**: `golpes` tal
  como los tipeó el operario, `uni_x_golpe` (**foto del factor** al momento del registro, así
  cambiar el factor mañana no mueve la producción vieja) y `uni`. Si el payload NO trae
  `golpes` (app vieja en un celular sin actualizar), se comporta **exactamente como antes**.
- **Interruptor**: `GP2.parametro.registro_en_golpes` ('1' pide golpes, '0' vuelve a
  unidades directas). Está por la duda de planta de abajo — se cambia una fila y la app
  entera vuelve atrás sin tocar código.

**Por qué esto además ARREGLA el premio**: `tiempo_toma = segundos ÷ unidades` y
`tiempo_historico` es por unidad. Si el operario contaba golpes en una matriz de 2, las
unidades registradas eran la mitad, el `tiempo_toma` el doble y el premio salía mal **en
contra del operario**. Verificado con rollback: 240 golpes en la 348 con 300 s dan 480 uni y
`tiempo_toma` 0,625 s/uni (no 1,25). `[dato]` `GP2.produccion` está **vacía** (0 filas), así
que no hay historia que migrar.

**Duda abierta `[usuario, va a confirmarlo en planta]`**: si hoy los operarios cuentan
golpes o unidades. *"Ahí tenemos una duplicación de unidades en todos lados que nos va a
confundir si es que lo hacen mal."* La app ya está del lado de los golpes y el aviso en
pantalla dice la cuenta en voz alta; si en planta resulta que cuentan unidades, se apaga con
el interruptor.

## 2c-quinquies. Pinza de fiambre: UN corte y DOS estampados (2026-08-31)

`[usuario 2026-08-31]` Dicho textual: *"La pinza fiambre se corta en alimentador con la
misma matriz y después se estampa con dos diferentes (una para cada lado). 63 estampa la
derecha, 65 la izquierda."* Y confirmó: **corta la 64**.

**Lo que GP2 tenía mal**: modelaba **dos cortes**, uno por lado, cada uno con su propia tira
intermedia:

```
MAL:  A4 --m62--> A4-M62 --m63--> F9  (derecha)
      A4 --m64--> A4-M64 --m65--> F10 (izquierda)

BIEN: A4 --m64--> A4-M64 --m63--> F9  (derecha)
                        \--m65--> F10 (izquierda)
```

Es **exactamente la forma que la pinza de fideos ya tenía bien** (m60 corta → m61 der /
m75 izq). Las dos gemelas quedan iguales.

**Qué se corrigió**: las 4 rutas de fiambre (130/132 art 595 y 53 por la derecha,
131/133 por la izquierda) pasan por la 64; el componente intermedio **A4-M62 se borró**
(no tenía stock, ni movimientos, ni recetas, ni precios — era puro producto del modelado
equivocado); la **64 se renombró** de *"Corte Pinza Fiambre Izquierda"* a **"Corte Pinza
Fiambre"**, porque ya no corta un lado sino la pieza entera; y **`uni_x_golpe = 2`**, que es
lo que decía el Excel y ahora cierra: un golpe saca las dos punteras.

**La 62 NO se borró** — la matriz física existe, pero `[usuario 2026-08-31]` está
**inactiva**. Se agregó `GP2.matriz.activa` (boolean, default true) y la 62 quedó en `false`:
las apps **no la ofrecen** en el buscador de matrices ni la aceptan tipeada ("está dada de
baja, no se usa más"), pero sigue en el diccionario para poder ponerle nombre a un registro
viejo. Es la única matriz inactiva de GP2.

**Impacto en el costo — el error valía plata**: el artículo 595 (y su gemelo 53) pasó de
**$353,08 a $270,46**. Contaba **la tira dos veces**: al salir F9 y F10 de tiras distintas,
el recorrido de costos sumaba dos cortes de fleje para una pinza que sale de **uno solo**.
Cambiaron exactamente esos 2 artículos y ninguno más de los 537 componentes.

**Cómo se detecta este error en otro lado**: si dos piezas que van juntas en el mismo
artículo salen de **tiras intermedias distintas** (`X-M##`) pero en la planta salen del
mismo golpe, el material está duplicado. Señal de alarma: dos matrices de corte con el mismo
fleje de entrada y el **mismo costo exacto** (A4-M62 y A4-M64 daban los dos US$ 0,083693).
`[dato]` Se barrió el resto de GP2 buscando matrices con "Derecha/Izquierda/Der/Izq" en el
nombre y **la de fiambre era la única mal modelada**.

**Verificación que cierra**: 594 (fideos) y 595 (fiambre) quedaron con la misma estructura,
US$ 0,094316 y US$ 0,096879 de material. La diferencia que queda ($304,52 vs $270,46) es
**sólo mano de obra**: fideos tiene 19 s cargados (m60 3 + m61 8 + m75 8) y fiambre tiene 0
porque la 63, la 64 y la 65 están entre las 34 matrices sin tiempo medido.

## 2c-sexies. Tiempos de la pinza de fiambre: qué tiene el vecino (2026-08-31)

`[dato 2026-08-31]` Se buscó en **las 4 tablas** del vecino. Resultado:

| Matriz | Maestro `Matrices` | `db_n8n_espejo` (+histórico) | `Registros Historicos` |
|---|---|---|---|
| 62 Corte Fiambre Der | 0 | — | — |
| 63 Estampado Fiambre Der | 0 | — | — |
| **64 Corte Fiambre** | 0 | — | **17 registros, ago–sep 2025** |
| 65 Estampado Fiambre Izq | 0 | — | — |

O sea: **63 y 65 no tienen ni un registro en ningún lado**. La 64 sí, pero **no sirve como
está**: de los 17 registros, **5 están anulados** (`Anular_Tiempo = true`) y los 12 que
quedan van de **9,3 a 50 s por unidad** — una dispersión de 5x. Los mejores son las tandas
largas de un mismo operario (394, 553, 387 y 670 uni): **9,3 / 11,2 / 11,4 / 14,1**.

**Lo que NO cierra y hay que resolver antes de cargar nada** `[pendiente]`: la 64 es
**alimentador** (tipo A en el vecino) y el usuario dijo que el alimentador va a **≈1 golpe
por segundo**; sacando 2 por golpe eso daría **~0,5 s/uni**, no 9–14. Y su **gemela exacta**,
la m60 *Corte Pinza Fideos* — mismo fleje A4, mismo alimentador, misma operación, también 2
por golpe — mide **2,30 s/uni** en el espejo (12 registros, 12.009 uni). La 64 daría **4 a 6
veces más lenta que su gemela haciendo lo mismo**. Alguna de estas tres es cierta y hay que
saber cuál: (a) el operario cargaba **cajones o golpes** en vez de unidades, (b) esos
registros de 2025 no son de esta operación, (c) la 64 realmente tarda eso.

`[dato]` Tiempos reales de la gemela, por si sirven de referencia mientras tanto — **medidos,
no los del maestro**: m60 corte **2,30** s/uni (maestro dice 3) · m61 estampado der **11,02**
(maestro 8) · m75 estampado izq **10,49** (maestro 8). Los tres estampados de balancín dan
~10-11 s, que sí cierra con "el balancín tarda 6 a 10 segundos" (§2c-ter).

## 2c-septies. El 506 va con SKIN: Gentile y el garage (2026-08-31)

`[usuario 2026-08-31]` Dicho textual: *"El 506 va con skin (o sea con Gentile y con
Martin/Carlos entregando en Cervantes garage)"*. Es el **mismo patrón de las bombillas
557/558** (§ del garage): quien arma entrega el cuerpo en el garage y **Gentile hace el
skin, que ES el packaging**, y de ahí sale a Virgilio.

```
ANTES:  partes -> Martin/Alex ------------------------> 506 -> Virgilio   (+ cartón $89)
AHORA:  partes -> Martin/Alex -> GRJ7 (garage) -> Gentile -> 506 -> Virgilio
        skin V3A ------------------------------> Gentile -> 506 -> Virgilio
        caja A11 ------------------------------> Gentile -> 506 -> Virgilio
```

**Las piezas YA existían sueltas y sólo había que conectarlas**: `GRJ7` *"Abrelata Uña 506"*
(Sector Garage) estaba **sin BOM, sin ruta y sin receta**, y `V3A` *"Skin 506"* estaba
marcado **discontinuo**. Ahora GRJ7 = A10 + C10 + V9, la receta del 506 es **GRJ7 ×1 +
V3A ×1 + caja ×1/12** (las partes sueltas y el cartón salieron), y las 8 rutas de partes
pasan por Gentile.

### `[usuario]` CARLOS = ALEX ESCALANTE — la misma persona
Dicho textual: *"carlos = alex, dejámelo decirte así y vos entendé que hablo del mismo"*.
Cuando el usuario dice **"Martin/Carlos"** habla de **Martin Cornejo + Alex Escalante**, que
son justo los dos que ya tenía el 506: **no hubo que cambiar ningún tallerista**. Cargado en
`contraparte_alias` ('Carlos' → tallerista 2). `[pendiente]` GP2 tiene además un tallerista
**"Carlos Aguirre" (id 9, 32 pasos)** — preguntar si es otra persona o un duplicado del
mismo; **no se fusionó nada**.

### El precio del skin: pliego + autoadhesivado
`[usuario]` *"el pliego de cartón es de $768 (pero hay que sumar el costo del
autoadhesivado)"*. O sea el skin **no** son los $89 del cartón común. Por la **regla de oro**
los dos costos tienen que vivir separados (cambia el autoadhesivado → se toca un número).
`[pendiente]` faltan **el costo del autoadhesivado** y **cuántos 506 entran por pliego**;
hasta que lleguen, **V3A quedó SIN precio** (cuenta en `faltan_precios`) en vez de inventar
uno. También falta **cuánto cobra Gentile el envasado del 506** (el de bombillas es $69/uni).

### Lo que se encontró de paso
- **V9 "Remache uña niq." tenía un placeholder de 1 USD** en `precio_proveedor` que inventaba
  **$1.535 por unidad** en cuanto V9 entraba por BOM en vez de por ruta: GRJ7 daba $1.795,93.
  Borrado el placeholder, GRJ7 = **$260,93**, y V9 conserva su costo real por ruta ($4,45 del
  remache + $1,48 de niquelado = $5,93). Snapshot de los 537 componentes: **no cambió ningún
  otro**. `[dato]` **quedan 35 placeholders de 1 USD** en `precio_proveedor` — la auditoría
  había limpiado los de `precio_servicio`, estos siguen ahí y muerden igual.
- `[dato]` **16 filas de `v_valor_stock` tienen stock NEGATIVO, por −$7.274.776.** Explican
  por qué el stock total neto da $8,6M. Sin relación con este cambio (GRJ7 y V3A tienen
  stock 0) — **pendiente de revisar aparte**.
- La **caja** ahora la arma Gentile, porque es quien entrega a Virgilio. `[deducido]` — el
  usuario no lo dijo; si la siguen poniendo Martin/Alex, se vuelve atrás.

### ⚠️ TRAMPA QUE MORDIÓ EN ESTE MISMO CAMBIO: buscar componentes POR CÓDIGO
El BOM de GRJ7 se cargó con `where codigo in ('A10','C10','V9')` y salieron **5 filas en vez
de 3**: `A10` es la pieza *"Cpo Uña LK C/M Pint."* (id 85) **y** el *"Fleje N° 8"* (id 174);
`C10` es *"Uñas Zinc."* (id 103) **y** el *"Fleje N° 62"* (id 208). Los dos flejes entraron
como si fueran partes del abrelatas. Corregido cargando por id.
**Los códigos de componente NO son únicos: siempre por `id`.** Es la misma regla que el
usuario dictó el 2026-08-30 para cargar precios, y se rompió igual — vale para TODO, no sólo
para precios.

## 2c-octies. El rollo depende de la PIEZA, no solo de la matriz (2026-08-31)

`[usuario 2026-08-31, con foto]` *"A15 usa un tipo de rollo (inox) y J2/J5 usa otro"*. Hay
matrices que **cortan de dos flejes distintos** según qué pieza salga:

| Matriz | Pieza | Fleje |
|---|---|---|
| **28** Corte Cuerpo Uña | A15 (Cpo Uña Crom.) | **Fleje N° 94 / F1A** (inox) |
| | J2 / J5 (Cuerpo Uña p/Pintar) | **Fleje N° 13 / A1** |
| **37** Corte Cuerpo Sacac. | F3-M37 | Fleje N° 22 / F3 |
| | F3A-M37 | Fleje N° 93 / F3A |

`[dato]` Barrido de `ruta_paso`: **son exactamente estas 2** las que cortan de más de un
fleje. Todo el resto es un fleje por matriz.

**El bug**: el bundle devolvía **UN solo fleje por matriz** (`matriz_fleje`,
`distinct on (n_matriz) order by c.id`), así que para la 28 ganaba siempre A1. El operario
que elegía A15 tenía que agarrar un rollo A1 igual, y **el descuento de stock salía del
fleje equivocado** (el común en vez del inox). No era cosmético.

**Arreglo**: `registro_operarios_bundle` agrega `matriz_fleje_pieza`
(`n_matriz → comp_salida_id → fleje`). La app:
- con **pieza elegida**, ofrece solo los rollos del fleje de esa pieza;
- en una matriz de 2 flejes **sin** pieza elegida, si la pantalla va a pedir la pieza
  (2+ salidas) espera a que la elija; si no la va a pedir, ofrece los rollos de **los dos**
  flejes con el código a la vista — nunca deja al operario sin ninguno;
- matriz de un solo fleje: igual que siempre (`matriz_fleje` de fallback).

`matriz_fleje` se mantiene para las matrices de un fleje y como respaldo si un celular corre
un bundle viejo.

## 2c-nonies. Un solo buscador de matriz (2026-08-31)

`[usuario 2026-08-31, con foto]` *"si puedo escribir arriba y busca, sacá lo de abajo"*. La
pantalla de operarios tenía **dos cajas de texto** para lo mismo: el campo *"Ingresa el
número"* (que ya filtra la lista por número **y** por nombre) y un *"Buscar por número o
nombre…"* debajo. Se sacó el de abajo (`#matrizSearch`); el filtro sale siempre del campo de
arriba.

## 2c-decies. Versiones y UX de la app de operarios (2026-08-31)

Varios pedidos del usuario sobre `Produccion/RegistroApp/Operarios_GP2.html` en una tarde:

- **Sin número de versión en pantalla** `[usuario]`: *"sacá el badge de versión... no hace
  falta que ahí haya un número de versión"*. Venía con versión propia (`1.9.0`) escrita en 3
  lugares (`?v=` del script, `MI_V` del auto-recargador, `APP_VERSION` del badge); al bumpear
  uno y olvidar otro el badge mentía y recargaba al pedo en cada celular. Ahora el badge
  `#syncBadge` es **solo estado de cola** (`✓ al día` / `⚠ N sin enviar`). Lo único versionado
  es el `?v=` del script (cache-busting, no a la vista) y el `MI_V` que lo sigue. El
  `test_tokens_cache` fija que no reaparezca una versión.

- **Un solo buscador** `[usuario]`: el campo *"Ingresa el número"* ya filtra la lista por
  número Y nombre; se sacó el `#matrizSearch` de abajo que era la misma cosa.

- **La lista colapsa en match exacto** `[usuario: "cuando elijo 1 no me muestres las demás"]`:
  si lo tipeado matchea EXACTO el número de una matriz, la lista muestra **solo esa** (antes,
  tipear "1" dejaba 1, 10, 11, 112...).

- **Rollos en BOTONES, no desplegable** `[usuario]`: `#rolloGrid` con botones `.rl` (kg grande
  + fleje · disponibles), mismo patrón que matriz/pieza. El elegido queda en `rolloSel` (antes
  el `value` de un `<select>`).

- **La pieza elegida va a la DERECHA del número de matriz y achica la pantalla** `[usuario]`:
  al elegir la pieza, la card de la matriz muestra un chip con el código de la pieza a la
  derecha (`.mz.has-chip` + `.mz-chip` "acá va el stock"), y el box amarillo de selección se
  **colapsa a una línea** ("Fabricás A15 · … — cambiar"). Tocar "cambiar" reabre el grid.


## 2c-undecies. Stock en Movimiento (Sector Tránsito): sin mín/máx ni carteles (2026-08-31)

`[usuario 2026-08-31, con foto]` sobre `StockSector/StockSector_GP2.html?sector=3`:

- **Solo el botón "Atrás"** en el header: sacados "Exportar CSV", "Stock SC" y "Stock SP".
- **Sacados los dos carteles amarillos**: el explicativo ("Piezas entre matrices…") y el de
  factores ("De 43 componentes, 43 sin `kg_x_uni`…").
- **No van mínimo ni máximo**: se quitaron las columnas Mínimo/Máximo, el KPI "Bajo mínimo" y
  el filtro "Bajo mínimo". Se hizo con un flag `sin_min_max: true` en el `STOCK_CFG` de esta
  pantalla, honrado por el renderer compartido `gp2-stock-sector.js` (bumpeado a ?v=1.3.0 en
  las 9 pantallas que lo usan). **StockSC / StockSP siguen con min/máx** — verificado.

**Por qué el Sector Tránsito no tiene mín/máx ni `kg_x_uni`/`uni_x_cajon`** `[dato]`: son las
piezas **intermedias entre matrices** (los `X-M##`, "Fleje N° 13 tras M28"): una matriz ya las
cortó y la siguiente todavía no las consumió. Es **trabajo en curso transitorio**, no algo que
se stockea, se pesa por kilo o se guarda en cajones ni que se "repone" a un mínimo — por eso
esos campos nunca se cargaron y salían "—". El stock en **Uni** es correcto igual. Cargar
`kg_x_uni`/`uni_x_cajon` ahí sería inventar un dato que el negocio no usa.

## 2c-duodecies. La tarjeta de Recepción muestra SOLO la OC (2026-08-31)

`[usuario 2026-08-31, con foto, en dos pasos]` sobre `StockFlejes/RecepcionInsumos_GP2.html`.
Primero: **"está mostrando lo último que recibí, está mal"** — el número verde de la tarjeta
era la ÚLTIMA RECEPCIÓN (A1 decía "280 kg" = lo recibido ese día) y, sin etiqueta (la palabra
"ult." se había sacado el 2026-08-29 a pedido), se leía como si fuera el stock. Se probó
mostrar el stock real (v3.19.0, A1 "959,12 kg") y el usuario cerró la decisión: **"no quiero
el stock, solo la OC. Si no hay OC, nada ahí abajo"**. Desde v3.20.0 la tarjeta es código +
descripción + medida + **la OC abierta** ("OC: lo que falta + unidad") — y sin OC, nada
debajo de la medida. Al recibir, lo único que importa mirar es qué pedido está esperando ese
insumo; el stock se consulta en las pantallas de stock. Regla general que dejó el ida y
vuelta: **un número sin etiqueta en una tarjeta se lee como stock** — cualquier otra cosa
(última carga, consumo) lleva etiqueta sí o sí, o directamente no va. El bundle sigue
mandando `stock` (clave agregada hoy a `recepcion_bundle`, `GP2.inventario` en la ubicación
del sector del insumo) y `ultima` por si hacen falta, pero la tarjeta no pinta ninguno.

## 2c-terdecies. Limpieza de placeholders de 1 USD (2026-08-31)

`[usuario]` "los 35 placeholders de 1 USD que quedan". Barrio de una: **23 borrados, 12
quedan pendientes de precio real**.

### Borrados sin dato del usuario (23)

**A) 15 fabricados por ruta** (crudo + niquelado ya los costea, el 1 USD solo inventaba plata
apenas entraban por BOM en vez de ruta — mismo patron que V9 ayer):
V1, V2, V3, V4, V5, V6, V7, V8, V12, V18D (remaches propios niquelados) · CV13, CV18D (sus
crudos) · D7 (Fleje N° 50, sale de ruta) · GRJ5, GRJ6 (bombillas armadas en garage).

**B) 8 discontinuos** (no hay proveedor real):
C1B (Carton 574), I3B (Carton 119), L4B1 (Carton 516), PB1, CV17, CV20, V18C, V20.

Sobre V20 (Tornillo Corta Queso): sigue en 3 rutas (arts 119/574/809) pero los 3 estan
**discontinuados** — es coherente, no es huerfano.

### DESCUBRIMIENTO IMPORTANTE — el 1 USD costeaba mas de lo que parecia
7 componentes cayeron **$1.535 -> $0** al borrar el placeholder (G4, M1, CV13, CV18D, D7,
V18D, D7-M23). Estos NO tienen ruta que los produzca y NO tienen precio real: el 1 USD era
lo unico que los hacia "costar algo". Ahora `faltan_precios=1` los marca como incompletos,
que es la verdad. Cargar el precio real cuando venga.

### Pendientes de precio real (12 comprables)
- **Cimarron** `[usuario 2026-08-31]`: "a Cimarron NO le compramos BOM12, le compramos la
  BOMBILLA entera 557/558". VERIFICADO: no hay NINGUN precio de Cimarron en la base hoy.
  BOM12 (Cano Inox 140 mm), BOM8 (Resorte), BOM13 (Filtro), BOM14 (Precinto) son componentes
  intermedios de recetas — si vos comprás la bombilla armada, no son insumos de compra. Falta
  cargar el precio de la 557/558 armada como compra a Cimarron; los BOM* siguen usandose en
  las recetas de fabricacion propia si algun dia la hacemos.
- Z19A (Alambre Corta Queso, 546), F12 (Fleje N° 49), C13 (Bastidor Corta Queso), V10 (Rem
  Alum Canel), V14 (Remache Pinza), V11 (Rem Sacacorcho), CV14, CV16.

## 2c-quaterdecies. Tiempos de matrices derivados del vecino (2026-08-31)

`[usuario 2026-08-31]` "los tiempos que puedas sacar del vecino, sacalos". El agente
`gp2-auditor-costos` propuso el protocolo (mediana + IQR, filtros por máquina, exclusiones
por dispersión), la sesión principal ejecutó y verificó con snapshot antes/después.

**Método**: unión de las 3 tablas del vecino con producción — `db_n8n_espejo`, su
histórica (`_20260419`), `Registros Historicos`. Filtros: `Eliminar<>'S'`, `Anular_Tiempo`
false, `Uni>0`, `Segundos_Trabajados>0`. Cada registro da `seg/uni`. Sobre esos:

- **N usado**: solo tandas con `Uni >= 10` (las de <10 mienten mucho).
- **Mediana** (no promedio, resiste outliers).
- **Dispersión** = `IQR / mediana`. Si `IQR > 2 x mediana` → DUDOSA, no se carga.
- **Rango por máquina** (§2c-ter): alimentador 0,4–4 s/uni; balancín 4–12. Fuera de esos
  rangos = DUDOSA.

**CARGADAS (15)** — 34 activas sin tiempo → 19:

| Nº | Descripción | Máquina | N | Mediana s/uni |
|---|---|---|---|---|
| 14 | Corte Engranaje chico (uxg=2) | alim | 5/5 | 0,53 |
| 32 | Corte Cuerpo 3 en 1 | alim | 5/5 | 2,61 |
| 40 | Corte Sacatapita (uxg=2) | alim | 24/24 | 0,84 |
| 44 | Corte Cuchufli | alim | 7/7 | 1,06 |
| 68 | Corte Resorte U | alim | 6/6 | 1,41 |
| 137 | Cortar arandela Batidor | alim | 5/5 | 0,73 |
| 152 | Corte Pza Ch Sacaf Gast | alim | 4/4 | 2,10 |
| 153 | Corte Pza Grande Sacaf Gast | alim | 7/7 | 3,69 |
| 155 | Estampado Pza Ch Sacaf Gast | balan | 11/11 | 8,04 |
| 169 | Doblado Vast Pala Canelón | balan | 3/3 | 6,09 |
| 346 | Corte Vast Corta Pizza Gr | alim | 4/4 | 1,84 |
| 347 | Corte Cuch Untar Mgo Plast | alim | 7/7 | 1,37 |
| 355 | Corte Pala Canelón | alim | 6/6 | 3,02 |
| 365 | Corte Pza Gr Sacaf Pizz | alim | 5/5 | 2,41 |
| 366 | Corte Super Mariposita | alim | 12/12 | 2,00 |

**DUDOSAS (2)** — NO cargadas:
- **m64 Corte Pinza Fiambre**: mediana 25,58 s/uni. Confirmado lo de la mañana: cargaban
  golpes o cajones, no unidades. Su gemela m60 (mismo alimentador, misma operación) mide
  2,30. Sigue en 0 hasta cronometrar en planta.
- **m16 Corte Arandela manguito (uxg=4)**: mediana 0,26 s/uni, muy bajo para alimentador
  (piso 0,4). Sospecha simétrica a la 64: pudieron haber cargado unidades × 4 (o sea el
  golpe multiplicado). Como uxg=4 es el mayor de la fábrica, el ruido es mayor.

**Impacto medido**: 76 componentes movidos, todos hacia arriba, delta máximo $27,66 (art
508: corte engranaje chico + estampado 3en1). Ningún componente ajeno cambió — el snapshot
demostró que las cirugías previas siguen aisladas.

**Bug propio detectado**: el auditor `gp2-auditor-costos` no tenía `execute_sql` — su
frontmatter decía `mcp__Supabase__` pero el server real del proyecto es
`mcp__c1349a3b-...__`. Corregido en los 3 agentes que tocan la base. La sesión principal
tomó el protocolo (la parte útil) y ejecutó las consultas.

## 2e-bis. `minimo` y `maximo` no miden lo mismo (2026-09-02)

Se confundieron una vez, así que queda escrito:

- **`minimo` = lo que consumís.** `consumo_uni_mes × ubicacion.meses_minimo` (en flejes, kg).
  Lo calcula **`recalcular_minimos()`** (creada el 2026-09-02, idea 7211), el espejo de las
  de máximos que ya existían. Marca las filas que toca con `minimo_origen = 'consumo'`.
- **`maximo` = lo que entra.** En crudo/procesado es físico (5 cajones ×`uni_x_cajon`,
  `maximo_origen 'cinco_cajones'` o `'fisico'`); en los sectores de insumo sale de la Est
  Madre, que también es consumo (`consumo × meses_stock`, `maximo_origen 'est_madre'`).

**Por eso `minimo > maximo` puede ser correcto**: significa que en ese lugar **no entra lo
que gastás** en esos meses. Después del recálculo quedan **77 filas así**, todas de máximo
físico — el caso más duro es **V9 en Sector Remache**: mínimo 113.912, máximo 10.581,
consumo 28.478/mes, o sea que ahí entran **menos de 15 días** de remaches. No es un dato
para arreglar: es la planta, y el que compra tiene que saberlo.

**Lo que NO se hizo, a propósito**: se había propuesto "topar el faltante contra el
máximo". Mirando el código no correspondía — `oc_bundle` y `crear_oc` no usaban `minimo`
ni `maximo`, así que nunca pedían de más por esto.

> ⚠️ **CORREGIDO EL 2026-09-04: esta frase dejó de ser cierta al día siguiente.** El
> 2026-09-03 `oc_bundle` se reescribió y hoy pide **`maximo − stock − pendiente`**; el
> `consumo × meses` quedó de respaldo, sólo cuando el máximo está vacío. Así que sí usa el
> máximo, y la garantía de "nunca pide de más por esto" **ya no vale**. Ver §4n. El único que usa el mínimo es `faltantes_bundle`, y ahí la marca de faltante
**tiene que quedar prendida** en esas 77 filas: es verdad que falta. Topearla sería tapar
la señal.

**Cuidado al recalcular**: los mínimos son **carga original del usuario** (los 766 del
estado limpio). `recalcular_minimos()` por eso **no toca** las filas cuyo consumo es 0 o
desconocido — el número del usuario es mejor dato que un cero calculado — ni las de
tallerista y proveedor de servicio, que tienen otro origen. La foto previa quedó en
`db/respaldo_inventario_minimo_20260902.csv` (en el repo: las 378 filas que cambiaron, con el
mínimo de antes y el recalculado) para poder volver atrás. `[2026-09-04]` La tabla
`GP2.inventario_minimo_backup_20260902` se borró en la auditoría de arquitectura (ver
`REFACTOR_GP2.md`): las copias de datos no viven en la base, viven en git.

## 2e. Faltantes y máximos de Crudo/Procesado: 5 cajones por ubicación (2026-08-31)

`[usuario 2026-08-30]` **"En crudo y procesado, el stock máximo tendría que ser 5
CAJONES por ubicación."** El máximo físico de cada componente de Sector Crudo y Sector
Procesado en su ubicación de sector es **5 × uni_x_cajon** (parámetro
`GP2.parametro['max_cajones_x_ubicacion'] = 5`, función `recalcular_maximos_cajones()`,
`maximo_origen = 'cinco_cajones'`). Pisó el modelo viejo de estantería
(`hueco_hasta_proximo_codigo` y supuestos). Se recalcula solo si cambia `uni_x_cajon`
de un componente o el parámetro (triggers `trg_maximos_cajones_*`). El componente sin
`uni_x_cajon` queda con máximo null y se lista pendiente en la pantalla de Faltantes
(hoy sólo Z12 de Procesado). No toca los sectores de insumos (5-11), que siguen con la
Est Madre (`recalcular_maximos_insumos`, `maximo_origen='est_madre'`).

`[usuario 2026-08-30]` **El faltante es AUTOMÁTICO en función del stock online** (antes,
en la casa del vecino, la "F" se ponía a mano cuando ibas a mandar a un tallerista/PS y
no había): crudo para mandar al proveedor de servicio, procesado para mandar al
tallerista. **Pero también se puede marcar a mano.** Módulo `Faltantes/Faltantes_GP2.html`:
faltante automático = stock menor al umbral, marcas manuales en `GP2.faltante_marcado`
(RPCs `marcar_faltante` / `resolver_faltante`). Las pantallas de Envíos persisten la
marca F ahí (origen `envios_tall` / `envios_ps`, best-effort al tocar el botón F).

`[deducido 2026-08-30, sin confirmar]` **Umbral del faltante automático: 1 cajón**
(`GP2.parametro['faltante_cajones_umbral'] = 1` — "ibas a mandar y no había un cajón").
Ajustable por parámetro; si el usuario dice otro número, cambiar el parámetro y esta línea.

`[usuario 2026-08-30]` **La cobertura dice la causa raíz**: la pantalla muestra cuántos
días dura el stock actual con el consumo real (`v_consumo_componente`) y cuántos días
duraría la ubicación LLENA (5 cajones). Si **ni llena aguanta 30 días**
(`ubicacion_corta` en `v_faltante_estado`), la causa del faltante crónico es que **no
alcanza lo que entra en la ubicación** — eso es lo que el usuario quiere ver. Hoy da 15
componentes de Crudo y 12 de Procesado en esa condición `[dato: v_faltante_estado]`.

---

## 2f-bis. Por qué faltan artículos en GP2 (2026-08-31)

`[usuario 2026-08-31]` Explicación de la cobertura: *"el empleado que armó las bases
normalizadas se enfocó primero en los artículos que usan un FLEJE para la fabricación.
Las bombillas, como el caño es comprado y no tiene proceso productivo interno nuestro,
por eso no están"*. O sea: **GP2 tiene los artículos CON proceso de fleje propio (80
con demanda, 116.817 uni/mes); faltan los comprados/sin proceso interno (276 códigos
con demanda, 79.490 uni/mes — el 40% de las unidades)**. `[dato]` Los que más venden
de los faltantes: coladores 26/27 (9.469 + 6.294), corta queso 546 (5.655), rallador
321 (3.035), filtro bombilla 550 (2.532), bombillas 558/557, cepillos 555/535,
peladores/cucharas/espátulas, y 88 códigos con sufijo "E".
**Sufijo E = IMPORTADO** `[usuario 2026-08-31]`: *"no vas a tener intervención desde
GP2"* — llegan terminados de afuera, sin proceso propio, así que esos 88 códigos
quedan FUERA del alcance de GP2 (no se construyen rutas ni recetas; solo existen en
la Est Madre por la demanda). El backlog se achica en capas `[dato 2026-08-31]`:
276 faltantes → −88 importados (E) → −45 ya cubiertos por el circuito **Prov. Art.
Terminado** (comprados terminados; el módulo AT ya los controla — ej. **los coladores
son de López José**, prov AT con 10 coladores activos `[usuario]`: 26, 27, 29, 110,
111, 112, 824, 825, 828, 830) → **backlog real: 143 artículos, 18.584 uni/mes** que sí
necesitan cadena en GP2. Se van incorporando de a uno con el usuario, empezando por
las bombillas (2f). Regla que deja esto: un artículo "faltante" primero se chequea
contra Articulos x Prov AT — si es comprado terminado, su lugar es el circuito AT,
no una ruta productiva.

## 2f. Bombillas 557/558 + Filtro 550 — cadena CONSTRUIDA (2026-08-31)

`[usuario 2026-08-31]` Los artículos **557 (Bombilla Resorte Chata)**, **558 (Bombilla
Resorte Tradicional)** y **550 (Filtro para Bombilla)** ya están completos en GP2
(Est Madre: 1.040 / 2.123 / 2.532 uni/mes). Primer caso de artículo con **dos fuentes**
(fabricado y comprado) en GP2.

### 557/558: el cuerpo armado tiene DOBLE ORIGEN (GRJ6 = chata, GRJ5 = tradicional)
- **(a) FABRICADO**: **un mismo caño + un resorte** (ambos comprados; componentes
  BOM12 "Caño Inox 140 mm" y BOM8 "Resorte para Bombilla", Sector Bombilla) van a
  **Martín Cornejo** (tallerista id 6), que arma y entrega en el **Sector Garage** de
  Cervantes. Dicho textual: *"el caño es el mismo, Martín le da un golpe diferente a
  cada caño"*. **(b) COMPRADO**: el mismo cuerpo armado se le compra a **Cimarrón**
  (`componente.proveedor` de GRJ5/GRJ6), que **también entrega en el garage**. Las dos
  variantes convergen ahí.
- *"Ya NO va con tapa de aluminio; hoy solo es caño+resorte"* `[usuario]` — nada de
  tapita / limpia bombilla / cartón del despiece viejo del vecino.
- **Cimarrón es proveedor habitual**: le compramos **de manera fija los artículos 654,
  658 y 659** `[usuario]` (siguen sin construir en GP2; Est Madre 568/150/86 uni/mes).
- Del garage → **Oscar = Gentile Norberto** (tallerista id 8, alias "Oscar"): recibe el
  cuerpo + el **pliego adhesivado** y hace el **SKIN, que ES el packaging**. Entrega
  557/558 terminados en **Virgilio**.
- **El pliego lo produce BLIST-PACK SA** `[usuario 2026-08-31, vía lista de precios]`:
  cod isis 3227, lista 2026-08-07 **por pliego** $147,97 ARS. Bombillas **de a 25 por
  pliego** → cantidad 1/25 = **0,04** en la receta (~$5,92 por bombilla)
  `[usuario, 25 posiciones a confirmar]`. TRAMPA de roles: **"Blist-Pack" ya existía
  como TALLERISTA id 13** (así figura en el vecino entregando GRJ5/GRJ6) y ahora además
  es **proveedor de insumo "Blist-Pack SA"** — misma empresa, DOS roles, NO se fusionan.
- **El envasado de Gentile se cobra POR UNIDAD**: $69 ARS/uni "Skin Bombillas" (lista
  2026-07-20, referencia isis **557/558/654** — o sea el 654 de Cimarrón TAMBIÉN lleva
  este envasado cuando se construya). Modelado en la tabla nueva
  **`GP2.precio_tallerista`** (tallerista_id + componente de salida del paso) y
  `v_costo_componente` lo suma en los pasos de tallerista (CTE `talx`, mismo patrón que
  `precio_servicio_pieza`; pasos de tallerista sin precio siguen a costo 0).
- **Recetas**: 557 = GRJ6 ×1 + PLIEGO557 ×0,04; 558 = GRJ5 ×1 + PLIEGO558 ×0,04.
  **BOM**: GRJ6 = BOM12 ×1 + BOM8 ×1; GRJ5 ídem (mismo caño, mismo resorte).
  **Rutas** (ids 609–616, patrón "Insumo X -> Art"): fabricada = insumos → Martín (sale
  GRJ) → Gentile (sale terminado) → Virgilio; comprada = insumo GRJ (Cimarrón) →
  Gentile → Virgilio; pliego = insumo → Gentile → Virgilio.
  Caja del vecino: N°2 (A8) de a 24 (`componente_caja_id`; la caja NO está en la
  receta — la receta es la que dictó el usuario).

### 550 Filtro para Bombilla: DOS variantes, hoy lo hace iJupa
1. **IJUPA (tallerista id 10) lo hace ENTERO**: solo le mandamos caja y cartón → 550
   terminado → Virgilio. **Regla explícita del usuario: aunque funcione como prov AT,
   SE MODELA Y MUESTRA COMO TALLERISTA.**
2. **FILTROS ×2 y PRECINTOS ×2** por unidad (componentes nuevos BOM13/BOM14, Sector
   Bombilla) **comprados a CIMARRÓN** → entrega en Cervantes y **se guardan en el
   Sector Garage** (*"no sé si tienen sector, no creo"* — el garage es su lugar; sector
   lógico = Bombilla, ubicación física = Garage) → van a iJupa con caja y cartón.
- **Cartón 550 = posición CCG6B** (vecino), consumido **÷25 como los pliegos** (0,04
  por unidad) `[deducido de la verificación pedida por el usuario, a confirmar]`.
  **Caja N°22 (A9) de a 36** `[dato: Uni_x_Articulo_x_Caja + est_madre uxb; el Despiece
  viejo dice 12 — presentación vieja/display]`. Receta: BOM13 ×2 + BOM14 ×2 +
  CCG6B ×0,04 + A9 ×1/36. Rutas patrón "Insumo X -> Art 550 (IJUPA)".
- **Los talleristas del 550 en el vecino (Garcia/Poly) están DESACTUALIZADOS**: hoy es
  iJupa. `[usuario]`

### Verificación (2026-08-31, v_consumo_demanda / v_consumo_componente / oc_bundle)
GRJ6 = 1.040 y GRJ5 = 2.123 **sin duplicar** entre las dos variantes de origen (el walk
deduplica por UNION); caño BOM12 = resorte BOM8 = **3.163**; pliegos = **41,6 / 84,9**
y cartón 550 = **101,3** (÷25); filtros y precintos = **5.064**; caja A9 = 70,3. Costos:
GRJ5/GRJ6 = 2 USD (caño+resorte placeholder), pliego $147,97/pliego, 557/558 Terminado
servicios $69 (envasado Gentile). Los 3 artículos aparecen en OC (BOM13/14 → Cimarrón,
pliegos → Blist-Pack SA) y en v_valor_pedido; Faltantes no los lista porque ese módulo
sólo mira Crudo/Procesado (por diseño, 2e).

### Pendientes de esta cadena
- **Caño BOM12 y resorte BOM8 sin proveedor ni precio real** (placeholder 1 USD):
  ¿a quién se compran? (¿también Cimarrón?). BOM12 además sin kg ni uni_x_cajon.
- Filtros/precintos/cartón CCG6B con placeholder 1 USD (Cimarrón/cartonero sin lista).
- Las **25 posiciones** del pliego y el **÷25 del cartón CCG6B** a confirmar.
- **654/658/659** (Cimarrón) sin construir; el 654 lleva el envasado de Gentile.

## 2g. Corta Queso 546 — construido (2026-08-31)

`[usuario 2026-08-31]` Lo hace **Lucho** (tallerista id 5). Se le manda: el **bastidor
importado C13** (posición en Sector Procesado; **ya trae el cilindro** — dicho: *"el
cilindro ya no se usa más"*, PB1 quedó `estado_compra='discontinuo'`), el **mango PC10**
y el **capuchón PA18** (elegidos por el usuario entre los Pat Bet Plast), más cartón
CCC4 y Caja N°1 (12 por caja, dato del vecino). Entrega el 546 terminado en Virgilio.
**OJO: NO es como el 119/574** (dicho textual: "119 y 809 NO SON COMO 546") — esos
llevan mango de alambre propio hecho de fleje; el 546 es todo comprado + armado.
Migración `articulo_546_corta_queso`: componentes, inventario, receta, 5 rutas
(patrón "Insumo X -> Art"), precios placeholder. Verificado: consumo fluye exacto
(C13 y CCC4 = 5.655/mes, sin duplicar).
**Resuelto (mismo día, "Avanza" del usuario)**: PB1 se sacó también de las recetas y
rutas del 574, 119 y 809 (migración `pb1_discontinuado_fuera_de_recetas_y_rutas`);
quedó sin referencias ni consumo, discontinuo, con su inventario en 0 como historia.

**Regla nueva del motor de costos** `[dato]` (migración
`costo_componente_comprado_fuera_de_sector_insumo`): también es "comprado" el
componente que tiene precio cargado y NUNCA es salida de un paso productivo — su costo
es su precio, viva en el sector que viva (el caso C13: comprado pero con posición en SP;
antes daba costo $0).

## 2h. 119 y 809 discontinuados: ahora se importan (2026-08-31)

`[usuario 2026-08-31]` *"119 y 809 son discontinuos, ahora se importan"* — los corta
quesos de mango de alambre ya no se fabrican acá; entran como importados (la familia
del sufijo E; en la Est Madre existe 809E con 1.095 uni/mes — cuál código E reemplaza
al 119 queda por confirmar si hace falta). Modelado: columna nueva
`articulo.discontinuado` (true para ambos; primer caso en GP2). Sus rutas y recetas
quedan como historia — sin fila en Est Madre no generan consumo, verificado. **El 574 también** `[usuario 2026-08-31, "574 discontinuo"]`: la familia entera de
corta quesos de mango de alambre (119, 574, 809) quedó discontinuada. OJO: el 574 SÍ
tenía demanda en Est Madre (936/mes), así que esto obligó a una regla nueva del motor
(migración `consumo_excluye_articulos_discontinuados`): **un artículo discontinuado no
genera demanda aunque la Est Madre lo proyecte**. Verificado: el mango de alambre A9
(id 84) quedó sin consumo — y de paso, A9 existe TRES veces (parte, Fleje 75 y Caja
N°22): otra prueba de que los joins van por id, nunca por código.
**Pendiente**: el 101 (Abrelatas) sigue sin fila en Est Madre y sin respuesta —
¿también discontinuado/importado?

## 2i-ter. Módulo "Recepciones · Checklist Pagos" (2026-09-02)

`[usuario 2026-09-02]` *"Hace un módulo que reciba todas las recepciones de los insumos o de
los talleristas... aquí tengo un checklist de las facturas que tiene que cargar el sector
de pagos al sistema. Después vemos qué información le agregamos, mínima tienen que estar
los ítems que reciben y las cantidades, con el cod de prov y el cod de isis de cada item"*.
Pantalla nueva `Compras/Recepciones_GP2.html` alimentada por la vista
`GP2.v_recepcion_unificada` (UNION de `recepcion_insumo` + `entrega_prov_at`). Cada línea
trae `cod_prov` (código ISIS del proveedor: viene de `proveedor_insumo.cod_prov` para
insumos y de `proveedor_at.cod_prov` para talleristas — nuevo campo agregado a
`proveedor_insumo`, se llena a demanda) y `cod_isis` (código del componente/artículo).
Filtros: origen (Insumo/Tallerista/Todo), con/sin factura, rango de fechas, buscador
libre. KPIs con conteos y botón imprimir. Enlace en el menú, grupo Insumos, como secundario
(los 2 principales del grupo son y siguen siendo Órdenes de Compra + Recepción Insumos).
El sector Pagos usa esta pantalla como checklist antes de cargar las facturas al sistema.

## 2i-bis-800. Aclaración: la pinza chica 800 NO se importa (2026-09-02)

`[usuario 2026-09-02]` *"800 no la importa chef. es la misma que 560 pero de chef. ya lo
hablamos y ya te contesté esto"*. El artículo 800 es la **versión Chef** de la pinza chica
(el 560 es la versión Loeke); ambos comparten cuerpo N7, remache CV14 y proceso completo
(fabricación en Cervantes → Pedernera croma todo entero → Carlos Aguirre envasa y entrega
en Virgilio). NO hay componente "800_importado" ni proveedor Chef en la cadena de armado —
Chef es solo el cliente al que se le vende esa versión. **Cero cambios estructurales para
el 800**: sigue con las 4 rutas actuales (201 cuerpo, 458 remache CV14, 428 cartón O5A,
533 caja A8) todas rematando en Carlos Aguirre → virgilio, cruzando con Pedernera.

## 2i. Pinza Chica 560 (y 800): Pedernera croma + envasa + entrega (2026-09-02)

`[usuario 2026-09-02]` *"el proceso del 560 es largo, pero lo importante es que su
fabricación entera se hace en Cervantes y cuando ya está listo para cromar, se le manda a
Pedernera (el dueño es Carlos Aguirre) para que lo crome y él mismo (Carlos Aguirre) lo
envasa y entrega en Virgilio"* + *"este artículo se arma entero en crudo y se manda a
cromar entero"* + *"no existe V, V14 niquelado"*. **Clave**: Pedernera (proveedor de
servicio) y Carlos Aguirre (tallerista) son la MISMA persona / mismo taller — Cervantes le
manda el 560 crudo entero, él croma **todo junto** (cuerpo + remache + lo que lleve
adentro), envasa y lo entrega en Virgilio como 560 terminado.

`[dato 2026-09-04: GP2.tallerista.ubicacion_stock_id, GP2.ubicacion]` Por eso en la base el
tallerista Carlos Aguirre (9) **no tiene ubicación propia**: su stock vive en la ubicación 18
«Pedernera / Carlos Aguirre» (tipo `proveedor_servicio`, ref Pedernera 6), vía
`tallerista.ubicacion_stock_id = 18`. Es el único tallerista con ese override, y es la razón
de que `ubic_de('tallerista', 9)` mire primero ese campo (ver `GP2_MAPA.md`). Si algún día
Carlos Aguirre pasa a tener depósito aparte, se le pone `ubicacion_stock_id = null` y se le
crea su ubicación `tallerista/9`: nada más cambia.

**Consecuencia estructural**: el remache "V14 niquelado" NO existe como pieza aparte. Solo
existe CV14 (crudo). Todo lo que hoy se veía como "cromar el remache aparte" era ruido de
modelado. **Aplicado**:
- Componente V14 (id 283) BORRADO. articulo_componente 445 (560) y 461 (800): componente_id
  283 → 525 (CV14).
- Ruta 457 (art 560): se sacó el paso `proveedor_servicio` que "cromaba" el remache (era
  Guazzaroni CV14→V14) y quedó: `ingreso CV14 → tallerista Carlos Aguirre → 560 → virgilio`.
  El cromado del cuerpo+remache YA está en la ruta 200 (N7 → Pedernera → Carlos Aguirre →
  virgilio).
- Ruta 458 (art 800): mismo criterio, `insumo V14` cambió a `insumo CV14`.
- Precio CV14 = $4,4487 ARS (Excel `A_Costos_VIGENTES` hoja Costos, columna Remaches del
  560). Proveedor: Bella Vista (mismo que el resto de los remaches acá).

**Cruce Pedernera / Carlos Aguirre — artículos que él entrega en Virgilio**
`[usuario 2026-09-02: "pedernera/carlos aguirre... 544/802/580/560/700"]`:
- **544, 802, 580, 560**: ya correctos. Cadena típica: `Alex Escalante arma el GRJ10/10A/N7
  crudo → Pedernera Ilario croma → Carlos Aguirre envasa → virgilio`. Prov 544 en 4 rutas,
  802 en 4, 580 en 5, 560 en 4 — todas cruzan bien.
- **700 (Sacacorchos Cimarrón)**: NO cruza así hoy — hoy figura Jade (G2→B8) + Danica Garcia
  como entrega. Falta confirmación del usuario para reasignar el cromado y entrega a
  Pedernera + Carlos Aguirre y aclarar si el código de salida del cromado sigue siendo B8 o
  pasa a ser una sola pieza como en los otros (entrada = salida). **Pendiente**.

**Regla derivada** `[deducido]`: cuando un artículo se ensambla entero en crudo y va
completo al cromado, el cromado del remache/tornillo NO se modela como paso separado — va
con el cuerpo. Un paso `proveedor_servicio X→Xniquelado` en la ruta del remache es
sospechoso: casi siempre sobra.

## 2i-bis. Pedernera / Carlos Aguirre: 1 depósito, 2 códigos ISIS (2026-09-02)

`[usuario 2026-09-02]` *"me entrega Carlos Aguirre pero debe descontar stock de Pedernera"*
+ *"a Pedernera se le manda en función del stock que tenemos nosotros en sector procesado,
pero a Carlos Aguirre hay que mandarle para un mes de estadística madre... no tienen las
mismas reglas"* + *"es medio lo mismo, porque se entrega a la misma persona"* + *"pedernera
y carlos aguirre son dos prov diferentes para ISIS"*. **Regla capital**:

- **Stock físico unificado**. Pedernera (taller) y Carlos Aguirre (dueño / persona que firma
  el remito) son el mismo depósito. Al entregar cajas en Virgilio, la pieza se descuenta de
  ahí. Migración `unificar_pedernera_carlos_aguirre_ubi_stock`: se agregó
  `tallerista.ubicacion_stock_id` (nullable, FK a ubicacion); Carlos Aguirre (id 9) apunta
  a ubi 18 (Pedernera). El inventario de la ubi 29 se consolidó en ubi 18 (sumando
  cantidades, tomando el máximo de mínimos y máximos por componente), y la ubi 29 fue
  borrada. Ubi 18 renombrada "Pedernera / Carlos Aguirre".
- **Toda contraparte tiene UNA ubicación de stock** `[dato 2026-09-05, db/verificar.sql regla A]`:
  PS, talleristas activos y Prov AT activos resuelven por `ubic_de(tipo, id)`; sin esa fila,
  `crear_envio_ps` / `crear_envio_prov_at` explotan ("No hay ubicación para…"). Pasó con AJ
  Adhesivos (04/09) y con Rec Color, Daniel, Esther y Tierra Nativa SA (05/09): el botón "nuevo
  pintor" (`alta_proveedor_servicio`) creaba el PS sin ubicación. Desde el 2026-09-05 la RPC la
  crea en la misma transacción ("Prov. Serv. <nombre>") y se crearon las 4 que faltaban (51–54).
  Los sectores 12 Terminado y 13 Alambre no tienen ubicación a propósito (Terminado vive en
  Virgilio; el 13 es la pregunta 21).
- **El espejo de Virgilio no reintenta** `[dato 2026-09-05]`: lo que no puede cruzar queda en
  `virgilio_espejo_pend` con el motivo y ahí se queda. Los "artículo sin equivalente en GP2"
  (13 códigos al 05/09: 535, 584E, 590E, 590ES, 760, 207, 599, 727E, 877E, 943, 948, 817, 823)
  son datos que faltan cargar (pregunta 8); un motivo `error: …` es un bug y hay que reponer la
  entrega a mano con `recepcion_virgilio(jsonb)` (se hizo con la entrega 2308: Carlos, 160 cajas
  del 510 del 04/09, que había fallado porque Carlos Aguirre todavía no tenía ubicación).
  `db/verificar.sql` regla O avisa si vuelve a pasar.
- **Los totales de control cambiaron de puerta** `[dato 2026-09-05, auditor de costos]`:
  `v_valor_stock` / `v_valor_pedido` no existen más (04/09); el stock valorizado y el "Máximo
  por sector" salen de `valorizacion_bundle()`, que **excluye terminados**. Los $8,6 M / $678 M
  de referencia del 31/08 los incluían: no son comparables de frente con el número de hoy.
- **"Sector de insumo" tiene UNA definición** `[dato 2026-09-05]`: `sector.es_insumo`
  (5,6,7,8,9,10,11). La OC, los máximos y — desde el 05/09 — también `v_costo_componente` la
  leen de ahí (antes la vista tenía dos arrays escritos a mano sin el 9 Garage; hoy da lo mismo
  fila por fila, pero era una segunda fuente de verdad).
- **`recalcular_minimos` sí pisa la carga original** `[dato 2026-09-05]`: las 697 filas con
  `minimo_origen` null (Excel) se recalculan cuando el consumo es > 0; sólo respeta consumo
  0/desconocido. El comentario de la columna decía lo contrario y se corrigió.
- **Tres ubicaciones con `meses_minimo > meses_stock`** `[dato 2026-09-05]`: Sector Crudo (2 >
  1), Sector Procesado (2 > 1) y Sector Bombilla (4 > 3). En Bombilla eso hace mínimo > máximo
  por aritmética en sus 10 componentes con consumo (pregunta 27).
- **`FLEJE90_BRUTO` entra a la OC con sugerido 0** `[dato 2026-09-05]`: llega por la rama del
  proveedor (Altrak está en `proveedor_insumo`), pero nada consume el bruto — el consumo está en
  `IC3` (150 uni/mes) e `IC3V` (15): la demanda del alambre habría que derivarla de IC3 + IC3V +
  merma de corte (pregunta 21).
- **Un sector de insumo puede tener piezas FABRICADAS** `[dato 2026-09-05]`: 11 componentes de
  sectores `es_insumo` no tienen proveedor porque se hacen por ruta y llevan
  `estado_compra = 'fabricacion'` (resortes `C9`, `D14`, `I2`, `I3`; clavo `D9`; `V18D`, `V4`; y
  los armados de garage `GRJ1`, `GRJ7`, `GRJ10`, `GRJ10A`). Esa marca es la que los saca de la OC
  y del costo "comprado" (`v_costo_componente` los costea por ruta): no es un dato que falte.
  El único artículo activo sin Est Madre es el **071** (Bowls): sus partes no tienen demanda ni
  máximo automático (pregunta 8, ítem 18).
- **Reglas de reposición distintas por componente en esa misma ubi** `[deducido, pendiente
  de implementar]`: los crudos/cromados (N7, GRJ10, GRJ10A, cuerpos p/cromar) se reponen en
  kg según lo que Cervantes tiene en Sector Procesado; los insumos de envasado (cartones
  G3C, O5A, C1A, G7A, P4A, I2A + cajas A8, A2, A4, A5, A11) se reponen en uni según 1 mes
  de est madre del artículo terminado. La ubicación es una, la regla por fila.
- **Facturación ISIS separada**. Aunque el depósito es uno, en ISIS son 2 proveedores:
  Pedernera Ilario cod_prov 701 (factura el cromado como servicio) y Carlos Aguirre
  cod_prov 4306 (factura la mano de obra del tallerista). Ambos catálogos conviven en la BD
  (`proveedor_servicio` y `tallerista`) y la separación NO se toca.
- **Frontend**: `gp2-motor.js` (v20260902a) al armar el bundle usa
  `tall[X].ubi_stock` para redirigir `UB["tall:" + X]` a la ubi compartida cuando
  corresponde. Todo lo demás (pantallas de Envíos a Talleristas, Envíos a Proveedores,
  Stock, etc.) no cambia — ambas puertas llegan al mismo stock.
- **Deuda residual** `[dato]`: la ubi 18 tiene cantidades negativas históricas por descuentos
  mal aplicados antes de la unificación: A2 (-51), A4 (-63), C1A (-612), P4A (-1512),
  GRJ10 (-2124). Falta decidir con el usuario si se blanquean a 0 con un movimiento de
  ajuste (para no perder trazabilidad) o si primero se investiga el desfase.
- **Pendiente**: aplicar el mismo criterio al **700** (hoy Jade + Danica Garcia) si el
  usuario confirma que también lo entrega Carlos Aguirre.

## 2c-quindecies. Costos cargados con datos reales del Excel `A_Costos_VIGENTES.xlsx` (2026-09-01)

`[usuario 2026-09-01, sesión en vivo]` "vamos con los costos". Se cargaron los precios reales
del **506** y **11 bombillas** desde el Excel oficial (planilla que el usuario mantiene, no
inventar valores). El agente `gp2-cargador-excel` está para cargas grandes con el mismo
protocolo. **Regla capital**: el usuario NO responde de memoria valores de plata — TODO se
verifica contra el Excel (`/root/.claude/uploads/.../A_Costos_VIGENTES.xlsx` o el que aporte)
y contra `public."Lista de Precios "`, `public."Bombillas"`, `public."Talleristas"`,
`public."Cajas "`, `public." Cartones"` en el vecino. Si no está en el Excel, se le pregunta y
si dice "buscalo vos", se busca — no se inventa ni se asume.

### Convenciones descubiertas para MODELAR pliegos con skin en GP2 (todos los productos que se blistereann)

**El proceso real** (Loeke lo hace igual para 506 y para las bombillas Mate):
1. **Talleres Gráficos Pol** (prov 2147) imprime la **cartulina** y la vende en **paquetes
   de 100 pliegos** con la impresión específica del articulo (uno por SKU).
2. Cervantes **manda a AJ - Adhesivos Termoactivos** (prov 697) mínimo 2 paquetes; AJ pega el
   **skin** (adhesivo termoactivo) sobre cada pliego y devuelve.
3. El **pliego con skin** va a **Gentile Norberto** (prov 3709, tallerista_id=8) con las
   piezas del garage; Gentile envasa y entrega en Virgilio.

**Cómo se modela en GP2** (mismo patrón para todos):
- `CART506` / `CART_MATE` / etc. — **componente "paquete"** (sector cartón=10,
  `unidad_medida='paquete'`), precio en pesos por PAQUETE (ej. $77.700 el 506, $78.600 la
  línea Mate). Stock se lleva en paquetes.
- `V3A` (Skin 506) / `PLIEGO557`, `PLIEGO558`, `PLIEGO654`, etc. — **componente "pliego"**
  (sector cartón=10, `unidad_medida='pliego'`), precio en pesos por PLIEGO **ya adhesivado**
  = precio Pol/100 pliegos + precio AJ/pliego (ej. $917/pliego para 506 = $777+$140; $915
  para bombillas = $786+$129). Stock se lleva en pliegos.
- **Ruta de trazabilidad** `CART_XXX → PLIEGO_XXX (via AJ)` — solo para OC/auditoría, no
  calcula costo (el precio del pliego con skin va directo como `precio_proveedor`).
- **Ruta insumo del articulo terminado**: consume el pliego con skin, con
  `cantidad = 1/N` donde N es el rendimiento del pliego (12 para el 506, **16 para las
  bombillas Mate**). El cartón crudo NO entra en la ruta del articulo — se estropea la
  trazabilidad al pretender que el articulo consume paquetes.
- **Precio del adhesivado por medida** en `precio_servicio_pieza(AJ, pliego, precio)` para
  trazabilidad — el motor no lo suma porque el pliego ya viene con precio directo, pero deja
  registro de la tarifa AJ por pliego (útil para OC y auditorías).

**Medidas y precios AJ 2026-06-17** (fila 225-227 LP, precio POR PLIEGO):
- 56 x 41 mm = **$140** (Uña 506)
- 56 x 38 mm = $134,28
- 47 x 43 mm = **$129** (Bombillas)

### Costo del 506 (Uña) cargado completo

`[usuario 2026-09-01, aprobado paso a paso]`

| Concepto | Componente/Servicio | $ | Cantidad | Aporte al 506 |
|---|---|---|---|---|
| Cartulina Pol | CART506 (paquete 100 pliegos) | $77.700/paq | (via V3A) | — |
| Pliego c/skin | **V3A** (Skin 506) $917/pliego | (agrupa $777+$140) | 1/12 | **$76,42** |
| Uña armada | Alex/Martin arma GRJ7 (A10 pintado o C10 zincado + V9 remache) | — | 1 | ~$260 |
| Envasado | **Gentile** (tallerista) | $70/uni | 1 | **$70** |
| Caja | A11 Caja N°29 $166,86 | (dentro caja) | 1/12 | $13,90 |

**Total 506: $420,88** (era $274,46 antes de esta carga). PLIEGO506 fue creado y luego
**fusionado en V3A por normalización** — V3A es el código nativo y ya existía.

### Costo de 10 bombillas (5 modelos × 2 códigos LK/Chef) cargado completo

`[usuario 2026-09-01, aprobado paso a paso]`

**Los 5 modelos físicos** (con doble código LK/Chef — el Chef NO se stockea; se descuenta del stock LK):

| Modelo físico | LK | Chef | Fabricación | Costo total |
|---|---|---|---|---|
| Resorte Chata | 557 | 762 | LK fabrica: BOM12 caño+BOM8 resorte, Martin arma GRJ6 | **$401,54** |
| Resorte Trad | 558 | 763 | LK fabrica: idem, arma GRJ5 | **$401,54** |
| Autolimpiante Inox | 654 | 769 | Compra a **Cimarron** (GRJ4 = $1.578) | **$1.715,10** |
| Plana Ancha Metalizada | 658 | 758 | Compra a Cimarron (GRJ15 = $1.035) | **$1.172,10** |
| Pico de Loro | 659 | 759 | Compra a Cimarron (GRJ14 = $2.005) | **$2.142,10** |

**Componentes comunes** (para todas las bombillas Mate):
- **Cartulina** en paquete `CART_MATE` = $78.600 (100 pliegos) — Pol prov 2147
- **PLIEGO xxx c/Skin** = $915/pliego = $786 (Pol/100) + $129 (AJ 47x43 mm) — uno por SKU
- **Rendimiento**: 16 uni por pliego (⚠️ contradicción histórica: la fórmula del cartón usaba
  /12 en versiones viejas; el usuario aclaró **es /16**)
- **Caja A8 (Caja N°2)** $261,82 / **24 uni** por caja → $10,91/uni (todas las bombillas usan la misma caja)
- **Envasado Gentile** $69/uni (fila 233 LP, cod ISIS "557/558/654" pero aplica a los 10)

**Componentes de fabricación LK (para 557/558/762/763)**:
- **BOM12 Caño Inox 140mm**: **$12,48 USD/kg × kg_x_uni=0,0095** (9,5 grs) — prov **3327 Metalurgica Giser**
- **BOM8 Resorte Bombilla Niquelado**: **$35,80 ARS/uni fijo** — prov **4466 Grudzien Claudia Laura**
- **Martin Cornejo** (prov 3805, tallerista_id=6) arma GRJ5/GRJ6 = **$47,25/uni**

**Componentes comprados a Cimarron** (para 654/658/659):
- Los 3 componentes en Sector Garage (GRJ4, GRJ14, GRJ15) ya existían, se les cargó
  `precio_proveedor` con `cod_prov='Cimarron'`. **Cimarron entrega en Garage** (mismo lugar
  para todos los modelos).

**Costo del 550** (Filtro Para Bombillas, modelo distinto de las Mate):
- **Precintos Omega** (prov 4444 "4 Zurdos") $38 c/u × **2 por uni** = $76
- **Filtro s/Envasar** (prov 4444) $13,25 c/u × 2 por uni = $26,50
- **Envasado García** (prov 4317) $51/uni
- **Cartón C** $89/uni (NO es el pliego Mate — es otro tipo de cartón)
- **Caja A8 (Caja N°2)** $146,42 / **36 uni** (rinde 36, no 24) = $4,07
- **Total 550: ~$247** aprox

### Reglas duras para próximas cargas de costos

- **Precio directo del componente `precio_proveedor(componente_id, precio, moneda,
  precio_por_kg)`** — SÍ pasa al costo del articulo.
- **Motor tiene bug residual con GRJ fabricados sin `precio_proveedor`**: los articulos que
  usan un GRJ armado internamente (no comprado) muestran `faltan_precios=1` aunque el costo
  esté bien calculado por la ruta. Ignorar el flag, mirar el `total_pesos`.
- **`estado_compra='fabricacion'`** en un componente del sector "comprado por defecto"
  (fleje/cartón/plástico/etc.) lo excluye del CTE `comprado` y lo trata como fabricado por su
  ruta. Cuidado con esto — si además tiene `precio_proveedor`, el motor lo vuelve a tratar
  como comprado.
- **NO INVENTAR CÓDIGOS DE PROVEEDOR**: el `cod_prov` en `precio_proveedor` es el que aparece
  en `public."Lista de Precios "` col2 ("Cod Prov"). El nombre a veces no está en
  `public."Proveedores"` (razón social vacía) — el usuario lo dice cuando corresponde.
- **Convención doble código LK/Chef**: cuando un modelo físico tiene 2 códigos (uno por
  marca), **stock solo LK**; los articulos Chef se crean para reportes de venta pero SIN
  inventario. Consumo se suma en aplicación.
- **Al `precio_tallerista` no le apunten `articulo_id`** (no existe la columna). Se apunta
  al **componente Terminado** por su `codigo` (igual al código del articulo pero en sector 12).
- **Cada articulo tiene su propio cartón/pliego** aunque comparta costo y proveedor con otro
  (la impresión es específica del SKU). `[usuario 2026-09-01, correctivo]`: el cartón 550
  cuesta lo mismo que el del 501 ($89 de Pol) pero son **componentes distintos** en GP2 —
  CCG6B "Cartón 550" y D2A "Cartón 501". No reusar componentes de cartón/pliego entre
  articulos distintos, aunque el precio y el proveedor sean idénticos.

## 3. Reglas del negocio ya incorporadas

- **Algunos talleristas pueden entregar partes EN CERVANTES** (además de Virgilio):
  **Martín Cornejo, ALEX ESCALANTE e IJUPA.** `[usuario 2026-08-31, corregido]` El dato
  original decía Carlos Aguirre, pero el usuario lo corrigió: *"Carlos es el papá de
  Alex, por eso le erré"* — son familia y por eso el cruce de nombres. Normalizado en
  `GP2.tallerista.entrega_cervantes` (true para ids 6, 2 y 10 — migraciones
  `talleristas_que_entregan_en_cervantes` + `entrega_cervantes_correccion_alex_no_carlos`).
  `[2026-09-04]` Esa columna se **borró** (ningún código la leía); el dato queda acá: los que
  entregan en Cervantes son Martin Cornejo (6), Alex Escalante (2) e IJUPA (10).
  Cierra con las rutas: Alex arma los GRJ (ej. Batidor Pera del 544) y los entrega en el
  Sector Garage de Cervantes. OJO: `Recepcion Cervantes.html` del programa VIEJO tiene
  hardcodeado ARTICULOS_EMPRESA con CARLOS y MARTIN — puede venir de la misma confusión
  padre/hijo; revisar cuando se arme el flujo GP2. Ninguna pantalla GP2 lo usa todavía.

- **La Est Madre manda hacia atrás.** El máximo de flejes e insumos NO sale de
  relevamiento físico: sale de la Est Madre explotada por receta y rutas × los meses de
  stock del rubro. Se recalcula sola. `[usuario, regla 2026-08-29]`
- **Virgilio no se analiza.** Existe sólo para medir a los talleristas; no se construye
  módulo de despacho ni de venta, y las 1.292 entregas históricas **no se cargan**.
  `[usuario]`
- **Producción arranca de cero.** No se cuelga el espejo de la producción vieja: las
  tablets pasan a la app GP2 y la historia queda en la casa del vecino. `[usuario]`
- **El motor de inventario vive en la base**, no en el JS: la app inserta filas crudas en
  `GP2.movimiento` y los triggers calculan y aplican el delta. `[arquitectura]`
- **Las entregas se cuentan en CAJAS, no en unidades.** `[usuario 2026-08-30]` Dicho
  textual: "todas las entregas de talleristas son en cajas". Confirmado en el codigo para
  Prov. Art. Terminado: el modulo de carga titula la columna **Cajas**
  (`Prov Art Terminado/Entregas/EntregasAT.html:44`) y arma el detalle como `Cajas: N`
  (`EntregasAT.js:189`) antes de guardarlo en la columna `"Cantidad"` de
  `public."Entregas Prov AT"`. `[dato]` **El nombre de la columna enganya**: dice
  "Cantidad" pero son cajas. Las unidades se derivan (cajas x uni_x_caja), nunca al reves.
  Pendiente de confirmar si vale igual para las entregas de talleristas propiamente
  dichas (`Entregas Tallerista Virgilio`), que no se revisaron. `[deducido]`
- **Un mismo codigo de articulo puede tener dos uni_x_caja**, y no es un dato faltante:
  son dos presentaciones (DISPLAY vs SUELTO, tipico 12 contra 36) o directamente dos
  articulos distintos que comparten numero entre LK y CH (ej. el 26 es Pinza de Fideos en
  CH y Colador N°8 en LK). `[dato: public."Uni_x_Articulo_x_Caja", 18 codigos]`
  `Articulos x Prov AT.marca` esta **null en las 86 filas**, asi que hoy no hay forma de
  saber cual corresponde: se muestran los dos valores y no se calculan las unidades.
- **Un cambio de proceso toca TODAS las tablas normalizadas**, en orden: componente →
  inventario → recetas → rutas → alias. Parchar una sola rompe el trazado. `[CLAUDE.md]`

---

## 3b. Acceso a la app (login)

`[usuario 2026-08-29]` **El login de Google está APAGADO, momentáneamente.** Razón: la
página ya es privada y es difícil que alguien la encuentre, así que por ahora se prefiere
entrar suelto, sin la validación de Gmail.

Se maneja con un interruptor de una línea: `GP2_AUTH_ON` en `auth-guard.js`
(`false` = suelto, `true` = con login + whitelist). Para volver a prenderlo hay que poner
`true` **y bumpear el `?v=` de auth-guard.js en los HTML**, si no las tablets siguen con el
archivo cacheado.

`[importante, no confundir]` El login siempre fue una tranquera de **pantalla**, no una
barrera de datos: la clave anon viaja en el HTML de cada página, así que quien tuviera la
URL siempre pudo llamar a las RPCs. Lo que realmente protege la base es la **RLS** (anon
sólo lee) + que **toda escritura pase por RPCs SECURITY DEFINER** que validan. Eso no se
tocó y sigue igual con el login prendido o apagado.

## 3c. Cómo se abre la app (ventana propia, no pestaña)

`[usuario 2026-08-29]` **GP2 tiene que verse como una aplicación, igual que Producción
Virgilio** — sin la barra de direcciones ni el botón de actualizar arriba. El usuario notó
la diferencia entre las dos apps y pidió emparejarlas.

`[dato]` La causa era simple: Virgilio siempre fue una **PWA** (tiene `manifest.json` con
`display: standalone` + service worker), y GP2 no tenía ninguno de los dos en la raíz. El
único `manifest.json` del repo estaba en `Produccion/RegistroApp/` y sólo aplica a ese
submódulo, así que Chrome trataba a GP2 como una página web común.

Arreglado en v1.30.0 con dos mecanismos que se complementan:

1. **`--app=` en `gp-launcher.ps1`**: Chrome abre en ventana propia apenas se hace doble
   clic en el `.bat`. No hace falta instalar nada, funciona para todos de una.
2. **PWA de verdad** (`manifest.json` + `sw.js` + `pwa.js` + `icons/` en la raíz): Chrome
   ofrece "Instalar", y GP2 queda con ícono propio en el escritorio y en el menú Inicio.

`[importante]` El `sw.js` **no cachea nada** y está así a propósito. Cachear el HTML dejaría
tablets pegadas a una versión vieja, que es justo lo que el sistema de tokens `?v=...` viene
evitando. El service worker existe sólo porque Chrome lo exige para poder instalar.

`[trampa]` El launcher elige el primer puerto libre entre 5501 y 5507. Para Chrome **cada
puerto es un origen distinto**, así que una app instalada desde 5501 no es la misma que una
instalada desde 5503. Con `--app=` da igual, pero si se instala a mano conviene hacerlo
siempre con el mismo puerto.

## 4. Trampas conocidas (cosas que ya nos mordieron)

- **Los nombres colisionan entre las dos casas.** El fleje "A1" del vecino no es la pieza
  "A1" de GP2. Nunca matchear por código sin mirar el sector. `[2026-08-29]`
- **El código de componente NO identifica una pieza; el `id` sí.** En GP2 hay **33 códigos
  repetidos** (A1, A10, A11, C9, D1, F2…): el "A1" del Sector Fleje y el "A1" del Sector
  Caja son piezas distintas. Lo único es el par **(código, sector)** — verificado: 0
  repetidos dentro de un mismo sector, y desde 2026-08-30 hay un índice único
  `uq_componente_codigo_sector` que lo garantiza.
  Consecuencia práctica: **el programa trabaja por `id` y está bien**; el riesgo aparece
  sólo cuando se hace un `update ... where codigo = 'X'` o se copian datos del vecino
  matcheando por código. En esos casos **siempre filtrar también por sector**.
  `[dato 2026-08-30; surgió al marcar los resortes que se fabrican, donde C9 es a la vez
  un Fleje N° 4 y el Resorte U Crom]`
- **Una persona = varios roles.** Pettofrezza es tallerista, proveedor AT y ahora
  proveedor de insumo. Maspoli es tallerista y proveedor AT. Buscar en las cuatro tablas
  antes de dar de alta a alguien "nuevo".
- **El mismo nombre escrito distinto.** "Pettofrezza Rafael" (tallerista) vs "Pettofrezza"
  (prov AT); el alias "RAFAEL" ya apunta al tallerista. Ver `GP2.contraparte_alias`.
- **La data del vecino es vieja.** Sirve para llenar huecos, pero no conoce los cambios
  recientes (no tiene a Kollplast ni a Pettofrezza como inyectores). Usarla como punto de
  partida, nunca como verdad final.
- **El ledger arrancó de cero hoy**, así que los bugs de saldo no se notan mirando la
  pantalla: hay que probarlos con movimientos de prueba y rollback.

---

## 5. Cómo se alimenta esto

Cada mensaje del usuario que traiga conocimiento del negocio —cómo funciona algo, por qué
se decidió así, quién hace qué, qué conviene y qué no— se agrega acá **en el mismo commit
del trabajo**, con su origen `[usuario]` y la fecha. No se espera a que "cierre un tema".

Si un dato nuevo **contradice** uno viejo: se corrige la línea y se anota que se corrigió
(como pasó con Becker). La contradicción es información: casi siempre significa que algo
cambió en la realidad, y el módulo que dependa de ese dato hay que revisarlo.

## 5. Pantallas que se achicaron (2026-08-30): fuera Punto de Stock, Verificación vive en Despiece

`[usuario 2026-08-30]` "Punto de stock no tiene sentido, podríamos borrarlo. Los dos de
verificación... que funcione mergeado todo en despiece x artículo."

- **Punto de Stock (`Stocks General/PuntoStock_GP2.html`) se BORRÓ.** La pantalla no
  aportaba: el punto de stock ya se ve donde se usa (OC sugiere por consumo, Orden de
  Producción por demanda). OJO: **la lógica en la BD queda viva** — `v_punto_stock` y
  `punto_stock_bundle` NO se tocaron porque `recalcular_maximos_insumos` (los máximos
  derivados de la Est Madre) depende de ese modelo.
- **Verificación Integridad + Verificación Madres se FUSIONARON dentro de
  `Despiece x Articulo/Despiece_GP2.html` (v2.0.0).** Motivo: las tres pantallas hablaban
  del MISMO artículo desde tres lugares (qué lleva / cómo se fabrica / qué dato falta).
  Ahora al elegir un artículo se ve junto: (1) la receta, con FALTA marcado en kg_x_uni /
  uni_x_cajon; (2) sus rutas trazadas con los botones Confirmar / Revisar después /
  Reportar problema / Marcar resuelto — **mismas RPCs `ruta_confirmar`/`ruta_reportar`/
  `ruta_resolver` y misma firma de deduplicación** (`F:<fleje>|tp:actor|...`), así que lo
  ya confirmado en la pantalla vieja sigue valiendo; (3) los avisos del artículo
  (componentes suyos sin datos maestros). Arriba, resumen global (rutas sin confirmar,
  problemas, componentes sin kg/uxc en sectores con peso) + filtro "solo artículos con
  pendientes", para no perder la vista de conjunto de las pantallas viejas.
- RPC nueva **`despiece_verif_bundle()`** (un solo viaje: sect + art/receta con flags de
  faltantes + rutas + confirmadas/problemas + resumen madres). `despiece_bundle`,
  `verificacion_bundle` y `verifmadres_bundle` quedan en la BD pero sin pantalla que las
  llame.
- `[dato 2026-08-30: GP2.ruta]` Al cruzar rutas con despieces: **3 rutas sin artículo**
  (ids 35 "Fleje 8 -> Art ", 151 "Fleje 49 -> Art ", 152 "Fleje 50 -> Art ") — en la
  pantalla nueva aparecen agrupadas como "— sin artículo —" para que no se pierdan.
  Además **55 componentes sin kg_x_uni y 72 sin uni_x_cajon** (sobre 301 de sectores con
  peso) y **12 artículos** tienen faltantes en su propia receta.

## 5b. Se disolvió "Herramientas GP2" (2026-08-30): el grupo del menú desaparece

`[usuario 2026-08-30]` **Decisión aprobada por el usuario** tras el análisis de las 3
pantallas del grupo: cada una va adonde se usa, y el grupo del menú se borra (v1.14.0).

- **"Programa de Stock" (`Programa/Programa.html`) SE CONSERVA entera**: es el simulador
  what-if por lote (artículo × N unidades → cadena completa + kg de fleje por matriz, RPC
  `programa_bundle`) y no duplica a nadie. Solo se **mudó el botón** al grupo Despiece con
  su nombre real: **"¿Qué necesito para producir?"**, marcado secundario.
- **"Faltantes" (`Faltantes/Faltantes.html`) se BORRÓ.** Sus acciones ya vivían mejor en
  OC (comprar) y Orden de Producción (producir), y calculaba con criterio contradictorio
  (mínimos estáticos vs. la demanda de la Est Madre). **Lo ÚNICO propio — el PRORRATEO del
  faltante por artículo — vive ahora en Despiece x Artículo (v2.1.0)**: al abrir un
  artículo, el bloque "Faltantes del artículo" muestra por componente y ubicación el
  mínimo, el stock, el faltante global y cuánto es atribuible a ESE artículo, con la
  matemática portada 1:1 del JS viejo (reparto ÷N cuando varios talleristas comparten el
  armado y firma anti-duplicado para que las rutas alternativas no cuenten doble los kg
  de fleje). La RPC **`faltantes_bundle` queda en la BD y ahora la llama el Despiece**,
  lazy, recién al abrir un artículo. `[dato: test_despiece_verif verifica los números a mano]`
- **"Registrar Movimiento" (`Movimientos/Registrar_Movimiento.html`) se BORRÓ.** 7 de sus
  9 tarjetas duplicaban pantallas dedicadas y escribían **tipos de movimiento distintos**
  (partían el ledger). Los 2 flujos propios — **Ajuste +/- y Armado en fábrica** — y la
  vista de últimos 50 movimientos pasaron a **Stocks general (v1.1.0)**, construidos por
  `gp2-motor.js` (funciones nuevas `GP2M.ajuste` / `GP2M.armadoFabrica` /
  `GP2M.ubicacionesDeComp` / `GP2M.artsFabricaDirecto`, portadas 1:1). El payload de
  `registrar_movimientos` NO cambió de contrato (test_stock_general lo fija exacto).
- `[dato 2026-08-30]` **Trampa de CSS descubierta al medir**: `font:18px inherit` es
  INVÁLIDO en Chromium (la declaración entera se descarta y el campo queda en la letra
  por defecto). Los campos de Despiece/Programa/StockGeneral pasaron a
  `font-size:18px;font-family:inherit` — si una pantalla usa el shorthand `font: Npx
  inherit`, la letra grande NO está aplicando aunque el CSS lo diga.

## 4a. El remito de REMACHES viene en UNIDADES, no en kg (2026-09-03)

- `[usuario 2026-09-03]` **"La recepción de remaches quiero que sea en unidades, no en kg."**
  El proveedor entrega los remaches contados, no pesados: el remito dice unidades. La
  pantalla pedía kg y obligaba al operario a traducir de cabeza.
- `[dato]` **Los pesos por remache SÍ están cargados** — esto tumbó mi primer diagnóstico.
  31 de los 34 componentes del sector 8 tienen `kg_x_uni`, de **0,00011** (CV13 Plaquita
  3 en 1) a **0,036** (CV17 Cremallera Doble Aleta). CV1 Remache Espiral = **0,00035 kg**.
  Los 3 sin peso son **tornillos** (V18D, CV18D Tornillo Sacafuente, V20 Tornillo Corta
  Queso) y están en **0 recepciones y 0 stock**.
- `[dato]` **Por qué parecía que no había pesos:** `fmt()` de `RecepcionInsumos_GP2.html`
  corta en 2 decimales, así que 0,00035 se renderizaba como **"1 uni = 0 kg"**. Era un bug
  de formato, no un dato faltante. Se agregó `fmtKgUni()` (6 decimales) para los carteles
  de kg por unidad. **Trampa general: antes de concluir "el dato no está cargado" porque la
  pantalla muestra 0, mirar el formateador.** El usuario lo cazó preguntando "¿no tenés los
  pesos por remache?".
- `[deducido, aplicado — CORREGIDO el mismo día, ver 4d]` Se cargaba en uni pero se
  **guardaba en kg**, convirtiendo con `kg_x_uni`. Lo justifiqué diciendo que "el stock del
  remache trabaja en kg". **Era falso**: la unidad canónica del inventario la fija
  `componente.unidad_medida`, que en todo el sector 8 es `unidad`. O sea que el kg era un
  rodeo — se convertía a kg al guardar y el trigger lo volvía a dividir para el inventario.
  Desde 4d se guarda en unidades.

## 4b. Maspoli es FASONERO: patrón tallerista + insumo a la vez (2026-09-03)

- `[usuario 2026-09-03]` **"A Maspoli le entregamos las virolas para que nos entregue los
  mangos de madera."** Le mandamos un componente nuestro y él devuelve un producto que
  incorpora ese componente **más material propio (la madera)** por el que nos cobra.
- `[dato]` **GP2 ya lo modela híbrido, no hay que construir nada:** `GP2.tallerista` id 7
  "Maspoli SRL" (paso de ruta que transforma la virola **D13** en el mango **PC12 / PEP7 /
  PEP8**) + `GP2.proveedor_insumo` "Máspoli SRL" (rubro Sector Plástico) sobre el componente
  mango, que es lo que se paga. El envío lo trata como tallerista (la virola queda de stock
  en él = **WIP**, no es un bug) y la entrega descuenta la virola
  (`SECTOR_SC_POR_PROV={'Maspoli':'D13'}` en `Facturas/EntregaProveedoresCervantes.html` y
  `Talleristas/Control Tall/ControlTall.js`).
- `[deducido]` **REGLA GENERAL: un fasonero que aporta material propio NO es un PS.** El PS
  (Guazzaroni niquela, Pedernera croma) hace servicio sobre material 100% nuestro y solo
  cobra mano de obra — no tiene dónde anotar la compra del material. El fasonero se modela
  **tallerista-en-ruta** (para rastrear lo que le mandaste) **+ insumo-en-componente** (para
  pagar lo que aporta).
- `[dato, PENDIENTE DE CONFIRMAR CON EL USUARIO]` **Riesgo de pagar la virola dos veces.**
  Las recetas de 508 y 518 listan **D13 (virola) Y el mango juntos**, y el mango ya contiene
  la virola. El consumo está blindado (`v_consumo_demanda` corta el walk, ver §3b), pero
  falta verificar que `v_costo_componente` no cuente la virola dos veces. Y el precio del
  mango (**$683,72**, `precio_proveedor` id 16/17/18, cod_prov 2339, etiquetado "Mango
  Sacafuente Barnizado (madera)") **debe ser solo madera+barniz+armado, no el mango con la
  virola puesta** — hay que cotejarlo contra la lista de Maspoli.
- `[dato]` **El nombre está escrito de 3 formas:** "Maspoli SRL" (tallerista), "Máspoli SRL"
  con tilde (proveedor_insumo), "Maspoli" (código operativo). Hoy la reconciliación aguanta
  porque va por id, pero cualquier módulo que matchee por string se parte en silencio.

## 4c. Las bombillas GRJ: rutas, make-or-buy y el paso fijo de Gentile (2026-09-03)

- `[dato]` **Los 6 GRJ de bombilla son sector 9 (Sector Garage), proveedor Cimarron.** Que
  estén en Garage es correcto — GRJ *es* Garaje, no es el sector del material (regla §1-bis:
  el sector es la zona física). El artículo terminado es familia `Bombillas`.

| GRJ | Descripción | Artículos finales | Origen del costo |
|---|---|---|---|
| GRJ4 | Bomb AutoLimp Inox | 654, 769 | precio ($1.578) |
| GRJ5 | Bombilla Resorte Trad 558 | 558, 763 | ruta (se fabrica) |
| GRJ6 | Bombilla Resorte Chata 557 | 557, 762 | ruta (se fabrica) |
| GRJ13 | Bowls 330ml | **ninguno** | — |
| GRJ14 | Bombilla Pico de Loro | 659, 759 | precio ($2.005) |
| GRJ15 | Bombilla Plana Ancha | 658, 758 | precio ($1.035) |

- `[dato]` **El paso final de Gentile Norberto cuesta $137,10 y es igual para los 10
  artículos.** Todos siguen `artículo = su GRJ + $137,10`, sin una sola excepción: 654/769 =
  1578+137,10 · 658/758 = 1035+137,10 · 659/759 = 2005+137,10 · 557/558/762/763 =
  265,04+137,10. Sirve como control: si un artículo de bombilla se sale de ese patrón, algo
  se rompió.
- `[dato]` **GRJ5 y GRJ6 son MAKE-OR-BUY: tienen 3 rutas cada uno por artículo** — comprarlas
  a Cimarron, o fabricarlas desde **BOM12** (Caño Inox 140 mm, Metalúrgica Giser) o **BOM8**
  (Resorte para Bombilla, Grudzien Claudia Laura), armadas por **Martin Cornejo**. Las otras
  siempre pasan por Gentile al final.
- `[dato, IMPORTANTE — desmiente una sospecha]` **Varias rutas para un mismo componente NO
  inflan el costo.** `v_costo_componente` elige UNA ruta, no las suma: GRJ5 = BOM8 ($35,80) +
  BOM12 ($181,99) + servicio ($47,25) = **$265,04** exacto, y toma la ruta de fabricación, no
  el precio de compra. Antes de acusar a un artículo de contar dos veces por tener rutas
  paralelas, **hacer la cuenta**: acá la sospecha era infundada.
- `[dato]` **El costo llega al artículo por la RUTA, no por `articulo_componente`.** GRJ4,
  GRJ14 y GRJ15 no figuran en ninguna receta y aun así su costo llega (654 = GRJ4 + 137,10).
  La receta faltante rompe consumo/faltantes/OC, **no** el costo. Solo GRJ5→558 y GRJ6→557
  tienen fila de receta, con cantidad 1.
- `[dato]` **GRJ5 y GRJ6 no tienen precio de Cimarron cargado** aunque tienen ruta de compra
  (rutas 615 y 611). Por eso 557/558/762/763 salen con `faltan_precios=1` y los otros 6
  artículos en 0. Sin ese precio no se puede comparar fabricar contra comprar.
- `[dato, aplicado 2026-09-03]` **GRJ4, GRJ13, GRJ14 y GRJ15 no tenían NINGUNA fila en
  `inventario`**, así que Faltantes y la OC no los veían en planta — el mismo agujero de D9
  (§ historial 2026-09-02). Migración `grj_filas_inventario_en_sector_garage`: fila en la
  ubicación 9 (Sector Garage) con cantidad 0 y mínimo/máximo en null, espejando a GRJ5/GRJ6.
  **El mínimo queda en null a propósito**: sale del consumo, el consumo sale de la Est Madre
  y esos artículos la tienen en null, y `recalcular_minimos` no pisa una fila con consumo 0 o
  desconocido. Se llena solo cuando se cargue la Est Madre.
- `[deducido, SIN CONFIRMAR]` **Los artículos parecen ir de a pares 5xx/7xx** (557↔762,
  558↔763, 654↔769, 658↔758, 659↔759) y **solo el de la izquierda tiene Est Madre** (557 =
  1040, 558 = 2123; los otros 8 en null). Huele al patrón "clon" ya visto en 104 = clon del
  581: la demanda viviría en el hermano y el 7xx sería la otra marca. **Falta que el usuario
  lo confirme** — si no es así, hay que cargar la Est Madre de los 8 o la OC nunca los pide.
- `[dato, PENDIENTE DE DECISIÓN]` **GRJ13 (Bowls 330ml) está huérfano**: 0 pasos de ruta, 0
  recetas, 0 precio, costo $0 (ahora sí tiene fila de inventario en 0). O se le construye la
  cadena entera, o se da de baja. No es una bombilla.

## 4d. Insumo → tallerista → Virgilio: los tres eventos de una ruta de armado (2026-09-03)

- `[usuario]` **"Se compra el insumo, después se va al tallerista, y después el tallerista
  entrega el artículo terminado en Virgilio."** Esa es la lectura correcta de las rutas del
  tipo `Insumo CARTxxx -> Art xxx`: son **tres eventos reales**, uno por paso, y por eso van
  tres pasos y no uno solo. El paso `insumo` es la COMPRA (el insumo entra a la casa), el
  paso `tallerista` es el armado, el paso `virgilio` es la entrega del terminado.
- `[dato]` **El paso `insumo` no transforma: entra y sale la misma pieza** (`comp_entrada_id
  = comp_salida_id`), igual que el paso `ingreso` de un fleje. Lo que transforma es el paso
  `tallerista`: entra el insumo, sale el artículo. Un insumo no cambia de código porque lo
  compres — cambia cuando alguien lo trabaja.
- `[dato, arreglado 2026-09-03]` **339 rutas tenían la cadena cortada** justo ahí: el paso
  `insumo` con `comp_salida_id` en NULL y el paso `tallerista` con `comp_entrada_id` en NULL.
  El insumo entraba y desaparecía; el artículo salía de la nada. No era un error de negocio
  sino carga incompleta: las dos columnas de enganche vacías. Emparejamiento perfecto
  (339 y 339, cada ruta con un solo insumo, el tallerista siempre inmediatamente después),
  así que se completó con un UPDATE sin ninguna ambigüedad.
- `[dato]` **Es el hallazgo #15 de `AUDITORIA_GP2_2026-08-31.md`** ("los 88 terminados
  pierden todo su material"), que había bajado de 366 a 339 pasos sin resolverse. Efecto
  medido del arreglo: cambiaron **exactamente los 98 terminados y nada más** — 0 componentes
  de crudo/procesado/fleje, 0 máximos y 0 mínimos recalculados, ninguno bajó de costo y
  ninguno quedó en $0. Todo el delta es **material**; servicios y mano de obra sin tocar.
  Ejemplos: 557/558 $402,14 → $1.796,75 · 546 $1.456,56 → $3.028,34 · 550 $249,77 → $651,84.
- `[dato]` **No hay doble conteo.** `v_costo_componente` solo camina aristas con
  `comp_entrada_id <> comp_salida_id` y tipo `matriz|proveedor_servicio|tallerista`: el paso
  `insumo` (que ahora tiene entrada = salida) queda fuera del walk por definición, y el
  material entra una sola vez, por el paso del tallerista.
- `[dato]` **Cerrar la cadena NO hace que el costo del terminado sea igual al de la receta.**
  El motor sigue costeando por ruta (ver § 4c: "el costo llega al artículo por la RUTA, no
  por `articulo_componente`"), así que donde la receta y la ruta no coinciden el número sigue
  corto — 557/558 quedan en $1.796,75 contra ~$3.076 por receta, porque el GRJ de bombilla no
  está en la receta. **El arreglo de fondo sigue pendiente**: costear el terminado desde la
  receta, que es la que tiene las cantidades.
- `[dato]` **Estado después del arreglo: 0 eslabones vacíos y 0 saltos duros en las 619
  rutas.** Cualquier paso cuyo `comp_salida` no sea el `comp_entrada` del siguiente es, desde
  ahora, un bug — vale como invariante para un test.

## 4e. "Movimiento" y "Tránsito" son DOS cosas distintas (renombre 2026-09-03)

- `[usuario]` **"En vez de que se llame Sector Tránsito en las tablas, que se llame Sector
  Movimiento, al que pasa de matriz en matriz. Sector Tránsito es el de los proveedores de
  servicio."** El nombre correcto es el que ya usaba el programa; el que estaba mal era el
  de la tabla.
- **Los dos, sin confundirlos nunca más:**
  - **Sector Movimiento** (sector id 3, 43 componentes) = la pieza a medio hacer que va **de
    matriz en matriz** (los códigos "tras M#", tipo `E6-M132`). Es WIP: no tiene mín/máx ni
    `kg_x_uni`/`uni_x_cajon` (ver § 2c-undecies). Lo muestra `StockMovimiento_GP2.html`,
    que trae el `sector_id: 3` hardcodeado.
  - **Stock Tránsito PS** = la pieza que un **proveedor de servicio** ya entregó y espera
    hasta mandarse **al PS siguiente**. No es un sector: sale de la RPC
    `stock_transito_ps_bundle` y lo muestra `StockTransitoPS_GP2.html`.
- `[dato, aplicado 2026-09-03]` Se renombró **`sector.nombre`** ('Sector Transito' →
  'Sector Movimiento'), **`sector.tipo`** ('transito' → 'movimiento') y el
  **`ubicacion.nombre`** de la ubicación 3. Se cambió el `tipo` y no solo el nombre a
  propósito: dejarlo en `'transito'` mantenía viva justamente la confusión que el usuario
  quiere eliminar, porque el `tipo` es lo que viaja en los bundles.
- `[dato]` **El `tipo` lo leen exactamente DOS lugares** (verificado con barrido del repo, y
  cero funciones o vistas de la BD dependen de él): `Programa/Programa.html` en el
  `SECT2CLS` (la clase CSS del nodo) y `OrdenProduccion/OrdenProduccion.js` en
  `resolverDestinos`, que sigue la cadena hasta el sector crudo/procesado final. Los dos
  quedaron actualizados en el mismo commit. **Si mañana aparece un tercer consumidor del
  `tipo`, este es el lugar donde mirar.**
- **Trampa**: casi todas las demás menciones de "tránsito" en el repo (ControlPS,
  StocksGeneral, Verificación, Despiece) hablan del **`ST` del programa viejo**, que es el
  tránsito de PS y está bien nombrado. No tocarlas al buscar y reemplazar.

## 4f. La unidad de una recepción la manda `componente.unidad_medida`, no el rubro (2026-09-03)

- `[usuario 2026-09-03]` **"En el caso de Eduardo Pintos, Pat Bet Plast, Pettofrezza Rafael:
  cuando voy a cargar un remito que me tire por default unidades (kg borralo), y en el
  control que pueda poner los kg y con el kg por uni de cada componente me lo pase a uni"**
  + **"Y en el caso de Tornillos Suipacha lo mismo... (como en todos los de sector
  remaches)"**. Son dos cosas distintas y conviene no mezclarlas: **el remito viene en
  unidades** (el proveedor entrega piezas contadas) y **el control se hace con la balanza**
  (nadie cuenta 5.000 piezas). La balanza es una forma de CONTAR, no otra unidad.
- `[dato]` **El inventario de plásticos y remaches YA está en unidades.** `GP2.to_canonical`
  convierte todo movimiento a `componente.unidad_medida`, y los 37 plásticos y los 33
  remaches la tienen en `unidad`. Guardar la recepción en kg obligaba a un ida y vuelta
  (uni → kg al cargar, kg → uni en el trigger) que sólo agregaba error de redondeo: de ahí
  salían stocks como **10.099,999999999999988571** en CV1.
- `[dato]` **Los tornillos sin `kg_x_uni` eran IMPOSIBLES de recibir.** CV18D (Tornillos
  Suipacha), V18D y V20 no tienen peso por unidad, así que la pantalla los mandaba a kg y
  `to_canonical` cortaba con *"componente X sin kg_x_uni válido para kg→uni"*. Cargados en
  unidades entran derecho, sin necesitar el peso. **Pendiente del usuario: el kg por unidad
  de esos tres** — sin él, su control físico no se puede pesar y hay que contar a mano.
- `[deducido, aplicado]` Regla general para la recepción: **se carga y se guarda en la unidad
  canónica del componente**; el kg aparece sólo donde la balanza es la herramienta (el
  control), y ahí se divide por `kg_x_uni` para volver a unidades. En el código es un solo
  criterio, `cargaEnUni()` en `RecepcionInsumos_GP2.html`: sector 8 entero + sector 6 sólo
  para los 3 proveedores de piezas.
- `[dato]` **No es todo el sector 6.** `Trefilados Industriales` también es un plástico
  (PCP3 Clavo 505) y ese **sí se compra por kg** (último remito: 1.000 kg). Por eso la regla
  de plásticos es **por proveedor** y no por rubro. Si aparece un proveedor nuevo de piezas,
  hay que sumarlo a `PLAST_UNI`.
- `[dato]` `controlar_recepcion_kg` **no convierte nada**: pisa `recepcion_insumo.cantidad`
  (y el movimiento) con el número que recibe. El "kg" del nombre quedó del día que sólo
  servía a remaches. La pantalla le manda la cantidad ya expresada en la unidad de la
  recepción. Las recepciones viejas, que quedaron en kg, se siguen controlando en kg: cada
  fila decide por su propio `unidad`.
- `[dato]` Volvió a aparecer la trampa de 4a: el cartel *"1 uni = 0 kg"* del control era
  `fmt()` cortando en 3 decimales sobre 0,00035. **Todo cartel que muestre `kg_x_uni` va con
  6 decimales.**

## 4g. Las marcas son TRES, y una se llama igual que un formato (2026-09-03)

> **REVERTIDO EN PARTE 2026-09-08: la submarca LOKE YA NO VA.** `[usuario 2026-09-08, viendo los
> chips MARCA de Recepción de Cartones — LOEKE (51) / LOKE (7): "la marca loke no va. todo lo que
> esta en loke ponelo en marca loeke y dentro del formato loke"]`. Aplicado (DB-only): los **8
> cartones** que tenían `marca='LOKE'` (H1A, H1C, H2C, H4C, I2B, I3B, I42, K5D) pasaron a
> `marca='LOEKE'`, **conservando `carton_formato='LOKE'`**. Ahora quedan **dos marcas** (LOEKE 81,
> CHEF 41); el chip LOKE desaparece solo porque las marcas salen de los datos (ver más abajo).
> **El formato LOKE se queda** — lo comparten esos 8 más los 28 CHEF: la familia de pedido sigue
> siendo "formato LOKE", lo que cambió es que su marca ahora es LOEKE. Todo lo de abajo describe
> el modelo VIEJO de tres marcas; se conserva por la historia.

- `[usuario 2026-09-03]` **"Ciento cuatro es marca LOKE. No sé qué tan claro tenés qué es
  la marca LOKE, l-o-k-e. Es una submarca dentro de Loekemeyer."**
- **Las tres marcas** (`componente.marca`):
  - **LOEKE** = Loekemeyer, la marca principal.
  - **LOKE** = **submarca dentro de Loekemeyer**. No es un typo de LOEKE ni lo mismo.
  - **CHEF** = la otra marca.
- `[dato]` **Ojo con el choque de nombres: `LOKE` es también un `carton_formato`.** Son dos
  cosas distintas: el **formato** dice cómo se imprime el pliego (LOKE = 16 posiciones) y la
  **marca** dice de quién es el producto. Que el formato se llame igual que la submarca es
  histórico. **Al leer un dato, mirar siempre de qué columna sale**; una frase como "el 104
  es LOKE" puede querer decir cualquiera de las dos (de hecho el usuario la usó primero para
  el formato y después para la marca, en dos mensajes seguidos).
- `[dato, arreglado 2026-09-03]` **Una lista de marcas escrita a mano hacía desaparecer
  productos.** `RecepcionInsumos_GP2.html` tenía los chips de marca hardcodeados en LOEKE y
  CHEF: un cartón con marca LOKE no entraba en ningún chip y **no se podía recibir** — ni
  siquiera caía en "Sin marca", porque ese chip filtra por marca vacía. Ahora los chips se
  arman con las marcas que traen los datos. **Regla general: nada que sea una lista de
  valores del negocio (marcas, formatos, categorías) se escribe a mano en el JS** — el día
  que aparece uno nuevo, lo que hace la pantalla no es mostrarlo mal, es esconderlo.
- `[usuario 2026-09-03, confirmado]` **Los 7 cartones de formato LOKE que figuraban como
  LOEKE son en realidad de la submarca LOKE** (H1A, H1C, H2C, H4C, I2B, I3B, I42). Con el
  K5D del 104 son **8 códigos**, y ésa es la familia de pedido "formato LOKE · marca LOKE",
  separada de los **28 CHEF** que usan el mismo formato. Antes esos 7 se agrupaban con los
  cartones LOEKE de otros formatos, que es justo lo que el usuario quería evitar.
- **Cómo quedan las familias de pedido del cartón** (sin contar los 24 pliegos, que van
  aparte de a 100):

  | Formato | Marca | Categoría | Códigos |
  |---|---|---|---|
  | C | LOEKE | Pelapapas | 4 |
  | C | LOEKE | Sacacorchos *(comodín)* | 6 |
  | C | LOEKE | Abrelatas | 6 |
  | C | LOEKE | Resto | 16 |
  | LOKE | ~~LOKE~~ **LOEKE** *(era submarca LOKE hasta 2026-09-08)* | — | **8** |
  | LOKE | CHEF | — | 28 |
  | Huevo | LOEKE | — | 11 |
  | Huevo | CHEF | — | 2 |
  | 8 | LOEKE | — | 2 |
  | Bolsa | LOEKE / CHEF | — | 2 / 1 |

## 4h. La demanda sale de `GP2.est_madre`, NO de `articulo.estadistica_madre_uni_mes` (2026-09-03)

- `[usuario 2026-09-03]` **"El parámetro del consumo lo tenés que levantar de donde está la
  estadística madre, ¿por qué no lo tendrías internamente acá?"** Tenía razón, y me sacó de
  un diagnóstico equivocado.
- `[dato]` **Hay DOS lugares con la Est Madre y sólo uno manda.**
  - **`GP2.est_madre`** (`cod`, `proy_cajas_mes`, `uxb`, `proy_uni_mes`) — **ésta es la
    fuente**. Se sincroniza sola del programa viejo. `v_consumo_demanda` y `v_consumo_parte`
    leen `proy_uni_mes` de acá, matcheando el código sin ceros a la izquierda.
  - **`articulo.estadistica_madre_uni_mes`** — **no la usa nadie** para el consumo. Está
    cargada a mano y **difiere en los 77 artículos** donde las dos tienen valor, casi siempre
    redondeada hacia arriba (505: 30.000 contra 28.184 · 504: 10.000 contra 7.826 · 510:
    8.000 contra 6.352), pero no siempre (502: 6.000 contra 6.244 · 586: 6.996 contra 7.960).
- **Trampa, y me mordió**: mirar la columna del artículo y concluir "este artículo no tiene
  Est Madre". Los 12 que figuran en null ahí **sí tienen proyección en `est_madre`**. Antes
  de decir que un dato falta, buscar de dónde lo lee la vista que lo usa.
- `[dato, arreglado 2026-09-03]` **Lo que faltaba de verdad era la receta.** Ocho artículos
  de bombilla (654, 658, 659, 758, 759, 762, 763, 769) tenían **una sola parte**: su Pliego
  Ad. Sin el GRJ en la receta la demanda nunca llegaba a la bombilla, así que **GRJ4, GRJ14 y
  GRJ15 pedían cero** aunque son compra limpia y con precio de Cimarrón cargado. Qué GRJ va
  en cada uno lo dice la **ruta** del propio artículo, y la cantidad (1) sale del patrón de
  los dos hermanos que sí estaban cargados: 557 lleva GRJ6 x1 y 558 lleva GRJ5 x1.
  Resultado: GRJ4 pide 3.480 · GRJ15 1.616 · GRJ14 832, y GRJ5/GRJ6 suben al sumarles la
  demanda de sus gemelos CHEF (763 y 762).

## 4i. Un armado que se compra Y se fabrica se pide dos veces (2026-09-03)

- `[usuario 2026-09-03]` **"El costo es la suma del caño, más el resorte, más la mano de obra
  de Martín."** Vale para GRJ5 (Bombilla Resorte Tradicional) y GRJ6 (Chata).
- `[dato]` **El costo ya estaba bien armado**: BOM12 Caño Inox 140 mm $181,99 + BOM8 Resorte
  $35,80 + armado de Martín Cornejo $47,25 = **$265,04**, y `v_costo_componente` les pone
  `origen='ruta'`. La tarifa de Martín está en `precio_tallerista` desde el 2026-09-01.
- `[dato, arreglado]` **Lo que estaba mal era la compra.** Los dos figuraban como comprables
  (`estado_compra` null) con proveedor Cimarrón y **sin ningún precio**, así que la OC los
  pedía a $0 — 4.312 y 2.800 — **mientras sus partes se pedían por separado**: 10.668 de caño
  a Metalúrgica Giser y 7.968 de resorte a Grudzien, con un consumo de 3.556 que es
  exactamente 2.156 + 1.400, o sea GRJ5 + GRJ6. **La misma bombilla pedida dos veces.**
- **Regla general**: si el costo de una pieza sale por RUTA (se fabrica), no puede estar
  además como comprable. Un componente con `origen='ruta'` y `estado_compra` en null es la
  firma de este bug: mirá si sus partes ya se están pidiendo. Y al revés — `origen='precio'`
  es la marca de lo que sí se compra (GRJ4, GRJ14 y GRJ15, que sí tienen precio de Cimarrón).

## 4j. El pliego: a Pol sin adhesivar, AJ lo adhesiva (2026-09-03)

- `[usuario 2026-09-03]` **"A Pol se le compra sin adhesivar, AJ lo adhesiva."**
- **La cadena correcta**: `Pliego NNN` (se compra a Talleres Gráficos Pol) → **AJ Adhesivos**
  pone el skin → `Pliego Ad NNN` → entra al artículo. El adhesivado **se fabrica, no se
  compra**.
- `[dato]` **El precio del adhesivado ya traía el servicio adentro** y lo decía en el propio
  campo: *"Pliego 557 c/Skin ($786 Pol + $129 AJ)"*. Con eso la OC le pedía a Pol $915 por
  pliego, $129 de más, y el servicio de AJ no aparecía en ningún pedido. **Un precio que es
  la suma de dos proveedores es siempre la firma de una cadena sin modelar.**
- `[dato]` El molde bueno **ya existía para uno solo, el 506**: la ruta 632, **sin
  `articulo_id`**, con dos pasos — `ingreso` del pliego y `proveedor_servicio` (AJ) que sale
  al adhesivado. Ése es el patrón para cualquier transformación por servicio, y se replicó
  en los otros 11.
- **Trampa del consumo**: `v_consumo_demanda` sólo camina aristas de rutas **con artículo**,
  así que una ruta de transformación (sin artículo) **no baja la demanda**. El enganche va
  por **`componente_bom`**, que la vista sí camina. Las dos cosas hacen falta: el BOM para
  el consumo y la ruta para el costo.
- `[dato]` **Dos bugs de plata que aparecieron al mirar**: el `Pliego 506` tenía cargado
  **$77.700, que es el paquete de 100** — y la OC pide en pliegos, así que lo valuaba **100
  veces de más**; y la tarifa de AJ del 506 estaba **por posición** ($11,67 = $140/12) en vez
  de por pliego. **Al cargar un precio, mirar siempre en qué unidad pide la pantalla.**

## 4k. El par `CVxx` / `Vxx`: lo que se compra es el CRUDO, no el niquelado (2026-09-04)

**El código que empieza con `CV` es la pieza cruda "p/Niquelar"; el `V` sin C es la misma
pieza ya niquelada.** El niquelado no se compra: lo hace un proveedor de servicio
(Guazzaroni Patricio) en un paso de la ruta. O sea que la plata sale UNA sola vez, por el
crudo, y el niquelado entra como costo de servicio.

Las dos rutas que hoy existen con esa forma (`tipo_paso`: ingreso → proveedor_servicio →
tallerista) son idénticas:

| Crudo | Proveedor del crudo | Niquela | Niquelado | Arma | Artículos |
|---|---|---|---|---|---|
| `CV18D` Tornillo Sacafuente p/Niquelar | Tornillos Suipacha | Guazzaroni Patricio | `V18D` | Martin Cornejo | 508, 708 |
| `CV13` Rem Plaquita 3 en 1 p/Niquelar | Electrónica Mandelli | Guazzaroni Patricio | `V13` | Martin Cornejo | 043, 511 |

**Consecuencia para precios (regla):** el `precio_proveedor` va SIEMPRE colgado del `CV`
(lo que se factura), y el `V` va marcado `estado_compra='fabricacion'` para que la OC no
lo pida. `V18D` ya está así. **`V13` NO**: hoy tiene el precio ($15,37, lista Mandelli
12/02, "Oj. Hierro niquelado 3x6x5,5") colgado del niquelado y `CV13` quedó en cero —
está del lado equivocado del par. Pendiente de confirmar con el usuario si Mandelli
entrega crudo (el precio se muda a `CV13`) o ya niquelado (entonces sobra el paso de
Guazzaroni en las rutas 238 y 307).

**Y un precio pegado al componente equivocado:** la fila `precio_proveedor` id 66,
lista 21/08, producto **"Tornillo sacafuentes" $68,70**, está colgada de **`W8`
(Vástago Sacafuente Pizzero, de Imel)**. Un vástago no es un tornillo: ese precio
pinta ser el del `CV18D` de Suipacha, que es justamente el que figura sin precio.
Pendiente de confirmar antes de moverlo (si se mueve, `W8` queda sin precio y hay que
cargarle el del vástago).

### Comprables sin precio: cómo se cerraron (2026-09-04)

De los 6 que quedaban colgados el 03/09:

- **`IC3V`** (Fleje N° 90 LARGO) — *[usuario]* "3 va el mismo precio": lleva el mismo
  precio que `IC3` (US$ 1,715, lista fleje 3711, Ø 1.63 mm alambre galvanizado). Cargado.
- **`BOM10`** (Resorte Bicónico, Resortes Charcas) — *[usuario]* discontinuo.
  `estado_compra='discontinuo'`.
- **`ID7`** (Fleje N° 50, EstaMetal) — *[usuario]* discontinuo. `estado_compra='discontinuo'`.
  Además no lo usaba nadie (0 recetas, 0 rutas).
- **`CV18D`** — sí se compra: es el crudo de la tabla de arriba. Falta el precio.
- **`CV13`** — ídem, pendiente de la confirmación de Mandelli.
- **`CV16`** (Vástago Sacafuente 5.2 x 100 Rosca 41 p/Niquelar, Bella Vista) — huérfano
  puro: 0 recetas, 0 BOM, 0 pasos de ruta, 0 precios. *[usuario]* "508 lleva ese vástago",
  pero la receta del 508 hoy no tiene NINGÚN vástago (sí `PC12`, `V18D`, `V6`, `Z1A`,
  `Z2A`, `D13`, `G2C`, `A8`), mientras el 518 y el 708 llevan `W8` (Vástago Sacafuente
  Pizzero, de Imel). Pendiente saber si el 508 lleva `W8` o el `CV16` — si es `CV16`,
  hay que armarle también la ruta crudo → niquelado como las de arriba.

### Cerrado: los tres precios se acomodaron y el 508 recuperó su vástago (2026-09-04)

Con lo que contestó el usuario quedó resuelto todo lo que arriba figuraba como pendiente:

- **El $68,70 "Tornillo sacafuentes" era del `CV18D`** *[usuario]*. Se movió del `W8` al
  `CV18D`. Efecto: `CV18D` pasa de $0 a $68,70, `V18D` (que sale de ruta) hereda ese costo
  y el 508 sube de $1.836,03 a $1.904,73. `W8` queda **sin precio**: hay que pedirle a Imel
  el precio real del vástago pizzero.
- **Mandelli entrega el `CV13` CRUDO** *[usuario]*. El precio ($15,37) se movió del `V13`
  al `CV13`, y `V13` quedó `estado_compra='fabricacion'` como su gemelo `V18D`. Ahora el
  niquelado de Guazzaroni se suma de verdad: `V13` pasa de $15,37 a $15,65, y los artículos
  043 y 511 suben $0,29 cada uno. Antes ese servicio no se estaba cobrando en ningún lado.
- **El 508 es el 708 con otro cartón y otro SP** *[usuario 2026-09-04: "508=708 pero con
  cartón chef y otro sp usa"]*. Comparando las rutas de los dos artículos, son gemelas paso
  a paso (Fleje 16 → Pedernera, Fleje 17 → `Z1A`, Fleje 27 → Guazzaroni → Maspoli → `PC12`,
  `CV6`→`V6`, `CV18D`→`V18D`, caja, cartón) y la **única** diferencia real era que al 708 le
  colgaba la ruta "Insumo W8 → Art 708" y al 508 no. O sea: el 508 sí lleva vástago, y es el
  mismo `W8`. Se le agregó la fila de `articulo_componente` (cantidad 1) y la ruta
  "Insumo W8 → Art 508" espejo de la 228. El costo del 508 no se movió todavía porque `W8`
  está sin precio; sus `faltan_precios` pasaron de 1 a 3, que es la señal correcta.
- **`CV16` sigue sin dueño.** Como el vástago del 508 resultó ser el `W8`, el `CV16` (Bella
  Vista) no lo usa nadie: 0 recetas, 0 BOM, 0 rutas, 0 precios. Candidato a `discontinuo`,
  falta que el usuario lo confirme.

Los comprables sin precio bajaron de **6 a 2**, y los 2 que quedan son los dos vástagos:
`W8` (precio de Imel) y `CV16` (que probablemente ni exista más).

**Diferencia que quedó marcada, sin tocar:** el 508 y el 518 listan `D13` (Virola
Sacafuente Niq) en `articulo_componente`, pero `D13` es un intermedio de la ruta 95/92
(`ID8` → matriz → `D13B` → Guazzaroni → `D13` → Maspoli → `PC12`). El 708 NO lo lista. O
sobra en el 508/518 o falta en el 708; revisar antes de creerle al costo de esos tres.

## 4l. `D13` es la virola, y va DENTRO del mango: por eso no va suelta en la receta (2026-09-04)

`CV16` quedó **`discontinuo`** *[usuario 2026-09-04]*: era el último vástago sin dueño, y
con el 508 llevando `W8` ya no lo usa nadie.

**Qué es `D13`.** Es un eslabón de la cadena de la virola del sacafuente, no un insumo que
alguien compre ni que el tallerista reciba suelto:

```
ID8  Fleje N° 27 (Basconia, kg)
  → matriz          → D13B  Virola Sacafuente (cruda, sector 1)
  → Guazzaroni      → D13   Virola Sacafuente Niq (niquelada, sector 2)   $27,17
  → Máspoli SRL     → PC12  Mgo Sacafuente Articulado 4.25 mm  $710,89   (508, 564, 708)
                     PEP7  Mgo sacafuente pizzero             $710,89   (518)
  → tallerista      → el artículo
```

O sea: Máspoli recibe la virola ya niquelada y devuelve **el mango con la virola adentro**.
El costo del mango ($710,89) **ya contiene** los $27,17 de la virola.

**El que estaba incompleto era el 708, y NO había doble conteo** *[usuario 2026-09-04:
"falta en 708"]*. El 508 y el 518 listaban `D13` en `articulo_componente` y el 708 no; se
le agregó la fila al 708 (cantidad 1) y ahora los tres están iguales.

**Por qué no se movió ni un peso al agregarla** (medido, no supuesto): agregar y sacar la
fila deja el costo de los tres artículos idéntico — 508 $1.904,73, 518 $2.189,20, 708
$1.882,06 — y el consumo de `D13`/`D13B`/`ID8` clavado en 1.949 uni/mes con o sin ella.

**La regla que sale de ahí, y que conviene no olvidar:** `articulo_componente` es la
**lista de partes** del artículo (trazabilidad, "de qué está hecho"), NO la fórmula del
costo. Tanto `v_costo_componente` como `v_consumo_componente` caminan las **rutas**, y en
la ruta la virola aparece una sola vez porque `D13` se transforma en el mango. O sea que
listar un intermedio en la receta no lo cobra dos veces — pero tampoco lo agrega: si un
componente no está en ninguna ruta, no existe para el costo ni para la OC por más que
figure en la receta.

## 4m. Las tarifas de servicio que faltaban: 2 cargadas, 2 sin fuente (2026-09-04)

*[usuario 2026-09-04: "dale, cargá las tarifas que falten"]*. Barriendo **todos** los pasos
`proveedor_servicio` de las 633 rutas contra `precio_servicio_pieza` → `tarifa_servicio` →
`precio_servicio`, los huecos reales eran **cuatro**, no seis:

**Cargadas** (las dos tenían fuente documentada en la propia base, no se inventó nada):

- **`IC3V`** — Resortes Charcas, proceso `corte alambre`, **$9,50/u**. Es la misma lista
  (2026-08-05) y el mismo proceso que ya tenía el `IC3`; el `IC3V` es el LARGO, el que va
  directo a Virgilio. Cierra los artículos **034** ($646,73 → $656,23) y **867** ($677,32 →
  $686,82), los dos con `faltan_precios` en 0.
- **`V18D`** — Guazzaroni, proceso `niquelado`. La tarifa no se escribe en la pieza: vive en
  `GP2.tarifa_servicio` por proceso ($2.606/kg) y la pieza sólo declara **qué proceso** es,
  como las otras 20 piezas de Guazzaroni. **Todavía no resuelve**, y no es culpa de la
  tarifa: **ni el `V18D` ni el `CV18D` tienen `kg_x_uni`**, o sea que falta el **peso del
  tornillo sacafuente**. Ojo con el patrón: en los pares CV/V el peso es **el mismo** de los
  dos lados (`CV13`=`V13`=0,00011; `CV6`=`V6`=0,00215), así que alcanza con pesarlo una vez.

**Sin fuente, hacen falta del usuario** — el proveedor cobra **distinto por pieza**, así que
no hay una tarifa única que aplicar:

- **`Z22`** Llavero Pie — Hernández Julio, serigrafiado. Sus otras piezas están a $18 y $19.
- **`B12`** Llavero Pie Pint. — Jade, pintado. Sus otras piezas están a $127, $150 y $305.

Las dos son del artículo **499**, que es el peor de todos con 4 precios faltantes.

### Lo que NO era una tarifa faltante

`G4` y `M1` figuraban con `faltan_precios = 1` y **sus servicios están todos pagos**. El
conteo viene del CTE `bomx` de `v_costo_componente`, que mira **sólo el precio de compra**
del hijo del BOM: si el hijo es **fabricado**, no tiene precio de compra, y `bomx` lo cuenta
como faltante **y además no le suma el costo**. Afecta a `G4` (no cobra su `V3`, $6,49) y a
los `GRJ1`/`GRJ7` (no cobran su `V9`, $5,93); `M1`→`V18C` y `C12`→`BOM10` dan $0 igual
porque son discontinuos. Plata chica, pero es un agujero del motor y no un dato que falte:
queda como **idea 7241**.

**Comprables sin precio: 1** — el `W8` (Vástago Sacafuente Pizzero, Imel).

## 4n. La OC pide contra el MÁXIMO, no contra el consumo (auditoría 2026-09-04)

*[usuario 2026-09-04: pidió revisar el módulo de OC con un agente antes de usarlo]*. La
auditoría de plata encontró que **la fórmula cambió el 2026-09-03 y la documentación no**.
Verificado contra la función viva:

```sql
'sugerido', greatest(0, round(coalesce(maximo_ef,0) - coalesce(online,0) - pendiente_oc))
-- maximo_ef = inventario.maximo, y SOLO si es null cae a round(consumo * meses_stock)
```

`oc_bundle` además devuelve `sugerido_consumo` (la fórmula vieja) al lado, sin usarla.
Corregidos en el mismo commit `CLAUDE.md`, `REGLAS_OC_INSUMOS.md` y el §2e-bis de acá, que
afirmaba textual *"la OC pide por consumo × meses_stock − stock, así que nunca pedían de
más"* — hoy es falso y era la única garantía escrita.

**Lo bueno, medido y no supuesto:** el desastre que temía la auditoría **no está**. De los
**200** insumos comprables con máximo y consumo:

- **0** con `maximo_origen` NULL (el 56% sin origen ya se arregló),
- **1** sin máximo, y cae bien al consumo,
- **6** discrepan, y las 6 tienen `maximo_origen='fisico'` — o sea, es el lugar del estante,
  no un error.

| | máximo (lugar) | por consumo | diferencia |
|---|---|---|---|
| `A5` Caja N°6 | 9.400 | 42 | **+$4.676.567** |
| `A4` Caja N°10 | 4.000 | 252 | **+$2.126.653** |
| `A6` Caja N°7 | 2.375 | 498 | +$864.603 |
| `A1` Caja N°1 | 11.625 | 13.026 | −$343.988 |
| `A9` Caja N°22 | 17.000 | 26.286 | **−$1.931.488** |
| `W8` Vástago Pizzero | 726 | 5.476 | (sin precio) |

O sea: en cajas de poca rotación el lugar es enorme y la OC **llena el estante** ($7,6 M de
más entre A5, A4 y A6); en las de mucha rotación el lugar no alcanza y **compra menos de lo
que se consume** ($2,3 M de menos entre A1 y A9, y el `W8` pide 726 contra un consumo de
5.476/mes).

### DECIDIDO: la OC llena el lugar

*[usuario 2026-09-04, textual: "llena el lugar (máximo según norma de cada rubro)"]*. **El
sugerido llena el máximo, no cubre los meses de consumo.** O sea que la fórmula de hoy
(`maximo − stock − pendiente`) **está bien y se queda**, y las 6 discrepancias de arriba
**no son bugs**: son el estante, que es lo que manda. El `consumo × meses` queda donde
está, de respaldo para cuando el máximo está vacío.

Y hay un segundo tramo en la frase que no es lo mismo: **"según norma de cada rubro"**. El
máximo dice cuánto entra; la norma del rubro dice de a cuánto se puede pedir, y se aplica
**después**, redondeando para arriba — múltiplos y mínimos de cartón (`ajustarFamilia`),
paquetes de 100 en pliegos, el piso de las bolsas, los paquetes de 10 kg de Charcas. Las
dos reglas conviven en ese orden: primero el lugar, después el envase.

**La única consecuencia que hay que mirar**, medida: con esta regla queda **un solo**
componente cuyo lugar no alcanza para un mes de consumo — el **`W8`** (Vástago Sacafuente
Pizzero): entran **726** y se consumen **1.369/mes**, o sea **medio mes**. Todos los demás
aguantan un mes o más. Es un problema de estante, no de la OC: o se le agranda el lugar, o
se le compra más seguido. (Es el mismo `W8` que además está sin precio.)

### Lo demás que buscó la auditoría, medido: NO está pasando

- **`precio_por_kg` sobre una línea que se pide en kg** (rompería el rubro fleje, el más
  caro): hay **2** filas con el flag en toda la base y **ninguna** cae sobre un componente
  que se pida en kg. Es una trampa dormida, no un bug vivo — el día que alguien cargue un
  precio de fleje "por kg" (que es lo semánticamente correcto) se rompe.
- **La unidad `'paq'` de Charcas**, que ni `_aplicar_recepcion_a_oc` ni el CTE `pend`
  saben convertir: **0 OC abiertas**, así que hoy no hay nada mal guardado. Dormida también.
- **Precios sin moneda** (se valorizarían en USD por el default del backend y en ARS por el
  de la pantalla): **0**.
- **Doble pedido / pedir y fabricar a la vez**: sigue vacío.

### Dos cosas vivas que sí hay que decidir

- **`estado_compra='importado'` deja al componente FUERA de la OC** (`oc_bundle` filtra
  `estado_compra is null`). Son **5**, y **se compran igual, sólo que afuera**: `Z23A` Cuch
  China (consumo 11.388/mes), **`D1` Espiral Sacacorcho** (9.588/mes, US$ 0,24, a Tierra
  Nativa — es más de la mitad del costo del 581), `C13` Corta Queso (7.700/mes, US$ 0,68),
  `ID1` Fleje N° 28 (3.090/mes, US$ 3,16, Hermac) y `Z23B` Cuchilla Laser (2.294/mes).
  El campo mezcla dos preguntas distintas: *"¿se compra?"* y *"¿de dónde sale?"*. Lo que
  tiene que salir de la OC es lo que **no se compra** (`fabricacion`, `discontinuo`), no lo
  importado.
- **Las bolsas caen en 2 familias, no en 1**: son 3 códigos de formato `Bolsa` repartidos en
  dos marcas, así que el piso de 20.000 se cobra **dos veces (40.000 bolsas)**. Y el piso
  sigue **sin confirmar** desde el 03/09.

## 4o. Virgilio: qué se guarda allá, y por qué la OC hoy no lo ve (2026-09-04)

*[usuario 2026-09-04, textual: "Espiral es importado, no se pide en ocs pero hay insumos en
virgilio… Allá se guardan: flejes, cajas, insumos importados, bolsas plásticas (que hay que
mandarle a los prov de inyección), partes plásticas, etc"]*.

### DECIDIDO: los importados NO se piden por OC

El `D1` (Espiral Sacacorcho) es importado y **no va a la orden de compra**. O sea que
`oc_bundle` filtrando `estado_compra is null` **está bien** y el hallazgo del auditor sobre
los `'importado'` queda **cerrado, sin cambio**. Son 5 y quedan afuera a propósito: `Z23A`
Cuch China, `D1` Espiral, `C13` Corta Queso Bastidor, `ID1` Fleje N° 28, `Z23B` Cuchilla
Laser. El campo `estado_compra` sirve entonces para tres cosas distintas y las tres sacan
al componente de la OC: **`fabricacion`** (sale de una ruta), **`discontinuo`** (ya no se
usa) e **`importado`** (se compra, pero por otro circuito, no con una OC nuestra).

### Dónde vive el stock de Virgilio (corregido el mismo día — antes decía "no existe")

**Primero dije que no estaba cargado en ningún lado. Estaba mal**: miré `*_stock_planta`
e `Insumos_Ubicaciones` (que casi no tienen cantidades) y me salteé la tabla que la app
de Virgilio usa de verdad. El usuario mostró la pantalla **"Stock y Compras → Insumos"**
de Producción Virgilio (v12.78) con 127 insumos, 578 de historial y 7 categorías, y con
eso se encontró:

**La app de Producción Virgilio pega contra ESTA MISMA base** (`hrxfctzncixxqmpfhskv`,
lo dice su `supabase-config.js`), y su stock de insumos es un **libro de movimientos**:

```
public."Movimientos_Stock"  where deposito = 'insumos'
   cod_art · delta · unidad · tipo · ref · legajo · ts
   tipos: inicial (95) · ajuste (153) · recepcion_insumo ⬇ ingreso a Virgilio (41)
          · entrega_insumo ⬆ egreso de Virgilio (61) · ingreso (1)
   stock = sum(delta) por (cod_art, unidad)
```

Está **vivo**: 351 movimientos, 132 códigos, del 2026-06-29 al **2026-09-03** (ayer:
Virgilio recibió de Cervantes 540 kg del fleje `1060500`, 145 kg del `N°94`, y el 01/09
entregó a Cervantes los `942P…967H`). El catálogo es `public."Insumos"` (cod, nombre,
categoria, isis), con `Insumos_Categorias`, `Insumos_Unidades` y `Insumos_Factores` (factor
de conversión entre unidades del mismo insumo). **Las 7 categorías son exactamente las que
nombró el usuario**: `fleje` Flejes y alambres (Kg), `cajas` (Paquetes/Uni), `importados`,
`plastico` **Bolsas plásticas** (la materia prima de inyección: ABS, Nylon Virgen,
Recuperado, c/Carga 25%, PP 2630, PE, PS, EBA, Alto Impacto — en **Bolsas**),
`partes_plasticas`, `parte_procesado` y `partes_crudo`.

**Lo que hay, con saldo ≠ 0** (94 códigos):

| categoría | códigos | lo gordo |
|---|---|---|
| fleje | 34 | **17.286 kg** en total: `N°13` 3.251 · `N°2` 1.286 · `N°92` 1.220 · `N°22` 1.014 · `N°56` 873 · `N°46B` 859 · `N°94` 835 |
| importados | 15 | `505C` Cuchilla 505 **142.000** · `H201Part` **Espiral TN 104.000** · `546P` Vastidor 31.968 · `H201Lever` 26.400 · `523C` 6.000 · `337P` 4.464 · `007` Espiral Chef 3.500 |
| parte_procesado | 22 | en **cajones** (7 `A1`, 8 `A4`, 14 `C6`, 26 `DISC1`…), sin unidades |
| partes_crudo | 13 | en cajones (20 `G11`, 13 `N7`, 10 `H1`…) |
| plastico (bolsas) | 9 | `PP 2630` 89 · `AI` 37 · `NY Virgen` 23 · `EBA` 20 · `NY Recup` 18 · `ABS` 14 · `PE` 10 |
| partes_plasticas | 3 | `Mgo Pelador 505` 27.000 · `Mgo Pelador Ergonomico` 8.750 · `TMP-0002` 4.056 |
| cajas | 3 | `Caja 22` 8.625 · `Caja Nº 1` 2.000 · `Caja Nº 12` 750 |

(El `Espiral TN` es el `D1` de GP2 — el importado que no va por OC — y tiene **104.000** en
Virgilio. El `546P` es el `C13` Corta Queso Bastidor.)

**Sigue siendo cierto** que la casa del vecino marca 76 plásticos `en_virgilio` en
`v_rc_catalogo` y que sus `*_stock_planta` sólo tienen `planta='Cervantes'`: esas tablas son
del **relevamiento de Cervantes**, otra cosa. Y la base comercial de Virgilio
(`kwkclwhmoygunqmlegrg`) sigue sin stock de insumos: el stock vive acá, en `public`.

### El cruce con GP2: los códigos no son los mismos

Virgilio usa **sus propios códigos**. Contra `GP2.componente.codigo` coinciden **22 de
127**, y son todos partes de Procesado/Crudo (`A1`, `A4`, `A9`, `C1`, `G11`, `H1`…) — y
ojo que `A1`/`A4`/`A9` en GP2 existen **dos veces** (parte y Caja), así que hay que cruzar
por sector. Para lo demás:

- **Flejes**: Virgilio dice `N°13`, GP2 dice `IA1` con descripción `Fleje N° 13`. Cruzando
  por el número: de los 34 con saldo, **27 tienen N° parseable y 16 matchean** un fleje de
  GP2 — **12.195 kg de los 17.286**. Los otros 18 son `TMP-000x` (altas provisorias), los
  `FLEJES CHEF·1.00 X 84` (dimensión sin número) y N° que GP2 no tiene (`N°17`, `N°18`,
  `N°44`, `N°63`, `N°64`…).
- **Cajas**: `Caja 22` / `Caja Nº 1` / `Caja Nº 12` ↔ GP2 `A9` / `A1` / `A2`. Las 3 cruzan
  por el número.
- **Importados**: a mano y `[deducido]`: `H201Part`→`D1`, `546P`→`C13`, `505C`→`Z23A` (Cuch
  China = la cuchilla del 505). El resto (`437E` colador, `584E` aceitera, `590E` pincel,
  `337P` tenedor…) son **artículos de reventa, no insumos de GP2**.
- **Bolsas de inyección**: GP2 **no las tiene como componente** (no son insumo de un
  artículo, se le mandan al proveedor de inyección). Falta decidir si entran.

**Qué hacer con esto (a decidir, no hecho):** GP2 puede **mirar** ese libro sin copiarlo —
una vista `GP2.v_stock_virgilio` que lea `Movimientos_Stock deposito='insumos'` y traduzca
`cod_art` → `componente_id` con una tabla de alias (`GP2.virgilio_alias`, cargada a mano
para lo que no cruza solo). Con eso la OC y Faltantes verían el stock de Virgilio **sin que
nadie cargue nada dos veces**, que es la regla de la casa: la fuente es una. Lo que hoy NO
hay que hacer es cargar `GP2.inventario` de Virgilio a mano: se desincronizaría en una
semana. Idea **7243**, reescrita.

---

## 4p. El circuito Relevamiento → Stock → OC, y los rubros de la OC (2026-09-04)

**El orden real del trabajo `[usuario 2026-09-04]`:** el relevamiento no es un informe
suelto, es **el paso previo a comprar**. La secuencia que pidió el usuario, textual:
"cuando subo el relevamiento, luego de eso tengo que hacer una orden de compra".

1. **Se releva** (conteo físico de un sector: flejes, cajas, cartones, garage…).
2. **Se compara** lo contado contra el stock que el programa venía calculando por
   movimientos. El usuario **elige cuál vale**, y el default es **el conteo**
   `[usuario: "que me tire por default que el correcto es el del conteo"]`.
3. **Se actualiza el stock** con lo elegido.
4. **Recién ahí se genera la OC**, contra ese stock ya corregido.

Por qué importa: la OC pide contra el stock. Si el stock viene desviado de la realidad, el
pedido sale mal. El relevamiento es el que lo endereza justo antes de comprar.

### El objetivo del pedido: máximo, y si no hay, consumo × meses `[usuario 2026-09-04]`

El usuario primero planteó usar `inventario.minimo` como respaldo cuando `maximo` está
vacío, y **al rato se corrigió solo**: "sí, en realidad es consumo por meses". O sea que
**la regla que ya estaba es la correcta y no se toca**:

- objetivo = `inventario.maximo` si tiene número;
- si está vacío → **consumo × meses** (no `minimo`).

**El dato de consumo por parte SÍ existe** `[dato: consulta 2026-09-04]`:
`GP2.v_consumo_parte` — 260 filas, columnas `componente_id, codigo, descripcion,
sector_id, consumo_uni_mes, en_articulos`. Ejemplos medidos: K9 Arandela 66.616/mes,
D9 Clavo 505 55.334/mes, B3A Cartón 505 28.184/mes, GRJ7 16.968/mes. Para flejes, en kg:
`v_consumo_fleje_kg`. La explosión completa está en `v_consumo_componente` (446).

### Los rubros de la OC son 7, y salen del SECTOR `[usuario 2026-09-04]`

Fleje · Plástico · Bombilla · Remache · Garage · Cartón · Caja.

- **El "rubro" de la pantalla de OC es el `sector_id` del componente**, no la columna
  `proveedor_insumo.rubro` `[dato: lectura de OC_GP2.html 2026-09-04]`. Son dos cosas
  distintas con el mismo nombre — trampa para el que venga después.
- **Alambre va DENTRO de Fleje**: el alambre es materia prima del fleje, no un rubro aparte.
- **Procesado NO va**: **Eclipse es proveedor de SERVICIO, no de consumo**
  `[usuario: "el descorazonador dentro de Eclipse, quiero que esté como proveedor de
  servicio, no como proveedor de consumo"]`. Eclipse hace el **descorazonador**.

**Cómo quedó implementado (v1.15.0):** por ahora es **mapeo de PANTALLA**
(`RUBRO_MAP {13:5}` + `RUBRO_OCULTO {2}` en `OC_GP2.html`), **no toca la base**. Se hizo así
a propósito: mover el rubro en `proveedor_insumo` y pasar Eclipse a proveedor de servicio
toca recepción, stock y costos, y eso se baja a datos **cuando el usuario lo confirme**.

### La OC empieza por el rubro `[usuario 2026-09-04]`

Textual: "separado por rubro, que no me aparezcan los proveedores, y cuando toco el rubro,
que ahí me aparezcan los proveedores". Implementado en v1.15.0: sin rubro elegido, la
botonera de proveedor y su cartel quedan ocultos y el proveedor seleccionado se limpia.

### "Pend. OC" se sacó, de la pantalla Y del cálculo `[usuario 2026-09-04]`

Primero se quitó la columna, la leyenda y la cuenta ("por ahora borralo"). Ese mismo día el
usuario pidió cerrarlo bien ("sí, hacé el cambio de back-end"), así que **el sugerido tampoco
lo resta**: migración `oc_sugerido_sin_pendiente_oc` sacó `- pendiente_oc` de `sugerido` y de
`sugerido_consumo` en `GP2.oc_bundle`. El campo `pendiente_oc` **sigue viajando** en el bundle
(es informativo). Hoy la cuenta es exactamente **máximo − stock**, que es lo que dice la
pantalla. **Deuda saldada, no queda nada oculto.**

### Se van Consumo/mes y Sugerido: el sugerido nace en "Pedir" `[usuario 2026-09-04]`

Textual: "que me aparezca insumo proveedor, stock actual máximo... que me aparezca el
sugerido directamente en pedir" + la aclaración de alcance, en el mismo momento: **"en
resumen, tendrías que eliminar consumo mes. Y sugerido... y que me aclare que es el
sugerido"**. Implementado en v1.17.0: la tabla queda en **Insumo · Proveedor · Stock
actual · Máximo · Precio · Pedir · Subtotal**.

- El sugerido ya no es un número para tocar: **cada fila visible llega con la cantidad
  puesta en Pedir**, y el cartón ya viene redondeado a su familia (lo que antes hacía
  "Usar sugeridos").
- **Debajo del campo dice qué es**: "sugerido 3.562 · máx 3.922 − stock 360". Sigue
  estando si la cantidad se pisa a mano, para ver contra qué se está cambiando.
- **Vaciar el campo = "este no lo pido"**: queda marcado y el render no lo vuelve a
  llenar. "Usar sugeridos" borra esas marcas y repone todo.
- También se fue de esta pantalla el **detalle de consumo tocable** (era la celda
  Consumo/mes): `consumo-detalle.js` ya no se carga en la OC. Sigue vivo en Pintores y
  Orden de Producción.

**Y enseguida se fueron también Precio y Subtotal (v1.18.0)** `[usuario 2026-09-04:
"precio se va y subtotal tambien"]`. La tabla de pedir quedó en lo **físico**: qué hay,
cuánto entra, cuánto pido. **La plata no desapareció del circuito**: el precio sigue
saliendo de `precio_proveedor`, valoriza el total de la barra, viaja a `crear_oc` y es el
que sale impreso — lo único que se perdió es **pisarlo desde esta pantalla** (estaba desde
v1.8.0, pedido el 2026-09-03). Si vuelve a hacer falta, se repone la celda: `PRECIO` y
`MONEDA` siguen en el código.

Dos cosas más del mismo día:

- **El "mín N" debajo del Stock actual se sacó** `[usuario: "eso no lo quiero ver"]`. El
  mínimo sigue en la base y sigue pintando el stock en **rojo** cuando está abajo; lo que
  se fue es el número en pantalla.
- **La OC anulada ya no se lista** `[usuario: "si anula una orden de compra, no quiero que
  me siga apareciendo en órdenes"]`. `pintarOcs()` la filtra: se esconde de la pantalla,
  **la fila queda en `GP2.orden_compra`** (es el historial y explica que la numeración
  tenga huecos).
- **PENDIENTE que el usuario dejó planteado**: los insumos **sin máximo cargado** no
  pueden calcular pedido — *"después lo vamos a agregar"*. Hoy caen al consumo × meses
  (`maximo_origen='consumo_x_meses'`); cuando se carguen los máximos, revisar si conviene
  sacar ese fallback.

### En pantalla se llama SECTOR, y sin elegir no hay lista (v1.19.0) `[usuario 2026-09-04]`

Textual: *"no pongas rubro, sector quiero que pongas"* + *"si no pongo el sector y no pongo
el proveedor, que no me aparezca la lista"*.

- **"Rubro" era una palabra nuestra, no del usuario.** La botonera y la hoja impresa dicen
  ahora **Sector**. Es sólo el rótulo: el campo sigue siendo `GP2.orden_compra.rubro` y el
  JS sigue usando `rubroSel`/`rubroDe`/`RUBRO_MAP` — **no se renombra media pantalla y una
  columna de la base por un texto**.
- **Sin sector ni proveedor elegido no se muestra nada**: `filtradas()` devuelve `[]` y toda
  la zona de armar la OC queda oculta. Efecto de fondo que importa: **la pantalla ya no
  arranca con todos los insumos de la fábrica con cantidad puesta** — el sugerido se carga
  recién cuando decís dónde estás comprando. Antes de esto, abrir la pantalla ya era un
  pedido gigante armado solo.

### PENDIENTES que el usuario dejó planteados y NO están hechos

- ~~**P10 y P3 dentro de Plástico**~~ **RESUELTO el mismo día — ver 4p-bis abajo.**
- **Garage como rubro de OC**: el sector existe (9) pero **no hay proveedor de insumo de
  Garage** — los GRJ los arman talleristas. Falta definir qué se pide ahí.
- **Bajar el mapeo de rubros a datos** (Alambre→Fleje, Eclipse→servicio) cuando se confirme.

### El módulo Relevamiento de hoy NO es de GP2 `[dato: lectura del código 2026-09-04]`

`Relevamiento/relevamiento.js` está cableado al **schema viejo**: `relevamiento_cervantes`
vía funciones `public.rc_*`, con el modelo de plantas Cervantes/Virgilio. O sea que hacer el
relevamiento "de GP2 mirando esa lógica" es **rehacer el módulo** (casa del vecino: se mira
la lógica, no se copia la casa), no ajustar el que está.

Lo que pidió el usuario para el de GP2:
- **Cronograma cargado con las fechas de conteo** (pasó la foto del Excel "conteo": Cartones,
  Garage, Remaches, Bombillas, Flejes, Plásticos, Bolsa Plást, Cajas — Garage se repite
  varias veces por mes).
- **Mostrar sólo el MÁS PRÓXIMO por tipo**, no toda la lista.
- **Al entrar, todos los componentes de ese sector** para completar (en flejes el total de
  kilos, en cajas todas las cajas, en cartones todos los cartones…).

---

## 4p-bis. "P10 y P3" son PA10 y PEP3, y salen a SERIGRAFIAR (2026-09-04)

**El caso completo, incluida la corrección — vale la pena leerlo entero porque es un ejemplo
de por qué la regla "NO inventar / NO asumir" existe.**

### Quiénes son `[dato: consulta 2026-09-04]`

El usuario los dictó por voz como "P10 y P3". No existen con ese código. Son:

| Código | Descripción | Sector | Proveedor |
|---|---|---|---|
| `PA10` (id 234) | Capuchón ф 8 | **Sector Procesado** | Pat Bet Plast |
| `PEP3` (id 246) | Mango Pelador LK 586 **c/Serig** | **Sector Procesado** | Pat Bet Plast |

Se los encontró cruzando `GP2.componente` contra `public."SectorPlasticos"` (la casa del
vecino, sólo lectura): son los **únicos dos** plásticos que están fuera del sector Plástico.

### La corrección `[usuario 2026-09-04, TEXTUAL]`

Primero el usuario dijo "no sé por qué P10 y P3 no están adentro de plástico. Dentro de Pat
Bet Plast", y se los movió al Sector Plástico. **Al rato lo corrigió:** *"perdón, me confundí
lo de los plásticos. Dejalo en sector procesado, pero no va en orden de compra, porque eso
sería plásticos que se mandan a serigrafear"*. Se **revirtió** (migraciones
`plasticos_pa10_pep3_al_sector_plastico` y su `revert_pa10_pep3_vuelven_a_procesado`).

**Por qué la corrección es la correcta, y la evidencia lo respalda:** no son una COMPRA de
plástico, son plástico propio que **sale a serigrafiar** — un **servicio**, no un insumo. Se
ve en los propios nombres: `PEP3` es "Mango Pelador LK 586 **c/Serig**" y en la tabla vieja
existe `PA10B` "Capuchón ф 8 **S/Serig**" (la versión sin serigrafiar). Por eso viven en
**Procesado** (que es donde va lo que está en proceso) y por eso **no deben aparecer en OC**.

**Consecuencia buena:** ocultar el Sector Procesado en Generar OC no es un parche, es **la
regla correcta** — ese sector no se compra.

### Qué NO se rompió, y por qué el revert fue barato

El movimiento tocó sólo `componente.sector_id`. **El inventario de PA10 y PEP3 ya vivía en la
ubicación "Sector Plástico"** (tipo sector), así que nada se movió físicamente ni se tocó
stock, recetas ni rutas. Lección: antes de mover un `sector_id`, mirar dónde está el
`inventario` — si no coinciden, hay algo mal clasificado y conviene preguntar antes de tocar.

### Lo que quedó en Procesado y NO va a OC

Además de PA10/PEP3, en Procesado hay 88 componentes, de los cuales **sólo 4 tenían precio**:
los dos de serigrafía, más `C13` (Corta Queso, **Importado**) y `D1` (Espiral Sacacorcho,
**Tierra Nativa SA**). Los dos últimos ya estaban cubiertos por la decisión de §4o
(**los importados no se piden por OC**), así que ocultar Procesado **no deja afuera nada que
debiera comprarse**.

## 4p-ter. Las reglas de rubro de la OC viven en `GP2.sector` (2026-09-04)

`[usuario 2026-09-04: "baja el mapeo a datos"]`. Migración `sector_reglas_de_rubro_oc`:

- **`GP2.sector.oc_rubro_id`** — a qué rubro **sube** este sector en la pantalla de OC.
  NULL = es su propio rubro. Hoy: **Alambre (13) → Fleje (5)** (el alambre es MP del fleje).
- **`GP2.sector.oc_pide`** — si el sector **se compra por OC**. Hoy: **Procesado (2) = false**
  (serigrafía = servicio).

**Regla de oro que se respetó:** NO se movió el `sector_id` de ningún componente. El sector es
la **zona física** (§1-bis) y moverlo corrompe el stock. Lo que bajó a datos es la **regla de
agrupación de la pantalla**, no la ubicación de las piezas. En Sector Alambre viven
`CHAPA430` (Aperam → Eclipse corta) y `FLEJE90_BRUTO` (Altrak, antes de cortar), que siguen
donde estaban.

`OC_GP2.html` v1.16.0 las lee en `boot()` con `cargarReglasRubro()`; el `RUBRO_MAP` /
`RUBRO_OCULTO` hardcodeado quedó **sólo como fallback** por si la consulta falla. Para sumar
un rubro nuevo o sacar uno, **ya no se toca código**: se actualizan esas dos columnas.

---

## 4q. Relevamiento GP2: el conteo físico que endereza el stock antes de comprar (2026-09-04)

**Arrancado el 2026-09-04. Backend hecho y verificado; falta el cierre/comparación y la
pantalla.** Registro del SQL en `db/relevamiento_GP2.sql`.

### Por qué es módulo nuevo y no un ajuste `[dato: lectura del código]`

`Relevamiento/relevamiento.js` (el que ya existía) lee del **schema viejo**
(`relevamiento_cervantes` vía `public.rc_*`) y está armado sobre **plantas**
(Cervantes/Virgilio). GP2 está armado sobre **sector + ubicación**. No es el mismo modelo:
se mira la **lógica** del vecino (cómo cuenta cada tipo, cómo compone envases + sueltas) pero
no se copia su casa.

### Los 7 tipos del viejo mapean 1:1 a sectores GP2

| Tipo (Excel) | Sector GP2 | Componentes |
|---|---|---|
| Cajas | 11 | 9 |
| Flejes | 5 | 54 |
| Cartones | 10 | 110 |
| Plásticos | 6 | 37 |
| Remaches | 8 | 33 |
| Bombillas | 7 | 12 |
| Garage | 9 | 10 |

**`Bolsa Plást` NO es uno de los 7 y no tiene sector.** Aparece en el Excel del usuario
(siempre el mismo día que Plásticos: 02-oct y 09-nov). Quedó cargado en el cronograma con
`sector_id NULL` y la pantalla lo va a mostrar como **no mapeado**. **PENDIENTE del usuario:
decir qué sector es.** No se inventó.

### El cronograma

Cargado con la foto del Excel "conteo" (28 fechas, sept–nov 2026) en
`GP2.relevamiento_cronograma`. `relevamiento_bundle()` devuelve **el más próximo por SECTOR**
`[usuario: "en el cronograma aparecen varias veces garage porque se hace más de una vez por
mes, pero quiero que me pongas el más próximo"]`. Si un sector ya no tiene fechas futuras,
muestra la última vencida en vez de desaparecer.

**Corregido el mismo día, tres cosas `[usuario 2026-09-04]`:**

1. *"me tendrían que aparecer todos a realizar, porque son todos futuros relevamientos"* —
   los 8 se muestran.
2. *"el de garage no me pongas el de hoy, poneme el próximo"* — la fecha tiene que ser
   **estrictamente futura** (`fecha > hoy`). Antes era `>=` y Garage mostraba el de hoy;
   ahora muestra el 11-sep.
3. *"me tendría que aparecer solo uno por sector, acordate"* — la clave de deduplicación es
   el **sector**, no la etiqueta del Excel. Los tipos sin sector (hoy "Bolsa Plást") se
   agrupan por su propio nombre para no fusionarse entre sí ni con ningún sector.

Resultado medido: Garage 11-sep (7 días), Remaches 16-sep, Bombillas 24-sep, Flejes 28-sep,
Bolsa Plást y Plásticos 02-oct, Cajas 06-oct, Cartones 13-oct.

### El envase cambia por sector, y ese es el único pedazo que varía

`GP2.relev_factor(componente_id)` devuelve **cuántas unidades entran en un envase** y **cómo
se llama ese envase**: Paquetes (cartón/caja), Bolsas (plástico/remache), Bolsa/Caj/Rollo
(bombilla), Cajones (garage). El **fleje se cuenta en kilos**, no en envases.

**El total lo calcula la BASE** (`relev_total_uni`), nunca el JS — el motor vive en la BD.

### Hallazgo: los factores de cartón y caja NO están por componente `[dato: medido]`

`componente.uni_x_cajon` está en **0 de 110** en Cartón y **0 de 9** en Caja (se ve en la
pantalla de stock: la columna "Uni × Cajón" toda en "—"). **No es un bug: son parámetros
globales**, no por pieza:

- `carton_uni_x_paquete` = **250**
- `pliego_uni_x_paquete` = **100** (los `es_pliego`)
- `caja_uni_x_paquete` = **25** — este **estaba hardcodeado** en `control-cajas.js` y se bajó
  a `GP2.parametro` para que el relevamiento y el control usen el mismo número.

Los que sí van por componente: Plástico 34/37, Garage 9/10, Bombilla 8/12, Remache 14/33.
**Los que faltan quedan con factor NULL y la pantalla los marca**: no se calcula un total
inventado (regla de la casa).

### El circuito completo `[usuario 2026-09-04]`

1. Se releva (conteo físico del sector).
2. Se compara **conteo vs programa**; el usuario elige cuál vale, **default el conteo**.
3. Se actualiza el stock.
4. **Recién ahí** se genera la OC, contra ese stock ya corregido.

**Decisión de cómo se aplica el ajuste:** por **movimiento** (`GP2.movimiento`, tipo
`ajuste`, `ubic_destino` = la del sector, cantidad **con signo**), **no** pisando
`inventario.cantidad`. Motivo: el motor de inventario vive en la BD (triggers
`fn_movimiento_calc` / `fn_movimiento_aplicar`) y así el ajuste queda **trazado**.

**Los pasos 2–3 ya están construidos** (`relevamiento_cerrar`, `relevamiento_comparar`,
`relevamiento_decidir`, `relevamiento_aplicar`). Dos reglas que salieron al construirlo:

- **Lo que NO se contó no se toca.** Al cerrar, sólo lo contado queda con `decision='conteo'`;
  el resto queda en `'programa'`. **Contar es afirmar; no contar no significa "hay cero"** —
  poner 0 a lo no contado borraría stock real. Es la trampa obvia de un conteo parcial.
- **El delta se calcula contra el stock DE AHORA, no contra la foto del cierre.** Si algo se
  movió entre que cerraste el conteo y que aplicaste, el resultado final sigue siendo
  exactamente lo contado. La foto (`stock_programa`) queda igual, como registro de lo que
  viste al decidir.

**Verificado end-to-end** (Sector Caja, 2026-09-04, datos de prueba borrados): A1 contó 85
contra 1.120 del programa → se aplicó un ajuste de −1.035 y el stock quedó en 85. A9 coincidía
(80 = 80) y **no generó movimiento**. Los 7 sin contar quedaron intactos. Después se restauró:
**borrar el movimiento de ajuste revierte el inventario solo**, porque `trg_movimiento_aplicar`
corre `AFTER INSERT OR DELETE OR UPDATE` — dato útil para deshacer un ajuste mal aplicado.

**Falta la pantalla.** El backend está completo.

### Verificado end-to-end el mismo día

Con Sector Caja: los 9 componentes salen con envase "Paquetes" y factor 25; cargando 3
paquetes + 10 sueltas en A1 el total dio **85** contra **1.120** del programa. Los stocks
coinciden con la pantalla que mostró el usuario (A1 1.120, A11 60, A2 20, A9 80). Los datos
de prueba se borraron.

### Relevamiento: SOLO CERVANTES, Virgilio apagado `[usuario 2026-09-04]`

*"todo lo que es relevamiento de virgilio por ahora no, solo cervantes"* — dicho mirando los
chips rojos **`Virg. ✗`** del cronograma del módulo viejo.

**Dónde se apagó:** `Relevamiento/relevamiento.js`, constante `PLANTAS_TIPO` (y `PLANTAS`).
Todo el módulo se maneja con esa constante — los chips del cronograma, si el ciclo está
completo, el selector de lugar al realizar y el cálculo de vencimiento — así que sacando
Virgilio de ahí desaparece de todas esas partes de una sola vez. Los tres tipos que lo tenían
eran **flejes, cajas y plásticos**; los otros cuatro (cartones, remaches, bombillas, garage)
ya eran sólo Cervantes.

Es un **filtro de pantalla**: no se borró ningún relevamiento de Virgilio ya cargado ni se
tocó `rc_plantas_tipo` en la base. Para volver a prenderlo está escrito cómo, en el propio
comentario del código.

**El módulo GP2 nuevo ya era Cervantes-only por construcción** `[dato: consulta 2026-09-04]`:
filtra `ubicacion.tipo='sector'`, y esos son los **11 sectores físicos de Cervantes**.
Virgilio es otro tipo (`ubicacion.tipo='virgilio'`, una sola fila "Virgilio (Distribución)"),
así que nunca lo toca. Además hay **exactamente una ubicación por sector**, por eso el
`LIMIT 1` de `relevamiento_aplicar` no es ambiguo.

**Pista para cuando se retome:** el chip de plásticos de Virgilio se llamaba **"Virg. bolsas"**
(`PLASTICO_LUGAR`). Es muy probable que el renglón **"Bolsa Plást"** del Excel del cronograma
sea justamente ese conteo — encaja con que caiga siempre el mismo día que Plásticos. **Sin
confirmar**; el usuario dijo "bolsas plast por ahora no".

### Factores de envase recuperados de la casa del vecino (2026-09-04)

`[usuario: "todos los que no tienen factor intentá encontrarlo en gestión productiva vieja, si
encontrás agregalo"]`. De **27 componentes sin factor se bajó a 12**.

**Lo que se cargó, y de dónde:**

| Código | Factor | Fuente en el viejo |
|---|---|---|
| PB8A | 500 | `SectorPlasticos."Uni x Bolsa"` |
| BOM12 | 1.760 | `Sector Bombilla."Uni_x_Bolsa"` |
| V11 | 2.729 | `Remaches SP`: 2 kg/bolsa ÷ 0,000733 kg/uni |
| **12 remaches `CV*`** | 556 a 100.000 | `Remaches SC` (crudos), mismo cálculo |

**La trampa de los remaches, y cómo se resolvió** `[usuario]`: los `CV*` ("p/Niquelar")
matcheaban por descripción en **las dos** tablas del viejo con factores que difieren **de 2x a
10x** (CV1: 57.143 en SC vs 5.714 en SP). Elegir a ojo dejaba el conteo diez veces mal. Lo
destrabó el usuario: *"en el viejo aparecían los remaches crudos con la c al final me parece"*
→ los `CV*` son **crudos**, así que la fuente es **`Remaches SC`**. 11 de los 12 llevan
efectivamente la C (V1C, V11C, V14C, V16C, V17C, V2C, V3C, V4C, V5C, V7C, V8C); `CV13` figura
como `V13` pero está **en la tabla de crudos**, que es lo que manda.

**Lo que NO se cargó, a propósito:**

- **`BOM14` — colisión de código.** En GP2 es "Precinto p/Bombilla"; en el viejo el mismo
  código es "Caño Inox 170 mm". **Son cosas distintas.** Copiar ese 1.000 metía el dato de
  otra pieza. **Regla que deja: al traer datos del vecino, matchear por código Y descripción,
  nunca sólo por código.**
- Los 12 que siguen sin factor: `BOM13, BOM14, C12, GRJ13, D9, PC16, CV12, CV18D, CV6, CV9,
  V18D, V20`. No están en el viejo, o el código no coincide. Quedan en NULL y la pantalla los
  muestra como **"falta el factor"** con el campo deshabilitado: no se inventa un total.

### Relevamiento: entrar a mirar no es empezar a contar (2026-09-04)

`[usuario: "que si salgo, después de haber puesto contar, no me aparezca seguir cargando,
porque lo estoy usando como prueba"]`. `relevamiento_descartar_si_vacio(id)` borra el
relevamiento **sólo** si está `en_curso` y **no tiene ni una fila contada**; si hay aunque sea
un dato, se niega y guarda. La pantalla la llama al tocar "Volver".

Se aplicó a lo que ya había: se descartaron dos aperturas vacías (Remache y Plástico) y
**se dejó intacto el de Bombillas, que tenía 8 de 12 cargados de verdad**.

**Tilde al terminar** `[usuario: "cuando lo termino de cargar quiero que me aparezca un
tilde"]`: `contado` → **✓ Contado** (+ botón a la comparación), `aplicado` → **✓ Hecho**, y la
línea entera se pinta verde.

**"Bolsa Plást" no se muestra** `[usuario: "bolsas plásticas no lo quiero ver por ahora"]`:
el bundle filtra los tipos sin sector. Sigue cargado en el cronograma; el día que tenga sector
aparece solo.

**El módulo viejo salió del menú** `[usuario: "borrá relevamientos (viejo) y dejá solo
relevamiento gp2 (nuevo) pero renombralo y ponele Relevamientos"]`. `Relevamiento/relevamiento.html`
quedó primero en el repo sin link; `[2026-09-04, auditoría de arquitectura]` se **borró del todo**
(html, js, el backup del 31/07 y su `db.sql`), junto con los 4 shims `GP2.rc_*` que sólo
existían para que esa pantalla llegara a `public.rc_*`. La tablet (`envios-only.html`) y la lista
de páginas del rol `envios` en `auth-guard.js` apuntan ahora al GP2. Ver `REFACTOR_GP2.md`.

### En qué unidad se cuenta cada sector `[usuario 2026-09-04]`

| Sector | Se cuenta en |
|---|---|
| Fleje | **Kilos** |
| Bombilla | **Bolsas** |
| Plástico | Bolsas |
| Remache | Bolsas |
| Garage | Cajones |
| Caja | Paquetes (+ uni sueltas) |
| Cartón | Paquetes (+ uni sueltas) — los `es_pliego`, paq. de 100 pliegos |

**Sólo se cambió Bombillas** (migración `relev_factor_bombillas_en_bolsas`): decía
"Bolsa/Caj/Rollo", heredado del módulo viejo, y el usuario lo corrigió a **Bolsas**. El resto
ya estaba bien — el usuario lo confirmó con *"el único que quiero que cambies es bombillas"*.

**PENDIENTE, sin aplicar** — el usuario había dicho antes dos cosas que después acotó a sólo
bombillas, así que **quedaron sin hacer** y hay que confirmarlas antes de tocar:

1. *"remaches crudo, es decir todos los que tienen la c, en kilos, y todo lo que es procesado
   en bolsas"* → hoy **todo Remache cuenta en Bolsas**. Partirlo es fácil: los crudos son los
   16 `CV*` (todos dicen "p/Niquelar" en la descripción; 15 de 16 tienen `kg_x_uni`), los
   procesados son los otros 17.
2. *"dentro de cajas y cartones también tendría que ir uni sueltas"* → hoy la columna de
   **uni sueltas aparece en todos** los sectores que no cuentan en kilos, no sólo en cajas y
   cartones.

### El cartón se CUENTA por paquetón, pero se PIDE por paquete `[usuario 2026-09-04]`

*"los cartones vienen en paquetones, o sea vienen de a mil según el formato. Entonces no
tendría que ser doscientos cincuenta. Yo cuento por paquetón, no por paquete. Y después en uni
sueltas ahí sí puedo poner."*

**Son dos números distintos y conviven:**

| | Cuánto | Dónde vive | Quién lo usa |
|---|---|---|---|
| **Paquete de pedido** | 250 | `parametro.carton_uni_x_paquete` | **OC** ("= N paq de 250") |
| **Paquetón de conteo** | 1.000 / 2.000 / 3.000 | `carton_formato.uni_x_bolsa` | **Relevamiento** |

El dato **ya estaba en la base** y varía por formato tal como lo dijo: **C 1.000, LOKE 1.000,
Huevo 2.000, "8" 3.000**. La nota del formato Huevo lo decía textual: *"Bolsa de 2.000 uni (8
paquetes de 250)"* — o sea el paquetón son 8 paquetes.

**Trampa evitada:** cambiar `carton_uni_x_paquete` de 250 a 1.000 habría "arreglado" el
relevamiento y **roto la OC**. Se dejó el parámetro quieto y el relevamiento lee el formato.

Cobertura: **106 de 110** cartones quedan con paquetón. Los 3 de formato **"Bolsa"** (que no es
cartón: es packaging de Envases Vihal) no tienen `uni_x_bolsa` → factor NULL y la pantalla los
marca "falta el factor". Los 24 `es_pliego` siguen con su regla propia de 100 pliegos.

### Relevamiento y Validación son DOS módulos, porque son DOS ROLES `[usuario 2026-09-04]`

*"necesito que me aparezca dentro de módulo relevamiento otro módulo que sea validación de
stock... pero no quiero que me aparezca después de hacer el relevamiento en el mismo módulo,
porque eso lo van a hacer los operarios, y el operador de acá del sistema va a hacer el chequeo."*

| Pantalla | Quién | Qué hace |
|---|---|---|
| `Relevamiento_GP2.html` | **Operario** | Cuenta y cierra. Ahí termina su trabajo. |
| `Validacion_Stock.html` | **Operador del sistema** | Compara conteo vs programa, elige cuál vale y **recién ahí toca el stock**. |

**El operario nunca decide sobre el stock.** Contar y decidir son cosas distintas y las hace
gente distinta. Por eso al completar el conteo la pantalla vuelve al cronograma con el tilde y
**no** salta a la comparación.

`validacion_bundle()` lista los conteos cerrados esperando validación, con **cuántas filas
difieren** del programa (que es lo que el operador quiere ver de un golpe), más un historial
corto de los ya aplicados.

**Dónde va el "Eliminar" — el usuario lo cambió dos veces, y la segunda tiene mejor razón.**
Primero pidió sacarlo del cronograma (*"que no me aparezca acá el eliminar, solo adentro"*), y
al rato lo revirtió: *"que no me aparezca el eliminar cuando estoy haciendo el conteo adentro
de la página... porque no tiene sentido poder ir para atrás, sino que me aparezca afuera"*.

**Queda afuera, en la línea del cronograma** (en "Seguir cargando" y en "Contado"), y también
en la barra de la comparación del módulo de validación. **Mientras se cuenta no aparece**: es
un botón para arrepentirse en el peor momento. En "✓ Hecho" tampoco va — ese ya tocó el stock
y la base lo rechaza.

### "Solo sueltas" NO es lo mismo que "falta el factor" `[usuario 2026-09-04]`

*"dentro de garage, el Bowl 330 ml, que aparezca solo la opción de cargar uni sueltas, porque
no se cuenta en cajones."*

Nueva columna **`componente.relev_solo_sueltas`** (hoy sólo `GRJ13` Bowls 330ml). Cuando está
en true, `relev_factor` devuelve **envase NULL** y `relev_total_uni` toma directamente lo suelto.

**Los dos casos terminan mostrando lo mismo, pero por motivos distintos:**

- **`envase` NULL** → el envase **no aplica** (el Bowl no viene en cajones).
- **`factor` NULL** → el envase aplica pero **no sabemos cuántas unidades entran**.

En los dos la pantalla dice **"solo sueltas"** y se cuenta directo en unidades
`[usuario 2026-09-04: "con respecto a todos los que falta factor, dejame cargar uni sueltas y
eliminá el botón, ya sea bolsa, cajón, lo que fuere"]`. Antes el segundo caso mostraba el campo
deshabilitado con un cartel rojo "falta el factor", y **era un callejón**: la pantalla pedía un
dato que no está y no dejaba avanzar. Son **15 componentes** (`D9, PC16, BOM13, BOM14, C12,
CV12, CV18D, CV6, CV9, V18D, V20, GRJ13` y los 3 cartones formato "Bolsa": `A1B, A1B1, G8C`).

La distinción sigue viva en los datos (`relev_solo_sueltas` vs factor faltante), así que el día
que aparezca un factor se carga y esa pieza vuelve sola a contarse por envase.

### El ciclo de vida de una fecha del cronograma `[usuario 2026-09-04]`

*"los pasos serían cargar el relevamiento y después hacer la validación de stock, y que
desaparezca de la página de relevamiento el relevamiento correspondiente al cual nos estamos
refiriendo, que se le hizo la validación de stock, y que aparezca el próximo relevamiento."*

| Estado | Qué muestra el cronograma |
|---|---|
| sin abrir | **Contar** |
| `en_curso` | **Seguir cargando (n/m)** + Eliminar |
| `contado` | **✓ Contado** + Eliminar — el operario terminó, espera al operador |
| `aplicado` | **desaparece**, y sube la próxima fecha de ese sector |

El salteo se hace en el CTE `base` de `relevamiento_bundle`, o sea **antes** de elegir el
próximo por sector: si se filtrara después, la fecha ya validada seguiría ocupando el lugar
del que sigue y el sector quedaría sin nada que mostrar.

Verificado en lectura pura: con el Garage del 11-sep validado, el sector pasa a mostrar el
**18-sep** y se reordena solo en la lista.

**Los ya aplicados no se pierden:** quedan en el historial de la pantalla de Validación de
Stock (`validacion_bundle` → `aplicados`, últimos 20).

## 3c-quater. La tablet de logística: specs físicas de `envios-only.html` (2026-09-04, fusión de TABLET_LOGISTICA.md)

`envios-only.html` es la portada que se usa **exclusivamente en la tablet del galpón**
(≈8,7", portrait, 19 × 11,25 cm; iPad mini o Android de 8"). Lo que importa para diseñar:

- **Ancho útil ≈ 744 px** (iPad mini) / 800 (Android) / 600 (Android barata 1024×600). Es la
  limitación principal: una tabla de 11 columnas no entra sin scroll horizontal explícito.
- **Alto útil ≈ 1.044 px** (descontando ~2,3 cm de barra de Chrome y ~0,9 cm de botones
  Android). Headers sticky de 60+ px se sienten enormes.
- Setup para probar en Chrome DevTools: Responsive **744 × 1044**, DPR 2.
- Botones táctiles ≥ 44 px en todo el flujo crítico (regla general de la casa).
- Una PWA a pantalla completa recuperaría los ~150 px de la barra de Chrome (hoy `pwa.js`
  registra el manifest en las 3 páginas de entrada).

`[dato: TABLET_LOGISTICA.md, 2026-07]` Pendientes que traía ese archivo y siguen abiertos:
auditar `envios-only.html` y las pantallas de Envíos/Entrega PS en 744×1044 (las tablas anchas
van en `.table-wrap`), y decidir si la tablet abre las pantallas GP2 (ver
`PREGUNTAS_ARQUITECTURA_GP2.md` pregunta 2).

## 4r. Nombres cortos de los PS, vocabulario cerrado del ledger, sectores de insumo (2026-09-05)

`[dato 2026-09-05: ex GP2.proveedor_servicio_alias, hoy proveedor_servicio.nombre_corto]` Cómo
se llama en la planta a cada proveedor de servicio (lo que muestra Control PS al lado del
nombre): **FAAT** = Laboratorio FAAT (templado/cementado), **Guazzaroni** = Guazzaroni Patricio
(niquelado), **Pedernera** = Pedernera Ilario (cromado), **Scor** = Scorrano Mario
(rectificado), **Jade** = Becker Sandra Nora `[usuario: "Becker Sandra Nora ES Jade"]`,
**Ximpa** = Hernandez Julio `[usuario: "Ximpa ES Hernandez Julio"]`. Es un atributo del
proveedor (`nombre_corto`), no una tabla aparte: la tabla de alias con "confianza" y "nota" se
borró en la auditoría.

`[deducido 2026-09-05]` El ledger (`GP2.movimiento.tipo_mov`) tiene **vocabulario cerrado** por
CHECK (16 palabras, ver `GP2_MAPA.md`). Razón: tres veces apareció una palabra nueva para un
evento que ya tenía nombre (`recepcion_tall`, `consumo_armado`, `consumo_transformacion`) y las
pantallas de control no la sumaban. Si hace falta un evento nuevo, se agrega al CHECK y al mapa
de etiquetas, deliberadamente.

`[dato 2026-09-05: GP2.movimiento.unidad_origen/unidad_destino]` **Las unidades del ledger son
dos palabras: `kg` y `uni`** (CHECK desde la auditoría, ciclo 8). Antes convivían `uni`, `unidad`
(la palabra de `componente.unidad_medida`) y `pliego` en 38 ajustes del 02/09; `to_canonical` ya
las trataba a todas como unidades, así que el stock era correcto, pero la palabra quedaba guardada
como vino. Hoy el trigger `fn_movimiento_calc` traduce cualquier cosa que no sea `kg` a `uni`
antes de calcular (y `KG` a `kg`), con lo que una pantalla puede mandar `unidad_medida` tal cual.
`componente.unidad_medida` sigue diciendo `unidad`: no se renombra por prolijidad.

`[dato 2026-09-05: GP2.parametro.charcas_kg_x_paquete = 10]` **La OC a Resortes Charcas se pide en
paquetes de 10 kg de producto y se guarda en kg.** La pantalla de OC muestra el pedido en paquetes
(con el «= N uni» que sale de `kg_x_uni`) y manda `unidad='paq'`; `crear_oc` lo convierte a kg con
ese parámetro (antes el 10 estaba escrito en `OC_GP2.html`). Así la recepción de Charcas, que
entra en kg de balanza, cruza directo contra la OC, y la OC gemela a Altrak suma esos kg
÷ (1 − `proveedor_servicio.desperdicio_pct`/100) `[act. 2026-09-08: el desperdicio es % DE LA CHAPA,
fórmula DIVISIÓN — Charcas 0 así que no cambia; Eclipse 40,28]`. Hasta el 2026-09-05 `crear_oc` sumaba los paquetes como si
fueran kg (3 paquetes → 3 kg de alambre): bug latente, sin ninguna OC de Charcas afectada.

`[dato 2026-09-05: GP2.proveedor_servicio.desperdicio_pct]` **El desperdicio de un PS híbrido es
un atributo del PS**: Eclipse **40,28 % de la chapa** (`[usuario 2026-09-08]` calibrado con la compra
real Aperam vs Eclipse; antes figuraba 28 %/67,46 % — ver bloque "Desperdicio Eclipse" arriba), Charcas **0** (`[usuario 2026-09-04]` "sin dato, asumir 0"; el 2 % que
había era un default que escribió un agente el 01/09 y quedó como si fuera dato — corregido al
cierre de la auditoría). Antes eran dos claves de `parametro` con el nombre del PS adentro. La
**OC gemela** sale de una sola regla en `crear_oc`: si la OC es a un PS híbrido, se crea otra al
proveedor de su materia prima (`mp_componente_id` → `componente.proveedor`) por kg de producto
pedido ÷ (1 − desperdicio/100). **Pero ese modelo está en duda** (pregunta 28): el 04/09 el usuario
decidió que la OC del Fleje 90 va SOLO a Altrak y que no hay gemela en el flujo de Charcas; el
código siguió con el modelo viejo y la auditoría lo generalizó antes de ver esa decisión.

`[dato 2026-09-05, segunda opinión gp2-experto]` Lo que hoy tiene el circuito de la OC gemela,
para cuando el usuario conteste la 28: (1) la recepción de Charcas descuenta el alambre **1:1**
(sólo la de Eclipse aplica el %); (2) **Eclipse no se puede pedir desde la pantalla** — el 1686 es
sector 2 Procesado con `sector.oc_pide=false` — así que la gemela a Aperam sólo se alcanza por RPC;
(3) las dos OC gemelas **no tienen vínculo en datos** (sólo texto en `nota`): anular una deja viva
la otra, y la huérfana cruza contra la próxima recepción; (4) la gemela **no aplica la norma de
envase** del proveedor de la MP (Aperam vende chapas enteras de 19,625 kg); (5) `crear_oc` suma a
la gemela todos los ítems de la OC sin verificar que sean del PS; (6) el precio 1,715 USD de
IC3/IC3V está cargado con `cod_prov` 3711 (Altrak, "Ø 1.63 mm alambre galvanizado") y
`precio_por_kg=false`, y `FLEJE90_BRUTO` / `CHAPA430` no tienen precio: la OC de Charcas se
valoriza con el precio del alambre y las gemelas salen sin valorizar; (7) `oc_bundle` y
`esCharcasIt()` siguen nombrando a Charcas/Eclipse: la configurabilidad es sólo de `crear_oc`.

`[dato 2026-09-05: GP2.sector.es_insumo]` Qué sectores son **de insumo comprado** (entran por
Recepción, salen en la OC, no los produce ninguna ruta) ahora es una columna del sector, no una
lista de ids adentro de una función: Fleje (5), Plástico (6), Bombilla (7), Remache (8), Garage
(9), Cartón (10), Caja (11). El sector 13 «Alambre» (tipo `crudo`, rubro de OC 5, único
componente FLEJE90_BRUTO que compra Altrak) quedó **fuera**, igual que antes, hasta que el
usuario diga si es comprable como los otros (`PREGUNTAS_ARQUITECTURA_GP2.md`, punto 21).

`[dato 2026-09-05: GP2.fn_est_madre_sync]` **El espejo de la Est Madre corrige al origen.**
`public.proyeccion_madre` trae 36 artículos con `uxb` vacío y, en esos, su `proy_uni_mes` es en
realidad la cantidad de cajas redondeada (43: 4 cajas → "4 uni"). El trigger que copia a
`GP2.est_madre` lo detecta y recalcula `proy_uni_mes = cajas × articulo.articulos_por_caja` (43:
4 × 24 = 96). Por eso GP2 y `public` difieren en esas 36 filas **a propósito**: la demanda buena
es la de GP2. Las 5 filas contables del origen (ANTICIPO VTA, CHEQ RECHAZADO…) no entran al
espejo porque no empiezan con dígito.


## 4s. Murió Gentile: hay que reemplazar el envasado skin (2026-09-07)

`[usuario 2026-09-07]` **Falleció Gentile Norberto** (tallerista id 8, cod_prov 3709, alias
"Oscar"). Hay que conseguir otro proveedor para el envasado en skin. **Todavía no se tocó nada
en la base**: sigue `activo=true` y sigue en las rutas, porque hasta que no haya reemplazo
borrarlo dejaría 11 artículos sin paso final y sin costo.

**Qué se cae con él** `[dato 2026-09-07]`: **48 pasos de ruta** (`ruta_paso.tallerista_id=8`)
sobre **11 artículos** — el **506** (uña) y las **10 bombillas** (557/558/654/658/659 y sus
gemelos Chef 762/763/769/758/759). En todos es el **último paso**: recibe el cuerpo del garage
+ el pliego adhesivado, hace el skin y entrega en Virgilio. Su precio son 11 filas de
`GP2.precio_tallerista`: **$69/uni** las 10 bombillas ("Skin Bombillas", lista 2026-07-20) y
**$70/uni** el 506 ("Envasado 506", usuario 2026-09-01).

### Cotización RC Pack SRL (Gustavo Carmona) — recibida 2026-09-07, **DESCARTADA**

`[usuario 2026-09-07]` Dicho textual: *"esta cotización es malísima. Así que esta no la
consideres"*. **No se usa para nada**: ni para costear, ni como piso de negociación. Queda
asentada abajo sólo para no volver a pedirla ni volver a evaluarla.

`[dato: cotización en papel, At. LOCKEMEYER HNOS / Sr. Thomas, 2026-09-07]` RC Pack SRL,
Calle 39 N°2425, Villa Maipú, San Martín. Tel 5067-1877, gcarmona@rcpack.com.ar.
**Ojo: no es lo mismo que cotizó Gentile — RC Pack PONE EL CARTÓN**, así que reemplaza a la
vez a Gentile (envasado), a Pol (cartón) y a AJ (adhesivado).

| Concepto | Abrelatas (506) | Bombilla |
|---|---|---|
| Por unidad | $125 + US$ 0,09 material | $108 + US$ 0,07 material |
| Unidades por cartón | 12 | 16 |
| Con dólar $1.530 (`parametro.tipo_cambio_usd_pesos`) | **$262,70/uni** | **$215,10/uni** |
| **Hoy (Pol + AJ + Gentile)** | **$146,42/uni** (pliego $917/12 = $76,42 + envasado $70) | **$126,19/uni** (pliego $915/16 = $57,19 + envasado $69) |
| Diferencia | **+$116,28 (+79%)** | **+$88,91 (+70%)** |

Más **gasto por única vez: cortante de abrelatas $300.000 y cortante de bombillas $350.000**
($650.000 los dos).

Incluye: colocación en cartón, provisión del material y sellado skin, troquelado de bocas,
guardado y cierre de caja, etiqueta de caja y paletizado. **Caja y pallets los pone Loeke.**

**Antes de comparar en serio, tres cosas a preguntarle a RC Pack** `[deducido]`:
1. **¿El cartón viene impreso con el arte del SKU?** El de Pol sí ($786–$777 por pliego, uno
   por SKU) y es la mitad del costo actual. Si RC Pack cotiza cartón liso, la comparación de
   arriba no vale y hay que sumarle la impresión.
2. **La caja**: el papel dice "guardado en caja por 16 unidades" para bombillas, pero la caja
   A8 (N°2) hoy es **de 24**. Y en el mismo párrafo dice "cerrar caja por 12 unidades", que
   parece copiado del ítem del abrelatas. Confirmar.
3. **US$ a qué cambio y a qué fecha** se factura la parte en dólares.

### Blist-Pack es el proveedor activo del skin (2026-09-07)

`[usuario 2026-09-07]` **Blist-Pack pasa a ser el proveedor activo del envasado skin**, en
lugar de Gentile. Textual: *"la de Blisspack sí, porque va a ser el proveedor activo de
momento"*. **"De momento"**: es el reemplazo con el que se sigue trabajando hoy, no
necesariamente el definitivo.

⚠️ **LOS PRECIOS TODAVÍA NO ESTÁN CARGADOS.** El usuario los pasó en un mensaje que llegó
**sin el archivo adjunto**, así que a la fecha no hay un solo número de Blist-Pack en la base
ni acá. **Lo primero de la próxima sesión: pedirlos y cargarlos** en `GP2.precio_tallerista`
(tallerista_id 13), reemplazando las 11 filas de Gentile (id 8), y recién ahí dar de baja a
Gentile de las rutas.

### Lo que había de Blist-Pack antes de esto

`[dato 2026-09-07]` Se buscó y **no hay ningún precio de envasado de Blist-Pack cargado**:
es tallerista id 13 (cod_prov 3227) con **cero filas en `precio_tallerista`** y **cero pasos
en `ruta_paso`** — está dado de alta y nada más. Lo único suyo que existe es la nota de la
lista **2026-08-07: pliego adhesivado $147,97 por pliego** (§ lista de precios ago-26), que es
**otro producto** (el pliego, no el envasado) y encima **ni siquiera está en
`precio_proveedor`**: los pliegos con skin están cargados a **Pol 2147 + AJ 697**
($786 + $129 = $915 bombillas; $777 + $140 = $917 el 506). Para que Blist-Pack compita hay que
**pedirle cotización de envasado por unidad**.

## 4t. El 506 podría dejar de ir con skin y pasar a ser como el 510 (idea 7268, 2026-09-07)

`[usuario 2026-09-07]` Dicho textual: *"probablemente hagamos que dejemos de hacer el 506 con
skin, porque también desaparecería lo de AJ, para que pase a ser como el 510. El que va a
entregar va a ser el tallerista directo en Virgilio, en lugar de tener que ir a entregar a
Cervantes"*. **Es una idea, no una decisión** — queda registrada como **7268** en
`IDEAS-GP2.md`, con el análisis completo de qué habría que tocar.

**Contradice a §2c-septies** ("El 506 va con skin", usuario 2026-08-31). No se corrige esa
sección todavía porque la de hoy es una intención, no un hecho: si se ejecuta, se tacha aquella
y se anota el cambio de realidad.

### La diferencia real entre el 506 y el 510 es sólo el packaging

`[dato 2026-09-07]` Los dos son la uña; lo que cambia es cómo se envasa y quién entrega:

| | 506 (hoy, con skin) | 510 (el molde a copiar) |
|---|---|---|
| Cartón en la receta | `Pliego Ad 506` ×**1/12** ($917/pliego → $76,42/uni) | `A2B` "Cartón 510" ×**1** ($89/uni, formato C, Pol 2147) |
| Adhesivado | **AJ (prov 697)**, ruta 632, $140/pliego | — |
| Envasado | **Gentile** $70/uni | — (lo hace el mismo tallerista que arma) |
| Quién cierra | Alex/Martin arman GRJ7 → **entregan en Cervantes** → sale a Gentile → Virgilio | Alex/Martin arman y envasan → **`virgilio` directo** |
| Caja | `A11` N°29 ×1/12 | `A11` N°29 ×1/12 (**la misma**) |
| Rutas | 10 con paso de Gentile (42, 158, 159, 298, 572, 592, 593, 594, 595, 596) | 10 sin él, duplicadas por tallerista (160/215/302/303/490 Alex · 601/602/604/605/607 Martin) |

**El molde ya existe y está probado**: el 510 es exactamente el patrón destino, incluso con la
misma caja y los mismos dos talleristas. No hay que inventar nada, hay que copiarlo.

**Plata**: se van $76,42 (pliego) + $70 (Gentile) = **$146,42/uni** y entra el cartón suelto a
**$89** → **ahorro ~$57/uni** `[deducido, a confirmar el precio del cartón 506 troquelado
individual con Pol: el $89 es el que hoy paga el 510, y el 506 es del mismo formato C]`. Más lo
que se ahorre de logística, que es la mitad del planteo del usuario.

**⚠️ Antes de usar cualquier número de estos para decidir, hay un desfasaje que entender**
`[dato 2026-09-07, sin explicar]`: `v_costo_componente` da hoy **506 = $1.519,65** contra
**510 = $486,93**, pero la cuenta a mano del 506 (GRJ7 $275,47 + pliego $76,42 + caja $13,90 +
Gentile $70) da **~$436**. Sobran ~$1.084 que no salen de la receta. La sospecha es que las dos
variantes de cuerpo (Fleje 13 → J2 → `A10` vía Jade, y Fleje 57 → L13 → `C10` vía FAAT +
Guazzaroni) se **suman** en vez de que la vista elija una — que es justo lo contrario de lo que
se verificó para GRJ5/GRJ6 en §4c. **Hay que medirlo antes y después del cambio**, si no el
ahorro no se va a poder ver en el costo.

### AJ no se queda sin trabajo

`[dato 2026-09-07]` AJ adhesiva **12 pliegos**: el 506, el 500 (discontinuo) y los 10 de
bombillas (rutas 632, 672-682). Sacar el 506 le quita **1 de 12**, no lo da de baja. El que sí
queda tocado es **el volumen que se le cotiza al proveedor de skin**: si el 506 sale, a
Blist-Pack hay que pedirle el precio **por las 10 bombillas solas**, no por los 11 artículos.

## 4u. La lista de Blist-Pack, y cómo arma el envasado la planilla madre (2026-09-07)

`[dato 2026-09-07: `A_Costos_VIGENTES.xlsx` que pasó el usuario, hoja «Lista de Precios », y
las fórmulas de la hoja «Costos»]` El usuario pidió registrar los costos de Blist-Pack. Están
acá abajo tal como figuran. **No se cargaron en la base todavía**, y el porqué está al final:
la planilla dice que son otra cosa que lo que se esperaba.

### Los 5 precios de Blist-Pack SA (3227) — lista 2026-08-07

Contacto: **Héctor 11 5609-5499 / 11 3072-3749**. Nota del bloque: *"15.000 piezas en un turno"*.

| Cod ISIS | Producto | $ ARS | Detalle | Últ. compra |
|---|---|---|---|---|
| 1906 | **Skin Bombilla** | **147,97** | — | 2026-04-15 |
| 1896 | **Skin Mariposa Uña** | **193,05** | **12 bocas** | 2026-05-19 |
| 2906 | **Skin Patita Pie** | **193,05** | — | 2026-05-11 |
| 0406 | **Skin Mariposa Uña Chef** | **131,89** | **20 bocas** | 2026-05-04 |
| 1907 | **Etiquetas EAN** | **92,40** | — | 2026-03-25 |

Historia de la 1906: 147,97 (ago-26) ← 135,33 ← 125 ← 80 ← 76,08 ← 68 ← 29,50 ← 11,84 ← 6,97
← 6,24. En tres de las cinco filas el propio usuario dejó escrito **«VER A QUIEN REEMPLAZA»**.

### Cómo arma la planilla el "Envas. Terc." — y por qué Blist-Pack no es el reemplazo de Gentile

`[dato 2026-09-07: fórmulas de la hoja «Costos», columna K]` La columna **«Envas. Terc.»** es
literalmente **AJ por pliego ÷ bocas + Gentile por unidad**:

- **506** (fila 29): `='Lista de Precios'!L225/12 + L232` = **$140 (AJ, 56×41 mm) ÷ 12 + $70
  (Gentile)** = **$81,67/uni**.
- **557 y 558** (filas 205 y 207): `=L227/16 + L233` = **$129 (AJ, 47×43 mm) ÷ 16 + $69
  (Gentile)** = **$77,06/uni**.
- **510** (fila 27): **la celda está VACÍA.** No tiene envasado tercero — es exactamente lo que
  dijo el usuario y lo que motiva la idea 7268.

> ⚠️ **CORREGIDO EL 2026-09-07 POR EL USUARIO.** Lo que sigue en esta lista (los tres puntos
> «deducidos») **estaba mal**. Textual: *"Blistpack cobra $193 x unidad de skineado"*. Los
> precios de Blist-Pack son **POR UNIDAD**, igual que los de Gentile — las notas «12 bocas» /
> «20 bocas» describen la herramienta, no la unidad de venta. Se deja el razonamiento tachado
> abajo porque el error es instructivo: **parecerse en el importe a otro proveedor no dice nada
> sobre la unidad de medida**, y acá esa suposición se comió el dato. Las conclusiones buenas
> están en §4u-bis.

~~**Tres cosas se deducen de esto, y hay que decidirlas antes de cargar nada**~~ `[deducido, ERRÓNEO]`:

1. **Los precios de Blist-Pack son POR PLIEGO, no por unidad.** Las notas «12 bocas» / «20
   bocas» son las posiciones del pliego, y los importes ($131,89 – $193,05) son **del mismo
   orden que los de AJ** ($129 – $140 por pliego), no del orden de Gentile ($69 – $70 por
   unidad). Si fueran por unidad, Blist-Pack cobraría **2,8 veces** lo de Gentile por el mismo
   trabajo.
2. **Entonces Blist-Pack compite con AJ (el adhesivado del pliego), no con Gentile (el
   envasado).** Y encima **más caro**: para la uña, $193,05 ÷ 12 = **$16,09/uni** contra los
   **$11,67/uni** de AJ. Eso explica el «VER A QUIEN REEMPLAZA» que escribió el usuario: ni él
   tenía claro a quién sustituye esta lista.
3. **Ninguna de las 5 filas alimenta un solo costo**: se buscaron todas las fórmulas del libro
   y hay **cero referencias** a las filas 241-245. La lista está cargada pero no la usa nadie.

⚠️ **Por eso NO se escribieron en `GP2.precio_tallerista`.** Meter $147,97 como precio por
unidad del envasado duplicaría el costo de las 10 bombillas con un dato mal leído, y la casa no
inventa datos de negocio (regla de `CLAUDE.md`). **Pregunta abierta al usuario**: ¿Blist-Pack va
a hacer el **envasado completo** que hacía Gentile (y entonces falta que cotice eso, por
unidad), o va a hacer **el skin del pliego** en lugar de AJ (y entonces estos 5 precios se
cargan en `precio_proveedor` / `precio_servicio_pieza`, no en `precio_tallerista`)?

### Hallazgo lateral: el cartón del 506 no coincide entre la planilla y GP2

`[dato 2026-09-07]` La hoja « Cartones» le da al **506 un cartón de $89 — el mismo que al 510**
(filas 255 y 250, las dos «Abrelatas», las dos $89). Pero el 506 va en **pliego de 12**: el
pliego sin adhesivar de Pol sale $777, o sea **$64,75 la posición**. GP2, por su lado, lo cobra
a **$76,42** (el `Pliego Ad 506` de $917 ÷ 12).

Las bombillas **sí cierran**: la planilla pone $49,125 de cartón (= $786 ÷ 16, el pliego sin
adhesivar) y $8,06 de AJ en otra columna; GP2 pone los dos juntos en el `Pliego Ad` de $915 ÷ 16
= $57,19. **Misma plata, distinta columna.**

El 506 es el único que no cierra: **planilla $89 vs GP2 $76,42, con $24,25/uni de diferencia**
contra el pliego real de Pol. Huele a que el $89 se copió de la fila del 510 sin ajustar. **Si
se ejecuta la idea 7268 el problema se disuelve solo** (el 506 pasaría a usar cartón suelto y
$89 sería el número correcto); si no, hay que corregir uno de los dos lados.

## 4u-bis. Blist-Pack cobra POR UNIDAD: qué queda en pie (2026-09-07)

`[usuario 2026-09-07]` Textual: **"Blistpack cobra $193 x unidad de skineado"**. Corrige la
deducción de §4u. Los 5 precios de su lista son **$/unidad**, no por pliego.

### Lo que cuesta el skineado, por unidad, con cada uno

| | Gentile (†) | **Blist-Pack** | Salto |
|---|---|---|---|
| Uña 506 | $70 | **$193,05** | **+$123,05 (+176%)** |
| Bombillas (las 10) | $69 | **$147,97** | **+$78,97 (+114%)** |

**El reemplazo de Gentile sale entre 2,1 y 2,8 veces lo que se pagaba.** Eso no es una
objeción — Gentile ya no está y hay que envasar igual — pero es la plata que se mueve, y
cambia dos cosas que ya estaban escritas:

**1. La cotización de RC Pack deja de ser "malísima" contra esta referencia.** RC Pack incluye
el cartón; Blist-Pack no, así que para comparar hay que sumarle el pliego:

| Por unidad | RC Pack (con cartón) | Blist-Pack + pliego | Gana |
|---|---|---|---|
| **506** | **$262,70** | $193,05 + $76,42 = **$269,47** | **RC Pack, por $6,77** |
| **Bombilla** | **$215,10** | $147,97 + $57,19 = **$205,16** | Blist-Pack, por $9,94 |

Quedan casi empatados, y en el 506 **RC Pack sale más barato**. El usuario descartó a RC Pack
el 2026-09-07 (§4u) **cuando todavía se creía que Blist-Pack cobraba por pliego**; con el precio
real la comparación es otra. `[deducido]` Falta meter en la cuenta los **$650.000 de cortantes**
de RC Pack por única vez, que a volumen alto se diluyen y a volumen bajo no.

**2. La idea 7268 (el 506 sin skin) pasa a valer mucho más.** Si el 506 deja el skin, no se
ahorran los $70 de Gentile sino **los $193,05 de Blist-Pack**: contra el cartón suelto de $89,
el ahorro salta de ~$57 a **~$180/uni**. Es, de lejos, la palanca más grande que hay sobre la
mesa.

✅ **Mapeado y cargado el 2026-09-08** — ver §4u-ter.

## 4u-ter. El mapeo Blist-Pack, contestado por el usuario (2026-09-08)

`[usuario 2026-09-08]` Los 5 productos de la lista de Blist-Pack contra los 11 artículos que
hacía Gentile. Respuestas textuales a las 6 preguntas:

| Producto de Blist-Pack | $ | Va a | |
|---|---|---|---|
| `Skin Mariposa Uña` | $193,05 | **506** | ✅ cargado |
| `Skin Bombilla` | $147,97 | **las 10 bombillas** (557, 558, 654, 658, 659, 758, 759, 762, 763, 769) | ✅ cargado |
| `Skin Mariposa Uña Chef` | $131,89 | *(era para el 706, que ya no lleva skin)* | ❌ no se usa |
| `Skin Patita Pie` | $193,05 | *"deja sin blistpack, que quede como ahora"* | ❌ no se usa |
| `Etiquetas EAN` | $92,40 | *"no va"* | ❌ no se usa |

**Lo que define el alcance del precio** (esto es lo que hace que el número sirva o no):

- **Blist-Pack arma y encaja**, no sólo skinea `[usuario]`. O sea: el precio cubre lo mismo que
  cubría el "Skin **y Arm.**" de Gentile. No hay que agregar un paso de armado a nadie.
- **El cartón se lo damos nosotros**, *"misma lógica que Gentile"* `[usuario]`. **El pliego de AJ
  sigue en pie**: el costo real por unidad es `$193,05 + pliego/12` para el 506 y
  `$147,97 + pliego/16` para las bombillas. Blist-Pack **no** reemplaza a AJ.

**Dos artículos salen del circuito de skin:**

- **706 (Uña Chef): ya no va más con skin, entrega Martín directo** `[usuario]`. La base ya
  estaba así — el paso final del 706 es Martín Cornejo con `Cartón 706` suelto, y Gentile nunca
  tuvo un `ruta_paso` del 706 pese a tener precio en su lista. No hubo nada que cambiar.
- **555 (Limpia Bombilla): mismo costo que las bombillas** ($147,97) `[usuario]`. **Pero el 555
  no existe en GP2**: ni artículo, ni componente. No se cargó nada (no se inventan datos); queda
  el precio anotado acá para cuando el 555 se dé de alta.

### Lo que quedó escrito en la base

11 filas nuevas en `GP2.precio_tallerista` para el tallerista 13 (Blist-Pack), una por cada
`XXX Terminado`, con el `referencia` diciendo que el cartón no está incluido. Los precios viejos
de Gentile (tallerista 8) **quedan**: sirven de comparación y son el histórico de lo que se pagó.

### ⚠️ Lo que todavía NO se hizo: las rutas siguen apuntando a Gentile

**Los 48 `ruta_paso` de los 11 artículos siguen con `tallerista_id = 8` (Gentile, fallecido).**
Cargar el precio no mueve la ruta. Mientras eso siga así, el motor de costos sigue valorizando
con los $70/$69 de Gentile y las pantallas siguen mandando el trabajo a un tallerista muerto.
Cambiar los 48 pasos a Blist-Pack es una cirugía aparte, y **no es sólo un UPDATE**: mueve a
quién se le envía y de quién se recibe (ubicación, envíos, recepción). Falta el OK del usuario.

**Cuando se haga, esto es la plata que se mueve** (sólo el envasado, sin el pliego):

| | Gentile (†) | Blist-Pack | Salto |
|---|---|---|---|
| 506 | $70 | $193,05 | **+$123,05 (+176%)** |
| Cada bombilla (x10) | $69 | $147,97 | **+$78,97 (+114%)** |

## 4v. La planilla madre de costos vive en la base (2026-09-07)

`[usuario 2026-09-07]` Pedido textual: *"Guarda costos de alguna manera en supabase para que no
lo tenga que subir siempre a cada sesion. Que quede alla como archivo de consulta"*. Eligió
**crudo + vistas encima** y **las 16 hojas de costos** de las 58 del libro.

### Cómo quedó

**No se guardó el `.xlsx`**: un blob de 7,8 MB no se consulta con SQL y habría que bajarlo
entero igual. Se guardó el contenido, en dos tablas:

| Tabla | Qué es |
|---|---|
| `GP2.planilla_snapshot` | Una fila por subida del archivo. `vigente=true` es la última. |
| `GP2.planilla_fila` | Una fila por fila del Excel: `hoja`, `fila`, `datos` (jsonb, las celdas por letra de columna), `formulas` (jsonb, sólo donde se guardaron) y `bloque` (el encabezado de proveedor arrastrado). |

Y dos vistas con columnas de verdad, que es como se consulta en el día a día:

- **`GP2.v_planilla_costo`** — la hoja «Costos»: `cod`, `familia`, `fabricante`, `descripcion`,
  `compra_3ros`, `material`, `remaches`, `tratamientos`, `tallerista`, `plastico_mango`,
  **`envasado_terceros`**, `carton`, `cajas`, `cod_y_precinto`, `costo_sin_aporte`,
  `aporte_produccion`, más **`formula_envasado`** y el jsonb `formulas` entero.
- **`GP2.v_planilla_precio`** — la hoja «Lista de Precios »: `proveedor` (del encabezado de
  bloque), `cod_prov`, `cod_isis`, `moneda`, `precio_proveedor`, `precio_ipc_al_dia`,
  `fecha_lista`, `cod_art`, `producto`, `tomado_en_costos`, `rubro`, `ultima_compra`, `detalle`.

Dos helpers, porque la planilla mezcla texto y plata en la misma columna (`"xx"`, `#REF!`,
direcciones y teléfonos donde en otras filas hay precios): **`GP2.planilla_num(text)`** y
**`GP2.planilla_fecha(text)`** devuelven `null` en vez de reventar.

### Por qué se guardan las FÓRMULAS y no sólo los valores

Porque fue **la fórmula la que explicó el dato**. `v_planilla_costo.formula_envasado` del 506
dice `='Lista de Precios '!L225/12 + L232`, o sea **AJ por pliego ÷ 12 + Gentile por unidad**;
la del 557/558 es `L227/16 + L233`. Sin eso, «Envas. Terc. = $81,67» es un número mudo. El 510
tiene esa celda **vacía**, que es exactamente lo que sostiene la idea 7268. Un valor dice
cuánto; la fórmula dice de quién.

### Cómo se recarga cuando el usuario mande una planilla nueva

1. `select "GP2".planilla_snapshot_nuevo('A_Costos_VIGENTES.xlsx', '<nota>', '<quien>');` —
   marca los anteriores `vigente=false` y devuelve el id nuevo.
2. `select "GP2".planilla_cargar(<id>, '<lote>'::jsonb)` por lote. Formato del lote:
   `{"<hoja>": [[fila, {celdas}, bloque?, {formulas}?], ...]}`. Es **idempotente**: reejecutar
   un lote no duplica.
3. Las vistas no hay que tocarlas: leen la tabla, sea cual sea el snapshot.

⚠️ **El cuello de botella es el canal, no la base.** El proxy de egreso **bloquea
`*.supabase.co`** (403 de política, no se rodea), así que la API REST no se puede usar desde
la sesión y **todo tiene que entrar por el MCP**, en lotes de ~26 KB. Por eso la carga es lenta
y se hace por tandas. El repo es privado, así que tampoco sirve dejar los datos en
`raw.githubusercontent.com` para que los baje la extensión `http` de Postgres (que **sí** está
instalada, versión 1.6, por si algún día hay una fuente alcanzable y confidencial).

### Estado de la carga (snapshot 1) — TERMINADA el 2026-09-08

**Las 16 hojas de costos están adentro: 4.456 filas.** No hay que volver a subir el Excel.

| Hoja | Filas | Hoja | Filas |
|---|---|---|---|
| `Costos` (con fórmulas) | 278 | `Materiales` | 299 |
| `Lista de Precios ` | 1.046 | `Talleristas-Procesos` | 290 |
| `Cajas ` | 473 | `Tratamientos ` | 275 |
| ` Cartones` | 434 | `Conversion cod Loeke Chef` | 234 |
| `Materiales Loeke` | 226 | `Talleristas` | 205 |
| `Remaches` | 169 | `Importados` | 151 |
| `Bombillas` | 138 | `Flejes` | 83 |
| `Ranking Compra Prov` | 83 | `Plasticos` | 72 |

**Lo que NO entró, y por qué** (contado contra el Excel, hoja por hoja: todo lo demás cierra
exacto):

- Se guardaron las columnas **A..P**; lo que vive más a la derecha se perdió. En
  `Lista de Precios ` eso son las columnas `Q..AS`, que son el **historial de fechas de compra**
  (una fecha por compra, hasta 29 columnas). Los precios están todos.
- En `Lista de Precios ` faltan **174 de 1.220 filas**, y ninguna trae un precio: **90 son la
  cabecera repetida** de cada bloque de proveedor (esa información ya está, en la columna
  `bloque` de cada fila), **69 son filas de ceros** que separan bloques, y **15 traían solo
  `H=0` más fechas de compra en `Q..AS`**.
- Las tres filas sueltas que el generador se había salteado (`Costos` 1 = "Lista Chef" en la
  columna W, `Materiales` 297 y 320 = un número suelto en E) se cargaron a mano después.

El `nota` del snapshot 1 dice todo esto en la base, para el que consulte desde SQL sin tener
este archivo a mano.

## 4w. El cruce planilla vs GP2: `v_costo_componente` ignora las cantidades (2026-09-08)

`[usuario 2026-09-08]` Pedido: *"Revisa que el costo sin aportes de la hoja costos te de igual
que en tu programa, salvo por cod/precinto"*. **No da igual.** Y el cruce encontró un bug de
fondo en el motor de costos.

### Cómo se comparó

- **Planilla**: `costo_sin_aporte` (columna O de `Costos`) **menos** `cod_y_precinto` (columna N),
  como pidió el usuario. La hoja cierra sola: en las 264 filas con costo,
  `O = suma(E..N)` exacto, así que la columna es confiable.
- **GP2**: `v_costo_componente.total_pesos` del componente `«<cod> Terminado»`.
- **Universo comparable: 60 artículos.** GP2 modela 99 (91 con el componente `«cod Terminado»`);
  la planilla tiene 264 filas (incluye Chef, importados y discontinuos que GP2 no modela).

### El resultado

| | Dentro del 2 % | Dentro del 10 % | Sobrevalúa | Sesgo medio | Peor caso |
|---|---|---|---|---|---|
| **`v_costo_componente` (hoy)** | **1 de 60** | 5 | **54 de 60** | **+73 %** | **+347 %** (557) |
| Recalculado por receta | 6 de 60 | 9 | 7 de 60 | −24 % | +137 % |

**El sesgo es de una punta: GP2 sale más caro en 54 de 60**, y el exceso está casi todo en
`material_pesos`.

### La causa: la vista cobra el insumo ENTERO, no la parte que se usa

`v_costo_componente` no recorre la receta (`articulo_componente`): recorre el **grafo de rutas**
(`ruta_paso`, CTE recursivo `w`/`wd`) y suma el costo de cada insumo que alcanza. **En esa
recursión nunca entra `ruta_paso.cantidad`.** En el CTE `mat` se ve la línea exacta:

```sql
CASE WHEN cb_1.sector_id = 5   -- flejes: sí multiplica, por kg_ref
     THEN cb_1.precio * COALESCE(wd.kg_ref, 1/m.partes_por_kilo_de_fleje)
     ELSE cb_1.precio          -- <<< TODO LO DEMÁS: precio entero, sin cantidad
END AS val
```

O sea: **sólo los flejes (sector 5) se prorratean**, vía `kg_ref`. Todo lo demás —cartones,
pliegos, cajas— entra al costo **por unidad entera de insumo**, no por la fracción que consume
un artículo.

**El caso más claro, la bombilla 557** (planilla: $401,96 sin cod/precinto):

| Insumo | Se usa | Cuesta | Debería aportar | La vista carga |
|---|---|---|---|---|
| `GRJ6` Bombilla Resorte Chata | 1 | $264,45 | $264,45 | $264,45 ✅ |
| `Pliego Ad 557` | **1/16** | $915,00 | **$57,19** | **$915,00** ❌ |
| `Caja N°2` (`A8`) | **1/24** | $261,82 | **$10,91** | **$261,82** ❌ |

Un pliego rinde 16 bombillas y una caja lleva 24, pero la vista le carga a **cada** bombilla el
pliego entero y la caja entera. Por eso 557 da $1.796 en vez de $402: **+347 %**.

### La prueba de que la receta sí está bien

Recalculando a mano `Σ(articulo_componente.cantidad × costo del hijo) + envasado`:

| | 557 | 558 | 659 | 658 | 104 | 505 | 550 |
|---|---|---|---|---|---|---|---|
| Planilla | 402 | 403 | 2.142 | 1.172 | 704 | 330 | 204 |
| **Por receta** | **402** | **402** | **2.142** | **1.172** | **700** | **325** | **197** |
| Vista hoy | 1.796 | 1.796 | 5.324 | 3.384 | 1.621 | 667 | 652 |

**Clavado.** Los datos de GP2 (recetas, cantidades, precios) están bien; **lo que está mal es
cómo la vista los suma.**

### Lo que esto desbloquea y lo que ensucia

- **Explica el misterio del 506** que estaba anotado como bloqueante de la idea 7268: la vista
  daba $1.519,65 y la cuenta a mano ~$436. La sospecha vieja era "se suman las dos variantes de
  cuerpo (Jade→`A10` y FAAT/Guazzaroni→`C10`)"; **era falsa**. Es esto: el pliego y la caja se
  cobran enteros. Por receta el 506 da **$436** contra $494 de la planilla (−12 %), coherente.
- **Todo lo que lee `v_costo_componente` está inflado**: valorización de stock, "Máximo por
  sector", el costo que se mira para decidir precios. Cuanto más comparte el artículo un envase
  (pliegos de 12/16, cajas de 24), más se infla.
- El residual **−24 %** del método por receta es otra cosa y más chica: recetas incompletas
  (falta cargar algún componente), no un error de fórmula.

**Está anotado como idea 7269. No se tocó la vista**: arreglarla mueve todos los números de
plata de la app y es una cirugía que el usuario tiene que autorizar.

## 4x. El costo de los más vendidos (Est Madre) — por dónde empezar (2026-09-08)

`[usuario 2026-09-08]` *"Empezá por el costo de los más vendidos de la est madre"*. Ordenado el
error de costo (§4w) por volumen de venta, para atacar por plata y no por código.

### El tamaño del problema, en plata

`GP2.est_madre` proyecta **267.595 uni/mes** en 405 productos. **59 artículos** cruzan las tres
puntas (Est Madre + planilla + GP2) y son **164.498 uni/mes, el 61 % del volumen**:

| | $/mes |
|---|---|
| Costo según la planilla | **$123.948.841** |
| Costo según `v_costo_componente` | **$221.397.987** |
| **Inflado** | **+$97.449.146/mes (+79 %)** |

**Y está concentrado**: el **top 10 explica el 71 %** del inflado y el top 20 el **87 %**.
Arreglando diez artículos se corrige casi todo.

### Los 10 más vendidos, uno por uno

| # | Cod | Uni/mes | Planilla | Vista | Receta | Inflado/mes | Qué le pasa |
|---|---|---|---|---|---|---|---|
| 1 | **505** | 28.184 | $330 | $667 | **$325** | $9,5 M | **Sólo la vista.** La receta cierra al −1,4 % |
| 2 | **506** | 16.968 | $494 | $1.520 | $436 | **$17,4 M** | Vista +208 %; y el cartón: GP2 $76,42 vs planilla $89 |
| 3 | **031** | 15.144 | $279 | $582 | $93 | $4,6 M | **Modelo distinto** (abajo) |
| 4 | **513** | 14.252 | $620 | $884 | $511 | $3,8 M | A la receta le falta el tallerista ($219 en la planilla) |
| 5 | **586** | 7.960 | $410 | $810 | $318 | $3,2 M | **`Cuch China` vale $0** en GP2 |
| 6 | **504** | 7.826 | $1.358 | $3.267 | $881 | **$14,9 M** | Vista +141 %; falta el tallerista ($234) |
| 7 | **546** | 7.700 | $1.464 | $3.022 | $1.343 | **$12,0 M** | Vista +106 %; la receta cierra al −8 % |
| 8 | **501** | 6.680 | $1.997 | $2.268 | $1.371 | $1,8 M | Vista +14 % |
| 9 | **510** | 6.352 | $382 | $487 | $204 | $0,7 M | Vista +28 % |
| 10 | **502** | 6.244 | $1.202 | $1.489 | $964 | $1,8 M | Vista +24 % |

**Los tres de arriba en plata son el 506 ($17,4 M), el 504 ($14,9 M) y el 546 ($12,0 M)** —
juntos, $44,3 M/mes, casi la mitad del total. No son los tres más vendidos: son los que combinan
volumen con un error grande.

### Lo que aprendimos ordenando por volumen: no alcanza con arreglar la vista

De los 10 más vendidos, **sólo 1 (el 505) tiene la receta completa**. En los otros nueve, aun
arreglando la 7269 el número seguiría mal, por tres motivos distintos:

**a) A la receta le falta el paso del tallerista.** El 513 ($219/uni) y el 504 ($234/uni) pagan
un tallerista que la planilla cobra y `articulo_componente` no tiene: ese paso vive en
`ruta_paso`, no en la receta. **Esto es importante para el arreglo de la 7269**: la solución NO
es cambiar la vista para que lea la receta — es que **siga recorriendo la ruta (que es la que
trae talleristas y servicios) pero multiplicando por `ruta_paso.cantidad`**.

**b) Hay componentes que valen $0.** El que más pega es **`Cuch China`**, que está en la receta
del 586, el 123, el 099 y el 108 — **11.388 uni/mes con la cuchilla a costo cero**. Otros:
`Cuchilla Laser` (587), `Alambre Corta Queso` y `Tornillo Corta Queso` (574, 119, 809),
`Argolla Grande`/`Chica` (057, 516, 498, 499, 700), `Vastago Sacafuente Pizzero` (518, 508, 708),
`Cartón 516`, `Cartón 515`, `Cartón 119`, y `Abrelata Uña Pie 500`. **No se inventó ningún
precio**: van como idea 7270 para que los aporte el usuario.

**c) El 031: es el cartón, no el modelo.** ⚠️ **Corregido el 2026-09-08 al armar el archivo de
comparación.** Acá decía que la planilla lo compra hecho a terceros y GP2 lo fabrica: **es falso**.
Los $230 de `Compra 3ros` de la planilla son `Lista de Precios !L532` = **el AyE de IJUPA**, y GP2
tiene ese mismo AyE de IJUPA a **$230 exactos**. Los dos lados lo modelan igual. La diferencia real
es **el cartón: $0,252 en la planilla contra $63 en GP2** — y el $0,252 sale del `IFERROR(...,0)`
de §4w, o sea que **no es un precio, es un cero disfrazado**. El resto: material $42,08 vs $21,78 y
caja $6,95 vs $8,67.

### El orden de trabajo que sale de esto

1. **Arreglar la 7269** (la vista multiplica por `ruta_paso.cantidad`, siguiendo la ruta). Es lo
   que destraba los 10 de una: hoy sobrevalúa a los 59 en $97,4 M/mes.
2. **Cargar los precios faltantes** (idea 7270), empezando por `Cuch China` (11.388 uni/mes).
3. **Decidir el modelo del 031** (compra vs fabricación) — el 3.º más vendido.
4. **Revisar el cartón del 506** ($76,42 vs $89) — ya estaba anotado en §4t.

### 4x-bis. El 505 componente por componente (2026-09-08)

`[usuario 2026-09-08]` *"Veamos el 505. Decime los componentes que tiene el archivo de costos y
los componentes que tiene en Gestión Productiva."* El 505 es el más vendido (28.184 uni/mes).

**Planilla** (`Costos` fila 9, "Pelador Mgo Plast"), siguiendo cada fórmula hasta su hoja:

| Componente | $ | Sale de |
|---|---|---|
| Cuchilla Pelador — fleje 13,6×0,8, **6,7558 g c/desp** × $5.183,34/kg | 35,02 | `Materiales!I74` |
| Clavo — 6,3 g × $5.060,66/kg | 31,88 | idem |
| Cuchilla — cementado | 36,53 | `Tratamientos !N84` |
| Cuchilla — zincado/pavonado | 9,40 | idem |
| Clavo — niquelado | 20,16 | idem |
| **Calado Manguito Pelador** (prov 4247) | 3,87 | `Lista de Precios !L522` |
| Cerrado de la cuchilla (prov 3805, $775,005/kg × 4,95 g) | 3,84 | `L592/1000*4,95` |
| Pelador Plastico(505) **AyE** (prov 3806) | 33,00 | `L555` |
| Mgo Pelador (505) Rojo — PP 5,72 g $20,58 + inyección $42,48 | 63,06 | `Plasticos!K23` |
| Cartón 505 (tipo 2) | 79,00 | `' Cartones'!B:F` |
| Caja 505M makro — $166,86 ÷ 12 | 13,91 | `'Cajas '!G129` |
| **Total sin cod/precinto** | **329,66** | |

**GP2** — 5 filas en `articulo_componente` **más** un paso de ruta:

| Componente | Cant | Costo | Aporta |
|---|---|---|---|
| Cuchilla Pela Afilada Caja | 1 | 119,22 | 119,22 |
| Cartón 505 | 1 | 79,00 | 79,00 |
| Mgo Pelapapa 505 Calado | 1 | 63,06 | 63,06 |
| Clavo 505 Niq. | 1 | 49,99 | 49,99 |
| Caja N°29 | 1/12 | 166,86 | 13,91 |
| *(en `ruta_paso`, no en la receta)* AyE Danica/Lucho | | 33,00 | 33,00 |
| **Total** | | | **358,17** |

La cuchilla y el clavo no son insumos sueltos: son cadenas de 8 rutas (57, 58, 295–297, 486,
547–550). `Fleje N° 19` → matriz 1 → `Cuchilla Pelapapa Abierta` → **Martin Cornejo** (cerrar) →
FAAT (cementado) → Mabra (pavonado) → matriz 501 → `Cuchilla Pela Afilada Caja`. Y
`Clavo 505` → **Guazzaroni** (niquelado) → `Clavo 505 Niq.`

### El cruce, línea por línea

| Concepto | Planilla | GP2 | Δ |
|---|---|---|---|
| Cuchilla — fleje | 35,02 (**6,76 g** c/desp) | 25,44 (**4,92 g** netos) | **−9,58** |
| Cuchilla — cementado + pavonado | 45,93 | 25,38 | **−20,55** |
| Cuchilla — cerrado (Martin) | 3,84 | 3,81 | −0,03 ✅ |
| Cuchilla — MO de matriz (1 y 501) | **0** (va a Aportes) | **68,39** | **+68,39** |
| Clavo — material + niquelado | 52,04 | 49,99 | −2,05 |
| Mango plástico | 63,06 | 63,06 | **0** ✅ |
| **Calado del manguito** | 3,87 | **no está** | **−3,87** |
| Cartón | 79,00 | 79,00 | **0** ✅ |
| Caja (1/12) | 13,91 | 13,91 | **0** ✅ |
| AyE | 33,00 | 33,00 | **0** ✅ |
| **Total** | **329,66** | **358,17** | **+28,51** |

**Cuatro conceptos dan exacto** (mango, cartón, caja, AyE). Los que no:

1. **La planilla NO pone la mano de obra interna en `Costo sin aportes`** — va a la columna
   `Aporte Produccion` (para el 505, $571,24). GP2 sí la mete en `total_pesos` ($68,39 de
   matricería). **Sacándola, GP2 da $289,78 contra $329,66: −12 %.** Medido sobre los 59
   artículos, esta mano de obra son **$5,1 M/mes, el 5 % del inflado** — no cambia el
   diagnóstico de la 7269 (el 95 % restante sigue siendo la cantidad), pero para comparar
   contra la planilla hay que restarla.
2. **GP2 no cobra el desperdicio del fleje.** El `Fleje N° 19` tiene `kg_x_uni` = **6,84 g** (con
   desperdicio, casi igual a los 6,7558 g de la planilla) y su precio coincide ($5.171,40/kg vs
   $5.183,34), pero la vista termina cobrando **4,92 g** — el peso de la `Cuchilla Pelapapa
   Abierta`. El CTE `mat` usa el `kg_ref` de la pieza que sale, no del fleje que entra.
3. **Los servicios de la cuchilla salen a la mitad**: $25,38 contra $45,93. `precio_servicio_pieza`
   tiene el precio en NULL para el cementado de FAAT y el pavonado de Mabra, y cae a
   `tarifa_servicio`.
4. **Falta el calado del manguito** ($3,87, prov 4247). En GP2 el mango entra como insumo ya
   calado (`Mgo Pelapapa 505 Calado`, $63,06 = material + inyección) y el servicio de calado no
   está en ninguna ruta.

⚠️ **Corrección de §4x**: ahí figura que el 505 "tiene la receta completa, cierra al −1,4 %".
Ese −1,4 % salió de comparar sólo las 5 filas de `articulo_componente` ($325,17) **sin sumarle el
AyE de $33** (el cálculo buscaba el envasado en `precio_tallerista` del tallerista 8, Gentile, que
el 505 no tiene). Sumando el AyE da $358,17, **+8,6 %**. La receta del 505 igual es la más sana de
los 10 más vendidos, pero no cierra sola: le falta el calado y le sobra la MO de matriz.

### 4x-ter. El archivo de comparación de los 10 (2026-09-08)

`[usuario 2026-09-08]` Pedido: un archivo para ver, de los 10 más vendidos, cuáles cuadran y
cuáles no, y cuál es la diferencia entre el Excel y GP2.
→ **`Informes/salidas/Comparacion_Costos_Top10.xlsx`**, 5 hojas: `Resumen`, `Por concepto`
(la que importa: los 6 conceptos lado a lado con semáforo), `Componentes GP2`,
`De dónde sale el Excel` (la fórmula real de cada celda de `Costos`) y `Cómo leerlo`.

**Comparando bien** — Excel = `Costo sin aportes` − cod/precinto; GP2 = **receta + el AyE del
tallerista que vive en la ruta** (no la vista, que tiene el bug 7269):

| Cód | Excel | GP2 | Dif | ¿Cuadra? |
|---|---|---|---|---|
| 546 | 1.463,97 | 1.453,16 | −0,7 % | **SÍ** |
| 513 | 619,72 | 597,07 | −3,7 % | **SÍ** |
| 501 | 1.996,65 | 1.861,66 | −6,8 % | CASI |
| 505 | 329,66 | 358,17 | +8,6 % | CASI |
| 502 | 1.201,56 | 1.097,28 | −8,7 % | CASI |
| 506 | 493,82 | 435,79 | −11,8 % | CASI |
| 586 | 409,77 | 352,12 | −14,1 % | CASI |
| 031 | 279,28 | 323,45 | +15,8 % | NO |
| 504 | 1.358,19 | 1.012,08 | −25,5 % | NO |
| 510 | 381,81 | 231,08 | −39,5 % | NO |

**Lo importante: sacando el bug de la vista, GP2 no está lejos.** 2 cuadran dentro del 5 %, 5 más
dentro del 15 %, y sólo 3 se van feo. Contra la vista actual el mismo grupo daba +73 % de sesgo:
**la distancia real entre el Excel y GP2 es chica; lo que estaba roto era la vista.**

⚠️ **CORREGIDO el 2026-09-08 — el usuario marcó que los rubros no cerraban.** La primera versión
del archivo agrupaba los costos de GP2 **por el sector donde se guarda cada pieza**, y el sector de
GP2 no es el rubro del Excel: el `Clavo 505 Niq.` vive en `Sector Plástico` pero **es una pieza de
metal**, así que caía en la columna de plástico en vez de material. Los totales daban bien y los
rubros no eran comparables — un total parecido tapando diferencias que se compensan. **Ahora los 6
rubros se arman por TIPO DE COSTO en los dos lados**, usando el desglose real de la vista
(`material_usd × TC + material_pesos`, `servicios_*`, `mano_obra_pesos`) más el AyE de la ruta.

Con el bucketeo bien, **el 505 pasa a tener 4 de 6 rubros exactos**:

| Rubro (505) | Excel | GP2 | |
|---|---|---|---|
| Material (metal / fleje) | 66,90 | 58,41 | −8,49 |
| Tratamientos y trabajo s/ piezas | 73,80 | 42,40 | −31,40 |
| **Armado y envasado** | **33,00** | **33,00** | ✅ |
| **Plástico / mango** | **63,06** | **63,06** | ✅ |
| **Cartón** | **79,00** | **79,00** | ✅ |
| **Cajas** | **13,91** | **13,91** | ✅ |
| (memo) MO interna de matriz | 0 | 68,39 | el Excel la manda a Aportes |

**Rubros exactos por artículo**: 505 y 510 **4 de 6**; 506, 031 y 502 **3 de 6**; 513, 504 y 501
**2 de 6**; 586 y 546 **1 de 6**. El **AyE del tallerista coincide al centavo en 6 de 10**
(501 $491, 502 $133,50, 510 $27,14, 031 $230, 546 $109,85, 506 $70); el **cartón en 6 de 10** y la
**caja en 5 de 10**.

**Dos de los que "no cuadran" son clasificación, no plata:**
- **586**: GP2 mete el mango plástico ($171,30) en Material porque el componente está en
  `Sector Procesado`; el Excel lo pone en Plástico ($147,24).
- **546**: `Corta Queso Bastidor c/Cilindro` ($1.040,40) trae todo adentro, incluido el bastidor
  de Valeria que el Excel cobra en la columna Tallerista. Por eso su total cierra al −0,7 % pero
  sólo un rubro coincide.

**Lección**: comparar totales no alcanza. La columna "Rubros OK" del archivo es la que dice si de
verdad cierra.

**Los tres que no cuadran, y por qué:**
- **510 (−39,5 %)**: GP2 no cobra el cromado del cuerpo ni el zincado de la uña ($83,81 de
  tratamientos en la planilla contra mucho menos en GP2).
- **504 (−25,5 %)**: material + tratamientos $448,28 en la planilla contra $179,68 en GP2 —
  falta el zincado y el rectificado de los tochos.
- **031 (+15,8 %)**: el cartón, ver el punto c) de §4x.

## 4y. Las pantallas de CONTROL se miran, no se cargan (2026-09-08)

**[usuario]** Viendo `Control Prov. Servicios` pidió: *"quiero que elimines esa parte"* (el panel
"Cargar movimiento PS" que estaba arriba de todo) y *"quiero que sea la misma lógica de control
partes talleristas"*.

**La regla que queda, para toda pantalla de control GP2:**

- **Un control es de SOLO CONSULTA.** No lleva formulario de carga adentro. Lo que se carga se
  carga en su pantalla: **Envío** (`EnviosPS_GP2.html`) y **Entrega** (`EntregaPS_GP2.html`),
  que ya estaban en el menú y usan las mismas RPC (`crear_envio_ps` / `crear_entrega_ps`).
  El panel de `ControlPS_GP2` era un **tercer** lugar para hacer lo mismo, con su propio
  buscador de componentes y sus propias validaciones: dos maneras de cargar el mismo
  movimiento es una de más.
- **El molde es `Talleristas/Control Tall/ControlTalleristas_GP2.html`**: `gp2-modulo.css` +
  `GP2EE`, header con `Volver / Exportar CSV / Imprimir` + links a Envío/Entrega/Atrás,
  fase0 (chips de contraparte, con un chip **"Todos"** al principio) → fase1 (aviso del estado
  de los datos, KPIs, buscador, tabla con totales). El saldo de cada fila abre la
  **composición** (`GP2Composicion.abrir`) apuntando a la ubicación de esa contraparte.
  En modo "Todos" aparece la columna de la contraparte; con una elegida, se oculta.
- **Lo que se ganó de paso** al pasar `ControlPS_GP2` a ese molde: exportar CSV (no lo tenía),
  el modo "Todos", los KPIs y la letra grande de la casa. Se fue el pivote "Stock en PS por
  parte" (partes en filas × PS en columnas), que hacía lo mismo que el modo "Todos" pero
  ancho y con celdas vacías.
### 4x-quater. Los 3 que no cuadran, cerrados (2026-09-08)

Cada uno tiene una causa distinta y concreta. Ninguna es "el costo está mal": a los tres les
falta **un dato puntual**.

**510 (−39,5 %) — a la ruta le falta el cromado del cuerpo.** La planilla cobra
`cromado mariposa $69,49` (`Tratamientos !N225`). En GP2 el componente se llama
`Cpo Uña Crom. LK C/M` ("Crom." de cromado) pero su costo es **$62,04 con `servicios_pesos` = 0**:
en las rutas del 510 hay pasos de FAAT (cementado de la uña), Guazzaroni (zincado de la uña) y
Guazzaroni (niquelado del remache), **pero ningún paso de cromado para el cuerpo**. El servicio no
está mal cotizado — no existe el paso.

**504 (−25,5 %) — a la receta le falta la Arandela Grande.** La planilla cobra
`Arandela Grande Afila $200,98` dentro de `Materiales!I94`. En GP2 `articulo_componente` del 504
tiene `Arandela Chica Afila Inox` ×8 ($71,28) **y nada más de arandelas**. Pero la **ruta sí la
tiene**: `Arandela grande Afila p/cementar y zincar` → FAAT (cementado, $3.084,02/kg) → Guazzaroni
(zincado, $1.172/kg) → `Arandela Gde Afila Zinc.`. O sea: **la pieza está modelada en la ruta y
falta en la receta.**

**031 (+15,8 %) — el cartón.** Ya cerrado en §4x punto c): $0,252 del `IFERROR(...,0)` de la
planilla contra $63 de GP2.

**Los tres refuerzan el diseño del arreglo de la 7269**: el 504 es otro caso donde la receta está
incompleta y la ruta está bien. La vista tiene que **seguir recorriendo la ruta** y sólo agregarle
la multiplicación por `ruta_paso.cantidad`.

### 4x-quinquies. Los precios que faltan ya están en la planilla (idea 7270)

Buscados en `GP2.planilla_fila` ahora que la planilla vive en la base. **Nada de esto se cargó** —
son candidatos para que el usuario confirme el mapeo:

| Componente GP2 (hoy $0) | Candidato en la planilla | $ | Dónde |
|---|---|---|---|
| `Cuch China` | Cuchilla 505 Ac Inox (`505C`, prov 2222) | **230,03** | `Lista de Precios ` 1006 · US$0,15 · lista 2026-05-29 |
| `Cuchilla Laser` | Cuchilla Laser (`587C`, prov 2222) | **184,02** | `Lista de Precios ` 1007 · US$0,12 · lista 2026-05-29 |
| `Argolla Grande` | Argolla | **32,99** | `Materiales` 166 |
| `Argolla Chica` | Argolla Redonda 70 mm × 1,7 mm | **17,56** | `Materiales` 167 · `Lista de Precios ` 26 |
| `Alambre Corta Queso` | alambre inoxidable 0,50 mm (1,936 g) | **63,98** | `Materiales` 213 / 218 / 226 |
| `Tornillo Corta Queso` | Tornillo cortaqueso | **12,10** | `Lista de Precios ` 20 · lista 2026-07-30 |
| `Cartón 515` | Batidor Resorte, cartón tipo 15 | **48,00** | ` Cartones` 376 |
| `Cartón 119` | Corta Queso (entero) Loke, tipo 17 | **48,00** | ` Cartones` 305 |

**Tres quedan sin candidato claro y los tiene que decir el usuario:**
- `Cartón 516` (Destapa Corona Suelto): **no hay fila de cartón para el 516** en ` Cartones`.
- `Vastago Sacafuente Pizzero`: el más parecido es `Perno (Trompo)` $598,91 (`Materiales` 179),
  pero el nombre no coincide.
- `Abrelata Uña Pie 500`: es el artículo terminado del 500, no un insumo — hay que ver por qué
  está en una receta a costo cero.

⚠️ **Ojo con `Cuch China`**: GP2 la tiene en la receta del **586, 123, 099 y 108**, pero la
planilla, para el 586, cobra material $66,90 = **cuchilla de fleje nacional + clavo**, no una
cuchilla importada. Antes de cargar los $230,03 hay que definir **si esos artículos van con
cuchilla china o con la nacional** — si van con la nacional, el error no es el precio, es que
sobra el componente.

## 4z. Lo que un PS PRODUCE no se compra: IC3/IC3V fuera de la OC (2026-09-08)

**[usuario]** Viendo IC3 y IC3V en la OC de flejes: *"estos dos items de ordenes de compra en
flejes hay que sacarlos porque esas dos partes de charcas se tratan como proveedor de servicio"*.
Esto **contesta la pregunta 28** de `PREGUNTAS_ARQUITECTURA_GP2.md` (alternativa A) y confirma lo
que ya había dicho el 04/09: la OC del Fleje 90 va **sólo a Altrak**.

**El circuito del Fleje N° 90, como queda:**

1. **Se compra `FLEJE90_BRUTO` a Altrak** (sector 13 Alambre, kg). Ése es el ítem de la OC.
2. **Se le manda a Charcas** (envío PS) y Charcas lo **corta**: es un servicio, no una venta.
3. **Vuelve como IC3** (corto, se guarda en Cervantes) e **IC3V** (largo, va directo a Virgilio),
   por **Entrega PS** — nunca por una OC ni por una recepción de compra.

**La regla en la base** (`oc_bundle`, 2026-09-08): un componente NO aparece en la OC cuando el
`proveedor` que tiene cargado es el **mismo PS que lo produce** en una ruta (`ruta_paso` de tipo
`proveedor_servicio` con `comp_salida` = ese componente). Hoy eso es exactamente IC3 y IC3V.
Se mira **el proveedor del componente**, no el paso suelto, y eso es a propósito:

- un insumo que **compramos** y mandamos a pintar/zincar (paso PS con entrada = salida) **sigue**
  en la OC — su proveedor es quien nos lo vende, no el que lo pinta;
- **Charcas es las dos cosas a la vez**: nos **corta** el alambre (servicio) y nos **vende**
  bombillas (BOM10, EP10, LLF8, sector Bombilla). Las bombillas siguen en la OC.

**Efecto colateral que había que tapar en el mismo movimiento** (`crear_oc`): la OC gemela al
proveedor de la materia prima sumaba **todos** los ítems de la OC. Con IC3/IC3V afuera, lo único
que se le puede pedir a Charcas son bombillas → **una OC de bombillas habría disparado una OC de
alambre a Altrak que nadie pidió**. Ahora la gemela suma **sólo lo que el PS produce** (componente
de un sector que NO es de insumo). Probado: OC de LLF8 a Charcas → sin gemela; OC de 35,4 kg del
1686 a Eclipse → gemela a Aperam por 59,28 kg de CHAPA430 (los mismos números de la compra real).

**Queda pendiente de decisión del usuario:** la pantalla de OC convierte a **paquetes de 10 kg**
todo lo que sea de Charcas (`esCharcasIt()` mira sólo el proveedor). Esa regla nació para el
alambre cortado, que ya no se pide; hoy sólo alcanza a las bombillas, que van en unidades.

## 4aa. Ester (calado) cala el mango PC3B → PC1B; el 123 se compra SIN calar (2026-09-08)

**[usuario]** *"Esther está como proveedora de servicio. No es con H, es Ester, y no tiene ninguna
parte que se lleva. Lo que se lleva es el mango 123. El PC1B es el que ya está calado. Antes de esa
ruta tenés que agregar de qué Ester lo cala: el mango PC3B. Le compramos el mango sin calar
[a Pat Bet Plast, «en principio»] y se lo enviamos a Ester para que lo cale, y después viene como
PC1B."*

**El circuito del mango del Pelapapa 123, como queda** (art 123, ruta 269):

1. **Se compra `PC3B`** = "Mgo Pelapapa 123 Sin Calar" a **Pat Bet Plast** (Sector Plástico, insumo).
   Es el mango inyectado, todavía sin el calado.
2. **Se le manda a Ester** (PS id 14, proceso **Calado**) por Envío PS. Ester lo **cala**.
3. **Vuelve como `PC1B`** = "Mgo Pelapapa 123" (calado) por Entrega PS, y de ahí va al tallerista
   **Lucho**, que arma el 123.

Ruta: `insumo PC3B → PS Ester (PC3B→PC1B) → tallerista Lucho (PC1B→123) → virgilio`.

**Cómo se modeló, y una diferencia fina con Charcas:**

- **`PC3B` es lo que se compra** (proveedor `Pat Bet Plast`, `estado_compra=null`): aparece en la OC
  con el punto de compra que antes tenía PC1B (mín/máx 6704, est_madre). El **precio $62,01** ("Mgo
  Pelador 123 Negro, mat+iny") se **movió de PC1B a PC3B**: es el precio del mango en sí, sin el
  calado.
- **`PC1B` ya NO se compra: lo produce Ester.** Se marcó `estado_compra='fabricacion'` y
  `proveedor=null`. Eso lo saca de la OC y hace que su costo se **derive de la ruta** (PC3B + el
  servicio de Ester), no de un precio propio. En Control/Entrega PS, PC1B es la parte que Ester
  **devuelve** y PC3B la que **recibe** (`partes_por_ps` de Ester: sc=PC3B, sp=PC1B).
- **Por qué `fabricacion` y no el truco de Charcas** (regla §4z, `proveedor = el PS`): la regla 4z
  necesita que el nombre del PS exista en `proveedor_insumo` (Charcas está ahí porque además nos
  **vende** bombillas). **Ester es servicio puro, no nos vende nada**, así que no va en
  `proveedor_insumo` — y hay un FK `componente.proveedor → proveedor_insumo.nombre` que lo impediría.
  Para una parte de **sector insumo** que pasa a ser **producida por un PS que no es proveedor de
  insumo**, la herramienta es `estado_compra='fabricacion'` (la saca de la OC) + `proveedor=null`.

**Verificado:** costo del 123 estable en **$520,27** (el material sigue entrando vía PC3B); la OC
pasa de "PC1B → Pettofrezza $6704" a "PC3B → Pat Bet Plast $6704"; invariantes de `verificar.sql`
en 0 (Ester tiene ubicación, sin códigos ni pasos duplicados).

**PENDIENTE (lo dijo el usuario):**
1. **El proveedor de PC3B es "en principio" Pat Bet Plast** — falta que el usuario confirme a quién
   le compramos el mango sin calar. (El precio $62,01 quedó con `cod_prov=797`, que puede no ser el
   de Pat Bet Plast; reconciliar al confirmar.)
2. **Ester no tiene tarifa de calado** — por eso el costo del 123 ahora marca `faltan_precios` (el
   servicio suma $0 hasta cargarla). El costo total no cambió sólo porque el calado todavía vale 0.

**Mismo circuito para el 505 (2026-09-08, mismo pedido).** `[usuario: "con el 505 vamos a hacer lo
mismo. Pat Bet Plast entrega el mango sin calar y se manda a Ester para calar. El sin calar sería
el PC2 y el calado en la ruta del 505 está como PC1A"]`. Se creó **`PC2`** = "Mgo Pelapapa 505 Sin
Calar" (proveedor Pat Bet Plast; tomó el punto de compra de PC1A, máx 112.736, y su precio $63,06);
**`PC1A`** pasó a `estado_compra='fabricacion'` + `proveedor=null` (lo produce Ester; conserva sus
240 uni en stock). El calado de Ester (PC2→PC1A) se insertó en **las DOS rutas** del 505 (296 con
Lucho, 548 con Danica García) — el 505 se arma por dos talleristas alternativos, y el paso va antes
del tallerista en ambas. El código lo eligió el usuario: **PC2**, sin la letra A (no PC2A).
Verificado: costo del 505 estable en $667,09; OC pasa de "PC1A → Pettofrezza" a "PC2 → Pat Bet
Plast" (sug 112.736); invariantes en 0 (inventario = ledger, los 240 de PC1A intactos). Mismos dos
pendientes que el 123. CERRADO 2026-09-09: **PC2 y PC3B (los mangos SIN CALAR de 505 y 123) se compran a Pettofrezza Rafael** [usuario: "no aparecen para comprárselos a Pettofrezza Rafael"] — estaban en Pat Bet Plast y por eso no salían bajo Pettofrezza en la OC/Recepción; migración `pc2_pc3b_proveedor_pettofrezza`. Sigue pendiente la tarifa de calado de Ester.


## 4ab. Estado real del módulo de OC, auditado (2026-09-08)

`[usuario 2026-09-08]` Pedido: *"¿Qué más hay para hacer, que no sea costos? Del módulo de órdenes
de compra. ¿Es lo que necesitemos terminar o está todo para vos ya hecho bien?"*. Se lanzaron dos
revisores: uno auditó el circuito completo, otro la lógica de reabastecimiento.

### El dato que ordena todo

`[dato]` **`GP2.orden_compra` tiene UNA fila: la OC N° 1 a Aperam, estado `anulada`, 10 ítems, 0
recibidos.** Ninguna OC llegó jamás a `enviada` ni a `recibida`. **El módulo está construido pero
nunca se usó de verdad** — todo lo que "anda", anda en teoría.

Y el stock tampoco está: **256 de 285 insumos tienen cantidad 0**. Sólo 29 tienen stock cargado.
Por eso la pantalla ve "falta todo": no es que falte, es que nunca se cargó.

### La cuenta que asusta

`[dato]` **Una corrida completa de sugeridos hoy: ~ARS 367.600.000** (183,5 M ARS + US$ 120.302 a
TC 1.530), con **201 de 235 líneas cargadas**. Reparto: cartón 77,8 M · plástico 55,5 M · cajas
25,6 M · garage 8,8 M · remaches 5,5 M · fleje US$ 119 k.

Eso no es una orden de compra, es el inventario objetivo entero. **Falta el gatillo**: hoy se
propone llenar el techo de todo lo que esté un peso por debajo. Y el techo es alto — cartón y fleje
están a **6 meses** de consumo, mientras en la realidad se recibe **todas las semanas**
(Corrugadora 3 visitas en 16 días, Basconia 2 en 7, Aperam 2 en 4).

### El gatillo ya existe y nadie lo usa

`[dato]` **`inventario.minimo` está cargado en 1.079 de 1.085 filas** (232 de 235 en el universo
OC), viaja en `oc_bundle` como `minimo`, y **la pantalla lo dejó de dibujar**. Lo lee sólo
`faltantes_bundle`. Con eso alcanza: **el mínimo dispara, el máximo dimensiona** — no hay que crear
ningún campo.

Sirve tal cual en **cartón, fleje y caja** (`meses_minimo` 4 contra `meses_stock` 6 → lote de 2
meses, ~6 OC al año). **No sirve** en plástico y remache (mínimo = máximo = 4 meses: cualquier
consumo dispara) ni en bombilla (**mínimo 4 > máximo 3**: siempre disparado). Hay 9 líneas del
universo OC con `minimo > maximo`.

### El máximo casi nunca es el lugar físico

`[dato]` De 235 líneas: **194 con `maximo_origen='est_madre'`** (consumo × meses), **10 `fisico`**,
**31 sin máximo**. O sea el lema "la OC llena el lugar" describe 10 filas; en las otras 194 el
"lugar" es consumo × meses ya materializado en `inventario.maximo`. **El fallback en vivo de
`oc_bundle` a consumo × meses está muerto** (0 filas lo usan): los que no tienen máximo tampoco
tienen consumo, así que quedan en sugerido 0.

### Lo que hace el vecino, y que GP2 no tiene

`[dato]` **`public."Ordenes_Compra"` calcula `máximo − stock + PEDIDOS`** y da exacto en 380 de 495
líneas. Ese `oc_pedidos` es **demanda comprometida con el cliente** y **suma**, no resta. Guarda
`oc_max`, `oc_stock`, `oc_pedidos`, `oc_proy` por línea.
`[dato]` **El vecino le pide a los 17 proveedores el mismo día, cada 7 días** (29/07, 12/08, 19/08,
26/08, 02/09; 93-104 líneas por fecha). Un flete por ronda, no por urgencia.
⚠️ **Pregunta abierta al usuario**: cuando dijo *"se ve en función de lo que se pide el
reabastecimiento"*, ¿se refería a **pedidos de clientes** (la fórmula del vecino) o a **lo que ya se
le pidió al proveedor**? Cambia el diseño: si es lo primero, GP2 **no tiene de dónde sacar ese
dato**.

### La concentración: 7 proveedores = 81 %

`[dato]` Pol 92 ítems · Basconia 23 · Pat Bet Plast 23 · Aperam 14 · Bella Vista 14 · Pettofrezza
12 · Corrugadora 12 = **190 de 235**. Con 7 OC se compra casi todo, así que agrupar por proveedor
y arrastrar todo lo suyo (aunque no sea urgente) es lo que evita pagar dos fletes. En cartón
además es **obligatorio**: para llegar al múltiplo de 12.000/16.000 hay que meter códigos que no
eran urgentes — `ajustarFamilia()` ya lo hace bien.

### Lo que está BIEN y no hay que tocar

- **La maquinaria de cartones** es la parte más sólida: familia = formato+marca+categoría, comodín
  sacacorchos, mínimo por código fijo, pliegos de 100 aparte, piso de bolsa 20.000. 30+ asserts en
  verde en `test_oc.js`.
- ⚠️ **La doc miente**: `CLAUDE.md` y `REGLAS_OC_INSUMOS.md` dicen que la validación de cartones
  está **DORMIDA** hasta que se asigne `carton_formato`. **Es falso**: los 110 cartones tienen
  formato y el tipo C ya tiene categoría (Abrelatas 6, Pelapapas 4, Resto 16, Sacacorchos 6). Las
  reglas están **vivas**. Hay que corregir las dos docs.
- `explicaSug()` muestra la cuenta debajo de cada campo ("sugerido 2.449 · máx 2.500 − stock 51"):
  el comprador ve de dónde sale el número.
- Los totales por moneda no inventan cotización (US$ y $ separados; el equivalente sólo si el TC
  vino del cron).
- La regla de OC gemela sale toda de datos (`proveedor_servicio.hibrido/mp_componente_id/
  desperdicio_pct`), sin un nombre de proveedor escrito.
- El cruce FIFO de recepción convierte kg/uni en las dos direcciones y descuenta en la unidad de la
  recepción (no en la del ítem, que sería el error fácil).

### Lo que falta para que un comprador lo use solo

Por orden de lo que le va a doler primero — el detalle está en las ideas **7271 a 7274**:

1. **Que la hoja lleve la fecha de entrega.** Hoy se pierde por un nombre de campo.
2. **Que avise "esto ya lo pediste".**
3. **Los 31 insumos sin máximo**, que hoy muestran "—" sin explicar.
4. **Poder corregir**: editar/borrar una OC en borrador, des-anular una anulada por error.
5. **Que anular una recepción devuelva el `recibido`.**
6. Contestar las preguntas **23** y **28** de `PREGUNTAS_ARQUITECTURA_GP2.md`.
7. Confirmar con Gráfica Pol el **pliego de 25.000 del cartón Huevo** (sin confirmar y ya empujando
   pedidos).

## 4ac. El gatillo de reposición de la OC: el mínimo dispara, el máximo dimensiona (2026-09-08)

**Es la regla de reposición de GP2, y ya estaba en la base sin que nadie la mirara.**

- **La cuenta de CUÁNTO no cambió**: sigue siendo `máximo − stock` (§4ab, decisión del usuario
  del 2026-09-04: "llena el lugar"). Lo que se agregó es **CUÁNDO** [deducido, implementado en
  `Compras/OC_GP2.html` v1.21.0]: `inventario.minimo` es el punto de pedido y ya viaja en
  `oc_bundle`; la pantalla lo había dejado de dibujar y por eso proponía llenar el techo de todo
  lo que estuviera un peso abajo del máximo.
- **Tres estados** (`estadoRepo(i)`):
  - `pedir` — `stock <= minimo`. Se carga solo, hasta el máximo.
  - `viaje` — `stock > minimo`. Campo vacío. Botón **"Aprovechar el viaje (N)"** los suma de una.
    Ese botón NO es un adorno: el cartón se pide por familia y necesita completar el múltiplo del
    pliego aunque un código puntual no esté bajo mínimo.
  - `sin-gatillo` — sin mínimo, sin stock, o `minimo >= maximo` (config rota). **Se comporta como
    antes y se carga solo.** El fail-safe es deliberado: ante la duda, que no se esconda algo que
    hace falta.
- **"Ya lo pediste" es AVISO, no resta** [usuario 2026-09-04: "por ahora borralo"]. La fila con
  `pendiente_oc > 0` muestra cuánto viene en camino y no se autocarga; la cuenta a la vista sigue
  siendo `máximo − stock`, sin el "− pendiente" que el usuario mandó sacar.
- **"Usar sugeridos" es la orden explícita del usuario y pisa las dos cosas**: carga todo lo
  visible que tenga sugerido, gatillo y aviso incluidos.
- **La pregunta abierta de §4ab quedó cerrada por el argumento del doble conteo** [deducido]:
  el vecino hace `máximo − stock + pedidos de clientes`, pero en GP2 el máximo NO es físico —
  194 de 235 son `maximo_origen='est_madre'`, y `v_consumo_demanda` arranca justamente de
  `est_madre.proy_uni_mes`. Sumar pedidos de clientes contaría la misma venta dos veces. Si algún
  día los máximos pasan a ser físicos, la pregunta se reabre.
- ⚠️ **HONESTO, y hay que decirlo cada vez que se hable del gatillo** [dato, consulta del
  2026-09-08]: **hoy casi no recorta**. Agrupando lo que tiene `sugerido > 0`: 144 líneas
  (ARS 100,7 M) caen en "hay que pedir", 52 (ARS 72,6 M) en config rota, 5 (ARS 10,0 M) sin
  config, y **una sola** en "aprovechá el viaje". La razón es que **205 de 236 insumos tienen
  stock 0** (86,9 %). **El gatillo empieza a servir recién cuando se cargue el stock** — por eso
  el orden correcto es contar primero y pedir después. Ver `STOCK_A_CONTAR_2026-09-08.md`.
- **CUÁL ES EL UNIVERSO DE LA OC — no es `estado_compra='compra'`** [dato 2026-09-08, leído del
  `prosrc` de `GP2.oc_bundle`]. Es `_es_sector_insumo(sector_id)` (o proveedor Charcas/Eclipse, o
  un proveedor que exista en `proveedor_insumo`) **con `estado_compra IS NULL`**, sacando lo que
  produce un PS; y el stock/mínimo/máximo salen de la fila de `inventario` que elige un `LATERAL`
  que prioriza la ubicación del sector. **Son 236 insumos, no 285** — el 285 de §4ab contaba otra
  cosa. Antes de volver a medir "cuántos insumos pide la OC", leer la función, no suponer.
- **La config rota que hay que corregir** (es `ubicacion.meses_minimo`, no la pantalla)
  [dato 2026-09-08]: son **53 líneas**, y 52 salen de 4 sectores donde `meses_minimo >=
  meses_stock`: Plástico (4 vs 4) 31, Remache (4 vs 4) 15, Bombilla (4 vs 3) 4, Procesado
  (2 vs 1) 2. **Cartón y Fleje están sanos** (4 vs 6: 0 rotos sobre 136 líneas). La 53ª es `A9`
  (Caja N°22), cargada a mano contra la fórmula. Mientras estén así esas líneas caen en
  `sin-gatillo` y se piden como antes.
- **31 insumos son invisibles para la OC** [dato 2026-09-08]: tienen proveedor pero
  `inventario.maximo IS NULL` **y** consumo 0, así que el fallback `consumo × meses_stock`
  tampoco los rescata y `sugerido = 0` siempre. Contarles el stock no cambia nada. Los que más
  llaman la atención tienen mínimo cargado y el máximo vacío: `IE4` (Fleje N° 31, mín 108.000),
  `IE5` (Fleje N° 32, mín 36.000) y `O6A` (Cartón 809, mín 5.184).

## 4ad. La serigrafía de Hernández Julio (ximpa): el mango sale, se serigrafía y vuelve (2026-09-08)

**[usuario, textual]: "Julio no va para 505. Sí para 586. El mango plástico que entregan, va a
Julio y después vuelve. El que vuelve va a talleristas."**

- **El modelo es el mismo que el de Ester con el 505**: se compra la pieza EN BLANCO, un
  proveedor de servicio la trabaja, y la que vuelve es la que va al tallerista. Nunca se compra
  la pieza ya terminada.
- **586 aplicado** (migración `serigrafia_julio_586_pep2_a_pep3`): `PEP2` (Mango Pelador 586 S/M,
  en blanco, $147,30 a Pat Bet Plast) → **Hernández Julio** serigrafía ($24) → `PEP3` (Mango
  Pelador LK 586 c/Serig) → Lucho → 586. `PEP3` pasó a `estado_compra='fabricacion'` y el punto
  de compra se mudó a `PEP2`.
- **No se inventó ningún número**: la propia fila de `precio_proveedor` de PEP3 ya decía
  `"mango $147,30 + serig Ximpa $24"` [usuario, cargado el 2026-08-30]. Sólo se separó lo que ya
  estaba junto. **Ximpa = Hernández Julio** (el título del bloque en la planilla dice
  `1149 - Hernandez Julio (ximpa)`).
- **PEP2 no era huérfana**: yo la había reportado como componente sin ruta ni receta. Era la
  pieza en blanco de una cadena que faltaba cargar. **Regla: antes de dar una pieza por huérfana,
  fijarse si su nombre dice "S/Serig", "S/M" o "Sin Calar" — eso significa que es el ANTES de un
  proceso, no una baja.**
- ⚠️ **El $67 de la planilla NO va**: en el bloque de Julio hay dos filas, `PELADOR 505 $67` y
  `PELADPR 586 $67`, que el usuario descartó explícitamente para el 505. La serigrafía del mango
  es la de $24 (`Mango Pelador Serigrafiado`, fila 778). Las de $67 quedan sin explicar.
- **Cómo leer la planilla de precios [usuario 2026-09-08]: el proveedor es el TÍTULO del bloque,
  no el `cod_prov` de las columnas.** Y buscar por palabra clave se pierde ítems: las filas de
  $67 están en el bloque de serigrafía y no dicen "serigrafía" en ningún lado.
- **Falta hacer lo mismo en los capuchones y manguitos** (PA18, PA10, PA13, PA4, PA5, PC13, PC14,
  PB5, PC15A, PC15B, PEP1). Para PA10 el par ya existe (`PA10B` es el S/Serig); para las otras hay
  un solo código y hay que crear la pieza en blanco. Precios de Julio: capuchones y mangos
  untadores $19, manguitos y cuerpos $24, cuchara de cocina $28.
- **Proveedores de proceso de la planilla que GP2 NO tiene** [dato 2026-09-08, por título de
  bloque]: `3131 - New Metal` (13 ítems), `559 - Becker Sandra Nora (GUSTAVO SETTON)` (10),
  `1673 - Industermic Chromium` (7), `4750-3157` (15, el título no trae nombre). Y
  `3149-Recubrimientos Color` existe en GP2 como "Rec Color" pero con 0 pasos y 0 precios.

### 4ad-bis. Cómo saber qué pieza lleva serigrafía (2026-09-08)

**[usuario]: "Buscar las partes que parezca que tengan el nombre serig o algo así, para que te
diga, porque esas son claramente las que tienen serigrafía."** Funciona, pero sólo encuentra la
mitad — y la otra mitad se detecta por el PRECIO:

1. **Por nombre**: el marcador vive en la pieza EN BLANCO, no en la terminada — `S/Serig`, `S/M`,
   `Sin Calar`, `p/Pintar`, `p/Estampar`, `p/cromar`. En plástico sólo dos piezas lo tienen:
   `PA10B` (Capuchón ⌀8 S/Serig) y `PEP2` (Mango Pelador 586 S/M). **Las dos ya están cableadas.**
2. **Por precio**: donde GP2 tiene UN SOLO código no hay marcador de nombre, pero la fila de
   `precio_proveedor` lo delata: dice **"(mat+iny)"** — material más inyección, **sin serigrafía**.
   Confirmado en PA18, PA13, PC13, PC14, PB5, PC15A, PC15B ("Capuchón LK (mat+iny)", "Manguito
   Abrelata (mat+iny)", "Cuerpo Doble Aleta (mat+iny)"), PA4/PA5 ("mat $19,04 + iny Pettofrezza
   $36,50") y PEP1 ("mat $61,10 + iny $86,20"). **En ninguna está el $19/$24 de Julio.**
   Para esas hay que CREAR la pieza en blanco antes de poder meter el paso.
3. **En metal el modelo YA está bien hecho** y sirve de plantilla: `G13 p/Pintar → A1 Pint. →
   A4 Serig`, `K2 S/marca p/pintar → B4B Pint. → B7 Serig`, `J13 p/Pintar → C2 Pint. → C1 Serig`.
   Cada flecha es un paso de proveedor de servicio real. El plástico es el que quedó a medias.

**Cerrado el 2026-09-08**: `PEP2 → Julio $24 → PEP3` (586) y `PA10B → Julio $19 → PA10` (315).
El 121 sigue usando `PA10B` derecho porque va sin serigrafiar — por eso PA10B se sigue comprando:
va al 121 **y** alimenta a PA10.

**El calado de Ester quedó cargado a $3,87** (PC1A y PC1B) [usuario 2026-09-08, eligió el precio
de lista sobre el IPC al día de $5,1837]. **El 505 pasó a `faltan_precios = 0`**: $667,09 → $670,96.
Hubo que dar de alta el proceso `calado` en la tabla `proceso`, que no existía.

### 4ad-ter. Serigrafía: las 3 que se hicieron por evidencia, y por qué las otras 7 esperan (2026-09-08)

**Cerradas** (se creó la pieza en blanco, el precio de compra se mudó a ella, la serigrafiada pasó
a `fabricacion` y la ruta lleva el paso de Julio):

| En blanco (se compra) | Julio | Serigrafiada (va al tallerista) | Artículos |
|---|--:|---|---|
| `PEP2` $147,30 | $24 | `PEP3` | 586 |
| `PA10B` $58,74 | $19 | `PA10` | 315 |
| `PA18B` $58,74 | $19 | `PA18` | 542, 543, 546, 559, 562, 587, 116 |
| `PA13B` $58,74 | $19 | `PA13` | 515 |
| `PC15AB` $513,36 | $24 | `PC15A` | 523 |

**El criterio para aplicar fue el ARTÍCULO, no el nombre de la pieza** — porque el nombre del
ítem de Julio ("Capuchón Espátula Serigrafiado") no trae código GP2 y cruzarlo por descripción es
adivinar. Se aplicó sólo donde la hoja **Tratamientos** de la planilla marca el artículo en la
columna `Serigrafiado`: los 6 artículos de PA18 figuran, el 515 de PA13 figura, el 523 de PC15A
figura.

**`PA4` y `PA5` cerradas el 2026-09-09** [usuario: **"$19 a 551 y 878"**]: el ítem
"Mango Untadores Plásticos Serigrafiado" $19 de Julio va a esos dos artículos, que en GP2 son
`PA4` (Mang Cuch Unt Rojo, art 551) y `PA5` (Mang Cuch Unt Chef, art 878). Se creó `PA4B` y
`PA5B`; el mango queda en $74,54 = $55,54 + $19. **Esto confirma que la columna `Serigrafiado`
de Tratamientos NO es la lista completa**: ni el 551 ni el 878 figuran ahí y sin embargo llevan
serigrafía. La planilla tiene el dato incompleto; la fuente buena es el usuario.

**Las 5 que NO se tocaron y por qué** [dato 2026-09-08]: `PC13` (701), `PC14` (501), `PB5` (101), `PC15B` (723), `PEP1` (099). **Ninguno de esos artículos aparece
en la columna `Serigrafiado` de Tratamientos.** El caso que más engaña es el **501**: sí figura
con serigrafía $19, pero la fila dice **"Planchuela Manija"** — es el mango de METAL (`A4`, que
GP2 ya tiene bien cableado), **no** el manguito plástico `PC14`. Así que la lista de precios de
Julio tiene ítems ("Manguito PP Plásticos Serigrafiado" $24, "Mango Untadores Plásticos
Serigrafiado" $19) que **no se pueden atar a ningún artículo** con lo que hay: o se usan en
artículos que GP2 no modela, o son ítems viejos. **Falta que el usuario diga cuáles van.**

**El efecto en el costo tiene dos formas, y conviene saber cuál toca antes de aplicar:**
- Si el precio de compra **ya incluía** la serigrafía (lo dice la descripción de la fila de
  precio), se **reparte** y el costo del artículo **no se mueve**. Fue el caso del 586.
- Si el precio dice **"(mat+iny)"**, la serigrafía **no estaba** y el costo **sube** lo que cobra
  Julio. Fue el caso de PA10, PA18, PA13 y PC15A.

### 4ad-quater. Julio: la lista completa y lo que quedó sin atar (2026-09-09)

**El detalle vive en `SERIGRAFIA_JULIO_2026-09-09.md`** (qué recibe, qué devuelve, a qué artículo
y a qué precio). Lo que hay que recordar acá:

- **GP2 tiene 10 pasos de Julio con precio**: 3 de metal (A4, B7, C1) y 7 de plástico, todos
  cargados el 08–09/09/2026.
- **Los manguitos abrelata NO llevan serigrafía** [usuario 2026-09-09: "no va en ninguno"]:
  `PC13` (701), `PC14` (501) y `PB5` (101) quedan cerrados así. El ítem "Manguito PP Plásticos
  Serigrafiado" $24 de la lista de Julio **no corresponde a ningún artículo de GP2**.
- **El 499 tiene el paso de Julio (`B12 → Z22`) SIN precio** → está subcosteado. Tratamientos
  marca el 499 con $24 en "Cuerpo pie", pero la lista de Julio no tiene ningún ítem que diga
  "llavero". Falta confirmar.
- **Contradicción a mirar**: `A8` se llama "Cuerpo Uña CH **Serigr.**" y su paso lo hace **Jade
  a $127** (pintado), no Julio — mientras Julio lista "Cuerpo Mariposa Uña Serigrafiado" $19 sin
  asignar. O falta el paso de Julio además del de Jade, o el nombre de A8 miente.
- **Quedan 5 ítems de Julio sin asignar**: Capuchón 10 Mm $19, Capuchón Pela Pica Ajo $24, Tapa
  Cucaracha $24, Patitas $24, Cuchara de Cocina $28. Varios con última compra de 2023–2025, así
  que pueden ser de artículos que GP2 no modela.
- **Y el `PELADPR 586` $67 sigue sin explicación**: el 586 se costea con el mango de $24, no con
  esa fila. (El `PELADOR 505` $67 el usuario ya lo descartó el 08/09.)

### 4ad-quinquies. Lista CERRADA de lo plástico que se lleva Ximpa (2026-09-09)

**[usuario, confirmando la lista de las piezas en blanco de Sector Plástico]:** los componentes
que se lleva **Ximpa (Hernández Julio)** a serigrafiar son exactamente estos 7, y ninguno más:

`PA4B` · `PA5B` · `PA10B` · `PA13B` · `PA18B` · `PC15AB` · `PEP2`

(las versiones EN BLANCO; vuelven serigrafiadas como PA4, PA5, PA10, PA13, PA18, PC15A, PEP3).
**Los 7 están cableados.** El lado plástico de la serigrafía quedó COMPLETO.

**Esto cierra `PC15B` (723) y `PEP1` (099)**: no están en la lista → **NO llevan serigrafía**.
Quedan como se compran, directo al tallerista. (Se habían quedado "sin definir" en §4ad-ter.)

## 4ae. Casa Landau: no aparecía en Recepción — dos causas (2026-09-09)

**[usuario: "casa landau dónde está? no me aparece en recepción de insumos? qué le compramos" →
"cambialo, no es sector procesado" → "ponelo como recepción de insumos dentro de bombillas"]**

Casa Landau nos vende **argollas**: `Z25A` (Argolla Grande, en 057/498/499/516/700) y `Z25B`
(Argolla Chica, en 498/499). Familia **Destapadores**. No aparecía en Recepción por DOS cosas:

1. **`estado_compra = 'compra'`** — eran los ÚNICOS 2 componentes de toda la base con ese valor.
   **La convención es al revés de lo que suena: `estado_compra IS NULL` = SE COMPRA (569 comp).**
   Los valores puestos (`fabricacion` 47, `discontinuo` 13, `importado` 4, y este `compra` 2) son
   marcas que SACAN del circuito. `recepcion_bundle` y `oc_bundle` filtran `estado_compra IS NULL`
   → las argollas quedaban afuera. **Regla: nunca poner `estado_compra='compra'`; para "se compra"
   se deja NULL.**
2. **Vivían en Sector Procesado, que NO es sector de insumo** (`_es_sector_insumo(2)=false`).
   `recepcion_bundle` sólo muestra `_es_sector_insumo(sector) OR proveedor∈(Charcas,Eclipse)`, y
   agrupa **por el sector del componente** — no hay un "sector de recepción" aparte. Así que aunque
   se arreglara el (1), en Procesado igual no entrarían.

**Aplicado** (migración `casa_landau_argollas_a_bombilla_y_estado_compra_null`): `estado_compra`
→ NULL, `sector_id` → 7 (**Sector Bombilla**, que sí es de insumo), la fila de inventario del
sector movida de Procesado a Bombilla con su min/max, y `proveedor_insumo.rubro` de Casa Landau →
Sector Bombilla. Sin movimientos ni stock (todo 0), invariante ledger=inventario en 0. Ahora
Casa Landau aparece en Recepción y en la OC, dentro del grupo Bombilla.

**Precio cargado el 2026-09-09** [usuario: "está dentro del archivo de costos, en Lista de
Precios, el precio de las dos argollas dentro de Casa Landau"]. Bloque "3228 - Casa Landau",
precio "Tomado en Costos". Cuál es cuál lo resolvió la hoja **Materiales**, que las nombra:
**Z25A Argolla Grande = $32,99** (ítem "Aro Llavero", ISIS 1225) y **Z25B Argolla Chica = $17,56**
(ítem "Argolla Redonda 70 mm", ISIS 1485). Los destapadores 057/498/516/700 quedaron sin
faltantes. (El 499 sigue con 2 faltantes, pero por el paso de Julio `B12→Z22` sin precio, no por
la argolla — ver §4ad-quater.)

## 4af. Altas de artículos comprados a Pat Bet Plast y envasados (2026-09-09)

**[usuario]** 4 productos que se compran hechos a **Pat Bet Plast** y sólo se envasan. GP2 no los
tenía. Patrón copiado del art **054** (Pinza): la parte se compra, un tallerista la **ENVASA**, y
**cada componente (parte + cartón + caja) entra por su PROPIA ruta** que converge en el terminado
→ virgilio. La caja va de dos formas: FK `articulo.componente_caja_id` con `articulos_por_caja`, y
en la receta a `1/articulos_por_caja`.

| Art | Parte (Pat Bet Plast) | Envasa | Cartón | Caja | UxB |
|---|---|---|---|---|--:|
| 547 Corta Torta | PV8 | **Alex Escalante** | F6B | A4 (N°10) | 12 |
| 569 Pela Naranjas | PV17 | **Lucho** | G5C | A11 (N°29) | 12 |
| 299 Muñeco Antiderrame | PA3 | **Fábrica** | G6B | A11 (N°29) | 12 |
| 280 Manga Repostera + 4 Boquillas | 4× PV14 + 1 manga BOM8B | Fábrica | F1A | A2 (N°12) | 12 |

**Hechos** (migración `alta_arts_547_569_299_pat_bet_plast_display`): 547, 569, 299. Los cartones
ya existían (F6B/G5C/G6B). Demanda ya cargada en est_madre (547=24, 569=80, 299=176/mes).
Invariantes en 0; costo 547=$614,69, 569/299=$180,76.

**Precios de las partes cargados el 2026-09-09** [usuario: "está en costos, buscá por proveedor"]
— planilla, Lista de Precios, bloque Pat Bet Plast (cod 797), tomado en costos: **PV8 $625,72**
(Pinza Corta Torta, f1180), **PV17 $118,64** (Pela Naranja, f339), **PA3 $171,68** (Muñeco
Antiderrame, f343). Migración `precio_partes_pat_bet_plast_547_569_299`. Las 3 partes costean
bien solas.
- ⚠️ **El costo del ARTÍCULO sale inflado por el bug 7275** (la vista cuenta cada componente dos
  veces: en la receta Y en su ruta). Ej.: 547 muestra $1.866 = parte $625,72 contada 2× + cartón
  + caja también 2×. NO es error de carga — lo tienen los 4 y todos los artículos de GP2; se
  corrige cuando se arregle 7275.
- **PENDIENTE**: (a) **precio de PV14** (Picos) — la planilla dice "Picos Reposteros **(4)**"
  $54,60 y falta que el usuario confirme si es por pico ($13,65) o por los 4 ($54,60); (b)
  **tarifa de envasado** de Alex/Lucho/Fábrica (van en `precio_tallerista`, todavía null).
- **familia**: es FK a la tabla `familia`. 569='Peladores' (existe); 547 y 299 no tienen familia
  propia → quedaron en **'Otros'** (el usuario los reubica si quiere).
- `uni_x_cajon` de las partes quedó **NULL**: el "UxB 12" del catálogo es del terminado
  (`articulos_por_caja`), no de cómo Pat Bet Plast entrega la parte.

**280 HECHO el 2026-09-09** (migración `alta_art_280_manga_repostera_4_picos`) [usuario: "además
de cuatro PV14 lleva una manga que se la compramos a Rueda"]. Receta = **4× PV14** (Picos
Reposteros, nuevo, Pat Bet Plast) + **1 manga `BOM8B`** (Tela Manga Repostera, ya existía, se
compra a **Rueda**, sector Bombilla, por rollo de 950) + cartón F1A + caja A2 (1/12). Envasa
Fábrica. `BOM8B` no se tocó (ya estaba bien: prov Rueda, estado NULL). Costo $390, `faltan_precios=6`
(precio de PV14 + tarifa de envasado, pendientes). Invariantes en 0. **Los 4 artículos quedaron
cargados.**

## 4ag. Palo de Amasar Francés (art 234) en el módulo Garaje de Recepción (2026-09-09)

**[usuario: "agregá en recepción de insumos un módulo que se llame garaje y agregá el palo de
amasar francés que se lo compramos a Tierra Nativa y envasa Fábrica"]**

- **El módulo Garaje YA existía**: `recepcion_bundle` arma la lista de módulos con los sectores que
  tienen `sector.es_insumo = true` (la función `_es_sector_insumo` lee ese flag), y **Sector Garage
  (9) ya lo tenía en true** — sólo no se veía poblado con un insumo comprable nuevo. No hubo que
  crear ningún módulo ni tocar HTML. **OJO con el nombre: en todo GP2 el sector se llama "Sector
  Garage" (con G, no "Garaje")** y los tests (`test_stock_sector.js`) y 6 pantallas dependen de ese
  string — renombrarlo a "Garaje" rompería tests, así que se dejó "Garage".
- **Alta** (migración `alta_art_234_palo_amasar_tierra_nativa`): componente `PALO234` "Palo de
  Amasar Frances 40 cm" en **Sector Garage** (código propio, NO GRJ: los GRJ del sector son
  bombillas), proveedor **Tierra Nativa SA**, `estado_compra` NULL (se compra). Terminado 234 en
  sector 12. Ruta: insumo palo → **Fábrica** envasa → 234 → virgilio. Demanda ya en est_madre
  (234 = 396/mes). Aparece en Recepción bajo Sector Garage. Invariantes en 0.
- **Completado el 2026-09-09** [usuario]: (a) **lleva caja N°15** (`A9B`) → agregada a la receta
  (1/12), al FK del artículo y a su ruta; **no lleva cartón** (GP2 no tiene cartón 234 y el usuario
  no lo mencionó). (b) **Precio del palo = $600** (Tierra Nativa, Lista de Precios f888 "Palo de
  Amasar Frances 40cm", tomado en costos; la planilla costea el 234 justamente con L888, NO con el
  "Torneado Palo de Amasar" $1245 de la misma hoja). (c) **La tarifa de envasado de Fábrica NO se
  carga** [usuario: "la tarifa de fábrica no la agregues"]. `234` quedó con `faltan_precios=0`
  (costo inflado por 7275, como todos). familia='Otros'.

## 4ah. Ñoqueras de madera (arts 207, 229, 909) — GRJ12 / GRJ12B (2026-09-09)

**[usuario]** Ñoqueras de madera compradas a **Eduardo Pintos**, envasa **Fábrica** con cartón y
caja. Mismo patrón que el Corta Torta (parte + cartón + caja 1/12; cada componente por su ruta →
Fábrica → terminado → virgilio). Van en **Sector Garage** (son GRJ).

| Art | Parte | Cartón | Caja |
|---|---|---|---|
| 207 Ñoquera Mgo Redondo | `GRJ12B` | G1C | A1 (N°1) |
| 229 Ñoquera Madera | `GRJ12` | G2B | A9 (N°22) |
| 909 Ñoquera Madera | `GRJ12` | S2A | A9 (N°22) |

`GRJ12` (plana) alimenta **229 y 909**; `GRJ12B` (mango redondo) el **207**. Migración
`alta_noqueras_madera_grj12_207_229_909`. Cartones ya existían. Demanda en est_madre (207=890,
229=800, 909=18). Invariantes en 0. Aparecen en Recepción bajo Sector Garage.
**Precio de las ñoqueras cargado el 2026-09-09** [usuario "está dentro de Pintos"], bloque
"3904 - Pintos Lorenzo Eduardo", tomado en costos. Cuál es cuál lo resolvió el Costos del vecino
por CÓDIGO de artículo (no por nombre): 229→L476, 207→L478. **GRJ12 (229 y 909) = $494,69**
("Ñoquera - Madera sin envasar"); **GRJ12B (207) = $693,73** ("Ñoquera Fresada madera a 200").
Migración `precio_noqueras_pintos`. Queda pendiente la tarifa de envasado de Fábrica.

## 4ai. Art 818 "Corta Torta" Chef (gemelo plástico del 547) (2026-09-09)

**Aclaración de historia**: en el primer pedido el usuario listó el 818 pero pasó 4 partes, todas
plásticas de Pat Bet Plast (PV8/PV14/PV17/PA3), y las instrucciones de envasado fueron para
547/569/280/299. El **818 no traía parte ni envasador**, así que quedó afuera (no se saltó: le
faltaban datos). **No es de inox** —la foto blanca engaña— **es Corta Torta plástico** [usuario].

**Hecho** (migración `alta_art_818_corta_torta_chef`): parte **PV8B** (Corta Torta Chef, Pat Bet
Plast, nueva), cartón **O2D** (Cartón 818, creado como el del 547 `F6B` —formato C, Gráficos Pol—
pero **marca CHEF**), envasa **Alex Escalante**. Terminado 818, receta = PV8B + O2D, dos rutas
(parte y cartón) → Alex → 818 → virgilio. Invariantes en 0. PV8B y O2D aparecen en Recepción.
**PENDIENTE (null)**: precio de PV8B, tarifa de Alex, la **caja** (el usuario no la dio; el gemelo
547 usa N°10/A4) y la **demanda** (est_madre 818 no existe).

## 4aj. "Sin formato" en Recepción de Cartones: bolsa 550/760 partida + formatos Manga/C (2026-09-09)

**[usuario]** El chip "Sin formato" en la Recepción de cartones NO significa formato NULL —ningún
cartón tiene formato NULL—. La pantalla arma los chips con un **mapa fijo** `FORMATOS_POR_MARCA`
(en `RecepcionInsumos_GP2.html`), y todo cartón cuyo `carton_formato` no esté en la lista de su
marca cae en "Sin formato". Los que caían:
- **LOEKE → F1A** "Cartón 280", formato **"Manga"** (de Talleres Gráficos Pol) — "Manga" no estaba
  en la lista.
- **CHEF → S2A (909) y O2D (818)**, formato **"C"** — **la lista de CHEF no tenía 'C'** (bug del
  mapa; CHEF sí tiene cartones tipo C).

**Fix (v3.51.0)**: se agregó `'Manga'` a las tres listas y `'C'` a la de CHEF. No queda ningún
"Sin formato". Es sólo el mapa de chips (lógica de display), no toca datos.

**Split de la bolsa 550/760** [usuario: "son dos bolsas distintas: 550 es de LOEKE y 760 de CHEF;
las trae Papelera Nueve de Julio"]: eran UNA sola (`BOLSA550`, marca null) compartida por los dos
artículos (decisión previa del 2026-09-08 "como las de Vihal"). Ahora son dos:
- `BOLSA550` → marca **LOEKE**, art 550.
- `BOLSA760` → marca **CHEF**, art 760 (nueva; se repuntó la receta y la ruta del 760).
Proveedor **Papelera Nueve de Julio** en las dos (ya lo era). Costo 550/760 sin cambio ($651,84).

**Correcciones que resultaron NO necesarias** (los datos ya estaban bien): F1A ya tenía proveedor
Talleres Gráficos Pol; `G8C` (836), `A1B` (031), `A1B1` (120) ya tenían **Envases Vihal**. El
usuario los mencionó pensando que estaban mal, pero no había que tocarlos.
