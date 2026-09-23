/* Regresión v20.17 — los pasos de EXCEDENTE del picking van en el ORDEN DEL RECORRIDO,
   no todos al principio.

   Thomas, 2026-09-18, después de probar el módulo de operarios con una tanda: "primero
   le dice que pickee del excedente, eso rompe el flujo de movimiento por las góndolas".
   La v15.41 (pedido de Luis) los había puesto a TODOS adelante para enterarse temprano
   si el excedente miente; el costo es que el operario arranca por la zona del excedente
   —la zona P, orden 718..757 en GV_Lugar, o sea DESPUÉS de toda la góndola (1..657)— y
   después vuelve.

   Chequea:
   - El PRIMER paso del picking NO es de excedente cuando la góndola arranca antes.
   - Cada paso ·EXC cae en la posición que le da el `orden` del sector donde está el
     excedente (un excedente en A05 se pickea entre A01 y D18; uno en P13, al final).
   - Sin el mapa de sectores (sin red / GV_Lugar caída) los pasos ·EXC van al FINAL,
     nunca al principio.
   - gvFetchLugares expone `orden` por sector (es de donde sale el recorrido).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    window.alert = function () {};
    const leg = "77";
    legajoInput.value = leg;

    // Una NP de Loeke (>90000) con tres códigos de góndola conocidos:
    //   502 → A01 (orden 1) · 505 → D18 (281) · 809 → M16 (462)
    const NP = "98001";
    window.fetchMonitorSheet = async function () {
      return new Map([["E99A", { tanda: "E99A", pedidos: [{ np: NP }] }]]);
    };
    window.fetchPickingBase = async function () {
      return new Map([[NP, [{ art: "502", cajas: 10 }, { art: "505", cajas: 10 }, { art: "809", cajas: 10 }]]]);
    };
    window.fetchCorrecciones = async function () { return new Map(); };
    window.supaFetchAllSafe = async function () { return []; };   // el sector por empresa no se mockea
    window.pwebAgregadoAviso = function () { return ""; };
    // 502 tiene 4 cajas de excedente en P13 (fondo) y 505 tres en A05 (arranque del
    // recorrido). Ninguno cubre todo el pedido, así que los dos siguen teniendo su
    // paso de góndola por el resto.
    window.pkFetchExcedente = async function () {
      return { "502": { cajas: 4, ubics: ["P13"] }, "505": { cajas: 3, ubics: ["A05"] } };
    };

    const _gvFetchLugaresReal = gvFetchLugares;   // se guarda antes de mockearla (chequeo C)
    const claves = function () { return (_pk && _pk.items ? _pk.items : []).map(function (x) { return x.key; }); };

    // ===== (A) con el mapa de sectores: cada excedente en su lugar del recorrido =====
    window.gvFetchLugares = async function () {
      return { lista: [], set: new Set(), libres: new Set(), emp: {},
               orden: { "A01": 1, "A05": 5, "D18": 281, "M16": 462, "P13": 730 } };
    };
    localStorage.removeItem("vir_pk_" + leg);
    await showPickingList("E99A", leg);
    await new Promise(function (res) { setTimeout(res, 60); });
    const kA = claves();
    out.A_orden = kA.join(",") === "502,505·EXC,505,809,502·EXC";
    out.A_primeroNoEsExcedente = !!kA.length && kA[0].indexOf("·EXC") < 0;
    out.A_excDelFondoAlFinal = kA[kA.length - 1] === "502·EXC";
    out.A_excDelArranqueAntesDeSuGondola = kA.indexOf("505·EXC") < kA.indexOf("505");
    // el reparto no cambió: del excedente lo que hay, de góndola el resto
    const gA = (_pk.items || []).filter(function (x) { return !x.isExc; });
    const eA = (_pk.items || []).filter(function (x) { return x.isExc; });
    out.A_reparto = eA.filter(function (x) { return x.art === "505"; })[0].esp === 3 &&
                    gA.filter(function (x) { return x.art === "505"; })[0].esp === 7;

    // ===== (B) sin mapa (GV_Lugar caída): al FINAL, nunca al principio =====
    window.gvFetchLugares = async function () { throw new Error("sin red"); };
    localStorage.removeItem("vir_pk_" + leg);
    await showPickingList("E99A", leg);
    await new Promise(function (res) { setTimeout(res, 60); });
    const kB = claves();
    out.B_orden = kB.join(",") === "502,505,809,502·EXC,505·EXC";
    out.B_primeroNoEsExcedente = !!kB.length && kB[0].indexOf("·EXC") < 0;

    // ===== (D) a IGUAL orden, primero la góndola y después su excedente =====
    // v21.79 — el hueco que destapó la prueba de mutación del 23/09: invertir el
    // `items.concat(excSteps)` del merge NO rompía este test, porque con órdenes
    // distintos manda el sector y la concatenación sólo decide el DESEMPATE. El
    // comentario del código fija esa regla ("Merge estable: a igual orden, primero
    // la góndola y después el excedente") y hasta hoy sólo la sostenía un candado
    // de texto en pk-deposito-pkc. Acá se prueba corriendo: el excedente del 505
    // vive en su MISMA celda de góndola (D18), así que los dos empatan en 281.
    window.gvFetchLugares = async function () {
      return { lista: [], set: new Set(), libres: new Set(), emp: {},
               orden: { "A01": 1, "D18": 281, "M16": 462 } };
    };
    window.pkFetchExcedente = async function () {
      return { "505": { cajas: 3, ubics: ["D18"] } };
    };
    localStorage.removeItem("vir_pk_" + leg);
    await showPickingList("E99A", leg);
    await new Promise(function (res) { setTimeout(res, 60); });
    const kD = claves();
    out.D_empate_gondolaPrimero = kD.indexOf("505") >= 0 && kD.indexOf("505·EXC") >= 0 &&
                                  kD.indexOf("505") < kD.indexOf("505·EXC");
    out.D_orden = kD.join(",") === "502,505,505·EXC,809";

    // ===== (C) gvFetchLugares de verdad expone `orden` (de ahí sale el recorrido) =====
    const srcReal = _gvFetchLugaresReal.toString();
    out.C_exponeOrden = /orden\s*:\s*\{\}/.test(srcReal) && /out\.orden\[sec\]/.test(srcReal);
    return out;
  });

  const bad = Object.entries(r).filter(([, v]) => v !== true).map(([k]) => k);
  console.log("pk-excedente-orden:", JSON.stringify(r));
  console.log("  pageerrors:", errs.length ? errs.join("|") : "none");
  await b.close();
  if (bad.length || errs.length) { console.error("✗ FALLA:", bad.join(", ") || "pageerrors"); process.exit(1); }
  console.log("✓ OK");
})();
