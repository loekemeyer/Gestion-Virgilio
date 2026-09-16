/* Regresión v18.42 → endurecida en la v18.73 — dos armados (o dos pickings) abiertos a la vez.

   `st.armado` / `st.picking` son UN SOLO casillero: arrancar el segundo PISA al primero, que
   queda sin TAP/TP, fuera de "Terminar Día" y trabado para los demás (casos reales E11B,
   D71A, E25A, E23A).

   La v18.42 avisaba con un `confirm` y "Aceptar = arrancar igual" — o sea que dejar la vieja
   colgada estaba a UN TOQUE, y se siguió usando. Luis, 16/09: "ningún operario puede arrancar
   a pickear una tanda si ya tiene una abierta (y lo mismo con armado)". Desde la v18.73 es un
   CORTE: no se pregunta, no se manda el evento, y se reabre la tanda vieja para que la cierre.
   El invariante lo garantiza el backend (`gv_tanda_reservar`, motivo 'otra_tanda_abierta');
   este test cuida la mitad del front.

   Chequea:
     1) AP con OTRA tanda abierta → NO pregunta, no encola, reabre el asistente de la vieja,
        y la vieja sigue abierta;
     2) que no haya forma de forzarlo: aunque algo conteste que sí a un confirm, no se manda;
     3) EP idem, con showPickingList de la tanda vieja;
     4) sin nada abierto, el AP normal no molesta y encola como siempre.
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
  /* v18.72 — este test ejecuta `send()`, que reserva la tanda contra Supabase. Sin este corte
     la corrida ESCRIBE EN LA BASE REAL: el 15/09 dejó dos locks del legajo de prueba 999
     (C72F/picking y D11X/armado) que, con el lock sin TTL de la v18.65, bloqueaban esas dos
     tandas para los operarios de verdad. Antes se limpiaban solos a las 10 h y por eso nadie
     lo había notado. Abortar la red deja a `tandaReservar` fallando ABIERTO, que es su
     comportamiento sin conexión y no cambia lo que este test mide. */
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const leg = "999";
    legajoInput.value = leg;
    const avisos = [];
    window.alert = function (m) { avisos.push(String(m)); };

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

    // ---- 1) AP con OTRA tanda abierta → corta, no encola, reabre la vieja ----
    {
      abrirArmado("E11B");
      let pregunto = false;
      window.confirm = function () { pregunto = true; return true; };
      enq.length = 0; comp = null; avisos.length = 0;
      selectOption("AP"); textInput.value = "E01C";
      await send();
      out.apNoPregunta    = !pregunto;
      out.apAvisaYCorta   = avisos.length === 1 && /⛔/.test(avisos[0]) &&
                            avisos[0].indexOf("E11B") >= 0 && avisos[0].indexOf("E01C") >= 0;
      out.apDiceComoSoltar= /No la armo yo/i.test(avisos[0] || "");
      out.apNoEnq         = enq.indexOf("AP") < 0;
      out.apReabreVieja   = !!(comp && comp[1] === "E11B");
      out.apSigueAbierta  = (getLegajoState(leg).armado || {}).value === "E11B";
    }

    // ---- 2) no se puede forzar: aunque el confirm conteste que sí, no se manda ----
    {
      abrirArmado("E11B");
      window.confirm = function () { return true; };
      enq.length = 0;
      selectOption("AP"); textInput.value = "E01C";
      await send();
      out.noSePuedeForzar = enq.indexOf("AP") < 0;
      out.viejaIntacta    = (getLegajoState(leg).armado || {}).value === "E11B";
    }

    // ---- 3) EP con OTRO picking abierto → corta, no encola, reabre el viejo ----
    {
      abrirPicking("E11B");
      let preguntoEP = false;
      window.confirm = function () { preguntoEP = true; return true; };
      enq.length = 0; pick = null; avisos.length = 0;
      selectOption("EP"); textInput.value = "E01C";
      await send();
      out.epNoPregunta     = !preguntoEP;
      out.epAvisaYCorta    = avisos.length === 1 && /⛔/.test(avisos[0]) &&
                             avisos[0].indexOf("E11B") >= 0;
      out.epDiceComoSoltar = /Anular picking/i.test(avisos[0] || "");
      out.epNoEnq          = enq.indexOf("EP") < 0;
      out.epReabreViejo    = !!(pick && pick[0] === "E11B");
    }

    // ---- 4) sin nada abierto, el AP normal NO molesta ----
    {
      const st = getLegajoState(leg);
      st.armado = { active: false, value: "", ts_inicio: null };
      st.picking = { active: false, value: "", ts_inicio: null };
      setLegajoState(leg, st);
      let pregunto = false;
      window.confirm = function () { pregunto = true; return true; };
      enq.length = 0; avisos.length = 0;
      selectOption("AP"); textInput.value = "E22Z";
      await send();
      out.limpioNoPregunta = !pregunto;
      out.limpioNoCorta    = !avisos.some(function (m) { return /⛔/.test(m); });
      out.limpioEnq        = enq.indexOf("AP") >= 0;
    }
    return out;
  });
  const malas = Object.keys(r).filter(function (k) { return !r[k]; });
  const pass = malas.length === 0 && errs.length === 0;
  console.log("dos-en-curso:", JSON.stringify(r),
    malas.length ? "· fallan: " + malas.join(", ") : "",
    "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
