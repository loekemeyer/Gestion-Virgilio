# Matrices: GP2 contra Registro Producción 2.0 — versión 2 (29/09/2026)

Pedido de Elías Irace. **Esta versión reemplaza a la primera**, que tenía errores de lectura de GP2 (ver al final).
Uso = producción cargada en Cervantes (`public.db_n8n_espejo`) en los últimos **90 días**. Nada se corrigió todavía.

## Cómo está armado GP2 (sin esto, todo se lee mal)

- **407 matrices en dos grupos.** **115 originales**, del Excel del dueño: tienen tipo (A/B/D/P), máquina, tiempo, y **107 tienen ruta**.
  **292 de catálogo**, copiadas de la base vieja el **22/09 por pedido del dueño** (CONOCIMIENTO §4fa): solo N°, descripción y tiempo,
  para que el operario las pueda elegir. **No tienen tipo ni ruta a propósito.** No es un error de GP2.
- **En las 115 originales, una matriz que saca varias piezas pregunta cuál** ("¿Qué pieza vas a fabricar?", sale de las rutas).
  La base vieja, en cambio, separa esos casos en matrices con letra (3/3B, 28/28B…). Las matrices con letra entraron a GP2 recién el
  22/09, como catálogo: **por eso no tienen ruta**. Cargar 3 + pieza M9 en GP2 equivale a la 3B de la vieja.

## 1. Diferencias de pieza entre GP2 y la base vieja (hay que decidir cuál vale)

| Matriz | GP2 (rutas del Excel) | Base vieja (Causa-Efecto / nombres) |
|---|---|---|
| 12 / 12C | la **12** hace I6 (mariposa 502) **y I11** (701 Chef) | I11 la hace la **12C**; la 12 solo I6 |
| ~~28 / 28B~~ | **GP2 está bien** [Elías]: ya no se croma, se compra fleje inox → A15 | la vieja quedó con "28B p/Cromar". ⚠ En RP se siguió cargando 28B hasta el 01/09 (22 cajones, 34.460 u.) |
| ~~10 / 10B~~ | **RESUELTO 29/09** [Elías]: la varilla curva (H15) es la **174** "Armado de Varilla Curva C/Cuchilla", que ya hace H15 en GP2. La **10B se eliminó** de `GP2.matriz` | (error mío: sí existe H15) |
| 74 / 74A | 74 hace G7 e IE10-M74; **no hay G5** | 74A = Rompenuez **Abierta** → G5 |
| 114 | GP2 usa la **114** (L11→L9 izq, L12→L10 der) | la vieja: 114A (izq) y 114B (der). En el último año se cargó solo la **114** (28 cajones, 31.384 u.); 114A/B nunca |
| 221 | hace **D2 / D3** (aletas inox) | Causa-Efecto: 114A→**L9**, 114B→**L10**. [Elías] las aletas ahora son **inox**; se está actualizando en GP2 (no tocar desde acá) |
| ~~349~~ | **GP2 está bien** [Elías]: el disco ya sale calado en el primer corte (349 → M2); la 123 ya no va | la vieja: 349 → M3 → 123 perfora → M2 |

## 2. Error interno de GP2

- ~~**138**: tipo A con máquina balancín~~ → **corregido 29/09: alimentador** [Elías]. Queda: el tiempo de 9 s parece del doblado; la vieja la tiene como B. Además el nombre cambia de sentido:
  GP2 "Corte Grampa Batidor", vieja "Doblado Sacafuente".
- **129, 130 y 131** tienen ruta pero **no tienen tipo** (las otras 104 con ruta sí).

## 3. Variantes con letra: cuándo termina igual y cuándo no

Si se traduce la letra a "matriz base + pieza" (3B → 3 + M9):

- **Termina igual** (misma pieza, mismo tiempo, mismo factor): 3B, 12C, 28B, 74A, 79B, 80B, 81B, 114A, 114B.
- **No termina igual — tiempo propio**: **39B** 2,9 s (la 39: 1,8 s). (La 10B era un duplicado de la 174 y se eliminó.)
- **Sin tiempo**: 127B, 360B. (360/360B: el dueño pidió el 22/09 *"dejalas ambas así"*.)
- **12B** es la única con letra que tiene ruta propia (hace G13 → abrelatas a manija 101 y 501).
- **Solo con letra, sin pieza** (tareas de mano de obra, iguales en las dos bases): 101 B–E, 150B, 186B, 214B, 254B, 255B, 305B,
  309B, 310B, 325B, 340B, 342B, 394 B y C, 395B, 401B, 505 B–F. Falta en GP2 la **325C** (se usó el 25/09).
