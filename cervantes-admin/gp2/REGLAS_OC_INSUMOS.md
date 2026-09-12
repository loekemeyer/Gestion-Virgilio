# Reglas para el futuro módulo de Órdenes de Compra de insumos

Registrado 2026-08-29 a partir de las definiciones del usuario. Estas reglas viven
parametrizadas en Supabase (`GP2.carton_formato`, `GP2.carton_categoria`,
`GP2.proveedor_insumo.modo_control`) — este documento explica la lógica.

## Idea general

El módulo de OC debe **generar los pedidos a partir del consumo**, no de importar PDFs:

1. El consumo nace de la **Est Madre** (`GP2.est_madre`, sincronizada sola del programa viejo):
   unidades por mes de cada artículo terminado.
2. Se explota por la receta (`articulo_componente`) y por las rutas hasta cada insumo: flejes,
   cartones, cajas, remaches, etc. Eso ya existe como vista: **`GP2.v_consumo_componente`**
   (consumo_uni_mes por componente, toda la cadena; sucesora de `v_consumo_parte`, que sólo
   cubría la receta directa y se borró el 2026-09-04) y `v_consumo_fleje_kg` para los flejes.
3. Con el máximo (`inventario.maximo`; si está vacío, consumo × meses) y el stock se decide cuánto
   pedir (**sugerido = máximo − stock**, sin restar lo pendiente de OC desde el 2026-09-04), y el
   pedido se arma respetando las reglas de cada tipo de insumo (abajo).

## Cartones (parametrizado en `GP2.carton_formato`)

Los cartones se **reciben en PAQUETES**: el proveedor siempre entrega alturas de
**250 unidades** por paquete (`parametro.carton_uni_x_paquete`), sea cual sea el tipo
(el C viene de a 1.000 = 4 paquetes de 250). La recepción carga paquetes y guarda unidades.

| Formato | Pedido total múltiplo de | Por código múltiplo de | Mínimo por código |
|---|---|---|---|
| C | 12.000 | 1.000 | 1.000 por cada múltiplo de 12.000 |
| LOKE | 16.000 | 1.000 | 1.000 por cada múltiplo de 16.000 |
| 8 | 30.000 | 1.000 | 1.000 por cada múltiplo de 30.000 |
| Huevo | 25.000 | 1.000 | **2.000** por cada múltiplo de 25.000 |

- **Las BOLSAS son de `Envases Vihal`, no de Pol**, y tienen **pedido mínimo de 20.000
  unidades** `[usuario 2026-09-03: "ponele veinte mil y mañana lo chequeo"]` — **SIN
  CONFIRMAR**. El mínimo es una cosa distinta del múltiplo y vive en su propia columna,
  `carton_formato.pedido_minimo`: el múltiplo dice de a cuánto sube el total, el mínimo dice
  el piso para que el proveedor lo tome. La bolsa va de a 1 pero no baja de 20.000.
  **No se afloja solo** `[usuario]`: *"ya me ha pasado que el proveedor acepta pedidos más
  chicos, como de diez mil, pero con un precio más caro… sobre todo para el 031"*. Pedir por
  debajo cambia el precio, así que si se habilita tiene que venir con su propia lista.
- **El PLIEGO se pide de a 100** `[usuario 2026-09-03: "los pliegos del quinientos,
  quinientos seis y bombillas se tienen en paquetes de 100 pliegos"]`. Los 24 pliegos
  (`componente.es_pliego`) llevan `carton_formato` porque el formato dice sus **posiciones**
  —que es para lo que se usa en el **costo**— pero **la regla de pedido es otra**: paquetes
  de 100 pliegos, sin múltiplo de familia. El Pliego 500/506 tiene formato C (12 posiciones)
  y **no** va en múltiplos de 12.000. El 100 vive en `GP2.parametro.pliego_uni_x_paquete`.
