/* Smoke de las etiquetas de lío (idea 5290, v6.88). TODO detrás del switch
   `vir_etiqueta_lio` + SÓLO legajos de prueba 0/1. Verifica:
   - las funciones existen,
   - switch APAGADO → no construye ninguna etiqueta (app = igual que hoy),
   - legajo real (104) → tampoco, aunque el switch esté prendido,
   - legajo 0 con switch on → una fila por lío, con np/lio_idx/cajas/items/razón/ZPL,
   - _etlAbrev abrevia la razón social (saca S.R.L./S.A. y recorta),
   - el client_id es determinístico por tanda|np|lío. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    out.fns = ["etlOn", "etlSetOn", "etlToggle", "etlBuildLabels", "etlEnqueueArmado", "_etlAbrev", "_etlZpl", "_etlOperRow"].every((n) => typeof window[n] === "function");
    const comp = { nps: [
      { np: "98001", rs: "DISTRIBUIDORA LA OSA S.R.L.", liosArr: [ { items: [{ cod: "502", qty: 3 }, { cod: "323E", qty: 2 }], cajas: 5 }, { items: [{ cod: "66", qty: 1 }], cajas: 1, suelta: true } ] },
      { np: "98002", rs: "Mundo Bazar S.A.", liosArr: [ { items: [{ cod: "943E", qty: 4 }], cajas: 4 } ] }
    ] };
    try { localStorage.removeItem("vir_etiqueta_lio"); } catch (_e) {}
    out.offEmpty  = (etlBuildLabels(comp, "0", "C99Z").length === 0);     // switch apagado → nada
    etlSetOn(true);
    out.realEmpty = (etlBuildLabels(comp, "104", "C99Z").length === 0);   // legajo real → nada
    const rows = etlBuildLabels(comp, "0", "C99Z");
    out.count = (rows.length === 3);                                      // 2 líos NP1 + 1 líos NP2
    const r0 = rows[0];
    out.row0 = !!r0 && r0.np === "98001" && r0.lio_idx === 1 && r0.lio_total === 2 && r0.cajas === 5 &&
      Array.isArray(r0.items) && r0.items.length === 2 && r0.razon_social === "DISTRIBUIDORA LA OSA" &&
      /502/.test(r0.zpl) && /TOTAL 5 cajas/.test(r0.zpl) && /\^XA/.test(r0.zpl);
    out.abrev = (_etlAbrev("Mundo Bazar S.A.") === "Mundo Bazar") &&
      (_etlAbrev("Comercial Del Plata S.R.L.") === "Comercial Del Plata") &&
      (_etlAbrev("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA").length <= 22);
    out.cid = /^etl_C99Z_98001_1_/.test(r0.client_id) && /^etl_C99Z_98002_1_/.test(rows[2].client_id);
    etlSetOn(false);
    return out;
  });
  await b.close();
  const ok = r.fns && r.offEmpty && r.realEmpty && r.count && r.row0 && r.abrev && r.cid && errs.length === 0;
  console.log("etl-lio:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", ok ? "✓ OK" : "✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
