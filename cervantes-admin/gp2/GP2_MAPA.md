# GP2_MAPA.md — Contratos de los bundles del schema GP2

> **Para que sirve:** antes de escribir o tocar una pantalla que hable con GP2, buscar
> aca el contrato del bundle. Extraido del codigo de los modulos conectados
> (2026-08-28, revisado 2026-09-05 al cierre de la auditoría). Complementa `ANALISIS_GP2_2026-08-28.md` y `REFACTOR_GP2.md`.

## Regla de oro

**NO existe una convencion unica: cada `*_bundle` serializa a su manera.** La misma
entidad cambia de nombre y forma entre bundles (`rp` con `tp/m/pr/ta` en Programa vs
`tipo/mat/prov/tall` en Movimientos; `sect` como `{t}`, `{nom}` o `{nom,tipo}`;
`tall` como string plano o `{nom}`; `mat.r` ≡ `mat.ppk`). **Nunca copiar el shape de
un bundle a otro modulo sin verificar.** Al crear bundles nuevos, converger al
"diccionario canonico" de abajo.

Patron de consumo comun a todos:

```js
var SB = GP2_SB();   // supabase-config.js: schema GP2, sin sesion persistida (desde 2026-09-05; antes cada pantalla hacia su createClient)
var D = {};
function __run(){ /* todo el codigo que usa D */ }
async function __boot(){
  var r = await SB.rpc('<modulo>_bundle');
  if (r.error) throw r.error;
  Object.assign(D, r.data);   // r.data es UN objeto jsonb, no un array
  __run();
}
__boot();
```

---

## programa_bundle() — Programa/Programa.html (solo lectura)

| Clave | Forma |
|---|---|
| `sect` | dict `String(sector_id)` → `{ t }`. `t` = tipo en minusculas: crudo, procesado, transito, afilado, fleje, plástico, bombilla, remache, garage, cartón, caja, terminado |
| `comp` | dict `String(comp_id)` → `{ cod, d, s (sector_id), id }` |
| `rp` | dict `String(ruta_id)` → lista de pasos `{ o, tp, ce, cs, m, pr, ta }`. **Nombres CORTOS**: `tp` = `ruta_paso.tipo_paso` tal cual, y los valores que existen en la base (verificado 2026-09-03) son ingreso\|insumo\|matriz\|proveedor_servicio\|tallerista\|virgilio — **`fleje` y `afilado` NO existen**; `m`→mat, `pr`→prov, `ta`→tall. Se ordena por `o` |
| `art` | LISTA `{ id, cod, fam }` |
| `bom` | LISTA plana `{ a (art_id), c (comp_id), q }` |
| `children` | dict `String(comp_padre)` → lista `{ c, q }` (sub-BOM; su existencia define "convergencia") |
| `mat` | dict `String(matriz_id)` → `{ n, d, r }`. `r` = rendimiento uni/kg (mismo dato que `ppk` en otros bundles) |
| `prov` | dict → `{ n (nombre), p (proceso) }` |
| `tall` | dict → **string plano** con el nombre (puede traer espacios colgantes → `.trim()`) |
| `rutas_by_art` | dict `String(art_id)` → lista `{ id (→rp), f (comp_id del fleje; null = ruta de insumo) }` |
| `tall_art` | dict `String(art_id)` → lista de NOMBRES (strings) de talleristas alternativos |

## faltantes_bundle() — Despiece x Articulo/Despiece_GP2.html (solo lectura; lazy)

**Desde el 2026-09-05 es un envoltorio de `movimientos_bundle()`**: mismo diccionario, con `art`
como LISTA (ordenada por id) y `mat.primera` siempre boolean. Cualquier clave nueva de
`movimientos_bundle` aparece acá sola.

| Clave | Forma |
|---|---|
| `art` | LISTA `{ id, cod, fam, est }`. `est` = demanda mensual (est>0 ⇒ hay demanda) |
| `rp` | dict → lista `{ o, tipo, art, ce, cs, flje, mat, tall, prov }`. **Nombres LARGOS** (distinto de Programa). `tipo` conocidos aca: ingreso, insumo |
| `comp` | dict → `{ cod, d, s, um }`. `um==='kg'` activa logica de fleje (kg via ppk) |
| `bom_art` | dict `String(art_id)` → lista `{ c, q }` |
| `bom_comp` | dict `String(comp_padre)` → lista `{ c, q }` (existencia = es sub-conjunto) |
| `mat` | dict → `{ n, primera, ppk }`. `primera` marca la matriz preferida para conversion; `ppk` piezas/kg (mismo dato que `r` en Programa) |
| `ubic` | dict `String(ubic_id)` → `{ tipo ('sector'\|'tallerista'\|'proveedor_servicio'), ref (id → tall/prov_serv), meses }. meses 0/null excluye` |
| `inv` | dict `'compId:ubicId'` → `{ min, cant }`. min<=0 excluye la fila |
| `tall` | dict → `{ nom }` (**objeto**, no string — distinto de Programa) |
| `prov_serv` | dict → `{ nom }` |
| `sect` | dict → `{ nom }` |

## movimientos_bundle() — Movimientos/Registrar_Movimiento.html (lee bundle, escribe `movimiento`)

Shape tomado del snapshot que estaba congelado en el HTML (fixture completo en el
repo git: linea 114 del archivo antes del commit del 2026-08-28). Claves que el
codigo CONSUME: sect, ubic, comp, prov_serv, tall, mat, bom_art, bom_comp, rp, c2a
(`art` e `inv` vienen en el bundle pero nadie los lee en esta pantalla).

| Clave | Forma |
|---|---|
| `sect` | dict → `{ tipo, nom }` (ej. `{tipo:'crudo', nom:'Sector Crudo'}`) |
| `ubic` | dict → `{ tipo, ref, nom, meses }` |
| `art` | LISTA `{ id, cod, fam, cja, por, est }` |
| `comp` | dict → `{ cod, d, s, um, kg_x_uni }` |
| `prov_serv` / `tall` | dict → `{ nom }` |
| `mat` | dict → `{ n, d, tipo, ppk, primera }` |
| `bom_art` / `bom_comp` | dict → lista `{ c, q }` |
| `rp` | dict → lista `{ o, tipo, flje, mat, prov, tall, ce, cs, art }` (nombres largos + `flje`) |
| `inv` | dict `'compId:ubicId'` → `{ cant, min }` |
| `c2a` | dict `String(comp_id)` → art_id (componente terminado → su articulo) |

**Escritura**: SOLO por RPC. Desde el 2026-08-31 `anon` no tiene INSERT/UPDATE en ninguna
tabla GP2: `gp2-motor.js` manda las filas a `registrar_movimientos(p_rows jsonb)` (que las
inserta tal cual, con el CHECK de vocabulario de `tipo_mov`) y cada flujo tiene su
`crear_*`. Los triggers `fn_movimiento_calc` / `fn_movimiento_aplicar` actualizan `inventario`.
Un `SB.from('movimiento').insert/update` desde una pantalla falla con "permission denied"
(así estaba roto «Desmarcar» en control-cajas/control-remaches hasta el 2026-09-05:
ahora `descontrolar_recepcion`).