- **Huevo, ojo**: `[usuario 2026-09-03]` *"los paquetes del cartón huevo vienen de múltiplos
  de dos mil, pero el pliego viene de veinticinco mil… necesito pedir un mínimo de dos mil
  por cada una y los de veinticinco mil"*. **Los dos números no cierran entre sí**: si cada
  código fuera en múltiplos de 2.000, la suma nunca podría dar 25.000 (25.000/2.000 = 12,5).
  Quedó cargado con el 2.000 como **mínimo** y el paso en 1.000 — la única lectura donde las
  dos frases conviven. **Falta que el usuario lo confirme**; si el paso fuera 2.000 de
  verdad, hay que revisar el 25.000 con Gráfica Pol.
- Con mínimo 2.000 entran **como mucho 12 códigos** en un pedido de 25.000. Hoy no molesta
  porque la marca separa los 13 huevos en 11 LOEKE + 2 CHEF, pero si alguna vez una marca
  junta 13, ese pedido es imposible y la pantalla lo dice.

- **El mínimo por código es FIJO: es el PAQUETE en que viene el cartón** `[usuario
  2026-09-03: "el paquete viene a mil, considerá que se puede recibir a mil"]`. **NO escala
  con el múltiplo** — acá decía que sí, y estaba mal: con el mínimo escalado una familia con
  muchos códigos **no tenía ningún pedido válido** (26 códigos LOKE CHEF × 1.000 ya se pasan
  de 16.000, y subir al múltiplo siguiente subía también el mínimo, así que nunca cerraba).
- **No se piden todos los códigos de la familia** `[usuario: "los códigos de resto no
  siempre se piden, solamente se pide lo que se necesita"]`. El mínimo corre para los
  códigos que entran en el pedido, no para el catálogo entero.
- Nunca cantidades intermedias: cada código va en múltiplos de 1.000 (1.500 no se puede).
- **La familia de pedido es FORMATO + MARCA + CATEGORÍA** (definido por el usuario el
  2026-09-03).
- **LOKE lo usan las dos marcas y NO se piden juntas**: *"una marca va con un pliego y la
  otra con el otro"*. Hoy son 7 códigos LOEKE y 28 CHEF, y cada uno es su propio pedido de
  16.000. La marca ya está cargada en los 110 cartones (`componente.marca`).
- **Tipo C**, las familias son: **Pelapapas** (4 códigos), **Sacacorchos** (7),
  **Abrelatas** (6) y **Resto** (16, todos mezclables entre sí). La clasificación NO se
  cargó a mano: sale de `GP2.articulo.familia`, que ya la tenía (Peladores → Pelapapas), y
  el cartón se llama "Cartón NNN" donde NNN es el artículo.
- **El sacacorchos es COMODÍN**: *"sacacorcho se puede mezclar con cualquiera"*. En
  `GP2.carton_categoria` eso es `mezcla_libre`, prendido sólo en Sacacorchos. En la OC no
  forma familia propia: se suma a la familia de su mismo formato y marca a la que más le
  falta para llegar al múltiplo. Si no hay otra familia en el pedido, va solo.
  (Ojo: **Resto no es comodín**. Que dentro de Resto se mezclen todos con todos es
  simplemente ser una familia; no habilita mezclarlos con Pelapapas.)
- `Pisapapas` quedó en el catálogo **sin uso**: no lo nombró el usuario y ningún artículo
  tiene esa familia. Probablemente fue una mala transcripción de "pelapapas".
- Cada cartón se asigna a su formato/categoría en `componente.carton_formato` /
  `componente.carton_categoria`. **El formato ya está cargado en los 110 cartones**
  (C 37 · LOKE 35 · Pliego 20 · Huevo 13 · Bolsa 3 · "8" 2); **la categoría sigue VACÍA**
  y hasta que llegue, cada formato valida como una sola familia.
