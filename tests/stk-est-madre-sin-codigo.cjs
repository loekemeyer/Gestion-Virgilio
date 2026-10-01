/* v25.72 — la Est. Madre de Gestión entra SIN código (Tomás Beviglia, 01/10/2026: "me pide código
   para ver la Est. Madre, que no me lo pida en Gestión Virgilio. La página LK dejala como está").

   Corre el admin espejo DE VERDAD (admin/admin.html?gv_em=1) adentro de un iframe cuyo padre tiene
   window.sbAuth (como Gestión), con la Edge Function gv-est-madre simulada. Chequea:
   A) que no aparezca el login / código OTP y la Est. Madre se dibuje con los datos de la función;
   B) que TODA lectura vaya a gv-est-madre con el JWT de Gestión del padre, y sólo las 5 de la carga;
   C) que NADA salga directo a la base de LK (rest/v1, auth/v1) ni a admin-login-otp;
   D) que el detalle de una celda (rpc/get_estadistica_madre_detail) viaje con sus argumentos;
   E) que una lectura fuera de la lista (customers) se corte sin salir a la red;
   F) que abierto SUELTO (fuera del iframe de Gestión) el modo no se active: ahí manda el login de siempre.
   G) v25.79 (un solo cuadro): que el módulo se baje de la URL ÚNICA de GitHub Pages (no el
      archivo de al lado), y que las filas sean las de Stocks de Gestión (stocks_carga_rapida,
      sin las ocultas vacías), con «Est Madre» en el encabezado y ninguna «Proyección»;
      el dual en dos filas (LK / CH) y el secundario con «→ principal».
   H) v25.81 (switch Cajas / Unidades): en Unidades cada valor es cajas × uxb de Gestión
      (vista_uxb_articulo, clave pública); un artículo sin uxb dice «s/uxb» y no suma al total
      (nunca un 0 inventado), y al volver a Cajas vuelven los números de Stocks.
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
const MIME = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json",
               ".png": "image/png", ".jpg": "image/jpeg", ".svg": "image/svg+xml" };
const LK = "https://kwkclwhmoygunqmlegrg.supabase.co";
const FN = LK + "/functions/v1/gv-est-madre";
const PADRE = '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
  '<script>window.sbAuth = { getAccessToken: async function () { return "tok-gestion"; } };</script>' +
  '<iframe id="fr" src="admin/admin.html?gv_em=1#estadistica-madre" style="width:1400px;height:900px"></iframe>' +
  '</body></html>';
const VENDOR = [
  [/supabase-js/, "vendor/supabase.umd.js"],
  [/xlsx/, "vendor/xlsx.full.min.js"],
  [/chart\.js|chart\.umd/, "vendor/chart.umd.min.js"],
];
const DATOS = {
  "products": [{ cod: "505", description: "Pelador Mgo Plástico", uxb: 12, active: true, category: "Peladores" },
               { cod: "501", description: "Pelador Papa", uxb: 12, active: true, category: "Peladores" },
               { cod: "029", description: "Colador Fideos", uxb: 12, active: true, category: "Coladores" }],
  "loke_products": [{ cod: "101", description: "Abrelatas A Manija", uxb: 6 }],
  "rpc/get_estadistica_madre_mensual": [
    { item: "505", empresa: "lk", meses: { "2026-08": 2100, "2026-09": 2250 } },
    { item: "501", empresa: "lk", meses: { "2026-08": 90, "2026-09": 110 } },
    { item: "437E", empresa: "lk", meses: { "2026-09": 30 } },
    { item: "437E", empresa: "chef", meses: { "2026-09": 12 } },
    { item: "29", empresa: "lk", meses: { "2026-09": 11 } },
    { item: "CARTONERIA", empresa: "lk", meses: { "2026-09": 5 } }],
  "rpc/get_estadistica_madre_detail": [
    { cod_cliente: "4188", business_name: "Orfali Alfredo Luciano", provincia: "Buenos Aires", boxes: 150, unidades: 1800,
      avg_monthly_units: 1120, ratio: 1.61, origen: "loke" }],
};
// Unidades por caja de Gestión: el 501 queda SIN uxb a propósito (tiene que decir «s/uxb»).
const UXB = [{ cod: "505", uxb: 12 }, { cod: "437E", uxb: 24 }, { cod: "029", uxb: 12 }];
// La lista de artículos y la Est Madre: Stocks de Gestión (con la clave pública de Gestión).
const GV = "https://hrxfctzncixxqmpfhskv.supabase.co";
const STOCKS = [
  { cod: "505", cod_base: "505", descripcion: "Pelador Mango Plástico", linea: "LK", familia_principal: "505", es_secundario: false, proy_cajas_mes: 2203, visible_en_stock: true, stock_total: 3654, cajas_pedidas: 599 },
  { cod: "501", cod_base: "501", descripcion: "Pelador Papa", linea: "LK", familia_principal: "501", es_secundario: false, proy_cajas_mes: 1084, visible_en_stock: true, stock_total: 929, cajas_pedidas: 254 },
  { cod: "437E LK", cod_base: "437E", descripcion: "Colador Pasta", linea: "LK", familia_principal: "437E LK", es_secundario: false, proy_cajas_mes: 36, visible_en_stock: true, stock_total: 314, cajas_pedidas: 16 },
  { cod: "437E CH", cod_base: "437E", descripcion: "Colador Pasta", linea: "CH", familia_principal: "437E CH", es_secundario: false, proy_cajas_mes: 6, visible_en_stock: true, stock_total: 14, cajas_pedidas: 1 },
  { cod: "29", cod_base: "29", descripcion: "Colador Fideos", linea: "LK", familia_principal: "437E", es_secundario: true, proy_cajas_mes: 0, visible_en_stock: true, stock_total: 0, cajas_pedidas: 0 },
  { cod: "VASTIDOR", cod_base: "VASTIDOR", descripcion: "", linea: "", familia_principal: "VASTIDOR", es_secundario: false, proy_cajas_mes: 0, visible_en_stock: false, stock_total: 0, cajas_pedidas: 0 },
];

(async () => {
  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split("?")[0]).replace(/^\/+/, "") || "padre.html";
    if (rel === "padre.html") { res.writeHead(200, { "Content-Type": "text/html" }); return res.end(PADRE); }
    const abs = path.join(RAIZ, rel);
    if (!abs.startsWith(RAIZ) || !fs.existsSync(abs) || fs.statSync(abs).isDirectory()) { res.writeHead(404); return res.end("no"); }
    res.writeHead(200, { "Content-Type": MIME[path.extname(abs)] || "application/octet-stream" });
    fs.createReadStream(abs).pipe(res);
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const base = "http://127.0.0.1:" + server.address().port;

  const browser = await chromium.launch();
  const ctx = await browser.newContext({ serviceWorkers: "block" });
  const llamadas = [];   // a gv-est-madre
  const fugas = [];      // directo a LK (rest, auth, admin-login-otp)
  const gvLecturas = []; // a Stocks de Gestión (la lista de artículos)
  const moduloPedido = []; // est-madre.js desde la URL única
  await ctx.route("**/*", async (route) => {
    const req = route.request();
    const u = req.url();
    if (u.startsWith(base)) return route.continue();
    for (const [re, local] of VENDOR) {
      if (re.test(u) && /cdn\.jsdelivr|cdnjs|unpkg/.test(u)) {
        return route.fulfill({ status: 200, contentType: "text/javascript", body: fs.readFileSync(path.join(RAIZ, local)) });
      }
    }
    // El módulo único se baja SIEMPRE de GitHub Pages (también desde el espejo): acá se sirve el del repo.
    if (u.split("?")[0] === "https://loekemeyer.github.io/Gestion-Virgilio/admin/est-madre.js") {
      moduloPedido.push(u);
      return route.fulfill({ status: 200, contentType: "text/javascript", body: fs.readFileSync(path.join(RAIZ, "admin/est-madre.js")) });
    }
    if (u === FN) {
      if (req.method() === "OPTIONS") return route.fulfill({ status: 200, body: "ok" });
      let b = {}; try { b = JSON.parse(req.postData() || "{}"); } catch (_e) {}
      llamadas.push({ path: b.path, args: b.args, auth: req.headers()["authorization"] || "" });
      const d = DATOS[b.path];
      if (!d) return route.fulfill({ status: 403, contentType: "application/json", body: JSON.stringify({ message: "no" }) });
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(d) });
    }
    if (u.startsWith(GV + "/rest/v1/stocks_carga_rapida")) {
      gvLecturas.push({ key: req.headers()["apikey"] || "" });
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(STOCKS),
        headers: { "Access-Control-Allow-Origin": "*" } });
    }
    if (u.startsWith(GV + "/rest/v1/vista_uxb_articulo")) {
      gvLecturas.push({ key: req.headers()["apikey"] || "" });
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(UXB),
        headers: { "Access-Control-Allow-Origin": "*" } });
    }
    if (u.startsWith(LK)) { fugas.push(req.method() + " " + u.replace(LK, "")); return route.abort(); }
    return route.abort();
  });

  const page = await ctx.newPage();
  const errs = [];
  page.on("pageerror", (e) => errs.push(String(e && e.message || e)));
  await page.goto(base + "/padre.html", { waitUntil: "domcontentloaded" });
  const fh = await page.waitForSelector("#fr", { timeout: 15000 });
  const fr = await fh.contentFrame();
  await fr.waitForFunction(() => typeof window.cargarEstadisticaMadre === "function" && document.readyState === "complete", null, { timeout: 30000 });
  await fr.waitForFunction(() => {
    const t = document.getElementById("estMadreTable");
    return t && t.textContent.indexOf("505") >= 0;
  }, null, { timeout: 20000 }).catch(() => {});

  const r = await fr.evaluate(async () => {
    const out = {};
    const vis = (id) => { const e = document.getElementById(id); return !!e && getComputedStyle(e).display !== "none"; };
    out.embed = window.GV_EM_EMBED === true;
    out.loadingOculto = !vis("loadingScreen");
    out.loginOculto = !vis("lkLoginBox");
    out.shell = vis("appShell");
    const pag = document.getElementById("estadistica-madre");
    out.paginaActiva = !!pag && pag.classList.contains("active");
    const t = document.getElementById("estMadreTable");
    out.tabla505 = !!t && t.textContent.indexOf("505") >= 0;
    out.tabla501 = !!t && t.textContent.indexOf("501") >= 0;
    const filas = Array.prototype.map.call(document.querySelectorAll("#estMadreTable tbody tr"), (tr) =>
      Array.prototype.map.call(tr.children, (td) => td.textContent.trim()));
    out.nFilas = filas.length;
    out.cods = filas.map((f) => f[1] + "/" + f[3]).sort().join(",");
    const f437lk = filas.find((f) => f[1] === "437E" && f[3] === "LK");
    const f437ch = filas.find((f) => f[1] === "437E" && f[3] === "CH");
    const f29 = filas.find((f) => f[1] === "029");
    out.dual = !!f437lk && !!f437ch && f437lk[5] === "36" && f437ch[5] === "6";
    out.secundario = !!f29 && /→\s*437E/.test(f29[5]);
    const th = document.querySelector("#estMadreTable thead").textContent;
    out.encabEstMadre = /Est Madre/.test(th);
    out.sinProyeccion = !/royecci/i.test(document.getElementById("estadistica-madre").textContent);
    out.sinCarton = !/CARTONERIA|VASTIDOR/.test(document.getElementById("estMadreTable").textContent);
    out.modulo = !!window.EstMadre && !!document.getElementById("estMadreCss");
    const st = document.getElementById("estMadreStatus");
    out.status = st ? st.textContent : null;
    // H) switch Cajas / Unidades
    const leer = () => Array.prototype.map.call(document.querySelectorAll("#estMadreTable tbody tr"), (tr) =>
      Array.prototype.map.call(tr.children, (td) => td.textContent.trim()));
    const fila = (fs, cod, marca) => fs.find((f) => f[1] === cod && (!marca || f[3] === marca));
    const btnU = document.querySelector('#estMadreUnidadSw button[data-u="uni"]');
    const btnC = document.querySelector('#estMadreUnidadSw button[data-u="caj"]');
    out.switchCajasOn = !!btnC && btnC.classList.contains("on") && !!btnU && !btnU.disabled;
    if (btnU) btnU.click();
    const fu = leer();
    const thU = document.querySelector("#estMadreTable thead").textContent;
    const u505 = fila(fu, "505"), u437 = fila(fu, "437E", "LK"), u501 = fila(fu, "501");
    out.uni = {
      est505: u505 && u505[5], sep505: u505 && u505[6], est437: u437 && u437[5], est501: u501 && u501[5], sep501: u501 && u501[6],
      enc: /u\/mes/.test(thU) && /unidades/.test(thU), on: !!btnU && btnU.classList.contains("on"),
      totEst: (document.querySelector("#estMadreTable thead tr.est-madre-totals-row th.est-madre-th-em") || {}).textContent,
      status: (document.getElementById("estMadreStatus") || {}).textContent || "",
    };
    if (btnC) btnC.click();
    const fc = leer();
    const c437 = fila(fc, "437E", "LK");
    out.vuelveCajas = !!c437 && c437[5] === "36" && /caj\/mes/.test(document.querySelector("#estMadreTable thead").textContent);
    const d = await window.sb.rpc("get_estadistica_madre_detail", { p_item_code: "505", p_ym: "2026-09" });
    out.detalleFilas = d.data ? d.data.length : -1;
    out.detalleErr = d.error ? d.error.message : null;
    const c = await window.sb.from("customers").select("cod_cliente");
    out.customersErr = c.error ? c.error.message : null;
    return out;
  });

  const fugasEmbed = fugas.slice();   // C) antes de abrir la pestaña suelta, que sí usa el login de siempre
  // F) abierto suelto: el modo NO se activa aunque traiga ?gv_em=1
  const suelta = await ctx.newPage();
  suelta.on("pageerror", () => {});
  await suelta.goto(base + "/admin/admin.html?gv_em=1#estadistica-madre", { waitUntil: "domcontentloaded" });
  await suelta.waitForFunction(() => typeof window.GV_EM_EMBED !== "undefined", null, { timeout: 30000 });
  r.sueltoEmbed = await suelta.evaluate(() => window.GV_EM_EMBED);

  const CARGA = ["products", "loke_products", "rpc/get_estadistica_madre_mensual"];
  const pathsLlamados = llamadas.map((l) => l.path);
  r.cargaCompleta = CARGA.every((p) => pathsLlamados.indexOf(p) >= 0);
  r.soloLista = pathsLlamados.every((p) => CARGA.indexOf(p) >= 0 || p === "rpc/get_estadistica_madre_detail");
  r.todasConToken = llamadas.length > 0 && llamadas.every((l) => l.auth === "Bearer tok-gestion");
  const det = llamadas.find((l) => l.path === "rpc/get_estadistica_madre_detail");
  r.detalleArgs = !!det && det.args && det.args.p_item_code === "505" && det.args.p_ym === "2026-09";
  r.customersLlego = pathsLlamados.indexOf("customers") >= 0;
  r.fugasEmbed = fugasEmbed.length;
  r.moduloUnico = moduloPedido.length > 0 && moduloPedido.every((u) => /\?t=\d+$/.test(u));
  r.gvLeido = gvLecturas.length > 0 && gvLecturas.every((l) => /^sb_publishable_/.test(l.key));

  const pass = r.embed && r.loadingOculto && r.loginOculto && r.shell && r.paginaActiva && r.tabla505 && r.tabla501 &&
    r.detalleFilas === 1 && !r.detalleErr && !!r.customersErr && !r.customersLlego &&
    r.cargaCompleta && r.soloLista && r.todasConToken && r.detalleArgs && r.fugasEmbed === 0 && r.sueltoEmbed === false &&
    r.nFilas === 5 && r.dual && r.secundario && r.encabEstMadre && r.sinProyeccion && r.sinCarton && r.modulo && r.gvLeido && r.moduloUnico &&
    r.switchCajasOn && r.uni.on && r.uni.enc && r.uni.est505 === "26.436" && r.uni.sep505 === "27.000" && r.uni.est437 === "864" &&
    r.uni.est501 === "s/uxb" && r.uni.sep501 === "s/uxb" && r.uni.totEst === "27.444" && /1 sin uxb/.test(r.uni.status) && r.vuelveCajas;
  console.log("stk-est-madre-sin-codigo:", JSON.stringify(r), "· llamadas:", pathsLlamados.join(","),
    "· fugas a LK (iframe):", fugasEmbed.length ? fugasEmbed.join(" | ") : "ninguna",
    "· pageerrors:", errs.length ? errs.join("|").slice(0, 300) : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await browser.close();
  server.close();
  process.exit(pass ? 0 : 1);
})();
