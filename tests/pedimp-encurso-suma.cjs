/* v29.41 (10/10: "solo en el módulo de importaciones ya mirá todo como 820, no como 809") — el corta pizza de LK
   pasa a 820E: la fila 809E LK se ve DENTRO de la 820E (GV_Importados_EnCurso_Suma) con su stock, Est. Madre y
   pedidos, y el 809E de Chef queda aparte. Corre ocgFetchImportados de verdad con la red simulada. */
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
    const base = { proveedor: "Ownland", uni_x_caja: 12, fob_uni: 0.7, meses_objetivo: 8, stock_insumos: 0, stock_gp2: 0, stock_conv: 0, cajas_pedidas: 0, unidades_pedidas: 0, principal: true, activo: true };
    const imp = [
      Object.assign({}, base, { id: 100, cod_art: "809E", marca: "LK", descripcion: "Corta pizza familiar", est_madre_eff: 288, stock_total_neto: 36, pedido_curso: 0 }),
      Object.assign({}, base, { id: 129, cod_art: "809E", marca: "CH", descripcion: "Corta queso x12", fob_uni: 0.47, est_madre_eff: 1224, stock_total_neto: 4368, pedido_curso: 7200 }),
      Object.assign({}, base, { id: 175, cod_art: "820E", marca: "LK", descripcion: "Corta Pizza Mgo Ergonomico 6cm", est_madre_eff: 0, stock_total_neto: 0, pedido_curso: 1632 })
    ];
    window.__suma = [{ destino_cod: "809E", destino_marca: "LK", origen_cod: "820E" }];
    supaFetchAllSafe = async function (url, q) {
      const u = String(url) + "?" + String(q || "");
      if (/GV_Importados_EnCurso_Suma/.test(u)) return window.__suma;
      if (/reingreso_est/.test(u)) return [{ cod_art: "820E", marca: "LK", reingreso_est: "2026-12-18" }, { cod_art: "809E", marca: "CH", reingreso_est: "2026-12-18" }];
      if (/Importados_Volumen/.test(u)) return [];
      if (/\/Importados\b|importados_ordenes|IMPORTADOS/i.test(u) && /select=id,cod_art/.test(u)) return imp;
      return [];
    };
    const out = {};
    for (const caso of ["con", "sin"]) {
      if (caso === "sin") window.__suma = [];
      const res = await ocgFetchImportados();
      const items = (res && res.items) || res || [];
      const lk = items.find(function (it) { return it.key === "809E|LK"; }) || {};
      const n = items.find(function (it) { return String(it.cod).toUpperCase() === "820E"; }) || {};
      const ch = items.find(function (it) { return it.key === "809E|CH"; }) || {};
      out[caso] = { hayLk: !!lk.key, nCurso: n.enCurso, nProy: n.proyUni, nStock: n.stockUni, nPedir: n.aPedirUni, nVer: n.verComo || "",
        chProy: ch.proyUni, chStock: ch.stockUni, chCurso: ch.enCurso };
    }
    return out;
  });
  await b.close();
  let fail = 0; const ok = (c, m) => { console.log((c ? "OK  " : "FAIL") + " " + m); if (!c) fail++; };
  const C = r.con, S = r.sin;
  console.log(JSON.stringify(r));
  ok(!C.hayLk, "con el vínculo no se dibuja la fila 809E LK");
  ok(C.nProy === 288 && C.nStock === 36 && C.nCurso === 1632, "la fila 820E trae la Est. Madre (288) y el stock (36) del 809E LK y su pedido (1.632)");
  ok(C.nVer === "809E LK", "la fila 820E dice que incluye el 809E LK");
  ok(C.chProy === 1224 && C.chStock === 4368 && C.chCurso === 7200, "el 809E de Chef queda igual (1.224 / 4.368 / 7.200)");
  ok(S.hayLk && S.nProy === 0, "sin el vínculo, como antes");
  ok(!errs.length, "sin errores de página " + errs.join(" | "));
  process.exit(fail ? 1 : 0);
})();
