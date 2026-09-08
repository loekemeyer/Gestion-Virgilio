# Mapa de conversiones de identidad en el pipeline — 2026-09-08

> **Para qué.** Gestión Virgilio va a ser la fuente de verdad del **stock**. El stock se
> mueve por **ventas** (pipeline de pedidos) y a futuro por **compras** (OCs). Los datos los
> informan las **páginas** (LK / Chef). Históricamente un pedido iba página → **ISIS** →
> volvía a entrar al pipeline, y en ese ida y vuelta se **convertían códigos e identidad**.
> Hoy los pedidos 100% del pipeline nuevo **no pasan por ISIS antes** (ISIS es sólo el último
> paso: facturar = bajar el Excel). Este documento mapea **cada punto donde un pedido cambia
> de código o identidad**, y clasifica cada uno en **herencia-ISIS (se puede sacar)** vs
> **necesidad-real (se queda)**, para decidir qué limpiar sin adivinar.
>
> **Es sólo un relevamiento. No cambia código.** Fecha del corte: 2026-09-08 (v14.45).

---

## 0. El principio

La identidad de una línea de pedido tiene **tres dimensiones**:

1. **Código de artículo** (qué producto).
2. **Empresa** (LK o Chef — define de qué **góndola** física sale el stock).
3. **NP** (a qué pedido/tanda pertenece).

El problema de fondo: por el camino de ISIS, la **empresa** se perdía y había que
**re-derivarla** (de los dígitos de la NP) o **codificarla dentro del string del código**
(sufijos ` LK`/` CH`). Casi todas las conversiones de abajo son consecuencia de eso.

**Norte propuesto:** que en el pipeline nuevo la identidad viaje como **campos de primera
clase** —`(empresa, cod_canónico, np_label, order_id)`— y que el **string del código quede
crudo** (tal como lo pidió la página, con su `L` si corresponde). Nada de codificar/decodificar
significado en el string a mitad de camino.

---

## 1. El camino de un pedido 100% nuevo (para stock)

```
página LK/Chef → Gestión (asigna NP: "LK 1350") → A Programar / tanda
  → picking (PKC)  → separado → a_facturar → facturado (drena stock)
```

Para **stock**, este camino **no hace round-trip por ISIS**. ISIS aparece sólo al final,
para facturar (bajar el Excel), y el stock ya se movió antes. O sea: la parte de stock ya
está casi limpia; lo que queda son conversiones heredadas.

---

## 2. Mapa — dimensión CÓDIGO DE ARTÍCULO

| # | conversión | dónde | qué hace | clasificación |
|---|---|---|---|---|
| C1 | `canon_cod` / `norm_cod` / `cob_norm_cod` (backend) · `_ocgNorm` (front) | vistas, joins, front | upper + trim + saca ceros a la izquierda | **Real, universal.** Canonicalización para matchear. No destruye identidad, no es ISIS. |
| C2 | `L` final (`505 → 505L`, `438E → 438EL`) | lo pone la **PÁGINA** (`paginach` / `admin-supercot.js` `addLSuffix = isChef`); `pkStripL` / `codBase` lo pelan para stock | marca "artículo de Loeke vendido por Chef" → stock sale de la góndola Loeke | **Real, identidad de origen.** No es ISIS. Ya consistente. |
| C3 | sufijo empresa ` LK` / ` CH` (`438E → 438E LK`) | `pkCodEmpresa` (front, al pickear) usando la góndola; el trigger `trg_normalizar_empresa_stock` lo pela y setea `empresa` | transportar la **empresa** del dual codificada en el string | **Mixto.** La necesidad (2 góndolas) es real, pero es un **workaround**: la empresa ya se conoce, se mete al string y se vuelve a sacar. Candidato #1 a reemplazar por un campo `empresa`. |
| C4 | `Equivalencias_Codigos` (8 filas) | tabla; `corrArt` (front) y `coalesce(e.cod_real, …)` en `reconciliar_..._etapa1` | ver §4 | **Mixto** (unas son parche de identidad perdida, otras unificación real). |
| C5 | correcciones `(np, art) → principal` | `corrArt` / caché de correcciones confirmadas por operario | arreglo puntual de un código mal cargado | **Real.** Corrección de dato, no ruta ISIS. |

## 3. Mapa — dimensión EMPRESA

| # | conversión | dónde | qué hace | clasificación |
|---|---|---|---|---|
| E1 | `empresa_de_np(text)` — dígitos `>90000 → LK`, si no `CH` | trigger de stock (fallback), `isis_*`, `gv_cruce_fc_asignacion` | adivinar la empresa **del número** de NP | **HERENCIA ISIS pura.** Sobre una NP web (`LK 1350`) da **CH** (mal). No debería tocar nunca una NP web. |
| E2 | `gv_empresa_de_np_texto(text)` — `^LK`/`^CH` manda, si no dígitos | vistas `gv_` (cruce, valuación) | empresa por **etiqueta** (con fallback a dígitos) | **Ya arreglada.** Es la versión correcta. El front tiene su gemela `empresaDeNp` (v12.64). |
| E3 | default de empresa por código (duales de `Equivalencias`) | §4 | si el dual llega **crudo**, asignarle una empresa fija por código | **Herencia ISIS.** Adivina; para una NP de Chef con `437E` da LK (mal). |

