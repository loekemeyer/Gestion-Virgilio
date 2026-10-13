/* v29.42 (10/10) — el pop-up de stock de un importado muestra DÓNDE está, como Stocks: Góndola, Pickeados,
   A facturar, A guardar, Racks… (de stocks_carga_rapida, en cajas y en u) y una fila 🏭 Cervantes (GP2).
   Corre pedImpStockDesglose de verdad con la red simulada. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async function () {
    const espera = (ms) => new Promise((ok) => setTimeout(ok, ms));
    window.__falla = false;
    supaFetchAllSafe = async function (url, q) {
      const u = String(url) + "?" + String(q || "");
      if (/stocks_carga_rapida/.test(u)) {
        if (window.__falla) throw new Error("caido");
        if (/cod_base=in\.\(026,26\)/.test(u)) return [{ cod: "26", linea: "LK", terminado: 10, excedente: 0, separar_pedidos: 3, a_facturar: 2, a_guardar: 0, racks: 5, racks_ch: 1, para_envasar: 0, insumos_dep: 0, fc_sin_salida: 1 }];
        return [];
      }
      if (/GV_Importados_Equiv_GP2/.test(u)) return [{ componente_codigo: "GRJ99", factor: 1 }];
      return [];
    };
    const it = { cod: "026", key: "026", planta: "", uxc: 12, stockUni: 0, stockPropioModulo: 0, stockGp2U: 120, stockInsU: 0, det: [{ id: 1, marca: "LK" }] };
    _stkPop = { kind: "pedImp", data: { items: [it] } };
    const out = {};
    pedImpStockDesglose("026"); await espera(300);
    const filas = [...document.querySelectorAll("#impStkDesgOv .imp-stk-dep tbody tr")].map((tr) => [...tr.children].map((td) => td.textContent.trim()));
    out.filas = filas;
    out.total = [...document.querySelectorAll("#impStkDesgOv .imp-stk-dep tfoot th")].map((x) => x.textContent.trim());
    out.fcs = /1 caja\(s\) facturadas sin salir/.test(document.getElementById("impStkDesgOv").textContent);
    pedImpStockDesgCerrar();
    window.__falla = true; pedImpStockDesglose("026"); await espera(300);
    out.error = !!document.querySelector("#impStkDesgOv .imp-dep-error");
    pedImpStockDesgCerrar();
    return out;
  });
  await b.close();
  let fail = 0; const ok = (c, m) => { console.log((c ? "OK  " : "FAIL") + " " + m); if (!c) fail++; };
  console.log(JSON.stringify(r));
  const get = (l) => (r.filas.find((f) => f[0].indexOf(l) === 0) || []);
  ok(get("Góndola")[1] === "10" && get("Góndola")[2] === "120", "Góndola 10 cajas = 120 u");
  ok(get("Pickeados")[1] === "3", "Pickeados 3");
  ok(get("A facturar")[1] === "2", "A facturar 2");
  ok(get("Racks")[1] === "6", "Racks suma racks + racks CH (6)");
  ok(!get("Excedente").length, "un depósito en 0 no se dibuja (salvo góndola)");
  ok(/Cervantes/.test(get("🏭")[0] || "") && /GRJ99/.test(get("🏭")[0] || "") && get("🏭")[2] === "120", "fila Cervantes (GP2) con el componente y sus 120 u");
  ok(r.total[1] === "31" && r.total[2] === "372", "total Virgilio + Cervantes: 21 + 10 cajas = 372 u");
  ok(r.fcs, "avisa lo facturado sin salir");
  ok(r.error, "lectura caída: lo dice, no muestra ceros");
  ok(!errs.length, "sin errores de página " + errs.join(" | "));
  process.exit(fail ? 1 : 0);
})();
