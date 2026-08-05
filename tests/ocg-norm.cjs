/* Test de regresión del generador de OCs (v7.68). Desde v7.68 TODO el cálculo (universo
   desde stock, Máximo = proy×índice o capacidad, stock con empresa LK/CH mergeada, pedidos)
   vive en la vista Supabase vista_generador_oc; ocgEnter solo la lee y arma los ítems +
   reparto por proveedor. Este test stubea el fetch de la vista y verifica el armado:
   - pasa stock/falta/capped tal cual,
   - parte los duales por proporción (P2 = resto),
   - muestra "(sin proveedor)" con su flag (no se envía, pero se ve),
   - excluye Racks.
   Part 2: la DEMANDA (ocgDemanda) netea los pedidos ya pickeados (tanda con TP). Sale 1 si falla. */
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
    // Stub del fetch de la vista (bindings léxicos globales, se reasignan SIN window).
    supaFetchAllSafe = async (url) => {
      if (String(url).indexOf("vista_generador_oc") >= 0) return [
        { cod: "031", descripcion: "A", proveedor: "Poly", tiene_prov_real: true, pr1: 100, proveedor2: null, pr2: 0, indice: 1.5, proy: 100, cap: 0, maximo: 150, pedidos: 0, stock: 60, uni_x_caja: 24, n_caja: 1, total: 90 },
        { cod: "066", descripcion: "B", proveedor: "PROV", tiene_prov_real: true, pr1: 100, proveedor2: null, pr2: 0, indice: 1.5, proy: 100, cap: 30, maximo: 30, pedidos: 0, stock: 20, uni_x_caja: 12, n_caja: 2, total: 10 },
        { cod: "123", descripcion: "Dual", proveedor: "Garcia", tiene_prov_real: true, pr1: 50, proveedor2: "Lucho", pr2: 50, indice: 1.5, proy: 120, cap: 0, maximo: 164, pedidos: 0, stock: 70, uni_x_caja: 12, n_caja: 3, total: 94 },
        { cod: "580", descripcion: "SinProv", proveedor: "(sin proveedor)", tiene_prov_real: false, pr1: 100, proveedor2: null, pr2: 0, indice: 1.5, proy: 0, cap: 66, maximo: 66, pedidos: 0, stock: 65, uni_x_caja: 0, n_caja: null, total: 1 },
        { cod: "809E", descripcion: "Racks", proveedor: "Racks", tiene_prov_real: true, pr1: 100, proveedor2: null, pr2: 0, indice: 1.5, proy: 50, cap: 0, maximo: 75, pedidos: 0, stock: 0, uni_x_caja: 12, n_caja: 4, total: 75 }
      ];
      return [];
    };
    _oc = { view: "gen", gen: null, rows: [] };
    ocRender = function () {};   // sin DOM del modal
    await ocgEnter();
    const items = (_oc.gen && _oc.gen.items) || [];
    const A = items.find((i) => i.cod === "031"), B = items.find((i) => i.cod === "066");
    const dual = items.filter((i) => i.cod === "123");
    const sin = items.find((i) => i.cod === "580");
    const racks = items.find((i) => i.cod === "809E");
    return {
      A_stock: A ? A.stock : null, A_falta: A ? A.falta : null, A_capped: A ? A.capped : null,       // 60 / 90 / false
      B_stock: B ? B.stock : null, B_capped: B ? B.capped : null, B_falta: B ? B.falta : null,       // 20 / true / 10
      dualN: dual.length, dualGarcia: (dual.find((i) => i.prov === "Garcia") || {}).falta, dualLucho: (dual.find((i) => i.prov === "Lucho") || {}).falta,  // 2 / 47 / 47
      sinProv: sin ? sin.prov : null, sinFlag: sin ? !!sin.sinProv : null,                            // "(sin proveedor)" / true
      racksExcl: !racks,                                                                              // true (Racks afuera)
      error: (_oc.gen && _oc.gen.error) || null
    };
  });
  const pass = r.A_stock === 60 && r.A_falta === 90 && r.A_capped === false &&
    r.B_stock === 20 && r.B_capped === true && r.B_falta === 10 &&
    r.dualN === 2 && r.dualGarcia === 47 && r.dualLucho === 47 &&
    r.sinProv === "(sin proveedor)" && r.sinFlag === true && r.racksExcl === true &&
    !r.error && errs.length === 0;
  console.log("ocg-norm:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  if (!pass) { await b.close(); process.exit(1); }

  // v7.18 — la DEMANDA del generador netea los pedidos ya pickeados (tanda con TP).
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