## despiece_verif_bundle() — Despiece x Articulo/Despiece_GP2.html (solo lectura)

Reemplazo (2026-08-30) de los viejos `despiece_bundle` y `verificacion_bundle`, que ya no existen.

| Clave | Forma |
|---|---|
| `art` | LISTA `{ id, cod, fam, por, caja, est, comp[] }` (mismo bloque que `abm_articulos_bundle.art`, + `fkg`, `fuxc`) |
| `art[].comp` | lista `{ cod, d, s, q, kg, uxc, um }` |
| `sect` | dict → `{ nom, tipo }` |
| `rutas` | LISTA `{ art, fam, fleje, fleje_desc, nom, ce_sect, cs_sect, pasos[] }`; `pasos[]` ordenados `{ tp, actor, actor_desc, ce, cs, ... }`, `tp` ∈ ingreso\|matriz\|insumo\|proveedor_servicio\|tallerista\|virgilio |
| `confirmadas` / `problemas` | filas de `ruta_revision` (RPCs `ruta_confirmar` / `ruta_reportar` / `ruta_resolver`) |
| `madres` | lo que antes daba VerifMadres (fusionada acá el 2026-08-30) |

La pantalla pide además `faltantes_bundle` (lazy, al abrir un artículo) para la matemática de
faltantes prorrateados: ver más arriba, hoy es un envoltorio de `movimientos_bundle`.

## produccion_bundle(p_matriz, p_anio) — Produccion/rendimiento_GP2.js (solo lectura)

Se llama 2 veces: sin args al init (usa `matrices` + `empleados`) y con
`{p_matriz, p_anio}` (usa `rows`).

| Clave | Forma |
|---|---|
| `matrices` | LISTA `{ N_Matriz, Matriz }` (N_Matriz admite sufijo tipo "101B") |
| `empleados` | dict legajo → nombre (string), derivado de `produccion` (la tabla `empleado` existe y la usan otros bundles; este todavia no la lee) |
| `rows` | LISTA de filas de produccion YA filtradas por el RPC (Eliminar<>'S', Legajo<>1, Uni>0, Tiempo_Toma>0). Campos con nombre LEGACY: `Fecha` ("YYYY-MM-DD..."), `Legajo`, `Uni`, `Segundos_Trabajados`, `Tiempo_Toma`, `Premio`, ... |

---

## Índice de bundles (claves de primer nivel reales, verificado contra la base el 2026-09-05)

Cada `*_bundle` devuelve UN objeto jsonb. Estas son sus claves de primer nivel tal como salen de
la base hoy, y la pantalla que lo pide (grep de `rpc('..._bundle')`). Antes de tocar una pantalla,
confirmar acá que la clave existe; si un bundle cambia, actualizar esta tabla en el mismo commit.

| Bundle | Pantalla que lo pide | Claves de primer nivel |
|---|---|---|
| `abm_articulos_bundle()` | ABM Artículos | `art, partes, sect` |
| `alertas_bundle()` | Alertas | `generado_en, matriz_sin_tiempo, pendientes, pm, recepcion_de_mas, ref_fecha, rm, ventana_dias` (`recepcion_de_mas` = `{total, items}` de `alerta_recepcion` en estado `abierta`, 2026-09-13) |
| `calculadora_cajones_bundle()` | Calcular Cajones | `cajones, sectores, comps` |
| `control_recepcion_bundle(p_sector_id)` | control-cajas.js (11) y control-remaches.js (5, 8, …) | `recepciones, sector, sector_id, uni_x_paq_default` (reemplaza a `control_cajas_bundle` + `control_kg_bundle`, 2026-09-05) |
| `control_envios_bundle(p_desde, p_hasta)` | Control Envíos y Entregas | (por vista/tipo, ver la pantalla) |
| `control_ps_bundle()` | Control PS | `generado_en, proveedores` (cada proveedor trae `nombre_corto`) |
| `despiece_verif_bundle()` | Despiece x Artículo | `art, confirmadas, madres, problemas, rutas, sect` |
| `devoluciones_tallerista_bundle()` | Devolución Cervantes | `analizar, online, talleristas, ultimas` |
| `disruptivas_bundle(...)` | Disruptivas | (filas de producción con premio anómalo) |
| `entregas_prov_at_bundle()` | Entregas AT | `arts, provs, ultimas` |
| `envios_prov_at_bundle()` | Envíos AT | `insumos, online_prov, paq, provs, ultimos` |
| `envios_ps_bundle()` | Envíos PS y Entrega PS | `partes, ps` |
| `faltante_partes_tallerista_bundle()` | Faltante Partes Tallerista | `generado_en, talleristas` |
| `faltantes_bundle()` | Despiece x Artículo (lazy) | `aporte, art, bom_art, bom_comp, c2a, comp, inv, mat, prov_serv, rp, sect, tall, tipos_mov, ubic` (= `movimientos_bundle`, `art` como lista, + `aporte`) |
| `faltantes_estado_bundle()` | Faltantes | `estado, marcas, max_cajones, pendientes_uxc, umbral_cajones` |
| `flejes_bundle()` | Flejes | **LISTA** de 55 flejes: `cod_isis, codigo, comp_id, cons, descripcion, kg_uni_desp, kg_x_cajon, maximo, medida, minimo, n_fleje, parte, proveedor, stock` |
| `informes_bundle(p_desde, p_hasta)` | Informe por persona | `desde, hasta, personas` |
| `informes_matriz_bundle(p_desde, p_hasta, p_incluir_piedra)` | Informe por matriz | `desde, hasta, empleados, hsTotalByEmp, matrices` |
| `inicio_bundle()` | GP2_MODULOS (menú) | `alertas, dia, generado_en, hoy, mes` (`alertas.recepcion_de_mas` = cuántas alertas de recepción siguen abiertas, 2026-09-13) |
| `inyectores_bundle()` | Inyectores | `generado_en, partes, proveedores, sector, sectores` |
| `movimientos_bundle()` | gp2-motor.js (Stocks General, Entregas Talleristas), Registro operarios | `art, bom_art, bom_comp, c2a, comp, inv, mat, prov_serv, rp, sect, tall, tipos_mov, ubic` |
| `oc_bundle()` | OC | `charcas_kg_x_paquete, generado_en, insumos, ocs, paq, pliego_uni_x_paquete, proveedores, tc`. Cada `insumos[]` trae ademas **`proveedores_alt[]`** (los de `componente_proveedor_alt`, que entregan la misma pieza) y **`precios_prov`** = {proveedor: {precio, moneda}} (CTE `pvx`), para que la O.C. salga con el precio del proveedor elegido; `precio` sigue siendo el VIGENTE, el del proveedor asignado. 2026-09-17 |
| `orden_produccion_bundle()` | Orden de Producción | `componentes, destinos, generado_en, matrices, pasos` |
| `pintores_bundle()` | Pintores | `partes, pintores` |
| `problemas_matrices_bundle(p_desde, p_hasta)` | Problemas con Matrices | (eventos RM/PM) |
| `produccion_bundle(p_matriz, p_anio)` | rendimiento_GP2.js | `matrices, empleados, rows` (ver sección propia) |
| `produccion_maestro_bundle(p_desde, p_hasta)` | Maestro de producción | `desde, empleados, hasta, matrices, rows` |
| `programa_bundle()` | Programa | `art, bom, children, comp, fl, mat, prov, rp, rutas, rutas_by_art, sect, tall, tall_art` (nombres CORTOS, ver sección propia; idea 7252) |
| `proporciones_bundle()` | Proporciones (**solo lectura**) | `generado_en, pasos` — reescrita el 2026-09-15. `pasos` = los PASOS (`articulo_id` + `comp_salida_id`) que hacen **2 o más talleristas**, con `art_codigo, familia, paso_cod, paso_desc, n_talleristas, suma_pct`, `talleristas[{tall_id, tallerista, pct, es_supuesto}]` y `partes[{cod, desc, por_tall[{tall_id, maximo, stock, origen}]}]` (el máximo de cada parte en la casa de cada tallerista). Ya no devuelve `articulos_compartidos`: la lógica de "mismo paso" vive en la función, no en el front |
| `reparto_guardar(p_articulo_id, p_comp_salida_id, p_filas)` | **nadie: se corre por SQL** | `p_filas` = `[{tallerista_id, pct}]`; exige que sumen 100 y que cada tallerista haga ESE paso según las rutas. Escribe `GP2.reparto_tallerista` y **recalcula los máximos** (`recalcular_maximos_talleristas(true)`). Desde el 2026-09-15 **no tiene EXECUTE para `anon`**: la pantalla es solo lectura [usuario: "que no se pueda modificar la proporción en el programa"] |
| `recepcion_bundle()` | Recepción Insumos | `insumos, pallets, proveedores, recepciones, rollos, sectores, tara`. Cada `insumos[]` trae `proveedor` (el principal, `componente.proveedor`) y **`proveedores_alt[]`** (los de `componente_proveedor_alt`, que entregan la misma pieza sin duplicar el componente; 2026-09-17, caso Recicor en Cajas) |
| `registro_operarios_bundle()` | App de operarios | `empleados, matrices, matriz_fleje, matriz_fleje_pieza, matriz_salidas, registro_en_golpes, rollos_abiertos, rollos_saldo` |
| `relevamiento_bundle()` | Relevamiento | `cronograma, hoy` |
| `rollos_bundle()` | Flejes (rollos) | `eventos, flejes, saldos, usos` |
| `tablet_bundle()` | Versión Tablet (`Tablet/Tablet_GP2.html`) | `alertas_abiertas, contrapartes, enviar, generado_en, recibir` (ver sección propia, 2026-09-13) |
| `stock_sector_bundle(p_sector_id)` | gp2-stock-sector.js (los 10 sectores) | `filas (+en_virgilio), generado_en, sector, ubicacion_id, ubicacion_virgilio_id` |
| `stock_transito_ps_bundle()` | Stock Tránsito PS | `filas, generado_en` |
| `talleristas_bundle()` | Envíos Talleristas y Control Talleristas | `generado_en, partes, tall` (`partes` = dict por tallerista `{entrada:[...], salida:[...]}`) |
| `validacion_bundle()` | Validación de Stock | `aplicados, hoy, pendientes` |
| `valorizacion_bundle()` | Valorización | `comps, costo_seg, generado_en, tc, tc_info` |

