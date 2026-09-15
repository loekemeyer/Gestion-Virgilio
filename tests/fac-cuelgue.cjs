/* Regresión v18.55 — Facturación no se queda en «Cargando tandas…» para siempre.
   Dos cosas, reportadas por Luis el 15/09 y reproducidas en otra sesión:
     A) `supaFetchAll` cachea la PROMESA de cada consulta en `_supaInflight` y la borra con
        `.finally()`, que sólo corre cuando la promesa se asienta. Un fetch colgado (pestaña
        dormida, máquina suspendida, corte de red de un segundo) dejaba la promesa pendiente
        para siempre, la clave nunca se limpiaba y TODOS los reintentos recibían esa misma
        promesa muerta: no salía ninguna request nueva y sólo destrababa recargar la página.
        Ahora hay timeout (AbortController), así que la promesa siempre se asienta.
     B) El motivo del error no se veía: `facSetStatus` escribe en `.fac-stats`, que está en
        display:none desde la v18.00 por pedido del dueño. La pantalla quedaba con el cartel
        de carga y parecía colgada. Ahora el error se pinta en #facContainer con «Reintentar».
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

    // ---- A) el timeout existe y corta un fetch colgado, dejando la clave libre ----
    out.hayTimeout = typeof SUPA_FETCH_TIMEOUT_MS === "number" && SUPA_FETCH_TIMEOUT_MS > 0;
    const realFetch = window.fetch;
    let pedidos = 0;
    window.fetch = function () { pedidos++; return new Promise(function () {}); };   // cuelga para siempre
    SUPA_FETCH_TIMEOUT_MS = 80;                                                      // acelerado para el test
    let err1 = null;
    try { await supaFetchAll("https://x/rest/v1/prueba", "select=a"); } catch (e) { err1 = e; }
    out.cortaElCuelgue   = !!err1;
    out.diceSinRespuesta = !!(err1 && /sin respuesta/i.test(err1.message || ""));
    // la CLAVE de esta consulta tiene que quedar libre (el mapa puede tener otras de la
    // propia carga de la página, así que no se mira el tamaño total)
    out.claveLiberada    = !_supaInflight.has("https://x/rest/v1/prueba?select=a");

    // el SIGUIENTE intento manda una request NUEVA (antes reusaba la promesa muerta)
    const antes = pedidos;
    try { await supaFetchAll("https://x/rest/v1/prueba", "select=a"); } catch (_e) {}
    out.reintentaDeVerdad = pedidos > antes;
    window.fetch = realFetch;

    // ---- B) el cartel dice qué pasó y ofrece reintentar ----
    // `fetchMonitorSheet` es el PRIMER await de facTick: tirando ahí se entra al catch sin
    // llegar al Promise.all de 15 lecturas (que en file:// no tiene a dónde ir).
    const cont = document.getElementById("facContainer");
    cont.innerHTML = '<div class="fac-empty">Cargando tandas…</div>';
    window.fetchMonitorSheet = async function () { throw new Error("Supabase gv_ppp_programacion_diaria HTTP 500"); };
    await facTick();
    const html = cont.innerHTML || "";
    out.pintaError       = /No se pudo cargar/i.test(html);
    out.diceElMotivo     = /HTTP 500/.test(html);
    out.tieneReintento   = /facReintentar/.test(html);
    out.yaNoDiceCargando = !/Cargando tandas/.test(html);

    // con datos ya pintados, un error posterior NO tapa la lista
    cont.innerHTML = '<table class="fac-t"><tr><td>LK 0001</td></tr></table>';
    await facTick();
    out.noTapaLoPintado = /LK 0001/.test(cont.innerHTML || "");

    // el botón vuelve a pedir: limpia el cache de la PPP y llama a facTick
    let tickeo = false;
    _pppCache = { algo: 1 }; _pppCacheTs = Date.now();
    const realTick = facTick;
    window.facTick = function () { tickeo = true; };
    facReintentar();
    out.reintentarLlama   = tickeo;
    out.reintentarLimpiaCache = _pppCache === null;
    out.reintentarMuestraCarga = /Cargando tandas/.test(cont.innerHTML || "");
    window.facTick = realTick;
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("fac-cuelgue:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
