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
        es_super: false, diff: 0, diff_pct: 0, estado: "ok", neto_actual: 16136550, corregido: false, total_count: 3 },
      { np: "LK 0004", empresa: "lk", tanda: "E01A", cod_cliente: "302", razon_social: "PEDIDO WEB",
        fecha_salida: "2026-09-08", cajas_ent: 12, neto_gestion: 500000, items_sin_precio: 1,
        registrado_at: "2026-09-08T11:30:00-03:00", factura_neto: null, factura_cajas: null,
        comprobante_id: null, doc_fecha: null, storage_path: null, es_super: false,
        diff: null, diff_pct: null, estado: "sin_factura", neto_actual: 500000, corregido: false, total_count: 3 },
      { np: "44601", empresa: "chef", tanda: "D69D", cod_cliente: "801", razon_social: "CHEF CLIENTE",
        fecha_salida: "2026-09-08", cajas_ent: 300, neto_gestion: 8561760, items_sin_precio: 2,
        registrado_at: "2026-09-08T10:00:00-03:00", factura_neto: 7791011.1, factura_cajas: 298,
        comprobante_id: "A-0001-00000777", doc_fecha: "2026-09-08", storage_path: "2026/09/ch_777.pdf",
        es_super: false, diff: -770748.9, diff_pct: -9, estado: "diff", neto_actual: 7000000, corregido: false,
        motivo: "precio: 809E · dif. pareja -2.0% (lista/descuento/factor)", total_count: 3 }
    ];
    const cmpRows = [
      { cod: "501", descripcion: "Abrelatas", cajas_ges: 5, cajas_isis: 5, precio_ges: 5520, precio_isis: 5520, dto_ges: 6, dto_isis: 6, importe_ges: 152550.72, importe_isis: 155664, diff: 3113.28, sin_precio_ges: false, motivo: "importe" },
      { cod: "809E", descripcion: "Corta Queso", cajas_ges: 1, cajas_isis: 1, precio_ges: 3005, precio_isis: 4060, dto_ges: 6, dto_isis: 6, importe_ges: 33218.47, importe_isis: 45796.8, diff: 12578.33, sin_precio_ges: false, motivo: "precio" }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_conciliacion_lista") return ok(filas);
        if (m[1] === "gv_conciliacion_totales") return ok([{ estado: "ok", n: 1, suma_diff: 0 }, { estado: "diff", n: 1, suma_diff: -770748.9 }, { estado: "sin_factura", n: 1, suma_diff: 0 }]);
        if (m[1] === "gv_conciliacion_comparar") return ok(cmpRows);
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

    // Nadie debe abrir una pestaña nueva: todo va en popups en la misma página.
    let openedTab = false;
    window.open = function () { openedTab = true; return null; };

    // columna "¿Por qué?" con la causa de la diferencia
    out.motivoCol = /¿Por qué/.test(out.html);
    out.motivoTxt = /809E/.test(out.html);

    // UN SOLO botón por fila ("🔍 Comparar") → modal con diagnóstico + comparación + PDF
    out.hayDetBtn = tabla ? tabla.querySelectorAll("button.fac-cc-det").length : 0;
    out.pdfEnFila = tabla ? tabla.querySelectorAll("button.fac-cc-pdf").length : 0;  // ya NO hay botón 📄 suelto
    const detBtns = tabla ? tabla.querySelectorAll("button.fac-cc-det") : [];
    const detBtn = detBtns[2] || detBtns[0];   // la 3ª fila (44601) es la "corregida"
    if (detBtn) detBtn.click();
    await new Promise((res) => setTimeout(res, 200));
    const detBody = document.getElementById("concilDetBody");
    out.detHtml = detBody ? detBody.innerHTML : "";
    out.detLineas = detBody ? detBody.querySelectorAll("tbody tr").length : 0;
    out.detTwoPane = !!document.getElementById("concilDetPdf");   // panel del PDF embebido, al lado de la comparación
    out.diag = /Diagn[óo]stico/.test(out.detHtml);
    out.diagPrecio = /809E/.test(out.detHtml);           // el diagnóstico marca el precio distinto

    // el botón "⤢ Ver la factura en grande" abre el visor grande en un popup (no pestaña)
    const grande = detBody ? detBody.querySelector("button.fac-concil-btn") : null;
    if (grande) grande.click();
    await new Promise((res) => setTimeout(res, 150));
    const pov = document.getElementById("concilPdfOverlay");
    out.pdfPopup = !!(pov && pov.style.display === "flex");
    out.noNewTab = !openedTab;
    if (typeof concilPdfClose === "function") concilPdfClose();
    if (typeof concilDetClose === "function") concilDetClose();

    // toggle "Sólo diferencias": deja sólo las con diferencia (o corregidas)
    concilToggleSoloDiff();
    await new Promise((res) => setTimeout(res, 50));
    out.filasSoloDiff = tabla.querySelectorAll("tbody tr").length;
    out.toggleOn = /ON/.test((document.getElementById("concilBtnSoloDiff") || {}).innerHTML || "");
    concilToggleSoloDiff();
    await new Promise((res) => setTimeout(res, 50));
    out.filasTodas = tabla.querySelectorAll("tbody tr").length;

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
  if (r.pdfEnFila !== 0) fails.push("no debería haber botón 📄 suelto en la fila (todo va por 🔍 Comparar), hay " + r.pdfEnFila);
  if (!/LK 0004/.test(r.html)) fails.push("la NP web no aparece");
  if (!/FC-A-0005-00000908/.test(r.html)) fails.push("falta el nº de comprobante");
  if (!/Sin factura aún/.test(r.html) || !/OK/.test(r.html) || !/Diferencia/.test(r.html)) fails.push("faltan estados (OK / Sin factura / Diferencia)");
  if (!/2 s\/precio/.test(r.html)) fails.push("no marca artículos sin precio");
  if (!/1 OK/.test(r.resumen) || !/1 con diferencia/.test(r.resumen) || !/1 sin factura/.test(r.resumen)) fails.push("resumen no usa los totales: " + r.resumen);
  if (!r.motivoCol) fails.push("falta la columna '¿Por qué?'");
  if (!r.motivoTxt) fails.push("la columna motivo no muestra la causa (809E)");
  if (!r.detTwoPane) fails.push("el modal no tiene el panel del PDF embebido al lado de la comparación (#concilDetPdf)");
  if (!r.pdfPopup) fails.push("el '⤢ Ver en grande' no abre el visor de PDF en un popup en la página");
  if (!r.noNewTab) fails.push("se abrió una pestaña nueva (window.open) en vez de popup");
  if (r.hayDetBtn !== 3) fails.push("esperaba un botón 🔍 Comparar por fila (3), hay " + r.hayDetBtn);
  if (r.detLineas !== 2) fails.push("la comparación no muestra las 2 líneas, hay " + r.detLineas);
  if (!/501/.test(r.detHtml) || !/809E/.test(r.detHtml)) fails.push("la comparación no muestra los códigos");
  if (!r.diag) fails.push("no aparece el bloque de Diagnóstico");
  if (!r.diagPrecio) fails.push("el diagnóstico no señala el precio distinto (809E)");
  if (r.filasSoloDiff !== 1) fails.push("'Sólo diferencias' debería dejar 1 fila (la que tiene diferencia), dejó " + r.filasSoloDiff);
  if (!r.toggleOn) fails.push("el toggle no quedó en ON");
  if (r.filasTodas !== 3) fails.push("al apagar el toggle deberían volver las 3 filas, hay " + r.filasTodas);
  if (!r.volvioFact) fails.push("no vuelve a Facturador");
  if (!r.registrar || String(r.registrar.p_np) !== "98700") fails.push("facturar no dispara gv_conciliacion_registrar con la NP: " + JSON.stringify(r.registrar));
  if (/undefined|NaN/.test(r.html)) fails.push("undefined/NaN en la tabla");
  if (errs.length) fails.push("pageerror: " + errs.join(" | "));

  if (fails.length) { console.error("FAIL fac-conciliacion:\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("OK fac-conciliacion: 2 solapas, snapshot Gestión vs ISIS, un botón 🔍 Comparar (PDF + detalle lado a lado), popups en la página, y el snapshot se registra al facturar");
})();
