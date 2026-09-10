# CLAUDE.md — Producción Virgilio

## 🪨 Modo Caveman (SIEMPRE activo)

**Cada conversación abre con caveman activo por defecto.** Responder en modo **caveman**:
frases cortas, directas, mínimas palabras, sin relleno. Solo aplica al **chat** (no al
código, comentarios ni mensajes de commit).

- **`desactiva caveman`** = responder solo el **próximo mensaje** normal/completo, y después **volver solo** a caveman.
- **`caveman desactivacion total`** = apagar caveman por completo (queda desactivado hasta que se reactive).

---

App web (PWA, sin framework) para registrar producción de depósito (picking,
armado, carga de camión, recepción). La usan operarios desde el celular y
supervisores desde un monitor. Se sirve por GitHub Pages desde `main`.

## ⚠ Antes de responder preguntas sobre datos o funcionamiento

**Leé `GUIA-PROYECTO.md`** (en la raíz del repo). Es la guía viva del proyecto:
modelo de datos, códigos de acción, flujo, de dónde salen los m³, cómo se calculan
las horas, recetas de SQL y reglas de inconsistencia. Respondé **basado en eso, no
inventes**.

**Mantené `GUIA-PROYECTO.md` actualizada** cuando cambie el código o los datos
(nuevos códigos `opcion`, tablas, flujo, versión, etc.).

## ⚠ Regla del dueño (2026-09-07, v13.64): ISIS o web, da lo mismo — salvo en Facturación

*"Que el pedido sea de ISIS o cargado por la web no me interesa para absolutamente nada. Lo que me importa
es para el módulo de Facturación, después de eso no."* → **Ninguna pantalla fuera de Facturación separa,
etiqueta ni cuenta aparte lo de ISIS y lo web** (ni "camiones web / ISIS", ni "m³ web", ni Tipo "WEB"). Por
dentro la distinción sigue (NP web = número de pedido con prefijo, facturada = bajar el Excel de ISIS), pero
no se muestra. Al agregar una pantalla o una columna, mostrar todo junto.

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
`_facXlsArmar`). Los 10 clientes LK de TdF ya cruzan por CUIT. **Excepción: La Anónima (771) se vende por LK** (`gv_isis_override` en LK, por CUIT). **Cencosud (Chef 2444) es el caso inverso: NP de Chef con artículos de Loeke sin L** → entra al checklist de ajustes ISIS (`gv_fac_ajustes_isis` v2, v13.79). Ser cliente de las dos empresas, solo, no es problema; **el cod
cliente no significa nada, sólo el CUIT vale** (v13.76). La regla v13.75/76 ("cliente con FC en LK → no se programa",
`cliente_fc_lk`) fue un malentendido y está **apagada** (`doble_lk_dias = 0`); **también la de v13.72 ("mismo cliente por CUIT, mismo día en ISIS LK", `en_produccion_lk`; `doble_lk_mismo_dia = 0`, v13.82)**: *"ya expliqué que eso no corresponde"*. §3.az, §3.ba y §3.bb.

## ⚠ Regla del dueño (2026-09-07, v14.12): el agregado va en tanda nueva SÓLO si mezclaría ISIS con web

*"Solo va en tanda nueva si mezcla lo que es pedido isis y pedido web"* → **el corte es el ORIGEN, no
"¿ya se pickeó?"**. Agregado web + tanda **WEB** del mismo cliente y día, sin empezar → **se junta**.
Agregado web + tanda de **ISIS** → **siempre tanda nueva**, aunque nadie la haya tocado. El guard de
"sin empezar" se mantiene (sumarle algo a una tanda ya pickeada rompe el picking).

Vive en `gv_ppp_web_tanda_abierta_cliente` (sólo mira `PPP_Web_Programacion`; las tandas de ISIS **no**
son candidatas), que usa el bloque (a1) de `gv_ppp_web_armar_pendientes` en los crons 71 y 73.
**La v14.05 lo había leído al revés** y metía pedidos de la página adentro de tandas de ISIS; se corrigió
en la v14.12. Caso testigo: Osa (2533, mié 09/09) → `E09A` ISIS + `E09B` web, mismo camión, picking
separado. §3.ca/§3.cb de `docs/SUPABASE-GESTION-VIRGILIO.md` y `sql/gv_ppp_web_tanda_abierta_cliente_v1412.sql`.

## ⚠ Regla del dueño (2026-09-07, v14.00): en el CHAT, los nombres; en la APP, los códigos

*"Yo nunca entendí CCR y CCN. Para mí es control remitos, carga camión y recepción remitos, sólo esos
nombres entiendo"* → **hablarle SIEMPRE con los nombres**: `CR`/`CCR` = **Control Remitos** · `CC`/`CCN` =
**Carga Camión** · `RR`/`CRN` = **Recepción Remitos** · `TAP` = armado terminado · `TAL` = armado de la NP.

**Eso NO es un pedido de cambiar la pantalla.** Cuando se interpretó así (v13.97, revertida en la v14.00) la
corrección fue textual: ***"en la app no tenías que cambiar nada. CR, TAP, CC, RR para operarios está ok"***.
Los operarios los usan todos los días y son los de los botones. **No tocar los códigos en la app ni en la base.**

## ⚠ Regla del dueño (2026-09-07, v14.23): el SÚPER no se junta con clientes

*"Súper no se puede juntar con clientes. Ya tenías esa regla. Van separados."* → un camión que
lleva un súper (Coto, Carrefour, Chango Más, Krikos…) **no lleva ningún cliente común**, y al
revés. Nada de "aprovechar el viaje" porque quede cerca.

