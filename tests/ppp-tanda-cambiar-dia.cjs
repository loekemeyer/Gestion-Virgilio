/* v19.11 (Thomas, 2026-09-16) — "📅 CAMBIAR DE DÍA" EN CADA TANDA DE LA TABLA.
   Pedido: *"PPP > Programación, vista tabla: quiero que agregues un botón a cada tanda que sea
   «Cambiar de día» y que te permita asignarla en un día diferente. Quiero que sea válido para la
   programación de entregas así como para los Pedidos atrasados"*.
   Se chequea:
     (a) la fila de la TANDA trae el botón, con ese texto, y tocarlo NO abre/cierra la tanda;
     (b) abre el pop-up de días con la tanda, cuántos pedidos y cuántos m³ — sacados del ÁRBOL
         (`_pgaRows`), no de `_pppParsed.prog`, que en atrasados está vacío;
     (c) elegir un día llama a gv_ppp_tanda_mover con la tanda, la fecha y p_forzar (la tanda está
         armada: el backend la rechazaría sin eso), cierra el pop-up y recarga el árbol;
     (d) si el backend contesta TANDA_EMPEZADA (el front no lo había detectado), se pregunta y se
         reintenta UNA vez con p_forzar = true;
     (e) el submódulo «Pedidos atrasados» tiene el MISMO botón, y ahí el pop-up cuenta los pedidos
         de `_patrRows` (día que ya pasó) — que es el caso que motivó el pedido.
   Estado inyectado; no pega contra la red. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.error("Playwright no encontrado."); process.exit(2); }
}
const _d = (n) => { const d = new Date(); d.setHours(12,0,0,0); d.setDate(d.getDate() + n);
  return d.getFullYear() + "-" + String(d.getMonth()+1).padStart(2,"0") + "-" + String(d.getDate()).padStart(2,"0"); };
/* v20.30 — las fechas del test son RELATIVAS A HOY. Estaban fijas (2026-09-16/17/18) y el test
   se cayo solo el 19/09, porque el front filtra los dias del pop-up contra la fecha REAL del
   sistema (`new Date()` en `_pppMovPintar`), no contra `getTodayKey()`, que el test si mockea:
   pasado el 18 no quedaba ningun dia para tocar y (c), (d) y (e) fallaban en cadena. Un test con
   fecha de vencimiento deja main en rojo sin que nadie sepa por que. */
