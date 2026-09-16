/* v18.77 (Luis, 2026-09-16) — Badge "Cliente nuevo" en Facturación.
   Regresión de lo que se rompió una vez y no se vio: la lógica existía (GV_Clientes_Nuevos, v17.12)
   pero la tabla tenía RLS sin policy de lectura, así que con la anon key devolvía 0 filas y el badge
   NUNCA aparecía en Facturación. Acá se prueba el front con fetch stubbeado:
     (a) un cliente que está en la tabla lleva el badge, con el número de pedidos en el title;
     (b) uno que NO está, no lo lleva;
     (c) el mismo código en la OTRA empresa no lo lleva (la clave es empresa+cod: LK 4185 ≠ CH 4185,
         y la empresa sale de la NP — prefijo LK/CH en las web, > 90000 en las de ISIS);
     (d) si la tabla vuelve vacía (policy caída / sin red) no se pinta nada y no explota.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    function J(data) { return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(data); } }); }
    const urls = [];
    window.__vacia = false;
    window.fetch = function (url) {
      url = String(url); urls.push(url);
      if (url.indexOf("GV_Clientes_Nuevos") >= 0) {
        return J(window.__vacia ? [] : [
          { empresa: "lk", cod: "4185", pedidos: 2 },
          { empresa: "lk", cod: "4223", pedidos: 1 },
          { empresa: "chef", cod: "2701", pedidos: 0 }
        ]);
      }
      return J([]);
    };

    await facNuevosCargar();
    out.pidioTabla = urls.some(function (u) { return u.indexOf("GV_Clientes_Nuevos") >= 0; });
    out.n = _facNuevos.size;

    // (a) está en la tabla → badge, con el detalle del title
    const bLk = facNuevoBadge("98626", "4223");                 // NP de ISIS de LK (> 90000)
    out.lkTieneBadge = bLk.indexOf("fac-nuevo-badge") >= 0;
    out.lkDice = bLk.indexOf("Cliente nuevo") >= 0;
    out.lkDetalle = bLk.indexOf("1 pedido facturado") >= 0;
    out.webTieneBadge = facNuevoBadge("LK 0099", "4185").indexOf("fac-nuevo-badge") >= 0;  // NP web
    out.webPlural = facNuevoBadge("LK 0099", "4185").indexOf("2 pedidos facturados") >= 0;
    out.chefCero = facNuevoBadge("CH 0007", "2701").indexOf("ninguna compra facturada") >= 0;

    // (b) no está → sin badge
    out.viejoSinBadge = facNuevoBadge("98651", "4114") === "";
    out.sinCodSinBadge = facNuevoBadge("98651", "") === "";

    // (c) la empresa importa: el 4223 es nuevo en LK, no en Chef (44620 es NP de Chef)
    out.otraEmpresaSinBadge = facNuevoBadge("44620", "4223") === "";
    // …y al revés: el 2701 de Chef no debe marcarse desde una NP de LK
    out.chefNoEnLk = facNuevoBadge("98626", "2701") === "";

    // (d) tabla vacía → nada pintado, sin excepción
    window.__vacia = true; _facNuevosTs = 0; _facNuevos = new Map();
    await facNuevosCargar();
    out.vacio = facNuevoBadge("98626", "4223") === "";
    return out;
  });

  await b.close();
  const fail = [];
  if (errs.length) fail.push("pageerror: " + errs.join(" | "));
  [["pidioTabla", true], ["lkTieneBadge", true], ["lkDice", true], ["lkDetalle", true],
   ["webTieneBadge", true], ["webPlural", true], ["chefCero", true],
   ["viejoSinBadge", true], ["sinCodSinBadge", true], ["otraEmpresaSinBadge", true],
   ["chefNoEnLk", true], ["vacio", true]].forEach(function (k) {
    if (r[k[0]] !== k[1]) fail.push(k[0] + " = " + JSON.stringify(r[k[0]]) + " (esperaba " + k[1] + ")");
  });
  if (r.n !== 3) fail.push("n = " + r.n + " (esperaba 3)");

  if (fail.length) { console.error("FAIL fac-cliente-nuevo:\n - " + fail.join("\n - ")); process.exit(1); }
  console.log("OK fac-cliente-nuevo — badge Cliente nuevo por (empresa, cod), y sin filas no pinta nada");
})();
