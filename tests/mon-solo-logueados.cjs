/* v29.90 (Luis, 13/10): *"no deberían aparecer esas cosas en el monitor. solo legajos que se hayan
   logueado (trabajadores o entrevistas)"*. Caso: el legajo 1 (Pruebas) apareció «en jornada» por UN
   evento suelto hecho desde el admin, sin haber entrado nunca a la app.
   Mide la pantalla corriendo (fetchMonitorDayStats), que es ≡ gv_monitor_horas_operario_dia:
     (a) el que NO se logueó no sale, aunque tenga eventos;
     (b) el que sí, sale;
     (c) FAIL-OPEN: si la lectura de logins falla o viene vacía (un día anterior al 30/09, cuando
         GV_Dispositivo_Login todavía no existía), NO se filtra a nadie.
   Sale 1 si falla. */
const fs = require("fs"), path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const DIA = "2026-10-13", iso = (h) => DIA + "T" + h + ":00-03:00";
const ev = (leg, op, txt, h, hi) => ({ opcion: op, texto: txt, legajo: leg, ts_cliente: iso(h), ts_inicio: hi ? iso(hi) : null });
const EV = [
  // 700 se logueó y pickeó una tanda
  ev("700", "EP", "Z98Z", "09:00"), ev("700", "TP", "Z98Z", "10:00", "09:00"),
  // 1 NO se logueó: un evento suelto desde el admin
  ev("1", "RI", "", "12:30"), ev("1", "RI", "", "12:33", "12:30")
];
let fail = 0; const ok = (c, m) => { console.log((c ? "ok   " : "FAIL ") + m); if (!c) fail++; };
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
ok(/gv_monitor_logueados/.test(html), "candado: el monitor pide gv_monitor_logueados");
ok(/_logueados\.size > 0 && !_logueados\.has/.test(html), "candado: el filtro es fail-open (con el Set vacío no filtra)");

function legajosDe(p, dia) {
  return p.evaluate(async (d) => {
    const s = await fetchMonitorDayStats(d, new Map());
    return (s.perOperario || []).map(x => String(x.legajo)).sort();
  }, dia);
}
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  let logins = [{ legajo: "700" }];
  await p.route("**/rest/v1/**", (r) => {
    const u = r.request().url();
    let body = "[]";
    if (u.indexOf("gv_monitor_logueados") >= 0) body = JSON.stringify(logins);
    else if (u.indexOf("Registros_Produccion_Virgilio") >= 0 && u.indexOf("opcion=eq.FJ") < 0) body = JSON.stringify(EV);
    r.fulfill({ status: 200, contentType: "application/json", body: body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  let legs = await legajosDe(p, DIA);
  ok(legs.indexOf("1") < 0, "el legajo 1, que no se logueó, NO está en el monitor — dio " + JSON.stringify(legs));
  ok(legs.indexOf("700") >= 0, "el que se logueó sí está");

  // (c) fail-open: sin logins registrados ese día, se ven todos (los días anteriores al 30/09)
  logins = [];
  await p.evaluate(() => { try { _monitorDayStatsCache.clear(); } catch (_e) {} });
  legs = await legajosDe(p, DIA);
  ok(legs.indexOf("1") >= 0 && legs.indexOf("700") >= 0, "fail-open: sin logins no se filtra a nadie — dio " + JSON.stringify(legs));

  ok(!errs.length, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));
  await b.close();
  console.log(fail ? "\nmon-solo-logueados: FAIL" : "\nmon-solo-logueados: OK"); process.exit(fail ? 1 : 0);
})();
