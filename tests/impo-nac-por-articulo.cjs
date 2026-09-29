/* v24.01 (Luis, 29/09) — el COSTO DE NACIONALIZACIÓN POR ARTÍCULO del pedido en curso.
   Prueba la función PURA `_impNacReparto` extraída del index.html, con los tres criterios.

   Lo que fija este test, y es lo que se pierde primero si alguien lo toca:
     · la suma del reparto es EXACTAMENTE el no recuperable del embarque (los tres criterios);
     · "m3"    reparte por volumen: dos artículos de igual m³ pagan igual aunque uno valga 10x;
     · "fob"   reparte por plata: proporcional al u$s de cada uno;
     · "mixto" manda el FLETE por m³ y el resto por FOB — o sea que NO le cobra los derechos
       al volumen, que es justo lo que pasaría repartiendo todo por m³;
     · los guards: m³ todos en 0 no divide por cero ni le tira todo al primero. */
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const ini = html.indexOf("let _NTL_PROVEEDORES");
const _finCfg = html.indexOf("v23.89 (Luis, 29/09) — LA CONFIG DE IMPORTADOS VIVE EN TABLAS");
const fin = _finCfg > 0 ? html.lastIndexOf("/*", _finCfg) : html.indexOf("async function openPedidosImportacion");
if (ini < 0 || fin < 0 || fin < ini) { console.error("No se encontró el bloque de nacionalización en index.html"); process.exit(2); }
const sandbox = { Number, Math, Date, Object, isFinite, String,
  _isoToDdMmAa: function (s) { return String(s || ""); }, escapeHtml: function (s) { return String(s); } };
vm.createContext(sandbox);
try { vm.runInContext(html.slice(ini, fin), sandbox); } catch (e) { console.error("El bloque no compila:", e.message); process.exit(1); }
const N = sandbox;

let fail = 0;
function ok(c, m) { if (!c) { fail++; console.error("✗ " + m); } else console.log("✓ " + m); }
function near(a, b, tol, m) { ok(Math.abs(a - b) <= (tol || 0.01), m + "  (dio " + (Math.round(a * 100) / 100) + ", esperaba " + (Math.round(b * 100) / 100) + ")"); }
const suma = (a) => a.reduce((x, y) => x + y, 0);

if (typeof N._impNacReparto !== "function") { console.error("✗ falta _impNacReparto (se la llevó alguna edición)"); process.exit(1); }

// Embarque de referencia: el mismo del Excel que usa tests/impo-nacionalizacion.cjs
const res = N._pedImpNacionalizar(33381.6, 31.53, { modo: "consolidada", valorM3: 110, tn: 10, ntl: true });
ok(res.ok === true, "el embarque de referencia calcula");

// A) cada concepto declara su base — sin eso "mixto" no puede existir
const bases = (res.detalle || []).map((d) => d[3]);
ok(bases.every((b) => b === "m3" || b === "fob"), "todo concepto del detalle declara su base (m3 | fob)");
const flete = (res.detalle || []).filter((d) => /Flete/.test(d[0]));
ok(flete.length > 0 && flete.every((d) => d[3] === "m3"), "el FLETE se reparte por m³ (se paga por volumen)");
const der = (res.detalle || []).filter((d) => /Derechos|Estad|NTL|Despachante/.test(d[0]));
ok(der.length > 0 && der.every((d) => d[3] === "fob"), "derechos, estadística, despachante y NTL se reparten por FOB (son % del FOB/CIF)");

// Dos artículos: MISMO m³, FOB muy distinto. Es el caso donde los criterios se separan.
const items = [{ m3: 10, fob: 30000, uni: 1000 }, { m3: 10, fob: 3000, uni: 1000 }];

// B) la suma cierra con el costo del embarque, en los tres criterios
["mixto", "m3", "fob"].forEach(function (c) {
  const r = N._impNacReparto(res, items, c);
  near(suma(r.items), res.noRecup, 0.01, "criterio " + c + ": la suma repartida = el no recuperable del embarque");
  near(r.total, res.noRecup, 0.01, "criterio " + c + ": el total que informa coincide");
});

// C) por m³: mismo volumen → mismo costo, aunque uno valga 10 veces más
const rm3 = N._impNacReparto(res, items, "m3");
near(rm3.items[0], rm3.items[1], 0.01, "por m³: dos artículos de igual m³ pagan lo mismo (aunque uno valga 10x)");

