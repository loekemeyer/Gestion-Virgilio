/* monitor/admin.html — la versión INTERACTIVA del monitor, para la pestaña «🛠️ Mon. Admin» del
   admin. Es el MISMO tablero de la pared (monitor/tv.html) pero clickeable: cada celda abre su
   desglose en un pop-up (m³/h de un operario → las tandas que cerró · una celda de «NPs por Día»
   → sus NP · una tanda → su detalle).

   admin.html NO se escribe a mano: se GENERA desde tv.html con monitor/build-admin.cjs (así la
   lógica del tablero vive en un solo lado y las dos vistas no se desvían). Este test cuida:

     1) FRESCURA: que admin.html sea exactamente lo que build-admin.cjs produce hoy desde tv.html.
        Si alguien tocó tv.html y no regeneró, falla y dice cómo arreglarlo.
     2) que tenga la capa interactiva (pop-up, celdas .cx, el resolvedor de clicks).
     3) en vivo (Supabase mockeado): que el tablero pinte y que clickear una celda de m³/h, una de
        «NPs por Día» y una tanda abra el pop-up con el desglose correcto; y que ✕/Esc lo cierren.

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");

const MON = path.join(__dirname, "..", "monitor");
const ADMIN = path.join(MON, "admin.html");
const fallas = [];

/* ── 1) frescura: admin.html == build(tv.html) ────────────────────────────── */
let src = "";
try {
  const { build } = require(path.join(MON, "build-admin.cjs"));
  const tv = fs.readFileSync(path.join(MON, "tv.html"), "utf8");
  const esperado = build(tv);
  src = fs.readFileSync(ADMIN, "utf8");
  if (src !== esperado) {
    fallas.push("admin.html quedó desincronizado de tv.html — regeneralo: `node monitor/build-admin.cjs`");
  }
} catch (e) {
  fallas.push("no pude correr build-admin.cjs: " + e.message);
}

/* ── 2) tiene la capa interactiva ─────────────────────────────────────────── */
if (src) {
  for (const marca of ['id="pop"', ".cx", "abrirDesglose", "function instrumentar()",
                       "window.__MA_INSTR", 'data-pop',
                       // v26.50 (Luis): puntaje 1-10 de picking, SÓLO en el admin (nunca en tv.html)
                       "gv_picking_puntaje_operario", 'data-pop="punt"', "window.parent.sbAuth", "function popPuntaje("]) {
    if (!src.includes(marca)) fallas.push("le falta la capa admin: " + marca);
  }
  // sigue leyendo las MISMAS fuentes que la TV (lo hereda de tv.html, pero lo confirmamos)
  for (const fuente of ["gv_ppp_programacion_diaria", "gv_ppp_prog_arbol", "gv_monitor_horas_operario",
                        "Registros_Produccion_Virgilio", "Range"]) {
    if (!src.includes(fuente)) fallas.push("no lee " + fuente);
  }
  if (!src.includes("../supabase-config.js")) fallas.push("no toma la key de supabase-config.js");
  // y la TV NO lleva el puntaje (es de supervisor): candado invertido
  const tvSrc = fs.readFileSync(path.join(MON, "tv.html"), "utf8");
  if (tvSrc.includes("gv_picking_puntaje_operario")) fallas.push("tv.html NO puede llevar el puntaje de picking (es sólo del admin)");
}

