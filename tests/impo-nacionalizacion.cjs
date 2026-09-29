/* v22.37 — Costo de nacionalización + MOQ/derechos del módulo Pedidos Importación.
   Verifica las funciones PURAS (_pedImpNacionalizar, _esProvNtl) contra los
   números del Excel "Calculo_Nacionalizacion" que trajo el usuario. Se extraen del index.html
   y se evalúan en un sandbox, así el test avisa si alguien cambia una tasa o la fórmula.

   Números de referencia (Excel, hoja "Carga Consolidada"):
     FOB 33.381,60 · m³ 31,53 · valor m³ flete 110 · TN 10  ->  costo NO recuperable 22.147,73
     y "Costo Nacionalizacion" = 22.147,73 / 33.381,60 = 0,6635 (66%).
   El 5% de NTL (línea "NTL", 0,05×FOB = 1.669,08) va SÓLO en proveedores NTL. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = (fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8") + "\n" + fs.readFileSync(path.join(__dirname, "..", "importacion.js"), "utf8"));
/* El bloque puro va desde la declaración de _NTL_PROVEEDORES hasta justo antes del bloque
   de config de la v23.89 (que ya toca DOM y red). ⚠ v23.89: los objetos pasaron de `const`
   a `let` porque son CACHÉ — la fuente es GV_Imp_Proveedor. Lo que queda escrito en el
   archivo es el FALLBACK, y es justo lo que mide este test: si el fetch falla, la cuenta
   tiene que dar igual que siempre. */
const ini = html.indexOf("let _NTL_PROVEEDORES") >= 0 ? html.indexOf("let _NTL_PROVEEDORES") : html.indexOf("const _NTL_PROVEEDORES");
const _finCfg = html.indexOf("v23.89 (Luis, 29/09) — LA CONFIG DE IMPORTADOS VIVE EN TABLAS");
const fin = _finCfg > 0 ? html.lastIndexOf("/*", _finCfg) : html.indexOf("async function openPedidosImportacion");
if (ini < 0 || fin < 0 || fin < ini) { console.error("No se encontró el bloque de nacionalización en index.html"); process.exit(2); }
const src = html.slice(ini, fin);

const sandbox = { Number, Math, Date, Object, isFinite, String,
  _isoToDdMmAa: function (s) { return String(s || ""); }, escapeHtml: function (s) { return String(s); } };
vm.createContext(sandbox);
try { vm.runInContext(src, sandbox); } catch (e) { console.error("El bloque no compila:", e.message); process.exit(1); }

const N = sandbox;
let fail = 0;
function ok(cond, msg) { if (!cond) { fail++; console.error("✗ " + msg); } else { console.log("✓ " + msg); } }
function near(a, b, tol, msg) { ok(Math.abs(a - b) <= (tol || 0.5), msg + "  (dio " + (Math.round(a * 100) / 100) + ", esperaba " + b + ")"); }

// --- NTL: quién lleva el 5% ---
["Frontier", "Fujian", "Kangli", "Zhixin"].forEach(function (p) { ok(N._esProvNtl(p) === true, p + " factura vía NTL"); });
["Ownland", "Becky", "Hugo Wong"].forEach(function (p) { ok(N._esProvNtl(p) === false, p + " NO usa NTL"); });

// --- Consolidada CON NTL (el ejemplo del Excel) ---
var c = N._pedImpNacionalizar(33381.6, 31.53, { modo: "consolidada", valorM3: 110, tn: 10, ntl: true });
// v23.77 (Luis): derechos 18% (no 35%). Excel: 22.147,73 con la tasa vieja; − 6.292,85 (35%→18% de CIF 37.016,81) = 15.854,88.
// v23.79: FOB 33.381,6 > 10.000 → estadística 3% del CIF SIN tope (1.110,50).
near(c.noRecup, 15854.88, 1, "Consolidada+NTL: no recuperable = 15.854,88 (derechos 18%, estadística 3% sin tope: FOB > 10.000)");
near(c.factor, 15854.88 / 33381.6, 0.001, "Consolidada+NTL: factor = no recup / FOB");
near(c.landed, 33381.6 + 15854.88, 1, "Consolidada+NTL: puesto en Arg = FOB + no recup");
near(c.ntl, 1669.08, 0.5, "Consolidada: línea NTL = 5% del FOB");

