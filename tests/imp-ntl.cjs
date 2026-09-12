/* v15.90 — Solapa 💱 NTL: la cuenta corriente del forwarder de Hong Kong. Se verifica que la
   solapa exista, que traiga resumen + pendientes + extracto, que los KPI sumen el saldo por
   empresa, que cada movimiento quede clasificado (ingreso / recupero / giro / comisión / gasto)
   y que los filtros de empresa y proveedor manden el parámetro a la RPC. */
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
    const RES = [
      { empresa: "CH", ingresos: "7000.00", recuperos: "157108.92", girado_a_fabricas: "208337.95",
        comisiones: "7708.25", gastos_bancarios: "576.00", saldo: "-52513.28", movimientos: 81, ultimo_mov: "2026-08-31" },
      { empresa: "D", ingresos: "133300.00", recuperos: "0.00", girado_a_fabricas: "0.00",
        comisiones: "3699.00", gastos_bancarios: "0.00", saldo: "129601.00", movimientos: 16, ultimo_mov: "2026-02-06" },
      { empresa: "TN", ingresos: "13444.63", recuperos: "83911.82", girado_a_fabricas: "180498.37",
        comisiones: "4712.04", gastos_bancarios: "317.36", saldo: "-76857.30", movimientos: 80, ultimo_mov: "2026-09-04" }
    ];
    const PEND = [
      { concepto: "Hugo Wong CH37", monto: "21951.84", empresa: "Tierra", detalle: null },
      { concepto: "Ownland", monto: "20956.00", empresa: "Chef", detalle: "FOB 34956 - 14000 Adelanto" }
    ];
    const MOV = [
      { fila: 184, fecha: "2026-09-04", descripcion: "Advance 30%", clase: "giro", debito: "3100.00",
        credito: null, saldo: "230.43", origen_destino: "Fob (10339,46)", proveedor: "Xihin", empresa: "TN" },
      { fila: 181, fecha: "2026-09-04", descripcion: "Recupero Hugo Wong", clase: "recupero", debito: null,
        credito: "1183.00", saldo: "3435.92", origen_destino: null, proveedor: "Hugo Wong", empresa: "TN" },
      { fila: 183, fecha: "2026-09-04", descripcion: "Comision NTL", clase: "comision", debito: "56.71",
        credito: null, saldo: "3330.43", origen_destino: null, proveedor: "Hugo Wong", empresa: "TN" },
      { fila: 151, fecha: "2026-02-06", descripcion: "Efectivo Recibido", clase: "ingreso", debito: null,
        credito: "10000.00", saldo: "20855.76", origen_destino: "USD Depositados Efectivo (Damian)", proveedor: null, empresa: "D" }
    ];
    const CARGAS = [
      { prov: "Ownland", carga: "CQ-9694", girado: "34990.00", fob_carga: "34956.00", saldo: "-34.00",
        movs: 3, desde: "2026-03-13", hasta: "2026-06-03", pedido_sugerido: "PI OL-10139",
        fob_pedido: "46626.00", sugerencia: "FOB difiere 11670", pedido_asignado: null, nota_asignacion: null },
      { prov: "Frontier", carga: "China 2", girado: "14400.00", fob_carga: "14400.00", saldo: "0.00",
        movs: 4, desde: "2025-07-17", hasta: "2026-02-15", pedido_sugerido: "Frontier 505C",
        fob_pedido: "14400.00", sugerencia: "FOB igual", pedido_asignado: "Frontier 505C", nota_asignacion: null }
    ];
    const CONC = [
      { pago_id: 1, pedido_ref: "Frontier 505C", proveedor: "Frontier", fecha: "2026-08-25",
        monto_usd: "4320", beneficiario: "NTL", fuente: "NTL", fila_excel: 175, fecha_excel: "2026-08-25",
        monto_excel: "4320.00", detalle: "Frontier", match: "exacto" },
      { pago_id: 2, pedido_ref: "PI B260601-2", proveedor: "Becky", fecha: "2026-06-02",
        monto_usd: "7359", beneficiario: "Becky", fuente: null, fila_excel: null, fecha_excel: null,
        monto_excel: null, detalle: null, match: "SIN MATCH" }
    ];
    const ALIAS = [
      { alias: "Fuyian", canonico: "Fujian", es_empresa: false, nota: "typo", movimientos: 3 },
      { alias: "Cestos", canonico: null, es_empresa: false, nota: "define Thomas", movimientos: 3 },
      { alias: "Chef", canonico: null, es_empresa: true, nota: "es la empresa", movimientos: 6 }
    ];
    const calls = [];
    window.fetch = async (u, o) => {
      const url = String(u); calls.push({ u: url.split("/rest/v1/")[1] || url, b: o && o.body });
      let data = [];
      if (url.indexOf("gv_imp_ntl_resumen") >= 0) data = RES;
      else if (url.indexOf("gv_imp_ntl_pendientes") >= 0) data = PEND;
      else if (url.indexOf("gv_imp_ntl_mov") >= 0) data = MOV;
      else if (url.indexOf("gv_imp_cargas") >= 0) data = CARGAS;
      else if (url.indexOf("gv_imp_conciliacion") >= 0) data = CONC;
      else if (url.indexOf("gv_imp_prov_alias") >= 0) data = ALIAS;
      else if (url.indexOf("gv_imp_carga_pedido_set") >= 0) data = { ok: true };
      else if (url.indexOf("gv_imp_prov_alias_set") >= 0) data = { ok: true };
      else if (url.indexOf("gv_imp_cc_lista") >= 0) data = [{ pedido_ref: "PI OL-10139", proveedor: "Ownland", fob: "46626.00" }];
      return { ok: true, status: 200, json: async () => data, text: async () => "" };
    };

    out.tab = _impTabsHtml("curso").indexOf("openImpNtl()") >= 0;
    await openImpNtl();
    const body = () => document.getElementById("stkPopBody");
    const t = body().innerText.replace(/\s+/g, " ");
    out.txt = t;
    out.filas = [...body().querySelector(".intl-tbl").tBodies[0].rows].length;
    out.chips = [...body().querySelectorAll(".intl-c")].map((x) => x.innerText.trim());
    // el saldo total es la suma de las 3 empresas: 129601 - 76857,30 - 52513,28 = 230,42
    out.saldoOk = /230/.test(t);
    out.pendOk = /42\.908|42\.907/.test(t);
    out.nombres = /Tierra Nativa/.test(t) && /Chef/.test(t) && /Dep[óo]sitos sin asignar/i.test(t);

    // ---- vista CARGAS ----
    await impNtlSetVista("cargas");
    const tc = body().innerText.replace(/\s+/g, " ");
    out.cargasTxt = tc;
    out.cargasFilas = [...body().querySelector(".intl-tbl").tBodies[0].rows].length;
    out.asignado = /✓ Frontier 505C/.test(tc);     // la que ya tiene pedido confirmado
    out.sugerido = /sugerido:/.test(tc);           // la que sólo tiene sugerencia
    // asignar una carga a un pedido desde la pantalla
    calls.length = 0;
    window.prompt = () => "1";
    await impCargaAsignar(encodeURIComponent("Ownland"), encodeURIComponent("CQ-9694"));
    out.callAsig = calls.filter((c) => c.u.indexOf("rpc/gv_imp_carga_pedido_set") === 0).map((c) => JSON.parse(c.b));
    // definir uno de los nombres sin decidir (Cestos) desde el aviso
    calls.length = 0;
    window.prompt = () => "Becky";
    await impAliasDefinir(encodeURIComponent("Cestos"));
    out.callAlias = calls.filter((c) => c.u.indexOf("rpc/gv_imp_prov_alias_set") === 0).map((c) => JSON.parse(c.b));
    // ---- vista CONCILIACIÓN ----
    await impNtlSetVista("conc");
    const tk = body().innerText.replace(/\s+/g, " ");
    out.concTxt = tk;
    out.concFilas = [...body().querySelector(".intl-tbl").tBodies[0].rows].length;
    // el aviso de alias sin definir (Cestos) aparece en las dos
    out.avisoAlias = /Cestos/.test(tk);
    await impNtlSetVista("extracto");

    // filtros -> la RPC recibe el parámetro
    calls.length = 0;
    await impNtlSetEmpresa("TN");
    out.callEmp = calls.filter((c) => c.u.indexOf("rpc/gv_imp_ntl_mov") === 0).map((c) => JSON.parse(c.b));
    calls.length = 0;
    await impNtlSetProv(encodeURIComponent("Hugo Wong"));
    out.callProv = calls.filter((c) => c.u.indexOf("rpc/gv_imp_ntl_mov") === 0).map((c) => JSON.parse(c.b));
    return out;
  });

  console.log(JSON.stringify({ ...r, txt: (r.txt || "").slice(0, 260) }, null, 1));
  if (!r.tab) fail("la solapa 💱 NTL no está en la barra del módulo");
  if (r.filas !== 4) fail("deberían verse los 4 movimientos, hay " + r.filas);
  if (!r.saldoOk) fail("no muestra el saldo de NTL (230): " + r.txt.slice(0, 200));
  if (!r.pendOk) fail("no muestra los recuperos pendientes (42.908): " + r.txt.slice(0, 200));
  if (!r.nombres) fail("no traduce las empresas (Tierra Nativa / Chef / Depósitos sin asignar)");
  const chips = (r.chips || []).join("|");
  ["recupero", "giro", "comisión", "ingreso"].forEach(function (c) {
    if (chips.toLowerCase().indexOf(c) < 0) fail("falta el chip de clase '" + c + "': " + chips);
  });
  if (r.callEmp.length !== 1 || r.callEmp[0].p_empresa !== "TN") fail("el filtro de empresa no viaja: " + JSON.stringify(r.callEmp));
  if (r.callProv.length !== 1 || r.callProv[0].p_proveedor !== "Hugo Wong") fail("el filtro de proveedor no viaja: " + JSON.stringify(r.callProv));
  // v15.91 — las otras dos vistas
  if (r.cargasFilas !== 2) fail("la vista Cargas debería listar 2 cargas, listó " + r.cargasFilas);
  // la fila con pedido ya confirmado muestra el asignado; la otra, la sugerencia
  if (!/CQ-9694/.test(r.cargasTxt) || !/FOB difiere/i.test(r.cargasTxt)) fail("la vista Cargas no muestra la carga ni la sugerencia: " + (r.cargasTxt || "").slice(0, 250));
  if (r.concFilas !== 2) fail("la conciliación debería listar 2 giros, listó " + r.concFilas);
  if (!/exacto/i.test(r.concTxt) || !/sin match/i.test(r.concTxt)) fail("la conciliación no distingue el que matchea del que no: " + (r.concTxt || "").slice(0, 250));
  if (!/1 de 2/.test(r.concTxt)) fail("la conciliación no cuenta cuántos aparecen: " + (r.concTxt || "").slice(0, 250));
  if (!r.avisoAlias) fail("no avisa los nombres del extracto sin definir (Cestos)");
  // v15.94 — el mapa carga ↔ pedido se carga desde la pantalla
  if (!r.asignado) fail("no distingue la carga que ya tiene pedido asignado: " + (r.cargasTxt || "").slice(0, 250));
  if (!r.sugerido) fail("no marca como 'sugerido' la que todavía no se confirmó");
  if (r.callAlias.length !== 1 || r.callAlias[0].p_alias !== "Cestos" || r.callAlias[0].p_canonico !== "Becky"
      || r.callAlias[0].p_es_empresa !== false) fail("definir el alias no manda bien los datos: " + JSON.stringify(r.callAlias));
  if (r.callAsig.length !== 1) fail("Asignar no llamó a la RPC: " + JSON.stringify(r.callAsig));
  else {
    const a = r.callAsig[0];
    if (a.p_proveedor !== "Ownland" || a.p_carga !== "CQ-9694" || a.p_pedido_ref !== "PI OL-10139")
      fail("Asignar mandó mal los datos (eligiendo la opción 1): " + JSON.stringify(a));
  }
  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ imp-ntl OK");
})();
