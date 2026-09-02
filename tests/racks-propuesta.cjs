/* Regresión — MG "De los racks" (rkbConfirmar), semántica v12.35:
   la bajada del operario se registra ATÓMICAMENTE en el server vía UN solo RPC
   (registrar_baja_racks): la fila de Racks_Bajadas 'aprobada' + los 2 movimientos
   de stock (racks − / terminado +, en INNER = master × CxM) en una transacción.
   v9.27 muestra un modal con código de 4 dígitos que hay que confirmar (#rkbVerifyOk)
   antes de que pase nada.
   Verifica: NO llama stockMove ni postea directo a Racks_Bajadas; llama al RPC
   registrar_baja_racks con p_items[0] = {cod_art:590E, cajas:24 (inner), orden_id
   null}. Sale 1 si falla.
   (Historia: hasta v9.59 esto PROPONÍA (estado='propuesta', sin mover stock); v9.60
   pasó a mover stock al toque con 2 POST sueltos (stockMove + POST Racks_Bajadas);
   v12.35 unificó esos 2 POST en un RPC atómico e idempotente para que no queden a
   medias — bajada 'aprobada' sin descuento de racks era el descuadre que motivó el cambio.) */
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
    window.alert = function () {};
    // Stubs para armar _rkb sin red (showRacksBajarModal solo llama estas 3).
    window.stockFetchSaldos = async function () { return { "590E": { cod: "590E", desc: "Aceitera", racks: 100 } }; };
    window.loadArtNombres = async function () { return; };
    window.rkbFetchCxM = async function () { return { cxm: { "590E": 12 }, locs: {} }; };
    let stockMoveCalled = 0; let movs = null; const fetches = [];
    window.stockMove = function (m) { stockMoveCalled++; movs = m; };
    window.fetch = function (url, opts) {
      fetches.push({ url: String(url), body: (opts && opts.body) || null });
      return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve([]); } });
    };
    await showRacksBajarModal("237");
    if (typeof _rkb === "undefined" || !_rkb || !_rkb.items || !_rkb.items.length) return { err: "no _rkb" };
    const it = _rkb.items.find(function (x) { return String(x.cod).toUpperCase() === "590E"; });
    if (!it) return { err: "no 590E item" };
    it.baja = 2;    // 2 master; cxm 12 → inner 24
    it.sec = null;  // sin ubicación → no dispara la RPC de planimetría
    const done = rkbConfirmar();
    // v9.27: modal de verificación (código en el rack) — confirmarlo como el operario
    await new Promise(function (res) { setTimeout(res, 30); });
    const okBtn = document.getElementById("rkbVerifyOk");
    if (!okBtn) return { err: "no modal verificación (#rkbVerifyOk)" };
    okBtn.click();
    await done;
    await new Promise(function (res) { setTimeout(res, 10); });
    const rpcCall = fetches.find(function (f) { return f.url.indexOf("rpc/registrar_baja_racks") >= 0; });
    let parsed = null; try { parsed = rpcCall ? JSON.parse(rpcCall.body) : null; } catch (_e) {}
    const item = (parsed && parsed.p_items && parsed.p_items[0]) || null;
    const directBaj = fetches.find(function (f) { return f.url.indexOf("/Racks_Bajadas") >= 0; });
    return { stockMoveCalled: stockMoveCalled, rpcCalled: !!rpcCall, directBajPost: !!directBaj, item: item };
  });
  if (r.err) { console.log("racks-propuesta:", JSON.stringify(r), "· ✗ FAIL"); await b.close(); process.exit(1); }
  const item = r.item || {};
  const pass = r.stockMoveCalled === 0 && r.rpcCalled === true && r.directBajPost === false &&
    String(item.cod_art) === "590E" && Number(item.cajas) === 24 &&
    (item.orden_id === null || item.orden_id === undefined) && errs.length === 0;
  console.log("racks-propuesta:", JSON.stringify({ stockMoveCalled: r.stockMoveCalled, rpcCalled: r.rpcCalled, directBajPost: r.directBajPost, item: item }), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
