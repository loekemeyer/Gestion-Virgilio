# Integración Gestión Virgilio ↔ GP2 (spec para el repo `gestion-virgilio`)

Escrito el 2026-09-11 desde GP2. **Del lado de GP2 ya está todo hecho y probado** (RPC en el schema
`GP2`, con EXECUTE para `anon`/`authenticated`). **Del lado de Virgilio, las secciones 1 y 2 están
HECHAS en `gestion-virgilio` v14.95** (2026-09-11: `index.html` módulo INS, helper `insGp2Rpc` +
`_insGp2*`; nota en su `GUIA-PROYECTO.md`). La sección 3 (cajas SC/SP) queda pendiente de definir
dónde entra en la UI de Virgilio.

Los dos programas viven en el **mismo proyecto Supabase** (`hrxfctzncixxqmpfhskv`): Virgilio ya
llama funciones de GP2 con `supabase.schema("GP2").rpc(...)`. No hay puente ni copia de datos.

## 0. Dónde se engancha en Virgilio

Botón **INS** (📦) de la botonera → `insumoChooser` → **RI** «Recibir insumos» / **EI** «Entregar
insumos» / **SC** «Salida a Cervantes». RI y EI escriben `Movimientos_Stock deposito='insumos'`
(`tipo recepcion_insumo` +delta / `entrega_insumo` −delta) con origen/destino en **texto libre**
(`askInsUbicacion`) y las bolsas plásticas en unidad «Bolsas» con códigos propios: `PP`, `ABS`,
`AI`, `NV`, `NR`, `N25`, `PE`, `PS` (`EBA` discontinuo, no existe en GP2).

**Regla**: el ledger de Virgilio se sigue escribiendo igual que hoy (las bolsas viven en los dos
catálogos «hasta que se unifique todo»). Lo que se agrega es que, **cuando el insumo es una bolsa
plástica**, además se llama a GP2. GP2 es el que manda (stock, OC, inyectores); Virgilio espeja.

Cómo saber si un insumo es una bolsa GP2: su `cod` está en `material_virgilio_bundle().materiales[]
.codigo_virgilio`. Si no está (cajas, flejes, importados…), el flujo sigue como hoy sin GP2.

## 1. EI «Entregar insumos» → bolsas a un INYECTOR

Hoy el destino es texto libre. Para una bolsa el destino tiene que ser **un inyector** (lista
cerrada) y el envío descuenta el stock de Virgilio en GP2 y se lo suma al inyector.

```js
// al abrir EI con una bolsa: qué inyectores hay y cuántas bolsas le faltan a cada uno para sus OC
const { data: mv } = await supabase.schema("GP2").rpc("material_virgilio_bundle");
// mv = { kg_x_bolsa: 25,
//        inyectores: ["JL Matriceria","Kollplast","Pat Bet Plast","Pettofrezza Rafael"],
//        materiales: [{ comp_id, codigo:'2405', codigo_virgilio:'PP', descripcion, kg_en_virgilio,
//                       bolsas_en_virgilio,
//                       inyectores: [{ proveedor, kg_en_inyector, kg_requerido_oc, kg_a_enviar, bolsas_a_enviar }] }] }
// -> en vez de "¿A dónde lo envías?" libre: botones con los inyectores, y al lado de cada uno
//    "le faltan N bolsas" (bolsas_a_enviar del material elegido). Sugerido = bolsas_a_enviar.

// al confirmar (además del insert en Movimientos_Stock de siempre):
const { data, error } = await supabase.schema("GP2").rpc("enviar_material_virgilio", {
  p_cod_virgilio: "PP", p_bolsas: 4, p_inyector: "Pat Bet Plast", p_legajo: "77", p_nota: null
});
// data = { ok, movimiento_id, codigo:'2405', codigo_virgilio:'PP', bolsas:4, kg:100, kg_x_bolsa:25,
//          virgilio_antes, virgilio_despues, inyector_despues, virgilio_negativo }
// virgilio_negativo === true -> GP2 quedó en negativo: mostrar aviso (se mandó más de lo que GP2 cree que hay).
```

Errores (`error.message`): código que no es una bolsa GP2, inyector que no existe / no es inyector,
bolsas ≤ 0. Si GP2 falla, **no** escribir el movimiento de Virgilio (o marcarlo pendiente): la idea
es que los dos ledgers digan lo mismo.

