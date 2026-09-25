// v22.75 (Luis, 25/09): Capacidad_Sector es una VISTA sobre GV_Lugar_Item.
// Candado: el front no vuelve a escribir en Capacidad_Sector (POST / DELETE / upsert); la capacidad
// entra por gv_lugar_item_guardar, la misma RPC del Mapa de góndolas. Y «Borrar todo» no vuelve.
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const fallas = [];
if (/SUPABASE_CAPACIDAD_ENDPOINT[^;\n]*\{\s*method:\s*"(POST|DELETE|PATCH)"/.test(src))
  fallas.push("hay una escritura directa a Capacidad_Sector (es una vista: va por gv_lugar_item_guardar)");
if (/onclick="stkCapBorrar\(\)"/.test(src)) fallas.push("volvió el botón «Borrar todo» de capacidad");
function cuerpo(fn) {
  const i = src.indexOf("async function " + fn + "(");
  if (i < 0) return "";
  return src.slice(i, src.indexOf("\n}\n", i));
}
for (const fn of ["stkCapImport", "dpSaveCap"]) {
  if (!/pmapRpc\("gv_lugar_item_guardar"/.test(cuerpo(fn))) fallas.push(fn + " no escribe por gv_lugar_item_guardar");
}
if (fallas.length) { console.error("✗ cap-sector-vista:\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("✓ cap-sector-vista: la capacidad se escribe sólo por gv_lugar_item_guardar");
