/* Regresión — Luis, 22/09/2026: "cuando se escribe 03 debería mostrar todos los códigos que
   empiecen con 03, no que lo tengan en alguna parte del código".

   Buscar un CÓDIGO en el módulo Stock es buscar por el PRINCIPIO. Dos cosas que el test cuida:

   1. El PREFIJO se mide sobre la grafía que se MUESTRA (031, con el cero adelante — regla del
      dueño del 12/09), que es la que el operario tiene delante. Nunca sobre la pelada de la
      base: la v21.02 probaba las dos y Luis lo frenó el mismo día — "si busco 30 en la tabla
      aparece el 030 y es un error". 030 empieza con 0, no con 30.
   2. Un término que arranca con dígito NO mira la descripción: "031" no puede traer un
      artículo porque su texto diga "031 cm". Un término de texto sí busca por pedazo.

   Y el candado: el filtro de la pestaña Stocks tiene que pasar por stkMatchBusq. Si alguien
   vuelve a escribirle su propio indexOf, la búsqueda por pedazo vuelve sin que nadie lo note. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

// [código, término, ¿matchea?]
const PREFIJO = [
  // lo que pidió Luis: 03 trae los 03x
  ["30", "03", true], ["31", "03", true], ["35E", "03", true], ["031", "03", true], ["036E", "03", true],
  // y no los que lo tienen en el medio
  ["231", "03", false], ["130", "03", false], ["703", "03", false], ["007", "03", false],
  // ⚠ y TAMPOCO por la grafía pelada: "30" no puede traer el 030 (Luis, 22/09: "es un error").
  // El código se muestra con el cero adelante, así que el prefijo se mide sobre esa forma.
  ["030", "30", false], ["31", "31", false], ["031", "31", false], ["026", "26", false],
  ["307", "30", true], ["311", "31", true], ["260E", "26", true],
  // la regla del 18/09 sigue en pie: 031 es el 031 y sus variantes de letra, nada más
  ["031", "031", true], ["31", "031", true], ["031E", "031", true], ["031 LK", "031", true],
  ["231", "031", false], ["311", "031", false], ["312", "031", false], ["931E", "031", false],
  // 3 dígitos: el prefijo vale igual (50 → 505, 506)
  ["505", "50", true], ["506", "50", true], ["605", "50", false],
  // sufijo de empresa: el código es el mismo artículo
  ["438E LK", "438", true], ["438E LK", "438E", true], ["809E CH", "809", true], ["809E CH", "708", false],
  // códigos que no arrancan con número
  ["GRJ10", "GRJ", true], ["GRJ10", "RJ", false],
];

// [término, cod, texto libre, numLibre, ¿matchea?]
const LIBRE = [
  ["031", "231", "colador 031 cm", false, false],   // un número NO busca en la descripción
  ["031", "231", "colador 031 cm", true, true],     // …salvo donde puede ser un remito
  ["cafe", "120", "filtro de cafe", false, true],   // texto: por pedazo
  ["cafe", "120", "colador", false, false],
  ["", "505", "", false, true],                     // sin término, pasa todo
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(({ PREFIJO, LIBRE }) => {
    const fallas = [];
    if (typeof codEmpiezaCon !== "function") fallas.push("no existe codEmpiezaCon");
    else PREFIJO.forEach(([cod, term, esp]) => {
      const dio = !!codEmpiezaCon(cod, term);
      if (dio !== esp) fallas.push("codEmpiezaCon(" + cod + ", " + term + ") = " + dio + ", esperaba " + esp);
    });

    if (typeof stkMatchBusq !== "function") fallas.push("no existe stkMatchBusq");
    else LIBRE.forEach(([term, cod, libre, num, esp]) => {
      const dio = !!stkMatchBusq(term, cod, libre, num);
      if (dio !== esp) fallas.push("stkMatchBusq(" + JSON.stringify(term) + ", " + cod + ", " + JSON.stringify(libre) + ", " + num + ") = " + dio + ", esperaba " + esp);
    });

    // candado: TODO buscador de código de la app pasa por el helper, no por su propio indexOf.
    // v21.43 — se sumaron los 17 que quedaban afuera (Stock del operario, Compras/OC, planimetría),
    // para que no haya dos criterios de búsqueda según la pantalla.
    [
      // Stock y Compras (admin)
      "stkBodyStocks", "stkDescargarExcel", "stkBodyIngresos", "stkBodySalidas", "stkBodyHistAjustes",
      "stkGondRender", "abastRender", "dpRender", "tallArtsRender",
      // Compras / OC
      "ocBodyEntregas", "ocBodyGeneral", "ocBodyCfg",
      "ocBodyGenArt", "ocBodyGenTall", "ocBodyGenImportados",   // el generador filtra en las TRES vistas, no en ocBodyGen
      // operario
      "mgRender", "excRender", "rkbRender", "scRender", "insRender", "mvRender",
      // planimetría / mapa de góndolas
      "lugRenderCod", "pmapMatch",
      // otros popups de código
      "_provImpRender", "_pedHechoRenderCuerpo",
    ].forEach((fn) => {
      if (typeof window[fn] !== "function") { fallas.push("no existe " + fn); return; }
      const src = String(window[fn]);
      if (!/stkMatchBusq|codEmpiezaCon/.test(src)) fallas.push(fn + " no usa el helper de búsqueda por prefijo");
    });
    // ⚠ los que NO van por prefijo, a propósito: ahí un número es una NP, un cliente, un remito
    // o una fecha, no un artículo. Si alguien les mete el helper, la búsqueda deja de encontrar.
    ["ocBodyList", "_pppEntFilter"].forEach((fn) => {
      if (typeof window[fn] !== "function") { fallas.push("no existe " + fn); return; }
      if (/stkMatchBusq|codEmpiezaCon/.test(String(window[fn]))) fallas.push(fn + ": ahí el número NO es un código de artículo (NP/cliente/fecha) — no va por prefijo");
    });
    // y la regla vieja (matchear el código entero y frenar si sigue un dígito) no puede volver
    if (/charAt\(tn\.length\)/.test(String(window.stkBodyStocks || ""))) fallas.push("stkBodyStocks volvió al match exacto: 03 no encontraría nada");
    return fallas;
  }, { PREFIJO, LIBRE });

  const ok = r.length === 0 && errs.length === 0;
  console.log("stk-busqueda-prefijo: prefijo=" + PREFIJO.length + " · libre=" + LIBRE.length +
    (r.length ? " · FALLAS: " + r.join(" | ") : "") + " · pageerrors:", errs.length ? errs.join("|") : "none",
    "·", ok ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(ok ? 0 : 1);
})();
