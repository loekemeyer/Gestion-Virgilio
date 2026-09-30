/* v24.72 — Cobranzas → 📐 Escala muestra la lista de CORONITAS (Luis, 30/09).
   "Tener coronita" (Thomas) = trato preferencial de plazo: cobra el descuento de contado hasta su
   plazo propio. Vive en cobranzas_excepciones. Mide, corriendo la pantalla:
     (a) la pestaña Escala lee cobranzas_excepciones y dibuja una fila por cliente;
     (b) el nombre sale del motivo y el plazo mayor va primero;
     (c) el buscador filtra. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext({ viewport: { width: 1400, height: 900 }, serviceWorkers: "block" })).newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const espera = (ms) => new Promise((res) => setTimeout(res, ms));
    for (let i = 0; i < 50 && typeof window.openCobranzas !== "function"; i++) await espera(100);
    window.requireSupervisor = () => true;
    const filas = [
      { id: 1, deudor_id: "30111111111", cod_cliente: "LK 2266", escalon: "contado", dias: 20, dto: 0.25, vigente_desde: "2025-01-01", motivo: "Coronita planilla 28/09: Bazar 33 Srl · 20 días" },
      { id: 3, deudor_id: "33534724239", cod_cliente: "LK 288 / CH 271", escalon: "contado", dias: 60, dto: 0.25, vigente_desde: "2019-07-10", motivo: "Coronita: contado a 30 días (Torres y Liva) → 60 por planilla 28/09" },
      { id: 23, deudor_id: "30715444255", cod_cliente: "LK 4149", escalon: "contado", dias: 60, dto: 0.25, vigente_desde: "2025-01-01", motivo: "Coronita planilla 28/09: Muelle1 Comex S.R.L. · 30/60 días" }
    ];
    let falla = false, tabla = null;
    const q = (t) => { const o = { select() { return o; }, order() { return o; }, limit() { return o; },
      then(res) { tabla = t; res(t === "cobranzas_excepciones" ? (falla ? { error: { message: "boom" } } : { data: filas }) : { data: [] }); } }; return o; };
    window.sb = { from: q, rpc: async () => ({ data: [] }) };
    const out = {};
    window.openCobranzas("escalones"); window.cbzSetTab("escalones");
    await espera(300);
    const body = document.getElementById("cbzCorBody");
    out.filas = body ? body.querySelectorAll("tr").length : 0;
    out.primera = body ? body.querySelector("tr td").textContent : "";
    out.nombres = body ? [...body.querySelectorAll("tr td:first-child")].map((t) => t.textContent) : [];
    out.titulo = /Coronitas · 3 clientes/.test(document.getElementById("cbzWrap").textContent);
    window.cbzCoronitasFiltrar("bazar");
    out.filtradas = document.getElementById("cbzCorBody").querySelectorAll("tr").length;
    return out;
  });
  const fails = [];
  if (r.filas !== 3) fails.push("(a) filas " + r.filas);
  if (!r.titulo) fails.push("(a) título");
  if (!/Muelle1 Comex/.test(r.nombres.join("|")) || !/Torres y Liva/.test(r.nombres.join("|"))) fails.push("(b) nombres " + r.nombres);
  if (!/Muelle1|Torres/.test(r.primera)) fails.push("(b) orden: primera " + r.primera);
  if (r.filtradas !== 1) fails.push("(c) filtro " + r.filtradas);
  if (errs.length) fails.push("errores: " + errs.join(" | "));
  await b.close();
  if (fails.length) { console.error("FALLA cbz-coronitas:\n  " + fails.join("\n  ")); process.exit(1); }
  console.log("OK cbz-coronitas");
})();
