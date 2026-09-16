/* v19.02 — tres cosas que reportó Luis el 16/09 sobre el Resumen del día del operario:

   (A) RELOJ DE 24 h. `toLocaleString("es-AR")` sin opciones deja el ciclo horario a
       criterio del dispositivo, y el WebView de varios Android resuelve es-AR a 12 h SIN
       a.m./p.m.: las 13:34 salían "01:34" y el registro parecía de la madrugada. El dato
       en la base estaba bien (skew con el server = 0 s). Problema 344.
   (B) UN RENGLÓN POR TAREA. Un toggle deja dos filas (apertura + cierre) rotuladas igual,
       así que un baño de 2 min se leía como dos baños. Ahora el cierre absorbe su
       apertura y muestra "Desde … hasta … (dur)"; la apertura sin cierre queda marcada
       `_abierto` para que se VEA. Problema 345.
   (C) CIERRE DE RI/EI. `closeIns` bajaba el flag local con `toggleStartOrEnd` (que sólo
       toca localStorage) y el cierre nunca salía al server → 20 toggles de insumos
       abiertos entre el 07/09 y el 16/09. Ahora emite el cierre con el total cargado,
       salvo cuando la sesión se ANULA (ahí la apertura ya se borró del server).
       Problema 347.

   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }

(async () => {
  const b = await chromium.launch();
  // Locale/TZ del dispositivo a propósito RAROS: si el formateo dependiera del celular,
  // (A) se rompe acá. Es exactamente el caso del Samsung de Jhonny.
  // Y el viewport es de CELULAR (360 px, el más angosto del depósito): el Resumen se mira
  // en la mano, no en el monitor.
  const p = await b.newPage({ locale: "en-US", timezoneId: "America/Los_Angeles",
                              viewport: { width: 360, height: 740 }, deviceScaleFactor: 2,
                              isMobile: true, hasTouch: true });
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const r = await p.evaluate(async () => {
    const out = {};

    /* ================= (A) reloj de 24 h ================= */
    // 16/09/2026 13:34:23 ART  (el PB de la foto)
    const tarde = new Date("2026-09-16T13:34:23-03:00").getTime();
    const fTarde = formatDateTime(tarde);
    out.A_tarde_es_13    = /\b13:34:23\b/.test(fTarde);
    out.A_tarde_no_es_01 = !/\b0?1:34:23\b/.test(fTarde);
    out.A_trae_la_fecha  = fTarde.indexOf("2026") >= 0 && fTarde.indexOf("9") >= 0;
    // hora sola
    out.A_hora_sola = formatTimeAr(tarde) === "13:34:23";
    // una de la MAÑANA sigue siendo 01, no 13
    out.A_manana = formatTimeAr(new Date("2026-09-16T01:07:27-03:00").getTime()) === "01:07:27";
    // medianoche: nunca "24:.."
    out.A_medianoche = /^00:/.test(formatTimeAr(new Date("2026-09-16T00:00:05-03:00").getTime()));
    // basura no rompe
    out.A_basura = formatDateTime("no-es-fecha") === "" && formatTimeAr(null) === "";
    /* ⚠ En Chromium con ICU completo `es-AR` YA resuelve a 24 h, así que las aserciones
       de arriba pasarían igual con el código viejo: el bug sólo se reproduce en el WebView
       del celular, que resuelve es-AR a 12 h. Lo que de verdad protege contra la regresión
       es que el ciclo horario quede FIJADO en el código y no dependa del dispositivo —
       por eso se chequea la implementación, no sólo la salida. */
    out.A_hour12_fijado = /hour12:\s*false/.test(String(formatDateTime)) &&
                          /hour12:\s*false/.test(String(formatTimeAr));
    out.A_campos_fijados = /hour:\s*"2-digit"/.test(String(formatDateTime)) &&
                           /minute:/.test(String(formatDateTime)) && /second:/.test(String(formatDateTime));
    // duraciones
    out.A_dur = formatDur(146000) === "2m 26s" && formatDur(3900000) === "1h 05m" &&
                formatDur(45000) === "45s" && formatDur(-5) === "";

    /* ================= (B) un renglón por tarea ================= */
    /* ⚠ La apertura va DESFASADA 267 ms respecto del `ts_inicio` del cierre, no en el
       mismo milisegundo. Así llegan de verdad: son dos `Date.now()` distintos y en los
       33 pares del 16/09 la diferencia fue de 2 a 306 ms, 33 de 33 distintos. Con el
       fixture "perfecto" que tenía este test hasta la v19.20 el bug no se veía, y en el
       celular de Jhonny cada pausa salía dos veces. v19.21. */
    const abreIso = "2026-09-16T13:31:57.187-03:00";
    const lista = [
      // cierre del PB (llega primero porque la lista viene ordenada desc)
      { opcion: "PB", descripcion: "Paré Baño", ts: new Date("2026-09-16T13:34:23.187-03:00").getTime(), ts_inicio_iso: abreIso },
      // su apertura: 267 ms ANTES de lo que dice el cierre
      { opcion: "PB", descripcion: "Paré Baño", ts: new Date(abreIso).getTime() - 267, ts_inicio_iso: null },
      // un EI abierto que NADIE cerró (el caso de insumos)
      { opcion: "EI", descripcion: "Entrega Insumos", ts: new Date("2026-09-16T13:41:59-03:00").getTime(), ts_inicio_iso: null },
      // un EP: NO es toggle, tiene que quedar igual aunque no tenga cierre
      { opcion: "EP", descripcion: "Empecé Picking", texto: "D69H", ts: new Date("2026-09-16T13:07:27-03:00").getTime(), ts_inicio_iso: null }
    ];
    const filas = _histColapsarPares(lista.map(x => Object.assign({}, x)));
    out.B_colapsa_a_3 = filas.length === 3;
    const pb = filas.filter(f => f.opcion === "PB");
    out.B_un_solo_PB  = pb.length === 1;
    out.B_PB_es_cierre = !!(pb[0] && pb[0]._desde && pb[0]._hasta);
    out.B_PB_dur = !!(pb[0] && formatDur(pb[0]._durMs) === "2m 26s");
    const ei = filas.filter(f => f.opcion === "EI")[0];
    out.B_EI_marcado_abierto = !!(ei && ei._abierto === true && !ei._desde);
    const ep = filas.filter(f => f.opcion === "EP")[0];
    out.B_EP_sobrevive = !!(ep && !ep._abierto && !ep._desde);
    // control: dos PB del mismo tipo con aperturas DISTINTAS no se pisan entre sí
    const dosPares = _histColapsarPares([
      { opcion: "PB", ts: 2000, ts_inicio_iso: new Date(1000).toISOString() },
      { opcion: "PB", ts: 1000, ts_inicio_iso: null },
      { opcion: "PB", ts: 5000, ts_inicio_iso: new Date(4000).toISOString() },
      { opcion: "PB", ts: 4000, ts_inicio_iso: null }
    ]);
    out.B_dos_pares_dan_dos = dosPares.length === 2 && dosPares.every(f => f._desde);
    /* Un cierre se come UNA sola apertura: con dos aperturas al alcance de la tolerancia
       y un solo cierre, la otra tiene que seguir figurando "sin cerrar" (si no, una pausa
       que quedó abierta de verdad desaparecería de la pantalla). */
    const unCierreDosAperturas = _histColapsarPares([
      { opcion: "PB", ts: 9000, ts_inicio_iso: new Date(3000).toISOString() },
      { opcion: "PB", ts: 3010, ts_inicio_iso: null },   // ← la que le corresponde (10 ms)
      { opcion: "PB", ts: 1200, ts_inicio_iso: null }    // ← otra, dentro de los 5 s
    ]);
    out.B_no_se_come_dos = unCierreDosAperturas.length === 2 &&
      unCierreDosAperturas.filter(f => f._abierto).length === 1 &&
      unCierreDosAperturas.filter(f => f._abierto)[0].ts === 1200;
    // y una diferencia MAYOR a la tolerancia no se empareja: queda abierta y avisa
    const lejos = _histColapsarPares([
      { opcion: "PB", ts: 60000, ts_inicio_iso: new Date(20000).toISOString() },
      { opcion: "PB", ts: 6000,  ts_inicio_iso: null }   // 14 s de diferencia
    ]);
    out.B_lejos_no_empareja = lejos.length === 2 &&
                              lejos.filter(f => f._abierto).length === 1;

    /* ================= (C) cierre de RI/EI ================= */
    // interceptamos la cola para ver QUÉ se encola, sin mandar nada.
    // `_enqueueReportRaw` y `_ins` son `let`/`function` del script global: NO están en
    // `window`, así que se llega a ellos con eval indirecto (corre en scope global y sí
    // ve el entorno léxico del script).
    const ev = window.eval;
    ev("window.__enc = []; window.__rawOrig = _enqueueReportRaw; _enqueueReportRaw = function (pl) { window.__enc.push(pl); };");
    const encolado = window.__enc;
    const LEG = "999999";   // legajo inventado: no toca ningún estado real

    // sesión de EI abierta a las 13:41:02 con 16 unidades cargadas
    const iniIso = "2026-09-16T13:41:02-03:00";
    let st = getLegajoState(LEG); st.toggles = st.toggles || {}; st.toggles.EI = iniIso;
    setLegajoState(LEG, st);
    ev("_ins = { legajo: '" + LEG + "', mode: 'EI', items: [{ qty: 10 }, { qty: 6 }, { qty: 0 }] };");
    closeIns();                                   // el operario terminó la entrega
    const ci = encolado.filter(x => x.opcion === "EI");
    out.C_emite_cierre   = ci.length === 1;
    out.C_lleva_ts_inicio = !!(ci[0] && ci[0].ts_inicio_iso === iniIso);
    out.C_lleva_total     = !!(ci[0] && ci[0].texto === "16");
    out.C_baja_el_flag    = !(getLegajoState(LEG).toggles || {}).EI;

    // ANULAR: NO tiene que emitir cierre (la apertura ya se borró del server)
    encolado.length = 0;
    st = getLegajoState(LEG); st.toggles = st.toggles || {}; st.toggles.RI = "2026-09-16T14:09:56-03:00";
    setLegajoState(LEG, st);
    ev("_ins = { legajo: '" + LEG + "', mode: 'RI', items: [{ qty: 3 }] };");
    closeIns(true);
    out.C_anular_no_emite = encolado.filter(x => x.opcion === "RI").length === 0;
    out.C_anular_baja_flag = !(getLegajoState(LEG).toggles || {}).RI;

    // sin toggle abierto no inventa un cierre
    encolado.length = 0;
    ev("_ins = { legajo: '" + LEG + "', mode: 'RI', items: [{ qty: 1 }] };");
    closeIns();
    out.C_sin_toggle_no_emite = encolado.length === 0;

    // y el que anula de verdad pasa noEmit=true
    out.C_insAnular_pasa_noEmit = /closeIns\(true\)/.test(String(insAnular));

    /* ===== (D) MOBILE: el Resumen mezclado entra en 360 px sin desbordar ===== */
    const cont = document.getElementById("legajoHistoryContent");
    if (cont) {
      const T = new Date("2026-09-16T08:00:00-03:00").getTime();
      const mk = (o, d, t, ms, ini) => ({ opcion: o, descripcion: d, texto: t, ts: T + ms,
        ts_inicio_iso: ini == null ? null : new Date(T + ini).toISOString(),
        status: "sent", id: "m" + o + ms });
      _historyCache["776::" + getTodayKey()] = [
        mk("EP", "Empecé Picking", "E11C", 0),
        mk("TP", "Fin Picking", "E11C", 300000, 0),
        mk("PB", "Paré Baño", "", 400000),
        mk("PB", "Paré Baño", "", 546000, 400000),
        mk("EI", "Entrega Insumos", "", 600000),            // abierto → "sin cerrar"
        mk("FGU", "Faltó pero había en góndola", "E12A|583E:4:42,566E:3:4", 700000),
        mk("PSP", "Picking sin planimetría", "E12A|231,232,233,537", 800000),
        mk("FJ", "Fin de Jornada", '{"picking":9,"armado":0,"cajas":412}', 900000)
      ];
      renderLegajoHistory("776");
      const ancho = cont.clientWidth;
      out.D_sin_overflow = (document.documentElement.scrollWidth
                          - document.documentElement.clientWidth) <= 0;
      out.D_tarjetas_entran = [...cont.querySelectorAll(".history-item")]
        .every(x => x.scrollWidth <= ancho + 1);
      out.D_avisa_sin_cerrar = cont.innerHTML.indexOf("sin cerrar") >= 0;
      out.D_muestra_desde_hasta = cont.innerHTML.indexOf("hasta") >= 0;
      // el JSON técnico del FJ sigue oculto (no se muestra como "Dato")
      out.D_fj_sin_json = cont.innerHTML.indexOf('"picking"') < 0;
      delete _historyCache["776::" + getTodayKey()];
      cont.innerHTML = "";
    }

    /* ===== (E) SI EL SERVIDOR NO CONTESTA, SE AVISA Y NO SE CACHEA EL VACÍO =====
       El picking NO se guarda en el celular: los PKC son cientos por día y viven sólo
       en la base. Así que una lista armada sin el servidor no tiene una sola línea de
       picking, y antes de la v19.21 eso se mostraba como si estuviera completa — y el
       vacío quedaba cacheado, sin reintento. Jhonny miró su Resumen, no vio el picking
       de E12E y dio por perdido lo que estaba guardado. Problema 364. */
    if (cont) {
      /* Bajo file:// no hay cliente de Supabase (el CDN no carga), así que
         `_fetchAndRenderHistory` toma solo el camino de falla: es justo el que se
         quiere probar, sin necesidad de pinchar nada. */
      const KEY = "779::" + getTodayKey();
      delete _historyCache[KEY];
      await _fetchAndRenderHistory("779", []);
      out.E_no_cachea_el_vacio = !(KEY in _historyCache);
      out.E_avisa_en_pantalla  = cont.innerHTML.indexOf("No se pudo leer el detalle") >= 0;
      out.E_ofrece_reintentar  = cont.innerHTML.indexOf("histReintentar") >= 0;
      out.E_no_dice_que_no_hay = cont.innerHTML.indexOf("No hay reportes hoy") < 0;
      // con red, en cambio, no aparece ningún aviso
      _historyCache[KEY] = [];
      _renderHistoryWithRemote("779", [], [], false);
      out.E_ok_sin_aviso = cont.innerHTML.indexOf("No se pudo leer el detalle") < 0;
      out.E_reintentar_limpia = (function () {
        _historyCache[KEY] = [{ opcion: "EP", descripcion: "x", ts: 1, status: "sent" }];
        histReintentar("779");                 // dispara el fetch de nuevo
        return !(KEY in _historyCache) || _historyCache[KEY].length !== 1;
      })();
      delete _historyCache[KEY];
      cont.innerHTML = "";
    }

    ev("_enqueueReportRaw = window.__rawOrig; delete window.__rawOrig; delete window.__enc;");
    try {
      const m = JSON.parse(localStorage.getItem("legajo_state_virgilio_v1") || "{}");
      delete m[LEG];
      localStorage.setItem("legajo_state_virgilio_v1", JSON.stringify(m));
    } catch (_e) {}
    return out;
  });

  const claves = Object.keys(r);
  const malas = claves.filter(k => r[k] !== true);
  const pass = malas.length === 0 && errs.length === 0;
  for (const k of claves) console.log((r[k] === true ? "ok  " : "FAIL") + "   " + k);
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  console.log("\nhora-24h-renglon: " + (pass ? "OK" : "FAIL (" + malas.join(", ") + ")"));
  await b.close(); process.exit(pass ? 0 : 1);
})();
