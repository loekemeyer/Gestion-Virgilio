/* Regresión v22.37 — la recepción de un tallerista graba la EMPRESA (línea) de la entrega.
   Sin gv_empresa, la OC de un dual ("437E CH") no se imputa nunca: gv_oc_recompute_recibido
   exige la misma empresa cuando la OC la trae. Candado estático sobre recepcion.js (sin comentarios). */
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "recepcion.js"), "utf8")
  .replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
const i = src.indexOf('tabla = "Entregas Tallerista Virgilio"');
const bloque = i >= 0 ? src.slice(i, i + 900) : "";
if (!/gv_empresa\s*:\s*opState\.linea/.test(bloque)) {
  console.error("rcp-empresa-dual: FALLA — la fila de Entregas Tallerista Virgilio no lleva gv_empresa: opState.linea");
  process.exit(1);
}
console.log("rcp-empresa-dual: OK — la entrega del tallerista viaja con su empresa");