**El armado automático ya la respeta** (`gv_ppp_web_camion_del_dia` sólo reusa camiones con
`zona !~* 'super|retira|expo'`; el bloque 3b dice que un súper con zona numérica no es camión a
esa zona). Lo que NO la respetaba era el atajo manual: un `GV_PPP_Prog_Override` metido a mano
se saltea esa función. Pasó el 07/09 —se enganchó Luján al camión de Chango Más en Moreno
porque quedaba a 31,5 km— y se revirtió el mismo día.

**Chequeo:** `select * from public.gv_ppp_super_mezclado;` — vacía = todo bien. Mirarla después
de tocar tandas a mano. `sql/gv_ppp_super_mezclado_v1423.sql`.

## ⚠ PROTOCOLO OBLIGATORIO: Backend vs Front-end — preguntar ANTES de implementar

**Cuando alguien pide cambiar lógica** (normalización de códigos, cálculos,
filtros, agregaciones, reglas de negocio, etc.), **SIEMPRE preguntar si quiere
que se aplique en el backend (vista/función/RPC de Supabase) o en el front-end
antes de implementar.** No asumir. Muchas veces se piden cambios que deberían
ir al backend y terminan implementados en el front.

Aplica a **todos los chats** (nuevos y vigentes) sobre este repo.

## ⚠ PROTOCOLO OBLIGATORIO: Lógica de negocio SIEMPRE en el backend

**Conversiones, normalizaciones, validaciones y reglas de negocio que afectan
datos persistidos van en Supabase (triggers, funciones, vistas), NO en el
front-end.** El front puede duplicar la lógica como optimización UX (mostrar
el dato convertido antes de que el servidor responda), pero la fuente de
verdad es el backend. Si algo se implementa en el front, **siempre debe
existir el equivalente en el backend** (trigger/función) que garantice la
integridad aunque el front no lo haga.

Ejemplo concreto: la conversión MC↔Uni de insumos (v11.77) vive en el trigger
`normalizar_unidad_insumo` de `Movimientos_Stock`. El front también convierte
como optimización, pero el trigger es el que manda.

## ⚠⚠ PROTOCOLO OBLIGATORIO: la base es COMPARTIDA con Producción Virgilio

> **Actualización del dueño (2026-09-08): Producción Virgilio YA NO SE USA** (todo migró a
> Gestión). **Ya no se condiciona un cambio de Gestión por "no romper Producción".** Las reglas
> de abajo (agregar en vez de modificar, overrides, etc.) siguen siendo **buena disciplina** —
> reducen riesgo y mantienen el rollback limpio— pero **dejaron de ser un bloqueo**: si lo
> correcto es tocar un objeto compartido/de Producción, se hace. La contrapartida es
> **obligatoria**: todo cambio que toque un objeto compartido/de Producción se anota en
> **`docs/ROLLBACK-PRODUCCION.md`** con impacto y rollback exacto (ese archivo es la fuente
> única para desarmar lo que afecte a Producción). Los backups siguen siendo obligatorios.

**Gestión Virgilio y Producción Virgilio usan el MISMO proyecto Supabase
(`hrxfctzncixxqmpfhskv`) y la MISMA anon key.** Producción Virgilio (repo
`loekemeyer/Produccion-Virgilio`) fue la app que usaban los operarios (hasta el
2026-09-07). Cualquier cosa que se toque en `public.*` —una fila, una columna,
una función, un trigger, un cron, un grant— la ve esa app al instante.

**Regla del dueño (2026-09-04): sobre una tabla compartida se AGREGA, nunca se
MODIFICA lo que ya está.** Cuando no alcance con agregar, se crea una tabla nueva
que sea la **fuente canónica para Gestión**, y Producción sigue leyendo la suya.

| Querés… | |
|---|---|
| Agregar **filas** a una tabla compartida | ✅ `insert … on conflict do nothing`. Nunca `do update`. |
| Agregar una **columna** | ✅ nullable, sin `default` que reescriba, sin backfill, con prefijo `gv_`. |
| `update` / `delete` / `truncate` de filas existentes | ❌ → tabla `GV_*` de override + vista que la superpone (ej. `GV_PPP_Prog_Override` → `gv_ppp_programacion_diaria`, v13.50) |
| Cambiar o borrar una columna existente | ❌ → override |
| Objeto **nuevo** (tabla, vista, función) | ✅ con prefijo `PPP_Web_*`, `GV_*`, `gv_*`, `ppp_web_*` |
| `create or replace` de una función/vista que Producción usa | ❌ → crear `gv_<nombre>` nueva |
| Trigger sobre una tabla compartida | ❌ **nunca**: corre para Producción también |
| Dropear algo que no creamos nosotros | ❌ |

**Antes de tocar CUALQUIER objeto de `public.*`, grepear el repo de Producción**
(clonado en `/home/user/loekemeyer/produccion-virgilio`; si no está, traerlo con
`add_repo` + `git clone`):

```bash
grep -rn "NOMBRE_DEL_OBJETO" --include=*.js --include=*.html --include=*.sql \
  /home/user/loekemeyer/produccion-virgilio
```

Además: **toda vista nueva va con `security_invoker = true`** (sin eso corre como
`postgres` y saltea la RLS — el 2026-09-04 eso costó una filtración real), **RLS
prendida por defecto** en cada tabla nueva, y los **crons/Edge Functions llevan
prefijo** porque son globales al proyecto.

