// v24.73 (Thomas) — Pedidos Importación: el FOB de lo que viene EN CAMINO se ve (fila, proveedor
// y barra de arriba) y "En camino" y "A pedir" son dos columnas. Candado estático + función pura.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../importacion.js", "utf8");
let ok = true; const fail = (m) => { ok = false; console.error("✗ " + m); };
const m = /function _pedImpCaminoUsd\(it\) \{[^\n]*\}/.exec(src);
if (!m) fail("falta _pedImpCaminoUsd");
else {
  const f = new Function(m[0] + "; return _pedImpCaminoUsd;")();
  if (f({ enCurso: 100, fobUni: 0.5 }) !== 50) fail("100 u × 0,5 tiene que dar 50");
  if (f({ enCurso: 0, fobUni: 0.5 }) !== 0) fail("sin en camino tiene que dar 0");
  if (f({ enCurso: 100 }) !== 0) fail("sin FOB tiene que dar 0");
}
if (!/>En camino<small>FOB u\$s<\/small><\/th><th[^>]*>A pedir<small>u<\/small><\/th>/.test(src)) fail("En camino y A pedir tienen que ser dos columnas");
if (/En camino<small>A pedir u<\/small>/.test(src)) fail("volvió la columna combinada En camino / A pedir");
if (!/pedimp-camino-fob"/.test(src)) fail("falta el FOB en camino en el encabezado del proveedor");
if (!/pedimp-camino-fob-tot/.test(src)) fail("falta el FOB en camino en la barra de totales");
if (!/pedimp-camino-usd/.test(src)) fail("falta el FOB en camino por fila");
if (ok) console.log("pedimp-camino-fob · ✓ OK"); else process.exitCode = 1;
