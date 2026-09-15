/* Regresión v18.58 — una tanda que deshicimos a propósito NO va al cartel de error.
   El monitor avisa «⚠ Tandas trabajadas que NO están en PPP — alguien se equivocó» cuando
   una tanda tiene TP/TAP de hoy y ya no figura en la programación. Una tanda desarmada
   (GV_Desarmes) o con el picking/armado anulado (GV_Tanda_Anulada) cumple esa condición
   sin que nadie se haya equivocado: la sacamos nosotros. Pasó el 15/09 con E01G —desarmada
   a pedido de Luis esa misma tarde— y el monitor la señaló igual.
   Chequea, en vivo con fetch mockeado:
     1) una tanda deshecha con TP de hoy y fuera de la PPP NO entra en alertasOffSheet;
     2) una tanda NO deshecha en la misma situación SÍ entra (la alerta sigue sirviendo);
     3) si la lectura de gv_tandas_deshechas falla, el monitor no se cae y la alerta vuelve
        a su comportamiento viejo.
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
    out.hayEndpoint = typeof SUPABASE_TANDAS_DESHECHAS_ENDPOINT === "string" &&
                      /gv_tandas_deshechas/.test(SUPABASE_TANDAS_DESHECHAS_ENDPOINT);
    out.hayFuncion  = typeof fetchTandasDeshechas === "function";
    if (!out.hayEndpoint || !out.hayFuncion) return out;

    // Dos tandas trabajadas HOY (TP) y NINGUNA en la PPP: una deshecha, la otra no.
    const hoy = new Date();
    const iso = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate(), 10, 0, 0).toISOString();
    const eventos = [
      { opcion: "TP", texto: "E01G", ts_cliente: iso, legajo: "277" },
      { opcion: "TP", texto: "E99Z", ts_cliente: iso, legajo: "277" }
    ];

    function armarFetch(deshechasOk) {
      return function (url) {
        const u = String(url);
        const json = (arr) => Promise.resolve({
          ok: true, status: 200,
          headers: { get: (k) => (/range/i.test(k) ? "0-" + Math.max(arr.length - 1, 0) + "/" + arr.length : null) },
          json: () => Promise.resolve(arr)
        });
        if (/gv_tandas_deshechas/.test(u)) {
          if (!deshechasOk) return Promise.reject(new Error("HTTP 500 a propósito"));
          return json([{ tanda: "E01G" }]);
        }
        if (/vista_tanda_status/.test(u)) return json([]);
        if (/Registros_Produccion_Virgilio/.test(u)) {
          // (B) eventos EP/TP/AP/TAP; el resto de las lecturas de la tabla van vacías
          return json(/opcion=in/.test(u) && /TP/.test(u) ? eventos : []);
        }
        return json([]);
      };
    }

    const realFetch = window.fetch;
    const sheetMap = new Map();   // la PPP no tiene ninguna de las dos

    // ---- 1 y 2) con la lista de deshechas disponible ----
    window.fetch = armarFetch(true);
    _tandasDeshechas = null; _tandasDeshechasTs = 0;   // sin cache entre casos
    _supaInflight.clear();
    let res = await fetchMonitorEvents([], sheetMap);
    out.deshechaNoAlerta = !res.alertasOffSheet.includes("E01G");
    out.otraSiAlerta     = res.alertasOffSheet.includes("E99Z");

    // ---- 3) si la lectura falla, el monitor sigue y la alerta vuelve a lo de antes ----
    window.fetch = armarFetch(false);
    _tandasDeshechas = null; _tandasDeshechasTs = 0;
    _supaInflight.clear();
    let murio = false;
    try { res = await fetchMonitorEvents([], sheetMap); } catch (_e) { murio = true; }
    out.noSeCaeSiFalla   = !murio;
    out.sinListaAlertaIgual = !murio && res.alertasOffSheet.includes("E99Z");

    window.fetch = realFetch;
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("monitor-tanda-deshecha:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
