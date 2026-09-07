/* v13.73 — Cruce factura ISIS ↔ Gestión como pantalla (pendiente 10 del dueño, 07/09: "11 porque no?").
   (a) Facturación tiene el botón "🔍 Cruce con ISIS" que abre la pestaña "cruce" de Deuda/Cobranzas
       (openCobros acepta la pestaña directo);
   (b) la pestaña manda el rango de fechas a gv_cruce_facturacion_resumen y pide los totales del rango
       a gv_cruce_facturacion_totales;
   (c) la tabla muestra cajas entregadas / facturadas, NP web (LK 0004) y numéricas juntas, el estado,
       el nº de comprobante y el botón 📄 para abrir el PDF (sólo si hay storage_path).
   RPC interceptadas por fetch, sin red. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__isSupervisor = true;
    window.requireSupervisor = function () { return true; };
    const calls = [];
    const filas = [
      { np: "98702", tanda: "D68A", fecha_salida: "2026-09-03", rs_virgilio: "SALVETTI", cod_cliente: "1651", empresa: "lk", neto_calculado: 1000000, cajas_ent: 40, items_sin_precio: 0,
        doc_id: 1, comprobante_id: "A-0003-00012345", doc_fecha: "2026-09-04", factura_total: 1250000, factura_neto: 1010000, factura_cajas: 40, storage_path: "2026/09/fa_12345.pdf", cae: "1", candidatos_cercanos: 1, diff: 10000, diff_pct: 1, estado: "ok", es_super: false, total_count: 3 },
      { np: "LK 0004", tanda: "E01A", fecha_salida: "2026-09-04", rs_virgilio: "PEDIDO WEB", cod_cliente: "302", empresa: "lk", neto_calculado: 500000, cajas_ent: 12, items_sin_precio: 1,
        doc_id: null, comprobante_id: null, doc_fecha: null, factura_total: null, factura_neto: null, factura_cajas: null, storage_path: null, cae: null, candidatos_cercanos: 0, diff: null, diff_pct: null, estado: "sin_factura", es_super: false, total_count: 3 },
      { np: "44601", tanda: "D69D", fecha_salida: "2026-09-02", rs_virgilio: "CHEF CLIENTE", cod_cliente: "801", empresa: "chef", neto_calculado: 8561760, cajas_ent: 300, items_sin_precio: 2,
        doc_id: 2, comprobante_id: "A-0001-00000777", doc_fecha: "2026-09-02", factura_total: 9500000, factura_neto: 7791011.1, factura_cajas: 298, storage_path: "2026/09/ch_777.pdf", cae: "2", candidatos_cercanos: 1, diff: -770748.9, diff_pct: -9, estado: "diff", es_super: false, total_count: 3 }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_cruce_facturacion_resumen") return ok(filas);
        if (m[1] === "gv_cruce_facturacion_totales") return ok([{ estado: "ok", n: 1, suma_diff: 10000 }, { estado: "diff", n: 1, suma_diff: -770748.9 }, { estado: "sin_factura", n: 1, suma_diff: 0 }]);
        return ok([]);
      }
      return ok([]);
    };

    // (a) botón en Facturación
    const btn = document.getElementById("facBtnCruce");
    out.btn = btn ? btn.getAttribute("onclick") : null;
    openCobros("cruce");
    await new Promise((res) => setTimeout(res, 400));
    out.tab = document.getElementById("cruceTabla") ? "cruce" : (document.getElementById("deudaTabla") ? "deuda" : "?");
    out.calls = calls.map((c) => c.fn);
    const c1 = calls.find((c) => c.fn === "gv_cruce_facturacion_resumen");
    out.rango = c1 ? { desde: c1.body.p_desde, hasta: c1.body.p_hasta } : null;
    const tabla = document.getElementById("cruceTabla");
    const resumen = document.getElementById("cruceResumen");
    out.html = tabla ? tabla.innerHTML : "";
    out.resumen = resumen ? resumen.textContent : "";
    out.filas = tabla ? tabla.querySelectorAll("tbody tr").length : 0;
    out.pdf = tabla ? tabla.querySelectorAll("button.cruce-pdf").length : 0;
    out.inputs = !!document.getElementById("cruceDesde") && !!document.getElementById("cruceHasta");
    // cambiar el rango → nueva llamada con las fechas nuevas
    calls.length = 0;
    document.getElementById("cruceDesde").value = "2026-08-01";
    document.getElementById("cruceDesde").dispatchEvent(new Event("change"));
    await new Promise((res) => setTimeout(res, 300));
    const c2 = calls.find((c) => c.fn === "gv_cruce_facturacion_resumen");
    out.rango2 = c2 ? c2.body.p_desde : null;
    // 📄 → deudaAbrirFactura con la empresa y el path
    let abierto = null;
    window.deudaAbrirFactura = async (e, sp) => { abierto = { e, sp }; };
    document.querySelector("button.cruce-pdf").click();
    await new Promise((res) => setTimeout(res, 50));
    out.abierto = abierto;
    // los filtros inline (oninput/onchange) de las 4 pestañas necesitan los estados en window
    out.globales = ["_deudaState", "_cruceState", "_antState", "_bancoState"].filter((k) => typeof window[k] !== "object");
    return out;
  });
  await b.close();

  const fails = [];
  if (r.btn !== "openCobros('cruce')") fails.push("falta el botón Cruce con ISIS en Facturación: " + r.btn);
  if (r.tab !== "cruce") fails.push("openCobros('cruce') no abrió la pestaña cruce: " + r.tab);
  if (!r.calls.includes("gv_cruce_facturacion_resumen")) fails.push("no llamó a gv_cruce_facturacion_resumen");
  if (!r.calls.includes("gv_cruce_facturacion_totales")) fails.push("no pidió los totales del rango");
  if (!r.rango || !/^\d{4}-\d{2}-\d{2}$/.test(r.rango.desde || "") || !/^\d{4}-\d{2}-\d{2}$/.test(r.rango.hasta || "")) fails.push("rango de fechas no viaja: " + JSON.stringify(r.rango));
  if (!r.inputs) fails.push("faltan los inputs desde/hasta");
  if (r.filas !== 3) fails.push("esperaba 3 filas, hay " + r.filas);
  if (r.pdf !== 2) fails.push("esperaba 2 botones 📄 (sólo con storage_path), hay " + r.pdf);
  if (!/LK 0004/.test(r.html)) fails.push("la NP web no aparece junto con las numéricas");
  if (!/40 \/ 40/.test(r.html)) fails.push("cajas ent / fact no se ve (40 / 40)");
  if (!/300 \/ 298/.test(r.html)) fails.push("cajas distintas no se ven (300 / 298)");
  if (!/A-0003-00012345/.test(r.html)) fails.push("falta el nº de comprobante");
  if (!/Sin factura/.test(r.html) || !/Diferencia/.test(r.html)) fails.push("faltan los estados");
  if (!/1 OK/.test(r.resumen) || !/1 con diferencia/.test(r.resumen)) fails.push("el resumen no usa los totales del rango: " + r.resumen);
  if (!/2 s\/precio/.test(r.html)) fails.push("no marca los artículos sin precio");
  if (r.rango2 !== "2026-08-01") fails.push("cambiar 'desde' no refresca con la fecha nueva: " + r.rango2);
  if (!r.abierto || r.abierto.e !== "lk" || r.abierto.sp !== "2026/09/fa_12345.pdf") fails.push("📄 no abre la factura: " + JSON.stringify(r.abierto));
  if (/undefined|NaN/.test(r.html)) fails.push("undefined/NaN en la tabla");
  if (r.globales.length) fails.push("estados de filtros no globales (los oninput tiran 'not defined'): " + r.globales.join(", "));
  if (errs.length) fails.push("pageerror: " + errs.join(" | "));

  if (fails.length) { console.error("FAIL fac-cruce:\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("OK fac-cruce: botón en Facturación → pestaña cruce, rango de fechas, totales, cajas ent/fact, NP web + ISIS juntas, 📄 abre el PDF");
})();
