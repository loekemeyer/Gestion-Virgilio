/* v31.49 (Luis, 16/10: "cuando un operario guarda en gondola un codigo del que no hay posicion
   establecida, debería preguntar DONDE se está guardando").
   (A) código de la lista SIN celda en el Mapa: sale «¿En qué góndola lo guardaste?»; sin anotarla
       NO se guarda; con ella guarda y emite PKG "COD|G09|GUARDADO|cajas" (cae al cuadro del admin).
   (B) código CON celda: no pregunta y no emite PKG.
   (C) fuera de lista (938E) con celda: muestra «Va en G09» (antes no mostraba nada) y no pregunta.
   (D) fuera de lista sin celda: pregunta.
   (E) el mapa de celdas no cargó (lectura rota): NO se exige (no se frena el guardado). */
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
    const out = {}, sent = [], moves = [], alerts = [];
    const wait = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function (m) { alerts.push(String(m)); };
    window.confirm = function () { return true; };
    window.stockMove = async function (rows) { moves.push(rows); return { ok: true }; };
    window.emitGuardadoSesion = function () {};
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return {
      "502": { cod: "502", desc: "X", a_guardar: 10, terminado: 0 },
      "503": { cod: "503", desc: "Y", a_guardar: 4, terminado: 0 } }; };
    window.rkbFetchCapacidad = async function () { return { pelada: {}, porEmp: {} }; };
    let celdas = { "503": ["F09"], "938E": ["G09"] };
    window.ocgFetchCeldas = async function () { return celdas; };
    window.ocgDemanda = async function () { return {}; };
    window.rkbFetchCxM = async function () { return { cxm: {} }; };
    window.gvFetchLugares = async function () { const L = ["F09", "G09", "M13"]; return (_gvLugares = { lista: L, set: new Set(L), libres: new Set(), emp: {}, orden: {} }); };
    window.trySendOneReport = async function (pl) { sent.push(pl); return { ok: true }; };
    localStorage.clear();
    legajoInput.value = "77";
    await showMGModal("77");
    await wait(60);
    const idx = (c) => _mg.items.findIndex((x) => String(x.cod).replace(/^0+/, "") === c);
    const html = () => document.getElementById("mgModal").innerHTML;
    // (A)
    out.aPregunta = _mg.items[idx("502")].sinCel === true && html().indexOf("¿En qué góndola lo guardaste?") >= 0;
    mgSet(idx("502"), 3); await wait(10);
    await mgGuardarUno(idx("502"), "guardado"); await wait(20);
    out.aFrena = moves.length === 0 && alerts.length === 1;
    mgSetGubic(idx("502"), "Q99");
    await mgGuardarUno(idx("502"), "guardado"); await wait(20);
    out.aLugarInexistente = moves.length === 0 && alerts.length === 2;
    mgSetGubic(idx("502"), "g9");
    await mgGuardarUno(idx("502"), "guardado"); await wait(20);
    const pkg = sent.filter((x) => x.opcion === "PKG");
    out.aGuarda = moves.length === 1;
    out.aPKG = pkg.length === 1 && pkg[0].texto === "502|G09|GUARDADO|3" && !pkg[0].ts_inicio_iso;
    // (B)
    sent.length = 0;
    out.bNoPregunta = _mg.items[idx("503")].sinCel === false;
    mgSet(idx("503"), 2); await wait(10);
    await mgGuardarUno(idx("503"), "guardado"); await wait(20);
    out.bGuarda = moves.length === 2 && sent.filter((x) => x.opcion === "PKG").length === 0;
    // (C)
    mgSearchInput("938E"); mgAddManual(); await wait(10);
    const m = _mg.items[idx("938E")];
    out.cMuestraLugar = !!m && m.sinCel === false && html().indexOf("Va en <b>G09</b>") >= 0;
    // (D)
    mgSearchInput("777"); mgAddManual(); await wait(10);
    out.dPregunta = _mg.items[idx("777")].sinCel === true;
    closeMG();
    // (E)
    _mg = null; celdas = {}; window._mgCeldas = null;
    await showMGModal("78"); await wait(60);
    out.eNoExige = _mg.items[idx("502")].sinCel === false;
    return out;
  });
  const checks = Object.keys(r).map((k) => [k, r[k]]);
  const pass = checks.every((c) => c[1]) && errs.length === 0;
  console.log("mg-sin-gondola:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none");
  checks.forEach((c) => console.log("  " + (c[1] ? "✓" : "✗") + " " + c[0]));
  console.log(pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
