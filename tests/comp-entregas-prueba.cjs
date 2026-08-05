/* Regresión v7.69 — el operador de PRUEBA (legajo 0/1) NO persiste Entregas_Virgilio.
   Un armado de prueba creaba filas en Entregas, y como `_compTandaYaArmada` usa esa tabla como
   señal de "ya fue armada", bloqueaba a un operario REAL de armar la tanda (caso real D06C: 28
   Entregas fantasma del legajo 0 → "La tanda D06C ya fue armada").

   Chequea:
   - esOperadorPrueba()=true  → _compSaveEntregas NO hace POST.
   - esOperadorPrueba()=false → _compSaveEntregas SÍ hace POST a Entregas_Virgilio.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    let posted = [];
    window.fetch = function (url, opt) {
      posted.push({ url: String(url), method: (opt && opt.method) || "GET" });
      return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve([]); } });
    };
    const rows = [{ np: "98156", cod_art: "501", cajas_pedidas: 3, cajas_entregadas: 3, cajas_falto: 0, tanda: "D06C" }];

    // --- CASO A: operador de PRUEBA → NO postea ---
    window.esOperadorPrueba = function () { return true; };
    posted = []; _compSaveEntregas(rows);
    out.prueba_noPost = !posted.some(function (x) { return x.method === "POST" && x.url.indexOf("Entregas_Virgilio") >= 0; });

    // --- CASO B: operador REAL → SÍ postea a Entregas ---
    window.esOperadorPrueba = function () { return false; };
    posted = []; _compSaveEntregas(rows);
    out.real_post = posted.some(function (x) { return x.method === "POST" && x.url.indexOf("Entregas_Virgilio") >= 0; });
    return out;
  });
  const pass = r.prueba_noPost === true && r.real_post === true && errs.length === 0;
  console.log("comp-entregas-prueba:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