📒 **Todo cambio se anota en `docs/SUPABASE-GESTION-VIRGILIO.md` el mismo día**, con
el impacto medido (la consulta que lo prueba, no "no debería afectar") y el rollback.
Ese archivo —no la memoria— es lo que dice en qué estado está el pipeline al abrir
una sesión nueva. **Leerlo antes de tocar Supabase.**

📌 **Y qué FALTA para cerrar el pipeline está en `docs/PENDIENTES-PIPELINE-GESTION.md`**
(nota del dueño del 2026-09-04, cruzada con el estado real del repo). Al sábado 2026-09-05 el
pipeline está **cerrado de punta a punta**: pedido de la página → NP = nº de pedido → A
Programar / job 00:01 → picking, armado, carga (mismo código que Producción) → Facturación
(NP web: bajar el Excel ISIS = facturada) → control de remito = entregado, solo. Lo que
queda es del dueño (cron de Chef, El Martillo, operarios a Gestión, y **de Krikos: cargar
`KRIKOS_IMAP_PASS` en el Vault de LK + mergear la rama de LK a `main`**) o estacionado
(duales, módulo Chef, tracking a la página). **Krikos ya no está estacionado** (v14.17,
07/09): la Bandeja de OC de supermercados está construida y la fecha de entrega del súper ya
viaja de LK a `lk_pedidos_match`; falta sólo lo del dueño. **Leerlo al abrir una sesión nueva sobre el pipeline.**

## ⚠⚠⚠ CUANDO GESTIÓN TOMA CONTROL Y SE VUELVE LA VERSIÓN QUE USAMOS, SEGUIR CON LA NUMERACIÓN QUE DEJÓ VIRGILIO

**Estado desde el 2026-09-04 (viernes, a la noche): la numeración está PRENDIDA
(`numeracion_activa = 1`), el cron de tandas (jobid 71) activo, y las tandas con prefijo `GV-`
hasta el sábado 05/09, cuando el dueño lo hizo sacar (`tanda_prefijo = ''` → `E01A`).** Decisión del dueño: prender **sólo Virgilio**, sin tocar LK — el mail de
las 12:30 (`procesar-pedidos-web`) siguió andando hasta el **sábado 2026-09-05 a las 13:50 ART,
cuando el dueño lo hizo apagar** (crons 7 y 10 de LK en `active=false`, v12.94). Último envío a
ISIS: sábado 12:30, pedidos 1340..1349. **⚠ Cambio del sábado a la noche (v13.15): el dueño dijo
"el lunes van a empezar a usar GV, no más PV" → el mail del sábado se IGNORA y GV programa también
los 1340..1349** (`PPP_Web_Config.excluir_enviados_a_isis = 0`; no cargar ese mail en ISIS, quedarían
dobles). **Desde el lunes 2026-09-07 los operarios usan Gestión.** **⚠ v13.22 (sábado a la noche): ANTICIPACIÓN
MÍNIMA de 4 días hábiles** (`PPP_Web_Config.dias_anticipacion_min`, `gv_ppp_web_dia_minimo()`): el lunes
los operarios sólo arman lo que ISIS dejó (mar 8 / mié 9 / jue 10); lo que Gestión programe cae recién el
**viernes 11** en adelante (job 00:01 vía cron 71 con `{"fecha": …}`, intradía, "A Programar"). Poner en 0
para volver a hoy/mañana. §3.af. **El lunes 07/09 es Día del Metalúrgico: no hábil** (`GV_Dias_No_Habiles`,
§3.ag); primer día real con Gestión = martes 08. **Cupo diario = pickers típicos × 3 m³ (hoy 6), contando
ISIS + web** (`gv_ppp_web_cupo`, idea 6220, v13.23, §3.ah; `cupo_por_dotacion = 0` → 5 fijo). **v13.67 (lun 07/09 01:30): los crons 71 y 73 de Virgilio estuvieron apagados desde el 06/09 20:40 (otro chat) hasta que `ppp_web_armar_tandas` v7 hizo que la tanda ACUMULE entre corridas hasta 0,80 m³ (`sql/ppp_web_armar_tandas_v7_acumula.sql`, §3.av); están PRENDIDOS de nuevo.** **El cron de Chef quedó APAGADO el domingo 2026-09-06** (proyecto nkhzocgdpwtgrmwleihr, jobs 1
`procesar-pedidos-web` y 2 `retry-procesar-pedidos` en `active=false`, lo corrió el dueño; v13.31).
Último mail de Chef: sábado 05/09 12:30, pedido 217; el del viernes llevó el 216. **Ninguno de los dos
se carga en ISIS: 216 ya es E02A (vie 11) y 217 es E06A (lun 14).** Para volver a prenderlo:
`cron.alter_job(1, active := true)` y `(2, …)` en Chef. **Dueño 07/09: "no, dejalo apagado"** (Gestión programa Chef; si se prende, compras tipea dobles). **Cron 76 `gv-alerta-sin-eventos`** (lun–vie 10:30 ART, v13.72): día hábil sin eventos de operarios → Telegram.
Detalle, medición y rollback en `docs/SUPABASE-GESTION-VIRGILIO.md` §3.l y §3.p.

