/* v29.98 — 📐 SC y SP: la TERCERA clase de lugar del depósito (Luis, 2026-10-13:
   "en el deposito tenes diferentes cosas: Gondolas / Racks / Sector SC y SP … hagamos que sea
   su propio sector, lugar. IN-A1 por ejemplo? … agrega al mapa este sector").

   Lo que se verifica:
   (a) el Mapa tiene los TRES modos y sigue arrancando en Góndolas;
   (b) SC y SP lee gv_scp_celda (no las tablas) y dibuja una solapa por COLUMNA, con la celda
       sin el prefijo IN- y la pieza con su stock. ⚠ NO se rotula SC ni SP (Luis, 13/10: "no importa
       SP o SC, ese sector tiene de los dos … todo ese sector es IN-<Letra><Numero>");
   (c) una celda con dos piezas las muestra juntas (+N) y una libre dice "libre";
   (d) buscar salta a la columna que tiene la pieza y la resalta;
   (e) tocar una celda abre su editor y Quitar va por gv_insumo_posicion_guardar
       (la MISMA RPC que las posiciones de racks de insumo);
   (f) las celdas de SC/SP NO abren solapa en el modo Racks (IN- no es un rack);
   (g) «Editar en el Mapa» de un insumo de SC/SP abre el modo SC y SP, no Racks. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const GOND = [
  { sector: "A01", gondola: "A", celda: 1, empresa: "LK", cod: "502", descripcion: "502L", cajas_max: 105, max_fuente: "capacidad", estado: "ok" }
];
/* La grilla real: IN-A1 tiene C15 (SP), IN-A2 dos piezas, IN-A4 libre, IN-G1 es Crudo. */
const SCP = [
  { sector: "IN-A1", col: "A", fila: 1, cod: "C15",   descripcion: "C Sacacorcho 520",   categoria: "parte_procesado", sec_gp2: "SP", cantidad: 0, stock: 1200, unidad: "Uni", estado: "ocupado" },
  { sector: "IN-A2", col: "A", fila: 2, cod: "B13",   descripcion: "Varilla C/ Cuchilla", categoria: "parte_procesado", sec_gp2: "SP", cantidad: 0, stock: 300,  unidad: "Uni", estado: "ocupado" },
  { sector: "IN-A2", col: "A", fila: 2, cod: "DISC.1", descripcion: null,                categoria: null,              sec_gp2: null, cantidad: 0, stock: null, unidad: null,  estado: "ocupado" },
  { sector: "IN-A4", col: "A", fila: 4, cod: null,    descripcion: null,                 categoria: null,              sec_gp2: null, cantidad: null, stock: null, unidad: null, estado: "libre" },
  { sector: "IN-G1", col: "G", fila: 1, cod: "Z33",   descripcion: "Cremallera p/Cromar", categoria: "partes_crudo",    sec_gp2: "SC", cantidad: 0, stock: 90,   unidad: "Uni", estado: "ocupado" }
];
/* En Racks NO tiene que aparecer ninguna solapa de la grilla: acá va una celda IN- a propósito. */
const RACKS = [
  { sector: "X05", rack: "X", orden: 810, empresa: "LK", uso: null, cod: "368E", descripcion: "Rallador", master_cajas: 14, innercajas: 56, estado: "ocupado", fuente: null, pos_rack: "X05", parte: null, partes: 1 },
  { sector: "IN-A1", rack: "IN", orden: null, empresa: "IN", uso: null, cod: "C15", descripcion: "C Sacacorcho 520", master_cajas: 0, innercajas: 0, estado: "sin_lugar", fuente: "insumo", pos_rack: "IN-A1", parte: null, partes: 1 }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let urlScp = null, rpc = null;
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.route("**/rest/v1/gv_planimetria_celda*", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(GOND) }));
  await p.route("**/rest/v1/gv_rack_celda*", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(RACKS) }));
  await p.route("**/rest/v1/GV_Rack_Revisar*", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.route("**/rest/v1/gv_rack_sin_ubicar*", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.route("**/rest/v1/gv_mapa_stock_sin_lugar*", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.route("**/rest/v1/gv_scp_celda*", (r) => {
    urlScp = r.request().url();
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(SCP) });
  });
  await p.route("**/rest/v1/rpc/gv_insumo_posicion_guardar*", (r) => {
    rpc = JSON.parse(r.request().postData() || "{}");
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ ok: true, sector: rpc.p_sector }) });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  p.on("dialog", (d) => d.accept());

  const out = await p.evaluate(async () => {
    const o = {};
    window.__isSupervisor = true;
    await openPlanimMapa();
    o.modos = [...document.querySelectorAll(".pmap-modos .pmap-modo")].map((e) => e.textContent.trim());
    o.arranca = (document.querySelector(".pmap-modo-on") || {}).id;

    pmapModo("scp");
    await new Promise((r) => setTimeout(r, 350));
    o.modoOn = (document.querySelector(".pmap-modo-on") || {}).id;
    o.cols = [...document.querySelectorAll("#pmapTabs .lug-tab")].map((e) => e.textContent.trim());
    o.colOn = (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent.trim();
    o.head = (document.querySelector("#pmapGrid .pmap-head") || {}).textContent || "";
    o.celdas = [...document.querySelectorAll("#pmapGrid .pmap-cell")].map((e) => ({
      sec: (e.querySelector(".pmap-sec") || {}).textContent || "",
      cod: (e.querySelector(".pmap-cod") || {}).textContent || "",
      txt: e.textContent, tip: e.getAttribute("title") || ""
    }));
    o.leg = (document.getElementById("pmapLeg") || {}).textContent || "";
    o.status = (document.getElementById("pmapStatus") || {}).textContent || "";

    // (d) buscar salta a la columna G
    pmapBuscar("Z33");
    await new Promise((r) => setTimeout(r, 120));
    o.trasBuscar = (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent.trim().split(/\s+/)[0];
    o.resaltadas = document.querySelectorAll("#pmapGrid .pmap-cell.pmap-hit").length;
    pmapBuscar("");
    await new Promise((r) => setTimeout(r, 120));

    // (e) tocar una celda y quitar una pieza
    window.__rpc = [];
    window.pmapRpc = async function (fn, body) { window.__rpc.push({ fn: fn, body: body }); return { ok: true, data: { sector: body.p_sector } }; };
    pscpAbrir("IN-A2");
    await new Promise((r) => setTimeout(r, 120));
    o.modal = document.getElementById("pmapCeldaModal").classList.contains("show");
    o.modalTit = (document.getElementById("pmapCeldaTit") || {}).textContent || "";
    o.modalBody = (document.getElementById("pmapCeldaBody") || {}).textContent || "";
    await pscpQuitar("IN-A2", "DISC.1");
    await new Promise((r) => setTimeout(r, 250));
    o.rpc = window.__rpc;

    // (f) en Racks no hay solapa de la grilla
    pmapModo("rack");
    await new Promise((r) => setTimeout(r, 350));
    o.racksTabs = [...document.querySelectorAll("#pmapTabs .lug-tab")].map((e) => e.textContent.trim());

    // (g) Editar en el Mapa de una pieza de SC/SP
    closePlanimMapa();
    await stkInsIrAlMapa("Z33");
    await new Promise((r) => setTimeout(r, 400));
    o.modoDesdeInsumo = (document.querySelector(".pmap-modo-on") || {}).id;
    return o;
  });
  await b.close();

  const ok = [];
  const chk = (c, t) => { ok.push([!!c, t]); };
  // v30.86: se sumó un cuarto modo, Tránsito, después de SC y SP
  chk(out.modos.length === 4 && /SC y SP/.test(out.modos[2]) && /Tránsito/.test(out.modos[3]), "(a) los CUATRO modos, con SC y SP tercero y Tránsito al final");
  chk(out.arranca === "pmapModoG", "(a) sigue arrancando en Góndolas");
  chk(out.modoOn === "pmapModoS", "(b) el modo SC y SP queda prendido");
  chk(/gv_scp_celda/.test(String(urlScp)), "(b) lee la vista gv_scp_celda");
  chk(out.cols.join(",") === "A,G", "(b) una solapa por columna: " + out.cols.join(","));
  chk(out.colOn === "A", "(b) arranca en la primera columna");
  chk(/Columna/.test(out.head) && /3 celdas/.test(out.head) && /1 libres/.test(out.head) &&
      !/Sector (Crudo|Procesado)/.test(out.head),
      "(b) el encabezado cuenta celdas y libres, SIN partir por SC/SP: " + out.head);
  const a1 = out.celdas.filter((c) => c.sec === "A1")[0];
  chk(a1 && a1.cod === "C15", "(b) la celda A1 muestra su pieza (sin el prefijo IN-)");
  chk(a1 && /1\.200|1200/.test(a1.txt) && !/\bSP\b/.test(a1.txt),
      "(b) la pieza lleva su stock y NINGÚN rótulo SC/SP (Luis: «no importa SP o SC»)");
  chk(a1 && /Sacacorcho/.test(a1.tip), "(b) el tooltip trae la descripción");
  const a2 = out.celdas.filter((c) => c.sec === "A2")[0];
  chk(a2 && /\+1/.test(a2.txt) && /DISC\.1/.test(a2.txt), "(c) una celda con dos piezas las muestra juntas");
  const a4 = out.celdas.filter((c) => c.sec === "A4")[0];
  chk(a4 && /libre/.test(a4.cod), "(c) la celda vacía dice libre");
  chk(/GP2|Cervantes/.test(out.leg) && !/Sector (Crudo|Procesado)/.test(out.leg),
      "(c) la leyenda dice que el stock lo lleva GP2 y no parte por SC/SP");
  chk(out.trasBuscar === "G", "(d) buscar salta a la columna de la pieza");
  chk(out.resaltadas >= 1, "(d) y la resalta");
  chk(out.modal && /IN-A2/.test(out.modalTit), "(e) tocar la celda abre su editor");
  chk(/Cervantes|piezas/i.test(out.modalBody), "(e) el editor aclara que no van cajas de artículo");
  const q = (out.rpc || [])[0];
  chk(q && q.fn === "gv_insumo_posicion_guardar" && q.body.p_sector === "IN-A2" &&
      q.body.p_cod === "DISC.1" && q.body.p_quitar === true,
      "(e) Quitar va por gv_insumo_posicion_guardar: " + JSON.stringify(q));
  chk(out.racksTabs.indexOf("IN") < 0, "(f) la grilla de SC/SP no abre solapa en Racks: " + out.racksTabs.join(","));
  chk(out.modoDesdeInsumo === "pmapModoS", "(g) «Editar en el Mapa» de una pieza de SC/SP abre SC y SP");
  chk(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));

  let malas = 0;
  ok.forEach(([c, t]) => { console.log((c ? "  ✓ " : "  ✗ ") + t); if (!c) malas++; });
  console.log(malas ? "\nFALLA: " + malas + " chequeos en rojo" : "\nOK — SC y SP es su propio lugar en el Mapa");
  process.exit(malas ? 1 : 0);
})();
