# Revisión del módulo 📦 Importación — 2026-09-26

**Pedido:** Thomas, 26/09: *"Mira el módulo de importaciones. Lanza agentes. Qué ves feo."*
**Cómo se hizo:** 8 revisores en paralelo (lógica de Pedidos, lógica de En curso / NTL / nacionalización,
SQL del repo, datos vivos, render Playwright, tests, doc, reglas del dueño) → 97 hallazgos crudos, 84
únicos. La verificación adversarial (2 agentes por hallazgo) y la síntesis **no corrieron** por el límite
semanal de agentes; lo de abajo lo verifiqué a mano contra la base (sólo SELECT) y contra el código, y
está etiquetado: **[Seguro]** = medido o leído en la línea · **[Probable]** = lo dijo un revisor con
evidencia y no lo repetí · **[Adivinando]** = relleno.

Ordenado por lo que cuesta plata primero. Nada de esto se tocó.

## Alto — compras: el número que decide el pedido a China miente

1. **[Seguro] Las PARTES se proyectan con la madre, no con la proyección única (rompe v22.68).**
   `vista_importados_partes` lee `vista_proyeccion_super` (proyeccion_madre) para los terminados de
   cada parte. Medido contra `gv_proyeccion_articulo` × uxb: 505C **39.925 vs 42.792 u/mes (−2.867)**
   → a 10 meses son **28.670 unidades de menos** en la cuchilla; 1000900 **−900**; 523C **−317**.
   La diferencia está en 099 y 713 (terminados de Chef): la madre trae **134 y 126** donde la única da
   **1.608 y 1.512** — cajas leídas como unidades. Además el stock de la parte suma
   `separar_pedidos + a_facturar` (lo comprometido, regla v19.85). Dónde: CTE `det` y `dep` de la vista,
   `sql/gv_importados_partes_stock_terminados_v1526.sql`.
2. ✅ **Arreglado en v22.93 (Thomas: *"no es lo mismo 809E en LK y 809E en CH"*): dos líneas, cada una con su FOB y su fila.** **[Seguro] 809E: el módulo funde LK y CH en una sola línea.** `ocgFetchImportados` agrupa por
   `cod_art` (`by[k]`, index.html ≈17052), y 809E es el único dual que en `Importados` va sin L.
   Hoy: LK proy 300 u/mes · stock 4.116 · en curso 1.632 ‖ CH proy 1.080 · stock 480 · en curso 7.200.
   Sumados, el sobrante de Loeke tapa lo que le falta a Chef. 437E/438E no lo sufren porque van
   `437EL`/`438EL` (v15.01). Regla del dueño: *"un dual NO es el mismo artículo, cambia el packaging"*.
3. **[Seguro] El «en curso» que resta el módulo no es el de los baches.** `Importados.pedido_curso`
   (espejo) ≠ suma de `GV_Importados_Baches` en curso en **17 códigos, 34.800 u**: 16.224 u de más
   (pide de menos) y 18.576 de menos (pide de más). 1546903 47.088 vs 36.000 · 816E 6.144 vs 9.984 ·
   702E 6.192 vs 3.024 · 525E 12.096 vs 14.400 · 119E 1.872 vs 0 · 589E y 812E 0 vs 1.440.
   `importados_set_curso` escribe el espejo sin resync.
4. **[Seguro] Si la base no contesta, Importados dice "nada que pedir".** `supaFetchAllSafe` devuelve
   `[]` en el catch (index.html:11886) y `ocgFetchImportados` arma la pantalla vacía: 📦 Pedidos y la
   sección importados de OC muestran cero a pedir sin un solo cartel. Es el pozo de *"una lectura rota
   no es un cero"*.
5. **[Seguro] Lo vendido sin stock no se suma a «a pedir».** `gv_importados_ordenes.stock_cajas =
   greatest(bruto − pedidas, 0)`: el exceso se pierde. Hoy **21 códigos, 187 cajas / 2.196 u**
   (590E 61 pedidas vs 2; 599E 42 vs 12; 360E 14 vs 0; 323E 13 vs 0; 566E, 982E, 957E, 606E…).

