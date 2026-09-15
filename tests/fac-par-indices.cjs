/* Regresión v18.56 — los resultados del Promise.all de Facturación se leen POR NOMBRE.
   La v18.29 insertó `facFetchModif()` en el MEDIO de la lista de lecturas de `facTick` y no
   corrió los índices de abajo, así que `_facPar[8]`, `[9]` y `[10]` quedaron apuntando a la
   lectura anterior: los saldos traían las tareas y `_facGuardadoHoy` —que tiene que ser un
   Set— pasó a ser el objeto de saldos. `.has` no existe ahí, así que facTick moría con
   «_facGuardadoHoy.has is not a function», salía por su catch y la pantalla quedaba en
   «Cargando tandas…». Lo destapó el cartel de error de la v18.55.
   Chequea:
     1) que no quede NINGÚN acceso por índice a los resultados (`_facPar[n]` / `res[n]`);
     2) que la cantidad de nombres desestructurados sea igual a la de lecturas del Promise.all
        — si alguien agrega una y no agrega el nombre, esto se pone en rojo;
     3) en vivo: después de un facTick con datos, `_facGuardadoHoy` es un Set de verdad y los
        saldos son los saldos, no las tareas.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];

// ---- 1) sin accesos por índice ----
const porIndice = src.match(/_facPar\s*\[\s*\d+\s*\]/g) || [];
if (porIndice.length) fallas.push("quedan " + porIndice.length + " accesos _facPar[n]: " + porIndice.join(", "));

// ---- 2) nombres vs lecturas, en facTick ----
const iTick = src.indexOf("const _facPar = await Promise.all([");
if (iTick < 0) fallas.push("no encuentro el Promise.all de facTick");
else {
  const bloque = src.slice(iTick, src.indexOf("]);", iTick));
  // una lectura por línea que llame a algo con .catch(
  const lecturas = (bloque.match(/\.catch\(/g) || []).length;
  const iDes = src.indexOf("const [", iTick);
  const des = src.slice(iDes, src.indexOf("] = _facPar;", iDes));
  const nombres = des.replace("const [", "").split(",").map(s => s.trim()).filter(Boolean).length;
  if (lecturas !== nombres) {
    fallas.push("facTick: " + lecturas + " lecturas en el Promise.all pero " + nombres +
                " nombres desestructurados — si se agregó una lectura, falta su nombre");
  }
  if (lecturas < 10) fallas.push("facTick: sólo " + lecturas + " lecturas detectadas, el parseo debe estar mal");
}

if (fallas.length) {
  console.log("fac-par-indices: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

// ---- 3) en vivo ----
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("fac-par-indices: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    // cada lectura devuelve algo RECONOCIBLE, para ver si el nombre recibe lo suyo
    window.fetchMonitorSheet = async function () { return new Map(); };
    window.facFetchFcKeys      = async function () { return new Set(["E01A"]); };
    window.fetchFacturadosHoy  = async function () { return new Set(); };
    window.fetchFacturadosTodos= async function () { return new Set(); };
    window.facFetchLios        = async function () { return {}; };
    window.facFetchEquiv       = async function () { return {}; };
    window.facFetchFaltantes   = async function () { return {}; };
    window.facFetchModif       = async function () { return {}; };
    window.facFetchCajas       = async function () { return {}; };
    window.facFetchTareas      = async function () { return { NO_SOY_SALDO: 1 }; };
    window.stockFetchSaldos    = async function () { return { "505": { terminado: 7 } }; };
    window.cpLoadGuardadoHoy   = async function () { return new Set(["505"]); };
    window.facCorreccData      = async function () { return [{ np: "98765", sec: "1", ppal: "2", cajas: 3 }]; };
    window.facFetchNcChef      = async function () { return []; };
    window.facFetchArmadosEventos = async function () { return new Set(); };
    window.facCorreccRichCached   = async function () { return []; };
    window.facRender = function () {};   // no nos interesa el dibujo

    await facTick();
    out.guardadoEsSet   = _facGuardadoHoy instanceof Set;
    out.guardadoTraeLoSuyo = _facGuardadoHoy instanceof Set && _facGuardadoHoy.has("505");
    out.saldosSonSaldos = !!(_facSaldosN && _facSaldosN["505"]) && !(_facSaldosN && _facSaldosN.NO_SOY_SALDO);
    out.correccEsLaSuya = !!(_facSecByNp && _facSecByNp.get && _facSecByNp.get("98765"));
    return out;
  });
  const pass = Object.keys(r).every(k => r[k]) && errs.length === 0;
  console.log("fac-par-indices:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
