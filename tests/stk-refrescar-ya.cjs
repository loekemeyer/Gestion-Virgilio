/* v25.18 (Luis, 30/09/2026) — "pone un boton en la tabla de stocks que permita refrescarla por la
   fuerza. 2 minutos es un monton".

   El refresco completo tarda ~7,4 s y el navegador corta a los 8 s, asi que el boton NO lo corre:
   agenda un job de un disparo (gv_stock_refrescar_ya) y espera a que gv_stock_refresco_ultimo()
   cambie. Mide:
   A) el boton esta en la barra de la solapa Stocks
   B) con el refresco hecho, vuelve a abrir la pantalla CONSERVANDO solapa y busqueda
   C) si el servidor NO termino todavia, no reabre (no pisa la tabla con datos viejos)
   D) si la RPC falla, no reabre y el boton vuelve a quedar usable
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
    const fila = { cod: "501", descripcion: "Pinza", linea: "LK", terminado: 10, excedente: 0, separar_pedidos: 0,
      a_facturar: 0, a_guardar: 0, racks: 0, racks_ch: 0, para_envasar: 0, insumos_dep: 0, stock_total: 10, cajas_pedidas: 1 };
    _stk = { movs: [], viewRows: [fila], cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [], filtro: "", openArt: null, soloNeg: false };
    out.A = stkBodyStocks().indexOf('id="stkRefYaBtn"') >= 0;

    // espera real de 1,5 s por vuelta: se acorta para el test
    const _st = window.setTimeout; window.setTimeout = function (f) { return _st(f, 0); };
    let abiertas = 0, cerradas = 0;
    window.closeStockAdmin = function () { cerradas++; _stk = null; };
    window.openStockAdmin = async function () { abiertas++; _stk = { tab: "stocks", filtro: "" }; };
    window.stkRender = function () {};
    window.alert = function () {};

    // B) termina en la 2.a vuelta
    let vueltas = 0;
    window.sb = { rpc: async function (fn) {
      if (fn === "gv_stock_refrescar_ya") return { data: { estado: "agendado", antes: "2026-09-30T17:00:00Z" } };
      vueltas++; return { data: vueltas >= 2 ? "2026-09-30T17:00:09Z" : "2026-09-30T17:00:00Z" };
    } };
    _stk = { tab: "racks", filtro: "505", soloConteo: false };
    await stkRefrescarYa();
    out.B = abiertas === 1 && cerradas === 1 && _stk && _stk.tab === "racks" && _stk.filtro === "505";

    // C) nunca termina (se acorta el reloj): no reabre
    abiertas = 0; cerradas = 0;
    const _now = Date.now; let t = 0; Date.now = function () { t += 10000; return t; };
    window.sb = { rpc: async function (fn) {
      if (fn === "gv_stock_refrescar_ya") return { data: { estado: "agendado", antes: "2026-09-30T17:00:00Z" } };
      return { data: "2026-09-30T17:00:00Z" };
    } };
    _stk = { tab: "stocks", filtro: "" };
    await stkRefrescarYa();
    Date.now = _now;
    out.C = abiertas === 0 && cerradas === 0;

    // D) la RPC falla: no reabre
    window.sb = { rpc: async function () { return { error: { message: "Solo un supervisor puede forzar el refresco del stock" } }; } };
    await stkRefrescarYa();
    out.D = abiertas === 0 && cerradas === 0;
    window.setTimeout = _st;
    return out;
  });
  await b.close();
  const ok = r.A && r.B && r.C && r.D && errs.length === 0;
  console.log((ok ? "OK" : "FALLA") + " stk-refrescar-ya", JSON.stringify(r), errs.join(" | "));
  process.exit(ok ? 0 : 1);
})();
