/* v31.13 (Luis, 15/10): las CAJAS POR MASTER tienen UNA fuente, la canónica GV_Rack_CxM.
   Falla si el front vuelve a leer Articulos.Cajas_x_Master o a derivar el CxM de la planimetría
   (ratio innercajas/master_cajas), o si desaparece el lector único gvFetchCxM. Estático. Sale 1 si falla. */
const fs = require("fs"), path = require("path");
const root = path.join(__dirname, "..");
const idx = fs.readFileSync(path.join(root, "index.html")).toString("utf8");
const rec = fs.readFileSync(path.join(root, "recepcion.js"), "utf8");
const sinComent = (t) => t.split("\n").filter((l) => !/^\s*(\/\/|\/\*|\*)/.test(l)).join("\n");
const r = {
  lectorUnico: /async function gvFetchCxM\(\)[\s\S]{0,300}GV_Rack_CxM/.test(idx),
  sinArticulosIdx: !/select=[^"]*Cajas_x_Master/.test(sinComent(idx)),
  sinArticulosRec: !/select\("[^"]*Cajas_x_Master/.test(rec) && /from\("GV_Rack_CxM"\)/.test(rec),
  sinRatioPlani: !/inn\s*%\s*m\s*!==\s*0/.test(idx) && !/a\.inner\s*%\s*a\.master/.test(idx),
};
const bad = Object.keys(r).filter((k) => !r[k]);
console.log("cxm-canonica:", JSON.stringify(r), bad.length ? "✗ FAIL " + bad.join(",") : "✓ OK");
process.exit(bad.length ? 1 : 0);
