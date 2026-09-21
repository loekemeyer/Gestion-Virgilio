/* Regresión v20.56 — UN PEDIDO RETENIDO NO VUELVE A UNA TANDA QUE YA AVANZÓ SIN ÉL.

   Luis, 2026-09-21, mirando el desglose del badge: *"esto me preocupa. estaban armados? qué
   interacción tienen si vuelven a programación a su tanda y su tanda está armada/facturada/
   entregada cuando estos no?"*.

   Lo medido ese día: los flags `ya_pickeada` / `ya_armada` de `GV_PPP_Web_Retenido` son la FOTO
   del momento en que se sacó el pedido. D69H decía `false` (del 15/09) y el 21/09 ya tenía TAP.
   Probado en transacción abortada: las 3 NP de LK 1448 volvían a D69H y salían del árbol como
   ARMADAS sin haberse pickeado nunca —su mercadería no está en ese pallet— y además dejaban la
   tanda en dos días (22/09 y 25/09), que es el problema 338.

   Este test cubre el lado del front. El guard de verdad está en `gv_ppp_web_tanda_reusar`.
   Chequea:
   - un pedido cuya tanda anterior está armada / pickeada / facturada / salida NO puede volver;
   - uno cuya tanda no se empezó, o ya no existe, SÍ puede;
   - sin dato de estado decide el backend (no se bloquea por las dudas);
   - de varias NP con tandas distintas manda la MÁS avanzada;
   - el chip rojo dice que va a tanda nueva, y ya NO promete «no se pickea de nuevo»;
   - el chip verde del que sí vuelve existe y es otro.
   Sale 1 si falla. */
const fs = require("fs");
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const fallos = [];
  const html = fs.readFileSync(path.join(root, "index.html"), "latin1");

  // el front tiene que PEDIR el estado vivo, si no decide con la foto
  if (!/gv_ppp_web_retenido\?select=[^"]*tanda_estado/.test(html))
    fallos.push("el front no pide `tanda_estado`: decidiria con la foto de cuando se saco el pedido");
  // y no puede quedar la promesa vieja
  if (/vuelve a esa misma tanda: NO se pickea de nuevo/.test(html))
    fallos.push("sigue el texto viejo del chip: prometia que no se pickea de nuevo, y es falso");
  if (!/\.apr-chip-vuelve\{/.test(html)) fallos.push("falta el CSS del chip del que si vuelve");

  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(() => {
    const out = {};
    const ped = (estado) => ({ empresa: "lk", order_id: 1, tanda_previa: "D69H", tanda_estado: estado });
    out.puede = {};
    for (const e of ["", "no existe", "sin empezar", "codigo tomado", "pickeada", "armada", "facturada", "salio"])
      out.puede[e || "(sin dato)"] = _aprPuedeVolver(ped(e));
    out.sinTanda = _aprPuedeVolver({ empresa: "lk", order_id: 1, tanda_previa: "", tanda_estado: "sin empezar" });
    out.txt = {
      armada: _aprTandaEstadoTxt(ped("armada")),
      salio: _aprTandaEstadoTxt(ped("salio")),
      sinEmpezar: _aprTandaEstadoTxt(ped("sin empezar")),
    };
    // el orden que usa el merge de varias NP: la MAS avanzada gana
    out.orden = APR_TANDA_ORDEN.slice();
    return out;
  });
  await b.close();
  if (errs.length) fallos.push("errores de página: " + errs.join(" | "));

  const q = r.puede || {};
  for (const e of ["pickeada", "armada", "facturada", "salio", "codigo tomado"])
    if (q[e] !== false) fallos.push("con la tanda '" + e + "' deja volver, y no tiene que dejar");
  for (const e of ["sin empezar", "no existe"])
    if (q[e] !== true) fallos.push("con la tanda '" + e + "' no deja volver, y tiene que dejar");
  if (q["(sin dato)"] !== true) fallos.push("sin dato de estado deberia dejar decidir al backend, no bloquear");
  if (r.sinTanda !== false) fallos.push("un pedido sin tanda anterior no puede 'volver' a ninguna");

  const o = r.orden || [];
  if (o.indexOf("armada") <= o.indexOf("sin empezar"))
    fallos.push("el orden de estados esta mal: 'armada' tiene que pesar mas que 'sin empezar'");
  if (o.indexOf("salio") !== o.length - 1)
    fallos.push("'salio' tiene que ser el estado mas avanzado");
  if (!/armada/.test(r.txt.armada) || !/sali/.test(r.txt.salio))
    fallos.push("el texto del estado no se entiende: " + JSON.stringify(r.txt));
  if (r.txt.sinEmpezar !== "") fallos.push("'sin empezar' no lleva texto de alerta");

  if (fallos.length) { console.error("apr-retenido-tanda FALLA:\n - " + fallos.join("\n - ")); process.exit(1); }
  console.log("apr-retenido-tanda OK — no vuelve a una tanda que avanzó sin él; el chip dice la verdad.");
})();