- **NP** → **v13.70 (2026-09-07): la NP web es un CONTADOR propio, un número por bloque, SIN sufijo** (dueño:
  *"el pedido tiene que ser único; no 1540-1, 1540-2; guardá el ID de la página pero que sea otro número; LK y 4
  dígitos"*): `LK 0001`, `LK 0002`… / `CH 0001`… (`gv_ppp_web_np_asignar` con lock, `PPP_Web_NP_Seed`, índice único
  `(empresa, np)`). El pedido de la página (`order_id`) queda guardado como referencia y se muestra "web LK 1350"
  hasta que se programa (ahí se asigna la NP). Un pedido de 4 bloques = 4 NP distintas. Deshace v12.92 (NP = nº de
  pedido con sufijo `-2`); `sql/gv_np_contador_v1370.sql`, §3.aw. Se
  programa por el job de las 00:01 para zona 1, 2 y 3 (`zonas_automaticas = '1,2,3'` desde v13.07)
  y a mano en "A Programar" para el resto.
  **Desde el 2026-09-05 además hay armado INTRADÍA** (idea 7317, cron jobid 73 cada 15 min
  lun–vie 07:00–18:45 ART, Edge Function v14 con `{"intradia": true}`): cuando lo pendiente de
  las zonas automáticas suma ≥ 0,80 m³ se arma ya, para hoy si es antes de las 12:00 y hay cupo, si no
  para el próximo hábil con cupo (`gv_ppp_web_proximo_dia_entrega`). §3.x de la doc de Supabase.
  **v13.47 (domingo 06/09, dueño: *"mandá directo a Programación si ya está, no más en A Programar"*):
  cada corrida programa TODO lo que tiene día previsible** — zonas automáticas en cascada de días con
  cupo, zonas manuales (4/5/6/7) al día en que ya hay camión a la zona (`gv_ppp_web_armar_pendientes`,
  §3.ao); el intradía corre todos los días 06:00–20:45 y el umbral está en 0,001. En A Programar quedan
  sólo Retira, Súper, sin zona y sin camión previsto. **v13.69: A Programar = pedidos | días; se arrastra el pedido DIRECTO al día, sin botones de tanda LK/Chef** (la planilla v13.61 se borró: al dueño no le gustó; la columna de tandas sin fecha sólo aparece si quedó alguna vieja). Soltar un pedido en un día arma la tanda con código automático y la programa (`aprGenerarTanda`; se descarta si falla: **ninguna tanda queda sin fecha**). **La PPP entra entera en una pantalla** (`pppFitPantalla`, zoom automático, sin scroll interno). Tandas numeradas como Producción (E01A, E02A…). **v13.60: camión = LETRA+NN y se REUSA por día y etiqueta** (Capital / GBA Sur / GBA Oeste / GBA Norte): una tanda nueva entra al camión que ya va ese día, aunque sea de ISIS (E01F, D68G); camión nuevo sólo si no hay. `sql/gv_ppp_web_camion_del_dia.sql`, §3.at. Ese día además se corrió la semana un día hábil (lun 7 feriado, nada armado; súper quedan) — backup `sql/backups/reprogramacion_20260906_pre_v1360.sql`.
  **Y las tandas se arman por CERCANÍA REAL** (v13.07, §3.y): sectores + vecinos en `GV_Sectores`,
  `GV_Barrios_Sector`, `GV_Sectores_Vecinos`, `GV_Barrios_Pares` (`sql/gv_sectores.sql`); Núñez
  nunca con Lugano, Barracas sí con Constitución o Avellaneda. Interruptor
  `PPP_Web_Config.sectores_activos` (0 = regla vieja por grupo de zona). Probar sin escribir:
  `gv_ppp_web_armar_simular(...)`.
  Regla del dueño: *"cuando Gestión tome control, va a asignarle la numeración
  nuestra a los pedidos que estén pendientes y a los que vayan cayendo"*. **Pendiente =
  pedido de la página con fecha ≥ `gestion_desde` (2026-09-03, piso) que Producción/ISIS no
  tenga** (v13.15). Con `excluir_enviados_a_isis = 1` además se excluye lo que salió por el mail
  (`enviado_a_compras`; era la regla de convivencia, v12.94); desde el sábado 05/09 a la noche
  está en 0 porque el lunes nadie usa Producción. La regla vive en UNA RPC de Virgilio, `gv_pedidos_web_excluidos`, que
  llaman el job y "A Programar"; los feeds de LK son crudos. Motivos: `enviado_a_isis`,
  `anterior_al_cambio`, `en_produccion`. **Bloques**: de a 18 (LK) / 15 (Chef) SEGUIDOS en el
  orden del carrito, igual que ISIS (v12.94; antes serpentina por m³).
  `pwebNumerar()` —la que numeraba todo al abrir una pantalla— quedó inalcanzable desde v12.82.
- **Tandas** → **codificación histórica `LETRA+NN+LETRA`** desde el sábado 2026-09-05 (dueño:
  *"sacá el prefijo GV-"*; `tanda_prefijo = ''`). `ppp_web_proxima_letra()` retoma desde la
  última letra de Producción (D71A) → la primera tanda de Gestión es **`E01A`**. Hasta ese día
  el prefijo era `GV-` para no pisarse con Producción; para volver: `valor_texto = 'GV-'`.
- **Canilla del espejo de ISIS: ABIERTA de nuevo desde el domingo 2026-09-06 (v13.51).** Gestión lee las
  vistas **`gv_ppp_programacion_diaria` / `gv_ppp_base_pedidos` / `gv_ppp_entregados_meta`**
  (`sql/gv_espejo_corte.sql`), que con `PPP_Web_Config.espejo_np_corte_lk/_chef = null` devuelven todo lo
  que ISIS numere (ISIS sigue cargando pedidos propios, ej. 98704 Salvetti D60G). Lo que NO debe verse
  (una NP de ISIS que duplica un pedido web ya programado por Gestión) se oculta **fila por fila** con
  `GV_PPP_Prog_Override.oculto = true` (`sql/gv_ppp_prog_override.sql`); las tres vistas y
  `gv_pedidos_web_excluidos` la saltean. Al 06/09 hay 10 ocultas: 98696–98703 y 44620/44621, el mail del
  sábado que se cargó en ISIS igual. La misma tabla sirve para **pisar tanda/fecha** de una NP de ISIS sin
  tocar la tabla compartida (44619 Chango Mas → E07A, v13.50). Estuvo cerrada del 05/09 al 06/09 (v12.90,
  corte 98694/44619); para cerrarla otra vez: `update public."PPP_Web_Config" set valor = 98704 where clave =
  'espejo_np_corte_lk'` (y 44621 en `_chef`). Detalle §3.m, §3.ap y §3.aq de `docs/SUPABASE-GESTION-VIRGILIO.md`.

