/* Smoke del modo scanner de picking (idea 8243, v6.75). TODO detrás del switch
   `vir_picking_scanner`. Verifica:
   - las funciones existen y el switch arranca APAGADO (OFF = app igual que hoy),
   - _pkFindByCode matchea por código y devuelve -1 para desconocidos,
   - pkOnScan "código|A" abre el input de cantidad (algunas) sobre el artículo,
   - pkOnScan "código|T" registra lo pedido (todas),
   - un código que no está en la tanda NO rompe ni marca nada. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    out.fns = ["pkScanOn", "pkScanSetOn", "pkScanToggle", "pkScanAllowedLegajo", "pkOnScan", "pkFaltaPend", "pkConfirmFaltaBatch", "_pkFindByCode", "pkScanToast"].every((n) => typeof window[n] === "function");
    try { localStorage.removeItem("vir_picking_scanner"); } catch (_e) {}
    out.defOff = (pkScanOn() === false);                 // arranca apagado
    pkScanToggle(); out.togOn = (pkScanOn() === true);
    pkScanToggle(); out.togOff = (pkScanOn() === false); // toggle ida y vuelta

    // DOM mínimo del modal para que pkRender no falle
    if (!document.getElementById("tandaModal")) {
      document.body.insertAdjacentHTML("beforeend", '<div id="tandaModal" class="show"><div class="tanda-modal-title"></div><div class="tanda-modal-body"></div></div>');
    }
    // tanda mock: 2 artículos (asignación BARE para setear el `let _pk` del script, como mva-quien con _stk)
    _pk = { tanda: "C99Z", legajo: "104", idx: 0, results: {}, mode: "item", items: [
      { art: "943E", key: "943E", esp: 12, sector: "I08" },
      { art: "323",  key: "323",  esp: 4,  sector: "A50" }
    ] };
    out.find = (_pkFindByCode("943E") === 0) && (_pkFindByCode("323") === 1) && (_pkFindByCode("999X") === -1);

    // ALGUNAS → FALTA DIFERIDO (idea 8243): NO abre input; marca faltaPend y avanza (no toca pantalla)
    try { pkOnScan("323|A"); out.algunas = (!!(_pk.faltaPend && _pk.faltaPend["323"] === true) && _pk.mode !== "fInput" && _pk.idx === 2); } catch (e) { out.algErr = String(e && e.message || e); out.algunas = false; }

    // TODAS → registra lo pedido (esp)
    try { _pk.idx = 0; _pk.mode = "item"; pkOnScan("943E|T"); out.todas = (_pk.results["943E"] === 12); } catch (e) { out.todErr = String(e && e.message || e); out.todas = false; }

    // desconocido → no rompe ni marca
    try { const before = JSON.stringify(_pk.results); pkOnScan("ZZZ|T"); out.unknown = (JSON.stringify(_pk.results) === before); } catch (e) { out.unkErr = String(e && e.message || e); out.unknown = false; }

    // ---- EAN interno (779558700=todo / 779558701=falta + NNN + check) ----
    out.num3 = (_pkNum3("943E") === "943") && (_pkNum3("27") === "027") && (_pkNum3("502T") === "502");
    const d1 = _pkDecodeEAN("7795587009432"), d2 = _pkDecodeEAN("7795587019431");
    out.eanDec = !!d1 && d1.accion === "T" && d1.nnn === "943" && !!d2 && d2.accion === "A" && d2.nnn === "943" && _pkDecodeEAN("1234567890123") === null;
    // TODO por EAN → registra sobre 943E (NNN 943)
    _pk = { tanda: "C99Z", legajo: "104", idx: 0, results: {}, mode: "item", items: [ { art: "943E", key: "943E", esp: 12, sector: "I08" }, { art: "323", key: "323", esp: 4, sector: "A50" } ] };
    try { pkOnScan("7795587009432"); out.eanTodo = (_pk.results["943E"] === 12); } catch (e) { out.eanTodoErr = String(e && e.message || e); out.eanTodo = false; }
    // FALTA por EAN → DIFERIDO: marca faltaPend sobre 943E, sin abrir input
    _pk = { tanda: "C99Z", legajo: "104", idx: 0, results: {}, mode: "item", items: [ { art: "943E", key: "943E", esp: 12, sector: "I08" }, { art: "323", key: "323", esp: 4, sector: "A50" } ] };
    try { pkOnScan("7795587019431"); out.eanFalta = (!!(_pk.faltaPend && _pk.faltaPend["943E"] === true) && _pk.mode !== "fInput"); } catch (e) { out.eanFaltaErr = String(e && e.message || e); out.eanFalta = false; }

    // BATCH al terminar (TP): con un FALTA diferido y el resto completo, pkRenderDone pide la cantidad en lote
    _pk = { tanda: "C99Z", legajo: "104", idx: 2, mode: "item", results: { "943E": 12 }, faltaPend: { "323": true }, items: [ { art: "943E", key: "943E", esp: 12, sector: "I08" }, { art: "323", key: "323", esp: 4, sector: "A50" } ] };
    try { pkRender(); const b = document.querySelector(".tanda-modal-body").innerHTML; out.batch = (/Cu.ntas cajas pusiste/i.test(b) && /id="pkBq_1"/.test(b)); } catch (e) { out.batchErr = String(e && e.message || e); out.batch = false; }
    // Confirmar el lote setea el result correcto (stub de pkFinishPicking para no disparar el envío/cierre real)
    try {
      const inp = document.getElementById("pkBq_1"); if (inp) inp.value = "3";
      const _fin = window.pkFinishPicking; window.pkFinishPicking = function () {};
      pkConfirmFaltaBatch();
      window.pkFinishPicking = _fin;
      out.batchConfirm = (_pk && _pk.results["323"] === 3 && !(_pk.faltaPend && _pk.faltaPend["323"]));
    } catch (e) { out.batchConfirmErr = String(e && e.message || e); out.batchConfirm = false; }

    // PILOTO restringido a legajos de prueba 0 y 1 (helper + toggle del operador)
    out.legGate = (pkScanAllowedLegajo("0") === true && pkScanAllowedLegajo("1") === true && pkScanAllowedLegajo("104") === false && pkScanAllowedLegajo("") === false);
    try {
      const bReal = document.createElement("div"); _pkScanOperRow(bReal, "104");   // legajo real → NO dibuja el toggle
      const bTest = document.createElement("div"); _pkScanOperRow(bTest, "0");      // legajo de prueba → sí
      out.operRowGate = (bReal.children.length === 0 && bTest.children.length === 1);
    } catch (e) { out.operRowErr = String(e && e.message || e); out.operRowGate = false; }

    pkScanSetOn(false);
    return out;
  });
  await b.close();
  const ok = r.fns && r.defOff && r.togOn && r.togOff && r.find && r.algunas && r.todas && r.unknown && r.num3 && r.eanDec && r.eanTodo && r.eanFalta && r.batch && r.batchConfirm && r.legGate && r.operRowGate && errs.length === 0;
  console.log("pk-scan:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", ok ? "✓ OK" : "✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
