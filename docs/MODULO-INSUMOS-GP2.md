# Equivalencias de insumos Virgilio ↔ Cervantes (GP2) ↔ ISIS

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠⚠ REGLA (Luis, 2026-10-13, v29.74): LA TABLA DE EQUIVALENCIAS DE INSUMOS ES UNA — `GP2.insumo_equivalencia`

**Luis:** *"tiene que haber una tabla de insumos que muestre la equivalencia entre un insumo de virgilio, de
cervantes y el codigo ISIS que tienen. Punto."* · *"¿cómo catzo terminamos teniendo dos?"*

> **Toda equivalencia de códigos de insumos vive en `GP2.insumo_equivalencia`** (`cod_virgilio` ·
> `componente_id` → cod de Cervantes · `isis`). Legible: **`GP2.v_insumo_equivalencia`**. Se edita en
> GP2 → Stock general → pestaña Virgilio. **No se crea otra, ni una columna que haga lo mismo.**

Había dos, y la vieja **no era una tabla: era una COLUMNA** (`GP2.componente.codigo_virgilio`, 8 filas, sólo
bolsas, de la v14.95). Por eso nadie la encontró el 30/09 cuando hizo falta un mapeo, y se creó la tabla al
lado. Mismo pozo que el módulo de Matricería duplicado.

⚠ **Y la columna nació mal, no se desalineó:** estaba cargada con abreviaturas del lado de Cervantes (`NV`,
`NR`, `N25`, `PP`, `PS`, `PE`) que **nunca existieron en Virgilio** — los códigos de Virgilio son `NY Virgen`,
`PP 2630`, `NY Recup`… desde el 02/07. Coincidían sólo `ABS` y `AI`.

**Lo que costó, medido el 13/10:** `GP2.movimiento` tipo `envio_inyector` tenía **0 filas en toda su
historia**, mientras en Virgilio salieron **86 bolsas (2.150 kg)** a inyectores entre el 25/08 y el 08/10
(Rafael 57, Manolo 29). 7 de las 9 bolsas no matcheaban, así que `enviar_material_virgilio` **no se llamaba
nunca y encima en silencio** (`_insGp2Mat` devolvía null y la fila salía del lote sin avisar). El espejo bajaba
la 57 igual: los kg se evaporaban.

⚠ **No hay desfase de stock que ajustar** (medido): el espejo del 09/10 fijó la 57 al saldo real de Virgilio
(la **subió de 0 a 5.525 kg**: GP2 nunca había tenido stock de bolsas), y esas salidas ya estaban netas ahí.
Lo que no existe es el **circuito del inyector: ni las salidas ni las devoluciones** (0 movimientos con las
ubicaciones 58-61 en toda la historia). Cargar sólo las salidas dejaría a Rafael debiendo kg que ya devolvió
inyectado: arrancarlo pide **un conteo de lo que cada inyector tiene hoy**, no un backfill.

| pieza | qué cambió |
|---|---|
| `GP2.componente.codigo_virgilio` | **borrada** (backup `zz_backups."GV_Backup_CodigoVirgilio_20261013"`) |
| `enviar_material_virgilio` · `recibir_oc_virgilio` | resuelven el componente por `insumo_equivalencia`; sin fila, **fallan ruidoso** |
| `material_virgilio_bundle` · `oc_pendientes_virgilio` | devuelven el **código REAL** de Virgilio (el front de GV matchea con `_insK()`, upper+trim: no hubo que tocarlo) |
| `recalcular_maximo_material` | «está en Virgilio» = tiene fila en la equivalencia |
| `public.gv_gp2_inventario` | `codigo_virgilio` sale de la equivalencia — ⚠ con `CREATE OR REPLACE`, nunca `DROP CASCADE` (cuelgan `gv_gp2_stock_componente` y `gv_importados_ordenes`: ese cascade ya dejó Importados en 404 en la v16.20 y la v16.33) |
| front (`index.html`) | **una bolsa sin equivalencia NO pasa en silencio**: con un inyector elegido, cualquier ítem que el bundle no reconozca frena con el confirm («¿registrar igual sólo en Virgilio?»). El criterio **no usa `insCatOf`**: si el catálogo de categorías no se leyó devuelve `""` para todo y el guard no frenaría nada |
| `isis` | cargado desde `Insumos.isis`: **29 de 79**. Las bolsas tienen el ISIS igual al código de Cervantes (2455 = ABS); ⚠ **AI no**: componente 2465, ISIS 1135 — mirar si no es un error de carga en `Insumos` |

