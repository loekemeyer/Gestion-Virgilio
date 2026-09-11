/* Regresión v15.70 — CARGA CAMIÓN: el tilde pasa a ser el ORDEN en que el operario fue cargando
   (1°, 2°, 3°…) y el camionero deja de ser opcional.

   Thomas (11/09/2026): *"quiero que los operarios que usen CC, una vez que cargaron los pedidos al
   camión, a medida que den click en lo que cargan, en lugar de un simple tilde, que diga 1°, 2°,
   3°, etc. […] una vez que ya terminó de cargar el camión, que le pregunte el nombre del camionero
   antes de cerrar el popup."*

   Por qué obligatorio: el campo existe desde la v11.47 pero se saltea. Medido el 11/09: el 10 y el
   11/09 salieron 33 cargas SIN camionero, el 08/09 otras 10. Sin ese dato Recepción Remitos no
   puede juntar "las NP que entregó Guillermo el 11/09" ni se puede medir el ritmo del viaje.

   Chequea, sin red:
   1) el número que se muestra es el orden de CLIC, no el de la lista (se tilda 3º, 1º, 2º),
   2) destildar y volver a tildar manda esa NP al final,
   3) el orden sobrevive a cerrar y reabrir el modal (localStorage),
   4) sin camionero NO termina la carga (y no manda ningún CCN),
   5) con camionero, el CCN lleva 'NP|TANDA|CAMIONERO|ORDEN' en el orden de carga,
   6) en RETIRA sigue el tilde ✓ y no se pide camionero.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { alerts: [] };
    const ITEMS = [
      { np: "98601", tanda: "D70A", rs: "Cliente Uno",  lios: 1, loadIdx: 1, ruta: "Norte", esRetira: false },
      { np: "98602", tanda: "D70A", rs: "Cliente Dos",  lios: 2, loadIdx: 2, ruta: "Norte", esRetira: false },
      { np: "98603", tanda: "D70B", rs: "Cliente Tres", lios: 1, loadIdx: 3, ruta: "Norte", esRetira: false }
    ];
    window.fetchCCData = async function () { return ITEMS.slice(); };
    window.ccFetchCamioneros = async function () { return ["Guillermo", "Renato"]; };
    window.ccWakeLock = function () {}; window.ccReleaseWakeLock = function () {};
    window.alert = function (m) { out.alerts.push(String(m)); };
    window.confirm = function () { return true; };
    // los CCN se leen de la COLA de envíos (localStorage): ccFinish llama a la función interna
    // del script, no a window.ccSendDetail, así que espiar el global no sirve.
    const QK = "legajo_queue_virgilio_v1";
    const enviados = [];
    const leerCola = function () {
      let q = []; try { q = JSON.parse(localStorage.getItem(QK) || "[]"); } catch (_e) {}
      // la cola guarda { id, payload, … }: el evento está en x.payload
      return (Array.isArray(q) ? q : []).map(x => (x && x.payload) || x).filter(x => x && x.opcion === "CCN").map(x => x.texto);
    };
    const limpiarCola = function () { try { localStorage.setItem(QK, "[]"); } catch (_e) {} };
    limpiarCola();
    window.trySendOneReport = function () { return Promise.resolve({ ok: false }); };
    window.ccSendClose = function () {}; window.ccUpsertCamionero = function () {};
    window.closeTandaModal = function () {};
    if (!document.getElementById("tandaModal")) {
      const d = document.createElement("div"); d.id = "tandaModal";
      d.innerHTML = '<div class="tanda-modal-title"></div><div class="tanda-modal-body"></div>';
      document.body.appendChild(d);
    }
    const body = () => document.querySelector("#tandaModal .tanda-modal-body");
    const chips = () => Array.prototype.slice.call(body().querySelectorAll(".cc-np")).map(function (el) {
      return { np: (el.querySelector(".cc-npnum") || {}).textContent, chk: (el.querySelector(".cc-chk") || {}).textContent };
    });

    // --- (1) orden de CLIC, no el de la lista ---
    await showCargaCamion("104", "camion");
    ccToggle("98603"); ccToggle("98601"); ccToggle("98602");
    out.orden1 = chips().map(c => c.np + ":" + c.chk).join(" ");   // esperado 98601:2° 98602:3° 98603:1°

    // --- (2) destildar y volver a tildar → al final ---
    ccToggle("98601"); ccToggle("98601");
    out.orden2 = chips().map(c => c.np + ":" + c.chk).join(" ");   // 98601 pasa a 3°

    // --- (3) sobrevive a cerrar y reabrir ---
    ccClose();
    await showCargaCamion("104", "camion");
    out.orden3 = chips().map(c => c.np + ":" + c.chk).join(" ");
    out.persiste = out.orden3 === out.orden2;

    // --- (4) sin camionero no termina --- (ccFinish relee el INPUT, no la variable)
    const camInp = () => document.getElementById("ccCamioneroInput");
    camInp().value = "";
    ccFinish();
    out.bloqueaSinCamionero = leerCola().length === 0 && out.alerts.some(a => /camionero/i.test(a));
    out.siguiAbierto = !!_cc;

    // --- (5) con camionero: CCN con orden de carga ---
    camInp().value = "Guillermo";
    ccFinish();
    out.enviados = leerCola();
    out.ccnOk = out.enviados.length === 3 &&
      out.enviados[0] === "98603|D70B|Guillermo|1" &&
      out.enviados[1] === "98602|D70A|Guillermo|2" &&
      out.enviados[2] === "98601|D70A|Guillermo|3";

    // --- (6) retira: tilde ✓ y sin camionero ---
    limpiarCola();
    window.fetchCCData = async function () { return [{ np: "98700", tanda: "D70C", rs: "Retira Uno", lios: 1, esRetira: true }]; };
    await showCargaCamion("104", "retira");
    ccToggle("98700");
    out.retiraChk = (chips()[0] || {}).chk;
    out.retiraSinInput = !document.getElementById("ccCamioneroInput");
    ccFinish();
    out.retiraEnvio = leerCola()[0] || "";
    return out;
  });

  const pass =
    r.orden1 === "98601:2° 98602:3° 98603:1°" &&
    r.orden2 === "98601:3° 98602:2° 98603:1°" &&
    r.persiste && r.bloqueaSinCamionero && r.siguiAbierto && r.ccnOk &&
    r.retiraChk === "✓" && r.retiraSinInput && /^98700\|D70C\|\|$/.test(r.retiraEnvio) &&
    errs.length === 0;
  const { alerts, ...vis } = r;
  console.log("cc-orden-camionero:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
