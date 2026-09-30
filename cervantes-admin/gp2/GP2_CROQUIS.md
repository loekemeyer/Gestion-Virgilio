# Croquis de GP2 — cómo funciona hoy (2026-09-13)

> Versión para mirar en el celular (misma info, dibujada):
> https://claude.ai/code/artifact/0004f23b-587f-4d5e-b8c8-bf313836955b

Una frase: **GP2 es un libro de movimientos sobre un catálogo normalizado.** La app nunca calcula
stock; inserta filas en `GP2.movimiento` y los triggers (`fn_movimiento_calc` +
`fn_movimiento_aplicar`) actualizan `GP2.inventario`. Todo sale del schema `GP2` (Regla 0).

---

## 1 · El circuito físico — la columna vertebral

**La cadena, dicha por el dueño (2026-09-13):**

```
OC → Recepción → Insumos → Producción (Alimentador/Balancines) → SC
   → Envío PS → Entrega PS → SP → Envío Tall → Entrega Tall → Virgilio
```

Eso es el espinazo: **una línea**, no una nube de sectores. Todo lo demás son ramas que se le
cuelgan.

```mermaid
flowchart LR
  OC["OC"] --> REC["Recepción"] --> INS["INSUMOS<br/>Fleje · Remache · Cartón<br/>Caja · Plástico · MP plástica"]
  INS -->|el fleje| PROD["PRODUCCIÓN<br/>Alimentador · Balancines<br/>(Mat N = pasos intermedios)"]
  PROD --> SC["SC<br/>Sector Crudo"]
  SC -->|envio_ps| PS["Prov. de Servicio"]
  PS -->|entrega_ps| SP["SP<br/>Sector Procesado"]
  SP -->|envio_tallerista| TALL["Tallerista"]
  TALL -->|"entrega_tallerista<br/>+ consumo de la receta"| TER["TERMINADO"]
  TER -->|recepcion_virgilio| VIR["VIRGILIO"]
  INS -.->|cartón · caja · plástico · bombilla · remache| TALL
  INS -.->|MP plástica| INY["Inyector"]
  INY -.-> TALL
  PAT["Prov. Art. Terminado"] -.->|lo trae ya hecho| TER
  VIR -.->|espejo| GV["Gestión Virgilio<br/>otro sistema"]
```

**La base dice lo mismo** (pasos de `ruta_paso`, contados el 2026-09-13):

| Tramo | Pasos | Qué confirma |
|---|---|---|
| Fleje → Crudo (matriz) | 120 (+91 vía `Mat N`) | la producción sale del fleje y termina en **SC** |
| Crudo → Procesado (prov. servicio) | 122 | el PS es el que convierte **SC → SP** |
| Procesado → Terminado (tallerista) | 173 | el tallerista arma desde **SP** |
| Terminado → Virgilio | 855 | todo cierra en Virgilio |
| Máquinas de producción | 70 balancín · 43 alimentador | **Alimentador / Balancines**, como se dice en la planta |

Dos precisiones que la cadena esconde y conviene tener:
- **`Mat N` (Sector Movimiento) es parte de Producción**, no un sector aparte: son las piezas
  a medio hacer entre matriz y matriz (91 pasos entran o salen de ahí).
- **No todo pasa por PS.** Hay 41 pasos de servicio que devuelven al mismo SC (procesos que no
  cambian de sector) y 14 rutas donde el tallerista toma directo de SC. La línea es el camino
  normal, no una obligación.

Quién hace qué **no se declara en ninguna tabla suelta: lo dice la ruta**. Cada artículo tiene sus
`ruta_paso` (`insumo`, `ingreso`, `matriz`, `proveedor_servicio`, `tallerista`, `proveedor_at`,
`virgilio`), y de ahí sale a quién se le manda, qué devuelve y quién lo entrega en Virgilio.

## 2 · El motor: una pantalla nunca toca el stock

```mermaid
flowchart LR
  P["Pantalla GP2<br/>(GP2_SB, schema GP2)"] -->|"rpc(...)"| R["RPC SECURITY DEFINER<br/>crear_envio_ps · crear_entrega_tallerista<br/>recepcion_virgilio · cargar_recepcion · registrar_movimientos"]
  R --> M[("GP2.movimiento<br/>el libro")]
  M -->|"trigger fn_movimiento_calc"| M
  M -->|"trigger fn_movimiento_aplicar"| I[("GP2.inventario<br/>cantidad por comp + ubicación")]
  I --> V["Lo que se ve<br/>StockSector · StockGeneral · ControlEnvios"]
```

Regla de la casa: **si un número de stock se calculó en el JS, está mal.** El JS arma el
movimiento; el stock lo decide la base.

## 3 · La cabeza: qué pedir y cuánto vale

