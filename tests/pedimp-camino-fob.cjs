// v24.73/74 (Thomas) — Pedidos Importación: "En camino" y "A pedir" son dos columnas, y el FOB en
// viaje es el u$s TOTAL de los pedidos en viaje (gv_importados_pedidos_curso, el de 🚢 En curso),
// no unidades × FOB de hoy. Candado estático + la agregación por proveedor corrida de verdad.
const fs = require("fs");
const src = fs.readFileSync(__dirname + "/../importacion.js", "utf8");
let ok = true; const fail = (m) => { ok = false; console.error("✗ " + m); };
if (!/>En camino<small>u · llega<\/small><\/th><th[^>]*>A pedir<small>u<\/small><\/th>/.test(src)) fail("En camino y A pedir tienen que ser dos columnas");
if (/En camino<small>A pedir u<\/small>/.test(src)) fail("volvió la columna combinada En camino / A pedir");
if (/_pedImpCaminoUsd/.test(src)) fail("volvió la estimación unidades × FOB");
if (!/_pedImpRpc\("gv_importados_pedidos_curso"/.test(src)) fail("el FOB en viaje tiene que salir de gv_importados_pedidos_curso");
if (!/pedimp-camino-fob"/.test(src) || !/pedimp-camino-fob-tot/.test(src)) fail("falta el FOB en viaje en el proveedor o en la barra");
// correr la carga con la RPC mockeada
const i0 = src.indexOf("var _pedImpViaje"), i1 = src.indexOf("function _pedImpPrioCmp");
const code = src.slice(i0, i1);
let rendered = 0;
const ctx = new Function("_pedImpRpc", "_stkPop", "_pedImpRender",
  code + "; return { cargar: _pedImpViajeCargar, usd: _pedImpViajeUsd, get v() { return _pedImpViaje; } };")(
  () => Promise.resolve([{ proveedor: "Hugo Wong", usd: 9000 }, { proveedor: "Hugo Wong", usd: 3000.5 }, { proveedor: "Fujian", usd: 0 }]),
  { kind: "pedImp" }, () => { rendered++; });
ctx.cargar();
setTimeout(() => {
  if (ctx.usd("Hugo Wong") !== 12000.5) fail("Hugo Wong tiene que sumar 12000,5 y da " + ctx.usd("Hugo Wong"));
  if (ctx.v.nPorProv["Hugo Wong"] !== 2) fail("Hugo Wong son 2 pedidos");
  if (ctx.usd("Fujian") !== 0) fail("un pedido sin u$s no suma");
  if (rendered !== 1) fail("tiene que redibujar una vez al llegar el dato");
  if (ok) console.log("pedimp-camino-fob · ✓ OK"); else process.exitCode = 1;
}, 20);
