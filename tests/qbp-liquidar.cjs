/* v24.52 (Thomas) — ¿Qué bajar primero?: un artículo en Articulos_Discontinuados con motivo
   «no se vende» / «liquidar» (396) NO se manda a guardar: sale de la lista, del SOS y de las horas.
   Uno que sólo «no se repone más» (634) SÍ sigue. Corre la pantalla. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 700, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => {
    if (/Articulos_Discontinuados/.test(r.request().url())) return r.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify([{ cod: "396", motivo: "discontinuo — no se vende" }, { cod: "634", motivo: "No se repone mas (dueno 12/09/2026)" }]) });
    return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const sal = { "396": { cod: "396", a_guardar: 4, excedente: 0, racks: 0, terminado: 0 },
                  "634": { cod: "634", a_guardar: 12, excedente: 0, racks: 0, terminado: 0 },
                  "505": { cod: "505", a_guardar: 50, excedente: 0, racks: 0, terminado: 10 } };
    window.stockFetchSaldos = async () => sal;
    window.ocgFetchCapacidad = async () => ({ "396": 20, "634": 30, "505": 100 });
    window.rkbFetchCxM = async () => ({ cxm: {} });
    window.stockFetchArtFactors = async () => ({});
    window.loadArtNombres = async () => ({});
    await showGuardarOrden("");
    const txt = (document.getElementById("gordenModal") || {}).textContent || "";
    let badge = null; window.supSetBadge = (id, n) => { if (id === "qbpBadge") badge = n; };
    await qbpLoadBadge();
    return { txt, badge, urg: (_gorden.urgentes || []).map((x) => x.cod), items: (_gorden.items || []).map((x) => x.cod) };
  });
  if (r.items.includes("396")) fail("396 (no se vende) no tiene que estar en la lista: " + r.items);
  if (r.urg.includes("396")) fail("396 no tiene que contar como SOS: " + r.urg);
  if (!r.items.includes("634")) fail("634 (no se repone más) SÍ se sigue guardando: " + r.items);
  if (!r.items.includes("505")) fail("505 común tiene que estar: " + r.items);
  if (r.badge !== 2) fail("badge SOS: 634 y 505 → 2, dio " + r.badge);
  if (errs.length) fail("errores JS: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("✓ qbp-liquidar: lo que no se vende no se manda a guardar");
})();
