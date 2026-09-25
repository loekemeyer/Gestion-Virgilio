/* v22.81 — el maestro de importados (Importados / Importados_Volumen) se escribe CON LOGIN.
   Hasta v22.74 las 5 escrituras iban con la clave publicable como Bearer (= anon) y la base las
   aceptaba de cualquiera. Ahora la base sólo deja a supervisores (es_supervisor_virgilio()) y el
   front manda el JWT de la sesión Google por _impEscribir().

   Lo que se verifica (sin navegador, sobre el index.html):
   (a) ningún fetch escribe directo a /rest/v1/Importados ni /rest/v1/Importados_Volumen;
   (b) las 5 funciones que escriben el maestro pasan por _impEscribir;
   (c) _impEscribir: sin sesión no manda nada y avisa; con sesión manda el JWT (no la clave);
       HTTP con error → error; un PATCH que la RLS filtra (0 filas) → error, no un "guardado"
       mudo; un PATCH que actualiza → ok. */
const fs = require("fs");
const path = require("path");

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };

// (a) nada de fetch directo a las dos tablas (las lecturas van por supaFetchAllSafe)
const directos = html.match(/fetch\(\s*SUPABASE_URL\s*\+\s*"\/rest\/v1\/Importados(_Volumen)?[?"]/g) || [];
ok(directos.length === 0, "(a) quedan " + directos.length + " fetch directos al maestro de importados (tienen que pasar por _impEscribir)");

// (b) cada escritura pasa por _impEscribir
function cuerpoDe(nombre) {
  const i = html.indexOf("async function " + nombre + "(");
  if (i < 0) return null;
  const j = html.indexOf("\n}\n", i);
  return html.slice(i, j < 0 ? i + 4000 : j);
}
[["provImpSet", '"Importados?cod_art=eq."'], ["pedImpEditVol", '"Importados_Volumen?on_conflict=cod"'],
 ["pedImpEditFob", '"Importados?cod_art=eq."'], ["pedImpSetReingreso", '"Importados?cod_art=eq."'],
 ["pedImpSetCurso", '"Importados?cod_art=eq."']].forEach(function (x) {
  const c = cuerpoDe(x[0]);
  ok(c, "(b) no encuentro " + x[0]);
  if (c) ok(c.indexOf("_impEscribir(" + x[1]) >= 0, "(b) " + x[0] + " no escribe por _impEscribir(" + x[1] + ")");
});

// (c) comportamiento de _impEscribir con fetch y sesión simulados
const src = cuerpoDe("_impEscribir");
ok(src, "(c) no existe _impEscribir");

(async () => {
  if (src) {
    const armar = function (token, respuesta) {
      const llamadas = [];
      const facAuthWriteHeaders = async function (extra) {
        if (!token) return null;
        return Object.assign({ apikey: "PUB", Authorization: "Bearer " + token, "Content-Type": "application/json" }, extra || {});
      };
      const authNoSesionMsg = function (b) { return b; };
      const fetch = async function (url, op) { llamadas.push({ url: url, op: op }); return respuesta; };
      const fn = new Function("facAuthWriteHeaders", "authNoSesionMsg", "fetch", "SUPABASE_URL",
        src.replace(/^async function _impEscribir/, "return async function") + "\n}");
      return { f: fn(facAuthWriteHeaders, authNoSesionMsg, fetch, "https://x.supabase.co"), llamadas: llamadas };
    };
    const resp = function (status, cuerpo) {
      return { ok: status >= 200 && status < 300, status: status,
               json: async function () { return cuerpo; }, text: async function () { return JSON.stringify(cuerpo); } };
    };
    const falla = async function (p) { try { await p; return null; } catch (e) { return String(e.message || e); } };

    // sin sesión: no llama y pide login
    let t = armar(null, resp(200, [{}]));
    let e = await falla(t.f("Importados?cod_art=eq.437E", "PATCH", { fob_uni: 1 }));
    ok(e && /Inici/.test(e), "(c) sin sesión no avisa que hay que iniciar sesión: " + e);
    ok(t.llamadas.length === 0, "(c) sin sesión igual mandó el pedido");

    // con sesión: manda el JWT del usuario y pide la representación
    t = armar("JWT-USUARIO", resp(200, [{ id: 1 }]));
    e = await falla(t.f("Importados?cod_art=eq.437E", "PATCH", { fob_uni: 1 }));
    ok(e === null, "(c) un PATCH que actualiza dio error: " + e);
    const h = (t.llamadas[0] || {}).op ? t.llamadas[0].op.headers : {};
    ok(h.Authorization === "Bearer JWT-USUARIO", "(c) no manda el JWT del usuario: " + JSON.stringify(h));
    ok(/return=representation/.test(h.Prefer || ""), "(c) el PATCH no pide la representación (no podría contar filas)");
    ok(t.llamadas[0] && t.llamadas[0].url === "https://x.supabase.co/rest/v1/Importados?cod_art=eq.437E", "(c) URL mal armada");

    // RLS filtró: 0 filas → error (no un guardado mudo)
    t = armar("JWT-NO-SUPERVISOR", resp(200, []));
    e = await falla(t.f("Importados?cod_art=eq.437E", "PATCH", { fob_uni: 1 }));
    ok(e && /0 filas/.test(e), "(c) un PATCH filtrado por la RLS no avisa: " + e);

    // HTTP con error → error
    t = armar("JWT-USUARIO", resp(403, { message: "new row violates row-level security policy" }));
    e = await falla(t.f("Importados_Volumen?on_conflict=cod", "POST", { cod: "437E" }, "resolution=merge-duplicates,return=minimal"));
    ok(e && /403/.test(e), "(c) un 403 no da error: " + e);
  }

  if (fallas.length) { console.error("✗ imp-escritura-login:\n  - " + fallas.join("\n  - ")); process.exit(1); }
  console.log("✓ imp-escritura-login: el maestro de importados se escribe sólo con la sesión, y un rechazo se avisa");
})().catch(function (e) { console.error(e); process.exit(1); });
