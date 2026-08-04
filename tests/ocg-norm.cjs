/* Test de regresión (v5.17, hallazgo ALTA de la auditoría SE): el generador de OCs
   (ocgEnter) tiene que cruzar máximos ↔ stock ↔ demanda ↔ proyección ↔ capacidad con
   LA MISMA normalización de código (_ocgNorm = upper + sin ceros a la izquierda).
   Fixture: el máximo dice "007"/"066" pero el stock está cargado como "7"/"66" y la
   capacidad como "66". Si alguna pata vuelve a cruzar sin normalizar, el stock da 0
   silencioso y el generador sobre-pide → este test falla. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    // Stubs: son bindings léxicos globales (function/let), se reasignan SIN window.
    ocgFetchMaximos = async () => [
      { cod: "007", descripcion: "test A", max_cajas: 100, proveedor: "PROV", indice: null },
      { cod: "066", descripcion: "test B", max_cajas: 50, proveedor: "PROV", indice: null }
    ];
    stockFetchMovs = async () => [
      { cod_art: "7", deposito: "terminado", delta: 50, tipo: "inicial", ts: "2026-06-30T00:00:00Z" },
      // v7.17: "a guardar" TAMBIÉN es stock disponible para el generador (7 → 50+10=60)
      { cod_art: "7", deposito: "a_guardar", delta: 10, tipo: "inicial", ts: "2026-06-30T00:00:00Z" },
      { cod_art: "66", deposito: "terminado", delta: 20, tipo: "inicial", ts: "2026-06-30T00:00:00Z" },
      // pickeado / a facturar: NO cuentan como disponible
      { cod_art: "66", deposito: "separar_pedidos", delta: 40, tipo: "inicial", ts: "2026-06-30T00:00:00Z" },
      { cod_art: "66", deposito: "a_facturar", delta: 30, tipo: "inicial", ts: "2026-06-30T00:00:00Z" }
    ];
    stockGetCutoff = async () => null;
    ocgDemanda = async () => ({});
    ocgFetchProyeccion = async () => ({});
    ocgFetchCapacidad = async () => ({ "66": 30 });
    _oc = { view: "gen", gen: null, rows: [] };
    ocRender = function () {};   // sin DOM del modal
    await ocgEnter();
    const items = (_oc.gen && _oc.gen.items) || [];
    const A = items.find((i) => i.cod === "007"), B = items.find((i) => i.cod === "066");
    return {
      A_stock: A ? A.stock : null, A_falta: A ? A.falta : null,                       // esperado 60 / 40
      B_stock: B ? B.stock : null, B_capped: B ? B.capped : null, B_falta: B ? B.falta : null,  // esperado 20 / true / 10
      error: (_oc.gen && _oc.gen.error) || null
    };
  });
  const pass = r.A_stock === 60 && r.A_falta === 40 && r.B_stock === 20 && r.B_capped === true && r.B_falta === 10 && !r.error && errs.length === 0;
  console.log("ocg-norm:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  // v7.17 — la DEMANDA del generador netea los pedidos ya pickeados (tanda con TP).
  // (recarga: la fase 1 dejó ocgDemanda stubeada)
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r2 = await p.evaluate(async () => {
    supaFetchAll = async (url, q) => {
      if (String(url).indexOf("PPP_Programacion_Diaria") >= 0)
        return [{ np: "9001", tanda: "C10A" }, { np: "9002", tanda: "C10B" }, { np: "9003", tanda: "C10C" }];
      if (String(url).indexOf("PPP_Base_Pedidos") >= 0) return [];
      if (String(q || "").indexOf("opcion=eq.TP") >= 0) return [{ texto: "c10b" }];   // C10B ya pickeada
      return [];
    };
    supaFetchAll.__ppp = true;
    fetchPickingBase = async () => new Map([
      ["9001", [{ art: "500", cajas: 5 }]],
      ["9002", [{ art: "500", cajas: 7 }]],   // pickeada → NO cuenta
      ["9003", [{ art: "500", cajas: 3 }]]
    ]);
    const todo   = await ocgDemanda(false, false);   // como el resto de la app
    const neteda = await ocgDemanda(false, true);    // como el generador de OCs
    return { todo: todo["500"], neteada: neteda["500"] };
  });
  if (r2.todo !== 15 || r2.neteada !== 8) {
    console.error("ocg-norm: FALLÓ el neteo de demanda → " + JSON.stringify(r2) + " (esperado todo=15, neteada=8)");
    await b.close(); process.exit(1);
  }
  console.log("ocg-norm: demanda neteada OK (sin pickeadas 8 de 15)");

  await b.close();
  process.exit(pass ? 0 : 1);
})();
