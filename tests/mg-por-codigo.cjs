/* v23.72 (Luis, 28/09: "agrega opciones a modulo") — Guardado a Góndola POR CÓDIGO y
   recuperar lo abierto desde otro celular.
   (A) «✓ Guardé este código»: guarda ese código solo, emite UN MG con ts_inicio (el tramo) y
       vuelve a abrir el módulo (MGI); el resto de la lista sigue ahí.
   (B) «Ya estaba en góndola»: mueve el stock pero emite MGR (instantáneo, sin tiempo), NO un MG.
   (C) los botones por código están en la fila y el «Terminé de guardar» también.
   (D) gvRecuperarTogglesServidor: un RT abierto en el servidor (otro celular) vuelve a este;
       uno cerrado por FJ no. Sale 1 si falla. */
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
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "load" });
  const r = await p.evaluate(async () => {
    const out = {}, sent = [], moves = [];
    window.alert = function () {};
    window.confirm = function () { return true; };
    window.stockMove = async function (rows) { moves.push(rows); return { ok: true }; };
    window.emitGuardadoSesion = function () {};
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return {
      "502": { cod: "502", desc: "X", a_guardar: 10, terminado: 0 },
      "503": { cod: "503", desc: "Y", a_guardar: 4, terminado: 0 } }; };
    window.ocgFetchCapacidad = async function () { return {}; };
    window.ocgFetchCeldas = async function () { return {}; };
    window.ocgDemanda = async function () { return {}; };
    window.rkbFetchCxM = async function () { return { cxm: {} }; };
    window.trySendOneReport = async function (pl) { sent.push(pl); return { ok: true }; };
    localStorage.clear();
    legajoInput.value = "77";
    await showMGModal("77");
    await new Promise((res) => setTimeout(res, 60));
    const idx = (c) => _mg.items.findIndex((x) => String(x.cod).replace(/^0+/, "") === c);
    out.nItems = _mg.items.length;
    // (C) botones en la fila
    mgSet(idx("502"), 3);
    await new Promise((res) => setTimeout(res, 20));
    const html = document.getElementById("mgModal").innerHTML;
    out.cBotones = html.indexOf("Guardé este código") >= 0 && html.indexOf("Ya estaba en góndola") >= 0;
    // (A) guardar 502 solo
    sent.length = 0;
    await mgGuardarUno(idx("502"), "guardado");
    await new Promise((res) => setTimeout(res, 20));
    const mg = sent.filter((x) => x.opcion === "MG"), mgi = sent.filter((x) => x.opcion === "MGI");
    out.aUnMG = mg.length === 1 && !!mg[0].ts_inicio_iso;
    out.aReabre = mgi.length === 1;
    out.aMovio = moves.length === 1;
    out.aQuedaResto = idx("503") >= 0 && _mg.items.length === out.nItems;   // 502 quedó con 7
    // (B) regularizar 503
    sent.length = 0;
    mgSet(idx("503"), 4);
    await new Promise((res) => setTimeout(res, 20));
    await mgGuardarUno(idx("503"), "regularizar");
    await new Promise((res) => setTimeout(res, 20));
    out.bSinMG = sent.filter((x) => x.opcion === "MG").length === 0;
    const mgr = sent.filter((x) => x.opcion === "MGR");
    out.bMGR = mgr.length === 1 && mgr[0].texto === "503|4" && !mgr[0].ts_inicio_iso;
    out.bMovio = moves.length === 2;
    out.bSale = idx("503") < 0;
    out.cTermino = document.getElementById("mgModal").innerHTML.indexOf("Terminé de guardar") >= 0;
    closeMG();
    // (D) recuperar toggles
    const hace = (min) => new Date(Date.now() - min * 60000).toISOString();
    window.supaFetchAllSafe = async function () { return [{ opcion: "RT", ts_cliente: hace(30), ts_inicio: null }]; };
    const n1 = await gvRecuperarTogglesServidor("55");
    out.dRecupera = n1 === 1 && !!getLegajoState("55").toggles.RT;
    window.supaFetchAllSafe = async function () { return [{ opcion: "RT", ts_cliente: hace(30), ts_inicio: null }, { opcion: "FJ", ts_cliente: hace(5), ts_inicio: null }]; };
    const n2 = await gvRecuperarTogglesServidor("56");
    out.dFJCierra = n2 === 0 && !getLegajoState("56").toggles.RT;
    return out;
  });
  const checks = Object.keys(r).filter((k) => k !== "nItems").map((k) => [k, r[k]]);
  const pass = checks.every((c) => c[1]) && errs.length === 0;
  console.log("mg-por-codigo:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none");
  checks.forEach((c) => console.log("  " + (c[1] ? "✓" : "✗") + " " + c[0]));
  console.log(pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
