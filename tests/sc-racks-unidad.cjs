/* v29.13 (Luis, 09/10) — Salida a Cervantes sale de GÓNDOLA o de A GUARDAR, nunca de racks (para mandar una
   MC de racks: BR la baja a A guardar y se manda desde ahí). Retira la pestaña Racks de la v29.12. Sale 1 si falla. */
const path = require("path"), fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 390, height: 844 } }); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => {
    const u = r.request().url();
    let body = "[]";
    if (u.indexOf("vista_saldos_stock") >= 0) body = JSON.stringify([{ clave: "505", cod_art: "505", descripcion: "Pelapapas", terminado: 30, a_guardar: 0, racks: 0 }, { clave: "958E", cod_art: "958E", descripcion: "Pincel", terminado: 0, a_guardar: 12, racks: 240 }]);
    r.fulfill({ status: 200, contentType: "application/json", headers: { "Content-Range": "0-1/2" }, body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const sl = ms => new Promise(res => setTimeout(res, ms)); const out = {};
    window.alert = function () {}; window.confirm = function () { return true; };
    const movs = []; window.stockMove = function (rows) { rows.forEach(x => movs.push(x)); return Promise.resolve(); };
    await showCervantesModal("237"); await sl(300);
    const q = s => document.querySelectorAll("#scBody " + s);
    const tabs = Array.from(q(".sc-tab")).map(x => x.textContent);
    out.pestanas = tabs.length === 2 && /Góndola/.test(tabs[0]) && /A guardar/.test(tabs[1]) && !tabs.some(t => /Racks/.test(t));
    out.gondola = _sc.tab === "gondola" && q(".sc-row").length === 1 && /505/.test(document.getElementById("scBody").textContent);
    scSet(0, 3);
    scTab("aguardar"); await sl(50);
    out.aguardar = q(".sc-row").length === 1 && /958E/.test(document.getElementById("scBody").textContent) && /Bajar de racks/.test(document.getElementById("scBody").textContent);
    scSet(0, 99); out.tope = _sc.ag[0].sacar === 12;
    out.total = scTotCajas() === 15;
    scConfirmar(); await sl(50);
    const g = movs.find(m => m.cod_art === "505"), a = movs.find(m => m.cod_art === "958E");
    out.movGondola = !!g && g.deposito === "terminado" && g.delta === -3 && g.tipo === "salida_cervantes";
    out.movAguardar = !!a && a.deposito === "a_guardar" && a.delta === -12 && a.tipo === "salida_cervantes";
    out.sinRacks = !movs.some(m => /racks/.test(m.deposito));
    return out;
  });
  r.sinCodigoRacks = !/scFetchRacks|scRkCajas|deposito: dep, delta: -cj/.test(src);
  const malos = Object.keys(r).filter(k => !r[k]);
  const pass = !malos.length && errs.length === 0;
  console.log("sc-racks-unidad:", malos.length ? "fallan " + malos.join(", ") : Object.keys(r).length + " chequeos", "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
