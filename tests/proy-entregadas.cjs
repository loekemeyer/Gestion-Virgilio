/* Regresión del pop-up de PROYECCIÓN (Stocks → Proy. caj/mes).

   v15.52 — las cajas que el PROVEEDOR ENTREGÓ cada mes (gv_entregas_mensuales_cod:
   talleristas + prov AT) se muestran junto a lo facturado. Lo que NO puede pasar: que un mes
   anterior al arranque del registro (prov AT desde 06/2026, talleristas desde 12/2025) se
   muestre como 0 entregado — la RPC lo marca `cubierto=false` y no se cuenta.

   v18.21 — el dueño mandó sacar el bloque de barras por mes ("con el gráfico ya alcanza") y
   pidió que lo que quedara se viera mucho más grande. Entonces: lo entregado dejó de ser una
   columna y pasó a ser su ficha, y el desglose de un mes —que se abría tocando el número de
   la barra— ahora se abre tocando el mes EN EL GRÁFICO.

   ⚠ Este test estuvo en ROJO en main desde la v18.11 sin que nadie lo notara: esa versión
   cambió el orden de las columnas (pedido del dueño) y nadie lo actualizó. Se reescribió el
   15/09 contra lo que la pantalla hace hoy.

   Chequea, con fetch stubbeado (sin red):
   1) que pida gv_entregas_mensuales_cod con el código base,
   2) que el entregado esté en su ficha y sume SÓLO los meses cubiertos,
   3) que no queden rastros del bloque de barras (.proyv-row / .proyv-track),
   4) que el gráfico tenga una franja clicable por mes y que tocarla abra el desglose,
   5) que si la RPC de entregas no devuelve nada, la ficha de entregado NO aparezca.
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
    // 12 meses de ventas, oct-25 → sep-26; la ventana son los últimos 6 (abr → sep)
    const ventas = ["2025-10","2025-11","2025-12","2026-01","2026-02","2026-03","2026-04","2026-05","2026-06","2026-07","2026-08","2026-09"]
      .map(function (m, i) { return { mes: m, cajas: 300 + i * 10 }; });
    // entregas: el circuito arranca en junio → abr/may sin cobertura
    const entregas = ventas.map(function (v) {
      const cub = v.mes >= "2026-06";
      return { mes: v.mes, cajas: cub ? 500 : 0, cubierto: cub };
    });
    let conEntregas = true;
    window.fetch = function (url) {
      url = String(url); out.urls.push(url);
      if (url.indexOf("ventas_mensuales_cod") >= 0 && url.indexOf("clientes") < 0) return J(ventas);
      if (url.indexOf("gv_entregas_mensuales_cod") >= 0) return J(conEntregas ? entregas : []);
      if (url.indexOf("gv_ventas_clientes_mes_cod") >= 0) return J([{ cliente: "Osa", cajas: 120 }, { cliente: "Otros", cajas: 80 }]);
      if (url.indexOf("vista_historial_entregas") >= 0) {
        return J([{ fecha: "2026-07-04", cajas: 300, quien: "Carriero", remito: "R-9" },
                  { fecha: "2026-07-19", cajas: 200, quien: "Carriero", remito: "R-11" }]);
      }
      return J([]);
    };
    if (!document.getElementById("stkPopBody")) {
      const d = document.createElement("div"); d.id = "stkPopBody"; document.body.appendChild(d);
    }
    window._stkPopShell = function () {};

    await stkShowProyVentas(encodeURIComponent("321"), 367.2);
    let body = document.getElementById("stkPopBody");
    out.pidioEntregas = out.urls.some(function (u) { return u.indexOf("gv_entregas_mensuales_cod") >= 0; });

    const kpiTxt = function () {
      return Array.prototype.map.call(body.querySelectorAll(".proyv-kpi"), function (k) {
        return (k.querySelector("span") || {}).textContent + "=" + (k.querySelector("b") || {}).textContent;
      }).join("|");
    };
    const k = kpiTxt();
    out.fichaEntregado = /entregado 6m=2000/.test(k);      // 4 meses cubiertos × 500, los s/d no suman
    out.fichaProy = /proy\. caj\/mes=367\.2/.test(k);
    out.fichaFacturado = /facturado 6m=2310/.test(k);      // 360+370+380+390+400+410
    out.fichaArriba = /meses arriba=5\/6/.test(k);
    // el bloque de barras ya no existe
    out.sinBarras = !body.querySelector(".proyv-row") && !body.querySelector(".proyv-track") && !body.querySelector(".proyv-foot");
    // el gráfico: una franja clicable por mes (12)
    out.hits = body.querySelectorAll(".proyv-svg .hit").length;

    // tocar un mes abre el desglose, con las dos caras
    await stkProyMes("2026-07");
    body = document.getElementById("stkPopBody");
    const det = body.querySelector(".proyv-det");
    out.abrioDet = !!det;
    const dt = det ? det.textContent : "";
    out.detTieneCliente = dt.indexOf("Osa") >= 0 && dt.indexOf("Otros") >= 0;
    out.detTieneRemito = dt.indexOf("R-9") >= 0 && dt.indexOf("Carriero") >= 0;
    out.detMarcado = body.querySelectorAll(".proyv-svg .hit.on").length === 1;
    // volver a tocarlo lo cierra
    await stkProyMes("2026-07");
    out.cierraDet = !document.getElementById("stkPopBody").querySelector(".proyv-det");

    // sin entregas registradas → la ficha de entregado no aparece
    conEntregas = false;
    await stkShowProyVentas(encodeURIComponent("999"), 100);
    body = document.getElementById("stkPopBody");
    out.sinFichaEnt = kpiTxt().indexOf("entregado") < 0;
    return out;
  });

  const pass =
    r.pidioEntregas && r.fichaEntregado && r.fichaProy && r.fichaFacturado && r.fichaArriba &&
    r.sinBarras && r.hits === 12 &&
    r.abrioDet && r.detTieneCliente && r.detTieneRemito && r.detMarcado && r.cierraDet &&
    r.sinFichaEnt &&
    errs.length === 0;
  const { urls, ...vis } = r;
  console.log("proy-entregadas:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
