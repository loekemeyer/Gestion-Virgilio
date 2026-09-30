// v25.10 (Luis, 30/09) — recepción de importados: «Cervantes» es el PRIMER destino; lo de un insumo va
// en su unidad y no entra al stock de Virgilio (queda como aviso en GP2.ingreso_virgilio).
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(__dirname + "/../importacion.js", "utf8");
let mal = 0; const ok = (c, m) => { console.log((c ? "OK  " : "MAL ") + m); if (!c) mal++; };
const m = /var _IMP_REC_DEST = (\{[^}]*\});/.exec(src);
ok(!!m, "existe _IMP_REC_DEST");
const dest = m ? vm.runInNewContext("(" + m[1] + ")") : {};
ok(Object.keys(dest)[0] === "cervantes", "Cervantes es el primero de la lista (" + Object.keys(dest).join(",") + ")");
const f = /function _impRecU\(l\) \{[^\n]*\}/.exec(src);
ok(!!f, "existe _impRecU");
const ctx = { _impRec: { soloInsumo: true } }; vm.createContext(ctx); vm.runInContext(f[0], ctx);
ok(ctx._impRecU({ destino: "cervantes" }) === true, "Cervantes con insumo va en unidades");
ok(ctx._impRecU({ destino: "insumos" }) === true, "Insumos sigue en unidades");
ok(ctx._impRecU({ destino: "a_guardar" }) === false, "A guardar sigue en cajas");
ctx._impRec.soloInsumo = false;
ok(ctx._impRecU({ destino: "cervantes" }) === false, "Cervantes con un producto va en cajas");
ok(/unidad: _impRecU\(l\) \? "Uni" : null/.test(src), "la línea le dice al backend su unidad");
process.exit(mal ? 1 : 0);