## Lo que cambio el 2026-09-11 (auditoria de rutas completas)

Todo esto salio de recorrer las **861 rutas** de los 189 articulos ejecutando las RPC de verdad
(ver «El arnes de rutas» mas abajo). Al empezar, 142 rutas se cortaban; al cerrar, ninguna.

| Cambio | Que hay que saber al tocar una pantalla |
|---|---|
| **`GP2.tipo_movimiento`** (tabla nueva) | El vocabulario de `movimiento.tipo_mov` dejo de ser un CHECK de literales: ahora es una tabla (`clave, label, lado, clase, orden`) y `movimiento.tipo_mov` tiene **FK** contra ella. `movimientos_bundle` la sirve en **`tipos_mov`** (dict `clave → {lbl, lado, cls, ord}`). Un tipo nuevo se agrega a la tabla y a `db/vocabulario_GP2.sql`; las pantallas lo muestran solas. `tests/ui/test_vocabulario_mov.js` falla si un JS nombra una palabra que no esta en el catalogo (pasaba: `gp2-stock-sector.js` sumaba columnas por `produccion`, `envio_prov`, `envio_tall`, `recepcion_prov` y `recepcion_tall`, cinco palabras que la base nunca escribio). |
| **`faltantes_bundle.aporte`** | dict `'art:comp' → uni_mes` desde `v_consumo_demanda`: lo que ESE articulo consume de ESE componente por mes, ya explotado (receta + sub-BOM + intermedios de la ruta). Despiece lo usa en vez de recalcularlo; antes le ponia cantidad 1 a todo intermedio de ruta y en 59 pares la base decia otra cosa. |
| **`v_reposicion`** (vista nueva) | Donde se repone cada componente (la ubicacion de su sector, o Virgilio para los terminados) con `cantidad, minimo, maximo, maximo_origen, sugerido`. **Unica definicion** de "cuanto falta para llenar el lugar": la leen `oc_bundle` y `valorizacion_bundle`, que antes calculaban cosas distintas (54 de 342 componentes no cerraban entre las dos pantallas). |
| **`crear_entrega_ps` acepta `p_unidad`** (default `'kg'`) | Una pieza que se cuenta y no se pesa (los `Pliego Ad` de AJ Adhesivos -- **10 desde el 2026-09-18**, que el 500 y el 506 pasaron a carton y sus pliegos quedaron discontinuos, ver CONOCIMIENTO 4el --, `C12`, `V18D`: sin `kg_x_uni`) se entrega en unidades. `envios_ps_bundle.partes[]` trae `sp_um` y `sp_kgxuni` para que la pantalla sepa cual pedir. |
| **`crear_entrega_prov_at` mueve stock** | Delega en `recepcion_virgilio(origen_tipo='proveedor_at')`: consume la receta completa del articulo desde la ubicacion del proveedor y deja el terminado en Virgilio. Antes solo escribia en `entrega_prov_at` y el articulo comprado terminado **nunca entraba al inventario** (38 articulos, 75 rutas); el carton y la caja que se le mandaban no se consumian nunca. |
| **`_es_comprable(comp_id)`** | Reemplaza al chequeo por sector de `crear_recepcion_insumo` y al filtro hardcodeado de `recepcion_bundle`: se compra lo que es de un sector de insumo, **o** es `estado_compra='importado'`, **o** lo entrega un PS hibrido. `recepcion_bundle.insumos[]` trae ahora `estado_compra` y la pantalla de Recepcion tiene el rubro **Importados** (C13, D1, Z23A, Z23B, que viven en Sector Procesado y no se podian recepcionar por ningun lado). |
| **`fn_ubicacion_de_contraparte`** (trigger) | Un tallerista / Prov AT / PS / sector de insumo nuevo **se crea con su ubicacion de stock**. Antes solo `alta_proveedor_servicio` la creaba y un alta por migracion la salteaba: Blist-Pack SA quedo sin ubicacion y no se le podia enviar nada. |
| **`registrar_movimientos` valida** | cantidad > 0 (salvo `ajuste`, que puede ser negativo), al menos una ubicacion, el mismo componente no entra y sale del mismo lugar (si hay transformacion si: una matriz convierte I4 en I6 sin sacar la pieza del Sector Crudo), `comp_transformado_id` y `cantidad_transformada` van juntos. El JS puede seguir validando para dar un mensaje lindo; **el que manda es el backend**. |
| **`reprocesar_espejo_virgilio(p_ids, p_dry_run)`** | `virgilio_espejo_pend` era un cementerio: la entrega que no cruzaba quedaba anotada y nadie la miraba mas, aunque despues se diera de alta el articulo. Ahora es una cola (`resuelto_en`, `resultado`) y esta RPC la reintenta. **Corre en seco por defecto.** |
| **UNIQUE / NOT NULL / FK nuevos** | `articulo.codigo`, `matriz.n_matriz`, `sector.nombre`, `tallerista.nombre`, `lower(btrim(proveedor_servicio.nombre))`, `proveedor_insumo.cod_prov`, `articulo_componente(art,comp)`, `componente_bom(padre,hijo)`, `ruta_paso(ruta,orden)` *deferrable*, `planilla_snapshot(vigente)`. NOT NULL en las columnas del ledger y de las recetas. FK por nombre con `on update cascade` en `orden_compra.proveedor`, `recepcion_insumo.proveedor`, `produccion.legajo`, `rollo_evento/rollo_uso.legajo` y `entrega_prov_at(prov, cod_art)`. |

