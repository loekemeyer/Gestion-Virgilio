/* Regresión v20.70 — una tanda ARMADA cuyos pedidos de hoy no tienen armado propio.

   Luis, 2026-09-21: *"nunca se pickeo pero figura como armado? como, por que?"* → *"Agrega el
   centinela"*.

   EP, TP, AP y TAP son eventos de la TANDA (`texto = 'D69H'`, sin NP): una vez que la tanda
   tiene TAP queda armada para siempre, aunque después le cambien los pedidos de adentro. El
   único registro por NP es `Entregas_Virgilio`. Caso D69H: su TAP del 16/09 era de LK 0058, que
   ya no estaba, y sus 2 pedidos (62 cajas, 15 líneas) iban a salir el miércoles sin pickear.

   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const f = path.join(__dirname, "..", "sql", "gv_tanda_armada_sin_armado_v2070.sql");
if (!fs.existsSync(f)) { console.error("FALTA " + f); process.exit(1); }
const sql = fs.readFileSync(f, "utf8");
const vivo = sql.split("\n").map((l) => l.replace(/--.*$/, "")).join("\n");
const fallos = [];

const v = (vivo.match(/create or replace view public\.gv_tanda_armada_sin_armado[\s\S]*?order by w\.fecha_entrega, 1, 4;/i) || [""])[0];
if (!v) fallos.push("el archivo ya no crea gv_tanda_armada_sin_armado");
else {
  if (!/r\.opcion = 'TAP'/.test(v))
    fallos.push("no mira el TAP — y tiene que ser igualdad exacta: un armado anulado es TAPX y no cuenta");
  if (/opcion (=|in) .*'TAPX'/.test(v))
    fallos.push("cuenta los TAPX: un armado anulado NO es una tanda armada");
  if (!/not exists \(select 1 from public\."Entregas_Virgilio" e/.test(v))
    fallos.push("no compara contra Entregas_Virgilio, que es el unico registro por NP");
  if (!/upper\(btrim\(e\.np\)\) = upper\(btrim\(public\.gv_ppp_web_np_label/.test(v))
    fallos.push("compara la tanda pero no la NP: sin eso una sola linea tapa a todos los pedidos");
  if (!/salidos/.test(v))
    fallos.push("no saca lo que ya salio por CCN/CRN: su armado es historia");
  if (!/COALESCE\(btrim\(r\.legajo\), ''\) not in \('0', '1'\)|coalesce\(btrim\(r\.legajo\),''\) not in \('0','1'\)/i.test(v))
    fallos.push("cuenta los legajos de prueba (0 y 1)");
  if (!/w\.fecha_entrega >= current_date/.test(v))
    fallos.push("mira tandas viejas: el centinela es de lo que todavia va a salir");
}
if (!/alter view public\.gv_tanda_armada_sin_armado set \(security_invoker = true\)/.test(vivo))
  fallos.push("falta el `alter view ... security_invoker`");
if (!/grant select on public\.gv_tanda_armada_sin_armado to anon, authenticated/.test(vivo))
  fallos.push("falta el grant: el centinela lo mira la pantalla, no solo el MCP");
if (!/'gv_tanda_armada_sin_armado','vista'/.test(vivo))
  fallos.push("falta la fila de GV_Reglas_Centinela");

if (fallos.length) { console.error("FALLAS:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("OK ppp-tanda-armada-sin-armado: el centinela mira el TAP vivo contra el armado por NP");
