# Diferencias Excel del usuario ↔ GP2 (audit por rubro)

Lista viva. Se va llenando a medida que revisamos cada rubro de Recepción de Insumos,
cruzando el Excel de conteo del usuario contra GP2. **Para consultar todo junto y decidir.**
Nada se aplica hasta que el usuario confirme. Cada ítem: qué dice GP2, qué dice el Excel, la duda.

> Recordatorio de fuentes: la **medida de los flejes vive en GP2** (`GP2.fleje_detalle`,
> `n_fleje` + `medida_mm`, la que muestra la web vía `recepcion_bundle`). El Excel del usuario es
> la fuente de verdad del negocio. La "casa del vecino" (`public.*`) solo para huecos.

---

## RUBRO: FLEJES (sector 5) + ALAMBRE (sector 13)
Excel: `Conteo_Gral_FLEJES_y_Alambre_VACIO.xls`. GP2: 56 flejes, 48 completos.

### A resolver (con duda para el usuario)

1. **Fleje 49 "Bisagra"** — medida 40 x 0,45.
   - GP2 (`IF12`): `discontinuo`, **sin proveedor**, **sin detalle/medida**, 0 recetas/rutas.
   - Excel (hoja *Listado Flejes*): **ACTIVO**, medida **40 x 0,45**, kg_x_uni ~0,0044 (Stock CD), consumo ~40/mes.
   - Proveedor: **NO figura en el Excel** — el 49 solo está en hojas sin columna de proveedor (Listado, Stock CD, Consumo); en las que traen proveedor (Pedido/FLEJES/Med Prov) no aparece. La medida 40 x 0,45 = idéntica al **fleje 27 "Virola Sacaf/Bisagra" (Basconia)** → apunta a Basconia (inferencia).
   - **DUDA:** ¿el 49 "Bisagra" es un fleje aparte del 27, o son lo mismo (duplicado)?
     - Aparte → cargar Basconia + medida 40 x 0,45 + sacar discontinuo.
     - Mismo que 27 → borrar el 49.

2. **Fleje 45 (`IF5`, código F5) = Pinza Ensalada** — GP2 **sin medida** en `fleje_detalle`.
   - GP2: id 199, "Fleje N° 45", código **F5**, proveedor **Aperam**, `medida_mm` = **null**.
   - Excel (cruzando por **código**, no por N°): F5 / cód 0145 = **Pinza Ensalada / Espumadera Inox, 117 x 0,8, Aperam** (hojas *Pedido Flejes*, *Stock Fleje Virgilio*, *Conteo Cervantes*).
   - **NO había contradicción** (corrijo la versión anterior): el 117x0,8 y el 123x0,8 son **dos flejes distintos** que la hoja *FLEJES* renumera:
     - Pinza Ensalada 117x0,8 = **F5 / N°45** operativas, pero *FLEJES* la llama **N°36**.
     - Cuchara Inox 123x0,8 = **F6 / N°43**, pero *FLEJES* la llama **N°45**.
   - **✅ HECHO (2026-09-08):** cargada `medida_mm = '117 x 0,8'` en `GP2.fleje_detalle` (componente 199). La pantalla ya la muestra.

3. **IE13 "Cremallera"** (proveedor GP2 = Importado) — GP2 **sin detalle**.
   - Excel: "Cremallera Espumante", medida **74,5 x 1,25** (JL Metales / Materiales San Roque).
   - Ojo: en el Excel el **fleje 80** se usa para DOS cosas — "C/Queso Alambre" (Ø4 x 380, Brawin) y "Cremallera Espumante" (74,5 x 1,25). Numeración pisada.
   - **DUDA:** ¿la cremallera lleva N° de fleje y medida 74,5 x 1,25? ¿proveedor real (Importado / JL Metales / San Roque)?

### Dato firme (listo para cargar cuando el usuario diga)

4. **IC3V** (Fleje 90 largo, Charcas) — GP2 **sin detalle**. Firme: **fleje 90 = N°16, Altrak** (igual que IC3, que sí lo tiene).
5. **FLEJE90_BRUTO** (Altrak) — GP2 **sin detalle**. Firme: **fleje 90 = N°16**.

### Estructural (no es un fleje puntual)

6. **CHAPA430** — GP2 sin detalle. Es **chapa** (1250×2500×0,8), no un fleje clásico. ¿Le cargamos medida igual o queda sin N°?
7. **El Excel tiene 86 N° de fleje; GP2 tiene 56.** Los ~30 de más son **casi todos el bloque de JL Metales** (PP Ajo, Aletas Cortas, Pinza Parrillera, Cuerpo Espumante, Descarozador Aceituna, Sacapizzero…) + materiales pendientes. **DUDA:** ¿son flejes NUEVOS a dar de alta, o JL Metales como **proveedor alternativo** de flejes que ya existen?
8. **Numeración inconsistente entre hojas del Excel y GP2** — el mismo material tiene distinto N° según la hoja (ej. "Arandela Chica Afila" = fleje 17 en una hoja, 11 en otra). Por eso el cruce por N° tiene ruido; conviene cruzar también por descripción + medida.

---

<!-- Próximos rubros: Cajas, Cartones, Partes Plásticas, Remaches, Bombillas, Garage -->
