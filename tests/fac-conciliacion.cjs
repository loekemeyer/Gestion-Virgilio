/* v14.30 — Facturación en dos pestañas: "Facturador" (lo de siempre) y "Conciliación".
   Conciliación = snapshot forward-looking de lo que Gestión mandó a facturar (neto congelado)
   vs el neto de la factura parseada de ISIS (en vivo). Chequea:
   (a) existen las dos solapas y facSetTab alterna los paneles (#facPanelFact / #facPanelConcil);
   (b) al entrar a Conciliación llama a gv_conciliacion_lista + gv_conciliacion_totales y dibuja las filas;
   (c) la fila muestra el neto de Gestión (mandado), el de ISIS (facturado), la diferencia, el estado,
       el nº de comprobante y el 📄 (sólo si hay storage_path);
   (d) al facturar (facMarcarFacturada, el choke point de web+ISIS) dispara gv_conciliacion_registrar
       con la NP → se guarda el snapshot.
   RPC/REST interceptadas por fetch, sin red. Sale 1 si falla. */
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
      { np: "98619", empresa: "lk", tanda: "D68A", cod_cliente: "1651", razon_social: "SALVETTI",
        fecha_salida: "2026-09-08", cajas_ent: 585, neto_gestion: 16136550, items_sin_precio: 0,
        registrado_at: "2026-09-08T12:01:00-03:00", factura_neto: 16136550, factura_cajas: 585,
        comprobante_id: "FC-A-0005-00000908", doc_fecha: "2026-09-08", storage_path: "2026/09/fa_908.pdf",
        es_super: false, diff: 0, diff_pct: 0, estado: "ok", total_count: 3 },
      { np: "LK 0004", empresa: "lk", tanda: "E01A", cod_cliente: "302", razon_social: "PEDIDO WEB",
        fecha_salida: "2026-09-08", cajas_ent: 12, neto_gestion: 500000, items_sin_precio: 1,
        registrado_at: "2026-09-08T11:30:00-03:00", factura_neto: null, factura_cajas: null,
        comprobante_id: null, doc_fecha: null, storage_path: null, es_super: false,
        diff: null, diff_pct: null, estado: "sin_factura", total_count: 3 },
      { np: "44601", empresa: "chef", tanda: "D69D", cod_cliente: "801", razon_social: "CHEF CLIENTE",
        fecha_salida: "2026-09-08", cajas_ent: 300, neto_gestion: 8561760, items_sin_precio: 2,
        registrado_at: "2026-09-08T10:00:00-03:00", factura_neto: 7791011.1, factura_cajas: 298,
        comprobante_id: "A-0001-00000777", doc_fecha: "2026-09-08", storage_path: "2026/09/ch_777.pdf",
        es_super: false, diff: -770748.9, diff_pct: -9, estado: "diff", total_count: 3 }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_conciliacion_lista") return ok(filas);
        if (m[1] === "gv_conciliacion_totales") return ok([{ estado: "ok", n: 1, suma_diff: 0 }, { estado: "diff", n: 1, suma_diff: -770748.9 }, { estado: "sin_factura", n: 1, suma_diff: 0 }]);
        return ok([]);
      }
      return ok([]);   // Facturacion_NP POST, drenajes, etc.
    };

    // (a) las dos solapas y sus paneles
    out.tabFact = !!document.getElementById("facTab2Fact");
    out.tabConcil = !!document.getElementById("facTab2Concil");
    out.panelFact = !!document.getElementById("facPanelFact");
    out.panelConcil = !!document.getElementById("facPanelConcil");

    // arranca en Facturador
    facSetTab("fact");
    out.factVisibleAlInicio = document.getElementById("facPanelFact").style.display !== "none";

    // (b) entrar a Conciliación
    facSetTab("concil");
    await new Promise((res) => setTimeout(res, 400));
    out.concilVisible = document.getElementById("facPanelConcil").style.display !== "none";
    out.factOculto = document.getElementById("facPanelFact").style.display === "none";
    out.calls = calls.map((c) => c.fn);
    const tabla = document.getElementById("concilTabla");
    const resumen = document.getElementById("concilResumen");
    out.html = tabla ? tabla.innerHTML : "";
    out.resumen = resumen ? resumen.textContent : "";
    out.filas = tabla ? tabla.querySelectorAll("tbody tr").length : 0;
    out.pdf = tabla ? tabla.querySelectorAll("button.fac-cc-pdf").length : 0;

    // 📄 abre la factura con empresa + path
    let abierto = null;
    window.deudaAbrirFactura = async (e, sp) => { abierto = { e, sp }; };
    const pdfBtn = tabla ? tabla.querySelector("button.fac-cc-pdf") : null;
    if (pdfBtn) pdfBtn.click();
    await new Promise((res) => setTimeout(res, 50));
    out.abierto = abierto;

    // volver a Facturador
    facSetTab("fact");
    out.volvioFact = document.getElementById("facPanelFact").style.display !== "none" && document.getElementById("facPanelConcil").style.display === "none";

    // (d) facturar dispara el snapshot
    calls.length = 0;
    window._facLastTandas = [];
    const h = { apikey: "x", Authorization: "Bearer x", "Content-Type": "application/json" };
    await facMarcarFacturada({ np: "98700", tanda: "E01A", m3: 1, rs: "X", cod: "1", feRaw: "2026-09-08" }, h);
    await new Promise((res) => setTimeout(res, 100));
    const reg = calls.find((c) => c.fn === "gv_conciliacion_registrar");
    out.registrar = reg ? reg.body : null;

    return out;
  });
  await b.close();

  const fails = [];
  if (!r.tabFact || !r.tabConcil) fails.push("faltan las solapas Facturador/Conciliación");
  if (!r.panelFact || !r.panelConcil) fails.push("faltan los paneles #facPanelFact / #facPanelConcil");
  if (!r.factVisibleAlInicio) fails.push("Facturador no arranca visible");
  if (!r.concilVisible || !r.factOculto) fails.push("facSetTab('concil') no alterna los paneles");
  if (!r.calls.includes("gv_conciliacion_lista")) fails.push("no llamó a gv_conciliacion_lista");
  if (!r.calls.includes("gv_conciliacion_totales")) fails.push("no pidió los totales");
  if (r.filas !== 3) fails.push("esperaba 3 filas, hay " + r.filas);
  if (r.pdf !== 2) fails.push("esperaba 2 botones 📄 (sólo con storage_path), hay " + r.pdf);
  if (!/LK 0004/.test(r.html)) fails.push("la NP web no aparece");
  if (!/FC-A-0005-00000908/.test(r.html)) fails.push("falta el nº de comprobante");
  if (!/Sin factura aún/.test(r.html) || !/Diferencia/.test(r.html) || !/OK/.test(r.html)) fails.push("faltan estados");
  if (!/2 s\/precio/.test(r.html)) fails.push("no marca artículos sin precio");
  if (!/1 OK/.test(r.resumen) || !/1 con diferencia/.test(r.resumen) || !/1 sin factura/.test(r.resumen)) fails.push("resumen no usa los totales: " + r.resumen);
  if (!r.abierto || r.abierto.e !== "lk" || r.abierto.sp !== "2026/09/fa_908.pdf") fails.push("📄 no abre la factura: " + JSON.stringify(r.abierto));
  if (!r.volvioFact) fails.push("no vuelve a Facturador");
  if (!r.registrar || String(r.registrar.p_np) !== "98700") fails.push("facturar no dispara gv_conciliacion_registrar con la NP: " + JSON.stringify(r.registrar));
  if (/undefined|NaN/.test(r.html)) fails.push("undefined/NaN en la tabla");
  if (errs.length) fails.push("pageerror: " + errs.join(" | "));

  if (fails.length) { console.error("FAIL fac-conciliacion:\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("OK fac-conciliacion: 2 solapas, snapshot Gestión vs ISIS, estados, 📄, y el snapshot se registra al facturar");
})();
