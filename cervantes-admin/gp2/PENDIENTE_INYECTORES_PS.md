# Inyectores — material por pieza: CERRADO (2026-09-15)

**Giro respecto de lo que yo creía:** el modelo de inyección **ya estaba en la base** vía
`componente.material_id` (la resina que usa cada pieza) + ubicación de inyector +
`enviar_material_inyector` + la pantalla `Compras/Inyectores_GP2.html`. **NO hubo cirugía de
rutas ni cambio de costeo**: las piezas se costean por su **precio de compra** (`origen='precio'`
en `v_costo_componente`), no por el material; `material_id` solo maneja la **demanda de resina**
(cuánta bolsa mandarle al inyector) y el descuento de resina al recibir la pieza.

## Estado final (48 piezas; PEP5 "Mango Madera" queda sin material a propósito: es madera)
- **45 ya tenían `material_id` correcto** (coincidía con la planilla del usuario, `db/Conteo_y_Pedido_Sector_Plastico_VACIO.xls`).
- **Se completaron/corrigieron 3, con los datos que dio el usuario (2026-09-15):**
  - **PA3** (Muñeco Antiderrame) → **Santoprene** (`SANTO`, id 930, creada sin precio) + kg 0,008 (de la planilla).
  - **PC16** (Inserto Chef) → **PP 2630** + kg 0,0038.
  - **PB8A** (Mgo Sacac Plast) → cambiado de PP a **ABS** ("seguí lo que dice la planilla").
- **Santoprene creada sin precio** (`componente` sector 14 + inventario 0 en ubic 57). Hasta que
  tenga precio, la demanda/costeo por material de PA3 no computa (PA3 igual costea por su precio de compra).

## Invariantes tras los cambios
A2 (inyector con material sin ubicación) = 0. Sin stock negativo. Único invariante > 0 = AE=2,
**preexistente** (artículos 537/567 sin receta/ruta, no es de este trabajo).

## Lo que NO se hizo, a propósito
- **No se los convirtió en `proveedor_servicio`.** En GP2 los inyectores son **inyectores**
  (`proveedor_insumo` + `material_id`), NO `proveedor_servicio`. Modelarlos como PS con rutas sería
  un segundo modelo redundante que choca con el que ya existe.

## Cómo quedó en el Tablet (actualizado 2026-09-18)
Sí se les puede mandar la bolsa desde el Tablet, sin cirugía: `tablet_bundle` devuelve los 4
(JL Matriceria, Kollplast, Pat Bet Plast, Pettofrezza Rafael) como contraparte tipo `'inyector'`
con sus resinas, y `tablet_registrar` rutea el envío a `enviar_material_inyector` (el mismo RPC de
`Compras/Inyectores_GP2.html`, sin duplicar lógica). Desde **Tablet v1.14.0** tienen su **propio
botón "Inyectores"** en Enviar; entre el 15/09 y el 18/09 se los mostró adentro de "Prov. de
servicio" y el usuario pidió sacarlos de ahí.
