/* Test de regresión (v15.36) — RECEPCIÓN: dar de alta un artículo NUEVO que no está
   en la planimetría pide el OK de Thomas por WhatsApp y TRABA el cierre de la
   recepción hasta que él conteste.

   Pedido del dueño (2026-09-11). Viene del remito 38087 (02/09): con el botón "+"
   de Log/Fabr el operario dio de alta 599, 943 y 948 — los códigos reales son 599E,
   943E y 948E. El "+" no validaba nada ni le avisaba a nadie.

   Igual que rcp-oc.cjs, `recepcion.js` toma supabase-js de `window.supabase`, así que
   acá se define ese global con un cliente FALSO y se stubea `fetch` (la Edge Function
   gv-alta-articulo). Verifica:
   - un código que YA está en la planimetría no molesta a nadie (no se llama la Edge Fn),
   - un código que NO está dispara UNA llamada con cod/remito/legajo/tall/linea y queda
     'pendiente',
   - con un pendiente, opEnviar NO manda nada (ni Movimientos_Stock ni Control_Modo_OP)
     y avisa,
   - el botón del código muestra ⏳,
   - el estado se relee del BACKEND (no del local): si la tabla dice 'ok' se destraba,
     y si dice 'rechazado' sigue trabado,
   - un código aprobado no vuelve a pedir OK.
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
    const data = (table === "GV_Alta_Articulo_Aprobacion") ? window.__altaRows : [];
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
  arAddCode: arAddCode, altaBloqueados: altaBloqueados, altaRefrescar: altaRefrescar,
  altaEnPlanimetria: altaEnPlanimetria, altaPollStop: altaPollStop,
  drawArticulosGrid: drawArticulosGrid, opEnviar: opEnviar,
  el: { body: opBody } };
`;

if (!/window\.supabase/.test(src)) { console.error("rcp-alta-ok: recepcion.js ya no toma createClient de window.supabase."); process.exit(1); }
if (!/GV_Alta_Articulo_Aprobacion/.test(src)) { console.error("rcp-alta-ok: recepcion.js ya no consulta GV_Alta_Articulo_Aprobacion."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE + '<\/script><script type="module">' + patched + "<\/script></body>");
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
    window.prompt = function () { return "599E"; };
    await R.arAddCode();
    out.conPlanimetriaNoPide = window.__fetches.length === 0;
    out.conPlanimetriaEntra = S.articulos.some(a => a.Cod_Art === "599E");

    // ---- 2) código SIN planimetría: pide el OK y queda pendiente ----
    await new Promise(r => setTimeout(r, 30));   // que caiga el alta del paso 1
    window.__fetches = []; window.__alerts = []; window.__ins = [];
    window.__fetchResp = { token: "tok1", estado: "pendiente", wa_ok: true };
    window.prompt = function () { return "599"; };
    await R.arAddCode();
    const f = window.__fetches[0];
    out.pideOk = window.__fetches.length === 1 && /gv-alta-articulo/.test(f.url);
    out.mandaDatos = !!f && f.body.cod === "599" && f.body.remito === "38087"
      && f.body.legajo === "277" && f.body.tall === "Log/ Fabr" && f.body.linea === "LK";
    out.quedaPendiente = S.altaNuevos["599"] && S.altaNuevos["599"].estado === "pendiente";
    // pendiente = NO se guarda fijo en "Articulos Virgilio X Tallerista" todavía
    out.pendienteNoGuardaFijo = !window.__ins.some(i => i.table === "Articulos Virgilio X Tallerista");
    out.avisaAlOperario = window.__alerts.some(m => /Thomy/.test(m) && /599/.test(m));

    // ---- 3) el botón del código muestra ⏳ ----
    S.cargas["599"] = 16;
    R.drawArticulosGrid();
    let txt599 = "";
    R.el.body.querySelectorAll(".opCodeBtn").forEach(function (x) {
      const sp = x.querySelector("span");
      if (sp && sp.textContent.trim() === "599") txt599 = x.textContent;
    });
    out.botonReloj = /⏳/.test(txt599);

    // ---- 4) con un pendiente NO se puede cerrar la recepción ----
    window.__altaRows = [{ cod: "599", estado: "pendiente", token: "tok1" }];
    await new Promise(r => setTimeout(r, 30));   // que caiga cualquier insert async previo
    window.__ins = []; window.__alerts = [];
    await R.opEnviar();
    out.noEnvia = window.__ins.length === 0;
    out.avisaTrabado = window.__alerts.some(m => /No se puede cerrar/.test(m) && /599/.test(m));
    out.bloqueaLista = R.altaBloqueados().length === 1;

    // ---- 5) el estado sale del BACKEND: 'ok' destraba ----
    window.__altaRows = [{ cod: "599", estado: "ok", token: "tok1" }];
    await R.altaRefrescar();
    out.okDestraba = S.altaNuevos["599"].estado === "ok" && R.altaBloqueados().length === 0;
    await new Promise(r => setTimeout(r, 30));
    out.okGuardaFijo = window.__ins.some(i => i.table === "Articulos Virgilio X Tallerista");

    // ---- 6) 'rechazado' sigue trabado ----
    S.altaNuevos["599"].estado = "pendiente";
    window.__altaRows = [{ cod: "599", estado: "rechazado", token: "tok1" }];
    await R.altaRefrescar();
    out.rechazadoTraba = S.altaNuevos["599"].estado === "rechazado" && R.altaBloqueados().length === 1;
    window.__ins = []; window.__alerts = [];
    await R.opEnviar();
    out.rechazadoNoEnvia = window.__ins.length === 0 &&
      window.__alerts.some(m => /RECHAZ/.test(m));

    // ---- 7) un código ya aprobado no vuelve a pedir OK ----
    S.altaNuevos["599"].estado = "ok";
    window.__fetches = [];
    window.prompt = function () { return "599"; };
    await R.arAddCode();
    out.aprobadoNoRepide = window.__fetches.length === 0;

    R.altaPollStop();
    return out;
  });

  await b.close();
  const fails = Object.keys(r).filter(k => !r[k]);
  if (errs.length) { console.error("rcp-alta-ok: errores de página:", errs); process.exit(1); }
  if (fails.length) { console.error("rcp-alta-ok FALLÓ:", fails, r); process.exit(1); }
  console.log("rcp-alta-ok OK —", Object.keys(r).length, "chequeos");
})();