if (fallas.length) {
  console.log("mon-admin: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

/* ── 3) en vivo ───────────────────────────────────────────────────────────── */
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("mon-admin: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

const AR = (ms) => new Date(new Date(ms).toLocaleString("en-US", { timeZone: "America/Argentina/Buenos_Aires" }));
const key = (ms) => { const d = AR(ms); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
// reloj FIJO a las 15:00 ART de hoy (v26.47): entre las 00:00 y las 03:00 ART «hace 1,5 h» caia AYER y la pagina lo descartaba (CI 1700 en rojo a las 00:09 ART)
const T0 = Date.parse(key(Date.now()) + "T15:00:00-03:00");
const HOY = key(T0);
const _FER = (fs.readFileSync(path.join(MON, "tv.html"), "utf8").match(/var FERIADOS = \{[^}]*\}/) || [""])[0].match(/\d{4}-\d{2}-\d{2}/g) || [];
const MANANA = (function () {
  for (let t = T0 + 86400000, i = 0; i < 15; i++, t += 86400000) {
    const k = key(t), wd = AR(t).getDay();
    if (wd !== 0 && wd !== 6 && _FER.indexOf(k) < 0) return k;
  }
  return key(T0 + 86400000);
})();
const H = 3600 * 1000;
const iso = (ms) => new Date(ms).toISOString();
const RECEP_VIEJA = key(T0 - 28 * 86400000);
const hmAR = (ms) => { const k = key(ms); const h = new Date(ms).toLocaleTimeString("es-AR", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "America/Argentina/Buenos_Aires" });
  return k === HOY ? h : null; };

/* Un día de planta chico pero con todo lo que los pop-ups necesitan: un operario que cerró
   picking (m³/h con desglose), NP en varios estados (celda de «NPs por Día») y una tanda en
   curso con dos clientes (desglose de tanda). */
const DATOS = {
  prog: [
    { tanda: "E30A", np: "98801", m3: 2.5, fecha_entrega: HOY, razon_social: "Bazar Mandarin S.R.L.", zona: "Zona 3 - CABA Oeste", fecha_recep: RECEP_VIEJA },
    { tanda: "E31A", np: "98802", m3: 1.5, fecha_entrega: HOY, razon_social: "Perez Zarate S.R.L.", zona: "Zona 1 - CABA Sur", fecha_recep: HOY },
    { tanda: "E32A", np: "98803", m3: 3.0, fecha_entrega: MANANA, razon_social: "Simon Zeitune E Hijo S.A", zona: "Retira", fecha_recep: HOY }
  ],
  web: [
    { empresa: "lk", np: 97, tanda: "E30A", fecha_entrega: HOY, razon_social: "Casa Pepe",
      zona: "Zona 3 - CABA Oeste", fecha_recep: HOY, m3: 0.8, es_agregado: false, agregado_a_np: null }
  ],
  status: [
    { tanda: "E30A", last_pick_op: "EP", pick_legajo: 8, pick_start_ts: iso(T0 - 1.5 * H),
      last_arm_op: null, arm_legajo: null, arm_start_ts: null,
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E31A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(T0 - 3 * H),
      last_arm_op: "TAP", arm_legajo: 12, arm_start_ts: iso(T0 - 2 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null }
  ],
  eventos: [
    { legajo: 8,  opcion: "EP",  texto: "E30A", ts_cliente: iso(T0 - 1.5 * H), ts_inicio: null },
    { legajo: 8,  opcion: "TP",  texto: "E31A", ts_cliente: iso(T0 - 2.5 * H), ts_inicio: iso(T0 - 3 * H) },
    { legajo: 12, opcion: "TAP", texto: "E31A", ts_cliente: iso(T0 - 1 * H),  ts_inicio: iso(T0 - 2 * H) }
  ],
  /* v26.33: EP/TP de E30A — un ciclo cerrado (4 h → 3,5 h atrás), un EP de prueba (legajo 1,
     no cuenta) y el EP abierto de hace 1,5 h (en curso). */
  pickHs: [
    { legajo: 8, opcion: "TP", texto: "E30A", ts_cliente: iso(T0 - 3.5 * H), ts_inicio: iso(T0 - 4 * H) },
    { legajo: 1, opcion: "EP", texto: "E30A", ts_cliente: iso(T0 - 2 * H), ts_inicio: null },
    { legajo: 8, opcion: "EP", texto: "e30a", ts_cliente: iso(T0 - 1.5 * H), ts_inicio: null },
    /* v26.35 (D15): E31A pickeada (3 h → 2,5 h) y armada (2 h → 1 h); un APX anulado no cuenta. */
    { legajo: 8,  opcion: "TP",  texto: "E31A", ts_cliente: iso(T0 - 2.5 * H), ts_inicio: iso(T0 - 3 * H) },
    { legajo: 12, opcion: "APX", texto: "E31A", ts_cliente: iso(T0 - 2.2 * H), ts_inicio: null },
    { legajo: 12, opcion: "TAP", texto: "E31A", ts_cliente: iso(T0 - 1 * H),   ts_inicio: iso(T0 - 2 * H) }
  ],
  fichadas: [{ legajo: 12, ts_cliente: iso(T0 - 4 * H) }],
  empleados: [
    { Legajo: 8,  Empleado: "Farias Juan Hilario", hora_entrada: "08:00:00", hora_salida: "17:00:00" },
    { Legajo: 12, Empleado: "Ortiz Franco",        hora_entrada: "08:00:00", hora_salida: "17:00:00" }
  ],
  facturadas: [{ np: "98802" }],
  ccn: [{ opcion: "CCN", texto: "98805", ts_cliente: iso(T0 - 5 * H) }],
  deshechas: [],
  arbol: [
    { fecha: HOY, tanda: "E31A", np: "98802", m3: 1.5, estado: "facturado", razon_social: "Perez Zarate S.R.L." },
    { fecha: HOY, tanda: "E34A", np: "98805", m3: 2.0, estado: "armado", razon_social: "Nexxo S.R.L." },
    { fecha: HOY, tanda: "E30A", np: "98809", m3: 1.0, estado: "proceso", razon_social: "Bazar Mandarin S.R.L." },
    { fecha: HOY, tanda: "E30A", np: "98810", m3: 0.5, estado: "pendiente", razon_social: "Bazar Mandarin S.R.L." }
  ],
  /* con hs_pick/hs_arm para que el m³/h salga un número y el pop-up muestre el cociente. */
  horas: [
    { legajo: "8", nombre: "Farias Juan Hilario", tandas_pick: 1, prom_hs_pick: 1.0, tandas_arm: 0, prom_hs_arm: 0,
      hs_pick: 1.0, hs_arm: 0, hs_prod: 4.5, hs_mov: 0.8, hs_noprod: 0.6, hs_total: 6.2, en_jornada: true },
    { legajo: "12", nombre: "Ortiz Franco", tandas_pick: 0, prom_hs_pick: 0, tandas_arm: 1, prom_hs_arm: 1.5,
      hs_pick: 0, hs_arm: 1.5, hs_prod: 2.4, hs_mov: 2.1, hs_noprod: 0.5, hs_total: 5.4, en_jornada: false }
  ]
};

function responder(url) {
  const q = decodeURIComponent(url);
  if (q.includes("/gv_ppp_programacion_diaria")) return DATOS.prog;
  if (q.includes("/PPP_Web_Programacion"))       return DATOS.web;
  if (q.includes("/gv_tanda_status"))            return DATOS.status.filter(s => q.includes(s.tanda));
  if (q.includes("/gv_tandas_deshechas"))        return DATOS.deshechas;
  if (q.includes("/rpc/gv_ppp_prog_arbol"))      return DATOS.arbol;
  if (q.includes("/gv_monitor_horas_operario"))  return DATOS.horas;
  if (q.includes("/Facturacion_NP"))             return DATOS.facturadas;
  if (q.includes("/Fichadas_Virgilio"))          return DATOS.fichadas;
  if (q.includes("/Empleados"))                  return DATOS.empleados;
  if (q.includes("/rpc/gv_tv_clave_actual"))     return { clave: "1234", cambia_en_s: 60 };
  if (q.includes("/Registros_Produccion_Virgilio")) {
    if (q.includes("opcion=in.(EP,TP,AP,TAP)")) return DATOS.pickHs;   // v26.35: picking y armado   // v26.33: hora del picking de la tanda
    return q.includes("opcion=in.(CCN,FSS)") ? DATOS.ccn : DATOS.eventos;
  }
  return [];
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires", viewport: { width: 1600, height: 900 } });
  const p = await ctx.newPage();
  await p.clock.setFixedTime(T0);   // la pagina ve la misma hora que las fixtures
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));

  await p.route("**/rest/v1/**", (route) => {
    const filas = responder(route.request().url());
    const arr = Array.isArray(filas) ? filas : [filas];
    route.fulfill({
      status: 200,
      headers: { "content-type": "application/json",
                 "content-range": "0-" + Math.max(0, arr.length - 1) + "/" + arr.length },
      body: JSON.stringify(filas)
    });
  });

  await p.goto("file://" + ADMIN + "?key=tv", { waitUntil: "domcontentloaded" });
  await p.waitForSelector("#splash.hide", { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(700);

  const mal = [];
  const ok = (cond, msg) => { if (!cond) mal.push(msg); };
  ok(errs.length === 0, "errores de página: " + errs.join(" | "));

  // el tablero pintó (hereda de tv.html)
  const base = await p.evaluate(() => ({
    tandas: (document.getElementById("tandasBox") || {}).innerHTML || "",
    ops: !!document.querySelector("#opsBox table.ops"),
    rd: !!document.querySelector("#fcBox table.rd"),
    cxOps: document.querySelectorAll("#opsBox td.op-rit.cx").length,
    cxRd: document.querySelectorAll("#fcBox table.rd td.cx").length,
    cxTan: document.querySelectorAll("#tandasBox tr.cx").length
  }));
  ok(/E30A/.test(base.tandas), "no pintó la tabla de tandas (falta E30A)");
  ok(base.ops, "no pintó la tabla de Operarios");
  ok(base.rd, "no pintó «NPs por Día»");
  ok(base.cxOps >= 2, "las celdas de m³/h no quedaron clickeables (.cx): " + base.cxOps);
  ok(base.cxRd >= 5, "las celdas de «NPs por Día» no quedaron clickeables: " + base.cxRd);
  ok(base.cxTan >= 1, "las filas de tandas no quedaron clickeables: " + base.cxTan);
  // v26.50 (Luis): la columna «Punt.» (puntaje 1-10 de picking) está en el admin; abierto suelto (sin
  // window.parent.sbAuth) no pide nada y la celda dice «—» con el motivo en el title
  const punt = await p.evaluate(() => {
    const th = [...document.querySelectorAll("#opsBox table.ops thead th")].map((x) => x.textContent || "").join("|");
    const tds = [...document.querySelectorAll("#opsBox table.ops tbody tr:not(.op-tot-row) td.op-punt")];
    return { th, n: tds.length, txt: tds.map((x) => x.textContent.trim()).join(","), tit: tds.map((x) => x.getAttribute("title") || "").join("|") };
  });
  ok(/Punt\./.test(punt.th) && /picking/.test(punt.th), "v26.50: falta la columna «Punt.» en Operarios: " + punt.th);
  ok(punt.n >= 2, "v26.50: cada operario tiene que tener su celda de puntaje: " + punt.n);
  ok(/^—(,—)*$/.test(punt.txt) && /sin sesión de supervisor/.test(punt.tit), "v26.50: sin parent la celda tiene que decir «—» y el motivo: " + punt.txt + " / " + punt.tit);

  const popTxt = () => p.evaluate(() => {
    const pop = document.getElementById("pop");
    return (pop && !pop.classList.contains("hidden") && !pop.classList.contains("hide")) ? (pop.textContent || "") : null;
  });

  // a) m³/h picking del primer operario (legajo 8 cerró E31A, 1,5 m³ ÷ 1 h)
  await p.click("#opsBox table.ops tbody tr:first-child td.op-rit.cx");
  let t1 = await popTxt();
  ok(t1 !== null, "el pop-up de m³/h no se abrió");
  ok(t1 && /E31A/.test(t1), "el desglose de m³/h no lista la tanda que cerró el operario (E31A): " + (t1 || "").slice(0, 160));
  ok(t1 && /m³\/h/.test(t1), "el desglose de m³/h no muestra el cociente");
  ok(t1 && /Min trab/i.test(t1) && /Ritmo/i.test(t1) && /Total/.test(t1), "v25.92: el desglose de m³/h no trae Min trab · Ritmo · Total: " + (t1 || "").slice(0, 200));

  // cierre con ✕
  await p.click("#popX");
  ok((await popTxt()) === null, "el ✕ no cerró el pop-up");

  // b) una celda de «NPs por Día» (la de «Salió»: 98805 / Nexxo)
  await p.click("#fcBox table.rd tbody tr:first-child td.cx[data-sub='salio']");
  let t2 = await popTxt();
  ok(t2 !== null, "el pop-up de «NPs por Día» no se abrió");
  ok(t2 && /Nexxo/.test(t2), "el desglose de la celda de NPs no lista la NP de ese estado (Nexxo): " + (t2 || "").slice(0, 160));

  // cierre con Esc
  await p.keyboard.press("Escape");
  ok((await popTxt()) === null, "Escape no cerró el pop-up");

  // c) una tanda (E30A: dos clientes, uno web)
  await p.evaluate(() => {
    const tr = [...document.querySelectorAll("#tandasBox tr.cx")]
      .find((r) => (r.querySelector(".t-tanda") || {}).textContent && /E30A/.test(r.querySelector(".t-tanda").textContent));
    if (tr) tr.click();
  });
  let t3 = await popTxt();
  ok(t3 !== null, "el pop-up de la tanda no se abrió");
  ok(t3 && /Casa Pepe/.test(t3), "el desglose de la tanda no muestra sus clientes (Casa Pepe): " + (t3 || "").slice(0, 200));
  ok(t3 && /Clientes/.test(t3), "el desglose de la tanda no tiene la fila de Clientes");

  // v26.33 (Luis): la hora de inicio y fin del picking, si las tiene (llega en una consulta aparte)
  await p.waitForFunction(() => { const n = document.getElementById("popPickHs"); return n && n.textContent.trim().length > 0; },
    null, { timeout: 5000 }).catch(() => {});
  const hs = await p.evaluate(() => (document.getElementById("popPickHs") || {}).textContent || "");
  const i1 = hmAR(T0 - 4 * H), f1 = hmAR(T0 - 3.5 * H), i2 = hmAR(T0 - 1.5 * H), iPrueba = hmAR(T0 - 2 * H);
  if (i1 && f1 && i2) {   // las tres de hoy (si la corrida cae justo después de medianoche, el día va delante)
    ok(hs.includes(i1 + " → " + f1 + " (0:30)"), "v26.33: no muestra el picking cerrado " + i1 + " → " + f1 + " (0:30): «" + hs + "»");
    ok(hs.includes("desde " + i2), "v26.33: no muestra el picking en curso «desde " + i2 + "»: «" + hs + "»");
    ok(!iPrueba || iPrueba === i1 || iPrueba === f1 || iPrueba === i2 || !hs.includes(iPrueba), "v26.33: contó el EP del legajo de prueba (" + iPrueba + "): «" + hs + "»");
  } else ok(/→/.test(hs) && /desde/.test(hs), "v26.33: no muestra la hora del picking: «" + hs + "»");

  // v26.35 (D15): la tanda armada muestra también la hora de inicio y fin del ARMADO
  await p.keyboard.press("Escape");
  /* E31A ya está terminada y la tabla de la pared no la dibuja: se abre su pop-up por el mismo
     resolvedor de clicks (.cx + data-pop), que es lo que hace la fila. */
  const hayE31 = await p.evaluate(() => {
    const d = document.createElement("div");
    d.className = "cx"; d.setAttribute("data-pop", "tanda"); d.setAttribute("data-k", "E31A");
    document.body.appendChild(d); d.click(); d.remove();
    const pop = document.getElementById("pop");
    return !!(pop && !pop.classList.contains("hide") && /Tanda E31A/.test(pop.textContent || ""));
  });
  if (hayE31) {
    await p.waitForFunction(() => { const n = document.getElementById("popArmHs"); return n && n.textContent.trim().length > 0; },
      null, { timeout: 5000 }).catch(() => {});
    const r31 = await p.evaluate(() => ({ arm: (document.getElementById("popArmHs") || {}).textContent || "",
      pick: (document.getElementById("popPickHs") || {}).textContent || "" }));
    const ai = hmAR(T0 - 2 * H), af = hmAR(T0 - 1 * H), pi = hmAR(T0 - 3 * H), pf = hmAR(T0 - 2.5 * H);
    if (ai && af && pi && pf) {
      ok(r31.arm.includes(ai + " → " + af + " (1:00)"), "v26.35: no muestra el armado " + ai + " → " + af + " (1:00): «" + r31.arm + "»");
      ok(!/desde/.test(r31.arm), "v26.35: el APX anulado contó como armado en curso: «" + r31.arm + "»");
      ok(r31.pick.includes(pi + " → " + pf + " (0:30)"), "v26.35: E31A no muestra su picking " + pi + " → " + pf + ": «" + r31.pick + "»");
    } else ok(/→/.test(r31.arm), "v26.35: no muestra la hora del armado: «" + r31.arm + "»");
  } else ok(false, "v26.35: no se abrió el pop-up de la tanda E31A");

  await b.close();

  if (mal.length) { console.log("mon-admin: ✗ FAIL\n  - " + mal.join("\n  - ")); process.exit(1); }
  console.log("mon-admin: ✓ OK (frescura + tablero + 3 pop-ups + hora del picking y del armado)");
})().catch((e) => { console.log("mon-admin: ✗ ERROR " + e.message); process.exit(1); });
