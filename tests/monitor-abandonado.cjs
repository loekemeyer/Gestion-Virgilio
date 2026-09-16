/* Regresión v18.71 — el monitor no cuenta las horas de alguien que ya fichó salida.

   El 16/09 a las 8 de la mañana el monitor mostraba «JC 17h54» en E25A y «FO 16h18» en E23A.
   Los dos habían fichado FJ («terminé día») a las 17 del día anterior, sin cerrar. El chip
   seguía corriendo toda la noche, así que al supervisor le parecía que estaban trabajando —
   y era la segunda vez en el día que Luis preguntaba por lo mismo.

   FJ y el cierre de un picking/armado son cosas independientes en el modelo: fichar salida no
   cierra nada. Lo que cambia acá es la LECTURA: si hay un FJ posterior a la apertura, esa fase
   no está «en curso», está ABANDONADA. La duración se congela en el FJ (lo que se trabajó de
   verdad: 2,8 h y 0,9 h, no 17,9 y 16,3) y el chip lo dice.

   El dato lo calcula el backend (`gv_tanda_status` = vista_tanda_status + `pick_abandonado` /
   `arm_abandonado` / los ts del FJ), no el front: es una regla de negocio, no un formato. La
   vista vieja no se tocó porque la comparte Producción Virgilio.

   Chequea:
     1) que el monitor lea `gv_tanda_status` y pida las columnas nuevas;
     2) en vivo, que una fase abandonada muestre la duración CONGELADA en el FJ y no la que
        correría hasta ahora;
     3) que se distinga a simple vista (marca ⏏ y color propio) y que el title explique que la
        tanda quedó libre;
     4) que una fase en curso DE VERDAD siga contando como siempre.
   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const src = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");

const fallas = [];
if (!src.includes("/rest/v1/gv_tanda_status")) fallas.push("el monitor no lee gv_tanda_status");
for (const col of ["pick_abandonado", "arm_abandonado", "pick_fj_ts", "arm_fj_ts"]) {
  if (!src.includes(col)) fallas.push("no se pide la columna " + col);
}
if (fallas.length) {
  console.log("monitor-abandonado: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("monitor-abandonado: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
  const r = await p.evaluate(() => {
    const out = {};
    const H = 3600 * 1000;
    // el caso real: abrió ayer 14:29, fichó salida 17:17 (2h48), y ahora es la mañana siguiente
    const ini = Date.now() - 18 * H;
    const fj  = ini + 2.8 * H;

    const abandonada = statusCell("curso", "277", "E25A", "picking", new Date(ini).toISOString(), true, new Date(fj).toISOString());
    const enCurso    = statusCell("curso", "277", "E25A", "picking", new Date(Date.now() - 1.5 * H).toISOString(), false, null);

    const dur = (html) => { const m = html.match(/>(?:⏏ )?(\d+h\d{2}|\d+m)</); return m ? m[1] : ""; };

    // 2) congelada en el FJ: ~2h48, NO las ~18 h que corrieron desde que abrió
    out.durCongelada = dur(abandonada);
    out.congelaEnElFj = /^2h(4[5-9]|5\d)$/.test(out.durCongelada);
    out.noCuentaLaNoche = !/^1[0-9]h/.test(out.durCongelada);

    // 3) se distingue de un «en curso» normal
    out.tieneMarca   = /⏏/.test(abandonada);
    out.colorPropio  = /#7c3aed/.test(abandonada);
    out.explicaEnTitle = /Fich[oó] salida/i.test(abandonada) && /libre/i.test(abandonada);

    // 4) el que SÍ está en curso sigue como siempre
    out.enCursoSigue    = /^1h(2\d|3\d)$/.test(dur(enCurso));
    out.enCursoSinMarca = !/⏏/.test(enCurso) && !/#7c3aed/.test(enCurso);
    return out;
  });
  const pass = Object.keys(r).every((k) => r[k] !== false && r[k] !== "") && errs.length === 0;
  console.log("monitor-abandonado:", JSON.stringify(r), "· pageerrors:",
    errs.length ? errs.join("|") : "none", "·", pass ? "✓ OK" : "✗ FAIL");
  await b.close();
  process.exit(pass ? 0 : 1);
})();
