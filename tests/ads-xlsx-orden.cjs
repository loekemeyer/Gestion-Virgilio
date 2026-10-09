// v28.93 (Luis): el Excel de talleristas abría con «problema con el contenido»: <mergeCells> quedaba DESPUÉS de
// <pageMargins>. El esquema exige sheetData → mergeCells → pageMargins → pageSetup.
const fs = require("fs"), path = require("path"), vm = require("vm");
const XLSX = require(path.join(__dirname, "..", "vendor", "xlsx.full.min.js"));
const src = fs.readFileSync(path.join(__dirname, "..", "ads.js"), "utf8");
const i0 = src.indexOf("function _adsXlsxFormato("), i1 = src.indexOf("function _adsXlsx(", i0);
const ctx = { TextDecoder, TextEncoder, Uint8Array, String, Number, Error };
vm.createContext(ctx); vm.runInContext(src.slice(i0, i1), ctx);
const aoa = [["Cód", "Desc", "a", "b"], ["Garcia 50 %"], ["550", "Pinza", 1, 2], ["Lucho 30 %"], ["505", "Abre", 3, 4]];
const wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(aoa), "T");
const out = ctx._adsXlsxFormato(XLSX, wb, { anchos: [10, 20, 7, 7], izq: [1], fuente: 14, altoRot: 72, titulos: [1, 3], altos: [null, 22, 18, 22, 18] });
const cfb = XLSX.CFB.read(new Uint8Array(out), { type: "array" });
const ix = cfb.FullPaths.findIndex(p => /sheet1\.xml$/.test(p));
const x = new TextDecoder().decode(new Uint8Array(cfb.FileIndex[ix].content));
const pos = ["</sheetData>", "<mergeCells", "<pageMargins", "<pageSetup"].map(t => x.indexOf(t));
let mal = 0;
if (pos.some(p => p < 0)) { console.log("FALTA un elemento", pos); mal++; }
for (let k = 1; k < pos.length; k++) if (pos[k] < pos[k - 1]) { console.log("ORDEN MAL", pos); mal++; break; }
if (!/<mergeCell ref="A2:D2"\/>/.test(x)) { console.log("falta el merge de la fila-título"); mal++; }
XLSX.read(out, { type: "array" });
console.log(mal ? "ROJO ads-xlsx-orden" : "OK ads-xlsx-orden");
process.exit(mal ? 1 : 0);
