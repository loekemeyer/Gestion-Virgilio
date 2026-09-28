# Plan: login de operarios por legajo + red de la empresa (2026-09-28)

**Objetivo (Thomas, 28/09):** que la clave pública (`sb_publishable_…`, está en repos públicos) no
sirva para hacer daño. Jerarquía de acceso:

| Nivel | Cómo entra | Desde dónde | Qué puede |
|---|---|---|---|
| **operario** | legajo | **solo red de la empresa** (IP fija Cervantes / Virgilio) | cargar SUS registros, deshacer los suyos < 15 min |
| **supervisor** | Google (whitelist) | cualquier lugar | corregir lo de todos |
| **admin** | Google (whitelist, rol admin) | cualquier lugar | maestros, precios, empleados |
| clave pública sola | — | — | **nada** que escriba; solo lo mínimo para mostrar el login |

Datos del dueño (28/09): las dos plantas tienen **IP fija**; el **Wi-Fi de invitados está separado**.
Medido (28/09): la IP que ve el servidor **no se puede falsificar** con cabeceras (`X-Forwarded-For`,
`X-Real-IP` probados contra `fichada-qr-fichar` → el gateway los pisa).

Apps alcanzadas: **Gestión Virgilio** (`index.html` + `recepcion.js` + `sw.js`, más las copias de
`cervantes/` y `cervantes-admin/`) y **Registro Producción 2.0** (`app.js` + `sw.js`, repo
`loekemeyer/Registro-Produccion-2.0`).

## Estado

- **Etapa 0 (inventario): EN CURSO** desde el 28/09 — Routine nocturno llena `public.seg_inventario_anon` hasta el 03/10.
  Primer corte (28/09, hasta las 14:40): 10.382 escrituras con la clave pública; 90 % desde las 3 IP de la
  empresa; **otras redes fijas**: Caseros 190.247.118.38 (Planify de escritorio) y Lobos 181.105.135.47
  (pantallas de gestión de GV + `Registros_Produccion_Virgilio`); **celulares con datos móviles**: cargas de
  producción en Cervantes (≈8 legajos) y Virgilio → con la regla de red quedarían afuera. A decidir.
- **Etapa 1 (base del login): HECHA** el 28/09 — `login-operario` v2, `red_empresa` (3 IP), `jwt_rol/jwt_legajo`,
  cierre nocturno. Probada. Ninguna app la usa: no cambia nada de lo actual. SQL: `sql/login_operarios_etapa1.sql`.


**Decisiones del dueño (28/09):**
- La regla de red es **solo para operarios** (entran por legajo). Quien entra con **mail (Google)** —dueño,
  supervisores, gestión— **está exento**: entra desde cualquier lugar.
- Operarios con datos móviles: **sin excepción, usan el Wi-Fi** de la empresa.
- Redes vistas en el inventario: Lobos 181.105.135.47 = el dueño (cuenta Google) → exento; Caseros
  190.247.118.38 = Planify de escritorio → fuera de este plan (tanda Planify). Red de operarios = las 3 IP
  de la fichada. OJO etapa 2: desde la PC del dueño salen 6.336 pedidos SIN sesión (clave pública) contra
  297 con sesión: las pantallas de gestión de GV también tienen que mandar la sesión Google antes de cerrar.

**Red de operarios (public.red_empresa, 28/09)** — las sedes salen de `FichadaQR.config.ip_trabajo_nota`
(ya estaban anotadas ahí; mirar esa nota antes de preguntar):
190.245.164.168 = Cervantes ("loekemeyer"; probado desde el Wi-Fi: entra; con datos móviles: rechazado y aviso por
Telegram una sola vez) · 186.18.168.71 = Loeke fábrica · 181.164.213.179 = Virgilio (centro de distribución).
Página de prueba: https://loekemeyer.github.io/Prueba-Login-Operarios/ (repo aparte, temporal; legajo 1).

**Regla general (dueño, 28/09): todas las apps usan un login u otro; ninguna escribe con la clave pública sola.**

| Quién | Entra con | Rol |
|---|---|---|
| Operarios (tablets de Registro Producción y GV) | legajo + Wi-Fi de la empresa (`login-operario`) | operario |
| Supervisores / gestión | **mail (Google)** | supervisor |
| **Admin** | **mail (Google), siempre** — nada de legajo, clave compartida ni contraseña propia | admin |
| Lo que no es persona (Planify escritorio, agente ISIS, n8n, macros, procesos) | clave de servidor guardada en esa máquina, nunca en una página | servicio |

Trampa a resolver en la etapa 2: hoy casi todas las pantallas piden el login en el navegador pero le hablan a
la base con la clave pública (la base no sabe quién es). Cada app tiene que MANDAR la sesión en cada pedido.

