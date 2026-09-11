/* v15.74 — Vista PLATA de 🚢 En curso: la cuenta corriente con los chinos, calcada del Excel de
   Thomas. Se verifica: que la solapa tenga las dos vistas, que la tabla de plata traiga las
   columnas del Excel, que Falta = FOB − Pagado − Pend. giro directo, que los totales de arriba
   sigan el filtro, que editar un campo mande la RPC con su p_set_* y que el pop-up de giros
   liste, sume y permita cargar uno. */
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
    window._impCursoHoy = () => "2026-09-11";
    // dos pedidos: uno a nombre de NTL (sin giro directo) y otro a nombre del proveedor (con giro)
    const PEDIDOS = [
      { pedido_ref: "PI HT26-06-600-R1", proveedor: "Fujian", n_lineas: 11, unidades: 106488,
        pendiente: 106488, usd: "32388.00", m3: "32.5", fecha_embarque: "2026-09-19", fecha_llegada: "2026-11-01" },
      { pedido_ref: "PI OL-10139", proveedor: "Ownland", n_lineas: 13, unidades: 98376,
        pendiente: 98376, usd: "46626.00", m3: "21.9", fecha_embarque: "2026-11-08", fecha_llegada: "2026-12-18" }
    ];
    const CC = [
      { pedido_ref: "PI HT26-06-600-R1", proveedor: "Fujian", a_nombre_de: "NTL", fob: "32388.00",
        pagado: "10000.00", pend_giro_directo: "0.00", falta: "22388.00", n_pagos: 1,
        fecha_pago_30: "2026-08-05", fecha_recup: "2026-09-25", dias_produccion: 45, fob_difiere: false, fob_calculado: "32388.00" },
      { pedido_ref: "PI OL-10139", proveedor: "Ownland", a_nombre_de: "Ownland", fob: "46626.00",
        pagado: "14000.00", pend_giro_directo: "20956.00", falta: "11670.00", n_pagos: 1,
        fecha_pago_30: "2026-09-09", fecha_recup: null, dias_produccion: 60, fob_difiere: false, fob_calculado: "46626.00" }
    ];
    const GIROS = [
      { id: 7, fecha: "2026-08-05", monto_usd: "10000.00", beneficiario: "NTL", tipo: "anticipo30",
        factura_ref: "", nota: "seed" }
    ];
    const calls = [];
    window.fetch = async (u, o) => {
      const url = String(u); calls.push({ u: url.split("/rest/v1/")[1] || url, b: o && o.body });
      let data = [];
      if (url.indexOf("gv_importados_pedidos_curso") >= 0) data = PEDIDOS;
      else if (url.indexOf("gv_imp_cc_lista") >= 0) data = CC;
      else if (url.indexOf("gv_imp_pagos") >= 0) data = GIROS;
      else if (url.indexOf("gv_imp_cc_set") >= 0) data = { id: 1 };
      else if (url.indexOf("gv_imp_pago_add") >= 0) data = { pago_id: 9 };
      return { ok: true, status: 200, json: async () => data, text: async () => "" };
    };

    await openImpEnCurso();
    out.pidioCc = calls.some((c) => c.u.indexOf("rpc/gv_imp_cc_lista") === 0);
    const body = () => document.getElementById("stkPopBody");
    out.hayToggle = /Plata/.test(body().innerText);

    // ---- vista PLATA ----
    impCursoSetVista(true);
    const t = body().innerText.replace(/\s+/g, " ");
    out.txt = t;
    out.cols = [...body().querySelectorAll(".imcu-tbl thead th")].map((x) => x.innerText.trim());
    const filas = [...body().querySelector(".imcu-tbl").tBodies[0].rows];
    out.nFilas = filas.length;
    out.f0 = filas[0].innerText.replace(/\s+/g, " ").trim();
    out.inputs0 = [...filas[0].querySelectorAll("input")].map((i) => i.value);
    out.inputs1 = [...filas[1].querySelectorAll("input")].map((i) => i.value);
    // Falta = FOB − Pagado − Pend giro
    out.faltas = filas.map((tr) => tr.querySelector(".imcu-falta").innerText.trim());

    // ---- editar la cabecera manda la RPC con su p_set_* ----
    calls.length = 0;
    await impCursoCcSet(encodeURIComponent("PI OL-10139"), encodeURIComponent("Ownland"), "pendgiro", "21000");
    out.callGiro = calls.filter((c) => c.u.indexOf("rpc/gv_imp_cc_set") === 0).map((c) => JSON.parse(c.b));
    calls.length = 0;
    await impCursoCcSet(encodeURIComponent("PI OL-10139"), encodeURIComponent("Ownland"), "nombre", "NTL");
    out.callNom = calls.filter((c) => c.u.indexOf("rpc/gv_imp_cc_set") === 0).map((c) => JSON.parse(c.b));

    // ---- pop-up de giros ----
    calls.length = 0;
    await impCursoPagos(encodeURIComponent("PI HT26-06-600-R1"), encodeURIComponent("Fujian"));
    out.ovAbre = document.getElementById("impPagosOv").classList.contains("show");
    out.ovTxt = document.getElementById("impPagosOv").innerText.replace(/\s+/g, " ");
    out.callPagos = calls.filter((c) => c.u.indexOf("rpc/gv_imp_pagos") === 0).map((c) => JSON.parse(c.b));
    // cargar un giro nuevo
    const respuestas = ["5000", "10/09/26", "NTL", "2", "FC B-123"];
    let i = 0; window.prompt = () => respuestas[i++];
    calls.length = 0;
    await impPagoAdd();
    out.callAdd = calls.filter((c) => c.u.indexOf("rpc/gv_imp_pago_add") === 0).map((c) => JSON.parse(c.b));
    impPagosCerrar();
    out.ovCierra = !document.getElementById("impPagosOv").classList.contains("show");

    // ---- volver a logística ----
    impCursoSetVista(false);
    out.volvio = /embarque/i.test(body().innerText) && !/pend\. giro directo/i.test(body().innerText);
    return out;
  });

  console.log(JSON.stringify(r, null, 1));
  if (!r.pidioCc) fail("no pide la cuenta corriente al abrir la pantalla");
  if (!r.hayToggle) fail("no está el botón de la vista Plata");
  const cols = (r.cols || []).join("|").toLowerCase();   // los th van en uppercase por CSS
  ["A nombre de", "FOB", "Pagado", "Pend. giro directo", "Falta"].forEach(function (c) {
    if (cols.indexOf(c.toLowerCase()) < 0) fail("falta la columna del Excel '" + c + "': " + cols);
  });
  if (r.nFilas !== 2) fail("deberían ser 2 filas: " + r.nFilas);
  if (r.faltas.join("|") !== "22.388|11.670") fail("Falta = FOB − Pagado − Pend giro: esperaba 22.388|11.670, vino " + r.faltas.join("|"));
  if (r.inputs0.join("|") !== "NTL|32388||05/08/26|19/09/26|25/09/26") fail("fila NTL mal: " + r.inputs0.join("|"));
  if (r.inputs1.join("|") !== "Ownland|46626|20956|09/09/26|08/11/26|") fail("fila del proveedor mal: " + r.inputs1.join("|"));
  if (!/u\$s 79\.014/.test(r.txt)) fail("el KPI de FOB debería sumar 32.388 + 46.626 = 79.014: " + r.txt.slice(0, 300));
  if (!/u\$s 24\.000/.test(r.txt)) fail("el KPI de Pagado debería sumar 24.000: " + r.txt.slice(0, 300));
  if (!/u\$s 34\.058/.test(r.txt)) fail("el KPI de Falta debería sumar 22.388 + 11.670 = 34.058: " + r.txt.slice(0, 300));
  if (r.callGiro.length !== 1 || r.callGiro[0].p_pend_giro !== 21000 || r.callGiro[0].p_set_pend_giro !== true
      || r.callGiro[0].p_set_fob) fail("editar el giro directo mal: " + JSON.stringify(r.callGiro));
  if (r.callNom.length !== 1 || r.callNom[0].p_a_nombre_de !== "NTL" || r.callNom[0].p_set_a_nombre_de !== true)
    fail("editar 'a nombre de' mal: " + JSON.stringify(r.callNom));
  if (!r.ovAbre) fail("no abre el pop-up de giros");
  if (r.callPagos.length !== 1 || r.callPagos[0].p_pedido_ref !== "PI HT26-06-600-R1") fail("no pide los giros del pedido: " + JSON.stringify(r.callPagos));
  if (!/10\.000/.test(r.ovTxt) || !/anticipo 30%/.test(r.ovTxt)) fail("el pop-up no lista el giro: " + r.ovTxt);
  if (!/falta u\$s 22\.388/i.test(r.ovTxt)) fail("el pie del pop-up no calcula lo que falta: " + r.ovTxt);
  if (r.callAdd.length !== 1) fail("no cargó el giro nuevo: " + JSON.stringify(r.callAdd));
  else {
    const a = r.callAdd[0];
    if (a.p_monto !== 5000 || a.p_fecha !== "2026-09-10" || a.p_beneficiario !== "NTL"
        || a.p_tipo !== "saldo" || a.p_factura !== "FC B-123") fail("el giro nuevo va con datos mal: " + JSON.stringify(a));
  }
  if (!r.ovCierra) fail("no cierra el pop-up de giros");
  if (!r.volvio) fail("no vuelve a la vista de logística");
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-cuenta-corriente OK");
})();
