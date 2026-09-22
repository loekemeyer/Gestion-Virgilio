// v21.31 — candados de la RPC indexada de saldos y del arreglo de la huella.
// Lo que FUNCIONA se probo corriendolo contra la base (687 ms -> 7 ms, y
// EXCEPT ALL 0 en las dos direcciones sobre las 496 claves). Esto cuida que no
// se pierdan las decisiones que lo hacen seguro.
const fs = require("fs");
let malos = 0;
const ok = (c, m) => { if (!c) { console.error("FALLA: " + m); malos++; } };

const sql = fs.readFileSync("sql/gv_stock_indice_clave_v2131.sql", "utf8");
const html = fs.readFileSync("index.html", "latin1");   // el index tiene un NUL: se lee en bytes

// 1. el indice va sobre la EXPRESION ckey, con los ::text explicitos
ok(/create index if not exists mov_stock_ckey_idx/.test(sql),
   "tiene que estar el indice de expresion mov_stock_ckey_idx");
ok(/regexp_replace\(upper\(btrim\(cod_art\)\), '\^0\+\(\?=\.\)'::text, ''::text\)/.test(sql),
   "la expresion del indice va con los ::text explicitos o el planner no la reconoce");

// 2. NO se agrego columna ni trigger ni backfill al libro de stock
ok(!/alter table\s+public\."Movimientos_Stock"\s+add column/i.test(sql),
   "no se le agrega columna a Movimientos_Stock: alcanza con el indice de expresion");
ok(!/update\s+public\."Movimientos_Stock"\s+set/i.test(sql),
   "no se reescribe ni una fila del libro de stock");

// 3. el rollback esta escrito y no toca datos
ok(/drop index if exists public\.mov_stock_ckey_idx/.test(sql), "falta el rollback del indice");
ok(/drop function if exists public\.gv_saldos_por_clave/.test(sql), "falta el rollback de la RPC");

// 4. queda escrito POR QUE `in (select ... from cte)` no sirve
ok(/= any\(v_ck\)/.test(sql) && /planner NO lo usa/i.test(sql),
   "tiene que quedar escrito que el filtro va con = any(array) y no con in (select ... from cte)");

// 5. y por que la huella pasa a contenido
ok(/GV_Stock_Huella_Expr/.test(sql) && /gv-reconciliar-aguardar/.test(sql),
   "tiene que quedar escrito que el cron 81 movia la huella cada 2 min");
ok(/22P02/.test(sql), "tiene que quedar escrito el cast a bigint que exploto en ejecucion");

// 6. el front: el helper existe y postea a la RPC
ok(/async function gvSaldosDeClaves\(/.test(html), "falta el helper gvSaldosDeClaves");
ok(/rest\/v1\/rpc\/gv_saldos_por_clave/.test(html), "el helper tiene que pegarle a la RPC");
ok((html.match(/gvSaldosDeClaves\(/g) || []).length >= 3,
   "tienen que quedar al menos 2 llamadores ademas de la definicion");

// 7. ⚠ CANDADO INVERTIDO: el PICKING sigue leyendo la vista, a proposito.
//    Se reapunto a la RPC y `tests/pk-excedente-vista.cjs` se puso en rojo
//    (su mock intercepta por la URL de la vista). Se REVIRTIO en vez de tocar
//    el test: el picking es el camino caliente de los operarios. Si alguien lo
//    vuelve a reapuntar, que sea con el test de excedente adaptado y verde.
ok(/vista_saldos_stock\?clave=in\.\(/.test(html),
   "el picking (excedente) tiene que seguir leyendo vista_saldos_stock: se revirtio a proposito");

// 8. las 2 lecturas del universo entero siguen como estan
ok(/vista_saldos_stock", "select=\*"/.test(html),
   "la lectura del universo entero sigue contra la vista: el indice no la ayuda");

if (malos) { console.error(`\n${malos} candado(s) rotos`); process.exit(1); }
console.log("stock-clave-indexada: 13 candados OK");
