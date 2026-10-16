/* Regresión v31.60 — 636E / 635E de Chef se pickean del 636 / 635 nacional hasta liquidarlo (Luis, 16/10).

   Chequea:
   - A: 636 con 5 en góndola + 9 en excedente, piden 20 de 636E (Chef) → se liquidan 14 del 636
        (9 del excedente con su paso ·EXC, 5 de góndola) y 6 de 636E.
   - B: 635 con 11, piden 3 de 635E → paso "635" con 3 y el 635E salteado.
   - C: el mismo 636E en una NP de LK no se liquida (el par es de Chef).
   - D: total pedido intacto (14 + 6 = 20).
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
    out.A = A["636·EXC"] === 9 && A["636"] === 5 && A["636E"] === 6;
    out.A_liqDe = _pk.items.filter(function (x) { return x.art === "636"; }).every(function (x) { return x.liqDe === "636E"; });
    out.D_total = (A["636·EXC"] + A["636"] + A["636E"]) === 20;
    lineas = [{ art: "635E", cajas: 3 }];
    const B = await correr();
    out.B = B["635"] === 3 && B["635E"] === "skip";
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
