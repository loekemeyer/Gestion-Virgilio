/* Regresión v20.82 — el remito FACTURADO (el que se auto-imprime al tildar Facturación)
   tiene que traer CLIENTE y FECHA DE ENTREGA también cuando la NP es de la página.

   Es el mismo agujero de la v15.46, en el único camino que había quedado afuera:
   facPrintFacturado arma su propio `row` y resolvía la cabecera SOLO contra
   gv_ppp_programacion_diaria (espejo de ISIS), donde las NP web no existen. Caso real:
   NP LK 0145, tanda E35A, impresa el 21/09 14:51 con "Cliente —" y "Fecha Entrega —",
   estando el dato cargado (1802 · Tau Daniela Leonor · 22/09).

   Chequea, con fetch stubbeado (sin red):
   1) que facPrintFacturado consulte gv_ppp_web_estado,
   2) que el np_label vaya ENTRECOMILLADO (lleva un espacio: "LK 0145"),
   3) que la hoja impresa salga con código + razón social + fecha,
   4) que una NP de ISIS siga resolviéndose por el espejo, sin pisarse.
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
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = { urls: [], hojas: [] };
    function J(data){ return Promise.resolve({ ok: true, status: 200, json: function(){ return Promise.resolve(data); } }); }
    window.fetch = function (url) {
      url = String(url); out.urls.push(url);
      if (url.indexOf("opcion=eq.TAL") >= 0) {
        const np = /texto=like\.([^&*]+)/.exec(url);
        const label = np ? decodeURIComponent(np[1]).replace(/\|$/, "") : "";
        return J([{ texto: label + "|2|E35A|A=501X5;B=505X5|LIO", legajo: "46" }]);
      }
      if (url.indexOf("opcion=eq.TP") >= 0) return J([{ legajo: "46" }]);
      if (url.indexOf("gv_ppp_web_estado") >= 0) return J([
        { np_label: "LK 0145", cod_cliente: "1802", razon_social: "Tau Daniela Leonor", fecha_entrega: "2026-09-22", tanda: "E35A" }
      ]);
      if (url.indexOf("gv_ppp_programacion_diaria") >= 0) {
        return J(url.indexOf("98605") >= 0
          ? [{ np: "98605", cod: "4105", razon_social: "Riondini Federico", fecha_entrega: "2026-09-22", tanda: "E12E" }]
          : []);   // la NP web NO está en el espejo de ISIS: ése es el caso que se prueba
      }
      return J([]);
    };
    window.getEmpleadosNombres = async function(){ return new Map([["46", "Jhonny Cartaya"]]); };
    window.remitoPrintDoc = function (inner){ out.hojas.push(inner); };
    window.facShowToast = function (t){ out.toast = t; };

    await facPrintFacturado("LK 0145", "E35A");
    const web = out.hojas[0] || "";
    await facPrintFacturado("98605", "E12E");
    const isis = out.hojas[1] || "";

    out.pidioWebEstado   = out.urls.some(function(u){ return u.indexOf("gv_ppp_web_estado") >= 0; });
    out.npEntrecomillada = out.urls.some(function(u){ return u.indexOf("gv_ppp_web_estado") >= 0 && u.indexOf("%22LK%200145%22") >= 0; });
    out.webTieneCliente  = web.indexOf("1802 - Tau Daniela Leonor") >= 0;
    out.webSinGuion      = web.indexOf("<b>Cliente</b> —") < 0;
    out.webTieneFecha    = /Fecha Entrega<\/b>\s*22\/09\/2026/.test(web);
    out.webEsFacturado   = web.indexOf("FACTURADO") >= 0;
    out.isisTieneCliente = isis.indexOf("4105 - Riondini Federico") >= 0;
    return out;
  });

  const pass =
    r.pidioWebEstado && r.npEntrecomillada &&
    r.webTieneCliente && r.webSinGuion && r.webTieneFecha && r.webEsFacturado &&
    r.isisTieneCliente && errs.length === 0;
  const { urls, hojas, ...vis } = r;
  console.log("remito-fac-np-web:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
