/* v25.89 (Luis, 01/10) — Bajar de Racks ordena por URGENCIA: primero la góndola más vacía contando
   lo que ya está en A guardar y restando lo pedido ((góndola + a guardar − pedido) ÷ capacidad),
   igual que Guardado a Góndola. Sin capacidad, al final. Sale 1 si falla.
   v29.58 (Luis, 13/10) — dos cosas más, y el test las mide corriendo la pantalla:
     (a) el DUAL encuentra su capacidad por (cod, empresa): `vista_saldos_stock` emite "437E LK" y
         Capacidad_Sector el código pelado, así que el dual caía en prio = Infinity y último;
     (b) los que NO tienen capacidad cargada van al final ordenados por ESTADÍSTICA MADRE (desc). */
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
  const r = await p.evaluate(async () => {
    window.stockFetchSaldos = async function () { return {
      "501": { cod: "501", racks: 50, terminado: 90, a_guardar: 0 },      // (90+0-0)/100 = 0,90
      "502": { cod: "502", racks: 50, terminado: 10, a_guardar: 70 },     // (10+70)/100 = 0,80
      "503": { cod: "503", racks: 50, terminado: 40, a_guardar: 0 },      // (40-30)/100 = 0,10 (pedidos)
      "504": { cod: "504", racks: 50, terminado: 0, a_guardar: 0 },       // sin capacidad → al final, E.M. 5
      "505": { cod: "505", racks: 50, terminado: 20, a_guardar: 0 },      // 0,20
      "938E": { cod: "938E", racks: 228, terminado: 0, a_guardar: 12 },   // sin capacidad → al final, E.M. 300
      "437E LK": { cod: "437E LK", racks: 225, terminado: 72, a_guardar: 0 } };  // (72-16)/120 = 0,47 — DUAL
    };
    window.loadArtNombres = async function () {};
    window.rkbFetchCxM = async function () { return { cxm: {}, locs: {} }; };
    window.stockFetchArtFactors = async function () { return {}; };
    // v29.58: la capacidad trae las dos claves; la del dual vive por empresa (437E: LK 120 / CH 48).
    window.rkbFetchCapacidad = async function () { return {
      pelada: { "501": 100, "502": 100, "503": 100, "505": 100, "437E": 168 },
      porEmp: { "437E LK": 120, "437E CH": 48 } }; };
    window.ocgDemanda = async function () { return { "503": 30, "437E LK": 16 }; };
    window.ocgFetchProyeccion = async function () { return { "504": 5, "938E": 300 }; };
    window.gvRacksTramo = function () {};
    await showRacksBajarModal("777");
    return { orden: _rkb.items.map(function (it) { return it.cod; }).join(","),
             capDual: (_rkb.items.filter(function (it) { return it.cod === "437E LK"; })[0] || {}).cap };
  });
  const okOrden = r.orden === "503,505,437E LK,502,501,938E,504";
  const okDual = r.capDual === 120;   // la del LK, NO los 168 de las dos empresas pegados
  const ok = okOrden && okDual && errs.length === 0;
  console.log("rkb-orden-urgencia:", r.orden, "| cap 437E LK:", r.capDual,
    errs.length ? errs.join("|") : "", ok ? "✓ OK" : "✗ FAIL (esperado 503,505,437E LK,502,501,938E,504 y cap 120)");
  await b.close(); process.exit(ok ? 0 : 1);
})();
