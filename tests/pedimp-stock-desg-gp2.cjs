/* v25.71 (Luis, 01/10) — el resumen «📦 Stock — 323ES» más grande y con el CÓDIGO del componente de
   Cervantes (GRJ31). Corre el pop-up de verdad con el fetch mockeado:
   A. 323ES (100 %): la fila y el encabezado dicen GRJ31;
   B. 323E (20 %): dice GRJ31 y «20 % de 4.000 u»;
   E. 942E: tres componentes, se listan todos (v26.00);
   C. sin equivalencia (o si falla la lectura): se ve como antes, sin código;
   D. letra grande (tabla 16px, encabezado 19px). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async function () {
    const EQ = { "323ES": { componente_codigo: "GRJ31", factor: 1 }, "323E": { componente_codigo: "GRJ31", factor: 0.2 },
      "942E": [{ componente_codigo: "942E", factor: 1 }, { componente_codigo: "Z47", factor: 1 }, { componente_codigo: "Z47-M505D", factor: 1 }] };
    let falla = false;
    supaFetchAllSafe = async function (url, q) {
      if (/GV_Importados_Equiv_GP2/.test(url)) { if (falla) throw new Error("caida"); const m = /importado_cod=eq\.([^&]+)/.exec(q); const c = decodeURIComponent(m ? m[1] : ""); return EQ[c] ? (Array.isArray(EQ[c]) ? EQ[c] : [EQ[c]]) : []; }
      if (/GV_Importados_Equiv_Virgilio/.test(url)) { if (falla) throw new Error("caida"); return /importado_cod=eq\.702E/.test(q) ? [{ cod_art: "102E", empresa: "LK" }, { cod_art: "702", empresa: "LK" }] : []; }
      return [];
    };
    const items = {
      "323ES": { cod: "323ES", stockPropioModulo: 0, stockInsU: 0, stockGp2U: 4000, stockUni: 4000, esInsumo: true, meses: 12, mesesProv: 10 },
      "323E": { cod: "323E", stockPropioModulo: 0, stockInsU: 0, stockGp2U: 800, stockUni: 644, uniPedidas: 156 },
      "942E": { cod: "942E", stockPropioModulo: 5, stockInsU: 0, stockGp2U: 30, stockUni: 35 },
      "702E": { cod: "702E", stockPropioModulo: 100, stockInsU: 0, stockGp2U: 0, stockConvU: 480, stockUni: 580 },
      "999X": { cod: "999X", stockPropioModulo: 10, stockInsU: 0, stockGp2U: 50, stockUni: 60 }
    };
    _pedImpItemPorClave = function (k) { return items[k]; };
    const espera = () => new Promise((res) => setTimeout(res, 120));
    const out = {};
    const abrir = async (k) => { pedImpStockDesgCerrar(); await pedImpStockDesglose(encodeURIComponent(k)); await espera(); return document.getElementById("impStkDesgOv"); };
    let ov = await abrir("323ES");
    out.a = !!ov.querySelector(".imp-gp2-cod") && /GRJ31/.test(ov.querySelector(".imp-gp2-cod").textContent) && /GRJ31 en Cervantes/.test(ov.querySelector(".imp-gp2-hdr").textContent);
    out.d = getComputedStyle(ov.querySelector("table.imp-stk-desg")).fontSize === "16px" && /19px/.test(ov.innerHTML);
    ov = await abrir("323E");
    out.b = /GRJ31/.test(ov.innerHTML) && /20 %<\/b> de 4\.000 u/.test(ov.innerHTML);
    ov = await abrir("942E");
    out.e = /942E \+ Z47 \+ Z47-M505D/.test(ov.querySelector(".imp-gp2-cod").textContent) && /Z47-M505D en Cervantes/.test(ov.querySelector(".imp-gp2-hdr").textContent) && !/ %<\/b> de/.test(ov.innerHTML);
    ov = await abrir("702E");
    out.f = !!ov.querySelector(".imp-conv-cod") && /102E LK \+ 702 LK/.test(ov.querySelector(".imp-conv-cod").textContent) && /480/.test(ov.innerHTML);
    ov = await abrir("999X");
    out.c1 = !ov.querySelector(".imp-gp2-cod") && /Cervantes \(GP2\)/.test(ov.innerHTML);
    falla = true; ov = await abrir("323ES");
    out.c2 = !ov.querySelector(".imp-gp2-cod") && /Cervantes \(GP2\)/.test(ov.innerHTML);
    return out;
  });
  const fail = Object.keys(r).filter((k) => !r[k]);
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.log("pedimp-stock-desg-gp2: ✗ " + fail.join(" · ") + " " + JSON.stringify(r)); process.exit(1); }
  console.log("pedimp-stock-desg-gp2: OK — GRJ31 en la fila y el encabezado · 20 % del 323E · 942E con 3 componentes · 702E con stock convertible · sin equivalencia como antes · letra grande");
})();
