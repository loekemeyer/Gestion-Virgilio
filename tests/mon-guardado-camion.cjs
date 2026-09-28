// v23.64 (Luis, 28/09) — tres cosas del monitor que no pueden volver atrás:
//  1) la bajada de racks / guardado (Movimientos_Stock) cuenta como actividad: Isidro bajó racks
//     de 11:14 a 15:20 y el monitor decía "sin marcar hace 281 min";
//  2) el CAMIÓN del Total por día es el grupo de zonas (gv_monitor_tanda_camion), no letra+número;
//  3) el admin tiene la pestaña 📺 Vista TV (la misma monitor/tv.html en un iframe).
const fs = require("fs"), path = require("path");
const IDX = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const TV = fs.readFileSync(path.join(__dirname, "..", "monitor", "tv.html"), "utf8");
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };

// 1) correr _monActividadActual de verdad con un GST
const src = IDX.match(/var _MON_ACT_TOGGLES[\s\S]*?\nfunction _monActividadActual[\s\S]*?\n}\n/);
ok(!!src, "no encontré _monActividadActual");
if (src) {
  const f = new Function("isoToDayKey", src[0].replace(/const MON_GST_VIVO_MIN = 45;[^\n]*\n/, "") +
    "\nvar MON_GST_VIVO_MIN = 45; return _monActividadActual;")(function (ts) { return String(ts).slice(0, 10); });
  const now = Date.parse("2026-09-28T18:20:00Z");
  const evs = [
    { legajo: "94", opcion: "MG", texto: "", ts_cliente: "2026-09-28T13:37:00Z", ts_inicio: "2026-09-28T13:30:00Z" },
    { legajo: "94", opcion: "GST", texto: "", ts_cliente: "2026-09-28T14:14:00Z", ts_inicio: null },
    { legajo: "94", opcion: "GST", texto: "", ts_cliente: "2026-09-28T18:10:00Z", ts_inicio: null }
  ];
  const r = f(evs, "2026-09-28", new Set(), now, null)[0];
  ok(r && !r.idle && r.kind === "GST", "con bajada de racks hace 10 min tiene que decir Guardando: " + JSON.stringify(r));
  ok(r && r.sinceTs === Date.parse("2026-09-28T14:14:00Z"), "Guardando arranca en el primer movimiento de la racha");
  const r2 = f(evs, "2026-09-28", new Set(), now + 60 * 60000, null)[0];
  ok(r2 && r2.idle, "un guardado de hace más de 45 min ya no dice Guardando");
}
ok(/dataCG = dataGst\.length/.test(IDX) && /_monEnSilencio\(dataCG/.test(IDX), "el chip 'sin marcar' tiene que ver el guardado");
ok(/cargarGuardadoHoy\(\)/.test(TV) && /eventos\.concat\(guardado\)/.test(TV), "la TV tiene que ver el guardado");

// 2) camión por grupo de zonas
ok(/monCamionDeTanda\(t\.tanda\)/.test(IDX), "el Total por día del admin tiene que usar monCamionDeTanda");
ok(/gv_monitor_tanda_camion/.test(IDX) && /gv_monitor_tanda_camion/.test(TV), "los dos monitores leen gv_monitor_tanda_camion");
ok(/camionDeTanda\(v\.tanda\)/.test(TV), "la TV tiene que usar camionDeTanda");

// 3) pestaña Vista TV
ok(/setMonitorTab\('tv'\)/.test(IDX) && /monitor\/tv\.html\?key=tv/.test(IDX), "falta la pestaña 📺 Vista TV");

if (fallas.length) { console.log("mon-guardado-camion: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
console.log("mon-guardado-camion: ✓ OK");
