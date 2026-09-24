// v22.40 (Luis, 24/09) — la recepción NO puede tirar el error de gv_oc_aplicar_recepcion sin mirar.
// supabase.rpc resuelve con {error} ante un 500: el reintento tiene que mirar r.error, no sólo el reject.
// Corre el bloque de verdad con un supabase falso que falla la primera vez.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../recepcion.js", "utf8");
const i = src.indexOf("const _ocArgs"), j = src.indexOf("_ocAplicar(0);", i);
const fallos = [];
const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fallos.push(m); };
chk(i > 0 && j > i, "el bloque de reintento existe");
chk(!/gv_oc_aplicar_recepcion"[\s\S]{0,300}\.then\(function \(\) \{\}, function \(\) \{\}\)/.test(src), "ya no se descarta el resultado sin mirar");
if (i > 0 && j > i) {
  const body = src.slice(i, j + "_ocAplicar(0);".length);
  let llamadas = 0;
  const supabase = { rpc: () => { llamadas++; return Promise.resolve(llamadas === 1 ? { error: { message: "timeout" } } : { data: 1, error: null }); } };
  const opState = { tallNombre: "Blist-Pack" }, items = [{ cod: "764", cajas: 19 }];
  const timers = []; const setTimeout = (fn) => timers.push(fn);
  new Function("supabase", "opState", "items", "setTimeout", body)(supabase, opState, items, setTimeout);
  (async () => {
    await new Promise((r) => global.setTimeout(r, 20));
    chk(llamadas === 1 && timers.length === 1, "con {error} programa un reintento");
    timers.shift()(); await new Promise((r) => global.setTimeout(r, 20));
    chk(llamadas === 2 && timers.length === 0, "el reintento llama de nuevo y, si sale bien, no sigue");
    if (fallos.length) { console.log("\nFALLARON " + fallos.length); process.exit(1); }
    console.log("\nrcp-oc-reintento OK");
  })();
} else { console.log("\nFALLARON " + fallos.length); process.exit(1); }
