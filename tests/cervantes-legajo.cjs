/* v30.39 (Luis, 14/10): se sacó «Trabajo en Cervantes · entrar con legajo» (era v27.71, hasta que Cervantes tuviera TV).
   Cervantes ya entra con su TV en Registro Producción 3.0. Esta prueba controla que NO vuelva:
     (a) no hay botón de Cervantes en el paso del código de la TV ni paso tvCervStep;
     (b) no existen tvMostrarCervantes / loginCervantesLegajo;
     (c) el código de la TV sigue en pantalla.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
let fail = 0;
const ok = (c, m) => { console.log((c ? "✓ " : "✗ ") + m); if (!c) fail++; };
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 400, height: 800 } });
  // v31.78: el código de la TV se apaga el 17/10; este test mide el flujo viejo con el corte corrido al futuro.
  await p.addInitScript(() => { window.GV_CLAVE_TV_CORTE_TS = 8e15; });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*", (r) => (r.request().url().startsWith("file://") ? r.continue() : r.abort()));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof window.loginWithLegajo === "function", null, { timeout: 15000 }).catch(() => {});
  const r = await p.evaluate(() => ({
    boton: Array.from(document.querySelectorAll("#tvClaveStep button")).some((x) => /Cervantes/.test(x.textContent)),
    paso: !!document.getElementById("tvCervStep"),
    fns: typeof window.tvMostrarCervantes + "/" + typeof window.loginCervantesLegajo,
    clave: !!document.getElementById("tvClaveInput"),
  }));
  ok(!r.boton && !r.paso, "(a) sin botón ni paso de legajo para Cervantes");
  ok(r.fns === "undefined/undefined", "(b) sin tvMostrarCervantes / loginCervantesLegajo (" + r.fns + ")");
  ok(r.clave, "(c) el código de la TV sigue");
  ok(errs.length === 0, "sin errores de página " + JSON.stringify(errs.slice(0, 3)));
  await b.close();
  process.exit(fail ? 1 : 0);
})();