```mermaid
flowchart LR
  EM["est_madre<br/>lo que se va a vender"] --> CONS["v_consumo_componente<br/>v_consumo_fleje_kg"]
  CONS --> MAX["inventario.maximo<br/>(o consumo × meses)"]
  MAX --> REP["v_reposicion<br/>sugerido = máximo − stock"]
  REP --> OC2["OC_GP2<br/>+ norma del rubro:<br/>múltiplos de cartón, pliegos de 100,<br/>bolsas, paquetes de Charcas"]
  PRE["precio_proveedor · precio_tallerista<br/>tarifa_servicio · costo_segundo_pesos"] --> COST["v_costo_componente<br/>costea por las ARISTAS DE RUTA"]
  COST --> VAL["Valorización_GP2<br/>Despiece_GP2"]
  I2[("inventario")] --> REP
  I2 --> VAL
```

Dos cosas que ya nos mordieron y conviene tener a mano:
- **La receta (`articulo_componente` / `componente_bom`) no costea; costea la ruta.** La receta
  decide qué se DESCUENTA al entregar; el costo sale de los pasos.
- **El sugerido llena el máximo** (máximo − stock), y recién después se aplica la norma del rubro.
  Primero el lugar, después el envase.

---

## 4 · Dónde entran los 4 que faltan

Son los últimos archivos que miran `public` (ver `MIGRACION_PUBLIC_GP2.md`). Ninguno está en el
menú y ninguno está en uso hoy. Puestos en el croquis, **cada uno tapa un agujero distinto**:

```mermaid
flowchart LR
  PS2["Prov. Servicio<br/>Tallerista"] -.->|"① PREAVISO<br/>lo que PROMETEN traer"| PUERTA["Puerta de Cervantes"]
  PUERTA -->|"③ mostrador único<br/>(ya lo hacen EntregaPS_GP2<br/>+ RecepcionInsumos_GP2)"| MOV[("movimiento<br/>entrega_ps · compra")]
  MOV -->|"② FACTURA<br/>¿lo facturado = lo entregado<br/>al precio pactado?"| PLATA["Control de plata<br/>precio_proveedor · tarifa_servicio"]
  EXT["App externa de remitos<br/>(Control-Carga-Remitos-FC)"] -.->|"④ feed"| TABLERO["Tablero de control<br/>no toca stock"]
```

| # | Módulo viejo | Dónde se engancha | Qué le falta a GP2 | Si no se hace |
|---|---|---|---|---|
| ① | **Preaviso de Entrega** | **antes** de `entrega_ps` / `entrega_tallerista` | **HECHO el 2026-09-13**: `GP2.preaviso` + `v_preaviso_estado` + `Preavisos/Preavisos_GP2.html`. Guarda sólo la promesa (no mueve stock) y cruza contra el libro para mostrar vencidos y lo ya entregado. Qué entrega cada contraparte sale de la ruta, sin tabla nueva | — |
| ② | **Lectura de Facturas** | en la puerta **y** después, del lado de la plata | **La IA lee, GP2 decide** (idea 7338, decidido por el usuario): foto/PDF → API de Claude con JSON Schema → los renglones se atan a componentes por `precio_proveedor.cod_prov` (301 códigos cargados) → **propone** la recepción y la persona confirma. Falta la Edge Function y la pantalla | se sigue tipeando la recepción renglón por renglón, y se paga contra el papel sin cruzar con lo entregado ni con el precio pactado |
| ③ | ~~Entrega Prov. Cervantes~~ | **DESCARTADO el 2026-09-13** | Era un mostrador único que insertaba en `Entregas PS` **y** `Recepcion_Insumos`; GP2 ya hace las dos cosas en dos pantallas. `[usuario: "no sé para qué sirven esos 2"]` → si no se sabe para qué sirve, no sirve. Archivo borrado | — |
| ④ | ~~Control Carga Remitos~~ | **DESCARTADO el 2026-09-13** | No cargaba nada: sólo miraba una tabla que llena una **página externa** (`loekemeyer.github.io/Control-Carga-Remitos-FC`). No tocaba stock ni GP2. Archivo borrado; la página externa sigue existiendo por su cuenta | — |

**Estado al 2026-09-13: no queda ningún hueco.** ② (Lectura de Facturas) y ① (Preaviso) están
hechos; ③ y ④ se descartaron — `[usuario: "no sé para qué sirven esos 2"]`, y al mirarlos no
servían: uno era comodidad ya cubierta y el otro un visor de otra app.

---

*Archivos vivos relacionados: `GP2_MAPA.md` (contratos y nombres reales), `MIGRACION_PUBLIC_GP2.md`
(qué queda mirando `public`), `CONOCIMIENTO_GP2.md` (por qué cada cosa es como es).*
