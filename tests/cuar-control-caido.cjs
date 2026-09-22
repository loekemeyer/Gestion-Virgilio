/* v20.96 (Thomas, 2026-09-22) — CANDADOS del control de cuarentena.
 *
 * Qué pasó: `cuarMarcarPedidos` llamaba a las tres RPC dentro de UN `Promise.all`. Con la base
 * ocupada, `gv_cuarentena_marcar` devolvió 500 (`canceling statement due to statement timeout`)
 * 5 veces en 8 minutos; el `await` tiró, el `catch` se lo comió y NINGÚN pedido quedó marcado.
 * La pantalla dibujó "🚧 Cuarentena (0) · Sin pedidos retenidos" con Ierakuin (deuda $2.062.529)
 * y Romagessi ($2.216.125) en la lista normal, con el chip verde "se arma solo".
 *
 * Es un candado ESTÁTICO a propósito: un test de pantalla necesita reproducir el timeout, y lo
 * que hay que impedir es que alguien vuelva a juntar las tres llamadas o a tapar el error.
 */
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
let fallos = 0;
function ok(cond, txt) { console.log((cond ? "ok  " : "FALLA") + " " + txt); if (!cond) fallos++; }

// el cuerpo de cuarMarcarPedidos, para no mirar todo el archivo
const i = src.indexOf("async function cuarMarcarPedidos()");
const fin = src.indexOf("function cuarDemoPedido()", i);
const cuerpo = i >= 0 && fin > i ? src.slice(i, fin) : "";
ok(cuerpo.length > 0, "encuentro cuarMarcarPedidos");

ok(/Promise\.allSettled\(/.test(cuerpo),
   "las tres RPC van con Promise.allSettled (una que falla no se lleva a las otras)");
ok(!/await Promise\.all\(\[/.test(cuerpo),
   "NO volvió el Promise.all: con él, un timeout dejaba la Cuarentena en 0");
ok(/_apr\.cuarErr\s*=/.test(cuerpo),
   "el fallo queda registrado en _apr.cuarErr, no se traga en silencio");
ok(/if \(res === null\)/.test(cuerpo),
   "sin la marcación no se borran las marcas de la vuelta anterior");
ok(/async function cuarRpcMarcar\(/.test(src),
   "gv_cuarentena_marcar va aparte, con su reintento");

// el reintento: dos llamadas a la misma RPC dentro del helper
const j = src.indexOf("async function cuarRpcMarcar(");
const helper = j >= 0 ? src.slice(j, src.indexOf("async function cuarMarcarPedidos()", j)) : "";
ok((helper.match(/aprRpc\("gv_cuarentena_marcar"/g) || []).length === 2,
   "el helper reintenta UNA vez (el timeout deshace la transacción: reintentar es seguro)");

// el render avisa en vez de decir "no hay retenidos"
ok(/apr-cuar-err/.test(src), "el sector dibuja el aviso de control caído");
ok(/\(_apr\.cuarErr \? '' : '<div class="apr-vacio">Sin pedidos retenidos/.test(src),
   'con el control caído NO se escribe "Sin pedidos retenidos"');
ok(/\.apr-cuar-err\{/.test(src), "el aviso tiene su estilo");

// el estado CANCELADO del log
ok(/\["cancelado", "🗑 Cancelados"\]/.test(src) || /\[\"cancelado\"/.test(src),
   "el log tiene el chip de Cancelados");
ok(/cuar-log-est\.e-cancelado\{/.test(src), "el estado cancelado tiene su color");

console.log(fallos ? "\ncuar-control-caido FALLÓ (" + fallos + ")" : "\ncuar-control-caido OK");
process.exit(fallos ? 1 : 0);
