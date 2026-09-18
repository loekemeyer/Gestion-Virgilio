/* Regresión v19.92 — una tanda SIN pedidos en la PPP ya no deja al operario sin salida.
   Caso real del 18/09 (legajo 8, tanda E12M): su pedido —LK 0029— se había mudado a E12A, así
   que el código quedó con el picking viejo y CERO pedidos. Desde ahí las tres salidas estaban
   cerradas a la vez: «Terminar» (TAP) manda al asistente porque la tanda no tiene Entregas, el
   asistente volvía EN SILENCIO porque no hay pedidos, y con un armado abierto el botón AP queda
   bloqueado. Tres horas mirando la pantalla sin un solo cartel.
   Chequea:
     1) el asistente avisa que la tanda no tiene pedidos (no se vuelve callado);
     2) si el armado abierto es del que mira, llama a anular_armado_virgilio con ESA tanda y le
        limpia el casillero, así puede agarrar la que corresponde;
     3) ⚠ y suelta la tanda que se le pidió, NO la que quedó en `_comp` de un wizard anterior;
     4) si no tiene ese armado abierto, avisa y NO llama a ninguna RPC.
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
    const leg = "8", TANDA = "E12M", OTRA = "E12A";
    legajoInput.value = leg;
    let avisos = [], llamadas = [];
    window.alert   = function (m) { avisos.push(String(m || "")); };
    window.confirm = function () { return true; };
    window.prompt  = function () { return ""; };
    window.tandaLiberar = async function () {};
    window.tandaLockAnular = function () {};
    window.renderLegajoHistory = function () {};
    window.updateCoreButtonsState = function () {};
    window.updatePendingIndicator = function () {};
    window.renderPendingSuggestion = function () {};
    // la PPP no conoce la tanda: ése es todo el caso
    window.faltGetEnrich    = async function () { return null; };
    window.fetchMonitorSheet = async function () { return new Map(); };
    window.fetchPickingBase  = async function () { return new Map(); };
    window._compTandaYaArmada = async function () { return false; };
    window.fetch = async function (url, opt) {
      const u = String(url);
      if (u.indexOf("rpc/anular_armado_virgilio") >= 0) {
        llamadas.push(JSON.parse(opt.body));
        return { ok: true, status: 200, json: async () => "ok", headers: { get: () => null } };
      }
      return { ok: true, status: 200, json: async () => [], headers: { get: () => null } };
    };
    const abrirArmado = function () {
      const st = getLegajoState(leg);
      st.armado = { active: true, value: TANDA, ts_inicio: "2026-09-18T16:23:33.000Z" };
      setLegajoState(leg, st);
    };

    // ---- 1) el armado abierto es suyo → avisa y lo suelta ----
    abrirArmado(); avisos = []; llamadas = []; _comp = null;
    localStorage.removeItem("vir_comp_" + TANDA);
    await showCompletarWizard(leg, TANDA);
    out.aviso       = avisos.some(function (m) { return /no tiene ning/i.test(m) && m.indexOf(TANDA) >= 0; });
    out.llamoRpc    = llamadas.length === 1;
    out.tandaOk     = !!(llamadas[0] && llamadas[0].p_tanda === TANDA && llamadas[0].p_legajo === leg);
    const st1 = getLegajoState(leg);
    out.limpioEstado = !(st1.armado && st1.armado.active);
    out.noAbrioModal = !document.getElementById("completarModal").classList.contains("show");

    // ---- 2) con OTRO wizard en memoria, suelta la tanda pedida, no la de _comp ----
    abrirArmado(); avisos = []; llamadas = [];
    _comp = { tanda: OTRA, legajo: leg, nps: [{ np: "LK 0029" }], step: 2 };
    localStorage.removeItem("vir_comp_" + TANDA);
    await showCompletarWizard(leg, TANDA);
    out.noSoltoLaOtra = !!(llamadas[0] && llamadas[0].p_tanda === TANDA);

    // ---- 3) no es su armado → avisa y no toca nada ----
    try { const st = getLegajoState(leg); st.armado = { active: false, value: "", ts_inicio: null }; setLegajoState(leg, st); } catch (_e) {}
    avisos = []; llamadas = []; _comp = null;
    await showCompletarWizard(leg, TANDA);
    out.avisoSinArmado = avisos.some(function (m) { return /no tiene ning/i.test(m); });
    out.sinRpc         = llamadas.length === 0;
    return out;
  });
  const ok = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("comp-tanda-sin-pedidos:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLA");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
