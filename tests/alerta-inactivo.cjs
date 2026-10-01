/* v25.79 (Luis) — Bajar de racks como tarea abierta. v25.88: la ALARMA de 5 min se SACÓ (candado invertido).
   A) monitor/tv.html: una alerta viva → cartel centrado ~70 % con el nombre; se va si se cierra y a los 15 s.
   B) botonera: a los 5 min de tiempo muerto llama gv_alerta_inactivo_abrir; al registrar algo, _cerrar.
   C) Bajar de racks: abierto = tarea abierta (BR en rojo, tiempo muerto 0); al cerrar va al Historial.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const r = {}; const errs = [];
  // ── A: v25.88 (Luis, 01/10: "saca la alarma") — ningún monitor carga la alarma ──
  const fs = require("fs");
  for (const f of ["tv.html", "admin.html"]) {
    const n = fs.readFileSync(path.join(__dirname, "..", "monitor", f), "utf8").split("alerta-inactivo.js").length - 1;
    if (n !== 0) errs.push(f + " volvió a cargar la alarma (" + n + ")");
  }
  // ── B y C: el celular ──
  const p = await b.newPage({ viewport: { width: 390, height: 800 } });
  p.on("pageerror", (e) => errs.push("cel: " + e.message));
  const rpcs = [];
  await p.route("**/*.supabase.co/**", (rt) => {
    const u = rt.request().url();
    if (u.includes("Registros_Produccion_Virgilio?select=ts_cliente"))
      return rt.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ ts_cliente: new Date(Date.now() - 6 * 60000).toISOString() }]) });
    if (u.includes("rpc/gv_alerta_inactivo_")) { rpcs.push(u.split("rpc/")[1] + " " + (rt.request().postData() || "")); return rt.fulfill({ status: 200, contentType: "application/json", body: "1" }); }
    return rt.abort();
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  await p.evaluate(async () => {
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__esOpOrig = window.esOperadorPrueba; window.esOperadorPrueba = function () { return false; };
    window._enqueueReportRaw = function () {};
    localStorage.removeItem("gv_tm_alerta::777");
    legajoInput.value = "777"; goToOptions(); await new Promise(res => setTimeout(res, 1500));
  });
  r.noAbreA5min = !rpcs.some((x) => x.startsWith("gv_alerta_inactivo_abrir"));
  const c = await p.evaluate(async () => {
    window.stockFetchSaldos = async function () { return {}; }; window.loadArtNombres = async function () {};
    window.rkbFetchCxM = async function () { return { cxm: {}, locs: {} }; }; window.stockFetchArtFactors = async function () { return {}; };
    window.ocgFetchCapacidad = async function () { return {}; };
    await showRacksBajarModal("777"); await new Promise(res => setTimeout(res, 1200));
    const st = getLegajoState("777");
    const abierta = !!(st.racks && st.racks.active) && !_tmLibre("777") &&
      document.querySelector('#row4 [data-code="RKBM"]').classList.contains("pending") &&
      document.getElementById("tmMuertoVal").textContent === "0:00:00";
    closeRkb();
    const st2 = getLegajoState("777");
    const hist = localStorage.getItem(histKey(getTodayKey(), "777")) || "";
    return { abierta, cerrada: !(st2.racks && st2.racks.active) && _tmLibre("777"),
      enHist: hist.indexOf('"RKB"') >= 0 };
  });
  // D) v25.86: BR se SELECCIONA y arranca con «Enviar» (como RR)
  r.brEnviar = await p.evaluate(async () => {
    closeRkb(); selectOption("RKBM");
    const sel = document.getElementById("selectedBox").textContent === "BR" && !document.getElementById("rkbModal").classList.contains("show");
    await send(); await new Promise(res => setTimeout(res, 300));
    const ok = sel && document.getElementById("rkbModal").classList.contains("show") && getLegajoState("777").racks.active;
    closeRkb(); return ok;
  });
  r.brAbierta = c.abierta; r.brCerrada = c.cerrada; r.brHistorial = c.enHist;
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("alerta-inactivo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
