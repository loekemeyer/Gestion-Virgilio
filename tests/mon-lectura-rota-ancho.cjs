/* v26.70 (Luis, 05/10) — dos arreglos del monitor de la pared (tv.html) que hereda el Mon. Admin:

   D28 · UNA LECTURA ROTA NO ES UN CERO. Si la TV no podía leer `Facturacion_NP` (corte de red,
         timeout), el catch devolvía un conjunto VACÍO, la caché lo guardaba como dato bueno y el
         tablero leía «no hay nada facturado»: salía el cartel violeta «143 TANDAS YA SALIERON Y NO
         ESTÁN FACTURADAS», falso. Lo mismo con lo cargado al camión (CCN). Se prueba:
           A) Facturacion_NP falla desde el arranque → no hay cartel.
           B) lee bien, después falla → sigue con lo último bueno → no hay cartel.
           C) lo cargado (CCN) falla desde el arranque → «NPs por Día» y «Pendientes» dicen que no se
              pudo leer (no «Salió 0» ni todo el día pendiente), y no hay cartel.
           D) control: con las dos lecturas sanas y la tanda SIN facturar, el cartel SIGUE saliendo.

   D29 · el código de la tanda no se pisa con el m³. Las columnas eran % de la tabla y en el Mon. Admin
         la columna izquierda es más angosta («E48L0,4»). Se angosta la izquierda a propósito (34vw, como
         en el admin real) y ninguna celda de tanda, m³ ni encabezado puede desbordar.

   Sale 1 si falla. Verificado que falla contra la v26.69. */
const path = require("path");
const fs = require("fs");
const TV = path.join(__dirname, "..", "monitor", "tv.html");

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("mon-lectura-rota-ancho: sin Playwright, salteado"); process.exit(0); }
}

const AR = (ms) => new Date(new Date(ms).toLocaleString("en-US", { timeZone: "America/Argentina/Buenos_Aires" }));
const key = (ms) => { const d = AR(ms); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
const T0 = Date.parse(key(Date.now()) + "T15:00:00-03:00");   // reloj fijo (regla v26.47)
const HOY = key(T0);
const H = 3600 * 1000, iso = (ms) => new Date(ms).toISOString();

/* E40A: terminada (TP + TAP), cargada al camión y facturada → no tiene que haber cartel.
   E48M y F21A: en curso, para la tabla. */
const DATOS = {
  prog: [
    { tanda: "E40A", np: "98840", m3: 1.2,  fecha_entrega: HOY, razon_social: "Bazar Mandarin S.R.L.", zona: "Zona 3 - CABA Oeste", fecha_recep: HOY },
    { tanda: "E48M", np: "98841", m3: 10.8, fecha_entrega: HOY, razon_social: "Distribuidora Los Andes Sociedad Anonima", zona: "Zona 1 - CABA Sur", fecha_recep: HOY },
    { tanda: "F21A", np: "98842", m3: 0.4,  fecha_entrega: HOY, razon_social: "Borro Claudio Y Borro Carlos", zona: "Zona 1 - CABA Sur", fecha_recep: HOY }
  ],
  status: [
    { tanda: "E40A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(T0 - 4 * H), last_arm_op: "TAP", arm_legajo: 12, arm_start_ts: iso(T0 - 3 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E48M", last_pick_op: "EP", pick_legajo: 8, pick_start_ts: iso(T0 - 1 * H), last_arm_op: null, arm_legajo: null, arm_start_ts: null,
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null }
  ],
  ccn: [{ opcion: "CCN", texto: "98840", ts_cliente: iso(T0 - 2 * H) }],
  arbol: [
    { fecha: HOY, tanda: "E40A", np: "98840", m3: 1.2, estado: "facturado", razon_social: "Bazar Mandarin S.R.L." },
    { fecha: HOY, tanda: "E48M", np: "98841", m3: 10.8, estado: "proceso", razon_social: "Distribuidora Los Andes" },
    { fecha: HOY, tanda: "F21A", np: "98842", m3: 0.4, estado: "pendiente", razon_social: "Borro Claudio" }
  ]
};

async function abrir(b, estado, opt) {
  opt = opt || {};
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires", viewport: opt.viewport || { width: 1920, height: 1080 } });
  const p = await ctx.newPage();
  if (opt.reloj) await p.clock.install({ time: T0 }); else await p.clock.setFixedTime(T0);
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));
  await p.route("**/rest/v1/**", (route) => {
    const q = decodeURIComponent(route.request().url());
    const falla = (q.includes("/Facturacion_NP") && estado.facFalla) ||
                  (q.includes("/Registros_Produccion_Virgilio") && q.includes("opcion=in.(CCN,FSS)") && estado.ccnFalla);
    if (q.includes("/Facturacion_NP")) estado.lecturasFac = (estado.lecturasFac || 0) + 1;
    if (falla) { estado.fallas = (estado.fallas || 0) + 1; return route.fulfill({ status: 500, body: "{}" }); }
    let filas = [];
    if (q.includes("/gv_ppp_programacion_diaria")) filas = DATOS.prog;
    else if (q.includes("/gv_tanda_status")) filas = DATOS.status.filter((s) => q.includes(s.tanda));
    else if (q.includes("/rpc/gv_ppp_prog_arbol")) filas = DATOS.arbol;
    else if (q.includes("/Facturacion_NP")) filas = estado.facturadas || [{ np: "98840" }];
    else if (q.includes("/rpc/gv_tv_clave_actual")) filas = { clave: "1234", cambia_en_s: 600 };
    else if (q.includes("/Registros_Produccion_Virgilio") && q.includes("opcion=in.(CCN,FSS)")) filas = DATOS.ccn;
    const arr = Array.isArray(filas) ? filas : [filas];
    route.fulfill({ status: 200, headers: { "content-type": "application/json", "content-range": "0-" + Math.max(0, arr.length - 1) + "/" + arr.length },
      body: JSON.stringify(filas) });
  });
  if (opt.css) await p.addInitScript((css) => {
    document.addEventListener("DOMContentLoaded", () => { const st = document.createElement("style"); st.textContent = css; document.head.appendChild(st); });
  }, opt.css);
  await p.goto("file://" + TV + "?key=tv", { waitUntil: "domcontentloaded" });
  await p.waitForSelector("#splash.hide", { state: "attached", timeout: 15000 }).catch(() => {});
  await p.waitForSelector("#tandasBox td.t-tanda", { timeout: 10000 }).catch(() => {});
  await p.waitForTimeout(600);
  return { p, ctx, errs };
}
const cartel = (p) => p.evaluate(() => { const a = document.querySelector(".aviso-salio"); return a ? a.textContent.trim() : ""; });
const texto = (p, id) => p.evaluate((i) => (document.getElementById(i) || {}).textContent || "", id);

