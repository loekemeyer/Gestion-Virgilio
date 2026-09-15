/* Test de regresión (v17.27 · v17.99) — RECEPCIÓN: si entró MÁS mercadería que la habilitada por OC,
   avisarle a Thomas por WhatsApp es OBLIGATORIO, igual que la foto.

   Pedido de Luis (2026-09-14): *"tal y como es obligatorio sacar una foto de la mercadería,
   pone un botón abajo de eso que sea 'Enviar WhatsApp a Thomas' que aparezca cuando se
   selecciona una cantidad de cajas superior a lo que hay en OCs. Que el botón enviar no se
   pueda apretar hasta que no se carga la imagen y hasta que no se aprieta el botón de enviar
   mensaje a Thomas"*. Reemplaza al pop-up de la v17.17.

   Verifica:
   - el pop-up de cajas avisa el exceso EN VIVO pero sin botón — cargar no se interrumpe,
   - en la pantalla de resumen, debajo de la foto, aparece #opExcWa SÓLO si algún código
     supera lo que falta recibir por OC (sin cartel de detalle: se sacó en la v17.30),
   - un código SIN OC vigente cuenta como OC = 0 (v17.99): todo lo que llegue es excedente
     y también exige el aviso, y el mensaje lo dice con "SIN OC generada",
   - si la RPC de OCs falló (ocOk=false) NO se exige nada: no se sabe si el proveedor no
     tiene OCs o si no hubo red, y trabar ahí dejaría a todos sin poder recibir,
   - "Confirmar y enviar" está bloqueado sin foto, bloqueado con foto pero sin WhatsApp, y
     recién se habilita con las dos cosas,
   - el botón arma el wa.me con proveedor, remito y TODOS los códigos,
   - si el operario vuelve atrás y cambia las cantidades, el WhatsApp se vuelve a exigir,
   - sin exceso no aparece nada y alcanza con la foto,
   - v18.02: mientras las OCs no se leyeron (ocPorCod=null) el envío queda bloqueado y el
     resumen las pide solo — el caso de reanudar un borrador parado en "Confirmá el envío",
     que no pasa por la grilla y antes dejaba enviar el exceso sin avisar,
   - v18.02: `opEnviar` tiene guard propio y no registra nada si falta el aviso.
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
  opExcesoItems: opExcesoItems, opExcesoPendiente: opExcesoPendiente, opEnviar: opEnviar,
  el: { body: opBody, cajasInput: opCajasInput, cajasOc: opCajasOc } };
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
    // devuelve un objeto truthy = el pop-up se abrió. Si devolviera null, recepcion.js
    // cae a location.href (v18.02, pop-up bloqueado) y eso navegaría la página del test.
    window.open = function (url) { window.__wa.push(url); return { closed: false }; };
    const conf = function () { return document.getElementById("opConfirmar"); };
    const wa = function () { return document.getElementById("opExcWa"); };

    window.__fakeRows([
      { cod: "518", fecha: "2026-07-29", ped: 60,  rec: 0,  pend: 60 },
      { cod: "586", fecha: "2026-07-29", ped: 100, rec: 60, pend: 40 }   // faltan 40
    ]);
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.linea = "LK"; S.fecha = "2026-08-04";
    S.remito = "12345"; S.cargas = {}; S.ocPorCod = null; S.excesoAvisado = null; S.fotoFile = null;
    await R.cargarOCVigentes();

    // ---- 1) el pop-up de cajas avisa pero no tiene botón ----
    R.openCajas("586");
    R.el.cajasInput.value = "90";
    R.el.cajasInput.oninput();
    out.avisoEnVivo = R.el.cajasOc.textContent.indexOf("más mercadería") >= 0;
    out.sinBotonEnCajas = !R.el.cajasOc.querySelector("button");

    // ---- 2) resumen: el botón aparece con lo que se pasó de la OC y con lo que no tiene OC ----
    S.cargas = { "586": 90, "518": 60, "999": 25 };   // 586 se pasa; 518 justo; 999 SIN OC = OC 0
    const items = R.opExcesoItems();
    const i586 = items.filter(function (x) { return x.cod === "586"; })[0];
    const i999 = items.filter(function (x) { return x.cod === "999"; })[0];
    out.excedeOc = !!i586 && i586.ref === 40 && i586.exced === 50 && i586.sinOc === false;
    // v17.99: sin OC vigente es OC = 0, así que las 25 cajas son todas excedente
    out.sinOcEsExceso = !!i999 && i999.ref === 0 && i999.exced === 25 && i999.sinOc === true;
    out.justoNoEntra = items.length === 2;   // el 518, que viene justo con la OC, no figura

    R.renderResumen();
    const sec = document.getElementById("opExcSection");
    out.seccionVisible = !!sec && sec.style.display !== "none" && !!wa();
    // v17.30 (Luis): sin cartel de detalle, sólo el botón y el aviso de obligatorio.
    out.sinCartel = sec.textContent.indexOf("de más") < 0 && sec.textContent.indexOf("586") < 0
      && sec.textContent.indexOf("Obligatorio") >= 0;

    // ---- 3) el Enviar está bloqueado: sin foto y sin WhatsApp ----
    out.confBloqSinNada = conf().disabled === true;
    S.fotoFile = { fake: true };                 // como si hubiera sacado la foto
    R.renderResumen();
    out.confBloqSoloFoto = conf().disabled === true && R.opExcesoPendiente() === true;

    // ---- 4) el botón manda el WhatsApp y recién ahí se habilita ----
    wa().click();
    const url = decodeURIComponent(window.__wa[0] || "");
    out.wa = url.indexOf("https://wa.me/") === 0 && url.indexOf("Lucho") > 0 &&
      url.indexOf("12345") > 0 && url.indexOf("586") > 0 && url.indexOf("50 de más") > 0;
    // el que no tenía OC sale con su propio texto, no como "por OC faltaban 0"
    out.waSinOc = url.indexOf("999") > 0 && url.indexOf("SIN OC generada (OC = 0)") > 0 &&
      url.indexOf("las 25 son de más") > 0;
    out.confHabilitado = conf().disabled === false;
    out.btnMarcado = wa().classList.contains("has") && wa().textContent.indexOf("enviado") >= 0;
    // y sigue habilitado al volver a entrar a la pantalla
    R.renderResumen();
    out.recuerdaAviso = conf().disabled === false && R.opExcesoPendiente() === false;

    // ---- 5) si cambia la cantidad, hay que volver a avisar ----
    S.cargas = { "586": 120 };
    R.renderResumen();
    out.vuelveSiCambia = conf().disabled === true && R.opExcesoPendiente() === true;
    document.getElementById("opExcWa").click();
    out.reHabilita = conf().disabled === false;

    // ---- 6) sin exceso: no aparece nada y alcanza la foto ----
    S.cargas = { "518": 50 };   // 50 de 60 pedidas: entra en la OC
    R.renderResumen();
    const sec2 = document.getElementById("opExcSection");
    out.sinExcesoSinBoton = !document.getElementById("opExcWa") && sec2.style.display === "none";
    out.sinExcesoEnvia = conf().disabled === false;
    S.fotoFile = null;
    R.renderResumen();
    out.sinFotoNoEnvia = conf().disabled === true;

    // ---- 6.b) v18.02: OCs todavía sin leer (reanudar un borrador en "Confirmá el envío") ----
    S.fotoFile = { fake: true };
    S.cargas = { "586": 90 };
    S.excesoAvisado = null;
    S.ocPorCod = null; S.ocOk = false;          // como queda al reanudar el borrador
    R.renderResumen();
    out.ocSinLeerBloquea = conf().disabled === true;
    // el resumen las pide solo y, cuando llegan, aparece el botón y sigue bloqueado
    await new Promise(function (r) { setTimeout(r, 300); });
    out.ocSeCarganSolas = S.ocOk === true && !!document.getElementById("opExcWa")
      && conf().disabled === true && R.opExcesoPendiente() === true;

    // ---- 6.c) v18.02: guard de opEnviar — sin aviso no registra nada ----
    window.__ins = [];
    await R.opEnviar();
    out.enviarBloqueado = window.__ins.length === 0;

    // ---- 7) si las OCs no se pudieron leer, no se exige nada (ocOk = false) ----
    S.fotoFile = { fake: true };
    S.ocOk = false;                  // la RPC falló: ocPorCod queda en {} (no null)
    S.cargas = { "999": 25, "586": 90 };
    S.excesoAvisado = null;
    R.renderResumen();
    out.ocCaidaNoTraba = R.opExcesoItems().length === 0 && conf().disabled === false
      && !document.getElementById("opExcWa");

    return out;
  });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-exceso-gate: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-exceso-gate: OK — WhatsApp a Thomas obligatorio (como la foto) cuando se recibe de más");
  process.exit(0);
})();
