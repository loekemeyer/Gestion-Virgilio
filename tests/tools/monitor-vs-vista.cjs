/* HERRAMIENTA, no test (no la corre tests/run.sh).

   Corre el MONITOR DE VERDAD (`fetchMonitorDayStats`) con los datos REALES de un día
   inyectados por interceptación de red, e imprime lo que muestra por operario y por tanda,
   para comparar contra `vista_productividad_diaria` / `_semanal` del mismo día.

   Existe porque la v19.24 salió de acá: el monitor y el backend "usaban los dos la fichada
   real" —lo decía el comentario de las dos implementaciones— y sin embargo daban números
   distintos en cada cruce de día. **Leer las dos implementaciones no alcanza.**

   Cómo se usa:
     PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node tests/tools/monitor-vs-vista.cjs
     select legajo, arm_eff_min, pick_eff_min from public.vista_productividad_diaria
      where dia = '2026-09-15';

   Los fixtures (`ev-15.json`, `fjprev-14.json`, `emp.json`) son datos reales del 15/09
   bajados con el MCP de Supabase. Para comparar OTRO día hay que rebajarlos: el proxy de
   egress de las sesiones remotas bloquea supabase.co, así que no se pueden traer con curl.

   Diferencias ESPERADAS contra la vista (no son bugs): la vista topea cada cierre
   (TAP 180 min, TP 120) y cada tiempo muerto (30 min; PC 90), y descarta las tandas con
   ritmo roto. Ver §3.it de docs/SUPABASE-GESTION-VIRGILIO.md. */
const path = require("path");
const { chromium } = require("/opt/node22/lib/node_modules/playwright");

const EV = require("./ev-15.json");          // eventos del 15/09 (TP/TAP/muertos/FJ)
const FJPREV = require("./fjprev-14.json");  // FJ del 14/09
const FICH = [];                             // 0 fichadas: medido, el QR no se usa más
const EMP = require("./emp.json");

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
  await p.goto("file://" + "/home/user/Gestion-Virgilio/index.html",
              { waitUntil: "domcontentloaded" });

  const out = await p.evaluate(async () => {
    const st = await fetchMonitorDayStats("2026-09-15", new Map());
    window.__keys = Object.keys((st.perOperario||[])[0]||{});
    return (st.perOperario || []).map(o => ({
      legajo: o.legajo,
      armMin: Math.round((o.armH || 0) * 600) / 10,
      pickMin: Math.round((o.pickH || 0) * 600) / 10,
      armadas: (o.armedTandas && o.armedTandas.size) || 0,
      pickeadas: (o.pickedTandas && o.pickedTandas.size) || 0,
      arm: (o.armedDetail || []).map(d => ({
        t: d.tanda, min: Math.round(d.durMs / 6000) / 10,
        bruto: d.breakdown ? Math.round((d.breakdown.brutoMs || 0) / 60000) : null,
        muerto: d.breakdown ? Math.round((d.breakdown.muertoMs || 0) / 60000) : null,
        sameDay: d.breakdown ? d.breakdown.sameDay : null
      })),
      pick: (o.pickedDetail || []).map(d => ({
        t: d.tanda, min: Math.round(d.durMs / 6000) / 10,
        sameDay: d.breakdown ? d.breakdown.sameDay : null
      }))
    }));
  });
  const keys = await p.evaluate(() => window.__keys);
  console.log("CAMPOS: " + keys.join(", "));
  for (const o of out) {
    const cruz = [...o.arm, ...o.pick].filter(d => d.sameDay === false);
    console.log("lg " + o.legajo + " armMin=" + o.armMin + " pickMin=" + o.pickMin +
      " | cruces: " + (cruz.length ? cruz.map(d => d.t + "=" + d.min + "min(bruto " + d.bruto + ")").join(", ") : "-"));
    console.log("   arm: " + o.arm.map(d => d.t + ":" + d.min).join(" ") +
                " | pick: " + o.pick.map(d => d.t + ":" + d.min).join(" "));
  }
  if (errs.length) console.log("pageerrors: " + errs.join(" | "));
  await b.close();
})();
