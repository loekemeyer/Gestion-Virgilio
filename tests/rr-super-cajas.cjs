/* v24.51 (Thomas) — en RR / CR / Carga Camión, un SÚPER (clase 'etiqueta') sin líos muestra las
   CAJAS, igual que Retira. Antes salía «Líos: 0». Corre _liosCajasCell de verdad. Sale 1 si falla. */
const fs = require("fs"), path = require("path"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const i = src.indexOf("function _liosCajasCell("); const j = src.indexOf("\n}\n", i) + 3;
const ctx = { String }; vm.createContext(ctx); vm.runInContext(src.slice(i, j), ctx);
const f = ctx._liosCajasCell, fails = [];
const eq = (it, txt, esCajas, m) => { const r = f(it); if (r.txt !== txt || r.esCajas !== esCajas) fails.push(m + ": " + JSON.stringify(r)); };
eq({ lios: 0, clase: "etiqueta", cajas: 593 }, "593c", true, "súper sin líos → cajas");
eq({ lios: null, clase: "Etiqueta", cajas: 12 }, "12c", true, "súper sin dato de líos → cajas");
eq({ lios: 3, clase: "etiqueta", cajas: 40 }, "3", false, "súper con líos declarados → líos");
eq({ lios: 0, clase: "nada", cajas: 7 }, "7c", true, "retira sigue igual");
eq({ lios: 6, clase: "lio", cajas: 30 }, "6", false, "cliente común → líos");
eq({ lios: 0, clase: "lio", cajas: 30 }, "0", false, "cliente común con 0 líos no cambia");
if (!/data-label="\$\{cell\.esCajas \? "Cajas" : "Líos"\}"/.test(src)) fails.push("RR: el rótulo de la celda tiene que decir Cajas");
if (!/const cell = _liosCajasCell\(it\);   \/\/ v24\.51/.test(src)) fails.push("Carga Camión tiene que usar _liosCajasCell para todos, no sólo Retira");
if (fails.length) { console.log("✗ rr-super-cajas\n  " + fails.join("\n  ")); process.exit(1); }
console.log("✓ rr-super-cajas: el súper sin líos muestra cajas en RR, CR y Carga Camión");