## Alto — operación: pedidos que van a salir sin la mercadería

6. **[Seguro] 3 NP diferidas por importado están programadas ANTES de su «no antes de».**
   `GV_PPP_Web_Diferido` ⋈ `PPP_Web_Programacion`: **LK 0206 → 29/09** (E37A, no antes del 29/11) ·
   **LK 0221 → 30/09** (E49A, 29/11) · **LK 0227 → 01/10** (E18C, 03/11). Se pickean sin el importado.
   Causa [Probable]: la fecha de reingreso se corrió después de programar; la tabla no guarda historial.
7. **[Seguro] 360E: se vende y se programa sin stock, sin pedido a China y con el cartel de reingreso
   apagado.** 13 cajas programadas · stock 0 · en curso 0 · en `GV_Reingreso_Excluido` · sin
   `reingreso_est`. La página no avisa nada.
   **Confirmado por Thomas (26/09): *"ese sí no hay"*.** Las 13 cajas son 5 NP: LK 0225 (E18C, 4 cj,
   01/10) · LK 0238 (E18F, 3, 01/10) · LK 0243 (E18G, 3, 01/10) · LK 0066 (E48C, 2, 30/09) · CH 0024
   (E18B, 1, 01/10). Proveedor Kangli. Sigue a la venta en la web (no está en `GV_Web_Oculto`); el
   cartel lo apagó Luis el 24/09 *"sin fecha de reingreso"*.
   ~~599E~~ **RETIRADO (Thomas, 26/09): *"599E tengo suelto para envasar, no está registrado en
   Virgilio porque está en Cervantes"*.** El stock existe; lo que falla es que el sistema no lo ve.
   Medido: no está en `Insumos` ni en `GV_Importados_Insumo_Map`, y la fila `599ES` de `Importados`
   (id 91) está en 0. Consecuencia: el módulo le calcula **stock 0 y a pedir ~240 u** (proy 24 u/mes ×
   10 meses) y las 39 cajas programadas contra 12 en góndola se leen como sobreventa. Para que lo vea,
   el camino que ya existe es el de `522ES → 522E`: el suelto como insumo + su fila en
   `GV_Importados_Insumo_Map`. Falta la cantidad y decidir si el depósito de insumos de Virgilio
   puede tener algo que está físicamente en Cervantes.
   Thomas, 26/09: *"no sé, creo que 1.200 uni"*. Cualquier número ≥ 240 u deja la compra en 0, así que
   el estimado alcanza para compras. **Lo urgente es otro:** hay 39 cajas programadas del 30/09 al
   02/10 (LK 0166 sola lleva 24) contra 8 libres en góndola: Cervantes tiene que envasar y mandar
   ~31 cajas (372 u) antes del martes 30/09.
8. **[Seguro] Renombrar un PI deja la plata colgada del nombre viejo.** `gv_importado_pedido_ref` sólo
   renombra `GV_Importados_Baches`; `GV_Imp_Pedido_CC` y `GV_Imp_Pagos` quedan con el `pedido_ref`
   anterior → en Plata (y en 📒 Cta. proveedor) *Falta* vuelve a ser el FOB entero y los giros
   desaparecen del pedido.

## Alto — seguridad: la v22.81 quedó a medias

