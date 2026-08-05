/* Test de regresión (v7.51) — EDITOR de config de compras (OC_Maximos) desde la app,
   para que el Excel deje de ser necesario. Verifica sobre las funciones puras/estado
   (sin red, sin sesión de supervisor):
   - ocBodyCfg() dibuja las columnas nuevas (Objetivo · Uni×Caja · Índice · Activo),
     el botón de alta y los valores/proveedor cargados,
   - ocCfgEdit acumula un PATCH parcial por código en _oc.cfg.changed (merge de campos),
   - ocCfgSetAllIndice pone el índice a todos y lo registra como cambio,
   - ocCfgAltaOpen abre el formulario de alta.
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
    _oc = { view: "cfg", cfg: {
      changed: {}, filtro: "", error: null, alta: null,
      rows: [
        { cod: "107", descripcion: "Colador", proveedor: "Lucho", max_cajas: 100, uni_x_caja: 12, indice: 1.5, activo: true },
        { cod: "202", descripcion: "Otro",    proveedor: "Poly",  max_cajas: 50,  uni_x_caja: 24, indice: 1.5, activo: true }
      ]
    } };
    ocRender = function () {};   // sin re-dibujar el modal

    const html = ocBodyCfg();
    out.cols = ["Objetivo", "Uni×Caja", "Índice", "Activo"].every((c) => html.indexOf(c) >= 0);
    out.alta = html.indexOf("➕ Agregar artículo") >= 0;
    out.provInput = html.indexOf('value="Lucho"') >= 0;      // proveedor editable
    out.objetivo = html.indexOf('value="100"') >= 0;          // objetivo (max_cajas) editable
    out.noExcelWord = html.indexOf("ya no hace falta el Excel") >= 0;

    // Editar dos campos del 107 → PATCH parcial acumulado (merge)
    ocCfgEdit(0, "max_cajas", "99");
    ocCfgEdit(0, "uni_x_caja", "6");
    out.mergePatch = _oc.cfg.changed["107"] && _oc.cfg.changed["107"].max_cajas === 99 && _oc.cfg.changed["107"].uni_x_caja === 6;
    out.rowUpdated = _oc.cfg.rows[0].max_cajas === 99;

    // Desactivar el 202
    ocCfgEdit(1, "activo", false);
    out.activoOff = _oc.cfg.changed["202"] && _oc.cfg.changed["202"].activo === false;

    out.changedN = Object.keys(_oc.cfg.changed).length === 2;   // 107 y 202

    // Índice a todos (necesita el input #ociAll en el DOM)
    document.body.innerHTML = '<input id="ociAll" value="3">';
    ocCfgSetAllIndice();
    out.setAll = _oc.cfg.rows.every((a) => a.indice === 3) &&
                 _oc.cfg.changed["107"].indice === 3 && _oc.cfg.changed["202"].indice === 3;

    // Alta: abre el formulario
    ocCfgAltaOpen();
    out.altaForm = ocBodyCfg().indexOf('id="ocmaCod"') >= 0;
    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("ocg-config: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("ocg-config: OK — editor de OC_Maximos (objetivo/uni×caja/índice/proveedor/activo + alta)");
  process.exit(0);
})();
