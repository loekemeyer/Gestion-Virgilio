/* v17.74 (Luis, 2026-09-14) — BADGE DE HORARIO en A Programar.
   Pedido: *"para todos esos clientes (excepto Distribuidora GM) + CL 3905 Andser Química,
   CL 1974 Rayabo, CL 2533 Osa Distribuidora + los clientes que marcan retirar, quiero que cuando
   aparecen en A Programar tengan un badge con horario. […] La persona que programa debería poder
   hacer click en ese badge y editar el día y horario manualmente ahí. Y ese dato debería viajar
   con el pedido a Programación."*
   Se chequea:
     (a) el badge sale SÓLO en los que coordinan horario (la lista + retira), no en un cliente común;
     (b) arranca en "----" cuando no hay dato, y muestra día + franja cuando lo hay;
     (c) si lo eligió el cliente en la página se distingue (verde) del cargado a mano;
     (d) tocarlo abre el pop-up y guardar llama a gv_pedido_horario_set con la clave correcta
         (order_id si es de la página, NP si es de ISIS);
     (e) vaciar los dos campos saca el horario;
     (f) el dato viaja a la tabla de Programación.
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
  const p = await b.newPage({ viewport: { width: 1400, height: 950 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {}, rpc = [];
    _apr.listo = true; _apr.tandas = []; _apr.items = {}; _apr.salida = {}; _apr.cuarResumen = [];
    _apr.cal = [{ dia: "2026-09-14", habil: true, m3: 1, tandas: 1, np: 2, cupo: 6, resta: 5, pasado: false }];
    // la lista de quién coordina horario, como la devuelve gv_clientes_horario
    _aprHorLista = { "lk:801": "Coto", "chef:2444": "Jumbo", "lk:4263": "Gigot",
                     "lk:3905": "Andser Quimica SRL", "lk:1974": "Rayabo S.A", "lk:2533": "Osa Distribuidora SRL" };
    _aprHorListaTs = Date.now();
    _aprHor = {
      "lk:1401": { fecha: "2026-09-18", franja: "08:00 a 12:00", origen: "manual" },
      "lk:1402": { fecha: "2026-09-19", franja: "14:00 a 18:00", origen: "cliente" }
    };
    _aprHorTs = Date.now();
    window.aprHorNeed = function () {};                      // ya está todo inyectado
    window.aprQuien = async function () { return "luis@x"; };
    window.aprRpc = async function (fn, args) { rpc.push({ fn: fn, args: args }); return null; };

    const mk = (o) => Object.assign({
      order_id: 1400, empresa: "lk", cod: "1000", razon_social: "Cliente Comun",
      zona: "Zona 1 - CABA Sur", fecha_recep: "2026-09-11", localidad: "Barracas",
      direccion: "Montes de Oca 1", m3: 0.4, m3_parcial: false, lineas: 2, cajas: 3, np_total: 1, bloques: []
    }, o);
    _apr.pedidos = [
      mk({ order_id: 1400, cod: "1000", razon_social: "Cliente Comun" }),                       // sin badge
      mk({ order_id: 1401, cod: "801",  razon_social: "Coto C.I.C.S.A." }),                     // súper, a mano
      mk({ order_id: 1402, cod: "4103", razon_social: "Villar Cristina", zona: "Retira",        // retira, del cliente
           turno_fecha: "2026-09-30", turno_hora: "09:00", turno_txt: "30/09/2026 09:00" }),      // v19.11: el de la persona MANDA sobre el de la OC
      mk({ order_id: 1403, cod: "3905", razon_social: "Andser Quimica SRL" }),                  // de los 3, sin dato
      mk({ order_id: 1404, cod: "4080", razon_social: "Distribuidora GM" }),                    // súper SIN horario
      mk({ order_id: "np98426", _isis: true, np: "98426", cod: "4263", razon_social: "Matiz SA" }), // ISIS, súper
      // v19.11 (Thomas) — EL TURNO QUE TRAE LA OC. INC no está en la lista de los que coordinan
      // horario: el badge sale igual porque el PEDIDO trae fecha y hora de entrega pactada.
      mk({ order_id: 1405, cod: "1651", razon_social: "Inc Sociedad Anonima", zona: "Super",
           turno_fecha: "2026-09-29", turno_hora: "14:00", turno_txt: "29/09/2026 14:00" })
    ];
    _apr.pedidosTodos = _apr.pedidos.slice();
    _pppTab = "prog";
    document.getElementById("pppOverlay").classList.add("show");
    aprRender(); await new Promise((res) => setTimeout(res, 250));
    const prev = document.getElementById("pppPreview");
    const badgeDe = (oid) => {
      const tr = [...prev.querySelectorAll(".apr-card")].find((c) => c.innerHTML.indexOf("aprSel('lk:" + oid + "')") >= 0);
      const e = tr && tr.querySelector(".apr-hor");
      return e ? { txt: e.textContent.trim(), cls: e.className } : null;
    };
    out.comunSinBadge = badgeDe(1400) === null;
    out.gmSinBadge    = badgeDe(1404) === null;
    out.coto  = badgeDe(1401);
    out.retira = badgeDe(1402);
    out.andser = badgeDe(1403);
    out.inc = badgeDe(1405);
    out.incTitle = (function () {
      const c = [...prev.querySelectorAll(".apr-card")].find((x) => x.innerHTML.indexOf("aprSel('lk:1405')") >= 0);
      const e = c && c.querySelector(".apr-hor");
      return e ? (e.getAttribute("title") || "") : "";
    })();
    out.retiraTxt = (badgeDe(1402) || {}).txt;
    out.isis = (function () {
      const c = [...prev.querySelectorAll(".apr-card")].find((x) => x.innerHTML.indexOf("NP 98426") >= 0);
      const e = c && c.querySelector(".apr-hor");
      return e ? { txt: e.textContent.trim(), cls: e.className } : null;
    })();

    // (d) tocar el badge abre el pop-up y guarda con la clave correcta
    aprHorAbrir("lk:1403"); await new Promise((res) => setTimeout(res, 120));
    const mh = (document.getElementById("aprHorModal") || {}).innerHTML || "";
    out.modal = /🕑 Horario/.test(mh) && /Andser Quimica SRL/.test(mh) &&
                /id="aprHorFecha"/.test(mh) && /id="aprHorFranja"/.test(mh);
    out.modalChips = /08:00 a 12:00/.test(mh) && (mh.match(/apr-hor-chip/g) || []).length >= 6;
    aprHorSet("fecha", "2026-09-22"); aprHorSet("franja", "12:00 a 16:00");
    await aprHorGuardar(false); await new Promise((res) => setTimeout(res, 150));
    const g = rpc.find((x) => x.fn === "gv_pedido_horario_set");
    out.guarda = !!g && g.args.p_empresa === "lk" && g.args.p_clave === "1403" &&
                 g.args.p_fecha === "2026-09-22" && g.args.p_franja === "12:00 a 16:00" &&
                 g.args.p_origen === "manual";
    out.cerro = !!(document.getElementById("aprHorModal") || {}).hidden;
    out.enPantalla = (badgeDe(1403) || {}).txt === "🕑 22/09 12:00 a 16:00";

    // la clave de una NP de ISIS es la NP, no el order_id falso
    rpc.length = 0;
    aprHorAbrir("lk:98426"); aprHorSet("franja", "Mañana");
    await aprHorGuardar(false); await new Promise((res) => setTimeout(res, 150));
    const gi = rpc.find((x) => x.fn === "gv_pedido_horario_set");
    out.claveIsis = !!gi && gi.args.p_clave === "98426" && gi.args.p_np === "NP 98426";

    // (g) v19.11 — el pop-up de un pedido con turno de OC abre con ESE turno puesto:
    // confirmar es un clic y recien ahi viaja a Programacion (que lee gv_pedido_horario).
    rpc.length = 0;
    aprHorAbrir("lk:1405"); await new Promise((res) => setTimeout(res, 120));
    out.ocPrefill = _aprHorEdit.fecha === "2026-09-29" && _aprHorEdit.franja === "14:00";
    await aprHorGuardar(false); await new Promise((res) => setTimeout(res, 150));
    const go = rpc.find((x) => x.fn === "gv_pedido_horario_set");
    out.ocGuarda = !!go && go.args.p_clave === "1405" && go.args.p_fecha === "2026-09-29" &&
                   go.args.p_franja === "14:00" && go.args.p_origen === "manual";

    // (e) vaciar = sacar el horario
    rpc.length = 0;
    aprHorAbrir("lk:1401");
    await aprHorGuardar(true); await new Promise((res) => setTimeout(res, 150));
    const gb = rpc.find((x) => x.fn === "gv_pedido_horario_set");
    out.vacia = !!gb && gb.args.p_fecha === null && gb.args.p_franja === null;
    out.vaciaEnPantalla = (badgeDe(1401) || {}).txt === "🕑 ----";

    // (f) y en Programación se ve, sin poder editarse
    _pgaRows = [{ fecha: "2026-09-18", tanda: "E01A", np: "LK 0049", np_num: 49, cod: "801",
                  razon_social: "Coto", localidad: "CABA", zona: "Super", zona_corta: "Súper",
                  empresa: "LK", origen: "web", m3: 2.2, estado: "pendiente", estado_orden: 1,
                  clave: "1373", pide_horario: true, horario_fecha: "2026-09-18",
                  horario_franja: "08:00 a 12:00", horario_origen: "manual" }];
    _pgaTs = Date.now(); window.pgaNeed = function () {};
    _pppParsed = { prog: [{ np: "98630", tanda: "D72B", fecha_entrega: "2026-09-14", m3: 1.8, cod: "1000", razon_social: "X", zona: "Zona 2", programmed: true }] };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    window.getTodayKey = () => "2026-09-14";
    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    pppRenderProg(); await new Promise((res) => setTimeout(res, 200));
    pgaAbrirDia("20260918"); await new Promise((res) => setTimeout(res, 120));
    pgaAbrirTanda("20260918|E01A"); await new Promise((res) => setTimeout(res, 150));
    const ph = document.getElementById("pppPreview").innerHTML;
    // v21.67 (Luis): en Programación el reloj también se EDITA (mismo pop-up que A Programar).
    out.enProgramacion = /apr-hor[^"]*" style="cursor:pointer" onclick="event\.stopPropagation\(\);pgaHorAbrir\([^>]*>🕑 18\/09 08:00 a 12:00</.test(ph);
    return out;
  });

  let ok = true;
  const t = (c, m) => { console.log((c ? "  ✅ " : "  ❌ ") + m); if (!c) ok = false; };
  t(r.comunSinBadge, "(a) un cliente común NO lleva badge");
  t(r.gmSinBadge, "(a) Distribuidora GM tampoco (es súper pero no coordina horario)");
  t(r.coto && /apr-hor/.test(r.coto.cls), "(a) un súper sí");
  t(r.retira && /apr-hor/.test(r.retira.cls), "(a) el que retira, también");
  t(r.andser && /apr-hor/.test(r.andser.cls), "(a) y los 3 de la lista aparte (Andser)");
  t(r.isis && /apr-hor/.test(r.isis.cls), "(a) vale igual para una NP de ISIS");
  t(r.andser && r.andser.txt === "🕑 ----" && /vacio/.test(r.andser.cls), "(b) sin dato muestra ----");
  t(r.coto && r.coto.txt === "🕑 18/09 08:00 a 12:00", "(b) con dato, día y franja — " + JSON.stringify(r.coto && r.coto.txt));
  t(r.retira && /apr-hor cli/.test(r.retira.cls), "(c) el que eligió el cliente se distingue");
  t(r.inc && /apr-hor/.test(r.inc.cls) && / oc/.test(r.inc.cls), "(g) el turno que trae la OC pinta el badge aunque el cliente no coordine horario");
  t(r.inc && r.inc.txt === "📅 29/09 14:00", "(g) con día Y hora — " + JSON.stringify(r.inc && r.inc.txt));
  t(/OC del pedido/.test(r.incTitle || "") && /29\/09\/2026 14:00/.test(r.incTitle || ""), "(g) y el title dice de dónde sale, con el texto crudo de la OC");
  t(r.retiraTxt === "🕑 19/09 14:00 a 18:00", "(g) un horario ya cargado MANDA sobre el de la OC — " + JSON.stringify(r.retiraTxt));
  t(r.ocPrefill, "(g) el pop-up abre con el turno de la OC ya puesto");
  t(r.ocGuarda, "(g) y confirmarlo lo guarda, asi viaja a Programacion");
  t(r.coto && !/ cli/.test(r.coto.cls), "(c) del cargado a mano");
  t(r.modal, "(d) tocar el badge abre el pop-up con día y franja");
  t(r.modalChips, "(d) con las franjas de siempre como atajo");
  t(r.guarda, "(d) guardar llama a gv_pedido_horario_set con la clave del pedido");
  t(r.cerro, "(d) y cierra el pop-up");
  t(r.enPantalla, "(d) el badge queda con el horario nuevo sin recargar");
  t(r.claveIsis, "(d) en una NP de ISIS la clave es la NP, no el order_id falso");
  t(r.vacia, "(e) 'Sacar el horario' manda los dos campos en null");
  t(r.vaciaEnPantalla, "(e) y el badge vuelve a ----");
  t(r.enProgramacion, "(f) el horario viaja, se ve en la tabla de Programación y se puede tocar para editarlo (v21.67)");
  t(errs.length === 0, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));

  await b.close();
  console.log(ok ? "\nOK apr-badge-horario" : "\nFALLÓ apr-badge-horario");
  process.exit(ok ? 0 : 1);
})();
