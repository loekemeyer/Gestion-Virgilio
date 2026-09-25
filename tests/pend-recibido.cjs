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
  pendGenCodigo: pendGenCodigo, histRecibioTxt: histRecibioTxt, pendRefreshEnviar: pendRefreshEnviar, pendRows: _pendRows };
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
    const rr = card.querySelector(".pcActs .pcRecibidoRow"); const rb = rr && rr.querySelector(".tickBtn");
    out.tilde_esta = !!rb && /Recibido/.test(rr.textContent) && rb.disabled === false;
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
    out.persiste = u.length === 1 && u[0].vals.gv_recibido_por === "Fabi" && !!u[0].vals.gv_recibido_at
      && !("estado" in u[0].vals) && u[0].eqs.some(function (e) { return e[0] === "id" && e[1] === 77; });
    out.cierra = !rootEl.querySelector(".rcbOverlay");
    out.otro_queda = window.__calls.some(function (c) { return c.table === "GV_Recepcion_Receptores" && c.op === "insert" && c.rows && c.rows.nombre === "Fabi"; });
    out.ui = !card.classList.contains("sentRow") && /Fabi · /.test(rr.textContent) && rb.classList.contains("on") && rb.disabled === false;
    // es un paso más: con ISIS + partes + foto vista + recibido, Enviar se habilita y cierra
    const eb = card.querySelector(".enviarBtn");
    out.enviar_exige = eb.disabled === true;
    R.pendRows[77].isis = true; R.pendRows[77].partes = "no"; R.pendRows[77].foto_vista = true; R.pendRefreshEnviar(77);
    out.enviar_habilita = eb.disabled === false;
    // destildar borra quién y cuándo, y vuelve a bloquear Enviar
    window.__calls = []; rb.click(); await wait(30);
    const ud = upds();
    out.destilda = ud.length === 1 && ud[0].vals.gv_recibido_por === null && ud[0].vals.gv_recibido_at === null
      && !rb.classList.contains("on") && eb.disabled === true;
    // Error al guardar -> queda el cuadro con el error
    window.__calls = []; window.__updErr = { message: "boom" };
    const card2 = R.pendCard(Object.assign({}, row, { id: 78 })); rootEl.appendChild(card2);
    card2.querySelector(".pcRecibidoRow .tickBtn").click(); await wait(10);
    const ov2 = rootEl.querySelector(".rcbOverlay");
    ov2.querySelectorAll(".rcbOp")[0].click(); ov2.querySelector(".btnSend").click(); await wait(40);
    out.error_visible = !!rootEl.querySelector(".rcbOverlay") && /boom/.test(ov2.textContent) && R.pendRows[78].sent === false;
    // ---- Foto a posteriori: "Sin foto" se toca, pide foto + quién, persiste y muestra el registro ----
    window.__calls = []; window.__updErr = null;
    const card3 = R.pendCard(Object.assign({}, row, { id: 79, foto_url: null })); rootEl.appendChild(card3);
    const addB = card3.querySelector(".addFoto");
    out.sinFoto_clickeable = !!addB && /agregar/.test(addB.textContent);
    const rt3 = card3.querySelector(".pcRecibidoRow .tickBtn");
    out.sinFoto_noRecibe = rt3.disabled === true && /falta la foto/.test(card3.textContent);
    addB.click(); await wait(10);
    rootEl.querySelectorAll(".rcbOverlay").forEach(function (x, i, a) { if (i < a.length - 1) x.remove(); });
    const ov3 = rootEl.querySelector(".rcbOverlay");
    const ok3 = ov3.querySelector(".btnSend");
    ov3.querySelectorAll(".rcbOp")[1].click();
    out.foto_sinArchivo_bloquea = ok3.disabled === true;
    const fin = ov3.querySelector(".rcbFile");
    const dt = new DataTransfer(); dt.items.add(new File(["x"], "f.jpg", { type: "image/jpeg" })); fin.files = dt.files;
    fin.dispatchEvent(new Event("change"));
    out.foto_habilita = ok3.disabled === false;
    ok3.click(); await wait(40);
    const u3 = upds();
    out.foto_persiste = u3.length === 1 && /^http:\/\/x\/79_/.test(u3[0].vals.foto_url) && u3[0].vals.gv_foto_post_por === "Pablo"
      && !!u3[0].vals.gv_foto_post_at && u3[0].vals.foto_vista === true && !("estado" in u3[0].vals);
    out.foto_ui = !card3.querySelector(".addFoto") && /Agregada después por Pablo/.test(card3.textContent) && !!card3.querySelector(".fotoViewBtn.viewed") && rt3.disabled === false;
    // ---- Histórico: columna Recibió ----
    out.hist_txt = /^Nora · \d\d-\d\d /.test(R.histRecibioTxt({ recPor: "Nora", recAt: "2026-09-25T13:15:00Z" })) && R.histRecibioTxt({ recPor: "" }) === "—";
    return out;
  });
  const bad = Object.keys(r).filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("pend-recibido:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
