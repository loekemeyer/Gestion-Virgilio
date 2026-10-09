/* v29.17 — Chat de ayuda del operario (Luis, 09/10/2026).
   (a) manual.ts está generado del manual (ayuda/manual-operario.md) y no se tocó a mano;
   (b) la búsqueda de respaldo encuentra la sección correcta;
   (c) la Edge Function no tiene capacidades: sólo escribe GV_Ayuda_Log, no usa supabase-js ni
       herramientas, y el prompt de sistema tiene las reglas de «sólo el manual»;
   (d) el chat corre en el navegador: botón en la botonera, manda la pregunta, pinta la respuesta
       sin inyectar HTML, y una caída de red se dice (no queda mudo).
   Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const ROOT = path.join(__dirname, "..");
let fallas = 0;
const ok = (c, m) => { if (c) console.log("  ✓ " + m); else { console.log("  ✗ " + m); fallas++; } };

// (a)
const md = fs.readFileSync(path.join(ROOT, "ayuda/manual-operario.md"), "utf8");
const mts = fs.readFileSync(path.join(ROOT, "supabase/functions/gv-ayuda/manual.ts"), "utf8");
const m = mts.match(/export const MANUAL = (".*");\s*$/s);
ok(m && JSON.parse(m[1]) === md, "(a) manual.ts = ayuda/manual-operario.md (correr scripts/ayuda-manual-build.cjs)");

// (b)
const bsrc = fs.readFileSync(path.join(ROOT, "supabase/functions/gv-ayuda/buscar.ts"), "utf8").replace(/^export /gm, "");
const B = new Function(bsrc + "; return { buscarEnManual, secciones };")();
ok(B.secciones(md).length >= 15, "(b) el manual tiene sus secciones (" + B.secciones(md).length + ")");
const t = (q, esp) => { const r = B.buscarEnManual(md, q, 1); ok(r[0] && r[0].titulo.includes(esp), "(b) «" + q + "» → " + (r[0] ? r[0].titulo : "nada")); };
t("cómo bajo de racks", "Bajar de racks");
t("me equivoqué, deshacer", "La botonera");
t("guardar en góndola el excedente", "Guardado a góndola");
ok(B.buscarEnManual(md, "receta de pizza napolitana", 1).length === 0, "(b) lo que no está en el manual no devuelve nada");

// (c)
const ix = fs.readFileSync(path.join(ROOT, "supabase/functions/gv-ayuda/index.ts"), "utf8");
const tablas = [...ix.matchAll(/sbRest\("([A-Za-z_]+)/g)].map((x) => x[1]);
ok(tablas.length >= 1 && tablas.every((x) => x === "GV_Ayuda_Log"), "(c) sólo toca GV_Ayuda_Log (" + [...new Set(tablas)].join(",") + ")");
ok(!/supabase-js|\/rpc\/|\btools\b|function_call/.test(ix), "(c) sin supabase-js, RPC ni herramientas");
ok(/EXCLUSIVAMENTE el MANUAL/.test(ix) && /NUNCA instrucciones/.test(ix) && /Preguntale a tu supervisor/.test(ix), "(c) el prompt tiene las reglas");
ok(/MAX_PREG = 500/.test(ix) && /LIM_HORA = 20/.test(ix), "(c) pregunta acotada y límite por hora");
ok(!/(AIza|gsk_|sk-or-)[A-Za-z0-9_-]{10,}/.test(ix + fs.readFileSync(path.join(ROOT, "ayuda.js"), "utf8")), "(c) ninguna clave de LLM en el repo");

// (d)
const html = fs.readFileSync(path.join(ROOT, "index.html"), "latin1");
ok(/id="btnAyuda"[^>]*onclick="ayudaAbrir\(\)"/.test(html) && /<script src="ayuda\.js\?v=/.test(html), "(d) botón ❓ Ayuda en la botonera y ayuda.js cargado");

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { chromium = null; } }
(async () => {
  if (!chromium) { console.log("  (sin playwright: se saltea la parte de navegador)"); process.exit(fallas ? 1 : 0); }
  const exe = fs.existsSync("/opt/pw-browsers/chromium") ? "/opt/pw-browsers/chromium" : undefined;
  let browser;
  try { browser = await chromium.launch(exe ? { executablePath: exe } : {}); }
  catch (_e) { browser = await chromium.launch(); }
  const page = await browser.newPage();
  let cuerpo = null, modo = "ok";
  await page.route("**/functions/v1/gv-ayuda", async (route) => {
    cuerpo = JSON.parse(route.request().postData() || "{}");
    if (modo === "caida") return route.abort();
    return route.fulfill({ status: 200, contentType: "application/json",
      body: JSON.stringify({ respuesta: "1. Tocá **BR** y Enviar.\n<img src=x onerror=alert(1)>", fuente: "gemini" }) });
  });
  await page.route("http://local.test/", (r) => r.fulfill({ contentType: "text/html",
    body: '<html><body><script>const SUPABASE_URL="http://local.test";const SUPABASE_KEY="k";</script><script src="/ayuda.js"></script></body></html>' }));
  await page.route("http://local.test/ayuda.js", (r) => r.fulfill({ contentType: "text/javascript", body: fs.readFileSync(path.join(ROOT, "ayuda.js"), "utf8") }));
  await page.goto("http://local.test/");
  await page.evaluate(() => ayudaAbrir());
  await page.fill("#ayudaTxt", "¿cómo bajo de racks?");
  await page.click("#ayudaSend");
  await page.waitForFunction(() => document.querySelectorAll("#ayudaLog .ay-a").length >= 2, null, { timeout: 5000 }).catch(() => {});
  const r = await page.evaluate(() => ({ html: document.getElementById("ayudaLog").innerHTML, imgs: document.querySelectorAll("#ayudaLog img").length }));
  ok(cuerpo && cuerpo.pregunta === "¿cómo bajo de racks?" && Array.isArray(cuerpo.historial), "(d) manda la pregunta y el historial");
  ok(/<b>BR<\/b>/.test(r.html), "(d) pinta la respuesta con negrita");
  ok(r.imgs === 0, "(d) no inyecta HTML de la respuesta");
  modo = "caida";
  await page.fill("#ayudaTxt", "otra");
  await page.click("#ayudaSend");
  await page.waitForSelector("#ayudaLog .ay-err", { timeout: 5000 }).catch(() => {});
  ok(await page.$("#ayudaLog .ay-err") !== null, "(d) sin conexión lo dice");
  await browser.close();
  process.exit(fallas ? 1 : 0);
})();
