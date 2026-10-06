// v27.46 — el DESHACER (60 s) no puede borrar con DELETE (anon no tiene DELETE: 401 silencioso,
// caso F46A 06/10) ni liberar el client_id: tiene que pasar por la RPC gv_deshacer_evento.
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const i = src.indexOf("async function undoLastSent()");
const cuerpo = src.slice(i, src.indexOf("\n}\n", i));
let mal = 0;
function chk(ok, m) { console.log((ok ? "OK  " : "MAL ") + m); if (!ok) mal++; }
chk(i > 0, "existe undoLastSent");
chk(!/method:\s*"DELETE"/.test(cuerpo), "undoLastSent no hace DELETE");
chk(/_gvDeshacerServidor\(payload\.id, legajo, 0\)/.test(cuerpo), "undoLastSent llama a _gvDeshacerServidor");
chk(/rpc\/gv_deshacer_evento/.test(src), "la RPC gv_deshacer_evento se llama");
chk(/res === "sin_fila"[^]*intento < 4/.test(src), "reintenta si el evento todavia no llego");
process.exit(mal ? 1 : 0);
