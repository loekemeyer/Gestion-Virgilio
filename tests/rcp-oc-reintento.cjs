// v22.42 (Luis, 24/09: "tiene que reintentar hasta que esté") — la imputación de la recepción a
// la OC va a una COLA persistente y se reintenta hasta que la base la acepte. supabase.rpc
// resuelve con {error} ante un 500, así que el reintento tiene que mirar r.error.
// Corre el código de verdad con un supabase falso que falla 4 veces y después anda.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../recepcion.js", "utf8");
const fallos = [];
const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fallos.push(m); };
const i = src.indexOf("var RCP_OC_KEY");
chk(i > 0, "la cola persistente existe");
chk(/rcpOcEncolar\(opState\.tallNombre/.test(src), "el envío de la recepción encola la imputación");
chk(!/gv_oc_aplicar_recepcion"[\s\S]{0,300}\.then\(function \(\) \{\}, function \(\) \{\}\)/.test(src), "ya no se descarta el resultado sin mirar");
if (i < 0) { console.log("\nFALLARON " + fallos.length); process.exit(1); }
const body = src.slice(i).replace(/\n\s*try \{\n\s*if \(typeof window !== "undefined"\)[\s\S]*$/, "")
  + "\nreturn { rcpOcEncolar, rcpOcDrain, rcpOcLeer };";
const store = {};
const localStorage = { getItem: (k) => (k in store ? store[k] : null), setItem: (k, v) => { store[k] = String(v); } };
let llamadas = 0, fallar = 4;
const supabase = { rpc: async () => { llamadas++; return fallar-- > 0 ? { error: { message: "57014" } } : { data: 1, error: null }; } };
const timers = []; const setTimeout = (fn) => { timers.push(fn); return timers.length; }; const clearTimeout = () => {};
const api = new Function("localStorage", "supabase", "setTimeout", "clearTimeout", body)(localStorage, supabase, setTimeout, clearTimeout);
const tick = () => new Promise((r) => global.setTimeout(r, 10));
(async () => {
  api.rcpOcEncolar("Blist-Pack", [{ cod: "764", cajas: 19 }]);
  await tick();
  chk(llamadas === 1 && api.rcpOcLeer().length === 1, "falla la 1.ª vez: queda en la cola");
  // "se cierra la app": se pierde el timer, la cola sigue en localStorage
  chk(JSON.parse(store.rcp_oc_pend_v1).length === 1, "la cola vive en localStorage (sobrevive al cierre)");
  let vueltas = 0;
  while (api.rcpOcLeer().length && vueltas < 10) { const t = timers.shift(); if (!t) break; t(); await tick(); vueltas++; }
  chk(llamadas === 5 && api.rcpOcLeer().length === 0, "reintenta hasta que entra (5.ª llamada) y la cola queda vacía (llamadas " + llamadas + ")");
  chk(timers.length === 0, "vacía la cola, no programa más reintentos");
  if (fallos.length) { console.log("\nFALLARON " + fallos.length); process.exit(1); }
  console.log("\nrcp-oc-reintento OK");
})();
