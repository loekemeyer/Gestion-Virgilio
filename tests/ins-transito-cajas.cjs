/* v30.86 (Luis, 14/10) — tres cosas del mismo pedido (v30.87: + Ubicar de Tránsito; v31.05: códigos como botones,
   sub-pestañas, los insumos con stock sin lugar también en Tránsito, clase de lugar góndola/rack/SC y SP, sin emojis):
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
        { sector: "AGUARDAR", cod: "328E", emp: "LK", descripcion: "art", cantidad: 12, unidad: "caj", origen: "a_guardar" },
        { sector: "TRANSITO", cod: "N°19", emp: "IN", descripcion: "Fleje 13,6", cantidad: 144, unidad: "Kg", origen: "transito" },
        { sector: "TRANSITO", cod: "Caja Nº 8", emp: "IN", descripcion: "caja", cantidad: 50, unidad: "Cajas", origen: "transito" },
        { sector: "TRANSITO", cod: "N°94", emp: "IN", descripcion: "Fleje", cantidad: 835, unidad: "Kg", origen: "sin_lugar", ref_id: 77 }];
      if (/gv_rack_celda/.test(u)) return [{ sector: "X20", rack: "X", estado: "libre" }, { sector: "IN-F3", rack: "IN", estado: "libre" }];
      if (/gv_scp_celda/.test(u)) return [{ sector: "IN-F3", col: "F", fila: 3, estado: "libre" }];
      if (/gv_planimetria_celda/.test(u)) return [{ sector: "F03", gondola: "F", celda: 3, estado: "libre" }];
      return [];
    };
    window.__isSupervisor = true;
    try { await openPlanimMapa(); } catch (_e) {}
    const modos = Array.from(document.querySelectorAll(".pmap-modos .pmap-modo")).map(function (x) { return x.textContent; });
    pmapModo("transito");
    for (let i = 0; i < 50 && !_ptr; i++) await new Promise(function (s) { setTimeout(s, 20); });
    pmapRender();
    const tabs = document.getElementById("pmapTabs").innerText, grid1 = document.getElementById("pmapGrid").innerText;
    ptrGo("TRANSITO");
    const grid2 = document.getElementById("pmapGrid").innerText;
    // v30.87: de Tránsito se sale UBICANDO (gv_transito_ubicar), con posición y cantidad, sin pasarse de lo que hay
    // v31.05: cada código es un BOTÓN (como las celdas de los otros modos); A guardar se ve pero no se ubica desde acá
    out.btnsTr = document.querySelectorAll("#pmapGrid button.ptr-cell").length;
    out.subtabs = document.getElementById("pmapTabs").classList.contains("pmap-subtabs");
    ptrGo("AGUARDAR"); out.btnsAg = document.querySelectorAll("#pmapGrid button.ptr-cell").length; ptrGo("TRANSITO");
    let rpc = null; window.pmapRpc = async function (fn, body) { rpc = { fn: fn, body: body }; return { ok: true, data: { sector: body.p_sector } }; };
    const iN = _ptr.findIndex(function (x) { return x.cod === "N°19"; });
    ptrUbicarAbrir(iN); ptrClase("rack");
    document.getElementById("ptrUbSec").value = "X20"; document.getElementById("ptrUbCant").value = "500";
    await ptrUbicarOk(); const frenoTope = rpc === null;
    document.getElementById("ptrUbCant").value = "100";
    await ptrUbicarOk();
    out.ubicar = out.btnsTr === 3 && out.btnsAg === 0 && frenoTope && !!rpc && rpc.fn === "gv_transito_ubicar" &&
      rpc.body.p_cod === "N°19" && rpc.body.p_cantidad === 100 && rpc.body.p_sector === "X20" && rpc.body.p_unidad === "Kg";
    // v31.05: el insumo con stock SIN LUGAR se ubica por gv_insumo_posicion_guardar y reemplaza el lugar inexistente;
    // la clase elegida manda: «F3» con Góndola va a la celda F03, no a la IN-F3 de SC y SP
    rpc = null;
    const iS = _ptr.findIndex(function (x) { return x.cod === "N°94"; });
    ptrUbicarAbrir(iS); ptrClase("gondola");
    document.getElementById("ptrUbSec").value = "Z99"; await ptrUbicarOk(); const frenoClase = rpc === null;
    document.getElementById("ptrUbSec").value = "F3"; await ptrUbicarOk();
    out.sinLugar = frenoClase && !!rpc && rpc.fn === "gv_insumo_posicion_guardar" && rpc.body.p_sector === "F03" &&
      rpc.body.p_cod === "N°94" && rpc.body.p_cantidad === 835 && rpc.body.p_reemplaza_id === 77;
    out.rpcSin = rpc;
    // y sin emojis en todo el módulo (Luis, 15/10)
    const txtMod = document.getElementById("planimMapaOverlay").innerText + " " + document.getElementById("pmapSearch").placeholder;
    out.sinEmoji = !/[\u{1F300}-\u{1FAFF}\u2600-\u27BF\uFF0B\uFE62]/u.test(txtMod);
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
    // v30.90 (Luis, 15/10): al ENTREGAR también se puede escribir a mano una caja que no está; otra categoría, no
    _ins.cat = "cajas"; insRender();
    const htmlEiCj = document.getElementById("insBody").innerHTML;
    insNuevoOpen("fleje"); const eiFlejeNo = _ins.nuevo === null;
    insNuevoOpen("cajas"); const eiCajaSi = !!_ins.nuevo && /Sale una caja/.test(document.getElementById("insBody").innerHTML);
    insNuevoCancel();
    out.eiAlta = /ins-itbtn add/.test(htmlEiCj) && eiFlejeNo && eiCajaSi;
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
  const ok = r.a && r.ubicar && r.subtabs && r.sinLugar && r.sinEmoji && r.b && r.c && r.eiAlta && !errs.length;
  console.log("ins-transito-cajas:", JSON.stringify(r), errs.length ? "· errores: " + errs.join(" | ") : "· pageerrors: none", ok ? "· ✓ OK" : "· ✗ FALLA");
  process.exit(ok ? 0 : 1);
})();
