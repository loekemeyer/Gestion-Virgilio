/* v22.91 — Solapa 📒 Cta. proveedor (Thomas, 26/09: "debería estar la cta corriente de Hugo Wong, Becky
   Chen, Ownland"). Se verifica que la solapa exista, que arranque parada en el primer proveedor que manda
   el backend, que al elegir otro pida el libro con p_proveedor, que HOY liste los PI, que el LIBRO muestre
   el saldo corrido que viene del backend (no lo recalcula el front), que la HISTORIA (hoja + NTL) esté
   plegada y se abra, que avise cuando no hay hoja o cuando un PI no tiene giro, y que las fechas vayan
   dd/mm/aa. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const base = { prox_embarque: null, unidades: 0, m3: "0.000", fob_difiere: false, giros: 0, ultimo_giro: null,
      hoja_movs: 0, hoja_desde: null, hoja_hasta: null, hoja_saldo: null, ntl_movs: 0, ntl_girado: "0.00", ntl_recuperado: "0.00",
      ntl_ultimo: null, papa_real: null, papa_banco: null, papa_banco_factura: null, papa_banco_bl: null, papa_futuro: null, papa_fecha: null };
    const RES = [
      Object.assign({}, base, { prov: "Becky", empresa: "TN", pedidos: 2, fob: "55236.48", pagado: "7359.00", pend_giro_directo: "22441.00",
        falta: "25436.48", saldo: "47877.48", prox_llegada: "2026-09-29", giros: 1, ultimo_giro: "2026-06-02", ntl_movs: 9, ntl_girado: "48218.08" }),
      Object.assign({}, base, { prov: "Ownland", empresa: "CH", pedidos: 1, fob: "49291.44", pagado: "14000.00", pend_giro_directo: "20956.00",
        falta: "14335.44", saldo: "35291.44", prox_embarque: "2026-11-08", prox_llegada: "2026-12-18", giros: 1, ultimo_giro: "2026-09-09",
        hoja_movs: 21, hoja_desde: "2025-01-27", hoja_hasta: "2026-06-03", hoja_saldo: "34956.08", ntl_movs: 11, ntl_girado: "79951.04", ntl_recuperado: "52110.96",
        papa_real: "35291.00", papa_banco: "20956.00", papa_banco_factura: "Ownland", papa_banco_bl: "2026-06-05", papa_futuro: "49291.00", papa_fecha: "2026-09-16" }),
      Object.assign({}, base, { prov: "Hugo Wong", empresa: "TN", pedidos: 2, fob: "39240.00", pagado: "17041.00", pend_giro_directo: "21952.00",
        falta: "247.00", saldo: "22199.00", prox_llegada: "2026-11-03", giros: 3, ultimo_giro: "2026-09-12", ntl_movs: 16, ntl_girado: "92458.28",
        ntl_recuperado: "41658.41", papa_real: "24599.00", papa_banco: "21952.00", papa_banco_factura: "Hugo", papa_banco_bl: "2026-06-05", papa_futuro: "38640.00", papa_fecha: "2026-09-16" })
    ];
    const row = (o) => Object.assign({ orden: 0, carga: null, a_traves_de: null, canal: null, fob: null, pago: null, recupero: null, saldo: null, saldo_excel: null,
      pagado: null, pend_giro: null, falta: null, embarque: null, llegada: null, unidades: null, m3: null, fob_difiere: null, detalle: "", empresa: null }, o);
    const LIBRO = {
      "Hugo Wong": [
        row({ fuente: "pedido", fecha: "2026-07-30", concepto: "PI NY26-031438", carga: "PI NY26-031438", canal: "Hugo Wong", fob: "38640.00", saldo: "38640.00",
          pagado: "16441.00", pend_giro: "21952.00", falta: "247.00", embarque: "2026-09-19", llegada: "2026-11-03", detalle: "11 línea(s) · 43000 u · 62.4 m³" }),
        row({ fuente: "giro", fecha: "2026-07-30", orden: 6, concepto: "Anticipo → Hugo Wong", carga: "PI NY26-031438", canal: "Bco", pago: "14041", saldo: "24599.00", detalle: "Seed Excel 11/09" }),
        row({ fuente: "pedido", fecha: "2026-09-11", concepto: "Pedido 323ES suelto", carga: "323ES suelto", fob: "600.00", saldo: "25199.00", pagado: "600.00", pend_giro: "0.00", falta: "0.00", llegada: "2026-09-22" }),
        row({ fuente: "giro", fecha: "2026-09-12", orden: 7, concepto: "Saldo → Hugo Wong", carga: "PI NY26-031438", canal: "Bco", pago: "2400", saldo: "22799.00" }),
        row({ fuente: "giro", fecha: "2026-09-12", orden: 8, concepto: "Saldo → Hugo Wong", carga: "323ES suelto", canal: "Bco", pago: "600", saldo: "22199.00" }),
        row({ fuente: "ntl", fecha: "2026-01-05", orden: 120, concepto: "Balance", canal: "NTL", pago: "8400.0", empresa: "TN", detalle: "Extracto NTL · fila 120" }),
        row({ fuente: "ntl", fecha: "2026-09-04", orden: 181, concepto: "Recupero Hugo Wong", canal: "NTL", recupero: "1183.0", empresa: "TN", detalle: "Extracto NTL · fila 181" })
      ],
      "Ownland": [
        row({ fuente: "hoja", fecha: "2026-03-13", orden: 22, concepto: "Giro ", carga: "CQ-9694", a_traves_de: "CQ- 9553", pago: "14000.0", saldo_excel: "20990.08", detalle: "Hoja Ownland · fila 22" }),
        row({ fuente: "hoja", fecha: "2026-06-03", orden: 24, concepto: "Factura / carga China 52", carga: "CQ-9694", fob: "34956.0", saldo_excel: "34956.08", detalle: "Hoja Ownland · fila 24" }),
        row({ fuente: "pedido", fecha: "2026-09-09", concepto: "PI OL-10139", carga: "PI OL-10139", canal: "Ownland", fob: "49291.44", saldo: "49291.44",
          pagado: "14000.00", pend_giro: "20956.00", falta: "14335.44", embarque: "2026-11-08", llegada: "2026-12-18" }),
        row({ fuente: "giro", fecha: "2026-09-09", orden: 4, concepto: "Anticipo → Ownland", carga: "PI OL-10139", canal: "Bco", pago: "14000", saldo: "35291.44" }),
        row({ fuente: "ntl", fecha: "2025-12-30", orden: 140, concepto: "Recupero Ownland", canal: "NTL", recupero: "12000.0", empresa: "CH" })
      ],
      "Becky": [
        row({ fuente: "pedido", fecha: "2026-06-02", concepto: "PI B260601-2", carga: "PI B260601-2", canal: "Becky", fob: "31614.00", saldo: "31614.00", pagado: "7359.00", pend_giro: "22441.00", falta: "1814.00" }),
        row({ fuente: "giro", fecha: "2026-06-02", orden: 5, concepto: "Anticipo → Becky", carga: "PI B260601-2", canal: "Bco", pago: "7359", saldo: "24255.00" }),
        row({ fuente: "pedido", fecha: "2026-09-11", concepto: "PI B260601", carga: "PI B260601", fob: "23622.48", saldo: "47877.48", pagado: "0.00", pend_giro: "0.00", falta: "23622.48", llegada: "2026-09-29" })
      ]
    };
    const calls = [];
    window.fetch = async (u, o) => {
      const url = String(u); calls.push({ u: url.split("/rest/v1/")[1] || url, b: o && o.body });
      let data = [];
      if (url.indexOf("gv_imp_prov_cc_resumen") >= 0) data = RES;
      else if (url.indexOf("gv_imp_prov_cc_libro") >= 0) { const q = JSON.parse(o.body || "{}"); data = LIBRO[q.p_proveedor] || []; }
      return { ok: true, status: 200, json: async () => data, text: async () => "" };
    };
    const body = () => document.getElementById("stkPopBody");
    const txt = () => body().innerText.replace(/\s+/g, " ");
    const filas = (id) => { const t = document.getElementById(id); return t ? [...t.tBodies[0].rows] : null; };

    out.tab = _impTabsHtml("ntl").indexOf("openImpProvCC()") >= 0;
    await openImpProvCC();
    out.chips = [...body().querySelectorAll(".ipc-prov button")].map((x) => ({ t: x.innerText.trim(), on: x.classList.contains("on") }));
    out.primero = _impProv.prov;                                    // arranca en el primero del backend
    out.becky = txt();
    out.beckyAvisoSinGiro = /PI B260601 no tiene ning[úu]n giro cargado/.test(out.becky);
    out.beckyLibroFilas = (filas("ipcLibro") || []).length;
    // → Hugo Wong
    calls.length = 0;
    await impProvSet(encodeURIComponent("Hugo Wong"));
    out.callLibro = calls.filter((c) => c.u.indexOf("rpc/gv_imp_prov_cc_libro") === 0).map((c) => JSON.parse(c.b));
    const t = txt(); out.hugo = t;
    out.hoyFilas = (filas("ipcHoy") || []).length;
    out.libroFilas = (filas("ipcLibro") || []).length;
    const lib = filas("ipcLibro") || [];
    out.saldoUltimo = lib.length ? lib[lib.length - 1].cells[6].innerText.trim() : null;
    out.saldoPrimero = lib.length ? lib[0].cells[6].innerText.trim() : null;
    out.cardDeuda = /Le debemos hoy u\$s 22\.199/i.test(t);          // el título va en mayúsculas por CSS
    out.cardBanco = /Por banco, contra factura vieja u\$s 21\.952/i.test(t) && /factura Hugo · BL 05\/06\/26/.test(t);
    out.fechaDdMmAa = /30\/07\/26/.test(t);
    out.avisoSinHoja = /Sin hoja hist[óo]rica/.test(t);
    out.avisoPapa = /formato pap[áa]/.test(t);                     // 24.599 vs 22.199 → avisa
    out.histPlegada = !document.getElementById("ipcNtl") && !document.getElementById("ipcHoja");
    out.canales = [...body().querySelectorAll("#ipcLibro .ipc-chip")].map((x) => x.innerText.trim());
    impProvToggleHist();
    out.ntlFilas = (filas("ipcNtl") || []).length;
    out.hojaHugo = !!document.getElementById("ipcHoja");
    // → Ownland: tiene hoja, no avisa "sin hoja", y la historia muestra la hoja con SU saldo
    await impProvSet(encodeURIComponent("Ownland"));
    const to = txt(); out.own = to;
    out.ownSinAvisoHoja = !/Sin hoja hist[óo]rica/.test(to);
    out.ownHojaFilas = (filas("ipcHoja") || []).length;              // la historia sigue abierta (estado)
    const hj = filas("ipcHoja") || [];
    out.ownSaldoHoja = hj.length ? hj[hj.length - 1].cells[7].innerText.trim() : null;
    out.ownFactura = /China 52/.test(to);
    // Excel: arma el archivo y dispara la descarga una vez
    let urls = 0; const oc = URL.createObjectURL; URL.createObjectURL = () => { urls++; return "blob:x"; };
    const oclick = HTMLAnchorElement.prototype.click; HTMLAnchorElement.prototype.click = function () {};
    impProvExportExcel();
    URL.createObjectURL = oc; HTMLAnchorElement.prototype.click = oclick;
    out.excel = urls;
    return out;
  });

  console.log(JSON.stringify({ ...r, becky: (r.becky || "").slice(0, 160), hugo: (r.hugo || "").slice(0, 200), own: (r.own || "").slice(0, 120) }, null, 1));
  if (!r.tab) fail("la solapa 📒 Cta. proveedor no está en la barra del módulo");
  if (!r.chips || r.chips.length !== 3) fail("deberían verse 3 fichas de proveedor: " + JSON.stringify(r.chips));
  if (r.primero !== "Becky" || !(r.chips && r.chips[0].on)) fail("no arranca parado en el primer proveedor que manda el backend: " + r.primero);
  if (!r.beckyAvisoSinGiro) fail("no avisa el PI sin ningún giro cargado (PI B260601): " + r.becky);
  if (r.beckyLibroFilas !== 3) fail("el libro de Becky debería tener 3 renglones, tiene " + r.beckyLibroFilas);
  if (r.callLibro.length !== 1 || r.callLibro[0].p_proveedor !== "Hugo Wong") fail("elegir un proveedor no pide su libro con p_proveedor: " + JSON.stringify(r.callLibro));
  if (r.hoyFilas !== 2) fail("HOY debería listar los 2 PI de Hugo Wong, listó " + r.hoyFilas);
  if (r.libroFilas !== 5) fail("el LIBRO debería tener 5 renglones (2 PI + 3 giros, sin la historia), tiene " + r.libroFilas);
  if (r.saldoPrimero !== "38.640,00" || r.saldoUltimo !== "22.199,00") fail("el saldo corrido no es el del backend (38.640,00 → 22.199,00): " + r.saldoPrimero + " → " + r.saldoUltimo);
  if (!r.cardDeuda) fail("la ficha 'Le debemos hoy' no muestra 22.199: " + r.hugo);
  if (!r.cardBanco) fail("la ficha 'Por banco' no muestra 21.952 con la factura Hugo · BL 05/06/26: " + r.hugo);
  if (!r.fechaDdMmAa) fail("las fechas no van dd/mm/aa (30/07/26): " + r.hugo);
  if (!r.avisoSinHoja) fail("Hugo Wong no tiene hoja del Excel y no lo avisa");
  if (!r.avisoPapa) fail("el formato papá dice 24.599 y la planilla 22.199: tendría que avisar la diferencia");
  if (!r.histPlegada) fail("la historia tendría que arrancar plegada");
  if (!r.canales || r.canales.indexOf("Banco") < 0) fail("el canal del giro no se muestra como chip Banco: " + JSON.stringify(r.canales));
  if (r.ntlFilas !== 2) fail("al abrir la historia deberían verse los 2 renglones del extracto NTL, hay " + r.ntlFilas);
  if (r.hojaHugo) fail("Hugo Wong no tiene hoja y se dibujó la tabla de la hoja igual");
  if (!r.ownSinAvisoHoja) fail("Ownland tiene hoja del Excel y avisa que no la tiene");
  if (r.ownHojaFilas !== 2) fail("la hoja de Ownland debería mostrar 2 renglones, muestra " + r.ownHojaFilas);
  if (r.ownSaldoHoja !== "34.956,08") fail("el saldo de la hoja tiene que ser el del Excel (34.956,08), no uno rehecho: " + r.ownSaldoHoja);
  if (!r.ownFactura) fail("la fila de factura de la hoja (China 52) no se ve");
  if (r.excel !== 1) fail("⬇ Excel no armó el archivo (createObjectURL " + r.excel + " veces)");
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-cta-proveedor OK");
})();
