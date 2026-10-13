# Panel Web LK (espejo bajo /admin/)

> Movido de `CLAUDE.md` el 2026-10-13 (poda de reglas, pedido de Luis) para que no cargue en cada sesión.
> Es documentación operativa VIVA del módulo, no se resume: leer ENTERA antes de tocar este módulo.

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
  (i) **modo Est. Madre de Gestión sin código** (v25.72): `GV_EM_EMBED`, `_gvEmFetch`, `GV_EM_PERMITIDAS`
  y `window.supabaseClient = sb` al principio de admin.js, y el corte de `checkAuth()` y del init. Si se pisa,
  la pestaña EST. MADRE vuelve a pedir el OTP: buscar `gv_em` y correr `tests/stk-est-madre-sin-codigo.cjs`.
  (j) **la Est. Madre NO se re-copia de LK** (v25.79): vive SÓLO en `admin/est-madre.js` de este repo y los
  dos `admin.js` traen el mismo cargador `abrirEstadisticaMadre` (huella md5 en `tests/est-madre-unica.cjs` de
  los dos repos). Al re-sincronizar, no volver a traer la Est. Madre de `pagina-LK-copia`: allá ya no está.
  (k) el ítem **«Análisis de Cobranzas»** del menú lateral de admin.html es propio de la copia (LK nunca lo tuvo).
  (l) el encabezado **`pscThCant`** de Pedidos sin cot y su texto «…cargan en unidades» los **perdió LK** el 23/09
  (commit `27ddd39`, una copia vieja pisó admin.html); la copia los conserva hasta que LK los recupere.

  ⚠ **Re-sincronizada entera el 02/10/2026 (v26.13) contra LK v2.3.508**: estaba con el pie en 2.3.187 y
  `admin.js` con 3.648 líneas de diferencia (le faltaban, entre otros, el mapa por vendedor, la escala y el
  acuerdo de expo y el alta de clientes por Edge Function). **Cómo se hizo, para repetirlo**: se parte del
  archivo de LK y se le vuelven a aplicar SÓLO los bloques de (a)–(l) (`diff` LK → copia, hunk por hunk);
  nunca se copia la copia vieja encima. Lo sostienen `est-madre-unica`, `stk-est-madre-sin-codigo`,
  `stk-est-madre-tab`, `krikos-parsers`, `regla-L-super` y los `pweb-*`.

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
  (`hrxfctzncixxqmpfhskv`, con la **clave publishable** de GV escrita en la función —
  ya no la anon legacy, v16.55, problema 19) y **sólo si el
  mail del token == `RECIPIENT_EMAIL`** (mismo dueño, no amplía acceso a nadie)
  devuelve el mismo password temporal que `verify`. Gate 100% en backend: el
  front no puede falsear identidad. Si mañana se quiere que otro supervisor
  entre, ampliar el chequeo de `vemail` en la función (y crear su user en LK).

### ⚠⚠ REGLA (Tomás Gonzalez, 2026-10-05, v26.80): entrar al panel de LK NO le cambia la clave al usuario compartido

**Caso:** alta de cliente en el Panel Web LK → *«No se pudo crear el login (CUIT + PIN): invalid_token»*. El
usuario de LK `loekemeyer.n8n@gmail.com` lo comparten el panel (OTP y puente) y Gestión (`pwebLkToken`), y
`admin-login-otp` entraba **cambiándole la password: en Supabase eso CIERRA TODAS las sesiones del usuario**
(medido el 05/10: 22 cambios de clave por día). La sesión del que estaba en el panel quedaba muerta en el
servidor y viva en el navegador: las lecturas andaban (PostgREST sólo mira la firma del JWT) y
`crear-cliente-auth` (que pregunta al auth) contestaba `invalid_token`.

| pieza | qué hace desde v26.80 |
|---|---|
| `admin-login-otp` | con `modo: "enlace"` entra por `generateLink` (magiclink) + `verifyOtp` server-side y devuelve `access_token` + `refresh_token` **sin tocar la clave**. Si el enlace falla, cae al modo viejo (password temporal) y lo loguea |
| espejo `admin/admin.js` | `_lkOtpFn` pide enlace; `_lkAplicarLogin` entra con `setSession` (o con el password del modo viejo); `checkAuth` descarta la sesión muerta en el servidor (`_lkSesionViva`); todo `signOut` con `scope: "local"` |
| Gestión `pwebLkToken` | pide enlace y **renueva con el refresh token** la sesión que ya tiene en vez de abrir otra por el puente |
| rollback por navegador | `localStorage.lk_login_legacy = "1"` vuelve al modo viejo sin deploy |

⚠ **Nunca escribir `signOut()` pelado sobre un usuario compartido**: el default es `global` y cierra las sesiones
de todos. Lo sostiene `tests/lk-login-sin-pisar.cjs` (falla contra el código anterior: 4 `signOut()` pelados).
⚠ Con el enlace las sesiones del usuario ya no se borran solas: se acumulan en `auth.sessions` de LK (una por
entrada al panel o por pestaña de Gestión).
