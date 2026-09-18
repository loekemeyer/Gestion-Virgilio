/* Regresión v19.82 — CARGA CAMIÓN: los pedidos que RETIRA el cliente no van al reparto.

   Thomas (18/09/2026): *"Están apareciendo los pedidos que están marcados como que los retiran
   los clientes en el módulo «cargar camión»"*.

   Causa: `_ccAttachUbicYOrden` leía la zona SOLO de `gv_ppp_programacion_diaria` (la programación
   de ISIS), que no tiene las NP web ("LK 0076", "CH 0011" — ésas viven en `PPP_Web_Programacion`).
   Sin zona, `esRetira` quedaba en false y el pedido caía en el camión. Se cambió por
   `gv_np_prog_reparto`, que une las dos y resuelve el Retira en el BACKEND (`es_retira`).

   Chequea, sin red:
   1) la consulta va contra `gv_np_prog_reparto` y manda la NP ENTRE COMILLAS (la web lleva espacio),
   2) una NP web con zona Retira sale `esRetira = true` (→ pestaña Retira, no camión),
   3) una NP web de zona normal sigue en el camión,
   4) una NP de ISIS con zona normal sigue en el camión.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { urls: [] };
    const REP = [
      { np: "LK 0076", tanda: "E34A", razon_social: "Rodriguez Jonatan" },
      { np: "LK 0027", tanda: "E03C", razon_social: "Albalandia S.R.L. (M)" },
      { np: "98601",   tanda: "D70A", razon_social: "Cliente ISIS" }
    ];
    const PROG = [
      { np: "LK 0076", zona: "Retira",            direccion: "Virgilio 2788", barrio: "Retira",    m3: 0.024, es_retira: true },
      { np: "LK 0027", zona: "Zona 1 - CABA Sur", direccion: "Pergamino 3751", barrio: "Soldati",  m3: 0.709, es_retira: false },
      { np: "98601",   zona: "Zona 1 - CABA Sur", direccion: "Av. Saenz 100",  barrio: "Pompeya",  m3: 0.5,   es_retira: false }
    ];
    window.supaFetchAll     = async function (ep) { return /Facturacion_NP/.test(String(ep)) ? REP.slice() : []; };
    window.supaFetchAllSafe = async function () { return []; };
    window.facFetchCajas      = async function () { return new Map(); };
    window.fetchSinSalidaMap  = async function () { return new Map(); };
    window._rtCacheAll        = async function () { return {}; };
    window.fetch = async function (url) {
      const u = String(url); out.urls.push(u);
      const body = /gv_np_prog_reparto/.test(u) ? PROG : [];
      return { ok: true, json: async function () { return body; } };
    };

    const items = await fetchCCData();
    const by = {}; items.forEach(function (it) { by[it.np] = it; });
    out.pidioVista  = out.urls.some(u => /gv_np_prog_reparto/.test(u));
    out.npEntreComillas = out.urls.some(u => /gv_np_prog_reparto/.test(u) && u.indexOf("%22LK%200076%22") >= 0);
    out.retiraWeb   = by["LK 0076"] ? by["LK 0076"].esRetira === true  : null;
    out.camionWeb   = by["LK 0027"] ? by["LK 0027"].esRetira === false : null;
    out.camionIsis  = by["98601"]   ? by["98601"].esRetira   === false : null;
    out.zonaWeb     = by["LK 0076"] ? by["LK 0076"].zona : null;
    return out;
  });

  await b.close();
  const ok = r.pidioVista && r.npEntreComillas && r.retiraWeb && r.camionWeb && r.camionIsis && !errs.length;
  const vis = { pidioVista: r.pidioVista, npEntreComillas: r.npEntreComillas, retiraWeb: r.retiraWeb,
                camionWeb: r.camionWeb, camionIsis: r.camionIsis, zonaWeb: r.zonaWeb };
  console.log("cc-retira-web:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join(" | ") : "none", ok ? "· ✓ OK" : "· ✗ FALLA");
  process.exit(ok ? 0 : 1);
})();
