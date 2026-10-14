/* v30.42 (Luis, 14/10/2026) — un RACK no tiene empresa: la empresa viaja con el CÓDIGO.
   "La identidad del código es única para casi todos. Las únicas excepciones son el 437E, 438E, 439E y 809E.
    Para esos 4, cuando son producto y no insumo, se puede preguntar de qué empresa son cuando se los va a
    poner en un rack" · "un rack vacío puede ser ocupado por cualquier cosa, que se vea así en el mapa".

   Mide en el Mapa (📦 Racks) y en Ingreso a racks:
   (a) un rack VACÍO abre el formulario de producto Y el de insumos, sin selector de empresa;
   (b) un rack con insumos abre sólo el editor de insumos;
   (c) un rack con un DUAL muestra LK/CH con la empresa de lo que tiene adentro;
   (d) escribir un dual en un rack vacío muestra LK/CH sin nada elegido y no deja guardar sin elegir;
   (e) un código NO dual guarda sin empresa (p_emp null: la pone la base desde el código);
   (f) Ingreso a racks: el LK/CH sale sólo para los duales y no viene elegido. Sin red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const RACKS = [
  { sector: "AA01", rack: "AA", orden: 1, empresa: null, uso: null, cod: null, descripcion: null, master_cajas: null, innercajas: null, estado: "libre", pos_rack: "AA01", partes: 1 },
  { sector: "AC04", rack: "AC", orden: 2, empresa: "LK", uso: null, cod: "437E", descripcion: "Colador 16 cm", master_cajas: 2, innercajas: 24, estado: "ocupado", fuente: "stock", pos_rack: "AC04", partes: 1 },
  { sector: "X26",  rack: "X",  orden: 3, empresa: "CH", uso: null, cod: "725E", descripcion: "Espátula", master_cajas: 16, innercajas: 192, estado: "ocupado", fuente: "stock", pos_rack: "X26", partes: 1 },
  { sector: "Y04",  rack: "Y",  orden: 4, empresa: "IN", uso: null, cod: "1000900", descripcion: "Espiral Chino", master_cajas: 0, innercajas: 0, estado: "ocupado", fuente: "insumo", pos_rack: "Y04", partes: 1 }
];
const J = (b) => ({ status: 200, contentType: "application/json", body: JSON.stringify(b) });

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.fulfill(J([])));
  await p.route("**/rest/v1/gv_rack_celda*", (r) => r.fulfill(J(RACKS)));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const o = await p.evaluate(async () => {
    const o = {};
    const vis = (id) => { const e = document.getElementById(id); return !!e && e.style.display !== "none"; };
    window.__isSupervisor = true;
    await openPlanimMapa();
    pmapModo("rack");
    await new Promise((r) => setTimeout(r, 300));
    window.__rpc = [];
    window.pmapRpc = async function (fn, body) { window.__rpc.push({ fn: fn, body: body }); return { ok: true, data: { ok: true, stock: [] } }; };

    // (a) vacío: producto + insumos, sin selector
    prkAbrir("AA01");
    o.vacioForm = !!document.getElementById("prkCod");
    o.vacioIns = !!document.querySelector("#pmapCeldaBody .prk-ins");
    o.vacioSinEmp = !vis("prkEmpLbl");
    o.vacioTit = document.getElementById("pmapCeldaTit").textContent;

    // (b) insumos: sólo el editor de insumos
    prkAbrir("Y04");
    o.insSinForm = !document.getElementById("prkCod") && !!document.querySelector("#pmapCeldaBody .prk-ins");

    // (c) dual cargado: LK/CH visible con la empresa del contenido
    prkAbrir("AC04");
    o.dualVis = vis("prkEmpLbl");
    o.dualVal = document.getElementById("prkEmp").value;

    // (d) dual escrito en un rack vacío: sin elegir no guarda
    prkAbrir("AA01");
    const cod = document.getElementById("prkCod");
    cod.value = "438E"; cod.dispatchEvent(new Event("input"));
    o.dualNuevoVis = vis("prkEmpLbl");
    o.dualNuevoVal = document.getElementById("prkEmp").value;
    document.getElementById("prkInner").value = "12";
    document.getElementById("prkMotivo").value = "prueba";
    await prkGuardar("AA01", false);
    o.dualSinElegirRpc = window.__rpc.length;
    o.dualMsg = document.getElementById("pmapCeldaStatus").textContent;
    document.getElementById("prkEmp").value = "CH";
    await prkGuardar("AA01", false);
    o.dualCH = window.__rpc.length === 1 ? window.__rpc[0].body.p_emp : "sin rpc";

    // (e) no dual: sin selector y p_emp null
    window.__rpc = [];
    prkAbrir("AA01");
    const c2 = document.getElementById("prkCod");
    c2.value = "513"; c2.dispatchEvent(new Event("input"));
    o.noDualOculto = !vis("prkEmpLbl");
    document.getElementById("prkInner").value = "12";
    document.getElementById("prkMotivo").value = "prueba";
    await prkGuardar("AA01", false);
    o.noDualEmp = window.__rpc.length === 1 ? window.__rpc[0].body.p_emp : "sin rpc";
    pmapCerrarCelda();

    // (f) Ingreso a racks: LK/CH sólo para duales, sin elegir
    o.esDual = [prkEsDual("437E"), prkEsDual("809E CH"), prkEsDual("725E"), prkEsDual("513")];
    o.irIniVacio = /emp: ""/.test(String(showIngresoRacksModal));
    return o;
  });
  await b.close();

  const f = [];
  const ok = (c, m) => { if (!c) f.push(m); };
  ok(!errs.length, "errores de página: " + errs.join(" | "));
  ok(o.vacioForm && o.vacioIns, "(a) un rack vacío no ofrece producto e insumos: " + JSON.stringify(o));
  ok(o.vacioSinEmp, "(a) un rack vacío muestra empresa");
  ok(!/LK|CH|IN/.test(o.vacioTit), "(a) el título del rack vacío dice una empresa: " + o.vacioTit);
  ok(o.insSinForm, "(b) un rack con insumos no abre sólo el editor de insumos");
  ok(o.dualVis && o.dualVal === "LK", "(c) el dual cargado no muestra su empresa: " + o.dualVis + "/" + o.dualVal);
  ok(o.dualNuevoVis && o.dualNuevoVal === "", "(d) un dual nuevo no pide empresa o viene elegida: " + o.dualNuevoVis + "/" + o.dualNuevoVal);
  ok(o.dualSinElegirRpc === 0 && /dual/i.test(o.dualMsg), "(d) guardó un dual sin empresa: " + o.dualMsg);
  ok(o.dualCH === "CH", "(d) el dual elegido no viaja: " + o.dualCH);
  ok(o.noDualOculto, "(e) un código no dual muestra el selector de empresa");
  ok(o.noDualEmp === null, "(e) un código no dual manda empresa: " + JSON.stringify(o.noDualEmp));
  ok(JSON.stringify(o.esDual) === "[true,true,false,false]", "(f) prkEsDual: " + JSON.stringify(o.esDual));
  ok(o.irIniVacio, "(f) Ingreso a racks arranca con una empresa elegida");
  if (f.length) { console.error("✗ rack-sin-empresa:\n  - " + f.join("\n  - ")); process.exit(1); }
  console.log("✓ rack-sin-empresa: rack vacío = cualquier cosa, empresa del código, LK/CH sólo para los 4 duales");
})().catch((e) => { console.error(e); process.exit(1); });
