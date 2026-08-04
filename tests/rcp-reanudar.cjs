/* Test de regresión (v7.09) — RECEPCIÓN: reanudar una carga a medio hacer.

   Si el operario arranca una recepción y se va para atrás / cierra la pantalla, el
   estado NO se pierde: queda un borrador en localStorage por legajo+día y en
   "Resumen de hoy" aparece el botón "▶ Reanudar" que la reabre EN EL MISMO PASO.

   Igual que rcp-oc.cjs, `recepcion.js` se carga con el import de supabase-js
   parcheado por un cliente falso. Verifica:
   - al salir con ✕ Salir queda el borrador (tallerista, línea, remito y cajas) y se
     avisa a Producción (window.onRecepcionDraftChange),
   - window.recepcionDraftInfo resume bien (nombre, línea, remito, códigos, cajas),
   - reanudarRecepcionOp restaura el estado y vuelve al MISMO paso (articulos),
   - el borrador es por legajo+día (otro legajo no ve el de este) y los de días
     viejos se limpian solos,
   - empezar una recepción NUEVA (openRecepcionOp) borra el borrador anterior,
   - enviar la recepción borra el borrador,
   - el supervisor (menú de Administración, sin legajo) NO deja borrador.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

const root = path.join(__dirname, "..");
const src = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");

const FAKE_CLIENT = `
window.__ins = [];
function __q(table) {
  const o = {};
  ["select","gte","lte","eq","neq","in","not","or","ilike","order","limit","single","update","delete"]
    .forEach(function (m) { o[m] = function () { return o; }; });
  o.insert = function (rows) { window.__ins.push({ table: table, rows: rows }); return o; };
  o.then = function (res, rej) { return Promise.resolve({ data: [], error: null }).then(res, rej); };
  return o;
}
const createClient = function () {
  return {
    from: __q,
    rpc: function () { return Promise.resolve({ data: null, error: null }); },
    auth: {
      getSession: function () { return Promise.resolve({ data: { session: { fake: true } } }); },
      signInAnonymously: function () { return Promise.resolve({ data: { session: { fake: true } }, error: null }); }
    }
  };
};
`;

const patched = src.replace(/^import\s+\{[^}]*\}\s+from\s+"[^"]*";\s*$/m, FAKE_CLIENT) + `
window.__rcp = { opState: opState, RECP: RECP, closeOp: closeOp, renderArticulos: renderArticulos,
  drawArticulosGrid: drawArticulosGrid, opEnviar: opEnviar, renderResumen: renderResumen,
  rcpDraftLoad: rcpDraftLoad, el: { page: opPage, body: opBody } };
`;

if (patched.indexOf("esm.sh") >= 0) { console.error("rcp-reanudar: no pude parchear el import."); process.exit(1); }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  // Origen http REAL (no about:blank/data:) porque el borrador vive en localStorage
  // y los orígenes opacos lo bloquean. Se sirve con route(), sin levantar servidor.
  const html = '<!doctype html><meta charset="utf-8"><body><script type="module">' + patched + "<\/script></body>";
  await p.route("http://rcp.test/**", (route) => route.fulfill({ status: 200, contentType: "text/html; charset=utf-8", body: html }));
  await p.goto("http://rcp.test/");
  await p.waitForFunction(() => !!window.__rcp, null, { timeout: 10000 });

  const r = await p.evaluate(async () => {
    const R = window.__rcp, S = R.opState, out = {};
    const DIA = "2026-08-04", LEG = "104";
    const K = "vir_recepcion_draft_" + LEG + "_" + DIA;
    localStorage.clear();
    window.__avisos = 0;
    window.onRecepcionDraftChange = function () { window.__avisos++; };

    // El operario arranca la recepción por RT y carga hasta la grilla de códigos.
    window.openRecepcionOp(LEG, DIA);
    out.abre = R.el.page.classList.contains("open");
    S.tipo = "tallerista"; S.tallNombre = "Lucho"; S.tallCod = "L1";
    S.tallCods = { LK: "L1", CH: null }; S.linea = "LK"; S.fecha = DIA; S.remito = "38770";
    S.articulos = [{ Cod_Art: "518", Desc: "" }, { Cod_Art: "586", Desc: "" }];
    S.cargas = { "518": 12, "586": 7 };
    S.step = "articulos";
    R.drawArticulosGrid();                       // cada cambio de cajas guarda el borrador
    out.guardaAlCargar = !!localStorage.getItem(K);

    // ...y se va (✕ Salir): el borrador queda y Producción se entera.
    const avisosAntes = window.__avisos;
    R.closeOp();
    const d = JSON.parse(localStorage.getItem(K) || "null");
    out.guardaAlSalir = !!d && d.tallNombre === "Lucho" && d.linea === "LK" && d.remito === "38770" &&
      d.step === "articulos" && d.cargas["518"] === 12 && d.cargas["586"] === 7;
    out.avisa = window.__avisos > avisosAntes;
    out.cerro = !R.el.page.classList.contains("open");

    // Resumen para el botón de "Resumen de hoy".
    const info = window.recepcionDraftInfo(LEG, DIA);
    out.info = !!info && info.nombre === "Lucho" && info.linea === "LK" && info.remito === "38770" &&
      info.codigos === 2 && info.cajas === 19 && info.step === "articulos";
    // Es POR legajo+día: otro legajo / otro día no lo ven.
    out.porLegajo = window.recepcionDraftInfo("55", DIA) === null &&
                    window.recepcionDraftInfo(LEG, "2026-08-03") === null;

    // "▶ Reanudar" → vuelve al MISMO paso, con todo puesto.
    S.tipo = null; S.tallNombre = null; S.cargas = {}; S.articulos = null; S.step = null;
    window.reanudarRecepcionOp(LEG, DIA);
    out.reanuda = R.el.page.classList.contains("open") && S.step === "articulos" &&
      S.tallNombre === "Lucho" && S.tallCod === "L1" && S.linea === "LK" && S.remito === "38770" &&
      S.cargas["518"] === 12 && S.cargas["586"] === 7;
    out.reanudaGrilla = R.el.body.querySelectorAll(".opCodeBtn").length === 2 &&
      R.el.body.textContent.indexOf("12 cajas") >= 0;

    // Borrador de un día viejo: se limpia solo al leer.
    localStorage.setItem("vir_recepcion_draft_" + LEG + "_2026-07-01", '{"v":1}');
    window.recepcionDraftInfo(LEG, DIA);
    out.limpiaViejos = localStorage.getItem("vir_recepcion_draft_" + LEG + "_2026-07-01") === null;

    // Enviar la recepción borra el borrador.
    S.step = "resumen"; R.renderResumen();
    await R.opEnviar();
    out.enviarLimpia = localStorage.getItem(K) === null && window.recepcionDraftInfo(LEG, DIA) === null;

    // Una recepción NUEVA (RT otra vez) no arrastra el borrador anterior.
    window.openRecepcionOp(LEG, DIA);
    S.tallNombre = "Poly"; S.linea = "CH"; S.step = "linea"; S.cargas = { "300": 5 };
    R.drawArticulosGrid();
    window.openRecepcionOp(LEG, DIA);
    out.nuevaLimpia = localStorage.getItem(K) === null;

    // El supervisor (menú admin, sin legajo) no deja borrador.
    localStorage.clear();
    window.openRecepcionMenu();
    S.tallNombre = "Garcia"; S.cargas = { "107": 3 }; S.step = "articulos";
    R.drawArticulosGrid();
    R.closeOp();
    out.supervisorSinDraft = Object.keys(localStorage).filter(function (k) {
      return k.indexOf("vir_recepcion_draft_") === 0;
    }).length === 0;

    return out;
  });

  // ===== 2ª parte: el botón en "Resumen de hoy" (index.html) =====
  const p2 = await b.newPage();
  p2.on("pageerror", (e) => errs.push("index.html: " + e.message));
  await p2.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r2 = await p2.evaluate(() => {
    const out = {}, LEG = "104";
    // recepcion.js no carga sin red (importa supabase-js de esm.sh): se stubea su API.
    window.recepcionDraftInfo = function () {
      return { nombre: "Lucho", linea: "LK", remito: "38770", codigos: 2, cajas: 19, step: "articulos" };
    };
    window.__reanudado = null;
    window.reanudarRecepcionOp = function (leg, dia) { window.__reanudado = leg + "|" + dia; };
    const box = document.getElementById("legajoHistoryContent");

    // (a) con una fila RT en el resumen → el bloque cuelga de ESA fila
    writeDayHist(getTodayKey(), LEG, [{ id: "x1", opcion: "RT", descripcion: "Recepción Mercadería", ts: Date.now(), status: "failed" }]);
    renderLegajoHistory(LEG);
    const item = box.querySelector(".history-item.hist-pend");
    out.enFilaRT = !!item && item.textContent.indexOf("RT — Recepción Mercadería") >= 0 &&
      item.textContent.indexOf("Reanudar") >= 0 && item.textContent.indexOf("Lucho · LK · RTO/FC 38770") >= 0 &&
      item.textContent.indexOf("2 códigos · 19 cajas") >= 0;
    out.unSoloBoton = box.querySelectorAll("button.hist-reanudar").length === 1;

    // tocarlo reabre la recepción de ESE legajo
    box.querySelector("button.hist-reanudar").click();
    out.click = window.__reanudado === LEG + "|" + getTodayKey();

    // (b) sin fila RT (se perdió el evento) → tarjeta propia arriba de todo
    writeDayHist(getTodayKey(), LEG, [{ id: "x2", opcion: "MG", descripcion: "Guardado a Góndola", ts: Date.now(), status: "sent" }]);
    renderLegajoHistory(LEG);
    const first = box.querySelector(".history-item");
    out.tarjetaPropia = !!first && first.classList.contains("hist-pend") &&
      first.textContent.indexOf("Reanudar") >= 0 &&
      box.querySelectorAll("button.hist-reanudar").length === 1;

    // (c) sin borrador → no aparece nada
    window.recepcionDraftInfo = function () { return null; };
    renderLegajoHistory(LEG);
    out.sinDraft = box.querySelectorAll("button.hist-reanudar").length === 0 &&
      box.querySelectorAll(".history-item").length === 1;

    // (d) sin el módulo cargado no explota
    delete window.recepcionDraftInfo;
    renderLegajoHistory(LEG);
    out.sinModulo = box.querySelectorAll("button.hist-reanudar").length === 0;
    return out;
  });
  Object.keys(r2).forEach(function (k) { r["ui_" + k] = r2[k]; });

  await b.close();
  const fail = [];
  Object.keys(r).forEach(function (k) { if (r[k] !== true) fail.push(k + "=" + JSON.stringify(r[k])); });
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  if (fail.length) { console.error("rcp-reanudar: FALLÓ →", fail.join(", ")); process.exit(1); }
  console.log("rcp-reanudar: OK — la recepción a medio cargar sobrevive y se reanuda en su paso");
  process.exit(0);
})();
