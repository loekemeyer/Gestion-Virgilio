/* Regresión v12.99 — tres mejoras del backlog de agentes:
   (7953) send(): cerrar un TP/TAP/toggle abierto hace una duración absurda (>8 h / >3 h)
          pide confirmación; Cancelar no manda nada.
   (1257) computeInconsistencias: el hueco de inactividad ya no queda anulado por eventos de
          detalle (PKC/TAL/CCN/…) que subían el contador inProgress sin bajarlo nunca.
   (6092) Stock: "Cajas Pedidas" en 0 muestra — (igual que Capacidad), no una celda vacía. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};

    // ── (7953) confirmar cierre absurdo ──────────────────────────────────────
    const confirms = [];
    let confirmAnswer = false;
    let emitted = [];
    window.alert = () => {};
    window.fetch = () => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve([]), text: () => Promise.resolve("[]"), headers: { get: () => null } });
    window.confirm = (m) => { confirms.push(String(m)); return confirmAnswer; };
    window.esOperadorPrueba = () => false;
    window.askArmadoUbicaciones = async () => ({});
    window.askPickUbicacion = async () => "mesa";   // el TP pregunta dónde quedó lo pickeado (modal)
    window.getActivityStatus = async () => ({ pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map() });
    window.fetchMonitorSheet = async () => new Map();
    window.tandaReservar = async () => null;
    window.getEmpleadosNombres = async () => new Map();
    window.emitArmadoUbic = () => {};
    window.maybeRegisterLateArrival = async () => {};
    window.pushHistoryForLegajo = () => {};
    window.setLegajoState = () => {};
    window.tandaLiberar = () => {};
    window.stockSepararAFacturar = () => {};
    window.enqueueReport = (pl) => { emitted.push(pl.opcion); };
    window.trySendOneReport = async () => ({ ok: true, created_at: "x" });
    window.removeFromQueue = () => {};
    window.setHistoryItemStatus = () => {};
    window._compTandaYaArmada = async () => true;
    const hace = (h) => new Date(Date.now() - h * 3600000).toISOString();
    let pickIni = hace(20);
    window.getLegajoState = () => ({ picking: { active: true, value: "D09B", ts_inicio: pickIni }, armado: { active: false }, toggles: { CR: hace(5) } });
    const prep = (op, txt) => { document.getElementById("legajoInput").value = "8"; document.getElementById("textInput").value = txt || ""; selected = op; emitted = []; confirms.length = 0; };
    // TP abierto hace 20 h, Cancelar → no manda
    prep("TP", "D09B"); confirmAnswer = false; await send();
    out.tpCancelaNoManda = emitted.length === 0 && confirms.length === 1 && confirms[0].indexOf("20.0 h") >= 0;
    // Aceptar → manda
    prep("TP", "D09B"); confirmAnswer = true; await send();
    out.tpAceptaManda = emitted.indexOf("TP") >= 0 && confirms.length === 1;
    // TP abierto hace 2 h → sin pregunta
    pickIni = hace(2);
    prep("TP", "D09B"); confirmAnswer = false; await send();
    out.tpNormalSinPregunta = emitted.indexOf("TP") >= 0 && confirms.length === 0;
    // toggle CR abierto hace 5 h (> 3 h) → pregunta
    prep("CR", ""); confirmAnswer = false; await send();
    out.toggleLargoPregunta = confirms.length === 1 && emitted.length === 0;

    // ── (1257) hueco con eventos de detalle ──────────────────────────────────
    const DAY = "2026-01-05";
    const ts = (hhmm) => DAY + "T" + hhmm + ":00-03:00";
    const has = (res, cat, frag) => res.some((x) => x.cat === cat && x.detalle.indexOf(frag) >= 0);
    // picking 08:00→09:00 con PKC en el medio, después NADA hasta las 12:00 (3 h) → hueco
    let res = computeInconsistencias([
      { legajo: "20", opcion: "EP",  texto: "D10B", ts_cliente: ts("08:00") },
      { legajo: "20", opcion: "PKC", texto: "D10B|502|6|6", ts_cliente: ts("08:20") },
      { legajo: "20", opcion: "PKC", texto: "D10B|321|1|1", ts_cliente: ts("08:40") },
      { legajo: "20", opcion: "TP",  texto: "D10B", ts_cliente: ts("09:00"), ts_inicio: ts("08:00") },
      { legajo: "20", opcion: "EP",  texto: "D11B", ts_cliente: ts("12:00") },
      { legajo: "20", opcion: "TP",  texto: "D11B", ts_cliente: ts("13:00"), ts_inicio: ts("12:00") },
      { legajo: "20", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.huecoConDetalle = has(res, "Tiempos", "Hueco de 3.0 h");
    // mismo hueco pero DENTRO de un picking abierto → no es hueco
    res = computeInconsistencias([
      { legajo: "21", opcion: "EP",  texto: "D12B", ts_cliente: ts("08:00") },
      { legajo: "21", opcion: "PKC", texto: "D12B|502|6|6", ts_cliente: ts("08:20") },
      { legajo: "21", opcion: "TP",  texto: "D12B", ts_cliente: ts("11:30"), ts_inicio: ts("08:00") },
      { legajo: "21", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.sinHuecoEnCurso = !has(res, "Tiempos", "Hueco");
    // toggle abierto (CR) cubre el hueco; cerrado, no
    res = computeInconsistencias([
      { legajo: "22", opcion: "CR", texto: "", ts_cliente: ts("08:00") },
      { legajo: "22", opcion: "CR", texto: "", ts_cliente: ts("10:30"), ts_inicio: ts("08:00") },
      { legajo: "22", opcion: "EP", texto: "D13B", ts_cliente: ts("13:00") },
      { legajo: "22", opcion: "TP", texto: "D13B", ts_cliente: ts("13:30"), ts_inicio: ts("13:00") },
      { legajo: "22", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    // (_incHora formatea "10:30 a. m." según el locale del browser → chequeamos por partes)
    out.toggleCubreYLuegoHueco = !has(res, "Tiempos", "08:00") && res.some((x) => x.cat === "Tiempos" && /Hueco de 2\.5 h sin actividad \(10:30/.test(x.detalle));

    // ── (6092) Cajas Pedidas en 0 → — ───────────────────────────────────────
    function viewRowsDeMovs(movs) {
      const m = {};
      movs.forEach((mv) => {
        const k = String(mv.cod_art);
        if (!m[k]) m[k] = { cod: k, descripcion: "", terminado: 0, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0 };
        if (mv.descripcion) m[k].descripcion = mv.descripcion;
        if (Object.prototype.hasOwnProperty.call(m[k], mv.deposito)) m[k][mv.deposito] += Number(mv.delta) || 0;
      });
      return Object.keys(m).map((k) => m[k]);
    }
    const movs = [{ cod_art: "100", descripcion: "Normal", deposito: "terminado", tipo: "inicial", delta: 10, ts: "2026-08-01T16:00:00Z" }];
    _stk = { movs, viewRows: viewRowsDeMovs(movs), cutoff: null, asOf: null, dem: {}, cap: [], fcs: { porArt: {}, pend: {} }, filtro: "", gConf: [] };
    const html = stkBodyStocks();
    const fila = (html.match(/<tr[^>]*>(?:(?!<\/tr>)[\s\S])*stk-cod[\s\S]*?<\/tr>/) || [""])[0];
    out.filaHay = fila.indexOf("100") >= 0;
    out.pedidasGuion = /background:#fffbeb;color:#92400e">—<\/td>/.test(fila);
    out.sinCeldaVacia = !/background:#fffbeb;color:#92400e"><\/td>/.test(fila);
    return out;
  });

  const checks = [
    ["7953: TP abierto hace 20 h + Cancelar → no manda",           r.tpCancelaNoManda === true],
    ["7953: + Aceptar → manda",                                     r.tpAceptaManda === true],
    ["7953: TP de 2 h no pregunta",                                 r.tpNormalSinPregunta === true],
    ["7953: toggle CR de 5 h (> 3 h) pregunta",                     r.toggleLargoPregunta === true],
    ["1257: PKC en el medio no anula el hueco de 3 h",              r.huecoConDetalle === true],
    ["1257: dentro de un picking abierto no hay hueco",             r.sinHuecoEnCurso === true],
    ["1257: toggle abierto cubre; cerrado, el hueco se ve",         r.toggleCubreYLuegoHueco === true],
    ["6092: Cajas Pedidas en 0 muestra —",                          r.filaHay === true && r.pedidasGuion === true && r.sinCeldaVacia === true],
    ["sin errores de página",                                       errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "mejoras-v1299: " + bad + " FALLA(S)" : "mejoras-v1299: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
