# Qué puede hacer la clave pública en Gestión Virgilio (2026-09-28)

**Solo lectura. No se cambió nada** (ni base, ni Storage, ni Edge Functions, ni el repo de Gestión Virgilio).
Proyecto Supabase `hrxfctzncixxqmpfhskv` (compartido por Gestión Virgilio, Planify, GP2 y el programa viejo).

## Estado de los arreglos (se van aplicando 1 x 1 con el dueño)

Decisión del dueño 28/09: el operario sigue entrando **solo con legajo (opción A)** por ahora → lo que
depende de identificarlo (tablas de producción, bucket privado) queda abierto.

- [x] `diag_ins` limitado a `planify_diag_priv` (verificado como anon).
- [x] `remitos`: `delete` y `update` borrados; `recepcion.js` sube sin `upsert`. Falta `select` (probar contra Storage real; chequeo 29/09).
- [x] Token de `GV_Alta_Articulo_Aprobacion` cerrado a anon (v23.39).
- [x] `leer-produccion-foto`: sesión habilitada + tope 100/día (v49).
- [x] `send-rendimiento-matrices` dada de baja (410); el reporte vigente es el PDF de `reporte-diario-rendimiento`.
- [x] `gv-alta-articulo` v21: código validado, sin links, legajo conocido, tope 10/hora.
- [x] `send-whatsapp` v55: texto/destinatario libre solo desde el servidor; con clave pública 4 plantillas sin links.
      Arreglado el aviso "sugerencia aprobada" de Planify (roto desde 15/09) — probado con Elías, llegó.
- [ ] Lo que depende de identificar al operario (tablas de producción, bucket privado, datos personales):
      plan en Gestión Virgilio `docs/PLAN-LOGIN-OPERARIOS-RED.md` (legajo + red de la empresa, IP fija).
- [ ] `github_repo_problemas` legible por anon (la lista de agujeros).
- Caída de la base 14:11–14:19 del 28/09: incidente de la plataforma Supabase (dueño), no del proyecto.
- Hallazgos extra al revisar RLS: `github_repo_problemas` (la lista de agujeros) legible por anon;
  `relevamiento_cervantes` 18 tablas con RLS apagada (solo lectura, stock: bajo).

## 0. El punto de partida

- La `sb_publishable_…` está en el repo **público** `loekemeyer/Gestion-Virgilio` → la tiene cualquiera.
  Con esa clave la base te trata como rol `anon`.
- En Gestión Virgilio **los operarios entran por legajo** (se guarda en el navegador, `vir_legajo_auth`):
  para la base son `anon`. Los supervisores entran con Google (`authenticated`).
- Consecuencia: todo lo que el operario puede hacer desde la tablet, **lo puede hacer un extraño desde su
  casa** con un `curl`. Cerrar a `anon` sin darle antes al operario una identidad en la base **rompe la
  tablet**. Por eso cada arreglo de abajo dice si toca o no a los operarios.

## 1. CRÍTICO — daño hoy, con solo la clave

| # | Qué | Medido | Toca operarios |
|---|-----|--------|----------------|
| C1 | `planify.employees` legible por anon **con `pass_hash`** (5 bcrypt), email, teléfono, fecha de nacimiento; y **INSERT abierto** | 57 filas, respuesta 206 | No |
| C2 | Política de Storage `diag_ins`: INSERT para anon **sin condición de bucket** → sube archivos a **cualquier** bucket (incl. privados `isis-lk`/`isis-ch` y el público `planify_page` = hosting de phishing con dominio supabase.co del proyecto) | política leída | No (revisar Planify diag) |
| C3 | Bucket privado `planify_sanciones` (19 archivos): anon LEE, SUBE, PISA y BORRA | políticas leídas | No |
| C4 | `planify.planify_admin_user_guardar` / `_borrar` SECURITY DEFINER **sin chequeo de quién llama** → cualquiera crea/modifica/borra usuarios admin de Planify y sus módulos | código leído | No |
| C5 | 12 tablas de `public` **borrables** por anon: `Registros Produccion Cervantes` (16.435), `db_n8n_espejo` (14.984), `Envios a Talleristas`, `Partes x Tallerista`, `Despiece x Articulo`, `Matrices`, `Articulos Virgilio X Tallerista`, `Entregas PS`, `Pendientes`, `Proporcion_Articulo_Tallerista`, `Rutas_Problemas`, `Rutas_Confirmadas` | grant + política `true` | **Sí** (la app de producción escribe `db_n8n_espejo`) |