const F = { hoy: _d(0), d1: _d(1), d2: _d(2), atr: _d(-5) };
F.hoyC = F.hoy.replace(/-/g, ""); F.d1C = F.d1.replace(/-/g, ""); F.d2C = F.d2.replace(/-/g, ""); F.atrC = F.atr.replace(/-/g, "");
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => r.abort());
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (F) => {
    const out = {}, rpc = [], confirms = [];
    window.__isSupervisor = true;
    window.confirm = function (t) { confirms.push(String(t || "")); return true; };
    window.alert = function () {};
    window.getTodayKey = () => F.hoy;
    window.pppSetStatus = function () {};
    window.pppLoadProgFromSupabase = async function () {};
    window._faltMiLegajo = () => "52";
    let recargas = 0;
    window.pgaNeed = function () {};
    window.patrNeed = function () {};
    window.pgaRecargar = function () { recargas++; };
    window._pppPlanAgrupar = function () { return { venc: [], byDay: new Map() }; };
    window.pppPaintTabs = function () {};
    // la vista clásica NO tiene NINGUNA de las dos tandas del test (E01A ni D72B): si el pop-up
    // leyera de acá —como hace `pppMoverAbrir`, el botón de la vista clásica— diría "0 pedidos · 0 m³".
    // La fila que va es sólo para que la pantalla no muestre el cartel de "Importá el Formato PPP".
    _pppParsed = { prog: [{ np: "98630", tanda: "D99Z", fecha_entrega: F.d2, m3: 1.8,
                            cod: "1", razon_social: "Otra", zona: "Zona 2", programmed: true }] };

    window.__falla = "";
    window.aprRpc = async function (fn, args) {
      rpc.push({ fn: fn, args: args });
      if (fn === "gv_ppp_web_calendario") {
        return [{ dia: F.hoy, m3: 2, cupo: 6, habil: true, tandas: 2 },
                { dia: F.d1, m3: 1, cupo: 6, habil: true, tandas: 1 },
                { dia: F.d2, m3: 0, cupo: 6, habil: true, tandas: 0 }];
      }
      if (fn === "gv_ppp_web_camion_nuevo") return [];
      // v19.32: el paso 2 del pop-up pregunta qué tandas hay ese día, ya juzgadas por el backend.
      if (fn === "gv_ppp_tandas_del_dia") {
        return [{ tanda: "E18A", m3: 1.1, nps: 3, clientes: 2, estado: "armado", orden: 3,
                  zonas: "Zona 2", camiones: "Capital", es_super: false, compatible: true,
                  motivo: null, aviso: null },
                { tanda: "E30A", m3: 0.4, nps: 1, clientes: 1, estado: "pendiente", orden: 1,
                  zonas: "Zona 5", camiones: "GBA Oeste", es_super: true, compatible: false,
                  motivo: "Esa tanda esta pendiente y lo que moves esta armado. Solo se juntan tandas en el mismo estado.",
                  aviso: "Esa tanda es de un SUPER y lo que moves no: los super van solos, sin clientes comunes." }];
      }
      if (fn === "gv_ppp_tanda_mover") {
        if (window.__falla && !args.p_forzar) {
          window.__falla = "";
          throw new Error("TANDA_EMPEZADA: la tanda E01A ya tiene 11 evento(s) de operarios (pickeada o armada).");
        }
        return [{ movidas: 2, np_web: 2, np_isis: 0, m3: 1.5, aviso: null, empezada: true }];
      }
      return [];
    };

    const mk = (fecha, tanda, np, est, m3) => ({ fecha: fecha, tanda: tanda, np: np, np_num: 58,
      cod: "2118", razon_social: "Ricci Gabriel", localidad: "CABA", zona: "Zona 2",
      zona_corta: "Zona 2", empresa: "LK", origen: "web", m3: m3, estado: est, estado_orden: 3,
      barrio: "Villa Crespo", fecha_pedido: "2026-09-11" });
    _pgaRows = [mk(F.d1, "E01A", "LK 0058", "armado", 1.2),
                mk(F.d1, "E01A", "LK 0059", "armado", 0.3)];
    _pgaTs = Date.now();
    _patrRows = [mk(F.atr, "D72B", "44612", "facturado", 0.8)];
    _patrTs = Date.now();

    const esperar = async function (fn, ms) {
      const t0 = Date.now();
      // v21.49 — 4 s alcanzaban en una máquina libre y NO en un runner de CI ni con otros
      // chromium corriendo al lado: el paso 2 no llegaba a dibujarse, querySelector daba null
      // y el test moría con "Cannot read properties of null". No es un test roto, es una
      // carrera: corriendo solo pasa 5 de 5. El que espera es el test, así que espera más.
      while (Date.now() - t0 < (ms || 15000)) { if (fn()) return true; await new Promise((res) => setTimeout(res, 40)); }
      return false;
    };
    const filaTanda = function (txt) {
      const pv = document.getElementById("pppPreview"); if (!pv) return null;
      return [...pv.querySelectorAll("tr.pga-t")].find((x) => x.textContent.indexOf(txt) >= 0) || null;
    };

    _pppTab = "plan"; _pppPlanTabla = true; _pppPlanDay = null;
    document.getElementById("pppOverlay").classList.add("show");
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.pga"));
    pgaAbrirDia(F.d1C);
    out.hayFilaTanda = await esperar(() => !!filaTanda("E01A"));

    // (a) el botón está en la fila de la tanda y no abre la tanda
    let f = filaTanda("E01A");
    let bt = f && f.querySelector(".pga-acc-b.dia");
    out.hayBoton = !!bt;
    out.textoBoton = bt ? bt.textContent.trim() : "";
    out.titleBoton = bt ? (bt.getAttribute("title") || "") : "";
    out.npsAntes = document.querySelectorAll("#pppPreview tr.pga-n").length;
    if (!bt) { out.dump = (document.getElementById("pppPreview") || {}).innerHTML ? document.getElementById("pppPreview").innerHTML.slice(0, 2500) : "(sin preview)"; return out; }
    bt.click();
    await esperar(() => document.getElementById("pppMovOverlay") && document.getElementById("pppMovOverlay").classList.contains("show"));
    out.npsDespues = document.querySelectorAll("#pppPreview tr.pga-n").length;

    // (b) el pop-up, con los datos del árbol
    const ov = document.getElementById("pppMovOverlay");
    out.popupAbierto = !!ov && ov.classList.contains("show");
    out.titulo = (document.getElementById("pppMovTitle") || {}).textContent || "";
    await esperar(() => (document.querySelectorAll("#pppMovBody .mv-d") || []).length > 0);
    out.sub = (document.querySelector("#pppMovBody .mv-sub") || {}).textContent || "";
    out.pidioCalendario = rpc.some((x) => x.fn === "gv_ppp_web_calendario");

    // (c) elegir un día → mueve con p_forzar (la tanda está armada) y recarga el árbol
    rpc.length = 0; confirms.length = 0;
    // se busca por el ISO del onclick, no por el numero del dia: con fechas relativas el numero
    // puede coincidir con un m3 o un cupo del mismo boton.
    const diaD2 = [...document.querySelectorAll("#pppMovBody .mv-d")]
      .find((x) => String(x.getAttribute("onclick") || "").indexOf(F.d2) >= 0);
    if (!diaD2) { out.__diasOfrecidos = [...document.querySelectorAll("#pppMovBody .mv-d")].map((x) => x.getAttribute("onclick")); return out; }
    // v19.32: el dia ya no mueve nada — abre el PASO 2, «en que tanda?».
    // v21.49 — el click se REINTENTA: bajo carga (o sea, en CI) a veces no abria el paso 2 y
    // el querySelector de abajo daba null, con lo que el test moria con "Cannot read properties
    // of null". Subir la espera a 15 s no alcanzo: no es que tarde, es que ese click se pierde.
    // Con tres intentos, un paso 2 que de verdad no se dibuje sigue fallando — no se tapa nada.
    for (let i = 0; i < 3; i++) {
      diaD2.click();
      if (await esperar(() => !!document.querySelector("#pppMovBody .mv-esp-b.nueva"), 8000)) break;
    }
    out.paso2 = !!document.querySelector("#pppMovBody .mv-esp-b.nueva");
    out.pidioTandas = rpc.some((x) => x.fn === "gv_ppp_tandas_del_dia");
    const dests = [...document.querySelectorAll("#pppMovBody .mv-dest")];
    out.destOk = dests.some((b) => /E18A/.test(b.textContent) && !b.disabled);
    out.destNo = dests.some((b) => /E30A/.test(b.textContent) && b.disabled);
    out.destMotivo = /mismo estado/.test((dests.find((b) => /E30A/.test(b.textContent)) || {}).textContent || "");
    out.destAviso = !!document.querySelector("#pppMovBody .mv-dest-av");
    document.querySelector("#pppMovBody .mv-esp-b.nueva").click();
    await esperar(() => rpc.some((x) => x.fn === "gv_ppp_tanda_mover"));
    const arg = (rpc.find((x) => x.fn === "gv_ppp_tanda_mover") || {}).args || {};
    out.argMover = JSON.stringify({ t: arg.p_tanda, f: arg.p_fecha, forzar: arg.p_forzar, dest: arg.p_tanda_destino });
    out.confirmDiceArmada = confirms.join(" ").indexOf("pickeada o armada") >= 0;
    out.confirmDiceNoRepickear = confirms.join(" ").toLowerCase().indexOf("no hay que volver a pickear") >= 0;
    await esperar(() => recargas > 0);
    out.recargoElArbol = recargas > 0;
    out.popupCerrado = !document.getElementById("pppMovOverlay").classList.contains("show");

    // (d) el backend contesta TANDA_EMPEZADA → pregunta y reintenta con p_forzar
    rpc.length = 0; confirms.length = 0; window.__falla = "1";
    await pppTandaMover("E01A", F.d2, { filas: _pgaRows, empezada: false, desdeArbol: true });
    const mov = rpc.filter((x) => x.fn === "gv_ppp_tanda_mover");
    out.reintentos = mov.length;
    out.forzoAlReintentar = mov.length === 2 && mov[0].args.p_forzar === false && mov[1].args.p_forzar === true;
    out.pregunto = confirms.filter((c) => c.indexOf("TANDA_EMPEZADA") < 0 && c.indexOf("La movemos igual") >= 0).length === 1;

    // (e) el mismo botón en «Pedidos atrasados», con los pedidos de ESE día
    try { localStorage.setItem("vir_patr_colapsado", "0"); } catch (_e) {}
    pppRenderProg();
    await esperar(() => !!document.querySelector("#pppPreview table.patr-tbl"));
    pgaAbrirDia(F.atrC);
    out.hayFilaAtrasada = await esperar(() => !!filaTanda("D72B"));
    const fa = filaTanda("D72B");
    const bta = fa && fa.querySelector(".pga-acc-b.dia");
    out.botonEnAtrasados = !!bta;
    out.enTablaAtrasados = !!(fa && fa.closest("table.patr-tbl"));
    rpc.length = 0;
    bta.click();
    await esperar(() => document.getElementById("pppMovOverlay").classList.contains("show"));
    out.tituloAtr = (document.getElementById("pppMovTitle") || {}).textContent || "";
    await esperar(() => (document.querySelector("#pppMovBody .mv-sub") || {}).textContent);
    out.subAtr = (document.querySelector("#pppMovBody .mv-sub") || {}).textContent || "";

    out.errs = [];
    return out;
  }, F);

  const fallas = [];
  const ok = (c, txt, extra) => { console.log((c ? "ok  " : "FALLA") + " " + txt + (extra ? " — " + extra : "")); if (!c) fallas.push(txt); };

  if (!r.hayBoton) console.log("DUMP:", (r.dump||"").slice(0,1200));
  ok(r.hayFilaTanda, "la tabla dibuja la fila de la tanda");
  ok(r.hayBoton, "(a) cada tanda trae el botón");
  ok(/Cambiar de d[ií]a/.test(r.textoBoton), "(a) y dice «Cambiar de día»", JSON.stringify(r.textoBoton));
  ok(/TODA la tanda/.test(r.titleBoton), "(a) el tooltip avisa que mueve la tanda entera");
  ok(r.npsAntes === 0 && r.npsDespues === 0, "(a) tocarlo NO despliega la tanda", r.npsAntes + "→" + r.npsDespues);
  ok(r.popupAbierto, "(b) abre el pop-up de días");
  ok(/Cambiar de d[ií]a/.test(r.titulo) && /E01A/.test(r.titulo), "(b) con la tanda en el título", JSON.stringify(r.titulo));
  ok(/2/.test(r.sub) && /1,5|1\.5/.test(r.sub), "(b) y con sus pedidos y m³, sacados del árbol", JSON.stringify(r.sub));
  ok(r.pidioCalendario, "(b) pide el calendario con los m³ y el cupo de cada día");
  ok(r.paso2, "(c) elegir el día abre el paso 2 («¿en qué tanda?») y todavía no mueve nada");
  ok(r.pidioTandas, "(c) y le pregunta al backend qué tandas hay ese día (gv_ppp_tandas_del_dia)");
  ok(r.destOk, "(c) la tanda compatible se puede elegir");
  ok(r.destNo && r.destMotivo, "(c) la incompatible queda apagada y dice por qué (la regla de estados de Luis)");
  ok(r.destAviso, "(c) y el aviso de súper / camión distinto se ve, sin bloquear");
  ok(r.argMover === JSON.stringify({ t: "E01A", f: F.d2, forzar: true, dest: "" }),
     "(c) elegir «tanda nueva» mueve la tanda al día tocado, forzando porque está armada", r.argMover);
  ok(r.confirmDiceArmada && r.confirmDiceNoRepickear, "(c) y el confirm avisa que está armada y que no hay que volver a pickear");
  ok(r.recargoElArbol, "(c) recarga el árbol y los atrasados (tienen caché propio)");
  ok(r.popupCerrado, "(c) y cierra el pop-up");
  ok(r.reintentos === 2 && r.forzoAlReintentar, "(d) si el backend dice TANDA_EMPEZADA, reintenta una vez con p_forzar", "intentos " + r.reintentos);
  ok(r.pregunto, "(d) preguntando antes, con el motivo del backend");
  ok(r.hayFilaAtrasada && r.enTablaAtrasados, "(e) Pedidos atrasados dibuja su fila de tanda");
  ok(r.botonEnAtrasados, "(e) y tiene el MISMO botón");
  ok(/D72B/.test(r.tituloAtr), "(e) que abre el pop-up de esa tanda", JSON.stringify(r.tituloAtr));
  ok(/0,8|0\.8/.test(r.subAtr), "(e) con los m³ del día que ya pasó (los de _patrRows)", JSON.stringify(r.subAtr));
  ok(errs.length === 0, "sin errores de página", errs.join(" | "));

  await b.close();
  if (fallas.length) { console.error("\nppp-tanda-cambiar-dia: " + fallas.length + " falla(s)."); process.exit(1); }
  console.log("\nppp-tanda-cambiar-dia OK");
})();
