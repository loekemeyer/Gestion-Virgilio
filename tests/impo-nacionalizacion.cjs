/* v22.37 — Costo de nacionalización + proyección al mínimo (25k) del módulo Pedidos Importación.
   Verifica las funciones PURAS (_pedImpNacionalizar, _pedImpProy25k, _esProvNtl) contra los
   números del Excel "Calculo_Nacionalizacion" que trajo el usuario. Se extraen del index.html
   y se evalúan en un sandbox, así el test avisa si alguien cambia una tasa o la fórmula.

   Números de referencia (Excel, hoja "Carga Consolidada"):
     FOB 33.381,60 · m³ 31,53 · valor m³ flete 110 · TN 10  ->  costo NO recuperable 22.147,73
     y "Costo Nacionalizacion" = 22.147,73 / 33.381,60 = 0,6635 (66%).
   El 5% de NTL (línea "NTL", 0,05×FOB = 1.669,08) va SÓLO en proveedores NTL. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
// El bloque puro va desde `const _NTL_PROVEEDORES` hasta justo antes de openPedidosImportacion.
const ini = html.indexOf("const _NTL_PROVEEDORES");
const fin = html.indexOf("async function openPedidosImportacion");
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
// v23.77 (Luis): derechos 18% (no 35%) y estadística 3% con tope u$s 180. Excel: 22.147,73 con la tasa vieja;
// ahora 22.147,73 − 6.292,85 (35%→18% de CIF 37.016,81) − 930,50 (estadística 1.110,50 → 180) = 14.924,38.
near(c.noRecup, 14924.38, 1, "Consolidada+NTL: no recuperable = 14.924,38 (derechos 18%, estadística tope 180)");
near(c.factor, 14924.38 / 33381.6, 0.001, "Consolidada+NTL: factor = no recup / FOB");
near(c.landed, 33381.6 + 14924.38, 1, "Consolidada+NTL: puesto en Arg = FOB + no recup");
near(c.ntl, 1669.08, 0.5, "Consolidada: línea NTL = 5% del FOB");

// --- Consolidada SIN NTL: baja exactamente el 5% del FOB ---
var s = N._pedImpNacionalizar(33381.6, 31.53, { modo: "consolidada", valorM3: 110, tn: 10, ntl: false });
near(s.ntl, 0, 0.01, "Consolidada sin NTL: no hay línea NTL");
near(c.noRecup - s.noRecup, 1669.08, 0.5, "Sacar NTL baja el no recuperable en 5% del FOB");

// --- Full Container CON NTL (hoja "Carga Full") ---
var f = N._pedImpNacionalizar(7282, 26, { modo: "full", fleteFull: 2000, ntl: true });
near(f.noRecup, 6767.83, 1, "Full+NTL: no recuperable ≈ 6.767,83 (Excel 6.867,38 − estadística 279,55 → 180)");
near(Math.max.apply(null, f.detalle.filter(function (d) { return /Estad/.test(d[0]); }).map(function (d) { return d[1]; })), 180, 0.01, "Estadística topeada en u$s 180");

// --- Proyección al mínimo de 25k ---
var pNunca = N._pedImpProy25k(0, 1448, 14478, 25000);
ok(pNunca.estado === "nunca", "Frontier (techo 14.478) NUNCA llega a 25k solo");
var pFalta = N._pedImpProy25k(18380, 9659, 96587, 25000);
ok(pFalta.estado === "falta", "Ownland está en camino a 25k");
near(pFalta.meses, (25000 - 18380) / 9659, 0.001, "Ownland: meses = (25k - hoy) / consumo mensual");
var pYa = N._pedImpProy25k(40000, 5000, 90000, 25000);
ok(pYa.estado === "ya", "Un proveedor con 40k de demanda ya puede pedir");
var pSin = N._pedImpProy25k(1000, 0, 50000, 25000);
ok(pSin.estado === "sinburn", "Sin consumo mensual no se puede estimar la fecha");

// --- v23.75: desglose expandible (Luis) ---
["consolidada", "full"].forEach(function (m) {
  var r = N._pedImpNacionalizar(9324, 12.4, { modo: m, valorM3: 110, tn: 0, ntl: true, fleteFull: 2000 });
  var suma = r.detalle.reduce(function (s, d) { return s + d[1]; }, 0);
  near(suma, r.noRecup, 0.01, m + ": el desglose suma lo no recuperable");
  ok(r.detalle.every(function (d) { return typeof d[2] === "string" && d[2].length > 0; }), m + ": cada línea dice cómo se calcula");
  ok(r.cif > 0 && /FOB/.test(r.cifTxt), m + ": trae la base CIF explicada");
});
var itemsB = [{ cod: "970E", desc: "x", proyUni: 1000, fobUni: 2.5, aPedirUni: 3000 }, { cod: "971E", desc: "y", proyUni: 500, fobUni: 0, aPedirUni: 0 }];
var prB = N._pedImpProy25k(7500, 2500, 60000, 25000);
var nacB = N._pedImpNacionalizar(9324, 12.4, { modo: "consolidada", valorM3: 110, tn: 0, ntl: false });
var hB = N._pedImpBandaHtml(prB, nacB, 25000, 9324, { prov: "Becky", items: itemsB, m3: 12.4 });
ok((hB.match(/<details class="pedimp-desg"/g) || []).length === 2, "La banda tiene los dos chips expandibles");
ok(/970E/.test(hB) && /sin FOB/.test(hB), "El desglose del consumo lista los artículos y marca los sin FOB");
ok(/÷/.test(hB) && /Derechos/.test(hB) && /Puesto en Arg/.test(hB), "Muestra la cuenta de meses y las líneas de lo no recuperable");
ok(!/ open /.test(hB), "Cerrados por defecto");
N._pedImpDesgAb["Becky|izq"] = 1;
ok(/data-k="Becky\|izq" ontoggle="_pedImpDesgToggle\(this\)" open/.test(N._pedImpBandaHtml(prB, nacB, 25000, 9324, { prov: "Becky", items: itemsB, m3: 12.4 })), "El abierto sobrevive al re-render");

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
if (fail) { console.error("\n" + fail + " chequeo(s) fallaron."); process.exit(1); }
console.log("\nOK — nacionalización y proyección 25k.");