### El arnes de rutas: `"GP2".__sim_ruta(ruta_id, n)`

Funcion **interna** (sin EXECUTE para anon) que recorre una ruta llamando a las RPC de produccion
de verdad — `crear_recepcion_insumo`, `registrar_produccion`, `crear_envio_ps` + `crear_entrega_ps`,
`crear_envio_tallerista` + `crear_entrega_tallerista`, `crear_envio_prov_at` +
`crear_entrega_prov_at` — y termina con una excepcion centinela que **revierte todo**: no queda
nada escrito. Si un paso `insumo` pide un componente que no se compra, simula primero la ruta que
lo produce (los intermedios: `D1`, `A10`, los `Pliego Ad`), hasta 3 niveles.

Devuelve `{ruta, ok, pasos[], deltas[], colgado[]}`. Correrla sobre todas antes de cerrar una
sesion que toco el motor de stock o alguna `crear_*`:

```sql
with s as (select r.id, "GP2".__sim_ruta(r.id, 120) res from "GP2".ruta r)
select count(*) rutas, count(*) filter (where (res->>'ok')::boolean) ok from s;   -- 861 / 861
```

`__sim_base` es su tabla de apoyo (la foto del inventario al empezar cada corrida); fuera de una
corrida esta vacia.

### La prueba de conservacion: `"GP2".__sim_articulo(articulo_id, n)`

Una rama sola no puede probar que las cantidades cierren. `__sim_articulo` corre **todas** las
ramas del articulo hasta dejarle las partes a quien lo arma (tallerista) o lo entrega (Prov AT), y
recien ahi hace **UNA** entrega de `n` unidades por `recepcion_virgilio`. Si el modelo cierra,
despues de la corrida **cada contraparte queda en cero** (lo que entro se consumio) y Virgilio
tiene exactamente `n` articulos. Lo que quede en `colgado[]` es una cantidad que no cuadra entre
la ruta y la receta.

```sql
with s as (select a.id, "GP2".__sim_articulo(a.id, 120) r from "GP2".articulo a)
select count(*) filter (where (r->>'ok')::boolean) cierran_perfecto,
       count(*) filter (where jsonb_array_length(r->'colgado') > 0) con_colgado from s;
```

Al 2026-09-11: **189 de 189 dejan las 120 unidades en Virgilio**; 122 cierran perfecto y el resto
tiene colgado, casi todo por intermedios (GRJ, sub-conjuntos) que el arnes simula rama por rama.
Los descuadres REALES de receta contra ruta son 7 articulos y estan en la idea **7324**.

## Reparto entre talleristas y el maximo de cada uno (2026-09-15)

Cuando **dos talleristas hacen EL MISMO paso** (mismo `articulo` + mismo `comp_salida`, o sea la
ruta duplicada por tallerista), el volumen se reparte. Cuando hacen pasos DISTINTOS del mismo
articulo van en cadena y cada uno hace el 100 % de lo suyo: eso NO es un reparto.

| Objeto | Que es |
|---|---|
| `GP2.reparto_tallerista` | La tabla: `(articulo_id, comp_salida_id, tallerista_id, pct)`, unica por esa terna. Sin fila = 100 % |
| `GP2.v_reparto_efectivo` | El % efectivo de cada paso, **normalizado sobre los talleristas que siguen haciendo el paso** (si se borra la ruta de uno, el otro pasa a 100, no se queda con su mitad). `es_supuesto` = ninguno o solo algunos tienen % dictado -> parte en partes iguales (default, no dato) |
| `GP2.v_consumo_tallerista` | uni/mes por `(tallerista, componente que recibe)` = demanda del articulo (`v_consumo_demanda`) x su % |
| `GP2.v_nivel_stock_tallerista` | `max_calc = consumo repartido x ubicacion.meses_stock` (los 12 talleristas tienen `meses_stock = 1`) |
| `GP2.recalcular_maximos_talleristas(p_solo_repartidos, p_componentes, p_limpiar_sin_ruta)` | Escribe `inventario.maximo` con `maximo_origen = 'est_madre_x_reparto'`. Los dos primeros filtros se combinan con Y (null/false = sin filtro) y nunca pisa un `fisico`. `p_limpiar_sin_ruta` borra el maximo de la fila **sin consumo Y sin ruta** (el tallerista ya no recibe esa parte); la que tiene ruta pero no demanda NO se toca y vuelve en `sin_consumo_con_ruta` |
| `GP2.reparto_guardar(...)` | La puerta de la pantalla: valida, guarda y recalcula en una sola llamada |

**El maximo de un tallerista NO sale de `v_nivel_stock`**: esa vista cubre solo ubicaciones de
tipo `sector` (`u.tipo = 'sector'`), y por eso `recalcular_maximos_insumos` nunca toco una fila
de tallerista. De ahi que los 288 maximos de talleristas fueran todos `migrado_de_minimo` o nulos
hasta el 2026-09-15.

## Convenciones implicitas (fragiles — hoy viven hardcodeadas en el JS)

- ~~Ids de ubicacion por offset~~ (resuelto 2026-09-04/05): la pantalla vieja que sumaba
  `20 + tall_id` ya no existe; `gp2-motor.js` arma `UB["tipo:ref"]` desde `ubic.tipo + ubic.ref`
  y la base resuelve todo con `ubic_de(tipo, ref_id)`. Queda un solo literal:
  `TALL_FABRICA = 3` en `ControlTalleristas_GP2.html` (Fábrica no es un tallerista externo).
