/* v21.20 — LAS DOS PANTALLAS TIENEN QUE DAR EL MISMO NÚMERO.

   Las horas por operario están calculadas DOS VECES: en `fetchMonitorDayStats` (JS, la tabla
   «Mts3 x Hora» del monitor grande) y en `gv_monitor_horas_operario_dia` (SQL, lo que lee el
   monitor de la TV). Ya se despegaron tres veces:

     · v19.24 — "los dos usan la fichada real" decían los comentarios, y daban distinto en
                cada cruce de día;
     · v21.18 — la TV no restaba el tiempo muerto y el monitor sí;
     · v21.20 — el monitor contaba el tramo del día de apertura y la vista no; la vista
                restaba dos veces un `PB` que caía adentro de un `Limp` (3 min en el 15/09).

   Las tres se encontraron CORRIENDO las dos implementaciones, no leyéndolas. Este test deja
   esa comparación puesta en la suite.

   ── CÓMO ESTÁ ARMADO Y POR QUÉ ────────────────────────────────────────────────────────────
   Las sesiones no pueden pegarle a Supabase (el proxy de egress bloquea supabase.co), así que
   la mitad SQL va CONGELADA en `tools/vista-15.json` — la salida real de
   `gv_monitor_horas_operario_dia('2026-09-15')` el 22/09. La mitad JS se corre de verdad, con
   los eventos de ese día inyectados por interceptación de red.

   ⚠ Entonces este test caza los cambios del lado JS. Del lado SQL hay DOS centinelas, y hacen
   cosas distintas:
     · `select * from public.gv_reglas_perdidas;`    → ¿el PATRÓN sigue en el cuerpo? (10 filas
       sobre la función y la vista). No ve un cambio de CUENTA con el patrón puesto.
     · `select * from public.gv_huellas_cambiadas;`  → ¿el cuerpo es EXACTAMENTE el mismo que
       cuando se congeló este JSON? (v21.46). Ése es el que avisa que hay que re-congelarlo.
   Si se cambia una regla de horas A PROPÓSITO hay que tocar los dos lados, volver a congelar el
   JSON (cómo, adentro del propio JSON) y actualizar el md5 en `GV_Huella_Objeto`.

   ⚠ `hs_prod` SÍ se compara desde la v21.46. Antes no se podía: la vista le sumaba CC+CR+RR
   y el monitor grande **no medía ninguno de los tres** — colgaban de `tanda && ts_inicio` y el
   `texto` de esos eventos dejó de venir (CC en julio, CR en marzo, RR nunca lo tuvo). Eran
   79,10 h en 30 días que no se le atribuían a nadie. `hs_total` sigue afuera: sólo existe en
   la vista, el monitor grande no calcula la jornada por operario.

   ⚠ Y una honesta: el 15/09 NO tiene ningún tiempo muerto adentro de un MG/RT/RI/EI, así que
   este test pasa igual con o sin esa regla (v21.20). La que la prueba es
   `tests/muerto-neteado.cjs`, caso (C). Lo que este test SÍ caza, verificado rompiéndolo a
   propósito: sacarle el merge a los tiempos muertos deja al legajo 277 en 6,32 contra 6,37.

   Para una comparación EN VIVO contra la base: `tests/tools/monitor-vs-vista.cjs`.
   Sale 1 si falla. */
const path = require("path");
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("mon-vs-vista: sin Playwright, se saltea"); process.exit(0); }
}

const VISTA = require("./tools/vista-15.json");
const EV = require("./tools/ev-15.json");
const FJPREV = require("./tools/fjprev-14.json");
const EMP = require("./tools/emp.json");
const FICH = [];                       // 0 fichadas ese día: medido, el QR no se usa más

const DIA = VISTA.dia;
/* Tolerancia: la vista viene redondeada a 2 decimales y el monitor da el float crudo, así que
   0,005 ya es esperable. 0,011 deja pasar el redondeo y nada más — 1 minuto es 0,017 h. */
const TOL = 0.011;

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
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });

  const mon = await p.evaluate(async (dia) => {
    const st = await fetchMonitorDayStats(dia, new Map());
    /* La vista cuenta TANDAS DISTINTAS, no cierres: una tanda cerrada dos veces por error
       cuenta una sola (v12.97). El monitor ya acredita el tiempo una vez pero devuelve el
       detalle con los dos cierres, así que acá se dedupea igual que allá. */
    const nTandas = (det) => new Set((det || [])
      .map(d => String(d.tanda || "").trim().toUpperCase()).filter(Boolean)).size;
    const out = {};
    for (const o of (st.perOperario || [])) {
      const nP = nTandas(o.pickedDetail), nA = nTandas(o.armedDetail);
      out[String(o.legajo)] = {
        tandas_pick: nP, tandas_arm: nA,
        hs_pick: o.pickH || 0, hs_arm: o.armH || 0,
        prom_hs_pick: nP ? (o.pickH || 0) / nP : 0,
        prom_hs_arm:  nA ? (o.armH  || 0) / nA : 0,
        hs_prod: o.prodH || 0,
        hs_mov: (o.movMin || 0) / 60,
        hs_noprod: (o.noprodMin || 0) / 60
      };
    }
    return out;
  }, DIA);

  const mal = [];
  if (errs.length) mal.push("errores de página: " + errs.join(" | "));

  const CAMPOS = ["prom_hs_pick", "prom_hs_arm", "hs_pick", "hs_arm",
                  "hs_prod", "hs_mov", "hs_noprod"];
  const ENTEROS = ["tandas_pick", "tandas_arm"];
  const n2 = (x) => (Math.round((Number(x) || 0) * 100) / 100).toFixed(2);

  /* Que estén LOS MISMOS operarios: si el monitor deja a uno afuera (su filtro de "no tocó
     nada") y la vista no, es una diferencia de criterio, no un detalle. */
  const legVista = VISTA.operarios.map(o => o.legajo).sort();
  const legMon = Object.keys(mon).sort();
  if (legVista.join(",") !== legMon.join(",")) {
    mal.push("operarios distintos · vista [" + legVista.join(",") + "] · monitor [" + legMon.join(",") + "]");
  }

  for (const v of VISTA.operarios) {
    const m = mon[v.legajo];
    if (!m) { mal.push("legajo " + v.legajo + ": la vista lo tiene y el monitor no"); continue; }
    for (const k of ENTEROS) {
      if (Number(m[k]) !== Number(v[k])) {
        mal.push("legajo " + v.legajo + " · " + k + ": vista " + v[k] + " · monitor " + m[k]);
      }
    }
    for (const k of CAMPOS) {
      if (Math.abs(Number(m[k]) - Number(v[k])) > TOL) {
        mal.push("legajo " + v.legajo + " · " + k + ": vista " + n2(v[k]) + " · monitor " + n2(m[k]) +
                 "  (Δ " + n2(Math.abs(Number(m[k]) - Number(v[k]))) + " h)");
      }
    }
  }

  const ok = mal.length === 0;
  if (!ok) {
    console.log("mon-vs-vista: las dos pantallas NO dan lo mismo para el " + DIA + ":");
    for (const x of mal) console.log("  - " + x);
    console.log("  → si el cambio fue a propósito, tocá LOS DOS lados y volvé a congelar" +
                " tests/tools/vista-15.json (cómo, adentro del JSON).");
  } else {
    console.log("mon-vs-vista: OK — " + VISTA.operarios.length + " operarios del " + DIA +
                ", " + CAMPOS.length + " números cada uno, monitor grande == vista de la TV");
  }
  await b.close();
  process.exit(ok ? 0 : 1);
})();
