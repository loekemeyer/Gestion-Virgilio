/* v21.65 (Luis, 2026-09-23)
   (1) el día y la franja que el cliente elige para RETIRAR viajan en la fila del pedido
       (v_pedidos_web_np / gv_pedidos_web_np_chef) y A Programar los muestra aunque la copia de
       lk_pedidos_match (sync c/15 min) todavía no haya llegado; lo cargado a mano sigue mandando.
   (2) el comentario del pedido se ve como badge «💬 comentario» en la NP de Programación. */
const path = require("path"), fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "utf8");
const fallas = [];
const exige = (re, msg) => { if (!re.test(src)) fallas.push(msg); };
exige(/observaciones,retiro_fecha,retiro_franja"/, "A Programar no le pide a LK retiro_fecha/retiro_franja");
exige(/retiro_fecha: n\.retiro_fecha \?/, "el pedido de A Programar no guarda retiro_fecha");
exige(/if \(p && \(p\.retiro_fecha \|\| p\.retiro_franja\)\) return \{/, "aprHorDe no usa el retiro que trae el pedido");
exige(/rpc\/gv_np_obs_lista/, "Programación no pide los comentarios (gv_np_obs_lista)");
exige(/💬 comentario/, "falta el badge de comentario en la NP");
if (fallas.length) { console.log("ppp-retiro-y-comentario: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.log("ppp-retiro-y-comentario: estático ✓ OK"); process.exit(0); } }
(async () => {
  const b = await chromium.launch();
  const p = await (await b.newContext()).newPage();
  await p.route("**/rest/v1/**", (r) => r.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const ped = { order_id: 1530, empresa: "lk", retiro_fecha: "2026-10-07", retiro_franja: "13:00 a 16:30" };
    _aprHor = {};
    const soloPedido = aprHorDe(ped);
    _aprHor = {}; _aprHor[aprHorKey("lk", 1530)] = { fecha: "2026-10-08", franja: "Mañana", origen: "manual" };
    const manual = aprHorDe(ped);
    _aprHor = {};
    const nada = aprHorDe({ order_id: 1, empresa: "lk" });
    _pgaObs = new Map([["LK 0100", "Horario 8.30 a 12.30"]]);
    return { soloPedido, manual, nada, obs: _pgaObsDe({ np: "LK 0100" }), sinObs: _pgaObsDe({ np: "LK 0101" }) };
  });
  await b.close();
  const mal = [];
  if (!r.soloPedido || r.soloPedido.fecha !== "2026-10-07" || r.soloPedido.franja !== "13:00 a 16:30") mal.push("sin copia no muestra el retiro del pedido: " + JSON.stringify(r.soloPedido));
  if (!r.manual || r.manual.fecha !== "2026-10-08") mal.push("lo manual no manda: " + JSON.stringify(r.manual));
  if (r.nada !== null) mal.push("pedido sin retiro devolvió algo");
  if (r.obs !== "Horario 8.30 a 12.30" || r.sinObs !== "") mal.push("_pgaObsDe: " + r.obs + " / " + r.sinObs);
  if (mal.length) { console.log("ppp-retiro-y-comentario: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("ppp-retiro-y-comentario: ✓ OK");
})().catch((e) => { console.log("ppp-retiro-y-comentario: ✗ FAIL " + e.message); process.exit(1); });
