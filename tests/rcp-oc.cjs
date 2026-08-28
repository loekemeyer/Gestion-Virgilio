/* Test de regresión (v7.07) — RECEPCIÓN: detalle de la ORDEN DE COMPRA vigente en
   los botones de código + aviso Telegram (evento ROC) cuando lo recibido excede la
   OC en más de 20%.

   ⚠ v10.10 — el ARMADO de las OCs vigentes se fue al backend: la RPC
   `oc_vigentes_por_proveedor(nombre_ent)` hace el matcheo de proveedor (alias
   Pettofrezza→Rafael, compartidos "Garcia / Lucho", prefijos con ≤2 chars de slack),
   descarta lo 'recibida' / ya recibido entero, se queda con la generación más nueva y
   devuelve `cod` ya normalizado (norm_cod). El front solo mapea esas filas. Por eso
   este test dejó de armar filas de "Ordenes_Compra" y ahora stubea la RPC: lo que
   verifica es el CONTRATO (cómo el front consume esas filas) y todo lo que sigue
   siendo del navegador. El matcheo de proveedor se testea contra la base, no acá
   (ocProvCoincide/ocSplitProv/ocDiaLimite quedaron sin uso en recepcion.js).

   `recepcion.js` toma supabase-js de `window.supabase` (vendor/supabase.umd.js), así
   que el test define ese global con un cliente FALSO (responde la RPC y anota los
   insert) y expone los internos en window.__rcp. Verifica:
   - el front mapea cod/fecha/ped/rec/pend de la RPC, y un código que la RPC no
     devuelve queda sin OC,
   - el código cruza normalizado: la RPC devuelve "57" y el botón lo encuentra
     también buscándolo como "057" / "0057",
   - el botón muestra "OC N" y el pop-up de cajas la OC vigente,
   - +20%: 120 sobre 100 NO dispara, 121 SÍ; con recibido parcial la referencia es lo
     que FALTA,
   - exceder NO interrumpe al operario (sin pop-up de aprobación): la carga
     entra derecho, el botón queda en rojo con ⚠ y al enviar sale UN evento `ROC`
     (proveedor|remito|cod:recibidas/pedidas) — el que dispara el Telegram — sólo con
     los códigos que se pasaron.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");

const FAKE_CLIENT = `
const __fake = { rows: [] };
window.__fakeRows = function (rows) { __fake.rows = rows; };
window.__ins = [];
function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.insert = function (rows) { window.__ins.push({ table: table, rows: rows }); return o; };
  o.then = function (res, rej) {
    return Promise.resolve({ data: (table === "Ordenes_Compra" ? __fake.rows : []), error: null }).then(res, rej);
  };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function (fn) {
      if (fn === "oc_vigentes_por_proveedor") return Promise.resolve({ data: __fake.rows, error: null });
      return Promise.resolve({ data: null, error: null });
    },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
} };
`;

const patched = src + `
window.__rcp = { opState: opState,
  ocDeCod: ocDeCod, ocRef: ocRef, ocExcede: ocExcede, ocPctExceso: ocPctExceso,
  cargarOCVigentes: cargarOCVigentes, drawArticulosGrid: drawArticulosGrid,
  openCajas: openCajas, renderResumen: renderResumen, opEnviar: opEnviar, RECP: RECP,
  el: { body: opBody, cajasInput: opCajasInput, cajasNext: opCajasNext, cajasOc: opCajasOc } };
`;

/* v10.24 — recepcion.js dejó de importar supabase-js de esm.sh: ahora toma
   `createClient` de `window.supabase` (vendor/supabase.umd.js, servido desde el repo).
   El stub pasó de reemplazar el `import` a definir ese global ANTES del módulo. El
   guard viejo miraba si quedaba "esm.sh" en el fuente — y sigue quedando, pero en un
   comentario, así que el test se abortaba solo. */
