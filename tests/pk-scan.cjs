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
    out.fns = ["pkScanOn", "pkScanSetOn", "pkScanToggle", "pkOnScan", "_pkFindByCode", "pkScanToast"].every((n) => typeof window[n] === "function");
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

    // ALGUNAS → input de cantidad sobre el artículo escaneado
    try { pkOnScan("323|A"); out.algunas = (_pk.idx === 1 && _pk.mode === "fInput"); } catch (e) { out.algErr = String(e && e.message || e); out.algunas = false; }

    // TODAS → registra lo pedido (esp)
    try { _pk.idx = 0; _pk.mode = "item"; pkOnScan("943E|T"); out.todas = (_pk.results["943E"] === 12); } catch (e) { out.todErr = String(e && e.message || e); out.todas = false; }

    // desconocido → no rompe ni marca
    try { const before = JSON.stringify(_pk.results); pkOnScan("ZZZ|T"); out.unknown = (JSON.stringify(_pk.results) === before); } catch (e) { out.unkErr = String(e && e.message || e); out.unknown = false; }

    pkScanSetOn(false);
    return out;
  });
  await b.close();
  const ok = r.fns && r.defOff && r.togOn && r.togOff && r.find && r.algunas && r.todas && r.unknown && errs.length === 0;
  console.log("pk-scan:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join(" | ") : "none", "·", ok ? "✓ OK" : "✗ FALLÓ");
  process.exit(ok ? 0 : 1);
})();