**Para apagarlo (mismo día, todo reversible):**

```sql
-- en VIRGILIO (hrxfctzncixxqmpfhskv)
update public."PPP_Web_Config" set valor = 0 where clave = 'numeracion_activa';
select cron.alter_job(71, active := false);
```

**Hecho el sábado 2026-09-05: las tandas siguen la codificación histórica** (`tanda_prefijo = ''`;
`ppp_web_proxima_letra()` retomó desde la última letra que dejó Producción, D71A → `E01A`).
Para volver al prefijo de convivencia:

```sql
update public."PPP_Web_Config" set valor_texto = 'GV-' where clave = 'tanda_prefijo';
```

**La NP web es el número de pedido de la página** (v12.92): `LK 1350`, `LK 1350-2` (bloque 2),
`CH 0217`. Sin choque con Producción, cuyas NP son de 5 dígitos desde 44361 y sin prefijo. La
etiqueta la arma **`gv_ppp_web_np_label(empresa, np, np_idx)`** en el backend — prefijo +
espacio + 4 dígitos + `-bloque` si el bloque es > 1; el front (`pwebNpLabel`) y la Edge
Function (`npLabel`) la duplican sólo como optimización de UX. Historia del 2026-09-05: se
pasó de 5 a 4 dígitos (v12.91) y de contador propio a número de pedido (v12.92), las dos
veces antes de numerar el primero.

Con el prefijo vacío, `ppp_web_armar_tandas` vuelve sola a la codificación histórica
`LETRA+NN+LETRA` y `ppp_web_proxima_letra()` **retoma desde la última letra que dejó
Virgilio** (mira las dos tablas). No hay que tocar código ni redeployar nada.

Detalle y pruebas: `docs/SUPABASE-GESTION-VIRGILIO.md` §3.e y §3.f, `sql/ppp_web_tandas.sql`
y `sql/gv_tandas_diarias.sql`.

## ⚠ PROTOCOLO OBLIGATORIO: Backups antes de tocar datos en Supabase

**SIEMPRE que edites/alters/truncates/deletes en tablas de Supabase:**

1. **Haz un backup ANTES** de cualquier cambio:
   ```sql
   -- Exportar completa la tabla como SQL restore-ready
   SELECT * FROM table_name;
   -- Copiar resultado → archivo SQL con CREATE + INSERTs
   ```
2. **Guarda el backup** como `backup_table_YYYYMMDD_hhmmss.sql` en un lugar seguro (comentario/notas).
3. **Ejecuta tu cambio** (ALTER, TRUNCATE, DELETE, INSERT).
4. **Si algo falla o se rompe:** Restore inmediato ejecutando el SQL guardado.

**Ejemplo:**
```sql
-- BACKUP (ejecutar primero, guardar resultado)
SELECT 'INSERT INTO Capacidad_Sector (empresa, sector, cod, cajas_max) VALUES (' ||
  quote_literal(empresa) || ',' || quote_literal(sector) || ',' || 
  quote_literal(cod) || ',' || quote_literal(cajas_max) || ');'
FROM "Capacidad_Sector"
WHERE empresa IS NOT NULL;

-- Aquí va tu cambio (DESPUÉS de guardar el backup)
ALTER TABLE Capacidad_Sector ADD COLUMN nueva_col TEXT;

-- Si falla: restore ejecutando los INSERTs guardados
```

**Historial de incidentes:** 2026-08-07 — TRUNCATE accidental de Capacidad_Sector (730 registros perdidos). Lección aprendida → este protocolo existe.

## ⚠ PROTOCOLO OBLIGATORIO: NUNCA modificar datos sin permiso explícito

**Ante cualquier consulta sobre datos corruptos, errores, o inconsistencias en Supabase:**

1. **SOLO reportá el problema** — qué está mal, dónde, cuál es el valor esperado.
2. **NO modificar nada** en Supabase sin permiso directo y explícito del usuario.
3. **Máximo:** Preguntar "¿Quieres que corrija esto?" y esperar respuesta.

**Incidente 2026-08-26:** Corregí picking data (55215: 20833 → 208.33) sin consultar. Usuario pidió rollback. Regla clara desde ahora: **NUNCA asumir que hay que arreglar datos. Reportá, preguntá si se desea, ejecutá si confirma.**

## Quick-ref

- **Datos**: Supabase, proyecto `Control Partes Talleristas`, id
  `hrxfctzncixxqmpfhskv`. Consultar con la herramienta MCP `execute_sql`
  (`project_id = hrxfctzncixxqmpfhskv`).
- **Tabla central**: `Registros_Produccion_Virgilio` (log de eventos; `opcion` =
  código de acción, `texto` = código de tanda/pedido, `ts_inicio` no nulo = cierre).
