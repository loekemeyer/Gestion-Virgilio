// v23.42 (Luis, 28/09): el detalle del mes (facturado por cliente y entregas) tiene que decir
// UNIDADES en los encabezados de columna cuando el switch está en unidades, no "cajas" fijo.
const src = require("fs").readFileSync(__dirname + "/../index.html", "utf8");
const i = src.indexOf("function _stkProyDetHtml("), j = src.indexOf("\nfunction ", i + 10);
const f = src.slice(i, j);
const fijo = /<th class="n">cajas<\/th>/.test(f);
const dos = (f.match(/<th class="n">' \+ _stkProyUniTxt\(\) \+ '<\/th>/g) || []).length === 2;
if (fijo || !dos) { console.error("FALLA proy-det-unidades: encabezado 'cajas' fijo=" + fijo + " dinamicos=" + dos); process.exit(1); }
console.log("OK proy-det-unidades");
