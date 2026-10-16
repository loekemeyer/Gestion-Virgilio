/* Regresión v31.69 — la liquidación del 574 ya NO se hace en el picking (Luis, 16/10).

   v30.29 partía el picking (574 + 574E) con la NP en 574E: se armaba y FACTURABA 574E. Desde
   la v31.69 la liquidación cambia la NP (gv_web_np_liquidar → GV_NP_Cambio_Codigo) y el picking
   pide lo que dice la NP, sin mirar el saldo del viejo.

   Chequea:
   - A: saldo 574 = 2, la NP pide 5 de 574E → picking 574E con 5, sin paso 574 (no se parte).
   - B: la NP ya viene cambiada (574: 2 + 574E: 3) → pasos 574 con 2 y 574E con 3.
   - C: saldo 574 = 0 → 574E con 5.
   - D: la consulta del saldo falla → 574E con 5.
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
    let cajas = 5, saldo = 2, falla = false, cambiada = false;
    window.fetchMonitorSheet = async function () { return new Map([["E99A", { tanda: "E99A", pedidos: [{ np: NP }] }]]); };
    window.fetchPickingBase = async function () { return new Map([[NP, cambiada
      ? [{ art: "502", cajas: 4 }, { art: "574", cajas: 2 }, { art: "574E", cajas: 3 }]
      : [{ art: "502", cajas: 4 }, { art: "574E", cajas: cajas }]]]); };
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
    out.A = A["574E"] === 5 && !("574" in A);
    cambiada = true;
    const B = await correr();
    out.B = B["574"] === 2 && B["574E"] === 3 && _pk.items.every(function (x) { return !x.liqDe; });
    cambiada = false; saldo = 0;
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
