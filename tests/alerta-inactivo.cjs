/* v25.79 (Luis) — ALARMA de operario inactivo 5 min + Bajar de racks como tarea abierta.
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
  // ── A: la TV ──
  const tv = await b.newPage({ viewport: { width: 1600, height: 900 } });
  tv.on("pageerror", (e) => errs.push("tv: " + e.message));
  let cerrada = false;
  await tv.route("**/*.supabase.co/**", (rt) => {
    const u = rt.request().url();
    if (u.includes("rpc/gv_alertas_inactivo_vivas"))
      return rt.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify([{ id: 7, legajo: "104", nombre: "Jhonny Moncayo Pérez", abierta_en: new Date().toISOString(), cerrada: cerrada }]) });
    return rt.abort();
  });
  await tv.goto("file://" + path.join(__dirname, "..", "monitor", "tv.html"), { waitUntil: "domcontentloaded" });
  await tv.waitForFunction(() => { const o = document.getElementById("aiOv"); return o && o.classList.contains("on"); }, null, { timeout: 8000 }).catch(() => {});
  const a = await tv.evaluate(() => {
    const o = document.getElementById("aiOv"), bx = document.getElementById("aiBox");
    if (!o || !bx) return { on: false };
    const q = bx.getBoundingClientRect();
    return { on: o.classList.contains("on"), txt: bx.textContent,
      ancho: q.width / innerWidth, alto: q.height / innerHeight,
      centrado: Math.abs(q.left + q.width / 2 - innerWidth / 2) < 4 && Math.abs(q.top + q.height / 2 - innerHeight / 2) < 4 };
  });
  r.tvMuestra = a.on && /Jhonny Moncayo/.test(a.txt || "") && /más de 5 minutos inactivo/.test(a.txt || "");
  r.tv70 = Math.abs(a.ancho - 0.7) < 0.02 && Math.abs(a.alto - 0.7) < 0.02 && a.centrado;
  cerrada = true;
  await tv.evaluate(() => gvAlertaInactivo.leer());
  await tv.waitForTimeout(400);
  r.tvSeVaAlCerrar = await tv.evaluate(() => !document.getElementById("aiOv").classList.contains("on"));
  // a los 15 s se va solo (corremos el reloj de la alerta)
  cerrada = false;
  r.tvSeVaA15s = await tv.evaluate(async () => {
    const A = gvAlertaInactivo; A._abiertas["9"] = { id: 9, nombre: "Otro", cerrada: false }; A._vistas["9"] = Date.now();
    A.pintar(); const on1 = document.getElementById("aiOv").classList.contains("on");
    A._vistas["9"] = Date.now() - 16000; A.pintar();
    return on1 && !document.getElementById("aiOv").classList.contains("on");
  });
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
    window.esOperadorPrueba = function () { return false; };
    window._enqueueReportRaw = function () {};
    localStorage.removeItem("gv_tm_alerta::777");
    legajoInput.value = "777"; goToOptions(); await new Promise(res => setTimeout(res, 1500));
  });
  r.abreA5min = rpcs.some((x) => x.startsWith("gv_alerta_inactivo_abrir") && x.includes('"777"'));
  const n1 = rpcs.length;
  await p.evaluate(async () => { await new Promise(res => setTimeout(res, 1500)); });
  r.abreUnaVez = rpcs.filter((x) => x.startsWith("gv_alerta_inactivo_abrir")).length === 1 && rpcs.length === n1;
  await p.evaluate(async () => { enqueueReport({ legajo: "777", opcion: "RT", ts: Date.now(), id: "t_" + Date.now() }); await new Promise(res => setTimeout(res, 300)); });
  r.cierraAlRegistrar = rpcs.some((x) => x.startsWith("gv_alerta_inactivo_cerrar") && x.includes('"777"'));
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
  r.brAbierta = c.abierta; r.brCerrada = c.cerrada; r.brHistorial = c.enHist;
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("alerta-inactivo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
