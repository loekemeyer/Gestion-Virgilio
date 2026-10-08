// v28.77 (Luis, 08/10): Facturado = «con FC ISIS / exportadas» y el número grande con el % chiquito,
// en la PPP (index.html) y en la TV (monitor/tv.html → admin.html). Candado estático.
const fs = require("fs");
const idx = fs.readFileSync(__dirname + "/../index.html", "latin1");
const tv = fs.readFileSync(__dirname + "/../monitor/tv.html", "utf8");
const f = [];
const ok = (c, m) => { if (!c) f.push(m); };
ok(/gv_np_fc_parseada/.test(idx) && /function pgaFcCargar/.test(idx), "index: falta la lectura de FC parseadas");
ok(/_pgaPctTd\(fac, n, "fac", \(fcN != null && fac\) \? fcN \+ "\/" : ""\)/.test(idx), "index: Facturado no arma el x/y");
ok(/\+ n \+ '<small>' \+ p \+/.test(idx), "index: el número no va primero (grande) y el % chiquito");
ok(/gv_np_fc_parseada/.test(tv) && /function cargarFcParseada/.test(tv), "tv: falta la lectura de FC parseadas");
ok(/x\.fcNeto \+ "\/"/.test(tv), "tv: Facturado no arma el x/y");
if (f.length) { console.log("fc-parseada-x-de-y: ✗ FAIL\n  - " + f.join("\n  - ")); process.exit(1); }
console.log("fc-parseada-x-de-y: ✓ OK");
