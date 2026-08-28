/* Test de regresión (v12.07) — PENDIENTES de Recepción: al abrir "Ver foto" el visor
   muestra, EN EL MISMO LUGAR, la foto Y lo que cargó el operario (código → cajas +
   total). Antes el overlay tapaba la tarjeta y había que cerrar/abrir la foto para
   cotejar contra la mercadería.

   Igual que rcp-oc.cjs: `recepcion.js` toma supabase-js de `window.supabase`, así que
   el test define ese global con un cliente FALSO que devuelve una fila pendiente de
   Control_Modo_OP, y expone los internos en window.__rcp. Verifica:
   - la tarjeta pendiente se dibuja y el botón "Ver foto" abre el overlay,
   - el overlay tiene la <img> Y el panel de detalle a la vez,
   - el panel lista cada código con sus cajas (parseado de `detalle`) y el total,
   - el panel repite nombre/remito (contexto para el control),
   - cerrar marca "Foto vista" (no se rompió el flujo que habilita Enviar).
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
const __fake = { pend: [] };
window.__fakePend = function (rows) { __fake.pend = rows; };
window.__upd = [];
function __q(table) {
  const o = {};
  ["select","gte","lte","neq","in","not","or","ilike","order","limit","single","delete"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.eq = function () { return o; };
  o.insert = function () { return o; };
  o.update = function (patch) { window.__upd.push({ table: table, patch: patch }); return o; };
  o.then = function (res, rej) {
    return Promise.resolve({ data: (table === "Control_Modo_OP" ? __fake.pend : []), error: null }).then(res, rej);
  };
  return o;
}
window.supabase = { createClient: function () {
  return {
    from: __q,
    rpc: function () { return Promise.resolve({ data: null, error: null }); },
    storage: { from: function () { return { upload: function () { return Promise.resolve({ error: null }); },
      getPublicUrl: function () { return { data: { publicUrl: "x" } }; } }; } },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
} };
`;

const patched = src + `
window.__rcp = { opState: opState, renderPendientes: renderPendientes,
  pendFotoParseDetalle: pendFotoParseDetalle, el: { body: opBody } };
`;

if (!/window\.supabase/.test(src)) { console.error("rcp-foto-detalle: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, out = {};

    // parseo del `detalle` tal cual lo arma opEnviar(): "COD → N · COD → N"
    const it = R.pendFotoParseDetalle("518 → 12 · 586 → 7 · 057 → 3");
    out.parse = it.length === 3 && it[0].cod === "518" && it[0].cajas === "12"
      && it[2].cod === "057" && it[2].cajas === "3";
    out.parseVacio = R.pendFotoParseDetalle("").length === 0 && R.pendFotoParseDetalle(null).length === 0;

    window.__fakePend([{
      id: 77, fecha: "2026-08-28", tipo: "tallerista", nombre: "Lucho", linea: "LK",
      remito: "12345", detalle: "518 → 12 · 586 → 7 · 057 → 3", cantidad_total: 22,
      created_at: new Date().toISOString(), isis: false, control_partes: null,
      foto_url: "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==",
      foto_vista: false, codigo: "4321"
    }]);
    await R.renderPendientes();
    await new Promise(function (r2) { setTimeout(r2, 30); });

    const card = document.querySelector('#rcpRoot .pendCard[data-id="77"]');
    out.tarjeta = !!card;
    const btn = card && card.querySelector(".fotoViewBtn");
    out.botonVerFoto = !!btn && btn.textContent.indexOf("Ver foto") >= 0;
    btn.click();

    const ov = document.querySelector("#rcpRoot .fotoOverlay");
    out.overlay = !!ov;
    // foto y detalle CONVIVEN en el visor
    out.fotoYDetalleJuntos = !!(ov && ov.querySelector("img") && ov.querySelector(".fotoOverlayInfo"));
    const info = ov.querySelector(".fotoOverlayInfo");
    const items = Array.from(info.querySelectorAll(".fovItem")).map(function (x) {
      return [x.querySelector(".fovCod").textContent, x.querySelector(".fovCaj").textContent];
    });
    out.items = JSON.stringify(items) === JSON.stringify([["518", "12 cj"], ["586", "7 cj"], ["057", "3 cj"]]);
    out.total = /22 cajas/.test(info.querySelector(".fovTotal").textContent);
    out.contexto = /12345/.test(info.textContent) && /Lucho/i.test(info.textContent);

    // el detalle es visible de verdad (ancho/alto reales) y NO se pisa con la foto
    const im = ov.querySelector("img");
    await new Promise(function (r2) { if (im.complete) return r2(); im.onload = im.onerror = r2; });
    const rc = info.getBoundingClientRect(), ri = im.getBoundingClientRect();
    out.visible = rc.width > 100 && rc.height > 40;
    out.noSePisan = ri.right <= rc.left + 1 || ri.bottom <= rc.top + 1;

    // cerrar → marca "Foto vista" y persiste (flujo viejo intacto)
    window.__upd = [];
    ov.querySelector(".fotoOverlayClose").click();
    await new Promise(function (r2) { setTimeout(r2, 30); });
    out.cierra = !document.querySelector("#rcpRoot .fotoOverlay");
    out.marcaVista = btn.classList.contains("viewed")
      && window.__upd.some(function (u) { return u.table === "Control_Modo_OP" && u.patch && u.patch.foto_vista === true; });
    return out;
  });

  // ---- celular (≤460px): foto y detalle apilados, los dos visibles sin cerrar nada ----
  await p.setViewportSize({ width: 390, height: 780 });
  const rm = await p.evaluate(async () => {
    const out = {};
    const btn = document.querySelector('#rcpRoot .pendCard[data-id="77"] .fotoViewBtn');
    btn.click();
    const ov = document.querySelector("#rcpRoot .fotoOverlay");
    const info = ov.querySelector(".fotoOverlayInfo"), im = ov.querySelector("img");
    await new Promise(function (r2) { if (im.complete) return r2(); im.onload = im.onerror = r2; });
    const rc = info.getBoundingClientRect(), ri = im.getBoundingClientRect();
    out.celVisible = rc.width > 200 && rc.height > 40;
    out.celApilado = ri.bottom <= rc.top + 1;                   // foto arriba, detalle abajo
    out.celDentro = rc.left >= -1 && rc.right <= innerWidth + 1;  // sin scroll horizontal
    out.celItems = ov.querySelectorAll(".fovItem").length === 3;
    ov.querySelector(".fotoOverlayClose").click();
    return out;
  });
  Object.keys(rm).forEach(function (k) { r[k] = rm[k]; });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-foto-detalle: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-foto-detalle: OK — el visor muestra foto + código/cajas del operario a la vez");
  process.exit(0);
})();