- **Los múltiplos los confirmó el usuario el 2026-09-03** (12.000 / 16.000 / 30.000) y viven
  en `GP2.carton_formato`. Ojo: hasta ese día la tabla tenía cargado el tamaño de la **bolsa**
  (1.000 / 1.000 / 3.000) y no el múltiplo de pedido — si algún número no cierra, mirar
  primero si `pliegos_multiplo` no volvió a quedar igual a `uni_x_bolsa`.
- **Huevo queda SIN CONFIRMAR**: hoy vale 2.000 (el tamaño de bolsa). El usuario nombró
  25.000 el 2026-08-31 pero no lo confirmó — falta preguntarle a Gráfica Pol.
- **La OC ya arma el pedido sola**: "Usar sugeridos" redondea cada familia hacia arriba al
  múltiplo, aplica el mínimo por código y reparte el resto de a 1.000 empezando por el que
  más pidió. Si se escribe a mano algo que rompe la regla, el cartel rojo trae el botón
  "Ajustar al múltiplo".

## Proveedores de servicio — cuánto mandarles

Al PS **no** se le manda para llegar a X meses de stock propio. La cuenta es contra el
**MÁXIMO FÍSICO del Sector Procesado** (`inventario.maximo` del SP en su sector):
`enviar = máximo físico del SP − online en SP − online del PS`.
Ej: máximo 10, hay 5 en procesado y el PS tiene 3 → se le mandan 2 cajones de crudo
para que los convierta. Implementado como columna **"Sugerido Cajón"** en Envíos PS.
Aparte, el Punto de Stock avisa si ese máximo físico quedó desfasado contra el consumo
(estado "máximo insuficiente"). Las ubicaciones de PS no tienen `meses_stock`.

## Flejes — consumo en KG

El fleje se mide en **kg**, nunca en unidades. El consumo baja del artículo terminado
hasta la matriz que corta el fleje: `kg de fleje = consumo en unidades de la pieza /
partes_por_kilo_de_fleje de la matriz` (las partes por kilo ya incluyen el desperdicio).
Vista: `GP2.v_consumo_fleje_kg`; el Punto de Stock de flejes usa esos kg × 6 meses.

## Flejes (parametrizado en `GP2.proveedor_insumo.modo_control`)

- Se piden en kg (OC en kg).
- `rollos_remito` (Basconia, Aperam): el remito declara rollos y pallets.
- `pesaje` (Hermac, Brawin, Szapiro, EstaMetal, JL Metales, Altrak): el remito trae solo
  kg; el control en balanza es el mismo (pallets + rollos) pero sin datos declarados.
- **Varillas: pendiente** — el usuario constata cómo se controlan (lunes).

## Remaches — Bella Vista

- Se pide en kg (OC), **factura en unidades**; al anotar la recepción se convierte
  uni→kg (kg_x_uni) y el control pesa el total contra el remito (tolerancia
  `parametro.tol_ctrl_peso_pct`, hoy 2% o 0,5 kg).

## PS híbridos — la OC dispara una OC gemela al proveedor de la materia prima (2026-09-05)

> **RESUELTO 2026-09-08 (pregunta 28 contestada) — CHARCAS QUEDA FUERA DE ESTE MECANISMO.**
> El usuario: *"esos dos items de ordenes de compra en flejes hay que sacarlos porque esas dos
> partes de charcas se tratan como proveedor de servicio"*. **Lo que un PS produce no se compra**:
> `oc_bundle` ya no lista un componente cuyo `proveedor` es el MISMO PS que lo produce en una ruta
> (`ruta_paso` tipo `proveedor_servicio` con `comp_salida` = ese componente). Hoy son IC3 e IC3V.
> Entonces: **la OC del Fleje 90 va SOLO a Altrak** (`FLEJE90_BRUTO`, rubro Alambre) y el corte
> entra por Entrega PS. La gemela sigue viva **sólo para Eclipse**; y `crear_oc` ahora suma al kg
> de la gemela **sólo lo que el PS produce** (sector que no es de insumo), porque Charcas además
> nos VENDE bombillas (BOM10/EP10/LLF8) y una OC de esas disparaba una OC de alambre a Altrak que
> nadie pidió.

