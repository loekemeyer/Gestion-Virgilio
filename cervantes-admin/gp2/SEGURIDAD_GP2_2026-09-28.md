# Auditoría de seguridad GP2 — 2026-09-28

Alcance: repo `Gestion-Productiva-2.0` (árbol + historial completo de git) y proyecto Supabase
`hrxfctzncixxqmpfhskv` (schema `GP2`, sus Edge Functions y el Storage). Solo lectura: no se cambió
nada. Ningún secreto se copia en este archivo.

## Resumen

| # | Hallazgo | Severidad | Estado |
|---|---|---|---|
| 1 | 62 RPCs de GP2 que **escriben** se pueden llamar con la clave pública, **sin login** | **CRÍTICO** | **corregido** (fase A + fase B, 2026-09-28) |
| 2 | `gp2_leer_factura`: la puerta y el tope dependían del gateway (latente, no explotable hoy) | MEDIO | **corregido** (v17) |
| 3 | Las 62 tablas de GP2 se **leen** enteras con la clave pública (precios, costos, empleados) | ALTO | abierto |
| 4 | Bucket `remitos` es **público** | MEDIO | abierto |
| 5 | Clave `anon` legacy (JWT, vence 2036) en el historial de git | BAJO | conocido (plan en CLAUDE.md) |
| 6 | Clave de OpenAI que estuvo pegada en `leer-factura` (programa viejo) | MEDIO | función ya tapada; **falta confirmar que la clave se revocó en OpenAI** |
| — | Árbol de trabajo: sin secretos (solo la `sb_publishable_`, que es pública por diseño) | OK | — |
| — | GP2: 62/62 tablas con RLS, ninguna política abre escritura a anon, 0 funciones SECURITY DEFINER sin `search_path`, 0 SQL dinámico | OK | — |

## 1. Escritura anónima por RPC — CRÍTICO

**Qué pasa.** La app se loguea con Google, pero el login vive **solo en el navegador**
(`auth-guard.js` + `sessionStorage`). Después, todas las llamadas a la base salen con la clave
publicable (`GP2_SB()`, sin sesión), o sea como rol `anon`. La base **no distingue** a un usuario
logueado de un desconocido que copió la clave del HTML de cualquier pantalla (está en
`supabase-config.js`, que se sirve a cualquiera, incluida `login.html`).

**Medido:** en `GP2` hay 152 funciones `SECURITY DEFINER`; 119 las ejecuta `anon`; **62 escriben**
(insert/update/delete) y **ninguna de las 62** mira quién llama (`auth.uid`, `auth.jwt`, email,
rol). Entre ellas:

- Stock: `registrar_movimientos`, `relevamiento_aplicar`, `fabricar_stock`, `traslado_virgilio`,
  `cargar_recepcion*`, `crear_envio_*`, `crear_entrega_*`, `controlar_*`, `anular_recepcion`.
- Maestros: `abm_articulo_upsert`, `abm_articulo_baja`, `abm_bom_guardar`, `alta_proveedor_*`,
  `fleje_detalle_upsert`, `asignar_*`, `marcar_estado_compra`.
- Personas: `empleado_guardar`, `empleado_activar`.
- Compras / producción: `crear_oc`, `oc_marcar`, `registrar_produccion`, `anular_produccion`,
  `tablet_registrar`.
- Borran filas: `abm_articulo_baja`, `abm_bom_guardar`, `anular_recepcion`, `asignar_pintor_parte`,
  `pesar_pallet`, `relevamiento_descartar_si_vacio`, `relevamiento_eliminar`.