// --- Consolidada SIN NTL: baja exactamente el 5% del FOB ---
var s = N._pedImpNacionalizar(33381.6, 31.53, { modo: "consolidada", valorM3: 110, tn: 10, ntl: false });
near(s.ntl, 0, 0.01, "Consolidada sin NTL: no hay línea NTL");
near(c.noRecup - s.noRecup, 1669.08, 0.5, "Sacar NTL baja el no recuperable en 5% del FOB");

// --- Full Container CON NTL (hoja "Carga Full") ---
var f = N._pedImpNacionalizar(7282, 26, { modo: "full", fleteFull: 2000, ntl: true });
near(f.noRecup, 6767.83, 1, "Full+NTL: no recuperable ≈ 6.767,83 (FOB 7.282 → estadística fija 180)");
near(Math.max.apply(null, f.detalle.filter(function (d) { return /Estad/.test(d[0]); }).map(function (d) { return d[1]; })), 180, 0.01, "FOB 6.001–10.000: estadística fija u$s 180");

// --- v23.75: desglose expandible (Luis) ---
["consolidada", "full"].forEach(function (m) {
  var r = N._pedImpNacionalizar(9324, 12.4, { modo: m, valorM3: 110, tn: 0, ntl: true, fleteFull: 2000 });
  var suma = r.detalle.reduce(function (s, d) { return s + d[1]; }, 0);
  near(suma, r.noRecup, 0.01, m + ": el desglose suma lo no recuperable");
  ok(r.detalle.every(function (d) { return typeof d[2] === "string" && d[2].length > 0; }), m + ": cada línea dice cómo se calcula");
  ok(r.cif > 0 && /FOB/.test(r.cifTxt), m + ": trae la base CIF explicada");
});
var itemsB = [{ cod: "970E", desc: "x", proyUni: 1000, fobUni: 2.5, aPedirUni: 3000 }, { cod: "971E", desc: "y", proyUni: 500, fobUni: 0, aPedirUni: 0 }];
var nacB = N._pedImpNacionalizar(9324, 12.4, { modo: "consolidada", valorM3: 110, tn: 0, ntl: false });
var hB = N._pedImpBandaHtml(nacB, 9324, { prov: "Becky", items: itemsB, m3: 12.4 });
/* v23.91 (Luis): el desglose ya NO se abre DENTRO del chip — lo hacía crecer y empujaba la
   tabla. La banda quedó de una línea con un botón «ver desglose» que abre el pop-up, y los
   datos para rearmarlo quedan en _pedImpDesgData. Lo que se mide ahora es eso: que la banda
   sea chica y que el contenido siga estando completo, que es lo que el test cuidaba. */
