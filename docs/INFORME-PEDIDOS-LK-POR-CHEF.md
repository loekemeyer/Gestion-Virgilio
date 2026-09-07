# Pedidos de clientes LK cargados por la página de Chef — informe (2026-09-07)

Pedido del dueño: *"lanzá un agente para entender qué pasa con los pedidos de clientes de LK que se cargan por Chef"*.
Investigación de sólo lectura sobre el repo y las bases (Virgilio `hrxfctzncixxqmpfhskv`, LK `kwkclwhmoygunqmlegrg`).

## Recorrido real, paso a paso

**Premisa: no existe "cliente LK" en el pipeline.** La empresa del pedido la decide **la página por la que entró**, nunca
el cliente. Un pedido de `chef_orders` es `empresa='chef'` de punta a punta. El único cruce entre padrones es por **CUIT**
(vista `gv_clientes_lk_ch` en LK, 357 pares: Gifel 2715/CH, P&M Bazar 2701/CH = 4044/LK, El Martillo 2643/CH = 3831/LK,
Torres y Liva 271/CH = 288/LK; con el mismo número en las dos: Horcada 85, Salamone 269, Medl 105).

1. **Llegada.** `gv_pedidos_web_np_chef` (LK) devuelve `empresa='chef'`, `cod` = código **Chef**, razón social de
   `chef_padron`, bloques de 15, dirección de `chef_customer_delivery_addresses`. Etiqueta `CH 0003` (v13.70: contador).
   En ningún lado se mira el padrón LK para un pedido Chef: ni `PPP_Web_Programacion.cod_cliente`, ni zona, ni geo
   (`GV_Geo_Cliente` PK `(cod, dir_key)` sin empresa), ni valor (`gv_ppp_np_valor` → `precios_venta_chef`).
   A Programar usa la RPC vieja `get_pedidos_web_np_chef` (sin `direccion_expreso`); el job usa la buena.
2. **Programación.** `gv_pedidos_web_excluidos` para chef sólo cruza NP `^4` y cod Chef. El job corre LK y después Chef;
   `forzarChefDe` → `gv_cods_chef_de_lk` por CUIT: si el mismo CUIT entró hoy por LK, el pedido Chef entra prioritario ese
   día. Pero **la tanda es de UNA empresa** (PK `(empresa, codigo)`): termina en una tanda distinta de sus pedidos LK, en
   el mismo camión (v13.60) pero como dos tandas / dos remitos. `GV_Clientes_Reglas` es por `(cod, empresa)`: sólo Torres y
   Liva está espejado; Horcada 85 es prioritario sólo en lk.
3. **Picking / stock.** `empresaDeNp('CH 0003')` = CH; duales 437E/438E/439E/809E → góndola/stock CH; sufijo `L` → LK. El
   catálogo Chef es propio (701, 702E, 713…): un cliente LK pidiendo por Chef pide artículos Chef y el stock sale bien
   **para Chef**.
4. **Facturación.** Se baja el Excel ISIS (`facXlsBajar`); `_facXlsEmpresa` toma tope 15 y sucursal con `empresa='chef'`.
   **El archivo es uno solo, mezcla filas LK y CH** sin columna ni nombre que diga en qué ISIS importar; `cliente` = cod
   Chef; `vend` sale de `clientes_vendedor` (snapshot del padrón LK, sin empresa). Hoy un pedido CH **se factura por Chef,
   siempre**; no hay camino para pasarlo a LK.
5. **Entregados / remitos / WhatsApp.** `Entregas_Virgilio.cod_cliente` y `Facturacion_NP.cod_cliente` guardan el cod
   Chef sin empresa. Deudores cruza por CUIT (bien). "Avisar programación" resuelve vendedor por `clientes_vendedor[cod]`.

## Dónde se rompe o se comporta raro

1. **Vendedor equivocado en el Excel ISIS de una NP CH**: `vendBy[cod Chef]` contra el snapshot LK. Chef 213 Addoumie
   (cod Chef 2393) → `clientes_vendedor['2393']` = vend 2 = LK "Forrajería Trelew". Gifel 2715 / Elbantonio 2466 → vacío.
2. **Un solo Excel para dos ISIS**, filas mezcladas sin marca de empresa. Si en ISIS LK se importa una fila con cod Chef,
   cae en otro cliente.
3. **Si compras lo tipea en ISIS LK, Gestión no se entera y lo programa igual.** Caso real: Chef 208 P&M Bazar (cod Chef
   2701) está en Producción como **LK 98544/98545, cod 4044**, D55C, facturado 02/09, con artículos **recodificados a LK**
   (501, 502, 505… en vez de 701, 702E, 809E…). `gv_pedidos_web_excluidos` exige NP `^4` y cod Chef → no lo excluye.
   Sólo no se duplicó porque es anterior a `gestion_desde`.
4. **Reglas y geo por código sin empresa** (`GV_Clientes_Reglas`, `GV_Geo_Cliente`, `clientes_vendedor`): colisión cuando
   el mismo número es otro cliente en la otra empresa (Chef 2393 ≠ LK 2393).
5. **Tanda separada, remito separado, dos facturas** para el mismo CUIT el mismo día (por diseño, como hacía ISIS).
6. **A Programar lee la RPC vieja** de Chef (sin `direccion_expreso`): zona/geo de la sucursal del cliente para los de
   expreso.

## Casos reales en la base

- Chef 208 P&M Bazar → ISIS LK 98544/98545 cod 4044 (punto 3).
- Chef 200 El Martillo (2643/CH = 3831/LK): no está en ninguna tabla (§3.q).
- Últimos 60 días: **30 pedidos Chef de clientes que también existen en LK** (Addoumie, Super Clin, Zapata, Serpa, Andre
  Plast, Colucci, Renatek ×4, Arylo ×2…). Es el caso normal, no la excepción.
- Programados por Gestión en Chef: 216 Elbantonio (E01F, 14/09) y 217 Gifel (D69E, 15/09), sin espejo LK.

## Decisión del dueño (07/09, después del informe)

*"Es un cliente que pide por Chef, pero se factura por Chef directamente; para mí el pedido es para Chef. Se va a
facturar con la L al final cada artículo: el 505 se factura como 505L."* → Se mantiene como está el pipeline (pedido
Chef, cod Chef, factura Chef). La regla de la "L" ya vive en las páginas (`admin-supercot.js`, `addLSuffix = isChef`,
ítem `is_loke`) y en Gestión (`pkEmpresaArt`, `pkStripL`, `codEmpSplit`, m³ de `NNNL`); v13.71 la completa en
`gv_ppp_np_valor`. Lo que hizo compras con P&M Bazar (recodificar a LK y tipear en ISIS LK) va contra la regla.

Quedan sin decidir (puntos 1, 2 y 3 de "dónde se rompe"): vendedor de una NP CH en el Excel, Excel único para dos
ISIS, y detección de un pedido Chef tipeado en ISIS LK.

## Lo que tenía que decidir el dueño (preguntas originales)

1. Un pedido de un cliente LK entrado por Chef, ¿**se factura por Chef** (como hoy) o hay que poder **pasarlo a LK**? Si
   es lo segundo, hace falta un mapa de artículos Chef→LK (lo que hizo compras a mano con el 208) y el cod LK por CUIT.
2. ¿El Excel ISIS se **parte en dos archivos (LK / CH)** y el `vend` de una NP CH sale del padrón Chef (o vacío)?
3. Mismo CUIT por las dos páginas el mismo día: ¿alcanza con **mismo día / mismo camión en dos tandas** (hoy) o quiere
   una sola tanda mixta (rompe la PK por empresa y el picking por góndola)?
