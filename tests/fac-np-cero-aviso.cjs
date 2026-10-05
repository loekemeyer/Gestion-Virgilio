// v27.02 (Luis, 05/10): al bajar el Excel ISIS, una NP marcada en 0 cajas (todo faltó)
// no entra al archivo ni queda facturada: se AVISA, se le saca el tilde y sigue en la lista.
// Corre facXlsBajar de verdad con _facXlsArmar simulado.
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const i = src.indexOf("async function facXlsBajar(");
const j = src.indexOf("\n}\n", i);
const fn = Buffer.from(src.slice(i, j + 2), "latin1").toString("utf8");
let fallos = 0; const ok = (c, m) => { console.log((c ? "OK  " : "FAIL") + " " + m); if (!c) fallos++; };
async function correr(filasNps) {
  const ctx = { alerts: [], marcadas: [], descargas: 0 };
  ctx._facXlsSel = new Set(["LK 0001", "LK 0002"]);
  Object.assign(ctx, {
    requireSupervisor: () => true, facNpEsWeb: () => true, facXlsBtnSync() {},
    facAuthWriteHeaders: async () => ({}), authNoSesionMsg: (s) => s,
    document: { getElementById: () => null }, alert: (m) => ctx.alerts.push(m), confirm: () => true,
    _facXlsArmar: async () => filasNps.map((np) => ({ np, isisEmp: "LK", lineas: [{ art: "501", cajas: 3 }] })),
    FAC_XLS_FORMATO: "xlsx", _facXlsDescargarXlsx: () => { ctx.descargas++; return {}; }, facDescRegistrar: async () => {},
    facInfoNp: (np) => ({ np }), facMarcarFacturada: async (a) => { ctx.marcadas.push(a.np); return true; },
    facShowToast() {}, setTimeout: () => {}, facRender() {}, _facLastTandas: [], Promise, Set, Array, String,
  });
  vm.createContext(ctx); vm.runInContext(fn + "\nthis._run = facXlsBajar;", ctx);
  await ctx._run(); return ctx;
}
(async () => {
  let c = await correr(["LK 0001"]);
  ok(c.marcadas.join() === "LK 0001", "sólo la NP con cajas queda facturada");
  ok(c.alerts.some((a) => /LK 0002/.test(a) && /0 cajas/.test(a) && /Cancelar/.test(a)), "avisa la NP en 0 cajas");
  ok(!c._facXlsSel.has("LK 0002"), "la NP en 0 pierde el tilde");
  ok(c.descargas === 1, "el Excel se baja igual con las otras");
  c = await correr([]);
  ok(c.marcadas.length === 0 && c.descargas === 0, "todas en 0: no baja ni factura");
  ok(c.alerts.some((a) => /LK 0001, LK 0002/.test(a)), "todas en 0: las nombra");
  process.exit(fallos ? 1 : 0);
})();
