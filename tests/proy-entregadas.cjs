/* Regresión v15.52 — en el popup de PROYECCIÓN (Stocks → Proy. caj/mes), cada fila de la
   ventana de 6 meses muestra, A LA DERECHA DEL MES y ANTES de la barra, las cajas que el
   PROVEEDOR ENTREGÓ ese mes (gv_entregas_mensuales_cod: talleristas + prov AT). Al final de
   la fila sigue lo FACTURADO, como siempre.

   Pedido del dueño (11/09/2026), mirando el 321 (Rallador cilíndrico, Carriero): "a la
   derecha del mes, poné las cajas entregadas, y después el gráfico de barra".

   Lo que NO puede pasar: que un mes anterior al arranque del registro (Prov AT recién se
   carga desde 06/2026; talleristas desde 12/2025) se muestre como 0 entregado. La RPC lo
   marca con cubierto=false y el front lo pinta "s/d".

   Chequea, con fetch stubbeado (sin red):
   1) que pida gv_entregas_mensuales_cod con el código base,
   2) orden de la fila: mes → entregadas → barra → facturadas,
   3) mes cubierto → número; mes no cubierto → "s/d" (nunca "0"),
   4) el pie suma sólo lo cubierto,
   5) si la RPC no devuelve nada, la columna NO aparece (no dejamos una columna vacía).
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
      if (url.indexOf("ventas_mensuales_cod") >= 0) return J(ventas);
      if (url.indexOf("gv_entregas_mensuales_cod") >= 0) return J(conEntregas ? entregas : []);
      return J([]);
    };
    if (!document.getElementById("stkPopBody")) {
      const d = document.createElement("div"); d.id = "stkPopBody"; document.body.appendChild(d);
    }
    window._stkPopShell = function () {};

    await stkShowProyVentas(encodeURIComponent("321"), 367.2);
    let body = document.getElementById("stkPopBody");
    out.pidioEntregas = out.urls.some(function (u) { return u.indexOf("gv_entregas_mensuales_cod") >= 0; });
    const rows = Array.prototype.slice.call(body.querySelectorAll(".proyv-row:not(.proyv-head)"));
    out.filas = rows.length;
    // orden de las celdas de una fila cubierta (la última, sep-26)
    const ult = rows[rows.length - 1];
    out.orden = ult ? Array.prototype.map.call(ult.children, function (c) { return c.className.split(" ")[0]; }).join(">") : "";
    out.entSep = ult ? (ult.querySelector(".proyv-ent") || {}).textContent : "";
    out.facSep = ult ? (ult.querySelector(".proyv-val") || {}).textContent : "";
    // abr-26 (primera fila de la ventana) NO está cubierta → "s/d", no "0"
    const prim = rows[0];
    out.entAbr = prim ? (prim.querySelector(".proyv-ent") || {}).textContent : "";
    out.abrEsSd = prim ? !!prim.querySelector(".proyv-ent.sd") : false;
    out.cabecera = !!body.querySelector(".proyv-head");
    const foot = (body.querySelector(".proyv-foot") || {}).textContent || "";
    out.pieEntregado = /Entregado:\s*2000/.test(foot);   // 4 meses cubiertos × 500
    out.titulo = (body.textContent.indexOf("Entregado y facturado") >= 0);

    // sin entregas registradas → la columna no existe
    conEntregas = false;
    await stkShowProyVentas(encodeURIComponent("999"), 100);
    body = document.getElementById("stkPopBody");
    out.sinColumna = !body.querySelector(".proyv-ent") && !body.querySelector(".proyv-head");
    out.tituloViejo = (body.textContent.indexOf("Cajas facturadas") >= 0);
    return out;
  });

  const pass =
    r.pidioEntregas && r.filas === 6 &&
    r.orden === "proyv-mes>proyv-ent>proyv-track>proyv-val" &&
    r.entSep === "500" && r.facSep === "410" &&
    r.entAbr === "s/d" && r.abrEsSd &&
    r.cabecera && r.pieEntregado && r.titulo &&
    r.sinColumna && r.tituloViejo &&
    errs.length === 0;
  const { urls, ...vis } = r;
  console.log("proy-entregadas:", JSON.stringify(vis), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
