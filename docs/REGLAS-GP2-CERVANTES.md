# Reglas Gp2 Cervantes — Interacción Cervantes (GP2) ↔ Virgilio y estructura del repo (Cervantes, selector, admin)

> Movido de `CLAUDE.md` el 2026-10-13 (poda 3ra tanda, pedido de Luis) **sin cambiar una palabra**.
> **Leerlo ENTERO antes de tocar algo de este tema.** Las reglas siguen valiendo igual que cuando estaban en CLAUDE.md.

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
- **`/monitor/tv.html`** → **monitor liviano para la TV de pared** (v18.74): el mismo
  tablero, de SOLO LECTURA y sin nada clickeable, en **56 KB** contra los ~4,97 MB que
  pesa cargar el `index.html` entero (el monitor usa el 8,9 % de ese código, y el
  kiosko se recarga cada 7 min porque se queda sin RAM). **Es una segunda vista de los
  mismos datos**: si cambia una regla del tablero hay que tocar los dos lados — en el
  código de `tv.html` esos puntos están marcados con `≡ index.html`, y `tests/mon-tv.cjs`
  los verifica. `/monitor` sigue yendo al monitor grande. Detalle en `GUIA-PROYECTO.md`,
  sección "Monitor TV".
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
  tablet tomaba producción con el legajo del otro. Una sesión **de otro día** no se usa
  (se valida `day` contra hoy AR) y desde v1.9.2 **se borra ahí mismo**, sin esperar a que
  la limpie la raíz. Ojo: eso es la sesión de LOGIN; el **estado de trabajo** es otra cosa
  y no se toca — vive en `prod_state_Cervantes_v2_supa::<día>::<legajo>` y su guard diario
  retiene 14 días calendario (para no perder una matriz abierta el sábado).
- **Al tocar Cervantes**: subir `LOCAL_VERSION` (`cervantes/app.js`), `CACHE_VERSION`
  (`cervantes/sw.js`) y los `?v=` + el badge de `cervantes/index.html` **al mismo número**.
  Si se desalinean, el celular se queda con el JS viejo cacheado — pasó, y por eso los
  operarios corrieron 5 versiones atrás sin que nadie lo notara.

### Admin de Cervantes — dos pantallas, COPIADAS acá (`cervantes-admin/`)

> ⚠⚠ **v25.19 (Luis, 30/09, D9): GP2 YA NO ES COPIA — es LINK DIRECTO** a
> `https://loekemeyer.github.io/Gestion-Productiva-2.0/GP2_MODULOS.html` (GitHub Pages, v25.36 — antes apuntaba a Vercel) (`GP2_URL` / `abrirAdminCervantes`, otra pestaña).
> La copia se quedaba atrás (v1.137 contra v1.211) y se borró: en `cervantes-admin/gp2/` quedan sólo docs
> (`LEEME.md`, el CLAUDE.md renombrado, `CONOCIMIENTO_GP2.md`, `GP2_MAPA.md`, `agentes/`). Al ser otro sitio,
> **GP2 pide su propio login** (Google + su lista de mails) y no hereda la sesión de Gestión. Todo lo de abajo
> sobre la copia de GP2 queda como historia; el admin «entero» sigue siendo copia.

- **El supervisor que elige Cervantes en el selector de planta NO va a la pantalla de
  operario: va al admin** (`chooseCervantes` → `showCervAdmin`, v14.73). El operario sigue
  derecho a `./cervantes/`. La distinción es `__identity.type === "supervisor"`.
- **Los admin de Cervantes son DOS y están COPIADOS acá** (decisión del dueño, 2026-09-10:
  *"copia, no link… ya que esto es una integración"*): `cervantes-admin/entero/` (repo
  `GestionProductivaEntero`) y `cervantes-admin/gp2/` (repo `Gestion-Productiva-2.0`). La
  pantalla `#cervAdmin` muestra las dos tarjetas. **Todo Cervantes vive en este repo**: la
  app de operario en `cervantes/` y los dos admin acá.
