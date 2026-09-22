/* Test de regresión (v21.30) — RECEPCIÓN: "Introducir código diferente" para TODOS.

   Pedido de Luis (2026-09-22): *"en el módulo de recepción de tallerista, cuando se elige
   al tallerista deberían aparecer los códigos asignados a el como proveedor y un botón más
   grande que diga «Introducir Código diferente» que le permita al operario escribir un
   código (pero solo elegir de una lista de sugerencias que consiste en los códigos
   existentes). Una vez envíe el dato de la recepción, debería aparecer un botón para
   notificar a Thomy por WhatsApp (como si hubiesen recibido mercadería > a las OCs
   establecidas) que no impida la recepción"*.

   Hasta la v21.27 ese buscador era el "+" de Log/Fabr y NADIE más lo tenía: un tallerista
   que entregaba un código que no era suyo no tenía forma de cargarlo.

   Verifica:
   - el botón grande aparece con un tallerista que NO es Log/Fabr,
   - aparece TAMBIÉN cuando el proveedor no tiene ni un código (antes ahí se cortaba con
     un `return` y el operario quedaba sin salida),
   - el código agregado a mano queda marcado en `artExtra`,
   - NO se guarda fijo en el padrón salvo en Log/Fabr (si se guardara, la próxima entrega
     entraría en silencio y el aviso a Thomas no saldría nunca más),
   - en Log/Fabr SÍ se guarda (no se rompió lo que ya andaba),
   - el WhatsApp del resumen dice "no está asignado a <proveedor>" y no "SIN OC generada",
   - y NO impide la recepción: el botón de enviar sigue ahí.
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

/* Candado invertido: si alguien vuelve a colgar el botón de arEsLogFabr(), esto grita. */
if (/if\s*\(\s*arEsLogFabr\(\)\s*\)\s*\{[^}]*opCodeAdd/.test(src)) {
  console.error("rcp-codigo-diferente: el botón volvió a quedar sólo para Log/Fabr.");
  process.exit(1);
}
if (!/Introducir código diferente/.test(src)) {
  console.error("rcp-codigo-diferente: desapareció el botón \"Introducir código diferente\".");
  process.exit(1);
}

const FAKE_CLIENT = `
window.__inserts = [];
window.__selects = [];
function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete"]
    .forEach(function (m) { o[m] = function () { if (m === "select") window.__selects.push(table); return o; }; });
  o.insert = function (rows) { window.__inserts.push({ table: table, rows: rows });
                               return Promise.resolve({ data: rows, error: null }); };
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function (fn) {
      if (fn === "oc_vigentes_por_proveedor") return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: [], error: null });
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
  drawArticulosGrid: drawArticulosGrid, arAddCodeAplicar: arAddCodeAplicar,
  cargarOCVigentes: cargarOCVigentes, opExcesoItems: opExcesoItems,
  renderResumen: renderResumen, closeCajas: closeCajas,
  el: { body: opBody, actions: opActions } };
`;

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  p.on("dialog", (d) => d.accept());
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    window.__wa = [];
    window.open = function (url) { window.__wa.push(url); return { closed: false }; };
    window.alert = function () {};

    function reset(nombre) {
      S.tipo = "tallerista"; S.tallNombre = nombre; S.linea = "LK"; S.fecha = "2026-09-22";
      S.remito = "40001"; S.cargas = {}; S.artExtra = {}; S.altaNuevos = {};
      S.ocPorCod = null; S.ocOk = false; S.ocAjena = null;
      S.excesoAvisado = null; S.fotoFile = null;
      S.tallCod = "3806"; S.tallCods = { LK: "3806", CH: "3715" };
      S.step = "articulos";
      window.__inserts = [];
    }

    // ---- 1) tallerista normal, CON códigos: el botón grande está ----
    reset("Lucho");
    S.articulos = [{ Cod_Art: "586", Desc: "" }, { Cod_Art: "587", Desc: "" }];
    await R.cargarOCVigentes();
    R.drawArticulosGrid();
    const btn1 = document.getElementById("opCodeOtro");
    out.botonEnTalleristaNormal = !!btn1 && btn1.textContent.indexOf("Introducir código diferente") >= 0;
    out.sinTilePlus = !document.querySelector(".opCodeAdd");

    // ---- 2) proveedor SIN códigos: el botón sigue estando (antes cortaba con return) ----
    S.articulos = [];
    R.drawArticulosGrid();
    out.botonSinCodigos = !!document.getElementById("opCodeOtro");
    out.avisaQueNoHay = R.el.body.textContent.indexOf("No hay códigos asignados") >= 0;

    // ---- 3) agrega un código que no es suyo: queda marcado y NO se guarda fijo ----
    S.articulos = [{ Cod_Art: "586", Desc: "" }];
    await R.arAddCodeAplicar("550", true);
    R.closeCajas();
    await new Promise(function (r2) { setTimeout(r2, 120); });
    out.marcadoArtExtra = S.artExtra["550"] === true;
    out.enLaGrilla = S.articulos.some(function (a) { return a.Cod_Art === "550"; });
    out.noGuardaFijo = window.__inserts.filter(function (i) {
      return i.table === "Articulos Virgilio X Tallerista"; }).length === 0;

    // ---- 4) el WhatsApp lo dice por su nombre, y el envío NO queda impedido ----
    S.cargas = { "586": 3, "550": 7 };
    S.ocOk = true; S.ocPorCod = {};
    const items = R.opExcesoItems();
    const i550 = items.filter(function (x) { return x.cod === "550"; })[0];
    out.itemNoAsig = !!i550 && i550.noAsig === true;
    S.fotoFile = { fake: true };
    R.renderResumen();
    const wa = document.getElementById("opExcWa");
    out.hayBotonWa = !!wa;
    wa.click();
    const url = decodeURIComponent(window.__wa[0] || "");
    out.waTitulo = url.indexOf("no está asignado a él") > 0;
    out.waLinea = url.indexOf("550: recibo 7, NO está asignado a Lucho") > 0;
    const c550 = url.indexOf("• 550"), c586 = url.indexOf("• 586");
    const tramo = c586 > c550 ? url.slice(c550, c586) : url.slice(c550);
    out.noDiceSinOc = tramo.indexOf("SIN OC generada") < 0;
    // y el 586, que sí es suyo y no tiene OC, sigue saliendo como "SIN OC generada"
    out.elSuyoSigueSinOc = url.indexOf("586: recibo 3, SIN OC generada") > 0;
    // no impide la recepción: el botón de confirmar existe y se habilita al avisar
    const cb = document.getElementById("opConfirmar");
    out.puedeEnviar = !!cb && cb.disabled === false;

    // ---- 5) Log/Fabr SIGUE guardando fijo (no se rompió lo de antes) ----
    reset("Log/ Fabr");
    S.articulos = [];
    await R.arAddCodeAplicar("941E", true);
    R.closeCajas();
    await new Promise(function (r2) { setTimeout(r2, 120); });   // arSaveCodeRemote no se awaitea
    out.logFabrGuardaFijo = window.__inserts.filter(function (i) {
      return i.table === "Articulos Virgilio X Tallerista"; }).length > 0;

    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-codigo-diferente: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-codigo-diferente: OK — el botón vale para todos, el código ajeno no se asigna y Thomy se entera");
  process.exit(0);
})();
