// v23.27/28 (Luis, 28/09): el árbol de Programación muestra el MONTO en cada NP, tanda y día,
// leído de gv_ppp_np_valor (_pgaValorNp / _pgaValorTanda / _pgaValorDia), no recalculado.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../index.html", "latin1");
const ok = {
  helper: /function _pgaMontoChip\(v\)[\s\S]{0,300}pga-monto[\s\S]{0,300}_pgpMonto\(v\.valor\)/.test(src),
  np: src.includes("_pgaMontoChip(_pgaValorNp(r.np))"),
  tanda: src.includes("_pgaMontoChip(_pgaValorTanda(t))"),
  dia: src.includes("_pgaMontoChip(_pgaValorDia(d))"),
  css: /\.pga-monto\{/.test(src),
};
const mal = Object.keys(ok).filter(k => !ok[k]);
console.log(mal.length ? "FALLA pga-monto-np: " + mal.join(", ") : "OK pga-monto-np");
process.exit(mal.length ? 1 : 0);
