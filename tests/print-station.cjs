/* Regresión — idea 5044: ESTACIÓN DE IMPRESIÓN (auto-print de remitos al terminar armado).
   Cubre psSeedTodayIfNeeded (siembra lo YA terminado como impreso SIN imprimir, 1 vez por día),
   psPoll (detecta TAL nuevos, dedupea por NP, descarta TAL sin resumen marcándolo impreso,
   avanza lastSeen), psPrintBatch (imprime, loguea, y desde v12.08 marca en Impresion_NP para
   que la Cola no acuse pendientes falsos) y psSetAuto/psIsAuto (switch por dispositivo).
   v26.66 (Luis, 05/10): lo automático sale SÓLO por el helper (gvImprimirAuto → gvHelperEncolar con
   {auto:true}); se marca en Impresion_NP sólo si salió; sin helper (o sin respuesta) psPoll no imprime
   nada y corre los cursores: queda pendiente en la Cola de impresión NP. Todo con fetch stubbeado —
   no toca Supabase. Sale 1 si falla. */
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
    localStorage.clear();

    // ---- stubs: red y render de remitos (no imprimimos de verdad) ----
    let talRows = [];                       // respuesta del endpoint de TAL
    const impresionPosts = [];              // lo que se marca en Impresion_NP
    window.fetch = function (url, opts) {
      const u = String(url);
      if (u.indexOf("Impresion_NP") >= 0 && opts && opts.method === "POST") {
        try { JSON.parse(opts.body).forEach(function (r0) { impresionPosts.push(r0.np); }); } catch (_e) {}
        return Promise.resolve({ ok: true, status: 201 });
      }
      if (u.indexOf("opcion=eq.TAL") >= 0) return Promise.resolve({ ok: true, json: function () { return Promise.resolve(talRows); } });
      return Promise.resolve({ ok: true, json: function () { return Promise.resolve([]); } });
    };
    const printed = [];
    window.__resp = { ok: true, impreso: ["HP"], errores: [] };
    let helperOn = true;
    window.gvHelperActivo = function () { return helperOn; };
    window.helperVivo = async function () { return helperOn; };
    // el helper real arma un PDF y lo manda a 127.0.0.1; acá se registra la hoja y se contesta __resp
    window.gvHelperEncolar = function (tipo, inner, ref, opt) { printed.push(String(inner)); out.ultAuto = !!(opt && opt.auto); return Promise.resolve(window.__resp); };
    window.remitoPrintDoc = function () { out.usoCuadro = true; };   // lo automático NUNCA pasa por acá
    window.armadoRemitoInnerHtml = function (d) { return "REMITO-" + d.np; };
    // el enriquecido real pega a PPP/Entregas/TP; acá alcanza con un passthrough
    window._armadoRemitoDataForItems = async function (items) { return items.map(function (x) { return { np: x.np, rs: "Test", total: 1, nLios: 1 }; }); };
    window.colaImpLoadBadge = function () {};   // el badge real pega a la base
    const espera = function (ms) { return new Promise(function (res) { setTimeout(res, ms); }); };

    // ---- seed: lo ya terminado HOY se marca impreso SIN imprimir ----
    talRows = [
      { texto: "98001|1|D10B|A=1X1|L1", ts_cliente: "2026-01-01T10:00:00-03:00" },
      { texto: "98002|2|D10B|B=2X1|L1", ts_cliente: "2026-01-01T10:05:00-03:00" }
    ];
    await psSeedTodayIfNeeded();
    out.seed_marcaImpresas = psGetPrinted().has("98001") && psGetPrinted().has("98002");
    out.seed_noImprime = printed.length === 0;
    out.seed_lastSeen = !!_ps.lastSeen;
    // segunda llamada en el mismo día: no re-siembra (flag ps_seeded en localStorage)
    talRows = [{ texto: "98099|1|D11B|C=1X1|L1", ts_cliente: "2026-01-01T11:00:00-03:00" }];
    await psSeedTodayIfNeeded();
    out.seed_idempotente = !psGetPrinted().has("98099");

    // ---- poll (force): TAL nuevo con resumen imprime; sin resumen se marca y no imprime;
    //      ya impreso no se repite ----
    talRows = [
      { texto: "98001|1|D10B|A=1X1|L1", ts_cliente: "2026-01-01T12:00:00-03:00", legajo: "122" },  // ya impreso (seed)
      { texto: "98010|3|D12B|C=3X2|L2", ts_cliente: "2026-01-01T12:01:00-03:00", legajo: "122" },  // nuevo → imprime
      { texto: "98011|4|D12B||L1",      ts_cliente: "2026-01-01T12:02:00-03:00", legajo: "122" }   // sin resumen → marca, no imprime
    ];
    await psPoll(true); await espera(50);
    out.poll_imprimeNuevo = printed.length === 1 && printed[0] === "REMITO-98010" && out.ultAuto === true && !out.usoCuadro;
    out.poll_marcaNuevo = psGetPrinted().has("98010");
    out.poll_sinResumenMarca = psGetPrinted().has("98011");
    out.poll_lastSeenAvanza = String(_ps.lastSeen) === "2026-01-01T12:02:00-03:00";
    // v12.08: lo impreso por la estación también se marca en Impresion_NP (server)
    out.poll_marcaImpresionNP = impresionPosts.indexOf("98010") >= 0 && impresionPosts.indexOf("98011") < 0;
    // re-poll con las mismas filas: nada nuevo que imprimir
    await psPoll(true);
    out.poll_dedup = printed.length === 1;

    // ---- el helper NO imprimió: no se marca en Impresion_NP (queda pendiente en la Cola) y el log lo dice ----
    window.__resp = { ok: false, impreso: [], errores: [], motivo: "sin regla para armado" };
    impresionPosts.length = 0;
    await psPrintBatch([{ np: "98020", tanda: "D13B", resumen: "D=1X1", armadorLeg: "9" }]); await espera(50);
    out.fallo_noMarca = impresionPosts.indexOf("98020") < 0 && psGetPrinted().has("98020");
    out.fallo_log = !!_ps.log.length && /queda en la Cola/.test(_ps.log[0].nota || "");
    window.__resp = { ok: true, impreso: ["HP"], errores: [] };

    // ---- sin helper: psPoll no imprime nada, no abre el cuadro y corre el cursor a ahora ----
    helperOn = false; printed.length = 0; impresionPosts.length = 0;
    talRows = [{ texto: "98030|1|D14B|C=1X1|L1", ts_cliente: "2026-01-01T13:00:00-03:00", legajo: "122" }];
    _ps.lastSeen = "2026-01-01T12:30:00-03:00";
    await psPoll(true); await espera(50);
    out.sinHelper_noImprime = printed.length === 0 && !out.usoCuadro && impresionPosts.length === 0 && !psGetPrinted().has("98030");
    out.sinHelper_cursorAhora = String(_ps.lastSeen) > "2026-01-02";
    helperOn = true;

    // ---- switch por dispositivo ----
    psSetAuto(true);
    await new Promise(function (res) { setTimeout(res, 150); });   // psStart es async (seed) antes de armar el timer
    out.auto_on = psIsAuto() === true && !!_ps.timer;
    psSetAuto(false);
    out.auto_off = psIsAuto() === false && !_ps.timer;

    return out;
  });
  const pass = r.seed_marcaImpresas && r.seed_noImprime && r.seed_lastSeen && r.seed_idempotente &&
    r.poll_imprimeNuevo && r.poll_marcaNuevo && r.poll_sinResumenMarca && r.poll_lastSeenAvanza &&
    r.poll_marcaImpresionNP && r.poll_dedup &&
    r.fallo_noMarca && r.fallo_log && r.sinHelper_noImprime && r.sinHelper_cursorAhora &&
    r.auto_on && r.auto_off && errs.length === 0;
  console.log("print-station:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
