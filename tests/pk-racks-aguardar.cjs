/* Regresión idea 5703 — al pickear FALTÓ un artículo (esp>real) pero HAY del mismo
   código en racks o en "a guardar" → stockBajaPicking emite el evento RAG (Telegram) y
   abre el pop-up al operario. Chequea la detección: sólo faltantes CON stock en
   racks/a_guardar, familia-aware (codBase), sin falsos positivos ni SSG. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const PKC = [
  { texto: "T1|100|10|7" },   // esp 10, real 7 → faltó 3 ; hay 5 en racks → HIT
  { texto: "T1|200|5|0"  },   // esp 5, real 0 → faltó 5 ; sin stock en otro dep → NO
  { texto: "T1|300|4|4"  },   // completo → NO
  { texto: "T1|400|8|5"  },   // esp 8, real 5 → faltó 3 ; hay 10 en a guardar → HIT
  { texto: "T2|100|9|1"  }    // otra tanda: no debe entrar
];
const MOVS = [
  { cod_art: "100", deposito: "terminado", tipo: "inicial", delta: 7,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "100", deposito: "racks",     tipo: "inicial", delta: 5,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "300", deposito: "terminado", tipo: "inicial", delta: 4,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "400", deposito: "terminado", tipo: "inicial", delta: 5,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "400", deposito: "a_guardar", tipo: "inicial", delta: 10, ts: "2026-08-01T12:00:00Z" }
  // 200: sin stock en ningún depósito
];

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async (fix) => {
    const out = {};
    let ragArg = null, ssgCalls = 0, popupCalls = 0;
    window.stockEmitRacksAguardar = function (tanda, legajo, arr) { ragArg = { tanda: tanda, legajo: legajo, arr: arr }; };
    window.showRacksAguardarPopup = function () { popupCalls++; };        // no abrir modal ni fetch de NPs
    window.stockEmitSinStock = function () { ssgCalls++; };
    window.stockGetCutoff = async function () { return null; };
    window.stockFetchMovs = async function () { return fix.MOVS.slice(); };
    window.fetch = function () { return Promise.resolve({ ok: true, json: function () { return Promise.resolve(fix.PKC.slice()); } }); };

    await stockBajaPicking("T1", "104");

    out.emitido = !!ragArg;
    out.popup = popupCalls;
    out.ssg = ssgCalls;                                  // no debe haber SSG (no se pickeó de más)
    const arr = (ragArg && ragArg.arr) || [];
    const byCod = {}; arr.forEach(function (x) { byCod[x.art] = x; });
    out.cods = Object.keys(byCod).sort();
    out.hit100 = byCod["100"] && byCod["100"].falto === 3 && byCod["100"].racks === 5 && byCod["100"].aguardar === 0;
    out.hit400 = byCod["400"] && byCod["400"].falto === 3 && byCod["400"].aguardar === 10 && byCod["400"].racks === 0;
    out.no200 = !byCod["200"];       // faltó pero no hay en racks/a guardar → no avisa
    out.no300 = !byCod["300"];       // completo → no avisa
    return out;
  }, { PKC: PKC, MOVS: MOVS });

  const pass = r.emitido && r.popup === 1 && r.ssg === 0 &&
    r.cods.length === 2 && r.hit100 && r.hit400 && r.no200 && r.no300 && errs.length === 0;
  console.log("pk-racks-aguardar:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
