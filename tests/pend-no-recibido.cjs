/* v24.89 (Mel, 30/09) — «No recibido» a la derecha de Recibido en Pendientes de Recepción.
   Mismo criterio que «No corresponde»: excluyente con el tilde y se destilda tocándolo de nuevo.
   Al prenderlo abre WhatsApp a Marian (5491131181186) con el remito, el día, la hora y quién lo
   trajo, y persiste gv_no_recibido_at. NO habilita Enviar. Con Recibido tildado no se muestra
   (v24.93, Mel). Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
if (!/window\.supabase/.test(src)) { console.error("pend-no-recibido: recepcion.js ya no toma createClient de window.supabase — actualizá el stub."); process.exit(1); }

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
    storage: { from: function () { return {
      upload: function (path) { window.__uploads = (window.__uploads || []).concat([path]); return Promise.resolve({ data: {}, error: null }); },
      getPublicUrl: function (path) { return { data: { publicUrl: "http://x/" + path } }; } }; } },
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
  pendGenCodigo: pendGenCodigo, histRecibioTxt: histRecibioTxt, histOrdenar: histOrdenar, opExcesoEntraTxt: opExcesoEntraTxt, pendNombreCap: pendNombreCap, HIST_COLS: HIST_COLS, pendRefreshEnviar: pendRefreshEnviar, pendRows: _pendRows };
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
    window.__opened = [];
    window.open = function (u) { window.__opened.push(u); return {}; };
    window.__calls = [];
    // 23/09 17:58 UTC = 14:58 en Buenos Aires
    const row = { id: 91, fecha: "2026-09-23", tipo: "tallerista", nombre: "Log/ Fabr", linea: "CH", remito: "38868",
                  detalle: "727E → 60", cantidad_total: 60, created_at: "2026-09-23T17:58:37Z",
                  isis: true, control_partes: "no", foto_url: "http://x/f.jpg", foto_vista: true, codigo: null };
    const card = R.pendCard(row); card.style.width = "330px"; card.style.boxSizing = "border-box"; rootEl.appendChild(card);
    const rr = card.querySelector(".pcActs .pcRecibidoRow");
    const tick = rr.querySelector(".tickBtn"), no = rr.querySelector(".noRecBtn");
    out.boton_esta = !!no && no.textContent === "No recibido" && no.disabled === false;
    out.a_la_derecha = !!no && no.getBoundingClientRect().left > rr.querySelector(".pcLbl").getBoundingClientRect().right;
    out.misma_fila = !!no && Math.abs(no.getBoundingClientRect().top - tick.getBoundingClientRect().top) < 20;
    out.no_desborda = rr.scrollWidth <= rr.clientWidth + 1;
    // prender: WhatsApp + persiste
    no.click(); await wait(30);
    const url = window.__opened[0] || "";
    const txt = decodeURIComponent((url.split("?text=")[1] || ""));
    out.whatsapp_marian = url.indexOf("https://wa.me/5491131181186?text=") === 0;
    out.mensaje = txt === "Hola Marian, no recibí el remito 38868 que te llegó el día 23/09 a las 14:58 de Log/ Fabr, confirmame porfa que lo tenés o si ya lo mandaste";
    const u = upds();
    out.persiste = u.length === 1 && !!u[0].vals.gv_no_recibido_at && u[0].vals.gv_recibido_por === null
      && !("estado" in u[0].vals) && u[0].eqs.some(function (e) { return e[0] === "id" && e[1] === 91; });
    out.queda_rojo = no.classList.contains("on") && /avisado · /.test(rr.textContent);
    out.enviar_no_habilita = card.querySelector(".enviarBtn").disabled === true;
    // apagar: sin WhatsApp, borra la marca
    window.__calls = []; window.__opened = [];
    no.click(); await wait(30);
    const u2 = upds();
    out.apaga = u2.length === 1 && u2[0].vals.gv_no_recibido_at === null && !no.classList.contains("on") && window.__opened.length === 0;
    // excluyente: prender No recibido y después tildar Recibido lo apaga
    no.click(); await wait(30);
    window.__calls = [];
    tick.click(); await wait(10);
    const ov = rootEl.querySelector(".rcbOverlay");
    ov.querySelectorAll(".rcbOp")[0].click(); ov.querySelector(".btnSend").click(); await wait(40);
    const u3 = upds();
    out.recibido_lo_apaga = u3.length === 1 && u3[0].vals.gv_recibido_por === "Nora" && u3[0].vals.gv_no_recibido_at === null
      && !no.classList.contains("on") && tick.classList.contains("on");
    out.recibido_habilita = card.querySelector(".enviarBtn").disabled === false;
    // v24.93 (Mel): con Recibido tildado, «No recibido» no se ofrece
    out.oculto_con_recibido = no.style.display === "none" && no.offsetParent === null;
    // destildar Recibido lo vuelve a mostrar
    window.__calls = [];
    tick.click(); await wait(30);
    out.vuelve_al_destildar = !tick.classList.contains("on") && no.style.display === "" && no.offsetParent !== null;
    // sin foto: Recibido bloqueado, No recibido disponible
    const card2 = R.pendCard(Object.assign({}, row, { id: 92, foto_url: null })); rootEl.appendChild(card2);
    out.sin_foto = card2.querySelector(".pcRecibidoRow .tickBtn").disabled === true && card2.querySelector(".noRecBtn").disabled === false;
    // recarga: la marca guardada vuelve prendida
    const card3 = R.pendCard(Object.assign({}, row, { id: 93, gv_no_recibido_at: "2026-09-30T14:02:00Z" })); rootEl.appendChild(card3);
    out.recarga = card3.querySelector(".noRecBtn").classList.contains("on") && /avisado · 30-09/.test(card3.textContent);
    // recarga de una recepción ya recibida: el botón no aparece
    const card4 = R.pendCard(Object.assign({}, row, { id: 94, gv_recibido_por: "Mel", gv_recibido_at: "2026-09-30T13:10:00Z" })); rootEl.appendChild(card4);
    out.recarga_recibido_oculto = card4.querySelector(".noRecBtn").style.display === "none";
    return out;
  });
  const bad = Object.keys(r).filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("pend-no-recibido:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
