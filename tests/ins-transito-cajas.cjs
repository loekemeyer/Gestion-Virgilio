/* v30.86 (Luis, 14/10) — tres cosas del mismo pedido:
   (a) el Mapa tiene la pestaña 🚚 Tránsito con sus DOS sectores (A guardar · Tránsito), leídos de gv_transito_celda;
   (b) la RECEPCIÓN de un insumo se graba con ubicacion = 'TRANSITO' (la base lo sostiene con aa_gv_insumo_recepcion_transito);
   (c) al ENTREGAR, la lista de cajas trae TODAS las cajas de GP2 (Sector Caja), no sólo las que Virgilio ya tiene;
       y los demás rubros de GP2 no se suman a la entrega.
   Sin red: todo lo que pide la base va stubeado. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); } catch (_e) { ({ chromium } = require("playwright")); }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage(); const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**://**", (r) => (/^file:/.test(r.request().url()) ? r.continue() : r.abort()));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {};
    // (a) pestaña Tránsito
    window.supaFetchAllSafe = async function (u) {
      if (/gv_transito_celda/.test(u)) return [
        { sector: "AGUARDAR", cod: "328E", emp: "LK", descripcion: "art", cantidad: 12, unidad: "caj" },
        { sector: "TRANSITO", cod: "N°19", emp: "IN", descripcion: "Fleje 13,6", cantidad: 144, unidad: "Kg" },
        { sector: "TRANSITO", cod: "Caja Nº 8", emp: "IN", descripcion: "caja", cantidad: 50, unidad: "Cajas" }];
      return [];
    };
    try { openPlanimMapa(); } catch (_e) {}
    const modos = Array.from(document.querySelectorAll(".pmap-modos .pmap-modo")).map(function (x) { return x.textContent; });
    pmapModo("transito");
    for (let i = 0; i < 50 && !_ptr; i++) await new Promise(function (s) { setTimeout(s, 20); });
    pmapRender();
    const tabs = document.getElementById("pmapTabs").innerText, grid1 = document.getElementById("pmapGrid").innerText;
    ptrGo("TRANSITO");
    const grid2 = document.getElementById("pmapGrid").innerText;
    out.a = /Tránsito/.test(modos[3] || "") && /A guardar/.test(tabs) && /Tránsito/.test(tabs) &&
            /328E/.test(grid1) && !/N°19/.test(grid1) && /N°19/.test(grid2) && /Caja Nº 8/.test(grid2);
    pmapModo("gondola");
    // (b) + (c)
    const CATS = [["cajas", "📦 Cajas"], ["fleje", "🧵 Flejes"]];
    window.insLoadMeta = async function () { INS_CATS = CATS.map(function (c) { return { k: c[0], lbl: c[1], unis: [], desc: "" }; }); };
    window.insFetchCatalogo = async function () { return [
      { cod: "Caja Nº 1", nombre: "Caja N°1", categoria: "cajas", ubicacion: "Q30" },
      { cod: "F10", nombre: "121 X 1,20", categoria: "fleje", ubicacion: "K04" }]; };
    window.stockFetchSaldos = async function () { return { "F10": { insumos: 50 } }; };
    window.insFetchSaldosXUni = async function () { return {}; };
    window.insFetchGp2Ri = async function () { return [
      { comp_id: 456, codigo: "A1", nombre: "Caja N°1", categoria: "cajas", cod_virgilio: "Caja Nº 1" },
      { comp_id: 999, codigo: "A99", nombre: "Caja N°8", categoria: "cajas", cod_virgilio: null },
      { comp_id: 777, codigo: "FX", nombre: "fleje gp2", categoria: "fleje", cod_virgilio: null }]; };
    window.insFetchFlejeProv = async function () { return null; };
    window._insGp2 = null; window._insEnvioSub = "otros";
    await showInsumoModal("EI", "104");
    const cajas = _ins.items.filter(function (x) { return x.cat === "cajas"; }).map(function (x) { return x.cod || x.gp2Cod; }).sort();
    out.c = JSON.stringify(cajas) === JSON.stringify(["A99", "Caja Nº 1"]) && !_ins.items.some(function (x) { return x.gp2Cod === "FX"; });
    out.cajas = cajas;
    insAnular && (function () { try { _ins = null; document.getElementById("insModal").classList.remove("show"); } catch (_e) {} })();
    window._insRiCat = "fleje"; window._insGp2 = null; window._insDoc = { tipo: "remito", remito: "R-1" };
    await showInsumoModal("RI", "104");
    const i = _ins.items.findIndex(function (x) { return x.cod === "F10"; });
    _ins.items[i].qty = 3; _ins.items[i].unidad = "Kg"; _ins.items[i].marca = "Loeke";
    let mov = null; const sm = window.stockMove; window.stockMove = function (rows) { mov = rows; };
    try { await insConfirmar(); } catch (_e) {}
    window.stockMove = sm;
    out.b = !!(mov && mov[0] && mov[0].ubicacion === "TRANSITO" && mov[0].tipo === "recepcion_insumo");
    out.mov = mov && mov[0];
    return out;
  });
  await b.close();
  const ok = r.a && r.b && r.c && !errs.length;
  console.log("ins-transito-cajas:", JSON.stringify(r), errs.length ? "· errores: " + errs.join(" | ") : "· pageerrors: none", ok ? "· ✓ OK" : "· ✗ FALLA");
  process.exit(ok ? 0 : 1);
})();
