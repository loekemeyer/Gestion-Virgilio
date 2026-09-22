/* HERRAMIENTA, no test (no la corre tests/run.sh).

   Corre el MONITOR GRANDE DE VERDAD (`fetchMonitorDayStats`, el que dibuja la tabla
   «Mts3 x Hora») con los datos REALES de un día inyectados por interceptación de red, e
   imprime sus números **en el vocabulario de la vista** `gv_monitor_horas_operario_dia`,
   que es la que lee el monitor de la TV. Al lado imprime el SELECT para traer la otra
   mitad y comparar renglón por renglón.

   **Por qué existe.** Son dos implementaciones del mismo número —una en JS, otra en SQL—
   y ya nos mordió dos veces: la v19.24 salió de acá (el monitor y el backend "usaban los
   dos la fichada real" y daban distinto en cada cruce de día), y la v21.18 nació de
   descubrir que la TV no restaba el tiempo muerto y el monitor sí. **Leer las dos
   implementaciones no alcanza: hay que correrlas.**

   Cómo se usa:
     PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node tests/tools/monitor-vs-vista.cjs
   y después, con el MCP de Supabase, el SELECT que imprime al final.

   Los fixtures (`ev-15.json`, `fjprev-14.json`, `emp.json`) son datos reales del 15/09
   bajados con el MCP. Para comparar OTRO día hay que rebajarlos: el proxy de egress de las
   sesiones remotas bloquea supabase.co, así que no se pueden traer con curl.

   ── QUÉ SE COMPARA Y QUÉ NO ────────────────────────────────────────────────────────────
   Comparables (tienen que dar IGUAL, salvo redondeo):
     · prom_hs_pick · prom_hs_arm · hs_mov · hs_noprod
   NO comparables, y no es un bug:
     · `hs_prod`  — la vista le suma CC + CR + RR; el monitor grande **no mide CR ni RR**
                    (no están en ninguno de sus baldes). Se imprime igual, marcado.
     · `hs_total` — el monitor grande no calcula la jornada por operario.
     · la vista topea la jornada en la hora de salida del empleado; el monitor no la usa.
   Y contra `vista_productividad_diaria` (otra cosa más): esa topea cada cierre (TAP 180
   min, TP 120) y cada tiempo muerto (30 min; PC 90), y descarta las tandas con ritmo roto.
   Ver §3.it de docs/SUPABASE-GESTION-VIRGILIO.md.

   ── ÚLTIMA MEDICIÓN (2026-09-22, día 15/09) ────────────────────────────────────────────
     · `hs_noprod`  coincide en los 5 operarios.
     · `hs_mov`     coincide en 4 de 5. Difiere el legajo 94: 2,63 (monitor) vs 2,33 (vista).
     · los PROMEDIOS de armado difieren en los dos legajos que tienen un cierre que **cruzó
       la medianoche**: 237 → 0,49 vs 0,41 · 8 → 2,47 vs 2,23. La causa es el tramo del día
       ANTERIOR: el monitor grande cuenta desde la apertura hasta el fin de jornada de ese
       día (`businessDurBetweenMs`), la vista arranca en el primer evento de HOY. **No hay
       una de las dos "bien": es una decisión pendiente.** El de picking (277: 0,46 vs 0,45)
       queda sin explicar todavía.
   ⚠ No "arreglar" una de las dos para que cierre el número sin decidir antes CUÁL regla vale
     para un cierre que cruza el día. La diferencia es real y está medida. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");

const DIA = "2026-09-15";                    // el día de los fixtures
const EV = require("./ev-15.json");          // eventos del 15/09 (TP/TAP/muertos/FJ)
const FJPREV = require("./fjprev-14.json");  // FJ del 14/09
const FICH = [];                             // 0 fichadas: medido, el QR no se usa más
const EMP = require("./emp.json");

const n2 = (x) => (Math.round((Number(x) || 0) * 100) / 100).toFixed(2);

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = []; p.on("pageerror", e => errs.push(e.message));

  await p.route("**/rest/v1/**", (route) => {
    const u = route.request().url();
    let body = "[]";
    if (u.indexOf("Fichadas_Virgilio") >= 0) body = JSON.stringify(FICH);
    else if (u.indexOf("Empleados") >= 0) body = JSON.stringify(EMP);
    else if (u.indexOf("Registros_Produccion_Virgilio") >= 0) {
      body = (u.indexOf("opcion=eq.FJ") >= 0) ? JSON.stringify(FJPREV) : JSON.stringify(EV);
    }
    route.fulfill({ status: 200, contentType: "application/json", body });
  });
  await p.goto("file://" + path.join(__dirname, "..", "..", "index.html"),
              { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async (dia) => {
    const st = await fetchMonitorDayStats(dia, new Map());
    /* La vista cuenta TANDAS DISTINTAS, no cierres: una tanda cerrada dos veces por error
       cuenta una. El monitor ya acredita el tiempo una sola vez (v12.97) pero devuelve el
       detalle con los dos cierres, así que acá se dedupea para que el promedio coincida. */
    const tandas = (det) => new Set((det || []).map(d => String(d.tanda || "").trim().toUpperCase())
                                                .filter(Boolean)).size;
    return (st.perOperario || []).map(o => {
      const nP = tandas(o.pickedDetail), nA = tandas(o.armedDetail);
      return {
        legajo: String(o.legajo),
        nombre: o.nombre || "",
        tandas_pick: nP,
        prom_hs_pick: nP ? (o.pickH || 0) / nP : 0,
        tandas_arm: nA,
        prom_hs_arm: nA ? (o.armH || 0) / nA : 0,
        hs_pick: o.pickH || 0,
        hs_arm: o.armH || 0,
        hs_cc: o.ccH || 0,
        hs_mov: (o.movMin || 0) / 60,
        hs_noprod: (o.noprodMin || 0) / 60,
        /* Lo más parecido a `hs_prod` que el monitor grande puede armar: le FALTAN CR y RR,
           que no mide. Por eso se imprime aparte y marcado. */
        hs_prod_sin_cr_rr: (o.pickH || 0) + (o.armH || 0) + (o.ccH || 0)
      };
    }).sort((a, b) => a.legajo.localeCompare(b.legajo));
  }, DIA);

  console.log("MONITOR GRANDE (fetchMonitorDayStats) · día " + DIA + "\n");
  console.log(["legajo", "tp", "prom_pick", "ta", "prom_arm", "hs_mov", "hs_noprod",
               "prod(sin CR/RR)", "nombre"].join("\t"));
  for (const o of out) {
    console.log([o.legajo, o.tandas_pick, n2(o.prom_hs_pick), o.tandas_arm, n2(o.prom_hs_arm),
                 n2(o.hs_mov), n2(o.hs_noprod), n2(o.hs_prod_sin_cr_rr), o.nombre].join("\t"));
  }
  if (errs.length) console.log("\npageerrors: " + errs.join(" | "));

  console.log("\n── Y ahora la otra mitad, con el MCP de Supabase ──────────────────────────");
  console.log(`select legajo, tandas_pick, prom_hs_pick, tandas_arm, prom_hs_arm,
       hs_mov, hs_noprod, hs_prod, hs_total, nombre
  from public.gv_monitor_horas_operario_dia(date '${DIA}')
 order by legajo;`);
  console.log(`
Tienen que coincidir: prom_hs_pick · prom_hs_arm · hs_mov · hs_noprod.
\`hs_prod\` de la vista incluye CR y RR, que el monitor grande no mide: la diferencia
esperada es exactamente esas horas. \`hs_total\` sólo lo tiene la vista.
Si se despega alguno de los cuatro primeros, hay DOS implementaciones distintas otra vez.`);
  await b.close();
})();
