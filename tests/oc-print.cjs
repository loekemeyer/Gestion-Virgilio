/* Test de regresión (v7.x) — IMPRESO de OC con el formato de la planilla del tallerista.
   Columnas: Cod · Descripción · Cajas · Falta Pedidos · Uni x Caja · Caja N° · % Lleno.
   Los derivados salen de lo GUARDADO al generar (oc_max/oc_pedidos/oc_stock/
   oc_uni_caja/oc_ncaja): Falta Pedidos = máx(0, Pedidos−Stock); % Lleno = (Stock−Pedidos)/Máx;
   Caja N° = oc_ncaja (Articulos_Cajas.N_Caja, v7.42).
   Verifica sobre ocPrintHtml (función pura, sin ventana de impresión):
   - encabezado con tallerista + fecha (+ Tel si viene proveedor_telefono),
   - las 7 columnas y el orden,
   - Falta Pedidos y % Lleno bien calculados (incluye % negativo),
   - Caja N° mostrada (y "—" si no viene),
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
      // A propósito DESORDENADas por %Lleno (505 99%, 518 28%, 123 -33%) para probar el orden.
      rows: [
        // 505: %Lleno 99% (el más lleno → debe ir ÚLTIMO de los que tienen %)
        { codigo: "505", descripcion: "Pelador Plastico - Env.", cantidad: 22, oc_max: 3750, oc_pedidos: 0, oc_stock: 3728, oc_uni_caja: 12, oc_ncaja: 12 },
        // 518: Cajas 70, Stock 27.5, Máx 97.5 → Falta 0, %Lleno 28%
        { codigo: "518", descripcion: "Sacafuente Pizzero", cantidad: 70, oc_max: 97.5, oc_pedidos: 0, oc_stock: 27.5, oc_uni_caja: 12, oc_ncaja: 29 },
        // 123: Pedidos 59, Stock 0, Máx 178 → Falta 59, %Lleno -33% (el más negativo → PRIMERO)
        { codigo: "123", descripcion: "Pelador Plastico Loke", cantidad: 237, oc_max: 178, oc_pedidos: 59, oc_stock: 0, oc_uni_caja: 12, oc_ncaja: 2 },
        // OC vieja/manual: sin los valores guardados → "—" y va al FINAL (Caja N° también "—")
        { codigo: "999", descripcion: "Manual", cantidad: 10, oc_max: null, oc_pedidos: null, oc_stock: null, oc_uni_caja: null, oc_ncaja: null }
      ]
    };
    const html = ocPrintHtml(x);
    out.encabezado = html.indexOf("Lucho") >= 0 && html.indexOf("2026-07-29") >= 0 && html.indexOf("Tel: 11 3062-0152") >= 0;
    out.columnas = ["Cod", "Descripcion", "Cajas", "Falta Pedidos", "Uni x Caja", "Caja N°", "% Lleno"].every((c) => html.indexOf(c) >= 0);
    out.sinUnidadCol = html.indexOf(">Unidad<") < 0;   // la columna vieja "Unidad" ya no está
    // 123: falta 59, %lleno -33%
    out.falta123 = html.indexOf(">59<") >= 0;
    out.pct123 = html.indexOf("-33%") >= 0;
    // 518: %lleno 28% (redondeo de 28.2)
    out.pct518 = html.indexOf("28%") >= 0;
    // Caja N° (v7.42): los tres códigos con dato muestran su N_Caja
    out.ncaja = html.indexOf(">29<") >= 0 && html.indexOf(">2<") >= 0;
    // fila manual: "—" en las columnas derivadas
    out.manualGuion = html.indexOf("—") >= 0;
    // total de cajas = 22+70+237+10 = 339
    out.total = html.indexOf(">339<") >= 0;
    // ORDEN por % Lleno de menor a mayor: 123(-33) < 518(28) < 505(99) < manual(—, al final)
    const pos = function (cod) { return html.indexOf('>' + cod + '<'); };
    out.orden = pos("123") < pos("518") && pos("518") < pos("505") && pos("505") < pos("999");
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
