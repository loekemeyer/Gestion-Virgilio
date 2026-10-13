/* v29.67 (D2: «ponele candado») + v29.77 (Luis, 13/10: «mas que candado, solo debería dar opciones de
   poner un codigo ya existente. a medida que se escribe se sugiere el codigo») — el campo CÓDIGO del
   Ingreso a racks (modo Importación).

   Caso que lo originó: el 13/10 09:34 el legajo 104 escribió la POSICIÓN «AB3» en el campo del CÓDIGO y
   entraron 60 cajas de un código fantasma en AB03 (eran 956E y terminaron en AB10, 09:37). El 09/10 había
   pasado lo mismo con «606», que era 606E. Se prueba, corriendo la pantalla de verdad:
     A) un código que existe (956E) no avisa nada y deja seguir.
     B) una POSICIÓN de rack (AB3 → AB03) NO se puede cargar y NO lleva cartel (Luis, v29.78: «No tiene
        que avisar que es una posicion, simplemente no tiene que dejar»): no está en la lista, no ofrece
        el «usar igual» y «Revisar carga» queda deshabilitado; forzada por código (irSetCod) el candado
        la frena sin decir nada.
     C) «606» (lo que se tipeó el 09/10) sugiere el 606E, que es el que existe; y un código que no
        coincide con nada ofrece «✎ Cargar igual (código nuevo)», y ahí el candado PREGUNTA.
     D) un código dado de baja (865ED → 865E) avisa cuál va, no ofrece el «usar igual» y bloquea.
     E) en modo NACIONAL no hay candado: el código sale de la lista de stock real.
     F) candado invertido: irRevisar tiene que llamar a _irCodGuard antes del paso de revisión, y el
        input de Importación tiene que llamar a irSetPick (BUSCA), no a irSetCod (texto libre).
     G) las SUGERENCIAS: por código parcial, por nombre, el cero adelante (26 → 026) y que una
        coincidencia parcial NO elige sola.
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
    // el universo de códigos (gv_stock_cod_lista) y los tres RPC del candado, contestados acá (la base no se toca)
    const LISTA = [
      { cod: "026", nombre: "Colador Ø 8cm", importado: true },
      { cod: "502", nombre: "Prueba 502", importado: false },
      { cod: "606E", nombre: "Pinza 30 cm Ac Inox c/ Silic", importado: true },
      { cod: "956E", nombre: "Cuchara Calada Silicona Mgo Bambú", importado: true }
    ];
    const EX = { "956E": true, "502": true, "026": true, "606E": true, "AB3": false, "606": false, "XQ7": false, "865ED": false };
    const POS = { "AB3": "AB03", "AB10": "AB10", "X22": "X22" };
    const BAJA = { "865ED": "865E" };
    const pedidos = [];
    window.fetch = async function (url, opt) {
      const u = String(url); const body = JSON.parse((opt && opt.body) || "{}");
      const j = (v) => ({ ok: true, status: 200, json: async () => v });
      if (u.indexOf("gv_stock_cod_lista") >= 0) { pedidos.push("lista"); return j(LISTA); }
      if (u.indexOf("gv_stock_cod_conocido") >= 0) { pedidos.push("ex:" + body.p_cod); return j(EX[body.p_cod] === true); }
      if (u.indexOf("gv_codigo_baja_de") >= 0) { pedidos.push("baja:" + body.p_cod); return j(BAJA[body.p_cod] || null); }
      if (u.indexOf("gv_rack_sector") >= 0) { pedidos.push("pos:" + body.p); return j(POS[body.p] || null); }
      return { ok: false, status: 500, json: async () => null };
    };

    localStorage.clear();
    const inp = document.getElementById("legajoInput"); if (inp) inp.value = "77";
    await showIngresoRacksModal("77");
    await wait(30);
    out.leyoLista = !!(_ir && (_ir.cods || []).length === 4);
    const btn = () => document.querySelector("#irBody .ir-fin");
    const warn = () => { const w = document.querySelector("#irBody .ir-warn"); return w ? w.innerText : ""; };
    const sug = () => Array.prototype.map.call(document.querySelectorAll("#irBody button[onclick^='irPickCod']"), (x) => x.innerText.replace(/\s+/g, " ").trim());
    const nuevoBtn = () => document.querySelector("#irBody button[onclick^='irCodNuevo']");
    // escribir en el campo (el camino del operario): el código se ELIGE, no se escribe libre
    const tipear = async (txt) => {
      if (typeof window._irCodChk === "function") await _irCodChk(txt);   // calienta el cache: el aviso sale sin esperar el debounce
      irSetModo("import"); irSetPick(txt); irSetSec("AD05"); irSetI(60); await wait(10);
    };

    // A) código que existe: escrito entero se elige solo
    await tipear("956E");
    out.aElige = !!(_ir && _ir.cod === "956E" && !_ir.codNuevo);
    out.aSinAviso = warn() === "" && !!btn() && !btn().disabled;
    alerts.length = 0; await irRevisar();
    out.aSigue = !!(_ir && _ir.confirming) && alerts.length === 0;
    irVolver();

    // G) sugerencias
    await tipear("956");
    out.gParcialSugiere = sug().length === 1 && /956E/.test(sug()[0]) && /🚢/.test(sug()[0]);
    out.gParcialNoElige = !!(_ir && !_ir.cod) && !!btn() && btn().disabled === true;
    const bs = document.querySelector("#irBody button[onclick^='irPickCod']"); if (bs) bs.click();
    await wait(10);
    out.gClickElige = !!(_ir && _ir.cod === "956E") && !!btn() && btn().disabled === false;
    await tipear("cuchara");
    out.gPorNombre = sug().length === 1 && /956E/.test(sug()[0]);
    await tipear("26");
    out.gCeroAdelante = !!(_ir && _ir.cod === "026");

    // B) una POSICIÓN de rack: no se puede cargar, y sin cartel
    await tipear("AB3");
    out.bSinCartel = !/AB03/.test(document.getElementById("irBody").innerText) && !/POSICI/i.test(document.getElementById("irBody").innerText);
    out.bNoElige = !!(_ir && !_ir.cod) && !nuevoBtn();
    out.bBoton = !!btn() && btn().disabled === true;
    alerts.length = 0; await irRevisar();
    out.bNoSigue = !(_ir && _ir.confirming) && alerts.length === 0;
    irSetCod("AB3"); await wait(10);                       // forzado por código: lo frena el candado
    alerts.length = 0; await irRevisar();
    out.bForzadoFrena = !(_ir && _ir.confirming) && alerts.length === 0;

    // C) «606» (el caso del 09/10): no existe como código, pero la lista sugiere el que sí existe
    await tipear("606");
    out.cSugiere606E = sug().length === 1 && /606E/.test(sug()[0]) && !nuevoBtn();
    out.cBotonSinElegir = !!btn() && btn().disabled === true;
    // un código que no coincide con nada: se puede cargar igual y ahí el candado pregunta
    await tipear("XQ7");
    out.cNoEstaEnLaLista = sug().length === 0 && !!nuevoBtn();
    const bn = nuevoBtn(); if (bn) bn.click(); await wait(10);
    out.cUsarIgual = !!(_ir && _ir.cod === "XQ7" && _ir.codNuevo === true) && !!btn() && btn().disabled === false;
    out.cAvisa = /XQ7/.test(warn()) && /no existe/i.test(warn());
    siNo = false; await irRevisar();
    out.cNoSinConfirmar = !(_ir && _ir.confirming);
    siNo = true; await irRevisar();
    out.cSiConConfirmar = !!(_ir && _ir.confirming);
    irVolver();

    // D) código dado de baja
    await tipear("865ED");
    out.dAvisa = /865E/.test(warn()) && /no se usa/i.test(warn());
    out.dNoOfrece = !nuevoBtn() && sug().length === 0;
    out.dBoton = !!btn() && btn().disabled === true;
    irSetCod("865ED"); await wait(10);
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

  const sin = idx.replace(/\r/g, "");
  let bad = 0;
  const ok = (c, t) => { console.log((c ? "OK  " : "FALLA ") + t); if (!c) bad++; };
  ok(!errs.length, "la pantalla corre sin errores de JS" + (errs.length ? " — " + errs[0] : ""));
  ok(r.leyoLista, "el modal lee el universo de códigos (gv_stock_cod_lista)");
  ok(r.aElige && r.aSinAviso, "956E escrito entero: se elige solo, sin aviso y el botón habilitado");
  ok(r.aSigue, "956E: pasa al paso de revisión sin preguntar nada");
  ok(r.gParcialSugiere, "«956»: sugiere 956E con el 🚢 de importado");
  ok(r.gParcialNoElige, "una coincidencia parcial NO elige sola: hay que tocarla");
  ok(r.gClickElige, "tocar la sugerencia elige el código");
  ok(r.gPorNombre, "«cuchara»: sugiere por NOMBRE, no sólo por código");
  ok(r.gCeroAdelante, "«26» elige el 026 (el código como lo escriben los maestros)");
  ok(r.bSinCartel, "AB3: NO avisa que es una posición (v29.78) — ni en pantalla ni en un cartel");
  ok(r.bNoElige, "AB3: no se puede elegir ni ofrecer «usar igual» (es una posición)");
  ok(r.bBoton && r.bNoSigue, "AB3: «Revisar carga» deshabilitado y no pasa");
  ok(r.bForzadoFrena, "AB3 forzado por código: el candado la frena sin decir nada");
  ok(r.cSugiere606E, "«606» (el caso del 09/10): sugiere el 606E, que es el que existe");
  ok(r.cBotonSinElegir, "«606»: sin elegir nada el botón queda deshabilitado");
  ok(r.cNoEstaEnLaLista, "un código que no coincide con nada ofrece «Cargar igual (código nuevo)»");
  ok(r.cUsarIgual && r.cAvisa, "con «usar igual»: queda como código nuevo y avisa que no existe");
  ok(r.cNoSinConfirmar, "«usar igual»: si dice «no», no carga");
  ok(r.cSiConConfirmar, "«usar igual»: si dice «sí», sigue");
  ok(r.dAvisa && r.dNoOfrece, "865ED: el aviso dice que va el 865E y no se ofrece cargarlo");
  ok(r.dBoton && r.dNoSigue, "865ED: bloqueado y avisado");
  ok(r.eNacSinCandado, "modo Nacional: sin candado (el código sale de la lista de stock)");
  ok(/await _irCodGuard\(/.test(sin), "irRevisar llama al candado _irCodGuard (candado invertido)");
  ok(/id="irCod"[^>]*oninput="irSetPick\(/.test(sin) && !/id="irCod"[^>]*oninput="irSetCod\(/.test(sin),
     "el campo Código de Importación BUSCA (irSetPick), no acepta texto libre (irSetCod)");
  if (!bad) console.log("\nTODO OK (24 chequeos)"); else console.log("\n" + bad + " en rojo");
  process.exit(bad ? 1 : 0);
})();
