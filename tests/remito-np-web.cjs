/* Regresión v15.46 — el REMITO DE ARMADO que se imprime tiene que traer el CLIENTE y la
   FECHA DE ENTREGA también cuando la NP es de la página ("CH 0005", "LK 0057").

   El agujero es siempre el mismo y ya apareció tres veces: la cabecera se resolvía sólo
   contra el espejo de ISIS (gv_ppp_programacion_diaria / PPP_Programacion_Diaria /
   Facturacion_NP), donde las NP web NO existen — viven en PPP_Web_Programacion y se leen
   por gv_ppp_web_estado (np_label). Lo taparon la v14.36 (Composición a líos) y la v15.42
   (Recepción Remitos + lista de la Cola de impresión); faltaba la HOJA IMPRESA, que es la
   que mira el operario. Caso real: NP CH 0005, tanda E12B, impresa el 11/09 con
   "Cliente —" y "Fecha Entrega —".

   Chequea, con fetch stubbeado (sin red):
   1) que _armadoRemitoDataForItems consulte gv_ppp_web_estado,
   2) que las NP vayan ENTRECOMILLADAS en el in() (llevan un espacio: "CH 0005"),
   3) que el remito de una NP web salga con código + razón social + fecha,
   4) que una NP de ISIS siga saliendo igual que antes (no se pisa nada).
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
    const out = { urls: [] };
    function J(data){ return Promise.resolve({ ok: true, status: 200, json: function(){ return Promise.resolve(data); } }); }
    window.fetch = function (url) {
      url = String(url); out.urls.push(url);
      if (url.indexOf("gv_ppp_web_estado") >= 0) return J([
        { np_label: "CH 0005", cod_cliente: "328", razon_social: "Fernandez Sonia Blanca Guadalu", fecha_entrega: "2026-09-11", tanda: "E12B" }
      ]);
      if (url.indexOf("gv_ppp_programacion_diaria") >= 0 || url.indexOf("PPP_Programacion") >= 0) return J([
        { np: "98532", cod: "3958", razon_social: "Betbeze Gimenez Nahuel", fecha_entrega: "2026-09-10", tanda: "E10A" }
      ]);
      return J([]);
    };
    window.getEmpleadosNombres = async function(){ return new Map([["46", "Jhonny Cartaya"], ["77", "Franco Ortiz"]]); };

    const items = [
      { np: "CH 0005", tanda: "E12B", resumen: "713x5|713x1,731x3,764x1|802x4|809E CHx4", armadorLeg: "77" },
      { np: "98532",   tanda: "E10A", resumen: "500x2",                                   armadorLeg: "77" }
    ];
    const ds = await _armadoRemitoDataForItems(items);
    const web = ds.find(function(d){ return d.np === "CH 0005"; }) || {};
    const isis = ds.find(function(d){ return d.np === "98532"; }) || {};

    out.pidioWebEstado = out.urls.some(function(u){ return u.indexOf("gv_ppp_web_estado") >= 0; });
    // el in() tiene que llevar las NP entre comillas (encodeURIComponent deja %22)
    out.npEntrecomillada = out.urls.some(function(u){ return u.indexOf("gv_ppp_web_estado") >= 0 && u.indexOf("%22CH%200005%22") >= 0; });
    out.webCod = web.cod || ""; out.webRs = web.rs || ""; out.webFecha = web.fecha || "";
    out.isisCod = isis.cod || ""; out.isisRs = isis.rs || "";
    // y que llegue impreso al HTML del remito
    const html = armadoRemitoInnerHtml(web);
    out.htmlTieneCliente = html.indexOf("328 - Fernandez Sonia Blanca Guadalu") >= 0;
    out.htmlSinGuionCliente = html.indexOf("<b>Cliente</b> —") < 0;
    out.htmlTieneFecha = /Fecha Entrega<\/b>\s*11\/09/.test(html);
    return out;
  });

  const pass =
    r.pidioWebEstado && r.npEntrecomillada &&
    r.webCod === "328" && r.webRs === "Fernandez Sonia Blanca Guadalu" && r.webFecha === "2026-09-11" &&
    r.isisCod === "3958" && r.isisRs === "Betbeze Gimenez Nahuel" &&
    r.htmlTieneCliente && r.htmlSinGuionCliente && r.htmlTieneFecha &&
    errs.length === 0;
  const { urls, ...vis } = r;
  console.log("remito-np-web:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