Lista completa (62): abm_articulo_baja, abm_articulo_upsert, abm_bom_guardar, ajustar_rollos,
alerta_recepcion_marcar, alta_proveedor_insumo, alta_proveedor_servicio, anular_evento_prod,
anular_produccion, anular_recepcion, asignar_pintor_activo, asignar_pintor_parte,
asignar_proveedor_parte, cargar_compra_mp, cargar_recepcion, cargar_recepcion_charcas,
cargar_recepcion_eclipse, cerrar_rollo, controlar_entrega, controlar_recepcion_cajas,
controlar_recepcion_kg, crear_devolucion_tallerista, crear_entrega_prov_at, crear_entrega_ps,
crear_envio_prov_at, crear_envio_ps, crear_envio_tallerista, crear_oc, crear_preaviso,
descontrolar_recepcion, empleado_activar, empleado_guardar, enviar_material_inyector,
fabricar_stock, factura_alias_guardar, factura_lectura_permitida, fleje_detalle_upsert,
guardar_control_cartones, marcar_estado_compra, marcar_faltante, marcar_revisado, oc_marcar,
pesar_pallet, preaviso_marcar, recibir_oc_virgilio, registrar_evento_prod, registrar_movimientos,
registrar_produccion, relevamiento_abrir, relevamiento_aplicar, relevamiento_cerrar,
relevamiento_decidir, relevamiento_descartar_si_vacio, relevamiento_eliminar, relevamiento_guardar,
resolver_faltante, ruta_confirmar, ruta_reportar, ruta_resolver, tablet_registrar, tomar_rollo,
traslado_virgilio.

**Impacto:** cualquiera con la URL de la app puede mover stock, dar de baja artículos, cambiar
recetas, crear OC o tocar empleados, sin dejar rastro de quién fue.

**Arreglo propuesto (decide el dueño, es un cambio de arquitectura):**
1. Que las pantallas manden el JWT de la sesión de Google (el login ya lo tiene; hoy se descarta
   con "sin sesión persistida") y revocar `EXECUTE` a `anon` en las 62 → solo `authenticated`.
2. Dentro de cada RPC (o en un helper común) validar que el email del JWT está en la whitelist
   (`get_role_for_email`). Con eso la tablet de operarios necesita su propio camino (usuario de
   servicio o PIN validado en la base), porque no tiene login de Google.
3. Mientras tanto, lo mínimo: `revoke execute ... from anon` en las 7 que **borran** y en
   `empleado_*`, si ninguna pantalla sin login las usa.

### Plan del punto 1 (2026-09-28) — medido antes de decidir

**El login está APAGADO desde el 2026-08-29** (`auth-guard.js`: `GP2_AUTH_ON = false`, pedido del
usuario: "la página ya está privada… prefiero que esté suelta"), y 30 pantallas GP2 ni cargan
`auth-guard.js`. Sin login, la base **no puede** distinguir la app de un extraño con la clave.
"Privada" (Vercel) protege el HTML, no la base: la clave también viaja en las tablets y en la
macro de Excel `MACRO_ENTREGAS_SUPABASE.bas`.

**No hay atajo por "revocar lo que nadie usa":** de las 62, solo 3 no tienen llamador en este repo
(`fabricar_stock`, `recibir_oc_virgilio`, `traslado_virgilio`), y las dos de Virgilio pueden
usarse desde Gestión Virgilio / n8n. `track_functions` está en `none`, así que la base no cuenta
llamadas para confirmarlo.

**Fases:**
1. **Oficina:** prender el login y que `GP2_SB()` mande la sesión de Google (hoy va "sin sesión").
   En la base, un helper `GP2._autorizado()` que exige un email de la whitelist en el JWT; las RPCs
   de oficina lo llaman primero, y se les revoca `EXECUTE` a `anon` (quedan para `authenticated`).
   Lectura: las políticas `USING (true)` pasan a `authenticated`.
2. **Tablet de operarios** (sin Google): usa `registro_operarios_bundle`, `registrar_evento_prod`,
   `anular_evento_prod`, `tomar_rollo`, `cerrar_rollo`, `registrar_produccion`, `movimientos_bundle`.
   Propuesta: **token por dispositivo** (una clave larga por tablet, guardada hasheada en GP2 y
   revocable), que esas RPCs validan. Solo esas quedan para `anon`, y sin token no escriben.
