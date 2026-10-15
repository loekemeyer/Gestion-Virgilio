/* v31.12 (Luis, 15/10, D2: «D2 sí») — Bajar de racks NO registra una posición que no es rack.
   Caso: el 14/10 el legajo 94 bajó 54 cajas de 438E con «F15» (la góndola). La base lo grabó sin posición
   (−54 en el Mapa) y AD11 quedó con 78 cuando tenía 24. Se prueba corriendo la pantalla:
     A) con «F15» (gv_rack_sector → null) rkbConfirmar avisa y NO abre el código ni llama al RPC.
     B) si la base rechaza igual (400 RACKS_NO_ES_RACK), postBajaRacks lo AVISA (antes: console.error y nada).
     C) la cola offline con un ítem rechazado no se traba: se reenvía de a uno, entra el bueno y se avisa el malo.
     D) sin red para verificar, no frena (la base lo mira igual).
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const root = path.join(__dirname, "..");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const wait = (ms) => new Promise((res) => setTimeout(res, ms));
    const alerts = []; window.alert = function (m) { alerts.push(String(m)); };
    window.confirm = function () { return true; };
    window.stockFetchSaldos = async function () { return { "438E LK": { cod: "438E LK", desc: "Colador", racks: 24, terminado: 59 } }; };
    window.loadArtNombres = async function () { return; };
    window.rkbFetchCxM = async function () { return { cxm: {}, locs: {} }; };
    window.ocgFetchCapacidad = async function () { return {}; };
    let red = true, rechazar = {};
    const rpcs = [];
    window.fetch = function (url, opts) {
      const u = String(url), body = JSON.parse((opts && opts.body) || "{}");
      if (u.indexOf("rpc/gv_rack_sector") >= 0) {
        if (!red) return Promise.reject(new Error("sin red"));
        const map = { AD11: "AD11", F15: null };
        return Promise.resolve({ ok: true, status: 200, json: async () => (body.p in map ? map[body.p] : null) });
      }
      if (u.indexOf("rpc/registrar_baja_racks") >= 0) {
        rpcs.push(body.p_items.map((x) => x.sector).join(","));
        const malo = body.p_items.some((x) => rechazar[x.sector]);
        if (malo) return Promise.resolve({ ok: false, status: 400, text: async () => JSON.stringify({ code: "23514", message: "RACKS_NO_ES_RACK: «F15» no es una posicion de rack (¿es la gondola?). Deci de que rack bajas. No se grabo nada." }) });
        return Promise.resolve({ ok: true, status: 200, json: async () => 1 });
      }
      return Promise.resolve({ ok: true, status: 200, json: async () => [] });
    };
    await showRacksBajarModal("94");
    const it = (_rkb && _rkb.items || [])[0];
    if (!it) return { err: "no _rkb" };
    it.baja = 54; it.sec = "F15";
    alerts.length = 0;
    await Promise.race([rkbConfirmar(), wait(400)]);
    out.aAvisa = alerts.some((a) => /F15/.test(a) && /no es una posición de rack/.test(a));
    out.aNoModal = !document.getElementById("rkbVerifyOk");
    out.aNoRpc = rpcs.length === 0;

    // D) sin red para verificar: no frena (abre el código de verificación)
    red = false; alerts.length = 0;
    const done = rkbConfirmar(); await wait(60);
    out.dSigue = !!document.getElementById("rkbVerifyOk") && !alerts.length;
    const ok = document.getElementById("rkbVerifyOk"); if (ok) ok.click();
    await wait(30); const c = document.getElementById("rkcR0"); if (c) { c.value = "0"; document.getElementById("rkcOk").click(); }
    await Promise.race([done, wait(300)]); red = true;

    // B) la base rechaza: se avisa
    rechazar = { F15: true }; alerts.length = 0;
    await postBajaRacks([{ cod_art: "438E", cajas: 54, sector: "F15", legajo: "94" }]); await wait(20);
    out.bAvisa = alerts.some((a) => /NO se registró/.test(a) && /438E 54 cj \(F15\)/.test(a) && /no es una posicion de rack/.test(a));

    // C) la cola: un malo no traba al bueno
    alerts.length = 0; rpcs.length = 0;
    localStorage.setItem("vir_baja_racks_pend", JSON.stringify([{ cod_art: "438E", cajas: 5, sector: "AD11", cid: "x1" }, { cod_art: "438E", cajas: 54, sector: "F15", cid: "x2" }]));
    bajaRacksFlushPend(); await wait(60);
    out.cDeAUno = rpcs.join("|") === "AD11,F15|AD11|F15";
    out.cVacia = !JSON.parse(localStorage.getItem("vir_baja_racks_pend") || "[]").length;
    out.cAvisa = alerts.length === 1 && /F15/.test(alerts[0]);
    out.rpcs = rpcs;
    return out;
  });
  await b.close();
  let bad = 0;
  const ok = (c, t) => { console.log((c ? "OK  " : "FALLA ") + t); if (!c) bad++; };
  if (r.err) { console.log("FALLA " + r.err); process.exit(1); }
  ok(!errs.length, "la pantalla corre sin errores de JS" + (errs.length ? " — " + errs[0] : ""));
  ok(r.aAvisa, "F15 (la góndola): avisa que no es una posición de rack");
  ok(r.aNoModal && r.aNoRpc, "F15: no abre el código de verificación ni llama al RPC");
  ok(r.dSigue, "sin red para verificar la posición: no frena");
  ok(r.bAvisa, "la base rechaza (400): el operario ve qué no se grabó y por qué");
  ok(r.cDeAUno && r.cVacia, "cola offline: el rechazo no traba el resto (se reenvía de a uno)" + (r.cDeAUno ? "" : " — " + JSON.stringify(r.rpcs)));
  ok(r.cAvisa, "cola offline: avisa sólo el ítem rechazado");
  process.exit(bad ? 1 : 0);
})();