⚠ **`EBA` queda CERRADO** (Luis, 13/10: *"se definirá después; el admin que está creando la página tiene que
setear el código de Cervantes"*): sus 20 bolsas (celda Q34) no cruzan al espejo porque no tiene componente en
Cervantes. **No se da de alta desde acá y no se vuelve a sugerir.**
⚠ **`CAJA Nº 1` y `CAJA Nº 22` tienen el mismo ISIS (`0127`)** en `Insumos`: uno de los dos está mal.
⚠ Los centinelas de las 3 funciones de **GP2** no entran en `GV_Reglas_Centinela` (sólo alcanza `public`):
del lado de GP2 lo sostienen sus tests. En GV quedan los ids 388 y 406.

`sql/gv_insumo_equivalencia_unica_v2974.sql` (rollback en la cabecera), `tests/ins-bolsa-sin-equivalencia.cjs`.

### ⚠ v29.79 (Luis, 13/10): GP2 es el CANÓNICO del código ISIS — se replica a `Insumos`

**Luis:** *"si hay diferencias actualmente, asumi que el de GP2 es el canonico y remplazacelo a Virgilio"* ·
*"que haya boton para confirmar que se guarda/vincula el codigo ISIS con el de Virgilio y/o con el de Cervantes
o en cualquier permutacion de esas combinaciones"*.

> El dueño del ISIS de un insumo es **`GP2.insumo_equivalencia.isis`**. Lo que se guarda ahí se escribe en
> **`public."Insumos".isis`**, **incluido vaciarlo**. **Nunca al revés.**

- Lo hace el trigger **`public.gv_insumo_isis_sync`** (de GV, sobre la tabla de GP2 — mismo patrón que
  `gv_ingreso_virgilio_denegado`, v25.37). **No hay ciclo**: `gv_gp2_espejo_sync` copia `Insumos.isis` a
  `GP2.virgilio_insumo_stock`, que es **otra** tabla, y el bundle del editor ya leía la equivalencia primero.
- Pasa el bloqueo `aaa_gv_anon_bloqueo` porque es SECURITY DEFINER (`current_user` = postgres, regla v29.16).
- Del lado de GP2 (Stock general v3.7.0): el botón **«🔗 Vincular»** tiene columna propia y guarda en
  **cualquier permutación** (sólo Cervantes · sólo ISIS · los dos); un ISIS vacío **limpia** el dato en los
  dos lados. El vínculo con Cervantes no se borra desde ahí, a propósito.
- ⚠ **Para corregir el ISIS de un insumo de Virgilio se edita en GP2**, no en `Insumos`: si se toca sólo del
  lado de Virgilio, el próximo guardado desde GP2 lo pisa.
- Rollback: `drop trigger zz_gv_insumo_isis_sync on "GP2".insumo_equivalencia;`
  Adenda en `gestion-productiva-2.0/db/migracion_insumo_equivalencia_unica_20261013.sql`.
- **El Cód. Cervantes del editor sólo acepta códigos que EXISTEN** (Luis, 13/10, Stock general v3.8.0): es un
  `datalist` con todos los componentes de GP2; uno inventado no habilita el botón y no llega a la base.

#### ⚠ Medido el 13/10 (Luis: *"hacé la prueba de que funcione bien. que no joda ningún stock real"*)

> **VINCULAR NO MUEVE UN GRAMO DE STOCK.** Lo único que escribe es la fila de la equivalencia y el `isis`
> de `Insumos`. Medido en transacción abortada: `Movimientos_Stock` 82.475 → 82.475 · `GP2.movimiento`
> 45 → 45 · `GP2.inventario` 148.107,85 → 148.107,85 · el espejo 380.391,3 → 380.391,3.

| qué se probó | resultado |
|---|---|
| los dos (Cervantes + ISIS) | GP2 `9991` → GV `9991` |
| sólo ISIS (Cervantes vacío) | el componente **se conserva** (`coalesce`) y GV toma el ISIS nuevo |
| ISIS vacío | limpia en los dos lados, como pidió Luis |
| minúscula (`z23a`) | guarda la grafía real `Z23A` |
| código de Cervantes inventado | frena con `COMPONENTE_INEXISTENTE` |
| las 8 bolsas de material | cruzan a su componente (sólo falta **EBA**, cerrado); un envío de 2 bolsas de NY Virgen mueve 50 kg del sector 57 al inyector y **no toca `Movimientos_Stock`** |

⚠ **El riesgo de que un ISIS vacío borre un dato bueno es HOY CERO, y así se mide**: la pantalla pre-carga
el ISIS del espejo, y el espejo coincide con `Insumos` en **135 de 135** filas (0 casos de «espejo vacío y
GV tiene»). Si alguna vez el espejo quedara atrás, vincular con el campo vacío **sí** borraría el ISIS de
Virgilio: la consulta que lo mide es el `case` de `virgilio_insumo_stock` contra `Insumos` por `upper(cod)`.

⚠ **Lo que sí mueve stock es el ESPEJO**: al vincular un código con saldo, le fija ese saldo en el depósito
«<sector> en Virgilio». **No infla nada de Cervantes**: los 6 depósitos `virgilio_sector` tienen **0 filas en
`v_nivel_stock`**. Centinelas al cierre: `gv_reglas_perdidas`, `gv_endpoints_rotos` y `gv_huellas_cambiadas`
en **0**.

#### ⚠ v29.87 (Luis, 13/10): el espejo NO espera al cron — vincular lo dispara en el acto

**Luis, textual:** *"¿por qué tarda 10 min? debería ser lectura de una tabla en conjunto, instantáneo, no?"*.
Tenía razón, y lo que se mide es el tamaño del desperdicio:

| cuánto cuesta de verdad | medido 13/10 |
|---|---|
| calcular el stock de insumos **en vivo** (el bloque 1 de `gv_gp2_espejo_sync`) | **20 ms** · 163 filas |
| `gv_gp2_espejo_insumos(null, true)`, los 5 rubros | **28 ms** |
| leer el espejo ya copiado | 0,5 ms |
| el cron 112 entero (4 bloques con sus md5) | 123 ms, **cada 10 min** |
| el cron 152 del inventario | **cada 30 min** (`:19,:49`) |

> **~40 ms de trabajo esperaban en una cola de 10 y 30 minutos.** El motivo nunca fue el costo: el espejo
> se armó como **copia** por la Regla 0 de GP2 (GP2 no lee `public`).

- **El hueco concreto**: el stock ya se adelanta solo en cada movimiento de insumos (trigger
  `zz_gv_gp2_espejo_insumos` de `Movimientos_Stock`), pero **vincular no es un movimiento**, así que un
  código recién vinculado no mostraba su stock en GP2 hasta el cron. Hoy lo dispara el vínculo:
  **`public.gv_insumo_equiv_espejo`** (trigger `zz_gv_insumo_equiv_espejo` AFTER INSERT OR UPDATE OF
  `componente_id` sobre `GP2.insumo_equivalencia`, mismo patrón que el del ISIS).
- Medido: vincular N°56 tarda **57 ms** y sus **873 kg aparecen en el acto** en «Sector Fleje en Virgilio».
  Un vínculo que cambia **sólo el ISIS no dispara** el espejo (4,8 ms, 0 filas de log).
- ⚠ **Nunca frena el vínculo**: el error va a `GV_GP2_Espejo_Log` con `resultado = 'error'` y lo rehace el
  cron. Rollback: `alter table "GP2".insumo_equivalencia disable trigger zz_gv_insumo_equiv_espejo;`
- Centinela 420. `sql/gv_insumo_equiv_espejo_v2987.sql`.

#### ⚠⚠ v29.89 (Luis, 13/10: *"si, pasala a vista"*): `GP2.virgilio_insumo_stock` ES UNA VISTA EN VIVO

> **GP2 ya no lee una copia de hasta 10 minutos atrás: lee el saldo del momento, en 19,5 ms.**
> La tabla que el bloque 1 de `gv_gp2_espejo_sync` rehacía cada 10 min **se borró**; en su lugar hay una
> **vista** con las mismas 8 columnas (`actualizado_en = now()`), `security_invoker = true`.

- **Es una excepción APROBADA a la Regla 0 de GP2** (GP2 no lee `public`). La pidió Luis; el precedente
  que aprobó Thomas es **`GP2.v_produccion_todas`**, que lee `reg_prod_3_0`. **El resto del espejo sigue
  siendo copia**: los bloques 2, 3 y 4 (ubicaciones, Mapa, categorías) y el cron 112 no se tocaron, y
  tampoco `gv_gp2_espejo_insumos` / cron 152 / los dos triggers, que escriben el **inventario** de GP2 y
  son otra cosa.
- **Medido antes de aplicar** (transacción abortada): la vista devuelve las **mismas 163 filas y el mismo
  md5** que la copia, y **`anon` 163 · `authenticated` 163** — nadie pierde filas. Ese chequeo no es
  opcional: una vista con `security_invoker` sobre una tabla con RLS **no da error, devuelve MENOS filas**
  (la trampa de la v20.45), y `Movimientos_Stock` tiene RLS prendida. Medido aparte: `anon` ve las 163
  filas del depósito insumos y las 129 de `vista_insumos`.
- **Quién la lee** (medido, no supuesto): `GP2.virgilio_insumos_sin_match_bundle` (el editor de
  equivalencias) y `public.gv_insumo_isis_sync` (sólo la nombra en un comentario). **Ninguna vista**, y
  nadie le escribía salvo el bloque 1 que se sacó.
- ⚠ Los marcadores de la base dicen **v29.88** (otra sesión se llevó ese número mientras se escribía
  esto): son la **llave**, no se cambian.
- ⚠ **El marcador de la regla va en CÓDIGO** (`v_regla constant text := 'v29.88-vista'`), no en el
  comentario que la explica: `gv_reglas_perdidas` limpia los comentarios antes de buscar (regla v21.82),
  así que un marcador comentado vigila el rótulo y no la regla. Centinela **421**: si otra sesión repone
  el bloque 1 desde una copia vieja, avisa.
- Respaldo `zz_backups."GV_Backup_VirgilioInsumoStock_20261013"` (con RLS y sin escrituras).
  **Rollback completo** —vuelve la tabla, su PK, su policy y el bloque 1— en la cabecera de
  `sql/gv_insumo_stock_vista_v2988.sql`.

