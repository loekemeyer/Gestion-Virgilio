// v29.36 — en Pedidos Importación el 809E de Chef no puede salir con el nombre del de Loeke (y al revés).
// Corre _impNombre de verdad con el NOMBRE_POR_EMPRESA real de index.html y un padrón que sólo conoce el código pelado.
const fs = require("fs"), path = require("path");
const imp = fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8");
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
let fail = 0; const ok = (c, m) => { console.log((c ? "OK  " : "FAIL") + " " + m); if (!c) fail++; };
const npe = idx.match(/const NOMBRE_POR_EMPRESA = (\{[^\n]*\});/);
ok(!!npe, "NOMBRE_POR_EMPRESA está en index.html");
const fn = imp.match(/function _impNombre\([\s\S]*?\n\}\n/);
ok(!!fn, "_impNombre existe en importacion.js");
if (npe && fn) {
  const _ocgNorm = (c) => String(c || "").trim().toUpperCase().replace(/^0+(?=\d)/, "");
  const NOMBRE_POR_EMPRESA = eval("(" + npe[1] + ")");
  const artNombre = (cod, fb) => (_ocgNorm(cod) === "809E" ? "Corta Pizza Mgo Ergonomico 6cm" : (fb || ""));
  const _impNombre = eval("(" + fn[0] + ")");
  ok(/queso/i.test(_impNombre("809E", "CH", "Corta queso x12")), "809E CH = Corta Queso");
  ok(/pizza/i.test(_impNombre("809E", "LK", "Corta pizza familiar")), "809E LK = Corta Pizza");
  ok(/queso/i.test(_impNombre("809E CH", "", "")), "809E con sufijo CH = Corta Queso");
  ok(_impNombre("816E", "LK", "Pelador") === "Pelador", "un código común sigue por artNombre");
}
// v29.37 — artNombre de toda la app: "809E CH" = Corta Queso aunque el padrón pelado diga Corta Pizza
const an = idx.match(/function artNombre\(cod, fb\) \{[\s\S]*?\n\}\n/);
ok(!!an, "artNombre existe en index.html");
if (an && npe) {
  const _ocgNorm = (c) => String(c || "").toUpperCase().trim().replace(/^0+(?=.)/, "");
  const NOMBRE_POR_EMPRESA = eval("(" + npe[1] + ")");
  const _artNombres = { "809E": "Corta Pizza Mgo Ergonomico 6cm", "816E": "Pelador" };
  const artNombre = eval("(" + an[0] + ")");
  ok(/queso/i.test(artNombre("809E CH")), "artNombre(809E CH) = Corta Queso");
  ok(/pizza/i.test(artNombre("809E LK")), "artNombre(809E LK) = Corta Pizza");
  ok(artNombre("809E", "Corta Queso X 12") === "Corta Queso X 12", "artNombre(809E pelado, fila de Chef) = la fila");
  ok(artNombre("816E") === "Pelador", "un código común sigue por el padrón");
}
// ninguna descripción de importados vuelve al artNombre pelado con la fila al lado
ok(!/artNombre\((it|l\.it)\.cod, (it|l\.it)\.desc\)/.test(imp), "la tabla de pedidos no usa artNombre pelado");
process.exit(fail ? 1 : 0);
