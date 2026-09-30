# Planillas de relevamiento vs GP2 — cruce del 2026-09-25

Sesión nocturna (thomas, claude-remote). Fuente: los 5 Excel "VACIO" que mandó el dueño
(Conteo Cartones, Conteo y Pedido Sector Plástico, Conteo Remaches, Conteo Bombilla, Relevamiento
Garage) contra la base GP2 viva (`componente`, `inventario`, `v_consumo_demanda`, `oc_bundle`,
`relev_factor`, `tablet_bundle`). **Todo en solo lectura sobre los datos**: no se tocó ningún dato
de producción. Lo que se cambió es código (1 función + respaldo `db/`), ver §6.

Cómo leer: **Esperado** = lo que dice/calcula la planilla. **Programa** = lo que devuelve GP2 hoy.
Las planillas vienen **vacías de stock** (todas las columnas de conteo y de "Stock CD/Taller/PS" en
0), así que el cruce de stock es estructural: con stock 0 el pedido de la planilla = su máximo, y
eso se compara contra el máximo que usa la O.C. del programa.

## 1. Lo que más pesa (explica casi todas las diferencias de cantidad)

| # | Caso | Esperado (planilla) | Programa (GP2) | Efecto |
|--:|---|---|---|---|
| 1 | Est. Madre (demanda) | hoja "Madre 7-26" / "10-25", columna *USAR Sugerencia* | `GP2.est_madre.proy_uni_mes` (espejo de `public.proyeccion_madre`) | GP2 da **mediana 0,70× en LOEKE y 0,44× en CHEF**. Sólo 2 de 199 artículos coinciden. Todo consumo y máximo de GP2 sale más bajo. Ej.: 513 18.204 vs 14.450 · 225 3.000 vs 1.476 · 789 1.056 vs 216 |
| 2 | Meses del máximo — Cartón | 3 meses | `ubicacion.meses_stock` = **6** | combinado con #1, GP2 pide **1,81×** lo de la planilla en cartón (137 códigos cruzados) |
| 3 | Meses — Remache | 6 meses | **4** | GP2 pide **0,61×** (12 remaches) |
| 4 | Meses — Bolsas plásticas (MP) | 4 meses (MB 6) | 2,5 y máximos `fisico` | PP: 4.285 kg vs 2.025 kg |
| 5 | Garage | máximo = capacidad física en cajones ("Max Caja Entra" × uni/cajón) | consumo × 2 meses | 0,69× (8 cruzados). GRJ4: 6 caj × 720 = 4.320 vs 3.480 |
| 6 | Plástico y Bombilla | 4 y 3 meses | 4 y 3 | coinciden; la diferencia (0,88× / 0,77×) es sólo #1 |

Detalle código por código (maestro, despiece y máximos): `RELEVAMIENTO_VS_GP2_2026-09-25_detalle.xlsx`.

## 2. Despieces: artículo × parte, planilla vs receta GP2

Diferencias de **cantidad por artículo** (no de Est. Madre):

| Parte | Artículo(s) | Planilla | GP2 | Nota |
|---|---|--:|--:|---|
| GRJ21A Filtro / GRJ21B Precinto | 550, 760 | 1 | **2** | GP2 pide el doble (8.100/mes vs 4.488). Duda D1 |
| V9 Remache Uña | 511 | 1 | 2 | Duda D2 |
| V8 Remache Doble Aleta | 723 | 1 | 2 | el hermano 523 lleva 2 en ambos. Duda D2 |
| PEP5 Mango madera cuch. untar | 519, 719 ("x2") | 1 | 2 | GP2 coherente con "x2" (E7 ×2, W5 ×2). Probable error de planilla |
| PEP9 Cuchillo untar | 718 | 2 | 1 | 718 = "Cuchillito de untar Plast **x2**": GP2 probablemente mal. Duda D2 |
| PEP4 Base afila | 114, 504 | 0,5 | 1 | la planilla separa PEP4A/PEP4B (azul/blanca); GP2 tiene uno solo |
| GRJ18 Bombilla pico de loro | 659, 759 | 1,5 | 1 | Duda D2 |
| BOM8B Tela manga | 280 | 1 uni | 1/950 rollo | **no es diferencia**: GP2 cuenta en rollos (decidido 04-09) |

Partes que la planilla pone y la receta GP2 **no tiene** (artículo vivo):
- `PC6` Ojales (609, 789, 856, 857, 709, 859) y `PB6` (859), `PA19` (789), `PEST1` (709). En el 863
  se sacaron a propósito el 21-09 (§4ew). Planilla: PC6 2.280/mes · GP2 134. Duda D3.
