/* v23.86 (Luis) — la botonera de tandas del celular va ordenada POR CAMIÓN dentro de cada día:
   1° el camión con más m³ (orden_camion de gv_monitor_tanda_camion), después el siguiente.
   Así primero se arma un camión entero y, si no llegan, se patea uno solo.
   Chequea: 1) orden por camión y no alfabético; 2) rótulo "🚚 N° · camión" sólo en el día con
   más de un camión; 3) sin el dato (vista caída) vuelve al orden alfabético sin rótulos.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    window.getPppTandasForOperator = async () => [
      ["A01A", "2026-09-30"], ["B02A", "2026-09-30"], ["C03A", "2026-09-30"], ["D04A", "2026-09-30"],
      ["Z09A", "2026-10-01"], ["Y08A", "2026-10-01"]
    ].map(([t, f]) => ({ tanda: t, fechaRaw: f, fechaDisplay: f.slice(8) + "/" + f.slice(5, 7), m3: 1 }));
    const CAM = { A01A: ["GBA Sur", 2], B02A: ["Capital Oeste", 1], C03A: ["GBA Sur", 2], D04A: ["Capital Oeste", 1],
                  Z09A: ["Capital Sur", 1], Y08A: ["Capital Sur", 1] };
    window.monCargarCamiones = async function () {
      _monCamionDe = new Map(Object.entries(CAM).map(([k, v]) => [k, v[0]]));
      _monCamionOrden = new Map(Object.entries(CAM).map(([k, v]) => [k, v[1]]));
      return _monCamionDe;
    };
    const leer = () => [...document.querySelectorAll("#tandasList .tandas-day-group")].map(g =>
      [...g.querySelectorAll(".tandas-cam-lbl, .tanda-chip")].map(x => x.classList.contains("tandas-cam-lbl") ? "|" + x.textContent.trim() : x.dataset.code));
    await populateTandasList("all");
    const g = leer();
    out.dia1 = JSON.stringify(g[0]);
    out.ordenCamion = JSON.stringify(g[0]) === JSON.stringify(["|🚚 1° · Capital Oeste", "B02A", "D04A", "|🚚 2° · GBA Sur", "A01A", "C03A"]);
    out.unCamionSinRotulo = JSON.stringify(g[1]) === JSON.stringify(["Y08A", "Z09A"]);
    // vista caída → alfabético y sin rótulos
    window.monCargarCamiones = async function () { _monCamionDe = new Map(); _monCamionOrden = new Map(); return _monCamionDe; };
    _monCamionDe = new Map(); _monCamionOrden = new Map();
    await populateTandasList("all");
    out.sinDatoAlfabetico = JSON.stringify(leer()[0]) === JSON.stringify(["A01A", "B02A", "C03A", "D04A"]);
    return out;
  });
  const pass = ["ordenCamion", "unCamionSinRotulo", "sinDatoAlfabetico"].every(k => r[k]) && errs.length === 0;
  console.log("tandas-orden-camion:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
