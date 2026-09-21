/* v20.52 (Thomas, 2026-09-21) — DENTRO DEL BOTÓN DE IMPRIMIR, TAMBIÉN EXCEL.
   Pedido textual: *"dentro del botón de imprimir. dejame imprimir o descargar excel"*.

   Lo que fija este test:
     · el pop-up de «Imprimir» tiene los dos botones y comparten la misma selección de días;
     · «Ninguno» deshabilita LOS DOS — no se baja un Excel vacío;
     · el Excel sale PLANO: una fila por NP, con el día y la tanda repetidos en cada fila
       (un árbol en Excel no se filtra ni se ordena);
     · sólo entran los días tildados;
     · los m³ van con PUNTO decimal → Excel los toma como número y los suma;
     · trae la segunda hoja «Resumen» con el total por día y el total general;
     · el archivo que se baja es un .xlsx de verdad (ZIP: empieza con PK);
     · al bajarlo se cierra el pop-up.
   Estado inyectado; no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.getTodayKey = () => "2026-09-15";
    _pppParsed = { prog: [] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.pgaNeed = function () {};

    const mk = (f, t, np, rs, m3, est, o) => Object.assign({
      fecha: f, tanda: t, np: np, np_num: 0, cod: "2118", razon_social: rs, localidad: "Barracas",
      zona: "Zona 2 - CABA Centro", zona_corta: "Zona 2", empresa: np.startsWith("CH") ? "CH" : "LK",
      origen: /^(LK|CH) /.test(np) ? "web" : "isis", m3: m3, estado: est, estado_orden: 1,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11", pide_horario: false
    }, o || {});
    _pgaRows = [
      mk("2026-09-15", "E10A", "LK 0058", "Ricci Gabriel Edgardo", 1.2, "facturado"),
      mk("2026-09-15", "E10A", "98701", "Pettish Lacroze 2481", 0.9, "pendiente", { cod: "1974" }),
      mk("2026-09-15", "E10B", "LK 0060", "Lin Liqin", 2.5, "proceso", { cod: "4274" }),
      mk("2026-09-16", "E11A", "LK 0061", "Miguel Addoumie SRL", 1.35, "armado",
         { cod: "3958", pide_horario: true, horario_fecha: "2026-09-16", horario_franja: "08:00 a 12:00" }),
      mk("2026-09-16", "E11A", "CH 0019", "Osa Hermanos", 0.4, "pendiente", { cod: "2533" }),
      mk("2026-09-17", "E12A", "98700", "Andser Quimica", 1.3, "pendiente", { cod: "1000" })
    ];
    _pgaTs = Date.now();
    // v20.45: el destino (provincia) viaja aparte; la columna del Excel tiene que leerlo de ahí
    _pgaDest = new Map([["LK 0061", { provincia: "Misiones", expreso: "Andesmar", alerta: true }]]);
    window.fetch = async function () {
      return { ok: true, status: 200, json: async () => [], text: async () => "[]", headers: { get: () => null } };
    };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg(); await new Promise((res) => setTimeout(res, 250));

    pgaImprimirAbrir();
    const m = document.getElementById("pgiModal");
    out.hayExcel = !!document.getElementById("pgiXls");
    out.hayImprimir = !!document.getElementById("pgiOk");
    out.textoExcel = out.hayExcel ? document.getElementById("pgiXls").textContent.trim() : "";
    // los dos botones viven en la MISMA botonera, o sea que comparten la selección de días
    out.mismaBotonera = !!(out.hayExcel &&
      document.getElementById("pgiXls").closest(".pgi-btns") ===
      document.getElementById("pgiOk").closest(".pgi-btns"));

    // «Ninguno» tiene que deshabilitar los dos
    pgaImprimirTodos(false);
    out.ningunoDeshabilitaExcel = !!document.getElementById("pgiXls").disabled;
    out.ningunoDeshabilitaPrint = !!document.getElementById("pgiOk").disabled;
    pgaImprimirTodos(true);
    out.todosHabilitaExcel = !document.getElementById("pgiXls").disabled;

    // se espía lo que se manda a armar, sin romper el armado de verdad
    const orig = window._facXlsxBlob;
    let hojas = null, bytes = null, nombre = null, clicks = 0;
    window._facXlsxBlob = function (h) { hojas = h; return orig.apply(null, arguments); };
    const origClick = HTMLAnchorElement.prototype.click;
    HTMLAnchorElement.prototype.click = function () { clicks++; nombre = this.download; };

    const keys = _pgi.dias.map((d) => d.key);
    pgaImprimirTildar(keys[2], false);          // 2 de los 3 días
    pgaImprimirExcel();
    HTMLAnchorElement.prototype.click = origClick;
    window._facXlsxBlob = orig;

    out.clicks = clicks;
    out.nombre = nombre;
    out.cerroPopup = !!document.getElementById("pgiModal").hidden;
    out.hojas = (hojas || []).map((h) => h.nombre);
    const hoja = (hojas || [])[0] || { filas: [] };
    out.enc = hoja.filas[0] || [];
    out.filas = hoja.filas.slice(1);
    out.resumen = ((hojas || [])[1] || { filas: [] }).filas;

    // el blob que se baja tiene que ser un ZIP de verdad
    const blob = orig(hojas);
    bytes = new Uint8Array(await blob.arrayBuffer()).slice(0, 4);
    out.magic = String.fromCharCode(bytes[0], bytes[1]) + "," + bytes[2] + "," + bytes[3];
    out.mime = blob.type;
    return out;
  });

  await b.close();

  const ok = [];
  const chk = (c, d) => ok.push([!!c, d]);
  const col = (n) => r.enc.indexOf(n);

  chk(r.hayExcel, "el pop-up de «Imprimir» trae un botón de Excel");
  chk(/excel/i.test(r.textoExcel), "y dice Excel: " + JSON.stringify(r.textoExcel));
  chk(r.hayImprimir, "el botón de imprimir sigue estando");
  chk(r.mismaBotonera, "los dos salen de la MISMA selección de días (misma botonera)");
  chk(r.ningunoDeshabilitaExcel && r.ningunoDeshabilitaPrint,
      "«Ninguno» deshabilita los dos — no se baja un Excel vacío");
  chk(r.todosHabilitaExcel, "«Todos» vuelve a habilitar el de Excel");
  chk(r.clicks === 1, "baja el archivo una sola vez");
  chk(/^Programacion_20260915_a_20260916\.xlsx$/.test(r.nombre || ""),
      "el archivo se llama por el rango elegido: " + JSON.stringify(r.nombre));
  chk(r.cerroPopup, "al bajarlo se cierra el pop-up");
  chk(r.magic === "PK,3,4", "es un .xlsx de verdad (ZIP: PK\\x03\\x04): " + r.magic);
  chk(/spreadsheetml\.sheet$/.test(r.mime), "con el MIME de Excel: " + r.mime);
  chk(r.hojas.length === 2 && /Programaci/.test(r.hojas[0]) && r.hojas[1] === "Resumen",
      "trae dos hojas: " + JSON.stringify(r.hojas));

  chk(r.filas.length === 5, "sólo los días tildados: 5 NP de las 6 (el 17 queda afuera)");
  chk(!r.filas.some((f) => f[col("Tanda")] === "E12A"), "y ninguna fila del día no tildado");
  chk(r.filas.every((f) => f.length === r.enc.length),
      "toda fila tiene tantas celdas como el encabezado");
  // plano: el día y la tanda se repiten en cada fila, no hay renglón-título de tanda
  chk(r.filas.filter((f) => f[col("Tanda")] === "E10A").length === 2 &&
      r.filas.every((f) => f[col("Tanda")] && f[col("Día")]),
      "sale PLANO: el día y la tanda se repiten en cada fila (filtrable en Excel)");
  chk(col("NP") >= 0 && col("Cliente") >= 0 && col("m³") >= 0 && col("Estado") >= 0,
      "el encabezado tiene las columnas de la operación: " + JSON.stringify(r.enc));

  const f58 = r.filas.find((f) => f[col("NP")] === "LK 0058");
  chk(!!f58 && f58[col("Cliente")] === "Ricci Gabriel Edgardo",
      "cada fila trae la razón social");
  chk(!!f58 && f58[col("Cód cliente")] === "2118" && f58[col("Empresa")] === "LK",
      "el cód de cliente va en su columna, con la empresa al lado (la clave es (empresa, cod))");
  chk(!!f58 && f58[col("Estado")] === "Facturado", "y el estado en castellano");
  chk(!!f58 && f58[col("Fecha")] === "15/09/2026", "con la fecha del día");

  chk(r.filas.every((f) => /^\d+\.\d{3}$/.test(f[col("m³")])),
      "los m³ van con PUNTO decimal → Excel los suma como número: " +
      JSON.stringify(r.filas.map((f) => f[col("m³")])));
  chk(!!f58 && f58[col("m³")] === "1.200", "y con el valor de la NP, no el de la tanda");

  const f61 = r.filas.find((f) => f[col("NP")] === "LK 0061");
  chk(!!f61 && f61[col("Provincia destino")] === "Misiones",
      "la provincia de destino sale en su columna (v20.45: la zona es dónde va el camión)");
  chk(!!f61 && /08:00/.test(f61[col("Horario")] || ""), "y el horario pactado, si lo pide");
  chk(r.filas.filter((f) => f[col("Provincia destino")]).length === 1,
      "sin provincia resuelta la celda queda vacía — no se inventa");

  const tot = r.resumen[r.resumen.length - 1];
  chk(r.resumen.length === 4, "el Resumen trae un renglón por día + el total");
  chk(tot && tot[0] === "TOTAL" && tot[2] === "6.350" && tot[4] === "5",
      "y el total general cierra con la suma de los días tildados: " + JSON.stringify(tot));

  chk(errs.length === 0, "sin errores de JS: " + JSON.stringify(errs));

  let malas = 0;
  for (const [bien, d] of ok) { console.log((bien ? "  ok   " : "  FALLA") + " " + d); if (!bien) malas++; }
  console.log(malas ? "\n✗ " + malas + " de " + ok.length + " fallaron" : "\n✓ " + ok.length + " chequeos ok");
  process.exit(malas ? 1 : 0);
})();
