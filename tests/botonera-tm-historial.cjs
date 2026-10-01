/* v25.65 (Luis) — en la botonera: «Tiempo muerto» del día (jornada − prod − mov − no prod de
   gv_monitor_horas_operario, corre solo sin tarea abierta, "—" si no se pudo leer), botón
   «Historial de tareas» (el mismo Resumen de hoy, que vuelve a su lugar al cerrar) y el
   Deshacer adentro de la botonera. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 390, height: 800 } }); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  let falla = false;
  await p.route("**/*.supabase.co/**", (r) => {
    const u = r.request().url();
    if (u.includes("gv_monitor_horas_operario?")) {
      if (falla) return r.fulfill({ status: 500, body: "{}" });
      return r.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify([{ hs_prod: "2.00", hs_mov: "0.50", hs_noprod: "0.50", hs_total: "4.00" }]) });
    }
    return r.abort();
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; const sl = ms => new Promise(res => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    legajoInput.value = "999";
    goToOptions();
    await sl(400);
    const val = () => document.getElementById("tmMuertoVal").textContent;
    out.muertoUnaHora = /^1:00:0\d$/.test(val());          // 4 − 2 − 0,5 − 0,5 = 1 h
    // con picking abierto no corre
    const st = getLegajoState("999"); st.picking = { active: true }; setLegajoState("999", st);
    const a = val(); await sl(1200); out.noCorreConTarea = val() === a;
    st.picking = { active: false }; setLegajoState("999", st);
    // el contador y el botón están dentro de la botonera, arriba de los botones
    const bar = document.getElementById("tmBar");
    out.enBotonera = !!bar && document.getElementById("optionsScreen").contains(bar) &&
      bar.getBoundingClientRect().top < document.getElementById("row1").getBoundingClientRect().top;
    out.undoEnBotonera = document.getElementById("optionsScreen").contains(document.getElementById("undoBanner"));
    out.sinScrollHoriz = document.documentElement.scrollWidth <= window.innerWidth;
    // historial: se abre con el resumen y vuelve a su lugar
    histTareasAbrir();
    const cont = document.getElementById("legajoHistoryContent");
    out.histAbre = !document.getElementById("histTareasOv").classList.contains("hidden") &&
      document.getElementById("histTareasBody").contains(cont);
    histTareasCerrar();
    out.histVuelve = document.getElementById("legajoHistorySpace").contains(cont) &&
      document.getElementById("histTareasOv").classList.contains("hidden");
    return out;
  });
  falla = true;
  r.lecturaRotaGuion = await p.evaluate(async () => { await tmLeer(); return document.getElementById("tmMuertoVal").textContent === "—"; });
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("botonera-tm-historial:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
