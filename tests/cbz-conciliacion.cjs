/* v24.32 — pestaña 🏦 Conciliación del submódulo Cobranzas (Luis, 29/09).
   Hoy la conciliación se hace a mano en cuatro Excel; la pestaña es el tablero de eso:
   cuánto de cada extracto quedó identificado con cliente, qué entradas quedaron sin
   identificar (las que el motor de reglas va a tener que resolver) y qué falta definir.

   Mide, corriendo la pantalla de verdad:
     (a) la pestaña existe, abre y pide gv_conc_salud + gv_conc_sin_identificar;
     (b) una tarjeta por banco+empresa, con el % de entradas identificadas bien calculado;
     (c) el banco flojo se ve como flojo (Credicoop Chef: 12 de 606 = 2 %);
     (d) las entradas sin identificar salen con el TEXTO del extracto, que es de donde
         van a salir las reglas;
     (e) queda escrito en pantalla qué falta definir para que concilie solo.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.requireSupervisor = function () { return true; };

    const salud = [
      { banco: "credicoop", empresa: "lk", movimientos: 26619, entradas: 13845, con_cliente: 12689,
        con_recibo: 10506, sin_identificar: 1110, monto_sin_identificar: 1031493020,
        primera: "2021-01-07", ultima: "2026-09-28", archivo: "CONCILIACION CREDICOOP LOEKE.xls" },
      { banco: "credicoop", empresa: "chef", movimientos: 4444, entradas: 606, con_cliente: 12,
        con_recibo: 16, sin_identificar: 589, monto_sin_identificar: 1022438804,
        primera: "2012-03-01", ultima: "2026-09-28", archivo: "BANCO CREDICOOP CHEF.xlsm" },
      { banco: "santander", empresa: "chef", movimientos: 3850, entradas: 1085, con_cliente: 1020,
        con_recibo: 1021, sin_identificar: 62, monto_sin_identificar: 315800781,
        primera: "2023-02-01", ultima: "2026-11-21", archivo: "Bco Santander Rio Chef.xlsm" }
    ];
    const sin = [
      { banco: "credicoop", empresa: "lk", fecha: "2026-09-26", entrada: 1250000,
        detalle: "TRANSFERENCIA RECIBIDA 30712345678 BAZAR MONICA", operacion: "TR", nro_op: "88213", tipo: null, observacion: null },
      { banco: "santander", empresa: "chef", fecha: "2026-09-24", entrada: 840000,
        detalle: "DEPOSITO EN EFECTIVO SUCURSAL 044", operacion: "DEP", nro_op: null, tipo: null, observacion: null }
    ];

    const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
    window.fetch = async (url, opt) => {
      const u = String(url), m = /\/rpc\/([a-z_]+)/.exec(u);
      if (m) {
        calls.push(m[1]);
        if (m[1] === "gv_conc_salud") return ok(salud);
        if (m[1] === "gv_conc_sin_identificar") return ok(sin);
        return ok([]);
      }
      return ok([]);
    };

    await openCobranzas("conc");
    await espera(450);

    out.pestanas = Array.from(document.querySelectorAll("#cbzTabs .cbz-tab")).map((x) => x.textContent.trim());
    out.tabActiva = (document.querySelector("#cbzTabs .cbz-tab.on") || {}).textContent || "";
    out.pidio = calls.slice();

    const cards = Array.from(document.querySelectorAll(".cbz-conccard"));
    out.nCards = cards.length;
    out.cards = cards.map((c) => ({
      t: (c.querySelector(".t") || {}).textContent || "",
      p: ((c.querySelector(".p") || {}).textContent || "").trim()
    }));
    out.texto = (document.getElementById("cbzWrap") || {}).textContent || "";
    out.filasSin = document.querySelectorAll(".cbz-panel table.cbz-t tbody tr").length;
    return out;
  });

  await b.close();

  const fallas = [];
  const q = (c, m) => { if (!c) fallas.push(m); };

  q((r.pestanas || []).some((t) => /Conciliaci/.test(t)), "(a) no está la pestaña Conciliación: " + JSON.stringify(r.pestanas));
  q(/Conciliaci/.test(r.tabActiva || ""), "(a) openCobranzas('conc') no abrió en Conciliación (abrió en " + r.tabActiva + ")");
  q((r.pidio || []).indexOf("gv_conc_salud") >= 0, "(a) no pidió gv_conc_salud");
  q((r.pidio || []).indexOf("gv_conc_sin_identificar") >= 0, "(a) no pidió gv_conc_sin_identificar");

  q(r.nCards === 3, "(b) esperaba una tarjeta por banco+empresa (3), hay " + r.nCards);
  const lk = (r.cards || []).filter((c) => /CREDICOOP/.test(c.t) && /LK/.test(c.t))[0];
  const ch = (r.cards || []).filter((c) => /CREDICOOP/.test(c.t) && /CH/.test(c.t))[0];
  q(lk && /92 %/.test(lk.p), "(b) Credicoop LK: 12.689 de 13.845 es 92 %, dice " + JSON.stringify(lk && lk.p));
  q(ch && /^2 %/.test((ch.p || "").trim()), "(c) Credicoop Chef: 12 de 606 es 2 %, dice " + JSON.stringify(ch && ch.p));

  q(/BAZAR MONICA/.test(r.texto || ""), "(d) no muestra el texto del extracto de la entrada sin identificar");
  q(r.filasSin === 2, "(d) esperaba las 2 entradas sin identificar, hay " + r.filasSin);
  q(/1\.250\.000/.test(r.texto || ""), "(d) no muestra el importe de la entrada sin identificar");

  q(/manual/i.test(r.texto || "") && /e-cheque/i.test(r.texto || ""),
    "(e) no queda escrito qué falta definir para que concilie solo");

  if (errs.length) fallas.push("errores de JS en la página: " + errs.join(" | "));

  if (fallas.length) {
    console.log("cbz-conciliacion: FALLA");
    fallas.forEach((f) => console.log("  - " + f));
    process.exit(1);
  }
  console.log("cbz-conciliacion: OK — pestaña propia, una tarjeta por banco+empresa con el % identificado " +
    "(Credicoop LK 92 %, Credicoop Chef 2 %), las entradas sin identificar con el texto del extracto, " +
    "y lo que falta definir escrito en pantalla.");
  process.exit(0);
})();
