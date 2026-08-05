/* Regresión v7.71 — la tabla de Stock OCULTA la fila del código BASE de una familia empresa-split
   (ej. "438E") cuando no tiene stock propio y la familia sí tiene stock en LK/CH. El stock vive en
   "438E LK"/"438E CH"; sin esto quedaba una fila fantasma (base 0 stock + cajas pedidas). Un base
   CON stock propio (437E) NO se oculta.

   Chequea:
   - "438E" base (0 stock, demanda 37, familia 438E LK/CH con stock) → OCULTA.
   - "439E" base (0 stock, demanda 28, familia 439E LK con stock) → OCULTA.
   - "438E LK", "438E CH", "439E LK" → se ven.
   - "437E" base (stock propio 36) → se ve.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const ts = "2026-08-01T10:00:00Z";
    const movs = [
      { cod_art: "438E LK", deposito: "terminado", delta: 44, tipo: "inicial", ts: ts },
      { cod_art: "438E CH", deposito: "terminado", delta: 18, tipo: "inicial", ts: ts },
      { cod_art: "439E LK", deposito: "terminado", delta: 29, tipo: "inicial", ts: ts },
      { cod_art: "437E",    deposito: "terminado", delta: 36, tipo: "inicial", ts: ts },   // base CON stock propio
      { cod_art: "437E LK", deposito: "terminado", delta: 100, tipo: "inicial", ts: ts }
    ];
    // demanda sobre los códigos BASE (así entran a la tabla como fila con 0 stock)
    _stk = { movs: movs, cutoff: 0, dem: { "438E": 37, "439E": 28, "437E": 22 }, cap: [], fcs: {}, gConf: [], filtro: "", openArt: null, soloNeg: false };
    const html = stkBodyStocks();

    out.veLK438 = html.indexOf('stk-cod">438E LK<') >= 0;
    out.veCH438 = html.indexOf('stk-cod">438E CH<') >= 0;
    out.veLK439 = html.indexOf('stk-cod">439E LK<') >= 0;
    out.ocultaBase438 = html.indexOf('stk-cod">438E<') < 0;   // base sin sufijo → oculto
    out.ocultaBase439 = html.indexOf('stk-cod">439E<') < 0;
    out.ve437base = html.indexOf('stk-cod">437E<') >= 0;      // base CON stock propio → se ve
    out.veLK437 = html.indexOf('stk-cod">437E LK<') >= 0;
    return out;
  });
  const pass = r.veLK438 && r.veCH438 && r.veLK439 && r.ocultaBase438 && r.ocultaBase439 &&
    r.ve437base && r.veLK437 && errs.length === 0;
  console.log("stk-base-split-oculta:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
