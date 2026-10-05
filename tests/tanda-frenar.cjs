/* v26.62 (Luis, 05/10) — «Frenar la tanda», parte 2: el operario frena, otro (o él) la retoma.
   FRENAR ≠ PAUSAR: pausar es salir un rato (la tanda sigue siendo suya); frenar la suelta con
   todo lo hecho guardado en el servidor.
   (A) Picking: «Frenar la tanda» pide confirmación con el texto de Luis y dónde quedó el carro,
       manda ANTES lo que la cola tenía de esa tanda (EP y PKC), frena en la base y cierra la
       tarea en el celular (sin TP: queda en el historial como «Frenó picking»).
   (B) Sin señal no se frena: todo queda como estaba.
   (C) Si no dice dónde quedó el carro, no se frena.
   (D) Armado: la foto del armado llega al servidor ANTES de frenar; después se cierra la tarea.
   (E) Armado sin señal: no se frena.
   (F) Enviar EP sobre una tanda frenada por OTRO: cartel «Estás por agarrar una tanda que empezó
       X ¿Seguro?» exacto; «No» no registra nada; «Sí» se la lleva y abre el picking con lo
       pickeado de TODOS desde el servidor. La propia se retoma sin cartel.
   (G) Lista de tandas: la frenada vuelve a la lista de picking con ⏸; no aparece para «terminar».
   (H) Retomar el picking trae las marcas de todos, y corregir un artículo pisa SU fila (no suma otra).
   (I) Armado en otro celular / tanda frenada: el asistente arranca desde la foto del servidor, a
       nombre del que arma AHORA.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const llamadas = []; let modo = "ok";
  await p.route("**/*.supabase.co/**", (r) => r.abort());   // primero: Playwright corre las rutas al revés
  await p.route("**/rest/v1/rpc/gv_tanda_frenar**", async (route) => {
    let body = {}; try { body = JSON.parse(route.request().postData() || "{}"); } catch (_e) {}
    llamadas.push({ q: "frenar", body: body, t: Date.now() });
    if (modo === "sinred") return route.abort();
    return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ok: true, motivo: "frenada" }) });
  });
  await p.route("**/rest/v1/rpc/gv_armado_avance_guardar**", async (route) => {
    let body = {}; try { body = JSON.parse(route.request().postData() || "{}"); } catch (_e) {}
    llamadas.push({ q: "foto", body: body, t: Date.now() });
    if (modo === "sinred") return route.abort();
    return route.fulfill({ status: 200, contentType: "application/json", body: '"ok"' });
  });
  await p.route("**/rest/v1/rpc/gv_armado_avance_leer**", async (route) => {
    llamadas.push({ q: "leer" });
    return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({
      tanda: "F30A", estado: "en_curso", legajo: "104",
      snapshot: { legajo: "104", tanda: "F30A", step: 3, liosNpIdx: 0, clasifDone: true, _difMovs: [],
        nps: [{ np: "LK 0400", rs: "Cliente", clase: "lio", liosDone: false,
                liosArr: [{ items: [{ cod: "501", qty: 2 }], cajas: 2, suelta: false, leg: "104", ts: 1 }],
                codes: [{ cod: "501", raw: "501", sale: 6, rest: 4, cur: 0, sep: true }] }] } }) });
  });
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof pkFrenar === "function" && typeof compFrenar === "function");
  const out = {};
  const fasesT = () => llamadas.map((x) => x.q);

  // ---------------- (A) picking: frenar
  const a = await p.evaluate(async () => {
    const o = {}; let conf = "";
    window.confirm = function (m) { conf = m; return true; };
    window.alert = function () {};
    window.askPickUbicacion = async function () { return "Mesa 2"; };
    const enviados = [];
    window.trySendOneReport = async function (pl) { enviados.push({ op: pl.opcion, t: Date.now() }); return { ok: true }; };
    localStorage.clear(); legajoInput.value = "104";
    const st = getLegajoState("104"); st.picking = { active: true, value: "F30A", ts_inicio: new Date(Date.now() - 40 * 60000).toISOString() }; setLegajoState("104", st);
    // en la cola: el EP y un PKC de esta tanda, y uno de OTRA (no se manda)
    _enqueueReportRaw({ legajo: "104", opcion: "EP", texto: "F30A", ts: Date.now(), id: "q_ep" });
    _enqueueReportRaw({ legajo: "104", opcion: "PKC", texto: "F30A|501|6|6|0", ts: Date.now(), id: "q_pkc" });
    _enqueueReportRaw({ legajo: "104", opcion: "PKC", texto: "F31B|502|1|1|0", ts: Date.now(), id: "q_otra" });
    _pk = { tanda: "F30A", legajo: "104", items: [{ art: "501", key: "501", esp: 6 }], idx: 0, results: { "501": 6 }, mode: "item" };
    pkSave();
    document.getElementById("tandaModal").classList.add("show");
    await pkFrenar();
    o.conf = conf;
    o.enviados = enviados.map((x) => x.op).join(",");
    o.colaQueda = readQueue().map((x) => x.id).join(",");
    const st2 = getLegajoState("104");
    o.pickingCerrado = !(st2.picking && st2.picking.active);
    o.guardadoBorrado = localStorage.getItem("vir_pk_104") === null;
    o.pkNull = _pk === null;
    o.hist = readDayHist(getTodayKey(), "104").map((x) => x.opcion + ":" + x.texto).join(",");
    o.tEnvio = enviados.length ? enviados[enviados.length - 1].t : 0;
    return o;
  });
  const frA = llamadas.find((x) => x.q === "frenar");
  out.aCartelTextoDeLuis = /Se guardará el registro de todo lo que se pickeó hasta ahora y se podrá retomar después por vos u otro operario/.test(a.conf);
  out.aMandaColaDeEsaTanda = a.enviados === "EP,PKC" && a.colaQueda === "q_otra";
  out.aColaAntesDeFrenar = !!(frA && a.tEnvio && a.tEnvio <= frA.t);
  out.aFrenaConUbicacion = !!(frA && frA.body.p_tanda === "F30A" && frA.body.p_fase === "picking" && frA.body.p_legajo === "104" &&
                              frA.body.p_motivo === "boton" && frA.body.p_ubicacion === "Mesa 2" && frA.body.p_ts_cliente);
  out.aCierraEnElCelular = a.pickingCerrado && a.guardadoBorrado && a.pkNull;
  out.aHistorialFreno = /PKF:F30A/.test(a.hist);

  // ---------------- (B) sin señal: no se frena
  llamadas.length = 0; modo = "sinred";
  const bq = await p.evaluate(async () => {
    localStorage.clear(); legajoInput.value = "104";
    window.trySendOneReport = async function () { return { ok: true }; };
    const st = getLegajoState("104"); st.picking = { active: true, value: "F30A", ts_inicio: null }; setLegajoState("104", st);
    _pk = { tanda: "F30A", legajo: "104", items: [{ art: "501", key: "501", esp: 6 }], idx: 0, results: {}, mode: "item" };
    let alerta = ""; window.alert = function (m) { alerta = m; };
    await pkFrenar();
    const st2 = getLegajoState("104");
    return { sigue: !!(st2.picking && st2.picking.active) && _pk !== null, alerta: alerta };
  });
  out.bSinSenalNoFrena = bq.sigue && /Sin señal/.test(bq.alerta);
  modo = "ok";

  // ---------------- (C) sin ubicación: no se frena
  llamadas.length = 0;
  const c = await p.evaluate(async () => {
    window.askPickUbicacion = async function () { return null; };
    _pk = { tanda: "F30A", legajo: "104", items: [], idx: 0, results: {}, mode: "item" };
    await pkFrenar();
    return _pk !== null;
  });
  out.cSinUbicacionNoFrena = c && !fasesT().includes("frenar");

  // ---------------- (D) armado: foto antes de frenar
  llamadas.length = 0;
  const d = await p.evaluate(async () => {
    let conf = ""; window.confirm = function (m) { conf = m; return true; }; window.alert = function () {};
    window.trySendOneReport = async function () { return { ok: true }; };
    localStorage.clear(); legajoInput.value = "8";
    const st = getLegajoState("8"); st.armado = { active: true, value: "F30A", ts_inicio: new Date().toISOString() }; setLegajoState("8", st);
    _comp = { legajo: "8", tanda: "F30A", step: 3, liosNpIdx: 0, _difMovs: [],
      nps: [{ np: "LK 0400", rs: "C", clase: "lio", liosArr: [{ items: [{ cod: "501", qty: 2 }], cajas: 2, suelta: false, leg: "8", ts: 1 }], codes: [] }] };
    _compPersist();
    document.getElementById("completarModal").classList.add("show");
    await compFrenar();
    const st2 = getLegajoState("8");
    return { conf: conf, cerrado: !(st2.armado && st2.armado.active), compNull: _comp === null,
             local: localStorage.getItem("vir_comp_F30A"), hist: readDayHist(getTodayKey(), "8").map((x) => x.opcion).join(","),
             modal: document.getElementById("completarModal").classList.contains("show") };
  });
  const seq = fasesT();
  const foto = llamadas.find((x) => x.q === "foto");
  out.dCartelTextoDeLuis = /todo lo que se armó hasta ahora y se podrá retomar después por vos u otro operario/.test(d.conf);
  out.dFotoAntesDeFrenar = seq.indexOf("foto") >= 0 && seq.indexOf("frenar") > seq.indexOf("foto") &&
                           !!(foto && foto.body.p_snapshot && foto.body.p_snapshot.nps[0].liosArr.length === 1);
  out.dCierraEnElCelular = d.cerrado && d.compNull && d.local === null && !d.modal && /APF/.test(d.hist);

  // ---------------- (E) armado sin señal
  llamadas.length = 0; modo = "sinred";
  const e = await p.evaluate(async () => {
    window.alert = function () {};
    const st = getLegajoState("8"); st.armado = { active: true, value: "F30A", ts_inicio: null }; setLegajoState("8", st);
    _comp = { legajo: "8", tanda: "F30A", step: 3, nps: [{ np: "LK 0400", liosArr: [], codes: [] }], _difMovs: [] };
    await compFrenar();
    const st2 = getLegajoState("8");
    return !!(st2.armado && st2.armado.active) && _comp !== null;
  });
  out.eArmadoSinSenalNoFrena = e && !fasesT().includes("frenar");
  modo = "ok";

  // ---------------- (F) Enviar EP sobre una frenada
  const f = await p.evaluate(async () => {
    const o = {};
    localStorage.clear(); legajoInput.value = "277";
    window.alert = function () {};
    window.maybeRegisterLateArrival = async function () {};
    window.trySendOneReport = async function () { return { ok: true }; };
    window.fetchMonitorSheet = async function () { return new Map(); };
    window.fetchPickingBase = async function () { return new Map(); };
    window.getEmpleadosNombres = async function () { return new Map([["104", "Jhonny"]]); };
    window.__gasOrig = window.getActivityStatus;
    window.getActivityStatus = async function () { return { pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map(), pickingFrenadaBy: new Map([["F30A", "104"]]), armadoFrenadaBy: new Map(), pickingDone: new Set(), armadoDone: new Set() }; };
    let abre = null; window.showPickingList = function (t, l, opts) { abre = { t: t, l: l, opts: opts || null }; };
    const enq = []; window.enqueueReport = function (pl) { enq.push(pl.opcion); };
    let tomo = 0; window.tandaTomarFrenada = async function () { tomo++; return { ok: true, motivo: "tomada_de", ubicacion: "Mesa 2" }; };
    window.tandaReservar = async function () { return { ok: false, motivo: "frenada", legajo: "104", nombre: "" }; };
    // 1) dice que NO
    let conf = ""; window.confirm = function (m) { conf = m; return false; };
    selectOption("EP"); textInput.value = "F30A"; await send();
    o.cartel = conf; o.noRegistra = enq.length === 0 && tomo === 0 && abre === null;
    // 2) dice que SÍ
    window.confirm = function () { return true; };
    selectOption("EP"); textInput.value = "F30A"; await send();
    o.tomo = tomo; o.ep = enq.join(","); o.abre = abre;
    // 3) la PROPIA: la reserva ya la vuelve a tomar, sin cartel
    localStorage.clear(); legajoInput.value = "104"; enq.length = 0; abre = null; tomo = 0;
    let conf3 = null; window.confirm = function (m) { conf3 = m; return true; };
    window.tandaReservar = async function () { return { ok: true, motivo: "propia", retomada: true, legajo: "104" }; };
    selectOption("EP"); textInput.value = "F30A"; await send();
    o.propiaSinCartel = conf3 === null && tomo === 0 && enq.join(",") === "EP";
    o.abrePropia = abre;
    return o;
  });
  out.fCartelExacto = f.cartel === "Estás por agarrar una tanda que empezó Jhonny ¿Seguro?";
  out.fNoNoRegistra = f.noRegistra;
  out.fSiSeLaLleva = f.tomo === 1 && f.ep === "EP" && !!(f.abre && f.abre.t === "F30A" && f.abre.opts && f.abre.opts.seedFromServer && f.abre.opts.todos);
  out.fPropiaSinCartel = f.propiaSinCartel && !!(f.abrePropia && f.abrePropia.opts && f.abrePropia.opts.todos);

  // ---------------- (G) lista de tandas
  const g = await p.evaluate(async () => {
    const o = {};
    legajoInput.value = "277";
    window.getActivityStatus = window.__gasOrig;
    _activityStatusTs = 0; _activityStatusCache = null;
    const hace = (m) => new Date(Date.now() - m * 60000).toISOString();
    window.supaFetchAll = async function (ep, q) {
      if (/opcion=in\.\(EP,TP,AP,TAP,PKF,APF\)/.test(q)) return [
        { opcion: "EP", texto: "F30A", ts_cliente: hace(90), legajo: "104" },
        { opcion: "PKF", texto: "F30A", ts_cliente: hace(30), legajo: "104" },
        { opcion: "EP", texto: "F31B", ts_cliente: hace(20), legajo: "8" }];
      return [];
    };
    window.getPppTandasForOperator = async function () {
      const hoy = getTodayKey();
      return ["F30A", "F31B", "F32C"].map((t) => ({ tanda: t, fechaRaw: hoy, fechaDisplay: "Hoy", prioridad: 0 }));
    };
    window.monCargarCamiones = async function () {};
    await populateTandasList("notStarted");
    const box = document.getElementById("tandasList");
    o.epChips = [].slice.call(box.querySelectorAll(".tanda-chip")).map((x) => x.textContent.trim() + (x.classList.contains("frenada") ? "[fr]" : "")).join("|");
    o.txt = (box.querySelector(".tandas-frenada-txt") || {}).textContent || "";
    await populateTandasList("pickingCurso");
    o.tpChips = [].slice.call(box.querySelectorAll(".tanda-chip")).map((x) => x.textContent.trim()).join("|");
    return o;
  });
  out.gFrenadaVuelveAPicking = /F30A ⏸\[fr\]/.test(g.epChips) && /F32C/.test(g.epChips) && !/F31B/.test(g.epChips) && /legajo 104/.test(g.txt);
  out.gFrenadaNoSeTermina = !/F30A/.test(g.tpChips) && /F31B/.test(g.tpChips);

  // ---------------- (H) marcas de todos + client_id
  const h = await p.evaluate(async () => {
    const o = {}; let q = "";
    window.supaFetchAll = async function (ep, qq) { q = qq; return [
      { texto: "F30A|501|6|6|0", ts_cliente: "2026-10-05T12:00:00Z", client_id: "pkc_104_F30A_501_2026-10-05" },
      { texto: "F30A|502|3|2|0", ts_cliente: "2026-10-05T12:01:00Z", client_id: "pkc_104_F30A_502_2026-10-05" }]; };
    const m = await pkFetchServerMarks("F30A", null, null, true);
    o.q = q; o.v501 = m.get("501"); o.cid = m.cid["502"];
    const sent = []; window.enqueueReport = function (pl) { sent.push(pl); };
    window.trySendOneReport = null;
    _pk = { tanda: "F30A", legajo: "277", items: [{ art: "502", key: "502", esp: 3 }], idx: 0, results: { "502": 3 }, mode: "item", excOk: true, cid: m.cid };
    pkSendDetail("502", 3, 3);
    o.id = sent.length ? sent[0].id : "";
    o.leg = sent.length ? sent[0].legajo : "";
    return o;
  });
  out.hTraeLasDeTodos = /texto=like\.F30A%7C\*/.test(h.q) && !/legajo=eq/.test(h.q) && h.v501 === 6;
  out.hCorregirPisaSuFila = h.id === "pkc_104_F30A_502_2026-10-05" && h.leg === "277";

  // ---------------- (I) armado desde la foto del servidor, a nombre del que arma ahora
  const i = await p.evaluate(async () => {
    localStorage.clear(); legajoInput.value = "277";
    window.alert = function () {};
    window.faltGetEnrich = async function () { return { sheetMap: new Map([["F30A", { tanda: "F30A", pedidos: [{ np: "LK 0400", razonSocial: "Cliente", cod: "1" }] }]]), pickBase: new Map() }; };
    window._compTandaYaArmada = async function () { return false; };
    window.etlLoadGlobal = function () {};
    _comp = null;
    await showCompletarWizard("277", "F30A");
    return { leg: _comp && _comp.legajo, lios: _comp && _comp.nps[0].liosArr.length, liosLeg: _comp && _comp.nps[0].liosArr[0].leg,
             abierto: document.getElementById("completarModal").classList.contains("show") };
  });
  out.iArrancaDesdeElServidor = i.abierto && i.lios === 1 && i.liosLeg === "104";
  out.iANombreDelQueArma = i.leg === "277";

  let ok = true;
  for (const k of Object.keys(out)) { console.log((out[k] ? "OK   " : "FALLA") + " " + k); if (!out[k]) ok = false; }
  if (errs.length) { console.log("pageerror:", errs.slice(0, 3)); ok = false; }
  await b.close();
  console.log(ok ? "tanda-frenar: OK" : "tanda-frenar: FALLA");
  process.exit(ok ? 0 : 1);
})();
