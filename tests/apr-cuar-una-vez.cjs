/* v22.32 (Luis, 24/09: "tiene que calcularla para todos los pedidos: lk, ch y los de ISIS que
   quedaron rezagados") — A Programar calculaba la cuarentena 3 veces y el día de salida 3 veces
   por carga (el día de salida la recalcula adentro): 9 cálculos pesados casi a la vez y la base
   se saturaba (24/09 10-12 h: el día de salida falló 20 de 46). Se corre aprCargar de verdad:
   (a) normal: cuarentena 2 veces (LK+ISIS, y la lista COMPLETA con Chef) y día de salida 1 vez,
       con LK + Chef + ISIS adentro;
   (b) Chef sin pedidos: cuarentena 1 vez, día de salida 1 vez;
   (c) Chef se cae: cuarentena 1 vez (LK+ISIS), día de salida 1 vez con LK+ISIS;
   (d) otra solapa abierta mientras carga: igual se clasifica y se calcula el día UNA vez, completo.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const fail = (m) => { console.error("✗ " + m); process.exitCode = 1; };
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const correr = (modo, tab) => p.evaluate(async ({ modo, tab }) => {
    const esp = (ms) => new Promise((r) => setTimeout(r, ms));
    const ped = (e, id, cod, extra) => Object.assign({ order_id: id, empresa: e, cod: cod, razon_social: "C" + id, zona: "Zona 1 - CABA Sur", m3: 0.1, fecha_recep: "2026-09-20", bloques: [] }, extra || {});
    const lk = [ped("lk", 1601, "10"), ped("lk", 1602, "11")];
    const isis = [ped("lk", "98700", "12", { _isis: true })];
    const ch = modo === "chefVacio" ? [] : [ped("chef", 301, "20")];
    const calls = [];
    window.aprTraerPedidos = async (e) => { if (e === "lk") return lk.map((x) => Object.assign({}, x)); await esp(60); if (modo === "chefCae") throw new Error("FDW"); return ch.map((x) => Object.assign({}, x)); };
    window.aprTraerIsis = async () => isis.map((x) => Object.assign({}, x));
    window.aprGet = async () => [];
    window.aprCargarCalendario = async () => {}; window.aprCargarLog = async () => {}; window.aprCargarCfg = async () => {};
    window.aprRpc = async (fn, body) => {
      if (fn === "gv_cuarentena_marcar") calls.push({ fn: "marcar", k: (body.p_pedidos || []).map((x) => x.empresa + ":" + x.order_id).sort().join(",") });
      if (fn === "gv_ppp_web_dia_salida") calls.push({ fn: "salida", k: (body.p_filas || []).map((x) => x.empresa + ":" + x.order_id).sort().join(",") });
      await esp(20); return [];
    };
    _apr.cargando = false; _apr.pedidosTodos = []; _pppTab = tab;
    await aprCargar();
    await esp(400);
    return calls;
  }, { modo, tab });
  const cuenta = (c, fn) => c.filter((x) => x.fn === fn);
  const TODO = "chef:301,lk:1601,lk:1602,lk:98700", LKI = "lk:1601,lk:1602,lk:98700";

  const a = await correr("normal", "prog");
  if (cuenta(a, "marcar").length !== 2) fail("(a) cuarentena " + cuenta(a, "marcar").length + " veces, esperaba 2: " + JSON.stringify(a));
  if (!cuenta(a, "marcar").some((x) => x.k === TODO)) fail("(a) ninguna cuarentena con LK+Chef+ISIS juntos: " + JSON.stringify(a));
  if (cuenta(a, "salida").length !== 1 || cuenta(a, "salida")[0].k !== TODO) fail("(a) día de salida: " + JSON.stringify(cuenta(a, "salida")));

  const bb = await correr("chefVacio", "prog");
  if (cuenta(bb, "marcar").length !== 1 || cuenta(bb, "marcar")[0].k !== LKI) fail("(b) Chef vacío, cuarentena: " + JSON.stringify(cuenta(bb, "marcar")));
  if (cuenta(bb, "salida").length !== 1) fail("(b) Chef vacío, día de salida: " + JSON.stringify(cuenta(bb, "salida")));

  const c = await correr("chefCae", "prog");
  if (cuenta(c, "marcar").length !== 1 || cuenta(c, "marcar")[0].k !== LKI) fail("(c) Chef caído, cuarentena: " + JSON.stringify(cuenta(c, "marcar")));
  if (cuenta(c, "salida").length !== 1 || cuenta(c, "salida")[0].k !== LKI) fail("(c) Chef caído, día de salida: " + JSON.stringify(cuenta(c, "salida")));

  const d = await correr("normal", "otra");
  if (cuenta(d, "marcar").length !== 1 || cuenta(d, "marcar")[0].k !== TODO) fail("(d) otra solapa, cuarentena: " + JSON.stringify(cuenta(d, "marcar")));
  if (cuenta(d, "salida").length !== 1 || cuenta(d, "salida")[0].k !== TODO) fail("(d) otra solapa, día de salida: " + JSON.stringify(cuenta(d, "salida")));

  if (errs.length) fail("errores de página: " + errs.join(" | "));
  await b.close();
  if (!process.exitCode) console.log("apr-cuar-una-vez: OK — carga normal: cuarentena 2 (LK+ISIS, y LK+Chef+ISIS), día de salida 1 con todo; Chef vacío/caído/otra solapa: 1 y 1");
})();
