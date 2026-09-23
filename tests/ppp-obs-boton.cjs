/* v21.80 (Tomás González, 2026-09-23) — LEER LA OBSERVACIÓN DEL PEDIDO EN LA PPP.
   Pedido: *"un botón que deje ver las observaciones que pone el cliente en la web al momento de
   cargar pedido"*. El dato ya viajaba (v21.34) y el badge ya avisaba (v21.65), pero el TEXTO
   vivía sólo en el `title`: en la tablet y en el celular no hay hover, así que el comentario que
   el badge anunciaba no se podía leer.
   Se chequea, corriendo la Programación de verdad:
     (a) la fila de la NP trae el badge y ES CLICKEABLE — abre el pop-up con el texto COMPLETO,
         no truncado, y sin abrir/cerrar la NP;
     (b) la fila de la TANDA cuenta cuántos comentarios lleva adentro (💬 2) y los muestra todos;
     (c) la del DÍA también, sumando las tandas;
     (d) al abrir la NP el comentario se ve en la celda, sin hover y sin un click más;
     (e) una NP sin comentario no dibuja badge ni renglón, y una tanda sin ninguno tampoco;
     (g) A Programar: el mismo badge, con la clave empresa+pedido (ahi no hay NP todavia);
     (f) un comentario con comillas, apóstrofes y saltos de línea no rompe el `onclick` — el texto
         nunca viaja en el atributo, viaja la NP.
   Estado inyectado; no pega contra la red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const _d = (n) => { const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() + n);
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
const F = { hoy: _d(0), d1: _d(1) };
F.d1C = F.d1.replace(/-/g, "");
/* Con comillas, apóstrofe y salto de línea a propósito: es el texto que rompería un `onclick`
   si alguien volviera a meter el comentario adentro del atributo. */
