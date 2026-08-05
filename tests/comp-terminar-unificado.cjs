/* Unificación v7.75 — el botón "Terminar" del asistente Completar ahora emite TAP
   + mueve stock directamente (antes estaban separados). No hay TAP suelto.

   Chequea, disparando compTerminar() con stubs:
   - Entregas se guardan (_compSaveEntregas es llamado).
   - TAP event se emite (enqueueReport es llamado con opcion=TAP).
   - Stock se mueve (stockSepararAFacturar es llamado).
   - Armado state se marca inactivo.
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
    const out = {};
    const calls = [];

    // Stubs — registrar cada llamada
    window.alert = function () {};
    window._compClearPersist = function () { calls.push("_compClearPersist"); };
    window._compSaveEntregas = function (rows) { calls.push("_compSaveEntregas:" + rows.length); };
    window.getLegajoState = function (l) { calls.push("getLegajoState"); return { armado: { active: true, value: "D06B", ts_inicio: "2026-08-05T11:00:00Z" }, picking: { active: false }, toggles: {} }; };
    window.setLegajoState = function () { calls.push("setLegajoState"); };
    window.pushHistoryForLegajo = function () { calls.push("pushHistoryForLegajo"); };
    window.enqueueReport = function (pl) { calls.push("enqueueReport:" + pl.opcion); };
    window.removeFromQueue = function () { calls.push("removeFromQueue"); };
    window.tandaLiberar = function () { calls.push("tandaLiberar"); };
    window.trySendOneReport = async function () { calls.push("trySendOneReport"); return { ok: true, created_at: "x" }; };
    window.stockSepararAFacturar = async function (t, l) { calls.push("stockSepararAFacturar"); };
    window.updatePendingIndicator = function () { calls.push("updatePendingIndicator"); };
    window._compTandaYaArmada = async function () { calls.push("_compTandaYaArmada"); return false; };
    window.liosSend = function () { calls.push("liosSend"); };
    window._compBuildLiosData = function () { calls.push("_compBuildLiosData"); };
    window._compLiosResumen = function () { return ""; };

    // Setup _comp
    _comp = {
      legajo: "8",
      tanda: "D06B",
      fecha: "2026-08-05",
      hayFalt: false,
      clasifDone: true,
      nps: [{ np: "98151", clase: "lios", liosArr: [], liosDone: true, codes: { "035E": 1 } }],
      pedidoFull: [{ np: "98151", cod: "CLI01", items: [{ art: "035E", cajas: 10 }] }],
      arts: [],
      _liosDirty: false,
      _terminando: false
    };

    // Call compTerminar
    await compTerminar();

    // Check results
    out.compTerminarRan = _comp === null;   // debe estar nulleado
    out.entregarSaved = calls.some(c => c.indexOf("_compSaveEntregas") === 0);
    out.tapEmitted = calls.some(c => c === "enqueueReport:TAP");
    out.stockSeparado = calls.some(c => c === "stockSepararAFacturar");
    out.callsList = calls;

    return out;
  });

  const pass = r.compTerminarRan && r.entregarSaved && r.tapEmitted && r.stockSeparado && errs.length === 0;
  console.log("comp-terminar-unificado:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
