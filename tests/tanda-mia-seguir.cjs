/* Regresión v18.46 — la tanda que dejé empezada YO no se bloquea: se puede retomar.
   Caso real (Luis, 15/09, foto del celular de Franco): el legajo 237 arrancó el armado de
   E11B, y al volver a la lista de AP su propia tanda le aparecía con 🔒 "ya la está armando
   el legajo 237" — o sea él mismo — y el chip venía `disabled`. Sin camino de vuelta desde
   esa pantalla, agarraba otra tanda y E11B quedaba abierta para siempre.
   Chequea:
     1) el AP en curso de OTRO legajo → chip 🔒 disabled (la regla v5.74 no se toca);
     2) el AP en curso PROPIO → chip "▶ seguir", clickable, que abre el asistente;
     3) al tocarlo se reconstruye st.armado con el ts que trae el SERVIDOR, así el TAP sale
        con la duración real y la tanda vuelve a figurar en "Terminar Día";
     4) lo mismo en el picking (modo TP): el EP ajeno con candado, el propio "▶ seguir".
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
  const r = await p.evaluate(async () => {
    const out = {};
    const MIO = "237", OTRO = "8";
    const TS_AP = "2026-09-15T14:15:00.000Z", TS_EP = "2026-09-15T15:36:00.000Z";
    legajoInput.value = MIO;
    window.alert = function () {};

    // PPP con cuatro tandas del mismo día.
    window.getPppTandasForOperator = async function () {
      return ["E11B", "D72A", "E01G", "E11C"].map(function (t) {
        return { tanda: t, fechaRaw: "2026-09-16", fechaDisplay: "16/09", m3: 1 };
      });
    };
    const estado = {
      pickingStarted: new Set(["E11B", "D72A", "E01G", "E11C"]),
      pickingDone: new Set(["E11B", "D72A", "E01G"]),
      pickingDoneStrict: new Set(["E11B", "D72A", "E01G"]),
      armadoStarted: new Set(["E11B", "D72A"]),
      armadoDone: new Set(), armadoDoneStrict: new Set(),
      armadoEnCursoBy: new Map([["E11B", MIO], ["D72A", OTRO]]),
      armadoEnCursoTs: new Map([["E11B", TS_AP]]),
      pickingEnCursoBy: new Map([["E11C", MIO]]),
      pickingEnCursoTs: new Map([["E11C", TS_EP]])
    };
    window.getActivityStatus = async function () { return estado; };

    const chip = function (cod) {
      return [].slice.call(document.querySelectorAll("#tandasList .tanda-chip"))
        .find(function (x) { return x.textContent.indexOf(cod) === 0; }) || null;
    };

    // ---- lista de ARMADO (AP) ----
    await populateTandasList("pickingDone");
    const cMio = chip("E11B"), cOtro = chip("D72A"), cLibre = chip("E01G");
    out.miaClickable   = !!(cMio && !cMio.disabled && /seguir/i.test(cMio.textContent));
    out.miaVerde       = !!(cMio && cMio.classList.contains("mia"));
    out.ajenaBloqueada = !!(cOtro && cOtro.disabled && cOtro.classList.contains("ocupada"));
    out.ajenaDiceQuien = !!(cOtro && /legajo 8/.test(cOtro.getAttribute("title") || ""));
    out.libreNormal    = !!(cLibre && !cLibre.disabled && !/seguir/i.test(cLibre.textContent));

    // tocar la mía → abre el asistente y reconstruye el arranque desde el servidor
    let comp = null; window.showCompletarWizard = function (l, c) { comp = [l, c]; };
    const st0 = getLegajoState(MIO);
    st0.armado = { active: false, value: "", ts_inicio: null }; setLegajoState(MIO, st0);
    cMio.click();
    await new Promise(function (r2) { setTimeout(r2, 60); });
    out.miaAbreAsistente = comp && comp[0] === MIO && comp[1] === "E11B";
    const st1 = getLegajoState(MIO);
    out.miaRestauraEstado = !!(st1.armado && st1.armado.active && st1.armado.value === "E11B");
    out.miaRestauraTs     = st1.armado && st1.armado.ts_inicio === TS_AP;
    out.miaLlenaInput     = textInput.value === "E11B";

    // ---- lista de PICKING en curso (TP) ----
    await populateTandasList("pickingCurso");
    const pMio = chip("E11C");
    out.pkMiaClickable = !!(pMio && !pMio.disabled && /seguir/i.test(pMio.textContent));
    let lista = null; window.showPickingList = function (t, l) { lista = [t, l]; };
    const st2 = getLegajoState(MIO);
    st2.picking = { active: false, value: "", ts_inicio: null }; setLegajoState(MIO, st2);
    pMio.click();
    await new Promise(function (r2) { setTimeout(r2, 60); });
    out.pkMiaAbreLista  = lista && lista[0] === "E11C" && lista[1] === MIO;
    const st3 = getLegajoState(MIO);
    out.pkRestauraTs    = st3.picking && st3.picking.ts_inicio === TS_EP;

    // ---- control: con OTRO legajo, la misma tanda vuelve a estar bloqueada ----
    legajoInput.value = "999";
    await populateTandasList("pickingDone");
    const cAjena = chip("E11B");
    out.otroLaVeBloqueada = !!(cAjena && cAjena.disabled);
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("tanda-mia-seguir:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
