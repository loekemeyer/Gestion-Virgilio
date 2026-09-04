# HANDOFF — Pipeline de Ventas (Gestión Virgilio reemplaza a Producción Virgilio)

> Documento de traspaso para retomar el trabajo en otra sesión. Estado al 2026-09-04.
> **Leé esto entero antes de tocar nada.** Hay reglas de negocio y decisiones abiertas.

## ⚠ ESTADO DE RAMAS — LEER PRIMERO

- **Esta rama:** `claude/pipeline-estructura-supabase-1haka4` (donde vive este handoff y mi
  build). Está basada en un **`main` VIEJO** (`afd7ebd`).
- **`main` YA TIENE el pipeline 3717 completo y MÁS AVANZADO que el mío** (llegó a **v12.74**).
  Mientras yo lo reconstruía en esta rama, otro trabajo en paralelo lo construyó de punta a
  punta en `main`. **`main` es la fuente de verdad, no esta rama.**
- Commits clave que están en `main` y NO en esta rama:
  `Idea 3717 de punta a punta` · `v12.59 PPP Web` · `v12.60 m³ validado` ·
  `v12.62 NP "LK 1343" (prefijo empresa + 4 dígitos)` · `v12.66 Chef entra a la PPP Web` ·
  `v12.69 los pedidos se ven EN la PPP` · `v12.71 end-to-end datos reales` ·
  `v12.72 barrio por último guión (295 NP sin zona)` · `v12.73 localidad del padrón` ·
  `v12.74 zona interior = la del expreso`.
- **NO mergear esta rama a `main`:** chocaría dos implementaciones distintas (mi NP de 9
  dígitos vs la real "LK 1343"; mi esquema `pipeline` aislado vs el productivo). Mi código
  es **redundante y quedó atrás**.
- **Para la otra sesión:** arrancá de `main` (v12.74). Este handoff sirve como **mapa de
  decisiones y reglas de negocio** (§4) y de la lógica de resolución de zona (§2), que se
  descubrieron acá y muchas ya están resueltas en `main`. Compará antes de reimplementar.

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
   tramos y balancear por m³** (ej. 20 líneas LK → 2×10, no 18+2). **PENDIENTE de implementar.**
2. **NP interna:** `<E> + order_id(6) + parte(2)`; E = `9` lk / `4` ch (empresa por 1er dígito).
3. **Códigos L en CH = artículos de LK** (`438EL` = agarrá `438E` de la góndola LK). Resolver
   por **equivalencia read-time** (pela la L, resolvé base) para m³/picking/stock. **NO
   reescribir el código en el back** (regla dura del usuario). **PENDIENTE en m³/routing.**
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
`30_schema.sql` · `40_aplicar_pedido.sql` · `50_zonas_sucursales.sql`.

⚠ **Están DESFASADOS de lo ejecutado en vivo:** los feeds (10/11) y el FDW (20) NO incluyen
todavía la columna `barrio`; falta un archivo para `barrio_zona` y `config`. **Reconciliar
los .sql con la base antes de commitear.** Passwords van como placeholder en el repo.

## 6. Pendientes / decisiones abiertas

1. **Villa Devoto (180 pedidos):** mapeado a `Zona 2 - CABA Centro` (según la lista canónica
   `V.Devoto→Zona 2`), pero geográficamente es Oeste (Zona 3). **Confirmar con el usuario.**
2. **Ventana de edición** de pedidos (item adds) — ver §4.5.
3. **Retira / Super / Expo** — cómo se programan (§4.6).
4. **Día de la tanda** — cómo se asigna sin fecha pactada ni calendario (§4.7).
5. **Construir `ppp_programar`** (agrupar zona-día + tope 1 m³) — próximo paso grande.
6. **`aplicar_pedido` v2:** split balanceado por m³ + equivalencia códigos L + escribir zona.
7. **Rotar los passwords** de `virgilio_reader` (LK y CH). Quedaron expuestos en el chat de
   la sesión de origen (NO se copian acá: este repo es PÚBLICO). Rol read-only sobre una
   vista, riesgo bajo, pero rotar antes de producción (ALTER ROLE en la fuente + ALTER USER
   MAPPING en Virgilio). El valor vigente vive solo en el `user mapping` del FDW de Virgilio.
8. **ZonasSucursales completa** (opcional): el volcado del Sheet se cortó en "Lanus"; el
   fallback por `zona_expreso` lo hace casi innecesario.
9. **Commit al repo:** el CLAUDE.md dice trabajar en `main`; la sesión asignó la rama
   `claude/pipeline-estructura-supabase-1haka4`. **Definir rama antes de pushear.**
10. **Puente pipeline→producción:** para probar picking/armado real hay que llevar `pipeline.*`
    a lo que lee la app (`public.PPP_*`) — eso ya toca producción (un NP de prueba se hace
    visible a operarios). Se dejó "desenchufado" a propósito.

## 7. Cómo continuar

- **Verificar el feed:** `select empresa, count(*) from public.vista_pedidos_web_feed group by 1;`
  (en Virgilio). Debe dar lk ~1242, ch ~116.
- **Cobertura de zona:** unir `f.barrio` con `pipeline.barrio_zona` vía `public._norm_barrio`.
- **Probar la pipeline en la sombra:** `select pipeline.aplicar_pedido('lk', 888);` (reproduce
  el pedido 888 = 3 tramos). Todo cae en `pipeline.ppp_base` / `pipeline.ppp_prog`, producción
  intacta (chequear: 0 NP de 9 dígitos en `public.PPP_Programacion_Diaria`).
- **Próximo:** actualizar `aplicar_pedido` (v2, §6.6) y escribir `ppp_programar` (§6.5),
  después de cerrar las decisiones §6.1-6.4.
