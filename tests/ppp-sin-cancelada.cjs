// v28.37 — Programación y Resumen no dibujan una NP cancelada (caso LK 0066). Candado estático.
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../index.html", "utf8");
const i = s.indexOf("async function pppTraerWebProgramados");
const f = s.slice(i, i + 2500);
const ok = i > 0 && /GV_PPP_Web_NP_Cancelada/.test(f) && /_cSet\.has\(/.test(f) && /catch \(_e\) \{ canc = null; \}/.test(f);
console.log(ok ? "ppp-sin-cancelada OK" : "ppp-sin-cancelada FALLA"); process.exit(ok ? 0 : 1);
