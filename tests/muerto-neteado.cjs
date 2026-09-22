/* v19.07 — dos reglas que pidió Luis el 16/09 y una que verificó.

   (A) TIEMPO MUERTO NETEADO. "Si arma 1 h, va al baño 10 min y arma 50 min más, debería ser
       1 h 50 de armado y 10 de baño, cada uno contado individual." Hasta la v19.02 NO se
       restaba en ningún lado: `DEAD_TIME_CODES` sólo bloqueaba botones y `computeClosureDur`
       partía el cruce de día sin descontar nada. Problema 349.
   (B) NO CERRAR DOS VECES. Si el servidor ya tiene el TP/TAP de esa tanda (típico: sistemas
       la destrabó a mano por SQL), el celular no la cierra de nuevo: limpia el estado local
       y avisa. Caso E09A, dos TAP del mismo trabajo con el mismo ts_inicio. Problema 348.

   `computeClosureDur` es una closure dentro de `fetchMonitorDayStats`, así que no se la puede
   llamar desde afuera: se prueba el COMPORTAMIENTO a través de la función pública, con la red
   interceptada para devolver eventos armados a mano. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

const DIA = "2026-09-16";
const iso = (h) => "2026-09-16T" + h + "-03:00";

// El escenario del ejemplo de Luis, tal cual: armado de 2 h de punta a punta con un baño
// de 10 min adentro → 1 h 50 de armado y 10 min de baño.
const EVENTOS = [
  { opcion: "AP",  texto: "Z01A", legajo: "700", ts_cliente: iso("09:00:00"), ts_inicio: null },
  { opcion: "PB",  texto: "",     legajo: "700", ts_cliente: iso("10:10:00"), ts_inicio: iso("10:00:00") },
  { opcion: "TAP", texto: "Z01A", legajo: "700", ts_cliente: iso("11:00:00"), ts_inicio: iso("09:00:00") },
  // control: otro armado del mismo día SIN nada adentro → no se le toca un minuto
  { opcion: "AP",  texto: "Z01B", legajo: "700", ts_cliente: iso("11:05:00"), ts_inicio: null },
  { opcion: "TAP", texto: "Z01B", legajo: "700", ts_cliente: iso("12:05:00"), ts_inicio: iso("11:05:00") }
];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));

  // Interceptar Supabase ANTES de cargar: la app no debe pegarle a la base de verdad.
  await p.route("**/rest/v1/**", (route) => {
    const u = route.request().url();
    let body = "[]";
    if (u.indexOf("Registros_Produccion_Virgilio") >= 0 && u.indexOf("opcion=eq.FJ") < 0) body = JSON.stringify(EVENTOS);
    route.fulfill({ status: 200, contentType: "application/json", body: body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async (args) => {
    const out = {};
    const DIA = args.dia;

    /* ===================== (A) el tiempo muerto se resta ===================== */
    // Sin sheet de m³ el cálculo de duración corre igual (es lo que se mide acá).
    let stats = null;
    try { stats = await fetchMonitorDayStats(DIA, new Map()); }
    catch (e) { out.A_corrio = "ERROR: " + e.message; }
    out.A_corrio = !!stats;
    const op = (stats && stats.perOperario || []).filter(x => String(x.legajo) === "700")[0] || null;
    out.A_encontro_operario = !!op;
    if (op) {
      // Z01A: 2 h brutas − 10 min de baño = 110 min. Z01B: 60 min enteros. Total 170.
      const armMin = Math.round((op.armH || 0) * 60);
      out.A_total_170 = armMin === 170;
      out.A_no_es_180 = armMin !== 180;         // 180 = el número viejo, sin netear
      out._armMin = armMin;
      // el detalle de cada tanda tiene que decir cuánto era y cuánto se descontó
      const det = op.armedDetail || [];
      const a = det.filter(d => d.tanda === "Z01A")[0], bb = det.filter(d => d.tanda === "Z01B")[0];
      out.A_Z01A_110 = !!(a && Math.round(a.durMs / 60000) === 110);
      out.A_Z01A_bruto_120 = !!(a && a.breakdown && Math.round(a.breakdown.brutoMs / 60000) === 120);
      out.A_Z01A_muerto_10 = !!(a && a.breakdown && Math.round(a.breakdown.muertoMs / 60000) === 10);
      out.A_Z01B_intacta   = !!(bb && Math.round(bb.durMs / 60000) === 60
                              && bb.breakdown && Math.round(bb.breakdown.muertoMs / 60000) === 0);
      /* El baño sigue contándose aparte: 10 min. Eso es el "cada uno contado
         individual" del pedido de Luis — se resta del armado Y se suma en su
         propio casillero, no desaparece.
         ⚠ v21.18 (Damián): ese casillero ya NO es `movMin`. Hasta la v21.17 el
         baño, el timbre y la limpieza se sumaban junto con el guardado a góndola
         y la recepción, o sea que "movimiento de mercadería" incluía ir al baño.
         Ahora son dos baldes y el baño va en `noprodMin`; `movMin` tiene que
         quedar en CERO, que es lo que prueba que la separación existe de verdad
         y no es sólo un renombre. */
      out.A_bano_aparte     = Math.round(op.noprodMin || 0) === 10;
      out.A_bano_no_es_mov  = Math.round(op.movMin || 0) === 0;
    }

    /* ============ (B) no volver a cerrar lo que el server ya cerró ============ */
    // `send()` consulta getActivityStatus(); le devolvemos la tanda como YA terminada.
    const _origStatus = window.getActivityStatus;
    let alertado = "";
    const _origAlert = window.alert;
    window.alert = function (m) { alertado = String(m || ""); };
    const encolado = [];
    const ev = window.eval;
    ev("window.__enc2 = []; window.__raw2 = _enqueueReportRaw; _enqueueReportRaw = function (pl) { window.__enc2.push(pl); };");

    /* `send("TAP")` pasa antes por dos cosas que abren modales/red y que acá no se están
       probando: el chequeo de Entregas del asistente «Completar» y la pregunta de en qué
       ubicación quedó la tanda. Se stubean para llegar al guard nuevo. */
    ev("window.__origComp = (typeof _compTandaYaArmada === 'function') ? _compTandaYaArmada : null;" +
       "_compTandaYaArmada = async function () { return true; };" +
       "window.__origUbic = askArmadoUbicaciones;" +
       "askArmadoUbicaciones = async function () { return {}; };");

    window.getActivityStatus = async function () {
      return {
        pickingStarted: new Set(), pickingDone: new Set(["Z09Z"]), pickingDoneStrict: new Set(),
        armadoStarted: new Set(),  armadoDone: new Set(["Z09Z"]),  armadoDoneStrict: new Set(),
        pickingEnCursoBy: new Map(), pickingEnCursoTs: new Map(),
        armadoEnCursoBy: new Map(),  armadoEnCursoTs: new Map()
      };
    };
    const LEG = "999998";
    let st = getLegajoState(LEG);
    /* ⚠ El ts_inicio va RELATIVO a ahora, no a una hora fija. Con una hora fija el test
       era dependiente del reloj: a las 17:00 un ts_inicio de las 09:00 da 8 h de armado y
       salta el confirm() de "duración absurda" (v12.99), que Playwright cancela solo → el
       TAP no se emite y el control fallaba sin que nada estuviera roto. 30 min nunca lo
       dispara. */
    const _iniCerca = new Date(Date.now() - 30 * 60000).toISOString();
    st.armado = { active: true, value: "Z09Z", ts_inicio: _iniCerca };
    st.continuar = { Armado: "2026-09-16" };
    setLegajoState(LEG, st);
    try { legajoInput.value = LEG; } catch (_e) {}
    try { textInput.value = "Z09Z"; } catch (_e) {}

    // `send()` no toma argumentos: lee `selected` (global, `let` → por eval) y los inputs.
    ev("selected = 'TAP';");
    await send();
    out.B_no_emitio   = window.__enc2.filter(x => x.opcion === "TAP").length === 0;
    out.B_avisó       = alertado.indexOf("YA figura terminado") >= 0 && alertado.indexOf("Z09Z") >= 0;
    out.B_limpió      = !(getLegajoState(LEG).armado || {}).active;
    out.B_saco_marca  = !((getLegajoState(LEG).continuar || {}).Armado);

    // control: una tanda que el server NO tiene cerrada SÍ se emite
    window.__enc2.length = 0; alertado = "";
    st = getLegajoState(LEG);
    st.armado = { active: true, value: "Z08Z", ts_inicio: _iniCerca };
    setLegajoState(LEG, st);
    try { textInput.value = "Z08Z"; } catch (_e) {}
    ev("selected = 'TAP';");
    await send();
    out.B_control_emite = window.__enc2.filter(x => x.opcion === "TAP").length === 1;

    window.getActivityStatus = _origStatus;
    window.alert = _origAlert;
    ev("_enqueueReportRaw = window.__raw2; delete window.__raw2; delete window.__enc2;" +
       "if (window.__origComp) _compTandaYaArmada = window.__origComp;" +
       "askArmadoUbicaciones = window.__origUbic;" +
       "delete window.__origComp; delete window.__origUbic;");
    try {
      const m = JSON.parse(localStorage.getItem("legajo_state_virgilio_v1") || "{}");
      delete m[LEG]; localStorage.setItem("legajo_state_virgilio_v1", JSON.stringify(m));
    } catch (_e) {}
    return out;
  }, { dia: DIA });

  const claves = Object.keys(r).filter(k => k.charAt(0) !== "_");
  const malas = claves.filter(k => r[k] !== true);
  const pass = malas.length === 0 && errs.length === 0;
  for (const k of claves) console.log((r[k] === true ? "ok  " : "FAIL") + "   " + k + (r[k] === true ? "" : "  → " + JSON.stringify(r[k])));
  if (r._armMin != null) console.log("     (armado medido: " + r._armMin + " min)");
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  console.log("\nmuerto-neteado: " + (pass ? "OK" : "FAIL (" + malas.join(", ") + ")"));
  await b.close(); process.exit(pass ? 0 : 1);
})();
