/* Regresión (v20.88): RENOMBRAR UNA TANDA TIENE QUE MOVER TAMBIÉN LA PROGRAMACIÓN WEB.

   El pallet de El Gran Bazar (LK 0043) estaba en el depósito con un papel impreso que decía
   E03F, y el sistema la llamaba E12L. Luis, 21/09: *"en la programación vas a renombrar la
   tanda actual E12L a E03F"* — manda el pallet.

   Al renombrarla, `gv_ppp_tanda_renombrar` contestó **4 objetos tocados** y la PPP siguió
   diciendo E12L. La función renombra 18 tablas —eventos (incluidos los PKC y los `ref` con
   pipe), Entregas, Facturación, stock con fusión de deltas, los dos candados, Etiquetas_Lío,
   Faltantes, la conciliación, el override de ISIS, la kangoo, los comprobantes ARCA, los
   armados en espera y PPP_Web_Tandas— y se salteaba `PPP_Web_Programacion`, que es la tabla
   MADRE de los pedidos de la página.

   Resultado: la tanda queda partida en dos nombres según desde dónde se la mire. El stock, el
   picking, el armado y la factura viajan al código nuevo; la PPP se queda con el viejo.

   El test mira el archivo de la versión y exige que el update esté. El centinela vivo es
   `select * from public.gv_reglas_perdidas;` (objeto gv_ppp_tanda_renombrar, patrón
   PPP_Web_Programacion). */
const fs = require("fs");
const path = require("path");

const root = path.join(__dirname, "..");
const fallos = [];
const f = path.join(root, "sql", "gv_ppp_tanda_renombrar_prog_web_v2088.sql");
if (!fs.existsSync(f)) { console.error("FALTA " + f); process.exit(1); }

const sql = fs.readFileSync(f, "utf8");
// el SQL vivo, sin los comentarios: un `-- no tocar X` no cuenta como que X está
const vivo = sql.split("\n").map((l) => l.replace(/--.*$/, "")).join("\n");

if (!/update\s+public\."PPP_Web_Programacion"/i.test(vivo))
  fallos.push("falta el update de PPP_Web_Programacion: la tanda renombrada deja la PPP con el código viejo");
if (!/set\s+tanda\s*=\s*v_b/i.test(vivo))
  fallos.push("el update no escribe el código nuevo (v_b)");
if (!/upper\(btrim\(coalesce\(w\.tanda,''\)\)\)\s*=\s*v_a/i.test(vivo))
  fallos.push("el update no filtra por el código viejo normalizado (upper+btrim+coalesce)");
// va DESPUÉS del override de ISIS: los dos lados de la programación, juntos
if (vivo.indexOf('GV_PPP_Prog_Override') > vivo.indexOf('PPP_Web_Programacion'))
  fallos.push("el update web quedó antes del de ISIS: van juntos, primero ISIS y después web");

// el archivo tiene que dejar dicho que la lista de tablas se amplía al agregar una nueva
if (!/agregar una tabla con columna .?tanda.?, agregarla tambien aca/i.test(sql))
  fallos.push("falta la regla: al agregar una tabla con columna tanda hay que sumarla al renombre");

if (fallos.length) { console.error("FALLAS:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("OK ppp-renombrar-prog-web: el renombre mueve también la programación web");