- `Q7E` Cartón 922 **existe en GP2 pero ninguna receta lo usa**; el 922 no tiene cartón (ya anotado
  como sospecha el 21-09; la planilla lo confirma: 922 → Q7E).
- `P1A` Cartón 760: la planilla le da cartón propio; GP2 le pone `CCG6B` (el del 550).
- BOM8 en 654/769: la planilla lo usa (resorte), GP2 compra GRJ4 armada a Cimarrón → correcto por
  decisión de make-or-buy, no se toca.

Artículos que la planilla pide y GP2 no tiene (no son error, ya conocidos): 573, 630-636, 809,
864, 828 y los 77 cartones de familias no cargadas (§1-decies).

## 3. Maestro: códigos, envases, pesos, proveedores

**Códigos que la planilla usa distinto (renombre pendiente, no alta):**

| Planilla | GP2 | Qué es |
|---|---|---|
| I4C | CART186 | cartón 186 — CONOCIMIENTO decía "posición no la tengo": **la planilla la da** |
| G8C (Cierra Bolsa x2, 058) | CART058 | ⚠ en GP2 `G8C` es la **Bolsa 836** (Vihal). Choque |
| E2B | CCE2B | cartón 581 |
| G6A | CCG6B | cartón 550 |
| D5A | CCC4 | cartón 546 |
| H2A | K5D | cartón 104 |
| A2A / V3A | CART500 / CART506 | la planilla los pone bajo AJ Adhesivos (¿pliego o cartón?) |
| GRJ20 | GRJ30 | Set Tapers (decidido 21-09) |
| GRJ7/8, GRJ1, GRJ9 | — | borrados/no cargados por decisión (506 sin GRJ7) |
| C3A, H4C, T4A | idem | la planilla tiene **dos** ítems con cada código: cartón (Pol) y etiqueta (Cia Integral, 10.000/paq). GP2 tiene uno solo |

**Envase (uni por bolsa/cajón) distinto — el Relevamiento cuenta por el de GP2:**

| Código | Planilla | GP2 | Riesgo |
|---|--:|--:|---|
| CV1…CV14 (remaches crudos) | bolsa 2 kg o 10 kg | bolsa **20 kg** (y la O.C. redondea a **25 kg**) | contar 3 bolsas de 2 kg carga 10× de más. Duda D4 |
| PA8A Buje Blanco | 5.000 | **33.000** (= su pedido mínimo) | probable dato mal cargado |
| PA7A / PA7B Pirolo | 2.500 | 6.000 | |
| PA12 Pirolo Rojo | 2.500 | 1.000 | |
| PC10 Mango espátula | 1.000 | 500 | |
| PC13 / PC14 Manguito | 1.200 | 2.400 | |
| PC8 Cachas | 500 | 1.000 | |
| PEP1 | 280 | 800 | ya anotado 04-09 |
| BOM8 Resorte bombilla | 500 | 4.783 | |
| EP10 / LLF8 | 500 / 650 | 851 / 698 | |
| GRJ4 / GRJ18 / GRJ19 | 720 | 960 | |

**kg por unidad:** BOM10 0,0075 vs 0,00963 · GRJ14 0,0465 vs 0,0293 · GRJ6 0,0159 vs 0,0133.
La planilla trae **V5C Rem. Afila = 0,2212 kg/uni** (GP2 0,00388): error de la planilla (le da
un máximo de 20.796 kg).

**Proveedor distinto:** PA8A/PA8B y PEST1 Kollplast (GP2) vs Pat Bet (planilla) · PCP3 Trefilados vs
Martin Facciolo (ya anotado) · PP Santa Rosa vs Indarnyl · PE Beta vs Santa Rosa · G8C Vihal vs Pol
(choque de código).

**Faltan en GP2 y la planilla los pide con consumo:** `CV15` Rem Tapón Hierro (984/mes; se cargó el
04-09 como id 617 y **hoy no existe**; no encontré registro del borrado) · BOM5, BOM6, BOM11,
Z2S, Z2SB, Z19A, AA6/AE10, Z32, BOM4, caño 170 mm (ya en §1-septies) · PA15, PA16 (consumo 0),
PB1, PB7/PB8 (renombres), PC2A/PC2B, PEP4A/B, PEP6 · GRJ15 Pintura, GRJ16 Despolvillador.

## 4. Recorridos probados

