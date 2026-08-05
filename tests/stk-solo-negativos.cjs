/* Regresión v7.48 — tilde "🔴 Negativos" en la solapa Stocks. Al activarlo, la tabla deja SÓLO
   los artículos con saldo negativo en algún depósito. Chequea:
   - Apagado: se ven el negativo (700, góndola -5) y el positivo (800, góndola +10); el botón
     muestra el contador (1) y el estado ☐.
   - Encendido: se ve 700 pero NO 800; el botón queda ☑.
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
    const movs = [
      { cod_art: "700", deposito: "terminado", delta: -5, tipo: "ajuste",  ts: "2026-08-01T10:00:00Z" }, // negativo
      { cod_art: "800", deposito: "terminado", delta: 10, tipo: "inicial", ts: "2026-08-01T10:00:00Z" }  // positivo
    ];
    _stk = { movs: movs, cutoff: 0, dem: {}, cap: [], fcs: {}, gConf: [], filtro: "", openArt: null, soloNeg: false };

    // ---- APAGADO: se ven los dos + botón con contador ----
    const off = stkBodyStocks();
    out.off_ve700 = off.indexOf('stk-cod">700') >= 0;
    out.off_ve800 = off.indexOf('stk-cod">800') >= 0;
    out.off_botonOff = off.indexOf("☐ 🔴 Negativos") >= 0;
    out.off_contador = off.indexOf("🔴 Negativos (1)") >= 0;

    // ---- ENCENDIDO: sólo el negativo ----
    _stk.soloNeg = true;
    const on = stkBodyStocks();
    out.on_ve700 = on.indexOf('stk-cod">700') >= 0;
    out.on_oculta800 = on.indexOf('stk-cod">800') < 0;
    out.on_botonOn = on.indexOf("☑ 🔴 Negativos") >= 0;
    return out;
  });
  const pass = r.off_ve700 && r.off_ve800 && r.off_botonOff && r.off_contador &&
    r.on_ve700 && r.on_oculta800 && r.on_botonOn && errs.length === 0;
  console.log("stk-solo-negativos:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close(); process.exit(pass ? 0 : 1);
})();
