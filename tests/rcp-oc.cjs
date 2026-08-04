/* Test de regresión (v7.07) — RECEPCIÓN: detalle de la ORDEN DE COMPRA vigente en
   los botones de código + aviso Telegram (evento ROC) cuando lo recibido excede la
   OC en más de 20%.

   `recepcion.js` es un MÓDULO ES que importa supabase-js de esm.sh, así que no se
   puede cargar tal cual desde file:// (sin red). El test lo parcha: reemplaza el
   import por un cliente FALSO (devuelve filas fijas de "Ordenes_Compra" y anota los
   insert) y expone los internos en window.__rcp. Verifica:
   - matcheo de proveedor: exacto, compartido ("Garcia / Lucho"), con inicial pegada
     ("Martin C" = Martin), por alias (Pettofrezza = Rafael) y que NO matchee ajenos,
   - agrupado: se toma SOLO la generación más nueva (no acumula OCs viejas), se suman
     las líneas de esa fecha, se ignora 'recibida' / lo ya recibido entero, y el
     código cruza normalizado ("057" de la OC = botón "57"),
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
const createClient = function () {
  return {
    from: __q,
    rpc: function () { return Promise.resolve({ data: null, error: null }); },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
};
`;

const patched = src.replace(/^import\s+\{[^}]*\}\s+from\s+"[^"]*";\s*$/m, FAKE_CLIENT) + `
window.__rcp = { opState: opState, ocProvCoincide: ocProvCoincide, ocSplitProv: ocSplitProv,
  ocDeCod: ocDeCod, ocRef: ocRef, ocExcede: ocExcede, ocPctExceso: ocPctExceso,
  ocDiaLimite: ocDiaLimite, cargarOCVigentes: cargarOCVigentes, drawArticulosGrid: drawArticulosGrid,
  openCajas: openCajas, renderResumen: renderResumen, opEnviar: opEnviar, RECP: RECP,
  el: { body: opBody, cajasInput: opCajasInput, cajasNext: opCajasNext, cajasOc: opCajasOc } };
`;

if (patched.indexOf("esm.sh") >= 0) { console.error("rcp-oc: no pude parchear el import de supabase-js."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};

    // ---- 1) matcheo de proveedor ----
    out.provOk = R.ocProvCoincide("Lucho", "Lucho")
      && R.ocProvCoincide("Garcia / Lucho", "Lucho")
      && R.ocProvCoincide("Garcia / Lucho", "Garcia")
      && R.ocProvCoincide("Pintos / Maspoli", "Maspoli")
      && R.ocProvCoincide("Martin C", "Martin")
      && R.ocProvCoincide("Carlos E", "Carlos")
      && R.ocProvCoincide("Pettofrezza", "Rafael")      // ALIAS_NOMBRE
      && R.ocProvCoincide("Log/ Fabr", "Log/Fabr");     // claveTall saca espacios y "/"
    out.provNo = !R.ocProvCoincide("Poly", "Lucho")
      && !R.ocProvCoincide("Tierra Nativa", "Martin")
      && !R.ocProvCoincide("Pintos", "Pedernera")
      && !R.ocProvCoincide("", "Lucho")
      && !R.ocProvCoincide("Lucho", "");

    // ---- 2) carga/agrupado de OCs vigentes ----
    window.__fakeRows([
      // Lucho: generación VIEJA (no debe sumarse a la nueva)
      { codigo: "518", cantidad: 900, cantidad_recibida: 0, proveedor: "Lucho", fecha: "2026-05-02", estado: "pendiente" },
      // Lucho: generación NUEVA, dos líneas del mismo código → se suman (49 + 11 = 60)
      { codigo: "518", cantidad: 49, cantidad_recibida: 0, proveedor: "Lucho", fecha: "2026-07-29", estado: "pendiente" },
      { codigo: "518", cantidad: 11, cantidad_recibida: 0, proveedor: "Lucho", fecha: "2026-07-29", estado: "pendiente" },
      // OC compartida → también es de Lucho
      { codigo: "123", cantidad: 303, cantidad_recibida: 0, proveedor: "Garcia / Lucho", fecha: "2026-07-29", estado: "pendiente" },
      // recibido parcial: referencia = lo que falta (100 - 60 = 40)
      { codigo: "586", cantidad: 100, cantidad_recibida: 60, proveedor: "Lucho", fecha: "2026-07-29", estado: "pendiente" },
      // código con cero adelante en la OC: tiene que cruzar con el botón "57"
      { codigo: "057", cantidad: 34, cantidad_recibida: 0, proveedor: "Lucho", fecha: "2026-07-29", estado: "pendiente" },
      // ya recibida entera / marcada recibida → NO vigentes
      { codigo: "725", cantidad: 29, cantidad_recibida: 29, proveedor: "Lucho", fecha: "2026-07-29", estado: "pendiente" },
      { codigo: "809", cantidad: 159, cantidad_recibida: 0, proveedor: "Lucho", fecha: "2026-07-29", estado: "recibida" },
      // de otro proveedor → no es de Lucho
      { codigo: "999", cantidad: 500, cantidad_recibida: 0, proveedor: "Poly", fecha: "2026-07-29", estado: "pendiente" }
    ]);
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.linea = "LK"; S.fecha = "2026-08-04";
    S.remito = "12345"; S.cargas = {}; S.ocPorCod = null;
    await R.cargarOCVigentes();
    const oc518 = R.ocDeCod("518"), oc123 = R.ocDeCod("123"), oc586 = R.ocDeCod("586");
    out.soloNueva = !!oc518 && oc518.ped === 60 && oc518.fecha === "2026-07-29";
    out.compartida = !!oc123 && oc123.ped === 303;
    out.parcial = !!oc586 && oc586.ped === 100 && oc586.rec === 60 && oc586.pend === 40 && R.ocRef(oc586) === 40;
    out.normCod = !!R.ocDeCod("57") && R.ocDeCod("57").ped === 34 && !!R.ocDeCod("0057");
    out.fueraVigente = !R.ocDeCod("725") && !R.ocDeCod("809") && !R.ocDeCod("999");
    out.diaLimite = /^\d{4}-\d{2}-\d{2}$/.test(R.ocDiaLimite());

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
