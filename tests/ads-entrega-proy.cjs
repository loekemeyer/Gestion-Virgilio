/* v28.44 (Luis): en ADS → Stock, la «Entrega est.» usa la ENTREGA PROY. cargada a mano en la OC vigente
   (Ordenes_Compra.gv_entrega_proy) en vez de la estimación por ritmo; sin dato, sigue por ritmo.
   v28.47: sin escalar al plazo — lo declarado o OC × % que viene entregando, menos lo ya recibido de la OC. */
const fs = require("fs"), path = require("path"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "ads.js"), "utf8");
const ctx = { window: {}, document: { getElementById: () => null }, console, Date, Math, Number, String, isFinite, Promise };
vm.createContext(ctx); vm.runInContext(src, ctx);
const hace = (d) => new Date(Date.now() - d * 864e5).toISOString().slice(0, 10);
vm.runInContext(`_ads.tall = [
  { proveedor: "Garcia", codigo: "550", pedido: 100, entregado: 20, desde: "${hace(20)}", ult_fecha: "2026-10-07", ult_cant: 50, ult_rec: 5 },
  { proveedor: "Poly",   codigo: "550", pedido: 100, entregado: 50, desde: "${hace(20)}", ult_fecha: "2026-10-07", ult_cant: 40, ult_rec: 0 }];`, ctx);
const fallas = [];
let c = vm.runInContext(`_ads.epOc = {}; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estH !== 5 + 20 || c.estOc) fallas.push("sin dato: OC × % − recibido (Garcia 50×20 %−5 = 5 + Poly 40×50 % = 20): " + c.estH);
c = vm.runInContext(`_ads.epOc = {}; _ads.epOc[_adsEpKey("Garcia", "550", "2026-10-07")] = 60; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (!c.estCaj.some(t => /^Garcia: 55$/.test(t)) || !c.estCaj.some(t => /^Poly: 20\*$/.test(t)) || !c.estCalc) fallas.push("v28.53 asterisco = calculado: " + JSON.stringify(c.estCaj));
if (JSON.stringify(c.estXY.map(y => y.txt)) !== JSON.stringify(["60/50", "20*/40"])) fallas.push("v28.64 X/Y por tallerista (X proyectado, * si estimado; Y = OC): " + JSON.stringify(c.estXY));
c = vm.runInContext(`_ads.epOc = {}; _ads.epOc[_adsEpKey("Garcia", "550", "2026-10-07")] = 0; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estXY[0].txt !== "0/50") fallas.push("un 0 cargado en la OC es dato: va sin *: " + c.estXY[0].txt);
c = vm.runInContext(`_ads.epOc = {}; _ads.epOc[_adsEpKey("Garcia", "550", "2026-10-07")] = 60; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estH !== 55 + 20 || !c.estOc) fallas.push("Garcia declaró 60 en la OC − 5 recibidas = 55: " + c.estH);
const c30 = vm.runInContext(`_adsStockCalc({ cod: "550", saldo30: -5 }, 30)`, ctx);
if (c30.estH !== c.estH) fallas.push("no escala con el plazo (a 30 d igual que a 10): " + c30.estH);
if (!/cargado en la OC/.test(c.estDist.join("|")) ) fallas.push("el tooltip no dice el origen: " + c.estDist.join("|"));
c = vm.runInContext(`_ads.epOc = {}; _ads.epOc[_adsEpKey("Garcia", "550", "2026-09-30")] = 60; _adsStockCalc({ cod: "550", saldo10: -5 }, 10)`, ctx);
if (c.estH !== 25) fallas.push("un dato de una OC vieja no cuenta: " + c.estH);
if (fallas.length) { console.error("✗ ads-entrega-proy\n  " + fallas.join("\n  ")); process.exit(1); }
console.log("✓ ADS: Entrega est. usa la entrega proy. cargada en la OC vigente; sin dato, OC × %");
