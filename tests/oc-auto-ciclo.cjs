/* v21.13 — Luis, 2026-09-22: "OCs. Generacion manual. Si se generan manualmente, que consulte
   cuando retomar el ciclo de generacion automatica en ese momento."

   Lo que se verifica, corriendo la pantalla (no leyendo el código):
   (a) el contador del botón dice el día del ANCLA (`GV_OC_Auto.proxima_auto`), no "el miércoles";
   (b) sin ancla —o si la lectura falla— se cae al miércoles, que es lo que hace el backend;
   (c) generar a mano ABRE el diálogo (si no, el cron vuelve a generar como si nada);
   (d) elegir un día pega contra la RPC `gv_oc_auto_programar` con esa fecha;
   (e) "Dejarlo como está" NO escribe nada;
   (f) sin sesión de Google no escribe y lo dice. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

const hoyArt = new Date(Date.now() - 3 * 36e5).toISOString().slice(0, 10);
const mas = (iso, n) => { const d = new Date(iso + "T00:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const ANCLA = mas(hoyArt, 3);

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1200, height: 900 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.route("**/rest/v1/GV_OC_Auto*", (r) => r.fulfill({
    status: 200, contentType: "application/json",
    body: JSON.stringify([{ proxima_auto: ANCLA, cadencia_dias: 7, motivo: "se generaron a mano", fijado_por: "luis@" }])
  }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async (ancla) => {
    const o = {};
    // (b) primero SIN ancla: tiene que hablar de un miércoles
    _ocgAuto = null;
    const sin = _ocgNextAuto();
    o.sinAnclaEsMiercoles = sin.date.getUTCDay() === 3;
    o.sinAnclaTxt = _ocgAutoEnTxt();

    // (a) con el ancla leída de la base
    await ocgCargarAuto();
    o.anclaLeida = _ocgAuto && _ocgAuto.proxima;
    o.txt = _ocgAutoEnTxt();
    o.nextIso = _ocgNextAuto().iso;

    // (c) GENERAR A MANO de verdad: tiene que abrir el diálogo solo
    const rpc0 = [];
    window.facAuthWriteHeaders = async function () { return { apikey: "x", Authorization: "Bearer x" }; };
    window.fetch = async function (url, opt) {
      rpc0.push({ url: String(url), body: opt && opt.body ? JSON.parse(opt.body) : null });
      return { ok: true, status: 200, text: async () => "[]", json: async () => [] };
    };
    window.confirm = function () { return true; };
    window.ocFetchRows = async function () { return []; };
    window.ocBuildRecep = function () { return {}; };
    window.ocRender = function () {};
    _oc = { view: "gen", gen: { fecha: "2026-09-22", items: [
      { cod: "501", desc: "Abrelatas", prov: "Pettofrezza", falta: 10, max: 100, demanda: 5, stock: 20, proy: 30, uni: 12, ncaja: null }
    ] } };
    await ocgGenerar();
    o.generarPegoOc = rpc0.some((x) => x.url.indexOf("/rpc/gv_oc_generar_pendientes") >= 0);
    o.generarAbreDialogo = !!document.getElementById("ocAutoOv") && document.getElementById("ocAutoOv").classList.contains("show");
    ocAutoCerrar();

    // (c2) el diálogo, ya abierto a mano para mirarlo por dentro
    ocAutoAbrir(7);
    const ov = document.getElementById("ocAutoOv");
    o.abre = !!ov && ov.classList.contains("show");
    o.dice = ov ? ov.textContent : "";
    o.chips = ov ? [...ov.querySelectorAll(".oca-chip")].map((x) => x.textContent.trim()) : [];
    o.fechaPre = _ocAuto.fecha;

    // (d) elegir un día y guardar
    const rpc = [];
    window.facAuthWriteHeaders = async function () { return { apikey: "x", Authorization: "Bearer x" }; };
    window.fetch = async function (url, opt) {
      rpc.push({ url: String(url), body: opt && opt.body ? JSON.parse(opt.body) : null });
      return { ok: true, status: 200, text: async () => "[]" };
    };
    window.supaFetchAllSafe = async function () { return [{ proxima_auto: ancla, cadencia_dias: 7, motivo: "x", fijado_por: "y" }]; };
    ocAutoSetFecha(ancla);
    await ocAutoGuardar();
    o.rpcUrl = (rpc[rpc.length - 1] || {}).url || "";
    o.rpcBody = (rpc[rpc.length - 1] || {}).body || null;
    o.cierraAlGuardar = !document.getElementById("ocAutoOv").classList.contains("show");

    // (e) "Dejarlo como está" no escribe
    const antes = rpc.length;
    ocAutoAbrir(3); ocAutoCerrar();
    o.dejarNoEscribe = rpc.length === antes && !document.getElementById("ocAutoOv").classList.contains("show");

    // (f) sin sesión de Google
    window.facAuthWriteHeaders = async function () { return null; };
    const antes2 = rpc.length;
    ocAutoAbrir(2); ocAutoSetFecha(ancla);
    await ocAutoGuardar();
    o.sinSesionNoEscribe = rpc.length === antes2 && /sesi[óo]n/i.test(document.getElementById("ocAutoOv").textContent);
    ocAutoCerrar();
    return o;
  }, ANCLA);

  const fail = [];
  const eq = (a, b2, q) => { if (String(a) !== String(b2)) fail.push(q + ": " + JSON.stringify(a) + " != " + JSON.stringify(b2)); };

  if (!out.sinAnclaEsMiercoles) fail.push("sin ancla no cae en miércoles (el fallback tiene que ser el ciclo histórico)");
  if (/sola el/.test(out.sinAnclaTxt) === false && !/próxima corrida/.test(out.sinAnclaTxt)) fail.push("el contador sin ancla no dice nada útil: " + out.sinAnclaTxt);
  eq(out.anclaLeida, ANCLA, "lee el ancla de GV_OC_Auto");
  eq(out.nextIso, ANCLA, "el contador apunta al día del ancla");
  if (/miércoles/.test(out.txt)) fail.push("el contador sigue hablando del miércoles con ancla puesta: " + out.txt);

  if (!out.generarPegoOc) fail.push("ocgGenerar no pegó contra gv_oc_generar_pendientes (el fixture quedó mal)");
  if (!out.generarAbreDialogo) fail.push("generar a mano NO abre el diálogo de cuándo retoma: el cron vuelve a generar igual");
  if (!out.abre) fail.push("ocAutoAbrir no muestra el diálogo");
  if (!/vuelva a generarse/i.test(out.dice)) fail.push("el diálogo no pregunta cuándo retoma: " + out.dice.slice(0, 120));
  if (out.chips.length < 3) fail.push("faltan atajos de fecha en el diálogo: " + JSON.stringify(out.chips));
  eq(out.fechaPre, mas(hoyArt, 7), "viene pre-elegido en 7 días");

  if (out.rpcUrl.indexOf("/rpc/gv_oc_auto_programar") < 0) fail.push("no pega contra la RPC gv_oc_auto_programar: " + out.rpcUrl);
  eq(out.rpcBody && out.rpcBody.p_fecha, ANCLA, "manda la fecha elegida");
  if (!out.cierraAlGuardar) fail.push("el diálogo no se cierra al guardar");
  if (!out.dejarNoEscribe) fail.push('"Dejarlo como está" escribió igual');
  if (!out.sinSesionNoEscribe) fail.push("sin sesión de Google escribe igual (o no avisa)");

  if (errs.length) fail.push("errores de página: " + errs.join(" | "));
  await b.close();
  if (fail.length) { console.error("FALLÓ:\n- " + fail.join("\n- ")); process.exit(1); }
  console.log("oc-auto-ciclo OK — contador por ancla (con fallback al miércoles), diálogo tras generar a mano, RPC con la fecha, 'dejarlo como está' y sin sesión.");
})();
