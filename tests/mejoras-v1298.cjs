/* Regresión v12.98 — tres mejoras del backlog de agentes:
   (9017) stockFetchSaldos no exponía para_envasar / racks_ch aunque la vista los trae.
   (6124) TAP doble: después de terminar por el asistente, el botón viejo "Tenés un Armado
          pendiente" disparaba OTRO TAP (ts_inicio=null, AUB y stock otra vez). Ahora send()
          lo frena con _tapCerradoSesion y compTerminar redibuja la sugerencia.
   (5070) Barra de avance del día en el header del Monitor (tandas FC de la ventana / programadas). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1600, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const J = (data, range) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(data), text: () => Promise.resolve(JSON.stringify(data)),
      headers: { get: (h) => (String(h).toLowerCase() === "content-range" ? range || null : null) } });

    // ── (9017) saldos con para_envasar / racks_ch ────────────────────────────
    window.fetch = (url) => {
      if (String(url).indexOf("vista_saldos_stock") >= 0)
        return J([{ cod_art: "712E", descripcion: "Bandeja", terminado: 10, excedente: 0, separar_pedidos: 0, a_facturar: 0, a_guardar: 0, racks: 5, insumos: 0, para_envasar: 424, racks_ch: 444 }], "0-0/1");
      return J([]);
    };
    const s = await stockFetchSaldos();
    out.saldoEnv = s["712E"] && s["712E"].para_envasar;
    out.saldoRacksCh = s["712E"] && s["712E"].racks_ch;
    out.saldoRacks = s["712E"] && s["712E"].racks;

    // ── (6124) TAP doble ─────────────────────────────────────────────────────
    const calls = [];
    window.alert = (m) => { calls.push("alert:" + String(m).slice(0, 30)); };
    window._compClearPersist = () => {};
    window._compSaveEntregas = () => {};
    let armadoActivo = true;
    window.getLegajoState = () => ({ armado: armadoActivo ? { active: true, value: "D06B", ts_inicio: "2026-08-05T11:00:00Z" } : { active: false, value: "", ts_inicio: null }, picking: { active: false }, toggles: {}, continuar: {} });
    window.setLegajoState = (l, st) => { armadoActivo = !!(st && st.armado && st.armado.active); };
    window.pushHistoryForLegajo = () => {};
    window.enqueueReport = (pl) => { calls.push("enqueue:" + pl.opcion); };
    window.removeFromQueue = () => {};
    window.tandaLiberar = () => {};
    window.trySendOneReport = async () => ({ ok: true });
    window.stockSepararAFacturar = async () => { calls.push("stockSep"); };
    window.updatePendingIndicator = () => {};
    window._compTandaYaArmada = async () => false;
    window.liosSend = () => {};
    window._compBuildLiosData = () => {};
    window._compLiosResumen = () => "";
    window.askArmadoUbicaciones = async () => { calls.push("askUbic"); return {}; };
    let renders = 0;
    window.renderPendingSuggestion = () => { renders++; };
    _comp = { legajo: "8", tanda: "D06B", fecha: "2026-08-05", hayFalt: false, clasifDone: true,
      nps: [{ np: "98151", clase: "lios", liosArr: [], liosDone: true, codes: { "035E": 1 } }],
      pedidoFull: [{ np: "98151", cod: "CLI01", items: [{ art: "035E", cajas: 10 }] }], arts: [], _liosDirty: false, _terminando: false };
    await compTerminar();
    out.tapPrimero = calls.filter((c) => c === "enqueue:TAP").length;
    out.redibujo = renders;
    out.enSet = _tapCerradoSesion.has("D06B");
    // segundo toque: el botón viejo hace selectOption("TAP") + textInput = tanda → send()
    window.confirm = () => true;
    window.esOperadorPrueba = () => false;
    window.showCompletarWizard = async () => { calls.push("wizard"); };
    window.emitArmadoUbic = () => {};
    window.maybeRegisterLateArrival = async () => {};
    window.setHistoryItemStatus = () => {};
    document.getElementById("legajoInput").value = "8";
    document.getElementById("textInput").value = "d06b";
    selected = "TAP";
    let sendErr = null;
    try { await send(); } catch (e) { sendErr = String(e && e.message || e); }
    out.sendErr = sendErr;
    out.tapSegundo = calls.filter((c) => c === "enqueue:TAP").length;
    out.askUbic = calls.filter((c) => c === "askUbic").length;
    out.stockSep = calls.filter((c) => c === "stockSep").length;
    out.avisa = calls.some((c) => c.indexOf("alert:✓ El armado de D06B") === 0);
    out.sinWizard = !calls.some((c) => c === "wizard");
    out.otraTandaPasa = !_tapCerradoSesion.has("D07B");

    // ── (5070) barra de avance ───────────────────────────────────────────────
    window.fetchFacturadosHoy = () => Promise.resolve();
    window.fetchFacturadosTodos = () => Promise.resolve();
    const mk = (tanda, fr, fd, m3, np) => ({ tanda, _key: tanda, m3, fechaEntregaRaw: fr, fechaEntrega: fd, opIsSi: true, pedidos: [{ np }] });
    const sheet = new Map([
      ["C10A", mk("C10A", "2026-07-25", "25/07", 5, "111")],
      ["C20A", mk("C20A", "2026-08-10", "10/08", 8, "222")],   // fuera de ventana, terminada → no cuenta
      ["C30A", mk("C30A", "2026-07-25", "25/07", 3, "333")],
      ["C40A", mk("C40A", "2026-07-25", "25/07", 4, "444")]
    ]);
    const done = { picking: "done", separado: "done", doneTodayP: false, doneTodayA: false, pickLegajo: "55", sepLegajo: "55" };
    const none = { picking: null, separado: null, doneTodayP: false, doneTodayA: false, pickLegajo: null, sepLegajo: null };
    const status = new Map([["C10A", done], ["C20A", done], ["C30A", none], ["C40A", none]]);
    renderMonitor(sheet, status, [], ["2026-07-25"], [], [], null, null, null, null, "2026-07-24", "2026-07-23");
    const prog = document.getElementById("monitorProgress");
    out.progExiste = !!prog;
    out.progTxt = prog ? (prog.querySelector(".mon-prog-txt") || {}).textContent : null;
    out.progCls = prog ? prog.className : null;
    out.progW = prog ? (prog.querySelector(".mon-prog-bar") || { style: {} }).style.width : null;
    // todas hechas → verde, 100%
    status.set("C30A", done); status.set("C40A", done);
    renderMonitor(sheet, status, [], ["2026-07-25"], [], [], null, null, null, null, "2026-07-24", "2026-07-23");
    out.progTxt2 = prog ? (prog.querySelector(".mon-prog-txt") || {}).textContent : null;
    out.progCls2 = prog ? prog.className : null;
    out.unaSola = document.querySelectorAll("#monitorProgress").length;
    return out;
  });

  const checks = [
    ["9017: para_envasar llega al saldo",                       r.saldoEnv === 424],
    ["9017: racks_ch también",                                  r.saldoRacksCh === 444],
    ["9017: y los campos de siempre siguen",                    r.saldoRacks === 5],
    ["6124: el asistente emite UN TAP",                         r.tapPrimero === 1],
    ["6124: y redibuja la sugerencia (botón viejo afuera)",     r.redibujo >= 1],
    ["6124: la tanda queda marcada como cerrada",               r.enSet === true],
    ["6124: el segundo toque NO manda otro TAP",                r.tapSegundo === 1 && !r.sendErr],
    ["6124: ni pide ubicaciones ni mueve stock de nuevo",       r.askUbic === 0 && r.stockSep === 1],
    ["6124: avisa que ya estaba terminado (sin abrir el asistente)", r.avisa === true && r.sinWizard === true],
    ["6124: otra tanda no está bloqueada",                      r.otraTandaPasa === true],
    ["5070: la barra existe",                                   r.progExiste === true],
    ["5070: 1 de 3 en ventana → 33%, rojo",                     r.progTxt === "1/3 · 33%" && /\blow\b/.test(r.progCls || "") && r.progW === "33%"],
    ["5070: todas hechas → 100%, verde",                        r.progTxt2 === "3/3 · 100%" && /\bok\b/.test(r.progCls2 || "")],
    ["5070: no se duplica al refrescar",                        r.unaSola === 1],
    ["sin errores de página",                                   errs.length === 0]
  ];
  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "mejoras-v1298: " + bad + " FALLA(S)" : "mejoras-v1298: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