- **Sectores con semantica fija**: `comp.s === 12` = articulo terminado, `s === 9` =
  garage (Faltantes y Movimientos dependen de esos ids literales).
- `mat.r` (Programa) y `mat.ppk` (Faltantes/Movimientos) son el mismo dato con dos nombres.
- Ids siempre se indexan como `String(id)`; no esta confirmado si el jsonb los
  serializa como number o string en todos los bundles.

## Diccionario canonico sugerido (para bundles NUEVOS)

`sect {nom,tipo}` · `ubic {tipo,ref,nom,meses}` · `comp {cod,d,s,um,kg_x_uni}` ·
`art {id,cod,fam,cja,por,est}` · `mat {n,d,tipo,ppk,primera}` · `tall {nom}` ·
`prov_serv {nom}` · `rp {o,tipo,flje,mat,prov,tall,ce,cs,art}` · `inv 'c:u' {cant,min}`
— es el shape de `movimientos_bundle`, el mas completo. Los tres bundles viejos que
difieren (programa, faltantes, despiece) quedan como estan hasta que se los toque.

## El mismo concepto con dos nombres (verificado 2026-09-11) — MIRAR ANTES DE ESCRIBIR SQL

No se renombro nada: `movimiento.comp_id` toca el ledger, 30+ funciones y `gp2-motor.js`, y el
costo supera al beneficio (la auditoria del 2026-09-04 decidio igual con `produccion.dia/mes`).
Lo que sirve es tener la tabla a mano y no perder media hora escribiendo
`movimiento.componente_id`, que no existe:

| Concepto | Como se llama en cada lado |
|---|---|
| id de componente | `componente_id` (12 tablas) · **`comp_id`** (`movimiento`) · **`comp_entrada_id` / `comp_salida_id`** (`ruta_paso`) · `comp_transformado_id` |
| id de ubicacion | `ubicacion_id` (`inventario`) · **`ubic_origen_id` / `ubic_destino_id`** (`movimiento`) · `ubicacion_stock_id` (`tallerista`) |
| id de proveedor de servicio | `proveedor_servicio_id` (3 tablas) · **`proveedor_id`** (`ruta_paso`) |
| numero de caja | `n_caja` **integer** (`articulo_prov_at`) · `n_caja` **text** (`uni_x_articulo_x_caja`, con 4 filas en `'P'`) |
| unidades por caja | `articulo.articulos_por_caja` · `uni_x_articulo_x_caja.uni_x_caja` · `componente.uni_x_cajon` |
| marca de tiempo | **16 nombres**: `actualizado, actualizado_en, aplicado_en, cerrado_en, controlado_en, copiado_en, creado_en, created_at, en, fecha, obtenido_en, origen_created_at, resuelto_en, subido_en, ts_fin, ts_inicio` |

**El unico con riesgo de CALCULO, no de prolijidad**: la unidad se escribe de DOS formas.
`componente.unidad_medida` usa `kg` / **`unidad`**, mientras `movimiento.unidad_origen` y
`.unidad_destino`, `orden_compra_item.unidad` y `recepcion_insumo.unidad` usan `kg` / **`uni`**
(4 CHECK identicos). `fn_movimiento_calc` traduce en runtime. **El que compare
`unidad_medida` contra `'uni'` no matchea nunca y cae al camino de kg.** Unificar toca 733 de
800 filas, el CHECK, `fn_movimiento_calc`, `to_canonical` y los bundles que exportan
`comp[].um`: no es un commit suelto. Las columnas ya lo dicen en su `comment`.

Y los dos enum polimorficos que se solapan: `ubicacion.tipo` tiene 8 valores
(`sector, tallerista, proveedor_servicio, proveedor_at, virgilio, analisis, inyector,
virgilio_sector`) y `contraparte_alias.tipo` tiene 4 (`tallerista, proveedor_at,
proveedor_servicio, interno`). Coinciden en 3 de 4 y **no hay una fuente comun**: son dos CHECK
escritos a mano.

## Nombres REALES de las tablas (verificado 2026-08-28)

Los bundles serializan con nombres cortos; **las tablas usan otros**. Al escribir
SQL o RPCs nuevas, estos son los buenos:

| Bundle | Tabla / columna real |
|---|---|
| `comp[].cod` / `.d` / `.s` / `.um` / `.kg_x_uni` | `componente.codigo` / `.descripcion` / `.sector_id` / `.unidad_medida` / `.kg_x_uni` — **y ademas `uni_x_cajon`**, que ningun bundle expone todavia (228 componentes lo tienen cargado) |
| `ubic[].tipo` / `.ref` / `.nom` / `.meses` | `ubicacion.tipo` / **`.ref_id`** / `.nombre` / **`.meses_minimo`** |
| `inv['c:u'].cant` / `.min` | `inventario.cantidad` / **`.minimo`** (+ `componente_id`, `ubicacion_id`, `actualizado_en`) |
| `tall[].nom` | `tallerista.nombre` (+ `cod_prov`; la columna `clase` se borró el 2026-09-05: era `'tallerista'` en las 13 filas) |
| `bom_comp` | `componente_bom.componente_padre_id` / `.componente_hijo_id` / `.cantidad` |

`movimiento`: `id, fecha, tipo_mov, comp_id, ubic_origen_id, ubic_destino_id,
cantidad, comp_transformado_id, cantidad_transformada, unidad_origen,
unidad_destino, _delta_orig, _delta_dest, cajones, faltante, nota` (`_delta_*` los calcula el
trigger `fn_movimiento_calc`, no escribirlos a mano; `nota` es el texto libre del operario —
el motivo de una devolucion, desde el 2026-09-05 — y reemplaza a la tabla cabecera
`devolucion_tallerista`, borrada). `unidad_origen` / `unidad_destino` son **`kg` o `uni`**
(CHECK desde el 2026-09-05; el trigger traduce `unidad`, `pliego`, `KG`… antes de calcular, asi
que una pantalla puede mandar `componente.unidad_medida` tal cual; null = la del otro lado).

**`ubicacion.tipo` tiene OCHO valores**: `sector`, `tallerista`, `proveedor_servicio`,
`proveedor_at` (los 12 proveedores de articulos terminados), **`virgilio`** (id 33, la
distribucion), `analisis` (id 46 «Para Analizar», adonde va una devolucion que hay que mirar),
**`inyector`** (desde el 2026-09-10: `ref_id = proveedor_insumo.id`, una por inyector — Pat Bet
Plast, Pettofrezza Rafael, Kollplast, JL Matriceria — con la MATERIA PRIMA plastica en su poder) y
**`virgilio_sector`** (desde el 2026-09-11: `ref_id = sector.id`, solo 1 Crudo y 2 Procesado — las
cajas/cajones de piezas que se guardan en el deposito de Virgilio; se mueven con `traslado_virgilio(
p_comp_id, p_cantidad, p_sentido 'ida'|'vuelta')` = tipo_mov `traslado`, y `stock_sector_bundle`
las muestra en `filas[].en_virgilio` / `ubicacion_virgilio_id`).
Los 84 articulos terminados (sector 12) no tienen ubicacion de sector: viven en Virgilio.

