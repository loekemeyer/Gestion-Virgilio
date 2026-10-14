# ADS — Alertas Damián Stock (talleristas + stock + quiebres)

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (Luis, 2026-10-06, v27.21): ADS — ALERTAS DAMIÁN STOCK (`ads.js`)

Panel supervisor → **ADS — Alertas Damián Stock** (`openAds`), con badge **violeta** (`#adsBadge`, `gv_ads_badge()`).

- **Entregas talleristas** (`gv_ads_talleristas(p_n, p_incluir_actual)`): por (proveedor de la OC, código) en las
  últimas N OC (fechas de generación, rubro `Art Term`). La OC de cada semana REEMPLAZA a la anterior, así que
  **pedido = 1.ª OC del rango + Σ max(0, OC_k − (OC_{k−1} − recibido_{k−1}))** (ejemplo de Luis: 300/150 + 200/100 →
  350 pedido, 250 entregado). **v27.28 (Luis, D6: *"estamos
  tratando de evaluar stock real y quiebres reales"*): Entregado = lo que RECIBIÓ VIRGILIO** de ese proveedor y código
  (`Entregas Tallerista Virgilio` + `Entregas Prov AT`, `gv_prov_match` + `GV_OC_Fabrica_Para`) desde la 1.ª OC del
  rango hasta la OC siguiente a la última (o hoy), **topado en lo pedido por artículo** (el exceso de un código no tapa
  a otro). Las dos tablas de entregas quedan separadas (D8, Luis: *"dejalo"*). La OC más nueva
  no entra por defecto (su semana corre). Tallerista con % < umbral → cuenta en el badge. Medido 06/10: badge 13 → 10
  (Lucho 40 → 51 %, Poly 36 → 60 %, Pedernera 22 → 76 %). **v27.31**: lo recibido cuenta desde la 1.ª OC de ESE artículo en el rango, no desde la 1.ª OC del rango (599E: 34 cajas del 28/09 se contaban contra una OC del 30/09 → «100 %»). `sql/gv_ads_recibido_virgilio_v2731.sql`.
- **v27.73 (Luis, 07/10): rango 1 a 12, cada opción con la fecha de la OC más vieja que entra (`1 - 07.10.26`, `gv_ads_oc_fechas`); la OC en curso entra SIEMPRE (se fue la casilla).**
- ⚠⚠ **v28.95 (Luis, 09/10): el % de talleristas es un SNAPSHOT de las OC CERRADAS — la OC vigente NO entra nunca** (pantalla, Excel y badge; `Stock_Config.ads_incluir_actual = 0`). Retira el «entra SIEMPRE» de la v27.73. El selector dice la fecha de la n-ésima OC cerrada. **v28.96**: el selector se llama «Rango últimas cerradas»; el recuadro de la derecha (pantalla y Excel) es la **OC VIGENTE** (`gv_ads_talleristas(1, true)`), no la última del período; la pestaña Stock sigue leyendo el período CON la vigente (`_ads.tallInc`).
- **v27.75 (Luis): el rango abre siempre en 4 (el guardado sólo vale para el badge) y la Proporción lleva las cajas: `Garcia 57 % (140)`; en el Excel separadas con « - ». Con un solo tallerista también: `Lucho (350)` (v27.76, D1).**
- Rango, umbral (50 %) e «incluir la OC en curso» viven en `Stock_Config` (`ads_n_ocs`, `ads_umbral`,
  `ads_incluir_actual`); los guarda `gv_ads_config_guardar` (supervisor). Cambiarlos es un `update`.
- **Stock** (`gv_ads_stock2()`, v27.22; `gv_ads_stock` queda sin llamador, de rollback): saldo a 10/20/30 días =
  (góndola + racks + racks CH + a guardar + **excedente**, D2 Luis 06/10) − NP programadas sin
  pickear con entrega hasta hoy+N (vencidas incluidas, `gv_demanda_programada_pendiente`) − Est. Madre × N/30.
  Negativo = quiebre. Con la última OC vigente del código y el % de entrega del tallerista en ese artículo.
  **Sólo artículos CON TALLERISTA** (v27.23, Luis: *"los importados no"*): proveedor activo en `OC_Maximos`. Un importado
  que igual se le compra a un tallerista local (437E, 590E, 26…: 34 códigos) entra, porque tiene OC (D4, Luis 06/10: *"quedan, tienen tallerista"* — no volver a proponer sacarlos). 316 → 220 artículos;
  **D1 rechazado (Luis, 14/10, caso 945E): los artículos cuyo único proveedor en `OC_Maximos` es «Log/ Fabr» y que NUNCA tuvieron OC (11 al 14/10: 392, 543, 720, 722, 843, 846, 858, 941E, 942E, 945E, 946E) QUEDAN en ADS y en el semáforo** (*"ni loco, dejalo así"*). No volver a proponer sacarlos.
  quiebres 45 / 61 / 90 a 10/20/30 días.
- **Botón del panel (D3, Luis 06/10)**: a la IZQUIERDA badge violeta = talleristas a revisar; a la DERECHA semáforo
  (`gv_ads_badge_stock`): **rojo** = quiebre a 10 días · **naranja** = los que recién quiebran a 20 · **amarillo** = los que
  recién quiebran a 30 (cada artículo cuenta una vez, en su color más urgente). Cada pastilla lleva su leyenda **10d / 20d / 30d** al lado del número (v27.25, Luis). Son DOS pestañas (D1: no hay tercera).
- Medido 06/10 (últimas 4 OC cerradas): 13 de 18 talleristas debajo del 50 %; quiebres 80 / 98 / 127 a 10/20/30 días
  (con excedente) → semáforo 80 · 18 · 29.
  El % bajo refleja también la imputación (Oscar / Tierra Nativa se reciben como Log/ Fabr): mirar antes de reclamar.
- Sub-tabla (v27.29, Luis): **Fecha · Pedida · Recibida son de la ÚLTIMA OC** y van bajo un rótulo común «Última OC»
  dentro de un recuadro violeta. «Incluir la OC en curso» viene **prendido** por defecto.
- **Pestaña Stock (v27.30, Luis)**: TODO se calcula al horizonte elegido (10/20/30; «todos» muestra todo al último
  elegido). Columnas: Cód · Descripción · Stk · Comprom. H d · Est. Madre H d (mes × H/30) · Saldo H d · Días cobertura
  ((disp − comprom. H) ÷ Est. Madre diaria) · recuadro «Última OC» (Fecha · Pedido · **Recibido** · %) · Proporción (v27.42, antes «Dist.»: tallerista
  ; v27.33: sólo a quién le corresponde, y con varios la parte de cada uno en lo pedido del rango — lo entregado está en la otra pestaña). **Recibido = lo que recibió Virgilio de ese proveedor desde la fecha de la OC** (D10), no lo imputado:
  `gv_ads_stock3` (= stock2 + `oc_rec_v`). `sql/gv_ads_stock3_v2730.sql`.
- **v27.78 (Luis, 07/10): pestaña Stock sin «Días cobertura»; el recuadro es «Período (N OC)»: Fecha últ. OC · Pedido período · Recibido período · % = suma de todos los talleristas del código en las N OC del rango (lo mismo que Entregas talleristas). La Proporción ya era del período.**
- **v27.81 (Luis, 07/10): Proporción va ADENTRO del recuadro Período, y columna «Entrega est. H d»** = Σ por tallerista min(lo que le falta, recibido ÷ días desde su 1.ª OC del período × H). El detalle por tallerista va en el `title`; también en el Excel.
- **v27.82 (Luis, 07/10): la Entrega est. va DISCRIMINADA por tallerista** con su parte de lo estimado (`Garcia 83 % (50) - Poly 17 % (10)`), en el TOOLTIP de la celda (v27.85, Luis: dato aparte, no suma al Saldo ni al Stk) y en la columna «Entr. est. x tall.» del Excel (`estDist` de `_adsStockCalc`).
- **Excel de stock (v27.87, Luis): formato de SU Excel «ADS_stock_10d_20261007_1»** — Arial 14, rótulo alto 72 (Comprom · E M · Ped/Rec período · Entr est), anchos fijos 5,86 · 14,86 · 6 · 7,14 · 6,29 · 6 · 5,57 · 8,71 · 6,29 · 5,29 · 6,29 · 21 · 18,86, todo con ajuste de texto y alto de fila según el texto (`_adsAltos`). «Entr. est. x tall.» va lleno en todas las filas (también un solo tallerista, desde v27.86).
- **Excel de stock v27.91 (Luis, «ADS_stock_10d_20261007_3», optimización horizontal máxima)**: cada tallerista en su **sub-fila** (salto de línea dentro de la celda) en «Entr. est. x tall.» y «Proporción»; rótulo «Cód», borde grueso abajo del rótulo, descripción a la izquierda SIN ajuste, escala de impresión 74, anchos de su archivo (A 7,71 · L 23,29 · M 27,43). El alto de fila sale de la cantidad de sub-filas.
- **Excel de talleristas (v27.89, Luis): formato de SU Excel «ADS_talleristas_4OC_20261007»** — Arial 14, rótulo alto 72, filas de 18, anchos fijos 12,71 · 12,43 · 23 · 7,43 · 7,57 · 7,57 · 8,43 · 8,29 · 7,57 · 8,29; texto a la izquierda, números centrados. **v27.90: los anchos van EXACTOS como su archivo (12,7109375…) y el estilo Normal queda en Arial 10** — de esa fuente sale la unidad del ancho; con Normal en 14 las mismas columnas se ven distintas. El 14 va en la fuente de las celdas. El % de talleristas sale como texto «71%» (entero).
- **v27.97 (Luis, 07/10, caso 609): la Entrega est. sólo cuenta a los talleristas de la OC ACTUAL del código** (la de fecha más nueva): la OC de la semana reemplaza a la anterior, así que el que salió no entrega más. Pedido/Recibido/Proporción del período no cambian.
- **v28.28 (Luis, 07/10): los dos Excel de ADS (stock y talleristas) llevan TODOS los bordes** (fino en las 4 caras de cada celda; el rótulo con el de abajo grueso) → se imprimen en cuadrícula. `_adsXlsxFormato`, `borders` 1 y 2.
- **v28.30 (Luis, 07/10, «ADS_stock_10d_20261007_8_1», *"ese es el formato que quiero"*): Excel de stock con SUS anchos exactos** (A 11,29 · B 14,86 · C 5,29 · D 5,14 · E 7,14 · F 6 · G 7,71 · H 8,71 · I 6,29 · J 5,29 · K 6,14 · L 19,14 · M 27,43), filas de **2 renglones mínimo** (36; 54 / 72 si una sub-fila de L o M no entra: `_adsAltos(…, 2, 1.4)`), escala de impresión **68** y márgenes normales de Excel (`margenStd`). Retira los anchos y la escala 75 de la v27.99.
- **v28.01 (Luis, 07/10): en el Excel de stock el SALDO H d es la columna C (primera de datos) y va en NEGRITA** — es el dato más importante. Orden: Cód · Descripción · Saldo · Stk · Comprom · E M · Fecha últ. OC · … (`negrita` de `_adsXlsxFormato`, xf 5).
- **v28.00 (Luis, 07/10): TODAS las celdas del Excel van centradas en VERTICAL** (B, L y M incluidas; antes el texto a la izquierda quedaba abajo). Lo horizontal sigue como su archivo.
- **v27.99 (Luis, 07/10, «ADS_stock_10d_20261007_5», *"así tal cual"*)**: col G (Fecha últ. OC) 8 · L (Entr. est. x tall.) 19,14 · escala de impresión 75; el resto como la v27.91.
- **v27.98 (Luis, 07/10): en el Excel de stock «Entr. est. x tall.» va «Nombre: cajas»** (`Pettofrezza: 0`, un renglón por tallerista de la OC actual, sin %; `estCaj` de `_adsStockCalc`). Retira el «sólo el número» de la v27.94. La pantalla (tooltip) sigue con % y cajas.
- **v28.43 (Luis, 07/10): la pestaña Stock se ORDENA por el saldo del lapso elegido** (10/20/30), de mayor déficit a menor (antes siempre por el de 10 d). **El semáforo del botón muestra ACUMULADOS**: 10d = quiebran a 10 · 20d = quiebran a 20 (incluye los de 10) · 30d = quiebran a 30. Retira el «recién quiebra» de la v27.22.
- **v28.42 (Luis, 07/10): la pestaña Stock se ORDENA por el saldo del lapso elegido** (10/20/30), de mayor déficit a menor (antes siempre por el de 10 d). **El semáforo del botón muestra ACUMULADOS**: 10d = quiebran a 10 · 20d = quiebran a 20 (incluye los de 10) · 30d = quiebran a 30. Retira el «recién quiebra» de la v27.22.
- **v28.44 (Luis, 07/10): la Entrega est. usa la ENTREGA PROY. cargada a mano en la OC vigente** (`Ordenes_Compra.gv_entrega_proy`, consultada al tallerista) en vez de la estimación, por tallerista. **v28.47 (Luis): NO se escala al plazo** — la OC completa ya ES la cobertura (30 días × índice). Entrega est. = cuánto de la OC VIGENTE va a entregar cada tallerista: lo declarado o, sin dato, cantidad de la OC × el % que viene entregando en el período; menos lo ya recibido de esa OC. Rótulo «Entrega est. OC». El tooltip dice «cargado en la OC» y el número va subrayado punteado. Lectura rota = queda el ritmo. `tests/ads-entrega-proy.cjs`.
- **v28.64 (Luis, 08/10): «Entrega est. OC» va X/Y, una fila por tallerista**: X = lo proyectado de la OC vigente (lo cargado en la OC; si la casilla está VACÍA = OC × % que viene entregando, con **\***; un 0 cargado es dato, sin \*), Y = lo pedido en esa OC (`estXY`). Un tallerista con 0 % en el período da 0\* de estimado: es la cuenta, no un bug. `tests/ads-entrega-proy.cjs`.
- **v28.86 (Luis, 08/10): Pend. est. = Entrega proy. de la OC si está cargada; si no, la OC vigente × el % que entregó el tallerista en el último período CERRADO** (`gv_ads_talleristas(n, false)` → `_ads.tallCerr`), menos lo ya recibido. Antes el % incluía la OC vigente y lo recibido se contaba dos veces (Garcia 550: 247 × 14 % − 35 = 0). Medido 08/10: sólo 248 tiene Entrega proy. cargada (83), y casi todos los talleristas entregaron 0 en el período cerrado, así que el 0* es real.
- **v28.92 (Luis, 08/10): Excel de stock = la tabla de la pantalla** (Cód · Descripción · Tallerista · Stk · Comp. · E.M. plazo · Saldo en negrita · Últ. OC · Pedido · Recib. · Pend. est., una sub-fila por tallerista). **Excel de talleristas SIN columna Tallerista**: una fila-título por tallerista con su % (combinada, negrita, fondo gris; `titulos` de `_adsXlsxFormato`) y debajo sus artículos.
- **v28.91 (Luis, 08/10): la Entrega proy. de la OC = lo que el tallerista dice que entrega EN LA SEMANA de la OC** (X = eso − lo ya llegado desde la OC); si X pasa a Y se deja así (D4, no topear). Pestaña Stock ordena Cód · Descripción · Tallerista. Se fueron los renglones explicativos de las dos pestañas (v28.90).
- **v28.89 (Luis, 08/10): Pend. est. = X/Y por tallerista de la OC vigente**: Y = pedido − ya entregado; X = Entrega proy. cargada en la OC (vacía ≠ 0) o, sin dato, OC × % del período cerrado (con *), menos lo ya entregado. X puede pasar a Y si declararon más de lo que falta.
- **v28.85 (Luis, 08/10): la letra de las dos pestañas de ADS crece con la pantalla** (`font-size:clamp(14px,1.1vw,26px)`; anchos y rellenos en em), datos centrados en vertical, descripción cortada con «…» y el texto entero en el tooltip.
- **v28.84 (Luis, 08/10, «optimizame la tabla»)**: «Pend. est.» muestra sólo X (la Y era el mismo número que Pedido), rótulos cortos (Comp. · Saldo · Recib.), celdas de 3 px. ⚠ `.map(_adsN)` le pasa el índice como decimales (salía «87,0» en la 2.ª fila): siempre `map(function (v) { return _adsN(v); })`.
- **v28.83 (Luis, 08/10): Pedido y Recibido son los de la ÚLTIMA OC**, una línea por tallerista (como Estim. pend.), no la suma del período.
- **v28.82 (Luis, 08/10): sin recuadro «Período»**: a la derecha del Saldo van Últ. OC · Pedido · Recibido · **Estim. pend.** con el mismo encabezado que el resto (sin %), tabla `ads-stk` en 15 px. Estim. pend. = X/Y por tallerista con **X = lo que FALTA** (proyectado de la OC vigente − lo ya recibido; * si la casilla está vacía), Y = lo pedido en esa OC.
- **v27.92 (Luis, D3, 07/10): saldo = disponible − el MAYOR entre comprometido H d y Est. Madre H d, NO la suma** (lo comprometido ya es parte de la venta que mide la Est. Madre; sumarlos contaba dos veces). Quiebres 39/61/88 → 32/46/67. `gv_ads_stock2` (marcador `v27.92-max`), centinela, `sql/gv_ads_saldo_max_v2792.sql`.
- **v28.56 (Luis, 08/10): la columna es «E.M. plazo Xd» = Est. Madre × max(0, X − días que tarda en salir) / 30, y saldo = disponible − comprometido − E.M. plazo** (se SUMA, no el mayor): los pedidos que entran en el plazo salen recién L días después. L = promedio (entrega − fecha del pedido) de las NP web con entrega en las últimas 2 semanas (`gv_ads_lead_auto`, 12,7 d al 08/10) salvo que un supervisor lo fije en ADS → Stock «Tarda en salir» (`Stock_Config.ads_lead_dias` por `gv_ads_lead_guardar`; vacío = automático). 550: −57 / −93 / −127; semáforo 17 / 37 / 60. Retira el «mayor» de la v27.92. Centinela 351. `sql/gv_ads_em_plazo_v2857.sql`, `tests/ads-em-plazo.cjs`.
- **v28.59 (Luis, 08/10, D4): la E.M. plazo usa la DISTRIBUCIÓN real de lo que tarda un pedido en salir** (no el promedio fijo): cron **146** `gv-ads-lead-diario` (04:19 ART) guarda en **`GV_ADS_Lead`** el promedio y la curva F(d) de las NP web entregadas en las últimas 2 semanas; `gv_ads_em_dias(H)` = Σ_{t=0}^{H-1} F(H−t) días de Est. Madre (al 08/10: 2,14 / 8,36 / 18,26 de 10/20/30). Si se escribe a mano en «Tarda en salir» queda guardado (`Stock_Config.ads_lead_dias`) y vale el escalón max(0, H − días); el botón **«%»** («Promedio real de las últimas 2 semanas») vuelve al automático. 550: −64 / −97 / −131; semáforo 21 / 40 / 62. Centinela 351 (`ld\.e10`). Y ADS escribe el código con el cero adelante (`_adsCod`, 58 → 058, regla v16.23). `sql/gv_ads_lead_distribucion_v2859.sql`, `tests/ads-em-plazo.cjs`.
- **Saldos en cajas ENTERAS (v27.32, Luis D11)**: quiebre sólo si falta media caja o más (antes −0,3 de una Est. Madre de 1 caja/mes contaba). Rojo 45 → 40. `sql/gv_ads_saldo_cajas_enteras_v2732.sql`.
- Rango y umbral se guardan en `Stock_Config` **sólo con «Guardar para el badge»**: cambiarlos sin guardar vale para esa
  pantalla y se pierde al cerrar.
- **Excel (v27.34, Luis)**: «Descargar Excel» en Talleristas (una fila por tallerista + artículo) y en Stock un botón por rango (10 / 20 / 30 días, sólo lo que quiebra a ese horizonte). La pantalla y el Excel usan la misma cuenta (`_adsStockCalc`). **v27.40: el formato es el del Excel de Luis** (`_adsXlsxFormato`): talleristas sin «% tallerista», anchos fijos chicos (los de su archivo: 11,14 · 6,57 · 23 · 5,14 · 5,29 · 5,86 · 4 · 6,57 · 5,86 · 6), rótulo de alto 45 centrado con ajuste, datos centrados salvo tallerista / descripción / dist., Arial 10, fila 1 congelada, zoom 130 y al imprimir entra a lo ancho (A4 vertical). El de stock va con el mismo molde y rótulos abreviados (Comp. · Días cob. · Fecha/Ped./Rec./% últ. OC, v27.42) para que ninguna palabra se parta; Proporción al ancho de su dato (tope 24). **Optimización horizontal: no ensanchar columnas.**
- `sql/gv_ads_alertas_damian_v2720.sql`, `sql/gv_ads_excedente_semaforo_v2722.sql`, `tests/ads-alertas.cjs`.

## 🗄 RETIRADO — sólo revisar si se pregunta por algo ANTIGUO que no está arriba

> Reglas, versiones y hallazgos que **ya no valen**. Se guardan como historia, no como instrucción.
> **No leer esta sección en el trabajo normal**: sólo cuando alguien pregunta por un comportamiento viejo
> y no aparece en las reglas vigentes de arriba. Nada de acá se vuelve a aplicar sin un pedido explícito.

- «Entregado = `cantidad_recibida` (imputado a la OC)». Retirado en la v27.28: Entregado = lo que recibió Virgilio.

- ~~**Días cobertura (v27.62, Luis D16)**~~ (retirada en v27.78): (Stk − Comp. H) ÷ (Est. Madre mes ÷ 30). Si Stk no cubre lo comprometido → **0** aunque no tenga Est. Madre; si sobra y no hay Est. Madre → **«sin venta»** (antes quedaba vacío: 231, 233, 567).

- v28.45: «Entrega est. × H/7». Retirado en la v28.47: la OC completa ya es la cobertura, no se escala.
