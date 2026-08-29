/* Regresión idea 5267 — checklist de Pendientes de Recepción (Marianela): completitud,
   envío y código único.
   Desde v12.03 la tarjeta tiene 3 pasos: Carga ISIS · Control Partes (corresponde / no
   corresponde) · Foto. Cubre: Enviar deshabilitado hasta completar los 3 · cada tilde
   PERSISTE al toque en Control_Modo_OP (update + eq id) · "No corresponde" también
   completa el paso de partes · pendEnviar reusa el código que la fila ya trae (v10.02:
   no genera uno nuevo → un solo código por recepción) y marca estado='procesado' ·
   fila vieja SIN código → pendGenCodigo genera 4 dígitos evitando los ya usados hoy ·
   error al persistir → alert y el botón vuelve · doble Enviar no duplica.
   recepcion.js toma supabase-js de window.supabase → cliente FALSO. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
if (!/window\.supabase/.test(src)) { console.error("pend-checklist: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

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
    window.alert = function (m) { window.__alert = String(m); };
    const upds = function () { return window.__calls.filter(function (c) { return c.table === "Control_Modo_OP" && c.op === "update"; }); };
    const wait = function (ms) { return new Promise(function (res) { setTimeout(res, ms); }); };
    // Las tarjetas viven bajo #rcpRoot (pendRefreshEnviar busca ahí)
    const rootEl = document.getElementById("rcpRoot") || (function () { const d = document.createElement("div"); d.id = "rcpRoot"; document.body.appendChild(d); return d; })();

    // ---- tarjeta nueva: 3 pasos sin tildar → Enviar deshabilitado ----
    window.__calls = [];
    const row = { id: 55, fecha: "2026-08-29", tipo: "tallerista", nombre: "Lucho", linea: "LK", remito: "1234",
                  detalle: "500 → 3", cantidad_total: 3, created_at: new Date().toISOString(),
                  isis: false, control_partes: null, foto_url: "http://x/foto.jpg", foto_vista: false, codigo: "4444" };
    const card = R.pendCard(row); rootEl.appendChild(card);
    const btn = card.querySelector(".enviarBtn");
    out.arranca_bloqueado = btn.disabled === true && R.pendRowComplete(55) === false;
    // sin "Faltantes x Día" (v12.03): 3 filas de pasos, no 4
    out.tresPasos = card.querySelectorAll(".pcActs .pcRow").length === 3;

    // ---- tildar ISIS persiste y sigue bloqueado (faltan partes + foto) ----
    card.querySelectorAll(".pcActs .pcRow")[0].querySelector(".tickBtn").click();
    await wait(30);
    out.isis_persiste = upds().some(function (c) { return c.vals.isis === true && c.eqs.some(function (e) { return e[0] === "id" && e[1] === 55; }); });
    out.isis_sigueBloqueado = btn.disabled === true;

    // ---- "No corresponde" completa el paso de partes ----
    card.querySelectorAll(".pcActs .pcRow")[1].querySelector(".noBtn").click();
    await wait(30);
    out.partes_no = R.pendRows[55].partes === "no" && upds().some(function (c) { return c.vals.control_partes === "no"; });
    out.faltaFoto_bloqueado = btn.disabled === true;

    // ---- foto vista (el flujo real la marca al abrir el visor) → Enviar se habilita ----
    R.pendRows[55].foto_vista = true; R.pendRefreshEnviar(55);
    out.completo_habilita = btn.disabled === false && R.pendRowComplete(55) === true;

    // ---- Enviar: REUSA el código de la fila (no genera otro) y marca procesado ----
    window.__calls = [];
    await R.pendEnviar(55, card.querySelector(".pcFoot"));
    const env = upds();
    out.envia_procesado = env.length === 1 && env[0].vals.estado === "procesado" && !!env[0].vals.procesado_at;
    out.envia_reusaCodigo = env[0].vals.codigo === "4444";
    out.envia_ui = card.classList.contains("sentRow") && /4444/.test(card.querySelector(".pcFoot").innerHTML);
    // doble Enviar → no duplica
    await R.pendEnviar(55, card.querySelector(".pcFoot"));
    out.dobleEnvio_noDuplica = upds().length === 1;

    // ---- fila vieja SIN código → genera 4 dígitos evitando los usados hoy ----
    window.__codigosUsados = ["1000"];
    const seq = [0.0, 0.5];   // 1er random → "1000" (usado) → reintenta → "5500"
    let i = 0; const origRnd = Math.random; Math.random = function () { return seq[Math.min(i++, seq.length - 1)]; };
    const cod = await R.pendGenCodigo();
    Math.random = origRnd;
    out.codigo_unico = cod === "5500" && /^\d{4}$/.test(cod);

    // ---- fila LEGACY sin foto del operario → el paso Foto se auto-tilda (no bloquea) ----
    const rowL = Object.assign({}, row, { id: 57, foto_url: null });
    const cardL = R.pendCard(rowL); rootEl.appendChild(cardL);
    out.legacy_sinFoto_autoTick = R.pendRows[57].foto_vista === true && /Sin foto/.test(cardL.innerHTML);

    // ---- error al persistir el envío → alert, botón vuelve, sigue pendiente ----
    window.__calls = []; window.__updErr = { message: "boom" }; window.__alert = "";
    const row2 = Object.assign({}, row, { id: 56 });
    const card2 = R.pendCard(row2); rootEl.appendChild(card2);
    R.pendRows[56].isis = true; R.pendRows[56].partes = "corresponde"; R.pendRows[56].foto_vista = true;
    R.pendRefreshEnviar(56);
    await R.pendEnviar(56, card2.querySelector(".pcFoot"));
    const btn2 = card2.querySelector(".enviarBtn");
    out.error_alerta = /boom/.test(window.__alert);
    out.error_botonVuelve = !!btn2 && btn2.disabled === false && btn2.textContent === "Enviar";
    out.error_sigue = R.pendRows[56].sent === false && !card2.classList.contains("sentRow");

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("pend-checklist:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
