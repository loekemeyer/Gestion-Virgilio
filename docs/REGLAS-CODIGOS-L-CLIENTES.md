# Reglas Codigos L Clientes — Códigos con L, Cencosud / Tierra del Fuego, código de cliente por empresa, duales, códigos dados de baja

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

## ⚠ Regla del dueño (2026-09-07, v13.71): lo que entra por Chef ES de Chef; artículo LK → "L" al final

Un cliente de LK que pide por la página de Chef: el pedido es de Chef de punta a punta, se factura por Chef, y
cada artículo de Loekemeyer va con **"L" al final** (505 → 505L; 438E → 438EL). La regla vive en las páginas
(`paginach` / `pagina-LK-copia`, `admin-supercot.js` `addLSuffix = isChef`) y Gestión la respeta: la L manda el
stock a la góndola LK (`pkEmpresaArt`), el m³ sale de `vista_volumen_articulo_resuelto` (tiene los `NNNL`), el
precio de la lista LK pelando la L (`gv_ppp_np_valor` v13.71), y la factura / Excel ISIS llevan el código crudo
con L. **Nunca** recodificar 7xx→5xx ni "pasar a LK" un pedido de Chef. Informe: `docs/INFORME-PEDIDOS-LK-POR-CHEF.md`.
**Tierra del Fuego (v13.77, dueño 07/09): *"los que le hacemos FC E [Factura E] vendiéndole art. de Loeke … el pedido se arma
como Loeke (con una L al final) y después va a ISIS de CH, no de LK"*** — un pedido de la página LK con sucursal de entrega en
Tierra del Fuego sigue siendo NP **LK** (se pickea de la góndola Loeke), pero cada artículo lleva **L** (505L) y el Excel ISIS va
al de **Chef** con el código de cliente de Chef del mismo CUIT (vista `v_pedidos_web` de LK: `isis_empresa`, `cod_isis`;
`_facXlsArmar`). Los 10 clientes LK de TdF ya cruzan por CUIT. **Excepción: La Anónima (771) se vende por LK** (`gv_isis_override` en LK, por CUIT). **Cencosud (Chef 2444)** lleva **L** (v21.09, y Tomás Gonzalez 02/10/2026, ver «LA L ES DE CENCOSUD Y DE TIERRA DEL FUEGO»); igual entra al checklist de ajustes ISIS (`gv_fac_ajustes_isis` v2, v13.79), que lo detecta por la L. Ser cliente de las dos empresas, solo, no es problema; **el cod
cliente no significa nada, sólo el CUIT vale** (v13.76). La regla v13.75/76 ("cliente con FC en LK → no se programa",
`cliente_fc_lk`) fue un malentendido y está **apagada** (`doble_lk_dias = 0`); **también la de v13.72 ("mismo cliente por CUIT, mismo día en ISIS LK", `en_produccion_lk`; `doble_lk_mismo_dia = 0`, v13.82)**: *"ya expliqué que eso no corresponde"*. §3.az, §3.ba y §3.bb.
**⚠ Y la CUARENTENA de esos pedidos se evalúa con el cliente de CHEF (v17.75, dueño 14/09: *"se marcan y se evalúan
para cuarentena con código de cliente CH"*).** El padrón de LK los tiene con **límite 0** y 4 de 9 como *Suspendido*,
justamente porque a ese cliente no se le vende por LK: evaluar por LK retiene pedidos sanos (pasó con **LK 1431**,
Il Cheff) y nunca mide el crédito. El mapeo `(lk, cod)` → `(chef, cod_isis)` vive en `GV_Cliente_Isis` —lo empuja LK
con `sync_cliente_isis_virgilio()`, cron cada 15 min— y lo resuelve `gv_cuarentena_ident`, que usan las tres
funciones de Cuarentena. **Una NP tipeada en ISIS NO se remapea**: lleva el código de ese ISIS. **⚠ Cencosud NO entra
por esta regla y NO hay que darlo de alta** (dueño, 14/09: *"Cencosud sube pedido por Krikos… siempre (histórico)
subió pedidos por CH. No lo voy a dar de alta."*): no carga por la página, sus OC entran por **Krikos** y la Bandeja
las manda directo al portal de **Chef** (`precios_super.cadena`: `cencosud` → `empresa='chef'`, `cod_cliente_chef=2444`,
`cod_cliente_lk` nulo). Medido: 4.452 líneas del 2444 en `sales_lines` marcadas `chef` desde 2021-05-27, ninguna en LK.
Su caso (NP de Chef con artículos de Loeke, **con** L desde feb/2026, v21.09) ya lo cubre `gv_fac_ajustes_isis` (v13.79): es el caso
**inverso** al de Tierra del Fuego. `sql/gv_cliente_isis_v1775.sql`, §3.fp.

## ⚠ REGLA (Luis, 2026-09-22, v21.09): la L es de CENCOSUD y de TIERRA DEL FUEGO — de nadie más

**Luis, textual:** *"lo de la L debería aplicar únicamente a CENCOSUD y a pedidos que van a
TIERRA DEL FUEGO"*.

La regla v13.71 de más abajo (*"lo que entra por Chef ES de Chef; artículo LK → L al final"*)
se leyó como *"todo pedido de Chef lleva L"*, y **no es eso**:

> **La L no la decide quién FACTURA: la decide de quién son los ARTÍCULOS.**

| súper | factura por | sus artículos son de | ¿L? |
|---|---|---|:--:|
| **Cencosud** | Chef | **LK** (matchea contra LK + `loke_products`) | **SÍ** |
| **Dorinka** (Chango Más) | Chef | **Chef** (`usa_productos_chef`) | **NO** |
| el resto (Coto, INC, Día, Diarco…) | LK | LK | NO |

El criterio ya estaba en el código y en la config: `isChefSuper(k) && !usesChefProducts(k)`,
que sale de `precios_super.cadena` de LK. Medido: `empresa='chef' and usa_productos_chef=false`
devuelve **una sola cadena, Cencosud**.

**Lo que estaba roto** (en `pagina-LK-copia/admin-supercot.js` y su espejo `admin/` de acá):
`addLSuffix = isChef` en el submit y `cencosud || dorinka` en el PDF. El admin de **Chef**
(`paginach`) siempre estuvo bien, con el comentario *"Dorinka NO lleva L (son art. de Chef);
solo Cencosud"*.

**Lo que costó, medido:** el pedido 229 de Dorinka (NP **CH 0025**) salió con los 5 códigos con
L — `769L`, `840L`, `838L`, `865EL`, `798EL` — y del lado de LK **no hay una sola caja** de
ninguno: 769 → 0, 798E → 0, 840 → 0, 865E → 0. Todo el stock está en Chef (40, 74, 85 y 9).

⚠ **Esto NO contradice la regla de abajo: la L sigue sin sacarse nunca de un pedido.** Lo que
cambia es **quién se la pone al armarlo**. Si un pedido ya tiene la L, viaja y rutea como
siempre; lo que no puede es nacer con una L que no le corresponde.

⚠⚠ **La CONVERSIÓN de un pedido de Cencosud en Gestión: es de CHEF y cada código lleva L al final**
(Tomás Gonzalez, 02/10/2026: *"al hacer la conversión en Gestión-Virgilio, el pedido debe pasar a ser de
Chef, y los códigos de los artículos se le agregan una L al final"*). Las OC de Cencosud se cargan en el
**PDF Krikos del admin de LK** (en el de Chef están bloqueadas: matcheaba contra el catálogo de Chef y entraba
un renglón solo, 816L); LK crea el pedido en **Chef** con `cod_art` + **L** y el feed `gv_pedidos_web_np_chef`
la conserva (`usa_productos_chef = false`). Acá queda **NP CH**, el picking va a la góndola **LK** y el Excel
ISIS al ISIS de **Chef con la L** — que es como ISIS Chef le factura a Cencosud desde feb/2026 (031L, 102EL,
816EL…; en enero todavía iba sin L). Medido el 02/10: **todos** los códigos que Cencosud compró en 12 meses
terminan en dígito o `E` antes de la L, así que `pkStripL` (`/[0-9E]L$/`) los pela a todos. Lo sostienen
`tests/regla-L-super.cjs` acá y el bloque F de `tests/cencosud-cliente-chef.cjs` en `pagina-LK-copia`.

⚠ **Y Tierra del Fuego va por otro camino** (v13.77): ahí la L no la pone el cotizador de
súper sino el pedido de la página de LK con sucursal de entrega en TdF. Son dos orígenes
distintos de la misma marca.

`sql/gv_secundarios_web_y_regla_L_v2109.sql`.

**Chequeo (v21.84):** `node tests/regla-L-super.cjs` — candado **estático** sobre
`admin/admin-supercot.js`: las dos asignaciones de `addLSuffix` (el submit y el PDF) tienen que
llevar `&& !usesChefProducts(...)`. Verificado que falla con `addLSuffix = isChefSuper(k)` a
secas, que es como estuvo hasta la v21.09. Se corre **sin comentarios**: el comentario que
explica la regla nombra `usesChefProducts` igual, y un candado que vigila su propio comentario
no vigila nada (v21.82).

⚠ Esta regla **no tiene centinela en la base y no puede tenerlo**: no vive en Supabase, vive en
el JS de las páginas. Gestión tiene la copia que se sirve por Pages; el fuente está en
`pagina-LK-copia` y `paginach`, y ahí **no hay test que lo sostenga** — al tocar ese archivo en
cualquiera de los dos repos, mirar esto.

## ⚠⚠⚠ REGLA: LA "L" NO ES UN CÓDIGO — ES UNA DENOTACIÓN

**Thomas, 2026-09-18, textual:** *"la L no existe. `026L` no es un código válido. Existe sólo para
denotar que el `026L` es un `026` en pedido de Chef que se pickea del stock de LK."*

**No hay ningún artículo que termine en L** (verificado el 02/09 en `loke_products`,
`chef_articulos_activos`, `milver_products`, remaps y todo el pipeline). La L es una **marca de
ruteo** que viaja pegada al código del PEDIDO y significa exactamente dos cosas:

1. al **pickear** → la caja sale de la góndola de **Loekemeyer**, no de la de Chef;
2. al **facturar** → la línea va al ISIS de **Chef** con el artículo de Loeke.

### Dónde va la L y dónde NO — está resuelto en el código, no hay que decidirlo cada vez

| capa | objeto | ¿lleva L? | quién lo resuelve |
|---|---|:--:|---|
| Pedido | `PPP_Web_Base.articulo`, `gv_ppp_np_items` | **SÍ** (`026L`) | lo trae el feed de la página |
| Picking (pantalla y stock) | lista de picking, `Movimientos_Stock.cod_art` | **NO** (`026`, o `438E LK` si es dual) | **`pkResolveArt`** = `pkStripL` + `pkEmpresaArt` |
| Armado / factura | `Entregas_Virgilio.cod_art`, Excel ISIS | **SÍ**, crudo (`438EL`) | `_facXlsArmar` lo toma tal cual de `Entregas_Virgilio` |
| Badge **FC s/Salida** (Stocks) | `vista_fc_sin_salida`, `stocks_carga_rapida.fc_sin_salida` | **NO** | **`gv_cod_stock_de_entrega`** (artículo) + **`gv_empresa_de_entrega`** (empresa), en columnas separadas (v21.13) |

```js
// index.html, v12.39 — el comentario que lo dice todo:
function pkEmpresaArt(cod, np) { return /[0-9E]L$/.test(cod) ? "LK" : empresaDeNp(np); }
function pkStripL(cod)         { return cod.replace(/([0-9E])L$/, "$1"); }
function pkResolveArt(art, np) { return pkCodEmpresa(pkStripL(art), np, pkEmpresaArt(art, np)); }
//  "NO se usa para el código del PEDIDO que va a Entregas_Virgilio/factura
//   (ese se conserva crudo, ej. 438EL)."
```

⚠ **Por eso NO hay que "limpiar" la L de `PPP_Web_Base`.** Si se la saca, el código deja de matchear
`/[0-9E]L$/`, `pkEmpresaArt` cae en `empresaDeNp(np)` → como la NP es de Chef, **el picking manda al
operario a la góndola de Chef** y la factura sale con el artículo equivocado. El 18/09 se sacó y se
repuso dentro de la misma tanda de trabajo; queda escrito para que no se repita.

⚠ **Y la L tampoco se agrega a mano en Gestión.** La pone la página al armar el pedido
(`admin-supercot.js`, `addLSuffix = isChef`). Gestión la **respeta y la rutea**, no la genera.

⚠⚠ **Y todo lo que MUESTRA stock a partir de un código de FACTURA tiene que resolverlo primero**
(v21.13, Luis 22/09). `Entregas_Virgilio` guarda `026L` porque ése es el código de la factura; el
badge **FC s/Salida** lo agrupaba con `norm_cod()`, que **sólo saca ceros a la izquierda — no pela la
L**, así que el 026 salía partido en dos filas (026 = 10, **026L** = 1) y el front fabricaba una fila
fantasma sin empresa ni descripción. Eran **32 códigos**, todos del mismo pedido de Chef con
artículos de Loeke.

> ## **«438E LK» NO ES UN CÓDIGO.** Es el artículo `438E` **de la empresa `LK`**, y son **dos datos**.

**Luis, 22/09, textual:** *"Debería ser en todos lados «438E» de la empresa «LK» o de la empresa «CH»
como dato en una columna aparte que viaje con el código a todos lados."* Y el modelo correcto **ya es
el del libro de stock**: `Movimientos_Stock` guarda `cod_art = '438E'` + columna `empresa`, y
`GV_Lugar_Item` lo mismo — **0 filas con sufijo pegado en las dos**. El string concatenado vive en un
solo lugar, **8 filas de 367 de `stocks_carga_rapida`** (los 4 duales × 2 empresas), como **clave
heredada** de `vista_stock_procesada`; esa tabla **ya tiene los dos datos separados al lado**
(`cod_base` + `linea`). **Nada nuevo se escribe concatenado.**

Los dos datos salen de dos funciones, y no se vuelven a pegar:

| función | devuelve | ejemplo |
|---|---|---|
| **`gv_cod_stock_de_entrega(cod, np, emp)`** | el **artículo** | `026L` → `26` · `438EL` → `438E` |
| **`gv_empresa_de_entrega(cod, np, emp)`** | la **empresa** | `438EL` → `LK` · `438E` en NP de Chef → `CH` |

⚠ **La empresa de un código con L es LK: la da la L, NUNCA la NP.** En un código **no dual** la da el
**artículo** (`gv_empresa_de_articulo`), no el pedido — regla v19.26.

⚠ **En los duales, cruzar por el código solo cuenta doble o cuenta cero.** El universo de stock los
tiene desdoblados y el cruce es por **igualdad exacta**: con `438EL` y `438E` a secas los dos
quedaban en **0**, y el fallback `codBase` del front le daba las mismas cajas a las dos filas. El
cruce va por **`(cod_base, linea)`** y el front lee el número de **su propia fila**, no de un mapa.

**Al escribir una vista o una pantalla que cruce un código de `Entregas_Virgilio` / factura contra
stock o góndola: el artículo por `gv_cod_stock_de_entrega`, la empresa por `gv_empresa_de_entrega`,
en columnas separadas — nunca `norm_cod` a secas y nunca concatenados.** Lo sostienen
`tests/fcs-codigo-l.cjs` —que corre `pkResolveArt` de verdad y compara contra la base, así que avisa
si el front y el SQL se desfasan— y cuatro filas en `GV_Reglas_Centinela`.
`sql/gv_fc_sin_salida_codigo_l_v2113.sql`, §3.mj.

**Chequeo** (el operario tiene que ver el código pelado y la góndola LK):

```sql
-- el pedido con L …
select np_label, articulo from public."PPP_Web_Base" where empresa='chef' and articulo ~ '[0-9E]L$';
-- … y el picking sin L: ningún movimiento de stock puede terminar en L
select cod_art from public."Movimientos_Stock" where cod_art ~ '[0-9E]L$';   -- vacío = todo bien
```

## ⚠ REGLA: el CÓDIGO DE CLIENTE es por EMPRESA — nunca cruzar por código solo

**Thomas, 2026-09-16:** *"¿contemplaste que los códigos de clientes de LK y CH son diferentes?
Un cliente puede tener un código en LK y otro diferente en CH, y el mismo número de código puede
ser de dos clientes diferentes (uno de LK y otro de CH)."* Es la contracara operativa de la regla
de arriba (*"el cod cliente no significa nada, sólo el CUIT vale"*, v13.76), y hay que tenerla a
mano **cada vez que se escribe una consulta**, no sólo al pensar en identidad de clientes.

**Medido el 16/09 sobre las facturas parseadas** (`isis_lk.documentos` / `isis_ch.documentos`):

| | |
|---|---|
| códigos de cliente en facturas de **LK** | **1.057** |
| códigos de cliente en facturas de **Chef** | **396** |
| códigos que existen en **las dos** | **115** |
| …de esos, **clientes DISTINTOS** | **114** |

O sea: **cuando un código coincide entre las dos empresas, el 99 % de las veces son dos personas
distintas.** Cruzar por código sin empresa no es "un poco impreciso": está mal casi siempre que
matchea. Ejemplo del día: **4181 en LK es Mitre Hugo Alberto; en Chef ese código no existe.**

```sql
-- el barrido que lo mide (y que hay que repetir si se duda)
with lk as (select distinct regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod,
                   (array_agg(contraparte_nombre order by fecha desc))[1] nombre
              from isis_lk.documentos where familia='factura_venta' group by 1),
     ch as (select distinct regexp_replace(coalesce(contraparte_codigo,''),'^0+','') cod,
                   (array_agg(contraparte_nombre order by fecha desc))[1] nombre
              from isis_ch.documentos where familia='factura_venta' group by 1)
select count(*) comparten_codigo,
       count(*) filter (where upper(btrim(lk.nombre)) <> upper(btrim(ch.nombre))) son_otro_cliente
  from lk join ch using (cod);
```

**Qué hacer siempre:**
- La clave de un cliente es **`(empresa, cod)`**, nunca `cod` solo. Vale para `Facturacion_NP`,
  `PPP_Web_Programacion`, `Entregas_Virgilio`, `GV_Clientes_Direcciones`, `GV_Clientes_Nuevos`,
  `cobranzas_cliente_cadena` y cualquier tabla con `cod_cliente`.
- Las facturas viven en **dos esquemas separados** (`isis_lk` / `isis_ch`): buscar la factura de
  una NP **en el esquema de SU empresa**, no en los dos.
- La empresa de una NP sale del **prefijo** (`LK …` / `CH …`) o, en las de ISIS, de
  **`> 90000 = LK`** (la regla que usa `gv_ppp_prog_arbol`). No inventar otra: un
  `np ~ '^4\d{4}$'` acierta con las NP de Chef de ISIS pero **manda las `CH 0012` web a LK**.
  Lo que ya existe y es de fiar: `gv_empresa_de_np_texto(np)` y `gv_emp_de_np(np)`.
- Las funciones que ya lo hacen bien y sirven de molde: `gv_fac_rs_np` (cruza por
  `empresa + cod`) y `gv_vista_cruce_facturacion` (`d.empresa = b.empresa`).

⚠ **La excepción que rompe hasta esto: Tierra del Fuego.** Una NP de **LK** se factura en el
ISIS de **Chef**, con el **código de cliente de Chef** (regla v13.77, arriba). Si se busca la
factura en `isis_lk` con el código LK no aparece, y la NP queda como *"sin factura"* sin estarlo.
El mapeo `(lk, cod) → (chef, cod_isis)` está en **`GV_Cliente_Isis`** (9 filas al 16/09):
**antes de concluir que una NP de LK no se facturó, mirar ahí.**

## ⚠ REGLA (Luis, 2026-09-22, v21.15): pelar la L de LOS DOS LADOS es no matchear nunca

Tercera pieza del agujero de la v21.12. **`reporte_agentes_equivalencia_facturar()`** —el aviso de
Telegram *"al facturar cambíá el código"*, cron 14, 08:00 / 12:00 / 16:00 ART— no usaba
`vista_pedidos_equivalencia`: **rehacía el join por su cuenta contra `GV_PPP_Base_Pedidos`**, o sea
que los pedidos de la página no existían para él.

Y al taparlo apareció el error que duele, que estaba también en la vista:

> **`Equivalencias_Codigos` tiene dos `cod_pedido` que TERMINAN EN L** — `438EL` → `438E` y
> `439EL` → `439E`. Pelando la L del pedido, `438EL` se compara como `438E` contra un `cod_pedido`
> que es `438EL`: **no matchea nunca**. El pelado hacía invisibles justo a las dos equivalencias
> que existen para códigos con L.

Medido: **CH 0022 (438EL) y CH 0024 (439EL)**, las dos programadas y sin facturar, no salían en
ningún lado. Hoy se compara el código **crudo Y el pelado**: cualquiera que matchee, avisa. Sobrar
un aviso no cuesta nada (dice *"mirá el código al facturar"*); faltar uno cuesta una factura mal.

⚠ **Esto NO vale para `Equivalencias_Familia`** (`vista_pedidos_secundarios`): ahí `cod_secundario`
no tiene **ni una** fila terminada en L, así que pelar es lo correcto y se deja como está. La
diferencia no se adivina — se mide: `where upper(btrim(<col>)) ~ '[0-9E]L$'`.

⚠ **La consulta del aviso salió de la función y es una VISTA**
(`gv_equivalencia_facturar_pendiente`), para poder probarla sin mandar el Telegram: `tg_enqueue`
escribe en `telegram_outbox` y el cron 28 lo vacía **cada minuto**, así que llamar a la función
"para ver qué da" manda el mensaje de verdad. La prueba va dentro de un `do $$ … raise exception $$`
que aborta todo (verificado: la fila encolada desapareció al revertir).

**Chequeo:** `select * from public.gv_equivalencia_facturar_pendiente;` ·
`select * from public.gv_reglas_perdidas;` — vacía = todo bien.
`sql/gv_equivalencia_facturar_web_v2115.sql`.

## ⚠ REGLA (Luis, 2026-09-25, v22.64): «Ajustes manuales en ISIS» es SÓLO Cencosud y Tierra del Fuego

**Luis:** *"Es para pedidos de Cencosud y Tierra del Fuego eso nomas"*. Dorinka (Chef 2686) aparecía porque
factura 439EL y códigos que faltan en `precios_venta_chef` (439E, 809, 838E, 865ED). `gv_fac_ajustes_isis` ahora
filtra: NP de LK (con L = TdF) o cliente de Chef en `gv_ajustes_isis_clientes_chef()` (2444 + `GV_Cliente_Isis`
motivo `tierra_del_fuego`). La función es SECURITY DEFINER porque el panel lee con la clave anon y anon no ve
`GV_Cliente_Isis` (sin ella, los TdF de Chef desaparecían en silencio). `sql/gv_fac_ajustes_isis_sin_dorinka_v2264.sql`.

## ⚠ REGLA (2026-10-10, v29.38): 809E de Chef = SÓLO Corta Queso · 809E de Loeke = SÓLO Corta Pizza — y el corta pizza nuevo es 820E

- En todos lados el 809E CH se llama Corta Queso y el 809E LK, Corta Pizza. `artNombre` (index.html) e `_impNombre`
  (importacion.js) resuelven el nombre de un dual por empresa; el padrón (`vista_nombres_articulos`) tiene un solo nombre por
  código pelado y no sirve para los duales. `tests/pedimp-dual-nombre.cjs`.
- **La importación PI OL-10139 del corta pizza de LK llega como 820E** (Importados 175): el bache 86 (1.632 u, 18/12) se pasó
  del 809E LK al 820E. El 809E de Chef sigue con su pedido (7.200 u).
- ⚠ **No usar `Equivalencias_Familia` para 809E LK → 820E**: no distingue empresa y le pasaría al 820E la Est. Madre del corta queso.
- Consumos medidos el 10/10 (facturas ISIS, abr-sep): Chef 809E 840–2.316 u/mes · LK 809E 108–636 u/mes: no están cruzados.
- `sql/gv_820e_alta_v2938.sql`, `sql/gv_nombre_dual_v2937.sql` (el refresco de Stocks usa `gv_nombre_dual` desde la v29.43, con el sí de Thomas).
- **Las 336 cajas de AD05 (ingreso 23/07, 28 MC) son de CHEF** (confirmado 10/10): ajuste racks LK −336 / CH +336 en AD05
  (`client_id corr_809e_ad05_*`) y `GV_Lugar` AD05 → CH (backup `zz_backups."GV_Backup_Lugar_AD05_20261010"`). Retira lo del
  conteo del 17/09 («son de Loekemeyer») y el «AD05 pasó a LK» de la v19.33. Queda 809E LK = 5 cajas en góndola.
- **SÓLO en Importaciones el 809E LK se ve como 820E** (v29.41, *"ya mirá todo como 820, no como 809"*): la fila 809E LK
  se pliega dentro de la 820E (stock, Est. Madre, pedidos y en camino; chip «incluye 809E LK»; la proyección abre la del
  809E LK). El vínculo es la tabla `GV_Importados_EnCurso_Suma` (destino_cod/marca = el VIEJO, origen_cod = el NUEVO; el
  nombre quedó del primer intento: el ALTER de renombre se cuelga en el MCP). El 809E de Chef no se toca. **Cuando entren los
  pedidos del 820E se da de baja el 809E LK** (GV_Codigo_Baja no sirve: es por código y el 809E de Chef sigue).
  `tests/pedimp-encurso-suma.cjs`.

## ⚠ REGLA (Thomas, 2026-10-10, v29.44): el 119 pasa a SECUNDARIO del 119E — recién CUANDO LLEGA

- 119E (Corta queso Loke, Ownland, PI OL-10139: 1.872 u, llega 18/12) se dio de alta en Stocks en 0 y su pedido quedó en
  🚢 En curso. El 119 (góndola Ñ26, OC a Lucho) sigue como está hasta que llegue.
- **Familia diferida**: `GV_Familia_Al_Llegar` (secundario, principal). El cron **`gv-familia-al-llegar`** (`39 * * * *`,
  anti-solape) → `gv_familia_al_llegar_tick()`: cuando el principal tiene stock (> 0) o unidades recibidas, escribe la fila en
  `Equivalencias_Familia` y marca `aplicado_en`. Otro caso igual = un `insert`.
- **v29.45 (Luis, D10): al llegar, además la góndola del secundario pasa al principal** (`pasar_gondola`: Ñ26 → 119E, por
  `gv_lugar_item_guardar` / `_sacar`) **y la OC del secundario se apaga** (`apagar_oc`: `OC_Maximos` 119 `activo = false`; el 119E
  queda con fila activa). Todo queda en `aplicado_motivo`. `sql/gv_familia_al_llegar_v2945.sql`.
- Lectura: `select * from public.gv_familia_al_llegar_tick(true);` (qué haría). `sql/gv_familia_al_llegar_v2944.sql`.

## ⚠ REGLA (Luis, 2026-10-07, v27.74): 865ED NO EXISTE MÁS — es el 865E de 12 u

El 865E (antes caja de 24 u) pasó a ser el Rallador Plano A/I 3 Usos **de 12 u**, y el 865ED se unificó ahí: UxB,
OC, Importados, góndola L57 (56 cajas) y stock van por 865E; el 865ED queda inactivo y LK lo remapea a 865E
(`sales_item_remap`) para proyección y Est. Madre. Las 17 cajas viejas de 865E (24 u, 2025) no se tocaron. Las 47
cajas que fueron a etiquetar a Cervantes el 30/09 vuelven como 865E (se resuelve al recibirlas).
`sql/gv_865e_unificacion_v2774.sql`.

## ⚠ REGLA (Luis, 2026-10-09, v29.09): un CÓDIGO DADO DE BAJA no aparece en el front — la historia queda

**Luis:** *"no está en uso, no debería aparecer en el front en ningún lado. no hace falta limpiarlo de todas las bases porque tiene registros históricos"* (865ED, unificado en 865E el 07/10).

- La lista vive en **`GV_Codigo_Baja`** (cod, reemplazo). Dar de baja otro código = un `insert`, no un deploy.
- `gv_stock_cod_conocido` y `v_conocidos` de `refresh_stocks_carga_rapida` lo tratan como desconocido → `visible_en_stock = false` → no sale en Stocks ni en la Est. Madre (sin saldo ni pedidos). Centinelas v29.06.
- Trigger **`aa_gv_codigo_baja`** (BEFORE INSERT en `Movimientos_Stock`): un movimiento NUEVO a mano con ese código se graba con el reemplazo (la descripción lo dice). No toca el pipeline (picking/separado/facturado, legajo pipeline/sistema): reescribe historia por tanda.
- Stocks → Ajustar/Fijar avisa *«no se usa más: es el 865E»* (`gv_codigo_baja_de`) · Importados → «Modificar existente» no lo ofrece (`gv_codigos_baja`) · se sacó de `planimetria.js`.
- **No se borra nada**: movimientos, facturas, Importados/OC_Maximos/GV_Lugar_Item (inactivos) quedan como historia. Los marcadores de la base dicen `v29.06-baja` (llave, no cambiar).
- `sql/gv_codigo_baja_v2906.sql`, `tests/stk-ajuste-cod-inexistente.cjs`.

## 🗄 RETIRADO — sólo revisar si se pregunta por algo ANTIGUO que no está arriba

> Reglas, versiones y hallazgos que **ya no valen**. Se guardan como historia, no como instrucción.
> **No leer esta sección en el trabajo normal**: sólo cuando alguien pregunta por un comportamiento viejo
> y no aparece en las reglas vigentes de arriba. Nada de acá se vuelve a aplicar sin un pedido explícito.

- v13.7x: «Cencosud (Chef 2444) es el caso inverso: NP de Chef con artículos de Loeke SIN L». Retirado por la v21.09 y Tomás Gonzalez (02/10): Cencosud lleva L.

- «Cencosud: NP de Chef con artículos de Loeke SIN L». Retirado: desde feb/2026 ISIS Chef le factura con L (031L, 816EL) y el pedido nace con L (v21.09).