| Recorrido | Resultado |
|---|---|
| **Relevamiento** (`relev_factor` → `relev_total_uni`) | GRJ13, GRJ14, GRJ21A/B, Z21 **no tenían factor** (uni_x_cajon vacío) aunque tienen su caja cargada (`entrega_uni_x`): el conteo sólo aceptaba sueltas, contra la planilla que cuenta "Cajón/Bulto" de 100. **Corregido** (§6). Remaches: cuenta por bolsa de 20 kg (D4) |
| **O.C.** (`oc_bundle`: máximo − stock, luego norma) | cálculo consistente con su regla; las diferencias con la planilla son de insumos (§1) y no de código. Mínimos de plástico (`pedido_minimo_uni`) **coinciden** con la planilla en los 32 cruzados |
| **Tablet — Enviar a tallerista** | sugiere aunque el tallerista no tenga fila de inventario (PB2, PEP9, PV8, PV17 salen bien); sin error |
| **Est. Madre sync** (`fn_est_madre_sync`) | 43 filas quedan con "uni = cajas" porque el artículo no existe en GP2: sin efecto hoy (ninguna tiene receta) |
| **Invariantes** (`db/verificar.sql`) | 0 salvo AE=2 (preexistente, 567/537) y M=1 **falso positivo** (`reparto_guardar`, sin EXECUTE a propósito). Corregido el chequeo |
| **Lista de conteo** (hoja de conteo de la planilla vs lo que el Relevamiento GP2 pide contar) | ver abajo |

Qué pide contar GP2 que la hoja de conteo **no** tiene, y al revés (componentes activos):

| Sector | GP2 pide y la planilla no | La planilla pide y GP2 no |
|---|---|---|
| Plástico | D9, PA10B, PA13B, PA18B, PA4, PA4B, PA5, PA5B, PB5, PB8A/PB8B, PC15A/AB/B, PC2, PC3B, PEP3, PEP4, PINCEL590, PV8B | PA15, PA16, PB1, PB3, PB7, PB8, PC15, PC2A, PC2B, PC3, PEP4A/B, PEP6, PGRJ12/PGRJ12B (renombres o faltantes de §3) |
| Bombilla | C9, D14, I2, I3, Z21, Z25A, Z25B | BOM4, BOM5, BOM6, BOM11, BOM14 (caño 170), Z19A, Z2S, Z2SB, Z32, AA6/AE10 |
| Remache | CV13, CV18D, V18, V18D, W1B, W8, EST1, EST2 | CV10, CV15, CV16, CV17, "S/S" (Rem Plaquita = CV13 en GP2) |
| Garage | GRJ10A, GRJ22-GRJ28, GRJ30 | GRJ1, GRJ9, GRJ15, GRJ16, GRJ20 (=GRJ30); `GJR10` es typo de GRJ10 en la planilla |

Las hojas de conteo están atrasadas respecto de GP2 (partes nuevas del 09 al 24-09), y GP2 no tiene
las familias que la planilla todavía cuenta. Si el operario cuenta con el papel, esas filas quedan
sin contar en el programa.

## 5. Duplicados e inconsistencias de tablas (sin tocar)

- Códigos repetidos entre sectores: A1, A4, A8, A9 (Procesado/Caja) y Z22 (Procesado/Bombilla) —
  ya conocidos; se une por id.
- `C12` y `C12B` conservan una fila de inventario en **Sector Bombilla** (máx 1.656 c/u, stock 0)
  después de mudarse a Procesado/Crudo el 24-09; C12 no tiene fila en Procesado. Propuesta D6.
- Sin duplicados en recetas, BOM, rutas (0 rutas idénticas), artículos, proveedores, cod_prov;
  sin stock negativo ni inventario huérfano.
- Respaldo `db/` estaba desfasado de la base: 6 funciones (oc_bundle, talleristas_bundle,
  fabricar_stock, fn_est_madre_sync, cartones_para_reemplazo, stock_general_extra_bundle) y 1 vista
  con lógica distinta (`v_consumo_fleje_kg`). **Resincronizado** (§6).

## 6. Cambios hechos (código, no datos)

1. `GP2.relev_factor` (en la base + `db/funciones_GP2.sql`): fuera de cartón/caja/fleje, si la
   pieza no tiene `uni_x_cajon` usa su `entrega_uni_x` y rotula el envase con `entrega_unidad`
   (Cajas). Verificado: GRJ13 2 cajas + 10 sueltas = 210; PA1/GRJ5/CV1/cartones sin cambio. Los
   relevamientos abiertos (26 Bombilla, 36 Plástico) no tenían ítems contados.
2. `db/verificar.sql`: `reparto_guardar` pasa a la lista de funciones sin pantalla (reglas C y M).
3. `db/funciones_GP2.sql` y `db/vistas_GP2.sql`: 163/163 funciones y las 3 vistas desfasadas
   verificadas por md5 contra la base; fuera los 3 `__sim_*` ya borrados.
