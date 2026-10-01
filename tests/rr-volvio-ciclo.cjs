/* v25.95 — un pedido que SALIÓ y VOLVIÓ (↩ s/salida = FSS) y se recarga arranca el plazo de
   control de nuevo. Caso del 01/10: LK 0122 (carga 29/09, volvió 30/09, recargado 01/10) y
   LK 0177 (carga 28/09, volvió 29/09, recargado 01/10) salían VENCIDOS en Recepción Remitos
   y la PPP mandó la alarma CRA falsa, porque el reloj tomaba la PRIMERA carga de todas.
   A) _pppCargasCiclo (la PPP): el reloj arranca en la primera carga posterior a la vuelta.
   B) el que volvió y no se recargó: fuera de «cargados» y dentro de «volvió» (badge).
   C) sin vuelta: igual que antes (la primera carga).
   D) la fila de NP de la Programación dibuja el badge ↩ VOLVIÓ.
   E) la vista de RR (sql del repo) calcula first_load por ciclo.
   F) en vivo: en «Pedidos atrasados» (Luis, 01/10: *"está bien que se quede en atrasados, pero
      que esté con el badge"*) la NP que volvió lleva ↩ VOLVIÓ y la de al lado no. */
const fs = require("fs"), path = require("path");
const html = fs.readFileSync(path.join(__dirname, "..", "index.html"), "latin1");
const sql = fs.readFileSync(path.join(__dirname, "..", "sql", "vista_control_remitos_ciclo_v2595.sql"), "utf8");
const mal = [];
function tomar(src, inicio, fin) {
  const i = src.indexOf(inicio); if (i < 0) throw new Error("no está: " + inicio);
  const j = src.indexOf(fin, i); return src.slice(i, j + fin.length);
}
const f = tomar(html, "function _pppCargasCiclo(data, fssMap, maxCcn) {", "\n}\n");
const ciclo = new Function(f + "\nreturn _pppCargasCiclo;")();
const ms = (s) => Date.parse(s);
const ev = (np, s) => ({ texto: np + "|E30A|Horacio|1", ts_cliente: s });
const data = [
  ev("LK 0122", "2026-09-29T14:57:24Z"), ev("LK 0122", "2026-10-01T14:53:24Z"),   // salió, volvió, recargado
  ev("LK 0177", "2026-09-28T11:44:22Z"),                                            // salió y volvió, sin recargar
  ev("LK 0050", "2026-10-01T12:48:00Z"), ev("LK 0050", "2026-10-01T12:50:00Z"),   // normal, dos CCN
];
const fss = new Map([["LK 0122", ms("2026-09-30T11:13:28Z")], ["LK 0177", ms("2026-09-29T11:10:55Z")]]);
const maxCcn = new Map();
for (const e of data) { const t = e.texto.split("|")[0]; const m = ms(e.ts_cliente); if (!maxCcn.has(t) || m > maxCcn.get(t)) maxCcn.set(t, m); }
const r = ciclo(data, fss, maxCcn);

// A
if (!r.set.has("LK 0122")) mal.push("A: LK 0122 recargado tiene que estar cargado");
if (r.loadMs.get("LK 0122") !== ms("2026-10-01T14:53:24Z"))
  mal.push("A: el reloj de LK 0122 tiene que arrancar en la carga del 01/10, arrancó en " + new Date(r.loadMs.get("LK 0122")).toISOString());
if (r.volvio.has("LK 0122")) mal.push("A: LK 0122 ya se recargó: no lleva badge VOLVIÓ");
// B
if (r.set.has("LK 0177")) mal.push("B: LK 0177 volvió y no se recargó: no puede figurar cargado");
if (r.loadMs.has("LK 0177")) mal.push("B: LK 0177 sin recargar no tiene reloj de control");
if (r.volvio.get("LK 0177") !== ms("2026-09-29T11:10:55Z")) mal.push("B: LK 0177 tiene que estar en «volvió» con la fecha del ↩ s/salida");
// C
if (r.loadMs.get("LK 0050") !== ms("2026-10-01T12:48:00Z")) mal.push("C: sin vuelta, el reloj es la primera carga");

