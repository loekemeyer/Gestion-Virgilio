# Racks — inner cajas × master caja (pendiente de cargar)

Artículos con stock en **racks** que NO tienen cargado cuántas **inner cajas trae una master caja**
(`cxm`). Sin ese dato, el módulo "¿Qué bajar primero?" los baja 1:1 y los marca **"s/master"**, y no
puede aplicar la regla de "mínimo 1 master caja".

Origen del dato hoy: `Racks_Planimetria` (`master_cajas` / `innercajas` por ubicación). No hay campo
de master a nivel producto — cuando esté completa la lista, se decide el mecanismo para cargarlo
(override por código o planimetría) y se aplica de una.

## ✅ Confirmados (el usuario los pasó — 2026-08-09)

| Cód | Descripción | inner × master |
|-----|-------------|:--------------:|
| 437E (y 437E LK / 437E CH) | Colador 16cm | **3** |
| 438E (y 438E LK) | Colador 20cm | **3** |
| 198E | Pelador Negro Dentado Loke | **12** |
| 988E | Espumadera Línea Premium | **12** |

## ➖ SIN master caja (se bajan 1:1 — es correcto, NO es un dato faltante)

Nacionales palletizados, pero **no vienen en master caja** con inner fijo → se bajan sueltos (1:1).
No hay que cargarles ratio; "s/master" es el comportamiento correcto para ellos.

| Cód | Descripción | En racks |
|-----|-------------|---------:|
| 505I | Pelador Plástico | 1310 |
| 501 | Abrelatas Manija A y E | 1018 |
| 505 | Pelador Plástico - Env. | 1000 |
| 504 | Afila Cuchillos | 634 |

## ⏳ Pendientes (completar el ratio)

| Cód | Descripción | En racks | inner × master |
|-----|-------------|---------:|:--------------:|
| 809E CH | (809 CH) | 336 | ___ |
| 809E LK | (809 LK) | 48 | ___ |
| 566E | Aceitera 100 ml | 128 | ___ _(además tiene góndola −29 a corregir)_ |
