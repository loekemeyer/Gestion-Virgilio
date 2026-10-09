/* v29.05 (Luis, 09/10) — Salida a Cervantes (Insumos y Productos Movimiento) con pestañas GÓNDOLA y RACKS.
   En racks se manda desde una posición y se elige la unidad: caja o MC (cajas por master). El movimiento
   va en cajas, depósito racks, con la posición en `ubicacion`. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 390, height: 844 } }); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => {
    const u = r.request().url();
    let body = "[]";
    if (u.indexOf("vista_saldos_stock") >= 0) body = JSON.stringify([{ clave: "505", cod_art: "505", descripcion: "Pelapapas", terminado: 30, racks: 0 }, { clave: "529E", cod_art: "529E", descripcion: "Espumadera", terminado: 0, racks: 540 }]);
    else if (u.indexOf("Racks_Planimetria") >= 0) body = JSON.stringify([{ emp: "LK", sector: "Y26", cod_art: "529E", innercajas: 540 }, { emp: "LK", sector: "R27", cod_art: "505I", innercajas: 50 }]);
    else if (u.indexOf("GV_Rack_CxM") >= 0) body = JSON.stringify([{ cod: "529E", cxm: 12 }]);
    r.fulfill({ status: 200, contentType: "application/json", headers: { "Content-Range": "0-1/2" }, body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const sl = ms => new Promise(res => setTimeout(res, ms)); const out = {};
    window.alert = function () {}; window.confirm = function () { return true; };
    const movs = []; window.stockMove = function (rows) { rows.forEach(x => movs.push(x)); return Promise.resolve(); };
    await showCervantesModal("237"); await sl(300);
    const q = s => document.querySelectorAll("#scBody " + s);
    out.dosPestanas = q(".sc-tab").length === 2 && /Góndola/.test(q(".sc-tab")[0].textContent) && /Racks/.test(q(".sc-tab")[1].textContent);
    out.abreGondola = !!_sc && _sc.tab === "gondola" && q(".sc-row").length === 1;
    scSet(0, 3);
    scTab("racks"); await sl(50);
    out.racksPosiciones = q(".sc-row").length === 2 && /Y26/.test(document.getElementById("scBody").textContent);
    const i529 = _sc.rk.findIndex(x => x.cod === "529E"), i505 = _sc.rk.findIndex(x => x.cod === "505I");
    scRkUnidad(i505, "mc"); out.sinMasterNoMC = _sc.rk[i505].unidad === "caja";
    scRkUnidad(i529, "mc"); scRkSet(i529, 2); await sl(30);
    out.mcEnCajas = scRkCajas(_sc.rk[i529]) === 24 && /= 24 cajas/.test(document.getElementById("scBody").textContent);
    scRkSet(i529, 999); out.topeMC = _sc.rk[i529].sacar === 45;
    scRkSet(i529, 2);
    scRkUnidad(i505, "caja"); scRkSet(i505, 5);
    out.total = scTotCajas() === 3 + 24 + 5;
    scConfirmar(); await sl(50);
    const g = movs.find(m => m.deposito === "terminado"), m1 = movs.find(m => m.cod_art === "529E"), m2 = movs.find(m => m.cod_art === "505I");
    out.movGondola = !!g && g.delta === -3 && g.tipo === "salida_cervantes";
    out.movRackMC = !!m1 && m1.deposito === "racks" && m1.delta === -24 && m1.ubicacion === "Y26" && m1.tipo === "salida_cervantes";
    await sl(0); out.movRackCaja = !!m2 && m2.delta === -5 && m2.ubicacion === "R27";
    return out;
  });
  const malos = Object.keys(r).filter(k => !r[k]);
  const pass = !malos.length && errs.length === 0;
  console.log("sc-racks-unidad:", malos.length ? "fallan " + malos.join(", ") : Object.keys(r).length + " chequeos", "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
