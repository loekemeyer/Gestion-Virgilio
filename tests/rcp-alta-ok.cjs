/* Test de regresión (v15.39) — RECEPCIÓN: dar de alta un artículo NUEVO que no está
   en la planimetría le AVISA a Thomas por WhatsApp y deja el asiento, pero NO traba
   la recepción.

   Pedido del dueño (2026-09-11), con su corrección del mismo día: *"no quiero que
   quede bloqueado a que yo les conteste, porque capaz les contesto una hora después.
   Quiero que quede asentado el mensaje y que una vez que lo mandan ellos sí puedan
   seguir dando la recepción"*. La v15.36 trababa el envío; la v15.39 no.

   Viene del remito 38087 (02/09): con el botón "+" de Log/Fabr el operario dio de
   alta 599, 943 y 948 — los códigos reales son 599E, 943E y 948E. El "+" no
   validaba nada ni le avisaba a nadie.

   Igual que rcp-oc.cjs, `recepcion.js` toma supabase-js de `window.supabase`, así que
   acá se define ese global con un cliente FALSO y se stubea `fetch` (la Edge Function
   gv-alta-articulo). Verifica:
   - un código que YA está en la planimetría no molesta a nadie (no se llama la Edge Fn),
   - un código que NO está dispara UNA llamada con cod/remito/legajo/tall/linea y queda
     'pendiente',
   - el operario PUEDE cerrar la recepción con el aviso sin contestar (no se traba),
   - sin conexión tampoco se traba: avisa y deja seguir,
   - el botón del código muestra 🆕,
   - el estado se relee del BACKEND y es informativo ('ok' / 'rechazado'),
   - un código ya avisado no vuelve a mandar el WhatsApp.
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

const FAKE = `
window.__ins = [];          // inserts que intentó hacer el front
window.__fetches = [];      // llamadas a la Edge Function
window.__altaRows = [];     // lo que "tiene" GV_Alta_Articulo_Aprobacion
window.__ocMax = [];        // catálogo de códigos ACTIVOS (OC_Maximos)
window.__alerts = [];
window.alert = function (m) { window.__alerts.push(String(m)); };
window.__fetchResp = { token: "tok1", estado: "pendiente", wa_ok: true };

window.fetch = function (url, init) {
  window.__fetches.push({ url: String(url), body: JSON.parse((init && init.body) || "{}") });
  return Promise.resolve({ ok: true, json: function () { return Promise.resolve(window.__fetchResp); } });
};

function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.insert = function (rows) { window.__ins.push({ table: table, rows: rows }); return o; };
  o.then = function (res, rej) {
    let data = [];
    if (table === "GV_Alta_Articulo_Aprobacion") data = window.__altaRows;
    else if (table === "OC_Maximos") data = window.__ocMax;
    return Promise.resolve({ data: data, error: null }).then(res, rej);
  };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function () { return Promise.resolve({ data: null, error: null }); },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
} };
window.VIR_SUPABASE_URL = "https://fake.supabase.co";
window.VIR_SUPABASE_KEY = "fake-key";
// Planimetría: 599E sí tiene lugar; 599 (sin la E) no.
window.GONDOLA = { "599E": { sector: "J44" }, "505": { sector: "A01" } };
`;

const patched = src + `
window.__rcp = { opState: opState, RECP: RECP,
  arAddCode: arAddCode, arAddCodeAplicar: arAddCodeAplicar,
  arCatalogoCargar: arCatalogoCargar, arCatalogoBuscar: arCatalogoBuscar, arCatalogoTiene: arCatalogoTiene,
  arBusDibujar: arBusDibujar, arBusCerrar: arBusCerrar,
  altaSinRespuesta: altaSinRespuesta, altaRefrescar: altaRefrescar,
  altaEnPlanimetria: altaEnPlanimetria, altaPollStop: altaPollStop,
  drawArticulosGrid: drawArticulosGrid, opEnviar: opEnviar,
  el: { body: opBody, busModal: arBusModal, busInput: arBusInput, busList: arBusList } };
`;

if (!/window\.supabase/.test(src)) { console.error("rcp-alta-ok: recepcion.js ya no toma createClient de window.supabase."); process.exit(1); }
if (!/GV_Alta_Articulo_Aprobacion/.test(src)) { console.error("rcp-alta-ok: recepcion.js ya no consulta GV_Alta_Articulo_Aprobacion."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><button id="opConfirmar"></button><script>' + FAKE + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    R.RECP.legajo = "277";
    S.tipo = "tallerista"; S.tallNombre = "Log/ Fabr"; S.tallCod = "0001";
    S.tallCods = { LK: "0001", CH: "0001" };
    S.linea = "LK"; S.remito = "38087"; S.step = "articulos";
    S.articulos = []; S.cargas = {}; S.altaNuevos = {};

    // ---- 1) código QUE SÍ está en planimetría: no se molesta a nadie ----
    window.__fetches = [];
    await R.arAddCodeAplicar("599E", false);
    out.conPlanimetriaNoPide = window.__fetches.length === 0;
    out.conPlanimetriaEntra = S.articulos.some(a => a.Cod_Art === "599E");

    // ---- 2) código SIN planimetría: pide el OK y queda pendiente ----
    await new Promise(r => setTimeout(r, 30));   // que caiga el alta del paso 1
    window.__fetches = []; window.__alerts = []; window.__ins = [];
    window.__fetchResp = { token: "tok1", estado: "pendiente", wa_ok: true };
    await R.arAddCodeAplicar("599", true);
    const f = window.__fetches[0];
    out.pideOk = window.__fetches.length === 1 && /gv-alta-articulo/.test(f.url);
    out.mandaDatos = !!f && f.body.cod === "599" && f.body.remito === "38087"
      && f.body.legajo === "277" && f.body.tall === "Log/ Fabr" && f.body.linea === "LK";
    out.quedaPendiente = S.altaNuevos["599"] && S.altaNuevos["599"].estado === "pendiente";
    out.avisaAlOperario = window.__alerts.some(m => /Thomy/.test(m) && /599/.test(m));

    // ---- 3) el botón del código muestra ⏳ ----
    S.cargas["599"] = 16;
    R.drawArticulosGrid();
    let txt599 = "";
    R.el.body.querySelectorAll(".opCodeBtn").forEach(function (x) {
      const sp = x.querySelector("span");
      if (sp && sp.textContent.trim() === "599") txt599 = x.textContent;
    });
    out.botonNuevo = /🆕/.test(txt599);

    // ---- 4) con un aviso sin contestar SÍ se puede cerrar la recepción ----
    window.__altaRows = [{ cod: "599", estado: "pendiente", token: "tok1" }];
    await new Promise(r => setTimeout(r, 30));
    window.__ins = []; window.__alerts = [];
    S.fecha = "2026-09-11"; S.fotoFile = null;
    await R.opEnviar();
    out.noTraba = !window.__alerts.some(m => /No se puede cerrar/.test(m));
    out.envia = window.__ins.length > 0;
    out.listaInformativa = R.altaSinRespuesta().length === 1;

    // ---- 5) la respuesta de Thomas es informativa, no un permiso ----
    window.__altaRows = [{ cod: "599", estado: "ok", token: "tok1" }];
    await R.altaRefrescar();
    out.leeOk = S.altaNuevos["599"].estado === "ok" && R.altaSinRespuesta().length === 0;

    // ---- 6) 'rechazado' avisa pero tampoco traba ----
    S.altaNuevos["599"].estado = "pendiente";
    window.__altaRows = [{ cod: "599", estado: "rechazado", token: "tok1" }];
    await R.altaRefrescar();
    out.leeRechazo = S.altaNuevos["599"].estado === "rechazado";
    window.__ins = []; window.__alerts = [];
    await R.opEnviar();
    out.rechazadoIgualEnvia = window.__ins.length > 0 &&
      !window.__alerts.some(m => /No se puede cerrar/.test(m));

    // ---- 7) un código ya avisado no vuelve a mandar el WhatsApp ----
    window.__fetches = [];
    await R.arAddCodeAplicar("599", true);
    out.noRepiteAviso = window.__fetches.length === 0;

    // ---- 8) sin conexión: avisa que no salió, pero NO traba ----
    S.altaNuevos = {}; S.cargas = {}; S.articulos = [];
    const _f = window.fetch;
    window.fetch = function () { return Promise.reject(new Error("offline")); };
    window.__alerts = [];
    await R.arAddCodeAplicar("943", true);
    window.fetch = _f;
    out.offlineAvisa = window.__alerts.some(m => /sin conexión/i.test(m) && /943/.test(m));
    out.offlineEntraIgual = S.articulos.some(a => a.Cod_Art === "943");

    // ---- 9) v15.76 — el "+" es un BUSCADOR de códigos activos ----
    // Catálogo VACÍO = no se toma por bueno (si no, mandaría un WhatsApp por cada alta).
    out.catVacioNoCuenta = R.arCatalogoTiene("599") === null;

    window.__ocMax = [
      { cod: "590E",  descripcion: "Pincel Silicona 11 Gms" },
      { cod: "590ES", descripcion: "Pincel Silicona 11 Gms Suelto" },
      { cod: "941E",  descripcion: "Espatula Lisa Ac. Inox" },
      { cod: "0071",  descripcion: "Bowl Multi Uso 330ml" }
    ];
    await R.arCatalogoCargar();
    out.catCarga = R.arCatalogoTiene("590ES") === true && R.arCatalogoTiene("599") === false;
    out.catNormaliza = R.arCatalogoTiene("71") === true;          // 0071 → 71
    out.buscaPorCodigo = R.arCatalogoBuscar("590").map(x => x.cod).join(",") === "590E,590ES";
    out.buscaPorDesc = R.arCatalogoBuscar("espatula").map(x => x.cod).join(",") === "941E";
    out.buscaSinAcento = R.arCatalogoBuscar("espátula").map(x => x.cod).join(",") === "941E";

    // Elegir uno de la lista NO manda WhatsApp; lo que no matchea, SÍ.
    S.altaNuevos = {}; S.cargas = {}; S.articulos = [];
    window.__fetches = []; window.__alerts = [];
    await R.arAddCodeAplicar("590ES", false);
    out.activoNoAvisa = window.__fetches.length === 0 && S.articulos.some(a => a.Cod_Art === "590ES");

    window.__fetches = []; window.__alerts = [];
    window.__fetchResp = { token: "tok9", estado: "pendiente", wa_ok: true };
    await R.arAddCodeAplicar("9999", true);
    out.fueraDeListaAvisa = window.__fetches.length === 1 && window.__fetches[0].body.cod === "9999";
    out.fueraDeListaEntraIgual = S.articulos.some(a => a.Cod_Art === "9999");

    // La lista del modal se dibuja y ofrece "Cargar igual" sólo cuando nada coincide.
    R.el.busInput.value = "590";
    R.arBusDibujar();
    out.modalLista = R.el.busList.querySelectorAll(".arBusRow").length === 2 &&
                     R.el.busList.querySelectorAll(".arBusIgual").length === 0;
    R.el.busInput.value = "ZZZZ1";
    R.arBusDibujar();
    out.modalEscape = R.el.busList.querySelectorAll(".arBusRow").length === 0 &&
                      R.el.busList.querySelectorAll(".arBusIgual").length === 1;
    R.arBusCerrar();

    R.altaPollStop();
    return out;
  });

  await b.close();
  const fails = Object.keys(r).filter(k => !r[k]);
  if (errs.length) { console.error("rcp-alta-ok: errores de página:", errs); process.exit(1); }
  if (fails.length) { console.error("rcp-alta-ok FALLÓ:", fails, r); process.exit(1); }
  console.log("rcp-alta-ok OK —", Object.keys(r).length, "chequeos");
})();
