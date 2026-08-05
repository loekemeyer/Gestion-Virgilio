/* Regresión v7.57 — un operario REAL nunca queda bloqueado por un dueño de PRUEBA (legajo 0/1).
   Caso real D06C: un AP fantasma de legajo 0 dejaba la tanda "en curso por el legajo 0" y ningún
   operario podía arrancar el armado. Ahora los dos gates de send() (exclusividad por
   getActivityStatus y reserva atómica por Tandas_Lock) ignoran a un dueño 0/1.

   Chequea, disparando send() de verdad con stubs:
   - dueño = legajo 0  → NO bloquea (no aparece "ya la está armando").
   - dueño = legajo 237 (real, distinto) → SÍ bloquea, nombrando al 237.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; const alerts = [];
    window.alert = function (m) { alerts.push(String(m)); };
    window.confirm = function () { return true; };
    // Stubs de las dependencias de send() (todas son declaraciones de función → window-stub).
    window.getEmpleadosNombres = async function () { return new Map([["237", "Fulano"]]); };
    window.tandaReservar = async function (t, f, leg) { return { legajo: leg }; };   // yo soy el dueño → gate 2 no bloquea
    window.getLegajoState = function () { return { armado: { active: false, value: "" }, picking: { active: false, value: "" }, toggles: {} }; };
    window.setLegajoState = function () {};
    window.maybeRegisterLateArrival = async function () {};
    window.pushHistoryForLegajo = function () {};
    window.enqueueReport = function () {};
    window.trySendOneReport = async function () { return { ok: true, created_at: "x" }; };
    window.removeFromQueue = function () {};
    window.setHistoryItemStatus = function () {};
    window.showArmadoGuide = async function () {};
    window.showCompletarWizard = async function () {};
    window.fetchMonitorSheet = async function () { return new Map(); };

    function prep() {
      document.getElementById("legajoInput").value = "122";   // operario real
      document.getElementById("textInput").value = "d06c";
      selected = "AP";
    }

    // --- CASO A: dueño = legajo 0 (prueba) → NO debe bloquear ---
    window.getActivityStatus = async function () { return { pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map([["D06C", "0"]]) }; };
    prep(); alerts.length = 0;
    await send();
    out.caso0_bloqueado = alerts.some(function (m) { return m.indexOf("ya la está armando") >= 0; });

    // --- CASO B: dueño = legajo 237 (real, distinto) → SÍ debe bloquear ---
    window.getActivityStatus = async function () { return { pickingEnCursoBy: new Map(), armadoEnCursoBy: new Map([["D06C", "237"]]) }; };
    prep(); alerts.length = 0;
    await send();
    out.casoReal_bloqueado = alerts.some(function (m) { return m.indexOf("ya la está armando") >= 0 && m.indexOf("237") >= 0; });

    out.esP0 = esLegajoPrueba("0"); out.esP1 = esLegajoPrueba("1"); out.esP122 = esLegajoPrueba("122");
    return out;
  });
  const pass = r.caso0_bloqueado === false && r.casoReal_bloqueado === true &&
    r.esP0 === true && r.esP1 === true && r.esP122 === false && errs.length === 0;
  console.log("send-prueba-nobloquea:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