## 4. `Equivalencias_Codigos` en detalle (8 filas)

| cod_pedido | cod_real | tipo | clasificación |
|---|---|---|---|
| 437E | 437E LK | dual → default LK | **Parche de identidad perdida.** Correcto sólo si el 437E crudo es siempre LK; una NP de Chef con 437E quedaría mal. |
| 438E | 438E LK | dual → default LK | idem |
| 439E | 439E LK | dual → default LK | idem |
| 809E | 809E CH | dual → default CH | idem (809E cambia el default a Chef) |
| 438EL | 438E LK | `L` pickeado → góndola Loeke | **Real** (unificación L, C2) |
| 439EL | 439E LK | `L` pickeado → góndola Loeke | **Real** |
| 727 | 727E | unificación de código | **Real** (typo/baja de código) |
| 727EN | 727E | unificación de código | **Real** |

**Lectura:** las 4 filas de dual-default (`437E/438E/439E/809E → X LK/CH`) son una **red de
seguridad** para cuando el código llega **crudo** (sin empresa). En el pipeline nuevo la empresa
**viene de la página** (la NP es de LK o de Chef), así que ese default es una **adivinanza
lossy** que sólo acierta por costumbre. Las otras 4 (L y 727) son unificación real y se quedan.

## 5. Mapa — dimensión NP

| # | conversión | dónde | clasificación |
|---|---|---|---|
| N1 | NP la asignaba **ISIS** (5 dígitos) | histórico | **Ya resuelto.** Hoy la asigna Gestión: `gv_ppp_web_np_label` → `"LK 1350"`. |
| N2 | cast de la NP a número (`np::bigint`, sacar no-dígitos) | **16 funciones** (ver abajo) | **A revisar caso por caso.** |

**Las 16 funciones que castean NP/pedido/texto a entero:** `empresa_de_np`,
`gv_cruce_fc_asignacion`, `gv_espejo_corte`, `gv_espejo_np_pasa`, `gv_ppp_web_armar_pendientes`,
`gv_ppp_web_np_asignar`, `gv_ppp_web_tanda_agregar`, `gv_ppp_web_tanda_programar`,
`isis_api_pendientes`, `isis_pedido_json`, `notificar_picking_sin_base`, `ppp_web_armar_tandas`,
`ppp_web_resync`, `reconciliar_stock_articulo_rt`, `registrar_costo_api`, `wa_dashboard_rango`.

- Las `gv_ppp_web_*` / `ppp_web_*` castean **su propio número** de NP ya asignado (parte
  numérica del contador) → **OK**, no es herencia ISIS.
- `empresa_de_np`, `isis_api_pendientes`, `isis_pedido_json`, `gv_espejo_*` → **herencia ISIS**
  (asumen NP numérica de ISIS). Las `isis_*` están estacionadas (hoy la salida es el Excel).

---

## 6. Conclusión — qué se puede limpiar para pedidos 100% nuevos

**Se queda (necesidad real):**
- C1 canonicalización · C2 sufijo `L` de la página · C5 correcciones · E2 empresa-por-etiqueta ·
  las filas L/727 de Equivalencias · N1 (ya resuelto).

**Candidatos a limpiar (herencia ISIS / workaround):**
1. **E1 `empresa_de_np` por dígitos:** que **nunca** decida la empresa de una NP web. Enrutar
   siempre por la empresa explícita (etiqueta / campo). Ya lo hace la cadena `gv_` de valuación
   (v14.44); falta que el **stock** no dependa de derivarla.
2. **C3 sufijo ` LK`/` CH` como transporte:** llevar `empresa` como **campo** en la línea de
   picking/stock, en vez de codificarla en el string y volver a decodificarla. Objetivo: el
   string del código queda crudo de la página de punta a punta.
3. **E3 dual-default de `Equivalencias`:** innecesario para pedidos nuevos (la empresa viene de
   la página). Queda sólo como red de seguridad del caso "código crudo sin empresa", que en el
   pipeline nuevo **no debería ocurrir**.

**Restricción que manda:** el motor de stock (`Movimientos_Stock`, trigger, `reconciliar_*`) es
**compartido con Producción**. Cualquier cambio ahí es `create or replace` de objetos de
Producción → decisión del dueño, y aditivo. Por eso el orden natural es: primero garantizar que
la **empresa viaje como campo** desde la página/Gestión (lo nuestro), y recién después decidir si
se toca el motor para leerla de ahí en vez del sufijo.

**Próximo paso sugerido (cuando se decida):** definir el **libro mayor de stock** keyed por
`(empresa, cod_canónico, np_label, order_id)` para los pedidos nuevos — que es también la base
para disparar **compras (OCs)** desde la venta de la página sin drift.
