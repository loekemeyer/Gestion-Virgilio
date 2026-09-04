# HANDOFF — Pipeline de Ventas (Gestión Virgilio reemplaza a Producción Virgilio)

> Documento de traspaso. Escrito en la rama `claude/pipeline-estructura-supabase-1haka4`
> el 2026-09-04 y **traído a `main` ese mismo día, reconciliado con lo que main ya tenía**.
> **Leé esto entero antes de tocar nada.** Hay reglas de negocio y decisiones abiertas.

## ⚠ QUÉ ES ESTO Y QUÉ NO — LEER PRIMERO

Hubo **dos builds del mismo pipeline al mismo tiempo**, sin saber uno del otro:

| | build de `main` (**el productivo**) | build de la rama (parado) |
|---|---|---|
| Cómo lee LK/CH | en vivo, por el bridge de admin | FDW (`lk_feed` / `chef_feed`) |
| Dónde escribe | `public.PPP_Web_NP` + `public.PPP_*` | esquema aislado `pipeline` |
| N° de NP | `LK 1343` (prefijo + 4 dígitos) | 9 dígitos internos |
| SQL en el repo | `sql/pedidos_web_lk.sql`, `sql/ppp_web_programacion.sql` | `sql/gv_pipeline_*.sql` |
| Estado | **fuente de verdad, v12.74** | redundante, quedó atrás |

**`main` es la fuente de verdad.** El build de la rama **NO se mergeó como código** —
habría chocado dos implementaciones distintas. Lo que sí se trajo a `main` es:

1. **este documento** (el mapa de reglas de negocio §4 y de decisiones abiertas §6);
2. **los `sql/gv_pipeline_*.sql`**, porque sus objetos **están vivos en Supabase**
   (esquema `pipeline`, esquema `fuentes`, servers FDW `lk_feed`/`chef_feed`, vista
   `public.vista_pedidos_web_feed`, rol `virgilio_reader` en LK y en Chef) y estaban
   quedando sin SQL en el repo. Se reconciliaron con la base viva: se les agregó la
   columna `barrio` que faltaba (§5) y el archivo `35` del diccionario;
3. **el diccionario canónico de 113 barrios** → `sql/gv_pipeline_35_barrio_zona.sql`,
   y el merge propuesto contra el productivo en
   `sql/zonas_barrios_dic_canonico_20260904.sql` (**sin ejecutar**, ver §2).

Nada de eso escribe en `public.PPP_*`. Es seguro dejarlo quieto.

### Lo que ya está resuelto en `main` (no reimplementar)

`v12.59` PPP Web · `v12.60` m³ validado · `v12.62` NP "LK 1343" · `v12.66` Chef entra ·
`v12.69` los pedidos se ven EN la PPP · `v12.71` end-to-end con datos reales ·
`v12.72` el barrio se corta por el último guión · `v12.73` la localidad sale del padrón ·
`v12.74` la zona del interior es la del expreso.

En particular **§2 de este documento ya está implementado en `main`**: la zona se deriva
de `zona_expreso`. Lo único que quedó afuera es el diccionario — ver el recuadro de §2.

## 0. Objetivo

Gestión Virgilio (este repo, `loekemeyer/gestion-virgilio`) va a **reemplazar por completo**
a Producción Virgilio. Primer módulo en construcción: la **programación de pedidos web**
(idea 3717). El pedido web nace en las páginas de venta y hoy espera al mail de las 12:30 →
ISIS. La idea: Gestión Virgilio **levanta el pedido, lo parte, le pone NP interna, calcula
m³, resuelve zona, arma tandas y lo programa** — y ISIS pasa de ENTRADA a SALIDA (solo
devuelve el N° de NP al facturar).

**Regla de oro:** todo se construye en un **esquema aislado `pipeline`** (lado escritura
"desenchufado"). Las tablas PPP de producción NO se tocan. El único puente a producción es
de **solo lectura** (FDW a los feeds). Cuando esté probado, se "enchufa" apuntando la
escritura de `pipeline.*` a `public.PPP_*`.

## 1. Proyectos Supabase (SON 3, distintos)

| Rol | Proyecto | Org | Acceso |
|---|---|---|---|
| **Virgilio** (destino) | `hrxfctzncixxqmpfhskv` | azosplccoimzkdtbvzfi (Gestion Productiva) | MCP directo |
| **LK web** (fuente) | `kwkclwhmoygunqmlegrg` | azosplccoimzkdtbvzfi | MCP directo |
| **Chef** (fuente) | `nkhzocgdpwtgrmwleihr` | eczogcnncryxuaipplqx | MCP directo (se enchufó ampliando el conector a esa org) |

El repo `loekemeyer/paginach` (página CH) está clonado en `/home/user/loekemeyer/paginach`.
La app de este repo apunta al proyecto Virgilio (`supabase-config.js`).

