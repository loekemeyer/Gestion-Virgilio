/* v25.89 (Luis, 01/10) — Bajar de Racks ordena por URGENCIA: primero la góndola más vacía contando
   lo que ya está en A guardar y restando lo pedido ((góndola + a guardar − pedido) ÷ capacidad),
   igual que Guardado a Góndola. Sin capacidad, al final. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const errs = [];
  const p = await b.newPage({ viewport: { width: 390, height: 800 } });
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (rt) => rt.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const orden = await p.evaluate(async () => {
    window.stockFetchSaldos = async function () { return {
      "501": { cod: "501", racks: 50, terminado: 90, a_guardar: 0 },   // (90+0-0)/100 = 0,90
      "502": { cod: "502", racks: 50, terminado: 10, a_guardar: 70 },  // (10+70)/100 = 0,80
      "503": { cod: "503", racks: 50, terminado: 40, a_guardar: 0 },   // (40-30)/100 = 0,10 (pedidos)
      "504": { cod: "504", racks: 50, terminado: 0, a_guardar: 0 },    // sin capacidad → al final
      "505": { cod: "505", racks: 50, terminado: 20, a_guardar: 0 } }; };   // 0,20
    window.loadArtNombres = async function () {};
    window.rkbFetchCxM = async function () { return { cxm: {}, locs: {} }; };
    window.stockFetchArtFactors = async function () { return {}; };
    window.ocgFetchCapacidad = async function () { return { "501": 100, "502": 100, "503": 100, "505": 100 }; };
    window.ocgDemanda = async function () { return { "503": 30 }; };
    window.gvRacksTramo = function () {};
    await showRacksBajarModal("777");
    return _rkb.items.map(function (it) { return it.cod; }).join(",");
  });
  const ok = orden === "503,505,502,501,504" && errs.length === 0;
  console.log("rkb-orden-urgencia:", orden, errs.length ? errs.join("|") : "", ok ? "✓ OK" : "✗ FAIL (esperado 503,505,502,501,504)");
  await b.close(); process.exit(ok ? 0 : 1);
})();
