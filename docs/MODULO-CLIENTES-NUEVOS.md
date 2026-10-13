# Pipeline de Clientes Nuevos

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

## ⚠ REGLA (Luis, 2026-09-21, v20.89): el PIPELINE **reemplazó** al submódulo de clientes nuevos

**Luis, textual:** *"implementá esta nueva versión de clientes nuevos en «A programar»
reemplazando la vieja"*. El submódulo 🆕 Clientes nuevos **ya no se dibuja**: en su lugar, dentro
de «A Programar», está el pipeline. Su pestaña propia se fue — el mismo módulo en dos lugares era
justo el problema de convivencia que se quería evitar. `clinNuevosHtml` y sus 9 funciones siguen
en el archivo (como `gv_ppp_np_desarmar` en la v18.77): lo que no puede volver es la **puerta**.

```
ingresado → [🔎 Análisis Cred.] abre Equifax y arranca el reloj
  → analisis → la dirección define UNO DE DOS:
      · 🤝 Referenciado    → ✅ Aprobar y programar
      · 💳 No referenciado → Speech 1 → Speech 2 (24 h) → 💵 Pagó → ✅ Aprobar
                                                        └→ 🗑 Cancelar pedido
```

### Los estados son DOS, y son del CLIENTE

**Luis, 21/09:** *"Después del análisis solo hay 2 estados que un cliente puede tener:
Referenciado y No referenciado. No referenciado se le requiere que pague los primeros 3 pedidos
por adelantado y el pipeline contempla todos los casos ahí (comunicaciones, aceptación,
cancelación)."*

⚠ **«No válido» ya NO existe.** Al cliente al que no se le quiere vender **se le elimina el
pedido** (🗑, disponible desde `ingresado`, sin tener que analizarlo), que lo saca de la PPP y lo
deja en el log de anulados. Eso descarta *ese* pedido: si vuelve a pedir, entra de nuevo — y el
log del cliente, que ahora es histórico, muestra que ya pasó antes.

