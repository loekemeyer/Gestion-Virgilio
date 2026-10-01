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
               { cod: "501", description: "Pelador Papa", uxb: 12, active: true, category: "Peladores" }],
  "loke_products": [{ cod: "101", description: "Abrelatas A Manija", uxb: 6 }],
  "sales_item_remap": [{ from_code: "702", to_code: "702E" }],
  "sales_excluded_items": [{ item_code: "COTIZ-2%" }],
  "rpc/get_estadistica_madre_cache": [
    { cod: "505", descripcion: "Pelador Mgo Plástico", familia: "Peladores", uxb: 12, proy_uni_mes: 26434, proy_cajas_mes: 2202.83,
      total_unidades: 52000, meses: { "2026-08": 25000, "2026-09": 27000 }, calculado_at: "2026-10-01T10:00:00Z" },
    { cod: "501", descripcion: "Pelador Papa", familia: "Peladores", uxb: 12, proy_uni_mes: 1200, proy_cajas_mes: 100,
      total_unidades: 2400, meses: { "2026-08": 1100, "2026-09": 1300 }, calculado_at: "2026-10-01T10:00:00Z" }],
  "rpc/get_estadistica_madre_detail": [
    { cod_cliente: "4188", business_name: "Orfali Alfredo Luciano", provincia: "Buenos Aires", boxes: 150, unidades: 1800,
      avg_monthly_units: 1120, ratio: 1.61, origen: "loke" }],
};

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
  await ctx.route("**/*", async (route) => {
    const req = route.request();
    const u = req.url();
    if (u.startsWith(base)) return route.continue();
    for (const [re, local] of VENDOR) {
      if (re.test(u) && /cdn\.jsdelivr|cdnjs|unpkg/.test(u)) {
        return route.fulfill({ status: 200, contentType: "text/javascript", body: fs.readFileSync(path.join(RAIZ, local)) });
      }
    }
    if (u === FN) {
      if (req.method() === "OPTIONS") return route.fulfill({ status: 200, body: "ok" });
      let b = {}; try { b = JSON.parse(req.postData() || "{}"); } catch (_e) {}
      llamadas.push({ path: b.path, args: b.args, auth: req.headers()["authorization"] || "" });
      const d = DATOS[b.path];
      if (!d) return route.fulfill({ status: 403, contentType: "application/json", body: JSON.stringify({ message: "no" }) });
      return route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(d) });
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
    const st = document.getElementById("estMadreStatus");
    out.status = st ? st.textContent : null;
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

  const CARGA = ["products", "loke_products", "sales_item_remap", "sales_excluded_items", "rpc/get_estadistica_madre_cache"];
  const pathsLlamados = llamadas.map((l) => l.path);
  r.cargaCompleta = CARGA.every((p) => pathsLlamados.indexOf(p) >= 0);
  r.soloLista = pathsLlamados.every((p) => CARGA.indexOf(p) >= 0 || p === "rpc/get_estadistica_madre_detail");
  r.todasConToken = llamadas.length > 0 && llamadas.every((l) => l.auth === "Bearer tok-gestion");
  const det = llamadas.find((l) => l.path === "rpc/get_estadistica_madre_detail");
  r.detalleArgs = !!det && det.args && det.args.p_item_code === "505" && det.args.p_ym === "2026-09";
  r.customersLlego = pathsLlamados.indexOf("customers") >= 0;
  r.fugasEmbed = fugasEmbed.length;

  const pass = r.embed && r.loadingOculto && r.loginOculto && r.shell && r.paginaActiva && r.tabla505 && r.tabla501 &&
    r.detalleFilas === 1 && !r.detalleErr && !!r.customersErr && !r.customersLlego &&
    r.cargaCompleta && r.soloLista && r.todasConToken && r.detalleArgs && r.fugasEmbed === 0 && r.sueltoEmbed === false;
  console.log("stk-est-madre-sin-codigo:", JSON.stringify(r), "· llamadas:", pathsLlamados.join(","),
    "· fugas a LK (iframe):", fugasEmbed.length ? fugasEmbed.join(" | ") : "ninguna",
    "· pageerrors:", errs.length ? errs.join("|").slice(0, 300) : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await browser.close();
  server.close();
  process.exit(pass ? 0 : 1);
})();
