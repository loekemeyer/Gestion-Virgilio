// v28.82 (Luis, 08/10): el monitor viejo (#monitorContent, ?monitor=tv) no va mas.
// /monitor y el kiosko ?monitor=tv van a monitor/tv.html, y el admin no lo refresca en segundo plano.
const fs = require("fs"), path = require("path");
const R = path.join(__dirname, "..");
const IDX = fs.readFileSync(path.join(R, "index.html"), "latin1");
const MON = fs.readFileSync(path.join(R, "monitor/index.html"), "utf8");
let f = 0; const ok = (c, m) => { if (!c) { f++; console.log("FAIL:", m); } };
ok(/location\.replace\("tv\.html\?key=tv"\)/.test(MON) && !/monitor=tv/.test(MON), "/monitor tiene que ir a tv.html, no a ?monitor=tv");
ok(/__pendingMonitorParam === "tv"[\s\S]{0,200}location\.replace\("monitor\/tv\.html\?key=tv"\)/.test(IDX), "el kiosko ?monitor=tv tiene que ir a monitor/tv.html");
ok(/if \(window\.__monViejoActivo\) refreshMonitor\(\);/.test(IDX), "openMonitor no refresca el tablero viejo");
ok(/if \(window\.__monViejoActivo\) monitorIntervalId = setInterval\(refreshMonitor/.test(IDX), "sin intervalo del tablero viejo");
console.log(f ? f + " fallas" : "OK monitor viejo sin puerta"); process.exit(f ? 1 : 0);
