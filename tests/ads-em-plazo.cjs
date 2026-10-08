// v28.56 (Luis, 08/10): ADS Stock — «E.M. plazo Xd» = Est. Madre × max(0, X − días que tarda en salir) / 30,
// con los días del promedio de 2 semanas (gv_ads_config.lead_dias) o fijados a mano (gv_ads_lead_guardar).
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(__dirname + "/../ads.js", "utf8");
const sql = fs.readFileSync(__dirname + "/../sql/gv_ads_em_plazo_v2857.sql", "utf8");
const fallas = [];
const ctx = { window: {}, document: { getElementById: () => null }, console, Date, Math, Number, String, isFinite, Promise, Object };
vm.createContext(ctx); vm.runInContext(src, ctx);
vm.runInContext("_ads.cfg = { lead_dias: 12.7 }; _ads.tall = [];", ctx);
const em = (H) => vm.runInContext(`_adsStockCalc({ cod: "550", disponible: 46, proy_mes: 103, comp${H}: 103, saldo${H}: 0 }, ${H}).em`, ctx);
if (em(10) !== 0) fallas.push("10 d con 12,7 de demora: E.M. plazo tiene que dar 0, dio " + em(10));
if (Math.abs(em(20) - 103 * 7.3 / 30) > 1e-9) fallas.push("20 d: 103 × 7,3 / 30, dio " + em(20));
if (Math.abs(em(30) - 103 * 17.3 / 30) > 1e-9) fallas.push("30 d: 103 × 17,3 / 30, dio " + em(30));
vm.runInContext("_ads.cfg = {}", ctx);
if (Math.abs(em(30) - 103 * 18 / 30) > 1e-9) fallas.push("sin config: 12 días por defecto");
if (!/E\.M\. plazo<br>' \+ H \+ 'd/.test(src)) fallas.push("rótulo de pantalla «E.M. plazo Xd»");
if (!/"E\.M\. plazo " \+ H \+ "d"/.test(src)) fallas.push("rótulo del Excel «E.M. plazo Xd»");
if (!/gv_ads_lead_guardar/.test(src) || !/id="adsLead"/.test(src)) fallas.push("la demora se edita desde ADS");
if (!/greatest\(0, 10 - ld\.l\)/.test(sql) || !/h\.d - 14 and h\.d/.test(sql)) fallas.push("SQL: saldo con E.M. plazo y promedio de 14 días");
if (/greatest\(coalesce\(c\.c10/.test(sql)) fallas.push("SQL: volvió el «mayor entre comprometido y E.M.»");
if (fallas.length) { console.log("✗ ADS E.M. plazo:\n  " + fallas.join("\n  ")); process.exit(1); }
console.log("✓ ADS: E.M. plazo = Est. Madre × (plazo − demora) / 30, demora de 2 semanas o a mano");
