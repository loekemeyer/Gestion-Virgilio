/* Regresión v7.02 — el aviso SSG ("picking sin stock en góndola") NO debe dispararse
   cuando el cron server-side (reconciliar_pipeline_stock, jobid 22) ya escribió la baja
   del picking de ESA tanda antes de que corra el chequeo del cliente.

   Bug real (tanda D16A, 04-08): el cron escribió a las 08:30:27 y stockBajaPicking corrió
   a las 08:30:35 → leyó el saldo YA descontado y comparó "saldo_previo − need < need", o
   sea avisaba cada vez que había menos del DOBLE de lo pickeado. Avisó "764 pidió 20 /
   había 9" (tenía 29, alcanzaba) y "729E pidió 5 / había 0" (tenía 5, alcanzaba justo).

   El fix excluye del saldo los movimientos tipo='picking' con ref = la tanda que se está
   validando. Este test cubre las dos puntas: falso positivo apagado, verdadero positivo
   (stock que de verdad no alcanzaba) sigue avisando. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const PKC = [
  { texto: "D16A|764|20|20" },   // pidió 20, puso 20 — góndola tenía 29 antes del pick
  { texto: "D16A|729E|6|5" },    // pidió 6, puso 5 (faltó 1) — góndola tenía 5, alcanzó justo
  { texto: "D16A|555|10|10" },   // puso 10 — góndola tenía 4: ESTE sí es sin stock de verdad
  { texto: "D16B|764|9|9" }      // otra tanda: no debe entrar en el cálculo
];
// Movimientos como quedan DESPUÉS de que el cron escribió la baja de D16A.
const MOVS = [
  { cod_art: "764",  deposito: "terminado", tipo: "inicial", delta: 29, ts: "2026-08-01T16:02:00Z", ref: "conteo" },
  { cod_art: "764",  deposito: "terminado", tipo: "picking", delta: -20, ts: "2026-08-04T11:30:27Z", ref: "D16A" },
  { cod_art: "729E", deposito: "terminado", tipo: "inicial", delta: 5,  ts: "2026-08-01T16:02:00Z", ref: "conteo" },
  { cod_art: "729E", deposito: "terminado", tipo: "picking", delta: -5, ts: "2026-08-04T11:30:27Z", ref: "D16A" },
  { cod_art: "555",  deposito: "terminado", tipo: "inicial", delta: 4,  ts: "2026-08-01T16:02:00Z", ref: "conteo" },
  { cod_art: "555",  deposito: "terminado", tipo: "picking", delta: -10, ts: "2026-08-04T11:30:27Z", ref: "D16A" }
];

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async (fix) => {
    const out = {}, emitidos = [];
    window.stockEmitSinStock = function (tanda, legajo, negArr) { emitidos.push({ tanda: tanda, legajo: legajo, neg: negArr.slice() }); };
    window.stockGetCutoff = async function () { return null; };
    window.stockFetchMovs = async function () { return fix.MOVS.slice(); };
    window.fetch = function () { return Promise.resolve({ ok: true, json: function () { return Promise.resolve(fix.PKC.slice()); } }); };

    await stockBajaPicking("D16A", "104");
    out.emitidos = emitidos.length;
    out.neg = emitidos.length ? emitidos[0].neg.slice().sort() : [];

    // Control del bug: si NO se excluyera el picking de la tanda, 764 y 729E entrarían.
    out.no764 = !out.neg.some(function (s) { return s.indexOf("764:") === 0; });
    out.no729E = !out.neg.some(function (s) { return s.indexOf("729E:") === 0; });
    out.si555 = out.neg.indexOf("555:10>4") >= 0;
    out.soloUno = out.neg.length === 1;
    return out;
  }, { MOVS: MOVS, PKC: PKC });

  const pass = r.emitidos === 1 && r.no764 && r.no729E && r.si555 && r.soloUno && errs.length === 0;
  console.log("ssg-carrera-cron:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