9. ✅ **Cerrado en v22.95 (Thomas: *"Si"*), salvo `Stock_Config`.** **[Seguro] El maestro y la plata se escriben con la clave pública.** `pg_policies` hoy:
   `Importados.imp_upd_anon` (UPDATE anon, `using true`), `Importados_Volumen.impvol_ins/upd` (anon),
   `Stock_Config.scfg_insert/update` (anon: ahí viven la fecha global del carrito, el mínimo de 25k y el
   cutoff del stock), `Importados_Config` / `Partes_Map` / `Stock_Parte` con `ALL to authenticated
   using (true)`. Y **21 RPC de escritura SECURITY DEFINER** las ejecuta `anon` sin chequeo de
   supervisor (giros: `gv_imp_pago_add/borrar`; cuenta corriente: `gv_imp_cc_set`, `gv_imp_cc_deuda_*`;
   baches: `gv_importado_bache_add/editar/borrar/llego/embarque`, `gv_importado_pedido_fechas/ref`;
   NTL: `gv_imp_ntl_efectivo_*`, `gv_imp_prov_alias_set`, `gv_imp_carga_pedido_set`;
   `importados_set_curso`, `importados_marcar_llegada`, `gv_importados_resync`). El front las firma con
   `Bearer SUPABASE_KEY` (`_pedImpRpc`, index.html:21593). El commit v22.81 dice *"sólo con login de
   supervisor"* y la base no lo tiene.

## Medio

10. **[Seguro] Un giro tipeado «23.622» se guarda como 23,62.** `impPagoAdd`:
    `Number(String(mv).replace(/[^\d.]/g, ""))` toma el punto de miles como decimal (index.html:22667).
11. **[Seguro] Si falla `gv_imp_cc_lista`, Plata muestra pagado 0 y falta = FOB, sin aviso**
    (`impCursoReload`, catch que deja `cc = {}`).
12. **[Seguro] La cuenta corriente desaparece cuando el pedido llega**: `gv_imp_cuenta_corriente` cuelga
    de `gv_importados_pedidos_curso` (`estado = 'en_curso'`). Justo cuando hay que pagar el saldo, el
    pedido deja de tener plata en pantalla. 📒 Cta. proveedor (v22.91) hereda lo mismo.
13. **[Seguro] 💱 NTL filtra por nombre crudo**: `gv_imp_ntl_cuenta.proveedor` es `referencia` sin
    pasar por `gv_imp_prov_canon`, así que las fichas dicen *Fuyian*, *Xihin*, *Jason*, *Stephen
    Jiang*, *Chef*, *Tierra* y Zhixin no existe. Y la columna **Saldo** con filtro puesto es el saldo
    global de la cuenta (window sobre toda la hoja), no el de lo filtrado.
14. **[Seguro] Datos de En curso con huecos**: 323ES suelto (3.000 u, Hugo) llegaba el 22/09 y sigue
    en curso sin recepción; PI B260601 (Becky, u$s 23.622) llega el 29/09 sin embarque, sin giros y sin
    cabecera; 20 líneas sin fecha de embarque, 8 sin m³ (cuentan 0 en silencio), OL-10139 con 4 líneas
    sin llegada. Los 6 giros iniciales de la cuenta corriente siguen siendo el *seed* del 11/09 y
    `GV_Imp_Carga_Pedido` está vacía: ninguna carga del Excel se asignó a un PI.
15. **[Seguro] `GV_Imp_CC_Deuda` («formato papá») vive en la base con 6 RPC y sin archivo en el repo**;
    su vista `gv_imp_cc_deuda` es legible por anon y devuelve 0 filas en silencio (el pozo que v18.63
    cerró en 7 vistas).
16. **[Probable] Pantalla (render Playwright, 1366×768 y 390×844)**: la tabla de Pedidos tiene
    `min-width: 1366px` y en el monitor de 1366 «Baches» y «Acciones» quedan afuera; la celda Stock
    corta los chips (505C muestra «🧩+6694» por +66.942 y esconde 🧰114.000); en celular el pop-up de
    Baches corta Estado/Acciones (no se puede marcar Llegó) y el de Giros corta 🗑; Proveedores dibuja
    la Descripción con 0 px; m³ y FOB con punto decimal en Pedidos («12.23 m³», «0.072») contra coma en
    el resto; «A pedir u» en gris #94a3b8 (contraste 2,56:1); En curso / NTL / Giros estiran columnas
    para rellenar (Descripción 527 px).
