// v22.78: «Aceptar» un insumo TMP con ubicación llamaba _stkInsUbicSync(cod, [ubi]) con el texto pelado;
// la función espera {sector,cantidad} y tiraba después de identificar («No se pudo» con el alta hecha).
// Además pasar sólo la nueva borraba las ubicaciones que el código ya tenía.
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const i = src.indexOf("async function stkInsAceptar(");
const cuerpo = i < 0 ? "" : src.slice(i, src.indexOf("\n}\n", i));
const fallas = [];
if (!cuerpo) fallas.push("no encontré stkInsAceptar");
if (/_stkInsUbicSync\(cod,\s*\[ubi\]\)/.test(cuerpo)) fallas.push("volvió la llamada con el texto pelado [ubi]");
if (!/_stkInsFetchUbics\(\)/.test(cuerpo)) fallas.push("no suma la ubicación nueva a las que el código ya tenía");
if (!/sector:\s*String\(ubi\)/.test(cuerpo)) fallas.push("no arma {sector, cantidad} para la ubicación nueva");
// v22.80: las ubicaciones de insumos se escriben por la RPC que las valida contra el Mapa, no con REST suelto
const j = src.indexOf("async function _stkInsUbicSync(");
const sync = j < 0 ? "" : src.slice(j, src.indexOf("\n}\n", j));
if (!/gv_insumo_ubicaciones_guardar/.test(sync)) fallas.push("_stkInsUbicSync no escribe por gv_insumo_ubicaciones_guardar");
if (/SUPABASE_INS_UBIC_ENDPOINT[^;]*method:\s*"(DELETE|PATCH|POST)"/.test(src)) fallas.push("volvió una escritura directa a Insumos_Ubicaciones");
if (fallas.length) { console.error("✗ ins-aceptar-ubic:\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("✓ ins-aceptar-ubic: aceptar un TMP con ubicación suma {sector,cantidad} a las existentes");
