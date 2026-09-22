/* Regresion v21.08 (Luis, 22/09/2026): "quiero que la vision ahi muestre los que estan en
   0 demanda para generacion de OCs tambien".

   La vista "Por articulo" del generador listaba solo los articulos con a pedir > 0 (gen.items).
   Ahora sale de gen.itemsAll, que es TODO el universo activo, y los que quedan en 0 caen al
   final atenuados. Lo que se GENERA no cambia: ocgGenerar arma las OC desde ocgGroups(), que
   lee gen.items.

   Chequea las tres mitades, porque una sin las otras no sirve:
   - el articulo en 0 APARECE en la tabla;
   - el encabezado cuenta como "a pedir" SOLO los que se piden, y sus cajas;
   - ocgGroups() (lo que se manda) sigue trayendo solo los de falta > 0  <- candado invertido.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const mk = (cod, desc, prov, falta) => ({ cod: cod, desc: desc, prov: prov, falta: falta,
      max: 100, maxTot: 100, demanda: 10, demandaTot: 10, stock: 5, stockTot: 5, fuente: "proy",
      indice: 1.5, proy: 40, uni: 12, ncaja: null, prop: 100, sinProv: false, cap: null });
    const pide1 = mk("501", "Abrelatas Manija", "Pettofrezza", 1138);
    const pide2 = mk("506", "Abrelata Una", "Oscar", 905);
    const cero  = mk("581T", "Sac. Cabo Nylon Tira Imp", "Martin C", 0);
    const itemsAll = [pide1, pide2, cero];
    _oc = { view: "gen", genMode: "art", genFiltro: "",
            gen: { fecha: "2026-09-22", items: itemsAll.filter(x => x.falta > 0), itemsAll: itemsAll } };
    const html = ocBodyGenArt();
    const iCero = html.indexOf("581T"), i501 = html.indexOf(">501<"), i506 = html.indexOf(">506<");
    const g = ocgGroups();
    const codsQueSeMandan = Object.keys(g).map(k => g[k].items.map(i => i.cod).join(",")).join("|");
    return {
      veElEnCero:    iCero >= 0,
      veLosQueSePiden: i501 >= 0 && i506 >= 0,
      elCeroVaAlFinal: iCero > i501 && iCero > i506,
      atenuado:      html.indexOf('opacity:.55') >= 0,
      // con el texto ACENTUADO a proposito: la primera version de la v21.08 reescribio el
      // encabezado con los acentos como escapes \\xNN y salio "artÃ­culo(s)"; el chequeo sin
      // tilde pasaba igual y no lo cazo. Lo cazo ocg-una-fila. Que no vuelva a pasar.
      cuentaSolo2:   html.indexOf("<b>2</b> artículo(s) a pedir") >= 0,
      sinEscapesRotos: html.indexOf("\\x") < 0 && html.indexOf("Ã") < 0,
      cajasSinElCero: html.indexOf("<b>2043</b> cajas") >= 0,   // 1138 + 905, el 0 no suma
      avisaDelCero:  html.indexOf(">1</b> en 0") >= 0,
      seMandanSoloLosDeFalta: codsQueSeMandan.indexOf("581T") < 0   // candado invertido
    };
  });
  const pass = Object.keys(r).every(k => r[k] === true) && errs.length === 0;
  console.log("oc-muestra-los-en-cero:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
