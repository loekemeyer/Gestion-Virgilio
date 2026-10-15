/* v31.10 (Luis, 15/10: «Agrega al "Ingreso a Racks" una tercera pestaña que sea "Desde góndola" que permita
   enviar cajas desde góndola a racks y que tenga el conversor de masters») — se prueba corriendo la pantalla:
     A) hay tres pestañas y «Desde góndola» lista el stock de GÓNDOLA (terminado), sin el selector de origen.
     B) el conversor: 3 masters × CxM 6 = 18 cajas, y al RPC va p_origen 'terminado', 18 cajas, 3 masters.
     C) más cajas que las que hay en góndola: «Revisar carga» deshabilitado.
     D) un dual elegido de la lista («438E LK») va al RPC como 438E + empresa LK (antes iba «438ELK» → sin_stock)
        y no pide elegir empresa (la trae el saldo).
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
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "load" });
  await p.waitForFunction(() => ["showIngresoRacksModal", "irRevisar", "irSetModo", "irCargar"].every((f) => typeof window[f] === "function"), { timeout: 25000 });

  const r = await p.evaluate(async () => {
    const out = {};
    const wait = (ms) => new Promise((res) => setTimeout(res, ms));
    window.alert = function () {}; window.confirm = function () { return true; };
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return {
      "502": { cod: "502", desc: "Prueba", racks: 0, a_guardar: 0, terminado: 40, excedente: 0 },
      "438E LK": { cod: "438E LK", desc: "Colador", racks: 24, a_guardar: 0, terminado: 59, excedente: 0 },
      "999": { cod: "999", desc: "Sin gondola", racks: 0, a_guardar: 12, terminado: 0, excedente: 0 } }; };
    window.racksFetchPlani = async function () { return [{ sector: "AD05", estado: "libre", cod_art: null }, { sector: "AD06", estado: "libre", cod_art: null }]; };
    window.irFetchCxM = async function () { return { "502": 6, "438E": 3 }; };
    window.irFetchCodigos = async function () { return []; };
    window.trySendOneReport = async function () { return { ok: true }; };
    const rpcs = [];
    window.fetch = async function (url, opt) {
      const u = String(url);
      if (u.indexOf("racks_plani_ingreso_nacional") >= 0) { rpcs.push(JSON.parse(opt.body)); return { ok: true, status: 200, json: async () => "ok" }; }
      return { ok: false, status: 500, json: async () => null, text: async () => "" };
    };
    localStorage.clear();
    await showIngresoRacksModal("77");
    await wait(20);
    const body = () => document.getElementById("irBody").innerText;
    const btn = () => document.querySelector("#irBody .ir-fin");
    const lista = () => Array.prototype.map.call(document.querySelectorAll("#irBody button[onclick^='irPickCod']"), (x) => x.innerText.replace(/\s+/g, " ").trim());

    out.aTres = /Ingreso directo/.test(body()) && /Desde A guardar/.test(body()) && /Desde góndola/.test(body());
    irSetModo("gondola"); await wait(5);
    out.aOrigen = _ir.origen === "terminado" && !/Origen del stock/.test(body());
    const l = lista();
    out.aLista = l.some((x) => /^502 .*40 cj/.test(x)) && l.some((x) => /438E · LK.*59 cj/.test(x)) && !l.some((x) => /^999/.test(x));
    out.lista = l;

    irPickCod(encodeURIComponent("502")); irSetM(3); irSetSec("AD05"); await wait(5);
    out.bConvierte = Number(_ir.inner) === 18 && /6<\/b> cajas por master|6 cajas por master/.test(document.getElementById("irBody").innerHTML.replace(/<b>/g, ""));
    await irRevisar(); out.bRevisa = !!_ir.confirming;
    out.bConfTxt = /Desde góndola/.test(body()) && /Masters/i.test(body()); out.conf = body();
    await irCargar(); await wait(5);
    const r1 = rpcs[0] || {};
    out.bRpc = r1.p_origen === "terminado" && r1.p_cod === "502" && r1.p_inner === 18 && r1.p_master === 3 && r1.p_sector === "AD05";
    out.r1 = r1;

    irPickCod(encodeURIComponent("502")); irSetI(100); irSetSec("AD06"); await wait(5);
    out.cTope = !!btn() && btn().disabled === true && /No hay tantas/.test(body());

    irPickCod(encodeURIComponent("438E LK")); irSetM(0); irSetI(5); irSetSec("AD06"); await wait(5);
    out.dSinSelector = !/Empresa \(código dual\)/.test(body()) && !!btn() && btn().disabled === false;
    await irRevisar(); await irCargar(); await wait(5);
    const r2 = rpcs[1] || {};
    out.dRpc = r2.p_cod === "438E" && r2.p_emp === "LK" && r2.p_origen === "terminado" && r2.p_inner === 5;
    out.r2 = r2;
    return out;
  });
  await b.close();
  let bad = 0;
  const ok = (c, t) => { console.log((c ? "OK  " : "FALLA ") + t); if (!c) bad++; };
  ok(!errs.length, "la pantalla corre sin errores de JS" + (errs.length ? " — " + errs[0] : ""));
  ok(r.aTres, "Ingreso a racks tiene tres pestañas: Ingreso directo · Desde A guardar · Desde góndola");
  ok(r.aOrigen, "«Desde góndola»: origen terminado y sin el selector A guardar / Excedente");
  ok(r.aLista, "«Desde góndola» lista el stock de góndola (502 40 cj, 438E LK 59 cj) y no lo que sólo está en A guardar" + (r.aLista ? "" : " — " + JSON.stringify(r.lista)));
  ok(r.bConvierte, "conversor: 3 masters × 6 CxM = 18 cajas");
  ok(r.bRevisa && r.bConfTxt, "pasa a revisión y el resumen dice «Desde góndola» con los masters" + (r.bConfTxt ? "" : " — " + r.bRevisa + " " + JSON.stringify(r.conf)));
  ok(r.bRpc, "al RPC va p_origen terminado, 502, 18 cajas, 3 masters, AD05" + (r.bRpc ? "" : " — " + JSON.stringify(r.r1)));
  ok(r.cTope, "más cajas que las de góndola: avisa y no deja revisar");
  ok(r.dSinSelector, "dual elegido de la lista (438E LK): no pide empresa");
  ok(r.dRpc, "dual: al RPC va 438E + empresa LK, no «438ELK»" + (r.dRpc ? "" : " — " + JSON.stringify(r.r2)));
  process.exit(bad ? 1 : 0);
})();
