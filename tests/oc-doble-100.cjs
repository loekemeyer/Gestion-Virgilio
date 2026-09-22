/* Regresion v21.14 (Luis, 22/09/2026): "excepcion para 3 codigos. 544, 560 y 800 deberian
   generar OCs por el total (100%) para fab y para carlos / de momento ponemos esto como
   hardcode".

   Los 3 codigos de OCG_DOBLE_100 NO se reparten: cada tallerista recibe una OC por el TOTAL.
   Eso rompe el supuesto de toda la vista "Por articulo", que suma los subs para sacar el
   "a pedir" del articulo — sumando, 382 se veria como 764 en la fila y en el encabezado.

   Chequea las dos mitades, y una sin la otra no sirve:
   - lo que se GENERA: dos lineas, cada una por el total (eso es lo que pidio Luis);
   - lo que se MUESTRA: la fila y el encabezado cuentan las cajas UNA vez.
   Mas el candado estatico de la constante (los 3 codigos, los nombres EXACTOS de OC_Maximos)
   y el de que ocgEnter la use. Sale 1 si falla. */
const fs = require("fs"), path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const estaticos = {
  // los nombres van EXACTOS como estan en OC_Maximos: "Log/ Fabr" (60 codigos) y "Carlos E" (30).
  declaraLos3: /const OCG_DOBLE_100 = \{[^}]*"544"[^}]*"560"[^}]*"800"[^}]*\}/.test(src),
  nombresExactos: (src.match(/"Log\/ Fabr", "Carlos E"/g) || []).length === 3,
  ocgEnterLaUsa: /const doble = OCG_DOBLE_100\[_ocgNorm\(cod\)\];/.test(src),
  // el sub duplicado tiene que llegar marcado al item, o la vista no puede distinguirlo
  marcaElItem: /dupProv: !!sub\.dup/.test(src)
};

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const mk = (cod, desc, prov, falta, dup) => ({ cod: cod, desc: desc, prov: prov, falta: falta,
      max: 573, maxTot: 573, demanda: 0, demandaTot: 0, stock: 191, stockTot: 191, fuente: "proy",
      indice: 1.5, proy: 382, uni: 12, ncaja: null, prop: 100, sinProv: false, cap: null,
      dupProv: !!dup });
    // 544 = los dos subs con el TOTAL (lo que arma ocgEnter con OCG_DOBLE_100)
    const a1 = mk("544", "Batidor Pera", "Log/ Fabr", 382, true);
    const a2 = mk("544", "Batidor Pera", "Carlos E", 382, true);
    // 501 normal, para que el encabezado tenga con que comparar
    const b1 = mk("501", "Abrelatas Manija", "Pettofrezza", 100, false);
    const itemsAll = [a1, a2, b1];
    _oc = { view: "gen", genMode: "art", genFiltro: "",
            gen: { fecha: "2026-09-22", items: itemsAll.filter(x => x.falta > 0), itemsAll: itemsAll } };
    const html = ocBodyGenArt();
    // lo que se manda: una linea por sub, cada una por el total
    const g = ocgGroups();
    const fabr = (g["Log/ Fabr"] || { items: [] }).items.filter(i => i.cod === "544");
    const carlos = (g["Carlos E"] || { items: [] }).items.filter(i => i.cod === "544");
    return {
      // GENERA: dos OCs, cada una por las 382 enteras
      dosOcsPorElTotal: fabr.length === 1 && carlos.length === 1 &&
                        fabr[0].falta === 382 && carlos[0].falta === 382,
      // MUESTRA: una sola fila, y el "a pedir" NO se duplica
      unaSolaFila:   (html.match(/>544</g) || []).length === 1,
      noDuplicaCajas: html.indexOf(">382</td>") >= 0 && html.indexOf(">764<") < 0,
      encabezadoOk:  html.indexOf("<b>2</b> artículo(s) a pedir") >= 0 &&
                     html.indexOf("<b>482</b> cajas") >= 0,   // 382 + 100, NO 864
      // la celda Tallerista dice que NO se reparte (decia lo contrario)
      diceQueNoSeReparte: html.indexOf("cada tallerista recibe una OC por el TOTAL") >= 0,
      noDiceQueSeReparte: html.indexOf("El total de la fila se reparte") < 0,
      // los dos nombres a la vista
      nombraALosDos: html.indexOf("Log/ Fabr") >= 0 && html.indexOf("Carlos E") >= 0,
      sinEscapesRotos: html.indexOf("\\x") < 0 && html.indexOf("Ã") < 0
    };
  });
  const todo = Object.assign({}, estaticos, r);
  const pass = Object.keys(todo).every(k => todo[k] === true) && errs.length === 0;
  console.log("oc-doble-100:", JSON.stringify(todo), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
