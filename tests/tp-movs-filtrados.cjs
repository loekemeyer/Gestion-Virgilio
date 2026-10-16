/* v31.38 — el TP del operario NO baja Movimientos_Stock entera (86.572 filas, 25 MB):
   stockBajaPicking pide sólo la familia de los códigos de la tanda (stockFetchMovs(cods)). */
const fs = require("fs");
const html = fs.readFileSync(require("path").join(__dirname, "..", "index.html")).toString("utf8");
const ini = html.indexOf("async function stockBajaPicking(");
const cuerpo = html.slice(ini, html.indexOf("\nfunction stockEmitSinStock", ini));
const fetchFn = html.slice(html.indexOf("async function stockFetchMovs("), html.indexOf("function ssgSetSwitchUI"));
const chk = {
  bajaPideFiltrado: /stockFetchMovs\(_codsTanda\)/.test(cuerpo),
  bajaNoPideTodo: !/stockFetchMovs\(\)/.test(cuerpo),
  familiaConSufijos: /bk \+ " LK", bk \+ " CH", bk \+ " LOKE"/.test(cuerpo),
  fetchFiltraServer: /cod_art=in\./.test(fetchFn),
  fetchPaginaConOrder: /supaFetchAll\(SUPABASE_STOCK_ENDPOINT, "cod_art=in\.[^"]*"[^;]*order=ts\.desc,id\.desc/.test(fetchFn),
  sinArgSigueTodo: /select=\*&order=ts\.desc"\)/.test(fetchFn),
};
const ok = Object.values(chk).every(Boolean);
console.log("tp-movs-filtrados: " + JSON.stringify(chk) + (ok ? " · ✓ OK" : " · ✗ FALLA"));
process.exit(ok ? 0 : 1);
