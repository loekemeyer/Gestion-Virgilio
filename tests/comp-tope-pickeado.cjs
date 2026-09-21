/* Regresión v20.90 — EL ARMADO NO PUEDE ENTREGAR MÁS DE LO QUE SE PICKEÓ.

   POR QUÉ. `Entregas_Virgilio` escribe `cajas_entregadas = cajas_pedidas − faltante`, y ese
   faltante sale del reparto del Paso 2, que vive detrás de un booleano GLOBAL:

       const hayFalt = arts.some(a => a.nps.length);

   `arts` sólo tiene los artículos del faltante que se pudieron cruzar contra `pickBase`. Si
   ese cruce falla —un código que no matchea, un pedido que no está en la base— `hayFalt`
   queda en false, `faltMap` sale VACÍO y se pierden TODOS los faltantes de la tanda: cada
   línea se escribe «entregadas = pedidas» con el pallet a medio llenar, y el remito sale
   diciendo que se entregó lo que no se levantó.

   El TOPE no depende del reparto: el picking (PKC) dice cuántas cajas se levantaron de cada
   código, y la suma de lo entregado en la tanda no puede pasarse de ahí.

   Chequea:
   1. el reparto perdido igual queda topado contra lo pickeado (el caso de la fuga);
   2. el recorte empieza por la NP que más entregó, y la diferencia va a `cajas_falto`;
   3. la clave del tope es ESTRICTA: pela la L del pedido y el sufijo de empresa, pero NO
      colapsa la E final — 809 y 809E son artículos distintos y un match de más RECORTA
      cajas que sí están en el pallet;
   4. lo que no tiene faltante pickeado no se toca;
   5. candado invertido: sin el bloque del tope, el caso (1) escribe de más.
   Sale 1 si falla. */
const path = require("path"), fs = require("fs");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    let saved = null;
    window.alert = function () {}; window.confirm = function () { return true; };
    window._compBuildLiosData = function () {};
    window._compTandaYaArmada = async function () { return false; };
    window._compNpsYaArmadas = async function () { return []; };
    window.askArmadoUbicaciones = async function () { return {}; };
    window.liosSend = function () {};
    window._compLiosResumen = function () { return ""; };
    window._compClearPersist = function () {};
    window.stockMove = async function () {};
    window._compSendEntregasEvento = function () {};
    window._compSaveEntregas = function (rows) { saved = rows; };
    window.enqueueReport = function () {};
    window.trySendOneReport = undefined;
    window.updatePendingIndicator = function () {};
    window.renderPendingSuggestion = function () {};
    window.getLegajoState = function () { return { armado: { active: true, value: "E99Z", ts_inicio: null } }; };
    window.setLegajoState = function () {};
    window.fetch = function () {
      return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve([]); } });
    };

    function armar(pedidoFull, faltRaw) {
      saved = null;
      _comp = {
        legajo: "237", tanda: "E99Z", fecha: "2026-09-21", clasifDone: true,
        nps: [{ np: "98001", clase: "nada", liosDone: true, codes: [], liosArr: [] },
              { np: "98002", clase: "nada", liosDone: true, codes: [], liosArr: [] }],
        arts: [], hayFalt: false, faltRaw: faltRaw,       // <- el reparto se perdió
        pedidoFull: pedidoFull, step: 2, _difMovs: []
      };
      return compTerminar().then(function () { return saved; });
    }
    function de(rows, np, art) {
      const f = (rows || []).find(function (r) { return r.np === np && r.cod_art === art; });
      return f ? [f.cajas_entregadas, f.cajas_falto] : null;
    }

    // 1+2) el reparto se perdió; el picking dice 12 de 30 → se recorta 18, por la que más pidió
    let rows = await armar(
      [{ np: "98001", cod: "1", items: [{ art: "501", cajas: 20 }] },
       { np: "98002", cod: "2", items: [{ art: "501", cajas: 10 }] }],
      [{ art: "501", esp: 30, real: 12, falta: 18 }]);
    out.tope_98001 = de(rows, "98001", "501");     // [2, 18]
    out.tope_98002 = de(rows, "98002", "501");     // [10, 0]
    out.tope_total = (rows || []).reduce(function (a, x) { return a + x.cajas_entregadas; }, 0);   // 12

    // 3a) la L del pedido y el sufijo de empresa SÍ matchean (438EL vs "438E" de codBase)
    rows = await armar(
      [{ np: "98001", cod: "1", items: [{ art: "438EL", cajas: 9 }] }],
      [{ art: "438E", esp: 9, real: 4, falta: 5 }]);
    out.conL = de(rows, "98001", "438EL");         // [4, 5]

    // 3b) la E final NO se colapsa: 809 no se topa con el faltante de 809E
    rows = await armar(
      [{ np: "98001", cod: "1", items: [{ art: "809", cajas: 10 }] }],
      [{ art: "809E", esp: 4, real: 1, falta: 3 }]);
    out.noColapsaE = de(rows, "98001", "809");     // [10, 0]

    // 3c) un dual que en PKC entró dos veces (una por empresa) SUMA, no toma el mínimo
    rows = await armar(
      [{ np: "98001", cod: "1", items: [{ art: "437E", cajas: 10 }] }],
      [{ art: "437E", esp: 6, real: 2, falta: 4 }, { art: "437E", esp: 5, real: 3, falta: 2 }]);
    out.dualSuma = de(rows, "98001", "437E");      // [5, 5]

    // 4) sin faltante pickeado del código, no se toca nada
    rows = await armar(
      [{ np: "98001", cod: "1", items: [{ art: "501", cajas: 7 }, { art: "510", cajas: 3 }] }],
      [{ art: "501", esp: 7, real: 7, falta: 0 }]);
    out.intacto = de(rows, "98001", "510");        // [3, 0]

    out.sinErrores = true;
    return out;
  });

  // 5) candado invertido: el bloque del tope tiene que existir en compTerminar
  const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  const i = src.indexOf("var _topeAvisos = [];");
  const j = src.indexOf("const nFalt = Object.keys(faltMap).length;", i > 0 ? i : 0);
  const bloque = i > 0 && j > i ? src.slice(i, j) : "";
  const tieneTope = /_pick\[k\]/.test(bloque) && /cajas_falto/.test(bloque) &&
                    /codBase\(pkStripL/.test(bloque) && !/replace\(\/E\$\//.test(bloque);

  const eq = (a, x, y) => Array.isArray(a) && a[0] === x && a[1] === y;
  const pass =
    eq(r.tope_98001, 2, 18) && eq(r.tope_98002, 10, 0) && r.tope_total === 12 &&
    eq(r.conL, 4, 5) && eq(r.noColapsaE, 10, 0) && eq(r.dualSuma, 5, 5) &&
    eq(r.intacto, 3, 0) && tieneTope === true && errs.length === 0;

  console.log("comp-tope-pickeado:", JSON.stringify(r), "· bloque:", tieneTope,
              "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
