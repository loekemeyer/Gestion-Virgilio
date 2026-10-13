/* v29.67 (Luis, 13/10, D2: «el operario lo puso mal · ponele candado») — CANDADO del Ingreso a racks.

   Caso que lo originó: el 13/10 09:34 el legajo 104 escribió la POSICIÓN «AB3» en el campo del CÓDIGO y
   entraron 60 cajas de un código fantasma en AB03 (eran 956E y terminaron en AB10, 09:37). El 09/10 había
   pasado lo mismo con «606», que era 606E. Se prueba, corriendo la pantalla de verdad:
     A) un código que existe (956E) no avisa nada y deja seguir.
     B) una POSICIÓN de rack (AB3 → AB03) avisa que NO es un artículo, nombra la posición y el campo Sector,
        y DESHABILITA «Revisar carga»: no se puede ingresar.
     C) un código que no existe y no es posición (606) avisa y PREGUNTA (no bloquea): «no» no sigue, «sí» sí.
     D) un código dado de baja (865ED → 865E) avisa cuál va y bloquea.
     E) en modo NACIONAL no hay candado: el código sale de la lista de stock real.
     F) candado invertido: irRevisar tiene que llamar a _irCodGuard antes del paso de revisión.
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
  const idx = fs.readFileSync(path.join(root, "index.html"), "latin1");
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/*.supabase.co/**", (r) => r.abort());
  await p.goto("file://" + path.join(root, "index.html"), { waitUntil: "load" });
  await p.waitForFunction(() => ["showIngresoRacksModal", "irRevisar", "irSetCod"].every((f) => typeof window[f] === "function"), { timeout: 25000 });

  const r = await p.evaluate(async () => {
    const out = {};
    const wait = (ms) => new Promise((res) => setTimeout(res, ms));
    const alerts = []; window.alert = function (m) { alerts.push(String(m)); };
    let siNo = true; window.confirm = function () { return siNo; };
    window.loadArtNombres = async function () { return {}; };
    window.stockFetchSaldos = async function () { return { "502": { cod: "502", desc: "Prueba", racks: 0, a_guardar: 40, terminado: 0, excedente: 0 } }; };
    window.racksFetchPlani = async function () { return [{ sector: "AD05", estado: "libre", cod_art: null }]; };
    window.irFetchCxM = async function () { return {}; };
    window.trySendOneReport = async function () { return { ok: true }; };
    // los tres RPC del candado, contestados acá (la base no se toca)
    const EX = { "956E": true, "502": true, "AB3": false, "606": false, "865ED": false };
    const POS = { "AB3": "AB03", "AB10": "AB10", "X22": "X22" };
    const BAJA = { "865ED": "865E" };
    const pedidos = [];
    window.fetch = async function (url, opt) {
      const u = String(url); const body = JSON.parse((opt && opt.body) || "{}");
      const j = (v) => ({ ok: true, status: 200, json: async () => v });
      if (u.indexOf("gv_stock_cod_conocido") >= 0) { pedidos.push("ex:" + body.p_cod); return j(EX[body.p_cod] === true); }
      if (u.indexOf("gv_codigo_baja_de") >= 0) { pedidos.push("baja:" + body.p_cod); return j(BAJA[body.p_cod] || null); }
      if (u.indexOf("gv_rack_sector") >= 0) { pedidos.push("pos:" + body.p); return j(POS[body.p] || null); }
      return { ok: false, status: 500, json: async () => null };
    };

    localStorage.clear();
    const inp = document.getElementById("legajoInput"); if (inp) inp.value = "77";
    await showIngresoRacksModal("77");
    await wait(30);
    const btn = () => document.querySelector("#irBody .ir-fin");
    const warn = () => { const w = document.querySelector("#irBody .ir-warn"); return w ? w.innerText : ""; };
    const poner = async (cod) => {
      if (typeof window._irCodChk === "function") await _irCodChk(cod);   // calienta el cache: el aviso sale sin esperar el debounce
      irSetModo("import"); irSetCod(cod); irSetSec("AD05"); irSetI(60); await wait(10);
    };

    // A) código que existe
    await poner("956E");
    out.aSinAviso = warn() === "" && !!btn() && !btn().disabled;
    alerts.length = 0; await irRevisar();
    out.aSigue = !!(_ir && _ir.confirming) && alerts.length === 0;
    irVolver();

    // B) una POSICIÓN de rack
    await poner("AB3");
    const wB = warn();
    out.bAvisa = /AB03/.test(wB) && /no es un art/i.test(wB) && /Sector/i.test(wB);
    out.bBoton = !!btn() && btn().disabled === true;
    alerts.length = 0; await irRevisar();
    out.bNoSigue = !(_ir && _ir.confirming);
    out.bAlerta = alerts.length === 1 && /AB03/.test(alerts[0]) && /POSICI/i.test(alerts[0]);

    // C) código que no existe y no es posición: pregunta
    await poner("606");
    out.cAvisa = /606/.test(warn()) && /no existe/i.test(warn());
    out.cBotonHabilitado = !!btn() && btn().disabled === false;
    siNo = false; await irRevisar();
    out.cNoSinConfirmar = !(_ir && _ir.confirming);
    siNo = true; await irRevisar();
    out.cSiConConfirmar = !!(_ir && _ir.confirming);
    irVolver();

    // D) código dado de baja
    await poner("865ED");
    out.dAvisa = /865E/.test(warn()) && /no se usa/i.test(warn());
    out.dBoton = !!btn() && btn().disabled === true;
    alerts.length = 0; siNo = true; await irRevisar();
    out.dNoSigue = !(_ir && _ir.confirming) && alerts.length === 1 && /865E/.test(alerts[0]);

    // E) en nacional no hay candado (el código sale de la lista de stock real)
    irSetModo("nacional"); irSetOrigen("a_guardar"); irPickCod(encodeURIComponent("502")); irSetSec("AD05"); irSetI(10);
    await wait(10);
    const antes = pedidos.length;
    await irRevisar();
    out.eNacSinCandado = !!(_ir && _ir.confirming) && pedidos.length === antes;
    irVolver();
    out.pedidos = pedidos.join(" ");
    return out;
  });
  await b.close();

  let bad = 0;
  const ok = (c, t) => { console.log((c ? "OK  " : "FALLA ") + t); if (!c) bad++; };
  ok(!errs.length, "la pantalla corre sin errores de JS" + (errs.length ? " — " + errs[0] : ""));
  ok(r.aSinAviso, "956E (existe): sin aviso y el botón habilitado");
  ok(r.aSigue, "956E: pasa al paso de revisión sin preguntar nada");
  ok(r.bAvisa, "AB3: el aviso nombra la posición AB03 y el campo Sector");
  ok(r.bBoton, "AB3: «Revisar carga» queda DESHABILITADO");
  ok(r.bNoSigue, "AB3: no pasa al paso de revisión");
  ok(r.bAlerta, "AB3: el cartel dice que es una POSICIÓN de rack, no un artículo");
  ok(r.cAvisa, "606 (no existe, no es posición): avisa que no existe");
  ok(r.cBotonHabilitado, "606: el botón NO se bloquea — es una pregunta, no un candado");
  ok(r.cNoSinConfirmar, "606: si dice «no», no carga");
  ok(r.cSiConConfirmar, "606: si dice «sí», sigue");
  ok(r.dAvisa, "865ED: el aviso dice que va el 865E");
  ok(r.dBoton && r.dNoSigue, "865ED: bloqueado y avisado");
  ok(r.eNacSinCandado, "modo Nacional: sin candado (el código sale de la lista de stock)");
  ok(/await _irCodGuard\(/.test(idx.replace(/\r/g, "")), "irRevisar llama al candado _irCodGuard (candado invertido)");
  if (!bad) console.log("\nTODO OK (" + 15 + " chequeos)"); else console.log("\n" + bad + " en rojo");
  process.exit(bad ? 1 : 0);
})();