4. Suite `tests/ui/run.sh`: 58/58 antes y después.

## 7. Dudas para el lunes (por impacto)

- ~~D0 — ¿Qué Est. Madre manda?~~ **Resuelto** [Thomas 2026-09-26: *"Considerá la est madre de GP2"*].
  Manda `GP2.est_madre`; la de las planillas (7-26 y 10-25) no se usa.
  **Cruce con Gestión Virgilio** (`public.gv_proyeccion_articulo`, fuente única de Stock/OC/Importados
  allá desde v22.68): de los artículos vivos de GP2 coinciden todos (±1 caja por redondeo) salvo
  **8 a los que GP2 no les suma la familia**, porque el secundario no existe en GP2 y su venta se
  pierde: 580 Batidor Mini (GP2 114 uni/mes vs GV 708: el 580E aporta 49 cajas), 943E (+7 caj del
  336), 945E (+6, 332), 941E (+5, 338), 946E (+3, 335), 942E (+2, 334), 948E (+2, 333), 590E (+1, 548).
  En total GP2 deja afuera 75 cajas por mes (unas 900 uni). Seis artículos no tienen proyección en ninguna
  de las dos (231, 232, 233, 537, 567, 071): sin venta, igual en ambas. Propuesta D9.
- ~~D1 — GRJ21A/GRJ21B: ¿2 o 1 por artículo?~~ **Resuelto** [Thomas 2026-09-26: *"cada unidad del código 550 lleva dos filtros y dos precintos. El blister viene por dos"*]: GP2 (×2) está bien; el error es de la planilla (×1). Sin cambios.
- **D4 — Bolsa de remache: "depende"** [Thomas 2026-09-26]. Son dos envases distintos y no se tocó nada:
  la **bolsa del proveedor** es la de la planilla (2 kg la mayoría; 10 kg V3/V5/V7/V8/V9; 20 kg la
  cremallera) y la O.C. la pide en múltiplos de 25 kg (`remache_kg_x_bolsa`, dato del 18-09); el
  **cajón de 20 kg** de `uni_x_cajon` es el que va a Guazzaroni a niquelar (medido: 21 kg anotados por
  logística, §v_caj_contraparte). Pendiente: si el Relevamiento tiene que contar bolsas de proveedor,
  hay que cargar el kg/bolsa por código en `entrega_uni_x` y hacer que `relev_factor` lo prefiera en Remache.
- **D5 — Meses de máximo:** cartón 6 (planilla 3), remache 4 (planilla 6), MP plástica 2,5 (4).
- **D2 — Cantidades por artículo:** V9 en 511, V8 en 723, PEP9 en 718, GRJ18 1,5.
- **D3 — PC6/PB6/PA19/PEST1** en 609, 789, 856, 857, 709, 859: ¿van en la receta?
- ~~D6 — Datos propuestos~~ **HECHOS 2026-09-26** [Thomas: *"Avanzá si podés vos"*]: cartón `Q7E` en la
  receta del 922 (`articulo_componente` 979; consumo 274/mes); fila de `C12` movida de Bombilla a
  Procesado (id 124411; el trigger la recalculó a 1.165, regla 5 cajones, como su hermana C12B en
  Crudo); fila sobrante de `C12B` en Bombilla borrada (id 125353, stock 0); `PA8A` uni_x_cajon 33.000
  → 5.000; máximos `fisico` a PIEA 1, PIEB 1, PCP4A 800 y PCP2 145 kg (PCP2 ya estaba en kg).
- **D7 — Renombres de cartón** (I4C, E2B, G6A, D5A, H2A) y el choque G8C.
- ~~D9 — Familias en GP2~~ **HECHO 2026-09-26**: tabla `GP2.articulo_familia` (19 pares, copia interna
  de `Equivalencias_Familia`, RLS + policy SELECT, trigger que recalcula máximos) y `v_consumo_demanda`
  suma la Est. Madre del secundario al principal (el secundario queda en 0 aunque exista como
  artículo). Efecto medido: 13 componentes cambian de consumo — EP10, G7A, GRJ10A, ABPM, IVBCM 114 →
  702/mes; IVBLM 342 → 2.106; IF9 6.758 → 7.346; PEST1 684 → 1.178; Q7E 0 → 274 (por D6); A11,
  A9B, PINCEL590, CART590 +1 a +51. Máximos recalculados: 9 insumos, 68 filas de talleristas, 0 Prov AT.
  Ahora GP2 y Gestión Virgilio dan lo mismo (±1 caja de redondeo) en todos los artículos vivos.
  Invariante nuevo `AG` en `db/verificar.sql`: avisa si la tabla se desfasa de Virgilio (hoy 0).
