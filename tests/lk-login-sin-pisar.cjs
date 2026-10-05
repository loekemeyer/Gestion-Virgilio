/* v26.78 (Tomás Gonzalez, 05/10) — entrar al panel de LK NO puede echar al que ya está adentro.

   El usuario de LK del Panel Web LK (loekemeyer.n8n@gmail.com) es COMPARTIDO: lo usan el
   panel (OTP y puente desde Gestión) y Gestión para leer pedidos (`pwebLkToken`). La Edge
   Function `admin-login-otp` entraba cambiándole la password, y en Supabase cambiar la
   password CIERRA TODAS las sesiones del usuario. La del que estaba en el panel quedaba
   muerta en el servidor pero viva en el navegador: las lecturas andaban (PostgREST sólo
   mira la firma del JWT) y el alta de clientes moría con «invalid_token»
   (crear-cliente-auth sí pregunta al auth). Medido el 05/10: 22 cambios de clave por día.

   Candados:
   A. la función entra primero por ENLACE (generateLink + verifyOtp), sin tocar la clave;
      el cambio de clave queda sólo como respaldo.
   B. el espejo del panel pide modo enlace y sabe entrar con la sesión directa (setSession)
      o con el password temporal del modo viejo.
   C. ningún signOut del espejo cierra las sesiones de todos (scope local).
   D. el panel detecta la sesión muerta en el servidor y no la usa.
   E. «invalid_token» se explica en castellano. */
const fs = require("fs");
const path = require("path");
const RAIZ = path.join(__dirname, "..");
const adm = fs.readFileSync(path.join(RAIZ, "admin/admin.js"), "utf8");
const fn = fs.readFileSync(path.join(RAIZ, "admin/supabase/admin-login-otp/index.ts"), "utf8");
const sinComent = (t) => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

const fallos = [];
const chk = (cond, msg) => { console.log((cond ? "ok   " : "MAL  ") + msg); if (!cond) fallos.push(msg); };

// ── A. la Edge Function ─────────────────────────────────────────────────────
const fnC = sinComent(fn);
const iEntrar = fnC.indexOf("async function entrar(");
const cuerpoEntrar = iEntrar >= 0 ? fnC.slice(iEntrar, fnC.indexOf("\n}\n", iEntrar)) : "";
chk(/generateLink\(\s*\{\s*type:\s*"magiclink"/.test(fnC), "A. la función genera el enlace (magiclink) para el usuario del panel");
chk(/verifyOtp\(\s*\{\s*token_hash/.test(fnC), "A. lo canjea server-side por una sesión (verifyOtp con token_hash)");
chk(cuerpoEntrar.indexOf('modo === "enlace"') >= 0 &&
    cuerpoEntrar.indexOf("sesionPorEnlace") < cuerpoEntrar.indexOf("updateUserById"),
    "A. entrar(): primero el enlace, el cambio de clave sólo de respaldo");
const usosUpd = (fnC.match(/updateUserById\(/g) || []).length;
chk(usosUpd === 1, "A. un solo lugar cambia la clave (entrar), no uno por acción (hay " + usosUpd + ")");
chk((fnC.match(/entrar\(admin,\s*userId,\s*body\.modo\)/g) || []).length === 2,
    "A. bridge y verify pasan por entrar() con el modo que pidió el front");

// ── B/C/D/E. el espejo del panel ────────────────────────────────────────────
const admC = sinComent(adm);
chk(/body\.modo\s*=\s*modo/.test(admC) && /"enlace"/.test(admC), "B. _lkOtpFn pide modo enlace");
chk(/auth\.setSession\(\s*\{\s*access_token:/.test(admC), "B. con sesión directa entra por setSession");
const bareSignOut = admC.match(/\.auth\.signOut\(\s*\)/g) || [];
chk(bareSignOut.length === 0, "C. ningún signOut() pelado (cierra las sesiones de todos): hay " + bareSignOut.length);
chk(/_lkSesionViva\(\)/.test(admC.slice(admC.indexOf("async function checkAuth"), admC.indexOf("async function checkAuth") + 3000)),
    "D. checkAuth pregunta al auth si la sesión sigue viva");
chk(/em === "invalid_token"/.test(admC), "E. «invalid_token» tiene su explicación");

// ── B/D corriendo las funciones de verdad ───────────────────────────────────
function extraer(nombre) {
  const i = adm.indexOf((/^_lkModo/.test(nombre) ? "function " : "async function ") + nombre + "(");
  if (i < 0) return null;
  let d = 0, j = adm.indexOf("{", i);
  for (let k = j; k < adm.length; k++) {
    if (adm[k] === "{") d++;
    else if (adm[k] === "}") { d--; if (d === 0) return adm.slice(i, k + 1); }
  }
  return null;
}
(async () => {
  const src = ["_lkModoLogin", "_lkAplicarLogin", "_lkSesionViva"].map(extraer);
  chk(src.every(Boolean), "B. las tres funciones de login existen");
  if (src.every(Boolean)) {
    const llamadas = [];
    let user = { error: null };
    const sb = { auth: {
      setSession: async (x) => { llamadas.push(["setSession", x.access_token]); return { error: null }; },
      signInWithPassword: async (x) => { llamadas.push(["password", x.password]); return { error: null }; },
      getUser: async () => user,
    } };
    const ls = {}; const localStorage = { getItem: (k) => (k in ls ? ls[k] : null) };
    const f = new Function("sb", "localStorage", src.join("\n") +
      "\nreturn { _lkModoLogin, _lkAplicarLogin, _lkSesionViva };")(sb, localStorage);

    chk(f._lkModoLogin() === "enlace", "B. modo por defecto = enlace");
    ls.lk_login_legacy = "1";
    chk(f._lkModoLogin() === null, "B. lk_login_legacy=1 vuelve al modo viejo (rollback sin deploy)");

    const e1 = await f._lkAplicarLogin({ access_token: "A", refresh_token: "R" });
    const e2 = await f._lkAplicarLogin({ email: "x@y", tmp_password: "P" });
    const e3 = await f._lkAplicarLogin({});
    chk(!e1 && llamadas[0][0] === "setSession", "B. sesión directa → setSession, sin password");
    chk(!e2 && llamadas[1][0] === "password", "B. respuesta del modo viejo → signInWithPassword (compatibilidad)");
    chk(!!e3, "B. sin credenciales → error, no entra");

    user = { error: { status: 403, code: "session_not_found", message: "Session from session_id claim in JWT does not exist" } };
    chk((await f._lkSesionViva()) === false, "D. sesión borrada en el servidor → muerta");
    user = { error: { status: 0, message: "Failed to fetch" } };
    chk((await f._lkSesionViva()) === true, "D. error de red → NO la da por muerta");
    user = { data: { user: { id: "u" } }, error: null };
    chk((await f._lkSesionViva()) === true, "D. sesión reconocida → viva");
  }
  if (fallos.length) { console.error("\nFALLARON " + fallos.length + ":\n· " + fallos.join("\n· ")); process.exit(1); }
  console.log("\nlk-login-sin-pisar OK");
})();
