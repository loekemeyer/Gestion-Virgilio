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
near(c.noRecup, 22147.73, 1, "Consolidada+NTL: no recuperable = 22.147,73 (Excel H4)");
near(c.factor, 0.6635, 0.001, "Consolidada+NTL: factor = 0,6635 (Excel D2)");
near(c.landed, 33381.6 + 22147.73, 1, "Consolidada+NTL: puesto en Arg = FOB + no recup");
near(c.ntl, 1669.08, 0.5, "Consolidada: línea NTL = 5% del FOB");

// --- Consolidada SIN NTL: baja exactamente el 5% del FOB ---
var s = N._pedImpNacionalizar(33381.6, 31.53, { modo: "consolidada", valorM3: 110, tn: 10, ntl: false });
near(s.ntl, 0, 0.01, "Consolidada sin NTL: no hay línea NTL");
near(c.noRecup - s.noRecup, 1669.08, 0.5, "Sacar NTL baja el no recuperable en 5% del FOB");

// --- Full Container CON NTL (hoja "Carga Full") ---
var f = N._pedImpNacionalizar(7282, 26, { modo: "full", fleteFull: 2000, ntl: true });
near(f.noRecup, 6867.38, 1, "Full+NTL: no recuperable ≈ 6.867,38 (Excel H9)");

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

if (fail) { console.error("\n" + fail + " chequeo(s) fallaron."); process.exit(1); }
console.log("\nOK — nacionalización y proyección 25k.");
