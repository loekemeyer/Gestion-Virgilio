/* v14.08 — Facturación muestra la FECHA DE ENTREGA de la PPP como columna.
   Dueño 07/09, con captura de "Facturación — NPs a FC": "acá pone la fecha de la PPP también" · "de
   entrega". El dato ya lo tenía la fila (`fechaSalida`, que es la fecha de entrega de la tanda) pero
   vivía sólo en el globito del número de NP: había que pasar el mouse por cada uno.
   (a) hay una columna 📅 Entrega y sale una celda por NP con su fecha;
   (b) es la fecha de la tanda de cada NP, no una sola para toda la tabla;
   (c) las filas siguen ordenadas por esa fecha (lo más viejo arriba);
   (d) si una tanda no tiene fecha, la celda dice — y no rompe;
   (e) no se perdió ninguna de las columnas que ya estaban.
   Sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  // v15.40: sin este fallback el test muere en CI (el runner instala playwright con npm,
  // no tiene /opt/node22) y, como run.sh corta en el primero que falla, todo lo que venía
  // después NUNCA se corrió en GitHub. Mismo patrón que ya tenían los demás tests.
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1500, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // el contenedor que pinta facRender
    let c = document.getElementById("facContainer");
    if (!c) { c = document.createElement("div"); c.id = "facContainer"; document.body.appendChild(c); }
    for (const id of ["facCntTandas", "facCntNps"]) {
      if (!document.getElementById(id)) { const e = document.createElement("span"); e.id = id; document.body.appendChild(e); }
    }
    // sin filtros ni "ya facturadas", y todas cuentan como armadas
    _facNpsHoy = new Set(); _facNpsTodos = new Set();
    window.facEstaArmada = () => true;
    window.facFaltInfo = () => null;
    window.facTareaActiva = () => null;
    window.facFaltAgregDist = () => "";
    window.facNpEsWeb = (np) => String(np) === "98600";
    window.facPaintNeto = () => {};
    _facLios = new Map(); _facCajas = new Map(); _facClase = new Map();

    const ped = (np, cod, rs) => ({ np: np, cod: cod, razonSocial: rs, direccion: "x", m3: 0.2, barrio: "Soldati", zona: "Zona 1 - CABA Sur" });
    // a propósito DESORDENADAS: la del 10 primero, para ver que ordena por fecha
    facRender([
      { tanda: "D66C", fechaEntrega: "10/09/2026", fechaEntregaRaw: "2026-09-10", pedidos: [ped("98700", "1001", "Cliente Diez")] },
      { tanda: "D66B", fechaEntrega: "09/09/2026", fechaEntregaRaw: "2026-09-09", pedidos: [ped("98650", "2533", "Osa Distribuidora"), ped("98667", "2533", "Osa Distribuidora")] },
      { tanda: "D99Z", fechaEntrega: "",           fechaEntregaRaw: "",           pedidos: [ped("98600", "4242", "Sin Fecha SRL")] }
    ]);
    const h = c.innerHTML;
    out.html = h;
    out.hayColumna = /📅 Entrega/.test(h);
    out.celdas = (h.match(/class="center fac-fe-cell"/g) || []).length;
    // (b) cada NP con la fecha de SU tanda
    const fila = (np) => { const m = new RegExp('<tr data-fac-np="' + np + '"[\\s\\S]*?</tr>').exec(h); return m ? m[0] : ""; };
    out.f98650 = /09\/09\/2026/.test(fila("98650"));
    out.f98667 = /09\/09\/2026/.test(fila("98667"));
    out.f98700 = /10\/09\/2026/.test(fila("98700"));
    out.sinFecha = /fac-lios0">—<\/span>/.test(fila("98600")) && !/\d{2}\/\d{2}\/\d{4}/.test(fila("98600"));
    // (c) orden por fecha: las del 09 antes que la del 10
    out.orden = h.indexOf('data-fac-np="98650"') < h.indexOf('data-fac-np="98700"');
    // (e) las columnas de siempre
    out.columnas = ["Cod", "Razón Social", "Faltantes y Agregados", "Líos", "Cajas", "Subtotal", "Acción"]
      .filter((t) => h.indexOf(t) < 0);
    // los anchos suman 100
    out.anchos = (h.match(/width:(\d+)%/g) || []).reduce((a, x) => a + Number(/(\d+)/.exec(x)[1]), 0);
    return out;
  });
  await b.close();

  const fails = [];
  const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fails.push(m); };
  chk(r.hayColumna, "la tabla tiene la columna 📅 Entrega");
  chk(r.celdas === 4, "una celda de fecha por NP (4): " + r.celdas);
  chk(r.f98650 && r.f98667, "las dos NP de la D66B muestran el 09/09/2026");
  chk(r.f98700, "la de la D66C muestra el 10/09/2026 — es la de SU tanda, no una sola para todas");
  chk(r.sinFecha, "una tanda sin fecha muestra — y no rompe");
  chk(r.orden, "las filas siguen ordenadas por fecha de entrega");
  chk(r.columnas.length === 0, "no se perdió ninguna columna" + (r.columnas.length ? ": falta " + r.columnas.join(", ") : ""));
  chk(r.anchos === 100, "los anchos de la tabla siguen sumando 100%: " + r.anchos);
  chk(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  if (fails.length) { console.error("\nFALLARON " + fails.length + ":\n· " + fails.join("\n· ")); process.exit(1); }
  console.log("\nfac-fecha-entrega OK");
})();
