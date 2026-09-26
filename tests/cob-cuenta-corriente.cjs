/* v22.93 — 📒 Cuenta corriente en Deuda / Cobranzas (Thomas, 26/09: "que figuren todas las deudas… y a la derecha del
   importe facturado la explicación de qué pagó").
   (a) Cobranzas abre por defecto en "Cuenta corriente" y pide gv_cobranza_clientes;
   (b) la lista muestra deuda, vencida y lo que hay para reclamar, ordenada por deuda (mayor → menor);
   (c) el filtro "Pagaron mal" deja sólo los que tienen algo para reclamar;
   (d) tocar un cliente pide gv_cobranza_cliente(emp, cod) y dibuja, al lado de lo facturado, la explicación del pago.
   RPC interceptadas por fetch, sin red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 800 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {}; const calls = [];
    window.alert = function () {}; window.confirm = function () { return true; };
    window.__isSupervisor = true; window.requireSupervisor = function () { return true; };
    const clientes = [
      { empresa: "lk", cod_cliente: "862", cliente: "Muller", deuda: 8802249, vencida: 0, comprobantes_abiertos: 2, dias_mas_vieja: 3,
        ultimo_pago: "2026-09-29", ultimo_pago_monto: 11687939, pedidos_mal: 14, a_reclamar: 28873448, pedidos_tarde: 0, ret_cliente: 0, agente_retencion: false, ancla: "2026-09-25T20:24:14Z" },
      { empresa: "lk", cod_cliente: "288", cliente: "Torres Y Liva S.A Cif", deuda: 44999903, vencida: 13435258, comprobantes_abiertos: 11, dias_mas_vieja: 53,
        ultimo_pago: "2026-09-18", ultimo_pago_monto: 5693184.16, pedidos_mal: 22, a_reclamar: 38405798, pedidos_tarde: 0, ret_cliente: 0.021, agente_retencion: false, ancla: "2026-09-25T20:24:14Z" },
      { empresa: "chef", cod_cliente: "2686", cliente: "Dorinka S.R.L", deuda: 91811721, vencida: 0, comprobantes_abiertos: 19, dias_mas_vieja: 81,
        ultimo_pago: "2026-09-07", ultimo_pago_monto: 1000, pedidos_mal: 0, a_reclamar: 0, pedidos_tarde: 14, ret_cliente: 0, agente_retencion: true, ancla: "2026-09-25T12:15:35Z" }
    ];
    const detalle = [
      { fecha: "2026-09-25", comprobantes: "FCA 0004-00036023", facturado: 10603863.77, pendiente: 10603863.77, estado: "debe", explicacion: "Debe $10.603.864 · facturada hace 1 día · vence el 25/10." },
      { fecha: "2026-07-16", comprobantes: "35217+35218", facturado: 7764162.11, pendiente: null, estado: "mal", explicacion: "Recibo 14558 del 18/09/26: $5.693.184 = 75 % de la lista, menos 2,2 % de retención. Pagó a los 64 días: le correspondía 0 % y se tomó 25 % → reclamar $1.941.041." }
    ];
    window.fetch = async (url, opt) => {
      const u = String(url); const m = /\/rpc\/([a-z_]+)/.exec(u);
      const ok = (o) => ({ ok: true, status: 200, json: async () => o, text: async () => JSON.stringify(o), headers: { get: () => null } });
      if (m) {
        calls.push({ fn: m[1], body: JSON.parse((opt && opt.body) || "{}") });
        if (m[1] === "gv_cobranza_clientes") return ok(clientes);
        if (m[1] === "gv_cobranza_cliente") return ok(detalle);
        return ok([]);
      }
      return ok([]);
    };
    openCobros();
    await new Promise((res) => setTimeout(res, 400));
    out.tab = document.getElementById("ccTabla") ? "cc" : (document.getElementById("deudaTabla") ? "deuda" : "?");
    out.calls = calls.map((c) => c.fn);
    const filas = () => Array.from(document.querySelectorAll("#ccTabla > table > tbody > tr")).map((tr) => tr.textContent);
    out.orden = filas().map((t) => t.split(" ")[0]);
    out.resumen = (document.getElementById("ccResumen") || {}).textContent || "";
    // (c) filtro pagaron mal
    _ccState.filtro = "mal"; ccRender();
    out.mal = filas().length;
    // (d) abrir Torres y Liva
    _ccState.filtro = "deuda"; ccRender();
    ccAbrirCliente("lk", "288");
    await new Promise((res) => setTimeout(res, 300));
    const c = calls.find((x) => x.fn === "gv_cobranza_cliente");
    out.detBody = c ? c.body : null;
    const det = document.getElementById("ccDet_lk_288");
    out.detTxt = det ? det.textContent : "";
    return out;
  });
  await b.close();
  const fallas = [];
  if (errs.length) fallas.push("errores JS: " + errs.join(" | "));
  if (r.tab !== "cc") fallas.push("(a) Cobranzas no abre en Cuenta corriente: " + r.tab);
  if (r.calls.indexOf("gv_cobranza_clientes") < 0) fallas.push("(a) no pidió gv_cobranza_clientes");
  if (r.orden.join(",") !== "Dorinka,Torres,Muller") fallas.push("(b) no ordena por deuda mayor→menor: " + r.orden.join(","));
  if (!/reclamar/.test(r.resumen)) fallas.push("(b) el resumen no dice lo que hay para reclamar");
  if (r.mal !== 2) fallas.push("(c) filtro 'pagaron mal' debería dejar 2, dejó " + r.mal);
  if (!r.detBody || r.detBody.p_emp !== "lk" || r.detBody.p_cod !== "288") fallas.push("(d) no pidió el detalle del cliente: " + JSON.stringify(r.detBody));
  if (!/reclamar \$1\.941\.041/.test(r.detTxt) || !/10\.603\.864/.test(r.detTxt)) fallas.push("(d) el detalle no muestra la explicación del pago al lado de lo facturado");
  if (fallas.length) { console.error("FALLA cob-cuenta-corriente:\n  " + fallas.join("\n  ")); process.exit(1); }
  console.log("OK cob-cuenta-corriente: abre en Cuenta corriente, ordena por deuda, filtra los que pagaron mal y explica cada pago.");
})();
