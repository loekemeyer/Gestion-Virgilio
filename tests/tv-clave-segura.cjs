/* tests/tv-clave-segura.cjs — v29.84 (Elías, 13/10/2026): el código de ingreso ya no se pide pelado con la
   clave pública. Corre monitor/tv-clave.js con fetch falso y mira qué llama en cada caso, y candados
   estáticos sobre tv.html / index.html. */
const fs = require("fs"), path = require("path"), vm = require("vm");
const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "monitor/tv-clave.js"), "utf8");
let fallas = 0; const ok = (c, m) => { if (!c) { fallas++; console.log("✗ " + m); } else console.log("✓ " + m); };

function entorno(resp) {
  const llamadas = []; const ls = {};
  const w = {
    localStorage: { getItem: k => (k in ls ? ls[k] : null), setItem: (k, v) => { ls[k] = String(v); } },
    crypto: { getRandomValues: a => { for (let i = 0; i < a.length; i++) a[i] = (i * 37 + 11) & 255; return a; } },
    navigator: { userAgent: "test" },
    fetch: (url, o) => {
      const fn = url.split("/rpc/")[1]; const auth = o.headers.Authorization; const body = JSON.parse(o.body || "{}");
      llamadas.push({ fn, auth, body });
      const r = resp(fn, auth, body);
      return Promise.resolve({ ok: r != null, json: () => Promise.resolve(r) });
    }
  };
  w.window = w; vm.runInNewContext(src, w);
  return { w, llamadas, ls };
}
(async () => {
  // a) con sesión: va con el token, nada más
  let e = entorno((fn, auth) => fn === "gv_tv_clave_actual" && auth === "Bearer TOK" ? { clave: "1234", cambia_en_s: 30 } : null);
  let r = await e.w.gvTvClaveLeer("U", "K", () => Promise.resolve("TOK"));
  ok(r && r.clave === "1234" && r.fuente === "sesion" && e.llamadas.length === 1, "a) con sesión usa el token del supervisor y nada más");

  // b) TV vinculada: va con el secreto, nunca con la clave pública pelada
  e = entorno((fn, auth, b) => fn === "gv_tv_clave_actual_tv" && b.p_secreto && b.p_secreto.length >= 32 ? { ok: true, estado: "activa", clave: "5678", cambia_en_s: 12 } : null);
  r = await e.w.gvTvClaveLeer("U", "K", () => null);
  ok(r && r.clave === "5678" && r.fuente === "tv", "b) TV vinculada: código por el secreto");
  ok(!e.llamadas.some(l => l.fn === "gv_tv_clave_actual"), "b) TV vinculada: no llama a gv_tv_clave_actual");
  ok(e.ls.gv_tv_secreto && e.ls.gv_tv_secreto.length === 64, "b) el secreto queda guardado (64 hex)");

  // c) TV desconocida: pide vínculo y, mientras la base lo permita, cae a la clave pública
  e = entorno((fn) => fn === "gv_tv_clave_actual_tv" ? { ok: false, estado: "desconocida" }
    : fn === "gv_tv_vincular_pedir" ? { ok: true, estado: "pendiente", codigo: "445566" }
    : fn === "gv_tv_clave_actual" ? { clave: "9999", cambia_en_s: 5 } : null);
  r = await e.w.gvTvClaveLeer("U", "K", () => null);
  ok(r && r.vincular === "445566" && r.clave === "9999" && r.fuente === "anon", "c) TV sin vincular: muestra el código para vincularla");

  // d) parte B aplicada (la clave pública ya no contesta): queda el código de vinculación solo
  e = entorno((fn) => fn === "gv_tv_clave_actual_tv" ? { ok: false, estado: "pendiente", codigo: "112233" } : null);
  r = await e.w.gvTvClaveLeer("U", "K", () => null);
  ok(r && r.vincular === "112233" && !r.clave, "d) sin la clave pública queda sólo el código de vinculación");
  ok(!e.llamadas.some(l => l.fn === "gv_tv_vincular_pedir"), "d) pendiente vigente: no vuelve a pedir el vínculo");

  // e) estáticos
  const tv = fs.readFileSync(path.join(root, "monitor/tv.html"), "utf8");
  const adm = fs.readFileSync(path.join(root, "monitor/admin.html"), "utf8");
  const idx = fs.readFileSync(path.join(root, "index.html"), "latin1");
  ok(/tv-clave\.js\?v=/.test(tv) && /gvTvClaveLeer/.test(tv) && !/rpc\/gv_tv_clave_actual"/.test(tv), "e) tv.html usa el helper y no pide el código pelado");
  ok(/tv-clave\.js\?v=/.test(adm), "e) admin.html (generado) carga el helper");
  ok(/monitor\/tv-clave\.js\?v=/.test(idx) && !/rpc\/gv_tv_clave_actual"/.test(idx), "e) index.html usa el helper para el header del monitor");
  const lg = idx.slice(idx.indexOf("window.loginConClaveTv = async"), idx.indexOf("window.tvMostrarLegajoNum"));
  ok(/p_dispositivo: gvDispositivoId\(\)/.test(lg) && /p_huella/.test(lg) && /_tvClaveError\(j\.error\)/.test(lg), "e) el login manda el equipo y muestra el motivo");
  ok(/cfgGo\(openVincularTv\)/.test(idx) && /gv_tv_vincular_aprobar/.test(idx), "e) ⚙️ Configuración tiene «📺 Vincular TV»");
  console.log(fallas ? "\nFALLÓ (" + fallas + ")" : "\ntv-clave-segura: OK");
  process.exit(fallas ? 1 : 0);
})();
