/* Test de regresión (v7.49) — IMPRESO de OC con el formato de la planilla del depósito.
   Columnas: Linea · Cod · Descripcion · Cajas · Falta Pedido · [separación] · N° Caja ·
   Uni x Caja · % Lleno, y (solo OPERADOR) las 3 columnas "Cajas Recibidas".
   Los derivados salen de lo GUARDADO al generar (oc_max/oc_pedidos/oc_stock/
   oc_uni_caja/oc_ncaja): Falta Pedido = máx(0, Pedidos−Stock); % Lleno = (Stock−Pedidos)/Máx.
   Verifica sobre ocPrintHtml (función pura, sin ventana de impresión):
   - encabezado con tallerista + fecha (dd/mm/yyyy) (+ Tel si viene proveedor_telefono),
   - las columnas y el orden (por % Lleno ascendente),
   - la columna Linea (LK rojo / CH azul) y la separación en blanco (.gap),
   - VARIANTE OPERADOR con "Cajas Recibidas" (3 columnas) y TALLERISTA sin ellas,
   - Falta Pedido y % Lleno bien calculados (incluye % negativo), N° Caja mostrado,
   - filas sin valores guardados (OC vieja/manual) muestran "—",
   - el Total suma las Cajas, y cada fila tiene tantas celdas como el encabezado.
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
        { codigo: "505", descripcion: "Pelador Plastico - Env.", linea: "LK", cantidad: 22, oc_max: 3750, oc_pedidos: 0, oc_stock: 3728, oc_uni_caja: 12, oc_ncaja: 12 },
        // 518: Cajas 70, Stock 27.5, Máx 97.5 → Falta 0, %Lleno 28%
        { codigo: "518", descripcion: "Sacafuente Pizzero", linea: "CH", cantidad: 70, oc_max: 97.5, oc_pedidos: 0, oc_stock: 27.5, oc_uni_caja: 12, oc_ncaja: 29 },
        // 123: Pedidos 59, Stock 0, Máx 178 → Falta 59, %Lleno -33% (el más negativo → PRIMERO)
        { codigo: "123", descripcion: "Pelador Plastico Loke", linea: "LK", cantidad: 237, oc_max: 178, oc_pedidos: 59, oc_stock: 0, oc_uni_caja: 12, oc_ncaja: 2 },
        // OC vieja/manual: sin los valores guardados → "—" y va al FINAL (Caja N° también "—")
        { codigo: "999", descripcion: "Manual", cantidad: 10, oc_max: null, oc_pedidos: null, oc_stock: null, oc_uni_caja: null, oc_ncaja: null }
      ]
    };
    // TALLERISTA (sin Cajas Recibidas) y OPERADOR (con Cajas Recibidas).
    const htmlT = ocPrintHtml(x);
    const htmlO = ocPrintHtml(x, { conRecibidas: true });

    // Encabezado: nombre + fecha dd/mm/yyyy + Tel.
    out.encabezado = htmlT.indexOf("Lucho") >= 0 && htmlT.indexOf("29/07/2026") >= 0 && htmlT.indexOf("Tel: 11 3062-0152") >= 0;

    // Columnas del encabezado (con <br> → uso textContent del thead).
    const dT = document.createElement("div"); dT.innerHTML = htmlT;
    const dO = document.createElement("div"); dO.innerHTML = htmlO;
    const headT = (dT.querySelector("thead").textContent || "");
    out.columnas = ["Linea", "Cod", "Descripcion", "Cajas", "Falta", "Pedido", "N°", "Caja", "Uni x", "Lleno"].every((c) => headT.indexOf(c) >= 0);
    out.sinUnidadCol = htmlT.indexOf(">Unidad<") < 0;   // la columna vieja "Unidad" no está

    // Separación en blanco (.gap) presente en ambas variantes.
    out.gap = !!dT.querySelector(".gap") && !!dO.querySelector(".gap");

    // OPERADOR tiene "Cajas Recibidas" y 3 columnas .recib; TALLERISTA no.
    out.recibOperador = headT.indexOf("Cajas Recibidas") < 0 && (dO.querySelector("thead").textContent || "").indexOf("Cajas Recibidas") >= 0;
    out.recib3 = dO.querySelectorAll("thead .recib").length >= 3;

    // Linea LK (rojo) / CH (azul) renderizadas con su clase.
    out.lineaLK = !!dT.querySelector("td.lin.lk") && !!dT.querySelector("td.lin.ch");

    // 123: falta 59, %lleno -33%
    out.falta123 = htmlT.indexOf(">59<") >= 0;
    out.pct123 = htmlT.indexOf("-33%") >= 0;
    // 518: %lleno 28% (redondeo de 28.2)
    out.pct518 = htmlT.indexOf("28%") >= 0;
    // N° Caja: los códigos con dato muestran su N_Caja
    out.ncaja = htmlT.indexOf(">29<") >= 0 && htmlT.indexOf(">2<") >= 0;
    // fila manual: "—" en las columnas derivadas
    out.manualGuion = htmlT.indexOf("—") >= 0;
    // total de cajas = 22+70+237+10 = 339
    out.total = htmlT.indexOf(">339<") >= 0;
    // ORDEN por % Lleno de menor a mayor: 123(-33) < 518(28) < 505(99) < manual(—, al final)
    const pos = function (cod) { return htmlT.indexOf(">" + cod + "<"); };
    out.orden = pos("123") < pos("518") && pos("518") < pos("505") && pos("505") < pos("999");

    // Consistencia: cada fila del cuerpo tiene tantas celdas como columnas.
    // TALLERISTA = 9 columnas; OPERADOR = 12 (9 + 3 Cajas Recibidas).
    const tdsT = dT.querySelector("tbody tr").querySelectorAll("td").length;
    const tdsO = dO.querySelector("tbody tr").querySelectorAll("td").length;
    out.colsTallerista = tdsT === 9;
    out.colsOperador = tdsO === 12;

    // sin teléfono → no aparece "Tel:"
    const x2 = { proveedor: "Poly", fecha: "2026-07-29", telefono: "", rows: [{ codigo: "31", descripcion: "X", linea: "LK", cantidad: 5, oc_max: 100, oc_pedidos: 0, oc_stock: 20, oc_uni_caja: 24 }] };
    out.sinTel = ocPrintHtml(x2).indexOf("Tel:") < 0;
    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("oc-print: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("oc-print: OK — impreso de OC (Linea + separación + N° Caja/Uni x Caja/% Lleno; variantes operador/tallerista)");
  process.exit(0);
})();
