/* v25.65 — pestaña «📈 Est. Madre» en Stock y Compras (pedido del usuario, 01/10/2026:
   "quiero agregar una pestaña … que se llame EST. MADRE y vaya primera … que funcione como la
   Est Madre de pagina-lk-copia. quiero que sean exactamente iguales").

   No es una copia del código: es la MISMA pantalla del admin espejo (admin/admin.html
   #estadistica-madre) en un iframe. Chequea, sirviendo la app por HTTP (file:// no deja tocar el
   documento del iframe) y con el admin reemplazado por un stub:
   1) que la pestaña sea la PRIMERA,
   2) que al abrirla #stkBody se oculte y el iframe apunte a admin/admin.html#estadistica-madre,
   3) que deje el puente de sesión (lk_bridge_vjwt) ANTES de cargar el admin,
   4) que adentro del iframe se oculte el menú lateral del admin,
   5) que un re-render (realtime, filtros) NO recargue el iframe,
   6) que al ir a otra pestaña vuelva #stkBody y al volver sea el MISMO iframe, sin recargar.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const http = require("http");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const RAIZ = path.resolve(__dirname, "..");
const MIME = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
               ".css": "text/css", ".png": "image/png", ".json": "application/json" };
const STUB_ADMIN = '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
  '<div class="app-shell"><aside class="sidebar" id="sb">menu</aside>' +
  '<main class="main-content"><section class="page active" id="estadistica-madre">EM</section></main></div>' +
  '<script>parent.__emLoads = (parent.__emLoads || 0) + 1;' +
  'parent.__emHash = location.hash; parent.__emTok = sessionStorage.getItem("lk_bridge_vjwt");</script>' +
  '</body></html>';

(async () => {
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split("?")[0]).replace(/^\/+/, "") || "index.html";
    if (rel === "admin/admin.html") { res.writeHead(200, { "Content-Type": "text/html" }); return res.end(STUB_ADMIN); }
    const abs = path.join(RAIZ, rel);
    if (!abs.startsWith(RAIZ) || !fs.existsSync(abs) || fs.statSync(abs).isDirectory()) {
      res.writeHead(404); return res.end("no");
    }
    res.writeHead(200, { "Content-Type": MIME[path.extname(abs)] || "application/octet-stream" });
    fs.createReadStream(abs).pipe(res);
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;

  const browser = await chromium.launch();
  const ctx = await browser.newContext({ serviceWorkers: "block" });
  const page = await ctx.newPage();
  const errs = [];
  page.on("pageerror", (e) => errs.push(String(e && e.message || e)));
  await page.route("**/*", (route) => {
    const u = route.request().url();
    return u.startsWith(base) ? route.continue() : route.abort();
  });
  await page.goto(base + "/index.html", { waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => typeof window.stkTab === "function" && typeof window._stkEmMostrar === "function", { timeout: 20000 });

  const r = await page.evaluate(async () => {
    const out = {};
    const espera = (fn, ms) => new Promise((res) => {
      const t0 = Date.now();
      (function vuelta() { if (fn() || Date.now() - t0 > ms) return res(); setTimeout(vuelta, 50); })();
    });
    window.sbAuth = Object.assign({}, window.sbAuth || {}, { getAccessToken: async () => "tok-vir" });
    try { sessionStorage.removeItem("lk_bridge_vjwt"); } catch (_e) {}
    const ov = document.createElement("div"); ov.id = "stockAdminOverlay";
    ov.innerHTML = '<div class="stk-card"><div class="stk-tabs" id="stkTabs"></div><div class="stk-body" id="stkBody"></div></div>';
    document.body.appendChild(ov);
    window.stkBodyAjustes = function () { return '<p id="ajx">ajustes</p>'; };
    _stk = { tab: "stocks", soloConteo: false, filtro: "", openArt: null, viewRows: [] };

    stkTab("estmadre");
    const tabs = Array.prototype.map.call(document.querySelectorAll("#stkTabs .stk-tab"), (b) => b.textContent.trim());
    out.primera = tabs[0];
    out.marcada = !!document.querySelector("#stkTabs .stk-tab.on") && document.querySelector("#stkTabs .stk-tab.on").textContent.indexOf("Est. Madre") >= 0;
    out.bodyOculto = document.getElementById("stkBody").style.display === "none";
    const fr = document.getElementById("stkEmFrame");
    await espera(() => window.__emLoads >= 1 && fr.contentDocument && fr.contentDocument.getElementById("stkEmCss"), 8000);
    out.src = fr ? fr.getAttribute("src") : null;
    out.hash = window.__emHash;
    out.tokAntes = window.__emTok;
    out.sinMenu = !!fr.contentDocument && fr.contentWindow.getComputedStyle(fr.contentDocument.getElementById("sb")).display === "none";
    out.cargando = !document.getElementById("stkEmCarga");

    // re-render (realtime / filtros): mismo iframe, sin recargar
    stkRender();
    await new Promise((res) => setTimeout(res, 300));
    out.mismoTrasRender = document.getElementById("stkEmFrame") === fr && window.__emLoads === 1;

    // otra pestaña: vuelve el body, se esconde el iframe
    stkTab("ajustes");
    out.otraTabBody = document.getElementById("stkBody").style.display === "" && !!document.getElementById("ajx");
    out.otraTabHost = document.getElementById("stkEmHost").style.display === "none";

    // de vuelta: el MISMO iframe, sin recargar
    stkTab("estmadre");
    await new Promise((res) => setTimeout(res, 300));
    out.vuelveMismo = document.getElementById("stkEmFrame") === fr && window.__emLoads === 1 &&
      document.getElementById("stkEmHost").style.display === "" && document.getElementById("stkBody").style.display === "none";
    return out;
  });

  const pass = /Est\. Madre/.test(r.primera || "") && r.marcada && r.bodyOculto &&
    r.src === "admin/admin.html#estadistica-madre" && r.hash === "#estadistica-madre" &&
    r.tokAntes === "tok-vir" && r.sinMenu && r.cargando &&
    r.mismoTrasRender && r.otraTabBody && r.otraTabHost && r.vuelveMismo && errs.length === 0;
  console.log("stk-est-madre-tab:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await browser.close();
  server.close();
  process.exit(pass ? 0 : 1);
})();
