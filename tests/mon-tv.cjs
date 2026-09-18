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
const MANANA = key(Date.now() + 86400000);
const H = 3600 * 1000;
const iso = (ms) => new Date(ms).toISOString();

const DATOS = {
  // E30A en curso · E31A terminada y facturada · E32A mañana sin tocar · E33A facturada Y despachada
  // E34A terminada y YA CARGADA AL CAMIÓN, pero SIN facturar (v20.19: el caso urgente)
  prog: [
    { tanda: "E30A", np: "98801", m3: 2.5, fecha_entrega: HOY },
    { tanda: "E31A", np: "98802", m3: 1.5, fecha_entrega: HOY },
    { tanda: "E32A", np: "98803", m3: 3.0, fecha_entrega: MANANA },
    { tanda: "E33A", np: "98804", m3: 4.0, fecha_entrega: HOY },
    { tanda: "E34A", np: "98805", m3: 2.0, fecha_entrega: HOY }
  ],
  web: [
    { empresa: "lk", np: 97, tanda: "E30A", fecha_entrega: HOY, razon_social: "Casa Pepe",
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
         { opcion: "CCN", texto: "98805", ts_cliente: iso(Date.now() - 5 * H) }],
  deshechas: []
};

/* Qué devolver según la URL que pida la página. */
function responder(url) {
  const q = decodeURIComponent(url);
  if (q.includes("/gv_ppp_programacion_diaria")) return DATOS.prog;
  if (q.includes("/PPP_Web_Programacion"))       return DATOS.web;
  if (q.includes("/gv_tanda_status"))            return DATOS.status.filter(s => q.includes(s.tanda));
  if (q.includes("/gv_tandas_deshechas"))        return DATOS.deshechas;
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

  // 4b) v20.19 (Thomas) — la columna SALIÓ del monitor: sólo carga al camión (CCN)
  ok(/Salió/.test(r.fc), "la tabla 'a facturar' no trae la columna Salió");
  ok(/E34A/.test(r.fc), "E34A (terminada y cargada al camión, sin FC) no aparece en 'a facturar'");
  ok(/🚚/.test(r.fc), "E34A tiene CCN (NP 98805): le falta el 🚚 de salió");
  ok(/salio-sinfc/.test(r.fc), "E34A salió y no está facturada: la fila tiene que quedar marcada");
  ok(/ya salió sin FC/.test(r.fcTit), "el título no avisa cuántas se fueron sin factura: " + r.fcTit);

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
  ok(/6,8/.test(r.tot), "el total de hoy debería ser 6,8 m³ (E30A 3,3 + E31A 1,5 + E34A 2,0)");
  ok(/E30/.test(r.tot), "no agrupa por camión (E30)");

  // header
  ok(/2\/4/.test(r.prog), "la barra de avance debería decir 2/4 (E31A y E34A terminadas de 4 en ventana), dice: " + r.prog);
  ok(/1 en curso/.test(r.meta), "el header no cuenta la tanda en curso: " + r.meta);
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
