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

#### El circuito real del inyector `[usuario 2026-09-14]`
*"Nosotros le mandamos las bolsas plásticas y nos las devuelven como partes plásticas."* O sea:
**mandamos la resina (bolsas de sector 14) al inyector → él la inyecta → nos devuelve la pieza
plástica (sector 6)**, más el 4 % de master bach para el color. Es un **servicio**, no una compra.

- **Hoy la pieza está modelada como COMPRADA**, no como inyectada: `componente.proveedor` = el
  inyector (Pat Bet Plast 34, Pettofrezza 13, Kollplast 1, Eduardo Pintos 1 = 49 piezas) y se
  recibe en Recepción de Insumos (rubro Plásticos) como cualquier insumo comprado.
- **EL MODELO YA ESTABA EN LA BASE — no hubo cirugía `[2026-09-15]`.** La resina de cada pieza vive en
  **`componente.material_id`** (apunta al componente-resina del sector 14). 45 de las 48 ya lo tenían
  cargado y COINCIDÍA con la planilla del usuario. NO se costean por el material: `v_costo_componente`
  las da por su **precio de compra** (`origen='precio'`, lo que se le paga al inyector por la pieza
  hecha); `material_id` maneja la **demanda de resina** (cuánta bolsa mandar) y el descuento de resina
  al recibir la pieza (`crear_recepcion_insumo`, sólo si `material_id` está y el inyector tiene ubicación
  — invariante A2). Por eso poner/cambiar `material_id` NO mueve el costo.
- **Fuente del material por pieza:** la planilla del sector plástico, **ahora en
  `db/Conteo_y_Pedido_Sector_Plastico_VACIO.xls`** (hojas *Consumo x Parte* / *Consumo x Cod Articulo*,
  col Material + MB color). kg por pieza en `componente.kg_x_uni`.
- **Lo que se completó/corrigió (usuario dictó los 3):**
  - **PA3** Muñeco → **Santoprene** (`SANTO` id 930, creada sin precio) + kg 0,008 (planilla).
  - **PC16** Inserto Chef → **PP 2630** + kg 0,0038.
  - **PB8A** Mgo Sacac → estaba en PP; el usuario dijo "seguí la planilla" → **ABS**.
  - PEP5 "Mango Madera" queda sin material a propósito (es madera, no inyectado).
- **Corrección:** el cruce por peso contra `A_Costos` daba **PV8 "Corta Torta" = Alto Impacto**; tanto
  la planilla del sector como el `material_id` ya cargado dicen **Ny Recuperado**. La planilla del
  sector manda, `A_Costos` no.
- **Santoprene sin precio:** hasta que tenga precio, la demanda/costeo por material de PA3 no computa
  (PA3 igual costea por su precio de compra).
- **Dónde se eligen los inyectores en la Tablet — tres vueltas, y la última es la que vale:**
  1. *2026-09-14, descartado:* un botón **"Inyectores"** en Enviar que era un link a
     `Compras/Inyectores_GP2.html`. El usuario lo rechazó (*"saca el boton de inyectores y arranca
     la cirugia"*): no quería un atajo a otra pantalla, quería mandarles las bolsas desde la Tablet.
  2. *2026-09-15, v1.3.0:* los inyectores pasaron a mostrarse **dentro de "Prov. de servicio"**, sin
     cirugía: `tablet_bundle` los devuelve como contraparte tipo `'inyector'` con sus **resinas**
     (sector 14) y `tablet_registrar` rutea el envío a `enviar_material_inyector`. NO se los convirtió
     en `proveedor_servicio` de la base: eso habría sido un segundo modelo redundante y habría
     cambiado el costeo de la pieza de *comprada* a *inyectada*.
  3. **HOY — 2026-09-18, v1.14.0:** el usuario los quiere **aparte**, textual: *"quiero que a JL
     Matricera, Kollplast, Pat Bet Plas y Pettofrezza Rafael los pongas aparte como inyectores, no
     adentro de proveedores de servicio"*. Enviar tiene ahora un **cuarto tipo, "Inyectores"** (💉),
     y "Prov. de servicio" volvió a ser sólo PS. Cambió **únicamente dónde se los elige**: adentro es
     la misma pantalla de siempre (sugerido en kg desde la O.C., columna **O.C.** en vez de Máximo,
     cantidad vacía y sin memoria) y el registro sigue yendo a `enviar_material_inyector`.
  **Lo que NO cambió en ninguna de las tres:** en la base los inyectores son `proveedor_insumo` +
  `componente.material_id`, nunca `proveedor_servicio`, y las piezas se costean por su precio de
  compra. Los 4 salen de `componente.proveedor` cruzado contra `proveedor_insumo.nombre`.

#### Cuánta bolsa mandarle al inyector — el máximo sale de la PARTE, no de la bolsa `[usuario 2026-09-16]`
**Regla general de máximos (textual):** *"Los máximos surgen de estadística madre × cant de meses
por ubic."* → `maximo = est_madre (demanda) × ubicacion.meses_stock`. Es lo que ya hace
`recalcular_maximos_*`; el origen queda `est_madre`.

**Inyectores (caso específico) `[usuario 2026-09-16, textual]`:** *"según el máximo de partes
plásticas − stock de partes plásticas = O.C. de partes plásticas, mandarle la cantidad de bolsas
plásticas según esa orden de compra. Porque básicamente le mandamos bolsas plásticas para que luego
nos manden las partes plásticas."* O sea, el máximo/OC **vive en la PARTE plástica (sector 6), no en
la bolsa**:
1. `OC_parte (uni) = max(0, maximo_parte − stock_parte)` (la parte, en el Sector Plástico).
2. `bolsas a mandar (kg de resina) = Σ_partes( OC_parte × componente.kg_x_uni ) − resina ya en poder
   del inyector`, **agrupado por `material_id`** (la resina/bolsa, sector 14). `kg_x_uni` = kg de
   resina por pieza, ya cargado. La resina en poder del inyector vive en `inventario` @
   `ubic_de('inyector', prov_insumo_id)` (ahí la deja `enviar_material_inyector`, que la mueve del sector 14).
   - **`OC_parte` = O.C. REAL, no el déficit automático `[usuario 2026-09-16, textual]`:** *"si no se
     hizo la o.c. aparezca 0, por lo tanto sugerido 0. Recién cuando se manda la o.c. tienen que
     cambiar estos valores."* Así que en el tablet el inyector muestra O.C.=0 y sugerido=0 hasta que
     exista una **orden_compra de las partes plásticas en estado `enviada`** con `proveedor` = el
     inyector (se crea en `Compras/OC_GP2`, que ya cubre las partes de sector 6). `OC_parte` =
     `Σ (orden_compra_item.cantidad − recibido)` de esas OC enviadas. (rep_iny en `tablet_bundle`.)
   - **Distinto de PS/talleristas:** ahí el sugerido SÍ sale del déficit vivo (máximo − stock de la
     salida); el gatillo por O.C. es sólo del inyector.
- **El factor y los máximos ya existen:** las partes de los 4 inyectores ya tienen máximo est_madre
  (JL Matriceria 2/2, Kollplast 1/1, Pat Bet Plast 32/33 —falta 1 sin consumo—, Pettofrezza 13/13).
  Lo que **falta es que la tablet lo muestre como sugerido de bolsas** para el inyector (hoy en
  Enviar el inyector lista sus resinas con "online sector" y sin sugerido — quedó afuera del
  `envConSugerido` de v1.4.0, que sólo cubre PS y talleristas).
- **Ejemplo medido (Pat Bet Plast, partes en stock 0 → piden el máximo entero):** PP 2630 1.985,28 kg
  · Nylon Recuperado 399,70 · ABS GP 22 248,76 · PE Baja 63,43 · Nylon Virgen 22,64 · Santoprene 5,44.

#### Conversión de unidad en el sugerido kg→uni, y el descorazonador mal marcado `[usuario 2026-09-16]`
Cuando lo que se ENVÍA es un fleje/chapa (kg) y la SALIDA es una pieza contada (uni), el sugerido
del tablet ahora convierte el déficit de la salida a kg por su `kg_x_uni` (CTE `rep`, factor `fu`).
Antes daba el número de piezas tratado como kg (ej. CHAPA430 → Eclipse: "402 kg" cuando eran 402
descorazonadores). `fu` NO contempla la merma del corte (para eso iría `ruta_paso.cantidad` = kg de
chapa por pieza).
- **Trampa de datos:** el fu se dispara mirando `componente.unidad_medida` de la salida. El
  **Descorazonador (1686, id 596) está marcado `unidad_medida='kg'`** siendo el único de los 86 de
  Sector Procesado así (los otros 85 son 'unidad'); por eso su chapa seguía dando 402. Es un dato
  mal cargado (consumo 402 uni/mes, kg_x_uni 0,014508 = peso de UNA pieza; 0 movimientos, stock 0).
  Corregirlo a 'unidad' hace que la chapa dé 402 × 0,014508 ≈ 5,83 kg.

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
  - **Los mangos crudos SÍ existen como componente** `[dato: GP2.componente]`: **PC2** (id 622,
    "Mgo Pelapapa 505 Sin Calar") → Esther lo cala → **PC1A**; **PC3B** (id 621, "Mgo Pelapapa
    123 Sin Calar") → Esther lo cala → **PC1B**. Esa aclaración de proceso (quién cala y hacia
    qué código sale) **vive acá, no en la descripción del componente** `[usuario 2026-09-17:
    "no quiero que los componentes tengan descripciones así de largas… las aclaraciones
    guardalas en el conocimiento"]`: la descripción quedó en el nombre corto y el paso
    crudo→calado se documenta en este archivo. Falta todavía cargar la ruta PC2→PC1A / PC3B→PC1B
    y la tarifa de Esther.
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
  - **`B1-M78` (id 486, "Rompenuez Ch Pint. Remachado") y `D5-M78` (id 485, "Rompenuez LK
    Crom. Remachado")**: el `-M78` es porque son la variante **remachada tras pasar por la
    matriz M78** `[dato: GP2.componente]`. Ese "tras M78" se saca de la descripción y se anota
    acá `[usuario 2026-09-17: "las aclaraciones guardalas en el conocimiento, no en las
    descripciones"]`; la descripción quedó como nombre corto ("…Remachado").

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
- **La Cremallera (IE13) se recibe en el rubro Importados, no en Flejes** `[usuario 2026-09-22:
  "La cremallera mandala al módulo importado. Borra el módulo importado dentro de flejes"]`.
  Se hizo con `estado_compra='importado'` (id 219): la Recepción arma Importados por esa marca y
  Flejes la excluye, así que el chip "Importado" de Flejes desapareció solo.
  **CORREGIDO el 2026-09-23**: ya no se llama `IE13` ni vive en Sector Fleje — es **`E13`, Sector
  Procesado, y se cuenta por UNIDAD** (no en kg). Lo que arriba decía "se recibe en unidades y se
  guarda en kg" era justamente el problema: mientras estuvo en el sector de los flejes **no costeó
  nada**. Ver §4ft.
- **BOM8B Tela Manga Repostera: se cuenta por ROLLO, 900 uni por rollo; se compra a Rueda y Cia**
  (`proveedor_insumo` 'Rueda', cod_prov 3372) `[usuario 2026-09-22]`. **CORRECCIÓN:** el nombre
  viejo del componente (id 619) decía "950 uni por rollo" — estaba mal; son **900**. El paréntesis
  se sacó del nombre (`descripcion='Tela Manga Repostera'`). `uni_x_paquete` sigue NULL hasta que
  se decida cargarlo (ojo, en OC puede redondear a rollo entero). La planilla de costos lista a
  SIMKO SA como "(tela Manga Repostera)", pero esa fila es Santoprene: NO es el proveedor de la tela.
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
  Mangos ф10 LK, `PA17` Mangos Cuch y P Torta, `PB1` Cilindro Corta Queso, ~~`PC6` Ojales
  Neg/Blanco~~ (**hecha el 2026-09-10**, ver §4am), `PEST1` Insertos Mgo Madera, `PEST2`
  Insertos Pisa Papas.
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

**RESUELTO EN PARTE (2026-09-10, CAMINO A del usuario):** se alineó GP2 con la planilla.
Se renombraron en GP2 **`GRJ14` (Bombilla Pico de Loro) → `GRJ18`**, **`GRJ15` (Bombilla Plana
Ancha) → `GRJ19`** (que es como los llama la planilla) y **`GRJ13` (Bowls 330ml, discontinuo)
→ `GRJ21`** (parkeado). Con 13/14 libres se cargaron los cepillos de **Gilardi Esther**
(proveedor nuevo, cod 3847): **`GRJ13` Cepillo Limpia Mamadera** (535/307) y **`GRJ14` Cepillo
Limpia Vajilla** (534/052), y los 4 artículos (ver HISTORIAL/1-duodecies). **Falta todavía** de
idea 7248: la **`GRJ15` Pintura Azul Mate (Ortiz Yanina)** —el código 15 quedó libre para
ella— y las partes `GRJ16`/`GRJ17`/`GRJ20`. Lo de abajo queda como registro del enredo original.

`[dato: planilla "Relevamiento Garage VACIO", hoja "Pedido Garage VACIO"]` 17 renglones. Tres
códigos eran dos cosas distintas al mismo tiempo (antes de Camino A):

| código | en la planilla del usuario | en GP2 (antes) |
|---|---|---|
| `GRJ13` | Cepillo Limpia Mamadera (Gilardi) | Bowls 330ml (Cimarrón, discontinuo) |
| `GRJ14` | Cepillo Limpia Vajilla (Gilardi) | Bombilla Pico de Loro (Cimarrón) |
| `GRJ15` | Pintura Azul Mate (Ortiz Yanina) | Bombilla Plana Ancha (Cimarrón) |

Y del otro lado, los **`GRJ18`/`GRJ19`** de la planilla (Bombilla Pico de Loro y Bombilla
Plana Chata) eran los que GP2 llamaba `GRJ14`/`GRJ15`: las mismas bombillas con dos números.
El Camino A lo resolvió renumerando las bombillas a 18/19.

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
`[usuario 2026-09-29]` Confirmado otra vez: *"RULETA no se usa para ningún artículo, es para afilar la piedra
que afila"*. Por eso no tiene consumo y su máximo (27.175) queda `fisico`: la regla de consumo le daría 0.

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
**exactamente el BOM del `GRJ1`**. Se reemplazaron por el GRJ1, igual que el **506** llevaba
`GRJ7` en vez de `A10 + C10 + V9` (**⚠ corregido el 2026-09-17: el GRJ7 se borró y el 506 volvió a
las tres partes sueltas, ver §4eb; el 500 y su GRJ1 NO se tocaron**). **Si se dejan los dos, el armado se cuenta dos veces.** El
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
artículo) y los **diez de bombilla a 1/16** ($915 → $57,19).
⚠ **Corregido el 2026-09-18 (ver §4el): el 500 y el 506 YA NO LLEVAN PLIEGO** — pasaron a cartón
(`CART500` / `CART506`, ×1, $89). **Hoy los artículos con pliego son 10**, los de bombilla, y son
los únicos a los que se les aplica esta regla. El `Pliego Ad 500` estaba con
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
- **RECICOR TAMBIÉN ENTREGA LAS CAJAS, desde el 2026-09-17** `[usuario, textual: "dentro de
  cajas, además de corrugadora del plata, tenés que agregar al proveedor Recicor. Entrega las
  mismas cajas que corrugadora. El control de remito es igual al de corrugadora"]`. Son **las
  mismas 11 cajas de GP2** (no hay cajas propias de Recicor) y el control de remito es el
  mismo: `modo_control='ninguno'`, sin pesaje ni rollos. `cod_prov` ISIS **4370** (salió de su
  propia lista de precios, `precio_proveedor.cod_prov='4370'`).
  **A Recicor también se le emite O.C.** `[usuario 2026-09-17: "en las órdenes de compra
  tendrías que agregar a recicor también"]`, y la O.C. sale con **SU** precio: sus 8 precios que
  matchean una caja de GP2 se vincularon al componente y `oc_bundle` manda ahora el precio de
  cada proveedor (`precios_prov`). **El precio VIGENTE no cambió** —el que usa el costo sigue
  siendo el del Plata— porque el desempate es por `cod_prov` contra el proveedor asignado al
  componente, no por fecha. Verificado antes y después: los 11 precios y los 11 costos, iguales.
  **FALTA EL DATO**: Recicor **no cotiza las cajas N°15, N°16 y N°22** (su lista trae la N°27,
  que en GP2 no existe). En una O.C. a Recicor esas tres van **sin precio** —no se les pone el de
  Corrugadora, sería inventar plata— y la barra avisa "⚠ N ítems sin precio". Si Recicor las
  entrega, hay que pedirle el precio y cargarlo.
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
  **CORREGIDO EN PARTE EL 2026-09-23 (§4fo)**: los dos **bujes** (`PA8A`/`PA8B`) ya son de
  **Kollplast** a $20,48, por decisión del dueño. El **Pirolo sigue en Pat Bet** y ahí el barato
  es Pat Bet, así que no hay nada que mover.
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
- `[dato, corregido 2026-09-17]` **`precio_proveedor` no tiene FK al proveedor** (solo
  `cod_prov` text sin destino). **La trampa que decía esta línea ya no existe**: decía que
  vincular los precios de Recicor a un componente haría que las 9 cajas cambiaran de proveedor
  solas, porque el único desempate era `fecha_lista DESC`. Eso dejó de ser cierto el 2026-09-10,
  cuando `pv` (en `oc_bundle`, `crear_oc` y `v_costo_componente`) pasó a desempatar **primero
  por `cod_prov` contra el proveedor asignado al componente**. Los 8 precios de Recicor que
  matchean una caja SE VINCULARON el 2026-09-17 y ni un precio ni un costo se movió (medido).
  Lo que sigue faltando es la FK: el proveedor se sigue deduciendo por `cod_prov`.
- `[dato 2026-09-17]` **Un componente puede tener MÁS DE UN proveedor: `componente_proveedor_alt`.**
  `componente.proveedor` es un texto y es el proveedor **principal** — el que manda en la O.C.
  y en el costo. Los que **también** entregan esa misma pieza van a la tabla puente
  `GP2.componente_proveedor_alt (componente_id, proveedor)`, y `recepcion_bundle` los manda
  como `proveedores_alt` para que Recepción de Insumos muestre la pieza bajo los dos chips.
  **Por qué puente y no duplicar el componente**: una caja duplicada serían dos filas de
  inventario para la misma caja física, o sea dos stocks y dos máximos de la misma cosa.
  Primer caso: Recicor + las 11 cajas de Corrugadora (arriba).
  **La O.C. también se le puede emitir a cualquiera de ellos** (2026-09-17, mismo día): la
  botonera de `OC_GP2` sale de principal + alternativos y el **precio sigue al proveedor
  elegido** (`oc_bundle.insumos[].precios_prov`). Si el elegido no cotizó esa pieza, la fila va
  sin precio: no se rellena con la del otro.
  **El cruce contra O.C. ya mira quién entregó**: `_aplicar_recepcion_a_oc` toma un
  `p_proveedor` y aplica **primero** la O.C. de ese proveedor; si no alcanza, sigue con las
  demás (una entrega tapa la necesidad igual, así nada queda colgado). Antes cruzaba la más
  vieja sin mirar quién trajo la mercadería, y con dos proveedores de la misma caja eso le
  descontaba a la O.C. equivocada.
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

## 2c-septies. El 506 va con SKIN: Gentile y el garage (2026-08-31) — ⚠ DADO DE BAJA el 2026-09-17

> **Esta sección ya no describe la realidad.** El 2026-09-17 el dueño dio marcha atrás: Gentile
> no ensambla ni envasa más el 506, el `GRJ7` se borró y arman Martin Cornejo o Alex Escalante,
> que entregan directo a Virgilio (el molde del 500/510). **Lo vigente está en §4eb.** Se deja
> el texto porque explica de dónde salían el skin y el paso por el garage.

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

> ⚠️ **CAMBIADO EL 2026-09-29 (§4gu):** el máximo de Crudo/Procesado es consumo × `meses_stock` del sector
> **con tope de 5 cajones** (el menor de los dos). El faltante automático ya no es "< 1 cajón": es **stock < máximo**.

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

## 2e-ter. Disparo del pedido y dimensionamiento del máximo: mínimo de reposición + reserva `[usuario 2026-09-10]`

Es el criterio real con el que hay que definir mínimo/máximo/pedido en crudo y procesado —
refina §2e (los "5 cajones" son un placeholder físico, no este criterio). **Ejecutado
parcialmente para FAAT el 2026-09-10** (ver el bloque "EJECUCIÓN FAAT" al final de esta sección).

**Cuándo se dispara el pedido (mínimo de disparo):**
- **Procesado** (ej. Arandela CienGranajes): el pedido se dispara al bajar a **1 mes de
  stock** de esa parte (mes medido por Est Madre / consumo de la parte).
- **Crudo**: la reserva que no puede quedar en cero es de **1 a 1,5 meses** de stock; ese es
  el piso que dispara el corte.

**Cuánto se pide (lote / pedido MÍNIMO — es un concepto aparte del mínimo de disparo):**
- **Procesado** que va a cementar (caso FAT): el lote mínimo es **1 cajón = 30 kg**. Ese
  cajón vuelve entero y completa el sector procesado.
- **Crudo**: el corte mínimo son **3 meses** de stock (para que el corte valga la pena).

**Cómo tiene que quedar el máximo (la clave de todo esto):** el máximo del lugar NO es solo
"5 cajones"; tiene que **contemplar el lote mínimo de reposición MÁS la reserva** que había
cuando disparó el pedido, porque los dos van a convivir físicamente en el sector.
- Ejemplo del usuario (procesado): si la reserva de disparo son ~15 kg (2 semanas) y el lote
  que vuelve es 1 cajón de 30 kg → el lugar tiene que tener sitio para **~45 kg** de
  procesado (lo que quedaba + lo que entra).
- Regla general: `máximo ≥ reserva_de_disparo + lote_mínimo_de_reposición`. Hay que definir
  las TRES cosas (máximo, mínimo de disparo, y lote mínimo de pedido), no solo máximo y
  mínimo. El espacio entre "lo que había cuando disparó" y "lo que acabamos de cortar/cementar"
  tiene que entrar TODO en el sector.

**Circuito FAT (CORREGIDO por el usuario en el mismo mensaje):** FAT **no entrega directo al
cromador**. FAT entrega en **sector tránsito**, y **del sector tránsito se manda al
cromador**; el cromador es el que completa el sector procesado. (El dictado inicial decía
"FAT va directo al cromador" — es falso, va por tránsito.)

### EJECUCIÓN FAAT (2026-09-10) `[usuario, decisiones tomadas por AskUserQuestion]`

FAAT = `proveedor_servicio` id 2, "Laboratorio FAAT" (nombre_corto "FAAT"), proceso
"Templado, Cementado". No existe variante "FAT" ni "Arandela CienGranajes" en la base; la
única arandela por FAAT es **K11** "Arandela grande Afila p/cementar y zincar". En las rutas
el paso FAAT tiene entrada = salida con el MISMO código crudo (vuelve a crudo/tránsito); el
procesado lo genera un paso posterior (cromador) → confirma el circuito FAAT → tránsito →
cromador de esta sección.

Decisiones del usuario para esta corrida: **(a)** alcance = las 10 piezas que pasan por FAAT;
**(b)** el máximo se aplica en la ubicación del **crudo que va a FAAT** (no en el procesado
destino); **(c)** la reserva de disparo se deja en **2 meses** (el mínimo actual `consumo × 2`,
NO se bajó a 1); **(d)** el lote conflictivo (30 kg vs 1 cajón real en W1/W2/W7) se ve después.

**Aplicado a 4 piezas de Sector Crudo** con `maximo = mínimo (reserva 2 meses) + 30 kg`
convertido a uni por `kg_x_uni`, origen nuevo **`maximo_origen = 'faat_reserva_lote'`**:
- I14 Cuchilla Abrelata: 17.085 → **35.719** uni (313,6 kg)
- K11 Arandela: 30.405 → **7.191** uni (35,5 kg)
- L13 Uñas p/Zincar: 41.360 → **64.208** uni (232,9 kg)
- X4 Cuchilla Pelapapa Cerrada: 20.020 → **93.990** uni (462,4 kg)

Migración `faat_maximo_reserva_mas_lote`: se amplió el CHECK `inventario_maximo_origen_chk`
(+`faat_reserva_lote`) y se enseñó a **`recalcular_maximos_cajones()`** a NO pisar este origen
(igual que ya respeta `'fisico'`). Verificado: la función corre y deja las 4 intactas; ledger
vs inventario (invariante B) = 0. Snapshot antes/después en `db/respaldo_maximo_faat_20260910.csv`.

**NO se tocó (pendiente del usuario):**
- **W1 / W2 / W7** (Sector Crudo): su `uni_x_cajon` da ~2 kg por cajón (contra 30 kg del resto).
  "30 kg = 1 cajón" no cierra para ellas (30 kg = ~15 cajones). El usuario lo revisa: o el
  `uni_x_cajon` está mal cargado, o para esas piezas el cajón no son 30 kg. Quedan en `cinco_cajones`.
- **RULETA** (Sector Crudo): sin consumo cargado → no hay reserva de 2 meses que calcular. Queda en `cinco_cajones`.
- **I2 / I3** (Sector Bombilla, no Crudo): fuera del alcance "el crudo que va a FAAT" que eligió el usuario. Quedan en `est_madre`.

**Pendiente de modelo (no ejecutado):** el máximo se fijó como UPDATE puntual, no se
recalcula solo cuando cambia el consumo (el mínimo sí, vía `recalcular_minimos`). El "lote
mínimo" (30 kg cementado / 3 meses crudo) NO vive todavía en un parámetro ni función; cuando
se cierre W1/W2/W7 conviene hacerlo función. Falta también el lado CRUDO puro (corte de 3
meses + reserva 1–1,5 meses) y el disparo automático del pedido (hoy Crudo/Procesado no entran
a `oc_bundle`; sólo la marca de faltante de §2e los cubre, y dispara a 1 cajón, no al mínimo).

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
  **Martín Cornejo, ALEX ESCALANTE, IJUPA y LUCHO.** `[usuario 2026-08-31, corregido]` El dato
  original decía Carlos Aguirre, pero el usuario lo corrigió: *"Carlos es el papá de
  Alex, por eso le erré"* — son familia y por eso el cruce de nombres. Normalizado en
  `GP2.tallerista.entrega_cervantes` (true para ids 6, 2 y 10 — migraciones
  `talleristas_que_entregan_en_cervantes` + `entrega_cervantes_correccion_alex_no_carlos`).
  `[2026-09-04]` Esa columna se **borró** (ningún código la leía); el dato queda acá: los que
  entregan en Cervantes son Martin Cornejo (6), Alex Escalante (2), IJUPA (10) **y Lucho (5)**.
  `[usuario 2026-09-13, correctivo: "3 lucho tambien"]` Lucho faltaba en esta lista pero SÍ
  estaba en las rutas (J1 Tochos Zinc p/Rectificar → Sector Crudo, 3 rutas): la lista escrita
  a mano era la que estaba vieja, no la parametrización. **No hay tabla de configuración de
  quién entrega en Cervantes: sale de `ruta_paso`** — todo paso `tallerista` cuyo
  `comp_salida` NO cae en Terminado (sector 12) es una entrega en Cervantes; si cae en
  Terminado va por Recepción Virgilio. Antes de decir que alguien "no debería estar", mirar
  la ruta: la ruta manda.
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
| `CV18D` Tornillo Sacafuente p/Niquelar | ~~Tornillos Suipacha~~ **Imel** (corregido 2026-09-25, 4gi) | Guazzaroni Patricio | `V18D` | Martin Cornejo | 508, 708 |
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

**⚠ 2026-09-17 — esta tabla es la foto de ANTES.** El cambio se hizo, pero sólo en la mitad que
pidió el dueño: el 506 pasó al molde del 510 en armado y entrega (Martin/Alex, sin GRJ7, sin
Gentile), y **se quedó con el pliego adhesivado**, no con el cartón suelto. Ver §4eb.

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

> `[usuario 2026-09-28]` *"Sigue apareciendo Gentile Norberto y ya no es más tallerista"*.
> `[dato 2026-09-28]` Para esa fecha Gentile ya tenía **0 `ruta_paso`** (la cirugía de abajo se
> hizo) pero seguía `tallerista.activo = true`. Se pasó a `activo = false`; sus 13 filas de
> inventario (todas en 0) quedan en la base y Stock General las oculta.
> `[usuario 2026-09-28]` *"todo lo que es inventario de virgilio eliminalo (para eso está gestión
> virgilio)"*: **Stock General no muestra la ubicación Virgilio** (tipo `virgilio` /
> `virgilio_sector`) ni la columna "En Virgilio". El sector Bolsas Plásticas (en Virgilio) sí
> queda: es materia prima de GP2.
> `[usuario 2026-09-28]` "Sí" a borrar las filas de Virgilio de la base. `[dato]` De las 268 filas de
> `inventario` en ubicación 33 (todas cantidad 0) se borraron **189**; quedan **79**: terminados
> (sector 12) con `maximo` cargado, porque `v_reposicion` toma ESA fila como el máximo del terminado
> y de ahí leen `oc_bundle` y `valorizacion_bundle` (264.453 uni de sugerido). Borrarlas cambiaba OC
> y valorización. Respaldo: `GP2.bkp_inventario_virgilio_20260928` (268 filas, RLS prendida).
> `[usuario 2026-09-29]` "Borra": el respaldo se eliminó (`drop table`). Con él se perdieron los
> `maximo` de 86 de las 189 filas borradas; no hay otra copia. Ese mismo día se vaciaron también
> `GP2.movimiento` (2 filas, `entrega_ps` de prueba) y `entrega_control`, y todo `inventario.cantidad`
> quedó en 0 (las 1.137 filas y sus `maximo` siguen).
> `inv_delta` hace upsert, así que un movimiento nuevo a Virgilio recrea la fila sola.

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

### 2026-09-10: el usuario la siguió subiendo en cada sesión — y el archivo ahora VIVE EN EL REPO

`[usuario 2026-09-10, textual]` *"lo subo acá. Ya lo subí muchísimas veces. No sé qué hacer para
que lo tengas guardado."* Pasaba porque **ninguna sesión sabía que estaba en la base** (no estaba en
`CLAUDE.md`) y porque `.gitignore` excluye todo `*.xlsx`. Arreglo doble:
1. **`db/A_Costos_VIGENTES.xlsx` está en el repo** (excepción en `.gitignore`, 7,8 MB). Toda
   sesión lo tiene sin que nadie lo suba. Si el usuario manda una versión nueva, **se reemplaza
   ese archivo** (misma ruta) y se refresca el snapshot con `planilla_snapshot_nuevo` +
   `planilla_cargar`.
2. **Regla en `CLAUDE.md`** («🧭 Otros archivos vivos»): la planilla vive en la base
   (`v_planilla_precio` / `v_planilla_costo`) y en `db/`; **no se le pide al usuario**.

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

### 4ak. El remache V3 en la familia Sacacorchos: qué remacha en cada artículo (2026-09-10)

`V3` "Rem. Sacatapita Niq" **no siempre remacha una sacatapita**. Lo que remacha es lo que haya
en esa posición del cuerpo, y eso cambia por artículo [dato: `articulo_componente` + `ruta_paso`
de 520/521/530/531/730/731, cruzado 2026-09-10]:

| Artículo | Cuerpo | Qué lleva en esa posición | V3 | Dónde entra el V3 |
|---|---|---|---|---|
| 520 | C15 (Fleje 93) | Cuchufli E15 | sí | Martin Cornejo, al ensamblar |
| 521 | C16 = G4 cromado | Sacatapita K8 **soldada al cuerpo** | sí | **Matriz 135 "Remachado Sacatapita"**, dentro del G4 |
| 530 | B4 (pintado Jade) | Cuchufli E15 | sí | Martin Cornejo |
| 531 | B4 | Sacatapita C8 suelta | sí | Martin Cornejo |
| 730 | B7 (serigrafiado) | Cuchufli E15 | sí | Martin Cornejo |
| 731 | B7 | Sacatapita C8 suelta | sí | Martin Cornejo |

Dos reglas que salen de ahí:

1. **El 521 NO lleva cuchufli** [usuario 2026-09-10: "en el 521 aparece el Cuchufli E15, esa ruta
   borrala, porque no lleva cuchufli el 521"]. Su sacatapita va **soldada** al cuerpo
   (`componente_bom` de `G4` = K5 + K8 + V3, unidos por la Matriz 135), así que no hay pieza
   suelta que remachar aparte. Se borró la ruta `Insumo E15 -> Art 521` y su línea de receta.
2. **El 520 SÍ lleva V3 y le faltaba** [usuario 2026-09-10: "del 520 le falta el remache a esa
   sacatapita V3, al igual que está en el 530"]. Se agregó receta + ruta
   `CV3 → Guazzaroni Patricio (Niquelado) → V3 → Martin Cornejo → 520`, calcada de la del 530.

**Antes de ser V3 es CV3** ("Rem. Sacatapita Niq p/Niquelar"): el remache se compra a **Bella
Vista** sin niquelar y pasa por **Guazzaroni Patricio** [usuario 2026-09-10: "antes de ser V3 es
CV3, le falta la ruta del niquelado"]. Eso vale para los 6 artículos; al 521 le faltaba esa ruta y
se cargó (converge en la Matriz 135, no en el tallerista).

**Trampa de pantalla que salió de acá**: en "¿Qué necesito para producir?" (`Programa/Programa.html`)
las ramas de un convergente sólo aceptaban rutas que arrancan en un **fleje** (`programa_bundle`
marca `f` sólo si el ingreso es del Sector Fleje; CV3 es Sector Remache). Por eso la rama del V3
se dibujaba como un insumo pelado y **se comía el paso del niquelado**. Desde la v1.114.0 la rama
usa la ruta de insumo como fallback y esa ruta ya no se repite abajo en el bloque 4.
Lo cubre `tests/ui/test_programa_conv.js`.

**Peso de K8**: `0,013956667 kg` = **13,96 g**, ya estaba cargado en GP2 (el usuario dudaba).

### 4al. Stock Tránsito PS: qué es y por qué no hay stock de sector (2026-09-10)

[usuario 2026-09-10, textual]: *"Son partes que van de un proveedor de servicio a otro proveedor de
servicio. Lo que el proveedor de servicio de origen ya entregó y espera hasta mandarse al proveedor
de servicio siguiente es lo que se le llama stock tránsito. Después de que vuelva de FAAT vuelve el
Resorte U templado, pero después se tiene que ir a niquelar, entonces **no hay un stock de sector
procesado para esa parte, porque queda en tránsito** y después se va al otro proveedor de servicio."*

**La regla ya estaba en la base y es una sola** (`stock_transito_ps_bundle`, módulo *Stock Tránsito
PS*): **dos pasos `proveedor_servicio` consecutivos de la misma ruta donde el segundo consume lo que
salió del primero**. No hay un "Sector Tránsito" en `GP2.sector` (los 13 sectores no lo incluyen):
tránsito es un **estado**, no un lugar. Al 2026-09-10 hay **61 tramos** así, todos en rutas de fleje.

**Caso testigo — Resorte U, ruta 90 (Fleje 26 → art 053)**:
`M68 → M69 → I2 (Sector Bombilla) → FAAT (Templado) → ⟨tránsito⟩ → Guazzaroni (Niquelado) →
⟨tránsito⟩ → Pedernera (Cromado) → C9 (Sector Bombilla) → Pettofrezza`.
El I2 pasa por Sector Bombilla **una sola vez**: cuando lo deja la Matriz 69 y espera para salir.
Después de cada PS ya no vuelve.

**Ojo con la diferencia**: de **matriz → PS** SÍ hay stock de sector (la pieza se fabrica y espera
que la manden). De **PS → PS** NO. Sólo el segundo caso es tránsito.

**En pantalla** (`Programa/Programa.html`, desde v1.115.0): ese nodo dice **`🚚 Sector / TRÁNSITO`**
con el código, la descripción **sin su destino viejo** y el proceso que espera —
`I2 · Resorte U p/Niquelar`, y debajo a quién va (`→ Guazzaroni Patricio`). O sea: la descripción
del componente sigue diciendo "Resorte U p/Templar" en la base (es su nombre), pero una vez
templado lo que espera es el niquelado, y eso es lo que se muestra. El proceso se pasa a infinitivo
con un mapa chico (`PROC_INF`) + la regla `-ado → -ar`. Lo cubre `tests/ui/test_programa_transito.js`.

### 4am. PC6 "Ojales Neg/Blanco": **1 ojal por artículo** (2026-09-10)

[usuario 2026-09-10, textual: *"1 ojal"*] — cierra el único pendiente que había dejado el alta de
PC6 en los artículos **720 y 722**: la cantidad era **asumida** (se clonó el patrón de PC16, que
es 1). **Confirmada: 1 por artículo.** No hubo que tocar nada, `articulo_componente` ya tenía
cantidad 1 en los dos [dato: consulta a `articulo_componente` del 2026-09-10].

PC6 se compra a **Pat Bet Plast** (Sector Plástico) y lo ensambla el tallerista **Fábrica**.

**Sigue pendiente de PC6** (no inventar): el **precio** de Pat Bet Plast y la **tarifa de
envasado de Fábrica**. Mientras falte el precio, el 720/722 muestran `faltan_precios = 2` — es el
doble conteo conocido (idea 7275: la vista cuenta el componente en la receta Y en la ruta), no un
error de carga; se va a 0 solo al cargar el precio.

### 4an + 4an-ter. El 515/615 — BORRADO (ver §4cq)

Acá vivían dos secciones del 2026-09-10 sobre los batidores 515/615, sus partes y sus pendientes.
**El artículo y todas sus partes exclusivas se borraron de la base el 2026-09-13** y el tema está
cerrado: la historia está en el backup y en git. **No analizarlo ni volver a proponerlo.** §4cq.
### 4an-bis. Regresión propia: la Rama de un insumo quedaba vacía ("? produce BOM10")

La v1.114.0 dejó que las ramas de un convergente usaran rutas de **insumo** (para mostrar el
niquelado del V3 en el 521). Efecto no previsto: en una rama cuyo **único paso es el `insumo`** —el
BOM10 dentro del C12— el código buscaba el origen sólo en un paso `ingreso` y el fleje de la ruta
(`ruta.f`, null en una ruta de insumo), así que dibujaba **`Rama 1 — ? produce BOM10`** con el nodo
vacío. Al usuario le pareció que el Resorte Bicónico se había borrado.

Arreglado en la **v1.116.0**: el origen de la rama también se toma del paso `insumo`, y `insumo`
—como `ingreso`— no cuenta como paso productivo. Lo cubre `tests/ui/test_programa_insumo_conv.js`
con la convergencia C12 real. **Lección**: al ampliar qué rutas entran a un render, revisar el caso
de la ruta de **un solo paso**.

### 4ao. `articulo` ya tiene DESCRIPCIÓN y MARCA (2026-09-10)

Hasta hoy `GP2.articulo` era `codigo + familia + caja` y nada más: la única "descripción" de un
artículo era la del componente terminado, que dice **"043 Terminado"** — inútil para una pantalla.
Migración `articulo_descripcion_marca_cruce_listados`: se agregaron **`descripcion text`** y
**`marca text`** (check `LOEKE` / `CHEF`, el mismo dominio que ya usa `componente.marca` — no
inventar `loekemeyer`/`chef` en minúscula).

**Fuente**: los dos listados mayoristas del usuario del **10/09/2026** (`loekemeyer.com/mayorista`
y `chefsrl.com/mayorista`), 199 y 100 códigos, 296 únicos. Cruce por código exacto:

| | Códigos |
|---|---|
| Ya en `GP2.articulo`, descripción cargada del listado | 110 (66 LOEKE, 44 CHEF) |
| Los 10 que no figuran en ningún listado, descripción **dictada por el usuario**, marca LOEKE | 101, 103, 104, 108, 114, 115, 116, 120, 121, 123 |
| Sin descripción a propósito (los 3 corta queso ya discontinuados) | 119, 574, 809 |

**Ningún código de los 110 aparece en los dos listados a la vez** → la marca sale sola del cruce,
sin desempate.

**Ojo con `809E`**: está en **los dos** listados con **productos distintos** — Loekemeyer lo usa
para *"Corta Pizza Mgo Ergonómico 6cm"* y Chef para *"Corta Queso Blandos Mango Alambre"*. No se
cargó ninguno de los dos; si alguna vez hay que asociarlo al 809 de GP2, preguntar primero.

**El backlog medido contra ESTOS listados** (ojo: es otro universo que el conteo de §2f-bis, que
salía de la Est Madre por demanda — no se comparan). De los 186 códigos que no están en
`GP2.articulo`: **95 llevan sufijo E** (importados, fuera del alcance de GP2 — regla vieja de
§2f-bis, reconfirmada por el usuario el 2026-09-10: *"la e significa que es importado y en
principio los art importados no los quiero en gp2"*), **44 ya están cubiertos por
`articulo_prov_at`** (comprados terminados: coladores, cucharas de madera, tapones, espátulas,
ralladores…) y quedan **45 de backlog real** (20 LOEKE, 25 CHEF), sobre todo Madera, Utensilios,
Accesorios y Repostería.

**Pendiente**: los 3 corta queso (119, 574, 809) ya están `discontinuado = true`, que es la baja
que la casa reconoce. Borrarlos de verdad NO lo puede hacer `abm_articulo_baja`: las FK de `ruta`
y `articulo_componente` son `NO ACTION`, y cada uno cuelga **5 rutas, 22 pasos y 5 líneas de
receta** (más su cartón propio CART119 / CART574 / CART809, que quedaría sin uso). Es cirugía, no
un flag: pedir confirmación explícita antes de tocarlo.

### 4ap. Las familias de GP2 pasan a ser las del CATÁLOGO MAYORISTA (2026-09-10)

`[usuario 2026-09-10]`: *"antes teníamos otras familias… quiero que uses las que te mandé recién"*.
Las 23 familias que había las inventó GP2 por criterio productivo; las que manda ahora son las
**19 del catálogo mayorista** (los mismos dos listados del 10/09/2026 de §4ao). Migración
`articulo_familia_segun_catalogo_mayorista`: altas de `Coladores`, `Contenedores`, `Cortadores`,
`Mate` y `Utensilios` en la tabla `familia`, y los **123 artículos** reasignados. Quedan **15
familias con artículos** (las 4 del catálogo que GP2 no usa —Acacia, Ralladores, Tapón Vino,
Vidrio— son todas de artículos que GP2 todavía no tiene).

**El catálogo agrupa más grueso que la producción.** Lo que se pierde, a propósito:

| Familia GP2 vieja | Ahora | Arts |
|---|---|---|
| Bombillas | Mate | 12 |
| Cortadores (pizza) + (queso) + (ravioles) | Cortadores | 8 |
| Ahuecadores + Rompenueces + Sacafuentes | Accesorios | 9 |
| Batidores | Repostería | 5 |
| Pisa papas + Palas de canelones + Utensilios de nylon | Utensilios | 15 |
| Bowls | Contenedores | 1 |

**Dos incoherencias del catálogo que se copiaron TAL CUAL** (son del listado, no del cruce; si el
usuario quiere otra cosa se corrigen con una línea):
1. **El filtro de café se parte según la marca**: 031/034 (LOEKE) van a **Coladores** y los gemelos
   836/867 (CHEF) a **Accesorios**. Mismo producto, dos familias.
2. **248 y 908, "Cuchara Nylon 33 cm", quedan en `Madera`** porque así los lista el catálogo. Son
   de nylon.

Las 3 familias viejas que quedaron sin artículos siguen en la tabla `familia` (no se borran: son
FK y no molestan — el filtro del ABM se arma con las familias que los artículos usan, no con la
tabla). Ojo con **`componente.carton_categoria`**: se cargó el 2026-09-08 cruzando contra la
familia VIEJA (Abrelatas / Pelapapas / Sacacorchos / Resto). Es un valor **materializado**, no un
join vivo, así que la OC de cartones no se movió — pero los dos criterios ya no son el mismo y
conviene no volver a derivar uno del otro.

### 4ap-bis. "¿Qué necesito para producir?": filtro de marca y descripción en el combo

Antes el combo decía `501 — Abrelatas`: el código y la **familia repetida** en cada opción, sin
decir qué es el artículo. Ahora (`Programa/Programa.html`, v1.117.0):

- **Selector de marca** (Todas / Loekemeyer / Chef) delante del de artículo; al cambiarlo se
  rearma la lista y se redibuja.
- El combo se agrupa por **familia** con `<optgroup>` y cada opción muestra
  `código — descripción` (más `(discontinuado)` cuando corresponde).
- El encabezado de la pantalla muestra **descripción · familia · marca** en vez de solo la familia.
- `programa_bundle` devuelve ahora `d` (descripción), `mk` (marca) y `disc` en cada `art`
  (migración `programa_bundle_art_con_descripcion_y_marca`) — cambio aditivo, ninguna pantalla que
  ya lo usaba se rompe.

### 4aq. Baja REAL de los 3 corta queso: 119, 574 y 809 (2026-09-10)

`[usuario 2026-09-10]`: *"hacé la baja de los cortaquesos"*, sobre los tres que ya estaban
`discontinuado = true` porque hoy se importan (§4ao, sufijo E). Migración
`baja_articulos_corta_queso_119_574_809`. Se borró **el artículo y su cadena productiva propia**,
en este orden (las FK son `NO ACTION`, así que el orden no es decorativo):

| Qué | Filas |
|---|---|
| `ruta_paso` de sus rutas | 66 (22 por artículo) |
| `ruta` | 15 (5 por artículo: el Fleje 80 más 4 de insumo) |
| `articulo_componente` | 15 |
| `articulo` | 3 |

GP2 queda con **120 artículos**, todos con descripción y marca. Invariantes en 0 (`L_rutas_sin_pasos`
y el ledger incluidos). La familia `Cortadores (queso)` quedó sin artículos.

**LOS COMPONENTES NO SE BORRARON**, a propósito: `componente` lo referencian 21 tablas y la baja
pedida era la del artículo. Quedaron **16 huérfanos**, todos con stock 0 y sin un solo movimiento:
`IE3` Fleje N° 80 (Brawin) y sus 6 derivados `IE3-M*`, `IZ19A` Alambre Corta Queso (Alambres Rumbo),
`V20` Tornillo Corta Queso (Importado, ya discontinuo), `A9` Cpo Mango Alambre (ya discontinuo), los
3 cartones `I3B`/`C1B`/`O6A` (Gráficos Pol) y los 3 terminados `119`/`574`/`809`. **Ninguno queda
compartido**: lo único compartido de la receta era `A1` "Caja N°1", que sigue viva en 18 rutas y 9
recetas. Pendiente decidir si se barren o quedan.

### 4aq-bis. LOKE vuelve a ser marca, pero SOLO a nivel artículo (2026-09-10)

`[usuario 2026-09-10]`: *"falta la marca Loke. Pusiste solo loeke y chef no?"* y acto seguido pasó
**la lista exacta**: los 10 artículos LOKE son **101, 103, 104, 108, 114, 115, 116, 120, 121 y 123**
— justo los que **no figuran en ningún listado mayorista**, y ahora se entiende por qué: los
listados traen un solo bloque "Loekemeyer" y la submarca no aparece ahí. Migración
`articulo_marca_loke_submarca`: el check de `articulo.marca` pasa a `LOEKE / LOKE / CHEF` y esos 10
quedan en **LOKE** (antes los había cargado como LOEKE por la descripción dictada, §4ao).

Reparto final de los 120 artículos: **LOEKE 66 · CHEF 44 · LOKE 10**.

**Ojo con la contradicción, que sigue viva del lado de los cartones.** El 2026-09-08 el usuario
había dicho lo contrario para `componente`: *"la marca loke no va. todo lo que esta en loke ponelo
en marca loeke y dentro del formato loke"* (§4g), y los 8 cartones que tenían `marca='LOKE'` pasaron
a `marca='LOEKE'` conservando `carton_formato='LOKE'`. **Eso NO se revirtió**: hoy LOKE es marca de
**artículo** y no de **componente**. Antes de tocar los cartones hay que preguntarle, porque de eso
depende cómo se agrupan los pedidos en la OC (la familia de pedido es formato + marca + categoría).

- **`Programa/Programa.html` v1.118.0**: el filtro de marca tiene las tres (Todas / Loeke / Loke /
  Chef). Los rótulos son **"Loeke"** y **"Loke"** por pedido textual del usuario
  (*"en vez de loekemeyer que sea loeke"*) — **se parecen muchísimo a un ojo apurado**; si alguna
  vez confunde, la salida es rotular "Loeke (principal)" / "Loke (submarca)", no cambiar el dato.

### 4ar. Buscador de artículo en "¿Qué necesito para producir?" (2026-09-10)

`[usuario 2026-09-10]`: *"que me aparezca para buscar"*. Con 120 artículos el combo agrupado por
familia ya era largo para encontrar uno a mano. `Programa/Programa.html` v1.119.0:

- Campo **Buscar** entre Marca y Artículo. Filtra por **código, descripción o familia**, sin acentos
  ni mayúsculas (`norm()` con `NFD` + borrado de diacríticos: "sacacorcho" encuentra "Sacacorcho",
  "pelapapas" encuentra "Pelapapas Mango Metálico").
- **Se combina con el filtro de marca**, no lo pisa; si la combinación no deja nada, el combo dice
  *"(ningún artículo con ese filtro)"* y la pantalla **no se redibuja** en vez de romperse buscando
  un artículo que no está.
- Si el artículo que estaba elegido sigue en la lista filtrada, queda elegido; si no, pasa al primero
  y se redibuja.
- Ancho propio (`#buscar`, 210px con tope de 70vw) porque la regla general de la barra deja los
  inputs en 110px, que es el ancho de "Unidades". Los 18px de la regla de accesibilidad se respetan.

Lo cubre `tests/ui/test_programa_marca.js` (búsqueda por descripción, por código, sin acentos, y
combinada con la marca).

### 4as. Palos de amasar 231, 232 y 233: Tierra Nativa → Garage → Fábrica (2026-09-10)

`[usuario 2026-09-10]`: *"voy a crear el articulo 231, 232 y 233. son los tres palos de amasar…
en recepcion de insumos garage me entrega tierra nativa esos 3 palos… y despues se manda al
tallerista fábrica"*. Es el **mismo patrón del 234** (§4ag), calcado de su ruta 763. Migración
`alta_palos_amasar_231_232_233_tierra_nativa_fabrica`.

| Artículo | Descripción | Componente Garage | Ruta |
|---|---|---|---|
| 231 | Palo de Amasar 30cm | `GRJ22` | 801 |
| 232 | Palo de Amasar 40cm | `GRJ23` | 802 |
| 233 | Palo de Amasar 50cm | `GRJ24` | 803 |

Cada ruta son 3 pasos: **insumo** (el palo entra al Sector Garage) → **tallerista Fábrica** (id 3,
envasa y saca el terminado) → **virgilio**. Receta: 1 palo por artículo. Los tres componentes de
garage tienen proveedor **Tierra Nativa SA** y `estado_compra` NULL (se compran), inventario 0 en
Sector Garage; los terminados, inventario 0 en Virgilio. Artículos: familia **Madera**, marca
**LOEKE**, 24 por bulto (UxB del catálogo). Verificado: los tres salen en `recepcion_bundle` bajo
Sector Garage / Tierra Nativa SA con la descripción del artículo terminado, como pidió el usuario.
Invariantes en 0.

**`GRJ21` NO se pudo usar: ya era `Bowls 330ml`** (proveedor Cimarrón, `discontinuo`) y **está vivo
en la receta y en 2 pasos de ruta del artículo 071**, que es un artículo activo. Por eso la serie
arranca en **GRJ22**. Si el usuario quiere igual 21/22/23, es un `update componente set codigo=…`
de tres filas (el código no es FK de nada) más resolver qué pasa con el Bowl. **Ojo que esto
contradice en parte §4ag**, donde el palo del 234 se llamó `PALO234` justamente para no usar GRJ
("los GRJ del sector son bombillas"): hoy el sector Garage ya tiene GRJ de ñoqueras, cepillos y
palos, así que la regla vieja no aplica más.

**Lo que falta (nada inventado):**
1. **Precio del palo** en los tres — sin él costean $0. En la planilla del vecino sólo existe el
   234 (`L888`, $600); para el 30/40/50 no hay fila de referencia.
2. **La caja**: quedaron con `articulos_por_caja = 24` (del catálogo) pero **sin `componente_caja_id`**.
   El 234 usa `A9B` "Caja N°15" con 12 por caja; con 24 por bulto no se puede asumir la misma.
3. **No tienen demanda**: `est_madre` no trae 231/232/233 (sí el 234, 396 uni/mes), así que no
   generan consumo ni máximo de insumo hasta que la Est Madre los traiga.
4. La **tarifa de envasado de Fábrica no se carga**, por la regla del usuario del 2026-09-09.
5. Los tres siguen además en `articulo_prov_at` como artículos terminados de Tierra Nativa — igual
   que el 234; las dos vías conviven.

### 4at. Stock de material plástico: vive en VIRGILIO, va a los INYECTORES, y hay que conectarlo a Gestión Productiva (2026-09-10)

Salió de analizar el Excel del usuario `Conteo_y_Pedido_Sector_Plastico_31-8` (no está en el repo).
Es la memoria del **circuito de materia prima plástica**, que hoy **GP2 no gestiona** y hay que
incorporar.

**El circuito (cómo funciona) `[usuario 2026-09-10]`:**
- La **materia prima plástica** viene en **bolsas de 25 kg** (PP 2630, ABS, Alto Impacto,
  Nylon Virgen, Nylon Recuperado, Nylon c/Carga, PE, PS h555, + aditivos **Master Bach** de color).
- Ese stock **se guarda en VIRGILIO** y **se gestiona desde "gestión Virgilio"** (no desde
  Cervantes). **El Master Bach también debería mandarse ahí** (hoy figura aparte).
- Desde Virgilio, las bolsas **se le mandan a los INYECTORES**. El inyector **inyecta piezas
  plásticas** (mangos, cachas, bujes, pirolos, insertos, etc.) y **las va entregando**.
- **Objetivo del usuario (lo que hay que construir):** cuando el inyector **entrega** piezas, el
  sistema tiene que **"gastar" automáticamente el material** que consumió al inyectar (kg de cada
  material) y con eso **disparar la reposición**. Cada inyector debe mantener un **stock fijo de X
  días** de material plástico.

**Implicancia para Gestión Productiva:** hoy el motor de costos/inventario cuenta la pieza plástica
como comprada al inyector, pero **no descuenta la materia prima** (el kg de PP/ABS/etc.).

**Estado real en GP2 (2026-09-10, dos agentes read-only sobre el repo):**
- **La materia prima cruda NO existe en GP2**: ni como `componente`, ni en `inventario`, ni con
  ubicación. El rubro "Plásticos" (sector 6) que sí existe son las **partes YA inyectadas que
  compramos** (PA10B, PC16…) a Pat Bet Plast / Pettofrezza / Kollplast, recibidas en unidades. Idea
  **7243**: las bolsas viven hoy en el programa viejo (`public."Movimientos_Stock"`, "gestión
  Virgilio" = app vieja), que GP2 no mira.
- **"Virgilio" en GP2 hoy es otra cosa**: `ubicacion` singleton tipo `virgilio` (id 33), la
  distribución de producto terminado. Y hay una decisión vieja registrada
  (`REGLAS_OC_INSUMOS.md:240`, 2026-08-29): *"Virgilio: no interesa analizar su entrada/salida,
  existe solo para medir talleristas"* — **choca de frente con este pedido** y hay que actualizarla.
- **Master Bach: cero presencia** en repo y BD.
- **La maquinaria de "objetivo de stock" ya está**: `ubicacion.meses_stock` / `meses_minimo` +
  motor `maximo = consumo_mes × meses_stock − stock` (`db/funciones_GP2.sql`). Pero trabaja en
  **meses** (no días), calcula desde Est Madre de terminados, y **no tiene tope por capacidad
  física** (los 20 pallets × 15 bolsas).
- **El molde de "una entrega gasta materia prima" YA existe** y es el camino:
  `cargar_recepcion_eclipse` (suma el producto y descuenta chapa 430 por ratio desde la ubicación
  del PS) y `crear_entrega_tallerista(p_descontar_bom=true)` (descuenta el BOM desde la ubicación
  del tercero). El motor es `GP2.movimiento` → triggers `fn_movimiento_calc`/`fn_movimiento_aplicar`
  → `GP2.inventario` (stock por componente+ubicación).

**Gaps para construirlo (sin implementar aún):** (1) alta de las ~10 bolsas como `componente` (kg) +
`inventario` en Virgilio; (2) ubicación/stock **por inyector** (hoy `ubicacion.tipo` no tiene
"inyector"); (3) vínculo **pieza inyectada → material (kg x uni)** — no existe (el "gramos por
pieza" vive en el Excel del vecino, no en GP2); (4) RPC `crear_entrega_inyector` calcada de
`cargar_recepcion_eclipse`; (5) regla **stock-fijo-X-días** = `inventario.minimo` del material en el
inyector = consumo_diario × X, con envío Virgilio→inyector al tocar el mínimo.

**Layout físico de Virgilio `[usuario 2026-09-10]`:** **20 pallets**, cada pallet **15 bolsas**, cada
bolsa **25 kg** → **300 bolsas / 7.500 kg** de tope. Un material no se achica por debajo de su
pallet asignado: sólo se saca lo que no entra en los pallets que tiene.

**Consumo mensual por material `[dato: hoja "Relev y OP Bolsas Plast 31-8"]`:**
PP 2630 ~1.071 · Al/Alto Impacto ~273 · ABS ~112 · Ny Recup ~107 · PS h555 ~71 · Ny c/Carga ~56 ·
PE ~17 · Nylon Virgen ~6. Master Bach chico (Rojo ~12, Blanco ~11, Azul ~6, Negro ~3). El **PP es
lejos el más usado**; lo que más PP consume son los **Mango 505** y el **Mango Pelador 586**.

**Trampas del Excel del usuario (para no arrastrarlas a GP2):**
- **El "Mango 505" está DUPLICADO** `[dato]`: dos partes ("P/Calar" y "Calados") con el **mismo Cod
  Art 505 y la misma Est Madre (30.000 u)** → suma **162 kg/mes de más** al PP. El PP real es
  ~**909 kg/mes**, no 1.071. En GP2 el 505 es **una sola pieza**.
- **La hoja `Consumo x Parte` está incompleta/desalineada** `[dato]`: la columna de kg sólo está
  calculada para el bloque CH; en las partes LK queda en 0 → **no usarla para totales**. Fuente
  buena: `Consumo x Cod Articulo` / `Relev y OP Bolsas Plast`.
- **Nylon Virgen (PA6N)** es sólo para los **bujes de los abrelatas mariposa** (arts 502/66/512)
  `[dato]` — ~6 kg/mes, nylon de mejor calidad porque el buje va a rosca/giro.
- **EBA está DISCONTINUO** `[usuario 2026-09-10]` → sale entero de Virgilio, no ocupa pallet.
- **13 artículos consumen parte plástica pero NO figuran en el catálogo por familia** de su empresa
  `[dato]`: LK 333/334/336/339 (Inox), 389 Espumadera Nylon, 548 Pincel, 655 Bombilla Eco;
  CH 452/453/454/455 (Nylon c/Mango), 864 Pincel, 879 Set X3 Espátulas. Patrón: **Inox, Nylon
  c/Mango, Pincel, Bombilla**.

*(El detalle numérico y las tablas de pallets quedaron en `.xlsx` que se le pasaron al usuario en el
chat — regla de la casa: el detalle va al archivo, la memoria guarda la lógica.)*

### 4at-bis. CONSTRUIDO: la materia prima plástica entra nativa a GP2 (2026-09-10)

**Decisiones del usuario (mismo día):** *(1)* el material se compra a **3 proveedores** — Indarnyl,
Santa Rosa Plásticos y Beta Plásticos (Master Bach: Arcolor y Julio Garcia) `[dato: hoja "Lista de
Precios" del Excel, filas 271/283/296: "202 - Indarnyl", "3527 - Beta Plasticos", "837 - Santa Rosa
Plasticos". El snapshot 1 había guardado el bloque 837 con el TELÉFONO como nombre (la fila del
encabezado tiene el nombre en la columna K y el cargador tomó la fila siguiente); corregido en
planilla_fila el 2026-09-10]`. **Ojo con la columna "Se Compró Última Vez" de esa hoja**: a Santa Rosa
**no figura ninguna compra**; PP/ABS/PS/PE/Ny c-Carga/Ny Rec se compraron a Indarnyl y Beta (mismas
fechas en los dos bloques: PP 2026-05-05, ABS 2026-05-05, PS 2026-03-18…), y **Nylon Virgen dice
"NO" — nunca se compró**. El workbook del usuario igual asigna PE/PS/AI/Nylons a Santa Rosa: queda
como lo dice el usuario, pero es una contradicción a resolver;
*(2)* los gramos por pieza salen del workbook `Conteo_y_Pedido_Sector_Plastico` (col «Kg x Parte»);
*(3)* **el inyector no tiene X días fijos: tiene que tener lo que necesite para su OC** `[usuario,
textual: "Lo que necesite para su oc"]`; *(4)* **desperdicio 4 %** (el de la planilla del vecino);
*(5)* **códigos = Cod ISIS del vecino** (2405 PP, 2455 ABS, 2465 AI, 2475/2505/2485 Nylons, 2435 PE,
2425 PS, 0235/0255/0265/2595 Master Bach).

**Cómo quedó (migración `materia_prima_plastica_virgilio_inyectores`):**
- **Sector 14 «Materia Prima Plástica»** (es_insumo, kg), ubicación propia «en Virgilio», `meses_stock`
  2,5. Los 12 materiales con **stock inicial = conteo del usuario del 2026-09-10** (PP 123 bolsas, AI
  68, ABS 14, Ny c/Carga 1, Ny Rec 18, Ny Virgen 23, PE 10, PS 8 — 6.625 kg) y **máximo = 2,5 meses en
  bolsas enteras** (origen `fisico`). Master Bach en 0 (sin conteo). EBA afuera (discontinuo).
- **Los inyectores siguen siendo `proveedor_insumo`** (no se los convirtió en PS híbrido: ese patrón
  admite UNA materia prima por PS y los invariantes G/H lo asumen; un inyector usa PP, ABS, PE…).
  Ganan **ubicación tipo `inyector`** (`ref_id = proveedor_insumo.id`, columna nueva): Pat Bet
  Plast, Pettofrezza Rafael, Kollplast, JL Matriceria.
- **`componente.material_id`** en 54 piezas inyectadas (PP 24, ABS 9, Ny Rec 8, PE 6, PS 3, Ny Virgen
  2, Ny c/Carga 1, AI 1) y `kg_x_uni` completado sólo donde estaba null. **Sin material a propósito**:
  PEP5/PEP8 (mango de madera), PEP7 (palo blanco), PA3 (Santoprene, discontinuo), PC12/PC16 (el
  workbook no los trae → pendiente del usuario).
- **Descuento automático**: `crear_recepcion_insumo` (por donde pasa toda recepción de la pantalla) —
  si la pieza tiene material y el proveedor tiene ubicación de inyector, descuenta
  `uni × kg_x_uni × 1,04` de ESA ubicación (`consumo_inyector`). Probado con rollback: 1.000 Mango 505
  de Pettofrezza → 5,616 kg de PP. `anular_recepcion` lo revierte (y también la chapa de Eclipse,
  mismo patrón, que antes quedaba colgada).
- **Reposición por OC**: `v_material_inyector` = Σ OC abiertas al inyector (pendiente × kg_x_uni ×
  1,04) − stock en el inyector → kg y **bolsas a enviar**; `enviar_material_inyector` registra el
  envío Virgilio → inyector. Panel «Material» en `Compras/Inyectores_GP2.html`.
- Pantallas: Recepción gana el rubro «Mat. Plástica» (kg); Stock por sector gana `?sector=14`;
  Stocks General / composición rotulan los dos tipos nuevos.

**Pendientes que dejó (no se inventa nada):** **conteo de Master Bach**; material de **PC16
«Inserto Chef»** (`[usuario 2026-09-10]` "te lo consigo" — material y gramos). ~~Código 1135 del
Alto Impacto~~ → **1135 es código VIEJO; el vigente es 2465 (el de Santa Rosa y Beta)** `[usuario
2026-09-10, textual: "1135 es cod viejo / 2465 es de santa rosa y beta"]` — GP2 ya usa 2465.
**PC12 «Mgo Sacafuente Articulado» NO es plástico inyectado: es de MADERA, lo hace Máspoli**
`[usuario 2026-09-10: "PC12 es de Maspoli" / "Maspoli es madera, no inyectado"]` — igual que
PEP7/PEP8 (los otros mangos de Máspoli). Queda sin `material_id` a propósito; los tres están en
Sector Plástico por herencia del vecino, no porque sean inyectados. ~~Precio de PE / Nylon Virgen /
Nylon Rec~~ → resuelto con la regla de abajo.

### 4at-ter. Cada material se le compra AL MÁS BARATO, y la OC lo refleja (2026-09-10)

`[usuario 2026-09-10, textual: "al que sea más barato por material. la OC tiene que considerar
eso"]` — cierra la contradicción workbook (Santa Rosa) vs planilla (compras a Indarnyl/Beta): **no
hay proveedor fijo por material, hay uno por precio.**

- Se cargaron en `precio_proveedor` los precios de los **tres** (Indarnyl 202, Beta 3527, Santa Rosa
  837) por material, de la hoja «Lista de Precios» (filas 271-305). Fuera a propósito por ser otro
  grado: Santa Rosa «PE PEBD 26500» (1115) y «ABS GP 35» (2445), Beta «PP COPO» (2415). Indarnyl
  «AI Nacional» (0355) entra como Alto Impacto: **es el competidor del 2465** `[usuario 2026-09-10,
  textual: "Es el competidor"]` (0355 cotiza en USD 2,84; el 2465 en USD 3,54 en Beta y en pesos 4.040
  en Santa Rosa — Indarnyl y Santa Rosa quedan a ~8 % y se pueden dar vuelta con el dólar).
- **`v_material_precio_proveedor`**: precio por kg de cada proveedor **llevado a pesos al dólar
  oficial del día** (`parametro tipo_cambio_usd_pesos`, el mismo que usa la OC) y rankeado. Se
  compara así y no por el «IPC al día» de la planilla: la OC ya convierte USD con ese parámetro,
  y la regla tiene que ser la misma que ve el usuario en la pantalla.
- **`recalcular_proveedor_material()`** asigna `componente.proveedor` = orden 1 (sólo sector 14).
  Corre solo: trigger `trg_material_mejor_proveedor` (statement, al insertar/cambiar/borrar un
  precio) y **desde `actualizar_dolar_oficial`** (el cron del dólar) — porque un precio en pesos
  contra uno en dólares **se dan vuelta con el tipo de cambio** (Indarnyl PP 3.249 ARS vs Beta
  2,70 USD). Si el recálculo falla, el dólar igual se actualiza.
- **`oc_bundle` y `crear_oc` cotizan con el precio del proveedor ASIGNADO** (join por `cod_prov`);
  antes tomaban «el de fecha más nueva», que con varios proveedores podía ser el de otro.
- Resultado al 2026-09-10 (dólar 1.535): **Santa Rosa → PP (3.065 $/kg), PS (3.725), Alto Impacto
  (4.040); Beta → PE (2,70 USD); Indarnyl → ABS (2,90 USD), Nylon Virgen (3,45), Nylon c/Carga
  (3,10), Nylon Recuperado (3,35)**. Master Bach sin competencia.
- Las funciones nuevas quedaron **sin EXECUTE para anon** (nacen públicas por default de Postgres;
  el invariante C lo detectó). Lección: **toda función nueva interna lleva su `revoke` en la misma
  migración.**

### 4au. La OC de materia prima: un solo proveedor, 5 días, el formato del usuario, y Virgilio la recibe (2026-09-11)

`[usuario 2026-09-11, dictado]`:
- **La OC de un material va a UNO solo: el más barato.** *"No es que le voy a pedir a los tres el
  mismo material proporcionalmente."* Con `componente.proveedor` = el más barato (4at-ter) y la OC
  armada por proveedor, ya sale así; no hay reparto.
- **Los tres siempre tienen stock y entregan rápido, ~5 días desde que se genera la OC** →
  `proveedor_insumo.dias_entrega = 5` para Indarnyl, Beta y Santa Rosa (la OC propone la fecha).
- **Formato**: la OC tiene que salir **como las hojas «O.C.» del workbook** y **emitirse sola al
  generar el pedido**. Lo que dice esa hoja `[dato: hojas O.C. Indarnyl / Beta del workbook]`:
  membrete doble (**Loekemeyer Hnos. S.R.L**, CUIT 30-51584245-0, Cervantes 2868, Villa Devoto /
  **Chef SRL**, CUIT 30-68575625-7, Virgilio 2788, Villa Real), RAZÓN SOCIAL + COD PROV,
  **ENTREGA EN: Virgilio 2788** (el material vive ahí), **«FACTURAR Loekemeyer 85% Chef 15%»**,
  «ESTE PEDIDO ANULA CUALQUIER PEDIDO ANTERIOR», y **cada material en DOS renglones**: LK (Cod ISIS,
  «KG a FC» = 85 %) y CH (**otro Cod ISIS, el de Chef** — `componente.codigo_isis_ch`: PP 0675, ABS
  1085, PS 0635, AI 0625, Ny c/Carga 0815; PE, Nylons virgen/rec y Master Bach no tienen — 15 %),
  con Fecha Pos Ent y tres pares Fecha Ent / Kg Ent en blanco para anotar las entregas parciales.
  Construido: `hojaOCMaterial()` en `Compras/OC_GP2.html` v1.22.0, se abre sola al crear una OC
  cuyos items son todos del sector 14; el % vive en `parametro.oc_facturar_pct_loeke`.
- **Gestión Virgilio es OTRO repo** (`loekemeyer/Gestion-Virgilio`) y **tiene que recibir esa OC**
  «como hoy reciben las OC de los talleristas», para que desde ahí carguen lo que están por recibir.
  **En Virgilio también guardan cajas y cajones de Sector Crudo y Sector Procesado** cuando no
  entran en Cervantes: es **otro depósito** cuyo stock GP2 tiene que considerar.

**Lo que dio el mapeo de `Gestion-Virgilio` (agente read-only, 2026-09-11)** `[dato: repo]`:
- **Es el MISMO proyecto Supabase** (`hrxfctzncixxqmpfhskv`), schema `public`; GP2 es el schema
  `GP2` de la misma base. Virgilio puede llamar RPC de GP2 con `supabase.schema("GP2").rpc(...)`
  — **no hace falta puente, espejo ni FDW**. El repo de Virgilio incluso lleva una copia de GP2 en
  `cervantes-admin/gp2/`.
- **Cómo reciben hoy** (`recepcion.js`): el operario elige entidad (tallerista / prov AT), carga
  código y cajas, y confirma → inserta en `"Entregas Tallerista Virgilio"` (que GP2 ya espeja) o
  `"Entregas Prov AT"`, `rpc gv_oc_aplicar_recepcion` descuenta la OC más nueva de
  `public."Ordenes_Compra"` (por línea; el operario no tilda la OC, carga lo que llegó),
  `Movimientos_Stock` (`deposito='a_guardar'`) y `Control_Modo_OP` (foto → Pendientes del
  supervisor). **No existe el tipo "proveedor de insumos"**.
- **Virgilio ya tiene un catálogo `Insumos` con las bolsas de plástico** (`PP` AF7, `AI` AF14, `NR`
  AF20, `NV` AF5, `EBA` Q34, `ABS` AF3, `PS` AF13, `PE` AF10, `N25` AF11 — es lo que mostraba la
  foto del usuario) con su propio ledger `Movimientos_Stock deposito='insumos'`. **Riesgo de
  doble registro** contra `GP2.inventario` sector 14: hay que decidir quién manda (recomendado:
  GP2, y retirar/marcar esos 9 códigos en Virgilio).
- **Las cajas/cajones de Crudo/Procesado guardados en Virgilio NO existen en ningún sistema**
  (Virgilio sólo modela cajas de terminado). Lo más simple es modelarlo en GP2 (los componentes,
  `uni_x_cajon` y el motor ya están): ubicación «en Virgilio» + `tipo_mov traslado` + RPC que
  Virgilio llame por `schema("GP2")`.
- Propuesta para que reciban la OC de materia prima: **2 RPC en GP2** (`oc_pendientes_virgilio()`
  = OC enviadas del sector 14 con sus renglones; `recibir_oc_virgilio(oc, items, remito, legajo)`
  → llama a `crear_recepcion_insumo`, que ya cruza la OC y la marca recibida) + en `recepcion.js`
  una tercera entidad «📦 Materia Prima (GP2)». Sin escribir tablas GP2 a mano desde Virgilio.

### 4av. Cruce consumo de material: GP2 vs la planilla del usuario (2026-09-11)

`[usuario 2026-09-11, dictado]` *"Hay que contrastar el stock de insumos contra el consumo. Si el
consumo no te da igual al mío, algo falta (el despiece de algún artículo) — o la Est Madre que
considera el programa de flejes es distinta de la tuya."* Se cruzó a tres niveles (archivo
`Cruce_Consumo_Plastico_GP2_vs_Workbook.xlsx` entregado en el chat):

- **Bug propio encontrado y corregido: doble conteo por rutas.** Las piezas que el inyector entrega
  "sin serigrafía / sin calar" (PC2, PC3B, PA4B, PA5B, PA13B, PA18B, PC15AB) y sus variantes
  terminadas adentro (PC1A, PC1B, PA4, PA5, PA13, PA18, PC15A) tenían **las dos** `material_id`, y
  `v_consumo_componente` explota el consumo por las rutas a las dos → PP +183 kg, ABS +60 kg de
  más. **Regla: `material_id` va SÓLO en la pieza que se inyecta (la que se le compra al
  inyector); la variante `fabricacion` que sale de ella NO lleva material.** Quitado a las 7.
- **Resultado por material (kg/mes neto, GP2 vs planilla sin el 505 duplicado)**: PP 722 vs 868 ·
  AI 408 vs 262 · ABS 79 vs 108 · Ny Rec 72 vs 103 · PS 65 vs 68 · Ny c/Carga 49 vs 54 · PE 16 vs
  17 · Ny Virgen 6 vs 6. **Cierran PS, Ny c/Carga, PE y Ny Virgen.**
- **La causa principal es la Est Madre**: de 107 artículos con consumo plástico, **81 tienen una Est
  Madre distinta (>15 %) entre la planilla 31-8 y `GP2.est_madre`** (= `public.proyeccion_madre`,
  la que mantiene Virgilio). Ej.: 504 Afila 3.498 vs 7.826 (por eso AI da 408 en GP2), 513 18.204
  vs 14.252, 280 5.200 vs 1.566, 587 3.600 vs 2.294, 789 1.056 vs 9, 809 1.296 vs 16 (dado de
  baja). **La planilla de plásticos usa otra foto de la Est Madre que la que ve GP2.** Hay que
  decidir cuál manda; GP2 sigue a `proyeccion_madre`.
- **Despiece que falta en GP2** `[dato]`: el **cilindro plástico del Corta Queso** (546/809, AI ~64
  kg/mes en la planilla) no existe como pieza: vive adentro de `C13 «Corta Queso Bastidor
  c/Cilindro»` (Sector Procesado) → hay que darle de alta la pieza inyectada y ponerla en la
  receta/ruta. **570 Pala de Canelones** no tiene pieza plástica en su receta (la planilla le pone
  el mango PP). El **123** también está duplicado en la planilla (Calados / P/Calar), como el 505.
- **Consumo que la planilla tiene y GP2 no puede tener**: artículos que no son de GP2 (395, 396,
  312, 715, 58, 59, la línea inox 333-338, los importados 94xE, 725) ≈ 45 kg/mes de PP.
- **Nota de método**: la planilla lista muchas piezas por ARTÍCULO (mango integrado: «(art 546)
  Corta Queso»), no por pieza; el mango genérico PC10 de GP2 (199 kg) es la suma de 546 + 587 +
  559 + 542 + 543 + 515 + 562 + 116 en la planilla (209 kg) — cierra.

### 4aw. Decisiones "por escrito" sobre el circuito de material plástico (2026-09-11)

`[usuario 2026-09-11]` Respuestas a la lista de pendientes que salió del cruce (4av) y del
mapeo de Gestión Virgilio (4au). Lo que se decidió y lo que se hizo con cada una:

- **1. Est Madre: manda `proyeccion_madre`** (la que mantiene Virgilio). La planilla de plásticos
  31-8 usa otra foto y no se le corre atrás: GP2 sigue a `GP2.est_madre`.
- **3. Cilindro plástico del Corta Queso: discontinuo.** No se da de alta la pieza (los 3 corta
  queso ya están de baja, 4aq).
- **4. 570 Pala de Canelones lleva mango + capuchón** → HECHO: receta +`PC10` ×1 +`PA18` ×1 y dos
  rutas calcadas de las del 587 pero con el tallerista **Fábrica** (el que arma el 570):
  «Insumo PC10 → Art 570» (insumo → Fábrica → 570 → Virgilio) e «Insumo PA18 → Art 570» (PA18B →
  PS Hernandez Julio PA18B→PA18 → Fábrica → 570 → Virgilio). Con eso el PP del 570 entra al
  consumo de material.
- **5. PC16 «Inserto Chef»**: material y gramos los consigue el usuario (sigue pendiente).
- **6. Master Bach se stockea en Cervantes por ahora** → HECHO: `proveedor_insumo.entrega_en =
  'Cervantes 2868'` para Arcolor y Julio Garcia; la hoja de OC dice ENTREGA EN Cervantes y esas
  OC no aparecen en `oc_pendientes_virgilio()`. El stock sigue en el sector 14 (una sola ubicación
  para todo el material) — si algún día importa dónde está cada bolsa, se abre otra ubicación.
- **7. Material sin código de Chef → sin renglón CH** («si no lo usa») → HECHO: Nylon Virgen,
  Nylon Recuperado, PE y Master Bach van 100 % LK en la hoja.
- **9. Las bolsas siguen viviendo también en el catálogo `Insumos` de Virgilio** («más adelante se
  va a unificar todo»). El ledger que manda es GP2; el doble registro se tolera hasta la
  unificación.
- **10. Cajas/cajones de Crudo/Procesado en Virgilio: sí se modela** → HECHO: ubicación tipo
  `virgilio_sector` (ref = sector 1 / 2), tipo_mov `traslado`, RPC `traslado_virgilio(comp,
  cantidad, 'ida'|'vuelta')`, columna «En Virgilio» en Stock SC / Stock SP.
- **11. Virgilio recibe la OC de material** → HECHO del lado GP2: `oc_pendientes_virgilio()` +
  `recibir_oc_virgilio(oc, items, remito, legajo)` (probado con rollback: cruza la OC y la marca
  recibida). Del lado de Virgilio falta la entidad «Materia Prima (GP2)» en `recepcion.js`: spec
  en `INTEGRACION_GESTION_VIRGILIO.md`, se hace en una sesión sobre ese repo.
- **E. Flujo del material**: «se recibe por OC, se manda a inyectores desde el módulo Envío de
  insumos; deberíamos modelar eso más específico cuando se elige envío de insumos». **El módulo es
  de Gestión Virgilio** [usuario: "fijate que hay un módulo de entrega y envío de insumos que impacta
  en el stock de los insumos"] `[dato: agente sobre el repo gestion-virgilio, index.html]`: botón
  **INS** de la botonera → «Recibir insumos» (RI) / «Entregar insumos» (EI) / «Salida a Cervantes»;
  RI y EI escriben `public.Movimientos_Stock deposito='insumos'` (`recepcion_insumo` +delta /
  `entrega_insumo` −delta), con **destino/origen en texto libre** («Cervantes, Centro, Proveedor
  X»), bolsas plásticas en unidad fija «Bolsas» y códigos propios (PP, ABS, AI, NV, NR, N25, PE, PS;
  EBA discontinuo). Hoy **no toca GP2**. Lo que hay que modelar «más específico»: en EI, si el
  insumo es una bolsa, el destino es **un inyector** (lista cerrada) y el envío impacta GP2; en RI,
  la bolsa se recibe **contra la OC** de GP2. HECHO del lado GP2 (2026-09-11):
  `componente.codigo_virgilio` en las 8 bolsas (PP→2405, ABS→2455, AI→2465, NV→2475, NR→2505,
  N25→2485, PE→2435, PS→2425; Master Bach sin código en Virgilio), `material_virgilio_bundle()`
  (bolsas en Virgilio + inyectores + cuántas bolsas le faltan a cada uno), `enviar_material_virgilio(
  cod_virgilio, bolsas, inyector, legajo)` y `recibir_oc_virgilio` / `oc_pendientes_virgilio` que
  aceptan `{cod_virgilio, bolsas}`. Spec para el repo de Virgilio en `INTEGRACION_GESTION_VIRGILIO.md`.
  El ledger de Virgilio sigue escribiéndose igual (decisión 9): GP2 manda, Virgilio espeja.
  **HECHO también del lado de Virgilio** (`gestion-virgilio` v14.95, 2026-09-11, pusheado a su main):
  en EI los inyectores aparecen como botones con "le faltan N bolsas" y al confirmar se llama
  `enviar_material_virgilio`; en RI aparecen las OC pendientes con las bolsas precargadas y al
  confirmar `recibir_oc_virgilio`. GP2 va primero; si rechaza, el operario decide si registra sólo en
  Virgilio. Tarea Planify 3050 (Tomás Beviglia, "Th", regla del repo de Virgilio).

### 4ax. Máximos del material plástico: regla viva sobre el consumo GP2 (2026-09-11)

`[usuario 2026-09-11]` Al revisar los máximos de plásticos se le presentaron dos decisiones (dar de
alta los artículos del Excel que GP2 no tiene, o recalcular los máximos con el consumo GP2) y dijo
**"Elegí uno y vamos"** → se eligió la segunda, porque es coherente con la decisión 1 (Est Madre =
`proyeccion_madre`) y no exige inventar despieces.

- **Regla**: `inventario.maximo` del sector 14 = ceil(2,5 meses × consumo GP2 kg/mes con 4 % de
  desperdicio ÷ 25) × 25 (`recalcular_maximo_material()`, interna, corre a diario desde
  `actualizar_dolar_oficial` junto con el proveedor más barato). Master Bach no tiene consumo en GP2 y
  conserva el máximo a mano. La capacidad de Virgilio (20 pallets × 15 bolsas) se informa en la salida
  (`total_bolsas`, `pallets`), no se recorta.
- **Resultado del primer cálculo** `[dato]`: PP 76 bolsas (antes 91), AI 43 (antes 28 — GP2 consume
  424 kg/mes por la Est Madre del 504), ABS 9 (12), NR 8 (11), PS 7 (8), N25 6 (6), PE 2 (2), NV 1
  (1). Total ~152 bolsas ≈ 11 pallets de 20.
- **Lo que queda corto y por qué** `[dato]`: **34 artículos del Excel no tienen despiece plástico en
  GP2** (~115 kg/mes en el Excel, de los cuales ~70 son PP/ABS de artículos vivos: 395 Descorazonador
  10,9 · 715 Cierra Bolsa 5,1 · 312 Pala Torta inox 3,8 · 396 Enrulador 3,3 · línea inox LK 333–338
  21 · importados 94xE 16 · Chef inox 630–636 4,6 · 856/857/858/863/864/709/311 <1,5 c/u). El resto
  no cuenta: 809 dado de baja (22), palo blanco 725/909/719 (madera, no es material nuestro). Mientras
  no se den de alta, el máximo de PP queda ~18 % corto; cuando se agreguen, la regla lo sube sola.
  Archivo `Articulos_Excel_sin_despiece_GP2.xlsx` (chat 2026-09-11). **Pendiente del usuario**: si
  esos artículos se dan de alta en GP2 (con qué mango/inserto) o quedan afuera.

### 4ay. Los artículos del Excel sin despiece: qué se decidió de cada uno (2026-09-11)

`[usuario 2026-09-11]` "Veamos los artículos que te faltan definir el despiece y los vamos resolviendo."
El vecino tiene el despiece de TODOS (`public."Despiece x Articulo"` + `"Partes x Tallerista"`):
Carlos = tallerista 9 Carlos Aguirre, Martin = 6 Martin Cornejo, "Log/Fabr" = 3 Fábrica. Las piezas
plásticas ya existen en GP2; lo que falta son los artículos, sus cartones y alguna parte inox.

- **333–338 (línea inox LK) → DISCONTINUOS** `[usuario]`. No se dan de alta. Explican 21 kg/mes de
  la diferencia PP/ABS con el Excel: no hace falta reponerlos.
- **396 Enrulador de manteca → DISCONTINUO** `[usuario]`.
- **395 Descorazonador de Manzana → ALTA (hecha)** `[usuario: "lleva la parte que entrega Eclipse más
  mango y capuchón"]`: receta `1686` (descorazonador que corta Eclipse desde la chapa 430, sector
  Procesado) + `PC10` mango LK espátula + `PA18` capuchón; lo arma **Carlos Aguirre** `[dato: vecino]`;
  rutas «Chapa 430 → Art 395» (ingreso CHAPA430 → PS Eclipse CHAPA430→1686 → Carlos → 395 → Virgilio),
  «Insumo PC10 → Art 395», «Insumo PA18 → Art 395» (PA18B → Hernandez → PA18 → Carlos). Familia
  Utensilios `[deducido]`, marca LOEKE, 12 por caja (`est_madre.uxb`), terminado `395` con stock 0 en
  Virgilio. **Caja N°2 (A8)** `[usuario: "Caja 2"]`. **Cartón `CCG1C` «Cartón 395»** (sector Cartón,
  Talleres Gráficos Pol, LOEKE, ruta «Insumo CCG1C → Art 395»): nace con el código del vecino porque
  la posición de estantería no se sabe `[usuario: "no sé ubic de estantería"]` — cuando se sepa se
  recodifica (el código no es FK); formato del cartón pendiente. Falta la tarifa de Carlos por el
  armado. Con esto el 1686 (que estaba huérfano: existía sin ninguna ruta) ya tiene quién lo consuma.
- **311 Cuchillo de Torta LK → ALTA (hecha)** `[usuario: "es correcto"]`: receta `PA17` mango LK cuchillo/pala
  torta + `PA13` capuchón batidor + `PA18` capuchón espátula + `Z21` cuchillo inox (19,3 g, nuevo en Sector
  Procesado como pieza comprada, igual que la Z23B del 587) + cartón `CCG1A` «Cartón 311» (código del vecino
  hasta saber la posición); lo arma **Martin Cornejo** `[dato: vecino]`; 5 rutas calcadas de las del 535
  (PA13 y PA18 pasan por Hernandez: B → pintado). Familia Repostería `[deducido]`, LOEKE, 12 por caja.
  **Z21 se compra pero no se sabe a quién** `[usuario]` → tarea Planify **3058 para Alan Gonzalez** ("¿a
  quién se compra?"); mientras, `componente.proveedor` null. **Caja N°12 (A2)** `[usuario: "caja 12
  ambos"]`. Pendientes: formato del cartón, tarifa de Martin.
- **312 Pala de Torta LK → ALTA (hecha)** `[usuario: "ok 312"]`: misma estructura que el 311 con `Z20`
  «Pala Torta» inox (39 g, nueva en Procesado, comprada, proveedor pendiente) y cartón `CCG1B`; Martin;
  caja N°12. **OJO**: GP2 ya tenía una `Z22 «Pala de Torta»` de Melinox (37,3 g, sector 7) — puede ser
  la misma pieza; si el usuario lo confirma, se unifica (recodificar Z20 → Z22 y sacar la duplicada).
- **858 Pala de Canelones CH y 863 Corta Pizza Chef → COMPLETADOS (hecho)** `[usuario: "dale"]`: ya
  existían pero sin la parte plástica del mango Chef. Se les sumó, según el vecino, `PA19` mango Chef +
  `PC6` ojales + `PC7` inserto canelones (858, arma Fábrica) y `PA19` + `PB6` inserto espátula + `PC6`
  (863, arma Martin), con su ruta cada uno. Consumo GP2 del mango Chef PA19: 1.108 uni/mes.
- **Chef inox 630–636, 709, 856, 857, 864 → NO se dan de alta** `[dato: proyeccion_madre 0–3 uni/mes
  cada uno]`: el Excel los mostraba con 12–72/mes pero hoy no se venden; su aporte al plástico es nulo.
  Si vuelven a moverse, el despiece del vecino está listo (PA19 + PB6 + PC6 + cartón CCQ5; el vecino
  les suma además PB3/PB4 «Cuchara Ny», que parece un error suyo).
- **058 Cierra Bolsa x2 → ALTA (hecha)** `[usuario: "058 (con 0 adelante), se compone solo de 2 partes
  plásticas + cartón + caja" / "caja 22"]`: `PC4` «Cierra Bolsas Blanc.» **×2** (JL Matricería, 6,7 g) +
  cartón + **Caja N°22 (A9)**, 12 por caja; lo arma **Fábrica**. **El código lleva el 0 adelante** (`058`,
  como 031/043/052…): los artículos de 2 dígitos de GP2 se escriben con 3. El cartón no tiene código en
  el vecino y GP2 los codifica por posición de estantería → nace como `CART058` hasta saberla.
- **059 Cuchillito de Untar Plast x2 → ALTA (hecha)** `[usuario: "059 lo mismo, 2 x cartón. caja 22"]`:
  igual al 058 pero con `PEP9` «Cuchillo de Untar Blanc.» ×2 (JL Matricería, 7,3 g) + cartón `CART059` +
  Caja N°22, 12 por caja, Fábrica. Familia «Cuchillos de untar».
- **715 Cierra Bolsa x4 → ALTA (hecha)** `[usuario: "1 x4"]`: `PC4` **×4** + cartón + Caja N°22, Fábrica.
  **El vecino le pone ×2, igual que al 058: es un error suyo** — GP2 usa ×4.
- **PEST1 + los 7 importados 94xE → ALTA (hecha)** `[usuario: "creala, pero cuando llegue la nueva impo
  de 94xE, ya queda discontinuo"]`: `PEST1` «Insertos Mango de Madera» (6,6 g, **PP**, sector Plástico,
  proveedor pendiente) y los artículos **941E, 942E, 943E, 944E, 945E, 946E, 948E** (familia Madera, 12
  por caja, sin cartón: vienen importados y sólo se les pone el inserto en Fábrica). Consumo del inserto:
  684 uni/mes. **⚠ TRANSITORIO**: cuando llegue la **nueva importación de 94xE** el inserto **queda
  discontinuo** → marcar `PEST1.estado_compra = 'discontinuo'` y sacarlo de las 7 recetas; el PP baja
  ~4,7 kg/mes.
- **Las dos piezas inox del 311/312 son de MELINOX** `[dato 2026-09-11: planilla de costos, hoja «Lista
  de Precios», bloque «2593 - Adolfo A Gonzalez (Melinox)»]` `[usuario: "Z20 fijate en costos"]`:
  «Cuchillo para Torta» cod ISIS **1996**, $890 (última compra 2023-09-06) y «Pala de Torta» cod ISIS
  **2006**, $1.250 (última compra 2026-05-13). **Las dos están marcadas «NO COMPRAR +» en la planilla**
  — hay que preguntar por qué antes de generarles una OC. Consecuencias aplicadas: el `Z20` que se había
  creado para el 312 **era un duplicado** del `Z22 «Pala de Torta»` que GP2 ya tenía (id 618, Sector
  Bombilla, prov Melinox, 37,3 g, precio 1.100 del 2026-09-04) → el 312 usa el 618 y el Z20 se borró; el
  `Z21` se mudó al **Sector Bombilla** (donde viven las piezas de Melinox) con su proveedor y su precio.
  `proveedor_insumo.Melinox.cod_prov = 2593`. **Lección**: antes de crear una pieza comprada, buscarla en
  la planilla de costos por descripción — el código del vecino (Z20) no siempre es el de GP2 (Z22).
- **311 → DISCONTINUO** `[usuario 2026-09-11: "311 discontinuo"]`, apenas después de darlo de alta, al ver
  la venta real: **2 cajas en 4 meses** (jul y ago 2026, ~6 uni/mes) contra una proyección madre de 34, y
  la pieza inox sin comprarse desde **09-2023**. Se marcó `articulo.discontinuado = true` (eso solo ya lo
  saca de `v_consumo_demanda`, y con eso de la OC y del máximo) y `estado_compra='discontinuo'` en sus dos
  piezas exclusivas (`Z21` y el cartón `CCG1A`). **La receta y las rutas se dejan**: son la historia del
  artículo y el trazado tiene que seguir explicando el stock que quede. El **312 sí sigue vivo**: 61 cajas
  en 4 meses (jun 2 · jul 23 · ago 32 · sep 4), última compra de la pala a Melinox en mayo 2026.
- **Las tarifas de armado también estaban en la planilla** `[usuario 2026-09-11: "la tarifa de 395 y 312
  está en costos"]`: hoja «Lista de Precios», el bloque es **el tallerista que cobra** —
  «Descorazonador Manzana AyE» (395-709) **$39,25** en el bloque *4175 - Alex Escalante*, y «Pala de
  Torta AyE» (312-856) **$55,60** en *3805 - Martin Cornejo*. Cargadas en `precio_tallerista`
  (terminado + concepto AyE, como las otras 105). **⚠ Contradicción a resolver en el 395**: la tarifa
  está en el bloque de **Alex Escalante** pero el despiece del vecino dice que lo arma **Carlos
  Aguirre** (que es lo que quedó en la ruta); se cargó a nombre de Carlos con la nota en la referencia
  — si manda Alex, se mueven la ruta y la tarifa juntas.
- **Dónde mirar la venta real** `[dato]`: `public.vista_venta_mensual` (cod, mes, cajas, nps) — hoy tiene
  desde **jun-2026**. Sirve para contrastar la proyección madre antes de decidir un alta o una baja.
- **Cerrado el repaso de los 34**: el consumo de PP en GP2 quedó en **786 kg/mes** (era 722 antes de
  estas altas; el Excel decía 868 con otra Est Madre). Lo que queda afuera a propósito: 333–338 y 396
  (discontinuos), 809 (de baja), 725/909/719 (palo blanco, no es material nuestro) y la línea Chef inox
  630–636/709/856/857/864 (no se vende).

### 4az. BUG DE COSTO: los insumos se contaban dos veces (2026-09-11)

`[usuario 2026-09-11, sobre el art 312: "está mal $2435 material"]` — eran **$1.217,48 exactos ×2**.

- **Causa**: `v_costo_componente` junta el material de dos lados que se pisaban. `mat` camina las
  **aristas** (`ruta_paso` de tipo matriz / proveedor_servicio / tallerista) y suma cada ancestro
  comprado; `insumox` sumaba **además** todos los `ruta_paso` de tipo `'insumo'` por su cantidad. Una
  ruta típica «Insumo X → Art N» tiene el paso `insumo` (X→X, que no es arista) **y** el paso
  `tallerista` (X→N, que sí lo es): el mismo X entraba por los dos lados.
- **Arreglo** (en la vista, que es donde está la causa): `insumox` cuenta sólo los insumos que **no son
  entrada de ninguna arista** — la misma guarda que ya tenía `bomx`. Así sigue cubriendo su caso real
  (rutas sin actor, donde el insumo no entra a la caminata) sin duplicar el resto.
- **Impacto**: cambiaron **126 de 713** componentes, todos para abajo (el total de la vista pasó de
  622.355 a 576.542). Ejemplos contra la planilla del usuario (`costo_sin_aporte`): 312 2.529 → **1.311**
  (planilla 1.649, le faltan cartón y caja), 546 3.047 → **1.701** (planilla 1.466), 523 3.858 →
  **1.545** (planilla 2.414), 501 2.270 → **2.035** (planilla 2.005), 505 671 → **515** (planilla 334).
  Antes GP2 costeaba **por encima** de la planilla casi siempre; ahora queda en el mismo orden.
- **Lección**: cuando un costo GP2 da muy por encima del de la planilla, sospechar del doble conteo
  entre la caminata de rutas y las sumas por receta/insumo, no de los precios.
- **REGRESIÓN del mismo día, ya arreglada** (idea 7297): la guarda saca el insumo de `insumox` porque
  «`mat` ya lo cuenta», pero `mat` lo cuenta **una vez** y **no mira `ruta_paso.cantidad`**, mientras
  `insumox` sí la miraba. Un insumo con `cantidad = 2` pasó de cobrarse 3 veces a cobrarse **1**. Eran
  8 pasos con cantidad > 1, 4 con precio: **BOM13 ×2 y BOM14 ×2 en los artículos 550 y 760**, −$51,25
  cada uno. Arreglo: `insumox` no los excluye, les suma **lo que falta, `(cantidad − 1)`** (con
  cantidad = 1 suma 0), y el contador `sin_precio` sí mantiene la guarda para no avisar dos veces por
  el mismo precio faltante. Verificado contra foto previa: cambian **exactamente 550 y 760** y ninguno
  de los otros 713. `[deducido]` La lección de fondo: **`mat` e `insumox` no son intercambiables** —
  uno cuenta por arista y el otro por cantidad; mover un insumo de uno al otro cambia la aritmética.

### 4az-bis. Auditoría del motor de costos: lo que se verificó y lo que quedó abierto (2026-09-11)

Barrido del motor después del fix de 4az. **Lo que se comprobó con consulta, no con sospecha:**

- **El 580 contra la planilla: GP2 $1.194,70 vs $432,39** (`costo_sin_aporte − cod_y_precinto`). El
  hueco **no es la tarifa** (ya se arregló, ver 4bb) **ni el precio del fleje**: es el **peso**.
- **`GRJ10` (Batidor Pera) y `GRJ10A` (Batidor Pera Mini) tenían el MISMO `kg_x_uni`: 0,098 kg**.
  **RESUELTO** `[usuario 2026-09-11, textual: "98 gms la grande, 16.5 la chica"]`: la **grande estaba
  bien** (0,098) y la **chica tenía el peso de la grande** → `GRJ10A = 0,0165 kg`, que es exactamente el
  que sale de la fórmula del cromado de Pedernera en la planilla (`$2.796,25/kg × 16,5 g × 1,125`). El
  `GRJ_PESOS` del vecino (GRJ10 = 68,88 g) **no valía**. Con eso el **580 baja de $1.194,70 a $532,96**
  y el `GRJ10A` de $975,39 a $313,66. Idea 7295 cerrada.
  **Lo que todavía sobra** (idea 7296, abierta): la planilla dice **6,85 g de alambre** y GP2 cobra
  **2 × 16,5 = 33 g**, porque cada fleje sigue pagando el peso del armado entero. Contra los $432,39 de
  la planilla quedan ~$100 de diferencia, la mayor parte por ahí.
- **Cómo ese peso se multiplica**: en `v_costo_componente`, `mat` costea un fleje como
  `precio × kg_ref`, y `kg_ref` es el `kg_x_uni` de **la salida de la arista**. Con una matriz en el
  medio la salida es la pieza cortada y la cuenta cierra; **cuando el fleje entra directo al armado, la
  salida es el armado entero y cada fleje paga el peso total del producto**. En el batidor son 2 flejes
  × 98 g = **196 g de alambre** contra los 30,66 g que suman IE4 (14,63) e IE5 (16,03) y los **6,85 g**
  de la planilla. Pasa en **exactamente 2 nodos de todo GP2**: GRJ10 y GRJ10A. Idea 7296.
  **Ojo con el arreglo obvio**: usar el `kg_x_uni` del propio fleje **no sirve en general** —
  `CHAPA430` lo tiene en **1** (convención de precio por kg) y ahí la regla actual es la correcta.
- **Lo que NO estaba mal, chequeado** (vale tanto como lo otro): el **resorte EP10 sí está** en la
  cadena del 580 (ruta «Insumo EP10 → Art 580 (Alex Escalante)», $115, que es el `material_pesos` del
  GRJ10A); el **precio del fleje no está inflado**; el **cartón y la caja** coinciden con la planilla;
  y las **dos tarifas** del 580 suman $68,65, idéntico al total de la hoja Talleristas.
- **La guarda nueva de `insumox` no dejó material sin cobrar**: la consulta de insumos que la guarda
  excluye y que en **su** ruta no entran por ninguna arista con actor devuelve **0 filas** `[dato]`.
- **`bomx` se quedó con la guarda angosta** (`e.ent = hijo AND e.sal = padre`): hoy **1 sola fila**
  (`C12` ← `BOM10`) y **sin precio**, o sea sin plata en juego todavía. Idea 7298.
- **El semáforo de tiempos mentía y ya está arreglado** (idea 7301): `faltan_tiempos` contaba sólo el
  `NULL` y hay **19 matrices con `tiempo_historico = 0`** `[dato]`. **Un cero no es un tiempo**: son
  cortes y estampados reales en balancín o alimentador, ninguno tarda 0 segundos. **55 componentes**
  decían «0 sin tiempo» con la mano de obra en $0 y nadie se enteraba; ahora avisan (los avisos pasan de
  2 a 98) **sin que se mueva un peso**. Los ceros **no se tocaron en `matriz`**: `registrar_evento_prod`
  los usa para el premio del operario, así que lo que cambia es el aviso, no el dato. Medirlas es la 7302.
- **Regla de trabajo que quedó de esto** `[deducido]`: antes de tocar la vista de costos, **foto de los
  713 en una tabla auxiliar**, aplicar, y exigir que el diff diga *«cambian exactamente estos N y
  ninguno más»* — incluido `faltan_precios`, que es donde se coló el error intermedio de esta misma
  sesión (el semáforo empezó a contar dos veces el mismo precio faltante). Después **borrar la tabla
  auxiliar**: mientras existe, el invariante D da > 0.

### 4ba. Lo que faltaba usar del Excel de plásticos (2026-09-11)

Auditoría de las 41 hojas del `Conteo_y_Pedido_Sector_Plastico_31826.xls`: además del consumo y el conteo
(que ya usamos), el archivo tenía **un motor de pedido entero**. Lo que el usuario decidió de cada regla:

- **1. Master Bach = 2 % del plástico → POR FÓRMULA (hecho)** `[usuario: "calculalo x fórmula"]`. En el
  Excel cada fila calcula `Pedido MB KG = 2 % del Pedido Plast KG`, con el color (R/B/N/A/V) por pieza.
  **GP2 no sabe todavía qué color lleva cada pieza**, así que el 2 % se aplica al total de plástico (es un
  máximo: errar para arriba es lo correcto) y se reparte entre los 4 colores con la proporción ya cargada.
  Da exactamente lo que estaba a mano (Blanco 2 · Negro 1 · Rojo 2 · Azul 1 bolsas): la fórmula confirmó
  los números. **Pendiente**: el color por pieza; cuando esté, el 2 % se calcula por pieza.
- **2. Pedido mínimo del proveedor → CONSIDERADO (hecho)** `[usuario: "consideralo"]`:
  `proveedor_insumo.pedido_minimo_kg` = **Indarnyl 400 kg**, Beta 25, Santa Rosa 25, masterbatch 5 (hoja
  «Relev y OP Bolsas Plast», columna `Pedi Minimo KG`). La pantalla de OC suma los kg por proveedor y no
  deja crear la orden si no llega; **no se infla sola**. Ojo con Indarnyl: sus 4 materiales juntos llegan a
  600 kg de máximo, pero uno solo nunca llega a 400 → sus OC van a salir combinadas.
- **3. Meses de stock**: el Excel usa 4 meses para Pat Bet Plast / Maspoli / Barbetta y 3 para Pettofrezza
  / Telleria. `[usuario: "usamos 2,5 para bolsas plásticas. Para inyectores tenemos que mirar cuánto entra
  físicamente"]` → **las bolsas siguen en 2,5 meses**; el tope por inyector se va a medir en el lugar
  (tarea Planify **3076**, Alan).
- **4. Bolsas por pallet: 15** `[usuario]` — el 18 del Excel (celda M1 de «Relev y OP Bolsas») **no vale**.
- **5. Simko** (quinto proveedor de resina del Excel, mínimo 25 kg): `[usuario: "no sé quién es"]` → **no
  se da de alta**.
- **2-bis. Pedido mínimo POR PIEZA → CARGADO (hecho, 2026-09-11)**. La otra mitad del mínimo: el inyector
  no hace una tirada de menos de N piezas (`Pedi Min Uni` de la hoja «Pedido 31-08», 1 a 36.000 según el
  molde). Vive en `componente.pedido_minimo_uni`, **47 componentes** cargados (45 del sector Plástico + 2
  del Garage), y viaja en `oc_bundle.insumos[].pedido_minimo_uni`.
  **A diferencia del piso en kg del proveedor de resina, éste NO bloquea la OC**: hoy **24 de los 47**
  sugeridos quedan por debajo del piso — el Pirolo Blanco sugiere 2.248 y el mínimo del molde es 36.000,
  que son **64 meses de consumo**; el Pirolo Negro 4.132 vs 36.000; el PC3B 6.704 vs 36.000. Bloquear
  dejaría la OC imposible de crear. Es un **aviso amarillo aparte** (`#avisoMinUni`) con botón «Subir al
  mínimo» para las líneas que el comprador decida llevar al piso. `[deducido]` La lectura de fondo: o el
  máximo (4 meses) es muy corto para estas piezas, o el mínimo del molde obliga a comprar para años —
  **es una decisión de compra, no de la pantalla**, y por eso se muestra en vez de resolverse sola.
  **Cómo se mapearon los códigos**: 40 por código exacto + `PEST1`; y 7 renombres confirmados por
  descripción + proveedor + `uni_x_cajon` idénticos (`PC2A`→`PC2`, `PC2B`→`PC3B`, `PC15`→`PC15AB`,
  `PEP4A`/`PEP4B`/`CP5`→`PEP4` —GP2 no separa el color—, `PB7`→`PB8B`, `PGRJ12`/`PGRJ12B`→`GRJ12`/`GRJ12B`).
  **No se carga sobre lo que no se compra**: `oc_bundle` filtra `estado_compra is null`, así que los
  `fabricacion` (`PC1A`, `PC1B`, `PA10`, `PA13`, `PA18`, `PA4`…) quedan afuera — el mínimo es del que
  inyecta, y a esos los hacemos o los cala Ester.
  **Los códigos del Excel que GP2 no reconocía — RESUELTOS el 2026-09-11** `[usuario]`. Sirve de mapa
  para la próxima vez que aparezca un código raro del Excel de plásticos:

  | Excel | Qué resultó ser |
  |---|---|
  | `PA15` Capuchón ⌀10 | **Discontinuo** — regla del usuario: *"si en Excel consumo = 0, discontinuo"*, y su consumo es 0 |
  | `PA16` Mangos ⌀10 LK | **Discontinuo** — ídem, consumo 0 |
  | `PB1` Cilindro Corta Queso | **Discontinuo** `[usuario]` (ojo: su consumo en el Excel es 8.496, o sea el dato del Excel está vivo y la pieza no) |
  | `PEP6` Cabo Madera 525 | **Discontinuo** `[usuario]` |
  | `PB7` Inser. Neg. Batidor | **ACTIVO** `[usuario: "Pb7 activo, mañana lo vemos"]` — está cargado sobre `PB8B` («Inser. Neg. Batidor Calado», mismo proveedor y mismas 500 por bolsa) por equivalencia de descripción; **el mapeo queda a confirmar** |
  | `PB8` Mango Sacacorcho (581) | **= `PB8A`** de GP2 («Mgo Sacac Plast») `[usuario: "Pb8 es igual a Pb8a"]` — mínimo 5.000 cargado |
  | `IP4` Clavo 513 | **El 513 usa el clavo 505** `[usuario]`. GP2 **ya lo tenía bien**: la ruta «Insumo D9 → Art 513» va `PCP3` (Clavo 505) → niquelado → `D9` → 513. No hay pieza nueva |
  | `CP7` Mangos Corta Queso | **Pendiente** — Planify 3092 (Nazareno) |
  | `HP2` Inser. Neg. Cuch. y Pala | **Pendiente** — Planify 3092 (Nazareno) |

  **Por qué `CP7` y `HP2` no se pudieron cerrar con la regla del consumo** `[dato]`: sus celdas de consumo
  **no traen un número, traen `#REF!`** (código de error 23 de xlrd — la fórmula está rota; son dos de las
  71 celdas con error de la hoja «Pedido 31-08»). Cuidado al leer esa hoja con un script: **una celda de
  error devuelve un entero chico que parece un consumo bajo**. Acá `#REF!` se leía como «23».
  **Regla que quedó** `[usuario 2026-09-11]`: **si en el Excel el consumo es 0, la pieza está discontinua.**
- **Lo que quedó sin usar, a propósito**: corrida mínima de inyección (`Min Iny`), bocas por matriz, y los
  `cod_prov` de los inyectores
  (Pat Bet 797, Pettofrezza 1895, Kollplast 4465, JL Matricería 2661, Maspoli 2339…). Están en el archivo
  `Excel_Plastico_lo_que_falta_usar.md` que se le pasó al usuario.
- **El Excel está roto en partes** `[dato]`: 71 celdas con error en `Pedido 31-08` (bloque de
  discontinuos), 21 de 45 líneas pedidas por debajo de su propio mínimo, las O.C. emitidas no coinciden con
  lo calculado (una columna manual `Pedido Damian` pisa la fórmula: PP calculaba 1.510 kg y se pidieron
  500), y hay dos juegos de consumo distintos dentro del mismo archivo (PP 1.071 con el mango 505
  duplicado vs 868 sin él).

### 4bb. Los DOS Carlos: "Carlos" (= Carlos E, factura como Alex) y Carlos Aguirre (2026-09-11)

`[usuario 2026-09-11, textual]`: *"Carlos Aguirre no es «Carlos». Carlos puede ser Carlos E, que factura
como Alex. Carlos Aguirre es el que factura lo que entrega en Virgilio de la mercadería que le damos a
Pedernera"*. **Son dos contrapartes distintas y es una trampa fácil de pisar** (la pisó esta sesión al dar
de alta el 395):

- **«Carlos» en el despiece del vecino = Carlos E**, y **factura como `Alex Escalante` (tallerista 2)**.
  Por eso la planilla de costos tiene sus tarifas en el bloque **«4175 - Alex Escalante»** aunque el
  despiece diga Carlos. En el vecino, «Carlos» tiene 39 artículos (248, 307, 332-338, 395, 509, 510, 515,
  052, 534, 535, 547, 580, 613, 615, 630-637, 709, 710, 818, 908, A10, A15, C10, GRJ7/9/10, V9).
- **`Carlos Aguirre` (tallerista 9) es otro**: es quien **factura lo que se entrega en Virgilio de la
  mercadería que le damos a Pedernera** (el PS 6 «Pedernera Ilario», cromado). Por eso comparte con
  Pedernera la **ubicación 18** (`tallerista.ubicacion_stock_id = 18`) — eso no era un parche, es el
  modelo correcto. Sus trabajos en GP2 son envasados: 115, 544, 560, 800, 802.
- **Regla para el futuro**: si el despiece del vecino dice «Carlos», en GP2 va **Alex Escalante**. Carlos
  Aguirre sólo aparece en lo que viene de Pedernera.
- **Corregido**: el 395 se había dado de alta con Carlos Aguirre por leer «Carlos» en el despiece; sus 4
  rutas y la tarifa de $39,25 pasaron a **Alex Escalante**, que es de quien es la tarifa en la planilla.
- **Dos cosas quedan sospechadas, a confirmar con el usuario**:
  1. El alias **`CARLOS` → tallerista 9** (`contraparte_alias`): si «Carlos» es Carlos E, ese alias
     debería apuntar a Alex Escalante. Hay que ver con qué nombre llegan las entregas desde Virgilio
     (no existe alias «ALEX» ni «ESCALANTE»).
  2. ~~El 580 tiene tarifas gemelas~~ **RESUELTO abajo**.

**El 580 es el ejemplo perfecto de la cadena, y la ruta de GP2 ya estaba bien** `[usuario 2026-09-11:
"580 -> Carlos Escalante lo entrega en garage (crudo), se le manda a Pedernera (croma) y Carlos Aguirre
envasa y entrega en Virgilio"]`:

    Fleje/matriz → **Alex Escalante** arma el crudo `GRJ10A` (lo entrega en el Garage)
                 → **PS Pedernera Ilario** lo croma
                 → **Carlos Aguirre** lo envasa → `580` → Virgilio

- Lo que estaba mal era **la tarifa**: la fila de Carlos Aguirre tenía el **ARMADO** («Mini Batidor Pera
  ARMADO (entrega en Garage)», $51,807), que es el trabajo de Alex y **ya estaba cargado en el GRJ10A** →
  el costo del 580 sumaba el armado dos veces. Corregida a **«Mini Batidor Pera Envasado» $16,842**
  (planilla f618). El 580 bajó de $1.229,66 a $1.194,70.
- Viene de una lectura vieja: `[sesión 2026-09-02: "Carlos hace armado y entrega en garaje"]` se cargó a
  **Carlos Aguirre** cuando ese «Carlos» era Carlos E (= Alex). **Misma trampa, ahora documentada.**
- **Contradicción abierta**: la línea del envasado del 580 está en el bloque **«4175 - Alex Escalante»** de
  la planilla, no en el de **«4306 - Carlos Aguirre»** (que existe, con 544 Batidor Pera Envasado $15,
  560/561 Pinza Envasado $42 y los pulidos). O el 580 lo envasa Alex, o la planilla tiene la línea en el
  bloque equivocado. **A confirmar** — el usuario dijo que **Carlos Aguirre envasa el 580**, así que en
  GP2 la tarifa queda a su nombre; lo que no cierra es el importe, que sale de la línea de Alex.
- **Aparte**: el `GRJ10A` cuesta **$975** en GP2 y el 580 entero **$438** en la planilla — el costo del
  crudo está inflado por otro lado (fleje o matriz), no por esta tarifa. **RESUELTO el 2026-09-11**: es
  el **peso**, ver §4az-bis (GRJ10 y GRJ10A tienen los dos 98 g y el fleje directo paga el armado entero).

### 4bb-bis. Los batidores de Alex van de a pares: ARMADO + ENVASADO (2026-09-11)

`[dato, de la planilla, bloque «4175 - Alex Escalante»]` — **la forma de leer el bloque**, que evita
repetir el error del 580. Los tres batidores están cargados **de a dos líneas**, con el **armado bajo un
código interno** y el **envasado bajo el código del artículo**:

| | armado (cod interno) | envasado (cod art) |
|---|---|---|
| Batidor Pera | f615 · `4516` · **$64,2075** | f616 · `544-802` · **$16,842** |
| Mini (580) | f617 · `4316` · **$51,807** | f618 · `580` · **$16,842** |
| Resorte (515) | f619 · `3946` · **$62,7375** | f620 · `515` · **$56,007** |

- **En GP2 el armado va sobre la PIEZA INTERMEDIA y el envasado sobre el terminado.** Los tres están
  así desde el 2026-09-11: `GRJ10` ← f615, `GRJ10A` ← f617 y `C12` ← **f619** `[usuario: "ok"]`. Antes
  `C12` llevaba la **f621, que es el artículo 509** (que ni siquiera existe en GP2) — el mapeo se había
  confirmado el 2026-09-02 y resultó ser de otra línea. El 515 sube $6,73 (de $999,59 a $1.006,32) y su
  bloque de tallerista queda en los **$118,74** de la planilla. Idea 7299 cerrada.
- **Un importe repetido no significa duplicado** `[deducido]`: los dos envasados de batidor pera valen
  $16,842 porque es el mismo trabajo en dos productos. Lo que delata un error es el **concepto**, no el
  número — el 580 se detectó porque decía *"ARMADO"* en la fila de quien envasa.
- **Carlos Aguirre TAMBIÉN tiene un envasado de Batidor Pera** (f926, cod 544, **$15**, *"Formato 8"*) y
  **no es el mismo que el de Alex** (f616, $16,842): son dos formatos de envasado distintos del mismo
  producto. Por eso conviven; no sobra ninguno.

### 4bc. Los listados mayoristas son la FUENTE de descripción, marca y uni x caja (2026-09-11)

`[usuario 2026-09-11]`: *"toda la inf que te falte de descripcion, marca o uni x caja sacala de los
dos listados que te mande por excel"*, y acto seguido *"pone segun el catalogo"* para la familia.
Regla nueva y permanente para `GP2.articulo`: **descripción, marca, uni x caja Y familia** salen de
los listados mayoristas de Loekemeyer y Chef. **Corrige lo que decía esta misma sección unas horas
antes** ("la familia NO"): la familia también sale del catálogo.

El usuario cargó 20 artículos entre el 10 y el 11/09 (`052, 058, 059, 231, 232, 233, 307, 311, 312,
395, 534, 535, 715` y los siete `941E`–`948E`) y borró los 3 corta queso. GP2 tiene **140 artículos,
los 140 con descripción, marca, familia y uni x caja** — cero nulos. Reparto: **LOEKE 84 · CHEF 46 ·
LOKE 10**.

**Migración `articulo_completar_desc_y_marca_desde_listados`** — rellenó lo que estaba vacío:
descripción de los 4 cepillos (052, 307, 534, 535) y marca de esos 4 más los 7 códigos E.

**Migración `articulo_alinear_desc_marca_uxb_con_listados`** — 7 filas tenían un valor cargado
**distinto** del listado y se alinearon:

| Código | Estaba | Quedó |
|---|---|---|
| **715** | "Cierra Bolsa x4" · LOEKE · 12 | **"Cierra Bolsa x2" · CHEF · 24** |
| 942E / 946E | los dos "Cuchara Mango Madera" | "Cuchara Ac. Inox" / "Cuchara Calada Ac. Inox" |
| 941E | "Espatula Lisa Mango Madera" | "Espátula Lisa Ac. Inox" |
| 059 | "Cuchillito De Untar Plast x2" | "Cuchillo de Untar Plástico x2" |
| 311 / 312 | "Cuchillo de Torta" / "Pala de Torta" | "…Ac. Inox" / "…Acero Inox" |

**El 715 es el que cambió de significado**, no sólo de texto: estaba cargado como Loekemeyer y el
listado lo da como **el gemelo Chef del 058** (los dos "Cierra Bolsa x2"). 942E y 946E tenían la
**misma descripción**, un copiar-pegar que el listado desarma.

**Migración `articulo_familia_segun_catalogo_altas_nuevas`** — 12 altas nuevas estaban en una familia
propia y pasaron a la del catálogo: los 4 cepillos (052, 307, 534, 535) de `Cepillos` a
**Accesorios**, los 7 códigos E de `Madera` a **Utensilios** (son de acero inoxidable, no de madera)
y el 395 "Descorazonador De Manzana" de `Utensilios` a **Cortadores**. La familia **`Cepillos`** que
había creado el usuario **queda sin artículos** (la fila sigue en la tabla `familia`, no molesta: el
filtro del ABM se arma con las familias en uso).

Quedan **15 familias** y las únicas 10 filas cuya familia NO sale del catálogo son los artículos
**LOKE** (101, 103, 104, 108, 114, 115, 116, 120, 121, 123), que no figuran en ningún listado.

**Y los importados SÍ entraron a GP2**: los `941E`–`948E` los cargó el usuario el 11/09, un día
después de decir que *"en principio los art importados no los quiero en gp2"* (§4ao). La regla del
sufijo E sigue valiendo para el backlog, pero ya no es absoluta.

### 4bd. Sacafuente Pizzero: la matriz 364 saca la pieza CHICA y la 365 la GRANDE (2026-09-11)

`[usuario]` textual: *"la matriz 364 saca Z6 y la matriz 365 saca Z5, y está invertido ahora"*.
En GP2 las dos rutas del **artículo 518** terminaban en la pieza equivocada:

| Ruta | Fleje | Medida | Matriz de corte | Terminaba en | Quedó en |
|---|---|---|---|---|---|
| 27 | 6 (`IB3`) | 18,5 × 1,9 mm | 364 "Corte Pieza Chica Sacaf Pizz" | Z5 Grande ❌ | **Z6 Chica** |
| 34 | 8 (`IA10`) | 33 × 2 mm | 365 "Corte Pieza Grande Sacaf Pizz" | Z6 Chica ❌ | **Z5 Grande** |

**El chequeo que lo prueba sin depender del nombre**: el fleje 8 mide **33 mm** de ancho y el
fleje 6 **18,5 mm**. El fleje ancho tiene que dar la pieza grande — y daba la chica. La
descripción de las matrices YA era correcta; lo mal cargado era el `comp_salida_id` del paso de
doblado (M368) y el `comp_entrada_id` del remachado (M151). Se invirtieron 4 filas de
`GP2.ruta_paso` (178, 179, 218, 219). **No se tocó** `componente_bom` (Z36 sigue = 1 Z5 + 1 Z6),
ni `inventario`, ni los movimientos ya aplicados; lo que cambia es a qué fleje se le imputa el
consumo y el costo de cada pieza.

**Trampa para la próxima**: una ruta invertida NO la detecta ningún invariante de
`db/verificar.sql` — la cadena cierra igual (cada paso engancha con el anterior). Se detecta sólo
cruzando el **ancho del fleje** contra el tamaño de la pieza que sale.

**Dos datos que quedaron marcados y NO se tocaron:**
1. `fleje_detalle.descripcion_parte` miente en los dos: el fleje 8 dice *"Engranaje Chico Pizzero
   Pza Gde"* y el fleje 6 *"Mgo Plano Marip Perfora 3 en 1"* — ninguno es sacafuente. `[deducido]`
   es texto de arrastre de la planilla, sin confirmar.
2. **Los pesos no cierran**: Z5 0,0587 + Z6 0,0280 = **0,0867 kg**, y Z36 armado pesa **0,1192 kg**
   → faltan **32,50 g** sin explicar (¿el remache? ¿un peso mal cargado?). Pendiente del usuario.

### 4be. Las 9 maderas de Eduardo Pintos, y el molde para todo lo comprado terminado (2026-09-11)

El usuario devolvió el listado de faltantes con **46 filas visibles** (el resto filtrado) y una
columna propia con el destino de cada una: `prov at` (30), `disc` (3), en blanco (12, que son las que
él ya cargó) y una con *"chequear"*. Pedido: *"necesito que modelemos esos articulos que no estan en
el programa"*.

**El molde ya existía y es el de las ñoqueras** (rutas 764-772) y el de los palos de amasar (§4as):
`insumo` (la pieza comprada entra al **Sector Garage**) → `tallerista` **Fábrica** (envasa y saca el
terminado) → `virgilio`. Las ñoqueras suman además una ruta para el **cartón** y otra para la
**caja**; los palos y estas maderas todavía no las tienen.

**Migración `alta_maderas_pintos_208_220_221_225_901_902_911_920_922`**: 9 artículos, 6 componentes
de Garage (`GRJ25`–`GRJ30`), 9 rutas de 3 pasos. Invariantes en 0.

**Una cuchara de cada medida es UN componente, compartido por el gemelo LOEKE y el CHEF**
`[deducido del precedente GRJ12 "Ñoquera Madera", que usan el 229 y el 909]`:

| Componente | Lo usan |
|---|---|
| `GRJ25` Cuchara Madera 25 Cm | 922 |
| `GRJ26` Cuchara Madera 30 Cm | 911 |
| `GRJ27` Cuchara Madera 35 Cm | 225 (LOEKE) + 901 (CHEF) |
| `GRJ28` Cuchara Madera 40 Cm | 220 (LOEKE) + 920 (CHEF) |
| `GRJ29` Cuchara Madera 45 Cm | 221 (LOEKE) + 902 (CHEF) |
| `GRJ30` Cucharita 13cm Azucarera Madera | 208 |

Si los gemelos LOEKE y CHEF fueran cucharas distintas, esto hay que partirlo. **Confirmarlo.**

**Por qué sólo 9 de las 30 `prov at`:** son las que **Pintos provee en exclusiva**. Los otros 21
están frenados por dos cosas concretas:

1. **Seis códigos tienen más de un proveedor AT** y no se sabe quién los hace: `222` y `910` (Bate
   Bife) entre Pintos y Maspoli; `223` y `224` (Cuchara 25 y 30) entre Pintos y Cabral; `246` y `900`
   (Prensa Matambre) entre Maspoli y Cabral. `GRJ25` y `GRJ26` ya existen y los esperan.
2. **`Lopez Jose`, `Carriero`, `The Plast`, `Paternal Goma`, `Maspoli` y `Cabral` NO existen como
   `proveedor_insumo`** — hoy son sólo `proveedor_at`. Sin esa alta no se les puede colgar la pieza
   comprada. Los que sí existen: Eduardo Pintos, Melinox, Pettofrezza Rafael, Tierra Nativa SA.

Los 3 marcados `disc` (852 Pinza De Hielo, 848 Corta Torta Plástica, 338 Espátula Lisa) **no se
modelan**. El `575` Tapón De Vino lleva la nota del usuario *"se que hay una parte para 1/2 items que
damos nosotros"*: los 5 tapones (575, 577, 579, 816, 817) quedan a la espera de esa aclaración.

### 4bf. Prov. Art. Terminado: el circuito YA manda cajas y cartones; lo que falta son los datos (2026-09-11)

Revertido el alta de las 9 maderas de Pintos de §4be `[usuario 2026-09-11: "deshace si hiciste algo"]`
— migración `revertir_alta_maderas_pintos`, mismo día, 0 movimientos, GP2 vuelve a **140 artículos** y
los `GRJ25`–`GRJ30` dejan de existir. **§4be describe algo que ya NO está en la base.**

**Lo que el usuario quiere de los 40 "Solo en Prov Art Terminado"**: que estén en el módulo, que se
les mande su caja y su cartón, y que **el cartón se pueda recepcionar como insumo antes de
mandárselo**.

**Tres de las cuatro cosas ya funcionan, y no hacía falta tocar código** `[dato, verificado]`:
1. **Los 40 ya están** en `articulo_prov_at`, todos con proveedor activo.
2. **`crear_envio_prov_at` ya manda cajas y cartones y NADA más**: rechaza cualquier componente que
   no sea Sector Cartón (10) o Sector Caja (11). El movimiento sale del sector y entra a la ubicación
   del Prov AT.
3. **La recepción como insumo ya los toma**: `recepcion_bundle` arma la lista con los componentes que
   tienen proveedor, sin mirar a quién se le manda después. Un cartón nuevo aparece solo.

**Lo que falta es dato, y es lo que bloquea todo** (detalle: `ProvAT_cajas_y_cartones.xlsx`):

| Hueco | Cuántos |
|---|---|
| Artículos de Prov AT **sin cartón** en GP2 | **40 de 40** |
| Sin caja asignada (`n_caja` null) | 4 — 070, 222, 591, 910 |
| Caja asignada que **no existe** como componente | 2 — 338 pide Caja N°24, 732 pide Caja N°8 |
| Dos proveedores AT que declaran **cajas distintas** | 4 — 223, 224 (12 vs 2), 246 (2 vs 6), 577 (12 vs 22) |

**Faltan tres cajas en `componente`** (Sector 11 tiene 12 y la planilla usa 15): **N°4** (la pide el
280), **N°8** (732) y **N°24** (031, 034, 338, 535, 654). Crearlas necesita su **código de
estantería** (A1, A8, A9B, Z9…), que es convención de la casa y no se inventa.

**`articulo_prov_at.n_caja` es un número suelto, no un FK a `componente`.** Hoy nadie cruza "este
artículo lleva esta caja" con el stock de cajas: la pantalla de Envíos AT lista **las 12 cajas y los
110 cartones enteros**, sin filtrar por proveedor ni por artículo. Ése es el cambio de pantalla que
vale la pena cuando estén los datos.

**Los `disc` salen del backlog** `[usuario: "saca todos los disc de la lista de pendientes… no los
vamos a agregar"]`: 23 de las 36 filas de "no están en ningún lado" están marcadas `disc`, así que el
backlog real de esa hoja baja a **13**.

### 4bg. Los 30 cartones de Prov. Art. Terminado + tres formatos nuevos (2026-09-11)

Salen del **Conteo de Cartones** del usuario (`Conteo_Cartones_VACIO.xlsx`, no está en el repo).
**La columna "Sector" de esa planilla ES el `componente.codigo` de GP2** `[dato, verificado contra 6
cartones ya cargados: 502→D3A, 512→D2B, 510→A2B, 520→E2A, 547→F6B, 280→F1A]`. Es la fuente para los
códigos de cartón; no hay que inventarlos.

**Migración `alta_30_cartones_prov_at`**: 30 cartones nuevos, GP2 pasa de 144 a **174**. Todos de
**Talleres Gráficos Pol**, con inventario 0 y ya visibles en Recepción de Insumos.

**Correcciones del usuario** `[usuario 2026-09-11]`:
- *"corb8 es corbata"* → el formato de la planilla `Corb8` se carga como **Corbata**, NO como el
  formato `8` que ya existía.
- *"cuchara de helado, tipo loke. Bate bife también loke"* → 532 y 732 (cuchara) y 222 y 910 (bate
  bife) van en **LOKE**, pisando lo que decía la planilla (Tipo C / T.Loke/Huevo / #N/A).
- *"redondeá la uni por paquete"* → 998, 999 y 1001 son **1000**.
- *"el formato rallador, agregalo"*.
- *"los codigos que se pisan usa los del pedido"* → donde las dos hojas discrepaban (los 8 CHEF)
  manda la hoja **Pedido**: 824→Q6B, 825→Q6C, 901→Q5D, 902→Q5E, 910→Q5, 911→Q7C, 920→Q7D, 922→Q7E.

**LA TRAMPA: la posición de estantería NO es única — la planilla se la da a DOS artículos.** G2C es
del 208 y del 508; F4A del 562 y del 575; F4B del 564 y del 577; Q5D del 609 y del 901; Q7C del 816
y del 911. En GP2 el código es único por sector, así que el que llegó segundo lleva **sufijo 1**
(como ya hacen `A1B`/`A1B1` y `A1C`/`A1C1`): **`G2C1`** (208), **`F4A1`** (575), **`F4B1`** (577),
**`Q5D1`** (901) y **`Q7C1`** (911). El primero de cada par conserva su código.

**Migración `carton_formato_corbata_rallador_bandita`** — tres formatos que GP2 no tenía:

| Formato | Pliegos múltiplo | Lo usan |
|---|---|---|
| Corbata | 30.000 | 14 cartones |
| Rallador | 24.000 | 2 — F5A (Cartón 321, LK) y P2A (Cartón 840, CHEF) |

**`Bandita` se creó y se borró el mismo día.** La había deducido el agente de la planilla y el
usuario no la había pedido; al verla dijo *"la bandita no la pongas"* y que **los formatos nuevos son
sólo Rallador y Corbata**. El `P2A` (Cartón 840, el rallador de Chef) pasó a **Rallador**, con el
gemelo LK. Migración `sacar_formato_bandita_p2a_va_en_rallador`. **Lección: un formato deducido de una
planilla no se carga sin preguntar** — la tabla `carton_formato` manda en la agrupación de la OC.

`pliegos_multiplo` = "Cant x Pliego" de la planilla × 1000, que es la regla que **ya cumplen los
cuatro formatos viejos** (C 12, Huevo 25, LOKE 16, "8" 30). **`uni_x_bolsa` y `paq_x_bolsa` quedan
NULL**: la planilla no los trae, y sin ellos la OC no sabe armar la bolsa de esos tres formatos.
**`Bandita` la dedujo el agente** — el usuario sólo mencionó el Rallador.

**El "uni x paquete" por formato no tiene dónde guardarse hoy**: la planilla trae 2.500 para los
Corbata/Huevo de LK y 1.000 para los CH, pero GP2 usa un **parámetro global**
(`parametro.carton_uni_x_paquete` = 1.000) y ningún cartón usa `componente.uni_x_cajon`. Si esa
diferencia importa para la OC, hay que darle un lugar.

**Diez artículos de Prov AT no tienen cartón en la planilla**: 070, 246, 326, 591, 618, 619, 761,
823, 852 y 900.

### 4bh. REGLA: la marca del cartón es la del artículo que nombra su descripción (2026-09-11)

`[usuario 2026-09-11, textual]`: *"chequea que los cartones esten bien dividios por marca segun la
descripcion del carton. tiene que coincidir con la marca del respectivo articulo al que hace
referencia la descripcion del carton"*. Es un invariante chequeable: `componente.marca` de un cartón
"Cartón NNN" tiene que ser igual a `articulo.marca` del NNN.

Migración `carton_formato_5_sin_formato_y_marca_715_515`. **Formato de los 5 que estaban sin formato**
`[usuario]`: `CART058`, `CART059`, `CART715` y `CCG1C` (395) van en **C**; `CCG1B` (312) en **Huevo**.
Queda sin formato **sólo `CCG1A`** (Cartón 311), que está `discontinuo`.

**Dos marcas corregidas por la regla nueva:**
- `CART715` "Cartón 715" era LOEKE y el artículo 715 es **CHEF** (§4bc: el 715 es el gemelo Chef del 058).
- `A1C1` "Cartón 515" era CHEF y el artículo 515 es **LOEKE**. Esto **cierra el pendiente de §4an-ter**,
  que lo había marcado `[deducido, SIN confirmar]` el 2026-09-10: estaba mal, y la regla lo confirma.

**LAS 10 QUE QUEDAN SON TODAS DE ARTÍCULOS LOKE Y NO SE TOCARON**, porque la regla nueva choca de
frente con una decisión anterior del mismo usuario:

| | Dice |
|---|---|
| 2026-09-08 (§4g) | *"la marca loke no va. todo lo que esta en loke ponelo en marca loeke y dentro del formato loke"* → los cartones LOKE pasaron a `marca='LOEKE'` |
| 2026-09-11 (§4bc) | los 10 artículos 101, 103, 104, 108, 114, 115, 116, 120, 121 y 123 son **marca LOKE** |
| 2026-09-11 (esta sección) | la marca del cartón tiene que ser la del artículo |

Las tres juntas no pueden valer: si la del cartón sigue al artículo, `H1A`, `H1C`, `H2C`, `H4C`,
`I2A`, `I2B`, `I3C`, `I42`, `K5D` y `A1B1` tienen que volver a **LOKE**, que es justo lo que el
usuario mandó sacar el 08/09. **Preguntado, sin tocar.** Ojo que no es cosmético: la marca entra en
la familia de pedido de la OC (formato + marca + categoría), así que moverla parte o junta pedidos.

**57 cartones nombran un artículo que GP2 todavía no tiene** (`Cartón 026`, `Cartón 220`…): no son
error, son el backlog de artículos sin modelar; la regla no se les puede aplicar hasta que exista el
artículo.

### 4bi. Los gemelos Chef de 311, 312, 395 y 059 — y el código real de sus cartones (2026-09-11)

`[usuario 2026-09-11]`, y **corrige su propia anotación del Excel**, que decía 856 = 311 y 857 = 312:

| Chef | Gemelo LK | Qué cambia | Arma |
|---|---|---|---|
| **856** Pala De Torta | **312** | — | **Martín Cornejo** |
| **857** Cuchillo De Torta | **311** | — | **Martín Cornejo** |
| **709** Descorazonador | **395** | — | **Carlos Aguirre** (el 395 lo arma Alex Escalante) |
| **717** Cuchillo De Untar Acrílico x4 | **059** | — | sin definir |

Dicho textual: *"La parte del metal es la misma, pero el mango y el capuchón se reemplazan en chef por
el mango de chef y el inserto espátula"*. O sea que en la receta Chef se cambian:
- el **mango** (`PA17` "Mangos Cuch y P Torta" en 311/312, `PC10` "Mango LK Espatula" en 395)
- y el **capuchón** (`PA13`/`PA18`, que además pasan por la serigrafía de Hernández Julio)

por **mango de Chef** + **inserto espátula**. `[SIN CONFIRMAR cuáles son]`: los únicos candidatos en la
base son **`PA19` "Mangos Chef"** y **`PC16` "Inserto Chef"** (los dos de Pat Bet Plast), pero
**ninguno se llama "inserto espátula"**, así que no se cargó nada. La parte de metal sí está y se
comparte: `Z21` "Cuchillo Torta CH/LK" (ya venía nombrada CH/LK), `Z22` "Pala de Torta" y el `1686`
que corta Eclipse desde la chapa 430.

**LOS CARTONES DE 311, 312 Y 395 ESTABAN CON UN CÓDIGO INVENTADO.** Se habían cargado como
`CCG1A`/`CCG1B`/`CCG1C`, que no existen en la planilla. El código real es la posición del Conteo:

| Cartón | Era | Es | Formato |
|---|---|---|---|
| Cartón 311 | CCG1A | **F2C** | Huevo |
| Cartón 312 | CCG1B | **F3A** | Huevo |
| Cartón 395 | CCG1C | **G1A** | C |

Renombrar es seguro: `componente.codigo` no es FK de nada, las rutas y recetas apuntan por id.
Migraciones `carton_311_312_395_codigo_real_de_la_planilla` y `carton_311_formato_huevo`. **Con esto
no queda ningún cartón sin formato en toda la base.**

**Los cartones de los gemelos Chef ya están en la planilla**: `O3D` (856) y `O3B` (857), los dos
**Huevo**. El del **709 no tiene posición** (la celda está vacía) aunque sí tipo (**T.Loke**), y el
**717 y el 059 no figuran** — el `CART059` que existe en GP2 también es un código inventado.

### 4bj. Los comprados terminados TAMBIÉN tienen ruta: el paso `proveedor_at` (2026-09-11)

`[usuario 2026-09-11]`: *"el 575 no me aparece. Debería aparecer en la ruta que se le manda el cartón,
si es que tiene, y la caja al proveedor de artículo terminado y entrega en Virgilio"*. Ése es el
modelo, y faltaba la pieza de base: **`ruta_paso` no tenía forma de nombrar a un `proveedor_at`**.

- **`ruta_paso.proveedor_at_id`** (FK a `proveedor_at`) y el check de `tipo_paso` acepta
  **`proveedor_at`**. Migración `ruta_paso_tipo_proveedor_at`. **Riesgo medido antes de tocar**: de
  las 15 funciones que leen `ruta_paso`, ninguna usa `tipo_paso in (...)` ni compara con
  `'tallerista'`; sólo buscan `'ingreso'` o `'virgilio'`, así que un valor nuevo es aditivo.
- **`programa_bundle`** devuelve `pat` en cada paso y el diccionario **`provat`**.
- **`Programa/Programa.html` v1.128.0**: dibuja el nodo **PROV. ART. TERM.** con "entrega terminado".

**23 artículos de Prov AT creados** (`alta_23_articulos_prov_at_con_carton_y_caja`), cada uno con
**dos rutas de 3 pasos**: `insumo` (cartón) → `proveedor_at` → `virgilio`, y lo mismo con la caja.
La caja entra a la receta como **1 / uni por caja**. Ejemplo del 575: `F4A1` → Pettofrezza → Virgilio
y `A9` (Caja N°22) → Pettofrezza → Virgilio.

**Quedaron afuera 17**, por datos que faltan: seis tienen **dos proveedores AT** (222, 223, 224, 246,
577, 910), dos piden una **caja que no existe** (338 → N°24, 732 → N°8), y el resto no tiene cartón.

### 4bj-bis. Los gemelos Chef, construidos (2026-09-11)

`[usuario]`: el mango de Chef es **`PA19`** y el inserto espátula es **`PC16`**, y **el gemelo Chef NO
lleva serigrafía** (no pasa por Hernández Julio, a diferencia del LK). La **caja es la misma que la
del gemelo LK**.

| Artículo | Gemelo | Receta | Arma | Cartón |
|---|---|---|---|---|
| **857** Cuchillo De Torta | 311 | `Z21` + PA19 + PC16 + caja A2 | Martín Cornejo | `O3B` Huevo |
| **856** Pala De Torta | 312 | `Z22` + PA19 + PC16 + caja A2 | Martín Cornejo | `O3D` Huevo |
| **709** Descorazonador | 395 | `1686` + PA19 + PC16 + caja A8 | **Carlos Aguirre** | **falta** |
| **718** Cuchillito De Untar | 059 | `PEP9` (el mismo) + caja A9 | Fábrica `[deducido]` | **falta** |

El **717 NO se modela por ahora** `[usuario]`: queda pendiente junto al **537** (Pela y Pica Ajo) y el
**567** (Corta Palta). La corrección importante: **el gemelo del 059 es el 718, no el 717**.

**TRAMPA QUE MORDIÓ: `Z22` existe DOS VECES** — id 135 "Llavero Pie" (Sector Procesado) e id 618
"Pala de Torta" (Sector Remache). El alta joineó por código y se llevó los dos: la ruta del 856 quedó
con los pasos duplicados. Es el caso que el invariante `I` ya avisa
(*"dentro de un sector el código es único; entre sectores puede repetirse"*). **Al armar una receta o
una ruta por código hay que filtrar también por sector.** Arreglado con `fix_856_z22_duplicado` y
`fix_856_virgilio_duplicado`; invariantes en 0.

GP2 queda con **167 artículos** (94 LOEKE, 63 CHEF, 10 LOKE).

### 4bk. Dos proveedores AT = dos ALTERNATIVAS, no una ambigüedad (2026-09-11)

`[usuario 2026-09-11, textual]`: *"los dos proveedores de at son dos alternativas"*. Lo que yo venía
tratando como un dato sucio es el modelo real: **el mismo artículo se le puede pedir a cualquiera de
los dos**, igual que cuando dos talleristas hacen el mismo paso. La ruta se **duplica por proveedor**,
y **cada alternativa lleva la caja que ESE proveedor declara**.

Ejemplo del **223** (Cuchara Madera 25 Cm), 4 rutas: cartón `M2C` → Cabral, cartón `M2C` → Pintos,
caja `A2` (N°12) → Cabral y caja `A8` (N°2) → Pintos. Cabral y Pintos declaran cajas distintas para
el mismo artículo y **las dos son correctas**.

Otras dos decisiones del mismo mensaje:
- *"732 y 338, ambas caja 7"* → las dos pasan a **Caja N°7** (`A6`). Pedían la N°8 y la N°24, que no
  existen como componente; con esto **`articulo_prov_at.n_caja` ya no apunta a ninguna caja inexistente**.
- *"los 8 van sin cartón"* → los que no tienen cartón en la planilla se modelan **sólo con la caja**.

Migración `alta_14_prov_at_con_alternativas`: **14 artículos** (222, 223, 224, 246, 326, 338, 577,
618, 619, 732, 761, 823, 900, 910). `articulo.componente_caja_id` guarda **la caja del proveedor de
número más bajo**, porque el campo es uno solo; la otra vive en su ruta.

**Quedan 2 imposibles de modelar con lo que hay: `070` (Set Tapers) y `591` (Despolvillador)** — no
tienen cartón NI caja, así que **no hay nada que mandarle al proveedor** y la ruta quedaría vacía.

### 4bl. 735 Sacacorcho Cabo Ergonómico: calcado del 581 (2026-09-11)

`[usuario 2026-09-11]`: *"el 735 sí lo arma Martín y es igual al Loeke"*. Migración
`alta_735_gemelo_chef_del_581`, **5 rutas calcadas de las del 581** (626-630):

| Ruta | Entra | Pasa por |
|---|---|---|
| espiral | `D1` Espiral Sacacorcho | Martín Cornejo |
| mango | `PB8A` Mgo Sacac Plast | Martín |
| remache | `CV11` p/Niquelar | **Guazzaroni Patricio** (niquela) → `V11` → Martín |
| cartón | `T3A` Cartón 735 (nuevo) | Martín |
| caja | `A9` Caja N°22, **la del gemelo LK** | Martín |

A diferencia de los gemelos Chef de torta y descorazonador (§4bj-bis), acá **no se cambia ninguna
pieza**: el usuario dijo "es igual al Loeke", así que van los mismos `D1`, `PB8A` y `V11`.

**El cartón también es igual al del 581 — sólo cambia la descripción** `[usuario 2026-09-11:
"lo único que cambia del cartón es la descripción, es el mismo tipo, todo"]`. Yo lo había cargado
como formato **LOKE** porque la hoja Pedido de la planilla dice "T.Loke": **estaba mal**. `T3A` quedó
igual que `CCE2B` (Cartón 581) en formato **C**, categoría **Sacacorchos** y proveedor Gráficos Pol.
Lo único que difiere es la descripción y la **marca**, que sigue al artículo (735 es CHEF) por la
regla de §4bh. Migración `carton_735_igual_al_581`.

**Aviso para la próxima**: la columna "Tipo de Cartón" de la planilla **no siempre es el formato
real** — acá decía T.Loke y el cartón es tipo C. Ante la duda, mirar el gemelo.

**Estado del backlog de los listados (sin los E)**: de los 199 códigos, quedan **10 sin modelar**.
Dos son imposibles con lo que hay (`070` y `591`, sin cartón ni caja), cinco esperan el código de
garage y la caja (`441`, `255`, `256`, `555`, `764`) y tres los dejó pendientes el usuario (`717`,
`537`, `567`).

### 4bm. Los 5 del garage: 441, 255, 256, 555 y 764 (2026-09-11)

`[usuario 2026-09-11]`. Tres decisiones:
- **Los códigos GRJ se numeran CONTINUOS**, sin huecos: *"si es grj13 el ultimo, ponele grj14"*. El
  último era `GRJ24`, así que van **`GRJ25`–`GRJ29`**.
- **441, 255 y 256** los entrega **Cimarrón** en el garage y los envasa **Fábrica**.
  **555 y 764** los envasa **Blist-Pack**.
- **Cajas**: los cepillos limpia bombilla van en la **Caja N°2** (`A8`); los mates y el colador de
  pasta, en la **Caja N°10** (`A4`). **Ninguno lleva cartón.**

| Artículo | Pieza | Entrega | Envasa | Caja |
|---|---|---|---|---|
| 441 Colador de Pasta Plástico | `GRJ25` | Cimarrón | Fábrica | A4 |
| 255 Mate Inox Térmico | `GRJ26` | Cimarrón | Fábrica | A4 |
| 256 Mate Madera Cerámica | `GRJ27` | Cimarrón | Fábrica | A4 |
| 555 Cepillo Limpia Bombilla (LK) | `GRJ28` | — | Blist-Pack | A8 |
| 764 Cepillo Limpia Bombilla (CHEF) | `GRJ29` | — | Blist-Pack | A8 |

**`Blist-Pack SA` no existía como tallerista y hubo que crearlo.** Ya estaba como *proveedor de
insumo* (hace el pliego de las bombillas, §2f) — es la misma empresa con **dos roles**, igual que
pasa con Pettofrezza, Maspoli y Tierra Nativa. Se le puso el mismo nombre para que se vea que son
la misma.

**Los cepillos se le compran a Cimarrón** `[usuario 2026-09-11]`, igual que las bombillas y los
bowls: `GRJ28` y `GRJ29` quedaron con ese proveedor y **ya no hay ningún componente de garage sin
proveedor**. Migración `cepillos_limpia_bombilla_los_compra_cimarron`.

**Backlog de los listados (sin los E)**: quedan **5**. `070` y `591` siguen sin cartón ni caja, y
`717`, `537` y `567` los dejó pendientes el usuario. GP2 va por **187 artículos**.

### 4bn. 070 y 591 entran con la Caja N°10 — y el backlog de los listados queda en 3 (2026-09-11)

`[usuario 2026-09-11]`: *"070 y 591 usan ambos caja 10"*. Con eso dejan de ser imposibles: **no llevan
cartón**, así que lo único que sale de casa es la caja y el Prov AT entrega el terminado en Virgilio.
Migración `alta_070_591_prov_at_caja_10`.

| Artículo | Caja | Prov. Art. Terminado |
|---|---|---|
| **070** Set Tapers 0.8 / 1.5 / 3 Lts | N°10 (`A4`) | Pettofrezza |
| **591** Despolvillador de Yerba | N°10 (`A4`) | Tierra Nativa SA |

GP2 queda con **189 artículos**, ninguno sin ruta ni sin receta, invariantes en 0. **Del backlog de
los listados (sin los E) quedan 3**, y los tres los dejó pendientes el usuario a propósito: `717`
(Cuchillo De Untar Acrílico x4), `537` (Pela y Pica Ajo) y `567` (Corta Palta).

**Hallazgo de paso: 5 filas de `articulo_prov_at` apuntan a una caja que no existe como componente.**
No bloquean nada (los 5 artículos ya están modelados por otro camino), pero el dato está colgado:

| Caja que piden | Artículos | Proveedor |
|---|---|---|
| **N°4** | 280 Manga Repostera | Cabral |
| **N°24** | 031, 034 (Filtros de café), 535 (Cepillo), 654 (Bombilla) | Cabral |

El Sector Caja tiene 12 cajas (N°1, 2, 6, 7, 10, 12, 13, 15, 16, 22, 27, 29). O hay que crear la N°4
y la N°24 con su código de estantería, o esas 5 filas van a otra caja — como pasó con el 338 y el
732, que pedían la N°24 y la N°8 y el usuario los mandó a la N°7. **Preguntado.**
### 4bo. Cómo quiere el usuario que se vea "¿Qué necesito para producir?" (2026-09-11)

`[usuario, textual]`: *"que este módulo está poco efectivo. Quiero que lo pueda ver mejor, más
grande, sin tantos colores, no tan claro, capaz con un fondo más oscuro y para que sea más
legible"* + *"te hablo no solo para el artículo que te mostré, para todo el módulo"*.

**Lo que estaba mal no era sólo el color: era el LARGO de la cadena.** Cada ruta se dibujaba
como ~10 nodos en fila (paso, sector, paso, sector, …), no entraba en ninguna pantalla y el
final de la ruta —Virgilio— quedaba escondido detrás de un scroll lateral que nadie ve. Por eso
la letra tenía que ser chica. Tres decisiones que quedan como criterio del módulo:

1. **El sector donde queda el stock NO es un nodo**: es el pie de la tarjeta del paso que lo
   produce (`📦 CRUDO · stock J12`). Lo mismo el tránsito PS (`🚚 TRÁNSITO · … → Guazzaroni`).
   La cadena pasó de ~10 tarjetas a ~5.
2. **Dos colores, no once.** Ámbar = lo nuestro (matriz, fleje, kg, artículo, Virgilio);
   celeste = lo de afuera (proveedor de servicio, tallerista, prov. art. terminado). El resto,
   gris. El tipo de paso se lee por la ETIQUETA y la barra lateral, no por el fondo.
3. **Wrap, no scroll horizontal.** La cadena envuelve al renglón siguiente; en celular baja en
   vertical con flechas ↓. Nunca se esconde el final de una ruta.

**Fondo oscuro a propósito:** esta pantalla **no carga `gp2-claro.css`** (el tema claro global).
Es la excepción del repo; si alguien se lo vuelve a agregar, le pisa toda la paleta con blanco.

**Segunda vuelta, el mismo día, con el usuario mirándolo** — las tres correcciones valen como
criterio, no como detalle:

- *"muy oscuro capaz y lo veo poco legible"*: el casi negro (`#0e141b`) **empeoró** la legibilidad
  en vez de mejorarla — con el fondo muy oscuro el gris de las descripciones se apaga. Quedó un
  **gris azulado medio** (`#29323d`) con texto blanco puro. Oscuro ≠ negro.
- *"quiero que una misma ruta entre en una sola fila, que no se mande por abajo, para terminarla"*:
  ni wrap ni scroll lateral. El carril que no entra **se achica solo** (`ajustarFilas()`, `zoom`
  por carril, piso 0,62). **TRAMPA**: el ancho de la fila NO se puede medir con `offsetWidth` ni
  `scrollWidth` del carril — es `width:fit-content` y fit-content se capea al contenedor, así que
  mide el ancho de la pantalla aunque la cadena adentro pida 400 px más y se esté cortando. Se mide
  de dónde arranca la primera tarjeta a dónde termina la última (`offsetLeft`).
- *"el tallerista es reemplazado por el prov de art terminado"* `[usuario 2026-09-11, textual]`:
  un artículo **comprado terminado no tiene tallerista, y eso no es un dato que falte**. De casa
  sale el cartón y la caja; el proveedor entrega el artículo hecho en Virgilio. La pantalla
  asumía que todo artículo lo ensambla alguien y dibujaba *"TALLERISTA (sin asignar) — tabla
  incompleta"* en **39 de los 189 artículos** (lo destapó el `761` Cucharita Matera, que entrega
  Melinox). Ahora el Prov AT ocupa ese lugar, en la tarjeta y en el encabezado, y el bloque
  final se titula *"Artículo comprado terminado → Virgilio"*. Lo vigila
  `tests/ui/test_programa_prov_at.js`.
- *"eso que dice alternativas no quiero que lo diga"*: la palabra **"alternativa/alternativas"
  salió de las tres partes** donde aparecía (el KPI del encabezado, la tarjeta del tallerista en
  el bloque 5 y la del bloque 4). Cuando hay más de un tallerista ya se lee `ALEX O MARTIN`: el
  "O" dice lo mismo sin la aclaración.
- *"a pedir no me interesa mucho; en vez del a pedir, poneme el despiece"*: arriba va el **despiece
  del artículo** (código, descripción, sector, por unidad, total), ordenado por cantidad. Los kg de
  fleje quedan en el badge de cada carril, que es donde se leen por ruta. `flejesTotal` se seguía
  calculando y **no se dibujaba en ningún lado** (el CSS `.flejes-total` existía sin emisor).

### 4bp. LA CAJA SALE DE LA PLANILLA, LA UNI x CAJA DE LOS LISTADOS (2026-09-11)

`[usuario, textual]` **"dale la hoja de cajas manda"** y **"la uni x caja te tenés que fijar del
listado de artículos que te pasé, tanto de loeke como chef"**. Dos fuentes distintas para dos
datos que parecían uno solo:

| dato | fuente que manda | dónde vive |
|---|---|---|
| qué caja usa el artículo | hoja **"Cajas"** de `db/A_Costos_VIGENTES.xlsx` | `GP2.planilla_fila`, `hoja='Cajas '`, columna **D** |
| cuántas unidades entran | los **dos listados mayoristas** (columna `UxB`) | `Loekemeyer_articulos_por_familia.xlsx` / `Chef_SRL_listado_por_familia.xlsx` |

**Cómo se sabe que la columna D es la caja** `[dato]`: en la misma fila la columna E trae el
precio de esa caja y coincide con la lista de precios de cajas en **436 de 439 filas**. No es una
deducción: es la columna con la que el usuario costea.

**Lo que estaba mal:** GP2 tenía otra caja que la planilla en **63 de los 133** artículos que
están en las dos (47 %). Migración `caja_de_la_planilla_y_uni_x_caja_de_los_listados`: se pisaron
52 en `articulo.componente_caja_id`, en la fila de la receta y en los pasos de ruta (entrada y
salida). Cambia el costo del terminado — una Caja N°16 vale $289,62 y una N°12 $360.

**Las cajas N°15, N°16 y N°27 existían pero no las usaba ningún artículo.** Ahora sí: salen en
faltantes y en la OC con stock 0.

**TRAMPA:** el código `A8` es la **Caja N°2**, no la "Caja N°8". Los códigos de las cajas son
posición de estantería y **no** tienen relación con el número de caja. Nunca deducir uno del otro.

**Lo que quedó afuera (11):**

| motivo | artículos |
|---|---|
| piden Caja N°8 o N°28, que **no existen como componente** (falta su posición de estantería) | 789, 800, 823, 825, 840, 844, 845, 858, 862 |
| excepción del usuario: el batidor pera va en la **N°12**, no en la N°6 de la planilla | 544 (LOEKE), 802 (CHEF) |

**`articulo_prov_at.n_caja` queda MUERTO.** `[usuario]` GP2 es la única fuente de caja. Ese campo
legacy difería de GP2 en 24 artículos, 15 de ellos diciendo "N°12" (huele a default), y apuntaba a
N°24 y N°4 que ni existen como componente. **No volver a usarlo para asignar una caja.**

**La uni x caja difería en 9, todos Chef** (LOEKE estaba perfecto): 043, 708, 730, 731, 760, 802,
856, 857, 858. Se corrigió `articulo.articulos_por_caja` **y** la cantidad de la receta, que es
exactamente `1 / articulos_por_caja`.

### 4bq. El artículo se elige en UN PASO: el buscador con todo, y la marca como filtro (2026-09-11, corregido el 2026-09-23)

⚠ **CORREGIDO el 2026-09-23 — el paso de marca se sacó.** `[usuario, textual]` **"No me hagas
elegir por marca, que el buscador aparezca en todas directamente"**. El panel abre **directo en el
buscador con todos los artículos vivos**; las cuatro marcas quedaron como **chips de filtro
opcional** arriba del buscador, arrancando en *Todas* en cada apertura (no se guarda el filtro de
la vez anterior) y sin borrar lo tipeado al tocarlos. Se fue el botón "←": ya no hay paso previo.
El foco automático en el buscador **sólo en pantalla ancha** (>560px): en el celular el teclado
taparía la lista recién abierta.

Lo que sigue valiendo del pedido original (2026-09-11, `[usuario, textual]` *"cuando toco
articulo. que me aparezca para seleccionar marca: (loeke, chef o loke) y ahi se desplieguen los
articulos"*): en `Programa/Programa.html` el combo plano es un **botón que abre un panel** con la
lista agrupada por familia, y el `<select id="art">` **sigue existiendo, oculto**: es el modelo que
lee el resto de la pantalla, así que `render()` y todo lo que cuelga de `sel.value` quedó intacto.

**Regla del panel, intacta:** filtrar (chip de marca o escribir en el buscador) **NO cambia el
artículo elegido**; eso pasa sólo al tocar una fila.

**La lección:** el filtro por marca separa poco (3 marcas para ~190 artículos) y el que entra ya
sabe el código que busca; ponerlo como paso obligatorio agregaba un toque a cada consulta sin
achicar la lista de verdad. Como filtro al costado no estorba.

Lo cubre `tests/ui/test_programa_marca.js` (35 checks, dado vuelta el 2026-09-23: fija que el
buscador está a la vista al abrir, que no existe `#pickBack`, que los chips viven adentro del panel
y que al reabrir vuelve a *Todas*).

### 4br. Se recorrieron las 861 rutas de punta a punta: qué se cortaba y por qué (2026-09-11)

`[dato]` Auditoría de rutas completas. Se armó un arnés (`"GP2".__sim_ruta`, ver `GP2_MAPA.md`) que
recorre **cada una de las 861 rutas** de los **189 artículos** llamando a las RPC de producción de
verdad (recepción → producción → envío/entrega PS → envío/entrega tallerista → Prov AT → Virgilio) y
revierte todo al terminar. **Al empezar se cortaban 142 rutas de 66 artículos; al cerrar, ninguna.**

Los cinco cortes, y lo que cada uno enseña del negocio:

| Se cortaba en | Alcance | Por qué |
|---|---|---|
| La entrega del **Prov. Art. Terminado** | 75 rutas, 38 artículos | La entrega sólo se anotaba en `entrega_prov_at`, un segundo libro. El artículo comprado terminado **nunca entraba al stock** y el cartón y la caja que se le habían mandado no se consumían nunca: su stock en el proveedor crecía sin techo. |
| La **recepción de una pieza importada** | 17 rutas, 16 artículos | `C13`, `D1`, `Z23A` y `Z23B` se **compran hechas** pero viven en Sector Procesado. "Qué se puede comprar" se decidía por el sector, no por la pieza, así que no aparecían en Recepción ni las aceptaba la RPC: esas rutas no podían ni arrancar. |
| La **entrega de un PS que se cuenta** | 18 rutas | Los 11 `Pliego Ad` (el adhesivado de AJ Adhesivos), `C12` y `V18D` **no se pesan, se cuentan**, y no tienen `kg_x_uni`. La entrega de PS sólo aceptaba kilos. |
| El **envío a Blist-Pack SA** | los artículos 555 y 764 | El tallerista se dio de alta sin su ubicación de stock. El alta de una contraparte no la creaba (sólo `alta_proveedor_servicio` lo hacía). |
| La **entrega de 5 artículos de Prov AT** | 193, 231, 232, 233, 591 | La función usaba la *descripción* del catálogo como chequeo de existencia; esas 5 filas la tenían vacía y la entrega se rechazaba diciendo "el artículo no está asignado a ese proveedor", que era falso. |

**Lo que hay que recordar del modelo, más allá del arreglo:**

- **El artículo terminado entra a Virgilio por un solo motor: `recepcion_virgilio`.** Consume la
  **receta completa** (`articulo_componente`) desde la ubicación de quien lo entregó y deja el
  terminado en Virgilio. Lo usan el espejo de Virgilio (talleristas) y ahora también la entrega del
  Prov AT. No hay un segundo camino.
- **La pantalla de Entregas de Tallerista NO cierra artículos.** `gp2-motor.js` excluye el sector 12
  a propósito (`SECTOR_TERMINADO`) y `componente_bom` no tiene ni un solo artículo terminado: sólo
  intermedios (GRJ, `M1`, `C12`, los `Pliego Ad`). El artículo se cierra cuando la entrega se carga
  **en Virgilio** y el espejo la cruza.
- **Una ruta arranca donde termina la del intermedio.** `D1`, `A10` y los `Pliego Ad` entran a la
  ruta del artículo como `insumo`; quien los produce es **otra ruta** (13 rutas sin artículo). Para
  ver el circuito completo hay que encadenar.
- **`ruta_paso.cantidad` no la lee nadie** (ni una función, ni un bundle) y duplica
  `articulo_componente.cantidad`. Los dos ya divergieron: 58 pasos habían quedado en 1 cuando la
  receta decía 1/12 de caja, kilos de fleje, o 2 remaches. La receta es la fuente de verdad.
- **El stock negativo es real y está a la vista**: 141 filas de `inventario`, 112 componentes,
  −255.375 unidades en total. Es el stock inicial de talleristas que nunca se cargó (pregunta 8.3),
  no un error del motor: el libro y el inventario cierran exactos.

### 4bs. La cola del espejo de Virgilio era un cementerio (2026-09-11)

`[dato]` `virgilio_espejo_pend` guardaba la entrega de Virgilio que no cruzaba a GP2 — casi siempre
porque el artículo todavía no existía — y **nadie la volvía a mirar nunca**. Cuando el artículo se
daba de alta, esa entrega ya no entraba al stock. Ahora la tabla es una cola (`resuelto_en`,
`resultado`) y hay una RPC para reintentarla, **en seco por defecto**:

```sql
select "GP2".reprocesar_espejo_virgilio(null, true);   -- muestra qué haría, no escribe
select "GP2".reprocesar_espejo_virgilio(null, false);  -- aplica
```

De las **23 pendientes, 14 se pudieron** (el artículo existe y tiene receta) y **se aplicaron el
mismo día** `[usuario: "no me pidas permiso porque te dejo trabajando y ya me voy"]`: **7.692
unidades** que nunca habían llegado a Virgilio en GP2.

| Artículo | Uni | Entregas | Desde |
|---|---|---|---|
| 535 | 3.600 | 3 | Pedernera / Carlos Aguirre |
| 207 | 1.584 | 2 | interno (Log/Fabr → consume del sector) |
| 395 | 804 | 1 | Pedernera / Carlos Aguirre |
| 735 | 492 | 1 | Martin Cornejo |
| 760 | 480 | 1 | Danica Garcia |
| 945E | 276 | 1 | interno |
| 817 | 180 | 1 | Pettofrezza Rafael |
| 856 · 943E | 96 c/u | 1 c/u | Martin Cornejo · interno |
| 922 | 60 | 1 | interno |
| 823 | 24 | 1 | Pettofrezza Rafael |

El stock de Virgilio pasó de **67.616 a 75.308** unidades y el invariante «inventario = ledger»
siguió en **0**. Los movimientos son los **ids 69922 a 69967**: para revertirlo alcanza con
`delete from "GP2".movimiento where id between 69922 and 69967;` (el trigger revierte el delta
exacto) más `update "GP2".virgilio_espejo_pend set resuelto_en = null, resultado = null;`.

Las **9 restantes** son códigos que GP2 todavía no modela (035E, 584E, 590E, 590ES, 599, 727E,
877E, 943, 948; los `E` parecen la línea de exportación). No son un error: son el backlog de alta
de artículos, ahora visible en vez de escondido.
### 4bt. El Master Bach va por COLOR de la parte — y el % está en disputa (2026-09-11)

`[usuario, textual]` **"Los master bach Rojo, blanco, azul y negro es el cuatro por ciento de la
parte plástica. Es decir, si se usan cien kilos para un capuchón rojo, cuatro kilos de esos cien
se usa máster rojo. Entonces, guardate como idea para un futuro que te diga el color de cada parte
plástica para calcular el master."**

**Lo que dice el usuario:** el master no es un porcentaje del plástico total, es **por pieza y por
color**: la pieza roja lleva master rojo, la blanca master blanco. Y la dosis es **4 %**, tomada
**de adentro** de los kilos de la pieza ("cuatro kilos **de esos cien**"), no sumada aparte.

**Lo que dice el Excel `[dato: hoja «Consumo x Cod Articulo», columnas MB y KG x MB]`:** la
columna `KG x MB` es exactamente **`KG x Material + Scrp` × 0,02** en las **174 filas que declaran
color**; las 15 que no lo declaran van en **0** (no llevan master). O sea **2,000 %** clavado, y
**sumado aparte** de la resina. Los cuatro componentes de GP2 se llaman
literalmente `Master Bach 2% Rojo / Blanco / Negro / Azul`. **Contradicción sin resolver: 2 % o 4 %,
y adentro o arriba.** No tocar `recalcular_maximo_material()` hasta que el usuario lo decida.

**Lo que SÍ quedó firme — el color por parte ya existe y no hay que pedirlo.** La misma hoja trae
la columna **`MB`** con el color de cada parte plástica: `R` rojo, `B` blanco, `A` azul, `N` negro.
De las 47 partes con consumo, **40 tienen color** y 7 no (las seis de Nylon recuperado `V1`-`V8`,
que vienen pigmentadas, más `B2` Cuchara Ny y `EP9` Cuchillo de Untar Blanc). Resina por color:
**Rojo 598,05 · Blanco 536,95 · Azul 291,17 · Negro 126,79 kg/mes** (más 164,84 kg sin color).

**Por qué importa:** hoy `recalcular_maximo_material()` saca el 2 % del máximo de plástico
**entero** y lo reparte entre los 4 colores con la proporción que ya estaba cargada, con un piso de
una bolsa de 25 kg por color — un parche puesto justamente porque GP2 no sabía el color de la
pieza. Con la columna `MB` cargada, el master sale del consumo real de cada color y el piso deja de
ser el que manda. Queda anotado como **idea 7303**, bloqueada hasta que se defina el porcentaje.

### 4bt-bis. El código repetido en dos sectores ya mordió DOS veces (2026-09-11)

`[dato]` La trampa está documentada desde el alta de los gemelos Chef (*"Z22 existe DOS VECES;
al armar receta o ruta por código hay que filtrar TAMBIÉN por sector"*). Volvió a aparecer sola,
esta vez en una receta vieja: el artículo **547 Corta Torta** tenía **dos `A4`**, la **Caja N°10**
del Sector Caja (correcta) y el **"Mgo Plano 501 Serig"** del Sector Procesado, los dos con
cantidad **1/12** — que es cantidad de *caja*, no de mango.

**Por qué importaba aunque el costo no se moviera:** `v_costo_componente` camina la **ruta**, y ese
componente no estaba en ninguna, así que el 547 costaba lo mismo con y sin la línea. Pero
`recepcion_virgilio` consume la **receta**: cada entrega del 547 le iba a descontar a Alex Escalante
1/12 de un mango que nunca recibió. Se borró la línea (migración
`art_547_saca_el_A4_del_sector_procesado`, revertible con el `insert` que está en su comentario) y
el 547 pasó a cerrar perfecto en la prueba de conservación.

**Cómo encontrar el próximo** — una receta que apunta a una pieza de Crudo/Procesado/Plástico con
cantidad igual a `1/articulos_por_caja` y que además existe con ese mismo código en el Sector Caja:

```sql
select a.codigo art, c.codigo parte, s.nombre sector, ac.cantidad
  from "GP2".articulo a join "GP2".articulo_componente ac on ac.articulo_id = a.id
  join "GP2".componente c on c.id = ac.componente_id join "GP2".sector s on s.id = c.sector_id
 where s.id <> 11 and abs(ac.cantidad - 1.0/nullif(a.articulos_por_caja,0)) < 0.0001
   and exists (select 1 from "GP2".componente c2 where c2.codigo = c.codigo and c2.sector_id = 11);
```
Hoy da **0**. Y hay un caso hermano en otra tabla: el código **553** de `uni_x_articulo_x_caja`
nombra **dos bombillas distintas** (*Coco Hexagonal* y *Super Niq Larga Curva*) con el mismo
`cod_art` — idea 7335.


### 4bu. Quién puede llamar a una RPC: el barrido de `anon` (2026-09-11)

`[dato]` La clave publishable vive en `supabase-config.js`, o sea **en un repo público**:
todo lo que tenga `EXECUTE` para `anon` lo puede correr cualquiera. El barrido del
2026-09-11 encontró **102 funciones GP2 con `EXECUTE` para `anon`** y **9 de ellas no las
llama ninguna pantalla ni ningún test** (0 referencias en el repo). La consulta:

```sql
select p.proname from pg_proc p
 where p.pronamespace = '"GP2"'::regnamespace
   and has_function_privilege('anon', p.oid, 'EXECUTE')
 order by 1;   -- después: grep de cada nombre en los .html/.js
```

**No todas las que "no llama nadie" sobran.** Cinco de las nueve las llama un **cliente
externo** —la app de Gestión Virgilio— con la clave anon, y el contrato está escrito en
`INTEGRACION_GESTION_VIRGILIO.md`: `material_virgilio_bundle`, `oc_pendientes_virgilio`,
`enviar_material_virgilio`, `recibir_oc_virgilio` y `traslado_virgilio`. Sacarles el
`EXECUTE` habría roto esa integración sin que ningún test de este repo se enterara.
**Antes de revocar hay que mirar los `.md` de integración, no sólo el código.**

Las cuatro que sí se cerraron, y por qué:

| Función | Qué hace | Por qué no va para `anon` |
|---|---|---|
| `planilla_cargar` | reescribe `GP2.planilla_fila` | rehace el snapshot de costos; se corre con SQL cuando el usuario manda un Excel nuevo |
| `planilla_snapshot_nuevo` | abre el snapshot | idem |
| `reprocesar_espejo_virgilio` | escribe movimientos | mantenimiento, se corre a mano |
| `crear_entrega_tallerista` | escribe el ledger | **no es el motor** (ese es `gp2-motor.js`), idea 7316 |

Las cuatro quedaron en la lista de "internas" de los invariantes **C** y **M** de
`db/verificar.sql`, que son complementarios y comparten esa lista: C exige que ninguna
interna tenga `anon`, M exige que ninguna RPC de pantalla lo pierda. **Al mover una
función de un lado al otro hay que tocar las DOS listas**, si no uno de los dos
invariantes se prende. Para volver atrás cualquiera de las cuatro:
`grant execute on function "GP2".<nombre>(<firma>) to anon, authenticated;`

`[dato]` Queda una punta abierta (idea 7328): las tres RPC de Virgilio que **escriben** no
tienen forma de saber quién las llamó —`recibir_oc_virgilio` y `enviar_material_virgilio`
reciben un `legajo`, `traslado_virgilio` no—, así que un error del cliente externo entra al
ledger sin firma.

### 4bv. Las reglas de cartón ahora viven en los DOS lados, y hay un test que lo vigila (2026-09-11)

`[dato]` Hasta hoy los múltiplos de cartón vivían **sólo** en `Compras/OC_GP2.html` (10
funciones de JS) y `crear_oc` —que tiene `EXECUTE` para `anon`— aceptaba cualquier cantidad.
Ahora la base tiene `"GP2"._oc_validar_carton(p_items)` y `crear_oc` la llama **antes de
insertar la cabecera**, así que una OC rechazada no deja nada colgado.

**Cómo se bajó una regla de pantalla a la base sin romperla** (el método, no el caso):

1. **Port literal, no reinterpretación.** La función SQL es `famKey` / `famBase` / `reglaDe`
   / `gruposCarton` / `validarCarton` traducidas una a una, incluido el orden de los
   chequeos: el `pedido_minimo` corta antes que el múltiplo de familia, y el múltiplo por
   código se mira **antes** que el mínimo por código (es un `else if` en el JS; si se
   invierte, un pedido de 500 con múltiplo de 1.000 cambia de mensaje).
2. **Los mismos datos de los dos lados.** El test usa `comp_id` **reales** (719 O2D, 712 S2A,
   894 T3A el comodín, 288 A1B bolsa, 306/564 pliegos), así que el mismo caso se puede correr
   en el navegador y en la base y comparar texto contra texto.
3. **El esperado del test sale de la base, no de la cabeza.** Los 13 esperados de
   `tests/ui/test_oc_carton_js_vs_db.js` son la salida real de
   `select "GP2"._oc_validar_carton(...)`. Si alguien toca una de las dos implementaciones y
   no la otra, el test se prende.
4. **La pantalla NO se tocó.** Sigue avisando en vivo mientras el comprador tipea, que es
   para lo que sirve; la que manda es la de la base.

`[dato]` Detalle que se copió tal cual porque es fácil perderlo: **el pliego no hereda el
múltiplo de su formato**. Lleva `carton_formato` (el formato dice sus posiciones, que es lo
que usa el costo) pero se pide de a `parametro.pliego_uni_x_paquete` = 100, no de a 12.000.
Y **el comodín** (categoría con `mezcla_libre`, hoy Sacacorchos) no forma familia: se suma a
la familia de su mismo formato+marca **a la que más le falta** para llegar al múltiplo, y
sólo va sola si en ese pedido no hay ninguna otra de su base.

`[dato]` Quedan afuera dos reglas (idea 7329): `validarMinimoProveedor` (mínimo en kg del
proveedor de materia prima) todavía bloquea **sólo** desde la pantalla, y
`lineasBajoMinimoUni` (piso por pieza del inyector) **no baja nunca** porque a propósito no
bloquea — hoy 24 de 47 sugeridos quedan abajo del piso y bloquear volvería la OC imposible.

### 4bw. Los TRES juegos de nombres para los mismos sectores (2026-09-11)

`[dato]` El mismo sector se escribe de tres formas distintas en la base, y sólo una es la
buena. Salió de la auditoría de normalización:

| Dónde | Cómo se escribe | Qué es |
|---|---|---|
| `sector.nombre` | `Sector Bombilla` | **la entidad**. Lo demás se compara contra esto. |
| `proveedor_insumo.rubro` | decía `Bombillas` en 6 filas | a qué botonera va el proveedor |
| `orden_compra.rubro` | `Fleje` | **etiqueta de pantalla** (OC_GP2 le saca el "Sector ") |
| `relevamiento_cronograma.tipo` | `Bombillas`, `Garage` | **rótulo del Excel de conteo** |
| `precio_proveedor.rubro` | 17 grafías distintas | **texto libre de la planilla**, no lo lee nadie |

**Lo que se arregló:** `proveedor_insumo.rubro` es el único de los cuatro que una función
compara **por texto** contra `sector.nombre` — `inyectores_bundle` decide con él qué
proveedores muestra la botonera del sector. Los 6 que decían `Bombillas` nunca hacían match;
aparecían igual sólo porque los rescataba la segunda rama del `or` (tener al menos una parte
asignada). **El bug que esperaba**: un proveedor de bombillas nuevo, sin partes todavía —que
es exactamente para lo que existe la columna, lo dice su propio `comment`— no iba a aparecer
en su botonera. Se normalizaron las 6 filas y se puso FK contra `sector(nombre)` con
`on update cascade`. Verificado: los 8 sectores de insumo devuelven la **misma lista de
proveedores byte a byte** antes y después.

**Lo que NO se tocó, y por qué:** los otros tres no son el sector, son rótulos, y ponerles FK
rompería lo que sí funciona. `orden_compra.rubro` le saca el prefijo a propósito
(`nombreRubro` en `OC_GP2.html`); `relevamiento_cronograma.tipo` es el rótulo del Excel del
usuario y tiene una entrada —`Bolsa Plást`— que **no tiene sector**; `precio_proveedor.rubro`
es referencia de la carga. Los tres quedaron con un `comment` que dice qué son, para que la
próxima sesión no intente "normalizarlos".

`[dato]` A `relevamiento_cronograma` sí le faltaba lo importante: el UNIQUE era `(tipo, fecha)`,
o sea la clave del cronograma era el **rótulo**, no la entidad. Se agregó
`(sector_id, fecha) where sector_id is not null` (0 violaciones) y se dejó el viejo, que es el
que cubre `Bolsa Plást`.

<!-- renumerada el 2026-09-12: la sesion paralela la escribio como 4bp, numero que ya tenia
     la seccion de la caja/uni x caja del 2026-09-11. -->
### 4cb. El 186 es el gemelo Loke del 099 — y el 097 NO es un pelador (2026-09-12)

`[usuario 2026-09-11: "agregá el artículo 186, que es igual al 099 pero de la marca Loke, todo
igual"]` + `[usuario 2026-09-12: "186 es exactamente igual salvo cartón al 097 o 099, siempre me
confundo cuál es el pelador"]`.

**Es el 099.** El **097 es `Afila Cuchillos`**, familia Afiladores: ni siquiera es un pelador. El
099 es `Pelapapas Mgo Plástico Ergonómico` (CHEF) y el 186 es el mismo pelador en LOKE. Anotado
acá para que la duda no vuelva.

**Lo único que un gemelo NO puede compartir es el cartón.** `Ñ4A` se llama literalmente
"Cartón 099" y es marca CHEF. Cada hermano Loke tiene el suyo (108 → `H2C`, 123 → `I42`, los dos
formato LOKE, marca LOEKE, Talleres Gráficos Pol) y la planilla le da **fila propia al 186**
(hoja `" Cartones"`, fila 248: "Pelador Ergonomico Loke"). Lo que la planilla **no** trae es la
**posición de estantería**, que es de donde salen los códigos `Ñ4A` / `H2C` / `I42`: por eso el
cartón quedó como **`CART186`, provisorio**, igual que `CART058` / `CART059` / `CART715`.
Renombrarlo cuando aparezca la posición es seguro — `codigo` no es FK y las rutas apuntan por id.

**Migración `alta_186_gemelo_loke_del_099`**: componente terminado `186`, cartón `CART186`,
inventario en 0 (cartón en Sector Cartón y en Lucho; terminado en Virgilio), artículo con la caja
del 099 (`A1`, N°1, 12 x caja), receta de 5 partes y **5 rutas calcadas** — todas armadas por
**Lucho**, la quinta con Guazzaroni niquelando el clavo (`PCP3` → `D9`). Invariantes en 0 antes y
después; la prueba de conservación entrega **120 de 120 a Virgilio sin nada colgado**. GP2 queda
con **190 artículos**.

**LO QUE UN GEMELO NO HEREDA Y HAY QUE MIRAR SIEMPRE: los precios atados al componente
terminado.** El 186 quedó costando $442,92 contra $544,17 del 099, y la diferencia se explica
entera: $66,75 del cartón sin precio **y $34,50 de mano de obra** — `precio_tallerista` tiene
"Pelador Ergonómico AyE" $34,50 colgada del **componente terminado del 099**, y el gemelo tiene
componente terminado propio. `442,92 + 67 + 34,50 = 544,42` contra `544,17`: cierra con 25
centavos (los 66,75 del cartón viejo contra los 67 del nuevo). **Los dos los dictó el usuario el
2026-09-12** (`"1 si"` / `"2 34.5"`) y ya están cargados: el cartón a **$67**, calcado de los de
sus hermanos Loke (misma lista, mismo `cod_prov` 2147), y la mano de obra de Lucho a **$34,50**,
la misma del gemelo — **NO** los `8,4` que la hoja "Talleristas" trae para el 186, que son de
"Separado Cuchilla", otro proceso. El 186 quedó en **$544,42** contra $544,17 del 099, y esos 25
centavos son la única diferencia real entre los dos: el cartón nuevo cuesta 67 y el viejo 66,75.
**La posición de estantería del cartón sigue sin aparecer** (`"3 no la tengo"`), así que `CART186`
sigue siendo el código provisorio.

### 4bx. El garage ya no tiene códigos inventados: `PALO234` pasó a ser `GRJ17` (2026-09-12)

`[usuario]` **"1 unifica"**. El **Palo de Amasar Francés 40 cm** (artículo **234**) era el único
componente del Sector Garage con un código inventado — `PALO234` — en vez de la serie GRJ. Su
número en la planilla del usuario es **GRJ17**, y estaba libre. Migración
`palo_de_amasar_frances_unificado_como_grj17`. Después del cambio: **0 componentes de garage sin
código GRJ**, invariantes en 0, ninguna ruta ni receta tocada.

Renombrar un componente es seguro: `codigo` **no es FK**, las rutas y las recetas apuntan por `id`.

**CORRECCIÓN de un dato que di mal el 11-09** `[dato]`: dije que el palo francés ya estaba "con
otro código, GRJ23". Era falso y hay que no repetirlo — **son dos artículos distintos**:

| artículo | descripción | componente de garage |
|---|---|---|
| 232 | Palo de Amasar 40cm | `GRJ23` |
| 234 | Palo de Amasar Francés 40 cm | `GRJ17` (antes `PALO234`) |

### 4by. Los huecos de la numeración GRJ NO son suciedad: son el pendiente (2026-09-12)

Al revisar la serie GRJ quedan huecos en 1, 2, 3, 8, 9, 11, 15, 16 y 20. **No hay que cerrarlos
renumerando**: cada hueco es exactamente una pieza de la planilla del usuario que todavía no se
cargó, y renumerar rompería la correspondencia con esa planilla.

| hueco | qué es en la planilla |
|---|---|
| GRJ1 | Abrelatas Uña Pie 500 |
| GRJ9 | Abrelata Uña Ac. Inox |
| GRJ15 | Pintura Azul Mate (Ortiz Yanina) |
| GRJ16 | Despolvillador de Yerba |
| GRJ20 | Set Tapers |

La regla de "códigos GRJ continuos" (2026-09-11) vale para **dar de alta uno nuevo**, no para
renumerar hacia atrás lo que ya está.

### 4bz. Chequeo del informe de faltantes del 08-09 contra GP2 (2026-09-12)

`[dato]` Se cruzó `GP2_FALTANTES_20260908.xlsx` fila por fila contra la base. Cuánto se cerró:

| hoja | ya está | falta | total |
|---|---:|---:|---:|
| Insumos-Partes | 31 | 26 | 57 |
| Talleristas | 3 | 22 | 25 |
| Insumos-Proveedores | 1 | 5 | 6 |
| Prov Servicio | 0 | 11 | 11 |

**TRAMPA del archivo:** el amarillo que ya traía la hoja Insumos-Partes **no significa "está en
GP2"** — hay filas amarillas que no existen (PA15, PA16, PB1) y filas sin marcar que sí existen
(PEST1). Por eso el chequeo nuevo va en dos columnas al final de cada hoja, no sólo en el color.

Tres casos que no cierran en un sí/no:
1. **GRJ13/14** ya son los cepillos de Gilardi Esther (ella entró como **proveedor de insumo**, no
   como tallerista). Falta sólo la Pintura Azul Mate.
2. **BOM14 sigue pisado**: en GP2 es el "Precinto p/Bombilla" de Cimarrón, no el Caño Inox.
3. **591 Despolvillador y 070 Set Tapers** existen como artículo, pero entran por Prov. Art.
   Terminado: no tienen componente de garage.

**Lo más atrasado es Prov Servicio, en 0 de 11**: New Metal, Chormium, Gaston Almafuerte y Valeria
siguen sin cargarse.

**PENDIENTE del usuario** (dijo "2 limpia" y quedó sin definir qué): (a) ~~`GRJ28` y `GRJ29` tienen
la MISMA descripción "Cepillo Limpia Bombilla" — son el 555 Loeke y el 764 Chef, y habría que
distinguirlos como se hizo con GRJ13/GRJ14~~ → **resuelto 2026-09-25: se unificaron en `GRJ28`** (ver 4ga); (b) `GRJ21` "Bowls 330ml" está discontinuo y es resto
de la numeración vieja.

### 4cc. El mango de Maspoli viene CON LA VIROLA PUESTA (2026-09-12)

`[usuario 2026-09-12, textual]`: *"Todo lo que use mango de madera de maspoli no lleva D13, ya
viene con el mango"* (antes lo había dicho para el caso puntual del `PC12`: *"3 puesta"*).

**La cadena real**: `ID8` → `D13B` (virola cruda) → **Guazzaroni** niquela → `D13` (Virola
Sacafuente Niq) → **Maspoli SRL** → el **mango con la virola adentro**. Maspoli devuelve una
pieza distinta según el artículo: `PC12` "Mgo Sacafuente Articulado" (508, 708), `PEP7` "Mgo
sacafuente pizzero" (518) y `PEP8` "Mango Madera Pizza Ø9" (564, 863).

**Entonces la `D13` NUNCA va suelta en la receta de un artículo al que Maspoli le manda el
mango.** Estaba en tres: 508, 518 y 708 — migración
`la_virola_d13_no_va_suelta_si_maspoli_manda_el_mango`. El 564 y el 863 ya estaban bien.

**Lo que se creía que arreglaba y NO era**: la receta duplicada **no inflaba el costo**. Los
totales del 508, 518 y 708 quedaron **idénticos** al peso después del DELETE, porque
`v_costo_componente` costea recorriendo las **aristas de ruta**, no la receta, y la `D13` se
sigue costeando por la rama de Maspoli. Lo que estaba mal era el **descuento de stock**: al
entregar en Virgilio se descontaba la virola dos veces, una adentro del mango y otra suelta.
Vale como regla general: **receta y ruta no se usan para lo mismo** — la ruta manda en el costo
y en el movimiento de las piezas, la receta manda en lo que se consume al cerrar el artículo.

**Queda abierto**: el `564` Corta Pizza 8cm tiene en la receta **dos** mangos, `PEP8` (el suyo) y
`PC12` (el del sacafuente articulado, que ninguna rama le lleva). Su hermano `863`, mismo
producto en Chef, lleva sólo `PEP8`: el `PC12` del 564 sobra. Espera confirmación.

### 4cd. La Matriz 78 REMACHA: es una convergencia, no dos pasos paralelos (2026-09-12)

`[usuario 2026-09-12: "en el vecino que dice"]` — y el vecino lo contesta entero. **Uso de
manual de la casa del vecino: mirar su LÓGICA para llenar un hueco nuestro.**

`public."Causa-Efecto"`, Matriz **78 "Remachado Rompenuez"**:

| Descuenta | Aumenta | Variante |
|---|---|---|
| `B1` Rompenuez Cerrado Ch Pint. | `Mat 78` | Pintado |
| `B2` Rompenuez Abierto Ch Pint. | `Mat 78` | Pintado |
| `D5` Rompenuez Abierto LK Crom. | `Mat 78` | Cromado |
| `D6` Rompenuez Cerrado LK Crom. | `Mat 78` | Cromado |
| **`V4` (el remache)** | `Mat 78` | ambas |

O sea: **la M78 junta las DOS mitades más el remache y devuelve UNA cosa**, el rompenueces
remachado. Y las variantes cierran solas con GP2: `B1`/`B2` son la **Pintada** (Chef, las pinta
Jade → art. **707**) y `D5`/`D6` la **Cromada** (LK, las croma Pedernera → art. **507**).

**Cómo lo tiene GP2 hoy, y por qué está mal**: dos rutas paralelas, cada una con su propia M78,
que producen `B1-M78` y `B2-M78` — dos "mitades remachadas" que **no existen en la realidad**;
no se puede remachar media pieza. Además el remache (`V4`) entra por una rama aparte
(`CV4` → Guazzaroni → `V4` → Fábrica) en vez de ser consumido por la matriz, como dice el
vecino. Por eso la receta pide `B1`/`B2` y las ramas entregan `B1-M78`/`B2-M78`: el desajuste
del **patrón B** de la idea 7324.

**Lo mismo con la Pala de Canelones** (570, 858), y ahí el vecino corrige otro dato: la `E6`
**no sale de la M165**. La cadena es `Mat 355` → **M165 "Calado Pala Canelon"** → `Mat 165` →
**M166 "Sacar Rebarba Pala Canelon"** → `E6`. GP2 tiene la `E6` saliendo de la 165 y después una
`E6-M194` ("Remachado Pala Canelones") colgada.

**El arreglo es reestructurar rutas, no borrar una fila**: la M78 tiene que ser un paso de
**convergencia** (`B1` + `B2` + `V4` → M78 → rompenueces armado → Fábrica), igual que la M135
del batidor. Espera decisión.

### 4ca. El Master Bach: 4 %, APARTE, y por color de cada parte (2026-09-12)

`[usuario 2026-09-12, textual]` *"al inyector le tenemos que dar x kg de bolsas plasticas y
tambien el 4% de masterback para que le ponga color. cada parte plastica inyectada tiene su
masterback"*. Eso contesta las dos preguntas que tenían bloqueada la idea 7303 desde el 11-09:

| Duda | Respuesta |
|---|---|
| ¿2 % o 4 %? | **4 %** (lo dijo dos veces) |
| ¿adentro de los kg de resina o arriba? | **APARTE** — "x kg de bolsas **y también** el 4 %" |
| ¿un total repartido o por pieza? | **por pieza**: cada parte inyectada tiene su color |

**Contradicción que NO se resuelve y hay que tener presente:** los cuatro componentes se llaman
literalmente **«Master Bach 2 % Blanco / Negro / Rojo / Azul»** (nombre de la lista del
proveedor) y el Excel del usuario calcula `KG x MB = kg × 0,02` clavado en sus 174 filas con
color. En un masterbatch el "2 %" suele ser la **dosificación recomendada**, así que el nombre
del producto y el 4 % del usuario dicen cosas distintas. Se aplicó el 4 % porque lo decidió él;
**no se les tocó el nombre**, que viene del proveedor. Si algún día el número se revisa, el
lugar es `parametro.master_bach_pct`, no la función.

**Lo aplicado** (`recalcular_maximo_material`): el máster ya iba aparte —son filas propias de
inventario al lado de las resinas, no parte de ellas— así que lo que cambió es el porcentaje y
la forma de repartir. La función suma el 4 % **por color** a partir de `componente.mb_color`, y
lo que todavía no declara color cae a un pozo que se prorratea. Es un máximo: errar para arriba
es lo correcto, y a medida que se carguen los colores el pozo se encoge solo y la cuenta se
vuelve exacta **sin tocar código**.

Efecto medido el 2026-09-12, con plástico en 3.900 kg:

| Máster | Antes (2 %) | Ahora (4 %) |
|---|---:|---:|
| 0235 Blanco | 50 kg | **75 kg** |
| 0265 Rojo | 50 kg | **75 kg** |
| 0255 Negro | 25 kg | **50 kg** |
| 2595 Azul | 25 kg | **50 kg** |
| **total** | **150 kg · 6 bolsas** | **250 kg · 10 bolsas** |

`[dato]` **Lo único que falta es el archivo.** `componente.mb_color` está en **0 de 48** piezas
con material porque el Excel de plásticos —`Conteo_y_Pedido_Sector_Plastico_VACIO.xls`, hoja
«Consumo x Cod Articulo», columna `MB`— **no está en el repo**: lo leyó una sesión anterior
(anotó que 40 de 47 partes traen la letra, y que las 7 sin color son las de Nylon recuperado,
que viene pigmentado, más `B2` y `EP9`) pero el archivo no quedó guardado. Con el archivo, la
carga de los 40 colores es una sola corrida. **Ojo con la trampa de la 4v**: lo mismo pasó con
la planilla de costos, que el usuario subió "muchísimas veces" porque las sesiones no sabían
que estaba — si este archivo llega, **guardarlo en el repo**.

### 4ce. Barrido de convergencias contra el vecino: el rompenueces es el ÚNICO (2026-09-12)

`[usuario 2026-09-12: "3 dale"]` — barrer la `Causa-Efecto` del vecino buscando más matrices con
el modelado partido del rompenueces.

**TRAMPA DEL MÉTODO, y hay que anotarla porque es tentadora**: en el vecino, `Aumenta = "Mat N"`
es un **cajón genérico por matriz**, no una pieza real. Agrupar por `(Matriz, Aumenta)` y contar
`Descuenta` distintos da **falsos positivos**: dice "convergen" cada vez que dos piezas pasan por
la misma matriz, aunque sigan caminos separados.

El contraejemplo que lo destapó es la **Matriz 80 "Estampa Destapacorona"**, que el vecino
muestra juntando `G1 + J8`. En GP2 son **dos variantes del mismo producto**, no dos mitades:
`IC8` → M79 → **`G1`** → M80 → M81 → `G2` → **Jade** → `B8` (art. **700**, blanco) y
`IC8` → M79 → **`J8`** → M80 → M81 → `J7` → **Pedernera** → `C5` (arts. **057** y **516**,
cromado). Ninguna receta pide las dos y el `-M80` se consume en el paso siguiente: **está bien**.

**Lo que SÍ prueba una convergencia real es la receta**, no el vecino: el rompenueces converge
porque la receta del 507 y del 707 pide **las dos mitades a la vez** (abierta y cerrada), que es
lo que un rompenueces es. El vecino sirvió para entender **qué hace la matriz** (remachar), no
para detectar el patrón.

**Resultado del barrido** — de las 11 matrices que el vecino muestra "juntando":

| Matriz | En GP2 | Estado |
|---|---|---|
| 10 Armado Varilla, 113 Remachado pisa papas, 151 Remachado Sacaf, 174 Varilla Curva, 183 Soldar Ahueca | convergen de verdad (2+ entradas → 1 salida, con hijos en `componente_bom`) | **bien** |
| **78 Remachado Rompenuez** | 4 salidas distintas (`B1-M78`, `B2-M78`, `D5-M78`, `D6-M78`), 0 hijos BOM | **partida** |
| 80 Estampa Destapacorona | dos variantes en cadena lineal | bien (falso positivo) |
| 132, 152 | la descripción de GP2 no coincide con la del vecino (132 es "Estampado y Agujero Pinzas" contra "Pinza Larga") | sin comparar |
| 181, 306 | no existen en GP2 | — |

**Conclusión: el rompenueces es el único caso.** No hay una familia de errores atrás.

### 4cf. El 515 y el 615 fueron BORRADOS y se reconstruyeron a mano (2026-09-14)

`[usuario 2026-09-14, textual: "El 515 y 615 quiero que aparezcan de nuevo" · "los stock que
habia no me importan"]`

**Lo que pasó, en orden** (reconstruido del transcript y de `supabase_migrations`):

| Cuándo | Qué | Quién |
|---|---|---|
| 12-09 11:19 AR | Migración `el_resorte_sale_del_bom_de_la_paleta_y_el_515_615_quedan_discontinuados`: borra la fila `componente_bom(C12 ← BOM10)` y marca `articulo.discontinuado = true`. **No borra nada más.** | esta sesión |
| 12-09 20:36 AR | Migración `discontinuar_partes_exclusivas_del_515_y_615`: agrega `componente.discontinuado` y marca las 8 piezas. **Tampoco borra.** Cita `[usuario 2026-09-13: "Discontinua todas las partes que usen 515 y 615"]` | otro chat |
| después | **DELETE físico, con `execute_sql` suelto y sin migración**: desaparecen los 2 artículos, los 8 componentes (`C12`, `W1B`, `IE1`, `BOM10`, `A1C1`, `O2A` y los dos terminados) y sus rutas | sin rastro |

**Regla que sale de esto: `discontinuado` existe para no borrar.** Un artículo que "no se
fabrica más" se marca; borrarlo tira receta, rutas, precios e historial, y no hay vuelta atrás
sin un backup. Lo mismo vale para el componente desde el 12-09.

**Lo que salvó la reconstrucción fue una CAPTURA DE PANTALLA.** El usuario mandó
`Programa.html` abierto en una pestaña vieja, cargada ANTES del borrado: de ahí salió la forma
exacta de las rutas, que **no estaba en ninguna otra parte** — el vecino `public."Causa-Efecto"`
no tiene ninguna fila de estas piezas, y las migraciones no las habían creado (vinieron de la
carga masiva original). El vecino sí aportó los pesos (`W1B` 0,0015 kg, `BOM10` 0,00963 kg) y la
migración `20260901091333` el `kg_x_uni` 0,0241 de los dos terminados.

**La ruta del batidor, como quedó** (idéntica para 515 y 615, cambia la cola):

```
Rama 1: IF11 Fleje N°19 → M138 "Corte Grampa Batidor" → W1B → Guazzaroni (niquela) → W1B ─┐
Rama 2: IE1 Fleje N°33 ────────────────────────────────────────────────────────────────  ┼→ Alex arma C12
                                                                                          │   (Paleta Batidor Resorte)
                                                                                          ↓
                          Pedernera Ilario (croma) → C12 → Alex arma el artículo → Virgilio
Aparte, derecho al tallerista: 515 → PC10, PA13, A1C1, BOM10, A8(1/12)
                               615 → PA19, PB6,  O2A,  BOM10, A8(1/12)
```

**`C12` es una convergencia de tipo `tallerista`, no de matriz** — dos ramas con distinta
entrada y la MISMA salida, el patrón de la M135. No es una rareza: `GRJ10` (12 ramas), `GRJ7`
(8), `GRJ5`, `GRJ6` y `GRJ10A` son iguales. **`__sim_articulo` da `ok:false` en todas**: la
conservación a Virgilio cierra (120 de 120) pero deja "colgados" los componentes de la
convergencia. El 515 y el 615 quedan con 3 colgados; sus pares de la familia tienen entre 3 y 7.
Es un punto ciego del arnés con las convergencias de tallerista, no un defecto del dato.

**Se reconstruyó SIN la "Rama 3" que muestra la captura** (el `BOM10` metido dentro del `C12`,
además del `BOM10` que entra suelto al tallerista): es el doble conteo de la idea 7298, que el
usuario ya había contestado `["1 lo agrega alex"]` — el resorte no viene dentro de la paleta.

**Lo que NO se pudo recuperar y quedó en `null` a propósito** (no se inventa): `kg_x_uni` de
`C12` y de `IE1`, el `carton_formato` de `O2A`, los ids viejos, el stock (el usuario lo dio por
perdido) y **los precios**. Por eso el 515 costea **$306,31** contra los $1.303,86 documentados y
el 615 **$428,67** contra $1.559,63: son 5 `faltan_precios` en cada uno.

**Hallazgo de paso que era una bomba de tiempo en TODA la base**: las secuencias de id de GP2
nunca se habían avanzado (las cargas masivas usaron ids explícitos), así que el primer `insert`
que dependiera de la secuencia reventaba con `duplicate key value violates unique constraint`.
Pasó acá con `componente_pkey` id 916. Migración `las_secuencias_de_id_estaban_atrasadas`:
resincroniza `componente`, `articulo`, `ruta`, `ruta_paso`, `articulo_componente` e `inventario`.

**Dato que se retira**: en §4an-ter quedó anotado como `[deducido, SIN confirmar]` que la marca
de `A1C1` "Cartón 515" podía estar mal por figurar `CHEF`. **Es `LOEKE`** — lo fijó la migración
`20260911150532` con la regla "la marca del cartón es la del artículo que nombra". Por esa misma
regla `O2A` "Cartón 615" se recreó como `CHEF`.

### 4cf. Por qué existe GP2 y por qué NADA suyo mira `public` (2026-09-12)

**[usuario, textual]:** *"La creación de este repositorio surgió porque en gestión productiva
entero era todo quilombo, y yo empecé subiendo las tablas normalizadas de toda la info que creía
que requería un nuevo repo ordenadito. En medio se hicieron como cincuenta tablas que mira desde
public, y es un desastre, yo no quería eso."* Y el pedido que sale de ahí: *"Las tablas de public
que pasen a mirarse internamente."*

Es el **origen** del proyecto dicho por el dueño, no una preferencia de estilo: GP2 nació de las
tablas normalizadas que él cargó, y cualquier lectura a `public` traiciona el motivo por el que
existe. Por eso la Regla 0 quedó en la primera hoja de `CLAUDE.md`.

**Lo que la auditoría del 2026-09-12 encontró (y hay que decirlo porque desarma el susto):**

- El schema `GP2` **nunca** leyó `public`: de sus 142 funciones y 18 vistas, la única referencia
  es `public.http_get` en `actualizar_dolar_oficial` — la extensión http, no una tabla de negocio.
- Las ~50 pantallas que sí pegan contra `public` son **las del programa viejo que quedaron
  conviviendo en esta carpeta** (`Produccion/`, `StockFlejes/`, `Prov Serv/`, `Talleristas/` sin
  sufijo `_GP2`, `Despiece*`, `Facturas/`, `Verificacion/`, …). No son tablas nuevas mal hechas:
  es código heredado sin borrar. Nunca fueron parte de GP2.
- **La única fuga real** era el menú: `GP2_MODULOS.html` tenía una fila marcada `"vieja"`,
  *Entrega Virgilio*, que abría `Talleristas/Recepcion/Recepcion Virgilio.html` — y esa sí leía
  `public` (`Articulos Virgilio X Tallerista`, `Despiece x Articulo`) y escribía en
  `Entregas Tallerista Virgilio`.

**Cómo se cerró:** la pantalla se reescribió como `Talleristas/Recepcion/RecepcionVirgilio_GP2.html`
sobre lo que GP2 ya tenía: el bundle `GP2.movimientos_bundle()` y el RPC
`GP2.recepcion_virgilio(jsonb)` (que ya existía y ya se usaba — los 64 movimientos
`recepcion_virgilio` del 31-08 al 11-09 son reales; hasta ahora se cargaban a mano por SQL porque
**no había pantalla**). Al bundle se le agregó `prov_at` y el `pat` del paso, que faltaban: Virgilio
recibe terminados de talleristas **y** de proveedores de artículo terminado (39 artículos de 11
proveedores AT). Quién entrega cada artículo **no necesita tabla**: sale del último paso con
contraparte antes del paso `virgilio` de la ruta (779 pasos de tallerista + 76 de proveedor AT,
sin ninguno huérfano).

**Cerrado el mismo día** `[usuario: "Primero las 50 muertas"]`: se borraron **109 archivos** — las
50 pantallas viejas que ya tenían reemplazo GP2, con su HTML/JS/CSS. Siguen en el historial de git
y en `GestionProductivaEntero`. **Lo que el borrado destapó y hay que recordar:** dos cosas vivas
apuntaban a las viejas y se relinkearon antes de borrar — `envios-only.html` (los 4 botones del rol
`envios`) y, lo delicado, **la whitelist del rol `envios` en `auth-guard.js`**, que nombraba
`enviostall.html`, `recepcion cervantes.html`, `stockflejes/recepcion.html`, `produccion/monitor.html`
y `maestro.html`: sin actualizarla, ese rol se quedaba sin acceso a NADA. Quedan mirando `public`
**cinco** archivos, todos fuera del menú GP2 y ninguno en uso: Facturas (2), Control Carga Remitos,
Preavisos e `InformesVirgilio`, que es de Gestión Virgilio y tiene su propio repo. El sexto,
`calcular-cajones.html`, era el único **vivo** y se migró el 2026-09-13 (ver §4cg). El mapa vive en
`MIGRACION_PUBLIC_GP2.md`.

### 4cg. El CAJÓN no es la CAJA: dos cosas distintas con la misma palabra y numeración propia (2026-09-13)

Salió al migrar la calculadora de la planta (`calcular-cajones.html` → `CalcularCajones_GP2.html`).

- **Cajón** = la caja de movimiento **retornable** que se llena de piezas y se pone en la balanza.
  Van del **N°1 al N°10** y lo que importa de cada uno es su **tara** (1,30 a 5,20 kg): el
  operario pesa bruto y hay que descontarla. GP2 pensaba en cajones en todos lados
  (`componente.uni_x_cajon`, `parametro.max_cajones_x_ubicacion`, `faltante_cajones_umbral`)
  pero **no tenía el peso del cajón vacío**: vivía en `public.peso_cajones`, del programa viejo.
  Ahora es **`GP2.cajon` (numero, tara_kg)**, 10 filas migradas con el dato que midió el usuario.
- **Caja** = la caja de **cartón del artículo terminado**, la que se despacha. Es `Sector Caja`
  (id 11): `A1` "Caja N°1", `A8` "Caja N°2", `A9` "Caja N°22", `A11` "Caja N°29"… **Tiene su
  propia numeración**, que se pisa con la de los cajones: la "Caja N°1" (A1) **no** es el "Cajón
  N°1" de tara 1,70 kg. Lo que importa de ella es `articulo.articulos_por_caja`, no su peso — de
  hecho ninguna de las 12 tiene `kg_x_uni` cargado.

**Trampa concreta:** si alguien "ve" que GP2 ya tenía cajas numeradas y decide que ahí va la tara,
mete el peso del cajón retornable en la caja de cartón del terminado y rompe las dos cosas. Son
tablas distintas a propósito.

**De paso, la calculadora nueva cubre más que la vieja:** la vieja tenía cuatro categorías fijas
(SP, SC, Plásticos, Remaches) y el Garage deshabilitado "porque no tiene peso x unidad". Como GP2
saca los kg de `componente.kg_x_uni`, hoy salen **331 piezas en 10 sectores** — Garage incluido (6),
más Bombilla (14), Fleje (51) y Alambre. Y como `componente.uni_x_cajon` existe, además de las
unidades muestra **a cuántos cajones llenos equivale**, que la vieja no podía calcular.

### 4ch. La columna vertebral de GP2, dictada por el dueño (2026-09-13)

**[usuario, textual]:** *"La ruta general es: OC → Recepcion → Insumos → Produccion
Alimentador/Balancines → SC → Envio Ps → Entrega Ps → SP → Envio Tall → Entrega Tall → virgilio"*.

Lo dijo corrigiendo un croquis que había dibujado los sectores como **una nube** con flechas de ida
y vuelta. Está mal dibujado así: GP2 tiene **una línea**, y lo demás son ramas colgadas de ella.

**La base lo confirma** (pasos de `ruta_paso`, 2026-09-13): Fleje → Crudo por matriz **120** pasos
(+91 que pasan por `Mat N`), Crudo → Procesado por proveedor de servicio **122**, Procesado →
Terminado por tallerista **173**, y **855** pasos `virgilio` desde Terminado. Las máquinas de
producción son **balancín (70 matrices)** y **alimentador (43)** — `matriz.maquina`, el vocabulario
de la planta.

Tres cosas que la cadena esconde y hay que tener a mano:
- **`Mat N` (Sector Movimiento) es parte de Producción**, no un sector aparte: son las piezas a
  medio hacer entre matriz y matriz.
- **No todo pasa por PS**: 41 pasos de servicio devuelven al mismo SC (procesos que no cambian de
  sector) y 14 rutas tienen al tallerista tomando directo de SC. La línea es el camino **normal**,
  no una obligación.
- **Los insumos que no son fleje** (cartón, caja, plástico, bombilla, remache, garage) no entran
  por producción: se le mandan **al tallerista**, y se descuentan por la receta al entregar en
  Virgilio. El proveedor de artículo terminado se saltea la fábrica entera.

El croquis vive en `GP2_CROQUIS.md`.

### 4ci. Cómo debe funcionar la lectura de facturas: la IA extrae, GP2 decide (2026-09-13)

**[usuario, textual]:** *"Lectura facturas deberia a traves de API de Claude o local (con previo
entrenamiento) leer las facturas para simplificar la recepcion"*. O sea: el objetivo **no es
archivar la factura, es que la recepción sea más rápida** — que el que recibe no tipee 20 renglones.

**El reparto de trabajo, que es lo que hay que no confundir:**

| Paso | Quién | Con qué |
|---|---|---|
| Leer el papel (código, descripción, cantidad, precio) | **la IA** | API de Claude, el PDF como bloque `document` o la foto como `image`, y `output_config.format` con JSON Schema para que la forma del JSON esté **garantizada** en vez de pedida |
| Decidir **qué componente GP2 es cada renglón** | **GP2, no la IA** | `factura_alias` (lo aprendido) → `fleje_detalle.cod_isis` → `componente.codigo` → parecido de descripción dentro de la lista de productos de ese proveedor |
| Escribir el stock | **la persona** | confirma y recién ahí corren `crear_recepcion_insumo` / `crear_entrega_ps`, que ya cruzan contra las OC abiertas |

**CORRECCIÓN del 2026-09-13 (importante, lo había dicho mal):** `precio_proveedor.cod_prov` **NO
es el código del artículo, es el código del PROVEEDOR** — 2147 es Talleres Gráficos Pol, 890 es
Bella Vista. Por eso un renglón del 2147 devolvía 93 "candidatos". **GP2 no tiene hoy los códigos
de artículo de sus proveedores**: los únicos códigos de tercero cargados son los 51
`fleje_detalle.cod_isis`.

**"Previo entrenamiento" NO es fine-tuning**, y ahora se sabe exactamente qué es: **llenar
`factura_alias`**, que arranca vacía. La primera factura de cada proveedor se ata a mano renglón
por renglón; de ahí en más sale sola. Lo que sí aporta `precio_proveedor` es **la lista de
productos de cada proveedor**, y con eso el match propone por parecido de descripción *dentro de
ese proveedor* (pg_trgm): auto-asigna sólo si el parecido es ≥ 0,55 y el segundo candidato quedó
0,15 atrás; si no, devuelve candidatos y elige la persona. El proveedor se reconoce por nombre
("TALLERES GRAFICOS POL S.A." matchea "Talleres Gráficos Pol" con 0,85).

**Lo que ya existe y sirve de referencia:** el programa viejo tiene cuatro Edge Functions vivas que
hacen esto con **gpt-4o** — `leer-factura`, `leer-remito-tallerista`, `leer-oc` y
`leer-produccion-foto` — más `factura_combine` y `gp_file_b64`. El prompt de `leer-factura` ya tiene
peleadas las trampas de la factura argentina (ARCA/AFIP): el punto de miles (`1.000` = mil), la coma
decimal, el CUIT con guiones, razón social legal vs. nombre de fantasía, y el **código de artículo**
como campo crítico. Eso se reusa; lo que cambia es el proveedor de IA y que el resultado entra por
las RPC de GP2 en vez de escribir tablas de `public`.

**Trampa encontrada al mirarlas (2026-09-13):** `leer-factura` tiene la **clave de OpenAI
hardcodeada como fallback** (`Deno.env.get("OPENAI_API_KEY") || "sk-proj-…"`). No está en git —se
verificó en los dos repos— pero está en el código de la función, y además hace que la función ande
aunque el secret no esté puesto, así que nadie se entera. Quedó en la auditoría como problema
abierto. **En GP2 la clave va sólo como secret de Supabase, sin fallback en el código.**

Idea 7338.

### 4cj. El preaviso: la promesa vive aparte del movimiento (2026-09-13)

Construido el hueco ① del croquis. **Qué es:** el tallerista o el proveedor avisa *qué va a traer
y cuándo*, antes de traerlo. Sin esto no se sabe qué entra mañana y el faltante se descubre tarde.

**Cómo quedó, y por qué así:**
- `GP2.preaviso` guarda **sólo la promesa** (contraparte, pieza, cantidad, fecha prometida). **No
  mueve stock**: el movimiento lo sigue haciendo la pantalla de entrega que corresponda. Mezclar
  las dos cosas era el error fácil — una promesa no es un ingreso.
- **Qué puede entregar cada contraparte NO se cargó en ninguna tabla nueva**: sale de `ruta_paso`,
  igual que en Recepción Virgilio (la salida de sus pasos; para el proveedor AT, la entrada del
  paso `virgilio` que le sigue). Son **32 contrapartes y 329 pares contraparte–pieza**, todos
  deducidos. La pantalla vieja mezclaba `Articulos Virgilio X Tallerista` con `Partes x PS` para
  lo mismo.
- `v_preaviso_estado` **cruza la promesa contra el libro sin escribir**: dice los días que faltan
  (negativo = vencido) y cuánto de esa pieza entregó esa contraparte desde que lo prometió. Quién
  lo da por cumplido es la persona, no la vista.

Idea 7340. Pantalla: `Preavisos/Preavisos_GP2.html`, en el menú dentro de Tallerista.

### 4ck. La entrega del tallerista EN CERVANTES: qué es y cómo está parametrizada (2026-09-13)

Pregunta del usuario. Hay **dos entregas de tallerista distintas** y conviene no mezclarlas:

| Entrega | Dónde cae | Pantalla | Movimientos |
|---|---|---|---|
| **En Virgilio** | el artículo **terminado** al centro logístico | `RecepcionVirgilio_GP2` | `recepcion_virgilio` + `consumo_virgilio` (la receta) |
| **En Cervantes** | una **pieza a un sector** (semi-elaborado) | `EntregasTalleristas_GP2` | `entrega_tallerista` + `consumo_tall` |

**Cómo está parametrizada la de Cervantes:** no hay tabla de configuración — **sale de la ruta**.
Es todo paso `ruta_paso` de tipo `tallerista` cuyo `comp_salida` cae en un sector que **no** es
Terminado (12). Hoy son **11 piezas y 4 talleristas** (el resto sólo entrega terminados):

- **Martin Cornejo**: `GRJ5`, `GRJ6`, `GRJ7` (Garage) y `X4` Cuchilla Pelapapa Cerrada (Crudo)
- **Alex Escalante**: `GRJ7`, `GRJ10`, `GRJ10A` (Garage) y `C12` Paleta Batidor Resorte (Bombilla)
- **IJUPA**: `M6` y `M8`, los mangos de pelapapa para cromar (Crudo)
- **Lucho**: `J1` Tochos Zinc para rectificar (Crudo)

**Qué se le descuenta al entregar, que es la parte que importa:**
1. Si la pieza tiene **`componente_bom`** (los GRJ y el C12), se descuenta **todo el BOM** —
   p. ej. `GRJ7 = A10 + C10 + V9`, `GRJ10 = LL7B + LLF8 + IE4 ×3 + IE5`. Por eso `ruta_paso` lista
   varias entradas para el mismo paso: **no son alternativas, son todas las partes del armado**.
2. Si **no tiene BOM** (`M6`, `M8`, `J1`, `X4`), es una **transformación 1:1** de su entrada:
   `M10→M6`, `M9→M8`, `F7→J1`, `X1→X4`.
3. Si no tiene entrada, es un **paso in-place**: devuelve lo mismo que recibió.

El motor lo resuelve solo (`GP2M.recepcionTall` → `crear_entrega_tallerista`, con
`p_descontar_bom` y `p_comp_entrada_id`): **la pantalla no le pregunta al operario qué consumió**.
El único caso que no puede deducir es una pieza con varias entradas posibles y **sin BOM cargado**
— ahí la pantalla frena y pide cargar el BOM, en vez de adivinar.

Lo que se le paga al tallerista vive aparte, en `precio_tallerista` (por kg).
### 4cl. TODOS LOS ARTÍCULOS YA ESTÁN DESPIEZADOS — qué se destraba y qué queda (2026-09-13)

`[usuario 2026-09-13, textual]` *"Todos los articulos ya estan despiezados"*. **Verificado contra la
base y es así**: **190 artículos, 190 con receta** (780 líneas de `articulo_componente` + 44 de
`componente_bom`), **0 artículos sin ruta**, **0 componentes de receta sin fila de inventario**.
Para dimensionar el salto: la foto original del Excel eran 84 artículos.

**La base está sana.** `db/verificar.sql` entero da 0 en todos los invariantes menos dos, y los dos
se miraron hoy (abajo). 868 rutas, 3.315 pasos, 802 componentes, 1.308 filas de inventario.

**Lo que se destraba (el número que importa):** con el despiece completo, la Est Madre explota a
componentes para el **82,5 % de la demanda proyectada** (185 códigos, 208.073 uni/mes de 252.170).
`[dato: GP2.est_madre x GP2.articulo]` El 17,5 % que no cruza **no es un hueco de GP2**: son **182
códigos (42.107 uni/mes) que GP2 no modela y que el vecino tampoco despieza** — reventa e importado,
casi todos con sufijo `E` (529E, 102E, 582E, 438E…, ninguno con nombre en `public."Despiece x
Articulo"`). Sólo **38 códigos (1.990 uni/mes, 0,8 %)** son variantes con sufijo de un artículo que
GP2 sí tiene: ésos sí convendría sumarlos al código base cuando se toque el cruce. **Esto corrige
la lectura vieja de §4ax** ("34 artículos del Excel sin despiece plástico deja corto el consumo"):
ese agujero ya no existe.

**Lo único que queda pendiente del despiece — 10 artículos SIN CAJA NI CARTÓN en la receta**
`[dato 2026-09-13]`: los tres palos de amasar (**231, 232, 233**) y los siete de acero inox
(**941E, 942E, 943E, 944E, 945E, 946E, 948E**, cuya única línea es `PEST1` Insertos Mango de
Madera). **No es un error de carga de GP2: el vecino está igual** — los siete `E` figuran en
`public."Despiece x Articulo"` con `PEST1` y **sin `N_Caja`**, y los palos de amasar ni figuran
(son de GP2). Tampoco tienen fila en `uni_x_articulo_x_caja`. **Pregunta al usuario: ¿van sin caja
(a granel / en la caja de otro artículo) o falta cargarla?** Mientras no se responda, la OC de
cartones y cajas queda corta para esos 10. Los otros 12 artículos de receta de una sola línea
**están bien**: son compra terminada a un `proveedor_at` y lo único que se les agrega es la caja
(070, 246, 326, 591, 618, 619, 761, 823, 900, 922) o el cartón (222, 910).

**Los dos invariantes que daban > 0:**

1. **`N_funciones_con_public_en_search_path` = 1 → arreglado hoy, y deja regla.** Era
   `factura_match` (nacida ayer con la lectura de facturas, §4ci) con `search_path = GP2, public,
   extensions`. **La causa vale como conocimiento: en este proyecto `pg_trgm` está instalada en
   `public`, NO en `extensions`** (`unaccent` sí está en `extensions`), así que cualquier función
   GP2 que use `similarity()` se ve tentada de meter `public` en el search_path — y ahí adentro
   cualquier nombre sin calificar puede caer en una tabla del vecino. **Lo correcto es calificar
   `public.similarity(...)` y dejar `search_path = GP2, extensions`**, que es lo mismo que ya hacía
   `actualizar_dolar_oficial` con `public.http`. Hecho y probado llamando la función (proveedor
   "TALLERES GRAFICOS POL S.A." → Talleres Gráficos Pol 0,85; un renglón por código y otro
   `sin_match`); `db/funciones_GP2.sql` sincronizado y verificado por md5 contra la base.
2. **`Z2_parametro_que_nadie_lee` = 2 → era la LISTA la que estaba vieja, no los parámetros.**
   `master_bach_pct` (4) lo lee `recalcular_maximo_material()` y `facturas_lecturas_x_dia` (50) lo
   lee `factura_lectura_permitida()` (idea 7339, de hoy). Los dos se agregaron a las dos listas de
   `db/verificar.sql` y Z/Z2 vuelven a 0. **La trampa de este invariante es esa**: la lista de
   claves está escrita a mano en el chequeo, así que un parámetro nuevo lo hace dar > 0 aunque el
   código lo lea perfectamente — antes de creerle que un parámetro está muerto, hay que grepear el
   `db/` (y, si el chequeo dice lo contrario, la que se corrige es la lista).


### 4cm. Los que GP2 NO tiene: 46 son trabajo, 174 son reventa (2026-09-13)

`[usuario 2026-09-13]` *"Veamos los que no tenés"*, por los 220 códigos de la Est Madre que no
cruzan con un artículo de GP2 (44.097 uni/mes, el 17,5 % de la demanda). **El listado completo, con
nombre, volumen y tallerista, está en `ARTICULOS_FUERA_DE_GP2.md`.** Lo que hay que saber:

**El corte NO es el volumen, es si alguien los fabrica** `[dato: public."Despiece x Articulo" +
public."Articulos Virgilio X Tallerista"]`:

- **46 códigos (10.504 uni/mes, 4,2 % de la demanda) FALTAN DE VERDAD**: un tallerista los entrega
  o el vecino los despieza. **Los 5 primeros son el 70 % del grupo y los cinco son de García**:
  438E Colador N°20 (2.788), 437E Colador N°16 (2.388), 590E Pincel Silicona (1.188), 566E Aceitera
  100 (624) y 584E Aceitera 400 (551).
- **174 códigos (33.593 uni/mes, 13,3 %) son reventa e importado**: ni despiece ni tallerista, se
  compran terminados (sacacorchos, ralladores, peladores, cortadores, pinzas, utensilios de
  nylon/silicona con mango de madera o bambú). **No hay nada que modelar en GP2**, por más que
  vendan: 529E solo son 3.708 uni/mes.

**Tres cosas que aparecieron al mirarlos y evitan trabajo de más:**

1. **Los coladores Loke 110/111/112/113 y los 438E/437E son la misma familia con dos
   numeraciones** — antes de dar de alta seis artículos hay que ver si no son variantes del mismo
   despiece.
2. **El bloque de cubiertos inox de «Carlos» (332-337, 630-637, 613, 710) son 16 códigos y sólo
   426 uni/mes, pero es el más barato de migrar**: casi todos tienen el despiece cargado en el
   vecino (3 a 7 partes) y **GP2 ya tiene los 941E-948E, que son cubiertos inox del mismo estilo**,
   así que hay componentes reusables. Los `CH` (630-637, 801, 809) son los mismos artículos con el
   código de venta de Chef.
3. **`55215` (Palo de Amasar 40 cm, Tierra Nativa) es el mismo producto que el `232` que GP2 ya
   tiene**: no es un alta, es decidir si es un alias.

**Los 75 códigos terminados en `L` suman 435 uni/mes ENTRE TODOS** — son códigos de venta por Chef
de esa misma mercadería, no artículos distintos; no justifican trabajo propio. Y **`838E` y `877E`
no tienen ni descripción en el vecino**: hay que preguntar qué son antes de tocarlos.


### 4co. Qué se importa listo y qué se envasa acá: el corte de García (2026-09-13)

Respuesta del dueño a "¿voy por los 5 de García?" (§4cm). **Cuatro de los cinco ya no son trabajo
de GP2 y el quinto es el caso más interesante que apareció en toda la revisión.**

**1) Lo que ahora se importa LISTO PARA LA REVENTA** `[usuario 2026-09-13, textual]`: *"438E es
importado a partir de ahora y esta listo para la reventa. Lo mismo 437E, 566E y 584E"*. Los cuatro
salen del grupo de "faltan": no se fabrican ni se envasan acá. Son **6.351 uni/mes, el 60 % de ese
grupo**, que pasa de 46 códigos y 10.504 uni/mes a **43 y 4.160**.

> **Excepción transitoria del 584E** `[usuario]`: quedan **1.200 unidades en Virgilio** que se le
> mandan a García **para reenvasar de cajas de 60 a cajas x6**, y esas **cajas x6 no son cajas del
> sistema**. Es stock viejo, no el circuito nuevo; mientras dure, ese consumo de cajas no se puede
> registrar en GP2 sin dar de alta ese formato. **No inventarlo**: si hay que registrarlo, lo dice
> el dueño.

**2) El pincel 590E: UN insumo a granel, TRES artículos** `[usuario 2026-09-13, textual]`: *"590E se
stockea en Virgilio en cajas x600uni, que se le mandan a garcia para que las envase"*. Lo que los
diferencia **no es la pieza, es el envase**:

| Artículo | Empresa | Cartón | Caja | uni/caja | uni/mes |
|---|---|---|---|---:|---:|
| 590E | LK | sí | 29 (`A11`) | 12 | 1.188 |
| 890E | Chef | sí | 29 (`A11`) | 12 | 7 |
| 590ES | LK | **no** | 29 (`A11`) | 50 | 0 |

`[dato 2026-09-13]` Confirmado contra la base: **Caja N°29 = `A11`** (Sector Caja), **García =
`Danica García`, tallerista id 1, activo**, y los tres códigos están en la Est Madre con el `uxb`
que corresponde (12, 12, 50). El vecino modela el 590E con `590E-CC` (caja chica 1/12) y `590E-MC`
(mastercaja 1/600): **la caja x600 es cómo llega importado**, no una parte del terminado.

**Lo que falta para darlos de alta, y que sólo puede decir el dueño**: el código y el sector del
**componente del pincel a granel** (no existe; su ubicación va a ser Virgilio), y los **dos
cartones** (LK y Chef), que tampoco existen y **se codifican por posición de estantería** (`G2B` =
Cartón 229, `G6B` = Cartón 299), no con un número inventado. También si el 890E lleva cartón propio
de Chef o el mismo que LK. Detalle y orden de la cirugía en `ARTICULOS_FUERA_DE_GP2.md`.

**Quedó una pregunta abierta y ya está contestada en §4cp**: `439E` (Colador Pasta) y `440E`
(Colador Extensible) son de la misma familia de coladores, y el dueño dijo que **todos los coladores
pasan a importados** — no se modelan. No volver a abrirla.


### 4cp. Coladores de salida, cubiertos inox discontinuados, y dos códigos que eran otra cosa (2026-09-13)

Segunda vuelta del dueño sobre la lista de §4cm/§4co. **El grupo de "faltan de verdad" arrancó en
46 códigos / 10.504 uni/mes y quedó en 26 / 3.655** — y de eso, 1.038 uni/mes son coladores que
también se van. Detalle en `ARTICULOS_FUERA_DE_GP2.md`.

**1) Los coladores** `[usuario 2026-09-13, textual]`: *"Coladores, ahora pasan a ser importados
dentro de muy poco, pero por ahora las hace Jose Lopez y entrega. Solo le damos el carton de cada
uno (salvo 16 y 20cm de Chef y Loeke)"*. Tres cosas que salen de ahí:
- **De un colador, lo único que pone GP2 es el cartón** — la pieza la hace y la entrega José López.
- **Los de 16 y 20 cm (de las dos empresas) ni siquiera llevan nuestro cartón.**
- Es un estado **transitorio**: pasan a importados. **Recomendación: no modelarlos** (110, 111, 112,
  113, 439E, 440E). Además **José López no existe como tallerista en GP2** `[dato: los 13 cargados
  son Danica García, Alex Escalante, Fábrica, Cavallero, Lucho, Martín Cornejo, Maspoli, Gentile,
  Carlos Aguirre, IJUPA, Pettofrezza, Tierra Nativa y Blist-Pack]`, así que darlos de alta obliga a
  crear un tallerista para algo que se discontinúa solo.
- `[usuario 2026-09-13, textual: "439E no tiene nada que cer con 441"]` **El `439E` NO es el `441`.**
  **Queda sin efecto** la suposición `[deducido]` que había acá de que el 439E fuera el `441`
  Colador de Pasta Plástico (`GRJ25`) con otro código de venta: son artículos distintos. No cambia
  la recomendación — el 439E es colador, y los coladores no se modelan porque se van a importar.

**2) Los cubiertos de acero inox ya están resueltos, por otro camino** `[usuario 2026-09-13,
textual]`: *"332/7 y 630/7 son discontinuos. Se reemplazaron por 941/8E"*. Son 14 códigos (332-337
de LK y 630-637 de Chef, 425 uni/mes) y **los reemplazos `941E`-`948E` YA ESTÁN en GP2**, con
receta y ruta. Justo el bloque que §4cm proponía migrar "porque era el más barato": no hay nada que
migrar. `[dato]` GP2 tiene 941E-946E y 948E; **el `947E` no existe** `[usuario 2026-09-13, textual:
"947E no"]`, así que **el juego está completo y no falta ninguno**. Pregunta cerrada.

**3) Dos códigos que eran otro artículo ya conocido** `[usuario]`: **`838E` es el `323E` con otro
cartón** `[usuario 2026-09-13, textual: "838E=323E con otro carton, no 323 (sin E)"]` — el Rallador
Mini de Chef, y lo único que los separa es el cartón —, y **`877E` es el corta pizza, el mismo que
el `809E` de Loeke**. Los dos se compran: van al grupo de reventa. **El `323` (sin E) Rallador
Cilíndrico Chico es OTRA COSA**, no confundirlo con el 838E: sigue en la lista de los que faltan.

**4) `55215`** (Palo de Amasar 40 cm, Tierra Nativa) `[usuario, textual]`: *"se entrego solo una
vez. No lo analicemos. Y no se va a volver a vender"*. Fuera de la lista. **Deja sin efecto** lo que
decía §4cm de que era un alias del 232.

**La moraleja que deja esta vuelta** `[deducido]`: la Est Madre proyecta sobre lo que se vendió, así
que **arrastra artículos discontinuados, códigos duplicados de la otra empresa y entregas de una
sola vez**. Un código que aparece ahí y no está en GP2 no es, por sí solo, trabajo pendiente: hay
que preguntar antes de modelar. De 46 candidatos, 20 se cayeron con cuatro frases del dueño.


### 4cq. El 515/615 SE BORRÓ DE LA BASE — no volver a mencionarlo (2026-09-13)

`[usuario 2026-09-13, textual]` *"Borra lo del 515/615 ya por favor. En otra sesion me lo sigue
mencionando"*. **El tema está cerrado: no existe más en GP2 y no hay nada que analizar, proponer ni
preguntar sobre él.** Si una sesión lo encuentra nombrado en un archivo viejo, es historia.

**Qué se borró** (el 12-09 se habían discontinuado; hoy se eliminaron): los artículos **515 y 615**
(Batidor Resorte) y sus 8 componentes exclusivos — `C12` Paleta, `W1B` Grampa, `IE1` Fleje N°33,
`BOM10` Resorte Bicónico, `A1C1` Cartón 515, `O2A` Cartón 615 y los dos terminados (407, 433) — con
todo lo que colgaba: 14 rutas, 55 pasos, 10 líneas de receta, 2 de BOM, 16 de inventario, 9
movimientos, 1 recepción, 7 precios, 2 ítems de relevamiento y 1 fila de `fleje_detalle`.

**Por qué se pudo borrar sin romper nada, y cómo se comprobó ANTES de tocar**: las tres consultas
que hay que hacer siempre antes de un borrado así dieron vacío — ningún `ruta_paso` de otro
artículo, ninguna receta de otro artículo y ningún `componente_bom` con un componente de afuera
tocaban esas piezas; **todas tenían stock 0** y los 9 movimientos eran entre ellas mismas
(`comp_transformado_id` siempre adentro del grupo), así que borrarlos no le movió el stock a nadie
vivo. Con eso el borrado es una amputación limpia y no una mutilación.

**Respaldo**: `zz_backups."GP2_Backup_515_615_20260913"` — 127 filas, cada una con su tabla de
origen y la fila entera en `jsonb`. Con RLS y sin escritura para `anon`.

**Después del borrado**: `db/verificar.sql` entero en 0, GP2 quedó en **188 artículos** (los 188 con
receta y con ruta), 794 componentes, 854 rutas y 3.260 pasos.

> **Regla que deja para el próximo borrado de un artículo**: discontinuar no alcanza si lo que se
> quiere es que deje de aparecer — un discontinuado sigue en las listas, en las auditorías y en las
> ideas, y cada sesión nueva lo vuelve a levantar. Si el dueño dice que no se fabrica más y no va a
> volver, **se borra con backup**, y se cierra la sección del conocimiento en vez de dejarla abierta.

### 4cr. El tipo de caja queda CERRADO; los precios esperan la lista del lunes (2026-09-13)

`[usuario, textual]` **"Corregí el tipo de caja. Los precios, me parece raro pero el lunes subo
los precios vigentes."** Dos cosas distintas que se venían mezclando:

**1. QUÉ CAJA usa cada artículo: cerrado.** Los 52 que se pisaron el 11-09 con la hoja "Cajas" de
`A_Costos_VIGENTES` **quedan como están, no se revierte nada**. La prueba que lo cerró no fue la
hoja Cajas sino la hoja **Costos**, que es la que calcula el costo del artículo: su columna **M**
(costo de caja por unidad) sale **por fórmula** apuntando a la hoja Cajas.

| artículo | fila en Costos | fórmula de M | valor | caja |
|---|---:|---|---:|---|
| 546 Corta Queso mgo Lk | 67 | `='Cajas '!G167` | 12,2017 | **N°22** |
| 315 Pisa Papas A. Inox | 112 | `='Cajas '!G97` | 30,00 | **N°12** |

Y los gemelos heredan de esas mismas celdas (546L y 118 Loke toman `M67`; el 121 Loke toma
`M112`; el 609 Chef y el 28 Chef también están en N°12). **Método a repetir:** cuando dos fuentes
discutan qué caja va, no mirar la hoja Cajas — mirar de qué celda la toma la hoja **Costos**.

**Impacto medido del cambio de los 52** `[dato]`: bajó el costo de caja **$47.636 por mes**
(bruto movido $131.076). Dos artículos explican $43.270 de ese bruto: el 546 (7.700 uni/mes) y el
315 (4.022 uni/mes); los otros 45 juntos mueven menos que el 546 solo.

**2. LOS PRECIOS de las cajas: NO TOCAR hasta la lista del lunes.** Se cruzaron los 12 precios de
caja de GP2 contra la planilla: **11 coinciden al centavo** (misma fecha de lista, 20-07-2026). El
único que no:

| | planilla | GP2 |
|---|---:|---:|
| Caja N°22 | 146,42 | **208,00** |

Si la planilla tuviera razón serían ~$39.500/mes de más sólo en el 546. **El usuario lo vio y
decidió esperar** — sube los precios vigentes el lunes. **Ninguna sesión debe "corregir" la N°22
antes de esa lista**: la diferencia probablemente sea un aumento que la planilla todavía no tiene,
no un error de carga.

**Lo único que sigue abierto del tema caja:** 9 artículos (789, 800, 823, 825, 840, 844, 845, 858,
862) piden **Caja N°8** o **Caja N°28**, que no existen como componente. Falta su **posición de
estantería** para crearlas — no se inventa. Y el batidor pera (544 y 802) queda en N°12 por
decisión del usuario, contra la N°6 que dice la planilla.

### 4cs. La Caja N°8 está DISCONTINUADA: el gemelo LK cierra los 9 que faltaban (2026-09-13)

`[usuario]` **"Fijate su equivalente en LK"**. Los 9 artículos que pedían una caja inexistente
quedaron resueltos **sin crear ninguna caja**, y la razón estaba escrita en el propio informe de
faltantes del 08-09: *"12 de 13; **la N°8 no va porque es discontinua**"*. La planilla la sigue
pidiendo, pero ya no se compra — y lo que GP2 tiene hoy es el reemplazo que usa el gemelo Loeke.

El mapeo Chef↔Loeke sale de la hoja **`Conversion cod Loeke Chef`** de `A_Costos_VIGENTES`
(columna **J** = Cod Loeke, **K/L/M** = Cod Chef 1/2/3). Vale la pena recordarla: es la fuente
oficial del gemelo y evita adivinarlo por descripción.

**6 de 9 ya estaban donde dice el gemelo — no se tocó nada:**

| Chef | pedía | gemelo LK | caja del LK y de GP2 |
|---|---|---|---|
| 789 Pisa Papas Nylon Con Mgo | N°8 | 355 | N°7 |
| 800 Pinza Corta Alambre 21 Cm | N°8 | 560 | N°2 |
| 825 Colador Ø 10 Cm | N°8 | 027 | N°2 |
| 844 Cuchara Fideos Nylon | N°8 | 391 | N°7 |
| 845 Cucharón Nylon | N°8 | 392 | N°7 |
| 840 Rallador Cilíndrico 21 Cm | N°28 | 321 | N°10 |

**Uno se corrigió:** el **862 Corta Pizza Familiar** estaba en Caja N°2 y su gemelo **562** va en
**N°22**, con la misma uni x caja (12). Migración `el_862_va_en_la_caja_22_como_su_gemelo_lk_562`
(artículo + receta + los dos pasos de ruta). El costo de caja baja de $21,82 a $17,33 por unidad.

**Dos quedan como están, a propósito:**
- **858 Pala De Canelones Ac. Inox.** — el gemelo 570 va en N°7, pero **la uni x caja no coincide**
  (858 de a 12, el 570 de a 24): no es el mismo empaque, así que el gemelo NO manda acá. Queda en
  N°12. **Regla: el gemelo sólo decide la caja si además coincide la uni x caja.**
- **823 Exprimidor De Cítricos** — es Loeke, no tiene gemelo. Queda en N°10.

**Con esto el tema caja queda cerrado del todo**, salvo los precios, que esperan la lista del
lunes (§4cr). Ya no hay ningún artículo pidiendo una caja que no exista.

### 4ct. El circuito del pincel YA ESTÁ EN LA BASE — y el número del cartón es el código del artículo (2026-09-13)

**Estado: dado de alta y verificado contra la base.** La §4co y la entrada de `[HISTORIAL]` del
13-09 decían *"NO SE DIO DE ALTA NADA todavía porque faltan tres datos que sólo tiene el dueño"*.
**Eso quedó viejo**: los tres artículos, los tres componentes y las ocho rutas están cargados. Esta
sección es la foto real, para que ninguna sesión vuelva a preguntar por lo que ya existe.

**Un solo insumo a granel que sale como TRES artículos** `[usuario 2026-09-13, textual: "590E se
stockea en Virgilio en cajas x600uni, que se le mandan a garcia para que las envase"]`. Lo que
separa a los tres **no es la pieza, es el envase**:

| Artículo | id | Empresa | Cartón | Caja | uni/caja | Familia |
|---|---:|---|---|---|---:|---|
| `590E` Pincel Silicona 11 Gms | 229 | LK | `CART590` | `A11` (Caja N°29) | 12 | Repostería |
| `890E` Pincel Silicona 11 Gms | 230 | Chef | `CART890` | `A11` (Caja N°29) | 12 | Repostería |
| `590ES` Pincel Silicona 11 gms s/Cartón | 231 | LK | **ninguno** | `A11` (Caja N°29) | 50 | Repostería |

**Los componentes** `[dato: GP2.componente]`: `PINCEL590` (id 910) *Pincel Silicona 11 gms
(granel)*, **Sector Plástico**, proveedor `Importado`, inventario en **Virgilio (Distribución)** —
que es donde se stockea; `CART590` (id 911) y `CART890` (id 912), **Sector Cartón**, inventario en
Sector Cartón. La **Caja N°29 = `A11`**, Sector Caja, proveedor Corrugadora del Plata.

**Las recetas** (`articulo_componente`) y **las 8 rutas**, una por insumo, todas con el tallerista
**Danica García (id 1)** y el patrón `insumo → tallerista → virgilio`, calcado 1:1 de los artículos
550/760:

| Artículo | Receta | Rutas |
|---|---|---|
| `590E` | PINCEL590 ×1 · CART590 ×1 · A11 ×1/12 (0,0833) | 964, 965, 966 |
| `890E` | PINCEL590 ×1 · CART890 ×1 · A11 ×1/12 (0,0833) | 967, 968, 969 |
| `590ES` | PINCEL590 ×1 · A11 ×1/50 (0,02) | 970, 971 |

**Base después del alta** `[dato]`: **191 artículos, 800 componentes, 862 rutas, 3.284 pasos**;
0 sin receta, 0 sin ruta, 0 componentes de receta sin inventario, y los 35 invariantes de
`db/verificar.sql` en 0.

#### La regla del número de cartón: 147 de 152, y las 5 excepciones dicen algo

**El número que lleva el cartón en su descripción es el código del artículo que envuelve.** Medido
sobre los 152 cartones de GP2 que tienen un número en la descripción: **147 de esos números son un
código de artículo de GP2**. Por eso `Cartón 590` y `Cartón 890`, y no un número inventado.

**Las 5 que no cierran no son ruido, son dos cosas distintas** `[dato 2026-09-13]`:

| Cartón | Código | Por qué no cierra |
|---|---|---|
| `Cartón 590` | `CART590` | El artículo es `590E`, con la E. El cartón es del pincel igual. |
| `Cartón 890` | `CART890` | Ídem con `890E`. |
| `Cartón 574` | `C1B` | **`574` no existe como artículo en GP2** — y está en el grupo A de los que faltan. |
| `Cartón 119` | `I3B` | **`119` no existe como artículo en GP2.** |
| `Cartón 809` | `O6A` | **`809` no existe como artículo en GP2** — también está en el grupo A. |

**Lo que deja como método:** un cartón cargado cuyo número no cruza con ningún artículo es **un
artículo que falta, no un cartón mal codificado**. Para el `574 Corta Queso Alambre` y el `809
Corta Queso Alambre Chef` el cartón **ya está**; lo que falta es el artículo. Eso baja el trabajo
de esos dos a la mitad y conviene mirarlo antes de darlos de alta desde cero.

#### Dos cabos sueltos del pincel, a propósito

1. **Faltan TRES precios, no uno.** `v_costo_componente` marca `faltan_precios` en `PINCEL590`,
   **`CART590` y `CART890`** (la §4co y el pedido original sólo nombraban el pincel). Consecuencia
   medida: los tres artículos dan **$166,86** de costo, que es **exactamente el costo de la caja
   `A11`** — o sea que hoy el pincel "cuesta su caja". No es que el pincel sea gratis: no tiene
   precio cargado. **Al mirar el costo de estos tres, leer `faltan_precios` antes de creerle al
   total** (la misma trampa que dejó §4cn con `BOM10`).
2. **`CART590` y `CART890` no tienen posición de estantería.** El código `CART###` es **provisorio**
   (precedentes `CART058`, `CART059`, `CART186`, `CART715`). La convención de la casa codifica el
   cartón **por posición** (`G2B` = Cartón 229, `G6B` = Cartón 299), así que el código definitivo
   sale de dónde se guardan, y eso lo tiene que decir el dueño. No se inventa.

#### Los dos cartones del pincel son FORMATO HUEVO — y eran los únicos de la casa sin formato (2026-09-13, misma noche)

`[usuario 2026-09-13, textual: "590/890 usan carton huevo" y "Chef tambien tiene formato huevo"]`.
Al leerlo, la primera lectura fue "un cartón compartido llamado huevo" — **estaba mal, y se retira**:
`Huevo` es un **`carton_formato`** de GP2 (el troquel: 25 posiciones por pliego, pedido múltiplo de
25.000, mínimo 2.000 por código, bolsa de 2.000) y ya lo usaban **36 cartones** (21 LOEKE, 15 CHEF;
ej. `C1B` Cartón 574 y `D5B` Cartón 867). Cada artículo sigue teniendo **su** cartón; lo que se
comparte es el formato. `[dato: GP2.carton_formato + planilla, hoja " Cartones" fila 429: 590E →
tipo 15 "Loekemeyer Huevo"; el 548 Pincel Pastelero usa el mismo tipo 15]`.

Lo que se aplicó (backup `zz_backups."GP2_Backup_carton_huevo_20260913"`, 2 filas, con RLS):

| Componente | id | `carton_formato` | `marca` | `proveedor` |
|---|---:|---|---|---|
| `CART590` Cartón 590 (590E, LK) | 911 | `Huevo` | `LOEKE` | Talleres Gráficos Pol |
| `CART890` Cartón 890 (890E, Chef) | 912 | `Huevo` | `CHEF` | Talleres Gráficos Pol |

**Eran los únicos dos cartones de todo GP2 con `carton_formato` y `marca` en NULL** (chequeo después:
0). Sin formato no entraban a la familia Huevo de `oc_bundle` / `_oc_validar_carton`, así que la OC
no les aplicaba los múltiplos. Proveedor Pol confirmado por el dueño (es el de los hermanos Huevo).
Invariantes en 0. **El cabo suelto 2 (posición de estantería) sigue abierto; el 1 (los tres precios)
también.**

### 4cu. La M78 es una convergencia (como la M135): qué entró, qué NO dio lo esperado y por qué (2026-09-13)

**Aplicado con "dale" del dueño**, en dos migraciones: `la_matriz_78_pasa_a_ser_una_convergencia`
(rutas) y `la_receta_del_rompenueces_pide_la_pieza_remachada` (receta + BOM). Respaldo:
`zz_backups."GP2_Backup_M78_20260913"` (58 filas: 38 `ruta_paso`, 4 `componente`, 4 `inventario`,
10 `articulo_componente`, 2 `precio_servicio_pieza`).

**El patrón de la casa para "una matriz que UNE varias piezas"** `[dato: 521/M135 y ahora 507-707/M78]`:
1. **Una ruta por rama de entrada**, todas con el **mismo paso de matriz** y la **misma pieza de
   salida** (521: K5, K8 y V3 → M135 → G4; 507: D6, D5 y V4 → M78 → `D5-M78`; 707: B1, B2 y V4 →
   M78 → `B1-M78`).
2. **`componente_bom` con la pieza de salida como padre** y las entradas como hijos (G4 ← K5+K8+V3;
   `D5-M78` ← D5+D6+V4; `B1-M78` ← B1+B2+V4).
3. **La receta del artículo pide lo que llega al tallerista**, no las partes (el 521 pide C16, que
   está aguas abajo de G4; el 507 pide `D5-M78`, el 707 `B1-M78`).
Las "mitades remachadas" que no existían (484 `D6-M78`, 487 `B2-M78`) se borraron; el remache V4
ahora pasa por la M78 en vez de llegar suelto al tallerista.

**Dos cosas que el pedido daba por ciertas y la base desmintió:**

- **"La M78 se cobra dos veces, el 507 y el 707 bajan ~$28,80."** [Seguro] Falso. `v_costo_componente`
  agrupa la mano de obra **por matriz** (`group by comp_id, matriz_id`), así que la M78 ya contaba
  una sola vez aunque hubiera dos pasos. Los costos del 507 (887,53) y del 521 (1.428,69) **no se
  movieron un centavo** con la migración; el 707 bajó por otra causa (el precio de Jade, abajo). El
  problema 113 diagnosticó bien la forma (dos pasos paralelos) y mal el síntoma (la plata).
- **"La simulación tiene que dar `colgado = []`."** [Seguro] Inalcanzable para *cualquier*
  convergencia: `__sim_articulo` corre cada ruta entera, así que tres ramas producen tres veces la
  pieza de salida y el tallerista consume una. **El testigo 521 deja exactamente lo mismo**
  (`C16 +240`). El criterio correcto es "se comporta como el 521": `a_virgilio = 120` y lo colgado es
  sólo la pieza de salida en positivo. Las piezas sueltas en negativo (D5, D6, V4 a −120) sí eran el
  bug, y desaparecieron con la receta.

**Precio de Jade: por el rompenuez entero, no por mitad** `[usuario 2026-09-13: "Me da que 305 cuesta
pintar entero"]`. Lo confirman dos cosas: la planilla dice *"Rompenueces Pintado"* $305 en una sola
línea (fila 654) y para el cromado dice explícito *"Abierto o Cerrado"* por kg (fila 740); y las
otras 12 piezas que pinta Jade valen $127 o $150 — las mitades a $305 cada una eran el doble del
máximo. Corregido a **$152,50 por mitad** (ids 71 y 72): el 707 pasa de 1.264,56 a **959,56**. La
diferencia real 507/707 son ~$72: cartón (−22) y pintar vs cromar (+94). Auditoría: problema 114.

**Hallazgo de paso, NO corregido (para el auditor de costos):** [Probable] el motor deduplica
aristas del grafo (`wd` = distinct sobre entrada/salida/paso). Las dos mitades del rompenuez salen
del **mismo fleje IE10 vía M73**, así que el fleje y la M73 se cuentan **una** vez para las dos. El
507/707 está **sub**-costeado en una mitad de fleje + una pasada de M73. Es anterior a esta
migración (las rutas 45/46 ya compartían esa arista) y afecta a cualquier artículo cuyas ramas
convergentes arranquen del mismo insumo.

**Se borró `db/pendiente/2026-09-12_mb_color_y_matriz78.sql`**: la parte (a) (colores de Master
Bach) ya estaba aplicada y la (b) es esto. `db/` no cambia: fueron migraciones de datos, no de schema.


### 4cv. La Versión Tablet: el contrato lo manda la base, y dos trampas de unidad (2026-09-13)

**Qué pasó.** Una sesión construyó la "Versión Tablet" (una pantalla con Enviar / Recibir / Conteo
para la tablet del galpón) y **su código se perdió**: la rama nunca llegó a `origin`. Pero el backend
**sí quedó vivo en la base**: `GP2.alerta_recepcion`, `tablet_bundle()`, `tablet_registrar(p)`,
`alerta_recepcion_marcar(...)` y `alertas_bundle()` con la clave `recepcion_de_mas`. Es exactamente el
desfasaje que el CLAUDE.md marca como el peligro real (la base adelantada, `main` sin el código). El
frente se **rehízo leyendo el cuerpo real de las funciones** (`pg_get_functiondef`), no la memoria de
lo que "debería" devolver. `[dato: base, 2026-09-13]`

**Lo que fija el contrato** (el detalle en `GP2_MAPA.md`, sección "Versión Tablet"):
- `um` en el bundle es `componente.unidad_medida`: **`'kg'` o `'unidad'`**; `tablet_registrar` acepta
  **`'uni'` o `'kg'`**. La pantalla traduce. Un `'unidad'` mandado crudo revienta con "Unidad invalida".
- `ref` es **texto** siempre (el id como string, el nombre del proveedor de insumo, o `'virgilio'`), y
  **el prov. AT viene con `ref = '*'` en `enviar`**: cualquier cartón/caja va a cualquier prov. AT.
- El **esperado** sale de la OC si trae un proveedor (`oc`; **null si no hay OC**, y sin esperado no
  hay alerta), y del stock online si trae un tallerista / PS (`online_tall` / `online_ps`) o Virgilio.
- Desde la tablet **no se le envía** a Virgilio ni al proveedor de insumo; el PS exige
  `comp_entrada_id` (el SC que consume); `tablet_registrar` no acepta `modo = 'conteo'`.

**Las dos trampas de unidad** `[usuario, vía la sesión perdida; verificado contra las RPC]`:
1. **El proveedor de artículo terminado entrega CAJAS.** `crear_entrega_prov_at` pide `p_cajas`. La
   pantalla carga cajas, muestra "= N uni x caja", y manda `cantidad` = cajas con `unidad 'uni'` y
   `por_caja`; la base compara `cajas × por_caja` contra la OC, que está en unidades.
2. **Una pieza en kg se manda y se recibe en kg** (fleje cortado, chapa, el 1686 de Eclipse): teclado
   decimal con coma, y `unidad 'kg'` en el payload. Mezclar kg con uni en esas piezas es lo que hacía
   imposible recibir CV18D / V18D / V20 (§ kg ↔ uni en `gp2-numero.js`).

**La alerta de "recibí de más" avisa pero no frena** `[usuario, vía la sesión perdida]`: la base
registra el movimiento **primero** y la alerta **después**; la pantalla marca la fila, dice "podés
registrar igual" y deja el botón habilitado. Quien revisa lo hace en Alertas (bloque "Se recibió de
más", botón Revisada → estado `vista`) y el menú muestra cuántas quedan sobre el botón Alertas.

**El Conteo no escribe.** Compara lo contado contra el online del sector y baja un CSV. El ajuste de
stock sigue el circuito de siempre — Relevamientos (el operario cuenta) → Validación de Stock (el
operador del sistema decide) — y `tablet_registrar` no tiene un modo para eso.

**Deuda que quedó en el backend, NO en la pantalla** (idea 7345): para recibir de un **tallerista**
`tablet_registrar` llama a `crear_entrega_tallerista`, y el propio `comment` de esa función dice que
**no es el motor** (el motor es `gp2-motor.js` + `registrar_movimientos`, idea 7316). Se documenta y
se deja abierto: esta sesión no podía tocar la base.

### 4cw. Cruce contra loekemeyer.com: 11 artículos activos sin despiece — y la Est Madre miente con el 515 (2026-09-13)

**Pedido del dueño:** *"Revisá loekemeyer.com. Revisá si te falta el despiece de algún artículo."*
La página no se puede leer desde la sesión (el proxy la bloquea), así que se cruzó **la fuente de
la página**: `public.products` del proyecto LK (`kwkclwhmoygunqmlegrg`), que es lo que el sitio
muestra `[dato 2026-09-13]`.

**Universo:** 264 productos, **199 activos** = 87 importados (terminan en E, reventa: fuera de GP2
por diseño, §4cm) + **112 propios**. De los 112, **101 tienen despiece en GP2** (0 sin receta, 0 sin
ruta) y **11 no**:

| Cód | Artículo | uni/mes Est Madre | Estado en GP2 |
|---|---|---:|---|
| 515 | Batidor Resorte | 486 | **borrado el 13-09** por orden del dueño (§4cq) — **ver abajo** |
| 332 | Espátula Calada Ac. Inox | 136 | "discontinuo → 941E-948E" (dueño, §4cp) |
| 509 | Pala Batidora | 104 | grupo A, Carlos; el vecino tampoco lo despieza |
| 396 | Enrulador de Manteca | 80 | grupo A, sin tallerista |
| 335 | Cuchara Calada Ac. Inox | 64 | "discontinuo → 941E-948E" |
| 573 | Bombilla Colores Metalizados | 52 | **nuevo**: no figuraba en ningún listado, sin despiece en el vecino |
| 337 | Pinche Ac. Inox | 48 | "discontinuo → 941E-948E" |
| 537 | Pela y Pica Ajo | 0 | pendiente a propósito (dueño) |
| 567 | Corta Palta | 0 | ídem |
| 556 | Sacayerba | 0 | **nuevo** |
| 517 | Pinza Acero Inox 25 cm | 0 | **nuevo** |

**Contradicción que se le mostró al dueño:** 515, 332, 335 y 337 están **activos en la página** y
GP2 los tiene como borrado / discontinuos. Su respuesta sobre el 515 `[usuario 2026-09-13, textual:
"No hay chance que se venda 486 uni de 515"]` → **la proyección de la Est Madre para el 515 es
falsa** y el borrado queda como está. **Regla que deja:** `GP2.est_madre.proy_uni_mes` no es
evidencia de que un artículo se vende — proyecta sobre lo vendido histórico y arrastra
discontinuados (§4cp ya lo decía para los 46 candidatos; el 515 es el caso más grande: 486 uni/mes
de un artículo que ya no se fabrica). Antes de usar ese número para decidir un alta, mirar ventas
reales recientes o preguntarle al dueño. Los otros tres inox (332/335/337) y los tres códigos nuevos
(573, 556, 517) siguen sin decisión del dueño; 509 y 396 siguen en el grupo A.

**Lo que NO cambia:** los 45 propios inactivos de la página no se miran (no se venden); los 87 E
no van a GP2.

## 4cx. Los palos de amasar 231/232/233: caja, bandita y quién los termina (2026-09-13)

**Decisión del dueño, textual:** *"231 y 232 van en misma caja que 234"* · *"1 ponele la 15"* ·
*"2 ponele 12 a los 4 items"* · *"3 si"*. O sea: **los cuatro palos** (231 de 30 cm, 232 de 40 cm,
233 de 50 cm y el 234 Palo Francés de 40 cm) van en la **Caja N°15** (`A9B`, componente 604, Sector
Caja) y **12 unidades por caja**. Antes los tres primeros tenían la caja vacía y decían 24. `[usuario]`

**Cómo es el circuito** `[usuario, reconstruido con la base]`: Tierra Nativa vende el palo hecho, se
guarda en el garage como `GRJ22/23/24`, y **Fábrica le pone la bandita y lo entrega en Virgilio**.
Por eso la ruta de cada palo es la misma forma de siempre: `insumo → Fábrica → virgilio`, tres pasos.

**La bandita no existía en la base y se creó**: componente `BANDITA` id **916**, Sector Cartón,
marca LOEKE, unidad `unidad`, inventario en Sector Cartón arrancando en 0. Va **×1 en los tres
palos**, y **el 234 NO la lleva** — ésa es la única diferencia de receta entre el francés y los otros
tres. `[dato: articulo_componente 917–922, rutas 972–977, pasos 3726–3743]`

**Tres cosas que quedaron sin resolver y conviene no re-descubrir:**

1. **Quién provee la bandita: no se sabe.** El componente quedó con `proveedor = NULL` a propósito.
   En la planilla hay tres candidatos y **ninguno dice "palo de amasar"**: Gráfica Pol "Bandita
   Ralladores" $8.250 y "Banditas 35 × 194 mm" $8.250 (las dos con col C = "Falta Prov"), y López
   José Daniel "Super Bands Bolsa N°15 (Bandita Negra)" $1,08 la unidad. Elegir a ojo es inventar.
2. **El máximo de la bandita queda NULL** porque **231/232/233 no están en `est_madre`** (el 234 sí,
   396 uni/mes). Sin demanda cargada, `recalcular_maximos_insumos()` no tiene de dónde sacar el
   máximo. No es un bug: es que falta el dato de cuánto se vende de cada palo.
3. **`articulo_prov_at` todavía dice que Tierra Nativa entrega los tres TERMINADOS** (ids 92/94/95,
   activos). **Eso contradice lo que explicó el dueño** (Tierra Nativa vende el palo, la bandita la
   pone Fábrica). Mientras siga activo, una entrega de Prov AT de un 231 descontaría GRJ22 + A9B +
   BANDITA desde la ubicación 54 (Prov. Art. Term. Tierra Nativa), que está vacía, y la dejaría en
   negativo. **Desactivarlo es una línea, pero es una pregunta, no una deducción.** `[deducido]`

**Costo:** los tres siguen con `faltan_precios` ≥ 2 (los `GRJ22/23/24` no tienen precio y la bandita
tampoco), así que lo único que hoy suma al costo es la caja ($28,69 por unidad). En la lista de
precios sólo están "Palo de Amasar Frances 40cm" $600 y "Torneado Palo de Amasar 40cm" $1.245, los
dos de Tierra Nativa: **no hay precio para el 30, el 40 ni el 50 lisos**. `[dato: v_planilla_precio]`


**Corrección al punto 3, medida el 2026-09-13 a la tarde (segunda vuelta):** eran **cuatro** filas,
no tres — el **234 (id 93)** tiene el mismo agujero, misma ruta `insumo → Fábrica → virgilio` y
mismo proveedor. Y el `activo=false` **no cierra la puerta del todo**: ver §4cy. `[dato]`

**Y la respuesta del dueño al punto 3, textual (2026-09-13): *"es la misma lógica que lo de cimarron
con las bombillas que entrega en cervantes"*.** Con eso la pregunta se cierra: **los palos son una
COMPRA DE INSUMO, no una entrega de Prov AT.** La base ya lo dice — `GRJ22/23/24` y `GRJ17` son
Sector Garage, proveedor de insumo Tierra Nativa, stock en Sector Garage, `estado_compra` NULL,
**exactamente la misma forma que `GRJ4` (Bomb AutoLimp Inox, proveedor Cimarrón)**: Cimarrón entrega
la bombilla en Cervantes, se guarda en el garage como GRJ y recién después alguien la termina y la
manda a Virgilio. El palo es eso mismo con Tierra Nativa y con Fábrica poniendo la bandita.

**Consecuencia:** las 4 filas de `articulo_prov_at` de los palos (ids 92/93/94/95, los tres + el
**234**) no describen nada real y hay que desactivarlas. De Tierra Nativa como Prov AT queda sólo el
**591** (Despolvillador), que sí entra terminado y tiene su paso `proveedor_at` en la ruta 956.
**Regla que deja: un proveedor puede ser las dos cosas a la vez** — insumo para unos artículos y
Prov AT para otros —, así que la pregunta correcta nunca es "¿qué es este proveedor?" sino "¿qué
llega de él para ESTE artículo: una pieza al garage, o el artículo terminado a Virgilio?". `[usuario]`

## 4cy. `articulo_prov_at` no garantiza nada, y `activo` sólo lo ve la pantalla (2026-09-13)

Salió de traer al dueño la pregunta del punto 3 de §4cx. Lo que apareció es más grande que los palos.

**1. La forma correcta de "entra terminado" es un paso `proveedor_at` en la ruta, no una fila en
`articulo_prov_at`.** El testigo bien modelado es el **591**: ruta 956 = `A4 (insumo) → proveedor_at
13 → virgilio`. `[dato]`

**2. De las 91 filas de `articulo_prov_at`, 34 son artículos de GP2 cuya ruta NO tiene ese paso**
(Cabral 26, Tierra Nativa 4 = los cuatro palos, Maspoli 3, Pettofrezza 1) y otras 12 ni siquiera
son artículos de GP2. Las 45 restantes están bien. **Los palos no son la excepción, son 4 de 34.**
`[dato]`

**3. Qué pasa si se registra una entrega de una de esas 34:** `crear_entrega_prov_at` delega en
`recepcion_virgilio`, que consume **toda la receta** desde `ubic_de('proveedor_at', N)`. La
ubicación 54 (Tierra Nativa) **no tiene ni una fila de inventario**, así que todo queda en negativo.
Con las 26 de Cabral es peor: el 501 arrastra 14 rutas. Hoy no pasó nunca (0 entregas en esas 34).
`[dato]`

**4. La trampa fina: `activo=false` saca el artículo de la PANTALLA, no de la RPC.**
`entregas_prov_at_bundle` filtra `coalesce(a.activo,true)` y `EntregasAT_GP2.html` es la única
pantalla que llama a `crear_entrega_prov_at` — así que para un operario la puerta queda cerrada.
Pero la RPC misma chequea **existencia de la fila, sin mirar `activo`** (el `if not exists` se
aflojó a propósito en su momento, por 5 filas con `descripcion` vacía — aquello era por
`descripcion`, no por `activo`, así que agregarle `and coalesce(a.activo,true)` no revive ese bug).
**Regla: antes de decir "con desactivarlo alcanza", leer la función con `pg_get_functiondef`, no
`db/`.** `[dato]`

### La respuesta del dueño sobre Cabral: NO es Prov AT, y el 031 es un respaldo (2026-09-21)

Cerró el punto 2 de arriba (las 26 filas de Cabral sin paso `proveedor_at`). Textual:
*"Cabral saca todo, solo el 031 se puede llevar a hacer (en caso de que no llegue ijupa con
todos los pedidos)"*. `[usuario]`

- **Cabral sale del padrón de Prov AT.** Las filas de `articulo_prov_at` contra Cabral no
  describen de dónde viene el artículo: de los 32 activos, **26 se fabrican adentro** (el 031 entre ellos) y su ruta lo
  dice (matriz + proveedor de servicio + tallerista → virgilio, sin ningún paso `proveedor_at`);
  el **574** ni siquiera existe en `GP2.articulo`. `[dato]`
- **El 031 (Filtro de Café 10cm) lo hace IJUPA**, tallerista 10, en sus 3 rutas. A Cabral se le
  *lleva a hacer* sólo cuando IJUPA no llega con los pedidos: es contingencia, no el circuito
  normal. Por eso el 031 es el único que queda. `[usuario]`
- **Encaja con lo ya sabido**: Cabral aparece en el archivo de cartones como proveedor de la
  **bolsa de filtro** ($39,32 contra los $63 de Vihal) — o sea que es un proveedor real, pero del
  insumo del filtro, no del artículo terminado. `[dato]`

**"Todo" es todo: las 5 con ruta real también salen.** `[usuario 2026-09-21]` Lo contestó sin
que hiciera falta repreguntar, mirando la tablet: *"cuando voy a enviar a prov de art terminado no
me aparece la cja y carton de 031 nomás"* — o sea, esperaba ver **sólo** la caja y el cartón del
031 y seguía viendo las 39 piezas de los 32 artículos. **Ejecutado con su "sí"**: 31 filas a
`activo=false`, queda el **031**. Verificado: Cabral pasa de 39 piezas a 2 en Enviar
(`A1B` Cartón 031 + `A9` Caja N°22) y de 32 artículos a 1 en Recibir.

**La pantalla de Enviar sale de `articulo_prov_at`, NO de la ruta** — por eso desactivar alcanzó
para que la tablet haga lo que él quiere. Es el cruce `articulo_prov_at → articulo →
articulo_componente` que puso el fix v1.3.1 de la tablet (2026-09-15). `[dato]`

**El `activo=false` NO toca las rutas, y de ahí salió el reclamo del día siguiente.** El dueño
abrió el despiece del 246 en `Programa.html` y vio "Maspoli **o** Cabral": *"te dije que solo
entrega el 031… ¿por qué sigue apareciendo acá en el 246?"*. **El despiece lee `ruta_paso`, no
`articulo_prov_at`** — medido con `pg_get_functiondef`: `programa_bundle` ni nombra al padrón. Son
dos libros distintos y hay que tocar los dos. `[dato]`

**Resuelto el 2026-09-21 con el sí del dueño** (*"Si"* + *"Ni siquiera lo tenés que poner. En el
031"*): se borraron las **7 rutas** de Cabral de 223 (915, 924), 224 (917, 926), 246 (929) y 577
(921, 935) —21 pasos— y la fila del **031** pasó a `activo=false`. **Cabral queda en 0 filas
activas y 0 rutas** en esos cuatro. Verificado: 223 y 224 siguen con Pintos (2 rutas cada uno),
246 con Maspoli y 577 con Pettofrezza; **0 rutas huérfanas**. La `ubicacion` 34 (Prov. Art. Term.
Cabral) se deja: guarda el historial y no se ve en ninguna pantalla. `[dato]`

**El 338 fue el único que frenó, y el dueño lo contestó: lo entrega Alex Escalante** (tallerista
2, activo) — primero dijo "Carlos" y se corrigió en el mensaje siguiente. Sus 2 rutas (920 por la
caja `A2`, 934 por el cartón `K5B`) son las **únicas** que le quedan a Cabral, y se dejaron vivas
a propósito: borrarlas antes de reasignarlas dejaba al 338 sin ninguna ruta. **Pasa de Prov AT a
tallerista**, el mismo movimiento que la otra sesión le hizo hoy al `070` (de `proveedor_at`
Pettofrezza a tallerista Fábrica, §4eq). `[usuario 2026-09-21]`

⚠ **Lo que ese cambio deja al descubierto: la receta del 338 es SÓLO envase** (caja `A2` + cartón
`K5B`), sin ninguna pieza de producto. Eso es normal en un artículo que se compra terminado, pero
con un tallerista significa que Alex "produce" la espátula de la nada y **lo que entra nunca llega
al costo** — exactamente la trampa de §"El paso de tallerista tiene que declarar QUÉ ENTRA".
Preguntado: de dónde sale la espátula lisa que Alex envasa. `[deducido, sin confirmar]`

**También sin respuesta: qué es "llevar a hacer" el 031.** Si Cabral nos vende el filtro terminado
es un paso `proveedor_at` en una ruta alternativa; si le mandamos las partes y él arma, es un
tallerista o un proveedor de servicio, y `articulo_prov_at` no es el lugar. Hoy el 031 quedó en
`articulo_prov_at` **sin** paso `proveedor_at` en ninguna de sus 3 rutas, que siguen siendo de
IJUPA: es justamente la forma que §4cy punto 1 llama mal modelada. Se deja así a propósito hasta
que el dueño defina el circuito.

### Cuáles artículos de Prov AT están modelados en GP2 y cuáles no (2026-09-21)

El dueño preguntó *"de todos los artículos que me mandaste que arman los proveedores de artículos
terminados decime cuáles tenemos modelados… porque por ejemplo en paternal goma está la espátula
goma, como no lo tenemos en GP2 no me interesa verlo"*.

**Su ejemplo estaba equivocado y conviene dejarlo escrito para no repetirlo: el 618 y el 619 de
Paternal Goma SÍ están modelados** — existen en `GP2.articulo`, tienen ruta con paso
`proveedor_at` y figuran en `est_madre`. Lo que tienen es **demanda mínima (2 y 20 uni/mes)**, que
no es lo mismo que no existir. Antes de dar de baja algo "porque no lo tenemos", mirar
`est_madre`: un artículo de 2 uni/mes se lee como inexistente y no lo es. `[dato]`

**De los 56 códigos activos de `articulo_prov_at`, 45 son artículos de GP2 y 11 no.** Los 11, por
demanda mensual (`est_madre.proy_uni_mes`): `565` Pinza de Hielo (Manfer, 528), `110` Colador N°8
(López José, 384), `111` Colador N°10 (López José, 296), `193` sin descripción (Kuffo, 176), `112`
Ø16 Env. (López José, 160), `852` Pinza de Hielo 14 (Manfer, 7), `830` Colador Ø20 (López José,
3), `828` Colador Ø16 (López José, 2), y sin demanda `029` Colador N°16 (López José), `122`
Rallador Cilíndrico (Carriero) y `554` Cucharita Matera (Melinox). **Los 8 primeros se venden y no
existen como artículo en GP2**; los 3 últimos no están ni en la Est Madre. `[dato]`

**Por proveedor, el peor es López José: 6 de sus 10 sin modelar.** Manfer 2 de 2, Kuffo 1 de 1,
Carriero 1 de 3, Melinox 1 de 2. Completos: Pintos (13), Pettofrezza (10), Maspoli (7), The Plast
(4), Paternal Goma (2), Tierra Nativa (1) y Cabral (1, el 031). `[dato]`

**Sospecha a confirmar con el dueño: `026`/`027` y `110`/`111` parecen el MISMO colador con dos
códigos.** 026 (Ø8) y 027 (Ø10) existen en `GP2.articulo` pero **sin** fila en `est_madre`; 110
(N°8) y 111 (N°10) tienen la demanda pero **no** existen en `GP2.articulo`. Si son el mismo
producto no faltan dos artículos: falta unificar el código. Mismo patrón posible en 029/828 (Ø16)
y en 112. `[deducido, sin confirmar]`

### Tanda de bajas del padrón de Prov AT (2026-09-21). El padrón queda en 48

El dueño repasó la lista limpia de 45 artículos y corrigió cuatro cosas de corrido. Todo
ejecutado con su *"Sí, corré"*.

**1. Maspoli NO entrega terminado el 508, 518 ni 564: sólo el mango, y lo entrega en Cervantes.**
*`[usuario]`: "508, 518, 564 no los arma Maspoli. Solo el mango entrega en Cervantes (por ejemplo
PC12)"*. **La ruta ya lo decía bien y la fila del padrón mentía**: las tres rutas tienen a
**Maspoli SRL como `proveedor_servicio`** (508: `D13 → PC12`, 518: `D13 → PEP7`, 564: `D13 →
PEP8`) y después van al tallerista; ninguna tiene paso `proveedor_at`. Se desactivaron las 3
filas. **Maspoli queda como Prov AT sólo de 246, 900, 222 y 910.** `[dato]`

**2. Discontinuados: 618, 619 (Paternal Goma), 761 (Melinox) y 591 (Tierra Nativa).** Se marcó
`discontinuado=true` en `articulo` **y** en `componente` (el terminado), se desactivaron sus filas
del padrón y los tres proveedores quedaron `activo=false` como Prov AT. **No se borró nada**: el
dueño dijo "eliminá", pero `discontinuado` es el mecanismo de la casa —conserva componente, receta
y ruta, y sale de la OC y de las pantallas de compra— y se revierte con un update. Los cuatro
tenían 0 entregas registradas. ⚠ **El 591 proyecta 398 uni/mes en la Est Madre** (los otros tres:
618 = 2, 619 = 20, 761 = 32): se avisó antes de ejecutar y el dueño lo reafirmó. Si más adelante
alguien se pregunta por qué un artículo con esa demanda está discontinuado, la respuesta es que
fue deliberado. `[usuario 2026-09-21]`

**3. El reclamo del 222 ya estaba resuelto cuando llegó.** *"El 222 no aparece la ruta en el
despiece para mandarle caja y carton y si le mandamos"*. Medido: el 222 tiene **4 rutas** —cartón
`M2B` y caja `A2`, una por Pintos y otra por Maspoli—; las dos de la caja (980, 981) tienen id
alto, o sea que se crearon después del resto, casi seguro en la tanda de la sesión paralela del
mismo día. **Y no hay más casos**: ni un componente de receta sin su ruta de insumo en ningún
artículo con paso `proveedor_at`. `[dato]`

⚠ **El hueco que SÍ queda es el otro: 9 artículos de Prov AT cuya receta no tiene cartón** (sólo
caja). Con las bajas de hoy quedan **5**: `246` y `900` (Maspoli), `823` (Pettofrezza), `922`
(Pintos) y `326` (The Plast). El 326 y el 922 tienen evidencia fuerte de que les falta —su gemelo
de la otra marca sí lo tiene (848 y 223)—; los otros tres hay que confirmarlos uno por uno, porque
puede que alguno vaya sin cartón de verdad. `[dato]`

**4. El circuito real de los tapones de Pettofrezza** `[usuario 2026-09-21]`: *"575, 579, 817,
816: le damos v15 y él entrega cada art que requiere una unidad por item de v15"*, y el **577**
*"le damos v15 y LEV serig: es un componente que inyecta Pettofrezza Rafael (lev sin serigrafear)
y lo mandamos a Ximpa (Julio Hernandez) a serigrafiar"*.

- **`V15` = remache de hierro, Sector Remache (8), proveedor Bella Vista.** Rompe el patrón de los
  otros remaches, que son `CVx` crudo → Guazzaroni → `Vx` niquelado: **el V15 se compra ya hecho**,
  sin paso de niquelado.
- **`LEV` = levas, Sector Plástico (6), las inyecta Pettofrezza Rafael**; el serigrafiado lo hace
  **Hernández Julio** (`proveedor_servicio` 8), que es el "Ximpa" del dueño.
- **Ninguno de los dos existe todavía en GP2** — hay que darlos de alta con la cadena completa
  (componente → inventario → receta → ruta).
- **Y esto reclasifica a Pettofrezza:** si le mandamos el V15 y él devuelve el artículo armado,
  es un **tallerista** (Pettofrezza Rafael, id 11, activo), no un Prov AT — el Prov AT es el que
  nos vende el producto hecho. Mismo movimiento que el `070` (§4eq) y que el 338 con Alex.

## 4cz. El cruce de la lista de precios se hace por `cod_isis`, no por el nombre del producto (2026-09-13)

Se buscó el proveedor de **`PEST1`** (Insertos Mango de Madera, 768, el único insumo comprable sin
proveedor) y por texto no aparecía: en el bloque de Pat Bet Plast la línea se llama **"Insertos
Importados"**. Cruzando por `cod_isis` aparece que **es el mismo artículo**: `4776` lo cotizan
**Pat Bet Plast a $90,26** (última compra 28-11-2025) y **Kollplast a $219,97** con el nombre
literal **"Inserto Mgo Madera"**. `[dato: v_planilla_precio]`

- El hermano `PEST2` (Insertos Pisa Papas, 735) ya está en **Pat Bet Plast**, mismo sector y **mismo
  `material_id` 742** (PP 2630). Kollplast cotiza los dos códigos (4776 y 3096): es la alternativa
  de Pat Bet Plast en toda la línea, no un proveedor suelto.
- **La plata:** PEST1 consume 684 uni/mes → la diferencia entre los dos precios es **$1,06 M por
  año**. Elegir "el que suena parecido" acá cuesta plata de verdad.

**DECISIÓN DEL DUEÑO (2026-09-13, textual): *"PEST 1, KollPlast. pero deja registrado que a partir
de noviembre aprox no se debería inyectar más"*.** Aplicado: `GP2.componente` 768 `proveedor =
'Kollplast'` (antes NULL). Verificado con SELECT; invariante `A2` sigue en 0 (Kollplast ya tenía
ubicación de inyector, la 60) y el costo no se movió porque **PEST1 no tiene fila en
`precio_proveedor`** (sigue `faltan_precios = 1`). Después del cambio, el único insumo comprable sin
proveedor es `BANDITA`. `[usuario + dato]`

**⏳ PEST1 se deja de inyectar alrededor de NOVIEMBRE 2026.** Es un insumo con fecha de vencimiento:
va en los 7 artículos `941E`–`948E` (684 uni/mes) y cuadra con que esos siete son **importados** —
la LP los tiene comprados hechos a Tierra Nativa a USD 1,36. Qué hacer llegado noviembre, y qué NO
hacer antes: `[usuario]`
- **No cargarle precio nuevo ni stock mínimo pensando en el largo plazo**, y mirar con desconfianza
  cualquier OC de PEST1 con horizonte mayor a esa fecha (el sugerido es `máximo − stock`, y su
  máximo hoy son 2.736 uni de `est_madre`: eso es más de lo que va a consumir).
- Cuando se confirme, **`estado_compra` pasa a `discontinuo`** y hay que revisar las 7 recetas y las
  7 rutas antes de tocar el componente (no se borra: tiene recetas y rutas colgando, misma regla que
  `GRJ21`).
- El inventario de PEST1 hoy está en **−372 uni** (stock inicial nunca cargado). Si se discontinúa
  sin cerrar ese negativo queda arrastrando para siempre.

**Regla que deja: para encontrar un insumo en la lista de precios, cruzar por `cod_isis` y recién
después por texto. Dos proveedores con el mismo `cod_isis` son dos alternativas del mismo artículo**
(igual que los dos Prov AT de §4bk), no un duplicado a limpiar. `[deducido]`

## 4da. La caja puede estar en el FK y no estar en la receta: $821.628 al año sin costear (2026-09-13)

`GP2.articulo.componente_caja_id` dice **qué** caja usa el artículo; lo que hace que la caja **cueste**
es su línea en `articulo_componente` (y su ruta). **175 de los 189 artículos con caja la tienen en la
receta. 14 no**, y en esos 14 la caja vale $0 en `v_costo_componente`: `[dato]`

| Art | Caja | uni x caja | $/mes sin costear |
|---|---|--:|--:|
| **222** | A2 | 12 | **32.580** |
| 312 | A2 | 12 | 9.420 |
| 395 | A8 | 12 | 8.509 |
| 943E · 942E · 948E · 945E · 944E | A2 | 12 | 16.200 (los cinco) |
| 311 | A2 | 12 | 1.020 |
| 910 | A2 | 12 | 720 |
| 715 | A1 | 24 | 20 |
| 818 · 058 · 059 | A4 / A9 | 12 | 0 (sin Est Madre) |

**Total $68.469/mes = $821.628/año.** El más caro no es ninguno de los que se estaban mirando (los
94xE): es el **222**, que solo explica casi la mitad.

**APLICADO el 2026-09-13 (dueño: *"cajas, dale"*).** Las 14 cajas entraron a la receta a
`1/articulos_por_caja` y cada artículo recibió su ruta de caja `insumo → <su actor> → virgilio`,
calcada del 223 (el actor NO se inventó: se copió del paso que ya cerraba cada artículo). **222 y
910 llevan DOS rutas de caja cada uno** porque tienen dos alternativas de Prov AT (Maspoli y
Pintos) y la regla §4bk dice que cada alternativa lleva su caja; los dos declaran `n_caja` NULL,
así que las dos rutas van con A2. Total: **14 recetas (923–936), 16 rutas (978–993), 48 pasos
(3744–3791)**. Snapshot previo en `zz_backups."GP2_Snap_costos_cajas_20260913"`. Invariantes
35/35 en 0. **Ya no queda ningún artículo con caja en el FK y sin línea de receta.** `[usuario + dato]`

**⚠ PERO EL COSTO NO SUBIÓ $30 POR UNIDAD: SUBIÓ $360. Ver §4dc — el bug es de la vista, no de la
receta.**

**Regla: `componente_caja_id` sin línea de receta es un costo que no existe. Al tocar la caja de un
artículo, verificar las dos cosas** (es la misma regla de "completar tablas manteniendo la
normalización", aplicada a la caja). `[deducido]`

## 4db. Los cubiertos inox 332-337 se reemplazaron por los 94xE, y el sitio quedó viejo (2026-09-13)

`[usuario 2026-09-13, textual]` *"332/7 y 630/7 son discontinuos. Se reemplazaron por 941/8E"*.
**332, 335 y 337 no están "discontinuados en GP2": no existen en `GP2.articulo`.** Aparecen en
`est_madre` (136 / 64 / 48 uni/mes) porque la Est Madre arrastra discontinuados — la misma trampa
del 515 (§4cw). Que loekemeyer.com los muestre activos es trabajo del repo del sitio, no de GP2.
`[dato]`

**Y lo de "573, 556 y 517 no tienen despiece en ningún lado" era falso para dos de los tres:**
`[dato: GP2.planilla_fila]`

- **573 Bombilla Color Metalizado** — despiece completo en la hoja **Bombillas** (fila 2, *"ART:
  755/L573"*): caño 135 mm + resorte + niquelado + tapón aluminio + anodizado + corte cañito =
  $578,98, con tiempos. Gemelo Chef **755**.
- **517 Pinza Gastronómica** — despiece completo entre **Materiales Loeke** (filas 166-167: pala
  121,3 × 0,8 y manija 167,3 × 0,8, las dos `517D`, tallerista **GUILLE**) y **Remaches** (fila 54:
  **SR1 + SR2 + SR3**). Lo que está roto es su fila en Materiales (`#REF!`) y que no figura en Costos.
- **556 Sacayerba** — el único sin despiece de verdad: Costos fila 225 dice `Fab` pero con
  `E='xx'`, o sea **lo costea sólo como envase** (cartón 89 + caja 10,91 + 5,90 = $105,81). Ni la
  planilla sabe de qué está hecho.

**Regla: antes de decir "no tiene despiece", buscarlo en la hoja del RUBRO** (Bombillas, Materiales
Loeke, Remaches, Flejes, Plásticos), no sólo en Costos y Cartones. Un artículo puede estar
despiezado en tres hojas y en ninguna de las dos que uno mira primero. `[deducido]`


## 4dc. `v_costo_componente` cobra la CAJA ENTERA por unidad: ARS 38,5 M por mes de sobrecosto (2026-09-13)

**Salió de medir el efecto de cargar las 14 cajas de §4da.** Se esperaba que el 942E subiera $30
(la caja de $360 dividida por 12). **Subió $360.** El mismo error estaba de antes en los otros 175
artículos: el **234** da $944,26 = $600 del palo **+ los $344,26 de la caja entera**, cuando la
caja de a 12 tendría que aportar $28,69. `[dato]`

**Dónde está, leído de `pg_get_viewdef`:** la vista arma el costo por dos caminos y la caja entra
por el equivocado.

| CTE | De dónde saca | ¿Usa la cantidad? |
|---|---|---|
| `insumox` | los pasos `tipo_paso='insumo'` | **sí**, `cantidad * precio` |
| `mat` | `edges` = los pasos `matriz` / `proveedor_servicio` / `tallerista` | **no**, `cb.precio` pelado (salvo sector 5, los flejes, que multiplica por kg) |

La caja aparece en los **dos**: como entrada del paso `insumo` (0,0833) y como entrada del paso
`tallerista` (el que la convierte en el terminado). Y `insumox` tiene este `case`:
`when exists (edges e where e.ent = insumo_id) then greatest(cantidad - 1, 0) * precio`. Como la
caja **sí** es entrada de un edge, `greatest(0,0833 − 1, 0) = 0` → **`insumox` aporta 0 y `mat`
aporta el precio entero.** El `− 1` está pensado para una pieza que se transforma (entra 1, sale 1)
y le pega de lleno a todo insumo con cantidad < 1: cajas, cartones, pliegos. `[dato]`

**La plata:** sumando `precio_caja × (1 − 1/uni_x_caja) × uni_mes` sobre los 189 artículos con caja
da **ARS 38.538.090 por mes**. Es de lejos el número más grande que apareció en esta auditoría, y
**es anterior a cualquier cambio de hoy** — lo de §4da sólo sumó 14 artículos más a la misma cuenta.

**Prueba de que el modelo querido es el otro:** la planilla, hoja Costos, columna M del 942E dice
**15** = 360 ÷ 24, la parte por unidad. Y la cuenta que el dueño validó el 11-09 para la Caja N22
del 546 (§4cr, *"~$39.500/mes de más"*) es `7.700 × (208 − 146,42) / 12`: **dividida por 12**. O sea
el negocio siempre pensó en la parte; la vista es la que cobra la caja entera. `[dato]`

**ARREGLADO el 2026-09-13** (dueño: *"1 arregla"*), migración `la_caja_se_cobra_por_su_parte_no_entera`.
Se tomó la opción 2, en su forma mínima: `mat` pasa de cobrar `cb.precio` pelado a cobrar
`cb.precio × least(coalesce(cantidad_del_paso_insumo, 1), 1)`. La cuenta queda exacta para todo `q`:

    antes:  mat = 1 × precio          + insumox = greatest(q−1,0) × precio  =  max(q,1) × precio
    ahora:  mat = least(q,1) × precio + insumox = greatest(q−1,0) × precio  =  q × precio

**Lo que NO se tocó, a propósito:** el `greatest(q−1,0)` de `insumox` (existe para que una pieza que
entra 1 y sale 1 no se cuente dos veces) y los flejes (sector 5, que ya escalan por `kg_ref`).
`insumo_por_art` se movió arriba de `mat` para poder leerse desde ahí, sin cambiarle una coma.

**Verificado en seis testigos, todos exactos al centavo:** 234 `944,26 → 628,69` (= 600 del palo +
28,69 de caja) · 942E `360,00 → 30,00` · 311 `515,48 → 185,48` · 312 `1.671,08 → 1.341,08` ·
395 `559,80 → 319,80` · 546 `1.659,70 → 1.469,03` (= 208 − 17,33 menos). Ningún costo quedó nulo ni
negativo, y ninguno subió (matemáticamente no puede: `least(q,1) ≤ 1`). El costo mensual valorizado
de los 191 artículos queda en **ARS 141.866.763**. `db/vistas_GP2.sql` regenerado y **verificado por
md5 contra la vista viva**. `[usuario + dato]`

**Regla que deja: en GP2 un insumo que además es la ENTRADA del paso que lo consume se cobra
entero, no por su cantidad. Antes de creerle a `total_pesos`, comparar contra la columna M de la
hoja Costos.** `[deducido]`


## 4dd. 942E y 945E quedan en 12 por caja, contra lo que dice la planilla (2026-09-13)

`[usuario 2026-09-13, textual: *"2 12."*]`. La planilla los da de a **24** en sus dos hojas
(Cajas F=24 y Costos M=15=360/24) y GP2 los tenía en **12**; el dueño confirmó **12**. **Se retira
el hallazgo de §7.4(b) de `PENDIENTES_CAJAS_PALOS`**: no hay nada que corregir en la base, la que
está desactualizada es la planilla.

Consecuencia concreta, ahora que la caja se cobra bien (§4dc): 942E y 945E aportan **$30,00** de
caja por unidad, no $15. Sobre 214 uni/mes son **$3.210 más por mes** que lo que dice la planilla —
diferencia real, no error de carga. `[deducido]`

**Regla que deja: la planilla no gana automáticamente.** El 11-09 la hoja Costos fue la que cerró la
discusión de qué caja usa cada artículo (§4cr); acá el dueño la contradice en la uni x caja y manda
él. La hoja Costos es la mejor fuente cuando **nadie** sabe, no cuando el dueño ya decidió.


## 4de. 573 y 517 son discontinuos: no se dan de alta aunque tengan despiece (2026-09-13)

`[usuario 2026-09-13, textual: *"2 discontinuos"*]`, contestando si se daban de alta el **573**
Bombilla Color Metalizado y el **517** Pinza Gastronómica, que §4db había encontrado **con despiece
completo en la planilla**. **No se modelan.** Tener el despiece no los hace vivos: la planilla
guarda el despiece de cosas que ya no se venden, igual que la Est Madre arrastra discontinuados
(§4cw, el caso del 515).

Con esto los tres del cruce contra loekemeyer.com quedan cerrados y **ninguno entra a GP2**:

| Cód | Qué es | Por qué no entra |
|---|---|---|
| 573 | Bombilla Color Metalizado | discontinuo `[usuario]`. Ojo: **sigue en `est_madre` con 52 uni/mes** — misma basura que el 515 |
| 517 | Pinza Gastronómica | discontinuo `[usuario]`. No está en est_madre ni en la hoja Costos |
| 556 | Sacayerba | el único sin despiece de verdad; la planilla lo costea sólo como envase (§4db) |

**Queda por decidir:** si se borra la fila `573` de `est_madre` (52 uni/mes), como se hizo con el
515. No se tocó. **Y loekemeyer.com los sigue mostrando activos**, igual que a los 332/335/337 —
eso es trabajo del repo del sitio, no de GP2. `[dato]`

## 4df. El precio de la bandita: la planilla lo tiene y NO lo cobra (2026-09-13)

El dueño pidió *"el mismo precio que la que se usaba para 323, no tenés esa?"*. **No, y hay dos
motivos, los dos medidos:** `[dato]`

1. **El 323 no está en GP2** (Rallador Cilíndrico Chico, grupo A de `ARTICULOS_FUERA_DE_GP2`,
   124 uni/mes, tallerista Garcia). Ningún componente de GP2 tiene esa bandita.
2. **La planilla tampoco la cobra.** El 323 en la hoja Costos (fila 154) da
   `E 918,1033 + K 16,606 + L 33 + M 25,2292 + N 3,0862 = O 996,0247`, **exacto al centavo y sin
   lugar para una bandita**. La columna K no es la bandita: el encabezado (fila 6) dice
   **"Envas. Terc."** (envasado por terceros); L es Cartón, M Cajas y N "Cod y Precint".

Lo que sí existe es la **línea en la lista de precios**: `Bandita Ralladores` (Gráfica Pol, cod ISIS
**0317**) a **$8.250**, y `Banditas 35 × 194 mm` (mismo proveedor, ISIS 0357) **al mismo precio
exacto, $8.250**. Así que "el mismo precio que la del 323" da $8.250 por cualquiera de los dos
caminos — el problema es **de qué** son esos $8.250.

**⚠ NO se cargó, y el motivo es un pozo en el que la casa YA se cayó:** el comment de
`precio_proveedor` del `Pliego 506` dice textual *"POR PLIEGO (el paquete de 100 sale $77.700).
Corregido 2026-09-03: estaba cargado el precio del PAQUETE y la OC pide en pliegos, así que valuaba
100x"*. **Los precios de Pol en la lista vienen por paquete**, y la lista no tiene columna de
cantidad. Cargar $8.250 como precio unitario le sumaría $8.250 a CADA palo de amasar — y desde
§4dc la caja ya se cobra bien, así que el error se vería entero en el costo.

**Falta el único dato que no está en ningún lado: cuántas banditas trae el paquete de $8.250.**

**Regla que deja: un precio de Gráfica Pol es del PAQUETE hasta que se demuestre lo contrario.
Antes de cargarlo, buscar la cantidad por paquete; si no aparece, preguntar.** `[deducido]`


## 4dg. Se borro el 573 de est_madre — y son 235 filas, no una (2026-09-13)

`[usuario 2026-09-13, textual: *"2 si"*]`. Borrada la fila `573` de `GP2.est_madre`
(52 uni/mes, uxb 24), como se hizo con el 515 el mismo dia (§4cw). Backup en
`zz_backups."GP2_Backup_est_madre_573_20260913"`. `est_madre` queda en **404 filas**.

**Medido antes y despues: el md5 de TODOS los maximos de `inventario` es IDENTICO**
(`3ff3dad8…`). No podia ser de otra forma y conviene entender por que: `recalcular_maximos_insumos()`
llega al maximo por la RECETA del articulo, y el 573 **no existe como articulo en GP2**, asi que su
fila nunca alimento un solo calculo. **Borrarla no arregla ningun numero: saca un dato que confunde
al que lo lee.** `[dato]`

**Y no es una fila, son 218.** `[CORREGIDO el mismo dia: primero escribi 235, con un `join` por
codigo exacto. Esta mal — ver abajo.]` De las 404 filas que le quedan a `est_madre`, **218 no cruzan
con ningun articulo de GP2**. La Est Madre es una foto del sistema viejo: trae discontinuados,
reventa e importados que GP2 no modela. El desglose completo, grupo por grupo, esta en
`EST_MADRE_HUERFANAS_2026-09-13.md`. `[dato]`

**⚠ LA TRAMPA DEL CERO ADELANTE, que casi me hace reportar un bug que no existe.** `est_madre`
escribe `31`, `26`, `27`, `34`, `66`, `57`, `58`, `59`, `99`, `97`, `70`, `55`, `43`, `53`, `54` y
`52`, y GP2 los tiene como `031`, `026`, … Un `join` por codigo exacto los marca como huerfanos —
son **16 codigos y 28.812 uni/mes**, entre ellos el **031 Filtro de Cafe con 15.144 uni/mes, el
articulo de mayor demanda de la casa**. Llegue a concluir que sus insumos estaban sub-dimensionados
en la OC. **Es falso:** `v_consumo_demanda` cruza con
`regexp_replace(em.cod,'^0+','') = regexp_replace(a.codigo,'^0+','')`, o sea **ya normaliza**, y el
consumo del carton `A1B` da exactamente 15.144. **Regla: para cruzar `est_madre` con `articulo`,
sacar los ceros de adelante de los dos lados — es lo que hace el motor.** `[dato]`

**De las 218, las unicas que pueden ser trabajo son 16** (las que la hoja Costos marca `Fab`), y
**13 ya estan resueltas**: 332-337 son los cubiertos inox discontinuos (§4db), el 548 es el pincel
que ya entro como 590E/890E/590ES (§4ct), y 513L/546L/520L/505L/586L son **variantes con sufijo `L`
de articulos que GP2 ya tiene** (513, 546, 520, 505, 586). **Quedan tres preguntas: el 561 Pinza
Grande Alambre (324 uni/mes), el 396 Enrulador de Manteca (80) y si los cinco codigos `L` son una
variante real o basura.** Y un detalle: **el 515 sigue en `est_madre` con 486 uni/mes** — si alguna
vez se quiso borrar, no se borro. `[dato]`

**Regla que deja: una fila de `est_madre` sin articulo de GP2 no mueve ningun maximo — es ruido de
lectura, no un bug de calculo. Y `proy_uni_mes` NO es evidencia de que algo se venda**
(§4cw, textual del dueño sobre el 515: *"No hay chance que se venda 486 uni de 515"*). Antes de
borrar de a una, vale preguntarse si conviene limpiar las 234 de un saque o dejarlas y no leerlas.

## 4dh. La bandita queda SIN precio: el dueño tampoco sabe cuantas trae el paquete (2026-09-13)

`[usuario 2026-09-13, textual: *"1 nose"*]`, contestando cuantas banditas vienen en el paquete de
$8.250 de Grafica Pol. **`BANDITA` (componente 916) queda con proveedor Pol y SIN precio**, y esa es
la decision correcta: cargar $8.250 como unitario le sumaria $8.250 a cada palo de amasar (§4df, la
trampa del `Pliego 506` que ya costo una correccion el 03-09).

**Lo que hay que preguntarle a Pol cuando se pueda:** cuantas unidades trae el paquete de $8.250 del
ISIS **0317** (Bandita Ralladores) o del **0357** (Banditas 35 × 194 mm) — los dos al mismo precio.
Con ese numero el precio unitario sale solo y se carga en `precio_proveedor`.

**Mientras tanto los tres palos siguen con `faltan_precios` ≥ 2** (los `GRJ22/23/24` tampoco tienen
precio: la LP solo lista el Palo Frances $600 y el Torneado 40cm $1.245). O sea que hoy el costo de
un palo es **solo su caja, $28,69**. No es un bug: es que faltan dos precios. `[dato]`


## 4di. Que es un `GRJ` (el dueño pregunto, y conviene que quede escrito) (2026-09-13)

`[usuario 2026-09-13, textual: *"nose que es eso"*]`, preguntando por el precio de los
`GRJ22/23/24`. **Un `GRJ` es una pieza del Sector Garage: algo que se COMPRA hecho, entra por el
garage y despues alguien lo termina.** No es un articulo que se venda: es el insumo principal del
articulo.

En el caso de los palos: **`GRJ22` es el palo de amasar de 30 cm en si** — la madera torneada que
vende Tierra Nativa. `GRJ23` el de 40 y `GRJ24` el de 50. Fabrica les pone la bandita y los entrega
en Virgilio, y eso los convierte en los articulos 231 / 232 / 233. Es el mismo patron que el `GRJ4`
de Cimarron (§4cy).

**Ninguno de los tres tiene precio cargado, y la lista tampoco lo tiene:** el bloque de Tierra
Nativa solo lista *"Palo de Amasar Frances 40cm"* $600 (que es el `GRJ17`, el del 234) y
*"Torneado Palo de Amasar 40cm"* $1.245. **Para los palos lisos de 30, 40 y 50 no hay precio en
ningun lado.** Por eso hoy un palo cuesta $28,69, que es solo su caja. `[dato]`


## 4dj. La `L` final: es Chef vendiendo Loeke, y GP2 pierde 301 uni/mes por no pelarla (2026-09-13)

`[usuario 2026-09-13: *"Ya lo explique lo 1 en GV, busca"*]`. Encontrado en
`loekemeyer/Gestion-Virgilio`, `CLAUDE.md` linea 396 y `GUIA-PROYECTO.md` §4737. **La regla, textual
de ese repo:**

> *"Un cliente de LK que pide por la página de Chef: el pedido es de Chef de punta a punta, se
> factura por Chef, y cada artículo de Loekemeyer va con **'L' al final** (505 → 505L; 438E →
> 438EL). … la L manda el stock a la góndola LK"*. Y el caso mas comun, `[dueño 07-09 en GV]`:
> un pedido con entrega en **Tierra del Fuego** (Factura E) se arma como Loeke con L y el Excel ISIS
> va al de Chef.

**O sea `546L` NO es un artículo: es el 546, vendido por Chef.** No hay que darlos de alta en GP2.

**PERO hay una consecuencia que no estaba vista: GP2 pierde esa demanda.** En `est_madre` hay **75
códigos con `L`**; **32 cruzan con un artículo de GP2 al pelarla**, y suman **301 uni/mes** que hoy
**no llegan a ninguna receta** porque `v_consumo_demanda` normaliza el cero de adelante pero **no la
L**. Los mas grandes: `31L` 55 (Filtro de Café), `123L` 52, `504L` 30, `315L` 29, `544L` 21,
`513L` 18. `[dato]`

**Gestión Virgilio ya resolvió exactamente esto, y al reves:** su `vista_generador_oc`
*"strippea la 'L' final y aglomera en el código base sumando UNIDADES / uni×caja del base → el 505L
cae dentro del 505 (se pide 505, nunca 505L)"*; antes eran *"63 códigos ≈ 1.265 cajas fantasma que
inflaban la lista"*. A GV le inflaba la OC; a GP2 se la **desinfla**, porque directamente ignora esas
filas. **APLICADO el 2026-09-13**, migracion `la_venta_con_L_de_chef_suma_al_articulo_de_loeke`
`[dueño, textual: *"Los de L: es venta que facturo chef de articulos de Loeke, el consumo realmente
es de loeke, se debe considerar ahi. Ejemplo 513L, es venta de loeke"*]`. El join de
`v_consumo_demanda` pasa a pelar tambien la L, igual que ya pelaba el cero de adelante. Como `seed`
agrupa y **suma** por (articulo, componente), las dos filas de `est_madre` (el `513` y el `513L`)
se suman solas en el articulo 513 — no hizo falta tocar nada mas. `[usuario]`

**Verificado antes de aplicar:** **ningun articulo de GP2 termina en `L`**, asi que el pelado no
puede producir un falso positivo. Y 74 de los 75 codigos `L` ya tenian su base en `est_madre`.

**Efecto medido:** `recalcular_maximos_insumos()` actualizo **81 maximos**, todos **para arriba**
(ninguno bajo: solo se suma demanda), **+4.587 unidades** en total. El testigo que pidio el dueño
cierra exacto: el **carton del 513 (`B1A`) subio 108 = 18 uni/mes del `513L` × 6 meses de stock**.
Los que mas se movieron: `A1B` Carton 031 +330, `I42` Carton 123 +312, `PCP3`/`D9` Clavo 505 +288,
`CV5` +240. Snapshot previo en `zz_backups."GP2_Snap_maximos_antes_L_20260913"` (las 1.295 filas de
`inventario`). Invariantes 35/35 en 0, `db/vistas_GP2.sql` regenerado y verificado por md5.

**Lo que esto significa en la practica: la OC venia pidiendo de menos.** Cada `L` es una venta real
que Chef factura de un articulo de Loeke, y su consumo no llegaba al insumo. `[dato]`

**Regla que deja: un codigo que termina en `L` es el mismo articulo sin la L.** Vale para `est_madre`,
para los listados y para cualquier cruce. El `590EL` es el `590E`; el `438EL` es el `438E`.

## 4dk. Las ventas REALES existen y estan en `sales_lines` — hay que mirarlas antes de dar algo por muerto (2026-09-13)

Buscando quien compra el 515 aparecio que **la evidencia de venta que faltaba en todas estas
discusiones ya existe**: `public.sales_lines` del proyecto **`kwkclwhmoygunqmlegrg`**
("loekemeyer's web"), con `item_code`, `boxes`, `invoice_date`, `customer_code` y `empresa`
(`lk` / `chef`), desde 2020. **Es la fuente que zanja "¿esto se vende?", que `est_madre` NO puede
contestar** (§4cw). `[dato]`

Medido el 13-09, ultimos 12 meses (desde 2025-09-13):

| Cód | Artículo | Cajas 12m | Clientes 12m | Última venta | Lo que se dijo |
|---|---|--:|--:|---|---|
| 515 | Batidor Resorte | **396** | **75** | **2026-08-25** | *"No hay chance que se venda 486 uni de 515"* |
| 561 | Pinza Grande | **246** | **75** | **2026-08-13** | *"discontinuos, no se fabrican más"* |
| 333 | Espumadera Ac. Inox. | 109 | 45 | 2026-04-15 | discontinuo (bloque 332-337) |
| 336 | Cucharón Ac. Inox. | 76 | 49 | 2026-07-06 | ídem |
| 332 | Espátula A. Inox. | 64 | 37 | 2026-08-27 | ídem |
| 334 | Cuchara Salsera | 48 | 35 | 2026-05-14 | ídem |
| 573 | Bombilla Color Metaliz | 46 | 19 | 2026-07-06 | discontinuo |
| 396 | Enrulador De Manteca | 40 | 20 | 2026-08-17 | *"no se fabrican más"* |
| 335 | Cuchara Calada | 21 | 18 | 2026-08-27 | discontinuo |
| 337 | Pinche Ac. Inox. | 20 | 15 | 2026-06-10 | discontinuo |
| 548 | Pincel Pastelero | 6 | 2 | 2026-05-08 | ya entro como 590E/890E |
| 525 | Sac Cabo Madera | 1 | 1 | 2026-03-09 | 0 uni/mes en est_madre |
| **556** | Sacayerba | **0** | **0** | 2025-05-05 | sin despiece |
| **517** | Pinza Gastronómica | **0** | **0** | **2021-11-26** | discontinuo |

**DECISION DEL DUEÑO (2026-09-13, textual): *"515 dejalo activo"*.** La fila del 515 en `est_madre`
**NO se borra** — se retira la idea de sacarlo, que venia de §4cw. Los 75 clientes y la factura del
25-08 lo respaldan. `[usuario]`

**Lectura, sin decidir nada:** *"discontinuo"* en boca del dueño significa **"no se fabrica mas"**,
no *"no se vende"* — lo dijo asi de los 561/396, y los numeros lo confirman: se sigue facturando del
stock. **Los unicos dos muertos de verdad son el 517 (ultima venta hace casi 5 años) y el 556
(16 meses).** Y **el 515 se vende**: 75 clientes distintos en 12 meses y factura del 25-08-2026,
o sea que la frase del §4cw *"No hay chance que se venda 486 uni de 515"* **no se sostiene contra la
facturacion** (396 cajas / 12 meses = 33 cajas/mes; est_madre pide 486 uni/mes = 40,5 cajas). No se
toco nada: el dueño decide.

**El `515L` tambien existe**: 22 cajas, **1 solo cliente**, ultima venta 2026-08-31 — ese es el caso
de §4dj, Chef vendiendole Loeke a Tierra del Fuego.

**Regla que deja: antes de dar un articulo por muerto, mirar `sales_lines` del proyecto
`kwkclwhmoygunqmlegrg`. `est_madre` dice lo que se proyecta; `sales_lines` dice lo que se facturo.**


## 4dl. La Est Madre SUBESTIMA la cola: hasta 14x menos de lo que se factura (2026-09-13)

Recalculando el grupo A de `ARTICULOS_FUERA_DE_GP2.md` con `sales_lines` en vez de `est_madre`
aparecio un sesgo con forma: **cuanto mas chico es el numero de la Est Madre, mas se equivoca.**
`[dato: sales_lines, 12 meses al 2026-09-13, uni/mes = cajas/12 × uxb]`

| Cód | Est Madre | Vendidas | Cuánto más |
|---|--:|--:|---|
| 456 Espátula Lisa Nylon | 1 | 14 | **14×** |
| 710 Enrulador Manteca | 1 | 13 | **13×** |
| 839 Rallador Chocolate | 10 | 114 | **11×** |
| 852 Pinza De Hielo 14 cm | 7 | 80 | **11×** |
| 801 Pinza Grande CH | 2 | 16 | 8× |
| 809 Corta Queso Chef | 1 | 8 | 8× |
| 977 Platos Pizza x6 | 2 | 11 | 5× |
| 574 Corta Queso Alambre | 88 | **319** | 3,6× |
| 747 · 717 · 613 | **0** | 6 · 2 · 1 | tienen facturas de 2026 |

Los grandes, en cambio, cierran bien: el `111`, el `112` y el `113` dan **exacto**, y el `565` y el
`439E` quedan cerca. **O sea la Est Madre esta bien donde hay volumen y se rompe en la cola larga**
— justo donde se venia usando para descartar (*"tiene 1 uni/mes, no importa"*). El caso mas caro es
el **574 Corta Queso Alambre**: 88 segun la proyeccion, 319 vendidas a 41 clientes, factura del
17-08-2026; era el decimo de la lista y es el tercero.

**Regla: `est_madre` decide el MAXIMO de stock (es lo que consume el motor); `sales_lines` decide
QUE VALE LA PENA MODELAR. No mezclar los dos usos.** Es la version general de lo que ya habia
mordido con el 515 (§4cw) y con el 573 (§4de). `[deducido]`


## 4dm. El $28,69 es SOLO de los tres palos nuevos, y el 234 no: corrijo lo que dije (2026-09-13)

`[usuario 2026-09-13, textual: *"Igual el palo de amasar no lo vende tierra a $28.69. Te falta el
costo de lo que vende tn tambien"*]`. **Tiene razon y la frase estaba mal dicha en §4dh y en el
chat.** Lo medido, componente por componente:

| Componente | Artículo | ¿Tiene precio? | Costo del artículo hoy |
|---|---|---|--:|
| `GRJ17` Palo de Amasar Frances 40 cm | **234** | **sí, $600** (LP f888, ISIS 103, lista 03-11-2025) | **$628,69** = 600 + 28,69 de caja |
| `GRJ22` Palo de Amasar 30cm | 231 | **no** | $28,69 (solo la caja) |
| `GRJ23` Palo de Amasar 40cm | 232 | **no** | $28,69 |
| `GRJ24` Palo de Amasar 50cm | 233 | **no** | $28,69 |

O sea **el $28,69 nunca fue "lo que cuesta un palo": es lo que GP2 puede calcular de los tres que no
tienen precio de Tierra Nativa.** El 234, que sí lo tiene, da $628,69.

**Y el bloque entero de Tierra Nativa en la lista de precios (72 filas, cod_prov 3917) tiene SOLO
DOS lineas de palo de amasar:** `[dato: v_planilla_precio]`

| Fila | cod ISIS | Producto | Precio | Fecha lista | Última compra | Asignado en GP2 |
|--:|---|---|--:|---|---|---|
| 888 | 103 | Palo de Amasar **Frances** 40cm | $600 | 03-11-2025 | 18-12-2024 | ✔ `GRJ17` (art 234) |
| 901 | 234L | **Torneado** Palo de Amasar 40cm | **$1.245** | **07-08-2026** | — | **sin asignar** |

**No hay linea para el de 30 ni para el de 50.** La unica libre es el Torneado de 40, que por medida
seria el **232**, pero el nombre no lo dice y el `cod_isis` de esa fila (`234L`) apunta al 234, no al
232 — **asignarla a ojo es inventar**. Falta que el dueño diga: (a) si el Torneado 40 es el 232, y
(b) que precio tienen el de 30 y el de 50, que en la lista no estan. `[dato]`

**Regla que deja: antes de decir "este articulo cuesta X", mirar `faltan_precios` Y decir de que
componentes falta el precio.** Un total bajo casi nunca es un articulo barato: es un componente sin
precio (misma trampa del BOM10 en §4cn y del pincel en §4ct).


## 4dn. Lo que realmente falta no son los palos: son 106 precios, y 67 son de Pol (2026-09-13)

`[usuario 2026-09-13: *"Nose"*]` sobre el precio de los palos de 30 y 50 — **nadie en la casa lo
sabe, hay que preguntarle a Tierra Nativa.** Eso disparo medir el agujero completo en vez de seguir
de a un componente, y el resultado cambia la prioridad: `[dato, medido el 13-09]`

| | |
|---|--:|
| Artículos de GP2 | 191 |
| **Artículos con al menos un precio faltante** | **96 (50 %)** |
| **Componentes comprables vivos SIN precio** | **106** |
| De esos 106, cuántos no tienen ni proveedor | **0** |

**Los 106 tienen proveedor asignado: lo unico que falta es el numero.** Y estan muy concentrados:

| Proveedor | Componentes | Consumo uni/mes |
|---|--:|--:|
| **Talleres Gráficos Pol** | **67** | **41.318** |
| Pat Bet Plast | 11 | 11.584 |
| Papelera Nueve de Julio | 2 | 4.050 |
| Cimarron | 5 | 2.540 |
| Gilardi Esther | 2 | 1.816 |
| Rueda · Imel · Importado | 3 | 4.185 |
| Tierra Nativa SA (los 3 palos) | 3 | 0 |
| los otros 9 proveedores | 13 | ~2.700 |

**Una sola lista de precios — la de cartones de Pol — cierra 67 de los 106 y el 63 % del consumo
afectado.** Los mas grandes son `C2A` Carton 026 (7.092 uni/mes), `F5A` Carton 321 (4.406),
`C2B` Carton 027 (3.320), `L2C` Carton 325 (1.600), `F1A` Carton 280 (1.570). Los tres palos, en
cambio, son **3 de 106 y con consumo 0** (los 231/232/233 no estan en `est_madre`).

**Regla que deja: cuando aparezca "a este articulo le falta un precio", no perseguir el componente
suelto — contar cuantos faltan y agruparlos por proveedor.** Casi siempre es UNA lista que nadie
cargo, no N datos sueltos. `[deducido]`

**Las dos preguntas de los palos quedan ABIERTAS, para Tierra Nativa:** (a) si el *"Torneado Palo de
Amasar 40cm"* $1.245 (ISIS 234L, lista 07-08-2026) es el **232**, y (b) que precio tienen el de
**30 (231)** y el de **50 (233)**, que no figuran en las 72 filas de TN.

### 4cg. El 515/615 probado de punta a punta con los RPC reales (2026-09-14)

`[usuario 2026-09-14: "No agregaste la convergencia (componente bomb) ademas quiero saber si se
puede recepcionar, fabricar, enviar segun corresponda en gp2"]` — las dos cosas eran ciertas.

**1) Faltaba `componente_bom`.** La reconstrucción dejó los PASOS de ruta que convergen en `C12`
pero no declaró los hijos. **Eso es lo que la pantalla usa para dibujar la convergencia**:
`Programa.html` agrupa por `D.children[cs]`, así que sin la fila el batidor se veía como "2 rutas
simples" en vez de "Convergencia · C12". Cargado `C12 ← W1B (1) + IE1 (1)`, con la convención de
las otras 26 convergencias (`D5-M78 ← D5+D6+V4`, `G4 ← K5+K8+V3`, `GRJ7 ← A10+C10+V9`…).
El `BOM10` NO va ahí: `[usuario 2026-09-12: "1 lo agrega alex"]`.

**2) El ciclo completo corre.** Probado con los RPC de verdad y rollback, 120 unidades del 515:

| # | Paso | RPC | Resultado |
|---|---|---|---|
| 1 | Recepción de 4 insumos | `crear_recepcion_insumo` | OK |
| 2 | Fabricación en matriz 138 | `registrar_produccion` | 120 W1B |
| 3 | Guazzaroni niquela | `crear_envio_ps` / `crear_entrega_ps` | OK |
| 4 | Envío a Alex | `crear_envio_tallerista` | W1B 120 · IE1 120 |
| 5 | **Convergencia** | `crear_entrega_tallerista` | C12 120, y el BOM deja W1B y IE1 en **0** |
| 6 | Pedernera croma | `crear_envio_ps` / `crear_entrega_ps` | OK |
| 7 | Envío del resto a Alex | `crear_envio_tallerista` | OK |
| 8 | Entrega en Virgilio | `recepcion_virgilio` | **120 del 515, cero sobras** |

**Dos errores míos que sólo aparecieron al correr el ciclo** — ninguna consulta los mostraba:

- **`IE1` sin `kg_x_uni`**: `to_canonical` cortaba con *"componente 917 sin kg_x_uni válido para
  uni→kg"*. No se podía **ni recibir ni enviar**. Cargado **0,0241** — el mismo número que el
  vecino da para `FE1` "Varilla Batidor" y que la migración `20260901091333` ya usaba para los dos
  terminados.
- **`IE1` en `kg` cuando va por pieza**: al enviarle 120 uni a Alex el stock quedaba en **2,892**
  (= 120 × 0,0241, convertido a kg) y el BOM le restaba **120 unidades**, dejando −117,108.
  **Contraejemplo que lo probó**: `IE4` y `IE5`, que alimentan la convergencia `GRJ10` igual que
  `IE1` alimenta `C12`, son `unidad` y conservan su `kg_x_uni`. `IE1` era el **único** fleje en kg
  usado como hijo de un BOM en toda la base — una anomalía de una sola fila es firma de dato mal
  cargado. `IF11` queda en kg: ese va a la matriz y se consume por kilo.

**Regla que sale de esto: un fleje que va DERECHO al tallerista se cuenta por pieza
(`unidad_medida='unidad'`, con su `kg_x_uni` cargado igual); el que entra a una matriz va en kg.**

**Lección de método**: la simulación de rutas (`__sim_articulo`) daba bien las dos veces, con y sin
el error de unidad. Lo único que lo destapó fue correr **los RPC reales** contra el inventario.




## 4do. Los 7 inox 941E-948E van en Caja N°15, no en la N°12 — y la "E" no es la regla (2026-09-14)

`[usuario 2026-09-14, textual: *"Todos los articulos que terminan con E: 941E 942E 943E 944E 945E
946E 948E. Llevan caja N°15, no 12"*, y ante la repregunta: *"Si, caja 15 solo para los que te
liste"*]`.

**Lo primero, porque es la trampa: el sufijo "E" NO define la caja.** `[dato]` En GP2 hay **9**
artículos que terminan en E, no 7: los otros dos son `590E` y `890E` (Pincel Silicona 11 Gms), que
van en **Caja N°29** (`A11`) y **quedan como están** por decisión explícita del dueño. Los siete de
la lista son la línea de **acero inoxidable**, y eso es lo que tienen en común, no la letra. Si en
otra sesión aparece "los artículos con E", preguntar cuáles: leerlo como regla de sufijo mete a
590E/890E en la caja equivocada.

**Estado antes del cambio** `[dato, medido el 14-09]`: los siete estaban de dos formas distintas.

| Art | Descripción | Caja antes | uni/mes | Δ costo $/mes |
|:---:|:---:|:---:|---:|---:|
| 941E | Espátula Lisa Inox | **ninguna** | 86 | **+2.467,20** |
| 946E | Cuchara Calada Inox | **ninguna** | 58 | **+1.663,92** |
| 943E | Cucharón Inox | N°12 (`A2`) | 144 | −188,88 |
| 942E | Cuchara Inox | N°12 (`A2`) | 132 | −173,14 |
| 948E | Espumadera Inox | N°12 (`A2`) | 108 | −141,66 |
| 945E | Espátula Calada Inox | N°12 (`A2`) | 82 | −107,56 |
| 944E | Cuchara Fideos Inox | N°12 (`A2`) | 74 | −97,06 |

**`941E` y `946E` no tenían caja en ningún lado** — ni el FK `articulo.componente_caja_id`, ni línea
de receta, ni ruta de caja — porque la planilla los trata como importados terminados (§3 de
`PENDIENTES_CAJAS_PALOS_2026-09-13.md`, que **se retira**: la planilla estaba equivocada). Para esos
dos no fue "15 en vez de 12": fue caja donde no había, y ahí está casi toda la plata del cambio.

**Lo que se escribió** (una transacción, `2026-09-14`): los 7 al FK `A9B`; los 5 que ya tenían `A2`
cambiaron de caja en receta y en su ruta de caja; `941E` y `946E` recibieron su línea de receta
(`A9B × 1/12`) y **una ruta de caja nueva cada uno**, calcada de las otras cinco
(`insumo A9B 1/12 → tallerista Fábrica → virgilio`). **Las cuatro tablas de la cadena se tocaron
juntas**, que es lo que pide la regla de normalización: tocar sólo el FK habría dejado la caja fuera
del costo y fuera de la OC, que es exactamente el agujero que tenían 941E y 946E.

**Los 12 uni x caja NO se tocaron** — sigue en pie la decisión del 13-09 (§4dd) contra la planilla,
que dice 24 para 942E y 945E.

**Efecto medido** `[dato]`:

| | Antes | Después |
|---|--:|--:|
| Consumo `A2` Caja N°12 | 1.196 uni/mes (29 art) | **1.151** (24 art) |
| Consumo `A9B` Caja N°15 | 205 uni/mes (7 art) | **262** (14 art) |
| Máximo de `A9B` en Sector Caja | 1.230 | **1.572** |
| Costo unitario de los 7 | $30,00 los cinco · $0 los dos | **$28,69 los siete** |

Neto **+$3.422,82/mes** de costo que antes no se cobraba. Los dos son del mismo proveedor
(Corrugadora del Plata) y sin `carton_formato`, así que **la familia de OC es la misma y no se
partió ningún pedido mínimo**. El máximo de `A2` **no se movió** y está bien: es `maximo_origen =
'fisico'` (4.275 fijado a mano por el lugar que hay, contra 6.906 que daría el cálculo), y
`recalcular_maximos_insumos` no pisa los físicos. **El de `A9B` sí subió porque es `est_madre`
(262 × 6 meses) y NO tiene tope físico cargado** — si el lugar de la N°15 no da para 1.572 cajas, hay
que cargarle el máximo físico, o la OC va a pedir de más. `[deducido, sin confirmar]`

**`faltan_precios` sigue en 1 para los siete**, y es `PEST1` (Kollplast, §7.3): el costo de $28,69 es
**sólo la caja**. Misma trampa de §4dm — un total bajo no es un artículo barato.

### 4ch. La paleta C12 se arma con TRES partes, y eso deja el resorte contado dos veces (2026-09-14)

`[usuario 2026-09-14, textual: "pone la rama 3 tal cual la foto. dentro de la tabla de componente
bomb se tiene que netender esto que c12 se arma con esas 3 partes"]`

**Corrige lo que yo había entendido del `"1 lo agrega alex"` del 2026-09-12.** Lo tomé como "el
resorte no va dentro de la paleta" y borré la fila `componente_bom(C12 ← BOM10)`. La foto del
Programa anterior al borrado mostraba la Rama 3, y el usuario la confirma:

> `C12` Paleta Batidor Resorte = `W1B` grampa + `IE1` varilla + `BOM10` resorte.

Cargado el BOM con las tres y agregada la Rama 3 en las dos rutas
(`Insumo BOM10 -> C12 -> Art 515` y `... Art 615`), con la misma forma que la rama del Fleje 33.

**Medido con el ciclo real en rollback, y el resultado es el que había que ver:**

| Momento | W1B | IE1 | BOM10 | C12 |
|---|---|---|---|---|
| Después de mandarle las 3 entradas a Alex | 120 | 120 | 120 | 0 |
| Alex entrega 120 paletas (el BOM descuenta) | **0** | **0** | **0** | 120 |
| Entrega de 120 del 515 en Virgilio | 0 | 0 | **−120** | 0 |

La convergencia de tres partes anda. **Lo que queda mal es que `BOM10` sigue ADEMÁS en la receta
del artículo (`articulo_componente`) y con su ruta suelta al tallerista** (el bloque 4 de la
pantalla), así que `recepcion_virgilio` lo vuelve a descontar: **el resorte se consume dos veces**.

**Hoy no se ve en la plata porque `BOM10` no tiene precio** ($306,31 y $428,67 antes y después,
idénticos). En cuanto Resortes Charcas entre a `precio_proveedor`, el 515 y el 615 empiezan a
cobrar dos resortes. El stock, en cambio, ya se rompe hoy.

**Espera decisión del usuario** (idea 7339): sacar `BOM10` de la receta del 515 y del 615 y borrar
las dos rutas sueltas `Insumo BOM10 -> Art 515/615`, dejándolo sólo dentro de la paleta.


## 4dp. Se borró el mínimo: la reposición la dispara el MÁXIMO (2026-09-14)

`[usuario 2026-09-14, textual: *"lo de minimo borralo. la orden de compra tiene que disparar segun
el maximo. es algo que habiamos hecho mal"*, y antes: *"La columna de mínimo en la tabla de
inventario hay que borrarla. Ya está la columna de máximo que reemplaza a esta (por más que
parezcan cosas distintas lo que se quiere en ambos es que sale el faltante)"*, y después:
*"todo lo que usaba el minimo ahora que use el maximo. es la misma lógica"*]`.

**Se retira la idea 7273 y la v1.21.0 de la OC entera.** El 08-09 se había metido un punto de
pedido separado del techo (el mínimo dispara, el máximo dimensiona). El dueño lo dio por error de
diseño: hay UNA sola pregunta — *¿le falta para llegar al máximo?* — y un solo número.

**Lo que se le dijo antes de hacerlo, y que él resolvió igual** (queda escrito para que ninguna
sesión futura lo "redescubra" y proponga volver atrás): mínimo y máximo NO eran lo mismo en la
base — `ubicacion` tenía `meses_minimo` y `meses_stock` cargados **distintos en 7 de los 11
sectores** (Cartón, Caja y Fleje 4 vs 6; Garage 1 vs 2; Crudo y Procesado 2 vs 1; Bombilla 4 vs 3),
o sea alguien los había configurado aparte a propósito. **Y el costo medido de sacarlo es chico:
el gatillo viejo frenaba 12 líneas por ARS 320.036 sobre una corrida de ~ARS 197 M**, porque hoy
casi todo el stock está en 0 y ya cae abajo del mínimo. Ese número crece cuando el stock esté
cargado de verdad. `[dato, medido el 14-09]`

**Qué se escribió, en orden.** Primero la migración de datos, **sólo donde no había máximo**
`[usuario: *"pero no migres todos. migra solo los que no tienen maximo"*]`:

| Dónde | Filas migradas | Qué quedó |
|:---:|---:|:---:|
| `inventario` · tallerista | 196 | `maximo = minimo`, origen `migrado_de_minimo` |
| `inventario` · Virgilio | 80 | ídem |
| `inventario` · sector | 12 | ídem |
| `inventario` · prov. servicio | 11 | ídem |
| `ubicacion` sin `meses_stock` | 13 | `meses_stock = meses_minimo` |

Verificado contra el backup: **0 máximos preexistentes pisados**, y las **456** filas que tenían
los dos números se quedaron con SU máximo. Las 7 ubicaciones con los dos valores distintos se
quedaron con `meses_stock`.

Después el borrado: `inventario.minimo`, `inventario.minimo_origen`, `ubicacion.meses_minimo` y la
función `recalcular_minimos()`. Backups en `zz_backups.GP2_Backup_inventario_minimo_20260914` y
`GP2_Backup_ubicacion_meses_minimo_20260914`.

**Lo que NO era obvio y hay que saber antes de tocar estas pantallas:**

1. **En Stock por Sector los nombres estaban cruzados.** La columna que decía **"Máximo"** mostraba
   `inventario.minimo`, y la que decía **"Capacidad"** mostraba `inventario.maximo`. Ahora hay una
   sola columna, "Máximo", con `inventario.maximo`; de dónde sale cada valor lo dice
   `maximo_origen`. `[dato, leído de gp2-stock-sector.js]`
2. **`movimientos_bundle` emitía `'meses'` desde `ubicacion.meses_minimo`, y con ese número
   `Despiece_GP2.html` calcula el "máximo por sector"** — o sea el máximo del Despiece se estaba
   calculando con los meses del *punto de pedido*. Ahora `'meses'` sale de `meses_stock`. Ése es
   probablemente el "algo que habíamos hecho mal" del que habla el dueño. `[deducido]`
3. **En Flejes, la columna "a pedir" era `minimo − stock`**; ahora es `maximo − stock`.
4. **Se fue el botón "Aprovechar el viaje" de la OC**: era la válvula de escape del gatillo viejo
   (sumar a mano lo que estaba arriba del mínimo). Sin estado intermedio no queda nada que
   aprovechar — lo que está abajo del techo entra solo y lo que llegó tiene sugerido 0.

**La regla nueva de la OC, en una línea:** `estadoRepo` = `'pedir'` si `stock < maximo`, `'lleno'`
si llegó, `'sin-gatillo'` (se carga igual, fail-safe) si falta el máximo o el stock.

**Queda pendiente**: la alerta `stock_bajo_minimo` de `alertas_bundle` sigue desactivada con el
motivo *"falta decidir con qué regla avisa (mínimo por ubicación vs máximo, y a quién)"* — la
primera mitad de esa pregunta ya está contestada (el máximo); falta **a quién** se le avisa.

**Resuelto el mismo día** `[usuario: "SI"]`, migración `el_resorte_va_solo_dentro_de_la_paleta_no_suelto`
(idea 7339): se borraron las dos líneas de receta (`articulo_componente` 941 y 947) y las dos rutas
sueltas (`ruta` 999 y 1006 con sus 3 pasos cada una). **El resorte entra sólo por la paleta.**
No se tocó `componente_bom(C12 ← BOM10)`, ni las Ramas 3, ni el componente, ni su historial.

Cómo quedan los dos artículos, y coincide con el encabezado de la foto ("5 partes BOM"):

| Artículo | Receta (5) | Rutas (7) |
|---|---|---|
| 515 | `C12`, `PC10`, `PA13`, `A1C1`, `A8` | 3 ramas de la paleta + 4 insumos al tallerista |
| 615 | `C12`, `PA19`, `PB6`, `O2A`, `A8` | 3 ramas de la paleta + 4 insumos al tallerista |

Ciclo real re-corrido de punta a punta: **120 unidades del 515 en Virgilio y cero sobras**, el
`BOM10` ya no queda en −120. Invariante ledger-vs-inventario en 0, suite 52/52.

**Regla que sale de esto: una pieza que es hijo de un sub-conjunto en `componente_bom` NO va
además como línea suelta de la receta del artículo.** Si está en los dos lados se descuenta dos
veces: una la entrega del tallerista que arma el sub-conjunto, otra `recepcion_virgilio` por la
receta. Vale para revisar las otras 26 convergencias.

### 4ci. Barrido de las 26 convergencias y los dos precios que se pudieron reponer (2026-09-14)

`[usuario 2026-09-14: "si"]` a las dos preguntas: cargar los precios y revisar las otras
convergencias buscando el mismo doble descuento del batidor.

**A) El doble descuento era ÚNICO.** Dos barridos, los dos en cero:

| Barrido | Resultado |
|---|---|
| Pieza que es hijo de un sub-conjunto **y** línea suelta de la receta de un artículo que usa ese sub-conjunto | **0** |
| Variante amplia: la pieza en la receta y alguna ruta del artículo **produce** el sub-conjunto | **0** |

**B) Pero el barrido destapó otras dos cosas, comparando ramas contra `componente_bom`:**

- **`G7` "sin BOM" es un FALSO POSITIVO**, y vale como recordatorio del método. Las rutas 45/47
  hacen `IE10 → M73 → M74 → G7` y las 46/48 hacen `IE10 → M73 → G7` salteando la M74: son **dos
  variantes del mismo camino**, no dos piezas que se juntan. Es la misma trampa de la Matriz 80
  (§4ce): compartir salida no prueba convergencia. `G7` **no necesita** `componente_bom`.
- **`H15` sí converge y tiene el BOM mal.** Dos flejes distintos llegan a la misma pieza para el
  artículo 066: `IE11 → H7 → H7-M173 → H7-M10 → H15` (ruta 107) e `IC7 → I12 → I12-M8 → I14 →
  PS → I16 → H15` (ruta 552). El BOM declara **`H7` + `I16`**, pero la rama entrega **`H7-M10`**,
  dos matrices después. **Impacto hoy: nulo en stock y en plata** — `H15` la produce una *matriz*,
  no un tallerista, así que `crear_entrega_tallerista` no descuenta ese BOM, y el costo lo saca de
  las aristas de ruta (`H7-M10` $142,91 + `I16` $109,01 + MO = $268,93, que es lo que da). Queda
  como inconsistencia de dato: el día que alguien entregue `H15` por tallerista, descontaría `H7`,
  que nadie tiene. Arreglo de una línea, **espera OK** (idea 7340).

**C) Precios repuestos, sólo los dos con fuente escrita:**

| Qué | Valor | Fuente |
|---|---|---|
| `precio_tallerista` de `C12`, Alex Escalante | **$62,7375** | migración `20260911004542`, Excel hoja `Lista de Precios `, bloque 4175, fila f619 "Batidor Resorte Armado" — el usuario ya lo había confirmado con "ok" |
| `precio_proveedor` de `A1C1` Cartón 515, Gráficos Pol | **$42,72** | el valor que estaba en la base antes del borrado (§4an-ter) |

Efecto: `C12` $25,76 → **$88,49**; 515 $306,31 → **$411,76**; 615 $428,67 → **$491,40**.

**Sin cargar, porque no hay dato**: `BOM10` (Resortes Charcas — ya faltaba ANTES del borrado,
§4an-ter), `IE1` Fleje N° 33, `O2A` Cartón 615 y el **envasado** del terminado (en el bloque de
Alex los batidores van de a pares armado + envasado, f619/f620; tenemos la f619, no la f620).

**Discrepancia sin resolver del Cartón 515**: la hoja ` Cartones` fila 376 le pone **$48,00**
(formato Huevo) y la base tenía **$42,72**. Se repuso lo que había — reponer no es decidir un
precio. Cambiarlo a 48 es un update de una línea.

**No comparar contra los $1.303,86 / $1.559,63 de §4an-ter**: son de antes del 13-09, y la
migración `la_caja_se_cobra_por_su_parte_no_entera` de esa fecha cambió cómo se costea la caja
(la `A8` vale $261,82 y el artículo usa 1/12). Los números viejos y los nuevos no son comparables.

### 4cx. La tablet del galpón es de CERVANTES: qué se recibe ahí y qué no (2026-09-14)

**Lo que el dueño corrigió** `[usuario 2026-09-14, textual]`: *"Proveedor de artículo terminado no va
dentro de recibir, sacalo. Porque entregan en Virgilio, y este módulo de tablet es para Cervantes"*.
Es conocimiento de negocio, no una preferencia de pantalla: **el proveedor de artículo terminado
entrega EN VIRGILIO**, así que en una tablet que está en Cervantes ese botón sólo podía generar una
carga en el lugar equivocado. Se le sigue **enviando** desde Cervantes (cartones y cajas): el que se
fue es el lado de **recibir**. Con él se fue la única carga en **CAJAS** de la tablet (§4cv, trampa 1):
hoy en la tablet no se recibe nada por caja. La RPC `crear_entrega_prov_at` sigue viva y el circuito
sigue siendo Prov Art Terminado → Entregas.

**Quién trae a Cervantes, entonces**: talleristas, proveedores de servicio, proveedores de **insumos**
y Virgilio (lo que vuelve del depósito). Nada más.

**Y lo que NO se vuelve a modelar** `[usuario 2026-09-14, textual]`: *"recibir, toca insumo y me
aparece todo lo que está en recepción de insumos, como ya lo modelamos"* y, para el conteo, *"dentro
del módulo conteo tendría que aparecer lo del módulo de relevamientos. Es esa lógica"*. Las dos cosas
ya existen (Recepción de Insumos con sus rubros, el pesaje de pallets y el cruce contra OC;
Relevamientos con el cronograma por sector y el conteo por envase + sueltas), así que la tablet **las
abre** con `?volver=tablet` en vez de tener una segunda copia. **El conteo propio de la tablet — la
tabla contra el online con CSV, §4cv — se borró**: el conteo del operario es el Relevamiento, y el
ajuste lo sigue decidiendo el operador del sistema en Validación de Stock.

**Cómo se elige a quién** `[usuario 2026-09-14]`: primero el **tipo** (tallerista / prov. de servicio /
prov. de art. terminado) y recién adentro la contraparte. Antes caían las 33 juntas en una grilla:
en la tablet del galpón eso no se lee. Si un tipo tiene una sola contraparte (Virgilio), se entra
derecho.

### 4dq. Stock General: entran Prov AT y tránsito, se va Virgilio (2026-09-14)

Tres pedidos del dueño en una sola pantalla `[usuario 2026-09-14, textual: *"Acá en stock general
falta el stock transito PS"*, *"agrega provedor de at con sus repectivas cajas y cartones"*,
*"agrega sector transito porque tengo que saber cuanto tengo de stock transito: cuando vuelve del
ps correspondiente subiria el stock y si va al siguiente ps sale del stock de transito"*, *"no
quiero que aparezca este modulo de virgilio dentro de stock general"*]`.

**El hallazgo de fondo: el árbol armaba grupos con 4 tipos de ubicación y descartaba EN SILENCIO
los otros 4.** `[dato]` `proveedor_at` (12 ubicaciones), `inyector` (4), `virgilio_sector` (2) y
`analisis` (1) no tenían grupo: si entraba stock ahí, era **invisible**. Hoy las 19 están en 0, por
eso nadie lo había notado.

**Tránsito PS NO es una ubicación, es un corte.** `[Seguro, leído de stock_transito_ps_bundle]` La
pieza que un PS ya devolvió y espera para irse al PS siguiente **vive físicamente en el sector del
componente** (Crudo, Procesado, Bombilla) y ya está contada ahí. Por eso el grupo nuevo lo dice
explícito y **no suma a ningún total**: si se sumara, esas unidades se contarían dos veces. El
número es exactamente el que describió el dueño: **entregas del PS de origen − envíos al PS
siguiente**. Hoy son 15 pares y los 15 están en 0 (todavía no hay movimientos de ese tipo).

**Prov AT: mostrar su inventario no alcanzaba.** `[dato]` Las 12 ubicaciones de Proveedor de
Artículo Terminado tienen **0 filas de inventario**, así que el grupo habría salido vacío. Lo que se
muestra son las **cajas y cartones que la receta de sus artículos consume**, con el stock real en la
ubicación del proveedor — que está en 0, y ese es justamente el dato: hay que cargarlo. Son
**9 proveedores activos**, de 1 a 39 piezas cada uno:

| Prov AT | Cajas + cartones |
|:---:|---:|
| Cabral | 39 |
| Pintos | 16 |
| Maspoli | 9 |
| Lopez Jose | 6 |
| The Plast | 4 |
| Carriero | 3 |
| Melinox · Paternal Goma · Tierra Nativa SA | 1 c/u |

**Ojo con Pettofrezza**: tiene **10 artículos asignados** en `articulo_prov_at` pero está
`proveedor_at.activo = false`, así que no aparece. O queda inactivo y esas 10 asignaciones sobran, o
hay que reactivarlo. `[dato — falta que lo diga el dueño]`

**Dónde vive:** RPC nueva `stock_general_extra_bundle()`, aparte de `movimientos_bundle` a propósito
(ese lo comparten todas las pantallas y no hay que inflarlo). Si la RPC falla, Stock General **no se
cae**: muestra el resto del árbol sin esos dos grupos.

**Y un tercer nombre cruzado, de la misma familia que los de §4dp:** en Stock General la columna
decía **"Máximo"** y leía el **mínimo** del bundle. Ya lee el máximo.


## 4dr. Generar OC: tocar el Máximo muestra de qué se compone (2026-09-14)

`[usuario 2026-09-14, textual: *"el módulo de generar órdenes de compra? quiero que, al tocar en
máximo, pueda ver de qué se compone. Por ejemplo, quiero ver cuántos meses es el máximo definido y
qué artículos y qué venta responde a ese máximo... Primero en unidades para después pasarse a
kilos"*]`.

La celda **Máximo** de Generar OC ahora es clickable (cuando no es "—") y abre un modal con el
desglose. Sale de la RPC nueva **`oc_maximo_desglose(p_componente_id)`** (lectura pura, 154→155
funciones). Muestra: máximo + origen, **meses** (`ubicacion.meses_stock` del sector), consumo/mes y
**consumo × meses**, y la tabla que lo arma.

**Hay DOS caminos, porque la demanda de un insumo se arma distinto según qué sea** `[Seguro]`:

1. **Insumo por receta** (cartones, cajas, plásticos-pieza, bombillas, remaches, garage, flejes): el
   consumo sale de `v_consumo_demanda` (est_madre → receta `articulo_componente` → `componente_bom`
   → rutas). El desglose es **por ARTÍCULO**: su venta (`est_madre.proy_uni_mes`) y lo que ese
   artículo consume del insumo (uni/mes). En flejes el aporte se muestra también en kg (× `kg_x_uni`).
2. **Resina** (sector 14, Bolsas Plásticas): NO entra en ninguna receta — se relaciona por
   `componente.material_id`. El desglose es **por PIEZA inyectada** (los mangos), con su consumo y
   sus kg (× `kg_x_uni` × (1+desperdicio)). El máximo de resina se redondea a bolsas de 25 kg, así
   que `consumo × meses` (p.ej. PP 770,5 kg × 2,5 = 1.926) no da exacto el máximo guardado (2.025,
   que además es `fisico`, una foto vieja): el modal lo aclara.

**Regla que deja para leer un máximo:** el desglose EXPLICA el número sólo cuando el origen es
`est_madre` / `consumo_x_meses` (ahí máximo = consumo × meses, exacto). Cuando es `fisico`,
`migrado_de_minimo`, `cinco_cajones` o master, el máximo se puso a mano o por otra regla, y el modal
muestra el consumo real **como referencia**, avisando que no viene de la demanda.

## 4ds. Proporciones: "artículo compartido" NO es lo mismo que "reparto de volumen" (2026-09-14)

**Pedido del dueño, textual:** *"En el módulo de proporciones dentro de tallerista. Quiero que
aparezcan, quiero que borres lo que hay y que aparezcan solo los artículos compartidos. Es decir,
los artículos que según las rutas se lo llevan más de un tallerista."* Y a continuación:
*"Después te digo las proporciones."* Así que la pantalla queda mostrando **sólo** los compartidos
y la columna Proporción sigue en PENDIENTE, esperando que él dicte los porcentajes.

**El hallazgo que importa** [dato: `ruta_paso` × `ruta` × `tallerista`, 2026-09-14]: que dos
talleristas toquen el mismo artículo **no significa que se repartan el volumen**. Hay dos casos
distintos y sólo uno admite un porcentaje:

| Caso | Qué pasa en la ruta | ¿Lleva %? | Hoy |
|---|---|---|---|
| **Mismo paso** | dos talleristas producen **el mismo `comp_salida`** (la ruta está duplicada por tallerista) | **SÍ**: ahí se parte el volumen | **6 artículos** |
| **Paso propio** | cada uno hace **un paso distinto** de la misma ruta (uno el mango, el otro el armado) | NO: van en cadena, cada uno hace el 100 % de lo suyo | 13 artículos |

Total: **19 artículos** con ≥2 talleristas, de los cuales **sólo 6** esperan un porcentaje.

Los 6 con paso duplicado: **315** y **609** (Cavallero German / Pettofrezza Rafael), **500** y
**510** (Alex Escalante / Martin Cornejo), **505** (Danica Garcia / Lucho — el tercero, Martin
Cornejo, hace X4, otro paso) y **506** (Alex Escalante / Martin Cornejo en GRJ7 — el tercero,
Gentile Norberto, hace el 506 terminado).

**Trampa a no repetir:** el artículo 505 aparece con `num_talleristas = 3` y el 506 también, pero
en los dos el tercero hace otra cosa. Si alguien reparte 100 % entre los 3 por mirar sólo el
contador, reparte mal. La cuenta del porcentaje se hace **por paso**, no por artículo.

**Dónde está escrito:** `Talleristas/Proporciones/Proporciones_GP2.html` (la distinción se calcula
en el front sobre `articulos_compartidos` del bundle: una parte que declaran 2+ talleristas del
mismo artículo = mismo paso). `proporciones_bundle()` no cambió; su rama `talleristas` (la vista
vieja, que listaba también los exclusivos) quedó sin usar.

## 4dt. Los porcentajes que dictó el dueño: 2 son reparto y 3 son rutas mal cargadas (2026-09-14)

Al ver la pantalla con los 6 pasos compartidos, el dueño dictó [usuario, textual]:
*"505 Danica Garcia 40/ Lucho 60 — 506 Alex Escalante 70/ Martin Cornejo 30 — 500 solo martin —
510 solo carlos — 315 y 609 solo pettofrezza"*.

**Sólo 2 de los 5 renglones son porcentajes.** Los otros dicen "solo fulano", o sea que el segundo
tallerista **no debería estar en la ruta**: no es un reparto mal medido, es un dato mal cargado.

| Artículo | Qué dijo | Qué hay hoy en `ruta_paso` | Qué es |
|---|---|---|---|
| 505 | Danica 40 / Lucho 60 | Danica + Lucho en el paso `505` | **reparto** |
| 506 | Alex 70 / Martin 30 | Alex + Martin en `GRJ7` | **reparto** |
| 500 | solo Martin | Alex (5 rutas) + Martin (5 rutas) | **borrar las de Alex** |
| 315 | solo Pettofrezza | Cavallero (5) + Pettofrezza (5) | **borrar las de Cavallero** |
| 609 | solo Pettofrezza | Cavallero (5) + Pettofrezza (5) | **borrar las de Cavallero** |
| 510 | solo Carlos | **Alex (5) + Martin (5); Carlos NO está** | **no cierra, preguntado** |

**El 510 no cierra** [dato: `ruta_paso` del art 510, 2026-09-14]: Carlos Aguirre (tallerista 9) no
aparece en ninguna ruta del 510 — ahí están Alex Escalante y Martin Cornejo — y en GP2 hace
Repostería (115, 544, 580, 802), no Abrelatas. El 510 era "Abrelata Uña Cromado" (hoy "Abrelata Uña Inox", ver abajo). No se tocó nada
hasta que el dueño aclare si (a) quiso decir otro tallerista, o (b) Carlos hace el 510 y las dos
rutas que hay son las equivocadas. **No se adivina.**

**Dónde van a vivir los porcentajes:** hoy **en ningún lado**. GP2 no tiene tabla de proporciones
(la vieja `Proporcion_Articulo_Tallerista` de `public` estaba vacía y por eso nació el PENDIENTE).
Hace falta crearla en GP2 — clave (artículo, paso/`comp_salida`, tallerista) + `pct`, con la suma
del grupo en 100 — antes de poder guardar el 40/60 y el 70/30.

**Dato que descarta un miedo razonable** [dato: `db/vistas_GP2.sql`]: la ruta duplicada por
tallerista **no** duplica el consumo ni el costo. Las vistas de demanda arman los `edges` con
`SELECT DISTINCT comp_entrada_id, comp_salida_id`, así que dos rutas iguales colapsan en una
arista. Borrar las rutas de más corrige el "quién lo hace", no cambia ningún número de plata.

## 4du. El reparto ya manda sobre el máximo de cada tallerista (2026-09-15)

El dueño autorizó los tres borrados de ruta y la tabla de proporciones, y agregó [usuario,
textual]: *"fijate que los maximos tienen que tener en cuenta esta proporcion"*. Eso destapó que
**el máximo de un tallerista nunca se calculaba**.

**Lo que estaba mal** [dato: `inventario` × `ubicacion`, 2026-09-15]: de los 288 máximos en
ubicaciones de tallerista, 196 eran `migrado_de_minimo` (el mínimo viejo del 14-09) y 92 estaban
en null. **Ninguno** salía de la demanda, porque `v_nivel_stock` —la vista que alimenta
`recalcular_maximos_insumos`— filtra `u.tipo = 'sector'` y nunca miró una fila de tallerista.
Con la ruta duplicada, el efecto era el doble conteo: Danica y Lucho tenían **15.000 de Cartón 505
cada uno** para una demanda de 28.108 uni/mes del 505, y lo mismo en Clavo, Mango y Cuchilla.

**Lo que se construyó** (schema GP2, detalle en `GP2_MAPA.md`):

| Objeto | Para qué |
|---|---|
| `reparto_tallerista` | la tabla del % por paso (artículo + `comp_salida` + tallerista) |
| `v_reparto_efectivo` | el % efectivo: el dictado, o 100 si el paso lo hace uno solo |
| `v_consumo_tallerista` | demanda del artículo × ese % = lo que consume cada tallerista |
| `v_nivel_stock_tallerista` | `max_calc = consumo × meses_stock` (los 12 talleristas tienen 1 mes) |
| `recalcular_maximos_talleristas()` | escribe el máximo con origen `est_madre_x_reparto` |
| `reparto_guardar()` | la puerta de la pantalla: valida, guarda y recalcula de una |

**Resultado en los 16 máximos que se tocaron** (sólo la cadena del 505 y el 506):

| Componente | Tallerista | Antes | Ahora |
|---|---|---|---|
| Cuchilla Pela Afilada Caja (Z23) | Danica Garcia | 30.000 | 11.243 |
| Cuchilla Pela Afilada Caja (Z23) | Lucho | 30.000 | 16.865 |
| Cartón 505 (B3A) | Danica Garcia | 15.000 | 11.243 |
| Cartón 505 (B3A) | Lucho | 15.000 | 16.865 |
| Uñas Zinc. (C10) | Martin Cornejo | 33.172 | 12.844 |
| Uñas Zinc. (C10) | Alex Escalante | 28.280 | 15.020 |

11.243 + 16.865 = 28.108, que es exactamente la demanda del 505: antes sumaban 30.000 y 60.000.

**Dos decisiones que quedan escritas:**
1. **No se limpia el máximo de la fila que quedó sin consumo** (24 filas hoy). Un consumo 0 puede
   ser un dato que falta (un artículo sin proyección en `est_madre`), no una verdad. Se informan.
2. **Un paso compartido sin reparto dictado parte en partes iguales**, marcado `es_supuesto`. Es
   un default para no contar el 100 % dos veces; el número real lo dice el dueño. Hoy el único
   así es el **510** (Alex / Martin), que espera su respuesta.

**Lo que NO se tocó y sigue esperando decisión:** los otros **284 máximos de tallerista**, que
siguen siendo el mínimo viejo migrado. `recalcular_maximos_talleristas(false)` los recalcula
todos de una (294 filas cambiarían, la suma baja 18 %: de 1.241.303 a 1.019.605 unidades).

## 4dv. C12B: la paleta sin cromar es un código propio, y eso es la convención de la casa (2026-09-15)

**Lo que pidió el dueño** [usuario 2026-09-14, textual]: *"En el articulo 515 y 615, cuando vuelve de
alex escalante quiero que sea C12B y despues de cromarse C12"*.

**Cómo quedaron las 6 rutas** (994/995/1010 del 515 y 1001/1002/1011 del 615):

```
… → Alex Escalante (armado) → C12B → Pedernera Ilario (cromado) → C12 → Alex Escalante → 515/615
```

Antes, Alex entregaba C12 y Pedernera hacía un paso `entrada = salida` sobre C12: el cromado no
tenía dónde apoyarse, porque la pieza entraba y salía con el mismo código.

**ESTO NO ES UNA EXCEPCIÓN, ES LA REGLA QUE YA SEGUÍA EL RESTO DE GP2.** Medido el 2026-09-15:
**260 pasos de proveedor de servicio en 240 rutas ya tienen entrada ≠ salida**, contra 71 pasos en
65 rutas con entrada = salida. Y el sufijo `B` para "antes del servicio" ya estaba en uso:
`PA4B→PA4`, `PA5B→PA5`, `PA10B→PA10`, `PA13B→PA13`, `PA18B→PA18`, `PC15AB→PC15A`, `PC3B→PC1B`,
`D13B→D13`, `Z2B→Z2A`, `Z3B→Z3A`. 515/615 eran la excepción; ahora no lo son.

**El costo NO se movió, y eso se verificó dentro de la misma transacción** (la migración tenía un
`raise` que revertía todo si algo cambiaba un centavo):

| Código | Antes | Después |
|---|---|---|
| 515 | 411,76 | 411,76 |
| 615 | 491,40 | 491,40 |
| C12 | 88,49 | 88,49 |

**LA TRAMPA QUE CASI CUESTA $ 62,74 POR UNIDAD:** `v_costo_componente` pega el precio del tallerista
por **(tallerista, `comp_salida_id` del paso)** — o sea, sobre la pieza que el tallerista ENTREGA.
El precio de Alex ("Batidor Resorte Armado", ARS 62,7375) estaba cargado sobre C12. Al pasar el
armado a entregar C12B, **si el precio se quedaba en C12 ningún paso entregaba C12 y el armado
desaparecía del costo** de 515, 615 y C12. Por eso la migración lo mueve a C12B. Vale para cualquier
corte futuro de este tipo: **el precio del tallerista viaja con la pieza que entrega, no con el nombre.**

**Por qué el servicio de Pedernera siguió valiendo lo mismo:** el paso dejó de ser `selfsrv`
(entrada = salida) y pasó a ser una arista de `edges`, pero las dos ramas de la CTE `srv` terminan
dando el mismo par `(componente, Pedernera)`. El valor y el conteo de `faltan_precios` no se movieron.

**Efecto lateral BUENO:** el cromado ahora tiene dónde apoyarse. Hoy `C12B` y `C12` cuestan los dos
88,49 porque **Pedernera / Cromado no tiene precio cargado**; el día que se cargue, la diferencia
entre los dos ES el cromado. Antes no había forma de separarlo.

**El máximo lo puso la base sola, no la migración.** `trg_maximos_rutas` (en `ruta_paso`, FOR EACH
STATEMENT → `fn_recalc_maximos_insumos`) se disparó con el UPDATE y le calculó a C12B **máximo 1656,
origen `est_madre`** — el mismo que C12. Es exactamente lo que ya pasa con los pares existentes
(`PA4B` y `PA4` tienen los dos 7.680 `est_madre`). **Consecuencia a tener presente:** Sector Bombilla
ahora muestra DOS líneas de 1.656 para lo que físicamente es la misma pieza en dos etapas, así que el
"falta" del sector la cuenta dos veces. Es el comportamiento que ya tenían los otros 10 pares, no un
bug nuevo — pero si molesta, se corrige poniendo el máximo sólo en el código que se consume (C12).

**Detalle de ubicación que queda a criterio del dueño:** C12B se creó en el **mismo sector que C12**
(7, Bombilla), como `PA4B`/`PA4`. Otros pares se modelan al revés: `D13B` y `Z2B` viven en Sector
Crudo y sus pares cromados en Sector Procesado. Si la paleta sin cromar en realidad se guarda en otro
lado, se mueve la fila de `inventario`, no el componente.

**Lo que NO se tocó, a propósito:** la receta del artículo (`articulo_componente`) sigue diciendo
515 → C12 y 615 → C12, porque el artículo se arma con la pieza YA cromada. Y los 6 pasos
`tallerista` que van de C12 a 515/615 quedaron igual.

## 4dw. El 510 lo hace solo Alex, la pantalla queda de sólo lectura, y por qué (2026-09-15)

**Tres cosas del mismo tirón** [usuario, textual]: *"510 solo alex lo hace"*, *"Que no se pueda
modificar la proporción en el programa"* y *"quiero que me pongas los máximos de cada parte del
artículo que se está proporcionando"*.

**1. El 510.** Se borraron las 5 rutas de Martin Cornejo (601, 602, 604, 605, 607). Alex Escalante
pasa al 100 %: A15 y Cartón 510 van de 3.170 a **6.340**, Uñas Zinc. y Remache de 15.020 a
**18.190**. Con eso ya no queda ningún paso compartido sin porcentaje dictado: los dos que quedan
son el 505 (Danica 40 / Lucho 60) y el 506 (Alex 70 / Martin 30).

**2. Por qué la pantalla ya no se edita — el incidente.** Mientras se cargaban los porcentajes,
alguien abrió la pantalla y apretó **Guardar** en los tres pasos (15:00:24, :26 y :27). La pantalla
mostraba el **50/50 que era un DEFAULT** para el 510, y ese clic lo grabó en
`reparto_tallerista` como si fuera un dato dictado. Resultado: cuando después se sacó a Martin,
Alex se quedó con el 50 % guardado, o sea **la mitad del máximo que necesita**.

Dos arreglos, no uno:
- **La pantalla no escribe más.** `reparto_guardar` perdió el `EXECUTE` para `anon`; el % se carga
  por SQL. Un default que se puede guardar con un clic deja de ser un default.
- **`v_reparto_efectivo` normaliza.** El % guardado se lleva a base 100 **sobre los talleristas que
  siguen haciendo el paso**: borrar la ruta de uno ya no puede dejar al otro con su mitad. Si
  ninguno tiene % —o sólo algunos— va mitad y mitad marcado `es_supuesto`, que es "falta que lo
  diga el dueño", no un dato.

**3. Los máximos en la pantalla.** Cada paso compartido muestra sus partes con el máximo de cada
tallerista, una columna por cabeza con su %. Ahí se ve que las dos columnas **suman** el consumo
del artículo en vez de duplicarlo: Cartón 505 = 11.243 (Danica) + 16.865 (Lucho) = 28.108.

**Lo que quedó suelto y hay que mirar:** Martin Cornejo conserva máximos de partes que ya no usa
(A15 y Cartón 510 en 3.170), porque la regla es **no limpiar la fila que quedó sin consumo** — un
consumo 0 puede ser un dato que falta. Hoy son 27 filas así en todos los talleristas.

## 4dx. Los 284 máximos migrados y las 27 filas sin consumo: cerrado (2026-09-15)

El dueño dio el "dale" a las dos pendientes de 4du/4dw.

**1. Se recalcularon TODOS los máximos de tallerista** (`recalcular_maximos_talleristas(false)`):
**270 filas** cambiaron. El mínimo viejo migrado ya no manda en ninguna: hoy **291 de 292** filas
con máximo dicen `est_madre_x_reparto`, o sea demanda × su % × meses. La suma baja de **1.241.303
a 1.024.041 unidades (−17,5 %)**, y no es un ajuste parejo: Danica sube (51.819 → 71.467, porque
el mínimo viejo le quedaba corto) y Martin, IJUPA y Gentile bajan fuerte.

**2. La regla para la fila que queda sin consumo** — la duda de 4du quedó resuelta partiéndola en
dos, que es la distinción que importa:

| Caso | Qué significa | Qué se hace |
|---|---|---|
| Sin consumo **y sin ruta** | ese tallerista ya no recibe esa parte (quedó de una ruta borrada o de la migración) | **se limpia** (25 filas) |
| Sin consumo **pero con ruta** | sí la recibe; lo que falta es la demanda (artículo sin proyección en `est_madre`) | **no se toca**, se informa |

Las 25 que se limpiaron son justamente la resaca de la limpieza de rutas: los 5 cartones y
capuchones de Cavallero German (315 y 609), el A15 de Martin Cornejo (510), el "Pliego Ad 500" de
Gentile Norberto y 7 piezas de rompenueces de Fábrica, entre otras.

**Las 2 que quedan abiertas, y son un dato que falta, no un error:** `PB6` (Inser. Neg. Espat) en
Alex Escalante con 60, y `E6-M194` (Pala Canelón tras M194) en Fábrica con 696. Las dos tienen
ruta pero su artículo no proyecta venta en `est_madre`.

## 4dy. El máximo de Crudo/Procesado ahora es demanda×meses, no "5 cajones"; y el PS no tiene máximo (2026-09-15)

`[usuario]` textual, mirando el módulo **Faltantes** (columna "MÁXIMO (5 CAJ)"): *"El maximo
recalculalo. Tiene que salir de la demanda por la cantidad de meses. Esto estaría mal"*. O sea:
el máximo físico de **5 cajones** (capacidad del lugar) estaba mal como criterio; el máximo tiene
que ser **consumo × meses_stock del sector** (lo que ya calcula `GP2.v_nivel_stock.max_calc`).

**Por qué no se recalculaban solos:** `recalcular_maximos_insumos()` tiene un `where es_insumo`
que **saltea Sector Crudo (1) y Procesado (2)**. Por eso esas piezas conservaban el `cinco_cajones`
sembrado, y las que no lo tenían (Descorazonador 1686, Grampa Batidor W1B) quedaban en NULL aunque
la vista ya tenía el número. `v_nivel_stock` filtra `u.tipo='sector'` pero **no** filtra `es_insumo`:
la maquinaria estaba, faltaba que la RPC la usara.

**Lo que se ejecutó (con OK del dueño, meses=1, incluyendo la reserva FAAT):**
```sql
update "GP2".inventario i set maximo = v.max_calc, maximo_origen = 'est_madre'
from "GP2".v_nivel_stock v
where i.id = v.inv_id and v.sector_id in (1,2) and v.max_calc > 0
  and i.maximo is distinct from v.max_calc;   -- 159 filas
```
- **159 filas** pasaron de físico/NULL a `est_madre`. Suma vieja Crudo+Procesado ~1,77 M → nueva ~0,83 M,
  pero **NO es parejo**: las de alta demanda SUBEN (A10 Cpo Uña 8.475 → 16.928, porque 1 mes de venta
  es más que 5 cajones) y los físicos sobredimensionados BAJAN fuerte (LL7B 94.340 → 6.644; ABPM
  75.000 → 114). Descorazonador → 402, Grampa Batidor → 552.
- **2 quedan con `cinco_cajones`** porque su artículo no proyecta demanda en `est_madre`: **RULETA**
  (27.175) y **A9 Cpo Mango Alambre Corta Queso** (3.845). No se inventan; dato pendiente.
- **Deuda:** el `where es_insumo` sigue en la RPC, así que el próximo recálculo de insumos NO mantiene
  Crudo/Procesado, y una corrida de "5 cajones" podría volver a pisarlos. Para que la demanda quede
  como regla permanente hay que sacar ese guard (cambio de función, pendiente de OK).

**El PS no tiene máximo propio** `[usuario]`: *"en proveedor de servicio no tiene que haber un
maximo... a los PS se les manda segun el maximo que necesita el sector procesado"*. Se pusieron en
**0 las 108 filas de inventario de PS** (los 22 que tenían valor —reserva FAAT y mínimos migrados— más
los 86 en NULL). En la pantalla Stock General el rubro Prov. Servicio ya no muestra la columna Máximo.
Inyector (4 ubic) y Prov AT (12 ubic) no tienen filas de inventario, así que ya estaban en 0.

**Dos ubicaciones singleton que se preguntaron:**
- **`analisis` ("Para Analizar", id 46)** — NO es basura: es el **buzón de las piezas sin sector**.
  Un flujo manda ahí el componente que no tiene `sector_id` (`ubic_de('analisis')`, y **revienta** si
  la ubicación no existe), y hay una vista que muestra "stock apartado en Para Analizar". Tiene función,
  **no se borra**.
- **`virgilio` ("Virgilio (Distribución)", id 33)** — el dueño pidió "eliminar por ahora", pero **no se
  borró**: la usan recepción Virgilio, los traslados (mueve stock entre `virgilio_sector` y `virgilio`)
  y es el **fallback** de una pieza sin sector (`coalesce(ubic_de('sector'), ubic_de('virgilio'))`), y
  tiene **268 filas de inventario** colgadas. De la pantalla Stock General ya está fuera (4dq). Borrarla
  de verdad rompe esos flujos: espera definición del objetivo real.

## 4dz — Auditoría de simplificación de tablas (2026-09-15, dueño: "emprolijá sin pedir permiso, sin romper, menos tablas y con nombres claros")

Recorrida tabla por tabla del schema GP2 buscando qué sacar. Regla del dueño: fewer/clearer tables, pero "sin romper el programa". Resultado:

**Borrado (seguro, verificado):**
- **Simulador muerto `__sim`**: tabla `__sim_base` (3 col, 0 filas, "pizarrón" de un arnés de prueba de rutas) + funciones `__sim_articulo` / `__sim_exec` / `__sim_ruta`. Cero llamadores (ninguna función/vista/pantalla), sin FKs. `db/verificar.sql` lo nombra solo en un COMENTARIO (de dónde salió el invariante RECETA vs RUTA), no lo ejecuta. −1 tabla.
- **`articulo_prov_at.creado_en`**: timestamp de auditoría con 0 lecturas. (Ojo: las otras dos que el dueño quería sacar de esa tabla, `marca` y `n_caja`, SÍ están en uso — las devuelve `entregas_prov_at_bundle` a EntregasAT.)

**NO se tocó (la premisa "no sirve" era falsa):**
- **`carton_formato` (10) + `carton_categoria` (5)**: NO son dos listas repetidas, son DOS NIVELES. formato = reglas numéricas (múltiplos/mínimos/pliegos); categoría = subdivisión del formato "C" (Abrelatas/Pelapapas/Pisapapas/Resto/Sacacorchos) + el comodín `mezcla_libre` (Sacacorchos). `_oc_validar_carton` usa las dos (formato para los números, categoría para agrupar pliegos del tipo C y el comodín). Fusionarlas = tabla auto-referenciada que complica el validador. Pocas filas = son parámetros, no datos. **Se dejan separadas.**
- **`alerta_recepcion`**: 0 filas hoy pero VIVA — la escribe `tablet_registrar` cuando recibido > esperado; la leen `inicio_bundle`/`alertas_bundle`; la cierra `alerta_recepcion_marcar`. 0 filas = todavía no hubo exceso, no muerta.
- **`articulo_prov_at` (91 filas)**: la usan 7 funciones + 3 pantallas (Control/Entregas/Envíos AT). Fusionarla con `articulo` + modelar cartones/cajas por `ruta_paso` es MIGRACIÓN real (su clave es `(proveedor_at_id, cod_art)`, el mismo cod_art se repite entre proveedores; `articulo` es único por código), no un borrado. Queda como proyecto propio, con OK del dueño.

**Pendiente de decisión del dueño (refactors, no tidy-ups):**
- **`articulo.discontinuado` → borrar el artículo al discontinuar**: hoy 1 fila en true (art 311 "Cuchillo De Torta"). Las FKs entrantes son RESTRICT, así que un DELETE pelado FALLA: hay que arrastrar `articulo_componente` (6) + `ruta`/`ruta_paso` (6) + revisar `est_madre` (join por cod). `articulo` y `componente` tienen CADA UNO su `discontinuado` (distintas: `v_reposicion` filtra por la del componente, `v_consumo_demanda` por la del artículo). Recomendación: conservar la columna salvo que se construya una baja-en-cascada probada; con 1 caso la columna cuesta casi nada y el borrado pierde histórico/reactivación.

**Housekeeping**: `db/` (backup del schema) queda a regenerar por los borrados de `__sim`/`creado_en`; no rompe nada estar desfasado (el test chequea que lo que las pantallas usan exista en db/, no la ausencia de extras).

## 4ea — Cómo se le ENVÍA a cada proveedor: la unidad la pone el proveedor, el bulto lo pone la pieza (2026-09-17)

`[usuario]` La tablet ya no manda "unidades" a todos. Cada proveedor dice en qué se le envía, y eso
vive en `GP2.proveedor_servicio.envio_unidad` / `envio_uni_x`. Hay dos formas, y la diferencia
entre ellas es de dónde sale el bulto:

- **Una unidad para TODO el proveedor** — `AJ Adhesivos` (id 12): `envio_unidad='paquetes'`,
  `envio_uni_x=100`. El sugerido y la cantidad se muestran y se cargan en paquetes (techo), y al
  registrar se multiplica por 100: el inventario nunca ve paquetes.
- **Por PESO, con el bulto al lado** — `Hernandez Julio` / Ximpa (id 8): `envio_unidad='kg'`, sin
  `envio_uni_x`. `[usuario 2026-09-17, textual: "para lo que son partes plásticas, que empieza con la
  letra P, el envío sugerido tiene que estar nominado en bolsas… cuántos kilos le están mandando y
  cuántas bolsas eso significa. Después, para A1, B12, B4B y C2, el sugerido en kilos y en cajones a
  enviar"]`. Acá el bulto **no es uno solo para el proveedor: cambia por pieza**, y lo decide el
  sector — **Sector Plástico → bolsas, el resto → cajones**. El tamaño del bulto es
  `componente.uni_x_cajon` en los dos casos (en los plásticos esa columna **es** el tamaño de la
  bolsa, mismo criterio que la OC de partes plásticas).

> **2026-09-18 — la pantalla de Julio dejó de tener columna de bulto** (v1.14.0): sus
> bolsas/cajones pasaron al renglón chico de debajo del campo de kg, como en todas las demás
> formas, y se calculan de los kg (ya no se corrigen a mano). Lo de abajo describe el modelo —qué
> es el bulto y de dónde sale—, que no cambió; el layout sí. Ver 4ee.

Cómo queda la pantalla de Julio (Tablet, Enviar): `Pieza | Sugerido | Cantidad (kg) | Cantidad
(bolsas / cajones)`. `[usuario 2026-09-17]` El **sugerido se mira en bultos ENTEROS** (no en kilos),
la Cantidad (kg) se precarga con el peso de esos bultos completos (2 cajones de 750 a 0,04 kg = 60
kg), y **las dos cantidades son el mismo tipo de campo**: la de bolsas no se muestra distinto que la
de cajones. **Un bulto nunca va partido**: bolsas y cajones se redondean **para arriba** en el
sugerido, en el autocompletado desde los kg y en lo que se registra (`"no puedes poner 4,83, sino
que pones 5"`). Los **kg son lo que se tipea y lo que se registra** (la balanza
manda; viaja `unidad='kg'` y la base lo pasa a unidades con `kg_x_uni`). Los **bultos se
autocompletan** desde los kg mientras el operario no los toque (si los corrige a mano no se le
pisan) y viajan a `movimiento.cajones` vía `crear_envio_ps(..., p_cajones)`. Sin `kg_x_uni` la fila NO se convierte: se carga en unidades
como siempre — no se inventa el factor. `[dato 2026-09-17]` las 11 piezas de Julio (A1, B12, B4B,
C2 metálicas; PA10B, PA13B, PA18B, PA4B, PA5B, PC15AB, PEP2 plásticas) tienen las dos columnas
cargadas, así que las 11 convierten.

**Qué falta:** el resto de los proveedores sigue en unidades; la unidad de envío se define caso por
caso con el dueño (ése fue el acuerdo al arrancar con AJ). **Ahora son CUATRO formas, no dos: ver
4ec (Ester) y 4ef (Guazzaroni, Jade y otros cinco), con la tabla de las cuatro en 4ef.**
**Y el sugerido ya no se precarga en el campo Cantidad de los P.S.: sólo se muestra (ver 4ee), que
además se eligen y se cargan por TARJETAS (4eg).**

## 4eb. El 506 pasa al molde del 500/510 (sin GRJ7) y el adhesivado de pliego es un PASO, no un subcomponente (2026-09-17)

> ⚠ **La parte de PLIEGO de esta sección caducó el 2026-09-18 (§4el)**: el 500 y el 506 dejaron de
> llevar pliego y llevan cartón (`CART500` / `CART506`), así que su cadena `pliego → AJ → pliego
> adhesivado` ya no existe. Todo lo demás de acá (el 506 sin GRJ7, los dos talleristas, el resto de
> las rutas) sigue vigente, y la regla del adhesivado como PASO sigue valiendo para los otros 10 pliegos.

`[usuario 2026-09-17, textual]` *"Te hago un cambio para el 506: Ahora va a ser la misma lógica
que el 500 y 510. Gentile Norberto no ensambla más. Ahora ensambla Martin Cornejo o Alex
Escalante. Y desaparece el GRJ7. Ahora C10, CV9 Y A10 se le manda a el tallerista final. No hay
conversion a GRJ7."* Y, aparte: *"La ruta para todos los pliegos es: pliego sin adhesivar --> AJ
adhesivados --> pliego adhesivado --> tallerista final. Esa sería la ruta paso, esta mal que lo
tomes como un subcomponente. Borralo si es que esta en componente bomb y agrega la ruta como te
digo."* Sobre el precio del tallerista nuevo: *"Fijate en el gemelo 500 o 510 para el costo."*

### Lo que quedó en la base

**506** (artículo 29, componente terminado 400). Receta: `A10 ×1 + C10 ×1 + V9 ×1 + A11 ×1/12 +
Pliego Ad 506 ×1/12` — calcada del 500. **10 rutas** (5 cadenas × 2 talleristas, la convención de
la casa cuando dos hacen el mismo paso), todas con el nombre del tallerista en el título para que
no se vuelvan a leer como duplicadas:

```
Fleje 13   -> M23 -> Jade        -> A10          -> Martin | Alex -> 506 -> Virgilio
Fleje 57   -> M24 -> FAAT -> Guazzaroni -> C10    -> Martin | Alex -> 506 -> Virgilio
CV9        -> Guazzaroni -> V9                    -> Martin | Alex -> 506 -> Virgilio
Pliego 506 -> AJ Adhesivos -> Pliego Ad 506       -> Martin | Alex -> 506 -> Virgilio
A11 (1/12)                                        -> Martin | Alex -> 506 -> Virgilio
```

**Las duplicadas que vio el usuario eran dos cosas distintas**, y sólo una era un error: (a) las
rutas de `A10` como insumo suelto (594/595) **sobraban** — el A10 lo produce la propia ruta del
Fleje 13, igual que el 500 no tiene ruta de insumo para su `C1`/`C10`; se borraron. (b) `CV9`
aparecía dos veces porque el paso del GRJ7 lo hacían dos talleristas: eso **no es un error**, es
el duplicado por tallerista, y ahora se distingue por el nombre de la ruta.

**GRJ7 borrado de todos lados** (componente 284, Sector Garage): receta del 506, su BOM
(`A10`/`C10`/`V9`), las 16 apariciones en `ruta_paso`, las 2 filas de `inventario` (Sector Garage
y Tallerista Gentile, las dos en stock 0, sólo tenían máximo), y el componente. **Cero
movimientos**, así que no se perdió historia. Las **Proporciones** (`reparto_tallerista`
Alex 70 / Martin 30) se mudaron del GRJ7 al `506` terminado: el reparto sigue siendo el mismo, lo
que cambió es sobre qué salida se aplica. `sector 9` (Garage) **sigue existiendo**: viven ahí los
otros 21 GRJ.

**Precios de tallerista**: las filas del GRJ7 se repuntaron al `506` (Martin $8,99 · Alex $8,988,
concepto "Abrelata Uña 506 Armado") — es exactamente el molde del 500, donde Martin cobra $9,00
por armar Y envasar. **Se borró el "Envasado 506" de Gentile ($70/uni, cargado el 2026-09-01)**:
Gentile ya no toca el 506 y el gemelo no tiene una línea aparte de envasado. Si algún día vuelve,
el número era 70 ARS.

### Los pliegos: el adhesivado estaba modelado DOS veces

Había tres cosas diciendo lo mismo para cada uno de los **12 pliegos** (500, 506, 557, 558, 654,
658, 659, 758, 759, 762, 763, 769): un `componente_bom` `Pliego Ad X = 1 × Pliego X`, una ruta
huérfana `Insumo PLIEGOX -> PLIEGO ADX (AJ Adhesivado)` sin artículo, y la ruta del artículo que
arrancaba directo en el `Pliego Ad`. Quedó **una sola** ruta por artículo:

```
Pliego X (insumo, 1/12 ó 1/16) -> AJ Adhesivos -> Pliego Ad X -> tallerista final -> Virgilio
```

Se borraron los 12 BOM y las 12 rutas huérfanas. La **receta sigue con `Pliego Ad X`** y eso es
deliberado: `v_consumo_demanda` siembra en la receta (lo que el tallerista recibe) y camina hacia
atrás por las aristas de la ruta hasta el pliego sin adhesivar. Si se pusiera el sin adhesivar en
la receta, el `Pliego Ad` se quedaría sin demanda y la tablet/OC de AJ se rompería. **Verificado:
el consumo de los 12 sin adhesivar no se movió ni una unidad.**

**La fracción NO es la de la caja**: 1/12 en 500 y 506 (caja de 12) pero **1/16** en las
bombillas, que van en caja de 24. Es cuántos blísters salen de un pliego, un dato propio.

### La plata: el pliego dejó de cobrarse ENTERO por unidad

Esto no se pidió, pero sale solo del cambio, y es grande. `v_costo_componente` multiplica el
precio del nodo comprado por `LEAST(cantidad_del_paso_insumo, 1)` — y buscaba esa cantidad por el
componente **comprado**. Con el `Pliego Ad` (fabricado) como insumo del artículo y el pliego
comprado un salto más arriba, **la fracción se perdía y cada unidad se comía un pliego entero**.
Ahora el paso `insumo` está sobre el pliego comprado y la fracción se aplica:

| | antes | después | delta |
|---|---|---|---|
| 506 | 1.276,75 | **494,50** | −782,25 (−712,25 pliego, −70 Gentile) |
| 500 | 1.285,83 | **573,58** | −712,25 |
| 557 · 558 | 1.259,95 | **523,07** | −736,88 |
| 762 · 763 | 1.259,27 | **522,40** | −736,87 |
| 658 · 758 | 2.029,91 | **1.293,03** | −736,88 |
| 654 | 2.572,91 | **1.836,03** | −736,88 |
| 769 | 2.572,23 | **1.835,36** | −736,87 |
| 659 · 759 | 2.999,91 | **2.263,03** | −736,88 |

Ningún otro costo del sistema se movió, `faltan_precios` quedó en 0 en los 13, y el consumo sólo
perdió la línea del GRJ7. **Esto cierra el "$1.084 que no salen de la receta" de §2c-septies**
(*"Hay que medirlo antes y después del cambio"*): eran el pliego entero. El 506 a mano daba ~$436
y ahora la vista da $494,50; lo que falta para cerrar es el punto de abajo.

### ⚠ Lo que QUEDA mal y no se tocó: el servicio de AJ tampoco se fracciona

El material del pliego ya se divide por 12/16, pero el **servicio de adhesivado sí se sigue
cobrando entero por unidad** ($140 en 500/506, $129 en el resto) porque el CTE `srv` de
`v_costo_componente` no mira ninguna cantidad. Si AJ cobra por pliego —y por precio parece que
sí: $140 contra $777 de cartón— cada unidad de los 12 artículos tiene ~$120-128 de sobrecosto.
Arreglarlo es cirugía del motor de costos (toca a todos los artículos), **no entraba en el pedido
y se dejó anotado como idea, no hecho**. `[deducido, a confirmar con el dueño si AJ cobra por
pliego o por blíster]`.

## 4ec. La tercera forma de enviar: Ester mira BOLSAS y escribe KG (2026-09-17)

Complementa 4ea, que quedó escrita el mismo día por otra sesión: ahí están las dos formas que
existían (AJ escribe el envase; Hernandez Julio escribe kg y el bulto sale del sector de cada
pieza). Ester es una tercera, y por eso hizo falta una columna más.

Cada proveedor de servicio pide/recibe en su propio envase, y eso **no es un detalle de pantalla:
es dato de la base**. Vive en `GP2.proveedor_servicio` con tres columnas:

| columna | qué dice | AJ Adhesivos (12) | Ester (14) |
|---|---|---|---|
| `envio_unidad` | el rótulo del envase | `paquetes` | `bolsas` |
| `envio_uni_x` | cuántas unidades canónicas entran en uno | 100 (pliegos) | 1800 (mangos) |
| `envio_carga_unidad` | en qué unidad se ESCRIBE la cantidad | `null` = en paquetes | `kg` |

**La columna nueva es `envio_carga_unidad`** `[usuario: "en el caso de Ester, el sugerido
que aparezca en bolsas (1800 uni por bolsa) redondeas por arriba y la cantidad pones kg y te
aparece al lado bolsas"]`. Hasta ese día sugerido y cantidad iban en la MISMA unidad (AJ mira 3
paquetes y escribe 3). **Ester mira bolsas pero PESA lo que carga**, así que el sugerido se ve en
bolsas y el campo se escribe en kg, con "= N bolsas" debajo. Los dos casos son la misma máquina
con distinta unidad de carga; no hay un "modo Ester" hardcodeado.

**Ojo con esto: bolsa ≠ cajón.** `componente.uni_x_cajon` de PC2 es **1852** y de PC3B **1800**,
pero la bolsa que pidió el dueño es **1800 para las dos**. Por eso el factor va en
`proveedor_servicio` (uno por proveedor) y no se saca del componente. 1 bolsa = 1800 × `kg_x_uni`
(0,0054) = **9,72 kg**.

**El inventario nunca ve bolsas ni paquetes.** Cuando se carga en kg, el kg viaja tal cual con
`unidad='kg'` y `to_canonical` lo pasa a mangos con `kg_x_uni` (`crear_envio_ps` ya recibía kg);
cuando se carga en paquetes, el front multiplica por el factor antes de mandar. Las bolsas quedan
anotadas en `movimiento.cajones` (mismo criterio que las bolsas calculadas de Julio en 4ea):
informativo, el stock lo mueve la cantidad. El redondeo del
sugerido es **siempre para arriba** (no se pide menos de lo que falta): 112.432 mangos ÷ 1800 =
62,46 → **63 bolsas** → 612,36 kg.

**Si a la pieza le falta `kg_x_uni` no hay forma de pasar de bolsas a kg**, y ahí la fila cae al
modo de AJ (se carga en el envase) en vez de mostrar un kg inventado. Hoy las dos piezas de Ester
lo tienen, así que no pasa.

**Dónde se ve**: `Tablet/Tablet_GP2.html` (v1.8.0) y `Prov Serv/Envios/EnviosPS_GP2.html` (v1.5.0,
donde además se fue la columna "Cajón envío" para ese proveedor: el cajón no es la unidad con la
que se le manda y era ruido). Lo sirven `tablet_bundle` (en cada contraparte) y `envios_ps_bundle`
(en cada PS). **Pendiente: seguir caso por caso con los demás proveedores** — van definidos AJ,
Hernandez Julio, Ester y los 7 del cajón por pieza. **Ya son cuatro formas: ver 4ef.** El sugerido
se sigue MOSTRANDO en su unidad, pero desde el 2026-09-17 ya no se precarga en el campo Cantidad
(ver 4ee).

## 4ed. La tabla de la tablet ENCOGE: el blanco va adentro de la celda, no entre columnas (2026-09-17)

`[usuario 2026-09-17, textual: "optimizame todos los espacios en blanco que hay entre las columnas
en todas las pantallas de envío a ps en la versión tablet"]` (sobre el screenshot de AJ Adhesivos:
3 columnas repartidas en 1.180px, con ~300px de blanco entre "Pliego 506" y su sugerido).

**Por qué pasaba:** `table.t` de `gp2-modulo.css` es `width:100%`. Eso está bien con 8 columnas,
pero desde que Enviar quedó en `Pieza | Sugerido | Cantidad` (§ v1.5.0) el navegador reparte todo
el ancho sobrante de la tablet entre 3 o 4 columnas, y el ojo tiene que cruzar media pantalla para
leer una fila. **Menos columnas hacen MÁS blanco, no menos.**

**La regla que queda** (Tablet, vale para todas las vistas de esa tabla — PS por paquetes, PS por
bolsas+kg, PS por peso, PS/tallerista/inyector común y Recibir, que son un solo render): el bloque de carga (buscador +
cartel de alerta + tabla) **encoge con la tabla**, cada columna mide lo que necesita su contenido
(el encabezado suele ser el que manda: "SUGERIDO (PAQUETES)" es más ancho que el "3"), y el aire
que hace falta va **adentro** de cada celda (padding 12px) en vez de entre columnas. El buscador
mide exactamente lo que miden las columnas, así que no queda una caja ancha arriba de una tabla
angosta. En el celular (≤640px) no hay blanco que recortar: la tabla vuelve a ocupar todo el ancho.

Lo cuida `tests/ui/test_tablet.js` midiendo a 1.280px (la tablet, no los 390px del celular): la
tabla tiene que medir lo mismo que su contenido (`max-content`) y el buscador lo mismo que la tabla.
Si alguna pantalla futura vuelve a quedar con pocas columnas, éste es el patrón a copiar.
## 4ee. El SUGERIDO es referencia, no orden: a los P.S. no se les precarga la cantidad (2026-09-17/18)

`[usuario 2026-09-17, textual: "en el caso de envío a proveedores de servicio en la versión tablet,
no me preescribas lo que voy a enviar la cantidad que voy a enviar sino que lo voy a escribir yo
porque puede generar confusiones"]`

Desde v1.4.0 la tablet metía el sugerido DENTRO del campo Cantidad, en la unidad de cada proveedor
(3 paquetes de AJ, 40 kg de Julio, 612,36 kg de Ester). **Eso se terminó para los proveedores de
servicio**: el campo arranca **vacío** y lo escribe quien envía. La columna **Sugerido se sigue
mostrando** con toda su maquinaria (techo, unidad del proveedor, equivalencia en bultos): la
cuenta no cambió, lo que cambió es que ya no se escribe sola en el campo.

**Por qué importa la distinción**: el sugerido sale de `máximo − stock − lo que ya está en el
destino`, o sea es lo que la base **cree** que falta. Lo que sale por la puerta es lo que hay en la
mano en ese momento. Cuando el número venía puesto, confirmar sin mirar registraba el cálculo en
lugar del envío real — y un envío mal cargado desbalancea el stock del P.S. en las dos puntas.

- **Alcance**: P.S. **e inyectores** (en la tablet se eligen dentro de "Prov. de servicio", así que
  para el que la usa son lo mismo). A los **talleristas se les sigue precargando**: no se pidió
  para ellos. Vive en `precargaCantidad()` de `Tablet/Tablet_GP2.html` (v1.12.0; la falta de memoria, en v1.13.0).
- **Efecto de rebote bueno**: el botón `Enviar (N)` vuelve a contar lo que la persona cargó de
  verdad. Con la precarga, abrir una contraparte ya dejaba todas las filas "cargadas" (por eso en
  2026-09-16 se sacó el cartelito "N sin registrar" de los botones de tipo, ver el historial de LOCKS del 2026-09-16).
- **Y en los P.S. la tablet NO se acuerda de lo tipeado** `[usuario 2026-09-18, textual: "hay
  algunos que siguen anotados. Si cargue algo yo, cuando salgo quiero que desaparezca, no que se
  guarde, por lo tanto todas las cantidades deben estar vacias"]`. Sacar la precarga no alcanzó: el
  buffer de `localStorage` guardaba igual lo que había tipeado una persona, así que al volver a
  entrar aparecían cantidades de otro día — **el mismo problema con otro origen**. Ahora el buffer de
  esa contraparte se borra al **entrar**, al **salir** ("← Cambiar", "Cambiar tipo", cambio de modo)
  y al **cerrar o recargar** la pantalla (`pagehide`). Se sigue usando mientras la contraparte está
  abierta: es de donde sale lo que se registra y lo que aguanta un toque de más. `envSinMemoria()` /
  `olvidarCargado()`, Tablet v1.13.0.
- **Al tallerista no se le tocó nada**: ahi la precarga sigue viva y el buffer tiene sentido (lo
  que se le manda se arma en varias vueltas). Su precarga queda firmada en `it.qAuto`, y mientras
  `it.q === it.qAuto` nadie la tocó, así que se refresca con el sugerido del día.
- **Y el campo vacío no dice "= 0 cajones"**: la equivalencia en bultos aparece cuando hay un número
  tipeado. Debajo de un campo en blanco era ruido.
- **`EnviosPS_GP2` (pantalla de escritorio) no se tocó**: el pedido fue "en la versión tablet".

## 4ef. La cuarta forma de enviar: el CAJÓN DE CADA PIEZA se mira, y se escribe KG — Guazzaroni (2026-09-17), Jade y otros cinco (2026-09-18)

`[usuario, textual: "dentro del version tablet, y envio a ps. Siguiendo la lógica del módulo
Ester ---> en el módulo de guazzaroni patricio, el sugerido tendría que aparecer en cajones y en
cantidad pones kg y que te diga cuantos cajones son (redondeando)"]`

Es lo de Ester (4ec) con **una** diferencia, y es la que importa: **el envase no es uno solo para
el proveedor, lo pone cada pieza**. Guazzaroni niquela/templa/zinca 25 piezas distintas y cada una
viene en su propio cajón, así que el factor sale de `componente.uni_x_cajon` fila por fila — igual
que el bulto de Hernandez Julio (4ea), pero acá el cajón **es** la unidad del sugerido, no una
columna al costado.

**La regla nueva no es una columna, es un significado**: en `GP2.proveedor_servicio`,
**`envio_uni_x` NULL ya no quiere decir "sin unidad de envío"**, quiere decir *"el factor no es del
proveedor, sale de la pieza"*. Con eso las cuatro formas entran en las mismas tres columnas:

| proveedor | `envio_unidad` | `envio_uni_x` | `envio_carga_unidad` | qué se ve |
|---|---|---|---|---|
| AJ Adhesivos (12) | `paquetes` | 100 | `null` | sugerido y cantidad en paquetes |
| Ester (14) | `bolsas` | 1800 | `kg` | sugerido en bolsas, cantidad en kg |
| **Guazzaroni Patricio (4)** | `cajones` | **null** | `kg` | **sugerido en cajones de ESA pieza, cantidad en kg** |
| **Jade (5)** | `cajones` | **null** | `kg` | idem Guazzaroni (2026-09-18) |
| **FAAT (2), Mabra (3), Pedernera (6), Scorrano (7), Maspoli (15)** | `cajones` | **null** | `kg` | idem (2026-09-18) |
| Hernandez Julio (8) | `kg` | null | `null` | sugerido en bultos, cantidad en kg; el bulto lo pone el SECTOR |

Ejemplo real: CV1 (remache espiral) tiene 57.143 uni por cajón y 0,00035 kg por unidad → **1 cajón
= 20,00 kg**. Sugerido 34.992 remaches → **1 cajón** (techo, como siempre: no se pide menos de lo
que falta) y la cantidad se precarga en 20,00 kg.

**El "(redondeando)" del pedido es la equivalencia de abajo del campo**: se tipean los kg y la
pantalla dice a cuántos cajones equivalen. ⚠ CADUCADO la tarde del 2026-09-18: ese redondeo se dio
vuelta y hoy va **con decimales** (70 kg → **"= 3,5 cajones"**). Ver la sección de abajo.

### ⚠ EL ENVASE SÍ SE PARTE: el equivalente va CON DECIMALES (2026-09-18, TARDE)

**Esta regla se dio vuelta el mismo día que se escribió.** A la mañana el usuario pidió redondear
(`"acordate que todo lo que sea envío de cajones y bolsas redondear. En este caso, el pasaje serían
6 bolsas"`, sobre un "= 6,17 bolsas" de Ester) y a la tarde pidió lo contrario, viendo un "menos de
1 bolsa" debajo de 1 kg: `[usuario, textual: "Que pueda anotar decimales a la hora de poner la
cantidad de kg. Además, no quiero que redondees las bolsas, cajones → lo quiero ver con decimales
también"]`. **Vale la segunda.** Lo que queda:

| lo que se mira | cómo se muestra | por qué |
|---|---|---|
| **el equivalente en bultos de lo que se manda** | el número **exacto, 2 decimales** (6,17 bolsas; 3,5 cajones) | es una descripción de lo que va en el camión: media bolsa existe |
| **el sugerido** | **para arriba** (techo), sin cambios | es *lo que falta*, y pedir menos no llena el lugar `[usuario 2026-09-17, Ester: "redondeás por arriba"]` |

Siguen siendo dos reglas distintas — la trampa es creer que es la misma. Lo que se dio vuelta es
sólo la primera.

El texto lo arma `textoEnvases()`: siempre **"="** y el número con coma; se fueron el **"≈"** y el
**"menos de 1 bolsa"** en palabras (ahora dice **"= 0,69 bolsas"**, que informa más). Misma función
en la Tablet y su gemela `equivEnvase()` en Envío a PS.

**Lo que se REGISTRA acompaña a lo que se ve**: `movimiento.cajones` (y el `p_cajones` de
`crear_envio_ps`) vuelve a guardar el número con 2 decimales, como antes de la mañana. La columna
es `numeric`, así que la base nunca fue el límite. Con el entero se perdía información: 0,4 bolsas
se anotaban como nada y 1,4 como 1.

**La cantidad en kg YA aceptaba decimales** (`inputmode="decimal"` + `GP2N`): "12,5" entra bien,
medido el 18/09 en Ester. Lo que **no** entra es el **punto**, que para la regla de la casa es el
separador de miles ("1.5" se lee 15). Si el teclado de la tablet escribe punto en vez de coma, eso
hay que decidirlo aparte: la regla de número es **una sola** para todas las pantallas
(`gp2-numero.js`) y cambiarla ahí se siente en todos lados.

**Ese renglón chico es AHORA EL ÚNICO FORMATO, en las cuatro formas** `[usuario 2026-09-18,
textual: "está bien que me lo ponga chiquito abajo, pero modificá Hernandez Julio así quedan todos
así"]`. Julio era el que quedaba distinto: tenía el bulto en una **columna aparte**, con su propio
campo. Desde la v1.14.0 su tabla también es `Pieza | Sugerido | Cantidad (kg)` y sus bolsas/cajones
salen abajo del campo. **Lo que se perdió a propósito**: el bulto ya no se corrige a mano — se
calcula de los kg con techo y es lo que se anota en `movimiento.cajones` (informativo; el stock lo
mueve la cantidad en kg). En el código hay **un solo** `eqFila(x, q)` que decide el renglón para
las dos maneras de convertir (envase del proveedor / bulto por sector).

**Jade (id 5), 2026-09-18** `[usuario, textual: "Seguimos con Jade. El sugerido tiene que aparecer
en cajones y la cantidad… Pones los kilos y te tira cuántos cajones es el equivalente. Es parecido
a lo que hicimos en Guazzaroni"]`. Exactamente la misma forma: **no hizo falta tocar una línea de
código**, sólo las tres columnas de `proveedor_servicio`. `[dato]` las **12 piezas** que Jade pinta
/ croma / zinca (G13, G2, G7, H11, H15, I1, I6, J13, J2, J5, K2, K5) tienen `uni_x_cajon` **y**
`kg_x_uni` cargados, así que **las 12 convierten** y ninguna cae a unidades. Los cajones de Jade
son grandes (606 a 1.685 piezas) y sus sugeridos a veces chicos: **con el techo, un sugerido de 54
unidades pide 1 cajón entero de 1.145** (G2). Es la regla de la casa —no se pide menos de lo que
falta— y el operario igual escribe los kg reales; queda anotado por si el dueño prefiere otra cosa
para los sugeridos chicos.

**Los otros cinco, 2026-09-18** `[usuario, textual: "Lo mismo con Laboratorio FAAT, Mabra
Metalurgica, Maspoli SRL… Y Pedernera Ilario y Scorrano Mario, la misma lógica"; "es decir, Jade,
FAAT, Mabra, Maspoli, Pedernera y Scorrano modelalo igual el sugerido y cantidad"]`. Otra vez
**sólo datos**: `update proveedor_servicio set envio_unidad='cajones', envio_uni_x=null,
envio_carga_unidad='kg' where id in (2,3,6,7,15)`. `[dato]` FAAT 10 piezas, Mabra 1, Pedernera 33,
Scorrano 1, Maspoli 1; sólo **Pedernera** tiene una pieza sin `uni_x_cajon` y una sin `kg_x_uni`
(esas quedan en unidades y la celda lo dice).

**Con esto ya no queda ningún P.S. con piezas sin unidad de envío definida**: los 7 del cajón por
pieza, AJ por paquetes, Ester por bolsas y Julio por peso cubren todos los que reciben algo. Los
que siguen en `null` (Rec Color, Daniel, Blist-Pack) **no tienen piezas en ruta**, y los dos
híbridos (Charcas, Eclipse) ni siquiera aparecen en Enviar. En los tests, el "P.S. común" —el
render de siempre, cajón + kg— lo representa **Blist-Pack**.

**Lo que NO se convierte**: `[dato 2026-09-17]` 5 de las 25 piezas de Guazzaroni no tienen
`uni_x_cajon` cargado (CV12, CV18D, CV6, CV9, W1B) y CV18D tampoco tiene `kg_x_uni`. Esas filas
**se cargan en unidades** y la celda lo dice ("sin cajón cargado"): no se inventa un cajón. Si el
dueño carga el `uni_x_cajon` de esas 5, pasan solas al modo cajones/kg — no hay que tocar código.

**El inventario sigue sin ver cajones**: viaja el kg (`unidad='kg'`) y `to_canonical` lo pasa a
unidades con `kg_x_uni`; los cajones quedan anotados en `movimiento.cajones`, informativos.

**Dónde se ve**: `Tablet/Tablet_GP2.html` (v1.11.0 — v1.9.0 y v1.10.0 las tomaron el mismo día otras dos sesiones: el encogido de columnas y el sugerido en bultos de Julio) y `Prov Serv/Envios/EnviosPS_GP2.html` (v1.6.0). **Sumar un proveedor más a esta forma es un UPDATE, no un deploy**: el alta de Jade (2026-09-18) no tocó ningún archivo de pantalla ni bumpeó versión.
En Envío a PS el sugerido **ya se calculaba en cajones**, así que ahí sólo cambió el rótulo y el
layout (se va la columna "Cajón envío", queda un solo campo en kg). **Ya no queda pendiente ningún
P.S. que reciba piezas**: van definidos 10 de los 15 (AJ, Ester, Julio y los 7 del cajón por pieza)
y los 5 que faltan son los que no tienen piezas en ruta o son híbridos.

### El bug que salió de paso: la Cantidad precargada quedaba VIEJA

> **Al día siguiente esto se volvió historia para los P.S.**: el dueño pidió que en Enviar a
> proveedor de servicio la Cantidad no se precargue **ni se guarde** (4ee), así que ahí el buffer
> se borra al entrar y al salir. Lo que sigue vale para el **tallerista**, que es donde la
> precarga quedó viva.

`[usuario 2026-09-17: "fijate que hoy aparece el sugerido y la cantidad preescrita distinta en
guazzaroni, chequea"]`. La Tablet precarga el Sugerido en la Cantidad, pero **sólo si el campo está
vacío** — para no pisarle al operario lo que cargó a mano. El buffer vive en `localStorage`
(`gp2_tablet_buffer`) y **sobrevive días**, así que cuando el sugerido del bundle cambiaba (se movió
el máximo o el stock) la pantalla mostraba el **Sugerido de hoy con la Cantidad de otro día**. La
migración que existía sólo corría para proveedores con unidad de envío propia, así que todos los
demás quedaban desfasados y nadie lo veía.

**Cómo se arregló**: la precarga queda firmada en `it.qAuto`. Mientras `it.q === it.qAuto` (el
operario no la tocó) se refresca con el sugerido del día; cualquier otro valor es una edición real
y **no se pisa nunca**. Vale para todos los proveedores. La lección general: *un valor derivado
guardado en `localStorage` necesita saber si sigue siendo derivado o ya lo editó una persona* —
guardar el valor no alcanza, hay que guardar también que lo puso la máquina.



## 4eg. Enviar a un P.S. se elige por TARJETAS, y la carga es una pantalla por parte (2026-09-18)

`[usuario 2026-09-18, textual: "En la versión tablet, dentro del módulo “Envío a proveedores de
servicio”, quiero modificar la forma en que se seleccionan las partes. Actualmente se muestran en
formato de listado. Quiero reemplazar ese listado por boxes o tarjetas individuales. Cada box debe
mostrar, como mínimo: código o nombre de la parte, descripción de la parte. Al seleccionar una
parte, debe abrirse una vista donde se muestre: la cantidad sugerida a enviar, un campo para
indicar la cantidad efectiva que se va a enviar"]`

El listado de un P.S. dejó de ser una tabla: es una **grilla de tarjetas**, una por parte, y al
tocar una se abre **la vista de esa parte** con el sugerido arriba y el campo de la cantidad abajo.

- **Alcance: Enviar → Prov. de servicio, inyectores incluidos** (se eligen dentro de ese mismo
  botón, así que para el que usa la tablet son lo mismo). Es **el mismo conjunto** que ya no se
  acuerda de lo tipeado (4ee): en el código la vista de tarjetas y `envSinMemoria()` son la misma
  cuenta, a propósito. **Talleristas, prov. de art. terminado y TODO Recibir siguen con la tabla**:
  ahí hay esperado, exceso y remito, que se leen de corrido y no de a una parte.
- **La tarjeta** muestra código (con su unidad), descripción, el **sugerido** de referencia y, abajo,
  lo que hoy se va a mandar: *"sin cargar"* en gris, o *"✓ envía N"* en verde con el borde verde.
  Ese renglón de estado es lo que reemplaza al vistazo que daba la tabla: de un golpe se ve qué
  falta cargar, sin abrir nada.
- **La vista de la parte** mantiene **todas** las formas de enviar de 4ea/4ec/4ef sin excepción:
  paquetes (AJ), kg con "= N bolsas" (Ester), kg con "≈ N cajones" redondeados (los 7 del cajón por
  pieza) y por peso (Julio), que **desde el mismo 2026-09-18 también tiene un solo campo**: sus
  bolsas/cajones son el renglón chico de debajo de los kg, como en todas las demás (ver 4ef). El
  segundo campo del bulto existió menos de un día.
- **Y no hay atajo para copiar el sugerido al campo** `[usuario 2026-09-18, textual: "no quiero que
  aparezca la opción de enviar sugerido"]`. La primera versión de esta pantalla tenía un botón
  "Usar el sugerido"; se sacó el mismo día. Es la misma línea de 4ee llevada hasta el final: si el
  sugerido es **referencia**, tampoco puede haber un botón que lo convierta en la cantidad de un
  toque — eso es la precarga otra vez, con un click en el medio. El único botón de la vista es
  "Listo", que cierra la parte.
- **No cambió nada de datos**: mismo buffer, mismo payload, mismas RPC. La cuenta del sugerido quedó
  en **una sola función** (`sugeridoInfo()` para mostrarlo, `sugeridoEnCarga()` para escribirlo) que
  ahora usan la tabla, la tarjeta, la vista de la parte y la precarga del tallerista: antes eran
  cuatro copias de la misma aritmética y se podían separar.
- **`EnviosPS_GP2` (escritorio) no se tocó**: el pedido fue "en la versión tablet". Sigue con la
  tabla, igual que antes.

## 4eh. En la tablet el botón de los inyectores dice "bolsas plásticas", y la tarjeta no corta texto (2026-09-18)

`[usuario 2026-09-18, textual: "En versión tablet, en vez de bolsas de resina, bolsas plásticas
poné"]` — el subtítulo del botón **Inyectores** de Enviar. Cambio de **palabra en pantalla**, nada
más: adentro sigue viajando **resina en kg** por `enviar_material_inyector`, con el sugerido que
sale de la O.C. de partes (4ea). Los comentarios del código y esta memoria siguen diciendo
"resina" porque eso es lo que se mueve; "bolsas plásticas" es cómo lo nombra el que carga.

`[usuario 2026-09-18, textual: "ojo que por ejemplo, en guazzaroni, aparece así" + captura de la
tarjeta de CV12 con "Sugerido 13.272 uni · sin cajón cargad" comido por el borde]` — **el texto de
la tarjeta se cortaba**. La causa era `white-space:nowrap` en `.pc-sug`: en la tablet real la
grilla arma columnas de 230px y esa línea, la más larga que produce la pantalla (sugerido +
unidad + la nota "sin cajón cargado" de 4ef), no entra en un renglón. Ahora baja de renglón, y la
tarjeta entera lleva `overflow-wrap:anywhere` para que un código o una descripción larga tampoco
se puedan ir afuera.

**Lo que hay que recordar de esto:** el recorte **no se ve a 390px**, donde la tarjeta ocupa el
ancho completo y la línea entra — se ve a **1.280px**, que es la tablet de verdad. Los dos anchos
se miden en `test_tablet.js`, y el chequeo del recorte va en el bloque de 1.280. Y se mide
comparando el ancho real del texto (`Range.getBoundingClientRect()`) contra el de su caja:
`scrollWidth` **no** sirve, porque con `nowrap` la caja mide bien y el texto se va afuera igual
(medido: el guardián con `scrollWidth` daba OK con el bug puesto; con `Range` dio 48px de desborde).

## 4ei. El FASONERO: a Maspoli se le emite O.C., y el envío de virolas sale de esa O.C. (2026-09-18)

`[usuario 2026-09-18, textual]`: *"que el envío a Maspoli de virolas no surja hasta que se hace una
orden de compra. Cuando se hace la orden de compra, imaginate que se hizo una orden de compra por 10
mangos. Por esos 10 mangos hay que mandarle 10 virolas. Entonces, en la cantidad sugerida tendría
que aparecer el equivalente a 10 unidades de virola."*

**Qué es un fasonero, y por qué no es un PS común ni un híbrido.** Tres figuras distintas, que hasta
hoy GP2 trataba como dos:

| Figura | Qué pone él | Qué le compramos | Cómo se le pide |
|---|---|---|---|
| PS común (Guazzaroni niquela, Pedernera croma) | sólo mano de obra | nada, se le paga el servicio | el envío sale del **máximo** de la pieza |
| PS **híbrido** (Charcas, Eclipse) | procesa materia prima que le compramos **a un tercero** | la pieza, y de paso la O.C. gemela al dueño de la MP | `proveedor_servicio.hibrido` |
| **Fasonero** (Maspoli) | **su propio material** (la madera del mango) | la pieza que devuelve | `proveedor_servicio.pedido_por_oc` ← **nuevo** |

Maspoli recibe la virola `D13` (nuestra, niquelada por Guazzaroni) y devuelve el mango de madera con
la virola adentro: `PC12` (508/708), `PEP7` (518) y `PEP8` (564/863). Ver 4b y 4cc.

**La trampa que costó media hora y hay que no repetir: NO se le toca el `estado_compra`.** Las tres
piezas están en `estado_compra='fabricacion'`, que es lo que las sacaba de la O.C. El reflejo es
ponerlo en `null` — y eso las mete en el CTE `comprado` de `v_costo_componente`, que corta el
recorrido de la ruta. **Medido antes de aplicar nada** (en una transacción con `rollback`): los cinco
artículos perdían **$710,89 cada uno** — el 508 pasaba de 1.553,91 a 843,02 — porque el mango dejaba
de costearse por la ruta (virola + servicio de armado) y pasaba a costear por su `precio_proveedor`,
que **no existe**. Por eso el flag va en el proveedor y no en la pieza: `oc_bundle` deja entrar las
salidas de un PS `pedido_por_oc` **con su `estado_compra` intacto**.

**Cómo quedó el circuito (es el mismo que ya tenía el inyector con sus bolsas, 4ea):**

1. **O.C.** — `Compras/OC_GP2.html` muestra a Máspoli SRL con sus 3 mangos (sugerido = máximo −
   stock: PC12 2.448, PEP7 2.864, PEP8 2.552). `proveedor_insumo` "Máspoli SRL" pasó a `activo`.
2. **Envío** — Maspoli aparece **siempre**, con O.C. o sin ella, y lo que cambia es el número:
   sin orden el sugerido es **0**, y con una O.C. **enviada** de 10 mangos dice **10 virolas** (1 a
   1) menos las que ya tiene en su poder. El borrador NO dispara: recién cuando la orden sale.
   `[usuario 2026-09-18, segunda vuelta: "los inyectores por más que no esté cargada la orden de
   compra aparecen igual con cero sugerido; tendría que aparecer Maspoli con cero sugerido y cuando
   sale la orden de compra ahí sube el sugerido de entrega de virolas"]`. **La primera versión lo
   escondía** mientras no hubiera O.C. y el dueño lo corrigió a las dos horas: un proveedor que
   desaparece de la pantalla no se distingue de una pantalla rota, y además el operario pierde la
   referencia de que ese proveedor existe. **Regla general que sale de acá: una fila con 0 informa;
   una fila que no está, no.**
3. **Entrega** — sigue por Entrega P.S., y desde hoy `crear_entrega_ps` **descuenta la O.C.**
   con el mismo cruce FIFO de la recepción de insumos. Sin eso la orden quedaba abierta para siempre
   y el sugerido de virolas nunca bajaba — el bug que se hubiera comido el cambio entero.

**El nombre no sirve para identificarlo.** "Maspoli SRL" (`proveedor_servicio`) y "Máspoli SRL"
(`proveedor_insumo`) son la misma persona escrita distinto; la exclusión "lo que produce un PS no se
compra" no lo agarraba **por la tilde**, no por diseño. Ahora esa exclusión matchea por nombre **o
por `cod_prov`** (los dos son 2339) y el fasonero queda afuera de ella a propósito, por el flag.

**Lo que falta (no bloquea):** el **precio del mango de Maspoli**. Los $683,72 que esta memoria citaba
en 4b (`precio_proveedor` 16/17/18, cod_prov 2339) **ya no están en la base**: hoy el único precio con
cod_prov 2339 es el del `PEP5` ($108, "Mango Madera Cuchillo Untar"), y encima `PEP5` figura a nombre
de *Eduardo Pintos*. Sin ese precio la O.C. a Maspoli sale **sin importe**. Dos cosas para el dueño:
cargar la lista de Maspoli, y decidir si el `PEP5` es de Pintos o de Maspoli.

## 4ej. Virgilio se APAGA como fuente de movimientos: ledger en cero y la canilla cerrada (2026-09-18)

`[usuario 2026-09-18, textual: "Quiero que en gestión productiva 2 por ahora no me agregues todo
lo que es Virgilio, no me lo generes como movimiento. Así que todos los movimientos borralos, que
quede todo en cero y el stock que se modificó por estos movimientos también deja todo en cero"]`

**Lo que había** `[dato, medido antes de tocar]`: `GP2.movimiento` tenía **51 filas y NINGUNA otra
cosa** — 38 `consumo_virgilio` + 13 `recepcion_virgilio`, todas del 17 y 18/09. O sea: el único
libro de movimientos que GP2 llegó a tener era el espejo de Virgilio. Y las **60 filas de
`inventario` con cantidad ≠ 0 eran exactamente** los 60 pares (componente, ubicación) que tocaban
esos 51 movimientos: ni una fila de stock venía de otro lado. Por eso "borrar todo" y "dejar todo
en cero" terminaron siendo **la misma operación**.

**No hizo falta tocar `inventario` a mano.** `trg_movimiento_aplicar` es `AFTER INSERT OR DELETE OR
UPDATE`, y en el `DELETE` revierte los dos deltas (`-old._delta_dest` al destino, `+old._delta_orig`
al origen). Un `delete from "GP2".movimiento` desarma el stock solo. Verificado fila por fila
**antes** de ejecutar: las 60 quedaban en 0,00 exacto y no había ninguna no-cero ajena al espejo.
Escribir el `update … set cantidad = 0` hubiera sido pisar el motor, no usarlo.

**Lo que se ejecutó** (con el sí del usuario, 2026-09-18):

```sql
delete from "GP2".movimiento;                 -- 51 filas
delete from "GP2".virgilio_espejo_pend;       -- 26 filas en cola (4bs)
alter table public."Entregas Tallerista Virgilio"
  disable trigger trg_virgilio_espejo_gp2;    -- la canilla
```

Después: `movimiento` 0, `virgilio_espejo_pend` 0, `inventario` 1.311 filas todas en 0,00 (suma
total 0), invariante ledger-vs-inventario en 0.

**La parte que importa para la próxima sesión: borrar los movimientos NO alcanzaba.** Los generaba
solo `trg_virgilio_espejo_gp2`, un trigger que vive sobre `public."Entregas Tallerista Virgilio"`
(casa del vecino) y llama a `GP2.fn_entregas_virgilio_espejo`. Si no se apagaba, la primera entrega
cargada en Virgilio volvía a escribir en `GP2.movimiento` y el "todo en cero" duraba horas. Ese
trigger **no está en `db/`** (el README lo dice: los dos triggers espejo sobre `public` quedan
afuera del respaldo), así que su estado sólo se ve en la base:

```sql
select tgname, tgenabled from pg_trigger t join pg_class c on c.oid = t.tgrelid
 where c.relname = 'Entregas Tallerista Virgilio';   -- 'D' = apagado, 'O' = vivo
```

**Lo que se pierde mientras esté apagado** `[avisado al usuario antes del sí]`: las entregas que se
carguen en Virgilio en el ínterin **no quedan ni en la cola** de `virgilio_espejo_pend` — el trigger
es el que encola, así que con el trigger apagado no hay rastro que reprocesar. Volver a prenderlo
(`enable trigger`) **no recupera el hueco**: hay que cargar esas entregas a mano o reconstruirlas
desde `public."Entregas Tallerista Virgilio"`, que sí las tiene. Se ofreció la variante "el trigger
sigue encolando pero no crea movimiento" (conserva el historial); el usuario eligió el apagado seco.

**Es "por ahora", no una decisión de arquitectura.** La integración entera sigue en pie:
`INTEGRACION_GESTION_VIRGILIO.md`, las RPC `recepcion_virgilio` / `reprocesar_espejo_virgilio` /
`enviar_material_virgilio`, la pantalla `Talleristas/Recepcion/RecepcionVirgilio_GP2.html` y los
tipos `recepcion_virgilio` / `consumo_virgilio` del vocabulario **no se tocaron**. Para volver:
`alter table public."Entregas Tallerista Virgilio" enable trigger trg_virgilio_espejo_gp2;`.

**La pantalla queda con candado, no borrada** `[usuario 2026-09-18: "Dale"]`. En
`GP2_MODULOS.html` (menú v1.17.0) la entrada **Entrega Virgilio** pasa de href a `null`, que es la
forma que ya tenía la casa para un módulo apagado: se ve el botón con 🔒 y no se puede abrir. El
archivo `Talleristas/Recepcion/RecepcionVirgilio_GP2.html` **no se borró** y su RPC tampoco, así que
volver es reponer el href — un renglón. Se eligió el candado y no borrar la línea justamente porque
esto es "por ahora": una entrada que desaparece del menú se olvida; una con candado se ve.
## 4ek. Al TALLERISTA la unidad de envío la pone la PIEZA (2026-09-18)

`[usuario 2026-09-18, textual: "Cartón según el formato se le manda según cómo viene el paquetón…
según el formato de cartón vienen o mil unidades o dos mil. Y las cajas en paquetes de 25. Entonces
el sugerido y la cantidad va para ambos en paquetes, cartones y cajas. En cambio para el resto el
sugerido va en cajones y la cantidad va en kilos… y abajo chiquito te pone a cuántos cajones
equivale"]`

Las cuatro formas de 4ea/4ec/4ef son **del proveedor**: AJ manda todo en paquetes de 100, Ester todo
en bolsas de 1800. Con un tallerista eso no se puede: **recibe de todo** — cartones, cajas, mangos,
flejes, plásticos — y cada cosa viaja en su propio envase. Así que acá la unidad **no es del
destino, es de la pieza**, y la dice la base (`tablet_bundle` → `env_unidad` / `env_factor` /
`env_carga` en cada fila de tallerista):

| pieza | sugerido | cantidad | de dónde sale el factor |
|---|---|---|---|
| Sector Cartón (10) | paquetes | **paquetes** | `carton_formato.uni_x_bolsa` del formato de esa pieza |
| Sector Caja (11) | paquetes | **paquetes** | `parametro.caja_uni_x_paquete` = **25** |
| todo lo demás | **cajones** | **kg**, con "≈ N cajones" abajo | `componente.uni_x_cajon` de esa pieza |

**El "paquetón" del cartón es la BOLSA del formato, no el paquete de 250.** En GP2 conviven los dos
números: `parametro.carton_uni_x_paquete` = 250 (el paquete chico, el de la O.C.) y
`carton_formato.uni_x_bolsa`, que es **1.000** (formatos C, LOKE, Manga), **2.000** (Huevo), **3.000**
(formato 8) y **100** (Pliego). El usuario dijo "o mil unidades o dos mil", que es exactamente esa
columna — por eso el envío usa `uni_x_bolsa` aunque en la pantalla se rotule "paquetes", que es la
palabra que usó él. `[dato 2026-09-18]`

**Lo que NO tiene el dato no se convierte** (misma regla que Guazzaroni en 4ef): la pieza queda en
unidades y la tarjeta lo dice. Al 2026-09-18, de las **285** piezas que se les mandan a talleristas:
- **6 cartones sin paquetón** porque su formato no lo tiene cargado (A1B, A1B1, BOLSA550, BOLSA760,
  G8C, O2A — formatos Bandita, Bolsa, Corbata, Rallador);
- **23 sin `uni_x_cajon`**, que quedan en unidades (1686, BOM10, BOM13, BOM14, C12, C13, D9, GRJ13,
  GRJ14, GRJ28, GRJ29, IE1, PA17, PC6, PEST2, PINCEL590, PV17, PV8, PV8B, V18D, W1B, Z12, Z21);
- **2 con cajón pero sin `kg_x_uni`** (GRJ18, GRJ19): tienen sugerido en cajones y **se cargan en
  cajones**, porque sin el peso no hay cómo pasar a kg;
- **254 andan completas**. Cargar el dato que falta las pasa solas al modo bueno: **no hay que tocar
  código**.

**Y con esto ya no queda nadie con la cantidad precargada**: el tallerista era el último
`[usuario 2026-09-18, eligiendo entre tres opciones: "igual que P.S.: vacío y sin memoria"]`. Se
fueron `precargaCantidad()`, `sugeridoEnCarga()` y la firma `qAuto` de 4ee — ya no hay ningún valor
derivado guardado en `localStorage` que pueda quedar viejo, que era el bug de fondo de aquella
sección. La **tabla** queda viva solo para el **prov. de art. terminado** y para **todo Recibir**.

**Trampa que se repitió acá** `[dato 2026-09-18]`: entre que se aplicó el cambio en
`tablet_bundle` y que se terminó el front, **otra sesión volvió a crear la función y se llevó puesto
el parche**. Se detectó porque el bundle devolvía `env_unidad` en null y se re-aplicó sobre la
definición viva (que ya traía la feature de la otra sesión, el fasonero Maspoli). Moraleja: cuando
se parchea una función compartida, **verificar el resultado del bundle al final, no al aplicar**.

### Y el PROV. DE ART. TERMINADO hereda lo mismo (2026-09-18)

`[usuario 2026-09-18: "seguís de la misma manera con prov de art terminado"]`. Era el último destino
de Enviar con tabla. Le tocó gratis la unidad: **recibe solo cartones y cajas** (sectores 10 y 11),
que son justo las dos cosas que van en **paquetes**, así que el mismo `case` del bundle lo cubre —
cambió una línea (`tipo in ('tallerista','proveedor_at')`).

**Su referencia no es el sugerido, porque no tiene**: la tarjeta y la vista muestran el **online del
sector** (lo que hay en Cervantes para mandarle), con ese rótulo. Lo resuelve `refInfo()`, que
devuelve la misma forma para los dos casos. El online se muestra **en la unidad de la pieza** (988
uni) y no en paquetes: es un stock, no algo que se manda. `[decidido 2026-09-18, avisado al usuario]`

Al 2026-09-18 son **68 piezas**: las **10 cajas** andan completas y de los **58 cartones**, **42**
tienen el paquetón de su formato y **16 no** (A1B, C2A, C2B, F5A, M1, M2A, M2C, M3A, M3B, P2A, Q5D1,
Q5E, Q6B, Q6C, Q7C1, Q7D): esos quedan en unidades y la tarjeta lo dice. Es el **mismo hueco** que
el de 4ek — formatos sin `uni_x_bolsa` cargado — y se tapa cargando el dato, sin tocar código.

**Con esto, en Enviar no queda tabla ni memoria en ningún destino**: `envSinMemoria()` son los
cuatro. La tabla sigue viva solo en **Recibir**.

## 4el. El 500 y el 506 dejan el pliego: ahora llevan CARTÓN, como el resto (2026-09-18)

`[usuario 2026-09-18, textual]` *"El pliego 500 y el pliego 506 ya no se compran más. Borra las
rutas de todos lados. Ahora lo reemplaza los cartones 500 y 506. Agregalos. […] eliminar todas
las rutas de pliegos, tanto sin adhesivar como adhesivado, del 500 y el 506, y agregar las rutas
tanto de compra como de recepción en gráficos Pol. De cartón 500 y 506. El precio es igual al
resto de los cartones. Y la ruta se le manda a los mismos talleristas que ensamblan."*

Da vuelta la parte de pliego de **§4eb** (17/09, *"la ruta para todos los pliegos es: pliego sin
adhesivar → AJ adhesivados → pliego adhesivado → tallerista final"*). **Esa regla sigue viva para
los otros 10 pliegos** (557, 558, 654, 658, 659, 758, 759, 762, 763, 769); el 500 y el 506 salen
de ella: ya no hay pliego ni adhesivado, hay un cartón comprado hecho.

### Lo que quedó en la base

| | Antes | Ahora |
|---|---|---|
| Pieza | `Pliego 500` (594) → AJ → `Pliego Ad 500` (306) | **`CART500`** "Cartón 500" (931) |
| Pieza | `Pliego 506` (564) → AJ → `Pliego Ad 506` (311) | **`CART506`** "Cartón 506" (932) |
| Receta | pliego adhesivado **×1/12** | cartón **×1** |
| Ruta | 3 pasos (insumo 1/12 → AJ Adhesivos → tallerista) | 2 pasos (insumo ×1 → tallerista) |

- Los dos cartones son **formato `C`, categoría `Abrelatas`, `Talleres Gráficos Pol`, marca
  `LOEKE`, $89** — calcados del gemelo exacto, `A2B` "Cartón 510", que es el mismo formato y la
  misma categoría. Los 6 cartones C/Abrelatas valen $89 sin excepción, así que *"el precio es
  igual al resto de los cartones"* no tuvo que adivinarse. **Ojo**: dentro del formato `C` conviven
  $89 y $79 (Pelapapas); el precio lo fija la **categoría**, no el formato.
- **Compra y recepción no se configuran en ningún lado.** Una pieza con sector de insumo +
  `proveedor` que existe en `proveedor_insumo` + `estado_compra` null aparece sola en `oc_bundle`
  y en `recepcion_bundle`. Verificado: los dos salen bajo Talleres Gráficos Pol con su $89 y su
  máximo (CART500 6.696 · CART506 101.568).
- **Talleristas: los mismos que ensamblan.** 500 → Martin Cornejo (ruta 603). 506 → Martin Cornejo
  (1045) y Alex Escalante (1050), que es el reparto 30/70 de §4eb. Inventario en 0 creado en Sector
  Cartón y en el taller de cada uno.
- Los 4 pliegos pasaron a `estado_compra='discontinuo'` + `discontinuado=true`: **no se borran**
  (conservan historial), pero desaparecen de la OC y de Recepción de Insumos. No tenían ni un
  movimiento, ni una OC, ni una recepción — stock 0 — así que no se perdió nada.
- Se borró la tarifa de adhesivado de AJ para esas dos piezas (`precio_servicio_pieza` 110 y 89).
  AJ sigue adhesivando los otros 10 pliegos.

### Lo que apareció de paso: el adhesivado se estaba cobrando DOS VECES

El costo del 500 **bajó** $115,75 y el del 506 también, cuando la cuenta del cartón decía que
tenían que **subir** $12,58 (de $76,42 el pliego a $89 el cartón). La diferencia son **$140 por
artículo** que se iban en un doble conteo que ya estaba pusheado:

- el precio del `Pliego Ad 506` es **$917 = $777 (Pol) + $140 (AJ)** — el adhesivado ya está
  adentro, y la receta lo pagaba a 1/12, o sea $11,67 de adhesivado por artículo, que es lo correcto;
- y **además** el paso `proveedor_servicio` de la ruta cobraba la tarifa de AJ **$140 × 1 por
  artículo**, no por pliego.

O sea: el adhesivado se pagaba dos veces y la segunda a 12× la escala. Al borrar el paso de la
ruta el doble conteo se fue solo. **La regla que deja**: cuando el precio de una pieza YA incluye
un servicio (acá el skin del pliego), ese servicio no puede estar también como paso de ruta — y si
está, mirar la ESCALA, porque el paso se cobra por artículo y el precio de la pieza se prorratea.
Los otros 10 pliegos tienen la misma forma (`precio_servicio_pieza` de AJ + paso PS en la ruta):
**hay que revisarlos uno por uno**, no se tocaron en este cambio.

| Artículo | Antes | Ahora | |
|---|---|---|---|
| **500** | $573,58 | $457,83 | −$115,75 |
| **506** | $494,50 | $378,75 | −$115,75 |

El material sí subió como estaba previsto: el 506 quedó con **$107,35 de material en pesos, el
mismo peso al peso que el 510**, que es el gemelo — buena señal de que la receta quedó pareja.

## 4el. RECIBIR de un tallerista: el esperado se mira en CAJONES y la cantidad se escribe en KG (2026-09-18)

`[usuario 2026-09-18, textual: "de talleristas, todos se entregan en cajones… tanto en esperado como
en recibido, tenés que poner la unidad de medida. En esperado va a ser en cajones… y en recibido va
a ser en kilos. Y pones en chiquito cuántos cajones equivalen. La única excepción que no es en
cajones sino en bolsas son las bombillas GRJ5 y GRJ6. Entregan bolsas de 120 unidades"]`

Es la misma idea que el envío (4ek) del otro lado del mostrador: **la unidad la pone la pieza**.
Lo que cambia es de dónde sale y cómo se llama lo de arriba:

| | Enviar | Recibir |
|---|---|---|
| referencia | **Sugerido** (lo que falta) | **Esperado** (lo que el tallerista tiene, `online_tall`) |
| campo | Cantidad a enviar | **Cantidad** — el usuario pidió que no se llame más "Recibido" |
| unidad del campo | según la pieza | **kg**, siempre, con "≈ N cajones" debajo |

**Cómo se guarda la excepción**: no con un `if` por código. Dos columnas nuevas en
`GP2.componente` — `entrega_unidad` y `entrega_uni_x` — que **sobreescriben el default**
(`cajones` + `uni_x_cajon`). Hoy las tienen cargadas **solo GRJ5 y GRJ6** (`bolsas` / **120**). Si
mañana otra pieza entrega distinto, se carga el dato y listo. `tablet_bundle` las manda en cada
fila de `recibir` con las **mismas claves** que ya usaba Enviar (`env_unidad` / `env_factor` /
`env_carga`), así que el front no aprendió un modelo nuevo: `envaseDe()` ahora también mira Recibir.

**La trampa que apareció acá — y que vale para cualquier pantalla que cambie de unidad:** el
**esperado viene en unidades** (es un stock) y ahora se escriben **kg**. Dos lugares donde eso se
comparaba crudo:
1. el aviso de "recibí de más" de la pantalla → se arregló con `canonDe()`, que lleva lo tipeado a
   la unidad canónica antes de restar;
2. `tablet_registrar`, que compara `cantidad > esperado` **tal cual vienen** para escribir
   `alerta_recepcion`. Ahí no se tocó la base: **el front manda el esperado en la misma unidad que
   la cantidad** (1.000 uni × 0,01 = 10 kg). Si alguna vez se cambia una unidad en otra pantalla,
   este es el segundo lugar que hay que mirar.

**Lo que NO se registra**: los cajones equivalentes. `crear_entrega_tallerista` no tiene dónde
anotarlos (a diferencia de `crear_envio_ps`, que tiene `p_cajones`); el kg es lo que mueve el stock
y el cajón es ayuda visual. `[deducido 2026-09-18]`

**Alcance al 2026-09-18**: las 9 filas de Recibir de talleristas — 7 en cajones (una, `C12B`, sin
`uni_x_cajon`, así que queda en unidades y la tarjeta lo dice) y las 2 bombillas en bolsas. El
**P.S. sigue con la tabla**: es lo que sigue.

### Y la ENTREGA de un P.S. copia la unidad del envío (2026-09-18)

`[usuario 2026-09-18, textual: "AJ adhesivos entrega en paquetes de 200. El resto copia la lógica
del envío: si enviamos en bolsas recepcionamos en bolsas, si lo hacemos en cajones, en cajones.
Charcas cajones"]`

La regla se escribió **una sola vez**: por defecto la entrega de un P.S. usa el **mismo envase con
el que se le envía** (`packEnvio` / `pesoEnvio`, que ya existían), así que **no hubo que cargar un
dato por proveedor**. Solo los que difieren tienen columnas propias — `proveedor_servicio.
entrega_unidad` / `entrega_uni_x` — y hoy son dos:

| proveedor | envía | entrega | por qué |
|---|---|---|---|
| **AJ Adhesivos** | paquetes de **100** | paquetes de **200** | lo dijo el dueño; se escribe en paquetes |
| **Maspoli SRL** | cajón de cada pieza, en kg | **bolsas de 250 mangos**, se escribe en bolsas | `[usuario 2026-09-18: "Maspoli entrega en bolsas de 250 mangos"]` — y 250 es justo el `uni_x_cajon` de sus tres mangos |
| **Resortes Charcas** | — (es híbrido, no está en Enviar) | **paquetes de 10 kg** | no tenía unidad de la cual copiar `[usuario 2026-09-18: "Charcas en paquetes"]` |

**El paquete de Charcas son 10 kg** `[usuario 2026-09-18, respondiendo la pregunta]`. Importa
porque sus dos piezas son flejes que se miden **en kg** (`IC3`, `IC3V`): sin ese dato el factor
caía al `uni_x_cajon` de la pieza (**1.205** y **24**), que para algo medido en kg se lee como *kg
por paquete* — un paquete de fleje de 1.205 kg no existe. Con `entrega_uni_x = 10` el esperado sale
en paquetes de verdad y la cantidad se escribe en paquetes (10 kg cada uno).

⚠ **Ese 10 está escrito en dos lugares**: `proveedor_servicio.entrega_uni_x` (la entrega, esta
pantalla) y `parametro.charcas_kg_x_paquete` (la **compra**: la O.C. a Charcas se pide en paquetes y
se guarda en kg, ver la sección de OC). Es el mismo paquete físico, así que **si cambia, hay que
cambiar los dos**; queda dicho también en el comment de la columna.

El resto sale solo: Guazzaroni, Jade, FAAT, Mabra, Maspoli, Pedernera y Scorrano entregan en **el
cajón de cada pieza** (su envase de envío), Ester en **bolsas de 1800** y Hernandez Julio en el
**bulto de su sector** (bolsas los plásticos, cajones el resto). Un P.S. **sin unidad definida**
(Blist-Pack, Rec Color, Daniel, Blist…) sigue como estaba: esperado y cantidad en la unidad de la
pieza. `[dato 2026-09-18]`

**El detalle que importa del "copia la lógica"**: copia el **envase Y la forma de cargar**. Donde el
envío se escribe en kg (Ester, los del cajón por pieza, Julio), la entrega también — con el mismo
renglón "≈ N cajones" debajo. Donde el envío se escribe en el envase (AJ, paquetes), la entrega
también. Por eso `packEnvio()` y `pesoEnvio()` dejaron de exigir `MODO === 'enviar'`: son del
**proveedor**, no del modo.
## 4em. Lo que se manda PESADO se anota en las DOS unidades, y la pantalla las cruza (2026-09-18)

`[usuario 2026-09-18, textual: "en cantidad a enviar tengo que poder poner cajones primero y después
los kg. Lo mismo con lo que se envía en bolsas. Si después de cargar cajones/bolsas y kg y no
coinciden por mucho (es decir, por ejemplo, si tengo 10k que equivalen a 2 bolsas y puse 3) que me
salte alerta pero que me deje poner listo igual. Si no coincide por poco (por ejemplo: 10kg eran 2
bolsas y media y puse 2) que no salte ninguna alerta. Que no pueda poner listo hasta que haya
cargado en las dos unidades de medida"]`

**Da vuelta la decisión de la mañana** (v1.15.2 había sacado el segundo campo de Hernandez Julio
para que el bulto fuera un renglón calculado). El motivo del cambio es bueno y conviene tenerlo
escrito: **los dos números existen en la realidad y los mide gente distinta** — el envase es lo que
el operario **cuenta** mientras carga el camión, el kg es lo que marca la **balanza**. Si uno se
calcula a partir del otro, un error de carga es **invisible**: sale un número perfecto y coherente
que no se parece a lo que subió al camión. Anotando los dos, la pantalla puede **cruzarlos**.

- **Alcance**: toda fila de **Enviar** con envase + kg (Julio por peso, Ester, los del cajón por
  pieza, los talleristas). Las que se escriben **solo en el envase** (AJ, cartón, cajas) y **todo
  Recibir** siguen con un campo. `[deducido — el usuario habló de "cantidad a enviar"]`
- **Orden**: primero el envase, después los kg. Así se carga en la realidad. Y van **uno al lado
  del otro** `[usuario 2026-09-18: "que sea una al lado de la otra… queda muy ancho"]`: apilados, la
  vista se hacía larga y el campo quedaba ancho al pedo. Las dos columnas **se achican**, no
  envuelven, así que a 390px siguen entrando.
- **Lo que FRENA**: falta una de las dos → "Listo" deshabilitado, la vista dice cuál falta y la
  tarjeta se pinta naranja. Una fila a medias **no entra** en el conteo del botón Registrar ni viaja
  en el payload: no se registra media carga.
- **Lo que AVISA pero no frena**: el desvío entre lo anotado y lo que dicen los kg.

**La tolerancia es el envase entero de arriba y el de abajo**, no "media unidad". Si los kg dan
**2,5** bolsas, anotar **2 o 3** está bien; si dan **2 justas**, anotar 3 ya avisa — que son los dos
ejemplos del usuario. Se probó primero con media unidad pelada y se descartó: **el kg por envase
casi nunca da redondo** (un cajón de A1 son 57.143 × 0,00035 = 20,00005 kg), así que 4 cajones
contra 3,49999 saltaban por una millonésima. `[dato 2026-09-18, medido en el test]`

**Al registrar viaja el envase ANOTADO**, no el calculado, en `movimiento.cajones`.

### Y el punto tipeado vale como coma

`[usuario 2026-09-18: "cuando voy a cargar quiero que me deje poner . o , para poner decimales"]`.
Está en `gp2-numero.js`, que es donde vive la regla de número de la casa. **Se hace en
`beforeinput`, sobre la tecla recién apretada, y NO en `conMiles()`**: ahí no se puede distinguir el
punto que tipeó la persona del que puso el separador automático de miles, y "1.000" más una tecla se
convertiría en 1,0005. En los campos de **enteros** (cajones, bolsas) el punto sigue sin entrar, que
es lo que ya pasaba. La regla de fondo no cambió: **el punto sigue siendo miles** para `num()`.
## 4en. El bulto del remache: 20 kg el crudo, 2 kg el niquelado (2026-09-18)

`[usuario, sobre CV12 que mostraba "sin cajón cargado" en la Tablet: "agregale la uni x bolsa. Del
crudo que sería 25kg dividido el peso por uni" → corregido dos mensajes después: "es 20 kg"]`.

**El envase de un remache se carga en kg, no en unidades**: `componente.uni_x_cajon` = kg del bulto
÷ `kg_x_uni`. Los valores de la tabla lo confirman: los 13 remaches **CV** (crudo, "p/Niquelar")
dan **20,000 kg** exactos y los **V** (niquelado) dan **2 kg** (algunos 10). No es casualidad: se
cargaron así.

Aplicado el 18/09: `CV12` (id 469) tenía el bulto vacío y se le cargó **20.683 uni** = 20,000 kg
con su `kg_x_uni` de 0,000967. Nada más se tocó.

⚠ **El 0,00085 kg/uni que se pasó ese día para CV12/V12 quedó DESCARTADO por el propio usuario**
(`"tiralo"`): el peso sigue siendo **0,000967** en los dos. Queda anotado para que una sesión futura
no lo "recupere" de este historial creyendo que se perdió.

**Por qué no rompió nada** (medido antes de escribir): `recalcular_maximos_cajones` sólo toca
`sector_id in (1,2)` y Remache es el **8**, así que el máximo de CV12 (13.272, `est_madre`) no se
movió; el precio de CV12 es **por unidad** (`precio_proveedor.precio_por_kg = false`), así que el
costo tampoco; y el stock estaba en 0.

**Lo que sigue sin resolver**: para un sector que no es plástico la pantalla rotula el bulto
**"cajones"**, así que el remache va a decir "cajones" aunque venga en bolsa. Preguntado al usuario,
sin respuesta.


## 4eo. Los remaches vuelven de Guazzaroni EN LOS MISMOS CAJONES — y el `uni_x_cajon` del niquelado es la BOLSA del fraccionado (2026-09-18)

Salió de una pregunta del dueño: `[usuario 2026-09-18, textual: "Mandé 5 cajones de cv11 y el
esperado de recepcion de v11 es 50 cajones. Por qué?"]`.

**El esperado estaba bien; el envase con el que se mostraba, no.** El esperado de un P.S. es lo que
tiene en su poder, o sea la pieza que le **mandamos** (CV11), contada en unidades de esa pieza:
5 cajones × 20 kg = 100 kg = **136.425 remaches**, correcto. La tablet lo dividía por el
`uni_x_cajon` de la pieza que **devuelve** (V11 = 2.729 uni = **2 kg**) → 50. El ×10 era la
diferencia entre dos números que se llaman igual y no son lo mismo.

**Qué es cada número** `[usuario 2026-09-18]`:

| número | qué es de verdad |
|---|---|
| `CV11.uni_x_cajon` = 27.285 (**20 kg**) | el **bulto** con el que se le manda el remache crudo a niquelar, y con el que vuelve. Ojo: la pantalla lo rotula *cajones* porque `bultoDe()` decide el rótulo con un regex sobre el nombre del sector (plástico → bolsas, el resto → cajones) — el remache crudo en realidad viene en **bolsa**, y eso quedó anotado como **idea 7353** |
| `V11.uni_x_cajon` = 2.729 (**2 kg**) | la **bolsa** en la que se fracciona DESPUÉS de recibirlo, con la **matriz de embolsado**. No es un cajón |

`[usuario, textual: "Guazzaroni nos entrega los remaches niquelados en los mismos cajones que se lo
enviamos. Pero vos tenes que los cajones del ya niquelado es de menos peso porque luego de que
llegan, con una matriz de embolsado fraccionan en bolsas de 2kg"]` y `[usuario: "si envío 2 cajones
lo esperado es recibir 2 cajones aprox (el peso niquelado es un poquito mas - muy infima la
diferencia)"]`. **El dato de la base está bien**: lo que estaba mal era leer la bolsa como cajón.

⚠ **LA REGLA NO ES UNIVERSAL** `[usuario 2026-09-18, textual: "No aplica para todos los casos. Esto
te lo estoy diciendo en el caso de los remaches"]`. Por eso **la base decide dónde aplica y el front
obedece**: `tablet_bundle` manda `ent_uxc` / `ent_kgu` (el cajón y el peso de la pieza enviada) en
las filas de `recibir` **sólo del sector Remache**, y la tablet los prefiere cuando vienen. Los
otros **105** pares de P.S. quedan exactamente como estaban (el cajón de la pieza devuelta).
Cuando aparezca otro proveedor que devuelva en el mismo envase, se amplía esa condición — un lugar.

**Se cruza con 4en**, que salió en paralelo esa misma tarde y cargó el bulto de 20 kg de CV12:
esa sección dice **qué** es cada número; ésta, **con cuál se mira el esperado**. Y contesta a medias
lo que 4en dejó abierto ("la pantalla rotula 'cajones' aunque venga en bolsa"): el **rótulo** sigue
mal — es la idea **7353** — pero el **factor** ya es el correcto.

⚠ **Y el envase del PROVEEDOR DE INSUMO es otro más**: `[usuario 2026-09-18, textual: "Cuando vienen
del prov de insumo vienen en bolsas de 25kg, no 20"]`. O sea, para el mismo remache conviven **tres**
envases: bolsa de **25 kg** del proveedor (Bella Vista / Mandelli / Suipacha) → cajón de **20 kg**
para ir y volver del niquelado → bolsa de **2 kg** (algunos 10) del fraccionado interno. La O.C. de
remaches se pide **en kg** (ver REGLAS_OC_INSUMOS) y hoy **no** redondea a bolsa de 25 kg: queda
PENDIENTE decidir si se pide en bolsas enteras, como los plásticos.

**Dato al pasar, para cuando haga falta**: los 9 crudos con cajón cargado dan **20,00 kg** clavados
los 9, y los niquelados dan 2 kg (V1, V2, V4, V9, V10, V11, V12, V13) o 10 kg (V3, V5, V7, V8) —
o sea que la bolsa del fraccionado no es una sola. **Tres crudos no tienen cajón cargado** (CV6,
CV9, CV18D): esas filas caen al envase de la pieza devuelta, que es lo único que hay. `[dato
2026-09-18, GP2.componente]`

## 4ep. En Recibir el número de referencia se llama por lo que es: el STOCK de la contraparte (2026-09-21)

`[usuario 2026-09-21, textual: "En la versión tablet, cuando voy a recibir, en vez de esperado
quiero que diga Stock tallerista o stock proveedor de servicio según corresponda"]`.

**No es un cambio de número, es un cambio de nombre — y el nombre viejo mentía.** Ese dato nunca
fue "lo que calculamos que va a traer": es **lo que la contraparte tiene en su poder** según la
base (`esperado_origen = online_tall` / `online_ps`), o sea lo que le mandamos y todavía no
devolvió. "Esperado" se leía como una expectativa de esta entrega, y de ahí salieron las dos
confusiones del 18/09 (4eo: "mandé 5 cajones y el esperado dice 50"). Con el rótulo correcto, el
operario que ve un número raro sabe qué mirar: el stock del tallerista, no la entrega de hoy.

- **Tallerista** → "Stock tallerista". **P.S.** → "Stock prov. de servicio".
- **Virgilio sigue diciendo "Esperado"**: ahí el número es su online y el usuario nombró sólo los
  dos. `[deducido]` — si alguna vez molesta, es un renglón en `rotuloRef()` de la tablet.
- **El número, su unidad (cajones/bolsas/paquetes) y la alerta de "recibí de más" no se tocaron.**
- De paso, en la tarjeta el rótulo bajó a su propio renglón chico y gris: "Stock prov. de servicio"
  en los 21px de negrita naranja se comía tres renglones y tapaba el número, que es lo que se lee
  de lejos. Vale también para "Sugerido" y "Online sector".

**Ampliación del mismo día — SIN STOCK SE DICE 0** `[usuario 2026-09-21, textual: "pero que me
diga 0 si no tiene stock"]`. Mostrar el rótulo correcto dejó a la vista un agujero viejo: cuando la
contraparte no tiene nada nuestro, la tarjeta decía "Stock tallerista" y **ningún número**. No era
que faltara el dato — `tablet_bundle` manda el esperado del tallerista y del P.S. con
`coalesce(..., 0)`, o sea que **para esos dos nunca es null** —, era que `textoEnvases()` devuelve
`""` cuando el número no es > 0. Eso está bien donde nació (el renglón "= N cajones" de abajo del
campo, que con el campo vacío no escribe nada) y estaba mal acá. Ahora el cero se escribe.

- **`0` y `—` no son lo mismo y siguen separados**: `0` = la base sabe y la contraparte no tiene
  nada; `—  sin referencia` = el esperado vino **null**, que hoy sólo pasa fuera de tallerista/P.S.
- **Consecuencia que conviene saber**: con stock 0, cualquier cantidad que se reciba dispara la
  alerta de "recibí de más" (`exceso = recibido − 0`). Eso **ya era así** antes de este cambio —el
  número siempre fue 0—, sólo que el operario no lo veía venir. `[dato, GP2.alerta_recepcion]`
## 4eq. Tanda de correcciones de despiece del usuario (2026-09-21)

Ocho correcciones dictadas de corrido por el dueño en una sola charla. Van juntas porque comparten
el mismo patrón: **el despiece que estaba cargado no era el que se arma en la planta**, y en la
mitad de los casos el dato nuevo contradijo algo que ya estaba escrito acá.

### a) Los coladores 026 y 027: "Telametal" **es** José López

`[usuario 2026-09-21, textual]` *"El colador 026 y 027 los arma el prov de art terminado
Telametal"* → preguntado si era un proveedor nuevo o el mismo, contestó *"Es Lopez Jose"*.
O sea **Telametal = el `GP2.proveedor_at` id 4 "Lopez Jose"**, que ya tenía los dos coladores
asignados con 6 entregas históricas cada uno. **No hubo cambio de despiece: ya estaba bien.**
Corrige de paso lo que decía §4cn (los coladores los hace José López y sólo le damos el cartón,
`[usuario 2026-09-13]`): sigue siendo cierto, Telametal es el otro nombre del mismo.
**PENDIENTE, preguntado 3 veces y sin respuesta:** si se guarda como **alias**
(`contraparte_alias` 'TELAMETAL' → proveedor_at 4, las pantallas siguen diciendo "Lopez Jose") o
se **renombra** el proveedor a Telametal (cambia el nombre en sus 10 coladores y 24 entregas).
Hasta que conteste, la base quedó **sin tocar**.

### b) La pinza lleva DOS cachas, no una — y estaba mal en las 6

`[usuario 2026-09-21]` *"El 053 le faltan las cachas azules PC8, lleva 2"*, y al marcarle que los
hermanos tenían 1: *"los otros 5 también llevan 2 cachas"*. El **053** (Pinza de Fiambre Inox) era
el único de las seis pinzas **sin `PC8`**; se le dio el alta con cantidad **2** más su ruta espejo
(insumo → tallerista Pettofrezza → virgilio), y **054, 055, 594, 595 y 596 pasaron de 1 a 2**, en la
receta y en el paso `insumo` de sus rutas. Lo que dio pie a preguntar: la base ya usaba 2 donde va
un par (la puntera de ensalada `F11` está ×2 en 054 y 596), así que el 1 de PC8 era el error.
Plata: PC8 = **$270,49** la unidad → el 053 sube $540,98 y los otros cinco $270,49 cada uno.
**PENDIENTE:** el **731** (Sacacorcho Combinado Color) también lleva `PC8` y quedó en **1** — no es
pinza, el usuario dijo "los otros 5" y ahí se paró.

### c) El 059 lo envasa Lucho, no la Fábrica

`[usuario 2026-09-21]` *"El 059 lo envasa Lucho"*. Los **3 pasos** del 059 (Cuchillo de Untar
Plástico x2) pasaron de tallerista **Fábrica (3)** a **Lucho (5)**: los tres son el mismo acto de
envasado (PEP9 ×2, CART059, caja A9). Cierra con lo que ya había: Lucho hace los hermanos **519** y
**719** (Cuchillo Untar Mgo Madera x2), a $72,282 (AyE) y $77,112 (reenvasado).
**PENDIENTE:** el 059 **no tiene `precio_tallerista`** de nadie, así que al salir de Fábrica su
costo quedó subvaluado hasta que se cargue lo que cobra Lucho.

### d) El 070 lo arma la FÁBRICA, y le faltaban dos partes

`[usuario 2026-09-21]` *"Al 070 hay que agregarle Etiqueta 070 (ETIQ070) y Set Tuppers (GRJ30)"*,
*"Lleva 1 de c/u"*, *"Los provee cimarron"*, y después *"El 070 arma fábrica"*. El 070 (Set Tapers
0,8/1,5/3 Lts) tenía **sólo la caja A4** y su ruta colgaba del `proveedor_at` **"Pettofrezza" (id 9,
`activo=false`** por duplicado con el tallerista Pettofrezza Rafael id 11): al pasar a Fábrica, esa
dependencia de una contraparte desactivada **se fue sola**. Alta de **`GRJ30` "Set Tapers"**
(Sector Garage, proveedor Cimarrón, ×1, con ruta propia); los 3 pasos del artículo son hoy
`tallerista → Fábrica`, y el stock de sus insumos vive en la ubicación de Fábrica (23).
**El nombre de la pieza NO es el que dictó el pedido**: se dio de alta como *"Set Tuppers"* (la
palabra que usó el usuario) y unas horas después él mismo la corrigió `[usuario 2026-09-21: "y grj30
que la descripcion sea Set Tapers"]` — **`GRJ30` = "Set Tapers"**, igual que el artículo 070 que
arma. *Tupper* es la marca; *taper* es como se llama acá y es lo que dice el resto de la base.

### e) ~~Lo que se compra es el ROLLO, no la etiqueta~~ — **DADO DE BAJA EL MISMO DÍA**

**LA ETIQUETA NO SE EVALÚA POR AHORA** `[usuario 2026-09-21, textual: "En el articulo 070 aparece
el rollo etiquetas. Eliminá, no queremos evaluar por ahora las etiquetas. Eliminá de todos los art
que agregaste"]`, ejecutado con el "Sí" sobre el SQL exacto. Se borró **todo** lo que había entrado
por este punto, unas horas después de cargarlo: `ROLLOETIQ` (comp 934), sus 2 filas de
`articulo_componente` (070 y 071), sus 2 rutas (1054 y 1055) con los 6 pasos, sus 2 filas de
`inventario` (las dos en 0) y el proveedor **Sumatik** (`proveedor_insumo` 49), que **sólo existía
por la etiqueta** — sin O.C., sin recepciones y sin precios. **El 070 queda `GRJ30 ×1 + A4 ×0,25`
y el 071 `GRJ21 ×1 + A4 ×0,25`.** El costo no se movió: el rollo nunca tuvo precio cargado.

**Ojo con el nombre del proveedor**: el pedido de baja decía *"Y saca melinox por lo tanto"*, y
**Melinox no tiene nada que ver con la etiqueta** — es el `proveedor_at` 7 que entrega el **761**
Cucharita Matera y el proveedor de `Z21` y `Z22`, con precio cargado; borrarlo dejaba al 761 sin
quién lo entrega y rompía `test_programa_prov_at.js`. El que entró **por** el rollo era **Sumatik**.
Se avisó antes de ejecutar y Melinox quedó intacto. **Regla que deja: un "sacá X por lo tanto" se
verifica contra quién entró en esa misma tanda, no contra el nombre que uno recuerda.**

**Lo que igual vale la pena no perder, para cuando se retome:** lo que se compra es el **rollo**
(8.000 etiquetas), no la etiqueta suelta — *"agregá como rollo etiquetas, NO etiq070… en realidad
se compra el rollo"*, *"8000 etiquetas en un rollo"*, *"El 071 también lleva etiqueta"*. Va en
**Sector Cartón**, no en un sector propio (*"No crees el sector etiquetas. Pone dentro de sector
carton"*), con `carton_formato` en **null** para que no le apliquen múltiplos, familias ni pliegos;
la cantidad es una **fracción como la caja** (1 de 8.000 = **0,000125**, cargarla con "1" mete un
rollo entero por artículo); y el código por artículo (`ETIQ070`) **no se crea**: imprimirle el
código es un paso posterior de la casa, no algo que se compre.

### f) La arandela chica inox era `K9` en Crudo; es `E3` en Procesado

`[usuario 2026-09-21, textual]` *"La arandela chica afila inox dice sector K9 pero es sector
procesado E3"*. El componente id 39 pasó a **código `E3` + Sector Procesado**, y su fila de
inventario (máximo 87.890) se mudó de la ubicación Crudo a Procesado. Cierra con la estructura:
sale de matriz desde el fleje `IF2` y va **derecho al tallerista** en las 3 rutas de los afiladores
(097, 114, 504), sin pasar por zincado ni cromado. **OJO con el código repetido**: en el Excel viejo
`E3` era la arandela **grande** (hoy `F7`); el detalle y cómo distinguirlas está en
`Renombres_Sectores.md`. La idea **7245** quedó actualizada (nombraba `K9`).

### g) El nombre de una ruta mentía sobre el insumo que lleva — 110 casos

Salió de la 670: se llamaba *"Insumo GRJ13 -> Art 071"* y lleva **GRJ21** (GRJ13 es el Cepillo Limpia
Mamadera, otra pieza). Barrido completo: de 234 rutas cuyo nombre no coincide con el código real,
**124 son apodos** legítimos (`CART053`, `V6`, `PLIEGO557`, "Caja") y **110 nombraban otro
componente que existe de verdad** — esas son las que engañan al leer (la 522 decía "A9" y lleva A3).
Se corrigieron las 110 reconstruyendo el nombre desde el insumo real y respetando el sufijo de
tallerista; los 124 apodos **no se tocaron**. Invariante nuevo de la casa, de hecho: el nombre de la
ruta no es decorativo, se lee para saber qué se manda.

### h) Lo que quedó rojo y NO es de esta tanda

`AE_paso_virgilio_y_codigo_dan_distinto` da **2**: los artículos **567** (Corta Palta) y **537**
(Pela y Pica Ajo) tienen su componente terminado en el sector 12 pero **ninguna ruta**, así que el
paso `virgilio` no existe. Es preexistente, no lo tocó esta sesión. El resto de los invariantes que
pegan con lo que se cambió (A, I, K, L, S, U, W, X, Y, AA, AB, AD) dan **0**.

## 4er. OTRO CARTÓN: cuando no hay stock del que va, se manda el de otro artículo y se le pega la etiqueta (2026-09-21)

`[usuario 2026-09-21, textual: "puede pasar de que no haya stock del cartón que quiero mandar y le
mande el cartón de otro artículo y se le pegue la etiqueta del artículo correspondiente. Entonces lo
tengo que modelar para que baje el stock del cartón que le mando realmente"]`. Vale para los **dos**
que reciben cartón: **tallerista** y **prov. de art. terminado**.

**El envío nunca fue el problema.** El movimiento descuenta el `comp_id` que se elige, así que el
stock que baja siempre fue el del cartón que sale de verdad. **El agujero estaba en el CONSUMO**: al
entregar el artículo terminado, `recepcion_virgilio` consume la **receta** (`articulo_componente`),
o sea el cartón **oficial** — que en poder del proveedor no está. Resultado sin esto: el oficial
quedaba **negativo** en la ubicación del tercero y el sustituto **clavado ahí para siempre**.

**El modelo: una columna, sin tabla nueva.** `GP2.movimiento.sustituye_comp_id` = el cartón OFICIAL
al que reemplaza el de `comp_id`. Lo llevan las **dos puntas**: el envío ("este va en lugar de
aquel") y el consumo ("este se gastó a cuenta de aquel"). El **saldo sale del ledger**
(`v_carton_sustituto_saldo` = envíos − consumos por ubicación), así que no hay derivada que se
desincronice y **borrar un movimiento se auto-corrige** — mismo criterio que el resto de GP2.

**Cómo se consume**: al recibir el terminado, cada línea de receta de sector 10/11 gasta **primero
el sustituto con saldo** (FIFO por fecha del envío) y **el resto el oficial**. Si nunca hubo
sustitución, sale igual que antes. `recepcion_virgilio` acumula lo asignado **dentro de la misma
llamada** (`v_usado`): la vista todavía no ve los movimientos que se están armando, y sin eso dos
artículos del mismo remito gastarían dos veces el mismo saldo.

**Dónde se declara**: en la **Tablet**, modo Enviar, adentro del tallerista o del prov. AT
`[usuario 2026-09-21: "dentro de envío a tallerista y prov at en la versión tablet"]`. Al final de
sus tarjetas aparece **➕ Otro cartón** → catálogo de los que ese destino **no** usa (RPC
`cartones_para_reemplazo`, no viaja en el bundle: son ~190 filas que casi ningún envío mira) →
**en reemplazo de cuál** de los suyos. Con un solo oficial del mismo sector no pregunta. La fila
entra como una tarjeta más, marcada *"↔ en lugar de XXX"*, y se carga en paquetes como cualquier
cartón. **Cartón por cartón y caja por caja**: la base rechaza reemplazar un cartón con una caja, y
que el reemplazado no sea pieza de ese destino (si no, la sustitución no se consumiría nunca).

⚠ **Lo que NO cambia**: la receta y el **costo**. El artículo sigue costeando con **su** cartón; la
sustitución es física, no contable. Si el sustituto vale distinto, esa diferencia hoy no se ve.

**Dos cosas que aparecieron al medir la cadena, y conviene tener a mano** `[dato 2026-09-21]`:
1. **Mandar cartón a un tallerista por `EnviosTalleristas_GP2.html` (escritorio) REVIENTA**: esa
   pantalla lista los cartones (141 `ruta_paso` de tipo tallerista los tienen como entrada) pero
   pide **Kg**, y los **180 cartones no tienen `kg_x_uni`** → `to_canonical` levanta excepción. No
   hay dato sucio porque **nunca se usó** (0 movimientos `envio_tallerista`). El camino bueno es la
   **tablet**, que los manda en paquetes.
2. **El cartón no está en NINGÚN `componente_bom`** (0 de 37): al tallerista que entrega una
   *parte*, el cartón **no se le descuenta nunca**. Sólo se consume cuando lo que entrega es el
   **artículo terminado** (`recepcion_virgilio`), que es justo el caso que el dueño confirmó
   `[usuario 2026-09-21, elegido entre tres: "el artículo terminado"]`.

## 4es. El 311 y el 312 llevan UN capuchón, el PA13 — el PA18 no va (2026-09-21)

`[usuario 2026-09-21, textual: "El 312 y 311 usan solo PA13, no usan PA18"; ejecutado con su
"Eliminá PA18 para esos dos art"]`

**Qué estaba mal:** el **311** (Cuchillo de Torta) y el **312** (Pala de Torta) tenían en la receta
los **dos** capuchones — `PA13` *Capuchón Batidor LK* **y** `PA18` *Capuchón Espátula LK* — más el
mango `PA17`. Un artículo lleva **un** capuchón; el segundo era grasa que venía de la carga
original.

**Qué se borró** (sólo datos, cero DDL): las 2 filas de `articulo_componente` del PA18 (ids 768 y
773) y las **2 rutas enteras** que lo traían, con sus 8 pasos — `814 "Insumo PA18B -> Art 311"` y
`819 "Insumo PA18B -> Art 312"` (el circuito era `PA18B` → P.S. 8 → `PA18` → tallerista 6 → art →
Virgilio). Los dos quedan con **5 componentes y 5 rutas**, una por insumo, que es como tiene que
cerrar.

**Lo que cambió el número** `[dato 2026-09-21]`: el consumo de `PA18` baja de **14.232 a 13.922
uni/mes** y de 10 a 9 artículos, o sea baja el sugerido de O.C. de `PA18B`. A `PA13` no le cambia
nada (ya estaba en los dos). El costo del 312 baja **$77,74/uni**, que es lo que vale el capuchón.

**LA TRAMPA DEL NÚMERO, que vale para cualquier cuenta de consumo:** la baja es **310**, no las 336
que salen de sumar las dos demandas de `est_madre` (311 → 34, 312 → 302). Son dos cosas:
1. **El 311 está `discontinuado = true` y NO cuenta**: `v_consumo_demanda` filtra `not
   a.discontinuado`. Sus 34 uni/mes están en `est_madre` pero no llegan a ninguna compra. Igual se
   le corrigió la receta, porque el día que se reactive arrastraba el error.
2. **Existe `312L` con 8 uni/mes**, y la vista lo mapea al **mismo** artículo 312
   (`regexp_replace(em.cod,'L$','')`). O sea el 312 real consume por **310**, no por 302. Antes de
   explicar una diferencia en un consumo, mirar si el código tiene hermano con `L`.

**Lo que sigue roto y NO se tocó** (queda preguntado): `PA17` *Mangos Cuch y P Torta* **no tiene
precio** (`faltan_precios = 1`), así que el costo del 312 sigue incompleto aunque el capuchón de
más ya no esté; y el **311 discontinuado con demanda viva en `est_madre`** es un dato que se
contradice solo.

Invariantes de `db/verificar.sql` que pegan con lo tocado (L, U, W, X, AA, AB, AD): **0**. `AE` da
**2** y es **preexistente** (artículos 567 y 537, ya anotado el 2026-09-21).

## 4et. El stock en poder de un tercero se cuenta con el CAJÓN QUE ANOTÓ LOGÍSTICA, no con el teórico (2026-09-21)

`[usuario, textual: "Cuando mando un cajón de 21kg a guazzaroni de cv1, después en recepción me
aparece para recibir 1.05 cajones" → "tiene que aparecer en su stock los cajones que escribe
logística, no los que se calcula a partir de los kg"]`.

**El número era correcto y aun así estaba mal.** El movimiento real (id 85501, 21/09): CV1, Sector
Remache → Guazzaroni, `cantidad = 21 kg`, `cajones = 1`, delta 60.000 unidades. La Tablet mostraba
ese stock dividiendo por el cajón del maestro — `componente.uni_x_cajon` de CV1 = 57.143 uni, que
son **20,000 kg exactos** (ver 4en: los remaches se cargaron así a propósito) — y daba
60.000 / 57.143 = **1,05 cajones**. Salió UN cajón del galpón y la pantalla decía 1,05.

**La distinción que hay que guardar**: `uni_x_cajon` es **cuánto entra en un cajón en promedio**
(sirve para el sugerido, los máximos y las O.C.), no **cuánto pesó el cajón que salió**. Para el
stock en poder de un tercero manda el segundo, y ese dato ya se venía guardando: `movimiento.cajones`
es lo que el operario **anota** al enviar (desde la v1.22 de la Tablet viaja el número tipeado, no
el calculado de los kg).

**Cómo quedó** (sin tabla nueva, todo sale del ledger):
1. `GP2.v_caj_contraparte` — por (ubicación de la contraparte, componente): `uni_x_cajon_anotado` =
   unidades enviadas ÷ cajones anotados, sólo sobre movimientos **con cajones > 0**.
2. `envios_ps_bundle` manda `sc_unixcaj_anot` y `tablet_bundle` manda `ent_uxc_anot` (este último
   sólo donde ya mandaba `ent_uxc`: P.S. + sector Remache, la regla de 4eo).
3. El front lo prefiere sobre el maestro: `GP2EE.uxcEnPoder()` en Envío PS y Entrega PS,
   `uxcRef()` en la Tablet. **Sin cajones anotados no cambia nada** — los talleristas no los anotan
   (`crear_envio_tallerista` no tiene `p_cajones`) y siguen con el cajón del maestro.

**Por qué NO se llevó un segundo libro de cajones** (enviados − devueltos, que era la otra forma):
al RECIBIR nadie anota cajones — `tablet_registrar` llama a `crear_entrega_ps` con `p_cajones =>
null` —, así que ese saldo nunca bajaría. Con el factor anotado el número **se concilia solo contra
el kg**: si el proveedor devuelve la mitad dice medio cajón, y si devuelve todo dice cero.

**Lo que el usuario pidió además, en la misma charla** `[usuario, textual: "En recepcion de
proveedores de servicio se tiene que seguir la lógica de primero cargar lo que dice el remito y
despues hacer el control (como en recepcion de insumos) en el remito que sea en kg y despues
controlar en kg y cajones (o unidad de medida correspondiente según la parte)"]`: **ya está hecho,
ver 4eu** (esta línea decía "queda pendiente" y se corrigió el mismo día, cuando se construyó).


## 4eu. Recepcionar un P.S. son DOS pasos: primero el remito, después el control (2026-09-21)

`[usuario, textual: "En recepcion de proveedores de servicio se tiene que seguir la lógica de
primero cargar lo que dice el remito y despues hacer el control (como en recepcion de insumos) en
el remito que sea en kg y despues controlar en kg y cajones (o unidad de medida correspondiente
según la parte)"; y enseguida: "Despues de recepcionar tengo que ir al control"]`.

**La forma ya existía en la casa y se copió tal cual**: en la recepción de insumos el remito deja
`recepcion_insumo` con `controlado=false`, y después `controlar_recepcion_kg` guarda lo declarado,
**pisa la cantidad y ajusta el movimiento** — o sea el stock queda con lo que se contó, no con lo
que dijo el papel. Lo mismo, ahora, para lo que entrega un proveedor de servicio.

**Cómo quedó** `[usuario 2026-09-21, elegido entre opciones: control en PANTALLA PROPIA a la que la
tablet manda al cerrar, y los dos pasos EN LA TABLET]`:

1. **El remito** se sigue cargando donde se cargaba (Tablet → Recibir → P.S.), sin cambios: viaja
   el kg y `crear_entrega_ps` mueve el stock como siempre.
2. Al registrar, la Tablet **se va sola** a `Tablet/ControlEntregaPS_GP2.html`, sin cartel
   intermedio — mismo criterio que insumos `[usuario 2026-09-03: "me gusta que me mande directo"]`.
   **Única excepción**: si quedó una alerta de "recibí de más" se muestra la fase 3 con el aviso y
   el paso al control va con un botón; esa alerta el operario tiene que leerla.
3. **El control** se carga por pieza: lo CONTADO (en kg o en unidades, según la pieza) y los
   BULTOS contados (cajones, o el envase del proveedor: AJ entrega en paquetes). Los campos
   **arrancan vacíos a propósito**: el control es un dato nuevo, no una confirmación — precargarlo
   con el remito invita a firmar sin contar. El remito queda arriba, a la vista, para comparar.
4. `controlar_entrega_ps` guarda la fila en `GP2.entrega_ps_control` (declarado + controlado +
   bultos + quién) y pisa `movimiento.cantidad` / `cantidad_transformada` / `cajones`; los triggers
   reacomodan el inventario de las dos puntas solos.
5. **Tolerancia**: la misma del pesaje de insumos (`parametro.tol_ctrl_peso_pct`, hoy 2 %). Abajo
   de eso se registra sin preguntar; arriba, la tarjeta se pinta y el confirmar avisa que el stock
   va a quedar con lo contado.

**Qué es "pendiente de controlar"**: un movimiento `entrega_ps` SIN fila en `entrega_ps_control`.
No hace falta un flag: el pendiente sale del ledger, igual que el saldo de cartones sustitutos
(4er). Los pendientes no caducan — una entrega sin controlar de hace un mes se sigue viendo — y el
encabezado de la Tablet los cuenta (`Control (N)`), que es lo que evita que quede algo colgado.

⚠ **La entrega de escritorio (`Prov Serv/Entregas/EntregaPS_GP2.html`) NO manda al control**: sólo
la Tablet, que es donde el usuario dijo que se hace el circuito. Lo que se cargue por ahí igual
aparece como pendiente en la pantalla de control, así que no se pierde.

⚠ **Lo que el control NO reajusta todavía**: si el P.S. es FASONERO (`pedido_por_oc`, hoy Maspoli),
`crear_entrega_ps` descontó la O.C. con lo que decía el remito y el control no corrige esa resta.
Es la misma limitación que tiene el control de insumos (`controlar_recepcion_kg` tampoco vuelve
sobre la O.C.), y se deja anotada en vez de inventar una regla: cuando aparezca un desvío real en
un fasonero hay que decidir si la O.C. sigue al remito o al control.

## 4eu. El 731 no lleva cachas azules: lleva el ESPIRAL (2026-09-21)

`[usuario 2026-09-21, textual: "Saca las cachas azules del 731 y agregá el espiral d1"; ejecutado
con su "Sí"]`

**El síntoma que lo delata, y que estaba a la vista:** el **731** (Sacacorcho Combinado Color)
llevaba `V1` *Remache Espiral* **sin el espiral** — el remache de una pieza que no figuraba en la
receta. Lo que sí tenía era `PC8` *Cachas Azules*, que en un sacacorchos no va.

**Se borró:** la fila `articulo_componente` id 395 (`PC8` x1) y la ruta **425 `"Insumo PC8 -> Art
731"`** con sus 3 pasos.
**Se dio de alta:** `D1` *Espiral Sacacorcho* x1 y la ruta **1056 `"Insumo D1 -> Art 731"`**
(`insumo D1 → tallerista 6 → 731 → virgilio`), calcada de la **576 del 531**.

**EL 731 Y EL 531 SON EL MISMO PRODUCTO** `[dato 2026-09-21]`: los dos se llaman *Sacacorcho
Combinado Color* y comparten `C8`, `D4`, `D14`, `V1`, `V2`, `V3`. Lo único que los separa es el
**cuerpo** (`B7` serigrafiado en el 731, `B4` pintado azul en el 531), la **caja** (A8 / A11) y el
**cartón** (T3B / E3B). El 531 ya llevaba `D1` y nunca llevó `PC8`: **el hermano era la prueba**.
Cuando dos códigos son el mismo producto, la receta del que está bien es el patrón, no hay que
adivinar.

**PC8 era del rubro equivocado** `[dato 2026-09-21]`: lo usan las **6 pinzas** (053, 054, 055, 594,
595, 596), todas **x2**, y el 731 era el único que no es pinza, y con x1. Esto **cierra el
pendiente** que había dejado la tanda de correcciones del mismo día (`4eq`: *"el 731 también lleva
PC8 y quedó en 1"*): no había que ponerle 2 — había que **sacarlo**. Ahora `PC8` queda en 6
artículos y 1.604 uni/mes.

**Lo que mueve la plata, y va para arriba:** el costo del 731 **sube $97,91/uni** (−$270,49 la
cacha, +$368,40 el espiral) sobre **404 uni/mes**, o sea el artículo estaba **subestimado ~$39.556
al mes**. El consumo de `D1` sube a 10.102 uni/mes: más O.C. de espirales. Una corrección de
receta que *sube* el costo es la que más urge, porque mientras tanto se estuvo cotizando barato.

Queda con **10 componentes y 10 rutas**, una por insumo. Invariantes de `db/verificar.sql` que
pegan con lo tocado (L, S, U, W, X, AA, AB, AD): **0**. `AE` da **2** y es **preexistente**
(artículos 567 y 537).

## 4ev. Buscar un componente sin saber en qué rubro está (2026-09-21)

**Lo que dijo el usuario, textual:** *"Que me deje buscar por fuera de algún sector y por dentro.
Porque hoy en día si no se a que sector pertenece el componente tengo que entrar uno por uno"*.
Es sobre `Stocks General/StockGeneral_GP2.html`, cuyo buscador filtraba **solo el rubro abierto**.

**Por qué dolía más de lo que parece:** no era solo cuestión de clicks. De las **1.324 filas de
`GP2.inventario`, 275 no tenían ningún botón que las mostrara** — 269 de Virgilio, 5 de inyectores
y 1 de un sector sin rubro en el selector (`Y1` *Cuchilla para Afilar*, Sector Afilado, con máximo
43.946). Entrando "uno por uno" por los 15 rubros esas filas **no aparecían nunca**.

**Cómo quedó (v2.1.0):** rubro `🔎 Todos los rubros` (una tabla con todo el inventario, columnas
`Rubro` + `Dónde`, sin columnas de movimiento porque cada rubro tiene las suyas) y, estando adentro
de un rubro, el renglón **"También en otros rubros: …"** con la cuenta por rubro y el salto en un
click conservando lo tipeado. Las filas sin rubro propio se muestran igual, etiquetadas por lo que
son (Virgilio, Inyector, o el nombre del sector).

**El dato sale de `movimientos_bundle`, que la pantalla YA carga** (`D.inv` es el inventario
entero): **cero RPC nuevas**. Los únicos dos lugares que no viven ahí —prov. AT y tránsito PS—
se suman desde `stock_general_extra_bundle`, igual que en sus rubros.

**Regla que deja, para cualquier pantalla con selector:** un filtro que solo mira la pestaña
abierta obliga al usuario a saber la respuesta antes de preguntar. Si el índice completo ya está
en memoria (y acá lo estaba), la búsqueda transversal no cuesta nada y encima destapa lo que
ningún botón mostraba.

## 4ew. El 863 lleva mango de MADERA, aunque se llame "Mgo Chef" (2026-09-21)

`[usuario 2026-09-21, textual: "El 863 no usa ni PC6 ni PB6 ni PA19"; ejecutado con su "Sí", después
de plantearle que el nombre del artículo decía lo contrario]`

**La contradicción, que vale más que el cambio:** el **863** se llama *"Corta Pizza Gastro. **Mgo
Chef** Ø 8 Cm"* y lo que había que sacarle era justamente `PA19` **Mangos Chef**. Parecía un error
del pedido. No lo era: **el 863 llevaba DOS mangos**, `PA19` (chef) y `PEP8` (*Mango Madera Pizza
Ø9*), y el que queda es el de madera.

**Cómo se probó antes de ejecutar** `[dato 2026-09-21]` — el hermano:

| | receta |
|---|---|
| 863 (después) | A8, E9, LL1, **PEP8**, S1A, V12, Z35 |
| 564 *"Corta Pizza 8cm **Mgo Madera**"* | A3, E9, F4B, LL1, **PEP8**, V12, Z35 |

Idénticos salvo **caja** (A8 / A3) y **cartón** (S1A / F4B). Y los otros dos que se sacaron son los
accesorios que acompañan al mango chef en los 5 artículos que lo usan de verdad (709, 720, 722,
856, 857): `PB6` *Inser. Neg. Espat* y `PC6` *Ojales Neg/Blanco*. **Los tres son un kit y salen
juntos.** El corta pizza que sí es de mango chef es el **862**, que lleva `PA19` sin `PEP8`.

**Entonces lo que está mal es la DESCRIPCIÓN del 863, no la receta** `[deducido 2026-09-21, sin
confirmar]`. Se dejó el nombre como está: el dueño no contestó si el nombre comercial se corrige.
**Queda preguntado.**

**Se borró:** `articulo_componente` ids 779 (`PA19`), 780 (`PB6`), 781 (`PC6`) y las **3 rutas**
825 / 826 / 827 (`"Insumo PA19|PB6|PC6 -> Art 863"`) con sus 9 pasos. Queda con **7 componentes y
7 rutas**.

**Plata:** el costo del 863 baja **$381,09/uni** sobre 34 uni/mes (~$12.957/mes), y es **piso**
porque `PC6` **no tiene precio cargado** (`faltan_precios = 1`), o sea que la baja real es mayor y
hoy no se puede medir. Consumo: `PA19` 13 → 12 artículos (1.336 uni/mes), `PB6` 6 → 5 (90),
`PC6` 4 → 3 (134).

Invariantes de `db/verificar.sql` que pegan con lo tocado (L, S, U, W, X, AA, AB, AD): **0**. `AE`
da **2** y es **preexistente** (artículos 567 y 537).

**REGLA QUE DEJAN LAS TRES CORRECCIONES DE HOY** (`4es` el 311/312, `4eu` el 731, ésta): cuando un
artículo tiene **dos piezas que cumplen la misma función** — dos capuchones, una cacha donde va un
espiral, dos mangos — **una sobra**, y el que dice cuál es el **hermano**: el artículo que hace lo
mismo y está bien cargado. El nombre del artículo **no** es evidencia; la receta del hermano sí.

## 4ex. Una botonera que ya eligió se cierra; Sector y Proveedor son dos cajas (2026-09-21)

[usuario, textual] *"quiero que cuando toco un sector me desaparezca el resto de los sectores y
además haya un botón que diga Todos"* + *"separame bien lo que es sector y proveedor porque no se
entiende bien la separación"*. Dicho sobre `Compras/OC_GP2.html` (v1.34.0), pero es una **regla de
pantalla**, no un arreglo de esa pantalla: vale para cualquier botonera de filtro de GP2.

1. **Elegido = el resto desaparece.** Con un sector elegido se ve **ese chip y nada más**, más un
   chip **"Todos"** que lo suelta y devuelve la botonera entera. Los 9 sectores ocupaban dos
   renglones **después** de elegir, que es justo cuando ya no se miran.
2. **Cada filtro, su propia caja**, con la etiqueta adentro a la izquierda. Dos botoneras pegadas
   una debajo de la otra, sin borde, se leen como una sola lista corrida — por eso el usuario no
   veía dónde terminaba Sector y empezaba Proveedor.
3. **La caja abraza el contenido** (`inline-flex`): con un sector elegido queda chica, no una barra
   vacía a lo ancho. Es la regla de la casa de no dejar huecos.
4. **El PROVEEDOR no se colapsa, y es a propósito** [deducido, sin confirmar]: ahí se **compara**
   entre proveedores del mismo sector (quién cotiza más barato la misma caja: Corrugadora contra
   Recicor, que entrega las mismas 11 y ~19% más barato), y esconderlos
   obligaría a abrir y cerrar en cada comparación. El sector, en cambio, se elige una vez. Si el
   dueño lo pide, es la misma línea de código.
5. **"Todos" no muestra todo:** sin sector no hay lista (regla del 2026-09-04, *"si no pongo el
   sector y no pongo el proveedor, que no me aparezca la lista"*), así que "Todos" vuelve al cartel
   "Elegí un sector". El chip elegido también se sigue soltando tocándolo, como siempre.

## 4ey. El sustento del consumo sale de la O.C.: módulo propio "Consumo x Componente" (2026-09-21)

**Lo que dijo el usuario, textual:** *"Quiero que me hagas un módulo que pueda ver por componente,
por sector, el consumo... por ejemplo, ya las órdenes de compra, hay algo parecido, de que yo en
PB6 cuando toco el máximo me dice en qué artículo se usa. Bueno, lo quiero eso, pero afuera. Otro
módulo aparte"*.

**Lo que había:** el desglose del Máximo de la O.C. (`oc_maximo_desglose`, pantalla
`Compras/OC_GP2.html`) y el popup compartido `consumo-detalle.js`, que ya contestaba "qué artículos
usan esta parte". El problema no era la información: era **el lugar**. La O.C. lista sólo lo
**comprable** y agrupado por rubro de compra, así que para mirar el sustento había que entrar a
comprar, y los componentes que no se compran no se podían mirar en ningún lado.

**El número: 567 componentes tienen consumo atribuido, y la O.C. muestra una fracción.** Los
**193 de los sectores que NO son insumo** (`sector.es_insumo = false`: Procesado 84, Crudo 75,
Movimiento 33, Afilado 1 — se fabrican, no se compran) no aparecían en ninguna pantalla con su
consumo mensual.

**Cómo quedó:** `Consumo/Consumo_GP2.html` (grupo Despiece del menú, al lado de *Despiece x
Artículo* — son las dos puntas del mismo mapa: del artículo a sus partes, y de la parte a los
artículos que la piden). Selector por sector con la cuenta de componentes, búsqueda, orden por
consumo de mayor a menor, CSV, y al tocar la fila el mismo popup de siempre. Una sola RPC nueva,
`consumo_bundle()` (~170 KB, 567 filas).

**No hay cuenta nueva: es el mismo motor que decide las compras.** `uni/mes` sale de
`v_consumo_componente`, el kg/mes de fleje de `v_consumo_fleje_kg`, y el kg/mes de resina del mismo
rollup por pieza que ya usaba `oc_maximo_desglose` (peso × consumo × `inyeccion_desperdicio_pct`).

**Lo que destapó, y es el hallazgo:** una **resina no está en ninguna receta**, así que
`v_consumo_demanda` no la toca y el popup le contestaba *"ningún artículo de la Est Madre llega a
esta parte"* — justo donde hay más kg en juego (9 resinas, **1.602,65 kg/mes**, el PP 2630 solo
807). El sustento de una resina son las **PIEZAS** que se inyectan con ella, no los artículos. Se
le agregó esa rama a `consumo_detalle` (clave `base`: `articulos` | `piezas`) y al popup, así que
también la ganan Pintores y Orden de Producción.

**Dos cosas que quedaron AFUERA a propósito:**
1. **El sector Terminado (198 componentes).** Un terminado no se consume, se vende: su número es la
   proyección de la Est Madre del artículo. Mezclarlo haría leer como consumo lo que es demanda.
2. **Stock y máximo.** Eso es la O.C.; esta pantalla contesta *cuánto se gasta y quién lo gasta*.

**Trampa a recordar al leer cualquier consumo de esta pantalla** (ya estaba en 4es): el consumo
sale de la Est Madre, así que un artículo `discontinuado` aporta **cero** aunque tenga proyección
viva, y un código con hermano `L` (p. ej. `312L`) suma al mismo artículo. Una diferencia entre "lo
que suman las recetas" y lo que muestra la pantalla casi siempre es una de esas dos.

## 4ez. Los Pisa Papas (121, 315, 609): el disco con vástago y el armado son de Pettofrezza (2026-09-22)

> ⚠ **CORREGIDA EL 2026-09-23 POR LA §4fl**: el `M1` (disco con vástago) **desaparece** del modelo.
> A Rafael se le manda el `M2` y el vástago **sueltos**, como cualquier otro componente. Lo que sigue
> vale como historia de por qué el paso existió un día; el modelo vigente es el de la §4fl.

`[usuario 2026-09-22, textual: "El 121 arma el disco con vástago Rafael Pettofrezza y también lo envasa
el. Modifica las rutas… y que se le pueda mandar todo en envio talleristas"` y, para los otros dos:
`"Para el 315 y 609 también hace el vástago"`]

- **Antes** `[dato]`: el `M1` (*Disco Inox C/Vástago Alu* = `M2` + `V18C`) lo hacía la **Matriz 113**
  en los tres, y el 121 lo armaba y envasaba **Cavallero German**. El `V18C` **no estaba en ninguna
  ruta**, así que no se le podía mandar a nadie.
- **Ahora**: el paso `M2 → M1` es tallerista **Pettofrezza Rafael** (id 11) en las rutas 136, 553 y
  558; el armado del 121 (rutas 136, 266, 267, 268, 477) pasó de Cavallero a Pettofrezza; y hay una
  ruta nueva por artículo `insumo V18C → Pettofrezza (V18C→M1) → Pettofrezza (M1→art) → virgilio`.
- **Envío Talleristas no necesitó código**: `talleristas_bundle` lee `v_contraparte_parte`, que sale
  de `ruta_paso`. Verificado: la entrada de Pettofrezza ya lista `M2`, `V18C`, `PA10B`, `PC11`, `I3C`, `A3`.
- **Cavallero German quedó sin rutas** (tenía sólo el 121; 0 stock y 0 movimientos: no quedó nada colgado).
- ⚠ **Costo**: la Matriz 113 salió de los tres. Pettofrezza **no tiene precio para el 121** (el de
  Cavallero, $85, ya no aplica); el 315 y el 609 tienen $140 "AyE". Pendiente que el usuario diga
  el precio del 121 y si el disco con vástago va aparte o está dentro del AyE.
- ⚠ Hay **dos componentes con código `M1`**: 146 (el disco) y 823 (*Cartón 220*). Buscar por id.

## 4fa. El maestro de matrices se completó con el del vecino: 406 matrices (2026-09-22)

`[usuario]` textual: *"En caso que falten matrices listadas en Gestión Productiva 2.0, quiero que les
sumes los N° y Descripción de las matrices faltantes que si aparezcan en Gestión Productiva Entero"* +
*"Carga las 290 que mencionas y también la de pruebas; las que dicen discontinuas no las cargues...
quiero que les cargues en Tiempo cargado el valor cargado en T Hist... si alguno de los tiempos
cargados en Gestión Productiva 2.0 es diferente... deja el de Gestion Productiva Entero"*.

- **EXCEPCIÓN A LA REGLA 0, pedida por el dueño y de una sola vez:** `GP2.matriz` pasó de 115 a
  **406** filas copiando N°, descripción y `Tiempo_Historico` de `public."Matrices"` (413 filas).
  No quedó nada leyendo `public`: fue un INSERT puntual, no una vista ni una función.
- Afuera: las 8 con `Disc=true` (43, 115, 158, 159, 160, 168, 337, 351, descripción "(discontinuada)").
  Adentro, a pedido: la **0 "Pruebas"** (T Hist 1).
- Las nuevas entran **activas** y con `uni_x_golpe` en 1 (el default: el vecino lo tiene casi todo vacío),
  así que el operario las ve para elegir. De las 291, solo 126 tuvieron alguna producción en el vecino.
- **Tiempos: manda el vecino.** Solo 2 difirieron: **360** vacío → 1,3 y **365** 2,41 → **1,7**. OJO:
  el 2,41 de la 365 era la MEDIANA MEDIDA de 5 producciones reales (tabla de §2c-vicies); el
  dueño eligió igual el 1,7 del vecino. No "corregirlo" de vuelta sin preguntarle.
- `[dato]` Después de la carga: 0 tiempos distintos entre los dos programas, 150 matrices sin tiempo.
- La pantalla Tiempos Matrices ya lista el maestro entero (commit 288d6a0 del mismo día).
- **360 y 360B se llaman igual ("Corte Ahueca")** — posible duplicado del vecino. `[usuario 2026-09-22]`: *"por ahora dejalas ambas asi como están, más adelante te digo como las cambiamos"*. No tocar hasta que lo diga.


## 4fb. Correcciones de recetas que salieron del despiece (2026-09-22)

`[usuario 2026-09-22]` Thomas revisó el Excel `Despiece_x_Articulo_GP2.xlsx` y pidió corregirlo **en GP2**
(*"no en el Excel, porque ya lo estoy modificando yo"*). Todo ejecutado con su "sí" y verificado:

| Art. | Cambio | Dicho |
|---|---|---|
| 223, 224, 225, 922, 911, 901 (cucharas madera 25/30/35) | Caja N°16 (A7B) → **Caja N°12 (A2)** | "usan caja N°12, NO 16" |
| 248 (Cuchara Nylon Reforzada 33) | Caja N°16 → **N°12**; armado Fábrica → **Alex Escalante** | |
| 307 (Cepillo Limpia Vaso) | Caja N°15 → **Caja N°6 (A5)**, sigue 24 x caja | |
| 234 (Palo Amasar Francés) | + **BANDITA** x1, igual que 231/232/233 | "lleva bandita… una" |
| 246, 900 (Prensa Matambre) | + **`BANDITAM` Bandita Prensa Matambre** x1 (alta nueva: Sector Cartón, unidad, Talleres Gráficos Pol, ruta insumo → Maspoli → Virgilio) | "se lo compramos al mismo proveedor que la bandita palo de amasar" |
| 280 (Manga Repostera) | Tela `BOM8B` **1/900** (el rollo trae 900): la tela se cuenta en **ROLLOS**, máximo 4.812 → 5,35, nombre "(rollo x 900)"; armado Fábrica → Blist-Pack SA → **de vuelta a Gentile Norberto el 2026-09-23** (ver 4fk) | |
| 338 (Espátula Lisa) | **discontinuado** | |
| 031, 120, 836 (IC3) y 034, 867 (IC3V) | Fleje N° 90 **1 por unidad**: IC3/IC3V pasaron de `kg` a `unidad` | "lleva un alambre" |

**Fleje 90 en unidad, sin tocar código** `[dato]`: el ledger convierte con `to_canonical` según
`componente.unidad_medida` y `kg_x_uni`. `cargar_recepcion_charcas` sigue grabando el movimiento en **kg de
balanza** y el stock de IC3/IC3V entra en **unidades** (0,83 kg de IC3 = 100 uni). `charcas_pendiente` y el
objetivo de Altrak siguen en kg (leen `recepcion_insumo`, que queda en kg). Es el mismo modelo del IE4/IE5.
Se pudo hacer sin migrar porque IC3/IC3V tenían 0 stock, 0 movimientos, 0 recepciones y 0 OC; los máximos
se convirtieron (÷ kg_x_uni).

**Quedan sin precio de tallerista** (el costo no suma ese paso): 121 Pettofrezza, 248 Alex, 280 **Gentile Norberto** (era Blist-Pack; volvió a Gentile el 2026-09-23 y sigue sin precio).

## 4fc. El Prov. de Art. Terminado ya tiene consumo, máximo y sugerido (2026-09-23)

> **CORREGIDO AL DÍA SIGUIENTE (2026-09-24, §4fw):** el dueño dio vuelta esta decisión. El prov AT
> **ya NO va como el tallerista a façon** (máximo de la casa, consumo × mes): va **como talleristas
> O.C.**, con **sugerido 0**, porque es gente de menos confianza y lo que hay que mandarle sale de
> una O.C. de Gestión Virgilio que GP2 no lee. La maquinaria de abajo (`reparto_prov_at`,
> `v_consumo_prov_at`, `recalcular_maximos_prov_at`) **queda dormida** —nunca escribió un máximo
> (inventario de prov AT = 0 filas)—, así que no se borra: si el dueño vuelve a querer el máximo de
> la casa, se reactiva. Lo de abajo queda como historia de lo que se construyó.

`[usuario, textual]`: *"En el módulo prov de art terminado, cuando voy a enviar: me aparece 0
sugerido para enviar. El inventario máximo de los prov de art terminado tiene que ser al igual que
los talleristas de un mes de consumo. Si hay más de un prov de art terminado o tallerista que haga
un artículo tenés que dividir según la proporción. Si no está la proporción → por default 50% cada
uno"*.

**El 0 no era un máximo sin cargar: era una cuenta que no se hacía.** El sugerido de la Tablet no
sale de `inventario.maximo` — lo calcula al vuelo la CTE `rep` de `GP2.tablet_bundle`, y esa CTE
filtraba `where tipo in ('proveedor_servicio','tallerista')`. El Prov AT nunca entraba, así que su
fila viajaba con `maximo` y `sugerido` en NULL y la tablet mostraba "Online sector". Cargar máximos
a mano no lo hubiera arreglado.

**Lo que se construyó** (calcado de lo que ya existía para talleristas, §4du):

| Objeto | Para qué |
|---|---|
| `reparto_prov_at` | el % dictado por artículo + prov AT (se carga por SQL, no hay pantalla) |
| `v_hace_articulo` | quién produce o entrega el TERMINADO: prov AT y tallerista del sector 12 |
| `v_reparto_at_efectivo` | el % efectivo; sin dictar, partes iguales entre los que lo hacen |
| `v_consumo_prov_at` | demanda del artículo × ese % = cartón/caja que consume cada prov AT |
| `v_nivel_stock_prov_at` | `max_calc = consumo × meses_stock` de SU ubicación (default 1 mes) |
| `recalcular_maximos_prov_at()` | escribe `inventario.maximo`, origen `est_madre_x_reparto` |
| `tablet_bundle` | `rep` cubre `proveedor_at`; los meses salen de la ubicación del prov AT |

Todo el SQL, con su porqué, en `db/migracion_maximo_prov_at.sql`. Las dos funciones quedaron
**verificadas por md5** contra la base.

**Lo medido al aplicarlo:** 5 prov AT reciben cartón/caja hoy (Pintos 15 piezas, Lopez Jose 6,
Maspoli 5, The Plast 4, Carriero 3) y **las 33 filas quedaron con número**: ninguna sigue en "—".
Los dos artículos con dos proveedores son el **222** y el **910** (Maspoli / Pintos): su cartón pasa
a 545 + 545 y 142 + 142, el 50/50 por default. Si el dueño dicta otra proporción, va en
`reparto_prov_at` y el número cambia solo.

**Tres cosas que quedan escritas:**
1. **Ningún artículo lo hacen hoy un prov AT y un tallerista a la vez** (medido: 0 filas). Por eso
   `v_consumo_tallerista` NO se tocó. Si mañana aparece uno, el prov AT ya queda en 50 % y el
   tallerista seguiría en 100 % hasta que el dueño confirme — la fila sucia de `articulo_prov_at`
   (§4cy) es la razón de no bajarle el máximo a un tallerista solo.
2. **Las 12 ubicaciones de prov AT tienen `meses_stock` NULL y CERO filas de `inventario`.** El
   "1 mes" lo pone un `coalesce`, y `recalcular_maximos_prov_at()` informa lo que le falta fila en
   vez de fallar; con `p_crear_faltantes => true` las crea en 0 con su máximo. **No se corrió:
   crear filas es escribir datos y eso lo autoriza el dueño.**
3. **16 de los 33 cartones no tienen formato cargado** (`carton_formato` sin `uni_x_bolsa`), así que
   su sugerido se ve en unidades y la tarjeta avisa "sin paquete cargado". Con el formato cargado
   pasaría a paquetones, como el resto.

## 4fw. El Prov. de Art. Terminado va como "Talleristas O.C.": sugerido 0 (2026-09-24)

`[usuario, textual]`: *"En el envío a proveedor de artículo terminado, al igual que talleristas
orden de compra, no tienen un máximo de inventario allá ellos, de un mes, como los talleristas,
porque proveedor de artículo terminado y talleristas OC es gente que no tenemos la misma confianza
que con los talleristas. Tenés que modelarlo al igual que talleristas OC, que no tienen un máximo
allá, por lo tanto no tiene que haber un sugerido de qué mandarle, sino que tiene que aparecer en
cero. ¿Cuándo va a aparecer? Cuando salga orden de compra de Virgilio, que todavía no lo modelamos,
porque lo hace otro sistema ahora"*.

**Da vuelta §4fc de AYER.** El 2026-09-23 se decidió que el prov AT tuviera máximo = consumo × un
mes, igual que el tallerista a façon; el 2026-09-24 el dueño lo **reagrupa con la gente de menos
confianza** (talleristas O.C., §4fr). El eje del cambio es de negocio, no técnico: al prov AT **no
le fiamos un mes de stock** como al tallerista de confianza; lo que tiene que hacer lo dicta una
**O.C. que emite Gestión Virgilio**, sistema que GP2 **todavía no lee**. Por eso su sugerido es 0 y
subirá cuando esa O.C. se modele acá (hoy la hace otro sistema).

**El cambio es una línea en la base.** `GP2.tablet_bundle`, CTE `rep`, case del techo:
`when e.tipo = 'proveedor_at' then 0` — mismo criterio que el fasonero sin O.C.
(`proveedor_servicio.pedido_por_oc`) y el tallerista con O.C. de Virgilio
(`tallerista.pedido_por_oc_virgilio`). **No hace falta flag por proveedor: TODO el rubro va así.**
En el front (`Tablet_GP2.html`, v1.36.0) el título de la carga agrega **"· O.C. Virgilio"** también
para el prov AT, porque un 0 pelado se lee como "no hay que mandarle nada".

**Medido antes → después:** las 47 filas de prov AT del Enviar pasaron de **33 con sugerido
(28.905 uni)** a **0**. Talleristas normales (**316** con sugerido), talleristas O.C. (**0**) y P.S.
(**108**) **intactos** — el cambio es quirúrgico.

**La maquinaria de §4fc queda dormida, NO se borra:** `reparto_prov_at` (0 filas),
`v_consumo_prov_at`, `v_reparto_at_efectivo`, `v_hace_articulo`, `v_nivel_stock_prov_at`,
`recalcular_maximos_prov_at`. Nunca escribió un máximo (las 12 ubicaciones de prov AT tienen 0 filas
de `inventario`), así que **no hay nada que revertir**. Si el dueño vuelve a querer el máximo de la
casa, ese `then 0` es lo único que se cambia. SQL en `db/migracion_prov_at_oc_virgilio.sql`.

## 4fd. Recibir de un P.S. es EL REMITO, y el remito va en unidades (2026-09-23)

`[usuario, sobre cinco proveedores distintos el mismo día]`: *"cuando voy a recibir de AJ adhesivos
el remito marca en unidades de pliego y después cuando voy a controlar sí, marco paquetes"*; lo
mismo con **Ester** (*"en el remito aparece en unidades y después el control si lo hago en bolsas y
kilos"*), **Hernández Julio** (*"me aparece en unidades y el control sí en cajones y kilos"*),
**Jade** y **Maspoli**.

**Son dos momentos y cada uno tiene su unidad.** Lo que se carga en la Tablet es el **remito**, y el
remito del proveedor viene contado en unidades de la pieza. El **envase** (bolsas de Ester, paquetes
de 200 de AJ, cajones de Jade y Julio) y los **kilos** son del **control**
(`ControlEntregaPS_GP2.html`), la pantalla a la que la tablet manda derecho desde la v1.28.0.

**Da vuelta la regla de v1.20.0** (*"la entrega copia la unidad del envío"*, 18/09). Esa regla no
estaba mal: se escribió **tres días antes de que el control fuera una pantalla aparte**, cuando lo
que se cargaba en la tablet era lo contado. Cuando el flujo se partió en dos, la unidad del envase
se quedó en el lado equivocado.

**El cambio es una línea**: la rama de recibir de `envaseDe()` devuelve `null` para el P.S. Con eso
la tarjeta dice el stock en unidades, el campo va en unidades, y se van el renglón "≈ N bolsas" y la
doble carga envase + kg. **Cero base**: `proveedor_servicio.entrega_unidad` / `entrega_uni_x` siguen
existiendo porque las usa el Control, que es su lugar.

**El TALLERISTA no se tocó**: ahí no hay pantalla de control y el esperado en cajones + la cantidad
en kg los pidió el usuario el 18/09 (§v1.19.0 de la Tablet). Si también tiene que ir en unidades, es
el mismo cambio de una línea.

## 4fe. El control de un P.S. se cuenta en el envase y en kilos (2026-09-23)

`[usuario, textual]`: *"Cuando voy a hacer el control de AJ adhesivos me aparece para marcar uni. Y
yo te dije solo paquetes"* y, enseguida: *"Lo mismo con Esther. El control lo hago en bolsas y
kilos, no en unibolsas. Me estás poniendo unidades cuando yo arriba te dije otra cosa"*.

Es la otra mitad de §4fd. Si el **remito** va en unidades, el **control** va en lo que se cuenta de
verdad: el **envase** (paquetes de AJ, bolsas de Ester y Maspoli, cajones de Julio y Jade, paquetes
de Charcas) y, donde la pieza se pesa, los **kilos**. El campo "Contado (uni)" se fue de
`ControlEntregaPS_GP2.html`: la unidad de la pieza dejó de ser algo que alguien tipea y pasó a ser
el **resultado**, que la tarjeta muestra antes de confirmar ("= 400 uni · Diferencia …") porque es
lo que se guarda y lo que pisa el stock.

**Cuál manda si están los dos: el PESO.** Mismo criterio que el control de la recepción de insumos,
donde los kg de la balanza son los que se guardan. Sin kg cargados, manda el envase.

**El dato tiene que estar, y esto es lo que falta** `[usuario: "Si vos tenés el dato de uni por
paquete o kilo por uni, podrías hacer el control. Si no lo tenés, lo tendríamos que agregar"]`.
Medido el 2026-09-23 sobre las piezas que devuelven los P.S. no híbridos:

| Falta | Piezas |
|---|---|
| Sin `kg_x_uni` (no se puede pesar) | los **10 pliegos de AJ Adhesivos** (control sólo en paquetes) |
| Sin envase (ni factor del proveedor ni `uni_x_cajon`) | **V18D** y **W1B** (Guazzaroni) y **C12** (Pedernera) |

Las tres últimas caen al campo suelto en unidades hasta que se les cargue el cajón. El resto —25
piezas de Guazzaroni, 34 de Pedernera, las de Ester, Julio, Jade, Maspoli y Charcas— ya tiene todo.

## 4ff. "Recibí de más" no se dispara por un decimal (2026-09-23)

`[usuario, con 1.852 uni de PC1A contra 1.852 esperadas]`: *"¿Por qué salta la alerta? Es
exactamente la misma cantidad"*. El cartel decía **"⚠ 0 de más"**, que es la firma del problema.

**La causa es el saldo del tercero, que arrastra decimales.** A Esther se le mandan 10 kg de mangos
y eso son **1.851,8518… unidades** (10 / 0,0054): ese 0,8518 queda colgando en su stock. Al recibir
1.852 el sistema comparaba crudo (`recibido > esperado`), veía 0,1481 de exceso y anotaba una fila
en `GP2.alerta_recepcion`. La alerta **id 5** (Ester, PC1A, esperado 1851,851851, recibido 1852,
exceso 0,148148) es exactamente eso, y quedó abierta.

**La tolerancia es media unidad, o 5 gramos si la pieza se mide en kg**, y vive en las **dos
puntas**: `exceso()` de la Tablet (el cartel que ve el operario) y el `if v_comparable > v_esp` de
`GP2.tablet_registrar` (el que escribe la alerta). Tocar sólo el front hubiera sacado el cartel y
dejado la alerta anotándose igual.

**Lo que NO se tocó**: la alerta 5 sigue abierta. Cerrarla es escribir datos y lo autoriza el dueño
(`alerta_recepcion_marcar(5, 'resuelta', …)`).

## 4fg. La diferencia se juzga en el control, contra el remito, y recién arriba del 5 % (2026-09-23)

`[usuario, textual]`: *"espero que el cartel aparezca si hay más de un cinco por ciento de
diferencia, tanto en kilos como en unidades. Pero este cartel, esta alerta, me tiene que aparecer no
a la hora de recibir, sino a la hora de hacer el control. Porque puede haber 1.800 unidades de stock
de proveedor de servicio… y capaz recibo menos"*. Y enseguida: *"El remito en unidades y el control
en kilos"* y *"en el control que las bolsas o los cajones sirvan nada más de dato. Vos lo que tenés
que comparar es los kilos con los kilos o los kilos con las unidades, en el caso de que tengas que
hacer el pasaje"*.

**Son tres reglas que cierran el circuito de §4fd y §4fe:**

| Momento | Qué se carga | Contra qué se compara |
|---|---|---|
| **Recibir** (Tablet) | el REMITO, en unidades de la pieza | **contra nada**: el stock del P.S. no es lo que va a traer |
| **Control** (ControlEntregaPS) | los KILOS (el envase es un dato) | contra el remito, y avisa arriba del **5 %** |

**Por qué al recibir no se compara:** el saldo que el proveedor tiene en su poder es una referencia,
no una promesa. Una entrega parcial —1.800 en su poder y traer 600— es lo normal, y convertir eso en
"recibí de más" llena `GP2.alerta_recepcion` de ruido. En los **otros destinos** (tallerista, prov.
AT, Virgilio) el aviso quedó, pero con el mismo umbral del 5 %.

**Por qué el peso manda en el control:** es lo que se mide con la balanza. El envase se sigue
anotando (`controlar_entrega_ps.p_cajones`, el dato físico de bultos) pero no decide el número. Donde
la pieza se pesa, el kilo es **obligatorio**; donde no hay `kg_x_uni` —los 10 pliegos de AJ— el
envase es lo único que hay y con eso alcanza.

**Dónde vive cada número** (los dos con clave propia y su default, así no hace falta cargar nada):

- el 5 % del control: `control_entrega_ps_bundle` lee `parametro.tol_ctrl_ps_pct`, y sin esa fila
  vale 5. **Antes compartía `tol_ctrl_peso_pct` con el pesaje de insumos, que sigue en 2 %.**
- el 5 % del aviso al recibir: `exceso()` de la Tablet y el `if` de `GP2.tablet_registrar`, con el
  piso de media unidad (5 gramos en kg) de §4ff para el caso de esperado 0.

## 4fh. El remito del tallerista también va en unidades (2026-09-23)

`[usuario, textual]`: *"Hicimos todas las recepciones de proveedores de servicio. Ahora seguimos con
las recepciones de talleristas. Lucho. Remito en unidades y control en kg y cajones (acordate de
hacer el control por kg — cajones es solo dato)"*.

Misma regla que §4fd, del otro lado: lo que se carga en la Tablet es **el papel**, y el papel viene
en unidades de la pieza. Da vuelta la v1.19.0 de la Tablet (*"de talleristas, todos se entregan en
cajones… en recibido va a ser en kilos"*, 18/09), escrita cuando lo que se cargaba ahí era lo
contado. `componente.entrega_unidad` / `entrega_uni_x` (las bolsas de 120 de GRJ5 y GRJ6) **no se
tocan**: son el envase con el que se va a contar en el control.

**Lo que todavía NO existe: el control de talleristas.** `ControlEntregaPS_GP2.html` y su circuito
(`control_entrega_ps_bundle`, `controlar_entrega_ps`, `entrega_ps_control`) sólo miran movimientos
`entrega_ps`. Por eso el aviso del 5 % al recibir de un tallerista **sigue vivo** en la Tablet: es
la única red que queda hasta que el control exista. El día que exista, esa comparación se va de la
recepción igual que se fue la del P.S.

**La decisión que hay que tomar antes de construirlo** (planteada al dueño el 2026-09-23): la
entrega de un tallerista NO es un movimiento solo. `crear_entrega_tallerista` escribe el
`entrega_tallerista` de la pieza que entra **y** uno o varios `consumo_tall` (la pieza que
transformó, o las partes del BOM), todos con la misma cantidad y sin columna que los vincule.
Si el control pisa la cantidad de la entrega, hay que decidir qué pasa con esos consumos:

| Opción | Qué significa |
|---|---|
| **Escalar** los consumos por el mismo factor | entregó 98 de 100 → consumió 98: el 1:1 y el BOM quedan coherentes |
| **Dejarlos** con lo declarado | entregó 98 y consumió 100: los 2 que faltan son merma del tallerista |

No es lo mismo para el stock del tallerista, y lo tiene que decir el dueño.

## 4fi. La unidad del remito la dice la PIEZA, no el destino (2026-09-23)

`[usuario, textual]`: *"Martin Cornejo. El remito de las bombillas en uni. Control en bolsas. El
remito de la cuchilla en kg y control kg y cajones (cajones dato)"*.

Esto corrige el §4fh del mismo día, que había dejado **todo** el remito del tallerista en unidades:
**dos piezas del MISMO tallerista vienen en unidades distintas**. Las bombillas (GRJ5/GRJ6) se
cuentan; la cuchilla (X4) se pesa. No lo decide el destino ni el sector: es una propiedad de la
pieza.

**Columna nueva `componente.remito_unidad`** (`'uni'` | `'kg'`, NULL = la unidad canónica).
`tablet_bundle` la manda en cada fila de Recibir y la Tablet la usa para el stock que muestra, para
el campo y para lo que viaja a la base (`uniRemito()` / `cargaEnKg()`). El envase del control
(`entrega_unidad` / `entrega_uni_x`, las bolsas de 120 de GRJ5 y GRJ6) **no se toca**: es otra cosa.

**Lo dictado hasta ahora**, para cargar el dato: X4 (Cuchilla Pelapapa Cerrada) en **kg**; bombillas
GRJ5/GRJ6 en **uni**; J1 de Lucho en **uni**; E4 de Scorrano en **uni**. Todo lo demás queda en su
unidad canónica (uni) hasta que el dueño diga lo contrario — el dato se carga pieza por pieza, no se
adivina por sector.
## 4fj. Enviar a un tallerista se ordena por RUBRO, no por código (2026-09-23)

`[usuario, textual]` *"En el módulo de envío a talleristas dentro de la versión tablet, quiero que
me ordenes no alfanuméricamente, sino que primero me pongas todo lo que se le manda de sector crudo,
después todo lo de sector procesado, después todo los remaches, después todo lo de partes plásticas,
después todo lo de cajas y después todo lo de cartones"* + *"me refiero dentro de cada tallerista"*
+ *"Garage ponelo primero, fleje segundo y bombilla último"*.

**El orden definitivo, el que está en `RUBRO_ORDEN` de `Tablet_GP2.html`:**

| # | Rubro | | # | Rubro |
|--:|---|---|--:|---|
| 1 | Garage | | 6 | Plásticas |
| 2 | Fleje | | 7 | Cajas |
| 3 | Crudo | | 8 | Cartones |
| 4 | Procesado | | 9 | Bombilla |
| 5 | Remaches | | 10 | lo que no esté en la lista |

**El orden de una lista de picking lo dicta el galpón, no el abecedario.** El envío se arma
caminando: el crudo y el procesado están en un lado, los cartones y las cajas en otro. Alfabético,
las cinco piezas del fixture de Martin (A10 crudo, BANDITA cartón, C10 cartón, CJ7 caja, F7 fleje)
obligan a cuatro paradas en cinco tarjetas, y el cartón queda partido en dos con la caja en el
medio. Por rubro, cada bloque es una parada.

**El rótulo del rubro no es decoración.** Con el código fuera de secuencia y nada que explique por
qué, el orden nuevo se lee como un desorden: cada bloque lleva su nombre de sector arriba
(`.pc-rubro`, ancho entero de la grilla, así que a 390px se ve igual).

**Los tres sectores que el primer pedido no nombró existen, y por eso el orden se cerró en nueve**
`[dato, medido sobre GP2.tablet_bundle el 2026-09-23]`: a los talleristas también se les manda
**Fleje** (6 filas, 3 talleristas), **Bombilla** (15 en 5) y **Garage** (11 en 4) — 32 de las 350
filas de Enviar a tallerista. Quedaron un rato al final por descarte; con el número a la vista el
dueño los ubicó él (*"Garage ponelo primero, fleje segundo y bombilla último"*). **Lección de
método: cuando un pedido enumera categorías, contar primero cuántas hay en la base.** Si ese conteo
no se hacía, 32 filas se decidían solas.

**Un sector que no esté en la lista cae al fondo, detrás de Bombilla.** Hoy no hay ninguno en Enviar
a tallerista (Movimiento, Terminado y Bolsas Plásticas no llegan). El día que aparezca uno, el lugar
honesto para algo que nadie clasificó es abajo y a la vista, no colado en el medio.

**El "➕ Otro cartón" cierra el bloque de cartones, no la grilla** `[usuario 2026-09-23: "el módulo
de otro cartón no lo dejes al final de todo, ponelo a lo último de los cartones"]`. Desde el
2026-09-21 iba al final de todas las tarjetas, que con una lista alfabética era "al lado de nada";
con bloques por rubro, "al final" pasó a ser tres bloques debajo de los cartones. **Es un cartón
más, así que vive donde están los cartones.** Sin bloques (prov. de art. terminado) sigue al final.

**Solo el tallerista.** P.S., prov. de art. terminado e inyector siguen alfabéticos y Recibir no se
tocó: el pedido fue explícito sobre el tallerista, y el mismo orden se puede extender cuando lo
pida. **Cero base**: el `sector` de cada pieza ya viajaba en `tablet_bundle.enviar`.

## 4fk. El control ahora también es de los talleristas (2026-09-23)

Cierra lo que §4fh dejó abierto. El circuito del control —remito primero, conteo después— dejó de
ser sólo del P.S.:

| Antes | Ahora |
|---|---|
| `control_entrega_ps_bundle` / `controlar_entrega_ps` | **`control_entrega_bundle`** / **`controlar_entrega`** |
| tabla `entrega_ps_control` | tabla **`entrega_control`** (misma estructura, 0 filas al renombrar) |
| sólo movimientos `entrega_ps` | `entrega_ps` **y** `entrega_tallerista`, en una sola lista |

**El envase del tallerista lo dice la PIEZA** (`componente.entrega_unidad` / `entrega_uni_x`: bolsas
de 120 en GRJ5 y GRJ6, cajones en el resto) y viaja en las mismas claves que el P.S., así que la
pantalla no aprendió un modelo nuevo. **Quién se pesa lo decide la base** (clave `pesa` del bundle):
una pieza de tallerista que declara su propio envase **se cuenta y no se pesa** —las bombillas—,
mientras que la cuchilla va en cajones + kilos y manda el peso. Es exactamente lo que dictó el
dueño: *"El remito de las bombillas en uni. Control en bolsas. El remito de la cuchilla en kg y
control kg y cajones (cajones dato)"*.

**LA COLUMNA QUE FALTABA: `movimiento.mov_padre_id`.** Una entrega de tallerista NO es un movimiento
solo: `crear_entrega_tallerista` escribe el `entrega_tallerista` **y** uno o varios `consumo_tall`
(la pieza transformada o las partes del BOM). Hasta hoy nada los vinculaba, y **no alcanzaba con la
fecha**: la Tablet manda día + 12:00, así que todas las entregas del día comparten la misma marca.
Ahora cada consumo cuelga de su entrega.

**Qué hace el control con esos consumos** `[decisión del dueño, 2026-09-23, entre dos opciones que
se le plantearon]`: **se escalan con el mismo factor**. Entregó 98 donde el remito decía 100 →
consumió 98, y el 1:1 y el BOM quedan coherentes. La alternativa (dejarlos en 100 y leer la
diferencia como merma del tallerista) quedó descartada.

**Y el aviso de "recibí de más" se fue de la recepción del tallerista**, igual que se había ido de
la del P.S.: ahora tiene dónde compararse de verdad. Al registrar el remito, la Tablet manda
derecho al control, también en el tallerista.

## 4fl. Los Pisa Papas (121, 315, 609): el `M1` desaparece — a Rafael se le manda el disco calado y el vástago suelto (2026-09-23)

`[usuario 2026-09-23, textual]` *"Va a desaparecer el componente M1. Ahora se le manda el disco
pizapapa calado. Y el vástago de aluminio a Rafael. Como cualquiera de los otros componentes. Como
los insertos, como el cartón, como el mango. Y él entrega el artículo terminado en Virgilio.
Además… El vástago aluminio V18C tendría que ser V18 porque no es crudo. Como es aluminio, ya se
compra así y sería el procesado, digamos."*

**Corrige la §4ez del 2026-09-22 (un día de vida).** Ahí el `M1` había sobrevivido como paso de
Pettofrezza (`M2 → M1`, y después `M1 → artículo`). El dueño lo saca del modelo: **el disco con
vástago no es una pieza, es el artículo empezando a armarse.** Rafael recibe el `M2` (Disco Pisa
Papa Calado) y el vástago sueltos, igual que el inserto, el cartón y el mango, y devuelve el
terminado. Un intermedio que sólo existe adentro del taller del que lo arma es un nodo de más:
obliga a un paso de ida y vuelta consigo mismo y a una fila de stock en cada ubicación por la que
no pasa nada.

- **Antes** `[dato]`: `M1` = `M2` + `V18C` (`componente_bom` 9 y 10), receta de los tres artículos
  con `M1` cantidad 1, y **12 filas de `ruta_paso`** — el `M2 → M1` de las rutas 136/553/558 y el
  `V18C → M1` + `M1 → art` de las rutas 1057/1058/1059.
- **Ahora**: la ruta del fleje termina `matriz 349 → M2 → Pettofrezza (M2 → art) → virgilio`, y la
  del vástago es `insumo V18 → Pettofrezza (V18 → art) → virgilio` — exactamente la forma que ya
  tenían `PA10B`, `PC11`, `I3C` y `A3`. La receta cambia `M1` por `M2` (1) + `V18` (1).
- **`M1` se puede borrar limpio** `[dato 2026-09-23]`: id 146, **0 stock y 0 movimientos**, y no lo
  referencia nada más que sus 4 filas de `inventario`, sus 2 de `componente_bom`, sus 3 de
  `articulo_componente` y sus 12 de `ruta_paso` (barrido de las 28 FK a `componente`). Beneficio de
  paso: se va el **`M1` duplicado** — quedaba el disco (146) y el *Cartón 220* (823) con el mismo
  código, y había que buscar por id.
- **`V18C` → `V18`, y el motivo del dueño es correcto aunque la letra no sea la del crudo**: en GP2
  los crudos de remache llevan **prefijo `CV`** (§ de los 12 `CV*`), así que el crudo de este
  vástago sería `CV18` y **no existe, porque no se fabrica: se compra terminado a Bella Vista**. La
  `C` de `V18C` era una variante de familia, como la `D` de `V18D` (Tornillo Sacafuente). Sacarla
  deja el maestro parejo (`V18` comprado, `V18D` fabricado) y no pisa nada: `V18` estaba libre.
- **Queda en Sector Remache (8), no pasa a Procesado**: el insumo vive donde el usuario lo cuenta y
  lo pide (mismo criterio que los aceites de Dilmax, que tampoco son remaches y viven ahí). "Sería
  el procesado" describe **que se compra terminado**, no una mudanza de sector.

**⚠ EL HALLAZGO DE PLATA: el vástago es la línea MÁS CARA de los tres artículos y GP2 la tiene en
$0.** `[dato, medido contra la planilla del propio dueño]` `v_planilla_costo` de los códigos 121 y
315 trae `remaches = 448,5373` tomado de `'Lista de Precios '!L171` — la fila 171 del bloque 890
Bella Vista, *"Remache Pisapapas 8 x 97"*, cod ISIS 0885, lista 2026-07-08. **Es por unidad, no por
kilo**: la planilla lo suma tal cual a un costo de artículo de $1.025,59, y GP2 hoy cierra el 315 en
$561,26 justamente porque el vástago entra en cero. Dos cosas lo mantienen en cero y hay que
arreglar las dos: `estado_compra='discontinuo'` (herencia de la decisión del 2026-08-31 *"el remache
de aluminio no va más"*, que **la planilla vigente desmiente**) y **cero filas en
`precio_proveedor`**. Las dos se arreglaron el mismo día con el "sí" del dueño.

**EJECUTADO el 2026-09-23** (`db/migracion_m1_desaparece.sql`, bloques A y B), con este efecto
medido en `v_costo_componente`:

| | Antes | Después |
|---|---|---|
| 315 | $561,26 | **$1.009,79** |
| 609 | $500,00 | **$948,53** |
| 121 | $397,49 | **$846,02** |
| `V18` | $0,00 (origen `ruta`) | **$448,54** (origen `precio`) |

La planilla pone el 315 en $1.025,59, o sea que quedan **$15,80** de diferencia — y encima GP2 usa
el tallerista de Pettofrezza ($140) donde la planilla usa el de Cavallero ($85), así que el resto
tendría que dar $55 MENOS que la planilla. Hay ~$71 repartidos en otras líneas sin perseguir.
`db/verificar.sql`: invariantes de modelo en 0. La única regla > 0 quedó en
`AE_paso_virgilio_y_codigo_dan_distinto = 2`, y **es ajena a esto**: los artículos **567 "Corta
Palta"** y **537 "Pela y Pica Ajo"** tienen componente terminado en el sector 12 pero **0 rutas y 0
receta** — están creados y sin cargar.

**Lo que se hizo además del cambio en sí, y por qué:**
1. **Se creó la fila de `inventario` del `M2` en la ubicación de Pettofrezza (31)**, que no existía
   (sólo estaba en Sector Procesado). `recalcular_maximos_talleristas` **sólo actualiza filas que
   existen, no las crea**: sin esa fila el Envío a Talleristas no le podía poner máximo ni sugerido
   al disco calado, que es justo la pieza que ahora se le manda. Después del recálculo, el `M2` y el
   `V18` quedaron los dos en **máximo 5.078** (`est_madre_x_reparto`) en la ubicación de Rafael.
2. **Se borraron las filas huérfanas de Cavallero German** (`M1` y `V18C` en la ubicación 24, las
   dos en 0, de cuando hacía el 121).

**Lo único que sigue faltando: Pettofrezza no tiene precio para el 121** (el $85 era de Cavallero,
que quedó sin rutas). El 315 y el 609 tienen $140 "AyE". Con el `M1` afuera el trabajo de Rafael es
**un solo paso**, así que el "AyE" ya cubre poner el vástago en el disco — deja de tener sentido la
pregunta del 2026-09-22 sobre si el disco con vástago se cobraba aparte. **Ojo con el semáforo**: el
121 quedó con `faltan_precios = 0` y `servicios_pesos = 0,00` al mismo tiempo, o sea que **un
servicio de tallerista sin precio NO se denuncia como faltante** (el 609 sí marca 1, por otra
pieza). No confiarse de ese contador para saber si un armado se está cobrando.

**Y a Pettofrezza NO se le recibe más nada — eso está bien y no necesita código**
`[usuario 2026-09-23: "Ya no recibiríamos más del tallerista Pettofrezza Rafael", con la pantalla a
la vista: Recibir → Pettofrezza mostraba UNA tarjeta, el `M1`, en 0 y "sin cargar"]`. La rama de
talleristas de `rec` en `GP2.tablet_bundle` lista las salidas del tallerista **salvo las del sector
12 (Terminado)**, porque un terminado no vuelve a Cervantes: se entrega en Virgilio. Los 15
terminados de Rafael ya estaban afuera por eso, así que el `M1` era **lo único** que quedaba — y era
un intermedio que él se hacía a sí mismo. Al irse, su `n_rec` queda en 0 y **la propia pantalla lo
saca del selector de Recibir** (`cpsDelModo()` filtra por `n_rec > 0`). Cero líneas de JS: el día
que un tallerista vuelva a devolver una pieza que no es terminado, reaparece solo.

## 4fm. El 280 vuelve a Gentile Norberto (2026-09-23)

`[usuario, textual]`: *"Quiero que el artículo 280 lo devuelvas a gentile norberto. Sacaselo a blist
pack"*. Revierte el movimiento del 2026-09-22 (§4fb), que lo había pasado de Fábrica a Blist-Pack.

**Lo que se tocó: cuatro pasos y nada más.** El 280 tiene una ruta por pieza que entra, y en las
cuatro el paso de tallerista pasó de Blist-Pack SA (14) a **Gentile Norberto (8)**: `ruta_paso`
3067 (PV14), 3070 (BOM8B), 3073 (F1A) y 3076 (A2, Caja N°12).

**Medido antes y después:**

| | Antes | Después |
|---|---|---|
| Consumo de Gentile | 7.186 uni/mes | **15.341** |
| Consumo de Blist-Pack | 10.628 uni/mes | **2.473** |
| Piezas que recibe Gentile | 17 | **21** |

A Blist-Pack le quedan el **555** y el **764** (los cepillos limpia bombilla), así que no queda
vacío. **No tenía ni una fila de inventario ni un movimiento**, o sea que no quedó stock colgado en
su poder.

**Dos cosas que el cambio NO arregla y conviene saber:**
1. **El 280 sigue sin precio de tallerista.** Ni Blist-Pack ni Gentile lo tienen cargado, así que
   ese armado no se cobra en el costeo del artículo — antes tampoco. El precio del tallerista viaja
   con la pieza que entrega (§4dv), así que el día que se cargue va sobre el componente 280.
2. **Gentile no tiene fila de inventario para las cuatro piezas** (PV14 6.416 uni/mes, F1A 1.604,
   A2 134, BOM8B 2). Sin fila no hay máximo guardado; el sugerido de la Tablet igual sale, porque
   se calcula al vuelo. Alinear los máximos es `recalcular_maximos_talleristas()`, que es otra
   escritura y la autoriza el dueño.

## 4fn. El 498 tiene su propio crudo: nace `I9` "Destapador Pie p/cromar" (2026-09-23)

`[usuario, textual]`: *"Ahora, luego de la matriz 27, va a parar al sector crudo I9: 'Destapador Pie
p/cromar', no I1"*, con su **sí** sobre el SQL exacto, en GP2 y en el vecino.

**No era un renombre: `I9` no existía en ningún lado.** Lo que pasó es que **`I1` se partió en dos**.
Hasta hoy la matriz 27 (Corte Cuerpo Uña Pie, sobre el Fleje 29 / `IA5`) sacaba un único crudo,
`I1` "Destapador Pie p/pintar", y la bifurcación ocurría recién en el proveedor de servicio:
`I1` → **Jade** (pintado) → `B12` para el **499**, e `I1` → **Pedernera** (cromado) → `Z45` para el
**498**. Ahora cada rama tiene su crudo: **`I1` se queda con el 499** (sigue igual, no se tocó ni un
paso suyo) y **`I9` se lleva el 498**.

| | Antes | Después |
|---|---|---|
| Ruta 101 (498), paso 2 matriz 27 | sale `I1` | sale **`I9`** |
| Ruta 101 (498), paso 3 Pedernera | entra `I1` | entra **`I9`** |
| Ruta 100 (499) | `I1` → Jade → `B12` | **sin cambios** |

**Lo que se escribió, y nada más que eso.** En GP2: `componente` **936** `I9` (Sector Crudo,
unidad, 0,02863 kg/uni, 1048 uni/cajón), dos filas de `inventario` en 0 (Sector Crudo con máximo
**5.240** = 5 cajones, y Pedernera / Carlos Aguirre), los `ruta_paso` **661** y **662**, y el borrado
de la fila de inventario de `I1` en Pedernera (id 500, en 0 y ya sin ruta que la justifique). En
`public`: alta en `SC Kg` (cod_verificacion 100130), una fila nueva en `Causa-Efecto`
(27 · Fleje 29 · `I9`, la de `I1` **queda** porque es el 499) y `Partes x PS` id 313 pasa a `SC='I9'`.

**El peso de `I9` es el de `I1`** (0,02863 kg/uni, 30 kg/cajón): es la misma estampada del mismo
fleje con la misma matriz. `[usuario confirmó el 2026-09-23]`.

**El costo no se movió, medido antes y después**: `I9` $145,51 (idéntico a `I1`), `Z45` $213,85 y
el 498 terminado **$431,35**, sin faltantes de precio, kg ni tiempos. Era lo esperado: Pedernera
cobra por la pieza que **devuelve** ($2.293,15/kg sobre `Z45`), no por la que recibe.

**Dos cosas del vecino que conviene tener anotadas:**
1. **`v_produccion_por_sector` le va a asignar a `I9` TODA la producción de la matriz 27**, igual
   que ya hacía con `I1` y `J13`: esa vista reparte el total de la matriz a cada fila `Aumenta`, sin
   prorratear. Es un defecto viejo del vecino, no de este cambio; ahora son tres filas en vez de dos.
2. **Insertar en `SC Kg` dispara `trg_pesos_sc`**, que llama a `actualizar_partes_tallerista()`,
   `actualizar_despiece()` y `actualizar_partes_ps()` — recálculo **global** de las tres derivadas.
   Los pesos de la fila de Pedernera no se movieron porque `actualizar_partes_ps` resuelve por el
   **SP** (`Z45`) y sólo cae al SC si no hay SP.

**Lo que NO hizo falta tocar, y por qué:** la receta del 498 (`articulo_componente`) pide `Z45`, no
el crudo — receta y ruta no se usan para lo mismo (§4cc); `Despiece x Articulo` y
`Partes x Tallerista` del vecino tampoco nombran el crudo (Garcia recibe `Z45`); el precio de
cromado cuelga del componente de salida; y `parte_proveedor_servicio` (los pintores de una pieza)
sigue con `I1` → Daniel/Jade, que es exactamente la rama que `I1` conserva.

**La entrega histórica de `I1` cromado en `Entregas PS` (1 fila) quedó como estaba**: la historia no
se reescribe.

## 4fo. La plancha de níquel se compra y se controla en kg — y la tolerancia del control es UNA sola, 5 % (2026-09-23)

**Lo que pidió el dueño, textual:** *"Ya vimos todo lo que es recepcion de ps y talleristas.
Insumos esta bastante modelado ya pero vamos a modificar a algunos proveedores. CC galvanoquimica.
plancha niquel en el remito viene en kg y se controla en kg"* y, enseguida, *"acordate de la regla
de que todo control no puede exceder el 5% de diferencia"*.

### El toggle no era el problema: la pieza no podía recibirse en kg

`PCP2` (Plancha de Níquel, CC Galvanoquímica, Sector Plástico) estaba declarada en **unidades** y
**sin `kg_x_uni`**. Con eso, elegir "Kg" en el popup de Recepción reventaba en el RPC
(`to_canonical: componente 612 sin kg_x_uni valido para kg->uni`): **en kg no se podía recibir**.
Nadie lo había notado porque la pieza tiene stock 0 y ni un movimiento.

Como el remito y el control son los dos en kg —nadie cuenta planchas—, la unidad canónica tiene
que ser el kg. **`PCP2` pasa a `unidad_medida='kg'`**, que es como ya viven 61 componentes (47
flejes, 13 bolsas plásticas, 1 alambre), más `remito_unidad='kg'`. Al no tener receta, ni
movimientos, ni recepciones, no hubo nada que convertir.

### `componente.remito_unidad` ahora también manda en la Recepción de Insumos

- **Metalúrgica Giser se recibe en KG** [usuario 2026-09-28: *"Metalúrgica Giser se recepciona en kg"*]. Su única pieza, **BOM12** (Caño Inox 140 mm, bombillas, `kg_x_uni` 0,0095), quedó con `remito_unidad='kg'`: la Recepción pide *Cantidad kg* y `to_canonical` lo pasa a unidades al guardar (1,9 kg = 200 uni) [dato]. Si Giser suma piezas, cada una lleva el mismo `remito_unidad`.
- **Cimarron se recibe en UNIDADES** [usuario 2026-09-28: *"Los remitos de Cimarron son en unidades"*]. Sus 10 piezas (GRJ4, GRJ5, GRJ6, GRJ18, GRJ19, GRJ21, GRJ25, GRJ26, GRJ27, GRJ30) quedaron con `remito_unidad='uni'` [dato]. 7 no tienen `kg_x_uni`: en el control se cuentan, no se pesan.
- **Eduardo Pintos y Gilardi Esther se reciben en UNIDADES** [usuario 2026-09-28: *"El remito de Pintos y Gilardi es en unidades"*]. `remito_unidad='uni'` en GRJ12, GRJ12B, PEP5 (Pintos) y GRJ13, GRJ14, GRJ28 (Gilardi) [dato]. Los GRJ de Pintos están en Garage, fuera del alcance de `PLAST_UNI` (que sólo cubre Plásticos): por eso hacía falta la bandera en la pieza. GRJ12 y GRJ12B no tienen `kg_x_uni`.
- **Tierra Nativa SA se recibe en UNIDADES** [usuario 2026-09-28: *"El remito de tierra nativa tambien es en unidades"*]. `remito_unidad='uni'` en GRJ17, GRJ22, GRJ23, GRJ24 (palos de amasar) [dato]. Ninguno tiene `kg_x_uni`: en el control se cuentan.
- **Las bolsas plásticas se reciben en KG, todas** [usuario 2026-09-28: *"Todo lo que es bolsas plásticas el remito es en kg"*]. `remito_unidad='kg'` en las 13 piezas de Sector Bolsas Plásticas (Arcolor, Beta Plásticos, Indarnyl, Julio Garcia e Hijos, Santa Rosa Plásticos, Simco) [dato]. Su `unidad_medida` ya era kg y no tienen `kg_x_uni`: no hay conversión, se guarda lo pesado. Una bolsa nueva de ese sector tiene que nacer con `remito_unidad='kg'`.
- **El control después de la recepción es en KG para Garage, Bolsas Plásticas e Importado** [usuario 2026-09-28: *"Todos los proveedores que te di en este chat, el control luego de la recepción es en kg"* + Importado: *"Remito en unidades y control en kg"*]. Hasta hoy esos rubros no tenían control: `CONTROL_URL` de la Recepción sólo mandaba 6, 7, 8 y 11. Se sumaron 9 (Garage) y 14 (Bolsas) a `control-remaches.html?sector=N`, e Importado **por proveedor** (`CONTROL_URL_PROV`, `?sector=2&prov=Importado`) porque el Sector Procesado lo comparte con Eclipse/Charcas, que tienen su propio pesaje. Importado: `remito_unidad='uni'` en D1, E13, Z23A, Z23B, PINCEL590; C13 sigue en `'envase'` [dato]. Una pieza con remito en uni y SIN `kg_x_uni` no se puede controlar en kg: la pantalla pide contarla. Faltan pesos en GRJ12, GRJ12B, GRJ17, GRJ18, GRJ21-GRJ27, GRJ30 y PINCEL590.
- **GRJ19 (Bombilla Plana Ancha, Cimarron): `kg_x_uni` = 0,0667** [usuario 2026-09-28]. Vienen 720 uni por envase y el envase pesa 48 kg (48 / 720 = 0,0667). Primero dijo 0,05 y se corrigió: el 0,05 no cerraba con los 48 kg.
- **"Rueda" pasó a llamarse "Rueda y CIA"** [usuario 2026-09-28]: `proveedor_insumo` id 26; las FK `ON UPDATE CASCADE` arrastraron el nombre a `componente` (BOM8B).

Es la misma columna que la Tablet usa para las entregas de talleristas (§4fi). Si la pieza dice
`'kg'` o `'uni'`, la Recepción fuerza esa unidad y **esconde el toggle Kg/Unidades**: no hay nada
que elegir. La rama va **primera** en el if-chain de `abrirPopup()`, antes que la regla del rubro
(cartones, cajas, flejes) y que la del proveedor (`PLAST_UNI`), porque es el dato más específico
que hay. `recepcion_bundle` manda la columna con cada insumo.

**Ojo con la conversión silenciosa:** cuando la pieza tiene `kg_x_uni` y no está en `PLAST_UNI`, la
pantalla venía multiplicando lo tipeado en unidades por el peso y **guardando kg**. Decir "este
remito viene contado" y guardarlo en kg es lo mismo que no decirlo, así que `remito_unidad='uni'`
también apaga esa conversión.

### Una sola tolerancia de control: `parametro.tol_ctrl_pct` = 5

Hasta hoy la misma diferencia pasaba o no **según por qué puerta entrara la mercadería**:

| Control | Antes | Dónde estaba el número |
|---|---|---|
| Insumos por peso y cajas | 10 % | escrito a mano en `control-remaches.js` / `control-cajas.js` |
| Pesaje de pallets de fleje | 2 % | `parametro.tol_ctrl_peso_pct` |
| Entrega de P.S. / tallerista | 5 % | `tol_ctrl_ps_pct`, clave que **no existía** (caía al default) |

`tol_ctrl_peso_pct` se renombró **`tol_ctrl_pct`** y vale **5**. La leen `v_control_pallet`,
`recepcion_tara`, `control_entrega_bundle` y —nueva— `control_recepcion_bundle`, que la manda en
`tol_pct`. Los dos controles de insumos la muestran en el cartel ("tolerancia 5 %").
**El piso de 0,5 kg de `tolKg()` queda**: el 5 % de un remito chico son gramos y ninguna balanza
afina tanto.

### Quién declara su remito, al 2026-09-23

El dueño fue dictando proveedor por proveedor. Lo cargado, con su **sí** en cada caso:

| Pieza | Proveedor | Remito | Control | Por qué el control es ése |
|---|---|---|---|---|
| PCP2 Plancha de Níquel | CC Galvanoquímica | kg | kg | la pieza vive en kg: no hay conversión |
| PC4, PEP9 | JL Matricería | uni | kg | tienen `kg_x_uni`: se pesa y se guardan unidades |
| PEST1 Insertos Mango de Madera | Kollplast | uni | kg | idem |
| PCP4A Cintas Adhesivas 48x100 | Packaging y Servicios | uni | uni | **no tiene `kg_x_uni`**: no hay con qué pesar |

**Lo que el `remito_unidad='uni'` arregló en JL Matricería y Kollplast:** esas piezas tienen
`kg_x_uni` y su proveedor no está en `PLAST_UNI`, así que la pantalla venía multiplicando lo
tipeado y **guardando kg**. El toggle decía "Unidades" y la base se llevaba otra cosa. Ninguna de
las cuatro tenía recepciones cargadas, así que no hubo historia que migrar.

**⚠ Trampa para la próxima:** el control de `PCP4A` es en unidades **porque le falta el peso por
unidad**, no porque alguien lo haya decidido. El día que se le cargue un `kg_x_uni`, el control va
a pedir kg solo. Es la misma trampa anotada para los pliegos de AJ en §4fe: si una pieza tiene que
quedar contada para siempre, eso hay que decirlo con un dato, no dejando un campo vacío.
## 4fp. Quién entrega cada artículo, y que lo discontinuado NO se vea (2026-09-23)

Salió de cruzar los **talleristas finales por artículo de GP2** contra los de la O.C. de Gestión
Virgilio (`public."OC_Maximos"`). De los 195 códigos que existen en los dos sistemas, coincidían
160; el usuario resolvió las 35 diferencias de una y dictó estos cambios.

### Los dos nombres que estaban cruzados

| Virgilio | es, en GP2 |
|---|---|
| **"Carlos E" / "Carlos"** | **Alex Escalante** (tallerista 2) |
| **"Pedernera"** | **Carlos Aguirre** (tallerista 9) |

Medido: los 12 códigos de "Carlos" en `Articulos Virgilio X Tallerista` son los de Alex Escalante
(52 entregas, 1.827 cajas), y "Pedernera" entrega 115/544/560/802 — que entregaba
**`AGUIRRE CARLOS RODOLFO`** hasta el 04/06, justo antes de que Pedernera arranque el 10/06.

⚠ **Por eso el alias `CARLOS` → tallerista 9 de `GP2.contraparte_alias` está MAL**: manda las
entregas de "Carlos" al tallerista equivocado. **No se tocó** — corregirlo es escribir datos y lo
autoriza el dueño.

### Lo que se cambió (dictado por el usuario)

| artículo | queda |
|---|---|
| 338, 618, 070, 591, 761, 818 | **discontinuados** (los 6 con stock 0) |
| 709, 908 | Alex Escalante |
| 280 | Fábrica |
| 557, 558, 654, 658, 659, 758, 759, 762, 763, 769 | Blist-Pack SA (555 y 764 ya estaban) |
| 222, 910 | sólo Pintos (se borraron las 4 rutas de Maspoli) |
| 123 | Garcia + Lucho, 50/50 |
| 355, 789 | Pettofrezza + German, 50/50 |

⚠ **Gentile Norberto (Oscar) quedó con CERO artículos**: sus 11 son exactamente los que se
reasignaron. No se lo dio de baja — eso lo decide el dueño.

⚠ El 50/50 se carga con **`reparto_guardar`**, que **valida contra las rutas**: el segundo
tallerista tiene que hacer el paso, así que primero se duplica la ruta (una por tallerista, la
convención de la casa) y recién después se guarda el reparto. Y la RPC **recalcula los máximos de
todos los talleristas**, no sólo de los tocados.

### ⚠ `articulo.discontinuado = true` NO alcanza para ocultarlo

[usuario 2026-09-23: *"lo discontinuado no quiero seguir viéndolo en el programa"*]. **De los 27
objetos de GP2 que leen rutas o el catálogo de prov AT, sólo 6 miraban el flag.** Lo que hacía
falta, medido llamando a los bundles de verdad (no leyéndolos):

| dónde | qué se hizo |
|---|---|
| `articulo_prov_at.activo = false` | con eso solo ya salieron de Recepción, Envíos, OC, Orden de producción, Proporciones y Stock general |
| `despiece_verif_bundle` | filtro en el bloque `art` y en `rutas_full` (se ocultan sus rutas) |
| `preavisos_bundle` | filtro en las 3 ramas del CTE `z` |
| `Programa/Programa.html` | `llenarArticulos()` no los ofrece, y se fue el rótulo `(discontinuado)` de las 2 listas |
| `RecepcionVirgilio_GP2.html` | ya los filtraba (`.filter(x => !x.disc)`), no se tocó |

⚠ **`movimientos_bundle` y `programa_bundle` los siguen mandando TODOS con el flag `disc`, a
propósito**: el que decide qué se ve es la pantalla. No se les puso filtro.

⚠ **En el ABM de Artículos sí tienen que verse** — es donde se los des-discontinúa. No tocar.

⚠ **Un `"338"` dentro del JSON de un bundle no siempre es el artículo 338.** Buscando el código
como texto, `registro_operarios_bundle` daba positivo y era la **matriz 338 "Embolsar Bombilla"**,
y en `movimientos_bundle` varios eran `ruta_id`. Antes de dar por mostrado un código, mirar el
contexto de la clave.

## 4fq. El despiece de la Pinza Corta Alambre (560 / 800) — y las matrices sin ruta (2026-09-23)

**De dónde salió:** el dueño preguntó *"en qué despiece usás la matriz 131, 130, 129"*. Respuesta
medida: **en ninguno**. Las tres existían en `GP2.matriz`, activas y con producción real cargada
hasta abril/mayo 2026 (129: 14.504 uni · 130: 16.546 · 131: 17.614), pero **no figuraban en ningún
`ruta_paso`**.

**No es un agujero de esas tres:** al 2026-09-23, **299 de 405 matrices activas** no aparecen en
ninguna ruta GP2. La migración de rutas quedó a medias. [dato: `ruta_paso` vs `matriz`]

**La cadena real, dictada por el dueño** (y coincide con la del vecino en `public."Causa-Efecto"`):

```
IE6 (Fleje N° 79) → 131 Estampado Punta Pinzas → 130 Doblado Agarre Pinzas
                  → 129 Estampa Pinza chica   → 132 Estampado y Agujero Pinzas
                  → 133 Doblado Punta Pinza chica → 134 Remachado pinza Chica/Gde
                  → N7 → Guazzaroni Patricio → Carlos Aguirre → Virgilio
```

**Tres cosas que fija este caso y valen para cualquier ruta de matrices:**

1. **La pieza intermedia entre dos matrices vive en el Sector Movimiento** (`sector_id` 3,
   `ubicacion_id` 3), con código `<fleje>-M<matriz>` y descripción `"<fleje> tras M<matriz>"`
   (`IE6-M131`, `IE6-M130`, …), unidad `unidad`, sin `kg_x_uni`, y nace con stock 0. Es la
   convención que ya usaban `IA4-M64` e `IE6-M133`.
2. **Un paso que junta dos piezas se modela en `componente_bom`, no en la ruta.** `ruta_paso` tiene
   UNA entrada; el remachado toma dos. Entonces: `N7 = 2 × IE6-M133 + 1 × CV14`
   [usuario 2026-09-23: *"N7 sería dos componentes que salen de la matriz 133 … y un remache Cv14"*].
   Mismo patrón que `B1-M78` / `D5-M78` (rompenuez = las dos mitades + el remache `V4`).
3. **Un insumo que se consume en una matriz NO va también en la receta del artículo.**
   `v_consumo_demanda` explota `articulo_componente` **y después** `componente_bom` en cascada: si
   `CV14` queda en los dos lados, el remache consume 2 por pinza. Por eso salió de
   `articulo_componente` de 560 y 800, y se borraron las rutas 457/458 que se lo mandaban a Carlos
   Aguirre [usuario: *"se lo estás mandando a Carlos Aguirre y está mal. Lo consumís en esta matriz"*].

**Dos límites del motor de costos que este caso dejó a la vista** (medidos, NO arreglados):

- **`v_costo_componente` no multiplica por la cantidad.** Suma cada matriz una sola vez, así que el
  `×2` no se cobra: la mano de obra real de una pinza es 2 × 36,25 s (las cinco matrices por mitad)
  + 32 s del remachado = **104,50 s**, y la vista calcula **74,25 s**. Son **60,50 $/uni** que 560 y
  800 no están cobrando.
- **El BOM no se propaga hacia arriba.** `bomx` se aplica sólo en la fila del componente padre: el
  remache aparece en el costo de `N7` (material 0 → 4,45) pero **no** llega al artículo terminado,
  que bajó 4,45 (560: 674,36 → 669,91 · 800: 652,11 → 647,66). Antes tampoco estaba bien (entraba
  por `insumox` en 800 y no entraba en 560, que lo tenía como paso `ingreso`): el cambio hizo
  visible una inconsistencia que ya existía, no la creó.

**Sin resolver:** el vecino arranca esta cadena en **Fleje 82** y GP2 la arranca en **Fleje N° 79
(IE6)**. Uno de los dos está mal; `Fleje N° 82` ni siquiera existe como componente en GP2.
## 4fr. Talleristas O.C.: a Blist-Pack y Carlos Aguirre el trabajo se lo pide Gestión Virgilio (2026-09-23)

`[usuario, con la foto de la Tablet: "A blist pack sa y carlos aguirre quiero que me los saques
afuera de talleristas y me los pongas en un módulo nuevo de talleristas o.c."]` + `[usuario, al
preguntarle qué cambia además del lugar: "No es o.c. de insumos. Es orden de compra que se hace
desde Gestión Virgilio que hoy no está modelado acá. Por ahora sugerí 0"]` + `[usuario, sobre
dónde: "Solo en la versión tablet dentro del módulo enviar"]`.

**El dato de negocio nuevo:** hay talleristas a los que **no se les manda contra el máximo de la
casa**. Lo que tienen que hacer se lo pide una **orden de compra que emite Gestión Virgilio**, un
sistema que GP2 todavía **no lee**. Hoy son dos: **Carlos Aguirre (9)** y **Blist-Pack SA (14)**.
Mientras esa O.C. no se modele acá, GP2 **no tiene con qué calcular cuánto mandarles**, y por eso
su sugerido es **0** — no porque no haya que mandarles nada.

**NO se los sacó de `GP2.tallerista`, y ese es el punto.** Carlos Aguirre tiene **32 pasos** de
ruta con `tipo_paso='tallerista'` y Blist-Pack **38**: cambiarles el tipo volteaba rutas,
inventario, reparto y costeo. Lo que se separó es **la vitrina**:

| Dónde | Qué cambia |
|---|---|
| `GP2.tallerista.pedido_por_oc_virgilio` | flag nuevo, `false` por defecto; en `true` los dos de arriba |
| `tablet_bundle` | manda `oc` en cada contraparte, y el **techo** de esas filas es **0** (y con él el sugerido) |
| `Tablet_GP2.html`, **solo Enviar** | baldosa aparte **"🧾 Talleristas O.C."**; el título de la carga agrega "· O.C. Virgilio" |
| Recibir, y todo lo demás | **igual que antes**: siguen siendo talleristas comunes |

**El criterio del techo 0 no es nuevo**: es el mismo del **fasonero** (`proveedor_servicio.
pedido_por_oc`, Maspoli) cuando no hay O.C. enviada. La diferencia es de dónde viene la orden —
la del fasonero se emite **acá** (`GP2.orden_compra`) y el sugerido sube sola cuando sale; la de
estos dos se emite **afuera**, así que el 0 se queda hasta que alguien modele esa O.C.
**Cuando se modele, lo único que se cambia es ese `then 0` de la CTE `t` de `tablet_bundle`.**

⚠ **Por qué el título dice "· O.C. Virgilio"**: un sugerido en 0 sin explicación se lee como "no
hay que mandarle nada", que es lo contrario de lo que pasa. El rótulo es lo que separa "no
corresponde" de "no lo sé".

⚠ **Cómo se parte una baldosa en la Tablet** (por si aparece otro corte así): `TIPOS` acepta
`clave` (el `data-tipo` del botón, para que dos baldosas del mismo tipo no compartan selector) y
`oc` (el lado del flag). Una baldosa **sin** `oc` no filtra nada — por eso Recibir quedó intacto.
`selTipo` pasó a guardar **la baldosa entera**: con dos baldosas `tallerista`, el string del tipo
ya no alcanza para volver.

**Lo que NO se tocó y sigue pendiente:** nada en `Talleristas/` (Envíos, Recepción, Control,
Proporciones) los separa — ahí los dos siguen mezclados con el resto, que es lo que el usuario
pidió por ahora. Y GP2 sigue **sin leer** la O.C. de Gestión Virgilio: ése es el hueco real.
## 4fs. Los bujes mariposa pasan de Pat Bet a Kollplast (2026-09-23)

`[usuario, textual]`: *"Los dos bujes mariposa ahora se los compramos a Kollplast. Remito en uni
control en kg"*, con su **sí** sobre el SQL exacto.

**Qué se movió** (`PA8A` Buje Blanco 237 y `PA8B` Buje Negro 226, los dos del Sector Plástico, que
entran en los artículos **066 / 502 / 512**, los abrelatas mariposa):

| | Antes | Después |
|---|---|---|
| `componente.proveedor` | Pat Bet Plast | **Kollplast** |
| Precio que toma el costo | $21,06 (lista Pat Bet, 01-08-26) | **$20,48** (lista Kollplast, 19-08-26) |
| Costo del buje | $21,06 | **$20,48** (−2,8 %) |
| Recepción | remito en uni (Pat Bet ya estaba en `PLAST_UNI`) | **igual**, ahora por Kollplast |

**La fila vieja de Pat Bet en `precio_proveedor` NO se borró, y no hace falta borrarla**: la vista
`v_costo_componente` ordena `DISTINCT ON (componente_id)` poniendo **primero la fila cuyo `cod_prov`
coincide con el `cod_prov` del proveedor asignado al componente** y recién después por `fecha_lista`.
Con Kollplast (4465) cargado, la de Pat Bet (797) queda de histórico y no gana nunca. **Corolario
para la próxima vez que cambie un proveedor: cambiar `componente.proveedor` sin cargar la fila de
precio del proveedor nuevo deja el costo con el precio del viejo, sin ningún aviso** — `faltan_precios`
sigue en 0 porque precio hay, sólo que es el de otro.

**Esto cierra la trampa anotada en §"Kollplast vs Pat Bet, misma pieza, otro precio"** (2026-08-31):
ahí quedó registrado que Kollplast cotizaba el buje a $20,48 contra $21,06 de Pat Bet y que "todo
quedó cargado con Pat Bet, revisar al repartir los inyectores". El buje ya está repartido; **el
Pirolo sigue pendiente** (`PA7A`/`PA7B`: Kollplast $51,76 vs Pat Bet $20,07, ×2,5 — ahí el barato es
Pat Bet).

**Sin ripple de stock**: los dos bujes estaban en **0** y no había ninguna OC abierta.

**"Remito en uni, control en kg" se dice en la BASE, no en el código**: `componente.remito_unidad
= 'uni'` en los dos bujes, la columna que estrenó la §4fo unas horas antes. Con eso la Recepción
fuerza unidades, esconde el toggle y **apaga la conversión silenciosa** (sin la bandera, una pieza
con `kg_x_uni` cuyo proveedor no está en `PLAST_UNI` se tipea en unidades y se guarda en kg).
El control sigue pidiendo los kg de la balanza y dividiendo por `kg_x_uni`, que es lo que el dueño
pidió. **`PEST1`, la otra pieza de Kollplast, ya tenía su bandera** puesta el mismo día.

**Lo que NO se hizo, y por qué importa `[deducido, decidido en el merge]`:** la primera versión de
este cambio agregaba `'kollplast'` a `PLAST_UNI`, la lista de proveedores hardcodeada en el JS.
Funcionaba, pero **habría dejado dos formas de decir lo mismo** en la misma pantalla, y por ser
**por proveedor** se habría llevado puesta cualquier pieza futura de Kollplast sin que nadie lo
decida. `PLAST_UNI` es el mecanismo viejo y va último en el if-chain; **lo nuevo que se agregue va
por `remito_unidad`**. La lista queda sólo por los tres proveedores que ya dependen de ella.

---

## 4ft. La cremallera no es un fleje: `IE13` → `E13`, Sector Procesado, por unidad (2026-09-23)

`[usuario, textual: "La cremallera IE13. Es E13 y está dentro de sector procesado. No fleje. Lo vi
en pettofrezza rafael"]`, con su **"Sí"** sobre el SQL exacto.

**Era un renombre en apariencia y un agujero de plata en los hechos: mientras la cremallera estuvo
en el Sector Fleje, costó $0 en los dos sacacorchos que la llevan.**

### Por qué costaba cero

`v_costo_componente` tiene una rama especial para el sector 5: `precio × kg_ref`, donde `kg_ref`
es el `kg_x_uni` del componente **fabricado** — o sea, el fleje se cobra por el peso de la pieza
que sale. Correcto para un fleje, que se compra por kilo. Pero:

- La cremallera **se importa armada y se paga por unidad**: USD 1,10 c/u = **$1.688,50**
  (planilla del dueño, fila 885, `cod_isis` 523C, Tierra Nativa SA, rubro Talleristas).
- El "523 Terminado" **no tiene `kg_x_uni`** → `kg_ref` NULL → el producto daba NULL → la suma lo
  ignoraba. El semáforo lo venía diciendo: los dos artículos estaban con **`faltan_kg = 1`**.

⚠ **`precio_proveedor.precio_por_kg` no sirve para distinguirlo**: los **48** flejes con precio lo
tienen en `false`, cobren por kilo o no. El que avisa es el texto de `producto` (acá decía
"importada, **por unidad**") y, sobre todo, el rubro de la planilla.

### El origen: la migración del 2026-09-03 la metió en la bolsa equivocada

La idea 7221 pasó `IC3`, `IE13` e `IZ19A` de `unidad` a `kg` porque eran "los 3 únicos flejes que no
estaban en kg". Para `IC3` (alambre galvanizado de Altrak, USD 1,715 **el kilo**) fue el arreglo
correcto. Para la cremallera fue al revés: **no era un fleje mal cargado, era una pieza procesada
mal clasificada**, y la migración le puso la receta en `0,0602 kg` donde decía `1 unidad`.
Aquella sesión verificó que "no cambió el costo de ningún componente" — cierto, pero porque ya
valía $0 antes y después.

### Lo que se escribió (4 UPDATE, con snapshot previo de los 803 costos)

| tabla | cambio |
|---|---|
| `componente` (219) | `codigo` IE13 → **E13**, `sector_id` 5 → **2**, `unidad_medida` kg → **unidad** |
| `articulo_componente` | arts **523** y **723**: cantidad 0,0602 → **1** |
| `ruta_paso` | rutas **339** y **416**, paso `insumo`: cantidad 0,0602 → **1** |
| `inventario` (213) | ubicación Sector Fleje → **Sector Procesado**; máximo 667,50 kg → **11.088 uni** |

El máximo vuelve exacto: los 667,50 kg salieron de multiplicar 11.088 uni × 0,0602 en la misma
migración del 03/09 (`maximo_origen='migrado_de_minimo'`, que sigue siendo cierto).
`kg_x_uni = 0,0602` **se queda**: es el peso real de la pieza (60,2 g — la planilla de Pedernera la
lista con `cod_art` "60.2"), y ahora es sólo peso, no unidad de cuenta.

### Costo medido, antes → después (sólo estos 2 de los 803 componentes se movieron)

| art | antes | después | Δ |
|---|---:|---:|---:|
| 523 Sacacorcho Doble Aleta | 1.304,96 | **2.993,46** | +1.688,50 (+129 %) |
| 723 Sacacorcho D. Aleta Nylon Reforzado | 1.262,12 | **2.950,62** | +1.688,50 (+134 %) |

`faltan_kg` pasó de 1 a **0** en los dos. Stock era **0** en las dos ubicaciones, así que no se
movió ni un peso de inventario y no hizo falta tocar `movimiento`.

### Lo que NO cambia

- **Sigue en Recepción → Importados.** Ese rubro se arma por `estado_compra='importado'`
  (`_es_comprable`: "pieza importada, viva donde viva"), nunca por el sector. Cero código tocado.
- Sale del **relevamiento de flejes** y del consumo en kg (`v_consumo_fleje_kg` sólo mira sector 5):
  ahora consume por unidades, que es como se pide.
- El máximo de Pettofrezza (inventario 746, 119, `est_madre_x_reparto`) **quedó como estaba** —
  viene de cuando el componente era kg. Recalcularlo es otra escritura, pendiente del sí del dueño.

### La regla que queda

**Antes de meter un componente en el Sector Fleje, preguntar si se compra por kilo.** El sector 5
no es "donde va el metal": es "lo que se paga por peso". Una pieza importada armada, aunque sea de
acero y aunque hoy entre por el mismo remito, va a su sector real o el costo se cae en silencio.

## 4fr. La mitad CERRADA del rompenueces nace: `G8` "Pieza Cerrada Rompenuez p/cromar" (2026-09-24)

`[usuario 2026-09-24, textual: "Después de la matriz 77 va al sector G8 que es Pieza Cerrada
Rompenuez p/cromar"]`, con su **"Sí a todo"** sobre crear el componente, redirigir la salida de la
M77 y mover el paso de cromado/pintado de la rama cerrada.

**El bug (dato, no código; venía pusheado):** en las rutas de **507** y **707** la **M74
"Estampado Rompenuez"** ya sacaba `G7` "Pieza Abierta Rompenuez p/cromar", y la **M77 "Aplastado
Punta Rompenuez"** —que es el CIERRE de la pieza— volvía a salir a **la misma `G7`**. O sea: la
mitad cerrada no tenía código propio antes del cromado, y el paso de servicio de la rama cerrada
(**Pedernera → `D6`** en el 507, **Jade → `B1`** en el 707) entraba por `G7`, la pieza abierta.
El trazado abierta/cerrada estaba pisado.

**Cruza con §4ce y con la M78:** §4ce dejó dicho que el rompenueces converge de verdad porque la
receta del 507/707 pide **las dos mitades a la vez**, y que la **M78** las junta devolviendo 4
salidas (`B1`/`B2`/`D5`/`D6`). Lo que faltaba era que esa separación abierta/cerrada existiera ya
**antes** del cromado: hasta ahora las dos mitades compartían `G7`. El barrido de §4ce miraba
**convergencias**, no esta **divergencia** aguas arriba, por eso no la había cazado. Ojo para el
futuro: un mismo `comp_salida_id` en dos matrices distintas de una misma ruta es sospechoso.

**Lo que se escribió (DB-only, manteniendo la normalización):**
- `GP2.componente` id **940**: `G8` "Pieza Cerrada Rompenuez p/cromar", clonando de `G7` (id 9)
  `sector_id`, `unidad_medida`, `kg_x_uni` 0,046166667 y `uni_x_cajon` 606 → **costo sin cambio**.
- `GP2.inventario`: una fila de `G8` en 0 (ubicación 1).
- `GP2.ruta_paso`: **M77** (pasos 284 del 507, 299 del 707) `comp_salida_id` `G7` → `G8`; y el
  paso de servicio de la rama **cerrada** (285 Pedernera→`D6` del 507, 300 Jade→`B1` del 707)
  `comp_entrada_id` `G7` → `G8`.

⚠ **Sólo se movió la rama CERRADA.** La abierta (M74 → `G7`; Pedernera→`D5` / Jade→`B2`) **queda
en `G7`**: mover los dos pasos de servicio a `G8`, como sugería la pregunta inicial en grueso,
habría roto la mitad abierta. Verificado con SELECT: 507 y 707 quedan M74→`G7`, M77→`G8`,
servicio-abierto←`G7`, servicio-cerrado←`G8`.

Auditoría `github_repo_problemas`: problema **538** registrado (categoría `datos`, severidad
`medio`) y cerrado con el commit de este cambio. DB-only: `db/` (respaldo de schema) no cambia,
sin bump de versión (no se tocó HTML/JS/CSS).

## 4fu. Una CONVERGENCIA descuenta TODAS sus entradas, no una sola (2026-09-24)

**Bug real que llegó al usuario** [Thomas, textual: *"todo lo que es convergencia, por lo menos
en matrices, me está descontando mal el despiece… si pongo a producir la matriz 10, varilla con
cuchilla para cromar, que es una convergencia entre I16 y H7, me descuenta solo de I16 y no de
H7… también con el ahueca papas: cuando voy a hacer N2 me descuenta solo de la flechita N3 y no
de la bochita N4 en la matriz 183"*].

**Convergencia** = una matriz que ARMA una salida a partir de **2+ entradas** (soldar, remachar,
armar): varilla+cuchilla → `H11`; flechita+bochita → `N2`. El motor tiene que descontar **todas**
las entradas y producir la salida **una** vez.

**Causa raíz — el motor tomaba UNA entrada.** `GP2.registrar_produccion` y
`GP2.registrar_evento_prod` resolvían `comp_entrada_id` con `... limit 1` e insertaban un solo
`movimiento` de `fabricacion`. Con 2+ entradas descontaba la primera y dejaba el resto. `ruta_paso`
tiene **una** entrada por paso (`comp_entrada_id` singular): una convergencia se modela como
**varios pasos con la misma matriz y misma salida**, cada uno con una entrada — igual que la
matriz 10 arma `H11` con `I16` (rutas del Fleje 2) **y** `H7` (rutas del Fleje 30). El motor
juntaba mal esos pasos.

**Fix del motor (DDL) — nuevo `GP2.fabricar_stock(mid, salida, uni, fecha)`.** Recorre TODAS las
entradas distintas de `(matriz, salida)` en `ruta_paso` (agrupadas, `qty = max(cantidad)`): la
**1ª** lleva la producción de la salida (`comp_transformado_id=salida`, `cantidad_transformada=uni`);
las demás son **consumo puro** (`cantidad_transformada=0` → +0 a la salida, −cant a la entrada).
`registrar_produccion` y `registrar_evento_prod` ahora la llaman en vez del `limit 1`. Medido en
matriz 10 (10 uni): `H7 −10`, `I16 −10`, `H11 +10`. En 183/`N2` (5 uni): `N3 −5`, `N4 −5`, `N2 +5`.

**Convergencias que arregla el motor (ambas entradas ya estaban cargadas):**
matriz **10** (`H11` ← `H7`+`I16`), **174** (`H15` ← `H7-M10`+`I16`), **151** (`Z36` ← `Z5`+`Z6`),
**78** (`B1-M78` ← `B1`+`B2`+`V4`; `D5-M78` ← `D5`+`D6`+`V4`), **135** (`G4` ← `K5`+`K8`+`V3`).

**Fix de datos — la ahueca estaba en TRES matrices** [Thomas: "183 es el paso único → unifico"].
El mismo soldado físico (flechita + bochita) tenía dos números de matriz porque las dos piezas
vienen de flejes distintos: **Fleje 59** → flechita `N3` soldaba en **183**; **Fleje 61** → bochita
`N4` (papa) / `N5` (fruta) soldaba en **363** / **362**. Se repuntó el paso de soldado del lado
bochita (rutas 177/178/179/180) de 362/363 a **183**, y 362/363 quedaron `activa=false`. Resultado:
**183** → `N2` ← `N3`+`N4` (ahuecapapa = flechita + bochita papa), `N1` ← `N3`+`N5` (ahuecafruta =
flechita + bochita fruta). Componentes: `N3` Flechita Ahueca Cruda, `N4` Bochita Ahuecapapa,
`N5` Bochita Ahuecafruta.

⚠ **Regla que queda:** una convergencia se carga como varios `ruta_paso` con la MISMA matriz y
misma `comp_salida_id`, una por entrada. Si el mismo armado aparece con números de matriz
distintos según de qué fleje viene cada pieza, es el mismo bug de la ahueca: unificar en una sola
matriz.

**Sospechosos NO tocados (posible misma clase, matriz de unión con una sola entrada):** **194**
Remachado Pala Canelones (`E6`→`E6-M194`) y **134** Remachado pinza (`IE6-M133`→`N7`) — a revisar
si les falta el remache como 2ª entrada.

`db/funciones_GP2.sql` actualizado (las 3 funciones). El repunteo de `ruta_paso` es dato (no va a
`db/`). Sin bump de versión (no se tocó HTML/JS/CSS). Auditoría `github_repo_problemas`: problema
**539** *"Convergencia de matriz: al producir se descuenta solo una entrada del despiece"*
(categoría `bug`, severidad `alto`) registrado y cerrado con el commit de este cambio.

### 4fu (bis). El motor de fabricación lee la RECETA (`componente_bom`), no `ruta_paso` (2026-09-24)

Ampliación del mismo día. Revisando pinza (134) y pala (194) con Thomas apareció que **la receta
real de cada convergencia vive en `componente_bom`, no en `ruta_paso`** — y es más completa:
`ruta_paso` tiene UNA entrada por paso, así que el remache o el vástago que se suman en la
soldadura/remachado quedan sólo en el BOM. (La lectura anterior de que "el BOM estaba vacío" fue un
error de una consulta multi-statement que se comió el resultado: **todas** las convergencias tienen
BOM.)

**`GP2.fabricar_stock` pasó a BOM-first:** si la salida tiene `componente_bom`, descuenta esa
receta (hijo × cantidad); si no, cae a las entradas de `ruta_paso` (transformación simple). Coincide
con cómo `v_costo_componente` costea el intermedio (que también arranca del BOM/ruta). La 1ª línea
lleva la producción de la salida, las demás son consumo puro.

Casos verificados (10 uni cada uno, filas de prueba borradas):
- **Pinza N7 (134):** el remache **CV14** estaba en el BOM (`2× IE6-M133 + 1× CV14`) pero no en
  `ruta_paso` → ahora descuenta IE6-M133 −20 y CV14 −10. La receta de 560/800 ya referenciaba `N7`,
  no las piezas sueltas: sin doble.
- **Pala E6-M194 (194):** era una convergencia **no modelada como tal** [Thomas: "E6-M194 tiene los
  tres: pala E6 + vástago F2 + 2 remaches V10; al artículo se le manda E6-M194, no las partes
  sueltas"]. Se creó `componente_bom(E6-M194) = E6×1 + F2×1 + V10×2` y se **alineó la receta** del
  570/858: se sacaron `E6/F2/V10` sueltos y se puso `E6-M194 ×1` (antes el route armaba E6-M194 que
  nadie consumía y E6 se descontaba dos veces). Ahora producir E6-M194 descuenta E6 −10, F2 −10,
  V10 −20.
- **H15 (174):** su `componente_bom` apuntaba a `H7` (varilla recta); la varilla **curva** usa
  `H7-M10`. Corregido el BOM. (El costo no se movió: ya salía por la ruta, que tenía `H7-M10`.)

**Costo:** neutro. `v_costo_componente` costea el terminado **por la ruta** (recorre `ruta_paso`
hasta los comprados) + insumos del BOM (`bomx`, sólo sectores `es_insumo`), **no** por
`articulo_componente`; por eso 570/858 no se movieron (708,04 / 865,24) al cambiar la receta.
E6-M194 subió 203→240,82 (sumó los 2 remaches vía `bomx`). ⚠ El **vástago F2** (sector 2, no
insumo) **sigue sin propagarse** al costo del terminado: es la limitación pre-existente ya anotada
en 4fq ("bomx no se propaga hacia arriba"), no la introdujo este cambio.

**Regla:** una convergencia se carga en `componente_bom` del intermedio (con cantidades), y al
artículo se le pone el intermedio, no las piezas sueltas. Así el descuento de producción y la
entrega no cuentan lo mismo dos veces (`recepcion_virgilio` descuenta `articulo_componente` sin
explotar BOM; el tallerista sí explota BOM de la parte).

**151 resuelto** [Thomas: "el remachado saca fuente se hace con el remache saca fuente V6"]: el
`componente_bom(Z36)` pasó de `Z5+Z6` a `Z5+Z6+V6×1` ("Rem Sacafuente", sector 8). Z36 (sacafuente
pizzero) se usa en el **art 518** (Fleje 6→Z6 y Fleje 8→Z5, convergen en M151→Z36→Pedernera→Lucho);
la receta de 518 **no** listaba V6, así que no hay doble. V6 sigue suelto en 508/708, que son el
sacafuente **articulado** (Z1A), otro producto — ahí no se toca. Verificado: producir Z36 en 151
descuenta Z5 −10, Z6 −10, V6 −10. `db/funciones_GP2.sql` con `fabricar_stock` BOM-first; los BOM de
E6-M194, H15 y Z36 y la receta 570/858 son datos. Auditoría 539: `agregar_commit` de esta ampliación.

## 4fv. Los artículos DISCONTINUADOS no aparecen en envío/recepción de talleristas (2026-09-24)

[Thomas, textual: *"te pongo como regla a todos los discontinuados acá, los de las rutas. Tanto
para enviar como para recepcionar. No tiene que aparecer más."*] Salió de un caso concreto: el
**"Corta Torta Chef"** (`PV8B`, parte del artículo **818 "Corta Torta" marca CHEF**,
`discontinuado=true`, consumo 0) seguía apareciendo en el envío a **Alex Escalante**.

**Por qué aparecía:** la pantalla de Envíos por Tallerista (y su gemela de Entregas/Recepción) NO
mira el consumo — arma la lista de partes desde `ruta_paso` (vía `talleristas_bundle`). Discontinuar
un artículo **no** borra su `ruta`/`ruta_paso`, así que sus componentes quedaban colgados. Es deuda
de datos, no un bug de pantalla.

**Fix (una sola función, cubre los dos lados):** `talleristas_bundle` dejó de leer el CTE `cfg`
desde `v_contraparte_parte` y lo reconstruye directo desde `ruta_paso` con
`join articulo a on … and not coalesce(a.discontinuado,false)`. Como el `group by` deduplica igual
que hacía la vista, **una parte que también vive en una ruta activa se conserva** (p.ej. la Caja
N°10, que es de 547 activo y de 818 discontinuado, se queda por el 547); sólo cae la que no tiene
ninguna ruta activa. `entrada` = lo que se le envía, `salida` = lo que recibe, así que un solo
filtro tapa "enviar" y "recepcionar".

Con el filtro se fueron exactamente 3 discontinuados que polucionaban en tallerista: **818** (Alex
Escalante), **070** "Set Tapers"/GRJ30 (Fábrica) y **311** (Martin Cornejo). Ninguna parte activa cayó.

### 4fv (bis). La regla vale para las CUATRO contrapartes y la Tablet (2026-09-24)

[Thomas, textual: *"la misma regla es para todos los envíos y recepciones, ya sea insumo, proveedor
de artículo terminado, proveedor de servicios, tallerista. Quiero que del programa no se pueda hacer
más nada con los componentes de ese artículo. Ahora, si los componentes se usan para otro artículo
activo, no los borres."*] El primer fix sólo tapó `talleristas_bundle`; el dueño seguía viendo `PV8B`
en la **Tablet** (que usa `tablet_bundle`, otra función).

**Concepto único — `GP2.v_componente_muerto` (vista, `db/vistas_GP2.sql`):** un componente está
*muerto* si pertenece a algún artículo **discontinuado** (por `ruta_paso` **o** `articulo_componente`)
y **no** pertenece a ningún artículo **activo** (ni por ruta ni por receta). Es una regla **derivada**:
cuando el dueño marca un artículo `discontinuado`, sus componentes exclusivos entran solos; los
compartidos con un activo **nunca** aparecen ahí (no se tocan). Hoy son **13** componentes de 8
artículos (070, 311, 338, 591, 618, 619, 761, 818): sus "X Terminado", los cartones exclusivos
(`O2D`/818, `F2C`/311, `K5B`/338) y `GRJ30` Set Tapers. Verificado que ninguno es hijo de un BOM vivo
ni intermedio, así que congelar el set no rompe nada.

**Dónde se aplica el filtro** (todos los bundles de envío/recepción/OC honran la vista o el flag de
artículo):

| Bundle | Pantalla | Cómo filtra |
|---|---|---|
| `talleristas_bundle` | Envío/Recepción tallerista (desktop) | ruta activa (fix original) |
| `tablet_bundle` | Tablet enviar/recibir (las 4) | `v_componente_muerto` en `env_x`/`rec_x` + `not a.discontinuado` en las ramas AT |
| `envios_ps_bundle` | Envío/Entrega PS | descarta pares con entrada/salida muerta |
| `envios_prov_at_bundle` | Envío Prov AT | catálogo sin muertos + `prov_insumos` sin artículos discontinuados |
| `entregas_prov_at_bundle` | Entrega Prov AT | lista y conteo sin artículos discontinuados |
| `recepcion_bundle` | Recepción de Insumos | insumos sin muertos |
| `oc_bundle` | Órdenes de Compra | no ofrece comprar muertos |

**Por qué AT filtra por artículo y el resto por componente:** el Prov AT es *article-driven* (cartones
de los artículos que arma), así que un cartón **compartido** (una caja) debe seguir para el artículo
activo pero no listarse bajo el discontinuado → se filtra `articulo.discontinuado` en la rama AT. Los
demás son *component-driven* (la parte tiene id propio), y ahí `v_componente_muerto` respeta lo
compartido solo. Medido después: 0 muertos en los 7 bundles, totales sanos (tablet 518 enviar / 161
recibir, OC 343, recepción 347) y la Caja N°10 sigue apareciendo. `cartones_para_reemplazo` y
`partes_por_ps` quedaron sin tocar (no son envío/recepción). Cambio pedido por el dueño → sin auditoría.

## 4fx. `uni_x_cajon` NO es "unidades por cajón": es cantidad por ENVASE (2026-09-24)

[Thomas, textual: *"que no sea uni por cajón, sino uni/kg por envase o algo genérico. Porque puede
ser uni por bolsa, uni por cajón"*.] La columna `GP2.componente.uni_x_cajon` es histórica y su
nombre miente: **el número es la cantidad que entra en el envase con el que se maneja esa pieza**, y
el envase cambia según el ítem. El nombre técnico **no se tocó** (está en 23 funciones + 2 vistas de
GP2 y 29 archivos del front, 184 usos: renombrar arrastra medio programa). En su lugar quedó un
`COMMENT ON COLUMN` que lo aclara en el editor de Supabase.

**Qué unidad es en cada caso:**
- **Plásticos (sector 6):** uni por **bolsa** — el inyector entrega en bolsas de N uni y la OC pide
  por bolsa entera (ya lo usaba así `uniPorBolsa()` de la OC). Es el caso general de la columna en
  plástico.
- **Sectores crudo/procesado/garage:** uni por **cajón** (el cajón de despacho), como el nombre.
- **Excepciones cargadas el 2026-09-24, que NO son bolsa ni cajón** (por eso van anotadas, para que
  nadie las lea como uni/cajón): `PCP2` Plancha de Níquel = **kg por plancha** (10); `PCP4A` Cintas
  Adhesivas 48×100 = **uni por caja** (36); `D9` Clavo 505 Niq. = **kg por caja** (15,6). ⚠ Cruce a
  confirmar: conviven `PCP3 "Clavo 505" = 4.594` (uni) y `D9 "Clavo 505 Niq." = 15,6` (kg/caja) —
  distinta unidad y distinto código, a validar con el dueño.

**Datos de uni/bolsa que faltaban en plástico, cargados el 2026-09-24** (salieron de la hoja "Pedido
VACIO" del Excel `Conteo_y_Pedido_Sector_Plastico`, columna "Uni x Bolsa"): PA17=1.000, PA3=1.000,
PC6=500, PEST1=2.000, PEST2=2.000, PIEA=1, PIEB=1, PV8=100, PV14=1.000, PV17=2.000. **Cerrados
después** [Thomas 2026-09-24]: `PINCEL590` Pincel Silicona = **600 uni/caja** (importado, `entrega_unidad='cajas'`,
NO bolsa); `PV8B` Corta Torta Chef queda **sin dato porque está discontinuado** (art 818 CHEF, ya no
aparece en envío por la regla de discontinuados).

**Carga previa del mismo día:** `C12` Paleta Batidor Resorte pasó de Sector Bombilla (mal) a
**Procesado** con kg_x_uni 0,03634 y uni_x_cajon 233; `C12B` (sin cromar) pasó a **Crudo** (peso y
uni/cajón todavía pendientes). `BOM10` Resorte Biconico (Sector Bombilla) = **400 uni/cajón** — acá
sí es cajón, el sugerido va en cajones.

**El envase del envío se define por PIEZA, no por pantalla (2026-09-24, implementado).** [Thomas:
*"para sector plástico estás usando cajones, quiero que uses bolsas"* + enfoque elegido: *"poblar
`entrega_unidad='bolsas'` en los plásticos + cablear el Envío Talleristas de escritorio"* + alcance:
*"también"* PS.] La verdad única es `componente.entrega_unidad` (+`entrega_uni_x`); si están en null,
se cae a `'cajones'` con factor `uni_x_cajon`. Se marcaron **63 plásticos con `entrega_unidad='bolsas'`**
(sector 6 con `uni_x_cajon`, EXCLUIDOS los que no son bolsa: clavos PCP3/D9, plancha PCP2, cinta PCP4A).
`entrega_uni_x` queda **null a propósito**: el factor cae a `uni_x_cajon`, así no se duplica el número
y la OC de bolsas (que lee `uni_x_cajon`) no se toca.
- **Tablet:** ya lo respetaba (`env_unidad`/`env_factor`), así que con el dato quedó sola.
- **Envío Talleristas escritorio:** `talleristas_bundle` ahora expone `entrega_unidad`/`entrega_uni_x`,
  y la pantalla rota la unidad por fila (helper `envase(x)`): columna "A Env.", el remito y el
  resumen dicen "bolsas" en plástico y "cajones" en el resto. Rótulos genéricos ("A Env." / "Cant.").
- **Envío PS escritorio:** NO se tocó porque **el plástico nunca entra a PS** (empareja crudo→procesado);
  su unidad la sigue dando el proveedor. Si algún día se rutea un plástico a un PS, se cablea igual.

**Otros `uni_x_cajon` en cajón cargados el 2026-09-24:** `BOM10` Resorte Biconico = 400 (Bombilla),
`W1B` Grampa Batidor = 24.615 (Remache). **`PIEA`/`PIEB` "Rueda Recta" van SUELTAS** [Thomas 2026-09-24]:
se les sacó el `entrega_unidad='bolsas'` y el `uni_x_cajon` (ambos null) — se cuentan por unidad, sin
envase.

**El cartón NO usa `uni_x_cajon`/`entrega_unidad`: su paquetón sale del FORMATO (2026-09-24).** En el
envío (Tablet/Prov AT), Sector Cartón (10) se rotula **"paquetes"** y el factor es
`carton_formato.uni_x_bolsa` (no el componente). `oc_bundle` **no** usa `uni_x_bolsa`, así que
cambiarlo es cost-neutral para la OC (la OC agrupa por múltiplos/categoría). Caso 2026-09-24 [Thomas]:
el formato **'Bolsa'** (packaging Vihal) estaba en null y lo compartían 5 ítems con **paquetón
distinto**: `BOLSA550`/`BOLSA760` van en **paquetes de 200** y los cartones `A1B`(031)/`A1B1`(120)/`G8C`(836)
en **7.500**. Como el paquetón es por formato, se **partió**: los 3 cartones pasaron a un formato nuevo
**'Bolsa Cartón'** (uni_x_bolsa=7.500, múltiplos y pedido mínimo copiados de 'Bolsa' tal cual) y 'Bolsa'
quedó en **200** para las dos bolsas. ⚠ El `pedido_minimo=20.000` heredado por 'Bolsa Cartón' es el de
la bolsa Vihal y queda **a confirmar** para cartones. (`carton_formato` es dato, no va a `db/`.)

## 4fy. Filtro y Precinto de Bombilla pasan a Sector Garage: `GRJ21A` / `GRJ21B` (2026-09-24)

[Thomas: *"el filtro para bombilla y el precinto para bombilla van a pasar a sector garage. El
filtro va a ser GRJ21A y el precinto GRJ21B"*.] Reclasificación de dos componentes que estaban en
Sector Bombilla (7): `BOM13` "Filtro p/Bombilla" → **`GRJ21A`** y `BOM14` "Precinto p/Bombilla" →
**`GRJ21B`**, ambos **sector 7 → 9 (Garage)**. Son partes de los artículos 90 "Filtro Para Bombillas"
y 105 "Filtro de Bombilla" (entrada y salida de las rutas 622/623/698/699) y los entregan Danica
García e IJUPA. **Stock 0 en todas las ubicaciones y 0 movimientos**, así que no hubo ripple: se movió
sólo la fila "casa" de inventario de la ubicación del sector Bombilla (7) a la del Garage (9); las
filas de los talleristas quedaron. **Cost-neutral** (GRJ21A 13,25 y GRJ21B 38,00 antes = después; son
fabricados por ruta, el sector no cambia su costeo). El código se referencia por `id` (no por string):
0 referencias a `BOM13`/`BOM14` en el repo, rutas y recetas intactas. DB-only, `db/` no cambia.

**Se compran a "4 Zurdos", sin descomposición** [Thomas 2026-09-24: *"está bien que no tenga
descomposición"* + corrección *"grj1a y grj1b se compran a 4 Zurdos"* (dijo primero Cimarrón y se
corrigió)]: `componente.proveedor='4 Zurdos'` en los dos. **"4 Zurdos" NO existía en `proveedor_insumo`**,
se dio de alta (activo, modo_control='ninguno', **`cod_prov` pendiente** — no lo dio). Ojo al insertar:
la secuencia del `id` estaba desfasada → hubo que poner el id explícito (`max(id)+1`). Cada uno ya tiene
su `precio_proveedor` (de ahí el costo 13,25 / 38,00) y `componente_bom` como padre = 0 (comprados, no
armados). No hace falta receta.

**Remito en unidades, control en kg; al tallerista se le manda en kg** [Thomas 2026-09-25: *"la recepción
de tablet insumos tendría que ser. Remito: unidades. Control: kg. Y al tallerista en la tablet envío a
talleristas se le manda en kg"*]. Hecho: `remito_unidad='uni'` en 550/551 (la Recepción de Insumos fuerza
unidades y esconde el toggle). **Falta el dato para que el resto ande solo** — hoy los dos tienen
`kg_x_uni` y `uni_x_cajon` en **null**: (1) sin `kg_x_uni` el control no puede pasar de kg a unidades y
queda pidiendo unidades (misma trampa que `PCP4A`); (2) el Enviar a tallerista ya carga en kg para todo
lo que no es cartón/caja (`env_carga='kg'`), pero exige un envase (`uni_x_cajon`) y `kg_x_uni`, si no
cae a unidades. **Peso cargado** [Thomas 2026-09-25]: `kg_x_uni` GRJ21A = 0,00015, GRJ21B = 0,000335 (costo intacto 13,25 / 38,00) → el control ya puede pedir kg. **Envase** `[usuario 2026-09-25: "Van 5400 uni x caja"]`: `entrega_unidad='cajas'`, `entrega_uni_x=5400` en los dos (caja de filtros = 0,81 kg; de precintos = 1,809 kg). El Enviar a tallerista los carga en kg y muestra cajas. Se usó `entrega_uni_x` y no `uni_x_cajon` (ése lo leen máximos/OC). Costo intacto.
`[dato]` La Lista de Precios de la planilla trae a 4 Zurdos como **cod. 4444** (cod ISIS 1897 "Prescintos
Omega" $38, 4966 "Filtro p/Bombilla s/Envasar" $13,25) — `[usuario 2026-09-25: "sí"]` cargado `proveedor_insumo.cod_prov='4444'` (costos 13,25/38,00 intactos).

### 4fz. IC3 / IC3V (Fleje N° 90 corto / largo): fleje que se CUENTA, en paquetes de 10 kg (2026-09-25)

- `[usuario 2026-09-25]` *"IC3 e IC3V vienen en paquetes de 10kg cada uno."* → `entrega_unidad='paquetes'`
  en los dos; `uni_x_cajon` = unidades por paquete: IC3 1.205 (10 / 0,0083), IC3V **746** (10 / 0,0134;
  antes decía 24, que daba un "cajón" de 0,32 kg).
- `[dato]` Son los **únicos 2 del sector Fleje (5) con `unidad_medida='unidad'`**; el resto se pesa.
  Por eso `tablet_bundle` ya no manda todo el sector 5 al consumo en kg: sólo el que es `kg`. Antes el
  sugerido a IJUPA daba 0 (commit `2737d21`). Hoy: IC3 15,66 paq., IC3V 1,47 paq. (1 mes de consumo).

### 4fz-bis. Flejes 31/32/33, Varillas B Pera Mini y Alambre Ganchito: al tallerista en PAQUETES / BOLSAS (2026-09-25)

`[usuario]` *"Los flejes 33, 31, 32 y los 2 de batidor pera mini (corto y largo) se manda en paquetes también.
fleje 33: 13.6kg por paquete. El resto 10kg por paquete"*. Son piezas en **kg**, así que el factor va en kg:
`entrega_unidad='paquetes'` + `entrega_uni_x` = **13,6** en `IE1` (Fleje N° 33) y **10** en `IE4` (N° 31),
`IE5` (N° 32), `IVBCM` (Varilla B Pera Corta Mini, N° 96) e `IVBLM` (Larga Mini, N° 95). Se usó
`entrega_uni_x` y **no** `uni_x_cajon` a propósito: `uni_x_cajon` lo leen 23 funciones (máximos, OC,
calculadora de cajones) y ese número es del envío, no del stock. Costo intacto.

**Corrección 2026-09-29** `[usuario]` *"Del batidor mini viene la varilla corta en diámetro 1.25 y 228mm de largo y
la larga 300mm de largo y diámetro 1.25. Ambas en paquetes de 2.5kg"*. → `IVBCM`/`IVBLM`: `entrega_uni_x`
**10 → 2,5** (el "10 kg" de arriba vale sólo para 31/32) y medidas en `fleje_detalle`: N° 96 corta **Ø1,25 x 228**,
N° 95 larga **Ø1,25 x 300**. ⚠ `[deducido]` El `kg_x_uni` cargado **no cierra con esas medidas**: el acero
teórico da **2,20 g** (corta) y **2,89 g** (larga), la base tiene 8,02 g y 7,32 g — ~3× y **la corta más pesada
que la larga**. No se tocó (mueve costo); pendiente de confirmar.

`[usuario]` *"el alambre aluminio ganchito se manda en bolsas de 1kg"* + *"pesa 0.000165 por uni"*: `Z12`
(por unidad) → `kg_x_uni=0,000165`, `entrega_unidad='bolsas'`, `entrega_uni_x=6.060,61` uni (= 1 kg).
**⚠ Movió el costo: Z12 $10,84 → $6,47.** Z12 sale por ruta del `IE8` Fleje N° 55 (matriz 56), y el costeo
usa el peso de la pieza que sale: antes caía al `kg_x_uni` del fleje (0,0004356 kg/pieza), ahora usa el de
Z12 (0,000165). **Los dos números no cierran entre sí (×2,6)** → `[usuario 2026-09-25]` *"tiene desperdicio"*: el 0,0004356 es `1/matriz.partes_por_kilo_de_fleje` de la matriz 56, que **incluye el scrap**.
**Choca con la regla de costeo vigente (§ costeo, punto 3):** el material del fleje usa el `kg_x_uni` de la pieza (sin scrap) y sólo cae a `partes_por_kilo_de_fleje` si falta el peso. `[dato 2026-09-25]` De 51 piezas que salen de fleje por matriz con los dos datos, **45 tienen consumo de matriz > peso de pieza** (+5 %): el costo de todas ignora el desperdicio, no sólo el de Z12. **NO se cambió la vista** — es una decisión de costeo global (sube el costo de ~45 piezas), pendiente del dueño. Z12 queda en $6,47 hasta entonces.

## 4ga. El Cepillo Limpia Bombilla es UNA sola pieza: `GRJ28` para 555 y 764; se compra a Gilardi Esther (2026-09-25)

[usuario, Thomas] *"En sector garage hay dos cepillos limpiabombilla. GRJ29 y GRJ28. Unificalos porque el
555 y el 764, ambos artículos usan GRJ28"* + *"Y se lo compramos a Gilardi Esther"*.

- `GRJ29` (id 900) **se borró**: stock 0 en todas las ubicaciones, 0 movimientos, sin precios ni OC.
- Receta del 764 (`articulo_componente` 894) y su ruta 949 (pasos 3666/3667, insumo → Gentile) apuntan a `GRJ28` (899).
- Inventario: la fila de GRJ29 en Sector Garage se borró y el máximo de GRJ28 pasó a 3.816 + 984 = 4.800
  (suma de los dos máximos Est Madre); la fila de Gentile (ubic 28, stock 0) pasó a GRJ28.
- `GRJ28.proveedor` Cimarron → **Gilardi Esther** (id 30, rubro Sector Garage). Corrige lo anotado el 2026-09-13
  (Cimarrón). Sin precio cargado: costo sigue en 0 para esa pieza.
- **Envase (2026-09-28)** [Thomas, con la foto de la Tablet: *"Peso por uni 0.00193 y vienen 3000 por caja.
  Sugerido en caja"*]: `kg_x_uni=0,00193`, `entrega_unidad='cajas'`, `entrega_uni_x=3000` (5,79 kg/caja),
  `uni_x_cajon` null — mismo modelo que `Z31`/`C13`. Tablet → Enviar (Sector Garage): sugerido 1.980 uni =
  **1 caja** (techo); la cantidad se escribe en kg. `v_costo_componente` idéntico antes/después (805 filas, mismo hash).

## 4gb. `C13` Corta Queso Bastidor c/Cilindro va en CAJAS DE 144 (2026-09-25)

[Thomas, textual: *"El corta queso bastidor c/cilindro se recepciona en cajas de 144 uni y se le manda
a lucho en esas cajas. modelalo para que el sugerido en la tablet aparezca así"*.] El bastidor importado
(`C13`, id 547, Sector Procesado, art 546) no se reenvasa: la caja que llega es la que va a Lucho.
Modelado igual que el caso hermano `Z31` Descorazonador (mismo sector, cajas de 2.400):
`componente.entrega_unidad='cajas'`, `entrega_uni_x=144`; `uni_x_cajon` **queda null a propósito**
(no es cajón de despacho, y así no se cuela en los cálculos de cajones del sector).
- **Tablet → Enviar → Lucho:** `tablet_bundle` ya manda `env_unidad='cajas'`, `env_factor=144`.
  Medido: sugerido 7.854 uni = **55 cajas** (techo). Como `C13` no tiene `kg_x_uni`, la cantidad
  también se escribe **en cajas** (no en kg) — correcto: se manda la caja cerrada.
- ~~Recepción de insumos NO lee el envase: el remito del C13 se sigue cargando en unidades.~~
  **Corregido el mismo día** (ver abajo).

**Remito en cajas + peso (mismo día)** [Thomas: *"Sí"* a recibirlo en cajas; *"4.4kg por caja. Hacé la
cuenta"*]:
- **Peso:** `C13.kg_x_uni` = 4,4 / 144 = **0,030556 kg/uni** (antes null). Medido: `v_costo_componente`
  idéntico antes/después (805 filas, total $526.858,63, hash igual; C13 sigue $1.047,20 porque es
  comprado, su costo es el precio). Efecto en la Tablet: como ahora hay peso, la **cantidad** del envío a
  Lucho se escribe en **kg** con el renglón "= N cajas" debajo (4,4 kg = 1 caja), igual
  que el Z31 y el resto de los talleristas; el **sugerido sigue en cajas** (55).
- **Recepción en cajas:** `componente.remito_unidad` acepta un tercer valor, **`'envase'`** (check
  `componente_remito_unidad_chk` ampliado): el remito viene contado en el envase de la pieza
  (`entrega_unidad` × `entrega_uni_x`). `recepcion_bundle` ahora manda `entrega_unidad`/`entrega_uni_x`, y
  `RecepcionInsumos_GP2.html` v3.62.0 pide "Cantidad cajas" y guarda cajas × 144 en **unidades** (3 cajas
  = 432 uni). El 144 vive en un solo lugar: el mismo dato con que la Tablet se lo manda a Lucho.
  Sin factor, `'envase'` no se reconoce y la pieza cae a su regla de siempre (importado → unidades).

## 4gc. `V18D` Tornillo Sacafuente va a Martín Cornejo en BOLSAS de 2 kg (2026-09-25)

[Thomas, con la foto de su planilla: *"Viendo el envío a Martín Cornejo en versión tablet del tornillo
Sacafuente, que me lo pone en unidades. Quiero que me lo ponga en bolsas"* — KG x Uni **0,0305**, Kg x
Bolsa **2**.] `V18D` (id 281, Sector Remache, sale niquelado de Guazzaroni y lo arma Martín Cornejo en el
508 y el 708) no tenía ni peso ni envase, así que la Tablet caía a unidades.
- **Dato:** `kg_x_uni=0,0305`, `entrega_unidad='bolsas'`, `entrega_uni_x` = 2 / 0,0305 = **65,57 uni por
  bolsa** (no redondo, como la bolsa de 1 kg del Z12: la bolsa se arma pesando). Tablet medida: sugerido
  612 uni = **10 bolsas** (techo de 9,33); la cantidad se escribe en kg (≈ 18,67 kg).
- ⚠ **Movió el costo, y es una corrección:** sin `kg_x_uni` el niquelado de Guazzaroni (cobra por kg,
  **$2.606/kg**, la misma tarifa que V1/V11/V12/V13/D9/D13) daba **$0**. Ahora `V18D` $68,70 → **$148,18**
  (+$79,48 de servicio) y arrastra a **508** $1.554,93 → $1.634,41 y **708** $1.531,98 → $1.611,47. Nada
  más cambió (diff por componente: 3 filas).

## 4gd. `Z21` Cuchillo Torta va a Martín Cornejo en CAJAS de 450, de 6,5 kg (2026-09-25)

[Thomas: *"El cuchillo torta se manda en cajas de 450 uni y cada caja pesa 6.5kg"*.] `Z21` (id 757,
Sector Bombilla, insumo que Martín Cornejo arma en el 311 y el 857): `entrega_unidad='cajas'`,
`entrega_uni_x=450`, y `kg_x_uni` = 6,5 / 450 = **0,014444** `[CORRECCIÓN]`: antes decía **0,01932**, que
daría 8,69 kg por caja — no cierra con la caja pesada (y la caja con cartón incluido pesa MÁS que las
piezas, no menos). Manda el dato del dueño. Costo neutro (comprado: su costo es el precio; diff por
componente vacío). Tablet: sugerido de hoy 4 uni = 1 caja.
- **Sigue activo** `[Thomas 2026-09-25: "Sigue activo. Que se le mande en cajas"]` `[CORRECCIÓN]`: el
  `estado_compra='discontinuo'` se le había puesto el 2026-09-11 al discontinuar el **311**, pero el
  **857** lo sigue usando. Pasa a `null` (igual que su hermano `Z22` de Melinox): vuelve a OC/recepción.
- **La cantidad se escribe en CAJAS, no en kg** (aunque tenga peso). Columna nueva
  **`componente.envio_carga`** (`'envase'` | `'kg'` | null = regla del sector: cartón/caja en envase, el
  resto en kg). `tablet_bundle` la usa para `env_carga`; el front ya sabía escribir en el envase (lo usan
  cartones y cajas) y guarda cajas × 450 en unidades. Hoy sólo `Z21='envase'`. Test en `test_tablet.js`.
- **Vuelve a la OC de Melinox** `[Thomas 2026-09-25: "Si"]`, aunque la planilla de costos del vecino lo
  marque «NO COMPRAR +» (esa marca era del 311). Medido en `oc_bundle`: consumo 4 uni/mes (Est Madre del
  857), máximo 12, **sugerido 12 uni** a $890. ⚠ La OC NO redondea a la caja de 450: el redondeo por
  envase de la OC es por norma de rubro y Sector Bombilla no tiene; si Melinox sólo vende la caja
  cerrada, falta esa regla.


## 4ge. Crudos p/niquelar a Guazzaroni en CAJONES + cartones Rallador/Huevo en PAQUETES (2026-09-25)

[Thomas: *"0.0022kg por uni 2kg por cajon remache sacafuente / 0.0305 kg por uni 2kg por cajon tornillo
sacafuente / 0.0006 kg por uni 10kg por cajon remache uña p/niquelar. Para el envio a guazzaroni que
aparezca en cajones el sugerido"*.]
- **Dato:** `CV6` kg_x_uni 0,00215 → **0,0022**, uni_x_cajon **909,09** (2 kg); `CV18D` 0,0305, **65,57**
  (2 kg); `CV9` 0,000567 → **0,0006**, **16.666,67** (10 kg). `V18D` uni_x_cajon null → 65,57 (sin eso el
  sugerido del SP daba "—"). Costo neutro (diff de `v_costo_componente` vacío). `V6`/`V9` (niquelados)
  quedan con su kg viejo (0,00215 / 0,000567): a confirmar si también cambian.
- **Bug corregido (EnviosPS v1.11.1):** con envase por pieza el sugerido salía en cajones del SP (V1 =
  5.714) rotulado como cajón del SC (CV1 = 57.143). Ahora se calcula en unidades (máx SP − online SP −
  en poder del PS) ÷ cajón del SC. Ester (factor fijo 1.800) no se tocó.
- **Cartones a prov. AT** [Thomas: *"Se les manda a Carriero. En paquetes de 3500. El formato rayador es
  en paquetes de 3500"* / *"El 824 y el 825 son tipo corbata. El 026 y 027 son tipo 8"* y enseguida *"Me corrijo. 026 y 027 son tipo huevo"*]:
  formato `Rallador` uni_x_bolsa null → ~~3.500~~ **2.500** (F5A 321, P2A 840; ver 4gg); `C2A` 026 y `C2B` 027 pasan de
  Corbata a formato **Huevo** (paquete 2.000). `Q6B` 824 / `Q6C` 825 siguen Corbata: paquete de **1.000** [Thomas: *"1000"*].
  El sugerido de hoy es 0 en todos porque máximo del destino = 0 y el Sector Cartón no tiene stock.

## 4gf. La Bandita Prensa Matambre va a Maspoli en BOLSITAS de 2.000 (2026-09-25)

[Thomas: *"La bandita prensa matambre en bolsitas de 2000"*.] `BANDITAM` (id 935) compartía el formato
`Bandita` con la del Palo de Amasar (`BANDITA`), y en cartón el paquete de envío es **por formato**. Para
no arrastrar a la otra, se hizo lo mismo que con "Bolsa Cartón" (4fx): formato nuevo **`Bandita Matambre`**
(múltiplos copiados de `Bandita`, OC igual) con `uni_x_bolsa=2000`. `BANDITA` queda sin paquete.
- **Rótulo:** `tablet_bundle` ponía "paquetes" fijo a todo cartón/caja; ahora respeta
  `componente.entrega_unidad` si está cargado (hoy solo `BANDITAM='bolsas'`, único del sector 10/11 con
  dato) → la Tablet dice **bolsas**. Sin dato sigue diciendo paquetes.

## 4gg. El paquete de envío del cartón es POR CÓDIGO, no por formato (2026-09-25)

[Thomas, con `Conteo_Cartones_VACIO.xlsx`: *"para poner el sugerido en paquetes busca según el código de
artículo… si es cartón 222 busca en la columna de código 222 y después en la columna de uni por paquete
tenés el dato"* / *"En la hoja pedido vacio"*.] La planilla muestra que el paquete **no es del formato**:
dentro de Huevo hay 1.000 y 2.500, dentro de Corb8 1.000 y 2.500, y el 700 (LOKE) va de 2.000.
- **Regla nueva:** `componente.entrega_uni_x` del cartón manda; si está en null cae a
  `carton_formato.uni_x_bolsa`. Cambiado en `tablet_bundle` (env_factor) y `cartones_para_reemplazo`.
  **Relevamiento también** (`relev_factor`, Thomas dijo que sí): el paquetón que se cuenta es el del cartón.
  **O.C. no lo usa** (agrupa por múltiplos de pliego). **Recepción también** [Thomas: *"Trae las unidades que
  dice el uni x paquete x cartón que acabas de cargar"*]: la bolsa de la gráfica = `entrega_uni_x` del cartón
  (2.500 = 10 paquetes de 250, +10 en la tarjeta). `guardar_control_cartones` y RecepcionInsumos v3.64.0.
- **El formato es SOLO EL NOMBRE** [Thomas: *"tendría que nada más decir el formato y esa tabla fija por formato
  de uni por paquete, sacala"*]. Se cargó `entrega_uni_x` a los 85 cartones que no lo tenían (con el número que
  tenían por formato) y a los pliegos (100), y se sacó toda caída al formato: `tablet_bundle`,
  `cartones_para_reemplazo`, `relev_factor`, `guardar_control_cartones`, `recepcion_bundle` (uni_x_bolsa_cat) y
  la tabla fija `UNI_X_BOLSA` del front. `carton_formato.uni_x_bolsa` queda en la tabla pero **nadie lo lee**
  para el paquete. Único cartón sin paquete: `BANDITA` (Palo de Amasar) → "sin paquete cargado".
- **Los 13 que no estaban en la planilla** quedaron fijos por cartón con el número de su formato [Thomas:
  *"usa esas uni x paquete"*]: 059/500/510/516/715/818/909 = 1.000 (C), 355/515/590/867/890 = 2.000 (Huevo),
  708 = 1.000 (LOKE). Ojo: la hoja tenía "590E" (2.500) y "890E" (1.000); **manda lo dicho por Thomas** (2.000).
  Los Bolsa Cartón (031/120/836 = 7.500) siguen por formato.
- **Dato:** 137 cartones de la base cruzan con la hoja (`Cartón NNN` = col Cod). **52** difieren del
  formato y se cargaron por pieza (`entrega_uni_x` + `entrega_unidad='paquetes'`, para que el escritorio
  no los rotule "cajones"): p.ej. M2B 222 = 2.500, M1/M2A/M2C/M3A/M3B = 2.500, C2A/C2B = 2.500,
  O1B 700 = 2.000, 23 Huevo en 1.000. Los otros 85 coinciden con su formato.
- `F5A` 321 y `P2A` 840 = **2.500** `[CORRECCIÓN]`: primero se cargó 3.500 (dicho en el chat); Thomas
  confirmó *"Tomá el que dice la planilla: 2500"* → formato `Rallador` uni_x_bolsa = 2.500. 824/825/901 dicen 998/999/1001 → se dejan en 1.000 (typo).

## 4gh. Las BOLSAS no tienen formato: formato es sólo de los cartones de Gráficos Pol (2026-09-25)

`[usuario 2026-09-25, Thomas]`: *"no tiene formato. Formato tienen solo los cartones de gráfica pol"*.
Aplicado a las 5 bolsas del sector cartón (se eligió: las 3 de Envases Vihal + las 2 de Papelera
Nueve de Julio; **NO** a los pliegos de AJ Adhesivos ni a los 2 C de Blist-Pack, que siguen con formato):

- Descripción **"Bolsa NNN"**, no "Cartón NNN": `A1B` Bolsa 031, `A1B1` Bolsa 120, `G8C` Bolsa 836.
- Código de posición como el resto de los cartones (lo eligió Claude a pedido, junto a sus hermanas):
  `BOLSA550` → **`A1B2`** (Bolsa 550, LOEKE) y `BOLSA760` → **`G8C1`** (Bolsa 760, CHEF). Todo lo
  referencia por id, así que el rename no rompió nada.
- `carton_formato = NULL` en las 5. El paquete de envío se pasó ANTES a la pieza (`entrega_uni_x` +
  `entrega_unidad='paquetes'`, mismo camino que 4gg): Vihal **7.500**, Papelera **200**. Tablet,
  relevamiento y reemplazo leen `coalesce(entrega_uni_x, formato)` → sin cambio de comportamiento.
- ⚠ Lo que SÍ se perdió: el aviso de **pedido mínimo 20.000** de la OC (vivía en el formato y estaba
  sin confirmar). Recepción las muestra en el chip "Sin formato" y las sigue contando en paquetes.
- Los formatos `Bolsa` y `Bolsa Cartón` de `GP2.carton_formato` quedaron sin uso (no se borraron).
- **Continuación (mismo día)** `[usuario]`: se **borraron** los formatos `Bolsa` y `Bolsa Cartón`
  (*"Sí"*), y Recepción Insumos (v3.63.0) ya no muestra la fila FORMATO cuando ningún ítem de la
  marca tiene formato: con Vihal y Papelera aparecen las bolsas de cada marca, sin clasificación.
- **`BANDITAM` es formato `Bandita`** `[usuario 2026-09-25: "Bandita matambre es formato bandita"]`.
  Da vuelta el formato aparte `Bandita Matambre` de 4gf: la bolsita de **2.000** pasó a la pieza
  (`entrega_uni_x=2000`, `entrega_unidad='bolsas'` ya estaba) y el formato `Bandita Matambre` se
  borró. Los múltiplos de OC eran los mismos de Bandita, así que la OC no cambia.

## 4gi. Proveedores del sacafuente: tornillo a Imel, vástago a Bella Vista (2026-09-25)

[Thomas: *"El tornillo sacafuente se lo compramos a IMEL. Y el vástago sacafuente se lo compramos a bella
vista"*.] `[CORRECCIÓN]` Estaban cruzados: `CV18D` Tornillo Sacafuente p/Niquelar decía **Tornillos
Suipacha** → **Imel**; `W8` Vástago Sacafuente Pizzero decía **Imel** → **Bella Vista**. Costo neutro (diff
de `v_costo_componente` vacío). Afecta en qué proveedor aparecen en OC y Recepción de Insumos.
- **Tornillos Suipacha dado de baja** (`proveedor_insumo.activo=false`) [Thomas: *"dalo de baja porque no le
  compramos más el tornillo corta queso"*]. Tras pasar `CV18D` a Imel no le quedaba ninguna pieza, ni proveedor
  alternativo, ni O.C. abierta. No se borra: queda para el historial de O.C. y recepciones.

## 4gj. Cruce de las 5 planillas VACIO contra el programa (2026-09-25, noche)

`[dato]` Informe completo en `RELEVAMIENTO_VS_GP2_2026-09-25.md` (+ `_detalle.xlsx`). Lo que conviene
recordar sin abrirlo:

- **La Est. Madre de GP2 da ~30 % menos que la "Sugerencia" de las planillas en LOEKE y ~56 % menos en
  CHEF** (sólo 2 de 199 artículos coinciden). Es la causa de casi toda diferencia de consumo, máximo y
  sugerido. Manda `GP2.est_madre` (§4h) hasta que el dueño diga otra cosa `[pendiente D0]`.
- **Meses del máximo distintos de la planilla**: cartón 6 (planilla 3), remache 4 (6), MP plástica 2,5
  (4); plástico 4 y bombilla 3 coinciden. Garage: la planilla usa capacidad física en cajones.
- **Bolsa de remache: tres números** — Relevamiento cuenta bolsas de 20 kg (`uni_x_cajon`), la O.C.
  redondea a 25 kg (`remache_kg_x_bolsa`), la planilla usa 2 o 10 kg `[pendiente D4]`.
- **`relev_factor` cae a `entrega_uni_x` cuando la pieza no tiene `uni_x_cajon`** (fuera de cartón,
  caja y fleje), con el envase de `entrega_unidad`. Sin eso GRJ13/GRJ14 (cajas de 100), GRJ21A/B
  (5.400) y Z21 (450) sólo se podían contar sueltas. OJO: **no** se usa `entrega_uni_x` cuando hay
  `uni_x_cajon`, porque no siempre es el mismo envase (GRJ5/GRJ6: cajón 960 en el sector, bolsa de
  120 al tallerista).
- La planilla de cartones **da posiciones que GP2 tenía como provisorias**: CART186 = `I4C`,
  CART058 = `G8C` (choca con la Bolsa 836), CCE2B = `E2B`, CCG6B = `G6A`, CCC4 = `D5A`, K5D = `H2A`.
- `CV15` Rem Tapón Hierro (id 617, cargado el 04-09) **ya no existe** en GP2 y la planilla lo sigue
  pidiendo; no hay rastro del borrado `[pendiente D8]`.
- `db/` estaba desfasado (6 funciones + `v_consumo_fleje_kg` cambiadas en vivo): se resincronizó y
  quedó verificado por md5, 163/163 funciones.
- **550 Filtro para bombillas lleva 2 filtros (`GRJ21A`) y 2 precintos (`GRJ21B`) por unidad**
  `[Thomas 2026-09-26: "el blister viene por dos"]`. La receta GP2 (×2) está bien; la planilla de
  Garage (Consumo Art, ×1) está mal. El 760 (gemelo CHEF) tiene la misma receta ×2 `[deducido]`.
- **Est. Madre ponderada, corrección de la línea de arriba**: sobre artículos vivos, GP2 da −15,5 %
  en LOEKE y −37 % en CHEF contra la planilla Madre 7-26 (la mediana −30/−56 % incluía artículos
  que GP2 no tiene).
- **DECIDIDO: manda la Est. Madre de GP2** `[Thomas 2026-09-26: "Considerá la est madre de GP2"]`, no la
  de las planillas (Madre 7-26 / 10-25). Cruzada contra Gestión Virgilio (`gv_proyeccion_articulo`):
  iguales salvo que **GP2 no suma la familia** (secundario → principal). Le falta demanda a 580 (el 580E
  aporta 49 caj/mes) y a 941E-948E y 590E (secundarios 332-338 y 548, que GP2 no tiene como artículo).
  Arreglo propuesto, no hecho: familias en una tabla propia de GP2 `[pendiente D9]`.

## 4gk. Familias de artículos en GP2: la venta del secundario va al principal (2026-09-26)

`[Thomas 2026-09-26: "Avanzá si podés vos"]` Hecho tras el cruce con Gestión Virgilio (§4gj). Tabla
**`GP2.articulo_familia (cod_secundario pk, cod_principal)`**, 19 pares copiados de
`public."Equivalencias_Familia"` (una vez; REGLA 0: ninguna función/vista GP2 lee `public`). La
regla es la de Virgilio (v22.68/v22.72): **la Est. Madre del secundario se suma al principal y el
secundario queda en 0** aunque exista como artículo GP2 (caso 338 → 941E). Vive en
`v_consumo_demanda` (CTE `dem`); un trigger sobre la tabla recalcula máximos. Mantenimiento: a mano;
`db/verificar.sql` regla `AG` compara con `Equivalencias_Familia` y avisa si se desfasa.
Efecto: el 580 Batidor Mini pasó de 114 a 702 uni/mes (el 580E aporta 588) y con él EP10, G7A,
GRJ10A, ABPM, IVBCM, IVBLM; los importados de acero 941E-948E suman sus secundarios 332-338
(PEST1 684 → 1.178). **Hallazgo de paso**: `trg_maximos_est_madre` no recalcula talleristas ni Prov AT
(68 máximos de tallerista estaban viejos); propuesto, no hecho `[pendiente D10]`.
- **Bolsa de remache: "depende"** `[Thomas 2026-09-26]` — dos envases: bolsa del proveedor (planilla 2/10 kg,
  O.C. múltiplos de 25 kg) y cajón de 20 kg a Guazzaroni (`uni_x_cajon`, medido 21 kg). Nada cambiado.
- Datos aplicados 2026-09-26: cartón Q7E en receta 922; C12 inventario a Procesado (máx 1.165 por 5
  cajones); fila C12B en Bombilla borrada; PA8A uni_x_cajon 5.000 (planilla); máximos físicos PIEA 1,
  PIEB 1, PCP4A 800, PCP2 145 kg.

## 4gl. Los máximos se recalculan UNA vez por transacción, al COMMIT (2026-09-26)

`[Thomas 2026-09-26: "Dale" a D10]` + panel de 5 agentes (3 lentes + 2 refutadores) antes de tocar.
- **Corrección a §4gk**: la Tablet **no** lee `inventario.maximo` de talleristas (calcula el techo en vivo:
  consumo × meses); ese máximo guardado lo muestran sólo Proporciones_GP2 y la vista Talleristas de Stock
  General. Lo de "afecta la Tablet" estaba mal dicho.
- **Hallazgo `[dato, pg_stat_statements]`**: el sync de LK hace `DELETE FROM proyeccion_madre` + 330
  `INSERT` de una fila, en una transacción, ~1,8 veces por día; `fn_est_madre_sync` es por fila, así que el
  trigger statement-level de `est_madre` corría `recalcular_maximos_insumos` **658 veces por sync** (~54 s;
  el DELETE 21,2 s promedio). Nadie lo notaba porque el rol `lk_ppp_reader` tiene timeout de 120 s.
- **Arreglo**: `fn_recalc_maximos_diferido` + los 4 `trg_maximos_*` como **constraint triggers
  DEFERRABLE INITIALLY DEFERRED** con bandera transaccional. Al COMMIT corre una sola vez insumos +
  **talleristas** (antes nadie recalculaba talleristas al cambiar la Est. Madre: 68 estaban viejos).
  Prov AT no entra (techo 0, regla 24-09). Probado con EP10/580. `fn_recalc_maximos_insumos` se borró.
- **Regla que queda**: en ubicaciones de tallerista el único origen que el recálculo respeta es `fisico`;
  un máximo cargado a mano por SQL con otro origen se pisa en el próximo sync. Hoy no hay ninguno.
- 13 máximos de tallerista sin ruta ni consumo (Gentile 9, Cavallero 3, Cornejo PC8) se limpiaron a null.

## 4gm. GP2 lee la O.C. de Gestión Virgilio: al Prov AT se le mandan las partes de su orden (2026-09-26)

> **2026-09-28 — "📄 Ver O.C." en la Tablet** `[usuario: "en el envío a prov de art terminado y talleristas
> o.c. … me aparezca arriba de 'buscar por código' una box que me diga ver o.c. y pueda ver la o.c. de gestión
> virgilio"]`. En Enviar, para las contrapartes cuyo sugerido sale de esta O.C. (tallerista O.C. y prov AT), hay
> una box arriba del buscador que abre lo PENDIENTE de `v_oc_virgilio_pendiente` (tipo + ref_id, con la
> descripción de `articulo`): código, fecha de la O.C., pedido, recibido y pendiente en cajas. Se lee al abrir, no
> viaja en `tablet_bundle`. Tablet v1.37.0, `tests/ui/test_tablet_ver_oc.js`.

`[Thomas 2026-09-26: "Para los proveedores de artículo terminado solamente tenemos que mandarle partes
para que puedan hacer lo que les pide su orden de compra"]`. Cierra el hueco que §4fr y §4fw dejaron
escrito ("cuando salga orden de compra de Virgilio, que todavía no lo modelamos").

**Cómo genera Virgilio las O.C.** `[dato: repo Gestion-Virgilio, sql/generar_ocs_automaticas.sql,
gv_generador_oc_*, oc_nueva_pisa_vieja_v1460.sql]`: `vista_generador_oc` arma por artículo
**máximo = ceil(proyección × índice)** (proyección = `gv_proyeccion_articulo`, índice default 1,5,
"la proyección es rey": no se topa a la góndola), **a pedir = máximo + pedidos pendientes − stock
disponible**, y el cron diario `gv_oc_auto_corrida()` (ancla `GV_OC_Auto`, cadencia 7 días) inserta
una línea por (proveedor, código) en `public."Ordenes_Compra"` (rubro `Art Term`, unidad `Cajas`,
estado `pendiente`, `oc_uni_caja`). El proveedor sale de `OC_Maximos.proveedor` (quién fabrica), salvo
Blistpack/Oscar/Pedernera, cuya O.C. se emite a **Log/ Fabr** (`GV_OC_Fabrica_Para`). Al recibir,
`gv_oc_recompute_recibido` cruza entregas contra O.C. por (proveedor, código) y sube
`cantidad_recibida`/`estado`. **Regla "la nueva pisa la vieja"**: por (proveedor, código) sólo vive
la O.C. de fecha más nueva no cerrada/anulada (ventana 120 días); pendiente = cantidad − recibida.
Los proveedores de esa tabla son también nuestros talleristas (Lucho, Poly=IJUPA, Martin C, Garcia,
German, Oscar, Pettofrezza, Carlos E) y fasoneros (Pedernera).

**Lo hecho en GP2 (REGLA 0: sin leer `public` desde GP2):**
- **`GP2.oc_virgilio`**: espejo fila a fila de `Ordenes_Compra` por el trigger `trg_oc_virgilio_espejo_gp2`
  (en `public`, patrón `est_madre`; `fn_oc_virgilio_espejo` nunca frena a Virgilio: `raise warning`).
  Semilla 872 filas; `db/verificar.sql` regla `AH` avisa si se desfasa.
- **`v_oc_virgilio_pendiente`**: O.C. vigente por (contraparte GP2, código) con la regla de Virgilio;
  el proveedor se resuelve a contraparte **activa** por nombre de `proveedor_at` (con o sin " SA"),
  `contraparte_alias`, nombre de tallerista exacto o por prefijo ("Martin C" → Martin Cornejo).
  **"Carlos E" = Alex Escalante** `[Thomas 2026-09-26: "Carlos E es el papá de Alex (el que
  factura)"]`: Virgilio le emite la O.C. al padre porque es quien factura; el trabajo lo hace Alex
  (tallerista 2). Alias `CARLOS E` → tallerista 2 cargado en `contraparte_alias` el 2026-09-26
  (17 líneas de O.C. vigentes resolvieron: 506, 510, 248, 535, 515, 395, 333…). El alias `CARLOS`
  a secas sigue siendo Aguirre (§1-nonies): no confundir. Como Escalante NO es `pedido_por_oc_virgilio`,
  su techo en la Tablet no cambia (sigue consumo × meses).
  Sin resolver hoy: "Log/ Fabr", "Blistpack", "Basconia" (flejes), "Paternal Goma" (prov AT inactivo).
  `uni_pend` = cajas × `articulos_por_caja` (o la caja de la O.C.; en `Uni` ya son unidades).
- **`v_oc_virgilio_partes`**: `uni_pend` × receta, sólo cartón y caja (lo que GP2 le manda al prov AT).
- **`tablet_bundle`**: el techo del prov AT pasa de `0` a esas partes; sugerido = techo − lo que ya
  tiene. Medido: 24 filas con sugerido en 5 prov AT (Pintos 13, Carriero 3, Maspoli 5, The Plast 3);
  Cabral, Kuffo, Lopez Jose y Manfer sin O.C. vigente → 0, como antes.
- Códigos de O.C. que **no son artículo GP2**: Manfer 565, Maspoli 55219, Tierra Nativa 55215 → no
  generan partes (se ven en la vista con `articulo_id` null).

**Pendiente (no hecho)**: los **talleristas O.C.** (Carlos Aguirre, Blist-Pack, §4fr) siguen con techo 0;
la misma vista sirve, pero sus partes salen de `ruta_paso` (comp_entrada del paso del tallerista),
no de la receta plana `[idea 7356]`. Pedernera (fasonero) idem.

**Ampliación del mismo día — talleristas O.C.** `[Thomas 2026-09-26: "Los prov AT le tenemos que mandar
mercadería en función de su OC. Lo mismo lo que entregan los talleristas en garage"]`:
- **`v_oc_virgilio_demanda`**: la O.C. vigente explotada por artículo y componente (receta + BOM +
  rutas, el mismo recorrido que `v_consumo_demanda` hace con la Est. Madre), sin importar a quién
  esté emitida la orden.
- **`v_oc_virgilio_partes_tallerista`**: partes que necesita un **tallerista O.C.**
  (`pedido_por_oc_virgilio`: Carlos Aguirre, Blist-Pack) para su O.C., todos sus pasos — cierra la
  idea 7356 y el `then 0` de §4fr. uni_requeridas = demanda por O.C. × % del tallerista
  (`v_reparto_efectivo`).
- **Medido**: Aguirre C1A/GRJ10 0 → 3.948; Blist-Pack GRJ28 0 → 1.980, GRJ4 960, GRJ6 768.

**⚠ Corrección del dueño, mismo día — el GARAGE NO va por la O.C. de Virgilio.** Durante unas horas
(commit `db409de`) los pasos de cualquier tallerista con salida en Sector Garage (Cornejo GRJ5/GRJ6,
Escalante GRJ10/GRJ10A) también tomaban el techo de la O.C. de Virgilio. `[Thomas 2026-09-26, textual:
"En realidad no, mentira, te mentí. Los que llenan garage se tienen que llenar por orden de compra de
INSUMOS, no por orden de compra de artículo terminado. Sí a Martín o a Carlos o a Poli debemos
mandarle mercadería, pero es para que llenen el sector de garage o lo que entrega Poli o lo que
entrega Lucho o lo que entrega Alex."]`. **Revertido** en la base y en `db/`: la vista quedó sólo con
`pedido_por_oc_virgilio` (sin columna `entrega_garage`) y `tablet_bundle` sin la rama `sector_id = 9`;
Cornejo y Escalante vuelven al máximo de la casa (consumo × meses).
- `[deducido, sin confirmar]` Lo que el dueño describe para el garage es el **patrón fasonero** (§4b,
  Maspoli): el GRJ lo compra GP2 con una **O.C. de insumos** (`GP2.orden_compra` al tallerista como
  `proveedor_insumo`) y el techo de lo que se le manda son las partes de esa O.C. pendiente
  (`oc_ps` de `tablet_bundle`). Hoy los GRJ son `estado_compra='fabricacion'` y no aparecen en
  `oc_bundle`; sólo Gilardi Esther es `proveedor_insumo` de rubro Garage. **Falta definir con Thomas**
  qué abarca "lo que entrega Poli / Lucho / Alex" (¿sólo GRJ o todo lo que entregan?) antes de modelarlo.

### 4ga. El login vuelve a estar PRENDIDO, y ahora la base sabe quién llama (2026-09-28)

**Decisión del dueño** `[usuario 2026-09-28]`, contestando la auditoría de seguridad
(`SEGURIDAD_GP2_2026-09-28.md`, punto 1): **"1 si"** → se vuelve a pedir login con Google;
**"2 si tiene"** → la tablet de operarios **sí** tiene login de Google (no hace falta un token
por dispositivo); **"n8n no escribe"** → n8n no es un llamador que escriba en GP2.
Revierte la decisión del 2026-08-29 (login apagado: "la página ya está privada… prefiero que
esté suelta").

**Por qué molestaba el login de antes** `[dato: auth-guard.js viejo]`: deslogueaba apenas vencía
el token de acceso (1 hora) y las pantallas usaban un cliente *sin sesión*, así que nadie lo
renovaba → Google de nuevo cada hora. **Fase A (hecha):** `GP2_SB()` usa la sesión guardada y la
renueva sola (un solo cliente por página: dos se pisan al renovar y desloguean); el guard solo
pide login si no hay sesión (sin `refresh_token`); al volver del login se regresa a la misma
pantalla (`?next=`, solo rutas propias); las 31 pantallas GP2 que no cargaban el guard ahora lo
cargan. El guard no actúa bajo `file://` (así abren los tests; la app real va por https).

**Fase B — HECHA el mismo día** `[usuario: "b: no se está utilizando actualmente"]`: como el
sistema no está en uso, no se esperó a los logs. Las 62 RPC que escriben exigen un usuario de la
whitelist (`public.usuarios_permitidos`, hoy 2 cuentas: una `admin` y una `envios`) y `anon` ya no
las ejecuta. **Toda cuenta que tenga que escribir (incluidas las tablets) tiene que estar en esa
tabla**; la cuenta `envios` además sólo ve su lista de pantallas en `auth-guard.js`.

**Lo que quedaba pendiente antes de la fase B (histórico):** la base sigue aceptando a `anon`. Desde ahora los pedidos
de un usuario logueado llegan como `authenticated` con su email; la **fase B** (exigir la
whitelist en las RPCs y sacarle `EXECUTE` a `anon`) va recién cuando se vea en los logs que los
pedidos reales llegan con sesión — si se corta antes, una tablet con la versión vieja cacheada
queda muda. La macro `MACRO_ENTREGAS_SUPABASE.bas` solo **lee** `public."Entregas Tallerista
Virgilio"` `[dato: el .bas]`, no toca GP2.


## 4gn. El menú principal son DOS grupos: Stocks y Herramientas (2026-09-28)

- [usuario, Thomas] *"Dos módulos en vez de 10"*. Lo que se ve en `GP2_MODULOS.html`: las dos
  pastillas de tablet (Logística y Operarios — lo que usan logística y los operarios) y dos grupos:
  - **Stocks**: Stock General, Control Partes Talleristas, Control Partes PS, Control Partes Prov. AT,
    Faltantes, Validación de Stock, Proporciones.
  - **Herramientas**: O.C., O.P., Despiece x Art., Consumo x Componente, Tiempos Matrices,
    Casos Especiales, Devolución Cervantes.
- [usuario] *"El resto ocultalos, si en algún momento te pido que los vuelvas a poner tenés que
  poder"*. Por eso **no se borró nada**: los 10 grupos anteriores siguen enteros en `MENU_OCULTO`
  (mismo archivo). Reponer un grupo = moverlo de `MENU_OCULTO` a `MENU`; un módulo suelto = copiar
  su línea. `GP2_MODULOS.html?todos=1` muestra todo junto, sin editar. Las pantallas siguen
  abriendo por su URL directa.
- [deducido] Quedan fuera del menú normal, entre otras, Recepción Insumos, Envíos/Entregas de
  tallerista/PS/Prov AT, el Relevamiento (conteo) y todo Producción salvo Tiempos Matrices. Los que
  se usan desde la tablet siguen accesibles por ahí; los de oficina sólo por `?todos=1` o URL.

- **Los dos grupos quedan SIEMPRE abiertos y no se pueden cerrar** [usuario, Thomas 2026-09-28: *"Por default quiero los dos módulos abiertos ... No lo quiero poder cerrar. Que esté expandido ambos"*]. v1.201.0: en el menú normal no hay chevron ni click que los cierre (clase `body.fijo`); con `?todos=1` sigue el acordeón de siempre, porque 13 grupos abiertos no entran. En celular las baldosas bajan de alto para que los 2 grupos entren juntos en una pantalla, y las pastillas de Tablet pasan a una barra fija abajo (una al lado de la otra) porque apiladas tapaban la última baldosa. [dato] En pantalla baja (375×600) la última fila queda detrás de la barra y se ve scrolleando 70px.

## 4go. O.C.: la pantalla es un cuadro sinóptico, sin textos de ayuda (2026-09-28)

- [usuario] Thomas: *"quiero que elimines todos esos textos... optimizame todo como cuadro sinóptico, lo más optimizado posible (tanto la página principal como el recuadro cuando tocás máximo)"*.
- Fuera de `Compras/OC_GP2.html` (v1.35.0): el cartel "Elegí un proveedor…", la leyenda de "Pedir", la ayuda de la fecha ("se propone sola") y los dos cartelitos debajo de Pedir ("sugerido N · máx − stock" y "hay que pedir / no hace falta"). La fecha se sigue proponiendo sola; el sugerido sigue viniendo cargado en Pedir; el stock en rojo es lo que dice "abajo del máximo".
- Queda sólo "ya pediste N (en camino)": es lo único que explica por qué una fila abajo del máximo llega vacía.
- Tabla, barra y buscador abrazan el dato (sin 100% de ancho ni anchos fijos); las dos barras son una. El modal del Máximo: los 4 recuadros son una fila de tabla con la unidad en el encabezado, el desglose va ordenado por consumo mayor → menor y el modal toma el ancho de la tabla.
- **No volver a meter texto explicativo en esta pantalla**: si algo necesita explicarse, es una columna o un dato, no una leyenda.
- **v1.36.0 (mismo día)** [usuario] Thomas: *"quiero que me aparezca esta ventanita cuando me pongo arriba de máximo, sin tener que clickear... solo esos datos. El resto no lo quiero"*. El desglose ya no es un modal: es una ventanita flotante pegada a la celda Máximo que se abre al pasar el mouse y se cierra al salir. Muestra **sólo** Artículo (o Pieza) · Venta · Consume · kg/mes + Total; se fueron el título, la fila Máximo/Origen/Meses/Consumo y el aviso de origen. En tablet/celular (sin mouse) un toque la abre y otro, o tocar afuera, la cierra.
- **v1.37.0** [usuario] Thomas: *"de todo esto quede el botón de Crear O.C. nomás. Que aparezca abajo de Buscar Insumo"*. Usar sugeridos, Limpiar, total en plata, Entrega y Nota quedan **ocultos** (`#barraOculta`), no borrados: la fecha se sigue proponiendo sola (hoy + `dias_entrega`) y viaja a `crear_oc`; la nota va vacía.
- **v1.38.0 — LA O.C. SE PIDE EN LA UNIDAD DEL REMITO** [usuario] Thomas: *"te dije en todas las recepciones con qué unidad de medida va el remito. Usá las mismas unidades para las órdenes de compra. Y al lado de pedir una columna Uni Medida... los resortes batidor los pido en unidades"*. `umRemito()` en `OC_GP2.html` replica la decisión de `abrirPopup()` de `RecepcionInsumos_GP2.html`: `remito_unidad` de la pieza → cartón en paquetes de 250 (pliego en uni) → remaches/bombillas/cajas en uni → plástico uni por proveedor → fleje por proveedor/UM → `recibe_en_cajas` kg → UM. `oc_bundle` ahora trae `remito_unidad`, `recibe_en_cajas`, `entrega_unidad`, `entrega_uni_x`. El campo Pedir se ve en esa unidad; internamente y a `crear_oc` sigue viajando la unidad de stock (así el cartón valida múltiplos en unidades).
  - [dato] Medido sobre `oc_bundle` (342 insumos): 153 cartones cambian a paquetes; 3 resortes de Charcas (EP10, LLF8, BOM10) pasan de paquetes de 10 kg a **uni**; BOM12 y PCP3 pasan a kg; el resto ya coincidía.
  - **El paquete de 10 kg de Charcas es sólo para sus flejes (sector 5).** Los resortes que nos vende se piden y se reciben en unidades. Antes 3 paq de EP10 se guardaban como 30 kg.
  - ⚠ Son dos copias de la misma regla (Recepción y OC). Si cambia la unidad de remito de un rubro, cambiar las dos.

## 4gp. Mínimos de pedido por pieza: la planilla los tiene, GP2 los muestra bajo "Pedir" (2026-09-28)

`[Thomas 2026-09-28: "comencemos a ver los mínimos de los pedidos de órdenes de compra"]`. Cruce en
`MINIMOS_OC_2026-09-28_detalle.xlsx`.

- `[dato: planillas de relevamiento]` **Cartón**: el "Pedi Min Uni" NO es por pieza, es el múltiplo de
  pliego por (tipo, marca): C-LK 12.000, LOKE-CH 16.000, Huevo-CH 25.000, **Huevo-LK 12.000**,
  Corb8-LK 12.000 / **Corb8-CH 30.000**, Rallador 24.000, tapones 18.000. GP2 tiene un solo
  `pliegos_multiplo` por formato → 46 códigos no coinciden y 28 tienen otro formato que la planilla.
  **Sin decidir**: si el múltiplo depende de la marca.
- `[dato]` **Resina**: los 5 pisos en kg (`proveedor_insumo.pedido_minimo_kg`) coinciden.
- `[usuario 2026-09-28: "cargá esos mínimos"]` **Bombilla, cargado en `componente.pedido_minimo_uni`**:
  EP10, LLF8, BOM8 10.000 · BOM10 5.000 · BOM12 1.760 (planilla 1.764,7 = 1 cajón) · Z22 1.200 ·
  Z25A/Z25B 1.000 (en la planilla figuran como Z2S/Z2SB "Aro/Argolla p/Llavero"). De los 22 códigos
  con mínimo en la planilla, **14 no existen en GP2** (BOM2/3/4/5/6/7/9/11/14, Z19A/B, Z32, AA6/AE10,
  tapitas). "A1 Arandelas Corta Queso" (Skotnica) no es el A1 de GP2, que es una caja. BOM8: la
  planilla dice Resortes Alfredo, GP2 Grudzien Claudia Laura — `[deducido]` el mismo proveedor.
- **Cómo se muestra** (`OC_GP2.html` v1.36.0): una línea "mín. proveedor N uni" debajo del campo
  Pedir (para Charcas también "= N paq"), en negrita si lo pedido queda corto. **Sólo informa**: el
  recuadro amarillo con "Subir al mínimo" se sacó el 14-09 y no vuelve; la OC dispara por el máximo.
- `[usuario 2026-09-28: "Sí, cargá"]` **Remaches, cargado en `componente.pedido_minimo_uni`** (16, sector 8):
  el mínimo va en la pieza que se COMPRA (`CV*` "p/Niquelar"), no en la niquelada `V*`. CV1 165.000 ·
  W8 150.000 · CV2 95.000 · CV9 90.000 · CV4 75.000 · V10 73.750 (no tiene CV) · CV3 70.000 · CV6 65.000 ·
  CV12 58.000 · CV11 39.000 · CV7 26.300 · CV8 16.000 · CV14 11.111 · V18 10.000 · CV5 6.700 · CV13 1.000
  (Mandelli). `[deducido]` W8 = "V16C Vástago Sacafuente 5,2×100" y V18 = "V18C Vástago Pisapapas",
  apareados por kg/uni (0,0305 y 0,01437), no por código. `[deducido]` CV5 6.700 desentona (la planilla
  tiene kg/uni 0,22 en esa fila, 57× el real): posible error de planilla, cargado tal cual.
  Sin componente en GP2: V17C Cremallera Doble Aleta (Bella Vista 16.632; GP2 tiene E13 de "Importado"),
  Tornillos Corta Queso (Suipacha, de baja) y Rem. Tapón Hierro (12.000).
- `[usuario 2026-09-28: "Manda la planilla"]` **Cartón aplicado**: la tirada del pliego depende de la
  marca. Sin tocar código: `carton_formato` nuevo **`Huevo LK`** (25 posiciones, múltiplo 12.000, mín.
  por código 1.000 `[deducido]`), **`8` pasa a 12.000** (es la corbata de 30 posiciones LOEKE; `Corbata`
  queda CHEF en 30.000), **`Manga` 12.000**. Formatos movidos según la planilla, cruzando POR ARTÍCULO
  (el código de estante se repite en la planilla: F4A, Q7C, Q5D, O2C, N2A figuran dos veces con
  artículos distintos): G4A/G4B/G4C C→Huevo LK; C2A/C2B/L4B/CART590 Huevo→8; M1/M2A/M2C/M3A/M3B
  Corbata→8; M2B LOKE→8; Q3D 8→Corbata; P4A/Q5 LOKE→Corbata; Q5D/O2C/N2A LOKE→Huevo; T3A C→LOKE;
  G8C1 (sin formato)→LOKE; G2A LOKE→C Resto; A1B2 (sin formato)→C Resto; Ñ4A/P6A ("Pelador", 12
  posiciones) LOKE→C Pelapapas. Tapones F4A1/F4B1/F4C (18.000) y Q4B/K1A (25.000) van como familias
  aparte `[Thomas 2026-09-28: "Sí"]`: formatos `Huevo LK Tapon` y `Huevo LK 25` (un formato = un
  múltiplo; la categoría no cambia el múltiplo). **Quedó sin aplicar**: BANDITA/BANDITAM y P2A
  (la planilla tiene "Rallador" y "Bandita" cruzados); CCG6B del 760 (tipo C LOEKE en un artículo CH).
  Sin formato siguen G8C, A1B, A1B1. Familias resultantes en `oc_bundle`: 8 LOEKE 18 · C LOEKE 41 ·
  C CHEF 4 · Corbata CHEF 10 · Huevo CHEF 20 · Huevo LK 21 · LOKE CHEF 23 · LOKE LOEKE 8.
- **⚠ Corrección del dueño (2026-09-29): "En cartones los mínimos son por cartón, aunque estén
  agrupados por familia."** El "Pedi Min Uni" de la planilla NO es la tirada de la familia (como leí el
  28/09): es el **mínimo de cada cartón**. Cargado en `componente.pedido_minimo_uni` para **129 cartones**,
  cruzado por artículo (12.000 ×71 · 16.000 ×25 · 25.000 ×19 · 30.000 ×10 · 18.000 ×3 · 24.000 ×1); 28
  cartones sin fila en la planilla quedan sin mínimo. La O.C. lo muestra bajo Pedir como en los demás
  sectores ("mín. proveedor N uni", rojo si corto) y **no frena**. Los formatos por marca (`Huevo LK`,
  `8` 12.000, `Huevo LK Tapon`, `Huevo LK 25`) quedan: sirven para agrupar y para el redondeo de
  "Sugerir", pero ya no son "el mínimo". `[Thomas 2026-09-29: "quiero que en la o.c. me separes por
  familia"]` → la tabla de cartones va con un renglón de título por familia (formato + marca +
  categoría), `OC_GP2.html` v1.42.0.
- `[Thomas 2026-09-29: "Seguimos con plásticos… Ahora sí el mínimo va por familia, no por parte. Es decir:
  entre todos los pirolos tengo que llegar a 36000. Separame por familia al igual que los cartones"]`
  **Plástico — familia de pedido = matriz del inyector.** Nueva tabla `GP2.familia_pedido` (30 familias,
  de la columna "Descripcion Matriz" de la planilla) y `componente.familia_pedido` en 49 piezas. El mínimo
  es de la familia (`familia_pedido.pedido_minimo_uni`); `componente.pedido_minimo_uni` por pieza queda
  pero la O.C. no lo muestra cuando hay familia. `oc_bundle` manda `familia_pedido` y `familia_minimo`;
  la O.C. (v1.43.0) agrupa el sector Plástico por familia con título "Pirolos · 3 piezas · mín. familia
  36.000 uni · pedido N uni", rojo si no llega; no frena.
  **Qué parte de la planilla es qué en GP2**: lo que se COMPRA es la variante sin serigrafía / sin calar:
  PA10→PA10B, PA13→PA13B, PA18→PA18B, PA4→PA4B (+PA5B Chef), PC1A/PC1B (calados) → PC2/PC3B (sin calar,
  36.000), PC15→PC15AB (+PC15B), PB8→PB8A, PB7→PB8B, PEP4A/PEP4B→PEP4, PA9=A11 Capuchón Mariposa. Las
  serigrafiadas/caladas (PA10, PA13, PA18, PA4, PA5, PC1A, PC1B, PC15A, PEP3) son `estado_compra=fabricacion`
  y no van a la O.C. `[deducido]` PB5 (manguito negro) en "Manguitos Abrelata" y PA5B en "Mango Cuchillo
  Untar" por matriz común. Familias con más de una pieza: Pirolos (PA7A/PA7B/PA12, 36.000), Bujes
  (PA8A/PA8B, 33.000), Mango Pelador 505/123 (PC2/PC3B, 36.000), Manguitos Abrelata (PC13/PC14/PB5, 19.200),
  Capuchones (PA10B/PA13B/PA18B, 10.000), Mango Tellería (PEP1/PEP2, 10.000), Mango Cuchillo Untar
  (PA4B/PA5B, 10.000), Plaquitas (PA1/PA2, 6.000), Mangos LK (PA17/PC10/PC11, 6.000), Insertos
  (PB6/PB8B/PEST2/PEST1, 2.000 — `[Thomas 2026-09-29: "los insertos son todos una familia. El único que
  tiene un mín aparte es el inserto canelón que es 5000. Resto 2000"]`; PEST1 es de Kollplast y aun así
  suma con los de Pat Bet Plast), Cuerpo Sacacorcho Plast (PC15AB/PC15B, 2.000), Espátulas (PV3/PV7, 1.500),
  Cucharas Calada y Fideos (PV5/PV6, 1.500), Corta Torta (PV8/PV8B, 1.500). El resto son de una pieza.
  **No están en GP2** (8): PA15 Capuchón ф10, PA16 Mangos ф10 LK, PB1 Cilindro Corta Queso (12.000),
  PEP6 Cabo Madera 525, CP7 Mangos Corta Queso, CP5 Afila Caladas Blanco, HP2 Inserto Cuch y Pal, FP3
  (sin descripción, "Manolo"). Sin familia (no son matriz): Maspoli PC12/PEP7/PEP8 (500), Pintos PEP5,
  consumibles PCP2/PCP3/PCP4A, ruedas PIEA/PIEB → en la O.C. van bajo un solo título "Otros", ordenadas por proveedor (v1.44.1;
  `[Thomas: "La sección de otros solo en plásticos y agrupámela por proveedor. Cartones está bien así"]`).
  `[Thomas 2026-09-29: "el mín es en kg en este caso, creo que siempre los mín es la unidad de medida que
  aparece en el remito de recepción y en la columna de la orden de compra"]` **El mínimo se lee en la
  unidad de la O.C.**: la planilla lo da en la unidad del remito (los bloques de Facciolo y Galvanoquímica
  dicen "Pedi Min KG"; cartón, remache, bombilla y el resto del plástico "Uni"). En la base
  `pedido_minimo_uni` sigue en la unidad canónica de la pieza (uni o kg): Clavo 505 PCP3 = 1.000 kg =
  153.139 uni (kg_x_uni 0,00653); Plancha de Níquel PCP2 = 10 kg (canónica kg). La O.C. muestra
  "mín. pedido 1.000 kg (= 153.139 uni)" / "48 paq 250 (= 12.000 uni)".
  `[Thomas 2026-09-29: "Las tres cosas de Tellería y la de Rodar mandalo a Rafael Pettofrezza"]` La planilla
  pone PB2, PEP1 y PEP2 bajo "Tellería" y PA4 bajo "Rodar", que no existen como proveedor de insumo en GP2:
  las cuatro quedan en **Pettofrezza Rafael** (PEP2 cambió de Pat Bet Plast; las otras tres ya estaban).
  Con eso la familia "Mango Tellería" (PEP1/PEP2) es de un solo proveedor. `[Thomas 2026-09-29: "Las dos de Pat Bet Plast mandalas a
  Pat Bet Plast"]` PA8A/PA8B (Bujes) y PEST1 pasan de Kollplast a **Pat Bet Plast**, como la planilla. Con
  esto todas las familias son de un solo proveedor y Kollplast no tiene piezas plásticas en GP2.
  `[Thomas 2026-09-29: "Por qué no veo el mínimo? Estoy viendo que en el relevamiento aparece"]` Los mínimos
  por pieza del plástico sin familia también se cargaron: Maspoli PC12/PEP7/PEP8 = 500 uni (era lo único que
  faltaba; PIEA rueda de Barbetta no tiene mínimo en la planilla). `[Thomas 2026-09-29: "A estos dos no les pongas
  mínimo"]` Las ruedas PIEA/PIEB de Barbetta quedan **sin mínimo** (PIEB tenía 1, sacado).
  `[Thomas 2026-09-29: "Chequeá que no se te haya escapado alguno"]` Barrido de TODO lo comprable sin mínimo
  ni familia contra las 5 planillas: se habían escapado **dos**: la Bolsa Filtro Café LK (A1B, art. 031,
  Vihal) con mínimo 55.000 uni y el piso de **Simco** (Santoprene) de 25 kg (`proveedor_insumo.pedido_minimo_kg`;
  la planilla lo escribe "Simko"). Cargados. Lo demás sin mínimo no tiene dato en las planillas: flejes,
  cajas y alambre (sin planilla), 24 cartones que no figuran (515, 510, 059, 186, 500, 715, 867, 355, 101,
  103, 108, 114, 115, 116, 121, 123, 104, 708, 909, banditas, bolsas 120 y 836), BOM8B, Z21, PIEA, garage
  (la planilla no tiene columna de mínimo) y CV18D/EST1/EST2 (ya avisados). Las etiquetas de Cía Integral
  (C3A/H4C/T4A 10.000) no son componentes GP2.
  Las familias salen de la columna **"Descripcion Matriz"** de la planilla `[Thomas 2026-09-29: "Sacaste
  las familias de la columna descripcion matriz no?"]`, con nombres normalizados (Regatones → Pirolos).
- **v1.39.0** [usuario] Thomas: *"entre columna y columna veo espacios"* + *"si no cumple con el mínimo que aparezca igual pero con color rojo y negrita"*. Causa de los huecos: `table.t{width:100%}` de `gp2-modulo.css` le ganaba en especificidad a `.t-insumos{width:auto}` (y en los tests no se veía porque el CSS está stubeado). Ahora `table.t.t-insumos{width:auto}` y el `.table-wrap` abraza la tabla. "mín. proveedor" en rojo y negrita cuando lo pedido queda por debajo; vacío no se marca.
- **v1.40.0** [usuario] Thomas: *"quiero que esté todo centrado y sin tanto blanco. Si es necesario poné proveedores sobrantes abajo"*. La tarjeta de OC mide lo que mide la tabla (`.card{width:fit-content}`, piso 720px para cuando no hay tabla), todo centrado, y la botonera de proveedores baja de renglón al lado de su etiqueta en vez de ensanchar la página (`contain:inline-size` en los filtros: no cuentan para el ancho).
- **v1.40.1** [usuario] Thomas: *"todo esto alineación a la izquierda"*: dentro de la tarjeta, botones Generar/Órdenes, filtros, cartel del proveedor, buscador y Crear OC van a la **izquierda**. La tarjeta sigue centrada en la página y del ancho de la tabla.

## 4gq. El maestro de empleados es `planify.employees` (lo gestiona RRHH); la letra del legajo es la empresa (2026-09-29)

- [usuario] Elías Irace: *"que el de planify sea el que se usa (lo gestiona RRHH); el que usábamos era manual"*. La lista
  de operarios de la app nueva de registro de producción (repo `GP2-Registro-Produccion`) sale de
  `planify.employees`, **no** de `public."Empleados"` (cargada a mano, queda desactualizada).
- [usuario] *"el c es porque pertenece a otra empresa; para diferenciar los legajos se le puso una letra adelante"*.
  → **El legajo es texto y la letra es parte de la clave.** El número solo NO identifica a nadie.
- [dato, consulta 29/09] Colisiones reales: `29` = Viviana Gauna y `c29` = Nora Heredia; `122` = Adrián Villalba
  y `C122` = Martín Castillo (baja). Hay `c` y `C` mezcladas (normalizar a minúscula al comparar).
  `public."Empleados"` guarda `94` para quien en Planify es `c94` (perdió la letra).
- [dato] De 35 activos en `Empleados`: 29 están en Planify; los 6 que faltan y los 6 que Planify tiene de baja
  **no cargaron producción en los últimos 30 días** → RRHH tiene razón; pasar a Planify no deja afuera a nadie activo.
- [dato] `planify.employees.tipo` dice "administrativo" también para operarios de la otra empresa (ej. c19
  Eduardo): no sirve para saber quién es operario. Los permisos de botones (`es_piedra`, `ve_cm`, …) y
  `hora_entrada` de producción solo existen en `Empleados` → hay que llevarlos a una tabla GP2 atada al
  `planify.employees.id` (no al legajo).
- [usuario 29/09] *"de planify es para utilizar los legajos y filtrando por operario"* + *"la letra es parte del
  legajo"*. El operario tipea el legajo completo (`c94`). Como el teclado del celular es numérico por regla, la
  pantalla de legajo lleva un **teclado propio en pantalla (0-9 + C)**, con botones grandes. `login-operario` hoy
  valida contra `public."Empleados"`: cambiar a `planify.employees` activo y de tipo operario.
- [usuario 29/09, captura de Planify] **Planify SÍ clasifica**: el campo es `planify.empleados_liquidacion.tipo_empleado`
  (Planta / Administrativo / Pasante / sin especificar), NO `planify.employees.tipo` (ese dice "administrativo" para
  los 56 y no sirve). **Operario = `tipo_empleado='planta'` y activo**, unido por `employee_id`.
- [dato 29/09] 19 de planta activos. Todos los que cargaron producción en 30 días son planta, salvo **261 Jennifer
  Muñoz** (sin tipo; 1 solo registro) y **504 Melany Pierola**, que tiene DOS filas activas de liquidación (una
  administrativo y otra planta). La empresa también está ahí (`empresa`): `c` = **CHEF SRL**, sin letra =
  **Loekemeyer SRL**, 50x = **Agencia**.
- [usuario 29/09] El legajo **600** es un caso especial para pruebas (carga en Virgilio): no es un empleado.
- ⚠ `empleados_liquidacion` es la tabla de SUELDOS (CBU, CUIL, banco). La app de operarios nunca la lee directo:
  una función `SECURITY DEFINER` que devuelva solo legajo, nombre y si es planta.
- [dato 29/09] La producción histórica guarda el legajo **sin la letra** (`94`, `104`, `8`, `19`, `92`): al migrar,
  mapear número→legajo con letra usando Planify, y ojo con 29/c29 y 122/C122.
- [dato 29/09] El horario del operario está en `empleados_liquidacion.horario_laboral` (texto "08:30 a 17:30", los
  19 de planta lo tienen); `planify.employees.hora_entrada` está VACÍO para todos ellos. `GP2.operario_por_legajo`
  devuelve entrada y salida parseadas de ahí. Ej.: 501 Graciela Santillán entra 07:00 (hoy la app la mide desde 08:30).
- [dato 29/09] **Planta NO alcanza para decir "operario de producción"**: Martín Pregelj (203, Técnico) y Martín
  Cornejo (c91, Oficial) son planta y [usuario] *"no son operarios pero también están en la app"*. Tampoco sirve la
  categoría (74 Omar Bachur es "Chofer de Carga" y carga producción). Falta un permiso propio "registra producción".

## 4gr. Registro de producción (app nueva): decisiones del dueño (2026-09-29)

Contexto: app unificada `GP2-Registro-Produccion`, se arranca por Cervantes. Tabla completa en
`docs/INVENTARIO-FUNCIONES.md` §7.3 de ese repo.
- [usuario] **Llegada tarde**: con el horario de Planify de cada operario, no 08:30 fijo.
- [usuario] **PM (paro de matriz)**: igual que Registro Producción = tiempo muerto con duración, + aviso WhatsApp al
  abrirlo (existe: `app.js` → `send-whatsapp`, plantilla `problemas_en_matriz_reducido`, permitida en v55).
- [usuario] **CM (cambiar matriz)**: *"solo personas específicas + matricería + alimentador lo hacen, no el operario
  común"* → quien hace CM NO es quien produce con esa matriz: CM asigna matriz↔balancín y **no** deja la matriz activa
  para el que la cambió.
- [usuario] **RM**: igual que hoy (cierra el cajón como completo y pasa a CM) + aviso WhatsApp "Rompió Matriz".
- [usuario] **Deshacer / editar**: va en el **admin**, no en la app del operario. [usuario] *"el admin es gestión productiva 2"*: el panel admin del registro de producción (habilitar "pendiente de pesar", cargar pesos, editar/deshacer) es una pantalla de **este repo** (GP2), no de Registro-Produccion-2.0. [usuario, aclaración] *"el de Cervantes a Gestión Productiva 2.0, el admin; el de Virgilio en Gestión Virgilio"*: el admin/maestro de producción de **Cervantes** (ver y corregir el día, pesos, deshacer) se **muda a GP2**; el de **Virgilio** queda en **Gestión Virgilio**. Registro-Produccion-2.0 deja de tener maestro.
- [usuario] **Terminar día con TM abierto**: se cierra solo (hoy ya lo hace: `app.js` `confirmarTerminarDia`, paso 2).
- [usuario] **Seguir cajón al día siguiente**: se mantiene; el código de Logística (hoy `151515` escrito en `app.js`,
  repo público) pasa a ser un **secreto en la base**, validado del lado del servidor.
- [usuario] **Rollos**: los maneja el **alimentador** (Eduardo c19 lo es), distinto de un balancín común → permiso de
  rol, no `legajo === "19"`.
- [usuario] **Turnos después de medianoche**: no hay. Cerrar lo abierto al terminar el día cierra los TIEMPOS MUERTOS,
  no el cajón marcado "sigo mañana" (no se pisa con lo anterior).
- [usuario] **WhatsApp**: los que ya están en las funciones (matriz sin tiempo, paro, rotura).
- [usuario] **Botones**: los de Registro Producción (`capsDe`/`botonVisible` + flags), incluidos RD, REM, MM, TRM, TL, PCM.
- [usuario] **Cajón**: *"toma como matriz de uni las que tienen salida de 1 unidad x golpe"* → `GP2.matriz.carga_en`:
  `golpes` solo si `uni_x_golpe > 1` (18 matrices: 7, 14, 15, 16, 20, 21, 22, 29, 40, 60, 64, 66, 71, 72, 116, 344,
  348, S/N), `unidades` el resto (388), `kg` la piedra 501.
- [usuario] **Piedra (501) es por KG**: el operario tipea con coma o con punto y las dos valen como decimal. [dato] RP
  hoy guarda el crudo con coma ("5,72") y el espejo como número (`db_n8n_espejo."Uni"` es `real`: 5.72). En la base
  nueva va **numérico** (sin coma ni punto: es un número). Ojo con la regla GP2N (punto = miles): en el campo de kg
  el punto es DECIMAL (valores < 1000). [dato] Hay cajones de 501 con "0" / "00" kg.
- [usuario] Los 0 kg de piedra (legajo 245, 22–28/09) fueron **por un problema en la fábrica: en ese lapso se pesaba lo
  hecho al día siguiente**. El 233 cargó 5,6 fijo porque **pesaba antes** (su dato es válido). [dato] Los pesos del día
  siguiente nunca volvieron a la base: esos cajones quedaron en 0.
- [usuario] **Opción "pendiente de pesar"** en la app nueva: el operario marca el cajón de piedra sin peso; el peso real
  se carga después en el admin y queda en el cajón original (su día y su tiempo), con aviso si pasa un día sin pesar.
  **Solo aparece si el admin la habilita en el panel admin** (apagada por defecto; la base rechaza un "pendiente" si
  está apagada, no solo la pantalla).
- [usuario Elías 29/09] **Casilla "registra producción" = OK.** Entra a la app de producción quien: **activo en Planify
  (alta) + planta + casilla prendida**. Tabla `GP2.operario` (una fila por `planify.employees.id`), la maneja el admin GP2.
  [dato] Carga inicial: 15 prendidos (los que cargaron en 90 días + **Alberto Práctico, prendido por decisión del
  dueño**), 4 apagados: Pregelj 203 (Técnico 3º), Cornejo c91 (Oficial), Pages 2 (Chofer de Carga), González 191
  (Logística). La categoría NO sirve de filtro: Cornejo y Farías (c8, 4.035 registros) son los dos "Oficial"; Bachur
  (74, 807 registros) y Pages son los dos "Chofer de Carga".
- [dato 29/09] Planify tiene 14 inactivos y los 14 tienen también la ficha de liquidación de baja (coinciden); ninguno
  cargó producción en 30 días. El que se da de baja en Planify queda afuera solo (`operario_por_legajo` exige activo).
- **CORRECCIÓN (mismo día)** [usuario Elías]: *"que queden habilitados"* — la casilla se dio vuelta: **entra todo
  activo + planta**; `GP2.operario.registra_produccion = false` es la excepción (sin fila = habilitado, así el alta
  nueva de RRHH entra sola). Los 19 quedaron habilitados. [dato, `public."Empleados"`] **Pregelj (203) y Cornejo (91)
  son los 2 de matricería** de Registro Producción 2.0 (TRM, REM, CM; Cornejo también TL): no son operarios de
  balancín pero SÍ usan la app con los botones de matricería. Lo que dije de "planta no alcanza" era falso.
- [dato] En `public."Empleados"` el legajo **1 = "Pruebas"**; en Planify el 1 es **Alberto Práctico**. Los 2 registros
  del "1" pueden ser pruebas, no de él. Otra colisión a tener en cuenta al migrar.
- [usuario Elías] **Estos cambios son para GP2-Registro-Produccion**: Registro Producción 2.0 (la app en uso) no se toca
  (ej.: deja entrar legajos de baja porque no mira `Activo`; eso se corrige en la app nueva, no en la vieja).
- [dato 29/09] **Permisos de botones migrados a `GP2.operario`** (una sola vez, desde `public."Empleados"`, casando el
  número con el legajo de Planify activo + planta): es_matriceria, es_piedra, es_alimentador, ve_cm, ve_trm, ve_tl,
  ve_rem, ve_mm. 7 con algún flag: matricería 203 y c91; piedra 233 (+CM +MM), 245, c92; alimentador c19 (+CM);
  282 con CM. `ve_ctm`/`ve_am` (Oscar Bordon) NO se migraron: no tienen código en ninguna app. 260 Valdés tenía
  piedra pero está de baja. `GP2.operario_por_legajo` devuelve `permisos` (jsonb) para la sesión del operario.
- [dato 29/09] **Matriz con variante vs matriz con varias piezas** (pregunta de Elías "¿por qué se ve diferente una
  bifurcada?"): son dos cosas. (1) *Variante* = otra matriz con letra (12/12B/12C; 39 en `GP2.matriz`, 40 en public
  —falta **325C** en GP2—): RP 2.0 pide el número base y abre un cartel "Seleccioná el tipo" (8 con etiquetas escritas
  en `app.js`: 10, 12, 28, 39, 79, 80, 81, 127; el resto las detecta de la base); la app GP2 muestra cada variante como
  otra tarjeta. (2) *Varias salidas* = la MISMA matriz saca piezas distintas (28: A15 del fleje 94 y J2/J5 del 13):
  solo GP2 lo sabe (`matriz_salidas`) y pide "Fabricás …" para que el stock vaya a la pieza correcta.
- [dato 29/09] **67 matrices usadas en 90 días no están en ninguna ruta de GP2**; 63 son tareas de mano de obra
  (envasar, reenvasar, armar importados, sacar film) sin Causa-Efecto tampoco en la base vieja. [usuario Elías]
  *"Fábrica sí tiene que estar porque se hacen en fábrica"*: deben figurar en la ruta del artículo como paso del
  tallerista **"Fábrica"** (`GP2.tallerista` id 3). **CORRECCIÓN mismo día** [Elías, sobre el PDF]: *"Fábrica" queda
  como tallerista, está bien así* — el "tallerista es un 3ro" vale para los demás; Fábrica es el interno y NO es un
  error de modelo (retirado el punto 7 del informe). Falta decidir cómo se asocia la matriz al paso de Fábrica
  (hoy los pasos de tallerista no llevan `matriz_id`). Listado: `PROBLEMAS_MATRICES_2026-09-29.md` (+ `.pdf`).
- [usuario Elías 29/09, verificado en la app] **La 28B está en GP2 como matriz 28 + pieza J5** (la 28 ofrece A15, J2, J5):
  GP2 reemplazó la variante con letra por la elección de pieza. Para la app nueva hace falta un mapeo
  variante → (matriz base, pieza). ⚠ Conflicto de nombres a resolver: RP 2.0 dice 28B = Cromar (JF5); GP2 dice
  J5 = "Cuerpo Uña s/M p/Pintar".
- [usuario Elías 29/09] **"LK" en el cartel de la 12 = Loekemeyer.** [dato, rutas GP2 + Causa-Efecto] Qué artículo sale de
  cada variante de la 12 (Doblado Mango Plano):
  12 (Loekemeyer) → I6 Mango Plano 502 doblado → abrelatas mariposa 066, 502, 512 (LOEKE);
  12B → G13 Mango Plano 501 doblado p/pintar → abrelatas a manija 101 y 501;
  12C (Chef) → I11 Mango Plano 701 doblado c/marca → abrelatas a manija 701 (CHEF).
  Los rótulos del cartel de RP 2.0 están BIEN. Lo que está mal: la descripción de la 12 en Causa-Efecto dice
  "(Chef Marip)" y GP2 pone I11 (701 Chef) como pieza de la **matriz 12** en vez de la **12C**.
- [dato 29/09, CORRECCIÓN del análisis de matrices] **GP2 = 115 matrices originales (Excel del dueño, con tipo; 107 con ruta)
  + 292 de catálogo (22/09, §4fa, sin tipo ni ruta a propósito).** Las variantes con letra están todas en el catálogo
  (salvo 12B, que tiene ruta): el Excel original modela esos casos como PIEZA de la matriz base. No confundir "sin ruta"
  o "sin tipo" de las de catálogo con un error de GP2. Errores reales: 138 tipo A con máquina balancín; 129/130/131 con
  ruta y sin tipo; 9 matrices con tiempo en la vieja y vacío en GP2 (182, 21, 325B, 361, 509, 512, 62, 63, 64).
  Informe: `PROBLEMAS_MATRICES_2026-09-29.md` (versión 2).
- [usuario Elías 29/09] **Matriz 28: GP2 está bien.** *"Cambió y ya no se croma; se compra el fleje inox para ese"* → la
  versión cromada es A15 (fleje inox). La 28B "p/Cromar" de la base vieja quedó vieja. [dato] Igual en Registro
  Producción 2.0 se siguió cargando 28B hasta el 01/09 (22 cajones, 34.460 u.): el cartel ofrece "Cromar (JF5)".
- [dato 29/09] **114A / 114B → sacacorcho doble aleta 523 (LOEKE) y 723 (CHEF).** Cadena en GP2: Fleje IC2 → 116 Corte
  Aleta (L11 izq / L12 der) → **114** Doblado (L9 / L10) → 221 Estampado (D3 / D2) → Pettofrezza → 523/723. La vieja
  hace lo mismo con 114A (izq) y 114B (der). En un año solo se cargó la 114 (28 cajones); 114A/114B nunca.

## 4gs. La materia prima que corta un PS no tiene consumo propio: su máximo sale del máximo de las piezas (2026-09-28)

- [usuario] *"Tiene que mandarse según máximos de sector de alambres y descorazonador. Es decir, si
  tengo que tener 10 alambres y eso equivale a 0.1 de fleje hay que mandarle eso"* + *"calcula el
  maximo segun los meses del sector x consumo de articulo"* + *"y agrega el maximo en la o.c."*.
- **Regla**: `maximo_mp (kg, en la ubicación del PS) = Σ maximo_pieza × kg_x_uni_pieza / (1 − desperdicio_pct del PS)`.
  `maximo_pieza` = el máximo de la pieza en su sector; si está vacío, consumo (Est Madre) × `meses_stock`
  del sector. Función `recalcular_maximo_mp_ps()`, origen `maximo_origen='derivado_pieza'`; la corre
  `fn_recalc_maximos_diferido` DESPUÉS de insumos/talleristas. Aplica a todo paso de PS con entrada en kg
  y salida contada: hoy FLEJE90_BRUTO → Charcas → IC3/IC3V y CHAPA430 → Eclipse → Z31.
- [dato] Al 2026-09-28: **FLEJE90_BRUTO 1.028,07 kg** (IC3 113.208 × 0,0083 + IC3V 6.600 × 0,0134, Charcas
  sin desperdicio) y **CHAPA430 3,31 kg** (Z31 402 × 0,0049 / (1 − 40,28 %), con 402 = consumo × 1 mes de
  Procesado porque Z31 no tiene máximo). La O.C. los muestra solos: `oc_bundle` ya leía el máximo de la
  ubicación del PS, que estaba en 0.
- **Las rutas de IC3/IC3V (art 120, 031, 836, 867, 034) arrancan en FLEJE90_BRUTO**, igual que la de chapa
  (antes arrancaban en IC3 y el bruto no aparecía en el despiece). El título "Fleje" de la ruta
  (`despiece_verif_bundle` / `programa_bundle`) acepta también el sector 13 (Alambre, único componente:
  FLEJE90_BRUTO). Las rutas confirmadas de esos 5 artículos cambian de firma: hay que reconfirmarlas.
- **`v_nivel_stock`**: solo el fleje que se PESA (sector 5 con `unidad_medida='kg'`) va por kg/mes. IC3/IC3V
  son sector 5 pero en unidades y daban `max_calc` 0 (misma regla que ya tenía `tablet_bundle`). Efecto:
  IC3V pasó de vacío a 6.600 y **IC3 de 100.800 (`migrado_de_minimo`) a 113.208 (`est_madre`)**. Ningún
  otro máximo ni consumo se movió (firma md5 de inventario/consumos/niveles igual antes y después).
- ⚠ [dato] **Sigue mal el CONSUMO en kg de estas materias primas** (no el máximo): `v_consumo_fleje_kg` da
  388 kg/mes de CHAPA430 (1 kg por descorazonador; real ≈ 3,3) y `v_consumo_componente` da 19.968 "uni"
  de FLEJE90_BRUTO. Hoy no pesa: la O.C. usa el máximo y no muestra el consumo, y la Tablet deja afuera
  a los PS híbridos. Si algo empieza a leer ese consumo, corregirlo primero.
- [dato] La ruta del art 709 arranca en Z31 (insumo) sin la chapa: su descorazonador no cuenta chapa.
- [usuario Elías 29/09] **La 10B no existe: la varilla con cuchilla curva (H15) es la matriz 174** "Armado de Varilla
  Curva C/Cuchilla" (8,5 s, ya tenía ruta → H15). **Se eliminó la 10B de `GP2.matriz`** (id 409; sin producción ni
  rutas en GP2; queda su fila histórica en `matriz_racha`). En la base vieja 10B tuvo 1 cajón en el año (17/07, 385 u.)
  y el cartel de Registro Producción 2.0 todavía la ofrece como "Varilla c/ Cuchilla Curva": en la app nueva, la
  varilla curva va a la 174.
- [usuario Elías 29/09, "sí y sí"] **La 10B se borró también de la base vieja**: `public."Matrices"` (id 374, queda en
  `Matrices_audit`) y `public."UnixCajon_Stock_Registro_Prod_Cerv"`. Causa-Efecto no tenía fila de la 10B. Registro
  Producción 2.0 **v1.9.1** (commit 47618cf): el cartel de la 10 "Varilla c/ Cuchilla Curva" ahora registra la **174**.
  Excepción puntual a la regla "public = solo lectura", pedida por Elías.
- [usuario Elías 29/09] **349: el disco del pisapapas ya sale calado en el primer corte** (349 → M2). La 123 "Perfora
  disco" de la base vieja ya no va: la ruta de GP2 está bien.
- [usuario Elías 29/09] **Las aletas del sacacorcho doble aleta ahora son inox**, igual que el cuerpo uña de la 28. Se está
  cambiando en GP2 en otra sesión (GP2 está más actualizado que la vieja, pero puede tener errores): no tocar desde acá.
- [dato 29/09] **138 en GP2 = "Corte Grampa Batidor"** (Fleje N° 19 → W1B Grampa → Guazzaroni → Alex Escalante → Pedernera →
  batidores 515/615), tipo A pero máquina balancín, **9 s**. En la vieja el 138 es "Doblado Sacafuente" (B, 9 s). Sin
  producción en 2 años en ninguna. El 9 s lo copió la carga del 22/09 del vecino: [deducido] es el tiempo del doblado,
  no del corte (un corte en alimentador anda en ~1,5 s), y entra en el costo del batidor.
- [usuario Elías 29/09] **138 = alimentador.** Corregido `GP2.matriz.maquina` 'balancin' → 'alimentador' (tipo ya era A).
  El tiempo de 9 s sigue pendiente de medir/confirmar (sospecha: es el del doblado sacafuente de la vieja).
- [usuario 29/09] **103 y 510 se llaman "Abrelata Uña Inox"** (antes "Abrelatas Uña Cromado" / "Abrelata Uña Cromado").
  Cambiado `GP2.articulo.descripcion` (ids 12 y 32) y `GP2.uni_x_articulo_x_caja` id 57 (510, "ABRELATA UÑA INOX").
  El 103 no tenía fila en `uni_x_articulo_x_caja`.


## 4gt. Rompenueces, sacacorcho doble aleta y Art 66: correcciones de ruta del dueño (2026-09-29)

- [usuario 29/09] **Art 66: la matriz 10 NO va.** Ruta "Fleje 30 → Art 66" queda IE11 → M6 → M173 → **M174** → Jade
  (Z41) → IJUPA. Se borró el stock movimiento `H7-M10` (0 stock, 0 movimientos) y la receta de H15 pasó a H7-M173 × 1
  + I16 × 1. H15/Z41 bajaron $12,60 (los 6,3 s de M10). M10 sigue viva en las otras 10 rutas (501/701/101/502/512).
- [usuario 29/09] **G7/G8 son SOLO del 507; el 707 lleva G5 (Pieza Abierta Rompenuez S/M p/Pintar) y G6 (Pieza
  Cerrada Rompenuez S/M p/Pintar).** Rutas 47/48: M77 → G6 → Jade → B1; M74 → G5 → Jade → B2. G5/G6 = mismo peso y
  cajón que G7/G8 (0,0462 kg, 606 u) [usuario: "sí"]. G7 ya no pasa por Jade (fila de inventario borrada).
- [usuario 29/09] **Máximo de G5/G6/G7/G8 = consumo × meses_stock del sector** ("Consumo x maximo de meses por
  sector"), no 5 cajones. Nuevo `maximo_origen = 'consumo_meses'` (opt-in por fila, `recalcular_maximos_consumo_meses`,
  lo refresca `fn_recalc_maximos_diferido`; `recalcular_maximos_cajones` no lo pisa). Hoy Crudo tiene meses_stock = 1
  → G5/G6 = 30, G7/G8 = 456. ⚠ [deducido] con umbral de faltante = 1 cajón, G5/G6 figuran en faltante aun llenos.
  Migración: `db/migracion_maximo_consumo_meses.sql`.
- [usuario 29/09] **L9, L10, L11, L12 DESAPARECEN** (aletas del 523/723). Corrección del mismo día: primero se
  pasaron a Sector Movimiento con su código — mal, el dueño: *"desaparecen… los nuevos stocks movimientos llevan la
  descripción de stock movimiento que es componente tal tras matriz tal"*. Quedan **IC2-M116-I / -D** (Fleje N° 92 tras M116 (Izq/Der),
  ex L11/L12) e **IC2-M114-I / -D** (Fleje N° 92 tras M114 (Izq/Der), ex L9/L10). Izquierda y derecha van SEPARADAS
  con sufijo -I / -D [usuario: "sí", para no sumar el stock de las dos aletas]. Rutas 210/211 (izq) → D3, 212/213 (der) → D2. Borrados L9-L12 (stock
  0, sin movimientos ni recetas). D2 $114,19 → $114,92 y D3 $114,30 → $115,26: el material ahora sale del fleje (37,8 u/kg).
  **Convención del stock movimiento** [usuario]: código `<raíz>-M<matriz>`, descripción `<desc. raíz> tras M<matriz>`, sin
  kg ni cajón; la raíz es el fleje/crudo de origen y se mantiene a lo largo de la cadena.
- [usuario 29/09] **Las aletas del 523/723 NO se croman: son inox.** La ruta IC2 → M116 → M114 → M221 → D3/D2 sin
  proveedor de cromado es correcta; el "p/Cromar" de las viejas L9/L10 era un resto (esos códigos ya no existen).

## 4gq. Flejes: mínimos y proveedores del relevamiento "Conteo Gral FLEJES y Alambre" (2026-09-29)

`[Thomas 2026-09-29: "Te paso el de flejes para que compruebes ahora"]`. Hoja "Pedido Flejes", columna
"Ped Min KG", por número de fleje (`componente.descripcion` "Fleje N° X" en GP2).

- `[dato]` **Mínimo en kg por fleje, cargado en `componente.pedido_minimo_uni`** (los flejes son canónicos
  en kg): Basconia 500 (23 flejes), Aperam 300 (11) y 200 (fleje 95), Hermac 200 (5), Szapiro 150 (fleje
  46), Brawin 25 (5 varillas). Sin cargar: Altrak fleje 90 (la planilla dice 0), JL Metales fleje 55
  (dice 0,1: no se entiende) e IVBCM fleje 96 (no está en la planilla).
- `[Thomas 2026-09-29: "Fleje 59: HERMAC"]` Fleje **59** (IB7) pasa de Aperam a **Hermac** (mínimo 200 kg,
  como el resto de Hermac). Sin precio de Hermac cargado para ese fleje. Y un cruce de
  numeración: la planilla llama **95** al "Vást. C Pizza 60×2" de Aperam, y en GP2 el 95 es la
  "Varilla B Pera Larga Mini" de Brawin (IVBLM). Sin tocar hasta que el dueño diga.
- `[dato]` **39 flejes de la planilla no existen en GP2** (piezas de otros artículos: Estribo Bombilla 91,
  Arandela Chica Afila 11/12, C/Queso 78/80, Espiral Doble Aleta 47, Paleta Batidora 34, Ganchito 50
  de Estametal, Arandela Base 36, cuchara/espátula/cucharón/espumadera inox 43/44/45, PP Ajo 65/66/67,
  doble aleta 56/63/64/72, etc.). Los demás 50 coinciden en proveedor.
- Archivo: copia en el scratchpad de la sesión; el original lo tiene el dueño.



## 4gu. Máximos de sector = consumo × meses, también en Crudo y Procesado (2026-09-29)

- [usuario 29/09, textual] *"Chequeá los máximos de los sectores. Tendrían que ser el máximo del sector en meses x
  el consumo de sus artículos correspondientes"* → *"USÁ LA REGLA DE CONSUMO, NO DE 5 CAJONES"*. **Retira la regla de 5
  cajones (§2e).** Todo Sector Crudo y Sector Procesado pasa a `maximo_origen = 'consumo_meses'`
  (`recalcular_maximos_consumo_meses`, ya no es opt-in); `recalcular_maximos_cajones` quedó de nombre y delega en
  ella. Sin consumo → máximo NULL. Excepciones que no se pisan: `fisico` y `faat_reserva_lote`.
- [usuario 29/09] **Los máximos `fisico` de Caja (9) y Remache (11) se corrigen** ("CORREGÍ"): vuelven a
  `est_madre`. Esto **revierte** la nota de §2e-bis (02/09) de que V9 con 10.581 "era la planta y no se arreglaba":
  hoy V9 = 113.304, V5 = 68.008, A9 Caja N°22 = 32.346, A5 Caja N°6 = 240. Quedan `fisico` sólo los 4 de Plástico sin
  consumo (PCP4A, PCP2, PIEA, PIEB), las 13 de resina/MB (regla propia, §4dr) y RULETA.
- [usuario 29/09] **Y1** (Sector Afilado) también a consumo × meses: 43.946 → 44.068.
- [usuario 29/09] **Z12, C13, Z31** (Procesado, sin `uni_x_cajon`) ahora tienen máximo por consumo: 9.034 / 7.854 / 402 (sin tope de cajones hasta que se cargue `uni_x_cajon`).
- [usuario 29/09] **A9 "Cpo Mango Alambre Corta Queso Crom." (id 84) BORRADO: discontinuo.** Tenía 0 movimientos, 0
  recetas, 0 rutas. Se fueron con él 2 filas de inventario en 0 y su precio de cromado (Pedernera $4.757,70/kg, lista
  01/07/2026, `precio_servicio_pieza` id 1).
- [dato, `valorizacion_bundle`] **Máximo por sector: $947,3 M → $913,2 M.** Crudo $53,2 M → $38,5 M; Procesado
  $80,4 M → $59,4 M; Remache $20,1 M → $21,9 M; Caja $26,6 M → $26,3 M. En unidades: Crudo 871.397 → 439.599, Procesado
  782.380 → 407.174 (los dos tienen `meses_stock` = 1).
- [usuario 29/09, textual] **"El máximo de sector crudo y sector procesado no puede exceder los 5 cajones"** → el
  máximo es el MENOR entre consumo × meses y 5 × `uni_x_cajon` (`parametro.max_cajones_x_ubicacion`). 28 piezas se
  pasaban (D1 Espiral Sacacorcho: 21,4 cajones; H11, B13, Z23, H7, M6, M5, M10: 15-20). Sin `uni_x_cajon` no hay tope
  (Z12, C13, Z31). Con el tope, 31 piezas quedan con `ubicacion_corta` (el máximo no cubre 30 días): es la señal de que
  ahí hay que reponer más de una vez por mes. Máximo en uni: Crudo 310.535, Procesado 318.866; en $: Crudo $24,5 M,
  Procesado $39,7 M; **Máximo por sector total $879,4 M**. Migración `db/migracion_maximo_tope_cajones_faltante.sql`.
- [usuario 29/09, textual] **Faltante automático = stock menor al máximo** ("Menor al máximo"; antes < 1 cajón, que
  con máximos chicos marcaba faltante con el sector lleno). `faltante_cajones_umbral` quedó sin uso en la regla (el
  bundle lo sigue mandando). Hoy las 161 piezas figuran en faltante porque las 161 tienen stock 0 (sin conteo cargado).
  Faltantes v1.1.0: el cartel dice "bajo el máximo: faltan N uni".
- **Cómo se arma el consumo de un artículo que tiene "familia"** (`articulo_familia`, 19 pares) `[dato, v_consumo_demanda]`:
  cuando un artículo se vende con dos códigos (ej. **580 Batidor Mini** y **580E**), la venta del código secundario
  se SUMA a la del principal y la receta del principal consume por las dos: 580 vende 114/mes + 580E 588/mes → la
  receta del 580 consume por **702/mes**. El secundario no cuenta por separado (para no contarlo dos veces). Es la
  única diferencia entre "venta del artículo × receta" y el consumo que usa el máximo.
- Migración: `db/migracion_maximo_consumo_sectores.sql`.

## 4gv. El fleje bruto de Charcas se llama ALAMBRE (2026-09-29)

- [usuario] Thomas: *"En vez de fleje 90 bruto que se llame ALAMBRE"*. `GP2.componente` id 583: `codigo`
  `FLEJE90_BRUTO` → **`ALAMBRE`**. La descripción (`Fleje N° 90`) no se tocó.
- [dato] El código estaba fijo en 5 funciones (`control_ps_bundle`, `oc_bundle`, `cargar_recepcion_charcas`,
  `recalcular_maximo_mp_ps`, `fn_recalc_maximos_diferido`) y en 2 pantallas (Recepción Insumos, Entrega PS):
  se reemplazó en todas. Ninguna tabla lo guardaba como texto salvo `componente.codigo`.
  Las menciones a `FLEJE90_BRUTO` en docs anteriores a esta fecha se refieren a este mismo componente.
- [usuario] Thomas, mismo día: *"en vez de chapa 430, Fleje Descorazonador"*. `componente` id 595: `CHAPA430` /
  `Chapa 430` → **`FLEJE_DESCORAZONADOR` / `Fleje Descorazonador`** (Aperam → Eclipse). Reemplazado en 4 funciones
  (`cargar_recepcion_eclipse`, `recalcular_maximo_mp_ps`, `control_ps_bundle`, `fn_recalc_maximos_diferido`) y en
  Recepción Insumos / Entrega PS. El proceso de Eclipse sigue rotulado "Corte Chapa 430" en Entrega PS.
- [usuario] Thomas, mismo día, sobre Consumo (`ALAMBRE · Sector Alambre · 19.968 uni`): *"ES SECTOR FLEJE, NO
  ALAMBRE"*. `componente` 583 `sector_id` 13 → **5 (Sector Fleje)**. Era el único componente del sector 13, que queda
  vacío (no se borró: `sector.oc_rubro_id` 13→5 sigue para la OC). Stock intacto: su inventario vive en la ubicación
  de Resortes Charcas, no en una ubicación de sector. `despiece_verif_bundle` / `programa_bundle` ya aceptaban (5, 13).
- [dato] Esos 19.968 no eran alambre: eran las **piezas** cortadas (IC3 18.868 + IC3V 1.100/mes). Al pasar a Fleje la
  pantalla lo lee en kg de `v_consumo_fleje_kg`, que multiplicaba piezas × `kg_x_uni` **de la entrada** (1 en la
  materia prima a granel) → daba 19.968 kg. Se corrigió la vista: si la entrada es `kg` con `kg_x_uni = 1`, usa el
  `kg_x_uni` de la pieza que sale. ALAMBRE: **171,3 kg/mes**. Mismo pozo, caso hermano ya vivo:
  FLEJE_DESCORAZONADOR mostraba **388 kg/mes** y son **1,9** (Z31, 0,0049 kg). Los máximos no cambian: los dos son
  `derivado_pieza` (§4gs), no salen de esta vista.

## 4gw. Ralladores y Pelador Mgo Madera: importados que viven en Garage (2026-09-30)

- [usuario] Thomas, sobre Recepción Insumos → Importados: *"añadime acá: Ralladores, Pelador Mgo Madera. Ambos van a
  tener ubicación en garage"*. Se crearon `GRJ31` "Ralladores" (id 949) y `GRJ32` "Pelador Mgo Madera" (id 950):
  `sector_id` 9 (Garage), `proveedor='Importado'`, `estado_compra='importado'`, `remito_unidad='uni'`, e `inventario`
  en la ubicación 9 con cantidad 0. Cero código: el rubro Importados se arma por `estado_compra` (§ de arriba, "viva
  donde viva") y la recepción suma en la ubicación del sector de la pieza (`ubic_de('sector', 9)`). Códigos: siguiente
  libre de la serie GRJ; no se reusó `GRJ29` (borrado) ni `GRJ16` (Batidor Mini 580 en la base vieja).
- [dato] El control posterior va por `CONTROL_URL[9]` (Garage, en kg). Sin `kg_x_uni` la pantalla pide contarlas, igual
  que el resto de los GRJ sin peso.
- **Pendiente, sin receta** [deducido]: los Ralladores 321 (LOEKE) y 840 (CHEF) tienen receta de sólo caja A4 + cartón,
  sin el rallador en sí; `GRJ31` sería esa pieza ×1, pero no se cargó sin confirmación. "Pelador Mgo Madera" **no existe
  como artículo** en `GP2.articulo` (los peladores son de mango plástico o metálico). Sin receta no tienen consumo ni
  máximo: la OC no los sugiere.
- **Conflicto abierto** [usuario, mismo día]: *"ubicacion GRJ 23 y 24"*. Esos dos códigos **ya son** `GRJ23` Palo de
  Amasar 40cm (id 737, art. 232) y `GRJ24` Palo de Amasar 50cm (id 738, art. 233), de Tierra Nativa, vivos. No se
  pisaron: `codigo` no es único en la base y un código repetido rompe todo lo que busca por código. Queda en
  `GRJ31`/`GRJ32` hasta que el dueño diga si los palos se mueven de código o si es otra numeración.

## 4gz. GP2 ve el stock de insumos y el Mapa de Virgilio en tablas de SOLO LECTURA (2026-09-30)

- [usuario] Luis (D5): *"mete la tabla de solo lectura … me interesa que los dos tengan acceso a los datos y que puedan
  hablar, después vemos si hablan en chino o japonés"*. O sea: primero que se vean; el vínculo de códigos (D3) va después.
- Tres tablas en GP2 que llena Virgilio cada 10 min (`public.gv_gp2_espejo_sync`, cron `gv-gp2-espejo-sync`); GP2 sólo lee:
  - `virgilio_insumo_stock` — saldo de cada insumo de Virgilio por unidad (164 filas al 30/09).
  - `virgilio_insumo_ubicacion` — en qué posición del Mapa está cada insumo (149).
  - `virgilio_lugar` — el Mapa entero: góndolas y racks, empresa, uso y qué códigos tiene cada celda (943).
- Respeta la Regla 0: GP2 lee su propio schema. La copia se reescribe entera sólo si cambió algo (compara md5).
- Con 4gx (`ingreso_virgilio`) y 4gy (`aceptado_virgilio`) son las tablas por donde "hablan" las dos plantas.

## 4gy. Lo que Virgilio le ACEPTA a Cervantes queda en GP2.aceptado_virgilio (2026-09-30)

- [usuario] Luis: *"crea una tabla con los datos de lo que gestion virgilio le acepta a GP2 que los dos puedan leer"*.
- [dato] Fuente: las recepciones de insumos de Virgilio que vinieron de Cervantes (`recepcion_insumo`, ref Cervantes):
  24 al 30/09, **7 aceptadas** (ya con código real: N°44, 10, N° 43, N°94, 1060500, D4, N°41) y **17 con código
  temporal TMP-** (todavía nadie las identificó en Virgilio).
- La tabla vive en GP2 y la llena Virgilio (función `public.gv_gp2_aceptado_sync`, cada 10 min). GP2 sólo la lee.
- `componente_id` está vacío a propósito: el vínculo código de Virgilio ↔ `GP2.componente` no existe y no se adivina.
- Es el espejo de 4gx (`ingreso_virgilio`: lo que Virgilio le manda a Cervantes).

## 4gx. Lo que Virgilio manda a Cervantes aparece en la portada de GP2 (2026-09-30)

[usuario, Luis 30/09] *"Cuando Gestión Virgilio marca que se ingresa algo en Cervantes, tiene que figurar
un cartel grande en la página principal de GP2 que diga «VIRGILIO DICE QUE TE LLEGÓ ESTO [detalle],
CONFIRMALO Y UBICALO» (falta implementar confirmación y ubicación)"*.

- En Gestión Virgilio, la **recepción de importados** tiene el destino **«Cervantes»** primero en la lista
  (sobre todo insumos). Lo que va ahí **no entra al stock de Virgilio**.
- Queda una fila en **`GP2.ingreso_virgilio`** (`estado = 'pendiente'`): cantidad, unidad, código importado,
  código de insumo, descripción, proveedor, pedido, nota. La escribe `public.gv_imp_recibir` (del lado de
  Virgilio, SECURITY DEFINER). **GP2 no lee `public`**: el dato vive en su propio schema (Regla 0).
- `GP2_MODULOS.html` lo muestra en un cartel grande (`#avisoVirgilio`) mientras esté pendiente.
- Si Virgilio anula esa recepción, la fila pasa a `anulado` y el cartel deja de mostrarla. No se puede anular
  si Cervantes ya la confirmó.
- **Falta**: confirmar (pasa a `confirmado`) y ubicar (entra al `inventario` en su `ubicacion`, con
  `componente_id`). [dato] Hoy **no hay** vínculo entre el código importado/insumo de Virgilio (1000900,
  H201Part, 007) y el `componente` de GP2: ubicar exige ese mapeo primero.

## 4gz. El botón "Control" de la tablet es de TODO lo que se recibe, y sólo en Recibir (2026-09-30)

- [usuario] Nazareno: *"Cargué una recepción en recepción de insumos y no hice el control. Ahora voy a control y no
  me aparece"*. Y la regla: *"Me gustaría que aparezca en el botón de control que está a la izquierda del botón atrás
  … Tendrías que poner los de talleristas, p.s. y prov de insumo. Además quiero que este botón sea visible cuando estoy
  en el módulo recibir (lo que traen): si estoy en enviar no quiero que aparezca"*.
- [dato] El caso: E13, C13 (Sector Procesado) y GRJ31, GRJ32 (Garage), todos de Importado, `recepcion_insumo.controlado
  = false`. Su control vive en `control-remaches.html` (sector 2 + prov Importado, y sector 9), y a esa pantalla **sólo
  se llegaba por la redirección automática al guardar**: ningún menú ni botón la linkeaba. Saliendo sin controlar, la
  recepción quedaba huérfana (Recepción de Insumos sólo retoma flejes; el Control de la tablet sólo miraba P.S. y
  talleristas). Registrado en auditoría como bug.
- Cómo quedó: `control_entrega_bundle` manda `insumos_pend` (agrupado por sector + proveedor; flejes con `via='pesaje'`
  por `v_recepcion_control`), la lista "qué rubro se controla en qué página" se mudó a `gp2-control-insumo.js` (GP2CI,
  una sola copia para Recepción de Insumos, el Control y la tablet), el Control de la tablet muestra una tarjeta por
  grupo con "Controlar →", y el botón cuenta P.S. + talleristas + insumos y sólo aparece en Recibir.
- **Pendiente** [deducido]: los **cartones** que quedan sin controlar tampoco tienen dónde retomarse (su control vive
  adentro de Recepción de Insumos y la barra de pendientes sólo mira flejes). No se muestran en el Control porque no
  hay pantalla a la cual mandarlos; hace falta que Recepción de Insumos los retome.
