/* Regresión idea 4259 (v14.81) — REEMPLAZO del aviso viejo RAG.
   Antes (idea 5703): al cerrar el picking (TP), si faltó algo con stock en racks o
   a_guardar, stockBajaPicking abría un pop-up informativo (RAG) y mandaba Telegram.
   Ahora ese aviso se REEMPLAZÓ por el paso de completar-desde-"a guardar" integrado
   en el cierre del picking (pkPrepAGuardar / pkAGuardarCardHtml / evento PKA), que
   además DESCUENTA de a_guardar. Racks queda fuera del flujo (pedido del dueño).
   Este test verifica:
     (A) stockBajaPicking YA NO abre el pop-up RAG ni emite el evento RAG (y sigue sin SSG falso).
     (B) pkFetchAGuardar lee el saldo de a_guardar por art (solo > 0), ignorando otros depósitos.
     (C) las funciones del flujo nuevo existen.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const PKC = [
  { texto: "T1|100|10|7" },   // faltó 3 ; hay 5 en racks (antes HIT, ahora NO dispara RAG)
  { texto: "T1|400|8|5"  },   // faltó 3 ; hay 10 en a guardar (antes HIT, ahora NO dispara RAG)
  { texto: "T1|300|4|4"  }    // completo
];
const MOVS = [
  { cod_art: "100", deposito: "terminado", tipo: "inicial", delta: 7,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "100", deposito: "racks",     tipo: "inicial", delta: 5,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "300", deposito: "terminado", tipo: "inicial", delta: 4,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "400", deposito: "terminado", tipo: "inicial", delta: 5,  ts: "2026-08-01T12:00:00Z" },
  { cod_art: "400", deposito: "a_guardar", tipo: "inicial", delta: 10, ts: "2026-08-01T12:00:00Z" }
];

(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async (fix) => {
    const out = {};
    // ---- (A) el aviso viejo RAG ya no se dispara en el TP ----
    let ragEmit = 0, popupCalls = 0, ssgCalls = 0;
    window.stockEmitRacksAguardar = function () { ragEmit++; };
    window.showRacksAguardarPopup = function () { popupCalls++; };
    window.stockEmitSinStock = function () { ssgCalls++; };
    window.stockGetCutoff = async function () { return null; };
    window.stockFetchMovs = async function () { return fix.MOVS.slice(); };
    window.fetch = function () { return Promise.resolve({ ok: true, json: function () { return Promise.resolve(fix.PKC.slice()); } }); };
    await stockBajaPicking("T1", "104");
    out.ragEmit = ragEmit;      // debe ser 0 (reemplazado)
    out.popup = popupCalls;     // debe ser 0 (reemplazado)
    out.ssg = ssgCalls;         // debe ser 0 (no se pickeó de más)

    // ---- (B) pkFetchAGuardar: saldo de a_guardar por art, solo > 0 ----
    window.fetch = function (url) {
      // devuelve filas de a_guardar (el resto de depósitos NO debería pedirse)
      const rows = [
        { cod_art: "400", delta: 10, ubicacion: "P7" },
        { cod_art: "100", delta: 0,  ubicacion: null },   // 100 no tiene a_guardar → no debe salir
        { cod_art: "900", delta: 3,  ubicacion: "P2" }
      ];
      return Promise.resolve({ ok: true, json: function () { return Promise.resolve(rows); } });
    };
    const ag = await pkFetchAGuardar(["400", "100", "900"]);
    out.ag400 = ag["400"] ? ag["400"].cajas : null;   // 10
    out.ag900 = ag["900"] ? ag["900"].cajas : null;   // 3
    out.ag100 = ("100" in ag);                        // false (saldo 0)
    out.ag400ubic = ag["400"] ? ag["400"].ubics.join("") : "";

    // ---- (C) las funciones del flujo nuevo existen ----
    out.fns = ["pkFetchAGuardar", "pkPrepAGuardar", "pkAGuardarCardHtml", "pkAGuardarConfirm", "pkAGuardarSkip", "pkEmitAGuardar"]
      .every(function (n) { return typeof window[n] === "function"; });
    // la tarjeta con _pk nulo no rompe (devuelve string)
    out.cardSafe = (typeof pkAGuardarCardHtml() === "string");
    return out;
  }, { PKC: PKC, MOVS: MOVS });

  const pass = r.ragEmit === 0 && r.popup === 0 && r.ssg === 0 &&
    r.ag400 === 10 && r.ag900 === 3 && r.ag100 === false && r.ag400ubic === "P7" &&
    r.fns === true && r.cardSafe === true && errs.length === 0;
  console.log("pk-racks-aguardar (reemplazo 4259):", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