3. **Otros llamadores:** la macro `.bas` y Gestión Virgilio / n8n pasan a una clave de servidor
   (`sb_secret_`, nunca en un archivo que se reparte) o al token de dispositivo.
4. Recién con 1-3 andando: revocar `anon` en todo lo demás y pasar `remitos` a privado.

**Decidido (2026-09-28):** (a) login prendido; (b) la tablet tiene login de Google → no hace
falta token por dispositivo; (c) n8n no escribe; la macro solo lee `public`.

**Fase A — HECHA:** login prendido, `GP2_SB()` manda la sesión y la renueva, el guard ya no
desloguea al vencer el token de 1 h, vuelve a la pantalla de origen (`?next=` seguro), y las 31
pantallas sin guard lo tienen. La base todavía acepta `anon`.
**Fase B — HECHA (2026-09-28)** (el dueño: "no se está utilizando actualmente", así que no hizo
falta esperar a los logs). Migración `seguridad_fase_b_rpcs_escritura_solo_usuarios_habilitados`:
- `"GP2"._autorizado()` / `_exigir_autorizado()`: pasa un usuario `authenticated` cuyo email está
  en `public.usuarios_permitidos` (vía `GP2.get_role_for_email`, la misma whitelist del login), o
  `service_role`, o SQL sin pedido de PostgREST (dueño, cron). Cualquier cuenta de Google puede
  loguearse en Supabase: por eso no alcanza con el rol, hace falta la whitelist.
- Las 62 llaman a `_exigir_autorizado()` al empezar y se les sacó `EXECUTE` a `PUBLIC`/`anon`.
- Medido: en SQL, extraño logueado → no, anon → no, admin → sí, envíos (email en mayúsculas) → sí,
  service_role → sí; en vivo con la clave pública, `factura_lectura_permitida`, `marcar_revisado`,
  `relevamiento_eliminar` y `registrar_movimientos` → **401 permission denied** (el contador de
  lecturas ni se movió); las lecturas siguen en 200 (eso es el punto 3).
- `gp2_leer_factura` v18 reenvía el JWT de la sesión y `LecturaFacturas_GP2.html` lo manda; sin
  sesión → 401.
- Invariante nuevo `AI_` en `db/verificar.sql` (hoy 0).

**Secuela (2026-09-29, v1.207.1):** si falla el refresh del login (`refresh_token_not_found`),
supabase-js descarta la sesion y la pantalla seguia **como anon**: leia bien y al grabar daba
`permission denied for function tablet_registrar` (Tablet, recepcion Charcas). Ahora `GP2_SB()`
escucha `SIGNED_OUT` y vuelve al login (`GP2_IR_AL_LOGIN` de `auth-guard.js`), y el guard solo
acepta el token `sb-hrxfctzncixxqmpfhskv-auth-token` (en `loekemeyer.github.io` conviven otras
apps con su propio `sb-*`). Cubierto en `test_login_flow.js` (8 y 9).

**OJO — whitelist:** hoy hay **2 cuentas habilitadas** (una `admin`, una `envios`). Toda tablet o
persona que tenga que ESCRIBIR necesita estar en `public.usuarios_permitidos`; la cuenta `envios`
además solo ve las pantallas de su lista en `auth-guard.js` (la tablet de operarios no está).

## 2. `gp2_leer_factura`: puerta y tope — MEDIO (latente) → CORREGIDO en v17

**Lo que decía el código v16:** la puerta aceptaba cualquier texto que empezara con
`sb_publishable_`, y si la consulta del tope fallaba el código seguía de largo y llamaba a la IA.
Leído solo, eso permitía llamadas pagas sin tope con una clave inventada.

**Lo que midió la prueba en vivo (corrige el diagnóstico de arriba):** el gateway de Supabase ya
rechaza con 401 `Invalid API key` cualquier `sb_publishable_…` inventada, venga en `apikey` o en
`Authorization`, **antes** de llegar a la función; y un texto que no empiece así lo frenaba la
propia puerta de v16. O sea: **no era explotable hoy**. Era latente: la función no se protegía
sola, dependía de un comportamiento del gateway que nadie controla desde acá.

