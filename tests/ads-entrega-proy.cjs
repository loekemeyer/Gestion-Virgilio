/* v28.44 (Luis): en ADS → Stock, la «Entrega est.» usa la ENTREGA PROY. cargada a mano en la OC vigente
   (Ordenes_Compra.gv_entrega_proy) en vez de la estimación por ritmo; sin dato, sigue por ritmo.
   v28.45 (D2): lo declarado es por semana → × H/7, topado en lo que falta, igual que el ritmo. */
const fs = require("fs"), path = require("path"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "ads.js"), "utf8");
const ctx = { window: {}, document: { getElementById: () => null }, console, Date, Math, Number, String, isFinite, Promise };
vm.createContext(ctx); vm.runInContext(src, ctx);
const hace = (d) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10);
vm.runInContext(`_ads.tall = [
  { proveedor: "Garcia", codigo: "550", pedido: 100, entregado: 20, desde: "${hace(20)}", ult_fecha: "2026-10-07" },
  { proveedor: "Poly",   codigo: "550", pedido: 100, entregado: 50, desde: "${hace(20)}", ult_fecha: "2026-10-07" }];`, ctx);
const fallas = [];
let c = vm.runInContext(`_ads.epOc = {}; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estH !== 10 + 25 || c.estOc) fallas.push("sin dato cargado tiene que ir por ritmo (35): " + c.estH);
c = vm.runInContext(`_ads.epOc = {}; _ads.epOc[_adsEpKey("Garcia", "550", "2026-10-07")] = 60; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estH !== 80 + 25 || !c.estOc) fallas.push("Garcia con 60/semana a 10 d = min(80 que falta, 86) = 80: " + c.estH);
const c7 = vm.runInContext(`_adsStockCalc({ cod: "550", saldo7: -5 }, 7)`, ctx);
if (c7.estCaj[0] !== "Garcia: 60") fallas.push("a 7 días el declarado vale tal cual (60): " + c7.estCaj[0]);
if (!/cargado en la OC/.test(c.estDist.join("|")) ) fallas.push("el tooltip no dice el origen: " + c.estDist.join("|"));
c = vm.runInContext(`_ads.epOc = {}; _ads.epOc[_adsEpKey("Garcia", "550", "2026-09-30")] = 60; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estH !== 35) fallas.push("un dato de una OC vieja no cuenta: " + c.estH);
if (fallas.length) { console.error("✗ ads-entrega-proy\n  " + fallas.join("\n  ")); process.exit(1); }
console.log("✓ ADS: Entrega est. usa la entrega proy. cargada en la OC vigente; sin dato, por ritmo");
