/* Regresión — evento FGU (idea del usuario): al pickear FALTÓ (esp>real) pero la GÓNDOLA
   (familia, disponible a esa tanda) tenía AL MENOS lo pedido → aviso URGENTE a Telegram.
   - 500: góndola 40, pidió 10, puso 4 (faltó 6) → SÍ FGU (había 40 en góndola).
   - 600: góndola 5, pidió 10, puso 3 (faltó 7) → NO FGU (góndola corta = escasez legítima).
   - 700: góndola 50, pidió 10, puso 10 (sin faltante) → NO FGU.
   - 800: góndola 3 pero racks 100, pidió 10, puso 2 → NO FGU (góndola corta) pero SÍ RAG.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const PKC = [
  { texto: "TFGU|500|10|4" },
  { texto: "TFGU|600|10|3" },
  { texto: "TFGU|700|10|10" },
  { texto: "TFGU|800|10|2" }
];
const MOVS = [
  { cod_art: "500", deposito: "terminado", tipo: "inicial", delta: 40,  ts: "2026-08-01T16:00:00Z" },
  { cod_art: "600", deposito: "terminado", tipo: "inicial", delta: 5,   ts: "2026-08-01T16:00:00Z" },
  { cod_art: "700", deposito: "terminado", tipo: "inicial", delta: 50,  ts: "2026-08-01T16:00:00Z" },
  { cod_art: "800", deposito: "terminado", tipo: "inicial", delta: 3,   ts: "2026-08-01T16:00:00Z" },
  { cod_art: "800", deposito: "racks",     tipo: "inicial", delta: 100, ts: "2026-08-01T16:00:00Z" }
];

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async (fix) => {
    const out = {}, fgu = [], rag = [], ssg = [];
    window.stockEmitFaltanteGondola = function (t, l, arr) { fgu.push(arr.slice()); };
    window.stockEmitRacksAguardar   = function (t, l, arr) { rag.push(arr.slice()); };
    window.stockEmitSinStock        = function (t, l, arr) { ssg.push(arr.slice()); };
    window.showRacksAguardarPopup   = function () {};
    window.stockGetCutoff = async function () { return null; };
    window.stockFetchMovs = async function () { return fix.MOVS.slice(); };
    window.fetch = function () { return Promise.resolve({ ok: true, json: function () { return Promise.resolve(fix.PKC.slice()); } }); };
    await stockBajaPicking("TFGU", "122");
    const f = fgu.length ? fgu[0] : [];
    const has = (arr, cod) => arr.some(function (x) { return String(x.art) === cod; });
    out.fguArts = f.map(function (x) { return x.art + ":" + x.falto + ":" + x.gond; });
    out.fires500 = has(f, "500");
    out.gond500ok = f.some(function (x) { return x.art === "500" && x.gond === 40 && x.falto === 6; });
    out.not600 = !has(f, "600");
    out.not700 = !has(f, "700");
    out.not800 = !has(f, "800");
    out.rag800 = rag.length > 0 && rag[0].some(function (x) { return String(x.art) === "800"; });
    out.noSsg = ssg.length === 0;   // ninguno pickeó MÁS de lo disponible
    return out;
  }, { MOVS: MOVS, PKC: PKC });

  const checks = [
    ["FGU dispara 500 (había góndola)", r.fires500],
    ["FGU 500 trae falto=6 y gond=40", r.gond500ok],
    ["FGU NO dispara 600 (góndola corta)", r.not600],
    ["FGU NO dispara 700 (sin faltante)", r.not700],
    ["FGU NO dispara 800 (góndola corta, stock en racks)", r.not800],
    ["800 va por RAG (racks), no por FGU", r.rag800],
    ["ningún SSG (no pickearon de más)", r.noSsg],
  ];
  const pass = checks.every((c) => c[1]) && errs.length === 0;
  console.log("fgu-faltante-gondola:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none");
  checks.forEach((c) => console.log("  " + (c[1] ? "✓" : "✗") + " " + c[0]));
  console.log(pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