⚠⚠ **Y la DECISIÓN AHORA SE HEREDA** (Luis: *"la verificación no se vuelve a hacer… lo único que
queda definir es el contacto por speech"*). **Esto dio vuelta la regla de la v20.73**, que decía
lo contrario. El 2.º pedido de un No referenciado arranca en «No referenciado» —o sea, pidiendo
el Speech 1— sin volver a Equifax, con el chip **🧠 ya definido**.

**Lo que NO se hereda son los timestamps**: el pedido nuevo tiene su `speech1_at` en null, así que
paga por adelantado igual. Si se heredaran, el 2.º pedido saldría como «ya pagado». Lo resuelve
`decision_ef = coalesce(propia, del cliente)` en `gv_clin_pipeline_lote`, y lo marca
`decision_heredada`.

### ⚠ El cliente nuevo RECURRENTE no se vuelve a analizar (Luis, 23/09, v21.48)

**Luis:** *"para clientes nuevos recurrentes (que todavía no tienen 3 pedidos completados) debería
directamente abrir el «qué sigue» en speech 1, speech 2 y agregar la opción de marcarlo como
referido"*. Caso: **LK 1448 · Silvano (LK 4282)**, 2.º pedido, figuraba «Sin analizar» porque su
1.er pedido es anterior al pipeline y no había decisión que heredar.

Si el pedido no tiene decisión propia ni heredada y `GV_Clientes_Nuevos.pedidos >= 1`,
`gv_clin_pipeline_lote` devuelve `decision = no_referenciado` (columnas nuevas `recurrente`,
`pedidos_previos`) → arranca en **💬 Speech 1**, con el chip **🔁 recurrente**. En
`no_referenciado`, `speech1` y `speech2` está el botón **🤝 Referenciado** (`gv_clin_etapa` ya le
da prioridad sobre los speech). No se escribe ninguna fila: se deriva al leer.
`sql/gv_clin_recurrente_v2148.sql`, `tests/pipe-recurrente.cjs`.

⚠ **«🔗 Vincular» a una razón social que ya es cliente va en TODA etapa abierta** (Luis, 07/10, v27.62): ingresado,
análisis, referenciado, no referenciado, speech 1, speech 2 y pagado (`_vinc` en `pipeAccionesBtns`). Faltaba en análisis,
speech 1/2 y pagado. `tests/pipe-vincular-todas-etapas.cjs`.

### ⚠ El cliente nuevo APROBADO sale en 48 h (Luis, 23/09, v21.67)

Aprobado (fila en `GV_Cuarentena_Liberados` con `cliente_nuevo`) → el pase **(a0e)** del armador lo
programa **forzado** en uno de los **2 días con reparto** siguientes a la aprobación
(`gv_clin_dia_aprobado`): primero el que ya tiene camión a su grupo de zonas, después el que tiene
cupo. Si no encaja por zona sale igual. El botón de Equifax abre la landing
(`https://www.equifax.com.ar/`), decidido por Luis. `sql/gv_clin_aprobado_48h_v2167.sql`.

### ⚠ «Aprobado» = la liberación que levanta `cliente_nuevo`, no cualquier fila (Luis, 02/10, v26.18)

**Luis:** *"si está aprobado, ¿por qué sigue apareciendo ahí?"*. **LK 1576** (Hsu Ya Wen) se liberó en
Cuarentena **sólo por límite de crédito** (30/09) y el pipeline lo pintó *«Aprobado — ya está en Pedidos a
programar»*, **sin botones**, mientras el armado lo seguía reteniendo por cliente nuevo: 2 días parado.

| dónde | criterio de «aprobado» |
|---|---|
| `gv_cuarentena_marcar_calc` (retiene) | motivos NULL / vacío (libera todo) **o** incluye el motivo |
| `gv_clin_pipeline_lote`, `gv_clin_evento`, `gv_clin_vencidos`, `gv_clin_prioritarios` | lo mismo, con `cliente_nuevo` |
| pase **(a0e)** de 48 h del armador | lo mismo — antes exigía `cliente_nuevo` explícito y el ✅ del pipeline graba **NULL**: LK 1548/1549, aprobados el 01/10, salían el 14/10 |

⚠ **Al leer `GV_Cuarentena_Liberados` para decidir algo de cliente nuevo, mirar `motivos`**: una fila puede ser la
liberación de OTRO motivo. Centinelas 282-284. `sql/gv_clin_aprobado_cliente_nuevo_v2618.sql` (marcador interno `v26.15-clin-aprob`: no cambiarlo).

### Los 3 pedidos NO se cuentan acá: ya los corta LK

*"Después de que pasan 3 pedidos bien pagando por adelantado ya se considera un cliente normal."*
Eso **ya estaba hecho y no se tocó**: `GV_Clientes_Nuevos` sólo trae clientes con **1 o 2**
pedidos facturados (medido al 21/09: 269 con 1, 80 con 2, **ninguno con 3**). Al tercero el
cliente desaparece de la tabla y deja de caer en el retén. Y como un pedido cancelado por no
pagar nunca se factura, no suma — el contador hace exactamente lo que pide la regla.

### ⚠ CUARENTENA PRIMERO — y liberar ya no levanta el candado entero

**Luis:** *"cuarentena toma prioridad sobre cliente nuevo (ej, un cliente nuevo con deuda pasa
primero por la cuarentena y después cuando es liberado con «Enviar a Pedidos a programar» va al
módulo de clientes nuevos"*.

Medido el 21/09 sobre 45 pedidos retenidos: **25** sin cliente nuevo, **13** cliente nuevo puro,
**7** cliente nuevo + deuda. Sin esta regla esos 7 (el **35 %** de los clientes nuevos) habrían
quedado en las **dos** columnas a la vez.

| el pedido está… | dónde cae |
|---|---|
| retenido por deuda / suspendido / límite (con o sin cliente nuevo) | **Cuarentena** |
| retenido **sólo** por cliente nuevo | **el pipeline** |
| liberado de la deuda, pero sigue siendo cliente nuevo | **el pipeline** |
| liberado de todo | Pedidos a programar |

Son **dos cambios que van juntos**, y uno sin el otro no hace nada:

1. **`gv_cuarentena_marcar_calc` resta** de los motivos vivos los que esa liberación resolvió
   (`GV_Cuarentena_Liberados.motivos`, que ya se guardaba y **nadie leía**). Antes el liberado
   quedaba excluido entero.
2. **El botón de Cuarentena nunca libera `cliente_nuevo`** (`cuarLiberarConfirmar` lo filtra). Si
   lo liberara, el pedido se iría derecho a programar y no pasaría nunca por el pipeline. Quien
   levanta ese motivo es el **✅ del pipeline**.

⚠ **Una liberación vieja con `motivos` en NULL *o en array vacío* libera TODO.** Los dos casos
significan lo mismo —"no se registró el detalle"— y sin el segundo guard el pedido **1368**, que
tiene `'{}'`, volvía al retén. Medido: de los 38 ya liberados, vuelven **2** (98585 y 98586, que
se liberaron sólo por deuda y siguen siendo cliente nuevo), y **los dos ya están programados**, o
sea que no están en la lista de pendientes: cero impacto visible.

### ⚠ El TELÉFONO se busca por `(empresa, cod)`, nunca por código solo

El Excel del dueño del 08/09 **ya está dentro de `whatsapp_clientes`**: de los 332 códigos
compartidos, **0** tienen teléfono distinto, y las dos cargas se escribieron con 12 segundos de
diferencia. No hay dos verdades — pero **26 filas del dueño nunca llegaron**:

| | |
|---|---:|
| filas del dueño que no están en `whatsapp_clientes` | **26** |
| …que son el mismo código en LK **y** en CH | 13 códigos |
| …de esos 13, con **otro teléfono** en cada empresa | **13** |
| …de esos 13, con **otra razón social** | **13** |

`whatsapp_clientes` no tiene columna empresa, así que esos códigos no entraban y **se descartaron
los dos lados**. Por eso `GV_Clientes_Whatsapp` (358, con empresa) **manda**, y `whatsapp_clientes`
(942, sin empresa) es el respaldo **sólo si el código no existe en las dos empresas** — son **257**
según el padrón de direcciones. La RPC devuelve además `origen`: `padron_empresa`, `historico`,
`ambiguo_sin_dato` o `sin_dato`.

**Chequeo** (tienen que salir dos teléfonos distintos):
```sql
select * from public.gv_cliente_nuevo_wpp_lote(
  '[{"empresa":"lk","cod":"94"},{"empresa":"chef","cod":"94"}]'::jsonb);
```

⚠ **Lo que sigue faltando, y no es un bug del código:** de los 12 clientes nuevos de hoy, **6 no
tienen teléfono en ninguna tabla** — y **11 de 12 tienen mail**. La página les pide mail, no
WhatsApp. Eso se arregla en la página, no acá. (Otros 2 están sólo en `customers.whatsapp` de LK
y necesitan que LK los empuje por el FDW, como `sync_cliente_isis_virgilio`.)

### El LOG es del CLIENTE, no sólo del pedido

**Luis:** *"deberían quedar registrados los «Coment.» a modo de log histórico. Si un cliente
vuelve a entrar en el módulo de clientes nuevos, debería traer todo el log anterior de veces
anteriores que estuvo."*

`GV_Cuarentena_Comentarios` tiene ahora **`cod`** (nullable, sin default que reescriba). El
backfill lo recuperó cruzando con `GV_Cuarentena_Log`: **70 de 71**. El 📖 muestra el hilo de
**este** pedido y debajo, apagado, **🕘 Antes, con este cliente** —los comentarios de sus otros
pedidos— vía `gv_clin_comentarios_cliente`, en su propia llamada con su propio catch.

### Lo que no cambió, y no se toca

| | el pipeline usa… |
|---|---|
| aprobar | **`gv_cuarentena_liberar`**, la MISMA función de siempre |
| el timer | sella **`GV_Clientes_Nuevos_Contacto`** |
| el log | **`GV_Cuarentena_Log`** con prefijo `pipeline_` |

Lo sostiene `tests/pipe-clientes-nuevos.cjs` con el **candado invertido**: si alguien le escribe
al pipeline su propio «aprobar», el test se pone en rojo.

### ⚠⚠ Esta función LA TOCAN VARIAS SESIONES — y lo pisó una, en el medio

Mientras se escribía esto, otra sesión hizo `CREATE OR REPLACE` de
**`gv_cuarentena_marcar_calc`** partiendo de su propia copia y **borró este cambio** (se notó
porque apareció su CTE `mismo`, de la v20.52, que antes no estaba). Se reaplicó sobre la
definición viva, conservando lo de la otra sesión.

Por eso el bloque de `sql/gv_clin_dos_estados_v2086.sql` **se aplica sobre `pg_get_functiondef`,
es idempotente** (si ya tiene la regla, no hace nada) y **falla con un `raise` si el texto no
matchea**, en vez de escribir una versión vieja encima. Y las cinco reglas tienen su fila en
`GV_Reglas_Centinela`:

```sql
select * from public.gv_reglas_perdidas;   -- vacía = ninguna regla se perdió
```

### Qué se prueba, y cómo

- **`tests/pipe-en-a-programar.cjs`** dibuja A Programar de verdad y mira **qué columna se lleva
  cada pedido**: es lo único que prueba que no se duplican. Ahí están también la zona, el
  colapsable, los dos estados y el fallback de la pestaña vieja.
- **`tests/pipe-clientes-nuevos.cjs`** son los candados estáticos (el aprobar compartido, el
  guard del array vacío, la herencia, el log por cliente, el teléfono por empresa).
- **`tests/pipe-vinculo-en-el-cuadro.cjs`** corre el cuadro y mira el **orden real** de las RPC.
  ⚠ Un candado de texto no puede verificar semántica: cuando importa el orden o la condición, el
  test se corre.

⚠ **El fallback de la pestaña vieja va ANTES del `return` de `"prog"`** en `pppRenderProg`, o no
se ejecuta nunca. Lo verifica el test — el primer intento lo puso después y quedaba muerto.

**Los relojes y la URL de Equifax se cambian con un `update`, no con un deploy:**

```sql
update public."PPP_Web_Config" set valor = 48 where clave = 'clin_speech_horas';
update public."PPP_Web_Config" set valor_texto = '<url>' where clave = 'clin_equifax_url';
```

⚠ `PPP_Web_Config.valor` es **numeric** y `make_interval(hours => numeric)` **no existe**: esos
coalesce van con `::int` o la función explota en la primera llamada (el `CREATE` sale limpio).

**El CLIENTE DE PRUEBA** (botón «👁 Ver cliente de prueba») avanza por las etapas de verdad, pero
su clave es `__DEMO__` y el backend lo aísla: no escribe el log, ni el timer, ni ninguna
excepción. **Si se suma una escritura nueva a `gv_clin_evento`, va con `and not v_demo`.**

**Chequeo:** `select * from public.gv_clin_vencidos;` — lo que espera hace demasiado (el pedido
**no se cancela solo**). Y `select * from public.gv_clin_prioritarios;` — lo aprobado que tiene
que salir en 2 días hábiles.

### ⚠ v24.32 (Luis, 29/09): el botón del cliente de prueba es 🖨 IMPRIMIR

*"cambiá el botón de cliente de prueba por un botón de imprimir que promptee la impresión de un
excel … asegurate de que haya una columna que se llame «Comentarios» que tenga todos los
comentarios de esa gestión en una celda (bien ordenados, separados y visibles)"*. Es el mismo
camino que tomó Cuarentena en la v20.53: el ejemplo era la ayuda de la primera semana y el
reporte se usa todos los días. `pipeDemoToggle` y `pipeDemoPedido` **siguen en el archivo** — lo
que no vuelve es la **puerta**: el ejemplo se prende desde la consola (`_apr.pipeDemo = true`) y
ahí reaparece su «↺ Reiniciar ejemplo».

El Excel (`pipeExportarExcel`) se arma en el FRONT, como el de Cuarentena: **20 columnas** con lo
que ya pinta la tabla (pedido y sus partes, NP, fecha y días, m³, empresa, código, razón social,
CUIT, teléfono, zona, etapa, espera, vencido, quién lo definió, a cobrar neto y c/IVA, descuento,
importados en falta) más **Comentarios**.

⚠ **Los comentarios NO están en la pantalla**: la tabla sólo muestra **cuántos** hay (el 📖 sale
de `gv_cuarentena_comentarios_lote`, que devuelve el conteo). El texto se pide por pedido con
`gv_cuarentena_comentarios`, **una llamada por parte** de la gestión —un pedido partido por
importados es UNA fila (v23.06), así que se juntan los de todas sus partes y se ordenan por
fecha— y todas en paralelo.

⚠ **Si esa lectura falla, la celda lo DICE** (`(no se pudieron leer los comentarios)`), no queda
vacía: una lectura rota no es *"sin comentarios"*.

⚠⚠ **SheetJS community NO escribe estilos, así que `wrapText` no se puede forzar** — medido el
29/09 sobre `vendor/xlsx.full.min.js` 0.20.3: se le pone `cell.s.alignment` y el `styles.xml` que
genera sale con `cellXfs count="1"` sin alignment. Por eso cada comentario va **numerado y con su
fecha y su autor** (`1) 26/09/26 09:00 · Vivi: …`) y separado además por salto de línea: sin el
ajuste de texto se leen igual, y con el ajuste puesto quedan uno por renglón. **No volver a
intentar el wrap desde el front.**
⚠ **v26.92: el formato SÍ se puede, pero no con `cell.s`**: `gvXlsxFormato(XLSX, wb)` abre el .xlsx ya
armado con `XLSX.CFB`, reescribe `styles.xml` (Arial 10 + encabezado centrado con ajuste) y congela la fila 1;
`gvXlsxBajar` lo descarga. Lo usa el Excel de Generar las OCs (`tests/ocg-excel.cjs` lo abre y lo mide).

**Chequeo:** `node tests/pipe-imprimir-excel.cjs` — corre el export de verdad con la RPC
mockeada (verificado que falla contra el index anterior). `sql/gv_clin_dos_estados_v2086.sql` (vigente; se aplicó como v20.89 — la v20.86, la v20.87 y la v20.88 se las llevaron otras sesiones) y
`sql/gv_clin_pipeline_v2066.sql` (tablas, config, vínculo y vistas), §3.ln.