Un **PS híbrido** (`proveedor_servicio.hibrido` con `mp_componente_id`) procesa una materia
prima nuestra: Resortes Charcas corta el alambre de Altrak (`FLEJE90_BRUTO`), Eclipse estampa la
chapa 430 de Aperam (`CHAPA430`). Una OC a ese PS crea sola la **OC gemela** al proveedor de la
MP (`componente.proveedor`) por **kg de producto pedido ÷ (1 − `proveedor_servicio.desperdicio_pct`/100)**
— Charcas 0 % (sin dato, decisión del 04/09; su recepción descuenta el alambre 1:1), Eclipse
**40,28 %** (el desperdicio se razona como recorte/chapa; su recepción descuenta la chapa con ese
%). ⚠️ **Corregido el 2026-09-08**: acá decía "Eclipse 28 %" y la fórmula con `× (1 + pct)`; las dos
cosas estaban viejas — el cambio a división y al 40,28 se hizo el 2026-09-08 (ver
`CONOCIMIENTO_GP2.md`, bloque de desperdicio). Es UNA regla en `crear_oc`, sin
proveedores por nombre — aunque `oc_bundle` y la pantalla todavía nombran a Charcas y Eclipse
(idea 7267).

- **Charcas se pide en PAQUETES** de `parametro.charcas_kg_x_paquete` kg (hoy 10): la pantalla
  muestra paquetes y «= N uni», manda `unidad='paq'` y `crear_oc` **guarda la OC en kg**, así la
  recepción (kg de balanza) cruza directo y la gemela suma kg de verdad.
  ⚠ **PENDIENTE (2026-09-08)**: esa regla se escribió para el alambre cortado (IC3/IC3V), que ya
  NO se pide por OC. Lo único que hoy le pedimos a Charcas son bombillas en unidades, y la
  pantalla se las sigue mostrando en paquetes de 10 kg (`esCharcasIt()` mira sólo el proveedor).
  Falta que el usuario diga si las bombillas también vienen en paquetes de 10 kg o si esa
  conversión hay que sacarla.
- **Eclipse se pide en unidades** (el 1686); la gemela convierte con `kg_x_uni`.
- `orden_compra_item.unidad` sólo admite `kg` / `uni` (CHECK).

## Estado 2026-08-29: el módulo YA EXISTE

`Compras/OC_GP2.html` (menú Insumos → Órdenes de Compra): genera OC con
**sugerido = máximo − stock** (cambiado el 2026-09-03; el «− pendiente OC» se sacó el
2026-09-04 por pedido del usuario; antes era consumo × meses, que hoy sólo se usa como
respaldo cuando el máximo está vacío — ahí el `maximo_origen` dice `consumo_x_meses`),
valida las reglas de cartón (**vivas**: los 110
cartones tienen formato y el tipo C ya tiene categoría — verificado 2026-09-08), imprime la OC
para el proveedor (**con la fecha de entrega**, que hasta el 2026-09-08 se perdía por un nombre de
campo, idea 7271), y la **recepción cruza sola**
contra las OC abiertas (`recibido` + estado `recibida` automático). RPCs: `oc_bundle`,
`crear_oc`, `oc_marcar`, `_aplicar_recepcion_a_oc`.

## Proveedores por rubro (cargados 2026-08-29, dato del usuario)

- **Cartones → `Talleres Gráficos Pol`** (siempre el mismo, los 85 códigos).
- **Cajas → `Corrugadora del Sur`** (siempre el mismo, los 9 códigos).
- **Flejes →** el que ya tenía cada uno en `fleje_detalle` (Basconia 23, Aperam 11,
  Hermac 6, Brawin 6, Szapiro, JL Metales, EstaMetal, Altrak): 50 copiados a
  `componente.proveedor`.
