/* Regresión (v12.87): una NP web CONTROLADA cuenta como ENTREGADA, y sigue contando
   aunque pase el tiempo.

   Regla del dueño: "si el pedido ya fue controlado, automáticamente tendría que ir a
   Pedidos Entregados". Para las NP de ISIS eso ya pasa: CRN (60 días) ∪ hoja de
   entregados (durable). Para las web la hoja nunca las va a tener (se trunca con el
   Sheet de ISIS cada 30 min), así que la fuente durable es la vista
   gv_ppp_web_entregados (los CRN con etiqueta, cruzados con PPP_Web_Programacion).

   Verifica que:
   (a) pppRefreshMetaEntSet sume las NP web de la vista al set de confirmadas,
       sin perder las de la hoja de ISIS,
   (b) _pppSplitDelivered ponga la NP web en ENTREGADOS y deje EN VIAJE a la que no
       tiene confirmación,
   (c) el "histórico completo" (pppRefreshEntregadosFull) incluya la fila web con
       cliente, tanda, m³ y fecha, con la misma forma que las de ISIS,
   (d) si la vista falla, lo de ISIS quede exactamente igual (aditivo). */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    let webFalla = false;
    window.pppRenderProg = function () {};
    function J(data, ok) {
      const n = Array.isArray(data) ? data.length : 0;
      return Promise.resolve({
        ok: ok !== false, status: ok === false ? 500 : 200,
        headers: { get: function (h) { return String(h).toLowerCase() === "content-range" ? ("0-" + Math.max(0, n - 1) + "/" + n) : null; } },
        json: function () { return Promise.resolve(data); },
        text: function () { return Promise.resolve(JSON.stringify(data)); }
      });
    }
    window.fetch = function (url) {
      url = String(url);
      if (url.indexOf("gv_ppp_web_entregados") >= 0) {
        if (webFalla) return J([], false);
        return J([{ np_label: "LK 01344", cod_cliente: "4188", razon_social: "Orfali", tanda: "GV-02A", m3: 1.184, fecha_entrega: "2026-09-11" }]);
      }
      if (url.indexOf("ppp_entregados_meta") >= 0) return J([
        { np: "98574", cod: "2533", rs: "Osa Distribuidora", tanda: "C03B", m3: 0.5, fecha_entrega: "2026-09-10" }
      ]);
      if (url.indexOf("vista_ppp_pedidos_entregados") >= 0) return J([
        { np: "98574",    tanda: "C03B",   cod_cliente: "2533", razon_social: "Osa Distribuidora", m3: 0.5,   fecha_salida: "2026-09-10", facturado_at: "2026-09-10T12:00:00Z", cajas_pedidas: 5, cajas_entregadas: 5, cajas_falto: 0 },
        { np: "LK 01344", tanda: "GV-02A", cod_cliente: "4188", razon_social: "Orfali",            m3: 1.184, fecha_salida: "2026-09-11", facturado_at: "2026-09-11T12:00:00Z", cajas_pedidas: 1, cajas_entregadas: 1, cajas_falto: 0 },
        { np: "98575",    tanda: "C03B",   cod_cliente: "2540", razon_social: "Otro",              m3: 0.3,   fecha_salida: "2026-09-10", facturado_at: "2026-09-10T12:00:00Z", cajas_pedidas: 2, cajas_entregadas: 2, cajas_falto: 0 }
      ]);
      return J([]);
    };

    // (a) el set de confirmadas
    await pppRefreshMetaEntSet();
    out.confIsis = _pppMetaEntSet.has("98574");
    out.confWeb  = _pppMetaEntSet.has("LK 01344");
    out.confNo   = !_pppMetaEntSet.has("98575");

    // (b) entregados vs en viaje
    await pppRefreshDelivered();
    const sp = _pppSplitDelivered();
    out.entregados = sp.entregados.map(x => x.np).sort().join(",");
    out.enViaje    = sp.enViaje.map(x => x.np).sort().join(",");

    // (c) el histórico completo
    await pppRefreshEntregadosFull();
    const w = (_pppDeliveredFull || []).find(x => x.np === "LK 01344");
    out.histWeb  = w ? { cod: w.cod, rs: w.rs, tanda: w.tanda, m3: w.m3, frep: w.frep, fkey: w.fkey } : null;
    out.histIsis = !!(_pppDeliveredFull || []).find(x => x.np === "98574");

    // (d) si la vista falla, ISIS sigue igual
    webFalla = true;
    await pppRefreshMetaEntSet();
    out.fallaIsisSigue = _pppMetaEntSet.has("98574");
    out.fallaWebFuera  = !_pppMetaEntSet.has("LK 01344");
    await pppRefreshEntregadosFull();
    out.fallaHistIsis  = !!(_pppDeliveredFull || []).find(x => x.np === "98574");
    out.fallaHistWeb   = !(_pppDeliveredFull || []).find(x => x.np === "LK 01344");
    return out;
  });

  const checks = [
    ["confirmadas: la NP de ISIS sigue viniendo de la hoja",    r.confIsis === true],
    ["confirmadas: la NP web viene de gv_ppp_web_entregados",   r.confWeb === true],
    ["confirmadas: la que no se controló no está",              r.confNo === true],
    ["entregados = ISIS confirmada + web controlada",           r.entregados === "98574,LK 01344"],
    ["en viaje = la que nadie confirmó",                        r.enViaje === "98575"],
    ["histórico: la fila web trae cliente",                     r.histWeb && r.histWeb.cod === "4188" && r.histWeb.rs === "Orfali"],
    ["histórico: tanda, m³ y fecha con la misma forma",         r.histWeb && r.histWeb.tanda === "GV-02A" && r.histWeb.m3 === 1.184 && r.histWeb.frep === "2026-09-11" && r.histWeb.fkey === "20260911"],
    ["histórico: la de ISIS sigue",                             r.histIsis === true],
    ["si la vista falla, la hoja de ISIS sigue en confirmadas", r.fallaIsisSigue === true],
    ["si la vista falla, la web simplemente no está",           r.fallaWebFuera === true],
    ["si la vista falla, el histórico de ISIS sigue",           r.fallaHistIsis === true],
    ["si la vista falla, el histórico no trae la web",          r.fallaHistWeb === true],
    ["sin errores de página",                                   errs.length === 0]
  ];

  let bad = 0;
  for (const [name, ok] of checks) { console.log((ok ? "  ok   " : "  FALLA") + " · " + name); if (!ok) bad++; }
  if (bad) console.log("  detalle:", JSON.stringify(r));
  if (errs.length) console.log("  pageerror: " + errs.join(" | "));
  console.log(bad ? "pweb-entregados: " + bad + " FALLA(S)" : "pweb-entregados: OK (" + checks.length + " chequeos)");
  await b.close();
  process.exit(bad ? 1 : 0);
})();
