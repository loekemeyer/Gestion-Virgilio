/* Regresión idea 9051 — computeInconsistencias (el motor de alertas del panel supervisor).
   Función pura: (events, dayKey, validTandas) → lista {sev, cat, legajo, hora, detalle}.
   Cubre: exclusión de legajos test 0/1 · pedido duplicado (misma tanda cerrada por 2 legajos)
   · FJ doble y evento después de FJ · día pasado con producción SIN FJ (y hoy no alerta)
   · TP que duró >8h · comida >90 min y comidas múltiples · TAP sin AP previo · AP sin cerrar
   (día pasado = alta; hoy >3h = media) · tanda fuera de la PPP (validTandas) · hueco >90 min
   sin tarea en curso · orden alta→media. Umbrales reales: INC_* de index.html. Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async () => {
    const out = {};
    const DAY = "2026-01-05";   // lunes pasado (no-hoy)
    const ts = function (hhmm) { return DAY + "T" + hhmm + ":00-03:00"; };
    const cats = function (res, cat) { return res.filter(function (x) { return x.cat === cat; }); };
    const has = function (res, cat, frag) { return res.some(function (x) { return x.cat === cat && x.detalle.indexOf(frag) >= 0; }); };

    // ---- legajos 0/1 (test) excluidos por completo ----
    let res = computeInconsistencias([
      { legajo: "0", opcion: "TAP", texto: "D01B", ts_cliente: ts("10:00") },
      { legajo: "1", opcion: "TAP", texto: "D01B", ts_cliente: ts("10:01") }
    ], DAY, null);
    out.excluyeTest = res.length === 0;

    // ---- pedido duplicado: misma tanda con TP de 2 legajos ----
    res = computeInconsistencias([
      { legajo: "10", opcion: "EP", texto: "D02B", ts_cliente: ts("08:00") },
      { legajo: "10", opcion: "TP", texto: "D02B", ts_cliente: ts("09:00"), ts_inicio: ts("08:00") },
      { legajo: "11", opcion: "EP", texto: "D02B", ts_cliente: ts("08:10") },
      { legajo: "11", opcion: "TP", texto: "D02B", ts_cliente: ts("09:10"), ts_inicio: ts("08:10") },
      { legajo: "10", opcion: "FJ", ts_cliente: ts("17:00") },
      { legajo: "11", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.duplicado = has(res, "Pedido duplicado", "D02B") && cats(res, "Pedido duplicado")[0].sev === "alta";

    // ---- FJ doble + evento después del FJ + día pasado sin FJ ----
    res = computeInconsistencias([
      { legajo: "12", opcion: "FJ", ts_cliente: ts("16:00") },
      { legajo: "12", opcion: "FJ", ts_cliente: ts("17:00") },
      { legajo: "12", opcion: "EP", texto: "D03B", ts_cliente: ts("17:30") }
    ], DAY, null);
    out.fjDoble = has(res, "Secuencia", "Fin de Jornada (FJ) en el día");
    out.postFj = has(res, "Secuencia", "después de Fin de Jornada");
    res = computeInconsistencias([
      { legajo: "13", opcion: "EP", texto: "D04B", ts_cliente: ts("08:00") },
      { legajo: "13", opcion: "TP", texto: "D04B", ts_cliente: ts("09:00"), ts_inicio: ts("08:00") }
    ], DAY, null);
    out.sinFj = has(res, "Secuencia", "SIN Fin de Jornada");

    // ---- TP que duró más de 8 h (cerrado) ----
    res = computeInconsistencias([
      { legajo: "14", opcion: "TP", texto: "D05B", ts_cliente: ts("18:30"), ts_inicio: ts("08:00") },
      { legajo: "14", opcion: "FJ", ts_cliente: ts("19:00") }
    ], DAY, null);
    out.tpLargo = has(res, "Duración", "duró");

    // ---- comida de 2 h (>90 min) + 2 comidas en el día ----
    res = computeInconsistencias([
      { legajo: "15", opcion: "PC", ts_cliente: ts("14:00"), ts_inicio: ts("12:00") },
      { legajo: "15", opcion: "PC", ts_cliente: ts("16:30"), ts_inicio: ts("16:00") },
      { legajo: "15", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.comidaLarga = has(res, "Tiempos", "Comida de");
    out.comidasVarias = has(res, "Tiempos", "comidas (PC) en el día");

    // ---- TAP sin AP previo ----
    res = computeInconsistencias([
      { legajo: "16", opcion: "TAP", texto: "D06B", ts_cliente: ts("11:00"), ts_inicio: ts("10:00") },
      { legajo: "16", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.tapSinAp = has(res, "Secuencia", 'sin "AP" previo');

    // ---- AP abierto en día pasado = alta "quedó sin cerrar" ----
    res = computeInconsistencias([
      { legajo: "17", opcion: "AP", texto: "D07B", ts_cliente: ts("10:00") },
      { legajo: "17", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.abiertoAyer = has(res, "Sin cerrar", "quedó sin cerrar");

    // ---- AP abierto HOY hace >3 h = media "abierto hace" (y sin alerta de FJ) ----
    const hoyKey = getTodayKey();
    const hace4h = new Date(Date.now() - 4 * 3600 * 1000).toISOString();
    res = computeInconsistencias([
      { legajo: "18", opcion: "AP", texto: "D08B", ts_cliente: hace4h }
    ], hoyKey, null);
    out.abiertoHoy = has(res, "Sin cerrar", "abierto hace") && cats(res, "Sin cerrar")[0].sev === "media";
    out.hoySinAlertaFj = !has(res, "Secuencia", "SIN Fin de Jornada");

    // ---- tanda fuera de la planilla PPP (validTandas) ----
    res = computeInconsistencias([
      { legajo: "19", opcion: "EP", texto: "ZZZZ", ts_cliente: ts("08:00") },
      { legajo: "19", opcion: "TP", texto: "ZZZZ", ts_cliente: ts("09:00"), ts_inicio: ts("08:00") },
      { legajo: "19", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, new Set(["D09B"]));
    out.tandaInvalida = has(res, "Pedido inválido", "ZZZZ");

    // ---- hueco de 5 h sin tarea en curso (entre dos cierres) ----
    res = computeInconsistencias([
      { legajo: "20", opcion: "TP", texto: "D10B", ts_cliente: ts("09:00"), ts_inicio: ts("08:00") },
      { legajo: "20", opcion: "TAP", texto: "D10B", ts_cliente: ts("14:00"), ts_inicio: ts("13:50") },
      { legajo: "20", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.hueco = has(res, "Tiempos", "Hueco de");

    // ---- orden: las "alta" antes que las "media" ----
    res = computeInconsistencias([
      { legajo: "21", opcion: "PC", ts_cliente: ts("14:00"), ts_inicio: ts("12:00") },   // media
      { legajo: "21", opcion: "TAP", texto: "D11B", ts_cliente: ts("15:00"), ts_inicio: ts("14:30") },  // alta (sin AP)
      { legajo: "21", opcion: "FJ", ts_cliente: ts("17:00") }
    ], DAY, null);
    out.orden = res.length >= 2 && res[0].sev === "alta" && res[res.length - 1].sev === "media";

    return out;
  });
  const keys = Object.keys(r); const bad = keys.filter(function (k) { return r[k] !== true; });
  const pass = bad.length === 0 && errs.length === 0;
  console.log("incons-motor:", JSON.stringify(r), "· pageerrors:", errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL " + bad.join(","));
  await b.close(); process.exit(pass ? 0 : 1);
})();