- **Pantalla**: Registro Producción 2.0 obliga a elegir la variante con un cartel; la app de GP2 la esconde si se escribe el número
  exacto (regla del 31/08).

## 4. Matrices donde solo GP2 pregunta pieza (en la vieja es un solo código)

| Matriz | Piezas | Nota |
|---|---|---|
| 27 Corte Cuerpo Uña Pie | I1, I9, J13 | la vieja también tiene 3 salidas |
| 33 Estampado 3 en 1 | J10 Loeke, J12 s/Marca | |
| 37 y 38 | fleje 22 / fleje 93 | la elección es del fleje (CONOCIMIENTO §2c-octies) |
| 78 Remachado Rompenuez | B1-M78 Chef, D5-M78 LK | |
| 116 Corte de Aleta | L11 izq, L12 der | ¿el mismo golpe saca las dos? |
| 137 Arandela Batidor | ABPM mini, LL7B | la vieja la llama "mini" |
| 183 Soldar Ahueca | N1 fruta, N2 papa | |
| 356 Corte Mango Plano Manija | G11 (501), I10 (701) | |
| 368 Doblado Sacafuente | Z5 grande, Z6 chica | ¿salen juntas? |

## 5. Tiempos: 9 matrices con tiempo en la vieja y vacío en GP2

182 (7,8 s) · 21 (0,4) · 325B (27,6) · 361 (1,7) · 509 (58,9) · 512 (54,5) · 62 (1) · 63 (7,3) · 64 (1). El 22/09 no había
ninguna diferencia: la vieja se completó después. (Otras 11 usadas no tienen tiempo en ninguna de las dos.)

## 6. Matrices de catálogo que se usan y no están en ninguna ruta (67)

Es la consecuencia esperada del catálogo del 22/09. **63 son trabajos de fábrica** (envasar, reenvasar, armar importados, sacar film)
sin Causa-Efecto tampoco en la vieja: no transforman una pieza, cuentan tiempo y premio. [Elías] *"Fábrica sí tiene que estar porque
se hacen en fábrica"*: van a la ruta del artículo como paso del tallerista **Fábrica** (queda como tallerista). Falta decidir cómo
se guarda la matriz en ese paso (hoy los pasos de tallerista no llevan matriz).