## 2. El modelo de resolución de ZONA (la pieza clave que costó)

**La zona NO se guarda: se deriva.** Cadena verificada (cobertura CH 100%, LK 99%):

```
pedido → customer_delivery_addresses.zona_expreso   (= el BARRIO que carga el operador en la página)
       → pipeline.barrio_zona (BUSCARV, réplica de 'Resumen Prog'!AC:AD del Sheet)
       → zona ("Zona 1 - CABA Sur", … / Retira / Super / Expo)
```

- **`zona_expreso` guarda el BARRIO** (Soldati, Pompeya, Barracas, Retira…), NO la zona,
  pese al nombre de la columna. Igual en LK y en CH. Nace al cargar el cliente en la página.
- El diccionario barrio→zona lo pasó el usuario (lista canónica, 100 barrios + variantes).
  Está en `pipeline.barrio_zona` (clave `barrio_norm` vía `public._norm_barrio`).
- **NO usar el Sheet ni parsear el address** — fue un callejón sin salida (37-43%). El dato
  nativo de la página resuelve al 99%.
- Interior se maneja redirigiendo el barrio a la terminal del flete (Barracas→Zona1 /
  Avellaneda→Zona4); esa curación ya viene en el barrio de la página.

> **Estado en `main` (2026-09-04).** La cadena de arriba **ya está andando**: v12.73 sacó
> la localidad del padrón y v12.74 hizo mandar a `zona_expreso` sobre la localidad y sobre
> el parseo de la dirección. El front resuelve `zona_expreso → localidad → parsear` y cruza
> contra **`public."Zonas_Barrios"`** (87 filas, auto-aprendizaje por `trg_ppp_autozona`,
> alta manual por la RPC `zona_barrio_set`) — **no** contra `pipeline.barrio_zona`.
>
> ✅ **El diccionario se completó el 2026-09-04.** Faltaban 22 barrios de entrega reales
> con 51 pedidos, que sí estaban en la lista canónica de 113. Entraron **28 filas** y
> `Zonas_Barrios` pasó de **87 a 115**. Script, medición y lo que quedó afuera:
> `sql/zonas_barrios_dic_canonico_20260904.sql`; backup previo en
> `sql/backups/backup_zonas_barrios_20260904.sql`.
>
> INSERT-only a propósito: en 3 barrios la lista canónica está **peor** que la base y no se
> pisó nada — `burzaco` (la lista dice CABA Centro y es GBA Sur), `villa bosch` y `v.devoto`
> (§6.1, sigue abierto).
>
> **Cobertura: 1.346 de 1.358 pedidos (99,1%).** Los 12 restantes no son un problema de
> diccionario: son clientes sin `zona_expreso` cargado en el padrón de LK, así que el pedido
> no trae punto de entrega. Se arregla en el padrón.

## 3. Lo construido (en vivo, funcionando)

### En LK y en CH (fuentes)
- Vista-contrato **`public.v_virgilio_pedidos_feed`** (mismas columnas en las dos):
  `empresa, order_id, cod_cliente, cliente_nombre, created_at, fecha, hora, status,
  sucursal_entrega, condicion_pago, items(jsonb en orden), barrio`.
  `barrio` = `customer_delivery_addresses.zona_expreso` (match por customer_id+label, fallback slot).
- Rol read-only **`virgilio_reader`** (SELECT solo sobre la vista, nada de tablas crudas).

### En Virgilio (destino)
- FDW **`lk_feed`** y **`chef_feed`** → foreign tables **`fuentes.pedidos_lk`** /
  **`fuentes.pedidos_ch`** → vista unificada **`public.vista_pedidos_web_feed`** (lk + ch).
- Esquema aislado **`pipeline`** (REVOKE anon/authenticated), tablas:
  - `pedidos_web` (control: empresa, order_id, np_interna, …)
  - `ppp_base` (líneas espejo de PPP_Base_Pedidos: pedido, articulo, cajas, cliente, fecha)
  - `ppp_prog` (cabecera espejo de PPP_Programacion_Diaria: np, tanda, m3, cod, razon_social, direccion, barrio, zona, …)
  - `zonas_sucursales` (import del Sheet ZonasSucursales — **PARCIAL: solo A-Lanus, 406 filas**, el volcado se cortó; casi innecesaria porque el barrio sale de la página)
  - `barrio_zona` (diccionario barrio→zona, ~113 filas)
  - `calendario_zona` (⚠ **DESCARTAR**: el calendario día→zona NO existe en la realidad, fue un invento)
  - `config` (`tanda_m3_max = 1`)