**v17 (desplegada y versionada en `supabase/functions/gp2_leer_factura/index.ts`):**
1. La clave la valida la base: el tope se consulta con la clave del llamador y PostgREST solo
   contesta 200 a una clave real. No se escribe la publicable en la función.
2. Tope obligatorio (fail-closed): si no se puede verificar, no se llama a la IA (503).
3. Tope de tamaño: más de ~15 MB → 413.

Pruebas en vivo, sin gastar: clave inventada `sb_publishable_…` → 401 (gateway); texto
cualquiera en `Authorization` → **401 "Clave del proyecto invalida" (lo corta v17)**; sin clave
→ 401; clave real sin archivo → 400; archivo de 20 MB → 413. No se probó una lectura real para no
gastar.

## 3. Lectura anónima de todo GP2 — ALTO

Las 62 tablas tienen RLS, pero con política `SELECT ... USING (true)` para todos. Con la clave
pública se lee todo, incluidas: `precio_proveedor`, `precio_tallerista`, `precio_servicio_pieza`,
`planilla_fila`/`planilla_snapshot` (la planilla de costos), `proveedor_*`, `empleado`,
`factura_alias`, `factura_lectura`. Mismo origen que el punto 1: sin JWT la base no puede filtrar.
Se arregla con el mismo cambio (políticas para `authenticated` + whitelist).

## 4. Bucket `remitos` público — MEDIO

`storage.buckets.remitos` tiene `public = true`: cualquier archivo se baja con su URL, sin clave.
Si los nombres son predecibles, se pueden recorrer. Pasar a privado y servir con URLs firmadas.

## 5. Clave `anon` legacy en el historial — BAJO

Una sola en todo el historial: JWT `role=anon` del proyecto, vence en 2036. Tiene el mismo poder
que la publicable (o sea, el del punto 1), así que no suma riesgo nuevo, pero **sigue viva** hasta
apretar `Disable JWT-based API keys` (plan ya escrito en CLAUDE.md, lo aprieta el dueño). No hay
`service_role`, `sb_secret_`, claves de OpenAI/GitHub/AWS ni cadenas de conexión en el historial.

## 6. Clave de OpenAI de `leer-factura` — MEDIO

La función ya es un tapón que devuelve 410 (sin clave en el código). Lo que no se puede ver desde
acá: **si la clave se revocó en OpenAI.** Si no, sigue sirviendo para quien la haya copiado.
Revocarla en platform.openai.com → API keys.

## Fuera de GP2, mismo proyecto (para tener en cuenta)

El proyecto es compartido, así que estos también afectan: 4 vistas `SECURITY DEFINER` en `public`
(nivel ERROR del linter), 266 funciones `SECURITY DEFINER` de `public` y 61 de `planify`
ejecutables por `anon`, 18 tablas de `relevamiento_cervantes` sin RLS (legibles por `anon`, no
escribibles), extensiones en `public`, y la protección de contraseñas filtradas (HaveIBeenPwned)
apagada en Auth. Detalle: `get_advisors(security)` del proyecto.

## Cómo se midió

- Árbol y `git log --all -p`: regex de JWT, `sb_secret_`, `sk-`, `ghp_`/`github_pat_`, `AKIA`,
  `AIza`, `EAA…`, claves privadas y `postgres://usuario:clave@`. Los JWT se decodificaron para ver
  el `role`.
- Base: `pg_class.relrowsecurity`, `pg_policy`, `has_table_privilege`/`has_function_privilege`
  para `anon`, `prosecdef`, `proconfig` y el cuerpo de cada función (`pg_get_functiondef`).
- `get_advisors(security)`, `list_edge_functions` y el código desplegado de `leer-factura` y
  `gp2_leer_factura`.
