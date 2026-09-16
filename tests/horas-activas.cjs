/* v19.23 — SÓLO SE CUENTAN LAS HORAS ACTIVAS (pedido de Luis, 16/09).

   Textual: *"debería solo contar horas activas. si está 1 hora pickeando algo, termina el
   día y después de 14 horas comienza el siguiente día y en 30min de trabajo lo cierra,
   tardó 1:30hs y no 15:30"*.

   El monitor ya lo hacía (`computeClosureDur`). Lo que medía reloj era todo lo demás:
     · el cartel de "duración absurda" al cerrar → decía 16 h y trataba un cierre normal
       de la mañana siguiente como un olvido (y cancelarlo perdía el cierre);
     · el tablero de Inconsistencias → lo listaba como "duración absurda";
     · las vistas de productividad de Supabase → peor: lo descartaban entero, así que no
       contaba 15:30 ni 1:30, contaba CERO, y se llevaba los m³ (eso se arregló en SQL,
       `sql/gv_productividad_horas_activas_v1923.sql`).

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: "[]" }));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};
    const ev = window.eval;
    const h = (ms) => Math.round(ms / 360000) / 10;   // ms → horas con 1 decimal

    /* ======== (A) el ejemplo de Luis, tal cual: 1 h + 30 min = 1,5 h ======== */
    // martes 16:00 → miércoles 08:30, jornada 08-17 (el legajo no tiene horario cargado)
    const ini = new Date("2026-09-15T16:00:00-03:00").getTime();
    const fin = new Date("2026-09-16T08:30:00-03:00").getTime();
    out.A_existe = typeof businessDurBetweenMs === "function";
    out.A_da_1_5 = h(businessDurBetweenMs("999996", ini, fin)) === 1.5;
    out.A_no_da_16_5 = h(businessDurBetweenMs("999996", ini, fin)) !== 16.5;
    // mismo día: se cuenta tal cual, sin recortes
    out.A_mismo_dia_intacto = h(businessDurBetweenMs("999996",
      new Date("2026-09-16T09:00:00-03:00").getTime(),
      new Date("2026-09-16T11:30:00-03:00").getTime())) === 2.5;
    // el fin de semana del medio no cuenta: viernes 16:00 → lunes 08:30 sigue siendo 1,5 h
    out.A_finde_no_cuenta = h(businessDurBetweenMs("999996",
      new Date("2026-09-11T16:00:00-03:00").getTime(),
      new Date("2026-09-14T08:30:00-03:00").getTime())) === 1.5;
    // un día hábil entero en el medio sí suma una jornada (9 h): mié 16 → vie 8:30
    out.A_dia_habil_suma = h(businessDurBetweenMs("999996",
      new Date("2026-09-16T16:00:00-03:00").getTime(),
      new Date("2026-09-18T08:30:00-03:00").getTime())) === 10.5;

    /* ======== (B) al cerrar, el cartel mide activo y ya no asusta de gratis ======== */
    const LEG = "999996";
    let preguntado = "", alertado = "";
    const _oc = window.confirm, _oa = window.alert;
    window.confirm = function (m) { preguntado = String(m || ""); return true; };
    window.alert   = function (m) { alertado   = String(m || ""); };
    window.getActivityStatus = async function () {
      return { pickingStarted: new Set(), pickingDone: new Set(), pickingDoneStrict: new Set(),
               armadoStarted: new Set(), armadoDone: new Set(), armadoDoneStrict: new Set(),
               pickingEnCursoBy: new Map(), pickingEnCursoTs: new Map(),
               armadoEnCursoBy: new Map(), armadoEnCursoTs: new Map() };
    };
    ev("window.__enc4 = []; window.__raw4 = _enqueueReportRaw;" +
       "_enqueueReportRaw = function (pl) { window.__enc4.push(pl); };" +
       "window.__try4 = trySendOneReport; trySendOneReport = async function () { return { ok:false }; };" +
       "window.__oPub4 = askPickUbicacion; askPickUbicacion = async function () { return 'Mesa 1'; };");

    function abrirPicking(tanda, iniIso) {
      const st = getLegajoState(LEG);
      st.picking = { active: true, value: tanda, ts_inicio: iniIso };
      st.armado = null;
      setLegajoState(LEG, st);
      try { legajoInput.value = LEG; } catch (_e) {}
      try { textInput.value = tanda; } catch (_e) {}
      ev("selected = 'TP';");
    }

    /* Un picking abierto AYER a las 16:45 y cerrado ahora. ⚠ Las aserciones NO pueden
       depender de la hora a la que corre el test: si son las 21:00 el tramo de HOY son
       13 h trabajadas de verdad y el cartel tiene que salir. Lo que se prueba es la
       INVARIANTE: el cartel sale si y sólo si las horas ACTIVAS pasan el umbral, y el
       número que muestra es el activo, nunca el de reloj. */
    const ayer1645 = new Date(Date.now() - 24 * 3600000);
    ayer1645.setHours(16, 45, 0, 0);
    const _iniB = ayer1645.getTime();
    window.__enc4.length = 0; preguntado = ""; alertado = "";
    abrirPicking("Z96A", ayer1645.toISOString());
    const _antes = Date.now();
    await send();
    const _activoH = businessDurBetweenMs(LEG, _iniB, _antes) / 3600000;
    const _relojH  = (_antes - _iniB) / 3600000;
    out._activoH = Math.round(_activoH * 10) / 10;
    out._relojH  = Math.round(_relojH * 10) / 10;
    out.B_coherente = (_activoH > 8) === (preguntado !== "");
    // el activo SIEMPRE es menor que el reloj cuando cruza la noche
    out.B_activo_menor_que_reloj = _activoH < _relojH;
    // y si preguntó, cita las horas ACTIVAS y no las de reloj
    out.B_cita_activas = preguntado === "" ||
      (preguntado.indexOf(_activoH.toFixed(1) + " h") >= 0 &&
       preguntado.indexOf(_relojH.toFixed(1) + " h") < 0);
    out.B_cerro = window.__enc4.filter(x => x.opcion === "TP").length === 1;
    /* Y el ts_inicio que viaja sigue siendo el REAL (la hora no se toca: lo que cambia es
       cómo se MIDE, no lo que se guarda). */
    const _tp = window.__enc4.filter(x => x.opcion === "TP")[0] || {};
    out.B_ts_inicio_intacto = _tp.ts_inicio_iso === ayer1645.toISOString();

    /* Un olvido de verdad: abierto hace 20 días → muchas horas ACTIVAS → sí pregunta,
       y el texto dice "TRABAJADAS" y "sin contar la noche". */
    window.__enc4.length = 0; preguntado = "";
    abrirPicking("Z96B", new Date(Date.now() - 20 * 24 * 3600000).toISOString());
    await send();
    out.C_pregunta_el_olvido = preguntado.indexOf("lleva") >= 0;
    out.C_dice_trabajadas   = preguntado.indexOf("TRABAJADAS") >= 0;
    out.C_dice_sin_la_noche = preguntado.indexOf("sin contar la noche") >= 0;

    /* Y si lo cancela, ahora se lo dice (antes volvía mudo — problema 365). */
    window.confirm = function () { return false; };
    window.__enc4.length = 0; alertado = "";
    abrirPicking("Z96C", new Date(Date.now() - 20 * 24 * 3600000).toISOString());
    await send();
    out.D_cancelar_no_emite = window.__enc4.filter(x => x.opcion === "TP").length === 0;
    out.D_cancelar_avisa    = alertado.indexOf("NO se cerró") >= 0 && alertado.indexOf("Z96C") >= 0;

    /* ======== (E) Inconsistencias mide activo, no reloj ======== */
    // El cálculo vive dentro del renderizador; se verifica que use el helper y que el
    // umbral no se aplique más sobre la resta cruda.
    const src = String(window.__incSrc || "");
    out.E_usa_helper = src === "" ? true : true;   // (se chequea abajo con el fuente real)

    ev("window.__oPubRestore = 1;" +
       "_enqueueReportRaw = window.__raw4; trySendOneReport = window.__try4;" +
       "askPickUbicacion = window.__oPub4;" +
       "delete window.__raw4; delete window.__try4; delete window.__enc4; delete window.__oPub4;");
    window.confirm = _oc; window.alert = _oa;
    try {
      const m = JSON.parse(localStorage.getItem("legajo_state_virgilio_v1") || "{}");
      delete m[LEG]; localStorage.setItem("legajo_state_virgilio_v1", JSON.stringify(m));
    } catch (_e) {}
    return out;
  });

  /* (E) sobre el fuente: el tablero de Inconsistencias tiene que medir con
     businessDurBetweenMs cuando el cierre cruza el día, no con la resta cruda. */
  const fs = require("fs");
  const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
  const iInc = src.indexOf("INC_DUR_CORE_MAX_MIN) add(");
  const bloque = iInc > 0 ? src.slice(Math.max(0, iInc - 1400), iInc) : "";
  r.E_incons_usa_activo = /businessDurBetweenMs\(leg, _iniMs, _finMs\)/.test(bloque);
  r.E_incons_avisa_cruce = /activas \(se abri/.test(src.slice(iInc, iInc + 400));
  // y el cartel del cierre ya no arma el texto con la resta pelada
  r.E_cierre_sin_reloj = !/está abierto hace " \+ _durH/.test(src);
  delete r.E_usa_helper;

  // las claves con "_" adelante son informativas (números medidos), no aserciones
  const claves = Object.keys(r).filter(k => k.charAt(0) !== "_");
  const malas = claves.filter(k => r[k] !== true);
  const pass = malas.length === 0 && errs.length === 0;
  for (const k of claves) console.log((r[k] === true ? "ok  " : "FAIL") + "   " + k);
  if (r._activoH != null) console.log("     (medido: " + r._activoH + " h activas contra " + r._relojH + " h de reloj)");
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  console.log("\nhoras-activas: " + (pass ? "OK" : "FAIL (" + malas.join(", ") + ")"));
  await b.close(); process.exit(pass ? 0 : 1);
})();
