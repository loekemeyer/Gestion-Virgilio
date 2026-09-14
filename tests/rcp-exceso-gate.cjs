/* Test de regresión (v17.17) — RECEPCIÓN: el aviso a Thomas por mercadería que entra por
   ENCIMA de la OC se pide UNA sola vez, en la pre-aceptación, y no código por código.

   Pedido de Luis (2026-09-14): *"dejar que carguen todo normal y que, al final haya una
   pre-aceptación (cuando aprietan enviar), si cargaron un remito que tenía una cantidad de
   cajas MAYOR a lo que hay en OC, les salga un pop-up en esa pantalla con un botón
   'Escribirle a Thomas' … y otro botón 'Ya le escribí' que permita terminar con el
   registro"*.

   Verifica:
   - el pop-up de cajas sigue avisando el exceso EN VIVO pero YA NO trae el botón de
     WhatsApp (v14.61) — cargar no se interrumpe,
   - al entrar al resumen sale #opExcesoModal con UNA fila por código que supera lo que
     falta recibir por OC (y sólo esos: el que está en regla y el que no tiene OC no
     figuran), con recibidas / faltantes / excedente,
   - "📲 Escribirle a Thomas" arma el wa.me con proveedor, remito y TODOS los códigos,
   - "✓ Ya le escribí" cierra el pop-up y no vuelve a salir con la misma carga; si la
     carga cambia, vuelve a salir,
   - sin exceso el pop-up no aparece y la pantalla de resumen queda usable.
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
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); };
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
  cargarOCVigentes: cargarOCVigentes, openCajas: openCajas, renderResumen: renderResumen,
  opExcesoItems: opExcesoItems,
  el: { body: opBody, cajasInput: opCajasInput, cajasOc: opCajasOc,
        excModal: opExcesoModal, excList: opExcesoList, excWa: opExcesoWa, excOk: opExcesoOk } };
`;

if (!/window\.supabase/.test(src)) { console.error("rcp-exceso-gate: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    window.__wa = [];
    window.open = function (url) { window.__wa.push(url); return null; };

    window.__fakeRows([
      { cod: "518", fecha: "2026-07-29", ped: 60,  rec: 0,  pend: 60 },
      { cod: "586", fecha: "2026-07-29", ped: 100, rec: 60, pend: 40 }   // faltan 40
    ]);
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.linea = "LK"; S.fecha = "2026-08-04";
    S.remito = "12345"; S.cargas = {}; S.ocPorCod = null; S.excesoVisto = null;
    await R.cargarOCVigentes();

    // ---- 1) el pop-up de cajas avisa pero ya no tiene botón de WhatsApp ----
    R.openCajas("586");
    R.el.cajasInput.value = "90";
    R.el.cajasInput.oninput();
    out.avisoEnVivo = R.el.cajasOc.textContent.indexOf("más mercadería") >= 0;
    out.sinBotonEnCajas = !R.el.cajasOc.querySelector("button");

    // ---- 2) el resumen lista SOLO lo que se pasó de la OC ----
    S.cargas = { "586": 90, "518": 60, "999": 25 };   // 586 se pasa; 518 justo; 999 sin OC
    const items = R.opExcesoItems();
    out.soloExcedidos = items.length === 1 && items[0].cod === "586" && items[0].ref === 40 && items[0].exced === 50;

    R.renderResumen();
    out.popupAbre = R.el.excModal.classList.contains("open");
    const filas = R.el.excList.querySelectorAll(".excRow");
    out.unaFila = filas.length === 1 && filas[0].textContent.indexOf("586") >= 0
      && filas[0].textContent.indexOf("90") >= 0 && filas[0].textContent.indexOf("40") >= 0
      && filas[0].textContent.indexOf("50 de más") >= 0;

    // ---- 3) el botón arma el WhatsApp con todo el detalle ----
    R.el.excWa.click();
    const url = decodeURIComponent(window.__wa[0] || "");
    out.wa = url.indexOf("https://wa.me/") === 0 && url.indexOf("Lucho") > 0 &&
      url.indexOf("12345") > 0 && url.indexOf("586") > 0 && url.indexOf("50 de más") > 0;

    // ---- 4) "Ya le escribí" cierra y deja seguir; no repregunta por lo mismo ----
    R.el.excOk.click();
    out.cierra = !R.el.excModal.classList.contains("open");
    R.renderResumen();
    out.noRepregunta = !R.el.excModal.classList.contains("open");
    // si cambia la carga, vuelve a preguntar
    S.cargas = { "586": 120 };
    R.renderResumen();
    out.vuelveSiCambia = R.el.excModal.classList.contains("open");
    R.el.excOk.click();

    // ---- 5) sin exceso no molesta ----
    S.cargas = { "518": 50 };
    R.renderResumen();
    out.sinExcesoSinPopup = !R.el.excModal.classList.contains("open");
    out.resumenOk = R.el.body.textContent.indexOf("518") >= 0;

    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-exceso-gate: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-exceso-gate: OK — aviso de exceso de OC en la pre-aceptación (un pop-up, todos los códigos)");
  process.exit(0);
})();
