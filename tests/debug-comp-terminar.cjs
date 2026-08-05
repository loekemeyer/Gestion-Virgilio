const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  
  await p.evaluate(async () => {
    console.log("desc defined:", typeof desc !== 'undefined');
    console.log("_comp structure check...");
    
    window._comp = {
      legajo: "8",
      tanda: "D06B",
      fecha: "2026-08-05",
      hayFalt: false,
      clasifDone: true,
      nps: [
        {
          np: "98151",
          clase: "lios",
          liosArr: [{ lios: 2, art: "035E" }],
          liosDone: true,
          codes: { "035E": 1 }
        }
      ],
      pedidoFull: [
        {
          np: "98151",
          cod: "CLI01",
          items: [
            { art: "035E", cajas: 10 }
          ]
        }
      ],
      arts: [],
      _liosDirty: false
    };

    let called = [];
    window._compSaveEntregas = function (rows) { called.push("_compSaveEntregas"); console.log("_compSaveEntregas called with", rows.length, "rows"); };
    window._compClearPersist = function () { called.push("_compClearPersist"); };
    window.getLegajoState = function (l) { called.push("getLegajoState"); return { armado: { active: true, value: "D06B", ts_inicio: "2026-08-05T11:00:00Z" }, picking: { active: false }, toggles: {} }; };
    window.setLegajoState = function () { called.push("setLegajoState"); };
    window.pushHistoryForLegajo = function () { called.push("pushHistoryForLegajo"); };
    window.enqueueReport = function (pl) { called.push("enqueueReport: " + pl.opcion); };
    window.tandaLiberar = function () { called.push("tandaLiberar"); };
    window.trySendOneReport = async function () { called.push("trySendOneReport"); return { ok: true, created_at: "x" }; };
    window.removeFromQueue = function () { called.push("removeFromQueue"); };
    window.stockSepararAFacturar = async function (t, l) { called.push("stockSepararAFacturar"); };
    window.updatePendingIndicator = function () { called.push("updatePendingIndicator"); };

    try {
      await compTerminar();
      console.log("compTerminar completed. Called:", called);
    } catch (e) {
      console.log("compTerminar ERROR:", e.message);
      console.log("Called before error:", called);
    }
  });

  await b.close();
})();
