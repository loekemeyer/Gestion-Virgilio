/* Regresión v7.74 — no se puede TERMINAR el armado (TAP) sin haber completado el asistente
   «Completar» (que graba las Entregas/líos). El TAP suelto dejaba la tanda ARMADA sin registros
   → no aparecía en el PDF de Facturado ni en la Composición a líos (caso real D06B).

   Chequea, disparando send() de verdad con stubs:
   - TAP sin registros (no está en _armadoRegistrado y _compTandaYaArmada=false) → NO emite TAP,
     avisa y abre el asistente.
   - TAP con la tanda en _armadoRegistrado (asistente completado) → SÍ emite el TAP (fast-path).
   - TAP con _compTandaYaArmada=true (ya tiene Entregas) → SÍ emite el TAP.
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
    let emitTAP = false, abrioWizard = false;
    window.alert = function (m) { alerts.push(String(m)); };
    window.confirm = function () { return true; };
    window.esOperadorPrueba = function () { return false; };
    window.showCompletarWizard = async function () { abrioWizard = true; };
    window.askArmadoUbicaciones = async function () { return {}; };   // omitir ubicaciones → sigue
    window.emitArmadoUbic = function () {};
    window.maybeRegisterLateArrival = async function () {};
    window.pushHistoryForLegajo = function () {};
    window.getLegajoState = function () { return { armado: { active: true, value: "D06B", ts_inicio: "2026-08-05T11:00:00Z" }, picking: { active: false }, toggles: {} }; };
    window.setLegajoState = function () {};
    window.tandaLiberar = function () {};
    window.stockSepararAFacturar = function () {};
    window.enqueueReport = function (pl) { if (pl && pl.opcion === "TAP") emitTAP = true; };
    window.trySendOneReport = async function () { return { ok: true, created_at: "x" }; };
    window.removeFromQueue = function () {};
    window.setHistoryItemStatus = function () {};

    function prep() {
      document.getElementById("legajoInput").value = "8";
      document.getElementById("textInput").value = "d06b";
      selected = "TAP";
      emitTAP = false; abrioWizard = false; alerts.length = 0;
    }

    // --- CASO A: sin registros → NO emite TAP, abre asistente ---
    _armadoRegistrado.clear();
    window._compTandaYaArmada = async function () { return false; };
    prep(); await send();
    out.A_noEmite = emitTAP === false;
    out.A_abreWizard = abrioWizard === true;
    out.A_avisa = alerts.some(function (m) { return m.indexOf("No") >= 0 || m.indexOf("no completaste") >= 0 || m.indexOf("asistente") >= 0; });

    // --- CASO B: tanda en _armadoRegistrado (fast-path) → SÍ emite TAP ---
    _armadoRegistrado.clear(); _armadoRegistrado.add("D06B");
    window._compTandaYaArmada = async function () { return false; };   // no debería llamarse
    prep(); await send();
    out.B_emite = emitTAP === true;
    out.B_noAbreWizard = abrioWizard === false;

    // --- CASO C: ya tiene Entregas (server) → SÍ emite TAP ---
    _armadoRegistrado.clear();
    window._compTandaYaArmada = async function () { return true; };
    prep(); await send();
    out.C_emite = emitTAP === true;
    return out;
  });
  const pass = r.A_noEmite && r.A_abreWizard && r.A_avisa && r.B_emite && r.B_noAbreWizard && r.C_emite && errs.length === 0;
  console.log("tap-sin-completar:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
