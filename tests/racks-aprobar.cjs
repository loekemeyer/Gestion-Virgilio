/* Regresión idea 4328 — racksAprobarBaja (Recepción: aprobación de Bajadas de Racks a góndola).
   Al aprobar una propuesta: (1) inserta el PAR de movimientos en Movimientos_Stock
   (racks −cajas / terminado +cajas, tipo baja_racks, ref "orden <id>", legajo "0"),
   (2) marca la fila de Racks_Bajadas como 'aprobada', (3) si era la ÚLTIMA propuesta de
   la orden cierra Racks_Ordenes (estado 'bajado' → apaga la alarma), si quedan otras NO
   la cierra, (4) si el insert falla: alert, botón re-habilitado y NO se marca aprobada,
   (5) UI: la tarjeta pasa a sentRow con el cartel de aprobado.
   recepcion.js toma supabase-js de window.supabase → cliente FALSO que anota las
   llamadas. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
if (!/window\.supabase/.test(src)) { console.error("racks-aprobar: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

const FAKE_CLIENT = `
window.__calls = [];
window.__insErr = null;
window.__count = 0;
function __q(table) {
  const call = { table: table, op: null, rows: null, vals: null, eqs: [], countReq: false };
  const o = {};
  ["neq", "gte", "lte", "in", "not", "or", "ilike", "order", "limit", "single"].forEach(function (m) { o[m] = function () { return o; }; });
  o.eq = function (col, val) { call.eqs.push([col, val]); return o; };
  o.insert = function (rows) { call.op = "insert"; call.rows = rows; window.__calls.push(call); return o; };
  o.update = function (vals) { call.op = "update"; call.vals = vals; window.__calls.push(call); return o; };
  o.select = function (sel, opts) { if (!call.op) { call.op = "select"; call.countReq = !!(opts && opts.count); window.__calls.push(call); } return o; };
  o.then = function (res, rej) {
    let payload = { data: [], error: null };
    if (call.op === "insert") payload = { error: window.__insErr };
    else if (call.op === "update") payload = { error: null };
    else if (call.countReq) payload = { count: window.__count, error: null };
    return Promise.resolve(payload).then(res, rej);
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
`;

const patched = src + `
window.__rcp = { racksAprobarBaja: racksAprobarBaja, racksBajaCard: racksBajaCard };
`;

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, out = {};
    window.alert = function (m) { window.__alert = String(m); };
    const calls = function (table, op) { return window.__calls.filter(function (c) { return c.table === table && c.op === op; }); };

    // ---- aprobar la ÚLTIMA propuesta de la orden (count 0) → cierra la orden ----
    window.__calls = []; window.__insErr = null; window.__count = 0; window.__alert = "";
    const b1 = { id: 7, orden_id: 3, cod_art: "500", descripcion: "Art 500", cajas: 12, creada_por: "104", sector: "R2", ts: "2026-08-29T10:00:00Z" };
    const card = R.racksBajaCard(b1);
    document.body.appendChild(card);
    const foot = card.querySelector(".pcFoot");
    await R.racksAprobarBaja(b1, foot);

    const ins = calls("Movimientos_Stock", "insert");
    out.mov_par = ins.length === 1 && ins[0].rows.length === 2;
    const rk = ins[0].rows[0], gd = ins[0].rows[1];
    out.mov_racks = rk.deposito === "racks" && rk.delta === -12 && rk.tipo === "baja_racks" && rk.ref === "orden 3" && rk.legajo === "0" && rk.cod_art === "500";
    out.mov_gondola = gd.deposito === "terminado" && gd.delta === 12 && gd.tipo === "baja_racks" && gd.ref === "orden 3";
    const upd = calls("Racks_Bajadas", "update");
    out.marca_aprobada = upd.length === 1 && upd[0].vals.estado === "aprobada" && !!upd[0].vals.aprobada_at &&
      upd[0].eqs.some(function (e) { return e[0] === "id" && e[1] === 7; });
    out.cuenta_propuestas = calls("Racks_Bajadas", "select").some(function (c) { return c.countReq && c.eqs.some(function (e) { return e[0] === "estado" && e[1] === "propuesta"; }); });
    const ord = calls("Racks_Ordenes", "update");
    out.cierra_orden = ord.length === 1 && ord[0].vals.estado === "bajado" && ord[0].eqs.some(function (e) { return e[0] === "id" && e[1] === 3; });
    out.ui_aprobado = card.classList.contains("sentRow") && /Aprobado/.test(foot.innerHTML);

    // ---- quedan OTRAS propuestas (count 2) → NO cierra la orden ----
    window.__calls = []; window.__count = 2;
    const b2 = { id: 8, orden_id: 4, cod_art: "600", cajas: 5 };
    const card2 = R.racksBajaCard(b2); document.body.appendChild(card2);
    await R.racksAprobarBaja(b2, card2.querySelector(".pcFoot"));
    out.noCierra_conPendientes = calls("Racks_Ordenes", "update").length === 0 &&
      calls("Racks_Bajadas", "update").length === 1;

    // ---- insert falla → alert, botón re-habilitado, NO marca aprobada ----
    window.__calls = []; window.__insErr = { message: "boom" }; window.__alert = "";
    const b3 = { id: 9, orden_id: 5, cod_art: "700", cajas: 3 };
    const card3 = R.racksBajaCard(b3); document.body.appendChild(card3);
    const foot3 = card3.querySelector(".pcFoot");
    await R.racksAprobarBaja(b3, foot3);
    const btn3 = foot3.querySelector("button");
    out.error_alerta = /boom/.test(window.__alert);
    out.error_botonVuelve = !!btn3 && btn3.disabled === false && btn3.textContent === "✓ Aprobar";
    out.error_noAprueba = calls("Racks_Bajadas", "update").length === 0 && !card3.classList.contains("sentRow");

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("racks-aprobar:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
