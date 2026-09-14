/* v17.85 (Luis, 2026-09-14) — "↩ ENVIAR A PROGRAMAR" en la fila de cada NP de la tabla de
   Programación.
   Pedido: *"deberían aparecer en la fila con los datos de cada nota de pedido particular un botón
   que sea una flecha para atrás y que sea «Enviar a programar» en caso de que se tenga que
   reprogramar la fecha de entrega. Atento a que, si es uno de los que se programan automáticamente
   (zona 1 y zona 2 creo que eran), tiene que quedar en «A programar» (quedan en el estado que
   estaban (armado o facturado o pendiente, o sea, el sistema tiene memoria para no mandar a armar
   algo dos veces o no mandar algo a armar que no estaba armado))"*.
   Se chequea:
     (a) el botón está en la fila de la NP y NO abre/cierra la fila al tocarlo;
     (b) una NP web llama a gv_ppp_web_desprogramar, y una de ISIS a gv_ppp_isis_desprogramar;
     (c) después de sacarlo, el árbol se recarga (tiene caché propio);
     (d) el cartel ya no promete que lo reprograma el automático;
     (e) en A Programar el pedido retenido sale con el chip rojo de "ya pickeada y armada · TANDA";
     (f) y programarlo lo devuelve a ESA tanda (gv_ppp_web_tanda_reusar), sin crear una nueva.
   Estado inyectado; no pega contra la red. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, rpc = [];
    window.__isSupervisor = true;
    const confirms = [];
    window.confirm = function (t) { confirms.push(String(t || "")); return true; };
    window.prompt = function (_m, d) { return d || "x"; };
    window.alert = function () {};
    window.getTodayKey = () => "2026-09-14";
    window.aprQuien = async function () { return "luis@x"; };
    window.aprRpc = async function (fn, args) { rpc.push({ fn: fn, args: args }); return [{ np_sacadas: 2, order_id: 1401, np_programadas: 2, tanda: "E01A" }]; };
    window.pppLoadProgFromSupabase = async function () {};
    window.pppSetStatus = function () {};
    window.pppCuarDeNpSacada = async function () { return null; };

    const mk = (np, est) => ({ fecha: "2026-09-15", tanda: "E01A", np: np, np_num: 58, cod: "2118",
      razon_social: "Ricci Gabriel", localidad: "CABA", zona: "Zona 2", zona_corta: "Zona 2",
      empresa: "LK", origen: /^(LK|CH) /.test(np) ? "web" : "isis", m3: 1.2, estado: est,
      estado_orden: 1, barrio: "Villa Crespo", fecha_pedido: "2026-09-11" });
    _pgaRows = [mk("LK 0058", "armado"), mk("98700", "facturado")];
    _pgaTs = Date.now();
    let recargas = 0;
    window.pgaNeed = function () {};
    window.pgaRecargar = async function () { recargas++; };
    _pppParsed = { prog: [{ np: "98630", tanda: "D72B", fecha_entrega: "2026-09-15", m3: 1.8, cod: "1", razon_social: "X", zona: "Zona 2", programmed: true }] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanClasica = false; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg(); await new Promise((res) => setTimeout(res, 200));
    pgaAbrirDia("20260915"); await new Promise((res) => setTimeout(res, 120));
    pgaAbrirTanda("20260915|E01A"); await new Promise((res) => setTimeout(res, 150));
    const prev = document.getElementById("pppPreview");

    // (a) el botón está, dice lo que pidió Luis y no abre la fila
    const fila = [...prev.querySelectorAll("tr.pga-n")].find((x) => x.textContent.indexOf("LK 0058") >= 0);
    const bt = fila && fila.querySelector(".pga-acc-b");
    out.hayBoton = !!bt;
    out.textoBoton = bt ? bt.textContent.trim() : "";
    out.titleBoton = bt ? bt.getAttribute("title") : "";
    out.abiertasAntes = prev.querySelectorAll("tr.pga-c").length;

    // (b) NP web → gv_ppp_web_desprogramar
    bt.click(); await new Promise((res) => setTimeout(res, 250));
    out.abiertasDespues = document.getElementById("pppPreview").querySelectorAll("tr.pga-c").length;
    out.rpcWeb = rpc.map((x) => x.fn).join(",");
    // v17.90 (Luis): "que también pida confirmación para enviar a programar", con su texto, UNA vez
    out.confirmTxt = confirms.join(" ||| ");
    out.confirmUno = confirms.length === 1;
    out.argWeb = JSON.stringify((rpc.find((x) => x.fn === "gv_ppp_web_desprogramar") || {}).args || {});
    out.recargo = recargas;

    // (b bis) NP de ISIS → gv_ppp_isis_desprogramar
    rpc.length = 0;
    await pgaEnviarAProgramar("98700"); await new Promise((res) => setTimeout(res, 250));
    out.rpcIsis = rpc.map((x) => x.fn).join(",");

    // (g) v17.88 — el tacho: pop-up de ATENCIÓN, justificativo obligatorio y la RPC del desarme
    rpc.length = 0;
    // ⚠ NO volver a llamar a pgaAbrirDia / pgaAbrirTanda acá: son TOGGLE, y llamarlas de nuevo
    // CIERRAN el día que ya estaba abierto y la fila desaparece. Basta con volver a pedir el nodo
    // (#pppPreview se puede haber redibujado con el click de arriba).
    const prev2 = document.getElementById("pppPreview");
    const filaD = [...prev2.querySelectorAll("tr.pga-n")].find((x) => x.textContent.indexOf("LK 0058") >= 0);
    const btD = filaD && filaD.querySelector(".pga-acc-b.del");
    out.hayTacho = !!btD;
    out.textoTacho = btD ? btD.textContent.trim() : "";
    out.titleTacho = btD ? btD.getAttribute("title") : "";
    btD.click(); await new Promise((res) => setTimeout(res, 150));
    const mh = (document.getElementById("dsmModal") || {}).innerHTML || "";
    out.atencion = /ATENCIÓN/.test(mh) && /NO SE DESHACE/.test(mh) && /permanente/i.test(mh);
    // v17.90 (Luis): el stock NO vuelve a góndola — pasa a "A guardar" y lo procesa un operario
    out.explica = /sale de la PPP<\/b>/.test(mh) && /A guardar<\/b>, y un operario las guarda/.test(mh) &&
                  !/vuelven a góndola/.test(mh) && /NO se borra de la página/.test(mh);
    out.sinAvisoFact = !/ya está facturada/.test(mh);   // LK 0058 está armada, no facturada
    out.avisoIsisWeb = /dsm-isis/.test(mh);                 // una NP web NO lleva el aviso de ISIS
    out.okBloqueado = !!(document.getElementById("dsmOk") || {}).disabled;
    document.getElementById("dsmJust").value = "corto"; dsmChk();
    out.cortoBloqueado = !!(document.getElementById("dsmOk") || {}).disabled;
    document.getElementById("dsmJust").value = "el cliente lo cancelo por telefono"; dsmChk();
    out.largoHabilita = !(document.getElementById("dsmOk") || {}).disabled;
    await dsmConfirmar(); await new Promise((res) => setTimeout(res, 250));
    const g = rpc.find((x) => x.fn === "gv_ppp_np_desarmar");
    out.desarma = !!g && g.args.p_np === "LK 0058" && g.args.p_justificativo === "el cliente lo cancelo por telefono";
    out.cerro = !!(document.getElementById("dsmModal") || {}).hidden;

    // y una NP de ISIS sí lleva el aviso de darla de baja a mano
    dsmAbrir("98700"); await new Promise((res) => setTimeout(res, 120));
    const mi = (document.getElementById("dsmModal") || {}).innerHTML || "";
    out.avisoIsis = /dsm-isis/.test(mi) && /dar de baja a mano/.test(mi);
    // 98700 además está facturada: tiene que avisar que no va a devolver ninguna caja
    out.avisoFacturada = /ya está facturada/.test(mi) && /no devuelve ninguna/.test(mi);
    dsmCerrar();

    // (d) el cartel del web ya no promete el automático
    out.cartel = String(window.pppVencVolver).indexOf("NO lo vuelve a programar solo") >= 0 &&
                 String(window.pppVencVolver).indexOf("lo toma el automático") < 0;

    // (e)(f) A Programar: el retenido sale con su chip y vuelve a SU tanda
    rpc.length = 0;
    _apr.listo = true; _apr.tandas = []; _apr.items = {}; _apr.salida = {}; _apr.cuarResumen = [];
    _apr.cal = [{ dia: "2026-09-22", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    window.aprHorNeed = function () {}; window.pppSupersNeed = function () {};
    const ped = { order_id: 1401, empresa: "lk", cod: "2118", razon_social: "Ricci Gabriel",
      zona: "Zona 2 - CABA Centro", fecha_recep: "2026-09-11", localidad: "Villa Crespo",
      direccion: "x", m3: 1.2, m3_parcial: false, lineas: 2, cajas: 3, np_total: 1,
      bloques: [{ np_idx: 1, items: [] }],
      tanda_previa: "E01A", ya_pickeada: true, ya_armada: true };
    _apr.pedidos = [ped]; _apr.pedidosTodos = [ped];
    _pppTab = "prog";
    aprRender(); await new Promise((res) => setTimeout(res, 250));
    const chip = document.getElementById("pppPreview").querySelector(".apr-chip-hecho");
    out.chip = chip ? chip.textContent.trim() : "";
    out.yaHecho = _aprYaHecho(ped);

    await aprGenerarTanda("2026-09-22", [aprKey("lk", 1401)], { sinConfirm: false });
    await new Promise((res) => setTimeout(res, 250));
    out.rpcProg = rpc.map((x) => x.fn).join(",");
    out.argProg = JSON.stringify((rpc.find((x) => x.fn === "gv_ppp_web_tanda_reusar") || {}).args || {});
    return out;
  });

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  t(r.hayBoton, "(a) la fila de la NP trae el botón");
  // v17.90 (Luis): "hacé que los botones sean sólo los íconos y agregá la descripción cuando uno
  // pone el mouse encima"
  t(r.textoBoton === "↩", "(a) es SÓLO el ícono — " + JSON.stringify(r.textoBoton));
  t(/Enviar a programar/.test(r.titleBoton), "(a) y lo que hace lo dice el tooltip — " + JSON.stringify(r.titleBoton));
  t(r.abiertasAntes === r.abiertasDespues, "(a) tocarlo NO abre ni cierra el contenido de la NP");
  t(/gv_ppp_web_desprogramar/.test(r.rpcWeb), "(b) una NP web va por gv_ppp_web_desprogramar — " + r.rpcWeb);
  t(/"p_np":"LK 0058"/.test(r.argWeb), "(b) con su NP — " + r.argWeb);
  t(/gv_ppp_isis_desprogramar/.test(r.rpcIsis), "(b) y una de ISIS por gv_ppp_isis_desprogramar — " + r.rpcIsis);
  t(r.recargo >= 1, "(c) después de sacarlo se recarga el árbol");
  t(/¿Estás seguro que querés sacar este pedido de esta tanda y mandarlo «A PROGRAMAR»\?/.test(r.confirmTxt),
    "(h) pide confirmación con el texto que pidió Luis — " + JSON.stringify(r.confirmTxt));
  t(r.confirmUno, "(h) y una sola vez (no encadena la confirmación vieja)");
  t(r.cartel, "(d) el cartel ya no promete que lo reprograma el automático");
  t(r.hayTacho, "(g) la fila trae también el tacho");
  t(r.textoTacho === "🗑", "(g) el tacho también es sólo el ícono — " + JSON.stringify(r.textoTacho));
  t(/Desarmar pedido/.test(r.titleTacho), "(g) con su tooltip — " + JSON.stringify(r.titleTacho));
  t(r.atencion, "(g) el pop-up grita ATENCIÓN, que no se deshace y que es permanente");
  t(r.explica, "(g) y explica las tres cosas: sale de la PPP, el stock pasa a «A guardar», NO se borra de la página");
  t(r.sinAvisoFact, "(g) una NP armada (no facturada) no lleva ese aviso");
  t(!r.avisoIsisWeb, "(g) una NP web no lleva el aviso de ISIS");
  t(r.okBloqueado, "(g) sin justificativo no se puede confirmar");
  t(r.cortoBloqueado, "(g) con un justificativo corto tampoco");
  t(r.largoHabilita, "(g) con uno de 10+ caracteres sí");
  t(r.desarma, "(g) confirmar llama a gv_ppp_np_desarmar con la NP y el justificativo");
  t(r.cerro, "(g) y cierra el pop-up");
  t(r.avisoIsis, "(g) en una NP de ISIS avisa que además hay que darla de baja a mano");
  t(r.avisoFacturada, "(g) y si ya está facturada, que el desarme no va a devolver ninguna caja");
  t(r.yaHecho, "(e) el pedido web retenido cuenta como «ya hecho»");
  t(/ya pickeada y armada · E01A/.test(r.chip), "(e) y sale con su chip rojo en A Programar — " + JSON.stringify(r.chip));
  t(/gv_ppp_web_tanda_reusar/.test(r.rpcProg) && !/gv_ppp_web_tanda_nueva/.test(r.rpcProg),
    "(f) programarlo lo devuelve a SU tanda, sin crear una nueva — " + r.rpcProg);
  t(/"p_order_id":1401/.test(r.argProg) && /"p_fecha":"2026-09-22"/.test(r.argProg),
    "(f) con el pedido y el día — " + r.argProg);
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  console.log(ok ? "\nOK pga-enviar-a-programar" : "\nFALLÓ pga-enviar-a-programar");
  process.exit(ok ? 0 : 1);
})();
