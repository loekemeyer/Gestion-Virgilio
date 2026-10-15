/* v31.18 (Luis, 15/10) — Stock → 📦 Empaque: carga inner × master / unidades × inner / unidades × master
   (o sin master; v31.20: sin inner ya no, es insumo a reenvasar) y guarda en la canónica con gv_cxm_guardar (sesión de supervisor).
   Verifica: (a) pendientes primero, con su motivo; (b) con dos datos sale el tercero; (c) un importado que entra como insumo
   muestra «insumo · reenvasa» y no hay tilde de sin inner; (d) si no cierra, avisa y NO llama a la RPC; (e) Guardar manda los 3 datos + flags a
   gv_cxm_guardar con la cabecera de gvWriteHdr y relee la fila; (f) la solapa existe en Stock. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}, alerts = [], posts = [];
    window.alert = function (m) { alerts.push(String(m)); };
    window.stkRender = function () {};
    window.gvWriteHdr = async function () { return { "x-sup": "1", "Content-Type": "application/json" }; };
    const filas = [
      { cod: "513", descripcion: "Pelador", racks: 733, a_guardar: 0, cxm: null, uni_x_inner: null, uni_x_master: null, sin_inner: false, sin_master: false, pendiente: "sin dato", sugerido_uni_x_inner: 12 },
      { cod: "712E", descripcion: "Pelador CH", racks: 444, a_guardar: 0, cxm: 12, uni_x_inner: null, uni_x_master: null, sin_inner: false, sin_master: false, pendiente: "no coincide con importación", iv_uni_master: 288, iv_uni_inner: 12 },
      { cod: "440E", descripcion: "Colador", racks: 528, a_guardar: 0, cxm: 3, uni_x_inner: null, uni_x_master: null, sin_inner: false, sin_master: false, pendiente: "incompleto", iv_uni_master: 24, iv_uni_inner: 0, importa_como_insumo: true },
      { cod: "598E", descripcion: "Pelador negro", racks: 1440, a_guardar: 0, cxm: 12, uni_x_inner: 12, uni_x_master: 144, sin_inner: false, sin_master: false, pendiente: null }
    ];
    window.supaFetchAllSafe = async function (url, q) { if (/cod=eq\.513/.test(q)) return [Object.assign({}, filas[0], { cxm: 12, uni_x_inner: 12, uni_x_master: 144, pendiente: null })]; return filas; };
    window.fetch = async function (url, o) { posts.push({ url: url, o: o }); return { ok: true, status: 200, json: async function () { return { ok: true }; } }; };
    _stk = { tab: "empaque", filtro: "" };
    await stkEmpLoad();
    let h = stkBodyEmpaque();
    out.a = h.indexOf("712E") < h.indexOf("513") && !/598E/.test(h) && /no coincide con importación/.test(h);
    empSet("513", "ui", "12"); empSet("513", "um", "144");
    out.b = _empVal(_stk.emp[0]).cxm === 12;
    h = stkBodyEmpaque();
    out.c = /insumo · reenvasa/.test(h) && !/'si'/.test(h) && !/Sin<br>inner/.test(h);
    empSet("598E", "um", "100");
    await empGuardar("598E");
    out.d = posts.length === 0 && alerts.some(function (m) { return /no cierra/.test(m); });
    await empGuardar("513");
    const body = posts[0] ? JSON.parse(posts[0].o.body) : {};
    out.e = posts.length === 1 && /rpc\/gv_cxm_guardar$/.test(posts[0].url) && posts[0].o.headers["x-sup"] === "1" &&
      body.p_cod === "513" && body.p_cxm === 12 && body.p_uni_x_inner === 12 && body.p_uni_x_master === 144 && body.p_sin_inner === false &&
      _stk.emp[0].pendiente === null && !_stk.empEd["513"];
    out.f = typeof stkBodyEmpaque === "function";
    return out;
  });
  const src = require("fs").readFileSync(path.join(__dirname, "..", "index.html")).toString("utf8");
  r.f = r.f && /\["empaque", "📦 Empaque"\]/.test(src) && /_stk\.tab === "empaque" \? stkBodyEmpaque\(\)/.test(src);
  const bad = Object.keys(r).filter((k) => r[k] !== true);
  const pass = !bad.length && !errs.length;
  console.log("stk-empaque:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
