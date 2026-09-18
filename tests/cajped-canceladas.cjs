/* Regresión v12.22 — pop-up "🟡 Cajas pedidas" de un artículo (stkOpenCajasPedidasArt):
   F1) Descuenta las NP CANCELADAS (NP_Canceladas, la operadora las marcó 🚫 "no va"), igual
       que la columna (vista_stock_procesada.cajas_pedidas) y ocgDemanda(). Antes NO las
       filtraba: mostraba cajas fantasma de pedidos cancelados (ej. NP 44458 de Dorinka con
       18 cajas del art 719) y encima las marcaba ⚠ "sin programar en el PPP" — una NP
       cancelada nunca se programa, así que el ⚠ era siempre falso.
   F2) Razón Social con fallback a PPP_Base_Pedidos.cliente cuando la NP no está en
       Programación Diaria (antes la celda quedaba vacía → "pedido sin nombre de cliente").
   F3) v19.65 — el pop-up muestra TAMBIÉN los pedidos de la WEB. Thomas, 18/09: *"¿por qué ahí
       dice que pide 198 pero cuando entro veo solo tres cajas? algo está mal"*. La fuente era
       `gv_ppp_base_pedidos` (SOLO el espejo de ISIS), así que las NP de la página —que se
       llaman "LK 0025" y viven en otra tabla— no aparecían: en el 321 mostraba 3 cajas de 2 NP
       cuando había 13 NP web más con 194. Ahora lee `gv_demanda_pedidos` (ISIS + web) y la
       programación sale de `gv_np_prog_info` (las dos programaciones + razón social), así que
       una NP web tampoco queda marcada ⚠ "sin programar". Las filas van ordenadas por DÍA.
   Todo con fetch stubbeado (sin red). Sale 1 si falla. */
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
    window.alert = function () {};
    function J(data) {
      return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } });
    }
    _stk = { movs: [], viewRows: [] };   // `let _stk` global: asignar sin window
    window.getEmpleadosNombres = async function () { return new Map(); };
    window.fetch = function (url) {
      url = String(url);
      // v19.65: la demanda sale de gv_demanda_pedidos (ISIS + WEB), no del espejo de ISIS
      if (url.indexOf("gv_demanda_pedidos") >= 0) return J([
        { pedido: "44458",   cajas: 18, articulo: "719", origen: "isis" }, // CANCELADA
        { pedido: "44593",   cajas: 6,  articulo: "719", origen: "isis" }, // sin programar (fallback de RS)
        { pedido: "44600",   cajas: 16, articulo: "719", origen: "isis" }, // programada
        { pedido: "44700",   cajas: 5,  articulo: "719", origen: "isis" }, // ya facturada
        { pedido: "LK 0053", cajas: 80, articulo: "719", origen: "web"  }  // F3: la de la página
      ]);
      // el fallback de Razón Social sigue saliendo de la base de ISIS (no tiene las web)
      if (url.indexOf("ppp_base_pedidos") >= 0) return J([
        { pedido: "44458", cliente: "Dorinka S.R.L" },
        { pedido: "44593", cliente: "Aguilar Maria Co" },
        { pedido: "44600", cliente: "Dorinka S.R.L" },
        { pedido: "44700", cliente: "Facturado SA" }
      ]);
      if (url.indexOf("NP_Canceladas") >= 0) return J([{ np: "44458" }]);
      if (url.indexOf("Facturacion_NP") >= 0) return J([{ np: "44700" }]);
      if (url.indexOf("ppp_entregados_meta") >= 0) return J([]);
      // v19.65: las dos programaciones juntas, con la web incluida
      if (url.indexOf("gv_np_prog_info") >= 0) return J([
        { np: "44600",   tanda: "D58A", razon_social: "Dorinka S.R.L",   fecha_entrega: "2026-09-03" },
        { np: "LK 0053", tanda: "E17B", razon_social: "Orfali Alfredo",  fecha_entrega: "2026-09-22" }
      ]);
      return J([]);
    };

    await stkOpenCajasPedidasArt(encodeURIComponent("719"));
    const rows = (_stkPop && _stkPop.rows) || [];
    const html = document.getElementById("stkPopBody").innerHTML;

    out.nps = rows.map(function (x) { return x.np; }).join(",");
    /* F1 + F3: 44458 (cancelada) y 44700 (facturada) fuera; quedan 44593 + 44600 + LK 0053.
       v19.65: ordenadas por DÍA de entrega — 44600 el 03/09, LK 0053 el 22/09, y la sin fecha
       (44593) al final. Si alguien vuelve a ordenar por número de NP, esto falla. */
    out.sinCancelada = out.nps === "44600,LK 0053,44593";
    out.total = rows.reduce(function (s, x) { return s + x.pidio; }, 0);
    out.totalOk = out.total === 102;   // 6 + 16 + 80
    // F3: la NP web está, con su origen, su tanda y SIN el ⚠ de "sin programar"
    var _web = rows.filter(function (x) { return x.np === "LK 0053"; })[0];
    out.webEsta = !!_web && _web.pidio === 80 && _web.origen === "web"
      && _web.tanda === "E17B" && _web.sinProg === false;
    out.webEnHtml = html.indexOf("LK 0053") >= 0 && html.indexOf(">WEB<") >= 0;
    out.hintCancel = html.indexOf("1 NP canceladas (🚫 no va)") >= 0;
    out.hintFact = html.indexOf("1 NP ya facturadas/entregadas") >= 0;
    // el ⚠ "sin programar" ya no se dispara por una cancelada: sólo la 44593 queda marcada
    out.spNps = rows.filter(function (x) { return x.sinProg; }).map(function (x) { return x.np; }).join(",");
    out.spOk = out.spNps === "44593";

    // F2: Razón Social — de la PPP la programada, de la base de pedidos la que no está en la PPP
    const byNp = {}; rows.forEach(function (x) { byNp[x.np] = x; });
    out.rs44600 = byNp["44600"] && byNp["44600"].rs;
    out.rs44593 = byNp["44593"] && byNp["44593"].rs;
    out.rsOk = out.rs44600 === "Dorinka S.R.L" && out.rs44593 === "Aguilar Maria Co";
    out.rsEnHtml = html.indexOf("Aguilar Maria Co") >= 0;

    // caso borde: si TODAS las NP están canceladas/facturadas, el pop-up lo dice y no rompe
    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("gv_demanda_pedidos") >= 0) return J([{ pedido: "44458", cajas: 18, articulo: "719", origen: "isis" }]);
      if (url.indexOf("ppp_base_pedidos") >= 0) return J([{ pedido: "44458", cliente: "Dorinka S.R.L" }]);
      if (url.indexOf("NP_Canceladas") >= 0) return J([{ np: "44458" }]);
      return J([]);
    };
    await stkOpenCajasPedidasArt(encodeURIComponent("719"));
    const html2 = document.getElementById("stkPopBody").innerHTML;
    out.todoCancelado = html2.indexOf("1 canceladas") >= 0 && html2.indexOf("44458") < 0;
    return out;
  });
  const pass = r.sinCancelada && r.totalOk && r.hintCancel && r.hintFact && r.spOk &&
    r.rsOk && r.rsEnHtml && r.todoCancelado && r.webEsta && r.webEnHtml && errs.length === 0;
  console.log("cajped-canceladas:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