ok(!/<details class="pedimp-desg"/.test(hB), "La banda ya no lleva el desglose adentro (v23.91)");
ok((hB.match(/pedImpDesgPop\(/g) || []).length === 1, "Un solo chip (el costo) abre el desglose en el pop-up");
// v24.58 (Thomas) — el mínimo de 25k ya no se muestra: es una norma general, no un requisito.
ok(!/mínimo|No llega solo|Ya se puede pedir/.test(hB), "La banda no habla del mínimo del pedido");
ok(!!N._pedImpDesgData["Becky"], "La banda deja los datos para que el pop-up rearme el desglose");
var dDer = N._pedImpDesgDer(nacB, 9324, 12.4);
ok(/÷/.test(dDer) && /Derechos/.test(dDer) && /Puesto en Arg/.test(dDer), "Muestra las líneas de lo no recuperable");
// v24.66 — el código del mínimo (25k) se borró: no puede volver
ok(typeof N._pedImpProy25k === "undefined" && typeof N._pedImpDesgIzq === "undefined", "Sin código del mínimo del pedido");
ok(/<details/.test(dDer), "Cada concepto sigue siendo expandible (la lógica de detalle se mantiene)");

// v23.78 (Luis): derechos 35% sólo Fujian, 18% el resto.
ok(N._derechosProv("Fujian") === 0.35 && N._derechosProv(" Fujian ") === 0.35, "Fujian paga 35% de derechos");
["Frontier", "Kangli", "Becky", "Ownland", ""].forEach(function (p) { ok(N._derechosProv(p) === 0.18, (p || "(vacío)") + " paga 18%"); });
["consolidada", "full", "avion"].forEach(function (m) {
  var b18 = N._pedImpNacionalizar(9324, 12.4, { modo: m, valorM3: 110, tn: 1, ntl: true, fleteFull: 2000 });
  var b35 = N._pedImpNacionalizar(9324, 12.4, { modo: m, valorM3: 110, tn: 1, ntl: true, fleteFull: 2000, derechos: 0.35 });
  var d18 = b18.detalle.filter(function (d) { return /^Derechos/.test(d[0]); })[0];
  var d35 = b35.detalle.filter(function (d) { return /^Derechos/.test(d[0]); })[0];
  ok(/18%/.test(d18[0]) && /35%/.test(d35[0]), m + ": el rótulo dice la tasa");
  ok(Math.abs(d35[1] / d18[1] - 35 / 18) < 1e-9, m + ": derechos 35% = 35/18 del de 18%");
  ok(b35.noRecup > b18.noRecup, m + ": Fujian sale más caro");
});
// v23.79 (Luis): estadística por tramo de FOB — ≤ 6.000: 3%; 6.001–10.000: 180 fijo; > 10.000: 3% sin tope.
near(N._nacEstad(5000, 5600).v, 168, 0.01, "FOB 5.000: 3% del CIF");
near(N._nacEstad(6000, 7000).v, 210, 0.01, "FOB 6.000: 3% del CIF, sin tope");
near(N._nacEstad(6001, 6100).v, 180, 0.01, "FOB 6.001: 180 fijo");
near(N._nacEstad(10000, 11000).v, 180, 0.01, "FOB 10.000: 180 fijo");
near(N._nacEstad(10001, 11000).v, 330, 0.01, "FOB 10.001: 3% sin tope");
// v23.80 (Luis): recuperable separado; la comisión NTL va sobre el FOB, no sobre el CIF.
var r80 = N._pedImpNacionalizar(33381.6, 31.53, { modo: "consolidada", valorM3: 110, tn: 10, ntl: true });
var d80 = r80.detalle.filter(function (d) { return /NTL/.test(d[0]); })[0];
near(d80[1], 0.05 * 33381.6, 0.01, "NTL = 5% del FOB (no del CIF)");
ok(r80.cif > 33381.6 && Math.abs(d80[1] - 0.05 * r80.cif) > 1, "NTL no usa el CIF");
var base80 = r80.cif + r80.detalle.filter(function (d) { return /^Derechos/.test(d[0]); })[0][1] + r80.detalle.filter(function (d) { return /^Estad/.test(d[0]); })[0][1];
near(r80.recup, base80 * (0.21 + 0.20 + 0.06 + 0.0017), 0.01, "Recuperable = 47,17% de (CIF + derechos + estadística)");
near(r80.noRecup, 15854.88, 1, "Lo recuperable NO se suma al no recuperable");
var fu80 = N._pedImpNacionalizar(7282, 26, { modo: "full", fleteFull: 2000, ntl: true });
ok(fu80.recup > 0 && fu80.detRecup.length === 4, "Contenedor también muestra lo recuperable");
var av80 = N._pedImpNacionalizar(9324, 12.4, { modo: "avion", tn: 1 });
ok(av80.recup === 0, "Avión (courier): el IVA no se recupera, queda en el costo");
var h80 = N._pedImpDesgDer(r80, 33381.6, 31.53);
ok(/No recuperable/.test(h80) && /Recuperable ·/.test(h80) && /Total recuperable/.test(h80) && /Plata a tener al despachar/.test(h80), "El desglose separa recuperable de no recuperable");
// v23.81 (Luis): en avión también va la NTL.
var avN = N._pedImpNacionalizar(9324, 12.4, { modo: "avion", tn: 1, ntl: true });
var avS = N._pedImpNacionalizar(9324, 12.4, { modo: "avion", tn: 1, ntl: false });
near(avN.noRecup - avS.noRecup, 0.05 * 9324, 0.01, "Avión: NTL suma 5% del FOB");
near(avN.ntl, 0.05 * 9324, 0.01, "Avión: ntl informado");
if (fail) { console.error("\n" + fail + " chequeo(s) fallaron."); process.exit(1); }
console.log("\nOK — nacionalización y proyección 25k.");
