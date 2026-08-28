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
   RECEPCIÓN (recepcion.js, módulo aparte)
   - la barra "✕ Anular recepción" está en TODOS los pasos del operario y NO para el
     supervisor (menú de Administración),
   - anular: descarta el borrador, llama al hook de Producción y cierra la pantalla,
   - el hook de index.html cierra el toggle RT, llama a anular_toggle_virgilio con
     'RT', pone en 0 el acumulador de cajas y pide 2ª confirmación si ya se mandaron
     entregas en esa sesión (devolviendo false si el operario dice que no).
   INSUMOS
   - el modal RI/EI muestra "✕ Anular recepción/entrega de insumos",
   - anular: llama a anular_toggle_virgilio con legajo+RI/EI, cierra el toggle del
     legajo, borra el borrador (opDraft) y cierra el modal.
   Sale 1 si falla. */
const fs = require("fs");
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

    // ================= RECEPCIÓN (hook de index.html) =================
    window.__rpc = []; window.__alerts = [];
    const stR = getLegajoState(LEG);
    stR.toggles = stR.toggles || {}; stR.toggles.RT = new Date().toISOString();
    setLegajoState(LEG, stR);
    writeDayHist(getTodayKey(), LEG, [{ id: "rt1", opcion: "RT", descripcion: "Recepción Mercadería", texto: "", ts: Date.now(), status: "sent" }]);
    writeQueue([{ id: "rt1", legajo: LEG, opcion: "RT", texto: "" }]);
    localStorage.setItem("vir_recepcion_cajas_" + LEG + "_" + getTodayKey(), "0");
    out.rcpHook = (await window.anularRecepcionSesion(LEG)) === true;
    const rpcRt = window.__rpc.filter((x) => x.url.indexOf("/rpc/anular_toggle_virgilio") >= 0);
    out.rcpRpc = rpcRt.length === 1 && rpcRt[0].body && rpcRt[0].body.p_legajo === LEG && rpcRt[0].body.p_opcion === "RT";
    out.rcpToggle = !getLegajoState(LEG).toggles.RT;
    out.rcpCola = readQueue().length === 0;
    out.rcpHist = readDayHist(getTodayKey(), LEG).length === 0;
    out.rcpCajas = recepcionCajasDelDia(LEG) === 0;

    // con cajas ya enviadas pide 2ª confirmación; si dice que no, NO anula
    const stR2 = getLegajoState(LEG); stR2.toggles.RT = new Date().toISOString(); setLegajoState(LEG, stR2);
    localStorage.setItem("vir_recepcion_cajas_" + LEG + "_" + getTodayKey(), "40");
    window.__confirm = false;
    out.rcpFrena = (await window.anularRecepcionSesion(LEG)) === false &&
      !!getLegajoState(LEG).toggles.RT && recepcionCajasDelDia(LEG) === 40;
    window.__confirm = true;

    return out;
  });

  // ===== 2ª parte: la barra roja dentro de recepcion.js (módulo aparte) =====
  const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
  /* v10.24 — recepcion.js ya no importa supabase-js de esm.sh: toma `createClient` de
     `window.supabase` (vendor/supabase.umd.js). El stub pasó de reemplazar el `import`
     a definir ese global en un <script> clásico ANTES del módulo; si no, recepcion.js
     tira "Falta vendor/supabase.umd.js" y window.__rcp nunca aparece (el test moría
     por timeout en el waitForFunction). */
  const FAKE = `
function __q() { const o = {}; ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","insert","update","delete"].forEach(function (m) { o[m] = function () { return o; }; });
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); }; return o; }
window.supabase = { createClient: function () { return { from: __q, rpc: function () { return Promise.resolve({ data: null, error: null }); },
  auth: { getSession: function () { return Promise.resolve({ data: { session: {} } }); },
          signInAnonymously: function () { return Promise.resolve({ data: { session: {} }, error: null }); } } }; } };
`;
  if (!/window\.supabase/.test(src)) { console.error("anular-sesion: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }
  const patched = src +
    "\nwindow.__rcp = { opState: opState, RECP: RECP, renderMenu: renderMenu, drawArticulosGrid: drawArticulosGrid, el: { page: opPage, bar: opAnularBar } };\n";
  const p3 = await b.newPage();
  p3.on("pageerror", (e) => errs.push("recepcion.js: " + e.message));
  const html3 = '<!doctype html><meta charset="utf-8"><body><script>' + FAKE + '<\/script><script type="module">' + patched + "<\/script></body>";
  await p3.route("http://rcp.test/**", (route) => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: html3 }));
  await p3.goto("http://rcp.test/");
  await p3.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });
  const r3 = await p3.evaluate(async () => {
    const out = {}, R = window.__rcp, S = R.opState, LEG = "104";
    window.__confirm = true; window.confirm = () => window.__confirm;
    window.__alerts = []; window.alert = (m) => window.__alerts.push(String(m));
    window.__hook = null;
    window.anularRecepcionSesion = function (leg) { window.__hook = leg; return Promise.resolve(true); };

    // operario (RT): la barra está desde el primer paso...
    window.openRecepcionOp(LEG, "2026-08-04");
    const btn = R.el.bar.querySelector("button.opAnular");
    out.barraOperario = !!btn && btn.innerText.indexOf("Anular recepción") >= 0;
    // ...y sigue estando en los pasos de adentro (no la pisa ningún render)
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.tallCods = { LK: "L1", CH: null };
    S.linea = "LK"; S.remito = "1"; S.articulos = [{ Cod_Art: "518", Desc: "" }]; S.cargas = { "518": 9 };
    S.step = "articulos"; R.drawArticulosGrid();
    out.barraEnPasos = !!R.el.bar.querySelector("button.opAnular");

    // cancelar el confirm no toca nada
    window.__confirm = false;
    await R.el.bar.querySelector("button.opAnular").onclick();
    out.cancelaNoToca = window.__hook === null && S.cargas["518"] === 9 && R.el.page.classList.contains("open");

    // anular: avisa a Producción, limpia el borrador y cierra
    window.__confirm = true;
    localStorage.setItem("vir_recepcion_draft_" + LEG + "_2026-08-04", '{"v":1,"tallNombre":"Lucho"}');
    await R.el.bar.querySelector("button.opAnular").onclick();
    out.llamaHook = window.__hook === LEG;
    out.limpiaBorrador = localStorage.getItem("vir_recepcion_draft_" + LEG + "_2026-08-04") === null;
    out.cierra = !R.el.page.classList.contains("open") && R.el.bar.innerHTML === "";
    out.avisa = window.__alerts.some((m) => m.indexOf("anulada") >= 0);

    // supervisor (menú de Administración): NO hay sesión RT → sin barra
    window.openRecepcionMenu();
    out.supervisorSinBarra = R.el.bar.innerHTML === "";
    return out;
  });
  Object.keys(r3).forEach(function (k) { r["rcp_" + k] = r3[k]; });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("anular-sesion: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("anular-sesion: OK — picking, recepción e insumos se anulan de verdad (RPC + estado local limpio)");
  process.exit(0);
})();
