/* v22.82 — el MAPA es el punto principal (Luis, 25/09: "que todas las definiciones de qué cosa hay en cada
   rack/góndola se puedan editar desde mapas; cambiarlo ahí informa a todos los demás" · "debería salir una
   alerta en el módulo de mapa" cuando hay stock y ningún lugar lo tiene).
   (a) la alerta gv_mapa_stock_sin_lugar se ve en Góndolas y en Racks, con góndola / racks / insumos;
   (b) una posición con varios insumos es UNA celda que los nombra;
   (c) el editor de un rack de insumos lista los insumos y escribe por gv_insumo_posicion_guardar;
   (d) un insumo sin lugar se ubica desde la alerta (con p_reemplaza_id si estaba en un lugar que no existe);
   (e) en el módulo de Insumos la ubicación ya no se tipea: botón «Editar en el Mapa» y Guardar no la toca. */
const path = require("path"), fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

const GOND = [{ sector: "A01", gondola: "A", celda: 1, empresa: "LK", cod: "502", descripcion: "502L", cajas_max: 105, max_fuente: "capacidad", estado: "ok" }];
const RACKS = [
  { sector: "AA04", rack: "AA", orden: 661, empresa: "LK", cod: "366E", descripcion: "Rallador", master_cajas: 15, innercajas: 75, estado: "ocupado" },
  { sector: "R11AD", rack: "R", orden: 900, empresa: "IN", cod: "N°63", descripcion: "96 X 2,00", master_cajas: null, innercajas: 4, estado: "ocupado", fuente: "insumo" },
  { sector: "R11AD", rack: "R", orden: 900, empresa: "IN", cod: "N°81", descripcion: "66 X 0,70", master_cajas: null, innercajas: 2, estado: "ocupado", fuente: "insumo" },
  { sector: "R11AD", rack: "R", orden: 900, empresa: "IN", cod: "63", descripcion: null, master_cajas: null, innercajas: 0, estado: "ocupado", fuente: "insumo" }
];
const ALERTA = [
  { tipo: "gondola", cod: "55219", emp: "LK", cantidad: 835, unidad: "caj", detalle: "Hay 835 cajas en góndola…", ref_id: null },
  { tipo: "rack", cod: "505I", emp: "LK", cantidad: 1139, unidad: "caj", detalle: "…", ref_id: null },
  { tipo: "insumo", cod: "546P", emp: "IN", cantidad: 12, unidad: "Kg", detalle: "…", ref_id: null },
  { tipo: "insumo_sin_lugar", cod: "N°18", emp: "IN", cantidad: 0, unidad: null, detalle: "Anotado en «Y29»…", ref_id: 83 }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const J = (x) => (r) => r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(x) });
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.route("**/rest/v1/gv_planimetria_celda*", J(GOND));
  await p.route("**/rest/v1/GV_Rack_Revisar*", J([]));
  await p.route("**/rest/v1/gv_rack_sin_ubicar*", J([]));
  await p.route("**/rest/v1/gv_rack_celda*", J(RACKS));
  await p.route("**/rest/v1/gv_mapa_stock_sin_lugar*", J(ALERTA));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async () => {
    const o = {}, espera = (ms) => new Promise((r) => setTimeout(r, ms));
    window.__isSupervisor = true;
    await openPlanimMapa(); await espera(300);
    const al = document.getElementById("pmapAlerta");
    o.alertaG = !al.hidden && al.textContent;
    pmapModo("rack"); await espera(300);
    o.alertaR = !document.getElementById("pmapAlerta").hidden;
    prkGo("R");
    o.celdasR = [...document.querySelectorAll("#pmapGrid .pmap-cell")].map((c) => c.textContent);
    window.__rpc = [];
    window.pmapRpc = async (fn, body) => { window.__rpc.push({ fn, body }); return { ok: true, data: { ok: true, sector: body.p_sector } }; };
    prkAbrir("R11AD");
    const body = document.getElementById("pmapCeldaBody");
    o.sinFormArt = !document.getElementById("prkCod");
    o.editorTxt = body.textContent;
    document.getElementById("prkInsQ_0").value = "9";
    await prkInsGuardar("R11AD", "N°63", 0);
    window.confirm = () => true;
    await prkInsQuitar("R11AD", "63");
    prkAbrir("R11AD");
    document.getElementById("prkInsNuevo").value = "546P";
    document.getElementById("prkInsNuevoQ").value = "12";
    await prkInsAgregar("R11AD");
    prkInsUbicarAbrir("N°18", 0, 83);
    document.getElementById("prkInsUbSec").value = "R14AT";
    await prkInsUbicarGuardar("N°18", 83);
    prkAbrir("AA04");
    o.artForm = (document.getElementById("prkCod") || {}).value;
    o.rpc = window.__rpc;
    return o;
  });
  await b.close();

  const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  const guardar = src.slice(src.indexOf("async function stkInsGuardar("), src.indexOf("async function stkInsGuardar(") + 3000);
  const f = [], ok = (c, m) => { if (!c) f.push(m); };
  ok(!errs.length, "errores de página: " + errs.join(" | "));
  ok(out.alertaG && /1 en góndola/.test(out.alertaG) && /1 en racks/.test(out.alertaG) && /1 insumos/.test(out.alertaG), "(a) la alerta no se ve en Góndolas: " + out.alertaG);
  ok(out.alertaR, "(a) la alerta no se ve en Racks");
  ok(out.celdasR.length === 1 && /N°63/.test(out.celdasR[0]) && /\+2 insumos/.test(out.celdasR[0]) && /N°81/.test(out.celdasR[0]),
     "(b) la posición con 3 insumos no es una celda: " + JSON.stringify(out.celdasR));
  ok(out.sinFormArt && /Insumos en esta posición/.test(out.editorTxt) && /N°81/.test(out.editorTxt) && /no está en Insumos/.test(out.editorTxt),
     "(c) el editor del rack de insumos está mal: " + out.editorTxt);
  const r = out.rpc;
  ok(r.length === 4 && r.every((x) => x.fn === "gv_insumo_posicion_guardar"), "(c) no escribió por la RPC: " + JSON.stringify(r));
  ok(r[0] && r[0].body.p_cod === "N°63" && r[0].body.p_cantidad === 9, "(c) guardar cantidad: " + JSON.stringify(r[0]));
  ok(r[1] && r[1].body.p_quitar === true && r[1].body.p_cod === "63", "(c) quitar: " + JSON.stringify(r[1]));
  ok(r[2] && r[2].body.p_cod === "546P" && r[2].body.p_cantidad === 12, "(c) agregar: " + JSON.stringify(r[2]));
  ok(r[3] && r[3].body.p_sector === "R14AT" && r[3].body.p_reemplaza_id === 83, "(d) ubicar el sin lugar: " + JSON.stringify(r[3]));
  ok(out.artForm === "366E", "(c) una posición de artículo sigue abriendo su formulario: " + out.artForm);
  ok(!/_stkInsUbicSync\(/.test(guardar), "(e) stkInsGuardar sigue escribiendo la ubicación");
  ok(!/_stkInsUbicEdit\(it\.cod/.test(src) && /_stkInsUbicMapa\(it\)/.test(src) && /Editar en el Mapa/.test(src), "(e) la ubicación de Insumos sigue editable a mano");
  if (f.length) { console.error("✗ pmap-punto-unico:\n  - " + f.join("\n  - ")); process.exit(1); }
  console.log("✓ pmap-punto-unico: alerta de stock sin lugar, posición agrupada, insumos editados desde el Mapa");
})().catch((e) => { console.error(e); process.exit(1); });
