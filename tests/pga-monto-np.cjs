// v23.27 (Luis, 28/09): cada NP del árbol de Programación muestra su MONTO, leído de
// gv_ppp_np_valor vía _pgaValorNp (no se recalcula en el front).
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const i = src.indexOf('<div class="pga-nrow"><span class="pga-ninfo">');
const f = src.indexOf("'</span>' +", src.indexOf("pga-ped", i));
const fila = i > 0 ? src.slice(i, f + 20) : "";
const ok = {
  filaNp: i > 0,
  monto: /pga-monto/.test(fila),
  deLaVista: /_pgaValorNp\(r\.np\)/.test(fila),
  formato: /_pgpMonto\(vn\.valor\)/.test(fila),
  css: /\.pga-monto\{/.test(src),
};
const mal = Object.keys(ok).filter(k => !ok[k]);
console.log(mal.length ? "FALLA pga-monto-np: " + mal.join(", ") : "OK pga-monto-np");
process.exit(mal.length ? 1 : 0);
