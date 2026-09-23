// v21.58 (Marianela): una tanda con picking/armado empezado conserva su CÓDIGO al moverla de día.
// Candado estático: el paso 2 ofrece «🔒 Mismo código» (destino "=" → p_tanda_destino null) y,
// si la tanda está empezada, no ofrece tanda nueva ni fusión. El backend lo frena con TANDA_CANDADO.
const fs = require("fs"), path = require("path");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
let fail = 0;
function ok(c, m) { if (!c) { console.error("FALLA: " + m); fail++; } else console.log("ok: " + m); }
const i = src.indexOf("function pppMovPaso2Html()"), j = src.indexOf("async function pgaNpMoverAbrir(");
ok(i > 0 && j > i, "existen pppMovPaso2Html y pppMovDestinoElegir");
const blk = src.slice(i, j);
ok(/pppMovDestinoElegir\(\\'=\\'\)/.test(blk), "botón «Mismo código» manda destino '='");
ok(/Mismo c.{1,3}digo/.test(blk), "texto «Mismo código» en el paso 2");
const iEmp = blk.indexOf("M.empezada) return"), iNueva = blk.indexOf("Le pongo un c");
ok(iEmp > 0 && iEmp < iNueva, "tanda empezada corta ANTES de ofrecer tanda nueva / fusión");
ok(/p_tanda_destino: \(mismo \? null : t\)/.test(blk), "mismo código → p_tanda_destino null (modo 'mantiene')");
ok(blk.indexOf("TANDA_CANDADO") > 0, "el front explica TANDA_CANDADO");
if (fail) { console.error(fail + " falla(s)"); process.exit(1); }
console.log("OK ppp-tanda-candado-codigo");
