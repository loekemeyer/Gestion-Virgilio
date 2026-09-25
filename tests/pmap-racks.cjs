/* v22.67 — 📦 pestaña Racks del Mapa de góndolas (Luis, 2026-09-25: "deberíamos agregar
   también Racks… separá eso en dos pestañas, Góndola y Racks").

   Lo que se verifica:
   (a) el mapa tiene las dos pestañas y arranca en Góndolas, como siempre;
   (b) Racks lee la vista gv_rack_celda (no las tablas) y muestra un tab por rack,
       con cada posición: código, MC y cajas; la libre dice "libre";
   (c) una posición cargada que no existe como rack sale marcada (sin_lugar);
   (d) buscar en Racks salta al rack que tiene el código y lo resalta;
   (e) tocar una posición abre su editor con lo cargado y el desfase contra el stock de racks;
   (g) guardar exige motivo y va por la RPC gv_rack_posicion_guardar (posición + stock juntos);
   (f) volver a Góndolas dibuja la góndola de nuevo. */
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
const RACKS = [
  { sector: "AA01", rack: "AA", orden: 658, empresa: "CH", uso: null, cod: null, descripcion: null, master_cajas: null, innercajas: null, estado: "libre" },
  { sector: "AA04", rack: "AA", orden: 661, empresa: "LK", uso: null, cod: "366E", descripcion: "Rallador Cónico", master_cajas: 15, innercajas: 75, estado: "ocupado" },
  { sector: "X05",  rack: "X",  orden: 810, empresa: "LK", uso: null, cod: "368E", descripcion: "Rallador hexagonal", master_cajas: 14, innercajas: 56, estado: "ocupado" },
  { sector: "O2",   rack: "O",  orden: null, empresa: "LK", uso: null, cod: "513", descripcion: "Pelador", master_cajas: 0, innercajas: 260, estado: "sin_lugar" }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let pidioRack = null;
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.route("**/rest/v1/gv_planimetria_celda*", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(GOND) }));
  await p.route("**/rest/v1/gv_rack_stock_desfase*", (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([
      { cod: "368E", empresa: "LK", en_posiciones: 132, stock_racks: 36, diferencia: 96, posiciones: "AD06 56, X05 56, Y12 20" }]) }));
  await p.route("**/rest/v1/gv_rack_celda*", (r) => {
    pidioRack = r.request().url();
    r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(RACKS) });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async () => {
    const o = {};
    window.__isSupervisor = true;
    await openPlanimMapa();
    o.modos = [...document.querySelectorAll(".pmap-modos .pmap-modo")].map((e) => e.textContent.trim());
    o.arranca = (document.querySelector(".pmap-modo-on") || {}).id;
    o.gondTab = (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent;

    pmapModo("rack");
    await new Promise((r) => setTimeout(r, 300));
    o.modoOn = (document.querySelector(".pmap-modo-on") || {}).id;
    o.rackTabs = [...document.querySelectorAll("#pmapTabs .lug-tab")].map((e) => e.textContent.trim());
    o.cells = [...document.querySelectorAll("#pmapGrid .pmap-cell")].map((c) => ({
      sec: (c.querySelector(".pmap-sec") || {}).textContent || "",
      cod: (c.querySelector(".pmap-cod") || {}).textContent || "",
      mc: (c.querySelector(".prk-mc") || {}).textContent || "",
      cls: c.className
    }));
    o.viejaOculta = document.getElementById("pmapVieja").style.display === "none";

    prkGo("O");
    o.sinLugarCls = (document.querySelector("#pmapGrid .pmap-cell") || {}).className;

    pmapBuscar("368E");
    o.buscarTab = (document.querySelector("#pmapTabs .lug-tab-on") || {}).textContent;
    o.hit = [...document.querySelectorAll("#pmapGrid .pmap-hit .pmap-cod")].map((e) => e.textContent);

    prkAbrir("X05");
    o.detVisible = document.getElementById("pmapCeldaModal").classList.contains("show");
    o.detTxt = document.getElementById("pmapCeldaBody").textContent;
    o.formCod = (document.getElementById("prkCod") || {}).value;
    o.formInner = (document.getElementById("prkInner") || {}).value;
    o.desfaseTxt = o.detTxt;
    // (g) editar: sin motivo no llama a la base; con motivo manda la RPC con lo tipeado
    window.__rpc = [];
    window.pmapRpc = async function (fn, body) { window.__rpc.push({ fn: fn, body: body });
      return { ok: true, data: { ok: true, stock: [{ cod: "368E", emp: "LK", delta: 6 }] } }; };
    document.getElementById("prkInner").value = "62";
    await prkGuardar("X05", false);
    o.sinMotivo = window.__rpc.length;
    o.sinMotivoMsg = document.getElementById("pmapCeldaStatus").textContent;
    prkAbrir("X05");
    document.getElementById("prkInner").value = "62";
    document.getElementById("prkMotivo").value = "conteo";
    await prkGuardar("X05", false);
    o.rpc = window.__rpc.slice();
    o.okMsg = document.getElementById("pmapCeldaStatus").textContent;
    pmapCerrarCelda();

    pmapBuscar("");
    pmapModo("gondola");
    o.volvio = (document.querySelector("#pmapGrid .pmap-head") || {}).textContent || "";
    o.viejaVuelve = document.getElementById("pmapVieja").style.display !== "none";
    return o;
  });
  await b.close();

  const fallas = [];
  const ok = (c, m) => { if (!c) fallas.push(m); };
  ok(!errs.length, "errores de página: " + errs.join(" | "));
  ok(out.modos.length === 2 && /Góndolas/.test(out.modos[0]) && /Racks/.test(out.modos[1]), "(a) faltan las dos pestañas: " + JSON.stringify(out.modos));
  ok(out.arranca === "pmapModoG" && out.gondTab === "A", "(a) no arranca en Góndolas");
  ok(!!pidioRack, "(b) no le pegó a gv_rack_celda");
  ok(out.modoOn === "pmapModoR", "(b) la pestaña Racks no quedó marcada");
  ok(JSON.stringify(out.rackTabs) === JSON.stringify(["AA", "O", "X"]), "(b) tabs de racks: " + JSON.stringify(out.rackTabs));
  const aa04 = out.cells.find((c) => /AA04/.test(c.sec)), aa01 = out.cells.find((c) => /AA01/.test(c.sec));
  ok(aa04 && aa04.cod === "366E" && /15\s*MC/.test(aa04.mc) && /75 caj/.test(aa04.mc), "(b) AA04 mal: " + JSON.stringify(aa04));
  ok(aa01 && aa01.cod === "libre" && /pmap-libre/.test(aa01.cls), "(b) AA01 no dice libre: " + JSON.stringify(aa01));
  ok(out.cells.length === 2, "(b) el rack AA debería tener 2 posiciones: " + out.cells.length);
  ok(out.viejaOculta, "(b) el aviso de la planimetría vieja (góndolas) no se esconde en Racks");
  ok(/pmap-smapa/.test(out.sinLugarCls || ""), "(c) la posición sin lugar no sale marcada");
  ok(out.buscarTab === "X 1" || /^X/.test(out.buscarTab || ""), "(d) buscar no saltó al rack X: " + out.buscarTab);
  ok(JSON.stringify(out.hit) === '["368E"]', "(d) no resaltó el 368E: " + JSON.stringify(out.hit));
  ok(out.detVisible && /368E/.test(out.detTxt), "(e) el detalle no muestra la posición");
  ok(out.formCod === "368E" && out.formInner === "56", "(e) el editor no trae lo cargado: " + out.formCod + "/" + out.formInner);
  ok(/stock del depósito racks/.test(out.desfaseTxt) && /132/.test(out.desfaseTxt) && /36/.test(out.desfaseTxt), "(e) el editor no muestra el desfase del 368E: " + out.desfaseTxt);
  ok(out.sinMotivo === 0 && /motivo/i.test(out.sinMotivoMsg), "(g) guardó sin motivo");
  ok(out.rpc.length === 1 && out.rpc[0].fn === "gv_rack_posicion_guardar" && out.rpc[0].body.p_sector === "X05" &&
     out.rpc[0].body.p_cod === "368E" && out.rpc[0].body.p_inner === 62 && out.rpc[0].body.p_motivo === "conteo",
     "(g) no llamó bien a gv_rack_posicion_guardar: " + JSON.stringify(out.rpc));
  ok(/368E \+6/.test(out.okMsg), "(g) no avisa el ajuste de stock: " + out.okMsg);
  ok(/Góndola\s*A/.test(out.volvio), "(f) volver a Góndolas no dibuja la góndola: " + out.volvio);
  ok(out.viejaVuelve, "(f) el aviso de la planimetría vieja no vuelve en Góndolas");

  if (fallas.length) { console.error("✗ pmap-racks:\n  - " + fallas.join("\n  - ")); process.exit(1); }
  console.log("✓ pmap-racks: dos pestañas, racks por vista, libre/sin lugar, búsqueda y edición por RPC");
})().catch((e) => { console.error(e); process.exit(1); });
