/* v28.61 (Luis, 08/10) — "si la OC es menor a 10 cajas, sólo puede pedirse si hay menos que 30 % de góndola".
   Corre ocgEnter con la vista y la RPC mockeadas: el código frenado queda con a pedir 0 (no se genera) y se lista
   arriba; el que no está frenado sigue igual. Si la RPC falla, lo dice. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; let falla = false;
    const V = [{ cod: "769", descripcion: "Bombilla", proveedor: "Blistpack", tiene_prov_real: true, pr1: 100, indice: 1.5, proy: 4, cap: 24, maximo: 6, pedidos: 0, stock: 0, uni_x_caja: 12, n_caja: 1, total: 6 },
               { cod: "715", descripcion: "Cierra", proveedor: "Log/ Fabr", tiene_prov_real: true, pr1: 100, indice: 1.5, proy: 4, cap: 36, maximo: 7, pedidos: 0, stock: 0, uni_x_caja: 12, n_caja: 1, total: 7 }];
    window.fetch = async (u) => {
      const J = (x) => ({ ok: true, status: 200, json: async () => x, headers: { get: () => null } });
      if (String(u).indexOf("gv_oc_chica_frenada") >= 0) return falla ? { ok: false, status: 500, json: async () => ({}) } : J([{ cod: "769", total: 6, terminado: 44, cap: 24, pct: 183 }]);
      if (String(u).indexOf("vista_generador_oc") >= 0) return J(V);
      return J([]);
    };
    window.ocRender = () => {}; window.ocgCargarAuto = async () => {}; window.ocgStartCountdown = () => {}; window.ocgFetchImportados = async () => null;
    _oc = { view: "gen" };
    await ocgEnter();
    out.genCods = _oc.gen.items.map((x) => x.cod);
    out.nota = ocgChicaNota(_oc.gen);
    falla = true; _oc = { view: "gen" }; await ocgEnter();
    out.err = ocgChicaNota(_oc.gen);
    out.genSinRpc = _oc.gen.items.map((x) => x.cod);
    return out;
  });
  const pass = JSON.stringify(r.genCods) === '["715"]' && /769/.test(r.nota) && /30 %/.test(r.nota) && /No pude leer/.test(r.err) && r.genSinRpc.length === 2 && !errs.length;
  console.log("oc-chica-gondola:", JSON.stringify(r), errs.join("|"), pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
