/* Regresión — MG "De los racks" (rkbConfirmar), semántica v9.60:
   la bajada del operario mueve el stock INMEDIATAMENTE (racks − / terminado +,
   vía stockMove) y deja la fila en Racks_Bajadas con estado='aprobada' (historial,
   NO entra a la cola de aprobación). v9.27 además muestra un modal con código de
   4 dígitos que hay que confirmar (#rkbVerifyOk) antes de que pase nada.
   Verifica: 1 llamada a stockMove con los 2 movimientos en INNER (master × CxM),
   POST a Racks_Bajadas con estado='aprobada' y cajas en INNER. Sale 1 si falla.
   (Historia: hasta v9.59 esto PROPONÍA — estado='propuesta', sin stockMove — y el
   test viejo validaba eso; se actualizó cuando v9.60 cambió el flujo a pedido del dueño.) */
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
    const bajPost = fetches.find(function (f) { return f.url.indexOf("Racks_Bajadas") >= 0; });
    let parsed = null; try { parsed = bajPost ? JSON.parse(bajPost.body) : null; } catch (_e) {}
    return { stockMoveCalled: stockMoveCalled, movs: movs, postedToBajadas: !!bajPost, row: (parsed && parsed[0]) || null };
  });
  if (r.err) { console.log("racks-propuesta:", JSON.stringify(r), "· ✗ FAIL"); await b.close(); process.exit(1); }
  const row = r.row || {};
  const movs = r.movs || [];
  const mRacks = movs.find(function (m) { return m.deposito === "racks"; }) || {};
  const mGond  = movs.find(function (m) { return m.deposito === "terminado"; }) || {};
  const pass = r.stockMoveCalled === 1 && movs.length === 2 &&
    Number(mRacks.delta) === -24 && Number(mGond.delta) === 24 && mRacks.tipo === "baja_racks" &&
    r.postedToBajadas === true &&
    row.estado === "aprobada" && Number(row.cajas) === 24 && String(row.cod_art) === "590E" &&
    (row.orden_id === null || row.orden_id === undefined) && !!row.aprobada_at && errs.length === 0;
  console.log("racks-propuesta:", JSON.stringify({ stockMoveCalled: r.stockMoveCalled, movsLen: movs.length, racksDelta: mRacks.delta, gondDelta: mGond.delta, postedToBajadas: r.postedToBajadas, row: row }), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
