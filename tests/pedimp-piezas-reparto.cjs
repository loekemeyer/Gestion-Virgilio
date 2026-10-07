/* v28.43 (Luis, 07/10) — piezas e insumos COMPARTIDOS (GV_Piezas_Reparto), repartidos por E.M.
   A. ocgFetchImportados pide piezas_share y piezas_reparto a gv_importados_ordenes y los pasa al ítem;
   B. el pop-up de stock del 942E dice que le toca el 87 % y el reparto (942E LK · 633E CH);
   C. sin reparto (share 1) no aparece la fila;
   D. el SQL del repo tiene las tres piezas (vista de %, ordenes, cartel) y el 323E sin GRJ31.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const fail = [];
  const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_piezas_reparto_em_v2843.sql"), "utf8");
  if (!/create or replace view public\.gv_piezas_reparto_share/.test(sql)) fail.push("D: falta la vista de %");
  if (!/LEFT JOIN gv_piezas_reparto_share sh ON sh\.grupo = upper\(i\.cod_art\)/.test(sql)) fail.push("D: ordenes sin el %");
  if (!/_rf_gp2 gp on gp\.grupo = g\.grupo/.test(sql) || !/_rf_ins ins on ins\.grupo = g\.grupo/.test(sql)) fail.push("D: el cartel no cuenta GP2/insumos");
  if (!/\('942E','633E','CH'/.test(sql) || !/\('438E','438E','CH'/.test(sql)) fail.push("D: faltan los grupos");

  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async function () {
    const out = {};
    let qOrd = "";
    supaFetchAllSafe = async function (url, q) {
      if (/gv_importados_ordenes/.test(url)) {
        qOrd = q;
        return [
          { id: 1, cod_art: "942E", marca: "LK", proveedor: "Becky", uni_x_caja: 12, est_madre_eff: 156, meses_objetivo: 10, stock_gp2: 374, stock_total_neto: 878, piezas_share: 0.8667, piezas_reparto: "633E CH 24 u · 942E LK 156 u", principal: true, activo: true },
          { id: 2, cod_art: "702E", marca: "LK", proveedor: "Becky", uni_x_caja: 12, est_madre_eff: 100, meses_objetivo: 10, stock_gp2: 0, stock_total_neto: 50, piezas_share: 1, piezas_reparto: null, principal: true, activo: true }
        ];
      }
      return [];
    };
    let data = { items: [] };
    try { data = await ocgFetchImportados(); } catch (e) { out.err = String(e); }
    out.a = /piezas_share/.test(qOrd) && /piezas_reparto/.test(qOrd);
    const it942 = (data.items || []).find((x) => x.cod === "942E");
    const it702 = (data.items || []).find((x) => x.cod === "702E");
    out.a2 = !!it942 && Math.abs(it942.piezasShare - 0.8667) < 1e-6 && /633E CH/.test(it942.piezasReparto) && !!it702 && it702.piezasShare === 1;
    const items = { "942E": it942, "702E": it702 };
    _pedImpItemPorClave = function (k) { return items[k]; };
    const espera = () => new Promise((res) => setTimeout(res, 120));
    const abrir = async (k) => { pedImpStockDesgCerrar(); await pedImpStockDesglose(encodeURIComponent(k)); await espera(); return document.getElementById("impStkDesgOv"); };
    let ov = await abrir("942E");
    const fila = ov && ov.querySelector(".imp-piezas-share");
    out.b = !!fila && /87 %/.test(fila.textContent) && /633E CH 24 u · 942E LK 156 u/.test(fila.textContent) && /Estadística Madre/.test(fila.textContent);
    ov = await abrir("702E");
    out.c = !!ov && !ov.querySelector(".imp-piezas-share");
    return out;
  });
  await b.close();
  Object.keys(r).filter((k) => k !== "err" && !r[k]).forEach((k) => fail.push(k));
  if (r.err) fail.push("err: " + r.err);
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.log("pedimp-piezas-reparto: ✗ " + fail.join(" · ") + " " + JSON.stringify(r)); process.exit(1); }
  console.log("pedimp-piezas-reparto: OK — piezas_share viaja · el 942E dice 87 % y el reparto con 633E · sin reparto no hay fila · SQL con vista, ordenes y cartel");
})();
