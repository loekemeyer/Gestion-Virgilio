/* Regresión — regla del dueño (12/09/2026): "No existe 26. Solo 026. No te equivoques
   más con eso. Revisá buscadores y cada vez que se escriba, siempre sea con 0 adelante".

   Dos cosas distintas, y el test cuida las dos:

   1. ESCRIBIR / MOSTRAR → el cero adelante va SIEMPRE. La parte numérica se rellena a 3
      dígitos, también cuando el código sigue con letra (35E → 035E). Los de 4+ dígitos y
      los que no arrancan con número quedan como están. Es lo que hace _padCod / codCanon
      en el front y public.gv_cod_mostrar() en Supabase.

   2. BUSCAR / COMPARAR → tiene que dar igual. Los normalizadores (_ocgNorm, _stkNormCod,
      _ppNormCod) PELAN el cero a propósito, para que tipear 26 encuentre el 026 y al revés.
      Eso NO se toca: si un día se "arreglaran" para no pelar, los buscadores dejarían de
      encontrar y este test lo caza. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

// [entra, como se escribe]
const ESCRITURA = [
  ["26", "026"], ["026", "026"], ["9", "009"], ["67", "067"], ["067", "067"],
  ["35E", "035E"], ["035E", "035E"], ["56E", "056E"],
  ["437E", "437E"], ["1063", "1063"], ["55215", "55215"],
  ["GRJ10", "GRJ10"], ["A10", "A10"],
];
// pares que TIENEN que normalizar igual, o el buscador no encuentra
const BUSQUEDA = [["26", "026"], ["27", "0027"], ["35E", "035E"], ["67", "067"]];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(({ ESCRITURA, BUSQUEDA }) => {
    const fallas = [];
    if (typeof _padCod !== "function") fallas.push("no existe _padCod");
    else ESCRITURA.forEach(([entra, esperado]) => {
      const dio = _padCod(entra);
      if (dio !== esperado) fallas.push("_padCod(" + entra + ") = " + dio + ", esperaba " + esperado);
    });

    // los normalizadores de los buscadores tienen que colapsar las dos grafías
    ["_ocgNorm", "_stkNormCod", "_ppNormCod"].forEach((fn) => {
      if (typeof window[fn] !== "function") { fallas.push("no existe " + fn); return; }
      BUSQUEDA.forEach(([a, z]) => {
        if (window[fn](a) !== window[fn](z)) fallas.push(fn + ": " + a + " y " + z + " no matchean");
      });
    });

    // las tres altas por teclado guardan con el cero adelante (no lo que se tipeó crudo)
    // v17.26 - planimAdd se borro: el editor viejo de planimetria quedo solo lectura
    ["tallArtAdd", "lugAddItem"].forEach((fn) => {
      if (typeof window[fn] !== "function") { fallas.push("no existe " + fn); return; }
      if (!/codCanon\(/.test(String(window[fn]))) fallas.push(fn + " guarda el código sin pasar por codCanon");
    });
    // v28.71 (Luis, D10/D11 tanda 1): codCanon y _abastCodDisp MUESTRAN con el cero adelante
    if (typeof codCanon === "function" && codCanon("58") !== "058") fallas.push("codCanon(58) = " + codCanon("58"));
    if (typeof _abastCodDisp === "function" && _abastCodDisp("58") !== "058") fallas.push("_abastCodDisp(58) = " + _abastCodDisp("58"));
    // los pop-ups de Stocks dibujan el código por _padCod
    ["stkOpenFcsArt", "stkOpenExcedenteArt", "stkOpenRacksArt", "stkOpenCapArt", "stkOpenMovsArt"].forEach((fn) => {
      if (typeof window[fn] !== "function") { fallas.push("no existe " + fn); return; }
      if (!/_padCod\(/.test(String(window[fn]))) fallas.push(fn + " muestra el código sin _padCod");
    });
    return fallas;
  }, { ESCRITURA, BUSQUEDA });

  const rcp = require("fs").readFileSync(require("path").join(__dirname, "..", "recepcion.js"), "utf8");
  if (!/function _rcpPad\(/.test(rcp)) r.push("recepcion.js sin _rcpPad");
  if (!/Cod_Art: _rcpPad\(/.test(rcp)) r.push("recepcion.js: el alta de código no guarda con _rcpPad");
  // v28.79 (D14, tanda 2): picking, hoja de picking, armado, faltantes y remito muestran el cero
  const ix = require("fs").readFileSync(require("path").join(__dirname, "..", "index.html"), "latin1");
  const cuerpo = (n) => { const i = ix.indexOf("function " + n + "("); if (i < 0) return ""; let d = 0; for (let k = ix.indexOf("{", i); k < ix.length; k++) { if (ix[k] == "{") d++; if (ix[k] == "}" && !--d) return ix.slice(i, k + 1); } return ""; };
  ["pkRender", "pkHojaHtml", "armadoRemitoInnerHtml", "arRender", "arCompTxt", "_compDifHtml", "_compSepMatrix", "_compRenderLios"].forEach((fn) => {
    const c = cuerpo(fn); if (!c) r.push("no existe " + fn); else if (!/_padCod\(/.test(c)) r.push(fn + " muestra el código sin _padCod");
  });
  const ok = r.length === 0 && errs.length === 0;
  console.log("cod-cero-adelante: escritura=" + ESCRITURA.length + " · busqueda=" + (BUSQUEDA.length * 3) +
    (r.length ? " · FALLAS: " + r.join(" | ") : "") + " · pageerrors:", errs.length ? errs.join("|") : "none",
    "·", ok ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
