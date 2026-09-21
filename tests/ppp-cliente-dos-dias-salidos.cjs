/* Regresión v20.67 — lo que YA SALIÓ no parte al cliente en dos días.

   Luis, 2026-09-21, sobre Riondini en `gv_ppp_cliente_dos_dias`: *"ya salio así que la macana ya
   esta hecha"*.

   Una NP con carga de camión (CCN) o remito controlado (CRN) ya se entregó: su `fecha_entrega`
   es historia, no una entrega pendiente, y compararla contra la de otro pedido del mismo cliente
   inventa un choque que no existe. Medido el 21/09: de las **179 NP programadas a futuro, 34 ya
   habían salido**. Sale 1 si falla. */
const fs = require("fs");
const path = require("path");

const f = path.join(__dirname, "..", "sql", "gv_cliente_dos_dias_salidos_v2067.sql");
if (!fs.existsSync(f)) { console.error("FALTA " + f); process.exit(1); }
const sql = fs.readFileSync(f, "utf8");
const vivo = sql.split("\n").map((l) => l.replace(/--.*$/, "")).join("\n");
const fallos = [];

const vista = (vivo.match(/create or replace view public\.gv_ppp_cliente_dos_dias[\s\S]*?ORDER BY l\.k, l\.dia, l\.np;/i) || [""])[0];
if (!vista) fallos.push("el archivo ya no reemplaza gv_ppp_cliente_dos_dias");
else {
  if (!/WITH salidos AS/i.test(vista)) fallos.push("falta el CTE `salidos`");
  if (!/'CCN'::text, 'CRN'::text/.test(vista))
    fallos.push("salidos no mira CCN/CRN: es el mismo criterio de salida que gv_ppp_tanda_mover");
  if (!/COALESCE\(btrim\(r\.legajo\), ''::text\) <> ALL \(ARRAY\['0'::text, '1'::text\]\)/.test(vista))
    fallos.push("salidos cuenta los legajos de prueba (0 y 1)");
  if (!/NOT EXISTS \(SELECT 1 FROM salidos s/.test(vista))
    fallos.push("la vista no saca las NP que ya salieron");
  // las dos mitades tienen que seguir entrando: web e ISIS
  if (!/FROM "PPP_Web_Programacion" w/.test(vista)) fallos.push("la vista perdio la mitad web");
  if (!/FROM gv_ppp_programacion_diaria i/.test(vista)) fallos.push("la vista perdio la mitad de ISIS");
  // y las reglas viejas que no se pueden perder
  if (!/zona !~\* 'super\|retira\|expo'/.test(vista))
    fallos.push("la vista dejo de excluir super/retira/expo");
  if (!/abs\(b\.dia - a\.dia\) <= 7/.test(vista))
    fallos.push("la vista perdio la ventana de 7 dias del choque");
}
if (!/alter view public\.gv_ppp_cliente_dos_dias set \(security_invoker = true\)/.test(vivo))
  fallos.push("falta el `alter view ... security_invoker`: CREATE OR REPLACE VIEW borra las reloptions");
if (!/'gv_ppp_cliente_dos_dias','vista','salidos'/.test(vivo))
  fallos.push("falta la fila de GV_Reglas_Centinela");

if (fallos.length) { console.error("FALLAS:\n - " + fallos.join("\n - ")); process.exit(1); }
console.log("OK ppp-cliente-dos-dias-salidos: lo que ya salio no cuenta como entrega pendiente");