- Función **`pipeline.aplicar_pedido(empresa, order_id)`**: parte (tope 18 lk / 15 ch en
  orden del payload), NP interna, m³ (Volumen_Articulos), tanda de prueba, escribe `pipeline.*`.
  **IDEMPOTENTE.** Probada: reproduce las NP reales de ISIS línea x línea y el m³ (dif <0.2%).
  ⚠ **Es v1** — todavía NO tiene: split balanceado por m³, equivalencia de códigos L, ni la zona.
- `Volumen_Articulos`: se cargaron 4 códigos faltantes (`574E,599E,505I` copiados de similar;
  `567` provisorio). Cobertura m³ del feed = 100%.

## 4. Reglas de negocio fijadas por el usuario

1. **Partición:** tope de líneas **18 LK / 15 CH**. En el régimen nuevo el Excel lo genera
   Virgilio → el orden es libre. Regla nueva pedida: dividir en **mín. `ceil(líneas/tope)`
   tramos y balancear por m³** (ej. 20 líneas LK → 2×10, no 18+2).
   ⚠ **SIGUE PENDIENTE en `main`.** Hoy `sql/pedidos_web_lk.sql` corta con
   `ceil(linea_rn / cap)`: bloques contiguos del tope, en el orden del carrito
   (reproduce exacto lo que hace la Edge Function del Excel). O sea 20 líneas LK
   salen **18 + 2**, no 10 + 10. Cambiarlo rompe la paridad con ISIS a propósito.
2. **NP interna:** `<E> + order_id(6) + parte(2)`; E = `9` lk / `4` ch (empresa por 1er dígito).
   ⚠ **SUPERADO.** `main` usa **`LK 1343` / `CH 1343`** — prefijo de empresa + 4 dígitos, de
   un contador propio (`ppp_web_np_asignar`). La identidad interna es `(order_id, np_idx)`.
   Ver `sql/ppp_web_programacion.sql`. La NP de 9 dígitos de esta rama no se usa.
3. **Códigos L en CH = artículos de LK** (`438EL` = agarrá `438E` de la góndola LK). Resolver
   por **equivalencia read-time** (pela la L, resolvé base) para m³/picking/stock. **NO
   reescribir el código en el back** (regla dura del usuario).
   ✅ **Resuelto en `main` para picking/armado/stock** (v12.37/v12.39): `pkStripL`,
   `pkEmpresaArt` y `pkResolveArt` en `index.html`.
   ✅ **Y en el m³ desde v12.75**, en el backend: la vista
   `public.vista_volumen_articulo_resuelto` (`sql/volumen_articulo_resuelto.sql`) emite cada
   código medido y su variante con L, **sólo cuando esa variante no tiene medida propia**;
   `pwebVolumenes()` la lee en lugar de la tabla cruda. Antes de esto, de los 12 códigos con
   L que traen los pedidos de Chef, 9 no tenían m³ y esas NP salían de menos. Resuelven 8
   (`097L`, `702EL`, `706L`, `798EL`, `824L`, `836L`, `840L`, `847L`); `727EL` no tiene
   medida en ningún lado y sigue sin m³, que es lo correcto.
   ⚠ **Queda un dato a revisar:** `438EL`, `439EL` y `809EL` tienen fila propia, y en dos no
   coincide con la del base — `439EL` mide 0,0561 y `439E` 0,0185, el triple. La vista no lo
   decide: el crudo manda siempre y el pelado sólo llena huecos. Habría que medir cuál está
   bien.
4. **Tanda:** agrupar **(empresa, zona, día)**. Tope **1 m³** para juntar pedidos chicos
   distintos. Un pedido con varias NPs → **todas sus NPs en la MISMA tanda** (mismo día),
   aunque supere 1 m³. Un pedido nunca se parte entre tandas.
5. **Editar pedido:** si agregan ítems a un pedido y supera un límite → **recomputar**
   (re-partir + re-empaquetar). aplicar_pedido ya es idempotente. **Falta la ventana de
   edición** (¿hasta cuándo? antes de tener tanda / antes del picking).
6. **Canales:** reparto local (zonas 1-7) por tanda de zona; **Retira** (zona 'Retira'),
   **Super** y **Expo** (interior) tienen lógica propia. **PENDIENTE definir cómo se programan.**
7. **NO hay calendario día→zona** en la realidad (verificado: 0 menciones de días). El día de
   entrega **no viene en el pedido** (no hay fecha pactada). **PENDIENTE: definir cómo se
   asigna el día de la tanda.**
8. Todo en **backend/código, nunca Sheets**. No modificar datos/códigos sin permiso explícito.

## 5. Archivos SQL en el repo (`sql/`)

`gv_pipeline_00_orden.sql` · `10_feed_ch.sql` · `11_feed_lk.sql` · `20_fdw_virgilio.sql` ·
`30_schema.sql` · **`35_barrio_zona.sql`** · `40_aplicar_pedido.sql`.

