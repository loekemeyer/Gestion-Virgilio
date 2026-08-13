/* Las librerías se sirven desde el repo, no de CDNs de terceros (v10.24).
   Sirve la app por HTTP en localhost (como GitHub Pages — los módulos ES no corren
   bajo file:// por CORS) y BLOQUEA toda salida a internet. Si los globales igual
   aparecen, salieron de vendor/ y no de un CDN.
   Cubre: jsPDF, jspdf-autotable, Chart.js, supabase-js (y con él recepcion.js, que
   es el que se rompía cuando esm.sh fallaba) + Leaflet, que se carga A DEMANDA.
   `xlsx` queda fuera a propósito (ver el comentario en pppLoadXlsx). */
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
const ESPERADOS = [
  "vendor/jspdf.umd.min.js",
  "vendor/jspdf.plugin.autotable.min.js",
  "vendor/chart.umd.min.js",
  "vendor/leaflet.min.js",
  "vendor/leaflet.min.css",
  "vendor/supabase.umd.js",
  "vendor/images/marker-icon.png",
];
const MIME = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript",
               ".css": "text/css", ".png": "image/png", ".json": "application/json" };

(async () => {
  const faltan = ESPERADOS.filter((f) => !fs.existsSync(path.join(RAIZ, f)));

  const server = http.createServer((req, res) => {
    const rel = decodeURIComponent(req.url.split("?")[0]).replace(/^\/+/, "") || "index.html";
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
  const page = await browser.newPage();
  const pageerrors = [];
  const externos = [];
  page.on("pageerror", (e) => pageerrors.push(String(e && e.message || e)));
  // Todo lo que NO sea nuestro server local se ABORTA: si algo dependía de un CDN, se rompe.
  await page.route("**/*", (route) => {
    const u = route.request().url();
    if (u.startsWith(base)) return route.continue();
    externos.push(u);
    return route.abort();
  });

  await page.goto(base + "/index.html");
  await page.waitForFunction(() => document.readyState === "complete");
  // recepcion.js es un MÓDULO: si supabase-js no estuviera, tiraría y esto nunca aparece.
  await page.waitForFunction(() => typeof window.openRecepcionOp === "function", { timeout: 15000 })
           .catch(() => {});

  // Leaflet se baja recién al abrir el mapa de zonas → se dispara su loader a mano.
  const leafletOk = await page.evaluate(async () => {
    if (window.L) return true;
    await new Promise((res, rej) => {
      const c = document.createElement("link"); c.rel = "stylesheet"; c.href = "vendor/leaflet.min.css";
      document.head.appendChild(c);
      const s = document.createElement("script"); s.src = "vendor/leaflet.min.js";
      s.onload = res; s.onerror = () => rej(new Error("leaflet no cargó")); document.head.appendChild(s);
    }).catch(() => {});
    return !!(window.L && typeof window.L.map === "function");
  });

  const g = await page.evaluate(() => ({
    jspdf:     !!(window.jspdf && window.jspdf.jsPDF),
    autotable: !!(window.jspdf && window.jspdf.jsPDF && window.jspdf.jsPDF.API
                  && typeof window.jspdf.jsPDF.API.autoTable === "function"),
    chart:     typeof window.Chart === "function",
    supabase:  !!(window.supabase && typeof window.supabase.createClient === "function"),
    recepcion: typeof window.openRecepcionOp === "function",
  }));

  await browser.close();
  await new Promise((r) => server.close(r));

  // Ningún pedido bloqueado puede haber sido a los CDNs que sacamos.
  const cdnsProhibidos = externos.filter((u) => /cdnjs\.cloudflare|cdn\.jsdelivr|esm\.sh/.test(u));

  const ok = !faltan.length && g.jspdf && g.autotable && g.chart && g.supabase &&
             g.recepcion && leafletOk && !cdnsProhibidos.length && pageerrors.length === 0;

  console.log("vendor-sin-cdn:", JSON.stringify({ globales: g, leaflet: leafletOk,
              faltanArchivos: faltan, cdnsProhibidosPedidos: cdnsProhibidos }),
              "· pageerrors:", pageerrors.length ? pageerrors.join(" | ") : "none",
              ok ? "· ✓ OK" : "· ✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
