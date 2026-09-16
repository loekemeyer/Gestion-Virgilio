/* v19.22 — CANCELAR EL "¿DÓNDE DEJÁS LA TANDA?" TIENE QUE DECIRLO.

   Al terminar picking (TP) o armado (TAP) la app pregunta dónde queda la tanda. Si el
   operario cancela, el cierre se aborta — eso está bien, un picking sin ubicación no
   sirve: nadie encuentra la tanda para armarla. Lo que estaba mal es que se abortaba
   EN SILENCIO: apretaba «Fin Picking», veía cerrarse el cuadro y se iba convencido de
   que la tanda estaba terminada. Y no queda ni rastro local, porque el evento nunca se
   crea (la cola guarda eventos ya armados; acá se vuelve antes de armarlo).

   Caso real: E12E el 16/09 — 62 artículos pickeados y la tanda sin TP y sin PUB,
   mientras las otras 8 tandas del día de ese mismo operario tienen los dos. Dijo que
   la había terminado, y tenía razón: la terminó de pickear. Problema 365.

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  // Nada tiene que salir a la red de verdad.
  await p.route("**/rest/v1/**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const LEG = "999997";
    const ev = window.eval;

    let alertado = "";
    const _origAlert = window.alert;
    window.alert = function (m) { alertado = String(m || ""); };
    // Playwright cancela los confirm() solos; el de "duración absurda" no debe saltar,
    // así que el ts_inicio va cerca de ahora.
    const _origConfirm = window.confirm;
    window.confirm = function () { return true; };

    // La cola, interceptada: se mira QUÉ se encola, sin mandar nada.
    ev("window.__enc3 = []; window.__raw3 = _enqueueReportRaw;" +
       "_enqueueReportRaw = function (pl) { window.__enc3.push(pl); };" +
       "window.__try3 = trySendOneReport; trySendOneReport = async function () { return { ok: false }; };");

    // Sin locks del servidor: la tanda no está pickeada ni en curso por otro.
    const _origStatus = window.getActivityStatus;
    window.getActivityStatus = async function () {
      return {
        pickingStarted: new Set(), pickingDone: new Set(), pickingDoneStrict: new Set(),
        armadoStarted: new Set(),  armadoDone: new Set(),  armadoDoneStrict: new Set(),
        pickingEnCursoBy: new Map(), pickingEnCursoTs: new Map(),
        armadoEnCursoBy: new Map(),  armadoEnCursoTs: new Map()
      };
    };
    // El asistente «Completar» y el chequeo de líos no son lo que se prueba acá.
    ev("window.__oComp = (typeof _compTandaYaArmada === 'function') ? _compTandaYaArmada : null;" +
       "_compTandaYaArmada = async function () { return true; };");

    const iniCerca = new Date(Date.now() - 20 * 60000).toISOString();
    function armarEstado(fase, tanda) {
      const st = getLegajoState(LEG);
      st.picking = null; st.armado = null;
      st[fase] = { active: true, value: tanda, ts_inicio: iniCerca };
      setLegajoState(LEG, st);
      try { legajoInput.value = LEG; } catch (_e) {}
      try { textInput.value = tanda; } catch (_e) {}
    }

    /* ============== (A) TP: cancelar avisa y no registra nada ============== */
    ev("window.__oPub = askPickUbicacion; askPickUbicacion = async function () { return null; };");
    armarEstado("picking", "Z77A");
    ev("selected = 'TP';");
    window.__enc3.length = 0; alertado = "";
    await send();
    out.A_no_encola_nada = window.__enc3.length === 0;
    out.A_no_encola_TP   = window.__enc3.filter(x => x.opcion === "TP").length === 0;
    out.A_no_encola_PUB  = window.__enc3.filter(x => x.opcion === "PUB").length === 0;
    out.A_avisa          = alertado.indexOf("NO quedó terminado") >= 0;
    out.A_nombra_la_tanda = alertado.indexOf("Z77A") >= 0;
    out.A_dice_que_hacer = alertado.indexOf("Fin Picking") >= 0;
    // el picking sigue ABIERTO: el operario tiene que poder reintentar
    out.A_sigue_abierto  = !!(getLegajoState(LEG).picking || {}).active;

    /* ============== (B) TP: eligiendo el lugar, cierra normal ============== */
    ev("askPickUbicacion = async function () { return 'Mesa 3'; };");
    armarEstado("picking", "Z77B");
    ev("selected = 'TP';");
    window.__enc3.length = 0; alertado = "";
    await send();
    out.B_encola_TP  = window.__enc3.filter(x => x.opcion === "TP" &&
                        String(x.texto || "").toUpperCase() === "Z77B").length === 1;
    out.B_encola_PUB = window.__enc3.filter(x => x.opcion === "PUB").length === 1;
    out.B_sin_aviso  = alertado.indexOf("NO quedó terminado") < 0;

    /* ============== (C) TAP: el mismo silencio, la misma corrección ============== */
    ev("window.__oArm = askArmadoUbicaciones; askArmadoUbicaciones = async function () { return null; };");
    armarEstado("armado", "Z77C");
    ev("selected = 'TAP';");
    window.__enc3.length = 0; alertado = "";
    await send();
    out.C_no_encola_TAP = window.__enc3.filter(x => x.opcion === "TAP").length === 0;
    out.C_avisa         = alertado.indexOf("NO quedó terminado") >= 0 &&
                          alertado.indexOf("Z77C") >= 0;
    out.C_menciona_omitir = alertado.indexOf("Omitir") >= 0;   // la salida legítima
    out.C_sigue_abierto  = !!(getLegajoState(LEG).armado || {}).active;

    /* (D) "Omitir" ({}) NO es cancelar: el armado se cierra igual, sin ubicaciones. */
    ev("askArmadoUbicaciones = async function () { return {}; };");
    armarEstado("armado", "Z77D");
    ev("selected = 'TAP';");
    window.__enc3.length = 0; alertado = "";
    await send();
    out.D_omitir_cierra = window.__enc3.filter(x => x.opcion === "TAP").length === 1;
    out.D_omitir_sin_aviso = alertado.indexOf("NO quedó terminado") < 0;

    // dejar todo como estaba
    ev("askPickUbicacion = window.__oPub; askArmadoUbicaciones = window.__oArm;" +
       "if (window.__oComp) _compTandaYaArmada = window.__oComp;" +
       "_enqueueReportRaw = window.__raw3; trySendOneReport = window.__try3;" +
       "delete window.__oPub; delete window.__oArm; delete window.__oComp;" +
       "delete window.__raw3; delete window.__try3; delete window.__enc3;");
    window.getActivityStatus = _origStatus;
    window.alert = _origAlert;
    window.confirm = _origConfirm;
    try {
      const m = JSON.parse(localStorage.getItem("legajo_state_virgilio_v1") || "{}");
      delete m[LEG]; localStorage.setItem("legajo_state_virgilio_v1", JSON.stringify(m));
    } catch (_e) {}
    return out;
  });

  const claves = Object.keys(r);
  const malas = claves.filter(k => r[k] !== true);
  const pass = malas.length === 0 && errs.length === 0;
  for (const k of claves) console.log((r[k] === true ? "ok  " : "FAIL") + "   " + k);
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  console.log("\ncierre-cancelado-avisa: " + (pass ? "OK" : "FAIL (" + malas.join(", ") + ")"));
  await b.close(); process.exit(pass ? 0 : 1);
})();