- **De la copia se dejaron afuera** los archivos de repo, no de app: `.git`, `.claude`,
  `.vscode`, `.mcp.json`, `.planning`, `LOCKS.txt` y los `.bat`. **Y desde el 2026-09-12
  tampoco entra `db/A_Costos_VIGENTES.xlsx`**: es la planilla madre de costos, o sea datos, y
  este repo se sirve por GitHub Pages. Que el `.gitignore` del origen la deje pasar allá no
  significa que tenga que viajar acá.
- **Re-sincronizada el 2026-09-30 (v25.17, GP2 v1.211.0; antes la copia estaba en v1.137.0 — el 12/09, v16.32)**, con 92 diferencias acumuladas. Cómo se hace, para
  la próxima: copiar `gestion-productiva-2.0` entero salvo lo de arriba, **re-aplicar a mano los
  parches de la copia** (los de abajo) y **verificarlos uno por uno antes de commitear** — el
  del `signOut` es el que importa: si se pierde, un supervisor que no esté en la whitelist de
  GP2 queda echado de Gestión entera. El `CLAUDE.md` del origen se copia **renombrado**, con el
  banner de "esto es documentación" pegado adelante. Chequeo de que no quedó ninguno suelto:
  `find cervantes-admin -name CLAUDE.md` tiene que dar vacío.
- **Los `CLAUDE.md` de los dos admin SÍ están, pero RENOMBRADOS** (v14.75):
  `cervantes-admin/entero/claude-admin--GestionProductivaEntero.md` y
  `cervantes-admin/gp2/claude-admin--Gestion-Productiva-2.0.md`. Ahí está cómo opera cada
  admin (tablas madre vs derivadas, orden de normalización, "casa del vecino", convenciones,
  trampas conocidas) y no está repetido en ningún otro `.md`. **Nunca renombrarlos de vuelta
  a `CLAUDE.md`**: con ese nombre se cargan como instrucciones del proyecto y una sesión de
  Gestión Virgilio pasa a obedecer las reglas de otro repo. Cada uno abre con un banner que
  lo aclara. Las reglas que mandan acá son las de ESTE archivo.
- **Los 5 agentes de GP2** quedaron archivados en `cervantes-admin/gp2/agentes/` (fuera de
  `.claude/`, con su README): se conserva el trabajo si aquel repo se apaga, sin que una
  sesión de acá los cargue sola. Para usarlos hay que copiarlos a `.claude/agents/` a mano.
- **Parches propios de estas copias** (no revertirlos al re-sincronizar):
  1. **Ningún rechazo de whitelist hace `signOut()`** (`entero/login.html`, `gp2/login.html`).
     La sesión de Google es **compartida** con Gestión (mismo origin, mismo proyecto): cerrarla
     ahí echaba al supervisor de Gestión entera sólo por no estar en `usuarios_permitidos`
     (que hoy tiene **2 mails**: `loekemeyer.n8n@` admin y `loekemeyer.logistica@` envíos).
     Ahora sólo se limpia el `sessionStorage` de esa app.
  2. **`entero/Inicio/index.html`**: el botón "Cerrar sesión" pasó a **"← Volver a Gestión"**
     (`../../../`) — hacía `signOut` + borraba las claves `sb-*`, o sea te echaba de todo.
  3. **`gp2/GP2_MODULOS.html`**: link **"← Volver a Gestión"** en el header (`../../`).
  4. **La fecha de carga lleva el AÑO: `dd/mm/aa`, nunca `dd/mm`** (v20.54, pedido de Elías,
     2026-09-21). `getDiaMesHoy()` y `getFechaDiaMes()` de `Talleristas/Envios/EnviosTall.js` y
     `getDiaMesHoy()` + los dos `split("-")` de `Prov Serv/Envios/EnviosPS.js`, en las **dos**
     copias, escribían el día y el mes y **tiraban el año** — incluso cuando el operario elegía
     la fecha en el `<input type=date>`, que lo trae. Medido ese día: **154 filas de `Envios a
     Talleristas` y 41 de `Envios a PS` sin año**, todas de agosto y septiembre de 2026, o sea
     que la carga de hoy lo estaba perdiendo. Hoy no molesta porque el año se adivina; el 1.º de
     enero esas filas dejan de poder ubicarse (`StockFlejes/cajas.js` las fecha con
     `hoy.getFullYear()`). El formato elegido es el que ya tenían las otras **2.446** filas, y
     ningún lector se rompe: los parsers (`mmDe` / `ddDe` de `EnviosPS.js`, los `split('/')`)
     ya toleran `dd/mm`, `dd-mm`, `dd/mm/aa`, `dd/mm/aaaa` e ISO, y **no hay un solo filtro por
     igualdad** sobre `Dia-mes`. ⚠ Al tocar cualquier pantalla de carga, mirar que la fecha que
     se guarda tenga año. **`Entregas PS` escribe ISO (`arDateISO()`) y se dejó como está**:
     tiene el año, y cambiarla movería un formato que los lectores ya soportan a propósito.
  5. **`entero/Produccion/maestro.html` no tiene «📷 Cargar foto»** (v27.10, 05/10: *"no se usa, sacá lo de OCR"*).
     Era el OCR de la planilla de matricería por `leer-produccion-foto`, que quedó como tapón 410. No reponerlo al re-sincronizar.