- **m³ SÍ están en Supabase** (desde v5.33): `PPP_Programacion_Diaria.m3`,
  `PPP_Entregados_Meta.m3` (por NP) y la vista `vista_tanda_m3` — se calculan por
  SQL desde el sandbox. El **origen upstream** sigue siendo el Google Sheet
  "PPP Pedidos Entregados 2026" (col `Mt3`, NO col H ni "Mt3 FC"), espejado en UNA
  vía: `PPP_Entregados_Meta` (np,cod,rs,tanda,m3,fecha_entrega) vía función Postgres
  `sync_ppp_entregados_meta()` por cron (ver `sql/`). La tabla `PPP_Pedidos_Entregados`
  (espejo duplicado vía Apps Script) se **borró en v10.25** — no citarla.
- **Zona horaria**: `America/Argentina/Buenos_Aires`, UTC-3 fijo.
- **Versión**: `APP_VERSION` en `index.html` y `SW_VERSION` en `sw.js`.
- Legajos `0` y `1` (Pruebas) son test/basura: excluir de reportes.

## Estructura: dos apps en un repo (Virgilio + Cervantes + selector)

Este repo junta **las dos plantas** (reemplaza al viejo repo `App-Produccion`, que se
borró). Layout:

- **Raíz** → app **Virgilio** (sin cambios; la usa también la app de Play Store/TWA).
- **`/cervantes/`** → app **Cervantes** (desde 2026-09-10 **el fuente vive acá**; el repo
  `Registro-Produccion-2.0` quedó congelado — ver más abajo).
- **`/selector/`** → pantalla **"¿Dónde vas a trabajar hoy?"** que linkea a ambas:
  Virgilio `../` y Cervantes `../cervantes/`. Recuerda la última planta usada
  (`localStorage` `appprod_ultima_planta`, marca "Última vez"), **no redirige solo**.
- Botón **"← Cambiar planta"** en la pantalla inicial de cada app → va al `selector/`.
- `selector/sw.js` y `cervantes/sw.js` no cachean (mismo patrón que Virgilio). Las dos
  apps conviven sin pisarse: tablas Supabase distintas (`Registros_Produccion_Virgilio`
  vs `Registros Produccion Cervantes`), IndexedDB y claves `localStorage` con prefijos
  distintos. Cervantes usa rutas relativas y SW con scope `/cervantes/`.
- **Entrada por defecto = Virgilio (raíz)**, no el selector (para no romper la URL
  actual ni la app de Play Store). Si se quisiera el selector como entrada, mover el
  selector a la raíz y Virgilio a `/virgilio/` (revisar TWA).
- ✅ **`/cervantes/` YA NO es una copia: es el fuente** (decisión del dueño, 2026-09-10).
  La integración se hizo **para que los operarios de Registro Producción pasen a Gestión
  Virgilio**, así que el código de Cervantes **se mantiene acá**, en `cervantes/`. El repo
  `Registro-Produccion-2.0` quedó **congelado** en `68eec03` (app **v1.9.0**): no se toca,
  no se re-sincroniza desde ahí, y el dueño **lo va a borrar** cuando termine la mudanza.
  Su URL se deja andando mientras tanto **a propósito** — sin cartel ni redirect.
  Nada se pierde al mudarse: es el **mismo origin** de GitHub Pages, así que la cola de
  eventos pendientes (IndexedDB `registro-prod` + localStorage) y la sesión son las mismas
  en las dos URLs.