// D) por FOB: proporcional a la plata
const rfob = N._impNacReparto(res, items, "fob");
near(rfob.items[0] / rfob.items[1], 10, 0.01, "por FOB: el de 30.000 paga 10 veces el de 3.000");

// E) mixto: queda EN EL MEDIO — el flete parejo por m³, los derechos con la plata
const rmix = N._impNacReparto(res, items, "mixto");
ok(rmix.items[0] > rm3.items[0] && rmix.items[0] < rfob.items[0],
  "mixto queda entre m³ y FOB: el caro paga más que por m³ y menos que por FOB");
ok(rmix.items[1] < rm3.items[1] && rmix.items[1] > rfob.items[1],
  "mixto: el barato paga menos que por m³ y más que por FOB");
// y la parte por m³ del mixto es exactamente el flete, repartido en partes iguales (mismo m³)
const fleteTot = suma(flete.map((d) => d[1]));
const k = res.noRecup / suma((res.detalle || []).map((d) => d[1]));
near(rmix.items[0] - rmix.items[1], k * (suma(der.concat((res.detalle || []).filter((d) => d[3] === "fob" && !/Derechos|Estad|NTL|Despachante/.test(d[0]))).map((d) => d[1]))) * (30000 - 3000) / 33000,
  0.5, "mixto: la diferencia entre los dos es SÓLO la parte por FOB");
near(rmix.items[0] + rmix.items[1] - k * fleteTot, k * suma((res.detalle || []).filter((d) => d[3] === "fob").map((d) => d[1])), 0.5,
  "mixto: lo que no es flete se reparte por FOB");

// F) guards: sin m³ no se divide por cero — cae a FOB
const sinM3 = N._impNacReparto(res, [{ m3: 0, fob: 30000, uni: 1 }, { m3: 0, fob: 3000, uni: 1 }], "m3");
near(suma(sinM3.items), res.noRecup, 0.01, "sin m³ cargado: no divide por cero y la suma sigue cerrando");
near(sinM3.items[0] / sinM3.items[1], 10, 0.01, "sin m³ cargado: se cae a repartir por FOB, no le tira todo al primero");

// G) guard duro: ni m³ ni FOB → por unidades; y sin nada, parejo
const soloUni = N._impNacReparto(res, [{ m3: 0, fob: 0, uni: 3 }, { m3: 0, fob: 0, uni: 1 }], "m3");
near(suma(soloUni.items), res.noRecup, 0.01, "sin m³ ni FOB: reparte por unidades y la suma cierra");
near(soloUni.items[0] / soloUni.items[1], 3, 0.01, "sin m³ ni FOB: proporcional a las unidades");
const nada = N._impNacReparto(res, [{ m3: 0, fob: 0, uni: 0 }, { m3: 0, fob: 0, uni: 0 }], "m3");
near(nada.items[0], nada.items[1], 0.01, "sin ningún dato: parejo entre las líneas, no todo al primero");

// H) lista vacía / embarque sin FOB: no explota
const vacio = N._impNacReparto(res, [], "mixto");
ok(Array.isArray(vacio.items) && vacio.items.length === 0 && vacio.total === 0, "lista vacía: devuelve vacío sin romper");
const sinFob = N._impNacReparto(N._pedImpNacionalizar(0, 10, { modo: "consolidada" }), items, "mixto");
near(suma(sinFob.items), 0, 0.01, "embarque sin FOB: no inventa costo");

// I) avión: la suma se ESCALA al no recuperable (su detalle no suma lo mismo, por el certificado)
const av = N._pedImpNacionalizar(7282, 12, { modo: "avion", tn: 2, ntl: true });
const rav = N._impNacReparto(av, items, "mixto");
near(suma(rav.items), av.noRecup, 0.01, "avión: la suma repartida es el no recuperable, no la suma del detalle");

// J) el texto del criterio existe para los tres (es lo que explica el chip)
["mixto", "m3", "fob"].forEach(function (c) {
  const t = N._impNacCritTxt(c);
  ok(t && t.lbl && t.tip && t.tip.length > 20, "criterio " + c + ": tiene etiqueta y explicación");
});

console.log(fail ? "\n✗ " + fail + " fallo(s)" : "\n✓ nacionalización por artículo OK");
process.exit(fail ? 1 : 0);