- **`Importado`** (proveedor marcador, no es una empresa): la **Cremallera (E13)** y los
  insumos del **corta queso** (Z19A Alambre, PB1 Cilindro, V20/CV20 Tornillo) ya **no se
  fabrican, se importan**. Las rutas ya son consistentes: E13 y Z19A entran como paso
  `insumo` (compra directa, sin matriz). PENDIENTE: si el tornillo se importa YA
  niquelado, el paso CV20 → niquelado (Guazzaroni) de las rutas 382/577/589 queda muerto
  y hay que sacarlo; si se importa en crudo, queda como está.
- **Quién hace cada parte se administra desde la pantalla `Compras/Inyectores_GP2.html`**
  (menú Insumos → "Inyectores · Quién hace cada parte"): a la izquierda la parte, a la
  derecha un botón por proveedor; se toca y se guarda al instante (RPC
  `asignar_proveedor_parte`). Sirve para cualquier rubro de insumo, no sólo plásticos.
  **Eso es lo que separa la OC**: en Órdenes de Compra se elige el proveedor y la orden
  sale sólo con SUS partes. Si mañana cambia el inyector, se cambia ahí y la OC lo sigue
  sola — no hay que tocar la base. Alta de proveedor nuevo desde el botón "+ Proveedor"
  (RPC `alta_proveedor_insumo`); `proveedor_insumo.rubro` hace que aparezca en la botonera
  de ese rubro aunque todavía no tenga partes.
- **Plásticos (inyección) → son TRES proveedores**: `Pat Bet Plast`, `Pettofrezza Rafael`
  y `Kollplast` (los tres dados de alta en `proveedor_insumo`). Hoy los 29 códigos están
  **todos** bajo Pat Bet Plast porque esa es la foto del **vecino**
  (`public.Partes_Plasticas`, columna Proveedor, matcheada por código y excluyendo lo que
  en GP2 fabrica un tallerista) — NO se inventó nada, pero **es data vieja**: el vecino no
  conoce ni a Pettofrezza ni a Kollplast como inyectores (solo suma 2 a Esther —
  PC2A/PC2B— y 2 a Maspoli —PC12/PEP7—). **PENDIENTE: repartir los 29 entre los tres.**
  Kollplast no existía en ninguna de las dos bases: se creó de cero.
- **Garage (GRJ1, GRJ7, GRJ10, GRJ10A)**: NO llevan proveedor — los arman los talleristas,
  no se compran.
- **Becker Sandra Nora NO es proveedor de insumos**: es `proveedor_servicio` (pintura /
  serigrafía de piezas metálicas). No confundir.

Faltan proveedor: 8 plásticos (ver abajo), bombillas/resortes 8, remaches 8, fleje F12.

## Pendientes

- Asignar formato/categoría a cada cartón (`componente.carton_formato/carton_categoria`).
- Varillas: proveedor y forma de control.
- Proveedor de: los 8 resortes (BOM10, C9, C12, D14, EP10, I2, I3, LLF8), los 8 remaches
  (V4, V10, V13, V14, V18D, W8, CV13, CV18D) y el fleje F12 (N° 49).
- Los 8 plásticos que quedaron sin proveedor y por qué:
  - `PA10B` Capuchón ф8 s/Serig, `PC16` Inserto Chef — códigos nativos de GP2, el vecino
    no los tiene (PA10B parece la variante sin serigrafía de PA10 = Pat Bet Plast).
  - `PC15A` Cpo doble aleta LK, `PC15B` Cuerpo Sac Aleta, `PEP5` Mango Madera — el vecino
    los tiene con proveedor VACÍO (PEP5 además es de madera, no inyección).
  - `PC12`, `PEP7`, `PEP8` — en GP2 los produce **Maspoli SRL** como tallerista (paso de
    ruta), no se compran como insumo. El vecino coincide en PC12/PEP7 (Maspoli) pero pone
    PEP8 bajo Pat Bet Plast: conflicto a resolver.