## 2. RI «Recibir insumos» → bolsas contra la OC de GP2

Las bolsas las compra GP2 (`Compras/OC_GP2.html`, un solo proveedor por material, el más barato) y
**se entregan en Virgilio 2788**. El Master Bach por ahora se entrega y stockea en Cervantes: esas
OC **no** aparecen acá.

```js
// 1) qué OC de material están por llegar (borrador/enviada, todos los items del sector 14)
const { data: ocs } = await supabase.schema("GP2").rpc("oc_pendientes_virgilio");
// [{ oc_id, numero, proveedor, cod_prov, estado, creado_en, fecha_entrega_estimada, nota,
//    items: [{ item_id, comp_id, codigo, cod_virgilio:'PP', codigo_isis_ch, descripcion, unidad:'kg',
//              cantidad, recibido, pendiente, pendiente_bolsas }] }]

// 2) llegó el camión: el operario elige la OC, carga las BOLSAS de cada material y confirma
const { data, error } = await supabase.schema("GP2").rpc("recibir_oc_virgilio", {
  p_oc_id: 21,
  p_items: [{ cod_virgilio: "PP", bolsas: 14 }, { cod_virgilio: "ABS", bolsas: 1 }],   // o {comp_id, cantidad} en kg
  p_remito: "0001-00012345",
  p_legajo: "77"
});
// data = { ok, oc_id, numero, estado ('recibida' cuando se completó), recepciones: [{comp_id, kg, recepcion_id, oc_cruzada}] }
```

Propuesta de UI en RI: cuando la ubicación de origen es un proveedor de material (o directamente un
paso previo «¿Es una OC de material plástico?»), combo de OC (número + proveedor + fecha estimada),
una fila por item con `pendiente_bolsas` precargado (letra grande, `inputmode="numeric"`), remito
(ya lo pide `askInsDocumentacion`), confirmar. El movimiento de Virgilio (`recepcion_insumo`) se
escribe igual que hoy.

Qué hace GP2 por adentro: por cada item llama a `crear_recepcion_insumo` → movimiento `compra` al
sector 14 (ubicación «Sector Materia Prima Plástica (en Virgilio)»), cruce FIFO contra las OC
abiertas de ese material (`orden_compra_item.recibido`), y la OC pasa a `recibida` sola cuando
está completa. Errores: OC inexistente / ya recibida o anulada, código que no está en esa OC,
cantidad ≤ 0.

## 3. Cajas/cajones de Sector Crudo / Procesado guardados en Virgilio

Virgilio guarda cajas de piezas (crudo y procesado) que son de Cervantes. En GP2 eso es **otro
depósito**: ubicaciones tipo `virgilio_sector` («Sector Crudo en Virgilio», «Sector Procesado en
Virgilio»). Un traslado es un movimiento `traslado`:

```js
// cajas que van de Cervantes a Virgilio ('ida') o vuelven ('vuelta'). p_cantidad en UNIDADES
// (uni_x_cajon está en GP2.componente si se carga por cajón: cantidad = cajones × uni_x_cajon)
await supabase.schema("GP2").rpc("traslado_virgilio", {
  p_comp_id: 46, p_cantidad: 2144, p_sentido: "ida", p_nota: "1 cajón L8"
});
// -> { ok, movimiento_id, sentido, stock_cervantes, stock_virgilio }
```

Para listar qué hay en Virgilio de cada sector: `stock_sector_bundle(1)` / `(2)` →
`filas[].en_virgilio` (o consultar `GP2.inventario` por `ubicacion_id = ubicacion_virgilio_id`).
Buscar componentes por código: `GP2.componente` (`codigo`, `sector_id` 1/2, `uni_x_cajon`).
Dónde entra en la UI de Virgilio: a definir (¿el mismo INS con una categoría «Cajas Cervantes»?).

## 4. Lo que NO cambia

- Las entregas de talleristas y prov AT siguen como hoy (`"Entregas Tallerista Virgilio"`,
  `"Entregas Prov AT"`, `gv_oc_aplicar_recepcion`); GP2 las espeja solo.
- «Salida a Cervantes» (SC) es de terminados, no de insumos: no toca nada de esto.
- Virgilio no escribe tablas GP2 a mano: **siempre por RPC**.
