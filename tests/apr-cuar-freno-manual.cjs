// v22.17 (Luis, 24/09, problema 528) — candado estático del freno de cuarentena en A Programar.
// La prueba corriendo (sin cuarentena verificada no se programa nada) está en apr-fit.cjs.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1")
  .replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'\\])\/\/[^\n]*/g, "$1");  // sin comentarios
const fallos = [];
const chk = (c, m) => { console.log((c ? "ok   " : "MAL  ") + m); if (!c) fallos.push(m); };
const fn = (name) => { const i = src.indexOf("function " + name + "("); return i < 0 ? "" : src.slice(i, i + 6000); };
const marcar = fn("cuarMarcarPedidos"), gen = fn("aprGenerarTanda");
chk(/if \(!askKey\[k\]\) return;\s*p\._cuarOk = true;/.test(marcar), "la marcación deja _cuarOk sólo en los pedidos de SU lote");
chk(/!p\._cuarOk/.test(gen) && gen.indexOf("_cuarOk") < gen.indexOf("gv_ppp_web_tanda_nueva"), "aprGenerarTanda frena ANTES de crear la tanda si la cuarentena no está verificada");
chk(/aprEnCuarentena\(p\)/.test(gen), "aprGenerarTanda frena un pedido retenido");
chk(/p\.tanda_previa && aprEnCuarentena\(p\)/.test(src) && /al aprobarlo se reprograma/.test(src), "en cuarentena el chip NO dice «vuelve a <tanda>»");
if (fallos.length) { console.log("\nFALLARON " + fallos.length); process.exit(1); }
console.log("\napr-cuar-freno-manual OK");
