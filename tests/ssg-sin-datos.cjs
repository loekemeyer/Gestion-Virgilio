/* Regresión v7.58 — el SSG "picking sin stock en góndola" NO dispara si no se pudo LEER el stock.
   stockFetchMovs() usa supaFetchAll, que TIRA si falla cualquier página del paginado. Cuando eso
   pasa (celular del operario + tabla Movimientos_Stock enorme), sal quedaba {} y TODOS los códigos
   pickeados daban "tenía 0" → aviso masivo falso (caso real D06A, leg 122: 28 códigos con la
   góndola llena). Ahora: si el fetch falla o vuelve vacío, no se dispara el SSG.

   Chequea:
   - fetch de movs FALLA  → no emite SSG.
   - fetch de movs VACÍO  → no emite SSG.
   - movs OK con FALTANTE real (504: 5 en góndola, pickeó 100) → SÍ emite SSG (504:100>5).
   - movs OK con stock suficiente (504: 200, pickeó 100) → no emite SSG.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    function J(data) { return Promise.resolve({ ok: true, status: 200, headers: { get: function () { return null; } }, json: function () { return Promise.resolve(data); } }); }
    // El fetch de PKC de la tanda D06A: dos códigos, cada uno pickeó 100.
    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("opcion=eq.PKC") >= 0) return J([{ texto: "D06A|504|100|100" }, { texto: "D06A|505|100|100" }]);
      return J([]);
    };
    window.stockGetCutoff = async function () { return 0; };
    window.stockEmitRacksAguardar = function () {};
    window.showRacksAguardarPopup = function () {};
    let emitted = null; window.stockEmitSinStock = function (t, leg, neg) { emitted = { t: t, neg: neg.slice() }; };

    // --- CASO A: fetch de movs FALLA → no SSG ---
    window.stockFetchMovs = async function () { throw new Error("boom paginado"); };
    emitted = null; await stockBajaPicking("D06A", "122");
    out.falla_noSSG = emitted === null;

    // --- CASO B: fetch de movs VACÍO → no SSG ---
    window.stockFetchMovs = async function () { return []; };
    emitted = null; await stockBajaPicking("D06A", "122");
    out.vacio_noSSG = emitted === null;

    // --- CASO C: movs OK, FALTANTE real (504 con 5 en góndola, pickeó 100) → SÍ SSG ---
    window.stockFetchMovs = async function () {
      return [
        { cod_art: "504", deposito: "terminado", delta: 5,   tipo: "inicial", ts: "2026-08-01T10:00:00Z" },
        { cod_art: "505", deposito: "terminado", delta: 500, tipo: "inicial", ts: "2026-08-01T10:00:00Z" }
      ];
    };
    emitted = null; await stockBajaPicking("D06A", "122");
    out.faltante_SSG = !!emitted && emitted.neg.some(function (x) { return x.indexOf("504:100>5") >= 0; });
    out.faltante_no505 = !!emitted && !emitted.neg.some(function (x) { return x.indexOf("505") >= 0; });   // 505 tenía 500 ≥ 100

    // --- CASO D: movs OK, stock suficiente → no SSG ---
    window.stockFetchMovs = async function () {
      return [
        { cod_art: "504", deposito: "terminado", delta: 200, tipo: "inicial", ts: "2026-08-01T10:00:00Z" },
        { cod_art: "505", deposito: "terminado", delta: 200, tipo: "inicial", ts: "2026-08-01T10:00:00Z" }
      ];
    };
    emitted = null; await stockBajaPicking("D06A", "122");
    out.suficiente_noSSG = emitted === null;
    return out;
  });
  const pass = r.falla_noSSG && r.vacio_noSSG && r.faltante_SSG && r.faltante_no505 && r.suficiente_noSSG && errs.length === 0;
  console.log("ssg-sin-datos:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