| Matriz | Descripción | Cajones | Unidades | Último |
|---|---|--:|--:|--:|
| 28B | Corte Cuerpo Uña p/Cromar | 12 | 19.100 | 01/09 |
| 255B | Calado Mgo Pelador Met | 8 | 12.088 | 03/09 |
| 389 | Env Ñoquera | 40 | 10.378 | 29/09 |
| 12C | Doblado Mango Plano Chef | 10 | 7.499 | 25/08 |
| 39B | Cerrado Cuerpo Sacacorcho (Sin Marca) | 9 | 7.487 | 13/08 |
| 113 | Remachado pisa papas Inox | 34 | 7.334 | 23/07 |
| 343 | Env Cuch Spaghetti 339 | 4 | 7.300 | 28/09 |
| 79B | Corte Destapacorona Sin Marca | 5 | 6.500 | 25/09 |
| 255 | Calado Mgo Pelador Plast | 2 | 3.654 | 28/08 |
| 146 | Aplastado Bombilla | 2 | 3.200 | 11/08 |
| 506 | Colocar Inserto Nuevo a Mgo Md Chino | 13 | 3.171 | 14/08 |
| 300 | Env Pelador | 12 | 3.107 | 24/08 |
| 341 | Env Uña Inox | 8 | 2.369 | 10/09 |
| 330 | Env Rallador Cilindrico | 8 | 2.316 | 28/07 |
| 401 | Env Cucharas Inox Imp | 20 | 2.266 | 17/09 |
| 237 | Poner Capuchon Mgo Espatula | 4 | 1.477 | 20/08 |
| 395 | Sacar carton 1 Precinto | 6 | 1.362 | 14/07 |
| 261 | Colocar Mgo a Ahueca Papa | 6 | 1.360 | 10/08 |
| 510 | Reenvasado de sacacorcho chino | 8 | 1.356 | 22/09 |
| 363 | Soldado Ahueca Papa | 1 | 1.350 | 24/09 |
| 157 | Recorte Sacatapita 523 | 3 | 1.334 | 27/08 |
| 906 | Remachado Prensa p.p Ajo | 4 | 1.205 | 14/08 |
| 505 | Armado Cuchara Fideo Inox Imp | 5 | 1.020 | 02/09 |
| 383 | Env Palo de Amasar | 13 | 1.016 | 29/09 |
| 381 | Env Abrelata mariposa Crom 502/ 066 | 2 | 1.008 | 11/08 |
| 309 | Env Rompenuez | 12 | 998 | 28/08 |
| 384 | Env Cuchara 25 Cm | 7 | 984 | 23/09 |
| 396 | Sacacorcho Doble Impulso | 5 | 972 | 13/07 |
| 512 | Reenvasado imp rallador | 8 | 888 | 28/09 |
| 505D | Armado Cuchara Inox Imp | 7 | 838 | 13/08 |
| 505C | Armado Cucharon Inox Imp | 6 | 828 | 17/09 |
| 57 | Cremallera D/Aleta Espiral y Sacatap. | 6 | 780 | 16/09 |
| 509 | Env Pelador Mgo Madera | 6 | 770 | 28/09 |
| 408 | Env Cuchara Madera | 5 | 660 | 20/08 |
| 402 | Env Ahueca Papa | 5 | 618 | 10/08 |
| 322 | Env Espatula NY | 4 | 600 | 28/08 |
| 321 | Env espatula calada NY | 3 | 504 | 14/09 |
| 254 | Colocar Mgo a Pala Canelones | 3 | 471 | 21/08 |
| 362 | Soldado Ahueca Fruta | 1 | 470 | 28/09 |
| 394 | Env Pala Canelones X 24 | 2 | 456 | 22/08 |
| 309B | Env Rompenuez CH | 3 | 456 | 27/08 |
| 214B | Sacar Film Protector Pala Canelones | 1 | 438 | 21/08 |
| 325B | Reenvasado Colador N°20 Chino | 3 | 432 | 25/09 |
| 325 | ReEnv Colador 10 | 1 | 432 | 11/09 |
| 249 | Colocar Bastidor a Mgo LK | 2 | 432 | 28/07 |
| 406 | Filtro de Bombilla | 1 | 396 | 02/07 |
| 10B | Varilla c/ Cuchilla Curva (H15) | 1 | 385 | 17/07 |
| 505B | Armado Espumadera Inox Imp | 5 | 380 | 16/09 |
| 403 | Env Filtro Cafe | 2 | 360 | 08/07 |
| 334 | Env Muñeco Silicona | 2 | 348 | 20/08 |
| 326 | Env Batidor Pera | 1 | 348 | 11/08 |
| 401B | Env Espatula Calada Mgo Madera Chino | 1 | 280 | 04/09 |
| 323 | Env Cuchara Calada NY | 1 | 240 | 28/08 |
| 242 | Armado Pelador 505 | 1 | 220 | 21/08 |
| 150 | Env Remaches | 26 | 214 | 11/09 |
| 342 | Env Cuchara 30 cm | 1 | 204 | 14/07 |
| 505F | Armado Espatula Calada Inox Imp | 1 | 167 | 30/07 |
| 507 | Env Cuerpo Uña Inox | 1 | 156 | 05/08 |
| 327 | Env Sacafuente Gastro | 1 | 144 | 12/08 |
| 400 | Env Despolvillador Yerba | 1 | 132 | 18/09 |
| 320 | Env Cuchara Spagueti NY | 1 | 120 | 28/08 |
| 511 | Reenvasado Corta Pizza Impor | 2 | 108 | 02/09 |
| 301 | Env Abre 502 | 1 | 96 | 10/07 |
| 312 | Env Bequisa | 1 | 90 | 04/09 |
| 508 | Env Aceitero | 1 | 60 | 18/08 |
| 105 | Sacar Rebarba Cucharon | 3 | 17 | 20/08 |
| 372 | Soldado C.Q. Mgo Alamb | 1 | 1 | 24/09 |

## 7. Faltan de un lado

- Solo en la vieja: **325C** Reenvasado Cola pastas 22,5 cm (usada 25/09) · **513** colocar etiqueta a bombillas.
- Solo en GP2: **S/N** Corte Arandela Cuchillitos · **227** Armado Sacacorcho 525.

## Qué se retiró de la versión 1 (errores míos)

- *"289 matrices sin tipo = problema"*: son las de catálogo del 22/09; sin tipo a propósito.
- *"GP2 pasó la variante a pieza y dejó la letra sin ruta"*: no fue un cambio; el Excel original ya modelaba piezas y las letras
  entraron después como catálogo.
- *"127.750 unidades que no suman stock"*: son trabajos de fábrica, no transformaciones de pieza.
- *"Fábrica mal cargada como tallerista"*: el dueño confirmó que queda como tallerista.
- *"19 sin tiempo en GP2"*: 11 no tienen tiempo en ninguna base; las 9 reales están en el punto 5.
- *"31 nombres distintos"*: en las 115 originales el nombre viene del Excel del dueño; lo que importa está en los puntos 1 y 2.
