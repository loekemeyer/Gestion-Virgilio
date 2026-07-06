/* Regresión v5.25 — "Seguir armado": si el operario hace AP y después una pausa
   (PC comida u otra tarea), tiene que poder RETOMAR el asistente de armado donde
   quedó, SIN volver a mandar AP, y el botón tiene que verse INCLUSO con un toggle
   activo (durante la pausa). Sale 1 si falla. */
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
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const leg = "999";
    const li = document.getElementById("legajoInput"); if (li) li.value = leg;
    // AP hecho (armado activo) + PC comida en curso (toggle activo) = la pausa del operario.
    const st = getLegajoState(leg);
    st.armado = { active: true, value: "C99Z", ts_inicio: null };
    st.toggles = Object.assign({}, st.toggles || {}, { PC: new Date().toISOString() });
    setLegajoState(leg, st);
    // Avance del wizard persistido en Paso 2.
    localStorage.setItem("vir_comp_C99Z", JSON.stringify({ _ts: Date.now(), step: 2, tanda: "C99Z", nps: [{ np: "1" }] }));
    // Stub para no pegar a la red al clickear (y verificar que NO se manda AP).
    let called = null; window.showCompletarWizard = function (l, c) { called = [l, c]; };
    renderPendingSuggestion();
    const box = document.getElementById("pendingSuggestion");
    const seguir = [].slice.call(box.querySelectorAll("button")).find(function (x) { return x.innerText.indexOf("Seguir armado") >= 0; });
    const seguirText = seguir ? seguir.innerText : null;
    if (seguir) seguir.click();
    // Negativo: sin armado activo NO aparece.
    const st2 = getLegajoState(leg); st2.armado = { active: false, value: "", ts_inicio: null }; st2.toggles = {}; setLegajoState(leg, st2);
    renderPendingSuggestion();
    const box2 = document.getElementById("pendingSuggestion");
    const hasWhenInactive = [].slice.call(box2.querySelectorAll("button")).some(function (x) { return x.innerText.indexOf("Seguir armado") >= 0; });
    return { shownDuringToggle: !!seguir, seguirText: seguirText, clicked: called, hasWhenInactive: hasWhenInactive };
  });
  const pass = r.shownDuringToggle && r.clicked && r.clicked[1] === "C99Z" &&
               !r.hasWhenInactive && /Paso 2/.test(r.seguirText || "") && errs.length === 0;
  console.log("ap-resume:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
