/* Regresión v18.50 — "No la armo yo": soltar un armado agarrado por error.
   Pedido de Luis (15/09): "FO tiene el armado de la E11B pero la seleccionó por error, él no la
   hace". Hasta la v18.49 las únicas salidas eran dar TAP —marcarla armada y mover stock, o sea
   mentir— o dejarla abierta, y abierta queda con candado para todos por la exclusividad v5.74.
   Así se colgó E11B 3 h 30.
   Chequea:
     1) el botón existe en el asistente y llama a compAnularArmado;
     2) confirmar → llama a la RPC anular_armado_virgilio con legajo, tanda y motivo;
     3) limpia el casillero local del armado, el borrador del asistente y cierra el modal;
     4) si la RPC dice "tiene_registros" (el asistente ya grabó Entregas) NO limpia nada y avisa
        que lo tiene que resolver sistemas — borrar eso movería stock;
     5) cancelar el confirm no llama a nada.
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
    const leg = "237", TANDA = "E11B";
    legajoInput.value = leg;
    let avisos = [];
    window.alert = function (m) { avisos.push(String(m || "")); };
    window.prompt = function () { return "la agarré por error, no la hago yo"; };
    window.tandaLiberar = async function () {};
    window.renderLegajoHistory = function () {};
    window.updateCoreButtonsState = function () {};
    window.updatePendingIndicator = function () {};
    window.renderPendingSuggestion = function () {};

    // el botón está y está cableado
    const btn = document.getElementById("compAnular");
    out.botonExiste = !!btn;
    out.botonLlama  = !!(btn && /compAnularArmado/.test(btn.getAttribute("onclick") || ""));
    out.botonTexto  = !!(btn && /no la armo/i.test(btn.textContent));

    let llamadas = [];
    const mockRpc = function (respuesta) {
      window.fetch = async function (url, opt) {
        const u = String(url);
        if (u.indexOf("rpc/anular_armado_virgilio") >= 0) {
          llamadas.push(JSON.parse(opt.body));
          return { ok: true, status: 200, json: async () => respuesta, headers: { get: () => null } };
        }
        return { ok: true, status: 200, json: async () => [], headers: { get: () => null } };
      };
    };
    const prepararArmado = function () {
      const st = getLegajoState(leg);
      st.armado = { active: true, value: TANDA, ts_inicio: "2026-09-15T14:15:00.000Z" };
      setLegajoState(leg, st);
      localStorage.setItem("vir_comp_" + TANDA, JSON.stringify({ _ts: Date.now(), step: 2, tanda: TANDA, nps: [{ np: "CH 0025" }] }));
      _comp = { tanda: TANDA, legajo: leg, nps: [{ np: "CH 0025" }], step: 2 };
      document.getElementById("completarModal").classList.add("show");
    };

    // ---- 1) camino feliz ----
    prepararArmado(); llamadas = []; avisos = [];
    window.confirm = function () { return true; };
    mockRpc("ok");
    await compAnularArmado();
    out.llamoRpc      = llamadas.length === 1;
    out.mandoTanda    = !!(llamadas[0] && llamadas[0].p_tanda === TANDA && llamadas[0].p_legajo === leg);
    out.mandoMotivo   = !!(llamadas[0] && /no la hago yo/.test(llamadas[0].p_motivo || ""));
    const st1 = getLegajoState(leg);
    out.limpioEstado  = !(st1.armado && st1.armado.active);
    out.limpioBorrador= localStorage.getItem("vir_comp_" + TANDA) === null;
    out.cerroModal    = !document.getElementById("completarModal").classList.contains("show");
    out.avisoSoltada  = avisos.some(function (m) { return /pendiente de armar/i.test(m); });

    // ---- 2) la RPC frena porque ya hay Entregas cargadas ----
    prepararArmado(); llamadas = []; avisos = [];
    mockRpc("tiene_registros");
    await compAnularArmado();
    const st2 = getLegajoState(leg);
    out.conRegistrosNoLimpia = !!(st2.armado && st2.armado.active && st2.armado.value === TANDA);
    out.conRegistrosAvisa    = avisos.some(function (m) { return /sistemas/i.test(m); });
    out.conRegistrosNoCierra = document.getElementById("completarModal").classList.contains("show");

    // ---- 3) cancelar no hace nada ----
    prepararArmado(); llamadas = []; avisos = [];
    window.confirm = function () { return false; };
    mockRpc("ok");
    await compAnularArmado();
    out.cancelarNoLlama = llamadas.length === 0;
    const st3 = getLegajoState(leg);
    out.cancelarNoLimpia = !!(st3.armado && st3.armado.active);
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("anular-armado:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