## Diseño

1. **Lista de redes**: tabla `public.red_empresa (ip, sede, activo)` con las IP fijas de Cervantes y
   Virgilio (hoy la fichada usa `FichadaQR.config.ip_trabajo`: se toma de ahí y se unifica). RLS sin
   políticas (solo service_role).
2. **Edge Function `login-operario`** (`verify_jwt=false`, la llama la pantalla de legajo):
   - toma la **IP real** del pedido y la busca en `red_empresa` → si no está: 403 *"solo desde la red
     de la empresa"* (y se anota, para detectar un cambio de IP);
   - valida que el legajo exista y esté activo en `Empleados`;
   - devuelve una **sesión de Supabase** del usuario `op<legajo>@operarios.interno` (se crea la primera
     vez, `app_metadata = {rol:'operario', legajo}`), generada del lado del servidor (admin API).
     La contraseña no existe para nadie: la única puerta es esta función.
3. **La sesión vence al final del turno**: cron nocturno (23:00 AR) que borra las sesiones de los
   usuarios operario (`auth.sessions` / `auth.refresh_tokens`). Al día siguiente, legajo de nuevo.
4. **En la base**: helpers `public.jwt_rol()` y `public.jwt_legajo()` (leen `auth.jwt()->'app_metadata'`).
   Las políticas y RPCs que hoy dicen `to anon ... using (true)` pasan a
   `to authenticated using (jwt_rol() in ('operario','supervisor','admin'))`, y las de "lo mío"
   comparan `legajo = jwt_legajo()`.
5. **Cola offline (`sw.js`, las dos apps)**: hoy reenvía con la clave pública. La página guarda el
   último `access_token` en IndexedDB; el SW lo usa; si da 401 el ítem **queda en la cola** (no se
   pierde) hasta que la página renueve la sesión. Es la parte más delicada: se prueba con la tablet
   sin red, cargando, y reconectando.
6. **Supervisores**: sin cambios (Google). Pantallas de admin que hoy escriben con la clave pública
   (ej. `Stock_Config` desde 10 lugares de `index.html`) pasan a la sesión Google.

## Etapas (en este orden; saltear la 3 es lo que obligó a volver atrás el 16/09)

| # | Qué | Rompe algo | Cómo se sabe que terminó |
|---|---|---|---|
| 0 | **Inventario** de toda escritura con la clave pública, por app y por tabla/RPC, sacado de los logs de la API (3–5 días hábiles) + código | no | lista cerrada, cada escritura con su app dueña |
| 1 | `red_empresa` + `login-operario` + cron de cierre + helpers `jwt_rol/jwt_legajo` | no (nadie los usa aún) | login probado desde la red y rechazado desde afuera |
| 2 | Las dos apps piden legajo contra `login-operario` y **mandan la sesión** (también el SW). La base todavía acepta anon | no | versión nueva en todas las tablets (`gv_app` / versión en logs) |
| 3 | **Medir**: en los logs, cero escrituras con rol anon durante N días hábiles | no | 0 escrituras anon, por tabla |
| 4 | **Cerrar** tabla por tabla / RPC por RPC: anon → `authenticated` con rol. Una tanda por día, con vuelta atrás escrita | si algo quedó afuera del inventario, eso | cada tanda sin 401 nuevos en logs |
| 5 | Lecturas con datos personales (`Empleados`, `Proveedores`, contactos, fichadas) solo con sesión | pantallas que lean sin sesión | idem |

## Riesgos

- **Cambio de IP** (el proveedor la cambia): nadie puede entrar. Mitigación: `login-operario` avisa
  por Telegram al primer rechazo por IP desde un legajo válido; actualizar `red_empresa` es una fila.
- **Operarios en datos móviles**: quedan afuera (buscado).
- **Alguien en la red con un legajo ajeno**: la IP prueba el lugar, no la persona. Con Wi-Fi de
  invitados separado el riesgo queda en gente de adentro. Si hace falta más: PIN (etapa futura).
- **TV de pared / monitores** (solo leen): o se les da un usuario de dispositivo, o las vistas que
  muestran quedan legibles sin sesión si no tienen datos personales.

## Lo que ya se cerró el 28/09 sin esperar este plan

`diag_ins` (subía a cualquier bucket), `remitos` sin borrar ni pisar, token de altas, `leer-produccion-foto`
con sesión y tope, `send-rendimiento-matrices` dada de baja, `gv-alta-articulo` acotada,
`send-whatsapp` sin texto libre público (y arreglado el aviso de sugerencias de Planify). Detalle en
`sql/seguridad_anon_v2338.sql` y en el informe `SEGURIDAD_ANON_GESTION_VIRGILIO_2026-09-28.md` (repo GP2).