## 2. ALTO

| # | Qué | Medido |
|---|-----|--------|
| A1 | `public`: anon INSERT en 107 tablas y UPDATE en 76 (incl. `Empleados`, `Proveedores`, `Precios_Proveedores`, `Ordenes_Compra`, `articulos`) | grant ∧ política abierta |
| A2 | Datos personales legibles: `Empleados` (70 emails), `Proveedores` (1.513 con CUIT/tel/email), `GV_Clientes_Contacto` (2.029 WhatsApp), `whatsapp_clientes` (942), `GV_Clientes_Whatsapp` (764), `Fichadas_Historico` (17.890 con email), direcciones | conteos en vivo, 206 |
| A3 | Funciones que anon ejecuta: `public` 477 (267 SECURITY DEFINER, **96 escriben sin chequear identidad, 23 borran**: `anular_picking_virgilio`, `insumo_borrar`, `gv_oc_generar_pendientes`, `gv_pedido_horario_*`, `tanda_*`, `rc_borrar`, `sync_stock_desde_matrices`, `gv_refrescar_precio_facturado`, `gv_supers_sync`…); `planify` 69 (26 escriben sin chequeo, 6 borran: `planify_chat_limpiar`, `planify_matriz_borrar`…); `procesos` 8 (5 escriben) | `pg_proc` + `has_function_privilege` |
| A4 | `planify`: anon INSERT 19 tablas, UPDATE 15 (`asistencia_diaria`, `novedades_manuales`, `vacaciones_lapsos`, `premios`, `recorrido_paradas`…), DELETE 3 (`tasks`, `task_lists`, `recorrido_destinos`) | grant ∧ política abierta |
| A5 | `wa_factura_grupo` (SQL dinámico con lista blanca, sin inyección) devuelve facturas por CUIT/fecha a anon | código leído |

## 3. MEDIO / BAJO

- `remitos` bucket público (401 fotos) con anon total — ya registrado como problema 584, migración propuesta **rechazada** el 28/09; no se reintenta.
- `planify_matriceria` (0 archivos) anon total; `planify_diag_priv` anon BORRA; `planify_manuales` anon LEE; `planify_chat` anon SUBE.
- 3 tablas de `GP2_bak` legibles por anon.
- `wa_sim_cleanup(_all)` borran solo filas de simulación.
- Bien: ninguna vista SECURITY DEFINER abierta a anon (arreglado 12/09); `gv_imp_cc_deuda_set` (chequea supervisor + lista blanca); liquidaciones/paritaria/sanciones (tablas) protegidas por `planify_is_maestro()`.

## 4. Edge Functions (`verify_jwt = false`)

51 funciones con `verify_jwt=false`; se leyó el código de 40 (11 de Planify sin fuente recuperable).
**Ninguna tiene rate limiting.** No hay secretos reales escritos en el código. Las tablas de secretos
(`lecturacvs.*_secrets`, `impo_comex.app_secrets`) están cerradas a anon.

