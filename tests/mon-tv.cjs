/* monitor/tv.html — la versión liviana y de SOLO LECTURA del monitor, para la TV de pared.

   Por qué existe (pedido de Luis, 2026-09-16): la TV cargaba el `index.html` entero para
   mostrar el tablero — ~4,97 MB de los que el monitor usa el 8,9% — y por eso el modo kiosko
   se recarga sola cada 7 minutos antes de quedarse sin RAM. Esta página pesa ~54 KB.

   Al ser una SEGUNDA vista de los mismos datos, lo que hay que cuidar es que no se desvíe de
   lo que muestra el monitor grande. Eso es lo que chequea este test:

     1) que siga siendo liviana y de sólo lectura: nada de supabase-js / Chart / jsPDF, ningún
        onclick ni input, y un techo de tamaño;
     2) que lea las MISMAS fuentes (las vistas y tablas del monitor grande, con las columnas
        de v18.71);
     3) en vivo, con las respuestas de Supabase simuladas: que pinte las tandas de la ventana,
        el ✅ de lo terminado, el reloj de lo que está en curso, quién trabaja en qué, los m³
        por camión, el aviso de agregado y el de tanda trabajada fuera de la PPP;
     4) que una tanda facturada Y despachada desaparezca del tablero (≡ _tandaDespachada), que
        es la regla que decide qué deja de mostrarse.

   Sale 1 si falla. */
const path = require("path");
const fs = require("fs");

const TV = path.join(__dirname, "..", "monitor", "tv.html");
const src = fs.readFileSync(TV, "utf8");
const fallas = [];

/* ── 1) liviana y de sólo lectura ─────────────────────────────────────────── */
const KB = Buffer.byteLength(src) / 1024;
if (KB > 80) fallas.push("pesa " + KB.toFixed(0) + " KB (techo 80): dejó de ser la versión liviana");
for (const pesado of ["supabase.umd.js", "supabase.js", "chart.umd", "jspdf", "xlsx", "cdn."]) {
  if (src.includes(pesado)) fallas.push("carga " + pesado + " — la TV no lo necesita");
}
for (const interactivo of ["onclick", "oninput", "onchange", "<input", "<button", "addEventListener(\"click\""]) {
  if (src.includes(interactivo)) fallas.push("tiene " + interactivo + ": la TV de pared no tiene puntero");
}
if (!src.includes("../supabase-config.js")) {
  fallas.push("no toma la key de supabase-config.js (v11.101: es el único lugar donde vive)");
}
if (/sb_publishable_|eyJhbGciOiJIUzI1NiIs/.test(src)) {
  fallas.push("tiene una key escrita adentro — tiene que salir de supabase-config.js");
}

/* ── 2) mismas fuentes que el monitor grande ──────────────────────────────── */
for (const fuente of ["gv_ppp_programacion_diaria", "PPP_Web_Programacion", "gv_tanda_status",
                      "gv_tandas_deshechas", "Facturacion_NP", "Registros_Produccion_Virgilio",
                      "Fichadas_Virgilio", "Empleados"]) {
  if (!src.includes(fuente)) fallas.push("no lee " + fuente);
}
for (const col of ["pick_abandonado", "arm_abandonado", "pick_fj_ts", "arm_fj_ts"]) {
  if (!src.includes(col)) fallas.push("no pide " + col + " (v18.71: sin eso cuenta las horas de quien ya se fue)");
}
if (!src.includes("Range")) fallas.push("no pagina: PostgREST corta en 1000 filas sin avisar");

if (fallas.length) {
  console.log("mon-tv: ✗ FAIL\n  - " + fallas.join("\n  - "));
  process.exit(1);
}

let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) {
  try { ({ chromium } = require("playwright")); }
  catch (_e2) { console.log("mon-tv: estático ✓ OK (sin Playwright para la parte en vivo)"); process.exit(0); }
}

/* ── Fixture: un día de planta con todos los casos que importan ───────────── */
const AR = (ms) => new Date(new Date(ms).toLocaleString("en-US", { timeZone: "America/Argentina/Buenos_Aires" }));
const key = (ms) => { const d = AR(ms); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); };
const HOY = key(Date.now());
/* v22.62 — «mañana» es el PRÓXIMO DÍA HÁBIL, no el día corrido: E32A tiene que decir 1 día de
   demora, y un viernes el día corrido es sábado (0 hábiles). El test fallaba los viernes y sábados.
   Salta fines de semana y los feriados de respaldo de tv.html (con el fetch mockeado vacío, son ésos). */
