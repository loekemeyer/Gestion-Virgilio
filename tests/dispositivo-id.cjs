// v25.25 (Luis): cada celular manda su ID propio con cada evento y cada ingreso.
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(__dirname + "/../index.html", "utf8");
let fail = 0; const ok = (c, m) => { console.log((c ? "  ok  " : "  FALLA ") + m); if (!c) fail++; };
const ini = src.indexOf("var _gvDispMem = null;"), fin = src.indexOf("/* v4.50 — Baliza", ini);
ok(ini > 0 && fin > ini, "bloque gvDispositivoId presente");
const store = {}, posts = [];
const ctx = { localStorage: { getItem: k => store[k] || null, setItem: (k, v) => { store[k] = String(v); } },
  crypto: { randomUUID: () => "11111111-2222-3333-4444-555555555555" }, navigator: { userAgent: "UA" },
  SUPABASE_URL: "https://x", SUPABASE_KEY: "k", APP_VERSION: "t", Date, Math, String,
  fetch: (u, o) => { posts.push({ u, b: JSON.parse(o.body) }); return Promise.resolve({ ok: true }); } };
vm.createContext(ctx); vm.runInContext(src.slice(ini, fin), ctx);
const a = ctx.gvDispositivoId(), b = ctx.gvDispositivoId();
ok(a === b && a.length >= 8, "el ID es estable entre llamadas");
ok(store.gv_dispositivo === a, "queda guardado en localStorage");
ctx.gvRegistrarIngreso({ type: "operario", emp: { legajo: "104" }, nombre: "Jhonny" }, "legajo");
ok(posts.length === 1 && /GV_Dispositivo_Login$/.test(posts[0].u), "el ingreso va a GV_Dispositivo_Login");
ok(posts[0] && posts[0].b.dispositivo === a && posts[0].b.legajo === "104" && posts[0].b.metodo === "legajo", "el ingreso lleva dispositivo, legajo y método");
setTimeout(() => {
  ctx.gvRegistrarIngreso({ type: "operario", emp: { legajo: "104" } }, "legajo");
  ok(posts.length === 1, "una recarga el mismo día no suma otra fila");
  const n = (src.match(/gv_dispositivo: gvDispositivoId\(\)/g) || []).length;
  ok(n >= 2, "los dos envíos de eventos (individual y replay) llevan gv_dispositivo (" + n + ")");
  ok(/function _routeAfterAuth\(\) \{\n  try \{ gvRegistrarIngreso/.test(src), "_routeAfterAuth registra el ingreso");
  ok(!/gvRegistrarIngreso[^\n]*signOut|clearLegajoSession\(\)[^\n]*gvDisp/.test(src), "no toca la sesión");
  process.exit(fail ? 1 : 0);
}, 20);