**Gestion Virgilio (otro repo, mismo proyecto Supabase) habla con GP2 por `schema("GP2").rpc`**
(2026-09-11): `oc_pendientes_virgilio()` = las OC abiertas de material plastico que le van a llegar
(items con `comp_id`, `codigo`, `pendiente` en kg) y `recibir_oc_virgilio(p_oc_id, p_items
[{comp_id, cantidad}], p_remito, p_legajo)` = cada item pasa por `crear_recepcion_insumo` (compra
al sector 14, cruce FIFO contra la OC, la marca recibida sola; `recepcion_insumo.rollos_json`
guarda `recibido_en: virgilio` y el legajo; los items aceptan tambien `{cod_virgilio, bolsas}`).
Para el modulo INS de Virgilio («Entregar insumos»): `componente.codigo_virgilio` (PP, ABS, AI, NV,
NR, N25, PE, PS en las bolsas del sector 14), `material_virgilio_bundle()` (bolsas en Virgilio,
inyectores, bolsas que le faltan a cada uno) y `enviar_material_virgilio(p_cod_virgilio, p_bolsas,
p_inyector, p_legajo, p_nota)` = `enviar_material_inyector` en bolsas. `oc_bundle.ocs[].entrega_en` /
`proveedores[].entrega_en` = `proveedor_insumo.entrega_en` (null = Virgilio 2788; Arcolor y Julio
Garcia = Cervantes 2868 porque el Master Bach se stockea en Cervantes por ahora). Ver
`INTEGRACION_GESTION_VIRGILIO.md`.

**Materia prima plastica (2026-09-10)**: sector **14** «Sector Materia Prima Plástica» (`es_insumo`,
ubicacion tipo `sector` ref 14, fisicamente en Virgilio, `meses_stock 2.5`). 12 componentes en **kg**
con codigo = Cod ISIS (`2405` PP 2630, `2455` ABS, `2465` Alto Impacto, `2475`/`2505`/`2485` Nylon
Virgen/Recuperado/c-Carga, `2435` PE, `2425` PS HF555, `0235`/`0255`/`0265`/`2595` Master Bach).
`componente.material_id` en la pieza inyectada dice de que bolsa esta hecha; `crear_recepcion_insumo`
descuenta `uni x kg_x_uni x (1 + parametro inyeccion_desperdicio_pct/100)` de la ubicacion del inyector
al recepcionar la pieza (movimiento `consumo_inyector`, anotado en `recepcion_insumo.rollos_json` para
que `anular_recepcion` lo revierta). `enviar_material_inyector(p_proveedor, p_comp_id, p_kg)` manda
bolsas de Virgilio al inyector (`envio_inyector`). `v_material_inyector` / `inyectores_bundle.material`
= lo que cada inyector necesita para sus OC abiertas menos lo que tiene, en kg y en bolsas
(`parametro material_plastico_kg_x_bolsa` = 25). **Proveedor de cada material = el más barato**:
`v_material_precio_proveedor` (precio de cada proveedor en pesos al dólar del día, rankeado) y
`recalcular_proveedor_material()` (asigna `componente.proveedor`; corre por trigger en
`precio_proveedor` y desde `actualizar_dolar_oficial`). `oc_bundle` / `crear_oc` cotizan con el
precio del proveedor asignado (join `precio_proveedor.cod_prov = proveedor_insumo.cod_prov`).

`tipo_mov` (vocabulario del ledger, verificado 2026-09-04): `compra` (recepciones de insumo y
compras de MP), `consumo` (MP consumida por un PS híbrido: Charcas/Eclipse), `envio_ps` /
`entrega_ps`, `envio_tallerista` / `entrega_tallerista` / `consumo_tall` (partes consumidas al
entregar un armado) / `devolucion_tallerista`, `envio_prov_at`, `fabricacion` (producción con
matriz), `armado_fabrica` / `consumo_prod` (armado en fábrica desde Stocks General),
`recepcion_virgilio` / `consumo_virgilio` (espejo de las entregas en Virgilio), `envio_inyector` /
`consumo_inyector` (materia prima plastica que va al inyector y la que consume al entregar la pieza,
2026-09-10), `traslado` (cajas/cajones de Crudo/Procesado entre Cervantes y su deposito en
Virgilio, 2026-09-11), `stock_inicial`, `ajuste`. Antes convivían `recepcion_tall` (JS) y `consumo_armado` / `consumo_transformacion`
(SQL) para lo mismo: se unificaron en la auditoría del 2026-09-04. **Desde el 2026-09-11 el
vocabulario es una TABLA**, `GP2.tipo_movimiento`, y `movimiento.tipo_mov` es FK contra ella (antes
era el CHECK `movimiento_tipo_mov_chk`, una lista de literales copiada además en tres mapas de JS,
los tres desfasados). Un tipo nuevo se agrega **en la tabla y en `db/vocabulario_GP2.sql`**; los
mapas `TIPOS` de Stocks General y `gp2-composicion.js` quedan como respaldo y se pisan con el
`tipos_mov` del bundle. `tests/ui/test_vocabulario_mov.js` rechaza cualquier palabra inventada en
el JS. **La entrega del Prov AT no tiene tipo propio**: usa `recepcion_virgilio` / `consumo_virgilio`,
igual que la del tallerista, porque desde el 2026-09-11 el motor es el mismo (`recepcion_virgilio`).

**Como funciona el motor de stock**: al insertar en `movimiento`,
`fn_movimiento_calc` convierte cantidades a la unidad canonica del componente con
`to_canonical` y guarda `_delta_orig`/`_delta_dest`; despues
`fn_movimiento_aplicar` llama a `inv_delta` restando en el origen y sumando en el
destino (`coalesce(comp_transformado_id, comp_id)`). Una ubicacion en `null` se
ignora, asi que una compra (sin origen) solo suma y un consumo (sin destino) solo
resta. **En DELETE el trigger revierte exactamente** — verificado.

**Resolucion de ubicaciones (desde el 2026-09-04): una sola puerta, `ubic_de(tipo, ref_id)`.**
Antes `crear_envio_ps`, `crear_entrega_ps` y `crear_envio_tallerista` buscaban la ubicacion
**por nombre** y el resto por `ref_id` (renombrar un sector rompia tres funciones). Ahora las
~25 busquedas de 32 funciones/vistas pasan por `"GP2".ubic_de(p_tipo, p_ref_id)`: devuelve el
`ubicacion.id` de `(tipo, ref_id)`, y para `tallerista` respeta primero
`tallerista.ubicacion_stock_id` (deposito compartido: Carlos Aguirre guarda en la ubicacion 18
«Pedernera / Carlos Aguirre», que es de tipo `proveedor_servicio`). Indices unicos sobre
`ubicacion(tipo, ref_id)` y sobre los singletons (`virgilio`, `analisis`) garantizan que la
respuesta sea una sola. Ninguna funcion busca mas una ubicacion por nombre
(`tests`: consulta `prosrc ~ 'from ubicacion .* where nombre'` da vacio).

