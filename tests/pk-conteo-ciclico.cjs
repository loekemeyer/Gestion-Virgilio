/* Regresión idea 3798 — CONTEO CÍCLICO de góndola. Al terminar un picking se elige UN
   artículo al azar SOLO de los que tienen UNA sola celda en góndola, se le pide al operario
   que confirme las cajas (no bloquea) y se emite el evento CG (Telegram lo compara).
   Chequea: la selección respeta "una sola celda" y excluye excedente/salteados; el card se
   arma; el submit emite el CG con el formato correcto. Sale 1 si falla. */
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
    const _realEmit = pkEmitConteo;   // guardar el real para el test de formato

    // ---- 1) SELECCIÓN: sólo artículos de UNA sola celda; excluye 2-celdas, 0-celdas, excedente, salteado ----
    _pk = { tanda: "T1", legajo: "104", results: {}, mode: "item", items: [
      { art: "500", sector: "A1" },                 // 1 celda → único candidato
      { art: "501", sector: "B1" },                 // 2 celdas → NO
      { art: "502", sector: "" },                   // 0 celdas → NO
      { art: "503", sector: "C1", isExc: true },    // excedente → NO
      { art: "504", sector: "D1", skip: true }      // salteado → NO
    ] };
    window._pkConteoSwitchOn = async function () { return true; };
    window._pkCeldasPorCod = async function () { return { "500": 1, "501": 2, "502": 0, "503": 1, "504": 1 }; };
    window.pkRender = function () {};   // sin DOM del modal
    await pkPickConteo();
    out.elegido = _pk.conteo && _pk.conteo.art;
    out.soloUnaCelda = out.elegido === "500";

    // ---- 2) CARD ----
    _pk.conteo = { art: "500", sector: "A1", done: false };
    const card = pkConteoCardHtml();
    out.cardCod = card.indexOf("500") >= 0;
    out.cardCelda = card.indexOf("A1") >= 0;
    out.cardInput = card.indexOf("pkConteoInp") >= 0 && card.indexOf("pkConteoSubmit") >= 0;
    _pk.conteo.done = true;
    out.cardDone = pkConteoCardHtml().indexOf("Anotaste") >= 0;

    // ---- 3) SUBMIT → llama al emit y marca done ----
    _pk.conteo = { art: "500", done: false };
    let emitArg = null; window.pkEmitConteo = function (a, c) { emitArg = { a: a, c: c }; };
    const inp = document.createElement("input"); inp.id = "pkConteoInp"; inp.value = "42"; document.body.appendChild(inp);
    pkConteoSubmit();
    out.submitEmit = !!emitArg && emitArg.a === "500" && emitArg.c === 42;
    out.submitDone = _pk.conteo.done === true;

    // ---- 4) FORMATO del evento CG (con el emit real) ----
    window.pkEmitConteo = _realEmit;
    let payload = null;
    window.enqueueReport = function (pl) { payload = pl; };
    window.trySendOneReport = function () { return Promise.resolve({ ok: false }); };
    _pk.legajo = "104";
    pkEmitConteo("500", 42);
    out.evOpcion = payload && payload.opcion;
    out.evTexto = payload && payload.texto;
    out.evId = payload && /^cg_104_500_/.test(payload.id);
    return out;
  });
  const pass = r.soloUnaCelda && r.cardCod && r.cardCelda && r.cardInput && r.cardDone &&
    r.submitEmit && r.submitDone && r.evOpcion === "CG" && r.evTexto === "500|42" && r.evId && errs.length === 0;
  console.log("pk-conteo-ciclico:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
