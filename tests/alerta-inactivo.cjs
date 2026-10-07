/* v25.79 (Luis) — ALARMA de operario inactivo 5 min + Bajar de racks como tarea abierta.
   v25.90: la alarma es SÓLO de la TV del depósito (tv.html, no Mon. Admin) y sólo la dispara un operario real
   (ni el legajo de prueba ni el supervisor en la vista de operario).
   A) monitor/tv.html: una alerta viva → cartel centrado ~70 % con el nombre; se va si se cierra; suena 15 s y queda 60 s (v27.67).
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
  // v25.90: la alarma va SÓLO en la TV del depósito (tv.html); Mon. Admin (admin.html) no la carga
  const fs = require("fs");
  const nCarga = (f) => fs.readFileSync(path.join(__dirname, "..", "monitor", f), "utf8").split("alerta-inactivo.js").length - 1;
  if (nCarga("tv.html") !== 1) errs.push("tv.html tiene que cargar la alarma una vez");
  // v26.02 PRUEBA TEMPORAL: Mon. Admin la carga UNA vez y SÓLO en modo "prueba" (legajo 1 en el baño)
  const admSrc = fs.readFileSync(path.join(__dirname, "..", "monitor", "admin.html"), "utf8");
  if (nCarga("admin.html") !== 1 || !/window\.GV_ALERTA_MODO = "prueba";<\/script>\n<script src="alerta-inactivo\.js/.test(admSrc))
    errs.push("Mon. Admin (admin.html) sólo puede cargar la alarma en modo prueba");
  if (!/window\.self !== window\.top\) return/.test(fs.readFileSync(path.join(__dirname, "..", "monitor", "alerta-inactivo.js"), "utf8")))
    errs.push("la alarma no puede correr dentro de un iframe (📺 Vista TV del admin)");
  await tv.goto("file://" + path.join(__dirname, "..", "monitor", "tv.html") + "?key=tv", { waitUntil: "domcontentloaded" });
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
  // v27.67 (Thomas): a los 15 s deja de sonar pero el cartel sigue; a los 60 s se va solo
  cerrada = false;
  const t60 = await tv.evaluate(async () => {
    const A = gvAlertaInactivo, on = () => document.getElementById("aiOv").classList.contains("on");
    A._abiertas["9"] = { id: 9, nombre: "Otro", cerrada: false }; A._vistas["9"] = Date.now();
    A.pintar(); const on1 = on();
    A._vistas["9"] = Date.now() - 16000; A.pintar(); const on16 = on(), sir16 = A._sirena();
    A._vistas["9"] = Date.now() - 59000; A.pintar(); const on59 = on();
    A._vistas["9"] = Date.now() - 61000; A.pintar(); const on61 = on();
    return { on1, on16, sir16, on59, on61 };
  });
  r.tvSigue16s = t60.on1 && t60.on16 && !t60.sir16 && t60.on59;
  r.tvSeVaA60s = !t60.on61;
  // ── B y C: el celular ──
  const p = await b.newPage({ viewport: { width: 390, height: 800 } });
  p.on("pageerror", (e) => errs.push("cel: " + e.message));
  const rpcs = [];
  await p.route("**/*.supabase.co/**", (rt) => {
    const u = rt.request().url();
    if (u.includes("Registros_Produccion_Virgilio?select=ts_cliente"))
      return rt.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ ts_cliente: new Date(Date.now() - 6 * 60000).toISOString() }]) });
    if (u.includes("rpc/gv_alerta_inactivo_") || u.includes("rpc/gv_alerta_prueba_bano")) { rpcs.push(u.split("rpc/")[1] + " " + (rt.request().postData() || "")); return rt.fulfill({ status: 200, contentType: "application/json", body: "1" }); }
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
  // D) v25.86: BR se SELECCIONA y arranca con «Enviar» (como RR)
  r.brEnviar = await p.evaluate(async () => {
    closeRkb(); selectOption("RKBM");
    const sel = document.getElementById("selectedBox").textContent === "BR" && !document.getElementById("rkbModal").classList.contains("show");
    await send(); await new Promise(res => setTimeout(res, 300));
    const ok = sel && document.getElementById("rkbModal").classList.contains("show") && getLegajoState("777").racks.active;
    closeRkb(); return ok;
  });
  // E) v25.90: el legajo de prueba 1 NO hace saltar la alarma
  rpcs.length = 0;
  await p.evaluate(async () => {
    window.esOperadorPrueba = window.__esOpOrig; localStorage.removeItem("gv_tm_alerta::1");
    tmStop(); legajoInput.value = "1"; goToOptions(); await new Promise(res => setTimeout(res, 1500));
  });
  r.prueba1NoAvisa = !rpcs.some((x) => x.startsWith("gv_alerta_inactivo_abrir"));
  // F) v25.90: el supervisor mirando la vista de operario tampoco
  rpcs.length = 0;
  r.supNoAvisa = await p.evaluate(async () => {
    try { __identity = { type: "supervisor", email: "x@y" }; } catch (_e) { return false; }
    localStorage.removeItem("gv_tm_alerta::778"); tmStop(); legajoInput.value = "778"; goToOptions();
    await new Promise(res => setTimeout(res, 1500)); return true;
  }) && !rpcs.some((x) => x.startsWith("gv_alerta_inactivo_abrir"));
  // G) v26.02 PRUEBA TEMPORAL (vence 18:40 ART del 01/10): legajo 1 abre / cierra el baño → avisa a Mon. Admin
  const VIGENTE = Date.now() < Date.parse("2026-10-01T18:40:00-03:00");
  rpcs.length = 0;
  await p.evaluate(async () => { try { __identity = null; } catch (_e) {} toggleStartOrEnd("1", "PB"); toggleStartOrEnd("1", "PB");
    toggleStartOrEnd("777", "PB"); toggleStartOrEnd("777", "PB"); await new Promise(res => setTimeout(res, 400)); });
  const pb = rpcs.filter((x) => x.startsWith("gv_alerta_prueba_bano"));
  r.pruebaBanoCel = VIGENTE ? (pb.length === 2 && pb[0].includes('"p_abierto":true') && pb[1].includes('"p_abierto":false')) : pb.length === 0;
  // H) Mon. Admin en modo prueba: prendido mientras el baño sigue abierto (sin el corte de 15 s), se apaga al cerrar
  const adm = await b.newPage({ viewport: { width: 1600, height: 900 } });
  adm.on("pageerror", (e) => errs.push("adm: " + e.message));
  let banoCerrado = false, pidioReal = false;
  await adm.route("**/*.supabase.co/**", (rt) => {
    const u = rt.request().url();
    if (u.includes("rpc/gv_alertas_inactivo_vivas")) { pidioReal = true; return rt.fulfill({ status: 200, contentType: "application/json", body: "[]" }); }
    if (u.includes("rpc/gv_alertas_prueba_vivas"))
      return rt.fulfill({ status: 200, contentType: "application/json",
        body: JSON.stringify([{ id: 31, legajo: "1", nombre: "PRUEBA (legajo 1)", abierta_en: new Date().toISOString(), cerrada: banoCerrado }]) });
    return rt.abort();
  });
  await adm.goto("file://" + path.join(__dirname, "..", "monitor", "admin.html") + "?key=tv", { waitUntil: "domcontentloaded" });
  if (VIGENTE) {
    await adm.waitForFunction(() => { const o = document.getElementById("aiOv"); return o && o.classList.contains("on"); }, null, { timeout: 8000 }).catch(() => {});
    const h = await adm.evaluate(() => {
      const o = document.getElementById("aiOv"); if (!o || !o.classList.contains("on")) return { on: false };
      const A = gvAlertaInactivo; A._vistas["31"] = Date.now() - 60000; A.pintar();
      return { on: true, txt: document.getElementById("aiBox").textContent, sigue: o.classList.contains("on") };
    });
    r.admPruebaMuestra = h.on && /PRUEBA \(legajo 1\)/.test(h.txt || "") && h.sigue;
    banoCerrado = true;
    await adm.evaluate(() => gvAlertaInactivo.leer()); await adm.waitForTimeout(400);
    r.admPruebaSeApaga = await adm.evaluate(() => !document.getElementById("aiOv").classList.contains("on"));
  } else {
    await adm.waitForTimeout(1500);
    r.admPruebaVencida = await adm.evaluate(() => { const o = document.getElementById("aiOv"); return !o || !o.classList.contains("on"); });
  }
  r.admNoLeeAlarmaReal = !pidioReal;
  r.brAbierta = c.abierta; r.brCerrada = c.cerrada; r.brHistorial = c.enHist;
  const pass = Object.values(r).every(Boolean) && errs.length === 0;
  console.log("alerta-inactivo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