- Prov AT: se les manda según la OC de Producción Virgilio (sin punto de stock propio).
- Meses de punto de stock ya definidos: flejes 6, crudo 1, procesado 1, talleristas 1,
  tránsito 0, cartones 6, cajas 6, remaches 4, plásticos 4, bombillas 3.
- **Máximos de flejes e insumos (regla 2026-08-29)**: surgen de la **Est Madre llevada
  para atrás** (consumo mensual explotado por receta/rutas × meses del rubro), NO de
  relevamiento físico. `inventario.maximo_origen='est_madre'`; se **recalculan solos**
  (triggers en est_madre / recetas / rutas, función `recalcular_maximos_insumos`). Los
  máximos FÍSICOS ya relevados (cajas, 11 remaches del vecino) tienen origen `fisico`
  y nunca se pisan. En Punto de Stock los derivados se ven con el tag **EM**.
- Virgilio como DISTRIBUCIÓN de terminados: NO interesa analizar su entrada/salida — existe solo
  para medir a los talleristas (decisión usuario 2026-08-29). No se construye módulo de
  despacho/venta. **OJO (2026-09-10): eso es la distribución. La MATERIA PRIMA PLÁSTICA también
  se guarda físicamente en Virgilio y ESA sí se gestiona** — sector 14 «Materia Prima Plástica»,
  ver abajo.