(async () => {
  const b = await chromium.launch();
  const mal = [];
  const ok = (c, m) => { if (!c) mal.push(m); };

  // A) facturadas falla desde el arranque
  {
    const est = { facFalla: true };
    const { p, ctx, errs } = await abrir(b, est);
    ok(est.fallas > 0, "A: la lectura de Facturacion_NP no llegó a fallar (el mock no se usó)");
    const c = await cartel(p);
    ok(!c, "A: con Facturacion_NP caída salió el cartel «ya salieron y no están facturadas»: " + c);
    ok(!errs.length, "A: errores de página: " + errs.join(" | "));
    await ctx.close();
  }

  // B) lee bien, después falla → sigue con lo último bueno
  {
    const est = { facFalla: false };
    const { p, ctx, errs } = await abrir(b, est, { reloj: true });
    ok(!(await cartel(p)), "B: con todo sano y E40A facturada no debería haber cartel");
    est.facFalla = true; est.fallas = 0;
    await p.clock.runFor(46000);          // pasa el TTL de facturadas (30 s): el ciclo la vuelve a pedir
    await p.waitForTimeout(1200);
    ok(est.fallas > 0, "B: después del TTL no se volvió a pedir Facturacion_NP (la prueba no probó nada)");
    const c = await cartel(p);
    ok(!c, "B: una recarga fallida de lo facturado borró lo último bueno y salió el cartel: " + c);
    ok(!errs.length, "B: errores de página: " + errs.join(" | "));
    await ctx.close();
  }

  // C) lo cargado al camión falla desde el arranque
  {
    const est = { ccnFalla: true };
    const { p, ctx, errs } = await abrir(b, est);
    ok(est.fallas > 0, "C: la lectura de CCN no llegó a fallar");
    ok(/No se pudo leer lo cargado al cami/.test(await texto(p, "fcBox")), "C: «NPs por Día» no dice que no pudo leer lo cargado: " + (await texto(p, "fcBox")).slice(0, 80));
    ok(/No se pudo leer lo cargado al cami/.test(await texto(p, "penBox")), "C: «Pendientes de salir hoy» no dice que no pudo leer lo cargado");
    ok(!(await cartel(p)), "C: sin el dato de lo cargado no puede haber cartel");
    ok(!errs.length, "C: errores de página: " + errs.join(" | "));
    await ctx.close();
  }

  // D) control: lecturas sanas, E40A cargada y SIN facturar → el cartel sale
  {
    const est = { facturadas: [] };
    const { p, ctx } = await abrir(b, est);
    ok(/E40A/.test(await cartel(p)), "D: con E40A cargada y sin facturar el cartel tiene que seguir saliendo");
    await ctx.close();
  }

  // D29) columna izquierda angosta (34vw, como en el Mon. Admin real): nada desborda
  for (const vp of [{ width: 1920, height: 1080 }, { width: 1366, height: 768 }]) {
    const { p, ctx } = await abrir(b, { facturadas: [{ np: "98840" }] }, { viewport: vp, css: "main{grid-template-columns:34vw 1fr !important}" });
    const r = await p.evaluate(() => {
      const celdas = [...document.querySelectorAll("#tandasBox table.tandas td.t-tanda, #tandasBox table.tandas td.t-m3, #tandasBox table.tandas td.t-np, #tandasBox table.tandas th")];
      return { n: celdas.length, des: celdas.filter((c) => {
        const rg = document.createRange(); rg.selectNodeContents(c);
        const cs = getComputedStyle(c);
        return rg.getBoundingClientRect().width > c.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) + 1;
      }).map((c) => c.textContent.trim().slice(0, 12)) };
    });
    ok(r.n >= 8, "D29 " + vp.width + ": no se dibujó la tabla de tandas (" + r.n + " celdas)");
    ok(!r.des.length, "D29 " + vp.width + ": con la columna izquierda angosta desbordan: " + r.des.join(" · "));
    await ctx.close();
  }

  await b.close();
  if (mal.length) { console.log("mon-lectura-rota-ancho: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("mon-lectura-rota-ancho: ✓ OK (lectura rota ≠ cero en facturadas y CCN; tanda y m³ no se pisan)");
})().catch((e) => { console.log("mon-lectura-rota-ancho: ✗ ERROR " + e.message); process.exit(1); });
