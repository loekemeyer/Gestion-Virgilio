// v28.02 — ENTREGA PROY. + 📓 log por línea de OC: sólo pantalla, persistido por RPC.
const fs = require("fs");
const s = fs.readFileSync(__dirname + "/../index.html", "latin1");
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log("✗ " + m); } else console.log("✓ " + m); };
ok(/gv_entrega_proy,gv_entrega_proy_por,gv_entrega_proy_at&order=fecha\.desc/.test(s), "ocFetchRows trae las columnas");
const det = s.slice(s.indexOf("function ocBodyDetail()"), s.indexOf("function _ocDetCantEff("));
ok(det.includes("Entrega<br>proy.") && det.includes("_ocEntProyCell(r)"), "columna en el detalle");
ok(det.indexOf("Entrega<br>proy.") > det.indexOf('<th class="num">Pedido</th>'), "va después de Pedido");
const pr = s.slice(s.indexOf("function ocPrintHtml("), s.indexOf("function ocPrintDetalle("));
ok(pr.length > 100 && !/gv_entrega_proy|_ocEntProyCell|ocLog/.test(pr), "no va al impreso / WhatsApp");
const xl = s.slice(s.indexOf("function ocDescargarExcelOC"), s.indexOf("function ocDescargarExcelOC") + 6000);
ok(!/gv_entrega_proy|_ocEntProyCell/.test(xl), "no va al Excel");
["gv_oc_entrega_proy_guardar", "gv_oc_log_agregar", "gv_oc_log_leer", "gv_oc_log_conteos"].forEach(f => ok(s.includes('"' + f + '"'), "RPC " + f));
ok(/catch \(e\) \{ box\.innerHTML = '<span style="color:#b91c1c">No se pudo leer el log/.test(s), "lectura rota lo dice");
process.exit(bad ? 1 : 0);
