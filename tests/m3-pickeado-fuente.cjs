/* v26.55 (Luis, 04/10): «una vez que se pickea, ya no se mira más el m³ del pedido entero: se analiza con el
   m³ PICKEADO y nada más, porque lo que se carga en el camión es lo pickeado». En el index la fracción se
   aplica en la FUENTE (programación del monitor, histórico y PPP), y lo que se GUARDA sigue siendo el m³ del
   pedido. Candado estático + la cuenta de gvM3Pickeado corrida de verdad. */
const fs = require("fs");
const path = require("path");
const idx = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };
const cuerpo = (nombre) => {
  const i = idx.indexOf(nombre); if (i < 0) return "";
  const j = idx.indexOf("\nasync function ", i + 10), k = idx.indexOf("\nfunction ", i + 10);
  const fin = Math.min(j < 0 ? idx.length : j, k < 0 ? idx.length : k);
  return idx.slice(i, fin);
};
ok(!/monPickFrac|gv_picking_pickeado/.test(idx), "volvió monPickFrac / gv_picking_pickeado al index: el m³ pickeado sale de gv_tanda_m3_pickeado");
ok(/\/rpc\/gv_tanda_m3_pickeado/.test(cuerpo("function gvFracPickeado(")), "gvFracPickeado tiene que leer gv_tanda_m3_pickeado");
ok(/gvFracPickeado\(\)/.test(cuerpo("async function fetchMonitorSheet(")), "fetchMonitorSheet no aplica el m³ pickeado (monitor, picking, armado, carga)");
ok(/gvFracPickeado\(\)/.test(cuerpo("async function fetchHistoricSheet(")), "fetchHistoricSheet no aplica el m³ pickeado (días pasados del monitor)");
ok(/gvFracPickeado\(\)/.test(cuerpo("async function pppLoadProgFromSupabase(")), "la PPP no aplica el m³ pickeado (camiones, Resumen, Ocupación)");
ok(/m3: \(p\.m3Ped != null \? p\.m3Ped : p\.m3\)/.test(cuerpo("async function pppGuardarWeb(")),
   "pppGuardarWeb tiene que GUARDAR el m³ del pedido (m3Ped), no el pickeado: si no, reprogramar pisa el dato");
ok(!/_pkFr/.test(idx), "quedó un _pkFr: el m³ se prorratearía dos veces (la fuente ya viene pickeada)");
// la cuenta, corrida
const src = cuerpo("function gvM3Pickeado(");
let f = null; try { f = new Function(src + "; return gvM3Pickeado;")(); } catch (e) { fallas.push("gvM3Pickeado no compila: " + e.message); }
if (f) {
  const fr = new Map([["E31A", 0.8], ["E40B", 0]]);
  ok(f(fr, "e31a", 1.5) === 1.2, "E31A 1,5 × 0,8 tiene que dar 1,2: " + f(fr, "e31a", 1.5));
  ok(f(fr, "E40B", 2) === 0, "una tanda pickeada en 0 vale 0 m³: " + f(fr, "E40B", 2));
  ok(f(fr, "E50A", 0.7) === 0.7, "una tanda sin pickear conserva el m³ del pedido: " + f(fr, "E50A", 0.7));
  ok(f(new Map(), "E31A", 1.5) === 1.5, "sin lectura (Map vacío) el m³ queda como el pedido (fail-open)");
}
if (fallas.length) { console.log("m3-pickeado-fuente: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("m3-pickeado-fuente: ✓ OK (monitor, histórico y PPP con el m³ pickeado; se guarda el del pedido)");
