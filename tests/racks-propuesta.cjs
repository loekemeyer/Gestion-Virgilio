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
   medias — bajada 'aprobada' sin descuento de racks era el descuadre que motivó el cambio.)
   v24.68 (Thomas, D23/D24): sin POSICIÓN no se registra; lo que no entra en góndola va a
   EXCEDENTE (campo `excedente`), y después del código se pide el CONTEO A CIEGAS del rack y de la
   góndola (`conteo_rack` en inner, `conteo_gondola` en cajas).
   v25.74 (Luis, 01/10): «Bajar de Racks» es su propio módulo (botón chico #row3b debajo de MG, ya no
   está en el chooser) y baja a A GUARDAR (`destino: 'a_guardar'`): sin excedente ni conteo de góndola. */
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
    window.ocgFetchCapacidad = async function () { return { "590E": 30 }; };   // góndola: entran 30, hay 10 → 20 de lugar
    window.stockFetchSaldos = async function () { return { "590E": { cod: "590E", desc: "Aceitera", racks: 100, terminado: 10 } }; };
    window.confirm = function () { return true; };
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
    it.sec = "";    // (A) sin posición → no se registra nada
    await Promise.race([rkbConfirmar(), new Promise(function (res) { setTimeout(res, 300); })]);
    if (document.getElementById("rkbVerifyOk")) return { err: "sin posición igual abrió el modal" };
    if (fetches.some(function (f) { return f.url.indexOf("rpc/registrar_baja_racks") >= 0; })) return { err: "sin posición igual llamó al RPC" };
    it.sec = "AD05";
    const done = rkbConfirmar();
    // v9.27: modal de verificación (código en el rack) — confirmarlo como el operario
    await new Promise(function (res) { setTimeout(res, 30); });
    const okBtn = document.getElementById("rkbVerifyOk");
    if (!okBtn) return { err: "no modal verificación (#rkbVerifyOk)" };
    okBtn.click();
    await new Promise(function (res) { setTimeout(res, 30); });
    const r0 = document.getElementById("rkcR0"), g0 = document.getElementById("rkcG0");
    if (!r0) return { err: "no pidió el conteo a ciegas del rack" };
    if (g0) return { err: "v25.74: va a A guardar, no tiene que pedir el conteo de góndola" };
    r0.value = "5";
    document.getElementById("rkcOk").click();
    await done;
    await new Promise(function (res) { setTimeout(res, 10); });
    const rpcCall = fetches.find(function (f) { return f.url.indexOf("rpc/registrar_baja_racks") >= 0; });
    let parsed = null; try { parsed = rpcCall ? JSON.parse(rpcCall.body) : null; } catch (_e) {}
    const item = (parsed && parsed.p_items && parsed.p_items[0]) || null;
    const directBaj = fetches.find(function (f) { return f.url.indexOf("/Racks_Bajadas") >= 0; });
    // v25.74: el chooser de MG ya no tiene «De los racks» y la botonera tiene el botón chico propio
    showMGChooser("237");
    const ch = document.getElementById("mgChooserModal");
    const sinRacks = !!ch && ch.innerHTML.indexOf("De los racks") < 0 && ch.innerHTML.indexOf("mgChooserGo('racks')") < 0;
    closeMGChooser();
    const bx = document.querySelector('#row4 [data-code="RKBM"]');   // v25.77: «BR» chico con las secundarias
    const btn = bx && bx.querySelector(".box-title").textContent.trim() === "BR" && bx.classList.contains("box-sm") && !document.getElementById("row3b");
    return { stockMoveCalled: stockMoveCalled, rpcCalled: !!rpcCall, directBajPost: !!directBaj, item: item, sinRacks: sinRacks, btn: !!btn };
  });
  if (r.err) { console.log("racks-propuesta:", JSON.stringify(r), "· ✗ FAIL"); await b.close(); process.exit(1); }
  const item = r.item || {};
  const pass = r.stockMoveCalled === 0 && r.rpcCalled === true && r.directBajPost === false &&
    String(item.cod_art) === "590E" && Number(item.cajas) === 24 &&
    (item.orden_id === null || item.orden_id === undefined) && errs.length === 0 &&
    String(item.sector) === "AD05" && Number(item.excedente) === 0 &&
    Number(item.conteo_rack) === 60 && item.conteo_gondola === null && item.destino === "a_guardar" &&
    r.sinRacks === true && r.btn === true;
  console.log("racks-propuesta:", JSON.stringify({ stockMoveCalled: r.stockMoveCalled, rpcCalled: r.rpcCalled, directBajPost: r.directBajPost, item: item, sinRacks: r.sinRacks, btn: r.btn }), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