- **Login de Cervantes = el global de la raíz** (gate en el `<head>` de `cervantes/index.html`,
  v1.9.0). Con sesión (Google autorizada, o sesión por legajo del día en `vir_legajo_auth`)
  **no se vuelve a pedir el legajo**: lo precarga, esconde el input y saluda por nombre. Los
  supervisores de la lista tipean el legajo. Sin sesión: bajo `/cervantes/` vuelve a `../`;
  en la URL suelta cae a la pantalla de legajo (el gate detecta dónde corre).
  **Un operario puede trabajar en las dos plantas** (regla del dueño, 2026-09-10: *"se tiene
  que poder, porque pueden ir entre Cervantes y Virgilio"*) → Cervantes **NO** filtra por
  `Empleados.Sede`; un legajo de sede V entra igual. Por eso el saludo lleva al lado
  **"¿No sos vos? Cambiar operario"** (v1.9.1): en un equipo compartido borra la sesión del
  anterior y devuelve el campo de legajo, que si no quedaba escondido y el que agarraba la
  tablet tomaba producción con el legajo del otro.
- **Al tocar Cervantes**: subir `LOCAL_VERSION` (`cervantes/app.js`), `CACHE_VERSION`
  (`cervantes/sw.js`) y los `?v=` + el badge de `cervantes/index.html` **al mismo número**.
  Si se desalinean, el celular se queda con el JS viejo cacheado — pasó, y por eso los
  operarios corrieron 5 versiones atrás sin que nadie lo notara.

## Panel Web LK bajo `/admin/`

Desde v9.11 el repo hospeda una **copia del panel admin de PaginaLK** bajo
`/admin/`. Se accede desde el panel supervisor de Virgilio con el botón grande
**🌐 Panel Web LK** (fila principal, 7 columnas). El botón chequea supervisor y
navega a `admin/admin.html`. Login: **código OTP de 6 dígitos al mail** vía la
Edge Function `admin-login-otp` (verify_jwt=false) que manda el código con
Resend directo (`onboarding@resend.dev` como sender — el SMTP nativo del
proyecto LK apunta a `@loekemeyer.com` sin verificar en Resend y rechazaría).
Al verificar setea un password temporal aleatorio en el user y el front hace
`signInWithPassword` para quedar con sesión.

### Decisión de arquitectura: coexistencia, NO migración

- El admin apunta al proyecto Supabase **LK** (`kwkclwhmoygunqmlegrg`) —
  distinto del de Virgilio (`hrxfctzncixxqmpfhskv`).
- Son **dos proyectos Supabase separados a propósito**: producción y comercial
  son dominios distintos con dueños de datos distintos (ISIS/ERP produce
  `sales_lines`; Virgilio produce `Registros_Produccion_Virgilio`).
- **No migrar tablas ni RPCs de LK a Virgilio.** La copia del admin son 31k
  líneas con 60 RPCs, 40+ tablas, 4 Edge Fns, caches y crons propios; moverlo
  serían semanas de trabajo sin ganar función que hoy no exista.
- Cuando desde Virgilio haga falta un dato del admin (BCRA, deuda, historia de
  un cliente titular de una NP), agregar un cruce puntual vía `postgres_fdw`
  (mismo patrón que ya usa Virgilio contra LK para PPP, o LK contra Chef para
  el padrón). Un cruce por vez, on-demand.

### La copia bajo `/admin/` es un espejo, no un fork

- Cambios que hagan falta al admin **deben originarse en el repo `PaginaLK`**
  y después re-copiarse acá. Mismo patrón que `/cervantes/`.
- Archivos copiados: `admin.html`, `admin.js`, `admin-supercot.js`,
  `admin-osa.js`, `admin-excel-krikos.js`, `analisis-venta-cliente.js`,
  `analisis-cobranzas.html/.js/.css`, `carga-pedidos.html`, `historial.html/.js`,
  `sugerencias.html/.js`, `excel-parser-smart.js`, `argentina-map-data.js`,
  `argentina-provinces.json`, `version.js`, `css/admin.css`, `css/productos.css`,
  `osa/`, `img/favicon.jpg`, `img/no-image.jpg`.
- **Ajustes propios de la copia** (no revertir al re-sincronizar): (a) redirects
  `location.href = "/mayorista"` en admin.js → `"../"` (index Virgilio),
  (b) botón sidebar "Volver a Mayorista" → "Volver a Producción" con `href="../"`,
  (c) `<meta name="robots" content="noindex,nofollow" />` en los HTML del admin
  para que ni buscadores ni la revisión del TWA lo indexen, (d) handler de
  login OTP `lkSendOtp`/`lkVerifyOtp` al final de admin.js que llama a la
  Edge Function `admin-login-otp`, (e) form de OTP dentro del `#loadingScreen`
  de admin.html, (f) redirects `/mayorista` → `../` en `carga-pedidos.html`
  (3 lugares), `historial.html`, `historial.js`, `sugerencias.html`,
  `sugerencias.js`, `analisis-venta-cliente.js` (2 lugares) — el original
  apunta a `mayorista.html` del sitio LK que no existe en Virgilio,
  (g) `historial.html` usa `img/favicon.jpg` (no `.png`, no existe),
  (h) **entrada directa sin OTP desde Virgilio** (v12.35): `admin.js` trae
  `lkTryBridge()` y `checkAuth()` lo llama antes de mostrar el login; canjea el
  `access_token` de la sesión Virgilio (dejado en `sessionStorage` como
  `lk_bridge_vjwt` por `openPanelWebLK()` de Virgilio, mismo origen) por la
  acción `bridge` de la Edge Fn `admin-login-otp`. Si al re-sincronizar se pisa
  alguno, buscar por `LK_ADMIN_EMAIL`, `LK_OTP_FN_URL`, `_lkOtpFn`, `lkTryBridge`,
  `lk_bridge_vjwt`, `lkLoginBox`, o `grep -r "/mayorista"` (no debe haber ninguno).

### Convenciones operativas

- El SW de Virgilio **no cachea** (`self.addEventListener("fetch", () => {})`
  es no-op), así que no colisiona con `/admin/`.
- El TWA de Play Store apunta a la raíz de Virgilio; el admin está dentro del
  `scope`, por eso lleva `robots noindex,nofollow`. No usarlo nunca como `start_url`.
- Los HTML del admin llevan hardcodeado un `?v=23176` heredado del repo LK
  (cache-busting). **No hay hook automático que lo bumpee** desde Virgilio. Si
  se toca un `.js` o `.css` del admin y se necesita invalidar cache, se
  hace a mano incrementando ese número — o el user hace `Ctrl+F5` (que es lo
  habitual).
- La anon key de LK vive en `admin/admin.js` (además de en `sw.js` y `index.html`
  del propio proyecto LK). Al rotar la anon key de LK, actualizarla también acá.

### Edge Function `admin-login-otp` (proyecto Supabase LK)

- Código fuente: `admin/supabase/admin-login-otp/index.ts`.
- Deployada manualmente desde el Dashboard de Supabase LK (verify_jwt=off).
- Reusa la tabla `admin_otp_codes` y los secrets `RESEND_API_KEY` / `RESEND_FROM`
  del vault, que ya usa la Edge Fn `admin-otp` (2FA del admin PPP).
- Destinatario **hardcodeado** a `loekemeyer.n8n@gmail.com`. El user está creado
  a mano en `auth.users` del proyecto LK y vinculado en `public.admins`.
- Si se cambia el destinatario o se agrega otro admin, editar `RECIPIENT_EMAIL`
  en la función Y re-deployar; crear el nuevo user en LK y agregarlo a `admins`.
- **Sensible: 73 chars rompen bcrypt.** El password temporal usa
  `crypto.randomUUID()` (36 chars). No concatenar dos UUIDs — pasa de 72 y falla.
- **NO usar `listUsers` para resolver el recipient.** LK tiene >1200 usuarios
  (clientes del sitio); el admin quedaba fuera de la primera página de 200 → 500
  en OTP y bridge. La función resuelve el `user_id` con la RPC
  `get_admin_login_user_id()` (SECURITY DEFINER, solo `service_role`; SQL en
  `admin/supabase/admin-login-otp/get_admin_login_user_id.sql`).
- **Acción `bridge` (v12.35):** entrada directa sin OTP desde Producción
  Virgilio. Recibe el `access_token` de la sesión del supervisor de Virgilio
  (`vjwt`), lo valida server-side contra el auth de Virgilio
  (`hrxfctzncixxqmpfhskv`, anon key hardcodeada en la función) y **sólo si el
  mail del token == `RECIPIENT_EMAIL`** (mismo dueño, no amplía acceso a nadie)
  devuelve el mismo password temporal que `verify`. Gate 100% en backend: el
  front no puede falsear identidad. Si mañana se quiere que otro supervisor
  entre, ampliar el chequeo de `vemail` en la función (y crear su user en LK).

## Agentes + código de 4 dígitos (Telegram)

Los agentes ya **NO corren automáticos** (el loop cada 2 h y el curador diario
fueron eliminados el 2026-08-10 para bajar consumo de tokens). Los subagentes
siguen definidos en `.claude/agents/` y se invocan **a mano** cuando hace falta:
`mejoras-virgilio`, `revisor-logica`, `auditor-consistencia`, `auditor-supabase`,
`guardian-stock`, `guardian-tests`, `revisor-render`, `keeper-guia`,
`curador-telegram`. Detalle en `docs/AGENTES-DIARIOS.md`.

Cuando se invoca un agente, cada idea nueva entra a `agente_propuestas`
(`estado='pendiente'`). Si se implementa y verifica (`node --check` + smoke
headless), pasa a `estado='lista'` en su rama **`idea/<código>`**. **Nunca** se
toca `main` desde el agente.

Cada propuesta tiene un **código de 4 dígitos** único.

### ⚠ Reglas para CUALQUIER chat sobre este repo

**Comando `:`** — si el usuario escribe un mensaje que es (o empieza con) `:`,
mostrale **todas las ideas creadas** como **checklist, de a 5** (paginá de 5 en 5),
para que marque cuáles confirma. Traelas así:

```sql
select codigo, estado, agente, impacto, titulo, rama
from public.agente_propuestas
where estado in ('pendiente','lista') order by creado_en desc;
```

Mostralas como `[ ] 4837 · [logica·alto] Título (rama idea/4837)`. El usuario
tilda las que quiere → tratá cada tildada como "idea aceptada" (regla de abajo).

**Idea escrita por el usuario** — cuando el usuario escriba una idea/mejora/pedido
en el chat (aunque no dé ningún número), **registrala para que no se pierda**:

1. `select public.nuevo_codigo_propuesta();` para el código.
2. `insert into public.agente_propuestas (codigo, agente, titulo, detalle, estado)
   values ('<cod>','usuario','<título corto>','<lo que pidió, textual>','pendiente');`
3. Agregá una línea ARRIBA en `docs/IDEAS-USUARIO.md`:
   `- [ ] **<cod>** (AAAA-MM-DD) — <idea> — _pendiente_`, y commiteá/pusheá a `main`.
4. Confirmale al usuario: "Anotada como **<cod>**" (así puede activarla después por número).

Las ideas del usuario tienen **prioridad**: quedan `pendientes` en la tabla hasta
que el usuario las active por número o las descarte.

**Idea aceptada (por número o tildada en el checklist)** — cuando el usuario diga
un **código de 4 dígitos** (`4837`, "hacé el 4837", "acepto 4837") o tilde ideas
en el checklist, por cada código aceptado **mergealo a `main` directamente**:

1. `select codigo, titulo, estado, rama from public.agente_propuestas where codigo='4837';`
2. Si `estado='lista'` y tiene `rama`: `git fetch origin && git checkout main &&
   git pull origin main && git merge --no-ff origin/idea/4837 && git push origin main`.
   Si hay conflicto por drift de main, resolvé o rebasá la rama sobre main y reintentá.
3. Si `estado='pendiente'` (todavía sin rama): desarrollala vos ahora en `idea/4837`,
   verificá (`node --check` + smoke headless), y mergeala a main igual.
4. Marcá `update public.agente_propuestas set estado='hecha', actualizado_en=now()
   where codigo='4837';`. Si el usuario la rechaza → `estado='descartada'`.
   Si es idea del usuario (`agente='usuario'`), además actualizá su línea en
   `docs/IDEAS-USUARIO.md` (`[x]` si hecha, `~~tachada~~` si descartada) y commiteá a `main`.

El merge a `main` es **directo, sin mostrar diff** (así lo pidió el usuario), salvo
que en el momento pida verlo.

## Git

- **Trabajar SIEMPRE directo en `main`**: commitear y pushear ahí sin preguntar.
  **NUNCA crear ni usar ramas** (ni feature branches, ni ramas de Claude).
  Todo va a `main` directo. Si la plataforma crea una rama automáticamente,
  mergear a `main` de inmediato y trabajar desde ahí.
- Estilo de commits: `vX.YZ: descripción` cuando hay bump de versión.
- **Desde el 2026-09-05: TODO cambio lleva bump** de `APP_VERSION` (index.html) y `SW_VERSION`
  (sw.js), también los de backend/Supabase/Edge Functions. Pedido del dueño: *"empezá a bumpear
  las modificaciones así voy chequeando"* — mira el badge de versión para saber qué llegó.
