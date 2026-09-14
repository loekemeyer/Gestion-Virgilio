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

    // ── v17.29: editar desde el mapa ───────────────────────────────────────────
    const rpc = [];
    window.facAuthWriteHeaders = async function () { return { apikey: "x", Authorization: "Bearer x" }; };
    window.fetch = async function (url, opt) {
      const u = String(url);
      rpc.push({ url: u, body: opt && opt.body ? JSON.parse(opt.body) : null });
      return { ok: true, status: 200, text: async () => '[{"cod":"066"}]' };
    };
    window.supaFetchAllSafe = async function () { return []; };   // el refresco no pisa el fixture
    window.confirm = function () { return true; };

    pmapAbrirCelda("A05");
    o.modalAbre = document.getElementById("pmapCeldaModal").classList.contains("show");
    o.modalTitulo = document.getElementById("pmapCeldaTit").textContent.trim();
    o.modalOrden = (document.getElementById("pmapOrd") || {}).value;
    o.modalCap321 = (document.getElementById("pmapCap_321") || {}).value;

    document.getElementById("pmapCap_321").value = "77";
    await pmapGuardarItem("321", "articulo");
    const g = rpc[rpc.length - 1];
    o.guardaRpc = g.url.indexOf("/rpc/gv_lugar_item_guardar") >= 0;
    o.guardaBody = JSON.stringify(g.body);

    await pmapSacarItem("321", "articulo");
    const d = rpc[rpc.length - 1];
    o.sacaRpc = d.url.indexOf("/rpc/gv_lugar_item_sacar") >= 0 && d.body.p_sector === "A05" && d.body.p_cod === "321";

    document.getElementById("pmapOrd").value = "9";
    await pmapGuardarOrden();
    const or = rpc[rpc.length - 1];
    o.ordenRpc = or.url.indexOf("/rpc/gv_lugar_orden") >= 0 && or.body.p_sector === "A05" && or.body.p_orden === 9;

    // alta en una celda LIBRE
    pmapAbrirCelda("A04");
    o.libreDiceLibre = /libre/i.test(document.getElementById("pmapCeldaBody").textContent);
    document.getElementById("pmapNuevoCod").value = "66";
    document.getElementById("pmapNuevoCap").value = "12";
    await pmapAltaItem();
    const al = rpc[rpc.length - 1];
    o.altaRpc = al.url.indexOf("/rpc/gv_lugar_item_guardar") >= 0 &&
                al.body.p_sector === "A04" && al.body.p_cod === "66" && al.body.p_cajas_max === 12;

    // sin sesión de Google no escribe y lo dice
    window.facAuthWriteHeaders = async function () { return null; };
    const antes = rpc.length;
    document.getElementById("pmapNuevoCod").value = "505";   // el alta anterior lo limpió
    await pmapAltaItem();
    o.sinSesionNoEscribe = rpc.length === antes &&
      /sesi[óo]n/i.test(document.getElementById("pmapCeldaStatus").textContent);
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

  // (f) editar desde el mapa
  if (!out.modalAbre) fail.push("tocar la celda no abre su editor");
  if (!/A05/.test(out.modalTitulo)) fail.push("el editor no dice qué celda es: " + out.modalTitulo);
  eq(out.modalCap321, "50", "el editor trae la capacidad actual");
  if (!out.guardaRpc) fail.push("guardar no pega contra la RPC gv_lugar_item_guardar");
  const gb = JSON.parse(out.guardaBody || "{}");
  eq(gb.p_sector, "A05", "guardar manda el lugar");
  eq(gb.p_cod, "321", "guardar manda el código");
  eq(gb.p_cajas_max, 77, "guardar manda la capacidad nueva");
  if (!out.sacaRpc) fail.push("sacar no pega contra la RPC gv_lugar_item_sacar");
  if (!out.ordenRpc) fail.push("el orden de recorrido no pega contra gv_lugar_orden");
  if (!out.libreDiceLibre) fail.push("una celda libre no lo dice en su editor");
  if (!out.altaRpc) fail.push("el alta en una celda libre no manda lo tipeado");
  if (!out.sinSesionNoEscribe) fail.push("sin sesión de Google escribe igual (o no avisa)");

  if (errs.length) fail.push("errores de página: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.error("FALLÓ:\n- " + fail.join("\n- ")); process.exit(1); }
  console.log("pmap-gondolas OK — dibujo (2 columnas, A05→A01, capacidad, libre, s/cap, buscar) y edición por RPC (guardar, sacar, orden, alta, sin sesión).");
})();
