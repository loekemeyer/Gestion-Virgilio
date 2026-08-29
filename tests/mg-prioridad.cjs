/* Regresión idea 4926 — Guardar a Góndola: prioridad con DEMANDA del día + hint de MCs.
   v8.40 ya ordenaba por góndola÷capacidad; v12.14 (idea 4926) resta la demanda del día
   ((góndola − pedidos) ÷ capacidad): un código lleno pero con muchos pedidos hoy también es
   urgente. Además muestra por código el máximo de MCs que entran sin rebalsar
   (piso((cap − góndola) / cajas×MC)) — informativo, no limita el input. Sin capacidad → va al
   final y sin cxm no hay hint. Best-effort: si demanda/cxm fallan, el modal abre igual.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    // saldos: 500 (gond 90/cap 100, sin demanda), 600 (gond 80/cap 100, demanda 60 → más urgente),
    // 700 (sin capacidad → al final, sin hint).
    window.stockFetchSaldos = async function () { return {
      "500": { cod: "500", desc: "", a_guardar: 10, terminado: 90 },
      "600": { cod: "600", desc: "", a_guardar: 5, terminado: 80 },
      "700": { cod: "700", desc: "", a_guardar: 3, terminado: 1 }
    }; };
    window.loadArtNombres = async function () { return {}; };
    window.ocgFetchCapacidad = async function () { return { "500": 100, "600": 100 }; };
    window.ocgFetchCeldas = async function () { return {}; };
    window.ocgDemanda = async function () { return { "600": 60 }; };
    window.rkbFetchCxM = async function () { return { cxm: { "500": 12, "600": 10 } }; };

    await showMGModal("104", null);
    out.orden = (_mg.items || []).map(function (it) { return it.cod; }).join(",");
    // 600: (80−60)/100 = 0.2 · 500: 90/100 = 0.9 · 700: sin cap → último
    out.ordenOk = out.orden === "600,500,700";
    const html = document.getElementById("mgBody").innerHTML;
    // hint de 600: floor((100−80)/10) = 2 MC (20 cajas)
    out.hint600 = html.indexOf("2 MC") >= 0 && html.indexOf("(20 cajas)") >= 0;
    // hint de 500: floor((100−90)/12) = 0 MC (góndola casi llena — el aviso vale igual)
    out.hint500cero = html.indexOf("0 MC") >= 0;
    // 700 sin capacidad/cxm → su tarjeta no lleva hint
    const i700 = html.indexOf(">700<");
    out.sin700hint = i700 >= 0 && html.slice(i700, i700 + 400).indexOf("mg-mchint") < 0;

    // best-effort: demanda y cxm rotos → el modal abre igual y ordena como v8.40
    window.ocgDemanda = async function () { throw new Error("x"); };
    window.rkbFetchCxM = async function () { throw new Error("x"); };
    await showMGModal("104", null);
    out.bestEffort_orden = (_mg.items || []).map(function (it) { return it.cod; }).join(",") === "600,500,700" ||
                           (_mg.items || []).map(function (it) { return it.cod; }).join(",") === "500,600,700";
    out.bestEffort_abre = !!document.getElementById("mgBody");
    return out;
  });
  const pass = r.ordenOk && r.hint600 && r.hint500cero && r.sin700hint &&
    r.bestEffort_orden && r.bestEffort_abre && errs.length === 0;
  console.log("mg-prioridad:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