- ~~D10 — Los máximos de tallerista no se recalculan solos~~ **HECHO 2026-09-26** [Thomas: *"Dale"*], con un
  diseño distinto al propuesto. Antes de tocar, 5 agentes lo analizaron y 1 de 2 refutadores tumbó la
  idea original (encadenar las 3 funciones en el trigger statement-level) con datos duros:
  - **Corrección**: la Tablet NO lee el máximo guardado del tallerista (calcula el techo en vivo). Lo leen
    sólo Proporciones_GP2 y la vista Talleristas de Stock General. La frase "afecta la Tablet" era falsa.
  - **Hallazgo mayor**: el sync diario de LK borra e inserta las 330 filas de `proyeccion_madre` de a una,
    en UNA transacción, y el trigger statement-level de `est_madre` corría el recálculo **658 veces por
    sync (~54 s; el DELETE solo 21,2 s, medido en pg_stat_statements)**. Encadenar talleristas ahí
    llevaba el DELETE a 76–200 s contra un `statement_timeout` de 120 s: riesgo de revertir el sync entero.
  - **Lo hecho**: `fn_recalc_maximos_insumos` → **`fn_recalc_maximos_diferido`**; los 4 triggers
    (`est_madre`, `articulo_componente`, `ruta_paso`, `articulo_familia`) pasan a **constraint triggers
    DEFERRABLE INITIALLY DEFERRED por fila** con bandera transaccional (`set_config` local + `txid_current`):
    al COMMIT corre UNA vez `recalcular_maximos_insumos()` + `recalcular_maximos_talleristas()` contra la
    Est. Madre final; un error adentro avisa (`raise warning`) y no tumba el sync. Prov AT queda afuera
    (techo 0 por regla del 24-09, 0 filas de inventario). Ninguna RPC que edite recetas/rutas lee el máximo
    en la misma transacción (verificado), así que nada cambia para las pantallas.
  - **Probado**: EP10 de Alex Escalante 702 → 700 a mano, `update est_madre … where cod='580'` (no-op),
    al COMMIT volvió a 702. Esperado en el próximo sync de LK: el DELETE baja de ~21.000 ms a < 500 ms
    (mirar `pg_stat_statements` del rol `lk_ppp_reader` el lunes).
  - **Limpieza de paso**: `recalcular_maximos_talleristas(false, null, true)` puso en null 13 máximos de
    tallerista sin ruta ni consumo (Gentile 9 filas, Cavallero 3, Cornejo PC8 404). Quedan 291 con máximo.
  - `db/tablas_GP2.sql`: el CHECK de `maximo_origen` no tenía `mb_2pct_por_color` (la base sí): corregido.
- **D8 — CV15** Rem Tapón Hierro: ¿se dio de baja a propósito?

### Auditoría propuesta (no ejecutada: tu regla pide "sí" para escribir)

```sql
select github_repo_problemas.registrar_problema(p_repo=>'loekemeyer/gestion-productiva-2.0',
  p_titulo=>'Relevamiento sin factor para piezas con caja de entrega (GRJ13/14, GRJ21A/B, Z21)',
  p_descripcion=>'relev_factor solo miraba uni_x_cajon; con caja cargada en entrega_uni_x el conteo solo aceptaba sueltas',
  p_categoria=>'bug', p_severidad=>'medio', p_modulo=>'Relevamiento',
  p_archivos=>array['db/funciones_GP2.sql'], p_sesion_id=>'session_01GJXazBYg8aEd9HYkSodRGL',
  p_detectado_por=>'thomas (claude-remote)', p_detectado_en=>now());
select github_repo_problemas.registrar_problema(p_repo=>'loekemeyer/gestion-productiva-2.0',
  p_titulo=>'db/ desfasado de la base: 6 funciones y v_consumo_fleje_kg tocadas en vivo sin refrescar',
  p_descripcion=>'el respaldo y test_contratos_db leian definiciones viejas (oc_bundle sin remache_kg_x_bolsa, fn_est_madre_sync con uxb)',
  p_categoria=>'documentacion', p_severidad=>'bajo', p_modulo=>'db',
  p_archivos=>array['db/funciones_GP2.sql','db/vistas_GP2.sql'], p_sesion_id=>'session_01GJXazBYg8aEd9HYkSodRGL',
  p_detectado_por=>'thomas (claude-remote)', p_detectado_en=>now());
```
