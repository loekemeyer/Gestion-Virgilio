// v23.28 (Luis 28/09): en Importados la L del maestro (437EL/438EL/439EL = Loeke) no se muestra como
// código: sale "437E" con la chapa LK, y la línea de Chef del mismo número con la chapa CH.
// Corre las funciones reales de index.html (no un candado de texto).
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../index.html", "latin1");
const a = s.indexOf("function _impLRuteo"), z = s.indexOf("function _pedImpItemPorClave");
if (a < 0 || z < 0) { console.error("FALTA _impLRuteo/_pedImpItemPorClave"); process.exit(1); }
eval(Buffer.from(s.slice(a, z), "latin1").toString("utf8"));
const casos = [
  [{ cod: "437EL", det: [{ marca: "LK" }] }, "437E", "LK"],
  [{ cod: "437E", plantaVista: "CH", det: [{ marca: "CH" }] }, "437E", "CH"],
  [{ cod: "809E", planta: "CH", det: [] }, "809E", "CH"],
  [{ cod: "505", det: [{ marca: "LK" }] }, "505", ""],
];
let mal = 0;
for (const [it, cod, pl] of casos) {
  const c = _impCodVista(it), p = _impPlantaVista(it);
  if (c !== cod || p !== pl) { mal++; console.error("MAL", it.cod, "->", c, p, "esperaba", cod, pl); }
}
if (!/plantaVista = "CH"/.test(s)) { mal++; console.error("MAL: el armado no marca la línea de Chef (plantaVista)"); }
if (/esc\(codCanon\(it\.cod\) \+ \(it\.planta/.test(s)) { mal++; console.error("MAL: el Excel vuelve a mostrar el código crudo"); }
console.log(mal ? "imp-cod-l-vista: " + mal + " fallas" : "imp-cod-l-vista: OK");
process.exit(mal ? 1 : 0);
