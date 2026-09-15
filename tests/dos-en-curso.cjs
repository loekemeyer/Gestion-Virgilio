/* Regresión v18.42 — dos armados (o dos pickings) abiertos a la vez.
   `st.armado` / `st.picking` son UN SOLO casillero: arrancar el segundo PISA al primero,
   que queda sin TAP/TP, fuera de "Terminar Día" y trabado para los demás (casos reales
   E11B y D71A). Ahora se avisa antes:
     1) AP con OTRA tanda abierta → confirm. Cancelar = no manda nada y reabre el asistente
        de la tanda vieja; Aceptar = arranca la nueva igual.
     2) EP idem, con showPickingList de la tanda vieja al cancelar.
     3) El aviso NO aparece si no hay nada abierto (no molestar en el caso normal).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const leg = "999";
    legajoInput.value = leg;
    window.alert = function () {};

    // Stubs: cortamos todo lo que sale a la red para quedarnos con las guardas.
    window.maybeRegisterLateArrival = async function () {};
    window.trySendOneReport = async function () { return { ok: true }; };
    window.getActivityStatus = async function () { return null; };
    window.fetchMonitorSheet = async function () { return null; };
    window.tandaReservar = async function () { return null; };
    window.getEmpleadosNombres = async function () { return new Map(); };

    const enq = [];
    window.enqueueReport = function (pl) { enq.push(pl && pl.opcion); };
    let comp = null; window.showCompletarWizard = function (l, c) { comp = [l, c]; };
    let pick = null; window.showPickingList = function (t, l) { pick = [t, l]; };

    const abrirArmado = function (tanda) {
      const st = getLegajoState(leg);
      st.armado  = { active: true, value: tanda, ts_inicio: new Date().toISOString() };
      st.picking = { active: false, value: "", ts_inicio: null };
      st.toggles = {}; setLegajoState(leg, st);
    };
    const abrirPicking = function (tanda) {
      const st = getLegajoState(leg);
      st.picking = { active: true, value: tanda, ts_inicio: new Date().toISOString() };
      st.armado  = { active: false, value: "", ts_inicio: null };
      st.toggles = {}; setLegajoState(leg, st);
    };

    // ---- 1) AP con OTRA tanda abierta, CANCELANDO → no manda nada, reabre la vieja ----
    {
      abrirArmado("E11B");
      let preguntado = null;
      window.confirm = function (msg) { preguntado = msg; return false; };
      enq.length = 0; comp = null;
      selectOption("AP"); textInput.value = "E01C";
      await send();
      out.apPregunta      = !!(preguntado && preguntado.indexOf("E11B") >= 0 && preguntado.indexOf("E01C") >= 0);
      out.apCancelNoEnq   = enq.indexOf("AP") < 0;
      out.apCancelReabre  = comp && comp[1] === "E11B";
      out.apSigueAbierta  = (getLegajoState(leg).armado || {}).value === "E11B";
    }

    // ---- 2) AP con OTRA tanda abierta, ACEPTANDO → arranca la nueva ----
    {
      abrirArmado("E11B");
      window.confirm = function () { return true; };
      enq.length = 0;
      selectOption("AP"); textInput.value = "E01C";
      await send();
      out.apOkEnq = enq.indexOf("AP") >= 0;
    }

    // ---- 3) EP con OTRO picking abierto, CANCELANDO → no manda nada, reabre el viejo ----
    {
      abrirPicking("E11B");
      let preguntadoEP = null;
      window.confirm = function (msg) { preguntadoEP = msg; return false; };
      enq.length = 0; pick = null;
      selectOption("EP"); textInput.value = "E01C";
      await send();
      out.epPregunta     = !!(preguntadoEP && preguntadoEP.indexOf("E11B") >= 0);
      out.epCancelNoEnq  = enq.indexOf("EP") < 0;
      out.epCancelReabre = pick && pick[0] === "E11B";
    }

    // ---- 4) sin nada abierto, el AP normal NO pregunta ----
    {
      const st = getLegajoState(leg);
      st.armado = { active: false, value: "", ts_inicio: null };
      st.picking = { active: false, value: "", ts_inicio: null };
      setLegajoState(leg, st);
      let pregunto = false;
      window.confirm = function () { pregunto = true; return true; };
      enq.length = 0;
      selectOption("AP"); textInput.value = "E22Z";
      await send();
      out.limpioNoPregunta = !pregunto;
      out.limpioEnq        = enq.indexOf("AP") >= 0;
    }
    return out;
  });
  const pass =
    r.apPregunta && r.apCancelNoEnq && r.apCancelReabre && r.apSigueAbierta && r.apOkEnq &&
    r.epPregunta && r.epCancelNoEnq && r.epCancelReabre &&
    r.limpioNoPregunta && r.limpioEnq &&
    errs.length === 0;
  console.log("dos-en-curso:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
