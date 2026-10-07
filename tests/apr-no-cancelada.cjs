// v28.35 — A Programar no ofrece un pedido CANCELADO (caso LK 0066). Candado estático.
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../index.html", "latin1");
const ok1 = /aprGet\('GV_PPP_Web_NP_Cancelada\?select=empresa,order_id/.test(s);
const ok2 = /const \[pedsLk, prog, items, canc, tandas, isis\]/.test(s);
const ok3 = /for \(const x of \(canc \|\| \[\]\)\) fuera\.add\(aprKey\(x\.empresa, x\.order_id\)\)/.test(s);
if (ok1 && ok2 && ok3) { console.log("apr-no-cancelada OK"); process.exit(0); }
console.log("apr-no-cancelada FALLA", { lee: ok1, destructura: ok2, excluye: ok3 }); process.exit(1);
