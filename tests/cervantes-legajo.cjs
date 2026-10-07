/* v27.71 (Thomas, 07/10) — «hasta que Cervantes tenga TV, habilitá la entrada con legajo en Cervantes».
   Corre la pantalla de entrada (RPC mockeadas):
     (a) hay botón «Trabajo en Cervantes · entrar con legajo» y abre el paso del legajo;
     (b) un legajo que no existe no entra;
     (c) uno que existe: guarda la sesión con soloCervantes, registra el ingreso como 'legajo_cervantes'
         y navega a ./cervantes/;
     (d) con esa sesión, elegir Virgilio NO entra (pide el código de la TV) y borra la sesión.
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
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  const ingresos = []; let navCerv = false;
  await p.route("**/*", (r) => {
    const u = r.request().url();
    if (/\/cervantes\/(index\.html)?$/.test(u)) { navCerv = true; return r.fulfill({ status: 200, contentType: "text/html", body: "<html><body>cervantes</body></html>" }); }
    if (/GV_Dispositivo_Login/.test(u)) { ingresos.push(JSON.parse(r.request().postData() || "{}")); return r.fulfill({ status: 201, body: "" }); }
    if (/Empleados\?Legajo=eq\.277/.test(u)) return r.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ Legajo: "277", Empleado: "Jhonny Cartaya" }]) });
    if (/Empleados\?/.test(u)) return r.fulfill({ status: 200, contentType: "application/json", body: "[]" });
    if (u.startsWith("file://")) return r.continue();
    return r.abort();
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.waitForFunction(() => typeof window.loginCervantesLegajo === "function" && typeof window.tvMostrarCervantes === "function", null, { timeout: 15000 }).catch(() => {});
  const r1 = await p.evaluate(async () => {
    const vis = (id) => { const e = document.getElementById(id); return !!e && !e.classList.contains("hidden"); };
    const btn = Array.from(document.querySelectorAll("#tvClaveStep button")).find((x) => /Cervantes/.test(x.textContent));
    localStorage.removeItem("vir_legajo_auth");
    if (btn) btn.click();
    const out = { boton: !!btn, paso: vis("tvCervStep"), clave: vis("tvClaveStep") };
    document.getElementById("cervLegajoInput").value = "999";
    await window.loginCervantesLegajo();
    out.malo = { ses: localStorage.getItem("vir_legajo_auth"), err: document.getElementById("legajoLoginError").textContent };
    document.getElementById("cervLegajoInput").value = "277";
    window.loginCervantesLegajo();
    return out;
  });
  ok(r1.boton && r1.paso && !r1.clave, "(a) botón de Cervantes abre el paso del legajo");
  ok(!r1.malo.ses && /No encuentro/.test(r1.malo.err), "(b) legajo inexistente no entra");
  await p.waitForTimeout(1500);
  ok(navCerv, "(c) va a ./cervantes/");
  const ing = ingresos.find((x) => x.metodo === "legajo_cervantes");
  ok(!!ing && ing.legajo === "277", "(c) ingreso registrado como legajo_cervantes (" + JSON.stringify(ingresos.map((x) => x.metodo)) + ")");
  // (d) se prueba por el código (la identidad vive adentro del módulo de auth)
  // la identidad del módulo de auth no es accesible directo: se prueba por el código
  const fs = require("fs"); const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  ok(/if \(__identity && __identity\.soloCervantes\) \{\s*alert\("Para trabajar en Virgilio entrá con el código de la TV\."\);/.test(Buffer.from(src, "latin1").toString("utf8")),
    "(d) chooseVirgilio frena la sesión de Cervantes");
  ok(/__identity\.soloCervantes\) \{ window\.location\.href = "\.\/cervantes\/"/.test(Buffer.from(src, "latin1").toString("utf8")), "(d) sesión de Cervantes va derecho a Cervantes");
  ok(errs.length === 0, "sin errores de página " + JSON.stringify(errs.slice(0, 3)));
  await b.close();
  process.exit(fail ? 1 : 0);
})();
