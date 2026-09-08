/* v14.36 — cuatro pedidos del dueño (08/09) sobre Facturación:
   (a) col A del Excel = fecha del DÍA EN QUE SE BAJA (antes: fecha de recepción del pedido);
   (b) col J = condición de pago que eligió el cliente en la página (LK: v_pedidos_web_np;
       Chef: gv_pedidos_web_np_chef_admin — las dos devuelven condicion_pago_code);
   (c) solapa "📥 Descargas": historial de Excel bajados (GV_Fac_Export, con su detalle para
       verlo o volver a bajarlo) + los PDF de factura de ISIS;
   (d) la NP cargada por la página muestra el nombre del cliente en Consulta de NP.
   RPC y feeds interceptados por fetch. Sale 1 si falla. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => "0-0/0" } });
    window.confirm = () => true; window.alert = (m) => { (window.__alerts = window.__alerts || []).push(String(m)); };
    window.sbAuth = { getAccessToken: async () => "h." + btoa(JSON.stringify({ email: "test@x" })) + ".s" };
    window.pwebLkToken = async () => "tok";
    window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t", "Content-Type": "application/json" });

    // ── (a) y (b): el armado de las filas del Excel ────────────────────────────────
    // _facXlsFilasPlanas es puro: se le pasa la fila ya armada y devuelve las líneas del archivo.
    const hoy = _facXlsHoyTxt();
    const filas = [{
      np: "LK 0011", cod: "4256", rs: "BP Import S.R.L", fechaTxt: "02/09/2026", vend: "7",
      suc: "CASA", tope: 18, cond: "8", isisEmp: "LK", tdf: false, codLk: "4256",
      lineas: [{ art: "0027", cajas: 3, uxb: 6 }, { art: "0505", cajas: 1, uxb: null }]
    }];
    const items = _facXlsFilasPlanas(filas);
    out.colA = items.map((i) => i.fecha);
    out.hoy = hoy;
    out.colJ = items.map((i) => i.condPago);
    out.recepGuardada = items[0].fechaRecep;
    // el XML pone la fecha en la col A y la condición en la J (10ª celda)
    const xml = _facXlsXml(items, "08-09 9Hs", ["LK 0011"]);
    const fila1 = (xml.match(/<Row>[\s\S]*?<\/Row>/) || [""])[0];
    const celdas = fila1.split("<Cell").length - 1;
    out.xmlA = /<Data ss:Type="String">(\d{2}\/\d{2}\/\d{4})<\/Data>/.exec(fila1);
    out.xmlA = out.xmlA ? out.xmlA[1] : "";
    out.xmlCeldas = celdas;
    out.xmlTieneCond = fila1.indexOf('<Data ss:Type="Number">8</Data>') >= 0;

    // ── (c) la solapa Descargas ────────────────────────────────────────────────────
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_fac_export_lista") return ok([{ id: 7, tipo: "excel_isis", archivo: "PEDIDOS_WEB_ISIS_LK_08-09-26_1130.xls", empresa: "LK", formato: "xls", n_nps: 2, n_filas: 3, creado_por: "test@x", creado_at: "2026-09-08T11:30:00-03:00", nps: ["LK 0011", "LK 0012"] }]);
        if (m[1] === "gv_fac_export_detalle") return ok(items);
        if (m[1] === "gv_fac_export_registrar") return ok(9);
        return ok([]);
      }
      return ok([]);
    };
    document.getElementById("facturacionModal").classList.add("show");
    facSetTab("desc");
    for (let i = 0; i < 40 && _facDesc.cargando; i++) await new Promise((res) => setTimeout(res, 50));
    await new Promise((res) => setTimeout(res, 250));
    const cont = document.getElementById("facDescCont");
    out.tabDesc = { panel: document.getElementById("facPanelDesc").style.display, fact: document.getElementById("facPanelFact").style.display, btn: document.getElementById("facTab2Desc").className };
    out.lista = cont.innerHTML.indexOf("PEDIDOS_WEB_ISIS_LK_08-09-26_1130.xls") >= 0;
    out.listaNps = cont.innerHTML.indexOf("LK 0011") >= 0;
    // detalle
    await facDescVer(7);
    await new Promise((res) => setTimeout(res, 150));
    out.det = { abierto: !!document.querySelector(".fac-desc-det"), condCol: (document.querySelector(".fac-desc-det") || {}).innerHTML || "" };
    out.detCalls = calls.map((c) => c.fn);
    // solapa PDF
    window._concil.rows = [{ np: "LK 0011", empresa: "lk", razon_social: "BP Import S.R.L", cod_cliente: "4256", comprobante_id: "A-0001-00012345", doc_fecha: "2026-09-05", storage_path: "2026/09/fac-12345.pdf", registrado_at: "2026-09-05T10:00:00-03:00" }, { np: "LK 0012", empresa: "lk", storage_path: null }];
    facDescTab("pdf");
    await new Promise((res) => setTimeout(res, 200));
    out.pdf = { html: document.getElementById("facDescCont").innerHTML };

    // ── registrar al bajar ─────────────────────────────────────────────────────────
    calls.length = 0;
    await facDescRegistrar("ARCH_TEST.xls", "LK", filas);
    const reg = calls.find((c) => c.fn === "gv_fac_export_registrar");
    out.reg = reg ? { archivo: reg.body.p_archivo, nps: reg.body.p_nps, n: reg.body.p_n_filas, detCond: (reg.body.p_detalle || [])[0] && reg.body.p_detalle[0].condPago, detFecha: (reg.body.p_detalle || [])[0] && reg.body.p_detalle[0].fecha } : null;
    // ── (d) Consulta de NP: la NP de la página muestra el nombre del cliente ───────
    window.fetch = async (url) => {
      const u = String(url);
      // corpus TAL: una NP de ISIS y una de la página
      if (u.indexOf("opcion=eq.TAL") >= 0) return ok([
        { texto: "98686|2|D70A|A: 027x3|", ts_cliente: "2026-09-05T10:00:00-03:00", legajo: "12" },
        { texto: "LK 0011|1|E01D|A: 027x3|", ts_cliente: "2026-09-05T11:00:00-03:00", legajo: "12" }
      ]);
      if (u.indexOf("gv_ppp_web_estado") >= 0) return ok([
        { np_label: "LK 0011", cod_cliente: "4256", razon_social: "BP Import S.R.L", tanda: "E01D", fecha_entrega: "2026-09-08" }
      ]);
      if (u.indexOf("gv_ppp_programacion_diaria") >= 0) return ok([
        { np: "98686", cod: "1792", razon_social: "Dapelo Claudio Marcelo", fecha_entrega: "2026-09-14 00:00:00", tanda: "D70A" }
      ]);
      return ok([]);
    };
    _npcRowsTs = 0; _npcRows = [];
    await npcLoad(true);
    out.npc = (_npcRows || []).map((x) => x.np + "|" + x.rs + "|" + x.cod);
    return out;
  });

  let fallas = 0;
  const t = (c, txt) => { console.log((c ? "  ok    · " : "  FALLA · ") + txt); if (!c) fallas++; };
  t(/^\d{2}\/\d{2}\/\d{4}$/.test(r.hoy), "(a) hay fecha de hoy en formato dd/mm/aaaa");
  t(r.colA.every((f) => f === r.hoy), "(a) col A = fecha del día en que se baja, no la del pedido");
  t(r.colA[0] !== "02/09/2026" && r.recepGuardada === "02/09/2026", "(a) la fecha de recepción NO se pierde (queda en fechaRecep)");
  t(r.xmlA === r.hoy, "(a) el XML del .xls escribe esa fecha en la primera celda");
  t(r.colJ.every((c) => c === "8"), "(b) col J = condición de pago del pedido (code 8)");
  t(r.xmlCeldas === 12 && r.xmlTieneCond, "(b) el XML sigue con 12 columnas y lleva la condición");
  t(r.tabDesc.panel === "" && r.tabDesc.fact === "none" && /\bon\b/.test(r.tabDesc.btn), "(c) la solapa 📥 Descargas abre su panel y tapa el facturador");
  t(r.lista && r.listaNps, "(c) lista los Excel bajados con su archivo y sus NP");
  t(r.detCalls.indexOf("gv_fac_export_detalle") >= 0, "(c) 🔎 Detalle pide el detalle guardado");
  t(r.det.abierto && r.det.condCol.indexOf("Cond. pago") >= 0, "(c) el detalle se ve en pantalla, con la columna de condición de pago");
  t(r.pdf.html.indexOf("A-0001-00012345") >= 0 && r.pdf.html.indexOf("fac-12345.pdf") >= 0, "(c) la solapa de PDF lista las facturas de ISIS");
  t(r.pdf.html.indexOf("concilAbrirFactura") >= 0, "(c) y las abre con el visor que ya existe");
  t(!!r.reg && r.reg.archivo === "ARCH_TEST.xls" && r.reg.n === 2, "(c) bajar registra la descarga con su nombre y sus líneas");
  t(!!r.reg && r.reg.detCond === "8" && r.reg.detFecha === r.hoy, "(c) el detalle guardado lleva la fecha de descarga y la condición");
  t((r.npc || []).indexOf("LK 0011|BP Import S.R.L|4256") >= 0, "(d) Consulta de NP: la NP de la página muestra razón social y código");
  t((r.npc || []).indexOf("98686|Dapelo Claudio Marcelo|1792") >= 0, "(d) y la NP de ISIS sigue mostrando la suya");
  t(errs.length === 0, "sin errores de página");
  if (errs.length) console.log("  errores:", errs.join(" | "));
  console.log("  detalle:", JSON.stringify({ hoy: r.hoy, colA: r.colA, colJ: r.colJ, xmlCeldas: r.xmlCeldas, reg: r.reg }));
  await b.close();
  console.log(fallas ? "fac-descargas: " + fallas + " FALLA(S)" : "fac-descargas: OK (17 chequeos)");
  process.exit(fallas ? 1 : 0);
})();
