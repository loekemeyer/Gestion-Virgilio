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
| `alertas_bundle()` | Alertas | `generado_en, matriz_sin_tiempo, pendientes, pm, ref_fecha, rm, ventana_dias` |
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
| `faltantes_bundle()` | Despiece x Artículo (lazy) | `art, bom_art, bom_comp, c2a, comp, inv, mat, prov_serv, rp, sect, tall, ubic` (= `movimientos_bundle`, `art` como lista) |
| `faltantes_estado_bundle()` | Faltantes | `estado, marcas, max_cajones, pendientes_uxc, umbral_cajones` |
| `flejes_bundle()` | Flejes | **LISTA** de 55 flejes: `cod_isis, codigo, comp_id, cons, descripcion, kg_uni_desp, kg_x_cajon, maximo, medida, minimo, n_fleje, parte, proveedor, stock` |
| `informes_bundle(p_desde, p_hasta)` | Informe por persona | `desde, hasta, personas` |
| `informes_matriz_bundle(p_desde, p_hasta, p_incluir_piedra)` | Informe por matriz | `desde, hasta, empleados, hsTotalByEmp, matrices` |
| `inicio_bundle()` | GP2_MODULOS (menú) | `alertas, dia, generado_en, hoy, mes` |
| `inyectores_bundle()` | Inyectores | `generado_en, partes, proveedores, sector, sectores` |
| `movimientos_bundle()` | gp2-motor.js (Stocks General, Entregas Talleristas), Registro operarios | `art, bom_art, bom_comp, c2a, comp, inv, mat, prov_serv, rp, sect, tall, ubic` |
| `oc_bundle()` | OC | `charcas_kg_x_paquete, generado_en, insumos, ocs, paq, pliego_uni_x_paquete, proveedores, tc` |
| `orden_produccion_bundle()` | Orden de Producción | `componentes, destinos, generado_en, matrices, pasos` |
| `pintores_bundle()` | Pintores | `partes, pintores` |
| `problemas_matrices_bundle(p_desde, p_hasta)` | Problemas con Matrices | (eventos RM/PM) |
| `produccion_bundle(p_matriz, p_anio)` | rendimiento_GP2.js | `matrices, empleados, rows` (ver sección propia) |
| `produccion_maestro_bundle(p_desde, p_hasta)` | Maestro de producción | `desde, empleados, hasta, matrices, rows` |
| `programa_bundle()` | Programa | `art, bom, children, comp, fl, mat, prov, rp, rutas, rutas_by_art, sect, tall, tall_art` (nombres CORTOS, ver sección propia; idea 7252) |
| `proporciones_bundle()` | Proporciones | `articulos_compartidos, generado_en, nota, proporcion_disponible, talleristas` |
| `recepcion_bundle()` | Recepción Insumos | `insumos, pallets, proveedores, recepciones, rollos, sectores, tara` |
| `registro_operarios_bundle()` | App de operarios | `empleados, matrices, matriz_fleje, matriz_fleje_pieza, matriz_salidas, registro_en_golpes, rollos_abiertos, rollos_saldo` |
| `relevamiento_bundle()` | Relevamiento | `cronograma, hoy` |
| `rollos_bundle()` | Flejes (rollos) | `eventos, flejes, saldos, usos` |
| `stock_sector_bundle(p_sector_id)` | gp2-stock-sector.js (los 9 sectores) | `filas, generado_en, sector, ubicacion_id` |
| `stock_transito_ps_bundle()` | Stock Tránsito PS | `filas, generado_en` |
| `talleristas_bundle()` | Envíos Talleristas y Control Talleristas | `generado_en, partes, tall` (`partes` = dict por tallerista `{entrada:[...], salida:[...]}`) |
| `validacion_bundle()` | Validación de Stock | `aplicados, hoy, pendientes` |
| `valorizacion_bundle()` | Valorización | `comps, costo_seg, generado_en, tc, tc_info` |

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

**`ubicacion.tipo` tiene SEIS valores**: `sector`, `tallerista`, `proveedor_servicio`,
`proveedor_at` (los 12 proveedores de articulos terminados), **`virgilio`** (id 33, la
distribucion) y `analisis` (id 46 «Para Analizar», adonde va una devolucion que hay que mirar).
Los 84 articulos terminados (sector 12) no tienen ubicacion de sector: viven en Virgilio.

`tipo_mov` (vocabulario del ledger, verificado 2026-09-04): `compra` (recepciones de insumo y
compras de MP), `consumo` (MP consumida por un PS híbrido: Charcas/Eclipse), `envio_ps` /
`entrega_ps`, `envio_tallerista` / `entrega_tallerista` / `consumo_tall` (partes consumidas al
entregar un armado) / `devolucion_tallerista`, `envio_prov_at`, `fabricacion` (producción con
matriz), `armado_fabrica` / `consumo_prod` (armado en fábrica desde Stocks General),
`recepcion_virgilio` / `consumo_virgilio` (espejo de las entregas en Virgilio), `stock_inicial`,
`ajuste`. Antes convivían `recepcion_tall` (JS) y `consumo_armado` / `consumo_transformacion`
(SQL) para lo mismo: se unificaron en la auditoría del 2026-09-04. **Desde el 2026-09-05 el
vocabulario es cerrado**: `movimiento_tipo_mov_chk` rechaza cualquier otra palabra (también las
que manda el JS por `registrar_movimientos`). Un tipo nuevo se agrega en el CHECK y en el mapa
`TIPOS` de Stocks General / `gp2-composicion.js`.

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
| `articulo_componente`, `est_madre`, `ruta_paso` | `trg_maximos_receta` / `_est_madre` / `_rutas` | `fn_recalc_maximos_insumos` | Maximo de insumos por Est Madre explotada |
| `precio_tallerista` | `trg_precio_tallerista_kg` | `fn_precio_tallerista_kg` | Precio por kg derivado |
| `recepcion_control_rollo` | `trg_rollo_desde_control` | `fn_rollo_desde_control` | Da de alta el rollo al pesar el pallet |
| `public."Entregas Tallerista Virgilio"` | `trg_virgilio_espejo_gp2` | `fn_entregas_virgilio_espejo` | **Espejo public → GP2**: cada entrega en Virgilio se registra en `movimiento` (o queda en `virgilio_espejo_pend` si no cruza) |
| `public.proyeccion_madre` | `trg_est_madre_sync_gp2` | `fn_est_madre_sync` | **Espejo public → GP2**: `est_madre` (uni = cajas × articulos_por_caja cuando el origen no trae uxb) |

Cron: un solo job de GP2 entre los 49 del proyecto, `gp2-dolar-oficial` (`10 9 * * *` UTC →
`"GP2".actualizar_dolar_oficial()`). Los otros 48 son de `public`/`planify` (la casa del vecino).

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
