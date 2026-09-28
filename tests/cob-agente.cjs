/* v22.93 — Cobranzas: solapa 🕵 Agente (gv_cobranza_agente_resumen / _cliente) y solapa 🏦 Bancos
   (gv_cobranza_bancos, paginada en el servidor), más los recibos según bancos en el detalle de Deuda
   (gv_cobranza_cliente_cuit). Corre la pantalla de verdad con las RPC interceptadas por fetch, sin red.
   Chequea:
   (a) la botonera tiene las dos solapas nuevas y "Extracto banco" ya no existe como solapa;
   (b) Agente: llama a gv_cobranza_agente_resumen, dibuja las filas ORDENADAS por a reclamar (mayor primero),
       el filtro "sólo con reclamo" saca al cliente con 0, y el Detalle llama a gv_cobranza_agente_cliente
       con (empresa, cod) y dibuja el tramo con su reclamo;
   (c) Bancos: llama a gv_cobranza_bancos con los filtros (cuenta → banco+empresa, desde), dibuja las filas,
       el resumen usa total_count del servidor (no el largo de la página) y "Cargar más" pide el offset;
   (d) Deuda → Detalle: pide gv_cobranza_cliente_cuit con el CUIT y escribe la sección de recibos.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
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
    const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__isSupervisor = true;
    window.requireSupervisor = function () { return true; };
    const calls = [];
    const resumen = [
      { empresa: "lk", cod_cliente: "862", cliente: "Muller Y Muller S.R.L.", pedidos_mal: 14, pedidos_imputados: 14, pedidos_atrasados: 14, dias_prom: 101, dias_max: 188, atraso_max: 188, ret_cliente: 0, a_reclamar: 28873448.36, recibos_sin_imputar: 0, pedidos_sin_recibo: 2, desde: "2025-09-10", hasta: "2026-08-03", calculado_en: "2026-09-25T22:20:25-03:00" },
      { empresa: "lk", cod_cliente: "288", cliente: "Torres Y Liva S.A Cif", pedidos_mal: 22, pedidos_imputados: 24, pedidos_atrasados: 22, dias_prom: 62, dias_max: 101, atraso_max: 71, ret_cliente: 0.0162, a_reclamar: 38405798.13, recibos_sin_imputar: 1, pedidos_sin_recibo: 0, desde: "2026-01-09", hasta: "2026-09-01", calculado_en: "2026-09-25T22:20:25-03:00" },
      { empresa: "chef", cod_cliente: "801", cliente: "Cliente Sano", pedidos_mal: 0, pedidos_imputados: 5, pedidos_atrasados: 0, dias_prom: null, dias_max: 12, atraso_max: 0, ret_cliente: 0, a_reclamar: 0, recibos_sin_imputar: 0, pedidos_sin_recibo: 0, desde: null, hasta: null, calculado_en: "2026-09-25T22:20:25-03:00" }
    ];
    // el backend ya ordena; acá vienen DESORDENADAS a propósito para ver que la pantalla no reordena mal
    const detalle = [
      { empresa: "lk", cod_cliente: "288", nombre: "Torres Y Liva S.A Cif", recibo: "14001", fecha_pago: "2026-03-11", medio: "e-cheque", pagado: 12220923, dto_tomado: 0.25, retencion: 0.0162, pedido: "2026-01-09", facturas: "33512", lista: 16294564, nc: null, lista_nc: 0, dias: 61, dias_contado: 30, dto_ganado: 0, a_reclamar: 4073641, calidad: "con retencion", grupo: 1, ret_cliente: 0.0162, plazo: 30, atraso: 31, calculado_en: "2026-09-25T22:20:25-03:00" },
      { empresa: "lk", cod_cliente: "288", nombre: "Torres Y Liva S.A Cif", recibo: "14230", fecha_pago: "2026-08-20", medio: "transferencia", pagado: 500000, dto_tomado: null, retencion: null, pedido: null, facturas: null, lista: null, nc: null, lista_nc: null, dias: null, dias_contado: null, dto_ganado: null, a_reclamar: null, calidad: "sin imputar", grupo: null, ret_cliente: 0.0162, plazo: null, atraso: null, calculado_en: "2026-09-25T22:20:25-03:00" }
    ];
    const bancos = (offset) => [
      { banco: "credicoop", empresa: "lk", anio: 2026, fila: 4835 - offset, fecha: "2027-01-01", operacion: "A Depositar", entrada: 552883.92, salida: null, saldo: -186380947.8, detalle: "Anjoru Sociedad Anonima", det: "3", nro_op: null, nro_recibo: "14565", cod_cliente: "2039", observacion: "Electronico", estado_echeq: "Aceptado 22/09", estado_isis: "Pasado a Isis", nota: null, tipo: "a_depositar", total_count: 412, suma_entrada: 99000000, suma_salida: 12000000 },
      { banco: "santander", empresa: "chef", anio: 2026, fila: 900 - offset, fecha: "2026-09-24", operacion: "Transferencia recibida", entrada: 1311008.62, salida: null, saldo: 1000, detalle: "Bollati Leandro (Cocinarte)", det: "D", nro_op: "778", nro_recibo: "14524", cod_cliente: "1936", observacion: null, estado_echeq: null, estado_isis: null, nota: "virgilio", tipo: "ingreso", total_count: 412, suma_entrada: 99000000, suma_salida: 12000000 }
    ];
    const cuit = [
      { empresa: "lk", cod_cliente: "288", nombre: "Torres Y Liva S.A Cif", recibo: "14001", fecha_pago: "2026-03-11", medio: "e-cheque", pagado: 12220923, dto_tomado: 0.25, retencion: 0.0162, pedido: "2026-01-09", facturas: "33512", lista: 16294564, nc: null, lista_nc: 0, dias: 61, dias_contado: 30, dto_ganado: 0, a_reclamar: 4073641, calidad: "con retencion", grupo: 1, ret_cliente: 0.0162, plazo: 30, atraso: 31 }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        const body = JSON.parse((opt && opt.body) || "{}");
        calls.push({ fn: m[1], body });
        if (m[1] === "gv_cobranza_agente_resumen") return ok(resumen);
        if (m[1] === "gv_cobranza_agente_cliente") return ok(detalle);
        if (m[1] === "gv_cobranza_bancos") return ok(bancos(Number(body.p_offset) || 0));
        if (m[1] === "gv_cobranza_bancos_cargas") return ok([{ banco: "credicoop_lk", anio: 2026, movimientos: 4831, cargado_en: "2026-09-25T18:17:23-03:00", archivo: "1_CONCILIACION_CREDICOOP_LOEKE.xls", ultima_fecha: "2026-09-25" }]);
        if (m[1] === "gv_cobranza_cliente_cuit") return ok(cuit);
        if (m[1] === "deudores_detalle") return ok([]);
        if (m[1] === "deuda_cobros_lista") return ok([]);
        return ok([]);
      }
      return ok([]);
    };

    // (a) botonera
    await openCobros("agente");
    await sleep(150);
    out.tabAgente = !!document.getElementById("cobrosTabAgente");
    out.tabBanco = (document.getElementById("cobrosTabBanco") || {}).textContent || "";
    out.sinExtracto = !/Extracto banco/.test(out.tabBanco);

    // (b) Agente
    out.llamoResumen = calls.some((c) => c.fn === "gv_cobranza_agente_resumen");
    let filas = Array.from(document.querySelectorAll("#agTabla tr.ag-row")).map((tr) => tr.getAttribute("data-k"));
    out.filasConReclamo = filas.slice();                       // el sano (a_reclamar 0) no tiene que estar
    out.ordenMayorPrimero = filas[0] === "lk|288" && filas[1] === "lk|862";
    out.resumenTexto = (document.getElementById("agResumen") || {}).textContent || "";
    document.getElementById("agSolo").checked = false; _agState.soloReclamo = false; agenteRender();
    out.filasTodas = Array.from(document.querySelectorAll("#agTabla tr.ag-row")).length;
    await agenteDetalle("lk", "288");
    await sleep(50);
    const cDet = calls.find((c) => c.fn === "gv_cobranza_agente_cliente");
    out.detalleArgs = cDet ? cDet.body : null;
    const det = document.querySelector("#agTabla tr.ag-det");
    out.detalleHtml = det ? det.textContent : "";
    out.detalleTieneReclamo = /4\.073\.641/.test(out.detalleHtml) && /33512/.test(out.detalleHtml) && /sin imputar/.test(out.detalleHtml);

    // (c) Bancos
    cobrosSetTab("banco");
    await sleep(150);
    const cBk = calls.filter((c) => c.fn === "gv_cobranza_bancos");
    out.bancosLlamada = cBk.length ? cBk[0].body : null;
    out.bancosFilas = document.querySelectorAll("#bkTabla tr.bk-row").length;
    out.bancosResumen = (document.getElementById("bkResumen") || {}).textContent || "";
    out.bancosCargas = (document.getElementById("bkCargas") || {}).textContent || "";
    document.getElementById("bkCuenta").value = "santander|chef";
    document.getElementById("bkCuenta").dispatchEvent(new Event("change"));
    await sleep(100);
    const cBk2 = calls.filter((c) => c.fn === "gv_cobranza_bancos");
    out.bancosFiltro = cBk2[cBk2.length - 1].body;
    bancosCargarMas();
    await sleep(100);
    const cBk3 = calls.filter((c) => c.fn === "gv_cobranza_bancos");
    out.bancosOffset = cBk3[cBk3.length - 1].body.p_offset;
    out.bancosFilasTrasMas = document.querySelectorAll("#bkTabla tr.bk-row").length;
    out.importadorViejoPlegado = !!document.getElementById("bancoViejo") && !document.getElementById("bancoViejo").open;

    // (d) Deuda → Detalle
    let escrito = "";
    window.open = function () { return { document: { write: function (h) { escrito += h; }, close: function () {} } }; };
    _deudaState.rows = [{ deudor_id: "33534724239", razon_social: "Torres Y Liva" }];
    await deudaVerDetalle("33534724239");
    const cCuit = calls.find((c) => c.fn === "gv_cobranza_cliente_cuit");
    out.cuitArgs = cCuit ? cCuit.body : null;
    out.deudaSeccion = /Recibos según bancos/.test(escrito) && /33512/.test(escrito) && /4\.073\.641/.test(escrito);
    out.deudaCartel = !/Todavía no hay conciliación automática/.test(document.body.innerHTML);
    return out;
  });
  await b.close();

  const fails = [];
  if (!r.tabAgente) fails.push("falta la solapa 🕵 Agente");
  if (!r.sinExtracto) fails.push("la solapa sigue diciendo 'Extracto banco': " + r.tabBanco);
  if (!r.llamoResumen) fails.push("Agente no llamó a gv_cobranza_agente_resumen");
  if (JSON.stringify(r.filasConReclamo) !== JSON.stringify(["lk|288", "lk|862"])) fails.push("con 'sólo con reclamo' tenían que quedar 288 y 862 en ese orden: " + JSON.stringify(r.filasConReclamo));
  if (!r.ordenMayorPrimero) fails.push("no ordena por a reclamar (mayor primero)");
  if (r.filasTodas !== 3) fails.push("sin el filtro tenían que verse 3 clientes, se ven " + r.filasTodas);
  if (!/2 cliente/.test(r.resumenTexto) || !/67\.279\.246/.test(r.resumenTexto)) fails.push("el resumen no suma el reclamo de los 2 clientes: " + r.resumenTexto.slice(0, 120));
  if (!r.detalleArgs || r.detalleArgs.p_empresa !== "lk" || r.detalleArgs.p_cod !== "288") fails.push("el detalle no pidió (lk, 288): " + JSON.stringify(r.detalleArgs));
  if (!r.detalleTieneReclamo) fails.push("el detalle no muestra el tramo con su reclamo / el recibo sin imputar: " + r.detalleHtml.slice(0, 200));
  if (!r.bancosLlamada || r.bancosLlamada.p_limit !== 300 || r.bancosLlamada.p_offset !== 0 || !r.bancosLlamada.p_desde) fails.push("Bancos no pidió la primera página con desde: " + JSON.stringify(r.bancosLlamada));
  if (r.bancosFilas !== 2) fails.push("Bancos dibujó " + r.bancosFilas + " filas (esperaba 2)");
  if (!/412 movimiento/.test(r.bancosResumen)) fails.push("el resumen de Bancos no usa total_count del servidor: " + r.bancosResumen.slice(0, 80));
  if (!/Credicoop LK/.test(r.bancosCargas) || !/25\/09/.test(r.bancosCargas)) fails.push("no muestra la última carga por banco: " + r.bancosCargas.slice(0, 120));
  if (!r.bancosFiltro || r.bancosFiltro.p_banco !== "santander" || r.bancosFiltro.p_empresa !== "chef") fails.push("el filtro de cuenta no viaja como banco+empresa: " + JSON.stringify(r.bancosFiltro));
  if (r.bancosOffset !== 300) fails.push("'Cargar más' no pidió offset 300: " + r.bancosOffset);
  if (r.bancosFilasTrasMas !== 4) fails.push("tras 'Cargar más' tenían que quedar 4 filas, hay " + r.bancosFilasTrasMas);
  if (!r.importadorViejoPlegado) fails.push("el importador viejo de Interbanking tiene que quedar plegado en un <details>");
  if (!r.cuitArgs || r.cuitArgs.p_cuit !== "33534724239") fails.push("el detalle de Deuda no pidió gv_cobranza_cliente_cuit con el CUIT: " + JSON.stringify(r.cuitArgs));
  if (!r.deudaSeccion) fails.push("el detalle de Deuda no escribe la sección de recibos según bancos");
  if (!r.deudaCartel) fails.push("el cartel viejo de 'no hay conciliación automática' sigue en Deuda");
  const realErrs = errs.filter((e) => !/Failed to fetch|NetworkError|net::ERR|aborted/i.test(e));
  if (realErrs.length) fails.push("errores de página: " + realErrs.join(" | "));

  if (fails.length) { console.error("cob-agente: FALLA\n - " + fails.join("\n - ")); process.exit(1); }
  console.log("cob-agente: OK — solapas Agente y Bancos, detalle por cliente, paginado del servidor y recibos en Deuda.");
})().catch((e) => { console.error("cob-agente: error", e); process.exit(1); });
