/* v16.04 — el stock del módulo de importados sale del DEPÓSITO REAL.

   Antes, `stock_actual` salía de `Importados_Mov_Stock`: un libro propio (seed del
   Excel + un sync manual) del que sólo se descontaban las entregas, así que ajustes,
   facturado, racks y recepciones no le llegaban y el módulo se despegaba del stock de
   verdad. Ahora lee la vista `gv_importados_ordenes`, que saca el stock de
   `vista_saldos_stock` (la misma fuente que la pantalla de Stock).

   `v_importados_ordenes` NO se puede seguir usando acá: la lee Producción Virgilio y
   por eso quedó intacta. Si alguien devuelve el endpoint, este test se pone rojo.

   Chequea, sin red (se intercepta el fetch):
   - `ocgFetchImportados()` pega contra `gv_importados_ordenes`, no contra `v_importados_ordenes`;
   - el `select` pide `stock_cajas` (la columna nueva) además de `stock_total`;
   - el stock que llega de la vista es el que se muestra (no se recalcula en el front).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async function () {
    const urls = [];
    window.fetch = function (u) {
      const s = String(u); urls.push(s);
      let body = [];
      if (s.indexOf("importados_ordenes") >= 0) {
        body = [{ id: 1, cod_art: "598E", marca: "LK", proveedor: "Hugo Wong", descripcion: "Pelador Negro Dentado",
                  uni_x_caja: 12, fob_uni: 0.3, est_madre_eff: 1200, meses_objetivo: 10,
                  stock_actual: 21048, stock_cajas: 1754, stock_insumos: 0, stock_total: 21048,
                  pedido_curso: 0, principal: true, activo: true }];
      }
      // supaFetchAll pagina con Range y lee content-range: sin `headers` el fetch falsa
      // tira y supaFetchAllSafe devuelve [] en silencio.
      return Promise.resolve({
        ok: true, status: 200,
        headers: { get: function (h) { return String(h).toLowerCase() === "content-range" ? "0-" + Math.max(0, body.length - 1) + "/" + body.length : null; } },
        json: function () { return Promise.resolve(body); },
        text: function () { return Promise.resolve(JSON.stringify(body)); }
      });
    };
    const g = await ocgFetchImportados();
    const it = (g.items || []).filter(function (x) { return String(x.cod).toUpperCase() === "598E"; })[0] || null;
    const u = urls.filter(function (x) { return x.indexOf("importados_ordenes") >= 0; })[0] || "";
    return {
      vistaNueva: u.indexOf("/rest/v1/gv_importados_ordenes") >= 0,
      vistaVieja: u.indexOf("/rest/v1/v_importados_ordenes") >= 0,
      pideStockCajas: u.indexOf("stock_cajas") >= 0,
      pideStockTotal: u.indexOf("stock_total") >= 0,
      stockMostrado: it ? it.stockUni : null
    };
  });

  await b.close();
  const fallas = [];
  const ok = function (c, m) { console.log((c ? "  ok   " : "  FALLA") + " · " + m); if (!c) fallas.push(m); };
  ok(r.vistaNueva, "pega contra gv_importados_ordenes");
  ok(!r.vistaVieja, "NO pega contra v_importados_ordenes (es la que usa Producción)");
  ok(r.pideStockCajas, "el select pide stock_cajas");
  ok(r.pideStockTotal, "el select sigue pidiendo stock_total");
  ok(r.stockMostrado === 21048, "el stock de la vista es el que se muestra (21048, dio " + r.stockMostrado + ")");
  ok(errs.length === 0, "sin errores de página" + (errs.length ? ": " + errs[0] : ""));
  console.log("  detalle: " + JSON.stringify(r));
  if (fallas.length) { console.log("imp-stock-real: " + fallas.length + " FALLA(S)"); process.exit(1); }
  console.log("imp-stock-real: OK");
})();
