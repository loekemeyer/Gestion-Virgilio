// v22.45 — el armado tiene que ver los faltantes del picking aunque se arme días después.
// Caso E41A: pickeada 15/09, armada 24/09; con ventana de 5 días el 865E salió como 16 pickeadas
// (eran 1) y el "de menos" dejó Pickeados en -15. Candado: la ventana de faltantesDeTanda >= 30 días.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html").toString("utf8");
const i = src.indexOf("async function faltantesDeTanda(");
if (i < 0) { console.error("FAIL: no está faltantesDeTanda"); process.exit(1); }
const cuerpo = src.slice(i, i + 3000);
const m = cuerpo.match(/Date\.now\(\)\s*-\s*(\d+)\s*\*\s*86400000/);
if (!m) { console.error("FAIL: no encuentro la ventana de faltantesDeTanda"); process.exit(1); }
const dias = Number(m[1]);
if (dias < 30) { console.error("FAIL: ventana de faltantes = " + dias + " días (< 30): una tanda armada tarde pierde sus faltantes"); process.exit(1); }
console.log("comp-falt-ventana: OK — ventana " + dias + " días");
