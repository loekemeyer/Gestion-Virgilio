/* v27.55-mgpisa (Thomas D6, 06/10: *"puede guardarse por mucho tiempo, siempre y cuando se esté guardando o que en el
   medio se pise con otra tarea"*). Caso Isidro (94) del 06/10, reducido: el guardado (MG) del día cuenta como la
   UNIÓN de sus tramos MENOS lo que se pisa con otra tarea. ≡ gv_monitor_horas_operario_dia (mg_ag).
     MG 09:30-10:08 + MG 09:30-10:48 (lo duplica) + MG 10:48-16:49 -> una isla 09:30-16:49 (7:19)
     pisada por RT 10:09-10:41 (0:32), Limp 10:58-12:09 y 12:46-15:57 (4:22) e IR 16:22-16:29 (0:07) -> 2:18 de MG
   Movimiento = 2:18 + RT 0:32 + IR 0:07 + MG abierto 16:49-16:50 = 2:58 (antes el duplicado y lo pisado sumaban dos veces).
   Y un candado de texto: la vista y el monitor llevan el marcador. Sale 1 si falla. */
const fs = require("fs"), path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { console.error("no playwright"); process.exit(2); } }
const DIA = "2026-10-06", iso = (h) => DIA + "T" + h + ":00-03:00";
const L = "700";
const EV = [
  { opcion: "MGI", texto: "", legajo: L, ts_cliente: iso("09:30"), ts_inicio: null },
  { opcion: "MG",  texto: "", legajo: L, ts_cliente: iso("10:08"), ts_inicio: iso("09:30") },
  { opcion: "RT",  texto: "", legajo: L, ts_cliente: iso("10:09"), ts_inicio: null },
  { opcion: "RT",  texto: "733", legajo: L, ts_cliente: iso("10:41"), ts_inicio: iso("10:09") },
  { opcion: "MG",  texto: "", legajo: L, ts_cliente: iso("10:48"), ts_inicio: iso("09:30") },
  { opcion: "MGI", texto: "", legajo: L, ts_cliente: iso("10:48"), ts_inicio: null },
  { opcion: "Limp", texto: "", legajo: L, ts_cliente: iso("10:58"), ts_inicio: null },
  { opcion: "Limp", texto: "", legajo: L, ts_cliente: iso("12:09"), ts_inicio: iso("10:58") },
  { opcion: "Limp", texto: "", legajo: L, ts_cliente: iso("12:46"), ts_inicio: null },
  { opcion: "Limp", texto: "", legajo: L, ts_cliente: iso("15:57"), ts_inicio: iso("12:46") },
  { opcion: "IRI", texto: "", legajo: L, ts_cliente: iso("16:22"), ts_inicio: null },
  { opcion: "IR",  texto: "513|N7|0M|360C|NAC:a_guardar", legajo: L, ts_cliente: iso("16:29"), ts_inicio: null },
  { opcion: "MG",  texto: "", legajo: L, ts_cliente: iso("16:49"), ts_inicio: iso("10:48") },
  { opcion: "MGI", texto: "", legajo: L, ts_cliente: iso("16:49"), ts_inicio: null },
  { opcion: "FJ",  texto: "", legajo: L, ts_cliente: iso("16:50"), ts_inicio: null }
];
let fail = 0; const ok = (c, m) => { console.log((c ? "ok   " : "FAIL ") + m); if (!c) fail++; };
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "gv_monitor_horas_mg_pisa_v2757.sql"), "utf8");
ok(/v27\.55-mgpisa/.test(html) && /_mgRaw/.test(html), "candado: el monitor tiene el bloque v27.55-mgpisa");
ok(/mg_oc o where o\.legajo = i\.legajo/.test(sql) && /y\.src = 'IR' and c\.opcion = 'MG'/.test(sql), "candado: el SQL resta lo pisado y destapa el IR");
(async () => {
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (r) => {
    const u = r.request().url();
    r.fulfill({ status: 200, contentType: "application/json",
      body: (u.indexOf("Registros_Produccion_Virgilio") >= 0 && u.indexOf("opcion=eq.FJ") < 0) ? JSON.stringify(EV) : "[]" });
  });
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(async (dia) => {
    const s = await fetchMonitorDayStats(dia, new Map());
    const op = (s.perOperario || []).filter(x => String(x.legajo) === "700")[0] || {};
    return { mov: Math.round(op.movMin || 0), noprod: Math.round(op.noprodMin || 0),
             mg: (op.movDetail || []).filter(d => d.opcion === "MG" && !d.abierta).map(d => Math.round(d.durMs / 60000)) };
  }, DIA);
  ok(r.mov === 178, "movimiento 2:58 (178 min) — dio " + r.mov);
  ok(JSON.stringify(r.mg) === "[138]", "MG una isla de 2:18 (138 min) — dio " + JSON.stringify(r.mg));
  ok(r.noprod === 262, "limpieza 4:22 aparte (262 min) — dio " + r.noprod);
  ok(!errs.length, "sin errores de JS" + (errs.length ? ": " + errs[0] : ""));
  await b.close();
  console.log(fail ? "\nmg-pisa-tarea: FAIL" : "\nmg-pisa-tarea: OK"); process.exit(fail ? 1 : 0);
})();
