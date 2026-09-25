/* v22.48 (Luis, 25/09) — botón «✓ Recibido» en Pendientes de Recepción: pide quién recibe
   (Nora / Pablo / Otro con texto, obligatorio), marca estado='procesado' con gv_recibido_por y
   gv_recibido_at, reusa el código de la fila. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
if (!/window\.supabase/.test(src)) { console.error("pend-recibido: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

const FAKE_CLIENT = `
window.__calls = [];
window.__updErr = null;
window.__codigosUsados = [];
function __q(table) {
  const call = { table: table, op: null, vals: null, eqs: [] };
  const o = {};
  ["gte", "lte", "in", "not", "or", "ilike", "order", "limit", "single", "neq"].forEach(function (m) { o[m] = function () { return o; }; });
  o.eq = function (col, val) { call.eqs.push([col, val]); return o; };
  o.insert = function (rows) { call.op = "insert"; call.rows = rows; window.__calls.push(call); return o; };
  o.update = function (vals) { call.op = "update"; call.vals = vals; window.__calls.push(call); return o; };
  o.select = function (sel) { if (!call.op) { call.op = "select"; call.sel = sel; window.__calls.push(call); } return o; };
  o.then = function (res, rej) {
    let payload = { data: [], error: null };
    if (call.op === "update") payload = { error: window.__updErr };
    else if (call.op === "select" && call.sel === "codigo") payload = { data: window.__codigosUsados.map(function (c) { return { codigo: c }; }), error: null };
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
window.__rcp = { pendCard: pendCard, pendRowComplete: pendRowComplete, pendEnviar: pendEnviar,
  pendGenCodigo: pendGenCodigo, pendRefreshEnviar: pendRefreshEnviar, pendRows: _pendRows };
`;

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.setContent('<!doctype html><meta charset="utf-8"><body><script>' + FAKE_CLIENT + '<\/script><script type="module">' + patched + "<\/script></body>");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });
  const r = await p.evaluate(async () => {
    const R = window.__rcp, out = {};
    const wait = function (ms) { return new Promise(function (res) { setTimeout(res, ms); }); };
    const upds = function () { return window.__calls.filter(function (c) { return c.table === "Control_Modo_OP" && c.op === "update"; }); };
    const rootEl = document.getElementById("rcpRoot");
    window.__calls = [];
    const row = { id: 77, fecha: "2026-09-25", tipo: "tallerista", nombre: "Garcia", linea: "LK", remito: "37843",
                  detalle: "584E → 35", cantidad_total: 35, created_at: new Date().toISOString(),
                  isis: false, control_partes: null, foto_url: "http://x/f.jpg", foto_vista: false, codigo: "2299" };
    const card = R.pendCard(row); rootEl.appendChild(card);
    const rb = card.querySelector(".recibidoBtn");
    out.boton_esta = !!rb && /Recibido/.test(rb.textContent);
    rb.click(); await wait(10);
    const ov = rootEl.querySelector(".rcbOverlay");
    const ok = ov && ov.querySelector(".btnSend");
    out.pide_quien = !!ov && ok.disabled === true;
    const ops = Array.from(ov.querySelectorAll(".rcbOp")).map(function (x) { return x.textContent; });
    out.opciones = ops.join("|") === "Nora|Pablo|Otro…";
    // Otro sin texto -> sigue bloqueado
    ov.querySelectorAll(".rcbOp")[2].click();
    out.otro_vacio_bloquea = ok.disabled === true;
    const inp = ov.querySelector(".rcbOtro"); inp.value = "  Fabi "; inp.dispatchEvent(new Event("input"));
    out.otro_habilita = ok.disabled === false;
    ok.click(); await wait(40);
    const u = upds();
    out.persiste = u.length === 1 && u[0].vals.estado === "procesado" && u[0].vals.gv_recibido_por === "Fabi"
      && !!u[0].vals.gv_recibido_at && u[0].vals.codigo === "2299" && u[0].eqs.some(function (e) { return e[0] === "id" && e[1] === 77; });
    out.cierra = !rootEl.querySelector(".rcbOverlay");
    out.ui = card.classList.contains("sentRow") && /Recibido por Fabi/.test(card.textContent) && !card.querySelector(".recibidoBtn");
    // Error al guardar -> queda el cuadro con el error
    window.__calls = []; window.__updErr = { message: "boom" };
    const card2 = R.pendCard(Object.assign({}, row, { id: 78 })); rootEl.appendChild(card2);
    card2.querySelector(".recibidoBtn").click(); await wait(10);
    const ov2 = rootEl.querySelector(".rcbOverlay");
    ov2.querySelectorAll(".rcbOp")[0].click(); ov2.querySelector(".btnSend").click(); await wait(40);
    out.error_visible = !!rootEl.querySelector(".rcbOverlay") && /boom/.test(ov2.textContent) && R.pendRows[78].sent === false;
    return out;
  });
  const bad = Object.keys(r).filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("pend-recibido:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
