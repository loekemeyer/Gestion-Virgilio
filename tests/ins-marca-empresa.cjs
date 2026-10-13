/* v29.56 (Luis, 13/10) — al RECIBIR insumos se marca de qué empresa vienen, en TODA categoría
   (antes sólo en cajas, v29.31). No parte el stock: el movimiento sigue siendo el mismo insumo
   en el mismo lugar (empresa `Mixto` la fuerza el trigger) y la marca queda en la descripción.
   (a) el pop-up de cantidad pide la marca en una categoría que NO es cajas (fleje), con «Mixto»;
   (b) cajas sigue con Loeke/Chef, sin «Mixto»;
   (c) sin marca NO se registra: insConfirmar no llama a stockMove;
   (d) con marca sí, y la descripción dice «· marca …»;
   (e) al ENTREGAR (EI) no se pide marca y el envío sale igual.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    window.alert = function () {};
    const CATS = [["fleje", "🧵 Flejes", ["Kg"]], ["cajas", "📦 Cajas", ["Uni", "Paquetes"]]];
    window.insLoadMeta = async function () { INS_CATS = CATS.map(function (c) { return { k: c[0], lbl: c[1], unis: c[2], desc: "" }; }); };
    window.insFetchCatalogo = async function () { return [
      { cod: "N°2", nombre: "65 x 1,25 · Fleje N° 2", categoria: "fleje", ubicacion: "K04" },
      { cod: "Caja Nº 29", nombre: "Caja Nº 29", categoria: "cajas", ubicacion: "" }
    ]; };
    window.stockFetchSaldos = async function () { return {}; };
    window.insFetchSaldosXUni = async function () { return {}; };
    window._insGp2Opciones = async function () {};
    const out = {};

    // ── RECIBIR, categoría fleje ───────────────────────────────────────────────
    window._insRiCat = "fleje";
    await showInsumoModal("RI", "104");
    const iF = _ins.items.findIndex(function (x) { return x.cod === "N°2"; });
    _ins.items[iF].qty = 300; _ins.items[iF].unidad = "Kg";
    _ins.qty = iF; insRender();
    let h = document.getElementById("insBody").innerHTML;
    out.a = /Marca:/.test(h) && />Loeke</.test(h) && />Chef</.test(h) && />Mixto</.test(h) && /elegí de qué empresa viene/.test(h);

    // ── (c) sin marca no se registra ──────────────────────────────────────────
    let mov = null; const _sm = window.stockMove; window.stockMove = function (rows) { mov = rows; };
    _ins.qty = null;
    await insConfirmar();
    out.c = mov === null && !!_ins;   // frenó y el modal sigue abierto

    // ── (d) con marca sí, y queda escrita ─────────────────────────────────────
    _ins.items[iF].marca = "Chef";
    await insConfirmar();
    window.stockMove = _sm;
    out.d = !!mov && mov.length === 1 && mov[0].cod_art === "N°2" && mov[0].delta === 300 &&
            mov[0].tipo === "recepcion_insumo" && / marca Chef/.test(mov[0].descripcion || "");

    // ── (b) cajas: Loeke/Chef, sin Mixto ──────────────────────────────────────
    window._insRiCat = "cajas";
    await showInsumoModal("RI", "104");
    const iC = _ins.items.findIndex(function (x) { return x.cod === "Caja Nº 29"; });
    _ins.items[iC].qty = 10; _ins.qty = iC; insRender();
    h = document.getElementById("insBody").innerHTML;
    out.b = /Marca:/.test(h) && />Loeke</.test(h) && />Chef</.test(h) && !/>Mixto</.test(h) &&
            /elegí si las cajas son de Loeke o de Chef/.test(h);

    // ── (e) ENTREGAR: no se pide marca ────────────────────────────────────────
    window._insRiCat = "";
    await showInsumoModal("EI", "104");
    const iE = _ins.items.findIndex(function (x) { return x.cod === "N°2"; });
    _ins.items[iE].qty = 5; _ins.items[iE].unidad = "Kg";
    _ins.qty = iE; insRender();
    const hE = document.getElementById("insBody").innerHTML;
    let mov2 = null; const _sm2 = window.stockMove; window.stockMove = function (rows) { mov2 = rows; };
    _ins.qty = null; window._insUbicacion = "Cervantes";
    await insConfirmar(); window.stockMove = _sm2;
    out.e = !/Marca:/.test(hE) && !!mov2 && mov2[0].delta === -5 && !/ marca /.test(mov2[0].descripcion || "");
    return out;
  });
  const pass = r.a && r.b && r.c && r.d && r.e && errs.length === 0;
  console.log("ins-marca-empresa:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
