/* Test de regresión (v7.55) — (1) DEPURAR INCOMPLETOS y (2) caja de PARÁMETROS de proyección.
   (1) ocBodyDepurar() lista los artículos activos de OC_Maximos con datos faltantes
       (sin proveedor / sin objetivo / sin uni×caja) o sin historial de ventas (sin proyección),
       usando _oc.gen.maxs + _oc.gen.proy; los completos no aparecen.
   (2) ocBodyCfg() dibuja la caja "Parámetros de la proyección" con el período (meses) y el
       switch "Suavizar anómalos", tomando los valores de _oc.cfg.params.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // ---- (1) Depurar incompletos ----
    _oc = { view: "depurar", gen: {
      maxs: [
        { cod: "107", descripcion: "Completo", proveedor: "Lucho", max_cajas: 100, uni_x_caja: 12 },   // OK (tiene proy) → no aparece
        { cod: "55289", descripcion: "Colador Verde", proveedor: "", max_cajas: 0, uni_x_caja: null },  // 4 problemas
        { cod: "202", descripcion: "Sin uni", proveedor: "Poly", max_cajas: 50, uni_x_caja: 0 }          // tiene proy → sólo sin uni×caja
      ],
      proy: { "107": 5, "202": 3 }   // 55289 sin proyección
    } };
    ocRender = function () {};
    const hd = ocBodyDepurar();
    out.dep55289 = hd.indexOf("55289") >= 0;
    out.dep202 = hd.indexOf(">202<") >= 0;
    out.depNo107 = hd.indexOf(">107<") < 0;                       // el completo NO se lista
    out.depTags = ["sin proveedor", "sin uni×caja", "sin objetivo", "sin ventas"].every((t) => hd.indexOf(t) >= 0);
    out.depCount = hd.indexOf("sin uni×caja: <b>2</b>") >= 0;      // 55289 y 202

    // ---- (2) Caja de parámetros en la config ----
    _oc = { view: "cfg", cfg: {
      rows: [{ cod: "107", descripcion: "X", proveedor: "Lucho", max_cajas: 100, uni_x_caja: 12, indice: 1.5, activo: true }],
      changed: {}, filtro: "", error: null, alta: null, params: { meses: 12, suavizar: false }
    } };
    const hc = ocBodyCfg();
    out.paramBox = hc.indexOf("Parámetros de la proyección") >= 0;
    out.paramMeses = hc.indexOf('id="ocpMeses"') >= 0 && hc.indexOf('value="12"') >= 0;
    out.paramSuav = hc.indexOf('id="ocpSuav"') >= 0 && hc.indexOf("Suavizar anómalos") >= 0;
    out.paramBtn = hc.indexOf("Guardar y recalcular") >= 0;
    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("ocg-depurar: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("ocg-depurar: OK — depurar incompletos + parámetros de proyección (período/suavizar)");
  process.exit(0);
})();
