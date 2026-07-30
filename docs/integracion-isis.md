# Integración Facturación app → ISIS (contabilidad)

Snapshot: **2026-07-30**. Estado: **facturación electrónica real ya operativa** en la
app (PV 11, prod). Falta el circuito para que esas facturas entren al ISIS para la
contabilidad / libro IVA ventas.

## Objetivo del usuario

- **Facturar desde Producción Virgilio** (la app) porque es más rápido para los
  empleados. A futuro, **auto-facturar** al cerrar/entregar la NP (sin click).
- Que después esas facturas **entren al ISIS** para la contabilidad (libro IVA ventas
  y, si hace falta, cuenta corriente del cliente).

## Contexto / restricciones

- La app emite Factura A por **web service** en **punto de venta 11** ("APP PRODUCCIÓN
  WS"). El ISIS emite en sus propios PV (4 y 5). Son sistemas separados: el ISIS **no
  ve** lo que emite la app.
- El módulo del ISIS "Procesar Facturas Electrónicas por método Web Service" **solo
  EMITE** (pide CAE de lo cargado en el ISIS). Si se usa para una factura de la app,
  la **duplica** (pide un CAE nuevo). ❌ No usar para esto.
- AFIP "Mis Comprobantes" sí muestra TODAS juntas (ISIS PV 4/5 + app PV 11), pero con
  demora de horas. Es la fuente consolidada para el contador.

## Cómo entra al ISIS (confirmado por el proveedor de Sistemas ISIS)

Sí se puede registrar en el ISIS una factura de venta ya emitida por otro sistema,
como **"Comprobante Manual"** (no electrónico, no fiscal → no pide CAE nuevo):

1. **Configurar un tipo de comprobante manual** (ej. "Factura Manual"), no electrónico
   ni fiscal.
2. Cargar por: **Ventas > Remito/Factura > Ingresar Comprobante Manual**.
3. Completar datos de la factura (cliente, artículos, importes).
4. En la confirmación, poner el **número real completo** (PV + 8 dígitos, ej.
   `0011-00000001`) en el campo **"Nro. Preimpreso"**.

Esto la registra para la contabilidad / libro IVA ventas **sin obtener un CAE nuevo**.

⚠ **No hay import masivo por archivo** para este fin — es **carga manual, uno por uno**.

## Plan del lado de la app

Como no hay import por archivo, la app no puede escribir sola en el ISIS (on-premise).
Lo que SÍ hace la app: **darle al operario un reporte con exactamente lo que tiene que
tipear**, para que la carga manual sea rápida y sin errores.

- **Feature a construir:** reporte / export **"Comprobantes para cargar en ISIS"**, que
  liste cada factura emitida (de `Comprobantes_ARCA`, entorno='prod') con:
  - **Nro. Preimpreso** = `PV(4) + "-" + nro(8)` → `0011-00000001`
  - Fecha, Cliente (razón social + CUIT), Neto / IVA 21% / Total
  - Artículos (cód + cajas + importe) — **solo si el ISIS los exige** (ver pregunta
    abierta)
  - Marca de "ya cargado en ISIS" (para no cargar dos veces) — a definir.

### Pregunta abierta (define el alcance del reporte)

- Al cargar un Comprobante Manual, ¿el ISIS **exige artículos** o alcanza con los
  **totales** (neto/IVA/total) para el libro IVA?
  - Solo totales → reporte simple.
  - Exige artículos → hay que persistir el `detalle` en `Comprobantes_ARCA` (hoy NO se
    guarda el detalle ítem por ítem; el `emitir_np` lo calcula pero solo loguea los
    importes) y mapear códigos app ↔ catálogo ISIS.

### Pasos siguientes (futuro)

- **Auto-facturar sin click:** emitir automáticamente al cerrar/entregar la NP. Se hace
  después de tener el circuito ISIS definido.

## Otros efectos a considerar

Al facturar por afuera del ISIS, ese sistema tampoco actualiza solo la **cuenta
corriente del cliente** ni el **stock** por esas ventas — no solo el libro IVA. Definir
con el contador/proveedor qué necesita el ISIS de esas ventas (mínimo: comprobante para
IVA; ideal: también CC del cliente).
