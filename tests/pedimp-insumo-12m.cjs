// v25.01 (Thomas, 30/09) — insumos en Pedidos Importación: sin empresa, objetivo 10 + 2 meses
// ("12M"), y el Stock abre su desglose. Candado estático + la regla de insumo corrida sobre datos.
const fs = require("fs");
const idx = fs.readFileSync(__dirname + "/../index.html", "latin1");
const imp = fs.readFileSync(__dirname + "/../importacion.js", "utf8");
let mal = 0; const ok = (c, m) => { console.log((c ? "OK  " : "MAL ") + m); if (!c) mal++; };
ok(/const INSUMO_MESES_PRODUCTO = 2;/.test(idx), "constante 2 meses de producto");
ok(/const mesesIt = mesesProv \+ \(esInsumo \? INSUMO_MESES_PRODUCTO : 0\)/.test(idx), "objetivo del insumo = meses prov + 2");
ok(/esInsumo: esInsumo, mesesProv: mesesProv/.test(idx), "el item lleva esInsumo y mesesProv");
ok(/function _impPlantaVista\(it\) \{ if \(it && it\.esInsumo\) return "";/.test(imp), "el insumo no muestra empresa");
ok(/function _pedImpEmpFoto\(it\) \{\s*if \(it && it\.esInsumo\) return "";/.test(imp), "el insumo no busca foto por empresa");
ok(/it\.esInsumo \? _pedImpInsumoChip\(it\)/.test(imp), "chip 12M en el código del insumo");
ok(/class="num pedimp-stk"[^]*?pedImpStockDesglose/.test(imp), "la celda Stock abre el desglose");
ok(/async function pedImpStockDesglose/.test(imp), "existe el desglose de stock");
// la regla de insumo: la parte cuyo propio código NO está entre los terminados
const esInsumo = (kk, det) => !(det || []).some(d => String(d.cod || "").toUpperCase().replace(/^0+/, "") === kk.replace(/^0+/, ""));
ok(esInsumo("1000900", [{ cod: "067" }, { cod: "520" }]), "1000900 (espiral) es insumo");
ok(!esInsumo("590E", [{ cod: "590E" }, { cod: "890E" }]), "590E (se vende) NO es insumo");
process.exit(mal ? 1 : 0);