- **`.nojekyll` en la raíz**: sin eso, Pages corre Jekyll y **no publica** lo que empieza con
  `_` — y las copias traen varios (`_backup_relevamiento_*`, `_export`, `_archivo`).
- El botón **🏭 Admin Cervantes (GP2)** del panel supervisor abre **esa misma pantalla**
  (`openAdminCervantes` → `showCervAdmin`): una sola puerta, no dos criterios.
- ⚠ **Ojo, deuda heredada**: cada admin trae adentro su propio `Produccion/RegistroApp/`, o
  sea que en el repo ahora hay **más de una copia** de la app de registro además de
  `cervantes/`. No se tocó; si algún día se unifica, es ahí donde hay que mirar.
- **No hace falta puente de sesión** (a diferencia de `/admin/` de LK, que necesita
  `lk_bridge_vjwt` porque es OTRO proyecto Supabase): GP2 usa el **mismo proyecto**
  `hrxfctzncixxqmpfhskv` y el **mismo origin**, con el `storageKey` default, así que la
  sesión de Google del supervisor ya se ve del otro lado y el login de GP2 entra solo
  (`getSession()` → `procesarSesion` → whitelist `GP2.get_role_for_email`).
- ⚠ **Hoy el login de GP2 está APAGADO**: `GP2_AUTH_ON = false` en su `auth-guard.js`
  (lo apagó el usuario el 2026-08-29: *"la página ya está privada y va a costar que
  accedan, por ahora prefiero que esté suelto"*). O sea que ese botón hoy entra **sin
  pedir nada**. Para volver a prenderlo hay que tocar el OTRO repo: `true` ahí y bumpear
  el `?v=` de `auth-guard.js` en sus HTML.

## 🔁 REGLA GENERAL (30/09): Cervantes (GP2) y Virgilio (GV) SE HABLAN — no es una excepción

[usuario, 30/09] *"establecé esta regla como general porque no es una eventualidad, suele pasar que haya
interacción entre Cervantes (GP2) y Virgilio"*. Toda mercadería o aviso que cruza de una planta a la otra sigue
el mismo molde (el mismo bloque está en el `CLAUDE.md` de `loekemeyer/Gestion-Productiva-2.0`):

| pieza | cómo |
|---|---|
| frontera | una tabla en el schema **`GP2`** (GP2 nunca lee `public`). GV escribe ahí con una `public.gv_*` SECURITY DEFINER: `GP2.ingreso_virgilio` (GV → GP2), `GP2.aceptado_virgilio`, y los espejos de solo lectura `virgilio_insumo_stock` (desde la v29.89 una **vista en vivo**) / `_ubicacion` / `virgilio_lugar` / `virgilio_insumo_categoria` |
| códigos | GV habla en código de ARTÍCULO (323ES), GP2 en COMPONENTE (GRJ31). El vínculo vive en **`GP2.insumo_equivalencia`** y **nunca se adivina** |
| confirmar | el que recibe dice **Sí / No** donde trabaja, en la tarjeta del componente. ⚠ **Hoy avisa sólo lo que RECIBE CERVANTES** (Luis, 02/10: *"lo que recibe Cervantes avisa"*): lo que GP2 manda a Virgilio (`enviar_a_virgilio`, tablet y botón «→ Virgilio») no pide Sí/No en GV |
| Sí | el MISMO camino que la carga manual (en GP2: `crear_recepcion_insumo` + control en kg pendiente) |
| No | cada lado toca SÓLO su fila; la reacción la hace un trigger del otro lado y se ve **donde se cargó** |

⚠ **01/10 (Luis, v25.42): se REVIRTIERON la v25.39 y la v25.41** junto con la v1.219.0/1.220.0 de GP2 (tablet Enviar/
Recibir → Virgilio, Fábrica → producir, Stock General en 3 cajas). Afuera: el bloque 4 de `gv_gp2_espejo_sync`
(`GP2.virgilio_articulo_stock`, borrada) y `gv_envio_cervantes_*` + «🏭 Cervantes mandó» en Recepción y Recibir
Insumos (`GP2.envio_virgilio`, borrada). **Queda sólo el aviso de importados** (GV → GP2 con Sí/No). El contenedor
de insumos de Virgilio en GP2 se rearma **desde cero y en blanco** cuando Luis lo defina: no reponer lo revertido.

### ⚠ ESPEJO DE ENTREGAS GV → GP2: lo que un tallerista entrega en Virgilio SUMA stock en GP2 (Luis, 05/10)

**Trigger `trg_virgilio_espejo_gp2`** (vive sobre `public."Entregas Tallerista Virgilio"`, llama a
`GP2.fn_entregas_virgilio_espejo`; **NO está en `db/` del repo GP2** — su estado sólo se ve en la base). Se
**re-prendió el 05/10 14:44** después de haber estado apagado desde el 18/09.

> **Cuando un tallerista o prov AT entrega algo en Virgilio, GP2 lo registra SOLO como recepción** (suma stock
> del artículo en GP2, `cajas × articulos_por_caja`, vía `recepcion_virgilio`). Resuelve la contraparte por
> nombre y el **artículo por código contra `GP2.articulo`** (exacto, si no sin ceros a la izquierda).

- **Es FORWARD-FACING: no hay backfill** (Luis, 05/10). Las ~99 entregas del 18/09–05/10 (7.981 cajas) cargadas con
  el trigger apagado **no se reprocesan** — ni siquiera quedaron en la cola, porque es el trigger el que encola. De acá
  para adelante.
- **Si el código no existe en `GP2.articulo` o la contraparte no resuelve, NO suma: queda en `GP2.virgilio_espejo_pend`**
  con el motivo (`articulo sin equivalente en GP2`, `contraparte sin resolver`, `cantidad en cero`, `error: …`). No se
  pierde: cruza cuando se da de alta el artículo en GP2.
- **Alta de un importado en GP2 con su receta**: se va haciendo **a medida que haga falta, por SQL en el back, no desde el
  front** (Luis, 05/10). Pendientes al 05/10 (sin fila): 323E, 838E, 438E, 439E, 584E, 727E, 865E, 55289. Hecho: 599E.
- **Mapeo componente ↔ artículo**: tabla **`GP2.insumo_equivalencia`** (`cod_virgilio → componente_id`), un
  insert por código. Es el vínculo del flujo de recepción de insumos importados; el espejo de entregas cruza por
  `GP2.articulo` directo.
- **Chequeo:** `select count(*), min(fecha), max(fecha) from "GP2".virgilio_espejo_pend;` — lo que todavía no cruzó, con
  su motivo. Vivo del trigger: `select tgenabled from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='Entregas Tallerista Virgilio' and t.tgname='trg_virgilio_espejo_gp2';` (`O` = vivo, `D` = apagado).

⚠ **El CONOCIMIENTO_GP2.md del repo GP2 queda por documentar aparte** (no se puede pushear a `loekemeyer/Gestion-Productiva-2.0` desde una sesión de este repo: acceso de solo lectura).

### v25.37: el «No» de Cervantes vuelve a poner el pedido EN VIAJE — chip «⛔ Denegado por Cervantes»

- GP2 contesta con `GP2.resolver_ingreso_virgilio(id, acepta, motivo)`: **Sí** = recepción de insumo normal
  (remito `Virgilio #<id>`); **No** = la fila pasa a `denegado`.
- Del lado de GV, **`gv_ingreso_virgilio_denegado`** (trigger BEFORE UPDATE OF estado sobre `GP2.ingreso_virgilio`,
  marcador `v25.31-cerv-no`) devuelve el bache a `en_curso` (resta las unidades), marca el destino en
  `GV_Imp_Recepcion_Destino` (`denegado_*`), anota el ajuste en `Importados_Mov_Stock` y recalcula con
  **`gv_importados_resync_calc`** (la cuenta de `gv_importados_resync` sin el guard de supervisor: el que dice No
  es un operario de GP2). Si falla, queda en `virgilio_revertido_error` y lo muestra
  `select * from public.gv_ingreso_cervantes_sin_revertir;` — vacía = todo bien.
- La pantalla lee `gv_imp_cervantes_denegados()` (sesión de supervisor, va en `_PED_IMP_RPC_ESCRITURA`) y pinta el
  chip en la fila del código, en 📦 Baches, en 📥 RECIBIR (con el motivo) y en 📜 Historial. Si la lectura falla,
  no hay chips y nada más cambia.
- ⚠ **Anular** una recepción con una parte denegada no vuelve a restar esas unidades (`gv_imp_recepcion_anular`).
- ⚠ Las funciones dicen **v25.31** (la etiqueta con que se aplicaron): la llave de idempotencia, no cambiarla.
- Centinelas en `GV_Reglas_Centinela` (4 filas). `sql/gv_ingreso_cervantes_denegado_v2537.sql`,
  `tests/imp-cervantes-denegado.cjs`. Del lado GP2: `db/migracion_ingreso_virgilio_resolver.sql`, CONOCIMIENTO §4hf.


## ⚠ LÓGICA DE NEGOCIO: por qué los catálogos de insumos NO se solapan del todo (Nazareno, 2026-10-14)

**Cervantes y Virgilio son dos PLANTAS del mismo grupo de empresas, no dos sistemas que deban
tener el mismo catálogo.** Antes de reportar un insumo "sin par" como un hueco a cerrar, aplicar
esta lógica (vale sobre todo para flejes, y por extensión para el resto de los insumos):

- **Cervantes es la FÁBRICA**: ahí se USAN los flejes (y demás insumos). Por eso el catálogo de
  Cervantes es el completo de lo que se consume en producción.
- **Virgilio ESTOQUEA lo que no entra en Cervantes**: cuando no entra todo el stock en la fábrica,
  el excedente se guarda en Virgilio. Virgilio es depósito, no fábrica.

Consecuencias al cruzar catálogos (no son errores, son lo esperado):

1. **Fleje/insumo que está en Cervantes y NO en Virgilio** → NORMAL. Cervantes lo usa y le entra
   todo en la fábrica; nunca hizo falta estoquearlo en Virgilio. **No es un link faltante.**
2. **Fleje/insumo que está en Virgilio (con saldo) y NO tiene par en Cervantes** → la causa más
   probable es que **es DISCONTINUO**: Cervantes ya no lo usa (lo sacó del catálogo o lo
   discontinuó), pero quedó stock físico guardado en Virgilio. **Antes de proponer darlo de alta
   en Cervantes, verificar si no es un discontinuado** (preguntar o mirar si el componente existía
   y se dio de baja). Dar de alta un discontinuado en la fábrica es volver a meter basura.

Por eso, al analizar el engranaje de insumos uno por uno: un "sin par" **no** se traduce
automáticamente en "falta vincular" ni en "falta dar de alta". Primero se clasifica: ¿Cervantes lo
usa (fábrica) o es excedente/descontinuado que sólo vive en Virgilio (depósito)?
