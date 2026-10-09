/* v28.93 (Luis, 09/10) — IR, Mover racks, CP, RC e Insumos funcionan como BR/MG: el 1.er toque
   SELECCIONA (no abre nada), «Enviar» EMPIEZA (MDI / IRI) y abre el módulo, el botón queda rojo,
   tocarlo RETOMA (sin un 2.º MDI), la barra trae ⛔ Anular (MDT ANULADO) y 🏁 Terminé (MDT con
   ts_inicio). Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 390, height: 844 } }); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const sl = ms => new Promise(res => setTimeout(res, ms)); const out = {};
    window.alert = function () {}; window.confirm = function () { return true; };
    const evs = []; const _enq = window.enqueueReport;
    window.enqueueReport = function (pl) { evs.push(pl); try { return _enq(pl); } catch (_e) {} };
    window.trySendOneReport = function () { return Promise.resolve({ ok: false }); };
    legajoInput.value = "237"; goToOptions(); await sl(400);
    const box = c => document.querySelector('#optionsScreen [data-code="' + c + '"]');
    const vis = id => { const e = document.getElementById(id); return !!e && getComputedStyle(e).display !== "none"; };
    const OV = { MOV: "mvModal", CP: "cpModal", RC: "rcModal", INS: "insChooserModal" };
    for (const c of ["MOV", "CP", "RC", "INS"]) {
      box(c).click(); await sl(150);
      out[c + "_selecciona"] = !document.getElementById("selectedArea").classList.contains("hidden") && !vis(OV[c]);
      const n0 = evs.length; send(); await sl(400);
      const mdi = evs.slice(n0).filter(e => e.opcion === "MDI");
      out[c + "_enviarEmpieza"] = mdi.length === 1 && mdi[0].texto === c && vis(OV[c]) && modTareaActiva("237", c);
      updateCoreButtonsState();
      out[c + "_rojo"] = box(c).classList.contains("pending");
      out[c + "_barra"] = vis("modTareaBar");
      MOD_TAREA[c].cerrar(); await sl(700);
      out[c + "_cerrarMinimiza"] = modTareaActiva("237", c) && !vis("modTareaBar");
      const n1 = evs.length; box(c).click(); await sl(400);
      out[c + "_retoma"] = vis(OV[c]) && !evs.slice(n1).some(e => e.opcion === "MDI") && vis("modTareaBar");
      const n2 = evs.length;
      modTareaBoton(c, c === "CP");   // CP se anula, el resto se termina
      await sl(100);
      const mdt = evs.slice(n2).filter(e => e.opcion === "MDT");
      out[c + "_fin"] = mdt.length === 1 && !!mdt[0].ts_inicio_iso && mdt[0].texto === (c === "CP" ? "ANULADO" : c) &&
        !modTareaActiva("237", c) && !vis(OV[c]);
    }
    // Insumos → Recibir: al arrancar el toggle RI termina la tarea «Insumos»
    box("INS").click(); await sl(100); send(); await sl(300);
    closeInsumoChooser(); selectOption("RI"); await sl(100);
    const n3 = evs.length; try { await send(); } catch (_e) {} await sl(200);
    out.INS_terminaAlArrancarRI = !modTareaActiva("237", "INS") && evs.slice(n3).some(e => e.opcion === "MDT" && e.texto === "INS");
    // IR: selecciona, Enviar abre con IRI
    box("IR").click(); await sl(150);
    out.IR_selecciona = !document.getElementById("selectedArea").classList.contains("hidden");
    const n4 = evs.length; send(); await sl(500);
    out.IR_enviarIRI = evs.slice(n4).some(e => e.opcion === "IRI");
    return out;
  });
  const malos = Object.keys(r).filter(k => !r[k]);
  const pass = !malos.length && errs.length === 0;
  console.log("modulo-tarea-enviar:", malos.length ? "fallan " + malos.join(", ") : Object.keys(r).length + " chequeos", "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