✅ **Reconciliados con la base viva el 2026-09-04** (estaban desfasados): los feeds (10/11)
y el FDW (20) ya llevan la columna `barrio`, y el `35` nuevo trae `barrio_zona` (113 filas)
y `config` (`tanda_m3_max = 1`), que no tenían archivo. Passwords van como placeholder.

`50_zonas_sucursales.sql` **no está en el repo** (`.gitignore`): lleva direcciones de
clientes y el repo es público. Igual quedó incompleto (cortado en "Lanus", 406 filas).

`pipeline.calendario_zona` sigue existiendo en la base y **hay que dropearla** — el
calendario día→zona fue un invento (§6.7). No se dropeó: es cambio de datos, va con permiso.

## 6. Pendientes / decisiones abiertas

1. **Villa Devoto (180 pedidos):** mapeado a `Zona 2 - CABA Centro` (según la lista canónica
   `V.Devoto→Zona 2`), pero geográficamente es Oeste (Zona 3). **Confirmar con el usuario.**
2. **Ventana de edición** de pedidos (item adds) — ver §4.5.
3. **Retira / Super / Expo** — cómo se programan (§4.6).
4. **Día de la tanda** — cómo se asigna sin fecha pactada ni calendario (§4.7).
5. **Construir `ppp_programar`** (agrupar zona-día + tope 1 m³) — próximo paso grande.
   (En `main` la tanda hoy la arma el supervisor desde la PPP Web, con el sugeridor de
   `pppSugerirTandas`; automatizarlo del todo sigue abierto.)
6. **`aplicar_pedido` v2:** split balanceado por m³ + equivalencia códigos L + escribir zona.
   Aplicado a `main`, lo único que queda vivo de esto es **el split balanceado (§4.1)**. La
   zona ya la escribe (v12.74) y el fallback de la L en el m³ se hizo en v12.75 (§4.3).
7. **Rotar los passwords** de `virgilio_reader` (LK y CH). Quedaron expuestos en el chat de
   la sesión de origen (NO se copian acá: este repo es PÚBLICO). Rol read-only sobre una
   vista, riesgo bajo, pero rotar antes de producción (ALTER ROLE en la fuente + ALTER USER
   MAPPING en Virgilio). El valor vigente vive solo en el `user mapping` del FDW de Virgilio.
8. **ZonasSucursales completa** (opcional): el volcado del Sheet se cortó en "Lanus"; el
   fallback por `zona_expreso` lo hace casi innecesario.
9. ~~**Commit al repo:** definir rama.~~ ✅ Resuelto: este documento y los `gv_pipeline_*.sql`
   viven en **`main`** desde el 2026-09-04. El código de la rama no se mergeó (§0).
10. **Puente pipeline→producción:** ya no hace falta — `main` escribe directo en
    `public.PPP_Web_NP` y la PPP Web se ve en la app. El esquema `pipeline` quedó
    **desenchufado y sin uso**.
11. 🆕 **Dar de baja lo que quedó huérfano en Supabase** (pide permiso, es cambio de datos):
    `pipeline.calendario_zona` (invento, §4.7) seguro; y decidir si se conservan el esquema
    `pipeline`, `fuentes` y los servers FDW `lk_feed`/`chef_feed` o se dropean. Hoy no los
    lee nadie: el pipeline productivo entra a LK por el bridge de admin, no por FDW.
12. ~~**Alta de los 22 barrios que faltan en `Zonas_Barrios`.**~~ ✅ Corrido el 2026-09-04
    (28 filas, 87 → 115). Ver §2.
13. 🆕 **Cargar `zona_expreso` en el padrón de LK** a los 12 clientes que no lo tienen —
    es lo único que queda entre el 99,1% y el 100%. Cuatro de ellos (Tigre, Adrogué,
    Berisso, "Caba") resuelven solos apenas se les cargue el barrio del punto de entrega.

## 7. Cómo continuar

- **Verificar el feed:** `select empresa, count(*) from public.vista_pedidos_web_feed group by 1;`
  (en Virgilio). Al 2026-09-04: lk 1242, ch 116 (1.358 en total).
- **Cobertura de zona (la que importa hoy):** cruzar `f.barrio` del feed contra
  **`public."Zonas_Barrios"`** —el diccionario productivo— vía `public._norm_barrio`. El
  paso 3 de `sql/zonas_barrios_dic_canonico_20260904.sql` tiene la consulta lista.
- **Probar la pipeline en la sombra** (sólo si se decide reactivarla, §6.11):
  `select pipeline.aplicar_pedido('lk', 888);` — todo cae en `pipeline.*`, producción intacta.
- **Próximo, sobre `main`:** cerrar §6.1 (Villa Devoto), correr el alta de barrios (§6.12),
  el fallback de la L en el m³ (§4.3), y después el split balanceado (§4.1).