| Riesgo | Función | Qué puede hacer un extraño |
|---|---|---|
| **CRÍTICO** | `planify_whatsapp-webhook` | El POST **no valida la firma de Meta** (`X-Hub-Signature-256`). Con un JSON falso y el celular de un empleado: crea tareas en su Planify, gasta Claude y le escribe por WA desde el número de la empresa; con el de Poli reordena el recorrido; con el de un candidato pisa su evaluación. `planify_social_webhook` sí valida la firma: es el modelo a copiar |
| **ALTO** | `leer-produccion-foto` | Sin auth ni tope: manda imágenes a gpt-4o vision a costo de la empresa, en loop. La URL está en `maestro.html` del repo público |
| **ALTO** | `gv-alta-articulo` | Sin auth: cada POST con un `cod` nuevo le manda a Thomas un WA + Telegram con texto y links del atacante (phishing desde el número propio). Y como anon lee los tokens de `GV_Alta_Articulo_Aprobacion` (política `gvaa_sel`), puede aprobar/rechazar cualquier alta. `cod` va al HTML sin escapar |
| **ALTO** | `send-rendimiento-matrices` | Sin auth: WA ilimitados a los 2 números del dueño + recorre todo `db_n8n_espejo` con service_role en cada llamada |
| MEDIO-ALTO | `fichada-qr-fichar` | Modo estático: desde la IP de la empresa alcanza con el email de un compañero para fichar por él (afecta sueldos) |
| MEDIO | `recon-facial-*` | Clave de kiosco de 20 caracteres sin bloqueo por intentos; el "liveness" lo declara el cliente. Con la clave: enrolar tu cara en el legajo de otro |
| MEDIO | `deposito-panel` | ABM de empleados y claves protegido por `clave_panel` sin bloqueo por intentos |
| MEDIO | `planify_recruit_cv_url` | "Valida" que la apikey sea la publicable (pública). Con el UUID de un candidato baja su CV |
| MEDIO | `planify_get_update_url` | Entrega el `.exe` de Planify a cualquiera usando el PAT de GitHub (2.098 llamadas en 24 h) |
| MEDIO (condicional) | `planify_notify-programacion` | Si no está cargada la env `BOT_NOTIFY_SECRET`, cualquiera dispara plantillas WA a clientes |
| SIN AUDITAR | 11 de Planify (`send-wa`, `transcribir`, `chat_media_url/up`, `get-produccion-dia`…) | No hay fuente. `get-produccion-dia` recibe llamadas desde ISPs residenciales con UA vacío |
| BAJO | isis-api, Impo_Comex_* (12), social_inbox/webhook, reporte-diario, cumple-wa, recruit_mail_import, excel_extract, fichada-qr-emitir-token, arca healthcheck, estimado-entrega, ia_page, stubs | Protegidas por token/HMAC o sin daño. Detalle: `SEND_WA_TOKEN` es uno solo para 5 funciones y viaja en la query string (queda en logs y en `cron.job`) |

## 5. Arreglos propuestos (nada ejecutado)

Orden: primero lo que **no toca a los operarios** (se puede hacer ya, sin romper nada), después lo que necesita
darle identidad al operario.

**Sin tocar operarios**
1. C1: `revoke select (pass_hash) on planify.employees from anon, authenticated` (o mover el hash a una tabla sin grant) + cerrar INSERT anon.
2. C2: borrar `diag_ins` o agregarle `bucket_id = '<bucket de diagnóstico>'`.
3. C3: sacarle a anon las 4 políticas de `planify_sanciones` (dejarlo para `planify_is_maestro()`).
4. C4 + A3 (planify): en cada función admin, `if not planify_is_maestro() then raise … end if`; revocar EXECUTE a anon.
5. Edge: `planify_whatsapp-webhook` → validar `X-Hub-Signature-256` con el App Secret de Meta (copiar `firmaValida` de `planify_social_webhook`).
   `leer-produccion-foto`, `send-rendimiento-matrices`, `gv-alta-articulo` → exigir sesión de supervisor (JWT) o token de servidor + tope por día;
   `gvaa_sel` → quitar SELECT anon de los tokens; escapar `cod`.
6. A2: vistas acotadas o `revoke select` de columnas personales a anon en las tablas que la tablet no lee (hay que cruzar con el código de `index.html` antes).

**Necesita identidad del operario** (decisión pendiente: legajo solo / **legajo + PIN validado en la base** / Google)
7. C5 + A1 + A3 (public): revocar DELETE/UPDATE/INSERT anon y reemplazar por RPCs que validen al operario.
   **Revisado en el código: sacar DELETE a anon hoy SÍ rompe.** La app de operarios (`cervantes/app.js`
   L1183 y L1413) borra en `Registros Produccion Cervantes` y `db_n8n_espejo` cuando el operario deshace un
   registro, y las pantallas de `cervantes-admin/` borran en `Entregas PS`, `Proporcion_Articulo_Tallerista`,
   `Rutas_*`, `Matrices`, `Pendientes`. Lo que sí se puede ya: el DELETE del operario pasa a una RPC
   `borrar_registro(id)` que solo borra filas **del día y de ese legajo**, y recién ahí se revoca DELETE.
