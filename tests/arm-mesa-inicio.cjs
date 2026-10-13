/* v29.90 — AL EMPEZAR EL ARMADO SE PREGUNTA LA MESA (evento AUI)

   Luis, 13/10: "d1 si, que pregunte la mesa al empezar armado. fijate que no rompa
   nada. todo esto fowardfacing".

   El monitor ya dice dónde quedó físicamente una tanda (v29.74), pero MIENTRAS la
   arman no había dato: el PUB es de cuando terminó el picking y el AUB de cuando
   termina el armado. Ahora el AP pregunta la mesa y emite un 'AUI' aparte.

   Lo que se mide, corriendo la pantalla de verdad:
     (a) con mesa elegida → se encola el AP **y** un AUI (texto=tanda, ts_inicio null)
     (b) la MESA ES OBLIGATORIA: el cuadro no tiene escape, y si no contesta no hay AUI
     (c) si el cuadro explota, el AP queda y el asistente se abre igual (no rompe nada)
     (d) el cuadro de verdad: Mesa 1 / Mesa 2 / Otro lugar / Después, y el click resuelve
     (e) AUI está en COLA_AUTO (es un evento de DETALLE: no es una tarea del operario)
     (f) el AUI no se emite en ninguna otra opción

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const LEG = "999994";
    const ev = window.eval;

    const _origAlert = window.alert, _origConfirm = window.confirm;
    window.alert = function () {};
    window.confirm = function () { return true; };

    // la cola, interceptada: se mira QUÉ se encola, sin mandar nada
    ev("window.__encM = []; window.__rawM = _enqueueReportRaw;" +
       "_enqueueReportRaw = function (pl) { window.__encM.push(pl); };" +
       "window.__tryM = trySendOneReport; trySendOneReport = async function () { return { ok: false }; };");

    // sin locks del servidor
    const _origStatus = window.getActivityStatus;
    window.getActivityStatus = async function () {
      return {
        pickingStarted: new Set(), pickingDone: new Set(), pickingDoneStrict: new Set(),
        armadoStarted: new Set(),  armadoDone: new Set(),  armadoDoneStrict: new Set(),
        pickingEnCursoBy: new Map(), pickingEnCursoTs: new Map(),
        armadoEnCursoBy: new Map(),  armadoEnCursoTs: new Map(),
        pickingFrenadaBy: new Map(), armadoFrenadaBy: new Map()
      };
    };
    // el asistente y la guía no son lo que se prueba: se anotan y no se dibujan
    ev("window.__abrio = 0;" +
       "window.__oGuia = (typeof showArmadoGuide === 'function') ? showArmadoGuide : null;" +
       "showArmadoGuide = function () {};" +
       "window.__oWiz = (typeof showCompletarWizard === 'function') ? showCompletarWizard : null;" +
       "showCompletarWizard = function () { window.__abrio++; };");

    function prepararAP(tanda) {
      const st = getLegajoState(LEG);
      st.picking = null; st.armado = null;
      setLegajoState(LEG, st);
      try { legajoInput.value = LEG; } catch (_e) {}
      try { textInput.value = tanda; } catch (_e) {}
      ev("selected = 'AP';");
      window.__encM.length = 0; window.__abrio = 0;
    }
    /* la mesa se emite SIN await (el armado no espera): un tick y ya está en la cola */
    const tick = () => new Promise(r2 => setTimeout(r2, 40));

    /* ============== (a) con mesa: AP + AUI ============== */
    ev("window.__oMesa = askArmadoMesa; askArmadoMesa = async function () { return 'Mesa 2'; };");
    prepararAP("Z66A");
    await send(); await tick();
    const aps = window.__encM.filter(x => x.opcion === "AP");
    const auis = window.__encM.filter(x => x.opcion === "AUI");
    out.a_encola_AP        = aps.length === 1 && String(aps[0].texto || "").toUpperCase() === "Z66A";
    out.a_encola_AUI       = auis.length === 1;
    out.a_AUI_mesa         = auis.length === 1 && auis[0].descripcion === "Mesa 2";
    out.a_AUI_tanda        = auis.length === 1 && String(auis[0].texto || "").toUpperCase() === "Z66A";
    out.a_AUI_sin_tsinicio = auis.length === 1 && !auis[0].ts_inicio_iso;   // NO abre tarea ni cuenta horas
    out.a_abrio_asistente  = window.__abrio >= 1;
    out.a_armado_abierto   = !!(getLegajoState(LEG).armado || {}).active;

    /* ============== (b) sin contestar: AP sin AUI, y el asistente igual ============== */
    ev("askArmadoMesa = async function () { return null; };");
    prepararAP("Z66B");
    await send(); await tick();
    out.b_encola_AP       = window.__encM.filter(x => x.opcion === "AP").length === 1;
    out.b_sin_AUI         = window.__encM.filter(x => x.opcion === "AUI").length === 0;
    out.b_abrio_asistente = window.__abrio >= 1;

    /* ============== (c) si el cuadro explota, el armado sigue ============== */
    ev("askArmadoMesa = async function () { throw new Error('boom'); };");
    prepararAP("Z66C");
    await send(); await tick();
    out.c_encola_AP       = window.__encM.filter(x => x.opcion === "AP").length === 1;
    out.c_sin_AUI         = window.__encM.filter(x => x.opcion === "AUI").length === 0;
    out.c_abrio_asistente = window.__abrio >= 1;   // ← "que no rompa nada"

    /* ============== (d) el cuadro de verdad ============== */
    ev("askArmadoMesa = window.__oMesa;");
    const pr = ev("askArmadoMesa('Z66D')");
    await new Promise(r2 => setTimeout(r2, 60));
    const card = document.querySelector("#auiModal .aui-card");
    const btns = Array.prototype.slice.call(document.querySelectorAll("#auiModal .aui-opt"));
    const txt = card ? card.textContent : "";
    out.d_se_dibuja   = !!card && document.getElementById("auiModal").classList.contains("show");
    out.d_nombra_tanda = txt.indexOf("Z66D") >= 0;
    out.d_mesa1       = btns.some(x => x.textContent.trim() === "Mesa 1");
    out.d_mesa2       = btns.some(x => x.textContent.trim() === "Mesa 2");
    out.d_otro_lugar  = btns.some(x => /Otro lugar/.test(x.textContent));
    /* v29.90 (Luis): la mesa es OBLIGATORIA — no hay botón de escape ni «Después» */
    out.d_sin_escape  = !document.querySelector("#auiModal .aui-x") && !/Después/.test(txt);
    out.d_dice_obligatorio = /Hay que elegir una/.test(txt);
    const b2 = btns.filter(x => x.textContent.trim() === "Mesa 2")[0];
    if (b2) b2.click();
    out.d_devuelve_mesa = (await pr) === "Mesa 2";
    out.d_cierra        = !document.getElementById("auiModal").classList.contains("show");

    /* ============== (f) ninguna otra opción emite AUI ============== */
    ev("askArmadoMesa = async function () { return 'Mesa 1'; };");
    const stP = getLegajoState(LEG);
    stP.picking = { active: true, value: "Z66E", ts_inicio: new Date(Date.now() - 20 * 60000).toISOString() };
    stP.armado = null; setLegajoState(LEG, stP);
    try { legajoInput.value = LEG; textInput.value = "Z66E"; } catch (_e) {}
    ev("window.__oPubM = askPickUbicacion; askPickUbicacion = async function () { return 'Mesa 1'; };" +
       "selected = 'TP';");
    window.__encM.length = 0;
    await send(); await tick();
    out.f_TP_sin_AUI = window.__encM.filter(x => x.opcion === "AUI").length === 0 &&
                       window.__encM.filter(x => x.opcion === "TP").length === 1;

    // dejar todo como estaba
    ev("askArmadoMesa = window.__oMesa; askPickUbicacion = window.__oPubM;" +
       "if (window.__oGuia) showArmadoGuide = window.__oGuia;" +
       "if (window.__oWiz) showCompletarWizard = window.__oWiz;" +
       "_enqueueReportRaw = window.__rawM; trySendOneReport = window.__tryM;" +
       "delete window.__oMesa; delete window.__oPubM; delete window.__oGuia; delete window.__oWiz;" +
       "delete window.__rawM; delete window.__tryM; delete window.__encM; delete window.__abrio;");
    window.getActivityStatus = _origStatus;
    window.alert = _origAlert; window.confirm = _origConfirm;
    try {
      const m = JSON.parse(localStorage.getItem("legajo_state_virgilio_v1") || "{}");
      delete m[LEG]; localStorage.setItem("legajo_state_virgilio_v1", JSON.stringify(m));
    } catch (_e) {}
    return out;
  });

  /* ============== (e) candados estáticos: AUI es un evento de DETALLE ============== */
  const fs = require("fs");
  const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  r.e_en_cola_auto = /const COLA_AUTO = new Set\(\[[^\]]*"AUI"[^\]]*\]\)/.test(src);
  r.e_emite_una_vez = (src.match(/emitArmadoMesa\(/g) || []).length === 2;   // la declaración + la única llamada
  r.e_pregunta_en_el_AP = /opcion === "AP" && \(texto \|\| ""\)\.trim\(\)\) \{[\s\S]{0,900}?askArmadoMesa\(texto\)/.test(src);
  /* el armado NO espera a nadie: la pregunta va DESPUÉS del asistente y SIN await */
  r.e_no_frena = !/await askArmadoMesa/.test(src) &&
                 /showCompletarWizard\(legajoStr, texto\);[\s\S]{0,500}?askArmadoMesa\(texto\)\.then\(/.test(src);

  const claves = Object.keys(r);
  const malas = claves.filter(k => r[k] !== true);
  const pass = malas.length === 0 && errs.length === 0;
  for (const k of claves) console.log((r[k] === true ? "ok  " : "FAIL") + "   " + k);
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  console.log("\narm-mesa-inicio: " + (pass ? "OK" : "FAIL (" + malas.join(", ") + ")"));
  await b.close(); process.exit(pass ? 0 : 1);
})();
