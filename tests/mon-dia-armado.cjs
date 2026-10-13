/* v29.86 — EL DÍA DEL MONITOR DICE CUÁNDO DEBIÓ ARMARSE (Luis, 13/10/2026).

   Textual: *"quiero que en el monitor, en el día figure así: «Mié 14/10 (debió armarse Vie 9)»
   o «Vie 16/10 (debe armarse Mié 14/10)»"*.

   El dato es el VERBO: «debió» = esa fecha YA PASÓ, o sea que ese día de reparto viene atrasado
   en el armado. La fecha sale de la norma de Thomas (23/09, v21.56): se arma el día 1, se
   factura el 2 y sale el 3 → armado = salida − 2 hábiles, con el mismo criterio de día hábil
   que ya usa `sumarHabiles` (finde + GV_Feriados).

   Este test corre la TV de verdad con el reloj fijo en el martes 13/10/2026 — el día en que Luis
   lo pidió — y mide los DOS ejemplos que escribió, que caen justo en el caso difícil: el lunes
   12/10 es feriado, así que dos hábiles antes del miércoles 14 es el VIERNES 9, no el lunes 12.

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");
const TV = path.join(__dirname, "..", "monitor", "tv.html");
const src = fs.readFileSync(TV, "utf8");
const fallas = [];
const ok = (c, m) => { if (!c) fallas.push(m); };

/* ── estático: las piezas ────────────────────────────────────────────────── */
ok(/function restarHabiles\(/.test(src), "falta restarHabiles: el día de armado se cuenta en HÁBILES, no corridos");
ok(/function diaArmado\(/.test(src), "falta diaArmado");
ok(/restarHabiles\(key, 2\)/.test(src),
   "el día de armado no son 2 hábiles antes de la salida (armar día 1 · facturar día 2 · salir día 3)");
ok(/FERIADOS\[k\]/.test((src.match(/function restarHabiles\([\s\S]*?\n\}/) || [""])[0]),
   "restarHabiles no saltea los feriados: contaría el 12/10 como hábil");
ok(/_rdArm\(x\)/.test(src), "la celda del día no muestra el día de armado");
/* No ensancha la columna: va en el `small`, que .rd td ya dibuja en bloque. Regla de espacio
   del 28/09: lo que no entra se abrevia o baja de renglón, nunca se ensancha la columna. */
ok(/small class="rd-arm/.test(src), "el día de armado tiene que ir en el <small> de la celda, no al lado");
ok(/rd-arm\.tarde/.test(src), "falta el estilo del vencido");

if (fallas.length) { console.log("mon-dia-armado: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("mon-dia-armado: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

/* martes 13/10/2026 a las 15:00 ART — el día del pedido. El lunes 12 es feriado. */
const T0 = Date.parse("2026-10-13T15:00:00-03:00");

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires", viewport: { width: 1920, height: 1080 } });
  const p = await ctx.newPage();
  await p.clock.setFixedTime(T0);
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  /* El resumen de días necesita el árbol de la PPP y lo despachado; el resto va vacío. */
  const ARBOL = [
    { fecha: "2026-10-13", np: "LK 9001", tanda: "Z90A", m3: 1.0, estado: "pendiente" },
    { fecha: "2026-10-14", np: "LK 9002", tanda: "Z90B", m3: 1.0, estado: "pendiente" },
    /* su armado cae HOY: ahí el verbo tiene que decir «hoy», no la fecha — en una pared se
       lee más rápido, y es el único caso que separa «debe» de «debió». */
    { fecha: "2026-10-15", np: "LK 9004", tanda: "Z90D", m3: 1.0, estado: "pendiente" },
    { fecha: "2026-10-16", np: "LK 9003", tanda: "Z90C", m3: 1.0, estado: "armado" }
  ];
  await p.route("**/rest/v1/**", (route) => {
    const u = decodeURIComponent(route.request().url());
    const filas = u.includes("/rpc/gv_ppp_prog_arbol") ? ARBOL : [];
    route.fulfill({ status: 200,
      headers: { "content-type": "application/json",
                 "content-range": "0-" + Math.max(0, filas.length - 1) + "/" + filas.length },
      body: JSON.stringify(filas) });
  });
  await p.goto("file://" + TV + "?key=tv", { waitUntil: "domcontentloaded" });
  await p.waitForSelector("#splash.hide", { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(600);

  /* El script de tv.html es una IIFE: no hay funciones globales que llamar. Se mide el DOM,
     que además es lo que ve el que mira la pared. Una fila por día, en orden. */
  const r = await p.evaluate(() => ({
    dias: (document.getElementById("fcBox") || {}).innerHTML || "",
    filas: Array.from(document.querySelectorAll("#fcBox tbody tr")).map((tr) => {
      const td = tr.querySelector("td.rd-fe"), sm = td && td.querySelector("small.rd-arm");
      return { fe: td ? td.firstChild.textContent.trim() : "",
               arm: sm ? sm.textContent.trim() : "",
               tarde: !!(sm && sm.classList.contains("tarde")),
               ancho: td ? Math.round(td.getBoundingClientRect().width) : 0 };
    })
  }));
  await b.close();

  ok(!errs.length, "errores de JS: " + errs.join(" · "));
  const f = (fe) => r.filas.filter((x) => x.fe === fe)[0] || null;
  ok(r.filas.length === 4, "se esperaban 4 días en «NPs por Día», hay " + r.filas.length +
     ": " + JSON.stringify(r.filas));

  /* ── los dos ejemplos de Luis, textuales ──────────────────────────────── */
  const d14 = f("Mié 14/10"), d16 = f("Vie 16/10"), d13 = f("Mar 13/10");
  ok(d14, "falta la fila del Mié 14/10");
  ok(d14 && d14.arm === "(debió armarse Vie 09/10)",
     "el 14/10 dice «" + (d14 && d14.arm) + "»; se esperaba «(debió armarse Vie 09/10)» " +
     "— dos hábiles antes del miércoles 14 es el VIERNES 9, porque el lunes 12 es feriado");
  ok(d14 && d14.tarde, "el 14/10 tiene su NP pendiente y el 09/10 ya pasó: el «debió» va marcado");

  ok(d16, "falta la fila del Vie 16/10");
  ok(d16 && d16.arm === "(debe armarse Mié 14/10)",
     "el 16/10 dice «" + (d16 && d16.arm) + "»; se esperaba «(debe armarse Mié 14/10)»");
  ok(d16 && !d16.tarde, "una fecha de armado futura no puede salir marcada como tarde");

  /* el jue 15/10 se arma HOY: el verbo es «debe» y dice «hoy», no la fecha */
  const d15 = f("Jue 15/10");
  ok(d15 && d15.arm === "(debe armarse hoy)",
     "el 15/10 dice «" + (d15 && d15.arm) + "»; su armado cae hoy, así que va «(debe armarse hoy)»");
  ok(d15 && !d15.tarde, "lo que se arma hoy todavía no está tarde");

  /* hoy (13/10): su armado era el jueves 8 — ya pasó, pero su NP sigue pendiente */
  ok(d13 && d13.arm === "(debió armarse Jue 08/10)",
     "el día de hoy dice «" + (d13 && d13.arm) + "»; se esperaba «(debió armarse Jue 08/10)»");

  /* la columna del día no se desbanda: el texto va en el <small>, que .rd td dibuja en bloque */
  const anchoFe = Math.max.apply(null, r.filas.map((x) => x.ancho));
  ok(anchoFe > 0 && anchoFe < 480,
     "la columna del día mide " + anchoFe + " px: el texto de armado la ensanchó");

  if (fallas.length) { console.log("mon-dia-armado: ✗ FAIL\n  - " + fallas.join("\n  - ")); process.exit(1); }
  console.log("mon-dia-armado: ✓ OK — Mié 14/10 (debió armarse Vie 09/10) · Vie 16/10 (debe armarse Mié 14/10), " +
              "columna de " + anchoFe + " px");
})();
