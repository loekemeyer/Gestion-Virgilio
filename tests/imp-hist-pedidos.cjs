/* v23.91 (Luis, 29/09) — «📜 Historial recepción» pasó a ser «📜 Historial» y muestra las dos
   mitades del circuito: lo que se PIDIÓ (gv_imp_pedidos_historial: un renglón por pedido y
   proveedor, con lo pedido, lo llegado y el estado) y lo que se RECIBIÓ (📥 RECIBIR).
   Se corre la pantalla de verdad. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };

const PEDS = [
  { pedido_ref: "PI HT26-06-600-R1", proveedor: "Fujian", creado: "2026-09-16T12:00:00Z", creado_por: "luis@x.com",
    embarque: "2026-10-01", reingreso: "2026-11-01", estado: "en curso", items: 11, unidades: 106488,
    llegadas: 0, anulados: 0, codigos: "026 · 438E", usd: 32388 },
  { pedido_ref: "(sin PI · 10/09/26)", proveedor: "Kangli", creado: "2026-09-10T10:00:00Z", creado_por: "",
    embarque: null, reingreso: null, estado: "llegado", items: 8, unidades: 21048,
    llegadas: 21048, anulados: 2, codigos: "328E · 361E", usd: 21993 }
];
const RECS = [
  { id: 1, ts: "2026-09-20T14:00:00Z", cod_art: "438E", descripcion: "Colador 20cm", empresa: "CH",
    proveedor: "Fujian", pedido_ref: "PI HT26", unidades: 1224, cajas: 17, faltante: 0, sobrante: 0,
    estado_bache: "llegado", por: "luis@x.com", nota: "", es_ultima: true, anulada_en: null,
    destinos: [{ destino: "a_guardar", cantidad: 17, unidad: "Cj", sector: "" }] }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", async (r) => {
    const u = r.request().url();
    let body = "[]";
    if (/gv_imp_pedidos_historial/.test(u)) body = JSON.stringify(PEDS);
    else if (/gv_imp_recepcion_historial/.test(u)) body = JSON.stringify(RECS);
    await r.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.evaluate(() => { window.facAuthWriteHeaders = async () => ({ apikey: "k", Authorization: "Bearer t" }); });

  await p.evaluate(() => openImpHistRecep());
  await p.waitForFunction(() => /Recepciones/.test(document.getElementById("stkPopBody").innerHTML));

  const solapa = await p.evaluate(() => {
    const t = [...document.querySelectorAll("#stkPopBody button")].map(x => x.textContent.trim());
    return { hist: t.some(x => /^📜 Historial$/.test(x)), viejo: t.some(x => /Historial recepción/.test(x)),
             // ⚠ «📦 Pedidos» es la solapa del módulo: las sub-vistas son 🚢 y 📥
             subs: t.filter(x => /^(🚢 Pedidos|📥 Recepciones)/.test(x)) };
  });
  if (!solapa.hist) fail("la solapa no se llama «📜 Historial»: " + JSON.stringify(solapa.subs));
  if (solapa.viejo) fail("quedó la solapa vieja «Historial recepción»");
  if (solapa.subs.length !== 2) fail("faltan las dos vistas (Pedidos / Recepciones): " + solapa.subs.join(" | "));

  // arranca en RECEPCIONES (era lo que la solapa mostraba antes)
  const rec = await p.evaluate(() => document.getElementById("stkPopBody").innerHTML);
  if (!/1\.224 u|1224 u/.test(rec)) fail("la vista de recepciones no trae la recepción");

  // y la de PEDIDOS trae lo pedido, lo llegado y el estado
  await p.evaluate(() => impHistVista("ped"));
  const ped = await p.evaluate(() => document.getElementById("stkPopBody").innerHTML);
  if (!/PI HT26-06-600-R1/.test(ped)) fail("la vista de pedidos no trae el PI");
  if (!/106\.488/.test(ped)) fail("no muestra las unidades pedidas");
  if (!/en curso/.test(ped) || !/llegado/.test(ped)) fail("no muestra el estado de cada pedido");
  if (!/llegaron 21\.048/.test(ped)) fail("no muestra lo que ya llegó del pedido cerrado");
  if (!/32\.388/.test(ped)) fail("no muestra el u$s del pedido");
  if (!/2 línea\(s\) anulada\(s\)/.test(ped)) fail("no avisa las líneas anuladas");

  // la búsqueda vale para las dos vistas
  await p.evaluate(() => impHistBuscar("kangli"));
  const filtr = await p.evaluate(() => document.getElementById("stkPopBody").innerHTML);
  if (/PI HT26-06-600-R1/.test(filtr)) fail("la búsqueda no filtró los pedidos");
  if (!/Kangli/.test(filtr)) fail("la búsqueda se llevó puesto el que sí coincide");

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("imp-hist-pedidos: OK — «📜 Historial» con Pedidos y Recepciones, y la búsqueda vale para las dos");
})();