const _FER_TV = (fs.readFileSync(path.join(__dirname, "..", "monitor", "tv.html"), "utf8")
  .match(/var FERIADOS = \{[^}]*\}/) || [""])[0].match(/\d{4}-\d{2}-\d{2}/g) || [];
const MANANA = (function () {
  for (let t = Date.now() + 86400000, i = 0; i < 15; i++, t += 86400000) {
    const k = key(t), wd = AR(t).getDay();
    if (wd !== 0 && wd !== 6 && _FER_TV.indexOf(k) < 0) return k;
  }
  return key(Date.now() + 86400000);
})();
const H = 3600 * 1000;
const iso = (ms) => new Date(ms).toISOString();
/* Fecha de entrada del pedido, para la columna «Días» (v21.18: entrega − pedido).
   28 días corridos antes de HOY son siempre más de 10 hábiles contra una entrega
   de hoy, caiga donde caiga el fin de semana: así el caso ROJO no depende de qué
   día se corra el test. */
const RECEP_VIEJA = key(Date.now() - 28 * 86400000);

const DATOS = {
  // E30A en curso · E31A terminada y facturada · E32A mañana sin tocar · E33A facturada Y despachada
  // E34A terminada y YA CARGADA AL CAMIÓN, pero SIN facturar (v20.19: el caso urgente)
  prog: [
    { tanda: "E30A", np: "98801", m3: 2.5, fecha_entrega: HOY,
      razon_social: "Bazar Mandarin S.R.L.", zona: "Zona 3 - CABA Oeste", fecha_recep: RECEP_VIEJA },
    { tanda: "E31A", np: "98802", m3: 1.5, fecha_entrega: HOY,
      razon_social: "Perez Zarate S.R.L.", zona: "Zona 1 - CABA Sur", fecha_recep: HOY },
    { tanda: "E32A", np: "98803", m3: 3.0, fecha_entrega: MANANA,
      razon_social: "Simon Zeitune E Hijo S.A", zona: "Retira", fecha_recep: HOY },
    { tanda: "E33A", np: "98804", m3: 4.0, fecha_entrega: HOY,
      razon_social: "Gifel S.R.L.", zona: "Zona 6 - GBA Norte", fecha_recep: HOY },
    { tanda: "E34A", np: "98805", m3: 2.0, fecha_entrega: HOY,
      razon_social: "Nexxo S.R.L.", zona: "Zona 1 - CABA Sur", fecha_recep: HOY },
    // v20.20: E36A está EN CURSO y ya tiene CCN (salió sin cerrar) → 🚚 en la tabla principal.
    // E37A y E38A completan las 3 que disparan el cartel de "salieron sin facturar".
    /* E36A entró HOY y sale HOY → «Días» = 0. Es el control del caso sano:
       sin él, en la tabla sólo quedan E30A (28 días) y E32A (1), porque las
       terminadas se van al panel «a facturar». */
    { tanda: "E36A", np: "98806", m3: 1.0, fecha_entrega: HOY,
      razon_social: "Valher SRL", zona: "Zona 1 - CABA Sur", fecha_recep: HOY },
    { tanda: "E37A", np: "98807", m3: 1.0, fecha_entrega: HOY },
    { tanda: "E38A", np: "98808", m3: 1.0, fecha_entrega: HOY }
  ],
  web: [
    { empresa: "lk", np: 97, tanda: "E30A", fecha_entrega: HOY, razon_social: "Casa Pepe",
      zona: "Zona 3 - CABA Oeste", fecha_recep: HOY,
      m3: 0.8, es_agregado: true, agregado_a_np: 95 }
  ],
  status: [
    { tanda: "E30A", last_pick_op: "EP", pick_legajo: 8, pick_start_ts: iso(Date.now() - 1.5 * H),
      last_arm_op: null, arm_legajo: null, arm_start_ts: null,
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E31A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(Date.now() - 3 * H),
      last_arm_op: "TAP", arm_legajo: 12, arm_start_ts: iso(Date.now() - 2 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E33A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(Date.now() - 5 * H),
      last_arm_op: "TAP", arm_legajo: 8, arm_start_ts: iso(Date.now() - 4 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E34A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(Date.now() - 30 * H),
      last_arm_op: "TAP", arm_legajo: 8, arm_start_ts: iso(Date.now() - 29 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E36A", last_pick_op: "EP", pick_legajo: 12, pick_start_ts: iso(Date.now() - 2 * H),
      last_arm_op: null, arm_legajo: null, arm_start_ts: null,
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E37A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(Date.now() - 32 * H),
      last_arm_op: "TAP", arm_legajo: 8, arm_start_ts: iso(Date.now() - 31 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null },
    { tanda: "E38A", last_pick_op: "TP", pick_legajo: 8, pick_start_ts: iso(Date.now() - 34 * H),
      last_arm_op: "TAP", arm_legajo: 8, arm_start_ts: iso(Date.now() - 33 * H),
      pick_abandonado: false, arm_abandonado: false, pick_fj_ts: null, arm_fj_ts: null }
  ],
  eventos: [
    { legajo: 8,  opcion: "EP",  texto: "E30A", ts_cliente: iso(Date.now() - 1.5 * H), ts_inicio: null },
    { legajo: 8,  opcion: "TP",  texto: "E31A", ts_cliente: iso(Date.now() - 2.5 * H), ts_inicio: iso(Date.now() - 3 * H) },
    { legajo: 12, opcion: "TAP", texto: "E31A", ts_cliente: iso(Date.now() - 1 * H),  ts_inicio: iso(Date.now() - 2 * H) },
    // trabajada y NO está en la programación → cartel "alguien se equivocó"
    { legajo: 8,  opcion: "TP",  texto: "E99Z", ts_cliente: iso(Date.now() - 0.5 * H), ts_inicio: null },
    // legajo de prueba: no tiene que aparecer en ningún lado
    { legajo: 0,  opcion: "EP",  texto: "E32A", ts_cliente: iso(Date.now() - 0.2 * H), ts_inicio: null }
  ],
  fichadas: [
    { legajo: 12, ts_cliente: iso(Date.now() - 4 * H) },
    { legajo: 44, ts_cliente: iso(Date.now() - 1 * H) }   // fichó y no arrancó
  ],
  empleados: [
    { Legajo: 8,  Empleado: "Farias Juan Hilario", hora_entrada: "08:00:00", hora_salida: "17:00:00" },
    { Legajo: 12, Empleado: "Ortiz Franco",        hora_entrada: "08:00:00", hora_salida: "17:00:00" },
    { Legajo: 44, Empleado: "Gomez Ana",           hora_entrada: "08:00:00", hora_salida: "17:00:00" }
  ],
  facturadas: [{ np: "98802" }, { np: "98804" }],
  ccn: [{ opcion: "CCN", texto: "98804", ts_cliente: iso(Date.now() - 6 * H) },
         { opcion: "CCN", texto: "98805", ts_cliente: iso(Date.now() - 5 * H) },
         { opcion: "CCN", texto: "98806", ts_cliente: iso(Date.now() - 1 * H) },
         { opcion: "CCN", texto: "98807", ts_cliente: iso(Date.now() - 7 * H) },
         { opcion: "CCN", texto: "98808", ts_cliente: iso(Date.now() - 8 * H) }],
  deshechas: [],
  /* v21.17 — horas por operario, ya clasificadas por `gv_monitor_horas_operario`.
     La TV NO recalcula nada de esto: si la vista cambia, cambia acá. */
  horas: [
    { legajo: "8", nombre: "Farias Juan Hilario", tandas_pick: 3, prom_hs_pick: 0.84,
      tandas_arm: 1, prom_hs_arm: 1.95, hs_prod: 4.5, hs_mov: 0.8, hs_noprod: 0.6,
      hs_total: 6.2, en_jornada: true },
    { legajo: "12", nombre: "Ortiz Franco", tandas_pick: 0, prom_hs_pick: 0,
      tandas_arm: 2, prom_hs_arm: 1.2, hs_prod: 2.4, hs_mov: 2.1, hs_noprod: 0.5,
      hs_total: 5.4, en_jornada: false }
  ]
};

/* Qué devolver según la URL que pida la página. */
function responder(url) {
  const q = decodeURIComponent(url);
  if (q.includes("/gv_ppp_programacion_diaria")) return DATOS.prog;
  if (q.includes("/PPP_Web_Programacion"))       return DATOS.web;
  if (q.includes("/gv_tanda_status"))            return DATOS.status.filter(s => q.includes(s.tanda));
  if (q.includes("/gv_tandas_deshechas"))        return DATOS.deshechas;
  if (q.includes("/gv_monitor_horas_operario"))  return DATOS.horas;
  if (q.includes("/Facturacion_NP"))             return DATOS.facturadas;
  if (q.includes("/Fichadas_Virgilio"))          return DATOS.fichadas;
  if (q.includes("/Empleados"))                  return DATOS.empleados;
  if (q.includes("/Registros_Produccion_Virgilio")) {
    return q.includes("opcion=in.(CCN,FSS)") ? DATOS.ccn : DATOS.eventos;
  }
  return [];
}

(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires", viewport: { width: 1920, height: 1080 } });
  const p = await ctx.newPage();
  const errs = [];
  p.on("pageerror", (e) => errs.push(e.message));

  await p.route("**/rest/v1/**", (route) => {
    const filas = responder(route.request().url());
    route.fulfill({
      status: 200,
      headers: { "content-type": "application/json",
                 "content-range": "0-" + Math.max(0, filas.length - 1) + "/" + filas.length },
      body: JSON.stringify(filas)
    });
  });

  // ?key=tv = el enrolamiento por única vez, igual que el kiosko del monitor grande
  await p.goto("file://" + TV + "?key=tv", { waitUntil: "domcontentloaded" });
  await p.waitForSelector("#splash.hide", { timeout: 15000 }).catch(() => {});
  await p.waitForTimeout(600);

  const r = await p.evaluate(() => {
    const t = (id) => (document.getElementById(id) || {}).innerHTML || "";
    return {
      arranco: document.getElementById("splash").classList.contains("hide"),
      tandas: t("tandasBox"), fc: t("fcBox"), fcTit: t("fcTit"), tot: t("totBox"),
      ops: t("opsBox"), opsTit: t("opsTit"), tandasTit: t("tandasTit"),
      act: t("actBox"), avisos: t("avisos"),
      m3Pick: (document.getElementById("m3Pick") || {}).textContent || "",
      m3Arm: (document.getElementById("m3Arm") || {}).textContent || "",
      prog: (document.getElementById("progTxt") || {}).textContent || "",
      meta: (document.getElementById("meta") || {}).textContent || "",
      estado: (document.getElementById("estado") || {}).textContent || "",
      // ¿sobresale algo del alto de la pantalla? En una TV no hay cómo scrollear.
      desborda: document.documentElement.scrollHeight > window.innerHeight + 2
    };
  });

  const mal = [];
  const ok = (cond, msg) => { if (!cond) mal.push(msg); };

  ok(errs.length === 0, "errores de página: " + errs.join(" | "));
  ok(r.arranco, "no llegó a pintar el tablero");

  // 3) la tabla de tandas
  ok(/E30A/.test(r.tandas), "falta E30A (la que está en curso)");
  ok(/E32A/.test(r.tandas), "falta E32A (programada para mañana, sin tocar)");
  ok(!/E31A/.test(r.tandas), "E31A está terminada: va a 'a facturar', no a la tabla");
  ok(/spin/.test(r.tandas), "la tanda en curso no muestra el reloj girando");
  ok(/>JF</.test(r.tandas), "no salen las iniciales del operario que la empezó (legajo 8 → JF)");
  ok(/1h3\d/.test(r.tandas), "no sale hace cuánto está abierto el picking (~1h30)");

  // 4) facturada + despachada = fuera del tablero
  ok(!/E33A/.test(r.tandas + r.fc), "E33A está facturada Y despachada: no tiene que aparecer en ningún lado");

  // a facturar, con su ✅
  ok(/E31A/.test(r.fc), "E31A no aparece en 'a facturar'");
  ok(/✅/.test(r.fc), "E31A está facturada (NP 98802) y no tiene el ✅");

  // 4b) v20.21 (Thomas) — la columna SALIÓ del monitor: sólo carga al camión (CCN)
  ok(/Salió/.test(r.fc), "la tabla 'a facturar' no trae la columna Salió");
  ok(/E34A/.test(r.fc), "E34A (terminada y cargada al camión, sin FC) no aparece en 'a facturar'");
  ok(/🚚/.test(r.fc), "E34A tiene CCN (NP 98805): le falta el 🚚 de salió");
  ok(/salio-sinfc/.test(r.fc), "E34A salió y no está facturada: la fila tiene que quedar marcada");
  ok(/3 ya salieron sin FC/.test(r.fcTit), "el título no avisa cuántas se fueron sin factura: " + r.fcTit);
  // v20.21 (Thomas) — el 🚚 también en la tabla principal, y el cartel a partir de 3
  ok(/E36A/.test(r.tandas), "E36A está en curso: tiene que estar en la tabla principal");
  ok(/🚚/.test(r.tandas), "E36A salió (CCN) sin cerrar el picking: le falta el 🚚 en la tabla principal");
  ok(/aviso-salio/.test(r.avisos), "3 tandas salieron sin facturar: falta el cartel de arriba");
  ok(/E34A/.test(r.avisos) && /E37A/.test(r.avisos) && /E38A/.test(r.avisos),
    "el cartel tiene que nombrar las tres tandas: " + r.avisos);

  // m³ terminados hoy
  ok(/1,5/.test(r.m3Pick), "m³ pickeados hoy debería ser 1,5 (E31A) y dice: " + r.m3Pick);
  ok(/1,5/.test(r.m3Arm), "m³ armados hoy debería ser 1,5 (E31A) y dice: " + r.m3Arm);

  // en este momento
  ok(/Pickeando/.test(r.act), "el panel no dice que alguien está pickeando");
  ok(/E30A/.test(r.act), "no dice qué tanda está pickeando");
  ok(/sin arrancar/.test(r.act), "el que fichó y no arrancó (legajo 44) no figura");
  ok(!/Leg 0\b/.test(r.act), "el legajo de prueba 0 se coló en el panel");

  // avisos
  ok(/AGREGADO/.test(r.avisos), "no canta el agregado de la PPP web (LK 0097 sobre el 0095)");
  ok(/E99Z/.test(r.avisos), "no avisa la tanda trabajada que no está en la PPP");

  // m³ por día y camión: E30A (2,5 + 0,8 de la web) + E31A (1,5) + E34A (2,0) = 6,8 hoy
  ok(/9,8/.test(r.tot), "el total de hoy debería ser 9,8 m³ (E30A 3,3 + E31A 1,5 + E34A 2,0 + E36A/E37A/E38A 1,0 c/u)");
  ok(/E30/.test(r.tot), "no agrupa por camión (E30)");

  // header
  ok(/4\/7/.test(r.prog), "la barra de avance debería decir 4/7 (E31A, E34A, E37A y E38A terminadas de 7 en ventana), dice: " + r.prog);
  ok(/2 en curso/.test(r.meta), "el header no cuenta las tandas en curso (E30A y E36A): " + r.meta);

  /* ── v21.17 · lo que pidió Damián (via Marianela, 22/09) ───────────────────
     UNA fila por tanda con el N° de pedido, el cliente resumido, los días que
     lleva esperando, la zona y el progreso como semáforo. */
  ok(/N° Pedido/.test(r.tandas) && /Cliente/.test(r.tandas) && /Zona/.test(r.tandas)
     && /Progreso/.test(r.tandas), "faltan las columnas nuevas de la tabla de tandas");
  ok(/98801/.test(r.tandas), "la tabla no muestra el N° de pedido");
  /* E30A lleva la NP de ISIS (Bazar Mandarin) y la web (Casa Pepe): UNA fila,
     el primer cliente + «+1». Si esto se rompe, volvió la fila por NP. */
  ok(/Bazar Mandarin/.test(r.tandas), "no resume el cliente de la tanda");
  ok(!/S\.R\.L/.test(r.tandas), "no le saca la forma societaria al cliente (ocupa lugar y no distingue)");
  ok(/\+1<\/b>/.test(r.tandas), "una tanda con dos clientes tiene que decir «+1», no repetir la fila");
  ok((r.tandas.match(/E30A/g) || []).length === 1, "E30A aparece más de una vez: la tanda va en UNA fila");
  /* v21.19 (Thomas: "acorta"): la etiqueta larga no entraba en la columna y se
     cortaba por un carácter. Ahora ciudad y punto cardinal van en sigla. */
  ok(/Z3 CO/.test(r.tandas), "no acorta la zona (Zona 3 - CABA Oeste → Z3 CO)");
  ok(/Z1 CS/.test(r.tandas), "no acorta la zona (Zona 1 - CABA Sur → Z1 CS)");
  ok(!/CABA/.test(r.tandas), "la zona sigue escribiendo CABA entero: no se acortó");
  ok(/Retira/.test(r.tandas), "Retira NO es un número de zona y tiene que verse tal cual");
  /* Semáforo: E30A pickeando (ámbar + rojo), E36A igual; ningún ✅ suelto en
     la columna de progreso. */
  ok(/s-curso/.test(r.tandas), "el semáforo no marca lo que está EN CURSO");
  ok(/s-no/.test(r.tandas), "el semáforo no marca lo que NO se empezó");
  /* Días = hábiles entre la fecha del pedido y la de programación (Thomas, 22/09).
     E30A entró hace 28 días y se entrega HOY → más de 10 hábiles, rojo. E31A entró
     hoy y sale hoy → 0. ⚠ E32A entró hoy y sale MAÑANA: si el número se calculara
     "hasta hoy" daría 0 y este test no lo distinguiría — por eso se mira E32A = 1. */
  /* Se mira la celda de Días, no el color suelto: #f87171 ya lo usa el reloj de
     una fase que lleva más de 2 h, así que un `/#f87171/` pelado da verde solo. */
  ok(/class="cen t-dias" style="color:#f87171"/.test(r.tandas),
     "un pedido de hace 28 días no se marca como demorado en la columna Días");
  ok(/class="cen t-dias" style="color:#94a3b8">0</.test(r.tandas),
     "un pedido que entró hoy y sale hoy tiene que decir 0 y no marcar demora");
  ok(/class="cen t-dias" style="color:#94a3b8">1</.test(r.tandas),
     "un pedido que entró hoy y sale MAÑANA tiene que decir 1 (entrega − pedido, no 'hasta hoy')");
  ok(/Mié|Lun|Mar|Jue|Vie|Sáb|Dom/.test(r.tandasTit), "el título no dice el día de la semana: " + r.tandasTit);
  /* La columna «Salida» salió de la tabla: el día tiene que quedar igual a la
     vista, como separador, o hoy y mañana se mezclan sin que se note. */
  ok(/<tr class="dia"><td colspan="7">/.test(r.tandas), "falta el separador de día en la tabla de tandas");
  ok((r.tandas.match(/<tr class="dia">/g) || []).length === 2,
     "tiene que haber UN separador por día de entrega (hoy y mañana)");

  // ── v21.17 · tabla de horas por operario
  ok(/Farias J\./.test(r.ops), "la tabla de operarios no muestra el nombre corto");
  ok(/Ortiz F\./.test(r.ops), "falta un operario de la tabla de horas");
  ok(/Prom hs/.test(r.ops) && /Hs no/.test(r.ops), "faltan las columnas de horas pedidas");
  ok(/0,8/.test(r.ops), "no muestra el promedio de horas por tanda pickeada");
  ok(/6,9/.test(r.ops) && /11,6/.test(r.ops),
     "la fila de Total no suma bien (prod 4,5+2,4=6,9 · total 6,2+5,4=11,6): " + r.ops.replace(/<[^>]*>/g, " "));
  /* El % va sobre el tiempo MEDIDO (prod + mov + no prod), no sobre la jornada:
     CR y RR quedan abiertos mientras el operario hace otra cosa, así que los
     baldes pueden sumar más que el total de horas del día. */
  ok(/63% productivas/.test(r.opsTit),
     "el título no dice el % de horas productivas (6,9 de 6,9+2,9+1,1 = 63%): " + r.opsTit);
  ok(/en vivo/.test(r.estado), "el estado no quedó 'en vivo': " + r.estado);

  // sin scroll: la TV no tiene cómo moverse
  ok(!r.desborda, "el contenido se sale de la pantalla y en una TV no hay forma de scrollear");

  await b.close();

  if (mal.length) {
    console.log("mon-tv: ✗ FAIL\n  - " + mal.join("\n  - "));
    process.exit(1);
  }
  console.log("mon-tv: ✓ OK (" + KB.toFixed(0) + " KB, sólo lectura, mismas fuentes que el monitor grande)");
})();
