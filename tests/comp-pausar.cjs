/* Regresión v7.07 — botón "⏸ Pausar" del asistente de armado (AP). Debe:
   1) existir en el footer con onclick=compPausar,
   2) cerrar el modal SIN mandar TAP (no llama compTerminar / no encola nada),
   3) dejar el avance en localStorage (retomable) y NO tocar st.armado.active,
   4) dibujar "▶ Seguir armado" en la pantalla del operario.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    const leg = "104", tanda = "D05B";
    // El botón existe en el DOM y apunta a compPausar.
    const btn = document.getElementById("compPausar");
    out.btnExiste = !!btn && /compPausar/.test(btn.getAttribute("onclick") || "");
    out.fnExiste = typeof compPausar === "function";

    // Simular un armado abierto: st.armado.active + un _comp con avance + persistencia.
    if (legajoInput) legajoInput.value = leg;
    const st = getLegajoState(leg);
    st.armado = { active: true, value: tanda, ts_inicio: new Date().toISOString() };
    setLegajoState(leg, st);
    _comp = { tanda: tanda, step: 2, nps: [{ np: "98110", rs: "Cliente", liosArr: [], codes: [] }], arts: [], pedidoFull: [] };
    try { _compPersist(); } catch (_e) {}
    // Mostrar el modal como si estuviera en curso.
    const modal = document.getElementById("completarModal"); if (modal) modal.classList.add("show");

    // Espiar que NO se encole nada y que NO se llame compTerminar.
    let enqueued = 0;
    if (typeof enqueueReport === "function") { const _o = enqueueReport; window.enqueueReport = function () { enqueued++; return _o.apply(this, arguments); }; }

    compPausar();

    out.modalCerrado = !(modal && modal.classList.contains("show"));
    out.compNull = (typeof _comp === "undefined") || _comp === null;
    out.enqueued = enqueued;                                   // debe ser 0 (no manda TAP/eventos)
    const st2 = getLegajoState(leg);
    out.armadoSigueActivo = !!(st2.armado && st2.armado.active && st2.armado.value === tanda);  // sigue pendiente
    out.persistido = !!localStorage.getItem("vir_comp_" + tanda);   // avance retomable

    // La pantalla del operario ahora ofrece "Seguir armado".
    let box = null; try { box = ensurePendingSuggestionContainer(); } catch (_e) {}
    out.ofreceSeguir = !!(box && box.innerHTML.indexOf("Seguir armado") >= 0);
    return out;
  });
  const pass = r.btnExiste && r.fnExiste && r.modalCerrado && r.compNull && r.enqueued === 0 &&
    r.armadoSigueActivo && r.persistido && r.ofreceSeguir && errs.length === 0;
  console.log("comp-pausar:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