if (!/window\.supabase/.test(src)) { console.error("rcp-oc: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};

    // ---- 1) el front mapea lo que devuelve la RPC ----
    /* Filas TAL COMO las devuelve oc_vigentes_por_proveedor("Lucho"): ya agrupadas por
       código (generación más nueva), con el cod normalizado y ped/rec/pend calculados.
       Lo que la RPC descarta (OC vieja, 'recibida', recibida entera, de otro proveedor)
       directamente no aparece — por eso 725/809/999 no están en la lista. */
    window.__fakeRows([
      { cod: "518", fecha: "2026-07-29", ped: 60,  rec: 0,  pend: 60 },   // dos líneas de la misma fecha ya sumadas
      { cod: "123", fecha: "2026-07-29", ped: 303, rec: 0,  pend: 303 },  // OC compartida "Garcia / Lucho"
      { cod: "586", fecha: "2026-07-29", ped: 100, rec: 60, pend: 40 },   // recibido parcial
      { cod: "57",  fecha: "2026-07-29", ped: 34,  rec: 0,  pend: 34 }    // en la OC es "057"; norm_cod le saca el cero
    ]);
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.linea = "LK"; S.fecha = "2026-08-04";
    S.remito = "12345"; S.cargas = {}; S.ocPorCod = null;
    await R.cargarOCVigentes();
    const oc518 = R.ocDeCod("518"), oc123 = R.ocDeCod("123"), oc586 = R.ocDeCod("586");
    out.mapeaRpc = !!oc518 && oc518.ped === 60 && oc518.rec === 0 && oc518.pend === 60 && oc518.fecha === "2026-07-29"
      && !!oc123 && oc123.ped === 303;
    out.parcial = !!oc586 && oc586.ped === 100 && oc586.rec === 60 && oc586.pend === 40 && R.ocRef(oc586) === 40;
    out.normCod = !!R.ocDeCod("57") && R.ocDeCod("57").ped === 34 && !!R.ocDeCod("057") && !!R.ocDeCod("0057");
    out.fueraVigente = !R.ocDeCod("725") && !R.ocDeCod("809") && !R.ocDeCod("999");

    // ---- 3) umbral del +20% ----
    out.umbral = !R.ocExcede("518", 60) && !R.ocExcede("518", 72) && R.ocExcede("518", 73)   // ref 60 → tope 72
      && !R.ocExcede("586", 48) && R.ocExcede("586", 49)                                     // ref 40 (lo que falta) → tope 48
      && !R.ocExcede("777", 9999);                                                           // sin OC → nunca dispara
    out.pct = R.ocPctExceso("518", 90) === 50;

    // ---- 4) el botón muestra el detalle de la OC ----
    S.step = "articulos";
    S.articulos = [{ Cod_Art: "518", Desc: "" }, { Cod_Art: "586", Desc: "" }, { Cod_Art: "999", Desc: "" }];
    R.drawArticulosGrid();
    const btns = {};
    R.el.body.querySelectorAll(".opCodeBtn").forEach(function (x) {
      const ocq = x.querySelector(".ocq");
      btns[x.querySelector("span").textContent.trim()] = ocq ? ocq.textContent.trim() : null;
    });
    out.btnOc = btns["518"] === "OC 60"              // pedidas
      && btns["586"] === "OC 40/100"                 // faltan/pedidas cuando hay recibido parcial
      && btns["999"] === null;                       // sin OC vigente → sin detalle

    // ---- 5) pop-up de cajas: muestra la OC, y exceder NO interrumpe ----
    R.openCajas("518");
    out.popupOc = R.el.cajasOc.style.display !== "none" && R.el.cajasOc.textContent.indexOf("60") >= 0;

    R.el.cajasInput.value = "70";                     // dentro del +20% → entra derecho
    R.el.cajasNext.click();
    out.okSinAviso = (S.cargas["518"] === 70) && !document.querySelector("#rcpRoot .modal.open");

    R.openCajas("586");
    R.el.cajasInput.value = "90";                     // ref 40 → +125%, pero NO se frena
    R.el.cajasNext.click();
    out.excesoNoFrena = (S.cargas["586"] === 90) && !document.querySelector("#rcpRoot .modal.open");

    // el botón que se pasó queda marcado en rojo; el que está en regla, no
    S.step = "articulos"; R.drawArticulosGrid();
    const rojos = {};
    R.el.body.querySelectorAll(".opCodeBtn").forEach(function (x) {
      rojos[x.querySelector("span").textContent.trim()] = x.classList.contains("exceso");
    });
    out.btnRojo = rojos["586"] === true && rojos["518"] === false;

    // ---- 6) al enviar sale UN evento ROC con los códigos pasados ----
    S.step = "resumen"; R.RECP.legajo = "104";
    window.__ins = [];
    R.renderResumen();
    await R.opEnviar();
    const roc = window.__ins.filter(function (x) {
      return x.table === "Registros_Produccion_Virgilio" && x.rows && x.rows.opcion === "ROC";
    });
    out.rocUnico = roc.length === 1;
    out.rocTexto = roc.length === 1 && roc[0].rows.texto === "Lucho|12345|586:90/40" && roc[0].rows.legajo === "104";

    // sin excesos no se emite ROC
    S.cargas = { "518": 50 };
    window.__ins = [];
    R.renderResumen();          // vuelve a crear el botón Confirmar que usa opEnviar
    await R.opEnviar();
    out.sinExcesoSinRoc = window.__ins.filter(function (x) {
      return x.table === "Registros_Produccion_Virgilio" && x.rows && x.rows.opcion === "ROC";
    }).length === 0;

    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-oc: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-oc: OK — OC vigente en los botones + evento ROC por exceso (+20%)");
  process.exit(0);
})();
