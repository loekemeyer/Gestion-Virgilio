/* Test de regresión (v19.76) — generador de OCs, vista "Por artículo".
   Un artículo repartido entre DOS talleristas tiene que salir en UNA sola fila, con los números
   ENTEROS del artículo (proy, máx, pedidos, stock, a pedir) y el reparto aclarado en la columna
   Tallerista. Antes salían dos filas con todo dividido salvo la proyección, que iba entera en las
   dos: parecía duplicada y el renglón no cerraba (problema 419). Verifica además que:
   - la flecha ⤓ "topado a la capacidad de góndola" NO se dibuja más (la vista vista_generador_oc
     NO topa a capacidad: maximo = ceil(proy × índice) salvo que el artículo tenga Llenar góndola),
   - lo que se GENERA no cambió: ocgGroups() sigue dando una línea de OC por tallerista.
   Caso: el 505 real del 2026-09-18 (proy 2342,33 · índice 1,5 · máx 3514 · pedidos 545 · stock
   3291 · total 768 repartido 50/50 entre Garcia y Lucho).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado (ver tests/smoke.cjs)."); process.exit(2); }
}

(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    // dos subs del MISMO artículo (como los arma ocgEnter) + uno de un solo tallerista
    const sub = (prov, prop, falta) => ({
      cod: "505", desc: "Pelador Plastico - Env.", prov: prov, max: Math.round(3514 * prop / 100),
      fuente: "proy", indice: 1.5, proy: 2342.3333, demanda: Math.round(545 * prop / 100),
      stock: Math.round(3291 * prop / 100), falta: falta, cap: 3340,
      maxTot: 3514, demandaTot: 545, stockTot: 3291,
      uni: 12, ncaja: null, prop: prop, sinProv: false
    });
    const items = [
      sub("Garcia", 50, 384), sub("Lucho", 50, 384),
      { cod: "506", desc: "Abrelata Uña", prov: "Oscar", max: 2117, fuente: "proy", indice: 1.5,
        proy: 1410.67, demanda: 256, stock: 1500, falta: 873, cap: 3252,
        maxTot: 2117, demandaTot: 256, stockTot: 1500, uni: 12, ncaja: null, prop: 100, sinProv: false }
    ];
    _oc = { view: "gen", genMode: "art", genFiltro: "", gen: { items: items, itemsAll: items, fecha: "2026-09-18" } };
    ocRender = function () {};

    const html = ocBodyGenArt();
    const filas = (html.match(/<tr><td class="oc-cod">/g) || []).length;
    out.unaFilaPorArticulo = (filas === 2);                       // 505 y 506, no 3
    out.meta2Articulos = html.indexOf("<b>2</b> artículo(s) a pedir") >= 0;
    out.cajasTotal = html.indexOf("<b>1641</b> cajas") >= 0;      // 768 + 873
    // la fila del 505 lleva los números ENTEROS del artículo
    // ojo: las filas van ordenadas por "a pedir" desc, así que el 506 (873) sale ANTES que el 505 (768)
    const f505 = ("<tr>" + html.split("<tr><td class=\"oc-cod\">").filter((x) => x.indexOf("505<") === 0)[0]);
    out.proyEntera  = f505.indexOf('>2342<') >= 0;
    out.maxEntero   = f505.indexOf('>3514<') >= 0;
    out.pedEntero   = f505.indexOf('>545<') >= 0;
    out.stockEntero = f505.indexOf('>3291<') >= 0;
    out.pedirTotal  = f505.indexOf('oc-falt">768<') >= 0;
    out.sinMitades  = f505.indexOf('>1757<') < 0 && f505.indexOf('>1646<') < 0;
    // el reparto se aclara
    out.dice2Tall   = f505.indexOf("2 talleristas") >= 0;
    out.desglose    = f505.indexOf("Garcia 50% →") >= 0 && f505.indexOf("Lucho 50% →") >= 0
                      && (f505.match(/>384</g) || []).length === 2;
    // la flecha del tope no va más, en ninguna de las dos vistas
    _oc.genMode = "tall";
    const htmlTall = ocBodyGenTall();
    out.sinFlecha = (html + htmlTall).indexOf("⤓") < 0 && (html + htmlTall).indexOf("Topado a la capacidad") < 0;
    // y lo que se genera sigue siendo una línea por tallerista
    const g = ocgGroups();
    out.generaPorTallerista = Object.keys(g).sort().join(",") === "Garcia,Lucho,Oscar"
      && g["Garcia"].total === 384 && g["Lucho"].total === 384 && g["Oscar"].total === 873;
    return out;
  });

  await b.close();
  const fallos = Object.keys(r).filter((k) => !r[k]);
  if (errs.length) { console.error("Errores de página:\n" + errs.join("\n")); process.exit(1); }
  if (fallos.length) { console.error("ocg-una-fila FALLÓ: " + fallos.join(", ") + "\n" + JSON.stringify(r, null, 2)); process.exit(1); }
  console.log("ocg-una-fila: OK (" + Object.keys(r).length + " chequeos).");
})();
