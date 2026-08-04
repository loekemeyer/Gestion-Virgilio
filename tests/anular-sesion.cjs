/* Test de regresión (v7.13) — ANULAR una sesión empezada por error.

   "Cerrar" sólo sale del modal: el picking seguía abierto (EP sin TP), la tanda
   reservada y el operario trabado. Ahora hay un botón rojo abajo de todo, tanto en el
   picking como en insumos (RI/EI), que ANULA la sesión.

   Verifica, con fetch/confirm/alert stubeados (sin red):
   PICKING
   - el modal de picking muestra el botón "✕ Anular picking" en el pie, en TODOS los
     pasos (artículo y resumen), y NO aparece cuando el modal lo usa otro flujo,
   - cancelar el confirm no toca nada,
   - anular: llama a la RPC anular_picking_virgilio con legajo+tanda, suelta la tanda
     (tanda_liberar), deja el picking del legajo cerrado (para poder arrancar otro),
     borra el avance guardado (vir_pk_<legajo>), saca EP y PKC de la cola y del
     historial del día, y cierra el modal,
   - si la RPC dice 'ya_cerrado' igual limpia la pantalla (no deja al operario trabado).
   INSUMOS
   - el modal RI/EI muestra "✕ Anular recepción/entrega de insumos",
   - anular: llama a anular_toggle_virgilio con legajo+RI/EI, cierra el toggle del
     legajo, borra el borrador (opDraft) y cierra el modal.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, LEG = "104", TANDA = "D18A";

    // ---- stubs: nada de red, confirm/alert automáticos ----
    window.__rpc = [];
    window.fetch = function (url, opt) {
      let body = null; try { body = JSON.parse((opt && opt.body) || "null"); } catch (_e) {}
      window.__rpc.push({ url: String(url), body: body });
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(window.__rpcResp || "ok"), text: () => Promise.resolve("") });
    };
    window.__confirm = true;
    window.confirm = function () { return window.__confirm; };
    window.__alerts = [];
    window.alert = function (m) { window.__alerts.push(String(m)); };
    const rpcCalls = (name) => window.__rpc.filter((x) => x.url.indexOf("/rpc/" + name) >= 0);

    // ================= PICKING =================
    const st0 = getLegajoState(LEG);
    st0.picking = { active: true, value: TANDA, ts_inicio: new Date().toISOString() };
    setLegajoState(LEG, st0);
    writeDayHist(getTodayKey(), LEG, [
      { id: "ep1", opcion: "EP", descripcion: "Empecé Picking", texto: TANDA, ts: Date.now(), status: "sent" },
      { id: "pkc1", opcion: "PKC", descripcion: "Picking artículo", texto: TANDA + "|518|5|5", ts: Date.now(), status: "sent" },
      { id: "mg1", opcion: "MG", descripcion: "Guardado a Góndola", texto: "", ts: Date.now(), status: "sent" }
    ]);
    writeQueue([
      { id: "ep1", legajo: LEG, opcion: "EP", texto: TANDA },
      { id: "pkc1", legajo: LEG, opcion: "PKC", texto: TANDA + "|518|5|5" },
      { id: "otro", legajo: LEG, opcion: "MG", texto: "" }
    ]);
    localStorage.setItem("vir_pk_" + LEG, JSON.stringify({ day: getTodayKey(), tanda: TANDA, legajo: LEG, items: [{ key: "a" }], idx: 0, results: {} }));

    // sesión abierta: el pie trae el botón en el paso de artículo Y en el resumen
    _pk = { tanda: TANDA, legajo: LEG, mode: "item", idx: 0, results: {},
            items: [{ key: "k1", art: "518", esp: 5, sector: "B49" }] };
    pkRender();
    const foot = document.querySelector("#tandaModal .tanda-modal-foot");
    const btn = foot ? foot.querySelector("button.pk-anular") : null;
    out.botonEnPaso = !!btn && btn.innerText.indexOf("Anular picking") >= 0;
    _pk.idx = 1; pkRender();   // pantalla de resumen
    out.botonEnResumen = !!document.querySelector("#tandaModal .tanda-modal-foot button.pk-anular");
    _pk.idx = 0; pkRender();

    // cancelar el confirm no toca nada
    window.__confirm = false;
    await pkAnular();
    out.cancelarNoToca = rpcCalls("anular_picking_virgilio").length === 0 &&
      getLegajoState(LEG).picking.active === true &&
      localStorage.getItem("vir_pk_" + LEG) !== null;

    // anular de verdad
    window.__confirm = true;
    await pkAnular();
    const rpcPk = rpcCalls("anular_picking_virgilio");
    out.llamaRpc = rpcPk.length === 1 && rpcPk[0].body && rpcPk[0].body.p_legajo === LEG && rpcPk[0].body.p_tanda === TANDA;
    out.liberaTanda = rpcCalls("tanda_liberar").length === 1;
    const stPk = getLegajoState(LEG);
    out.pickingCerrado = stPk.picking.active === false && stPk.picking.value === "";
    out.borraGuardado = localStorage.getItem("vir_pk_" + LEG) === null;
    const q = readQueue();
    out.limpiaCola = q.length === 1 && q[0].id === "otro";
    const hist = readDayHist(getTodayKey(), LEG);
    out.limpiaHist = hist.length === 1 && hist[0].opcion === "MG";
    out.cierraModal = !document.getElementById("tandaModal").classList.contains("show");
    out.pieVacio = document.querySelector("#tandaModal .tanda-modal-foot").innerHTML === "";
    out.avisa = window.__alerts.some((m) => m.indexOf("anulado") >= 0);

    // 'ya_cerrado' → igual limpia la pantalla
    window.__rpcResp = "ya_cerrado";
    window.__alerts = [];
    const st2 = getLegajoState(LEG);
    st2.picking = { active: true, value: "X99Z", ts_inicio: new Date().toISOString() };
    setLegajoState(LEG, st2);
    _pk = { tanda: "X99Z", legajo: LEG, mode: "item", idx: 0, results: {}, items: [{ key: "k", art: "1", esp: 1 }] };
    await pkAnular();
    out.yaCerrado = getLegajoState(LEG).picking.active === false &&
      window.__alerts.some((m) => m.indexOf("ya estaba cerrado") >= 0);
    window.__rpcResp = "ok";

    // ================= INSUMOS =================
    window.__rpc = []; window.__alerts = [];
    const stI = getLegajoState(LEG);
    stI.toggles = stI.toggles || {}; stI.toggles.RI = new Date().toISOString();
    setLegajoState(LEG, stI);
    opDraftSaveQuiet("INS", LEG, "Recepción de insumos", { legajo: LEG, mode: "RI" });
    _ins = { legajo: LEG, mode: "RI", items: [{ cod: "22", qty: 3, unidad: "Kg", cat: "fleje" }], cat: null, qty: null, filtro: "" };
    const ov = document.getElementById("insModal") || document.body.appendChild(Object.assign(document.createElement("div"), { id: "insModal" }));
    ov.innerHTML = '<div class="ins-card"><div class="ins-body in" id="insBody"></div></div>';
    ov.classList.add("show");
    insRender();
    const btnI = document.querySelector("#insBody button.ins-anular");
    out.botonInsumos = !!btnI && btnI.innerText.indexOf("Anular recepción de insumos") >= 0;

    await insAnular();
    const rpcIns = window.__rpc.filter((x) => x.url.indexOf("/rpc/anular_toggle_virgilio") >= 0);
    out.insRpc = rpcIns.length === 1 && rpcIns[0].body && rpcIns[0].body.p_legajo === LEG && rpcIns[0].body.p_opcion === "RI";
    out.insToggleCerrado = !getLegajoState(LEG).toggles.RI;
    out.insBorrador = opDraftLoad(LEG) === null;
    out.insCierra = !document.getElementById("insModal").classList.contains("show");
    out.insAvisa = window.__alerts.some((m) => m.indexOf("anulada") >= 0);

    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("anular-sesion: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("anular-sesion: OK — picking e insumos se anulan de verdad (RPC + estado local limpio)");
  process.exit(0);
})();
