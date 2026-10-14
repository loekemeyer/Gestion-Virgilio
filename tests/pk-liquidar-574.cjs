/* Regresión v30.29 — liquidar el 574 nacional dentro del picking del 574E (Luis, 14/10).

   Quedan 2 cajas de 574 en F50. El próximo picking que pida 574E (LK) levanta esas 2 del
   574 y el resto del 574E; cuando el saldo del 574 llega a 0, no se parte más.

   Chequea:
   - A: saldo 574 = 2, piden 5 de 574E → paso "574" con 2 y "574E" con 3.
   - B: saldo 574 = 2, piden 1 → paso "574" con 1 y el 574E salteado.
   - C: saldo 574 = 0 → picking normal, 574E con 5, sin paso 574.
   - D: la consulta del saldo falla → picking normal.
   - E: el total pedido no cambia (2 + 3 = 5).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {};
    const leg = "77";
    legajoInput.value = leg;
    const NP = "98001";   // Loeke
    let cajas = 5, saldo = 2, falla = false;
    window.fetchMonitorSheet = async function () { return new Map([["E99A", { tanda: "E99A", pedidos: [{ np: NP }] }]]); };
    window.fetchPickingBase = async function () { return new Map([[NP, [{ art: "502", cajas: 4 }, { art: "574E", cajas: cajas }]]]); };
    window.fetchCorrecciones = async function () { return new Map(); };
    window.supaFetchAllSafe = async function (url) {
      if (String(url).indexOf("vista_saldos_stock") >= 0) {
        if (falla) throw new Error("sin red");
        return [{ cod_art: "574", empresa: "LK", terminado: saldo }];
      }
      return [];
    };
    window.pwebAgregadoAviso = function () { return ""; };
    window.pkFetchExcedente = async function () { return {}; };
    window.gvFetchLugares = async function () { return { lista: [], set: new Set(), libres: new Set(), emp: {}, orden: {} }; };
    const correr = async function () {
      localStorage.removeItem("vir_pk_" + leg);
      await showPickingList("E99A", leg);
      await new Promise(function (res) { setTimeout(res, 60); });
      const m = {};
      (_pk && _pk.items || []).forEach(function (x) { m[x.key] = x.skip ? "skip" : x.esp; });
      return m;
    };
    const A = await correr();
    out.A = A["574"] === 2 && A["574E"] === 3 && _pk.items.filter(function (x) { return x.key === "574"; })[0].liqDe === "574E";
    out.E_total = (A["574"] + A["574E"]) === 5;
    out.A_orden = _pk.items.map(function (x) { return x.key; }).join(",") === "502,574E,574";
    cajas = 1;
    const B = await correr();
    out.B = B["574"] === 1 && B["574E"] === "skip";
    cajas = 5; saldo = 0;
    const C = await correr();
    out.C = C["574E"] === 5 && !("574" in C);
    saldo = 2; falla = true;
    const D = await correr();
    out.D = D["574E"] === 5 && !("574" in D);
    return out;
  });

  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("pk-liquidar-574:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