17. **[Probable] Performance**: abrir 📦 Pedidos u OC recorre `vista_saldos_stock` tres veces en serie
    (~2,8 s, pico 6,7 s contra timeout de 8 s) y se repite tras cada guardado; cada solapa vuelve a pedir
    todo (💱 NTL: 6 RPC encadenadas por cada filtro).
18. **[Seguro] Repo y doc desfasados**: `gv_importados_ordenes` viva ≠ `gv_importados_ordenes_completa_v1634.sql`
    (v22.68/70/73 se aplicaron como parches sobre `pg_get_viewdef`); v22.70–v22.86 y v22.81 sin § en la
    doc de Supabase ni en ROLLBACK-PRODUCCION; la GUÍA del módulo son ~40 notas de versión sueltas, varias
    de pantallas que ya no existen; CLAUDE.md dice que el índice de importados vive en `Stock_Config` y
    vive en `Importados_Config` (`meses_objetivo = 10`, sin cambios desde julio); las tasas de
    nacionalización (35 % / 18 % / 3 % / IVA sólo en avión) están fijas en `_pedImpNacionalizar` sin
    fuente.
19. **[Seguro] Tests**: 16/16 verdes y todos en `run.sh`, pero **sacar «en curso» de la cuenta de a pedir
    deja los 5 tests del generador en verde**; sin test: baches, borrar giro, cargas, renombrar PI, PDF,
    los dos Excel, solapa Proveedores, override de master cajas; `pedimp-hecho` no mira a qué importado
    va el bache.

## Bajo (lista corta)

Fecha sin año (`15/01`) toma el año en curso y `31/02` pasa el parser · el Excel de Pedidos ignora el MC
editado, el proveedor elegido y «Solo Pedido» · el Excel de En curso nunca baja la vista Plata · borrar
un giro es DELETE físico sin rastro · «Cargar pedido ya hecho» es una RPC por renglón sin transacción ·
alias 323ES: Reingreso / Web / Cartel escriben un código que ninguna página vende · `reingreso_est`
compartido entre la fila LK y CH de un dual · el PDF al chino imprime 437EL junto a 437E · v22.73 (round
2 decimales) quedó redundante con v22.84 · 32 importados activos sin uxb y 6 sin FOB (a pedir «—», USD 0).

## Lo que se descartó o no se pudo medir

- Ningún hallazgo pasó por los 2 verificadores (límite de agentes): los 84 quedaron sin refutar. Los de
  arriba marcados [Seguro] los repetí yo; los [Probable] no.
- Sin medir: si el 323ES suelto entró físicamente por otro camino; las tasas aduaneras vigentes; qué ve
  hoy la página LK para los 4 códigos de OL-10139 sin llegada; el proyecto LK no se consultó.
- Lo que dio **bien**: `gv_reglas_perdidas` vacía · los 99 importados con proyección en
  `gv_proyeccion_articulo`: 0 secundarios con proyección, 0 no enteras, 0 con venta y proyección 0 ·
  0 overrides manuales · 0 a pedir negativos · proveedores todos en la lista de 7 · las 7 vistas de
  v18.63 siguen sin SELECT para anon · 0 diferidos vencidos · suite del módulo 16/16.

## Qué haría, en orden

1. Partes a `gv_proyeccion_articulo` y sin comprometido (1) · 809E en dos líneas como 437EL/438EL (2)
   · `pedido_curso` derivado de los baches, no espejo (3) · feed caído = cartel, no cero (4) · sumar
   el exceso vendido a «a pedir» (5).
2. Reprogramar LK 0206 / 0221 / 0227 después del reingreso (6) — decisión de Marianela · 360E:
   o pedido a China o sacar de la web (7) · 599E: registrar el suelto de Cervantes para que el módulo lo cuente (7).
3. Aplicar de verdad la v22.81 en la base + chequeo de supervisor en las 21 RPC (9).
4. Renombrar PI que arrastre cabecera y giros (8) · monto con coma/punto (10) · CC que no muera al
   llegar (12) · NTL con alias y saldo filtrado (13).
