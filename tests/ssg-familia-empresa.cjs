/* Regresión v7.04 — el aviso SSG NO debe dispararse por un código PARTIDO POR EMPRESA
   cuando el stock está bajo el sufijo ("437E LK") pero el PKC guarda el pelado ("437E").

   Caso real (D05D, legajo 122): PKC "D05D|437E|1|1". El stock de 437E en góndola vive en
   "437E LK" (61 cajas) y "437E CH" (27), el pelado "437E" tiene 0 en góndola. Antes el
   chequeo miraba sal["437E"].terminado = 0 → SSG falso "tenía 0". El fix suma la familia
   (codBase): 61 + 27 = 88 ≥ 1 → NO avisa. El cron ya descuenta de 437E LK por la NP.

   Control: un código partido donde la familia entera NO alcanza SÍ debe avisar. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const PKC = [
  { texto: "D05D|437E|1|1" },    // pelado; stock está en 437E LK/CH → NO debe avisar
  { texto: "D05D|888E|10|10" }   // pelado; familia entera tiene 3 → SÍ debe avisar
];
const MOVS = [
  // 437E: góndola sólo en las variantes de empresa (el pelado en 0)
  { cod_art: "437E LK", deposito: "terminado", tipo: "inicial", delta: 61, ts: "2026-08-01T16:00:00Z" },
  { cod_art: "437E CH", deposito: "terminado", tipo: "inicial", delta: 27, ts: "2026-08-01T16:00:00Z" },
  { cod_art: "437E",    deposito: "racks",     tipo: "inicial", delta: 258, ts: "2026-08-01T16:00:00Z" },
  // 888E: familia entera = 3 en góndola, se pickean 10 → sin stock de verdad
  { cod_art: "888E LK", deposito: "terminado", tipo: "inicial", delta: 2, ts: "2026-08-01T16:00:00Z" },
  { cod_art: "888E CH", deposito: "terminado", tipo: "inicial", delta: 1, ts: "2026-08-01T16:00:00Z" }
];

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async (fix) => {
    const out = {}, emitidos = [];
    window.stockEmitSinStock = function (tanda, legajo, negArr) { emitidos.push(negArr.slice()); };
    window.stockGetCutoff = async function () { return null; };
    window.stockFetchMovs = async function () { return fix.MOVS.slice(); };
    window.fetch = function () { return Promise.resolve({ ok: true, json: function () { return Promise.resolve(fix.PKC.slice()); } }); };
    await stockBajaPicking("D05D", "122");
    const neg = emitidos.length ? emitidos[0] : [];
    out.neg = neg.slice();
    out.no437E = !neg.some(function (s) { return s.indexOf("437E:") === 0; });   // familia LK+CH cubre → no avisa
    out.si888E = neg.some(function (s) { return s.indexOf("888E:") === 0; });     // familia no alcanza → avisa
    out.emitidos = emitidos.length;
    return out;
  }, { MOVS: MOVS, PKC: PKC });

  const pass = r.no437E && r.si888E && errs.length === 0;
  console.log("ssg-familia-empresa:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