const OBS1 = 'Urgente: retira en moto el "Pato", av. O\'Higgins 123.\nSi no está, llamar al 11-5555-6666.';
const OBS2 = "Mandar con otro expreso, el de siempre no entrega en esa zona.";

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "load" });

  const r = await p.evaluate(async (A) => {
    const F = A.F, OBS1 = A.OBS1, OBS2 = A.OBS2, out = {};
    window.__isSupervisor = true;
    window.alert = function () {}; window.confirm = function () { return true; };
    window.getTodayKey = () => F.hoy;
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window.pgaNeed = function () {}; window.patrNeed = function () {};
    window.pgaRecargar = function () {};
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.aprRpc = async function () { return []; };
    _pppParsed = { prog: [{ np: "98630", tanda: "D99Z", fecha_entrega: F.d1, m3: 1.8,
                            cod: "1", razon_social: "Otra", zona: "Zona 2", programmed: true }] };

    const mk = (tanda, np, cli, m3) => ({ fecha: F.d1, tanda: tanda, np: np, np_num: 58,
      cod: "2118", razon_social: cli, localidad: "CABA", zona: "Zona 2", zona_corta: "Zona 2",
      empresa: "LK", origen: "web", m3: m3, estado: "pendiente", estado_orden: 1,
      barrio: "Villa Crespo", fecha_pedido: F.hoy });
    _pgaRows = [mk("E01A", "LK 0058", "Ricci Gabriel", 1.2),
                mk("E01A", "LK 0059", "Muller y Muller", 0.3),
                mk("E01A", "LK 0060", "Sin comentario SRL", 0.2),
                mk("E02A", "LK 0061", "Otra tanda SA", 0.4)];
    _pgaTs = Date.now();
    /* El mapa que alimenta el badge — el mismo que llena `gv_np_obs_lista`. Precargado, así
       `pgaObsNeed` no pide nada (y la red está cortada de todos modos). */
    _pgaObs = new Map([["LK 0058", OBS1], ["LK 0059", OBS2], ["LK 0060", ""], ["LK 0061", ""]]);
    _pgaItems = { "LK 0058": [{ art: "501", cajas: 3, uxb: 12 }] };

    const esperar = async function (fn, ms) {
      const t0 = Date.now();
      while (Date.now() - t0 < (ms || 15000)) { if (fn()) return true; await new Promise((res) => setTimeout(res, 40)); }
      return false;
    };
    const fila = function (sel, txt) {
      const pv = document.getElementById("pppPreview"); if (!pv) return null;
      return [...pv.querySelectorAll(sel)].find((x) => x.textContent.indexOf(txt) >= 0) || null;
    };
    const modalTxt = function () {
      const m = document.getElementById("gvObsModal");
      return (m && !m.hidden) ? (m.textContent || "") : "";
    };
    /* Contra un index.html SIN el pop-up esto no existe. El test tiene que REPORTAR las fallas,
       no morirse con "gvObsCerrar is not defined": una excepción no dice qué falló. */
    const cerrar = function () { try { gvObsCerrar(); } catch (_e) { const m = document.getElementById("gvObsModal"); if (m) m.hidden = true; } };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.pga"));

    // (c) la fila del DÍA cuenta los DOS comentarios (una tanda los tiene, la otra no)
    const fd = fila("tr.pga-d", "/");
    const bd = fd && fd.querySelector(".pga-obs");
    out.diaBadge = bd ? bd.textContent.trim() : "";
    if (bd) {
      bd.click();
      await esperar(() => !!modalTxt());
      const t = modalTxt();
      out.diaModalTieneLas2 = t.indexOf(OBS1) >= 0 && t.indexOf(OBS2) >= 0;
      out.diaModalNombraNps = t.indexOf("LK 0058") >= 0 && t.indexOf("LK 0059") >= 0;
      cerrar();
      out.diaNoAbrio = document.querySelectorAll("#pppPreview tr.pga-t").length === 0;
    }

    pgaAbrirDia(F.d1C);
    out.hayTandas = await esperar(() => !!fila("tr.pga-t", "E01A"));

    // (b) la fila de la TANDA: E01A tiene 2, E02A ninguno
    const ft = fila("tr.pga-t", "E01A"), ft2 = fila("tr.pga-t", "E02A");
    const bt = ft && ft.querySelector(".pga-obs");
    out.tandaBadge = bt ? bt.textContent.trim() : "";
    out.tandaSinObsNoDibuja = !!ft2 && !ft2.querySelector(".pga-obs");
    out.npsAntes = document.querySelectorAll("#pppPreview tr.pga-n").length;
    if (bt) {
      bt.click();
      await esperar(() => !!modalTxt());
      const t = modalTxt();
      out.tandaModalTieneLas2 = t.indexOf(OBS1) >= 0 && t.indexOf(OBS2) >= 0;
      out.tandaModalTitulo = /tanda E01A/.test(t);
      cerrar();
    }
    out.npsDespues = document.querySelectorAll("#pppPreview tr.pga-n").length;   // tocar el badge no abre la tanda

    pgaAbrirTanda(F.d1C + "|E01A");
    out.hayNps = await esperar(() => !!fila("tr.pga-n", "LK 0058"));

    // (a) el badge de la NP se toca y muestra el texto COMPLETO
    const fn = fila("tr.pga-n", "LK 0058"), fn0 = fila("tr.pga-n", "LK 0060");
    const bn = fn && fn.querySelector(".pga-obs");
    out.npBadge = !!bn;
    out.npBadgeClickeable = !!(bn && String(bn.getAttribute("onclick") || "").indexOf("pgaObsAbrir") >= 0);
    out.npBadgeSinCursorHelp = !!bn && String(bn.getAttribute("style") || "").indexOf("cursor:help") < 0;
    out.npSinObsNoDibuja = !!fn0 && !fn0.querySelector(".pga-obs");
    // (f) el texto NO puede estar en el atributo: ahí viaja la NP y nada más
    out.textoNoViajaEnElAtributo = !!bn && String(bn.getAttribute("onclick") || "").indexOf("O'Higgins") < 0;
    const abiertasAntes = document.querySelectorAll("#pppPreview td.pga-ncont").length;
    if (bn) {
      bn.click();
      await esperar(() => !!modalTxt());
      const t = modalTxt();
      out.npModalTextoCompleto = t.indexOf(OBS1) >= 0;
      out.npModalNombraCliente = t.indexOf("Ricci Gabriel") >= 0;
      out.npModalSoloLectura = /s.lo lectura/i.test(t);
      out.npModalCierra = (cerrar(), !modalTxt());
    }
    out.npNoSeAbrioPorElBadge = document.querySelectorAll("#pppPreview td.pga-ncont").length === abiertasAntes;

    // (d) al abrir la NP, el comentario se ve solo
    pgaAbrirNp(F.d1C + "|E01A|LK 0058", "LK 0058");
    out.celdaAbierta = await esperar(() => !!document.querySelector("#pppPreview td.pga-ncont"));
    const celda = document.querySelector("#pppPreview td.pga-ncont");
    out.celdaTieneObs = !!(celda && celda.querySelector(".pga-nobs"));
    out.celdaTextoCompleto = !!celda && (celda.textContent || "").indexOf(OBS1) >= 0;

    /* (g) A PROGRAMAR: ahí el pedido todavía no tiene NP, así que la clave es empresa+pedido y el
       badge corta a 40 caracteres — sin pop-up, un comentario largo sólo se leía con el mouse. */
    const pedido = { empresa: "lk", order_id: 1515, razon_social: "El Gran Bazar", obs_pedido: OBS1 };
    if (!_apr.pedidosTodos) _apr.pedidosTodos = [];
    _apr.pedidosTodos.push(pedido);
    const hb = (typeof aprObsBadge === "function") ? aprObsBadge(pedido) : "";
    /* Se lee el atributo por DOM, no partiendo el string: el `title` SÍ lleva el texto (es el
       tooltip del escritorio) y buscarlo a ojo en el HTML da un falso positivo. */
    const _tmp = document.createElement("div"); _tmp.innerHTML = hb;
    const _sp = _tmp.querySelector(".apr-obs");
    const _oc = _sp ? String(_sp.getAttribute("onclick") || "") : "";
    out.aprBadgeClickeable = _oc.indexOf("aprObsAbrir") >= 0;
    out.aprBadgeSinTextoEnElAtributo = _oc.indexOf("Higgins") < 0;
    out.aprBadgeTrunca = hb.indexOf("…") >= 0;
    try { aprObsAbrir("lk", 1515); } catch (_e) { out.aprError = String(_e && _e.message || _e); }
    await esperar(() => !!modalTxt());
    const ta = modalTxt();
    out.aprModalCompleto = ta.indexOf(OBS1) >= 0;
    out.aprModalNombraPedido = /web LK 1515/.test(ta);
    cerrar();

    return out;
  }, { F: F, OBS1: OBS1, OBS2: OBS2 });

  await b.close();

  const fallas = [];
  const ok = (c, m) => { if (!c) fallas.push(m); };
  ok(r.diaBadge === "💬 2", "(c) el dia tenia que decir «💬 2» y dice: " + JSON.stringify(r.diaBadge));
  ok(r.diaModalTieneLas2, "(c) el pop-up del dia no trajo los dos comentarios");
  ok(r.diaModalNombraNps, "(c) el pop-up del dia no dice de que NP es cada comentario");
  ok(r.diaNoAbrio !== false, "(c) tocar el badge del dia abrio el dia");
  ok(r.hayTandas, "no se dibujaron las tandas");
  ok(r.tandaBadge === "💬 2", "(b) la tanda tenia que decir «💬 2» y dice: " + JSON.stringify(r.tandaBadge));
  ok(r.tandaModalTieneLas2, "(b) el pop-up de la tanda no trajo los dos comentarios");
  ok(r.tandaModalTitulo, "(b) el pop-up de la tanda no dice de que tanda es");
  ok(r.tandaSinObsNoDibuja, "(e) E02A no tiene comentarios y le dibujo el badge igual");
  ok(r.npsAntes === r.npsDespues, "(b) tocar el badge de la tanda la abrio o la cerro");
  ok(r.hayNps, "no se dibujaron las NP");
  ok(r.npBadge, "(a) la NP con comentario no trae badge");
  ok(r.npBadgeClickeable, "(a) el badge de la NP no llama a pgaObsAbrir: sigue siendo solo un tooltip");
  ok(r.npBadgeSinCursorHelp, "(a) el badge de la NP sigue con cursor:help");
  ok(r.npModalTextoCompleto, "(a) el pop-up no muestra el comentario completo");
  ok(r.npModalNombraCliente, "(a) el pop-up no dice de que cliente es");
  ok(r.npModalSoloLectura, "(a) el pop-up no aclara que es solo lectura");
  ok(r.npModalCierra, "(a) el pop-up no se cierra");
  ok(r.npNoSeAbrioPorElBadge, "(a) tocar el badge de la NP la abrio");
  ok(r.npSinObsNoDibuja, "(e) LK 0060 no tiene comentario y le dibujo el badge igual");
  ok(r.textoNoViajaEnElAtributo, "(f) el TEXTO del comentario esta metido en el onclick");
  ok(r.celdaAbierta && r.celdaTieneObs, "(d) al abrir la NP el comentario no aparece en la celda");
  ok(r.celdaTextoCompleto, "(d) el comentario de la celda esta truncado");
  ok(r.aprBadgeClickeable, "(g) el badge de A Programar no llama a aprObsAbrir");
  ok(r.aprBadgeSinTextoEnElAtributo, "(g) el TEXTO del comentario esta metido en el onclick de A Programar");
  ok(r.aprBadgeTrunca, "(g) el badge de A Programar dejo de truncar: entonces el pop-up no hace falta y este test miente");
  ok(!r.aprError, "(g) aprObsAbrir tiro: " + r.aprError);
  ok(r.aprModalCompleto, "(g) el pop-up de A Programar no muestra el comentario completo");
  ok(r.aprModalNombraPedido, "(g) el pop-up de A Programar no dice de que pedido es");
  ok(errs.length === 0, "hubo errores de JS: " + errs.join(" | "));

  if (fallas.length) { console.error("ppp-obs-boton: FALLA\n - " + fallas.join("\n - ")); process.exit(1); }
  console.log("ppp-obs-boton: OK — badge clickeable en NP, tanda y dia; texto completo en el pop-up y dentro de la NP.");
})();