## Triggers (9 propios + 2 sobre `public`) y el cron

| Tabla | Trigger | Funcion | Que hace |
|---|---|---|---|
| `movimiento` | `trg_movimiento_calc` / `trg_movimiento_aplicar` | `fn_movimiento_calc`, `fn_movimiento_aplicar` | El motor de inventario: convierte kg/uni a `_delta_*` y aplica el delta en `inventario` |
| `componente`, `parametro` | `trg_maximos_cajones_*` | `fn_recalc_maximos_cajones` | Maximo "5 cajones" de Crudo/Procesado al cambiar `uni_x_cajon` o el parametro |
| `articulo_componente`, `est_madre`, `ruta_paso`, `articulo_familia` | `trg_maximos_receta` / `_est_madre` / `_rutas` / `_familia` (constraint triggers DEFERRABLE INITIALLY DEFERRED, por fila) | `fn_recalc_maximos_diferido` | Al COMMIT, UNA vez por transaccion: maximo de insumos por Est Madre explotada + maximos de tallerista (2026-09-26; antes era statement-level y corria 658 veces por sync de LK) |
| `public."Ordenes_Compra"` | `trg_oc_virgilio_espejo_gp2` (vive en `public`, como `trg_est_madre_sync_gp2`) | `fn_oc_virgilio_espejo` | Espejo fila a fila en `GP2.oc_virgilio`; `v_oc_virgilio_pendiente` (O.C. vigente por contraparte, "la nueva pisa la vieja"), `v_oc_virgilio_demanda` (explotada por receta/ruta), `v_oc_virgilio_partes` (prov AT: cartón y caja) y `v_oc_virgilio_partes_tallerista` (sólo talleristas O.C.; el Garage NO: va por O.C. de insumos, corrección del dueño) son el techo del Enviar de la Tablet (2026-09-26) |
| `precio_tallerista` | `trg_precio_tallerista_kg` | `fn_precio_tallerista_kg` | Precio por kg derivado |
| `recepcion_control_rollo` | `trg_rollo_desde_control` | `fn_rollo_desde_control` | Da de alta el rollo al pesar el pallet |
| `public."Entregas Tallerista Virgilio"` | `trg_virgilio_espejo_gp2` | `fn_entregas_virgilio_espejo` | **Espejo public → GP2**: cada entrega en Virgilio se registra en `movimiento` (o queda en `virgilio_espejo_pend` si no cruza) |
| `public.proyeccion_madre` | `trg_est_madre_sync_gp2` | `fn_est_madre_sync` | **Espejo public → GP2**: `est_madre` (uni = cajas × articulos_por_caja cuando el origen no trae uxb) |
| `tallerista`, `proveedor_at`, `proveedor_servicio`, `sector` | `trg_ubicacion_*` | `fn_ubicacion_de_contraparte` | Crea la ubicacion de stock de la contraparte nueva si `ubic_de` no la resuelve (2026-09-11; sin esto, Blist-Pack SA quedo sin ubicacion y no se le podia enviar nada) |

Cron: un solo job de GP2 entre los 49 del proyecto, `gp2-dolar-oficial` (`10 9 * * *` UTC →
`"GP2".actualizar_dolar_oficial()`). Los otros 48 son de `public`/`planify` (la casa del vecino).

## Versión Tablet (2026-09-13) — `tablet_bundle()` / `tablet_registrar(p)` — Tablet/Tablet_GP2.html

Una pantalla, tres modos (Enviar / Recibir / Conteo). **El contrato lo manda la base**: la pantalla se
rehízo el 13-09 leyendo `pg_get_functiondef` de las dos funciones, porque la sesión que las creó perdió
el frente. `tablet_registrar` **no inventa movimientos**: despacha a las RPC de siempre por tipo de
contraparte (`crear_envio_tallerista` / `crear_envio_ps` / `crear_envio_prov_at`;
`crear_entrega_tallerista` / `crear_entrega_ps` / `crear_entrega_prov_at` / `crear_recepcion_insumo`;
para Virgilio inserta un `traslado` Virgilio → sector). El Conteo **no llama a nada que escriba**.

⚠ **La pantalla usa MENOS de lo que el bundle trae (2026-09-14, pedido del dueño).** La base no
cambió; lo que cambió es qué agarra la tablet, que está en **Cervantes**:
- **Recibir ya no ofrece el prov. de art. terminado** (entrega en Virgilio): las filas
  `recibir[tipo='proveedor_at']` que el bundle sigue devolviendo **no se dibujan**, y con ellas se
  fue la única carga en CAJAS — la pantalla **ya no manda `por_caja`** (el backend lo sigue
  aceptando; lo usa la pantalla de Prov Art Terminado → Entregas).
- **Recibir → Prov. de insumos NO carga acá**: abre `StockFlejes/RecepcionInsumos_GP2.html?volver=tablet`
  (rubros, pesaje de pallets, cruce contra OC). Las filas `recibir[tipo='proveedor_insumo']` del
  bundle tampoco se dibujan.
- **El Conteo dejó de ser un modo**: es un link a `Relevamiento/Relevamiento_GP2.html?volver=tablet`.
  `tablet_registrar` nunca aceptó `modo='conteo'`, así que no hay contrato que romper.
- Enviar y Recibir preguntan primero el **tipo** de contraparte y recién después cuál.

### `tablet_bundle()` → jsonb

| Clave | Forma |
|---|---|
| `contrapartes` | LISTA `{ tipo, ref, nombre, oc, n_env, n_rec }`. **`oc`** (2026-09-23) = `tallerista.pedido_por_oc_virgilio`: a ese tallerista el trabajo se lo pide una O.C. de **Gestión Virgilio** que GP2 no lee, así que sus filas de `enviar` vienen con **máximo y sugerido 0** y la Tablet los muestra en la baldosa aparte "Talleristas O.C." (**solo en Enviar**). Hoy: Carlos Aguirre (9) y Blist-Pack SA (14). `tipo` ∈ tallerista \| proveedor_servicio \| proveedor_at \| proveedor_insumo \| virgilio; `ref` es **texto** (el id, o el nombre del proveedor de insumo, o `'virgilio'`). `n_env`/`n_rec` = cuántas piezas puede enviar / recibir. Talleristas activos menos Fábrica (id 3). |
| `enviar` | LISTA `{ tipo, ref, comp_id, cod, desc, sector, um, uxc, kg_x_uni, online_sector }`. `um` es `componente.unidad_medida`: **`'kg'` o `'unidad'`** (no `'uni'`). `online_sector` = stock en la ubicación del sector de la pieza (Cervantes). **El prov. AT viene con `ref = '*'`**: cualquier cartón/caja (sectores 10 y 11) se le puede enviar a cualquiera. |
| `recibir` | LISTA `{ tipo, ref, comp_id, comp_entrada_id, n_entradas, tiene_bom, cod_art, cod, desc, sector, um, uxc, kg_x_uni, por_caja, ent_cod, ent_desc, esperado, esperado_origen }`. `esperado` = lo que se espera recibir: OC abierta (`esperado_origen = 'oc'`, prov. AT e insumo; **null si no hay OC**), stock en poder del tallerista / PS (`online_tall` / `online_ps`) u online de Virgilio (`online_virgilio`). Prov. AT: `comp_id` **null**, la pieza es `cod_art` y `por_caja` = `articulo.articulos_por_caja`. PS: `comp_entrada_id` = el SC que consume (obligatorio para `crear_entrega_ps`). |
| `alertas_abiertas` | cuántas `alerta_recepcion` siguen `abierta` |

