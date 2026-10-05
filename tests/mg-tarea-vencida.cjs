/* Regresión v26.56 (Luis, 05/10) — alarma de inactividad con el guardado ABIERTO.
   Isidro (94) dejó el Guardado a Góndola abierto el 02/10 (MGI 15:23 y Terminar Día). El 05/10
   «Enviar» MG vio la tarea «activa», no renovó la hora, y _tmLibre la dio por vencida (> 12 h):
   el celular contó tiempo muerto con el operario adentro del módulo y saltó la alarma de los
   monitores a los 5 min (08:41 y 08:50).
   (A) guardado vencido + «Enviar» → la tarea arranca de nuevo con la hora de ahora y no está libre.
   (B) sigue sin estar libre con el módulo abierto y después de «✓ Guardé este código».
   (C) una tarea vencida no pinta el botón MG en rojo.
   (D) cerrar una vencida (sin volver a abrirla) no mete en el Historial una tarea de días.
   (E) control: una tarea de hoy sigue igual (no se le renueva la hora al reentrar).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const w = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    window.stockMove = async function () { return {}; };
    window.emitGuardadoSesion = function () {};
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return { "502": { cod: "502", desc: "X", a_guardar: 10, terminado: 0 } }; };
    window.ocgFetchCapacidad = async function () { return {}; };
    window.ocgFetchCeldas = async function () { return {}; };
    window.ocgDemanda = async function () { return {}; };
    window.rkbFetchCxM = async function () { return { cxm: {} }; };
    window.gvFetchLugares = async function () { return null; };
    window.trySendOneReport = async function () { return { ok: true }; };
    const TRES_DIAS = 3 * 86400000;
    const vencer = function (leg) { const s = getLegajoState(leg); s.mg = { active: true, ts: Date.now() - TRES_DIAS }; setLegajoState(leg, s); };

    // ===== (A)(B)(C) =====
    localStorage.clear(); legajoInput.value = "94";
    goToOptions(); await w(30);
    vencer("94");
    updateCoreButtonsState();
    out.cSinRojo = !document.querySelector('[data-code="MG"]').classList.contains("pending");
    selectOption("MG"); await send(); await w(30);
    const st = getLegajoState("94");
    out.aHoraNueva = !!(st.mg && st.mg.active && Date.now() - st.mg.ts < 60000);
    out.aNoLibre = _tmLibre("94") === false;
    mgChooserGo("guardar"); await w(500);
    out.bNoLibreAbierto = _tmLibre("94") === false;
    mgSet(0, 3); await w(20);
    await mgGuardarUno(0); await w(500);
    out.bNoLibreTrasGuardar = _tmLibre("94") === false;
    tmStop();

    // ===== (D) cerrar una vencida sin reabrirla: sin renglón de días en el Historial =====
    localStorage.clear(); legajoInput.value = "95";
    vencer("95");
    gvModTareaFin("95", "mg", "MG", "Guardado a Góndola");
    const st2 = getLegajoState("95");
    out.dCerrada = !(st2.mg && st2.mg.active);
    out.dSinHistorial = !readDayHist(getTodayKey(), "95").some((x) => x.opcion === "MG");

    // ===== (E) control: una tarea de HOY no se reinicia al reentrar =====
    localStorage.clear(); legajoInput.value = "96";
    const ts0 = Date.now() - 20 * 60000;
    { const s = getLegajoState("96"); s.mg = { active: true, ts: ts0 }; setLegajoState("96", s); }
    gvModTareaAbrir("96", "mg");
    out.eConservaHora = getLegajoState("96").mg.ts === ts0;
    out.eNoLibre = _tmLibre("96") === false;
    return out;
  });

  let ok = true;
  for (const k of Object.keys(r)) { console.log((r[k] ? "OK   " : "FALLA") + " " + k); if (!r[k]) ok = false; }
  if (errs.length) { console.log("pageerror:", errs.slice(0, 3)); ok = false; }
  await b.close();
  console.log(ok ? "mg-tarea-vencida: OK" : "mg-tarea-vencida: FALLA");
  process.exit(ok ? 0 : 1);
})();
