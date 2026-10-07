// v28.31 — una NP web armada en 0 cajas va con 🔒 y sin casilla: la casilla del día no la tilda.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const ok = [];
const chk = (c, m) => { ok.push([c, m]); };
chk(/function facNpEnCero\(np\)/.test(src), "existe facNpEnCero");
chk(/_facCajasTs && _facCajas && _facCajas\.has\(k\)/.test(src), "sólo bloquea con Entregas leído y la NP armada");
chk(/facNpEsWeb\(f\.np\) && facNpEnCero\(f\.np\)\)[\s\S]{0,120}fac-xls-lock/.test(src), "la fila en 0 dibuja el candado, no el checkbox");
let mal = 0; ok.forEach(([c, m]) => { console.log((c ? "OK   " : "FAIL ") + m); if (!c) mal++; });
console.log(mal ? "fac-np-cero-candado: FALLA" : "fac-np-cero-candado: OK");
process.exit(mal ? 1 : 0);