- **Materia prima plástica (2026-09-10)**: bolsas de 25 kg (PP 2630, ABS, Alto Impacto, Nylon
  Virgen/Recuperado/c-Carga, PE, PS HF555 + Master Bach) → sector 14. Tres proveedores cotizan
  (**Indarnyl 202, Beta Plásticos 3527, Santa Rosa Plásticos 837**; Master Bach: Arcolor / Julio
  Garcia) y **cada material se le compra AL MÁS BARATO** [usuario 2026-09-10: "al que sea más
  barato por material, la OC tiene que considerar eso"]: `v_material_precio_proveedor` lleva el
  precio de cada proveedor a pesos al dólar oficial del día y `recalcular_proveedor_material()`
  pone `componente.proveedor` = el de orden 1 — corre solo por trigger cuando entra/cambia un
  precio y desde el cron del dólar (`actualizar_dolar_oficial`). La OC (`oc_bundle` / `crear_oc`)
  cotiza con el precio del proveedor ASIGNADO al componente. Rubro propio en OC y en Recepción
  («Mat. Plástica», en kg). **La OC de un material va a UN solo proveedor (el más barato), nunca
  repartida; entregan en ~5 días (`dias_entrega`)**; se imprime con la hoja «O.C.» del usuario
  (membrete Loekemeyer/Chef, entrega en Virgilio 2788, renglones LK 85 % / CH 15 % con
  `codigo_isis_ch`) y **se emite sola al generarla** [usuario 2026-09-11]. **Sin código de Chef
  no hay renglón CH**: el material va 100 % LK (Nylon Virgen / Recuperado, PE, Master Bach)
  [usuario 2026-09-11: "si no lo usa"]. **ENTREGA EN = `proveedor_insumo.entrega_en`**: null =
  Virgilio 2788; **Master Bach (Arcolor, Julio Garcia) = Cervantes 2868, se stockea en Cervantes
  por ahora** [usuario 2026-09-11]. Gestión Virgilio ve las OC que le llegan con
  `oc_pendientes_virgilio()` y las recibe con `recibir_oc_virgilio` (ver
  `INTEGRACION_GESTION_VIRGILIO.md`). **Máximo = 2,5 meses de consumo en bolsas enteras** (`maximo_origen='fisico'`).
  **Desde el 2026-09-11 es una regla viva** [usuario: "elegí uno y vamos" → recalcular con el consumo
  GP2]: `recalcular_maximo_material()` = ceil(`ubicacion.meses_stock` 2,5 × consumo GP2 kg/mes con
  desperdicio ÷ 25) × 25, con el consumo de `v_consumo_componente` (Est Madre = `proyeccion_madre`);
  corre a diario desde `actualizar_dolar_oficial`. **El Master Bach sale por fórmula: 2 % del plástico**
  (regla del Excel del usuario; como GP2 todavía no sabe el color de cada pieza, el 2 % va sobre el total
  y se reparte entre los 4 colores con la proporción cargada, en bolsas enteras —
  `maximo_origen='mb_2pct_del_plastico'`).
- **Pedido mínimo del proveedor de resina** (`proveedor_insumo.pedido_minimo_kg`, del Excel, hoja «Relev y
  OP Bolsas Plast»): **Indarnyl 400 kg**, Beta Plásticos 25, Santa Rosa 25, masterbatch 5. Viaja en
  `oc_bundle.proveedores[]`; la pantalla suma los kg de la OC por proveedor y **no deja crearla si no llega
  al piso** (dice cuántos kg faltan). No se infla sola: sumar kg es una decisión de compra.
- **Pedido mínimo POR PIEZA** (`componente.pedido_minimo_uni`, del Excel, hoja «Pedido 31-08», columna
  `Pedi Min Uni`): el inyector no hace una tirada de menos de N piezas (1 a 36.000 según el molde), **47
  componentes cargados**. Viaja en `oc_bundle.insumos[].pedido_minimo_uni`. **NO bloquea**: hoy 24 de los
  47 sugeridos quedan por debajo (el Pirolo Blanco sugiere 2.248 contra un mínimo de 36.000 = 64 meses de
  consumo), y bloquear dejaría la OC imposible. Es un aviso amarillo con botón **«Subir al mínimo»** —
  comprar 16 veces el consumo es una decisión del comprador, no de la pantalla. Sólo se carga sobre lo
  que se compra (los `estado_compra='fabricacion'` quedan afuera: el mínimo es del que inyecta). Hasta ese día los máximos eran los del workbook del usuario (PP ~909 kg/mes); OJO: hay 34
  artículos del Excel sin despiece en GP2 (~70 kg/mes de PP/ABS reales), así que el máximo de PP
  queda corto hasta que se den de alta (archivo `Articulos_Excel_sin_despiece_GP2.xlsx`, chat 2026-09-11).
  Tope físico: 20 pallets × 15 bolsas en Virgilio. Las bolsas **se le mandan a los inyectores**
  (`enviar_material_inyector`, desde Inyectores) y **el inyector tiene que tener lo que necesita
  para su OC** [usuario]: `v_material_inyector` = OC abiertas × kg_x_uni × 1,04 − lo que ya tiene.
  Al recepcionar la pieza inyectada, `crear_recepcion_insumo` descuenta sola el material de la
  ubicación del inyector. Pendientes: precio de PE / Nylon Virgen / Nylon Recuperado (Santa Rosa
  no los lista en la planilla), stock inicial de Master Bach (0, sin conteo), y PC12 / PC16 sin
  material asignado (el workbook no los trae).
- ~~Flejes, cartones, plásticos y bombillas sin máximo~~ RESUELTO 2026-08-29: sus máximos
  se derivan de la Est Madre (ver regla arriba), ya no requieren relevamiento.
- Cartones: el formato (C/LOKE/8) de cada cartón se va a identificar POR PRECIO —
  los precios del cartonero están copiados en `GP2.precio_proveedor` (rubro carton).
- Máximos físicos: importados del vecino (SP 80, SC 74, cajas 9, remaches 13) + Virgilio
  (81 posiciones: también se guardan insumos/partes en Virgilio — SP y cajas con sus
  máximos "Virg" del vecino) + talleristas (103, CALCULADOS = 1 mes de Est Madre de los
  artículos que hace cada uno, parte por parte según sus rutas y recetas). Faltan:
  flejes, cartones, plásticos y bombillas (el vecino no los tiene).
- Costos: el vecino tiene precios de cartones en `public.Precios_Proveedores` (por texto
  de producto, sin cod_art); GP2 aún no tiene costos.
