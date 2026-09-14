/* v17.23 — 🗺️ Mapa de góndolas (pedido de Thomas: "un módulo en la APP que muestre
   la planimetría · Góndola A / a5 502 Cap / a4 502 Cap …").

   Lo que se verifica, que es lo que el dibujo tiene que respetar sí o sí:
   (a) la celda de ARRIBA de cada columna es la de número más alto (a5 … a1) y las
       columnas cortan de a 5, que es como está armado el módulo de góndola;
   (b) cada celda muestra el código y su capacidad en cajas;
   (c) una celda sin nadie dice "libre" y una sin capacidad cargada avisa (s/cap);
   (d) buscar un código NO filtra: resalta, y salta a la góndola que lo tiene;
   (e) el módulo pega contra la vista gv_planimetria_celda (no contra las tablas). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const FILAS = [
  // Góndola A: 6 celdas (dos columnas: 1-5 y 6-10, con la 6 sola)
  { sector: "A01", gondola: "A", celda: 1, empresa: "LK", cod: "502", descripcion: "502L",       cajas_max: 105, max_fuente: "capacidad", estado: "ok" },
  { sector: "A02", gondola: "A", celda: 2, empresa: "LK", cod: "502", descripcion: "502L",       cajas_max: 105, max_fuente: "capacidad", estado: "ok" },
  { sector: "A03", gondola: "A", celda: 3, empresa: "LK", cod: "502", descripcion: "502L",       cajas_max: 84,  max_fuente: "capacidad", estado: "ok" },
  { sector: "A04", gondola: "A", celda: 4, empresa: "LK", cod: null,  descripcion: null,          cajas_max: null, max_fuente: null,       estado: "libre" },
  { sector: "A05", gondola: "A", celda: 5, empresa: "LK", cod: "321", descripcion: "Rallador Cilíndrico 21cm", cajas_max: 50, max_fuente: "capacidad", estado: "ok" },
  { sector: "A06", gondola: "A", celda: 6, empresa: "LK", cod: "504", descripcion: "Afila Cuchillos", cajas_max: null, max_fuente: null,   estado: "solo_mapa" },
  // Góndola F: acá vive el 438E que se busca
  { sector: "F13", gondola: "F", celda: 13, empresa: "LK", cod: "438E", descripcion: "Colador 20cm", cajas_max: 40, max_fuente: "item", estado: "ok" },
  { sector: "F12", gondola: "F", celda: 12, empresa: "LK", cod: "437E", descripcion: "Colador 16cm", cajas_max: 36, max_fuente: "item", estado: "ok" }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  // ⚠ el orden importa: Playwright evalúa las rutas de la ÚLTIMA a la primera, así
  // que el corte general va PRIMERO y la de la vista después, si no nunca se llama.
  let pedido = null;
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.route("**/rest/v1/gv_planimetria_celda*", (r) => {
    pedido = r.request().url();
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(FILAS) });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async () => {
    const o = {};
    window.__isSupervisor = true;
    await openPlanimMapa();
    o.visible = document.getElementById("planimMapaOverlay").classList.contains("show");
    o.tabs = [...document.querySelectorAll("#pmapTabs .lug-tab")].map((e) => e.textContent.trim());
    o.tabOn = (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent;
    const cols = [...document.querySelectorAll("#pmapGrid .pmap-col")];
    o.nCols = cols.length;
    o.col1 = [...cols[0].querySelectorAll(".pmap-cell")].map((c) => ({
      sec: (c.querySelector(".pmap-sec") || {}).textContent || "",
      cod: (c.querySelector(".pmap-cod") || {}).textContent || "",
      cap: (c.querySelector(".pmap-cap") || {}).textContent || "",
      cls: c.className,
      oculta: c.style.visibility === "hidden"
    }));
    o.col2sec = [...cols[1].querySelectorAll(".pmap-cell")].filter((c) => c.style.visibility !== "hidden")
      .map((c) => (c.querySelector(".pmap-sec") || {}).textContent);
    o.head = document.querySelector("#pmapGrid .pmap-head").textContent;

    // buscar salta de góndola y resalta, sin filtrar
    pmapBuscar("438E");
    o.trasBuscar = {
      gondola: (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent,
      celdas: document.querySelectorAll("#pmapGrid .pmap-cell:not([style*='hidden'])").length,
      hits: [...document.querySelectorAll("#pmapGrid .pmap-hit .pmap-sec")].map((e) => e.textContent),
      status: document.getElementById("pmapStatus").textContent
    };
    pmapBuscar("");
    o.trasLimpiar = (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent;
    return o;
  });

  const fail = [];
  const eq = (a, b2, q) => { if (String(a) !== String(b2)) fail.push(q + ": " + JSON.stringify(a) + " != " + JSON.stringify(b2)); };

  if (!/gv_planimetria_celda/.test(pedido || "")) fail.push("no pegó contra la vista gv_planimetria_celda");
  if (!out.visible) fail.push("el overlay no se abrió");
  eq(out.tabs.join(","), "A,F", "solapas de góndola");
  eq(out.tabOn, "A", "arranca en la primera góndola");
  eq(out.nCols, 2, "dos columnas (6 celdas de a 5)");

  // (a) la de arriba es la 5 y la de abajo la 1
  eq(out.col1.map((c) => c.sec).join(","), "A05,A04,A03,A02,A01", "orden de la columna (arriba la 5)");
  eq(out.col2sec.join(","), "A06", "segunda columna arranca en la 6");

  // (b) código + capacidad
  const a05 = out.col1[0], a01 = out.col1[4];
  eq(a05.cod, "321", "código de A05");
  if (!/50\s*caj/.test(a05.cap)) fail.push("A05 no muestra las cajas: " + a05.cap);
  eq(a01.cod, "502", "código de A01");
  if (!/105\s*caj/.test(a01.cap)) fail.push("A01 no muestra las cajas: " + a01.cap);

  // (c) libre y sin capacidad
  const a04 = out.col1[1];
  eq(a04.cod, "libre", "A04 está libre");
  if (!/pmap-libre/.test(a04.cls)) fail.push("A04 no está pintada como libre: " + a04.cls);
  if (!/A06/.test(JSON.stringify(out.col2sec))) fail.push("falta A06 (la celda sin capacidad cargada)");

  // (d) buscar resalta, no filtra
  eq(out.trasBuscar.gondola, "F 1", "buscar 438E salta a la góndola F (con el contador)");
  eq(out.trasBuscar.hits.join(","), "F13", "resalta sólo la celda del 438E");
  if (out.trasBuscar.celdas < 2) fail.push("buscar filtró las celdas en vez de resaltarlas");
  if (!/438E/.test(out.trasBuscar.status)) fail.push("el pie no dice cuántas celdas tienen el código");
  eq(out.trasLimpiar, "F", "al limpiar la búsqueda no se pierde la góndola abierta");

  if (errs.length) fail.push("errores de página: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.error("FALLÓ:\n- " + fail.join("\n- ")); process.exit(1); }
  console.log("pmap-gondolas OK — 2 columnas, A05→A01, códigos con capacidad, libre y s/cap, y buscar resalta sin filtrar.");
})();
