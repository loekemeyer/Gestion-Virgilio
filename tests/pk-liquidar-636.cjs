/* Regresión v31.69 — 636E / 635E: la liquidación cambia la NP, no el picking (Luis, 16/10).

   v31.60 pickeaba 636 con la NP en 636E (se facturaba 636E, y encima 1:1 en cajas cuando el 636E
   es de 24 u y el 636 de 12 u). Ahora gv_web_np_liquidar cambia la NP y el picking pide lo que dice.

   Chequea:
   - A: 636 con 5 en góndola + 9 en excedente, la NP pide 20 de 636E → 636E con 20, sin paso 636.
   - B: la NP ya cambiada trae 636: 14 → paso 636·EXC con 9 y 636 con 5 (el excedente sale primero).
   - C: 636E en una NP de LK → 636E con 4.
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
    let NP = "CH 0099", lineas = [];
    window.fetchMonitorSheet = async function () { return new Map([["E99A", { tanda: "E99A", pedidos: [{ np: NP }] }]]); };
    window.fetchPickingBase = async function () { return new Map([[NP, lineas]]); };
    window.fetchCorrecciones = async function () { return new Map(); };
    window.supaFetchAllSafe = async function (url) {
      if (String(url).indexOf("vista_saldos_stock") >= 0)
        return [{ cod_art: "636", empresa: "CH", terminado: 5, excedente: 9 }, { cod_art: "635", empresa: "CH", terminado: 11, excedente: 0 }];
      return [];
    };
    window.pwebAgregadoAviso = function () { return ""; };
    window.pkFetchExcedente = async function (arts) {
      return arts.indexOf("636") >= 0 ? { "636": { cajas: 9, ubics: ["R1"] } } : {};
    };
    window.gvFetchLugares = async function () { return { lista: [], set: new Set(), libres: new Set(), emp: {}, orden: {} }; };
    const correr = async function () {
      localStorage.removeItem("vir_pk_" + leg);
      await showPickingList("E99A", leg);
      await new Promise(function (res) { setTimeout(res, 60); });
      const m = {};
      (_pk && _pk.items || []).forEach(function (x) { m[x.key] = x.skip ? "skip" : x.esp; });
      return m;
    };
    lineas = [{ art: "636E", cajas: 20 }];
    const A = await correr();
    out.A = A["636E"] === 20 && !("636" in A) && !("636·EXC" in A);
    lineas = [{ art: "636", cajas: 14 }];
    const B = await correr();
    out.B = B["636·EXC"] === 9 && B["636"] === 5 && _pk.items.every(function (x) { return !x.liqDe; });
    NP = "98001"; lineas = [{ art: "636E", cajas: 4 }];
    const C = await correr();
    out.C = C["636E"] === 4 && !("636" in C);
    return out;
  });

  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("pk-liquidar-636:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