### `tablet_registrar(p jsonb)` → `{ ok, n, contraparte, modo, items:[{cod, cantidad, unidad, res}], alertas:[{id, cod, esperado, recibido, exceso}] }`

`p = { modo: 'enviar'|'recibir', tipo, ref (texto), fecha (timestamptz; la pantalla manda 'YYYY-MM-DDT12:00:00'),
remito (sólo recibir, opcional), items: [ { comp_id, comp_entrada_id, cod_art, cantidad, unidad: 'uni'|'kg',
esperado, esperado_origen, por_caja } ] }`. Reglas que fija la base: `unidad` sólo `uni` o `kg`;
cantidad > 0; a Virgilio y al prov. de insumo **no se les envía** desde la tablet; el PS exige
`comp_entrada_id`; el prov. AT exige `cod_art` y su cantidad son **CAJAS** (`crear_entrega_prov_at`
pide cajas) — para la alerta la base compara `cantidad × por_caja` contra el `esperado` en unidades.

**La alerta de "recibí de más" avisa y no frena**: si `modo = 'recibir'`, viene `esperado` y lo
comparable supera al esperado, la base inserta en `GP2.alerta_recepcion` **después** de haber
registrado el movimiento, y lo devuelve en `alertas`. La revisan en Alertas (bloque "Se recibió de
más", `alerta_recepcion_marcar(p_id, p_estado 'vista'|'resuelta'|'abierta', p_nota, p_usuario)`).

⚠ **Deuda que dejó el backend, no la pantalla** (idea 7345): para `recibir` de un **tallerista**,
`tablet_registrar` llama a `crear_entrega_tallerista`, y el `comment` de esa función dice que **NO es el
motor** de la entrega de tallerista (el motor vivo es `gp2-motor.js` + `registrar_movimientos`, idea 7316;
difiere en el origen de los armados, en `comp_transformado_id` y en el descuento por BOM). Hasta que se
unifique, una recepción de tallerista por la tablet queda registrada con el modelo viejo.

## Lectura de facturas (2026-09-13) — la IA lee, GP2 decide, la persona confirma

No es un bundle: son tres piezas encadenadas, y **ninguna escribe stock sola**.

| Pieza | Qué es | Contrato |
|---|---|---|
| `gp2_leer_factura` | **Edge Function**, no RPC. `POST {archivo_b64, mime}` con la clave publicable en `apikey`. Llama a la API de Claude con el PDF como bloque `document` o la foto como `image`, y `output_config.format` con JSON Schema. | Devuelve `{ok, factura:{razon_social_emisor, cuit_emisor, fecha_emision, tipo_comprobante, punto_venta, numero_comprobante, remito, items:[{codigo, descripcion, cantidad, unidad_medida, precio_unitario, subtotal}], importe_total}, uso}` |
| `factura_match(p jsonb)` | RPC **solo lectura**: ata cada renglón a un componente. Orden de confianza: `factura_alias` (aprendido) → `fleje_detalle.cod_isis` → `componente.codigo` → parecido de descripción dentro de la lista de productos de ese proveedor. | `p = {proveedor, items:[{codigo, descripcion, cantidad, unidad, precio_unitario}]}` → `{ok, proveedor_texto, proveedor:{id,nombre,cod_prov,sim}, items:[{…, comp_id, comp_cod, via, confianza, sim, candidatos}], resueltos, sugeridos, sin_match, total}` |
| `factura_alias_guardar(p_proveedor, p_cod_prov, p_comp_id, p_descripcion, p_usuario)` | Ata a mano el código de un proveedor a una pieza. **Es el único "entrenamiento" que hace falta.** | Devuelve el `id` de `GP2.factura_alias` |

**Ojo con `precio_proveedor.cod_prov`: es el código DEL PROVEEDOR, no del artículo** (2147 =
Talleres Gráficos Pol). GP2 no tiene los códigos de artículo de sus proveedores; los únicos códigos
de tercero cargados son los 51 `fleje_detalle.cod_isis`. Por eso `factura_alias` arranca vacía y es
la tabla que hay que llenar con el uso.

## Puntos de contacto con `public` (la casa del vecino) — son estos y nada mas

GP2 no lee tablas de `public` desde ninguna funcion, vista ni pantalla. Las excepciones, todas
deliberadas y en una sola direccion (`public` → GP2):

1. Los dos triggers espejo de arriba (`fn_entregas_virgilio_espejo`, `fn_est_madre_sync`).
2. `virgilio_espejo_pend.entrega_id` apunta a la entrega de `public` que no pudo cruzar (sin FK,
   es otro schema).
3. `get_role_for_email(p_email)` delega en `public.get_role_for_email` (el rol del login es del
   programa viejo, pregunta 1 de `PREGUNTAS_ARQUITECTURA_GP2.md`).
4. `actualizar_dolar_oficial()` usa `public.http_get` (la extension `http`, no una tabla).

Verificado el 2026-09-05: `grep 'public\.'` sobre `db/funciones_GP2.sql` y `db/vistas_GP2.sql`
da solo los puntos 3 y 4; las pantallas GP2 hacen `from()` solo sobre 11 tablas/vistas GP2
(`produccion`, `empleado`, `componente`, `sector`, `inventario`, `v_recepcion_unificada`,
`proveedor_servicio`, `movimiento`, `familia`) y todo lo demas por RPC.

**El contrato de este mapa tiene guardia automática**: `tests/ui/test_contratos_db.js` lee `db/` y
falla si una pantalla nombra una RPC, tabla o vista que no existe, o manda una clave `p_*` que
la función no tiene. Si el test falla porque `db/` está viejo, se regenera `db/` (no el test).

## Verificaciones ya hechas (eran "pendientes" de este mapa)

1. Que puede tocar la anon key: **nada directo** — 0 policies de escritura, 0 grants
   INSERT/UPDATE/DELETE, 0 secuencias con USAGE; 97 RPC con EXECUTE y 23 funciones internas sin
   EXECUTE. `db/verificar.sql` lo chequea (reglas C, D, D2, E, F, M).
2. Los shapes de los bundles del indice de arriba estan verificados contra la base (claves
   reales de `jsonb_object_keys`, 2026-09-05).
3. Los espejos: son los dos triggers de la tabla de arriba (los nombres viejos
   `fn_espejo_produccion` / `fn_espejo_entrega_tallerista` no existen).

Las consultas de verificacion estan en `REFACTOR_GP2.md` (auditoria 2026-09-04/05) y en `db/verificar.sql`.
