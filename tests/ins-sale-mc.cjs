/* v24.69 (Thomas, 30/09, D11) — un insumo con MC (Insumos_Factores) SALE siempre en MC enteras:
   "lo mínimo que se le manda es 1 MC… no bajan uni sueltas, siempre por MC". El stock queda en la
   unidad base y el movimiento deja escrito lo que se cargó ("cargado 3 MC × 4000").
   Verifica: (a) en Entrega (EI) el pop-up abre fijo en MC; (b) aunque el ítem traiga "Uni", sale en
   MC; (c) el movimiento va en base (−12.000 Uni) con la nota; (d) en Recepción (RI) no se fuerza MC;
   (e) un insumo sin MC (plástico) no se toca. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    window.alert = function () {}; window.confirm = function () { return true; };
    const moved = []; window.stockMove = function (rows) { moved.push.apply(moved, rows); };
    window.fetch = function () { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve([]); } }); };
    const body = document.createElement("div"); body.id = "insBody"; document.body.appendChild(body);
    _insFactores = { "505C": { base: "Uni", unis: [{ u: "Uni", f: 1, base: true }, { u: "MC", f: 4000, base: false }] } };
    const out = {};
    _ins = { mode: "EI", legajo: "104", items: [
      { cod: "505C", nombre: "cuchilla", cat: "importados", qty: 0, unidad: "Uni", stock: 0, stockByUni: [] },
      { cod: "PP", nombre: "polipropileno", cat: "plastico", qty: 0, unidad: "Bolsas", stock: 0, stockByUni: [] }
    ], cat: "", filtro: "", qty: null };
    insOpenQty(0);
    out.a = _ins.items[0].unidad === "MC" && /sale siempre en MC/.test(body.innerHTML);
    insOpenQty(1);
    out.e = _ins.items[1].unidad === "Bolsas";
    _ins.qty = null;
    _ins.items[0].qty = 3; _ins.items[0].unidad = "Uni";   // (b) quedó otra unidad cargada antes
    await insConfirmar();
    const m = moved.filter(function (x) { return x.cod_art === "505C"; })[0] || {};
    out.b = !!m.cod_art;
    out.c = Number(m.delta) === -12000 && m.unidad === "Uni" && /cargado 3 MC × 4000/.test(m.descripcion || "");
    _ins = { mode: "RI", legajo: "104", items: [{ cod: "505C", nombre: "cuchilla", cat: "importados", qty: 0, unidad: "Uni", stock: 0, stockByUni: [] }], cat: "", filtro: "", qty: null };
    insOpenQty(0);
    out.d = _ins.items[0].unidad === "Uni";
    out.mov = m;
    return out;
  });
  const pass = r.a && r.b && r.c && r.d && r.e && errs.length === 0;
  console.log("ins-sale-mc:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