// D
const fila = html.indexOf("'<span class=\"pga-salio\" title=\"Ya sali");
const badge = html.indexOf("(_pgaVolvio(r) ? '<span class=\"pga-volvio\"");
if (fila < 0 || badge < 0 || badge - fila > 800) mal.push("D: la fila de NP tiene que dibujar el badge ↩ VOLVIÓ al lado del 🚚");
if (!/\.pga-volvio\{/.test(html)) mal.push("D: falta el estilo .pga-volvio");
if (!/_pppVolvio = _cic\.volvio/.test(html)) mal.push("D: pppRefreshEntregado tiene que publicar el mapa de los que volvieron");

// E
const sinCom = sql.replace(/--[^\n]*/g, "");
if (!/fss_prev AS \(/.test(sinCom)) mal.push("E: la vista de RR tiene que calcular la última vuelta (fss_prev)");
if (!/min\(ccn_raw\.ts_cliente\) FILTER \(WHERE ccn_raw\.ts_cliente > COALESCE\(fp\.fss_prev/.test(sinCom))
  mal.push("E: first_load tiene que ser la primera carga POSTERIOR a la última vuelta");
if (!/security_invoker = true/.test(sinCom)) mal.push("E: la vista tiene que conservar security_invoker");

function fin() {
  if (mal.length) { console.error("✗ rr-volvio-ciclo:\n  " + mal.join("\n  ")); process.exit(1); }
  console.log("✓ rr-volvio-ciclo: el reloj de RR arranca en la carga nueva y la PPP marca ↩ VOLVIÓ (también en atrasados)");
}

// F) en vivo
let chromium;
try { ({ chromium } = require("/opt/node22/lib/node_modules/playwright")); }
catch (_e) { try { ({ chromium } = require("playwright")); } catch (_e2) { chromium = null; } }
if (!chromium) { fin(); }
else (async () => {
  const b = await chromium.launch();
  try {
    const ctx = await b.newContext({ timezoneId: "America/Argentina/Buenos_Aires" });
    const p = await ctx.newPage();
    await p.route("**/rest/v1/**", (rt) => rt.fulfill({ status: 200, headers: { "content-type": "application/json" }, body: "[]" }));
    await p.goto("file://" + path.join(__dirname, "..", "index.html"), { waitUntil: "domcontentloaded" });
    const o = await p.evaluate(() => {
      const hoy = _pppHoyKey();
      const d = _pppKeyDate(hoy); d.setDate(d.getDate() - 2);
      const f = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
      const fila = (np) => ({ fecha: f, tanda: "F28A", np: np, np_num: null, cod: "4042", razon_social: "Cliente " + np,
        localidad: "Soldati", zona: "Zona 1 - CABA Sur", zona_corta: "Zona 1", empresa: "LK", origen: "web", m3: 0.3,
        estado: "facturado", estado_orden: 4, clave: np, pide_horario: false, horario_fecha: null, horario_franja: null,
        horario_origen: null, barrio: "Soldati", fecha_pedido: null });
      _pppSearch = ""; _pgaOpenD = {}; _pgaOpenT = {}; _pgaOpenN = {};
      try { localStorage.removeItem("vir_patr_colapsado"); } catch (_e) {}
      _patrRows = [fila("LK 0177"), fila("LK 0050")];
      _pppVolvio = new Map([["LK 0177", Date.now() - 86400000]]);
      const k = f.replace(/-/g, "");
      _pgaOpenD[k] = true; _pgaOpenT[k + "|F28A"] = true;
      const h = _patrHtml();
      // una fila de NP por trozo: así el badge de una no se cuenta para la otra
      const filas = h.split('<div class="pga-nrow">').slice(1);
      const de = (np) => filas.filter((x) => x.indexOf('<span class="pga-np">' + np + '</span>') >= 0)[0];
      const r177 = de("LK 0177"), r050 = de("LK 0050");
      return { hay177: !!r177, hay050: !!r050, filas: filas.length,
        badge177: !!r177 && /pga-volvio/.test(r177), badge050: !!r050 && /pga-volvio/.test(r050) };
    });
    if (!o.hay177 || !o.hay050) mal.push("F: las dos NP tienen que verse en Pedidos atrasados con el día y la tanda abiertos (filas: " + o.filas + ")");
    else {
      if (!o.badge177) mal.push("F: LK 0177 volvió y en Pedidos atrasados no lleva el badge ↩ VOLVIÓ");
      if (o.badge050) mal.push("F: LK 0050 no volvió y lleva el badge ↩ VOLVIÓ");
    }
  } catch (e) { mal.push("F: " + (e && e.message || e)); }
  finally { await b.close(); }
  fin();
})();
