/* Test de regresión (v7.x) — IMPRESO de OC con el formato de la planilla del tallerista.
   Columnas: Cod · Descripción · Cajas · Falta Pedidos · Uni x Caja · % Lleno.
   Los tres derivados salen de lo GUARDADO al generar (oc_max/oc_pedidos/oc_stock/
   oc_uni_caja): Falta Pedidos = máx(0, Pedidos−Stock); % Lleno = (Stock−Pedidos)/Máx.
   Verifica sobre ocPrintHtml (función pura, sin ventana de impresión):
   - encabezado con tallerista + fecha (+ Tel si viene proveedor_telefono),
   - las 6 columnas y el orden,
   - Falta Pedidos y % Lleno bien calculados (incluye % negativo),
   - filas sin los valores guardados (OC vieja/manual) muestran "—" en esas columnas,
   - el Total suma las Cajas.
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
    const x = {
      proveedor: "Lucho", fecha: "2026-07-29", telefono: "11 3062-0152",
      rows: [
        // 123: Cajas 237, Pedidos 59, Stock 0, Máx 178 → Falta 59, %Lleno (0-59)/178=-33%
        { codigo: "123", descripcion: "Pelador Plastico Loke", cantidad: 237, oc_max: 178, oc_pedidos: 59, oc_stock: 0, oc_uni_caja: 12 },
        // 518: Cajas 70, Pedidos 0, Stock 27.5, Máx 97.5 → Falta 0, %Lleno 27.5/97.5=28%
        { codigo: "518", descripcion: "Sacafuente Pizzero", cantidad: 70, oc_max: 97.5, oc_pedidos: 0, oc_stock: 27.5, oc_uni_caja: 12 },
        // OC vieja/manual: sin los valores guardados → "—" en Falta/Uni/%Lleno
        { codigo: "999", descripcion: "Manual", cantidad: 10, oc_max: null, oc_pedidos: null, oc_stock: null, oc_uni_caja: null }
      ]
    };
    const html = ocPrintHtml(x);
    out.encabezado = html.indexOf("Lucho") >= 0 && html.indexOf("2026-07-29") >= 0 && html.indexOf("Tel: 11 3062-0152") >= 0;
    out.columnas = ["Cod", "Descripcion", "Cajas", "Falta Pedidos", "Uni x Caja", "% Lleno"].every((c) => html.indexOf(c) >= 0);
    out.sinUnidadCol = html.indexOf(">Unidad<") < 0;   // la columna vieja "Unidad" ya no está
    // 123: falta 59, %lleno -33%
    out.falta123 = html.indexOf(">59<") >= 0;
    out.pct123 = html.indexOf("-33%") >= 0;
    // 518: %lleno 28% (redondeo de 28.2)
    out.pct518 = html.indexOf("28%") >= 0;
    // fila manual: "—" en las columnas derivadas
    out.manualGuion = html.indexOf("—") >= 0;
    // total de cajas = 237+70+10 = 317
    out.total = html.indexOf(">317<") >= 0;
    // sin teléfono → no aparece "Tel:"
    const x2 = { proveedor: "Poly", fecha: "2026-07-29", telefono: "", rows: [{ codigo: "31", descripcion: "X", cantidad: 5, oc_max: 100, oc_pedidos: 0, oc_stock: 20, oc_uni_caja: 24 }] };
    out.sinTel = ocPrintHtml(x2).indexOf("Tel:") < 0;
    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("oc-print: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("oc-print: OK — impreso de OC con Cajas / Falta Pedidos / Uni x Caja / % Lleno");
  process.exit(0);
})();
