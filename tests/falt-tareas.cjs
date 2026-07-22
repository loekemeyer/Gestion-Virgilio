/* Regresión v5.71 — FALT · faltante que llegó → completar (coordinación en vivo).
   Con fetch stubbeado (sin red), maneja el pop-up y la asignación atómica:
   A) tarea pendiente → pop-up "¡Llegó un faltante!" con botón asignarme
   B) me asigno y GANO → pop-up "Te lo asignaste" con NP + artículos + completar
   C) me asigno pero OTRO la tomó → "Ya lo está haciendo Ana"
   D) Facturación: facTareaActiva/facTareaBadge (aviso amarillo "en progreso")
   E) legajo de prueba (0) NO ve el pop-up
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
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  // Setup: stub fetch + operador "activo" en la botonera (legajo 55).
  await p.evaluate(() => {
    window.__TASKS = [];
    window.__ASSIGN = null;
    window.alert = function () {};
    function J(data) { return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } }); }
    window.fetch = function (url, opts) {
      url = String(url); const m = (opts && opts.method) || "GET";
      if (url.indexOf("rpc/faltante_tarea_asignar") >= 0) return J(window.__ASSIGN);
      if (url.indexOf("rpc/faltante_tarea_") >= 0) return J(null);          // completar/soltar/crear
      if (url.indexOf("Faltantes_Tareas") >= 0) return J(window.__TASKS);
      if (url.indexOf("Empleados") >= 0) return J([{ Legajo: "55", Empleado: "Pedro" }]);
      if (url.indexOf("Entregas_Virgilio") >= 0) return J([]);              // faltNpRestante / cpLoadFaltantes
      return J([]);
    };
    document.getElementById("legajoInput").value = "55";
    const ls = document.getElementById("legajoScreen"); if (ls) ls.classList.add("hidden");
    const os = document.getElementById("optionsScreen"); if (os) os.classList.remove("hidden");
  });

  const body = () => p.evaluate(() => { const b = document.getElementById("faltPopupBody"); return b ? b.innerHTML : ""; });
  const shown = () => p.evaluate(() => { const o = document.getElementById("faltPopup"); return !!(o && o.classList.contains("show")); });

  // A) pendiente → pop-up de call-to-action
  const A = await p.evaluate(async () => {
    window.__TASKS = [{ id: 1, np: "98114", estado: "pendiente", articulos: [{ cod: "315", falto: 10 }], cod_cliente: "771", tanda: "D02A", razon_social: "Distri Norte" }];
    await faltPoll();
    const h = document.getElementById("faltPopupBody").innerHTML;
    const o = document.getElementById("faltPopup");
    return { shown: !!(o && o.classList.contains("show")), isPend: /Llegó un faltante/.test(h), hasAssign: /faltAsignarme\(1\)/.test(h), noDetailYet: !/98114/.test(h) };
  });

  // B) me asigno y GANO → "Te lo asignaste" con detalle
  const B = await p.evaluate(async () => {
    const t = { id: 1, np: "98114", estado: "asignado", asignado_legajo: "55", asignado_nombre: "Pedro", articulos: [{ cod: "315", falto: 10 }], cod_cliente: "771", tanda: "D02A", razon_social: "Distri Norte" };
    window.__ASSIGN = t; window.__TASKS = [t];
    await faltAsignarme(1);
    const h = document.getElementById("faltPopupBody").innerHTML;
    return { isMine: /Te lo asignaste/.test(h), showsNp: /98114/.test(h), showsArt: /315/.test(h), hasCompletar: /faltCompletar\(1/.test(h), hasListo: /faltYaListo\(1\)/.test(h) };
  });

  // F) estoy MIRANDO una pendiente y la toma OTRO (sin que yo intente) → "ya la toma X"
  const F = await p.evaluate(async () => {
    window.__TASKS = [{ id: 3, np: "555", estado: "pendiente", articulos: [{ cod: "100", falto: 2 }] }];
    await faltPoll();
    const wasPend = /Llegó un faltante/.test(document.getElementById("faltPopupBody").innerHTML);
    window.__TASKS = [{ id: 3, np: "555", estado: "asignado", asignado_legajo: "77", asignado_nombre: "Marta" }];
    await faltPoll();
    const nowTaken = /Ya lo está haciendo Marta/.test(document.getElementById("faltPopupBody").innerHTML);
    return { wasPend, nowTaken };
  });

  // C) me asigno pero la tomó OTRO → "Ya lo está haciendo Ana"
  const C = await p.evaluate(async () => {
    window.__TASKS = [{ id: 2, np: "98091", estado: "pendiente", articulos: [{ cod: "440", falto: 5 }] }];
    // reset estado interno de "taken"/mine: forzamos un poll con la 2 pendiente
    await faltPoll();
    window.__ASSIGN = { id: 2, np: "98091", estado: "asignado", asignado_legajo: "88", asignado_nombre: "Ana" };
    await faltAsignarme(2);
    const h = document.getElementById("faltPopupBody").innerHTML;
    return { taken: /Ya lo está haciendo Ana/.test(h) };
  });

  // D) Facturación: badge amarillo "en progreso"
  const D = await p.evaluate(async () => {
    window.__TASKS = [{ np: "98114", estado: "asignado", asignado_legajo: "55", asignado_nombre: "Pedro" }];
    await facFetchTareas();
    const t = facTareaActiva("98114");
    const badge = facTareaBadge("98114");
    return { active: !!t, hasCompletando: /Completando/.test(badge), hasPedro: /Pedro/.test(badge), noneForOther: facTareaActiva("00000") === null };
  });

  // E) legajo de PRUEBA (0) no ve el pop-up
  const E = await p.evaluate(async () => {
    document.getElementById("legajoInput").value = "0";
    window.__TASKS = [{ id: 9, np: "777", estado: "pendiente", articulos: [] }];
    faltHidePopup();
    await faltPoll();
    const o = document.getElementById("faltPopup");
    return { hiddenForPrueba: !(o && o.classList.contains("show")) };
  });

  const okA = A.shown && A.isPend && A.hasAssign && A.noDetailYet;
  const okB = B.isMine && B.showsNp && B.showsArt && B.hasCompletar && B.hasListo;
  const okF = F.wasPend && F.nowTaken;
  const okC = C.taken;
  const okD = D.active && D.hasCompletando && D.hasPedro && D.noneForOther;
  const okE = E.hiddenForPrueba;
  const pass = okA && okB && okF && okC && okD && okE && errs.length === 0;
  console.log("falt-tareas:", JSON.stringify({ A, B, F, C, D, E }));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none");
  console.log(" ", okA ? "A pend ✓" : "A pend ✗", "·", okB ? "B gano ✓" : "B gano ✗", "·", okF ? "F mira-otro ✓" : "F mira-otro ✗", "·", okC ? "C pierdo ✓" : "C pierdo ✗", "·", okD ? "D fac ✓" : "D fac ✗", "·", okE ? "E prueba ✓" : "E prueba ✗", "·", pass ? "OK" : "FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
