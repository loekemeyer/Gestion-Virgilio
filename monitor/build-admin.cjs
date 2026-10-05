/* monitor/build-admin.cjs — genera monitor/admin.html a partir de monitor/tv.html.
 *
 * Por qué (pedido de Luis, 2026-10-01): «Mon. Admin» es el MISMO tablero de la pared pero
 * clickeable — cada celda abre su desglose en un pop-up. El tablero de la pared (tv.html) es
 * de SOLO LECTURA y liviano (lo blinda tests/mon-tv.cjs: nada de onclick, techo 100 KB), así
 * que no puede volverse interactivo sin romper la TV. En vez de copiar las ~1.480 líneas del
 * tablero a mano (y que las dos vistas se desvíen con el tiempo — el pozo que el CLAUDE.md
 * repite), admin.html se GENERA desde tv.html: la lógica del tablero vive en UN solo lado y
 * acá sólo se le pega encima la capa de interacción. tests/mon-admin.cjs vuelve a correr este
 * build y falla si admin.html quedó viejo respecto de tv.html.
 *
 * Los desgloses salen de datos que el tablero YA tiene en memoria al pintar: m³/h de un
 * operario → las tandas que cerró; una celda de NPs por Día → sus NP; una tanda → su detalle.
 * Única consulta propia (v26.33/v26.35, Luis): al abrir una tanda, sus EP/TP y AP/TAP para mostrar
 * la hora de inicio y fin del picking y del armado (por opcion + ts_cliente, ~1 ms). Si falla,
 * el pop-up queda igual.
 *
 * Uso:  node monitor/build-admin.cjs       (regenera monitor/admin.html)
 */
"use strict";
const fs = require("fs");
const path = require("path");

/* Reemplazo que FALLA RUIDOSO si el ancla no está exactamente una vez: si tv.html cambia un
 * punto donde se inyecta, el build se cae en vez de generar un admin.html mudo. */
function rep(src, find, repl) {
  const i = src.indexOf(find);
  if (i < 0) throw new Error("build-admin: no encontré el ancla:\n" + find.slice(0, 120));
  if (src.indexOf(find, i + 1) >= 0) throw new Error("build-admin: el ancla aparece 2+ veces:\n" + find.slice(0, 120));
  return src.slice(0, i) + repl + src.slice(i + find.length);
}

const BANNER = `
<!-- ═══════════════════════════════════════════════════════════════════════════
     Mon. Admin — ESPEJO INTERACTIVO del monitor de pared.
     ⚠ ARCHIVO GENERADO desde monitor/tv.html por monitor/build-admin.cjs.
        NO EDITAR A MANO. Todo cambio del tablero se hace en tv.html y se regenera
        con \`node monitor/build-admin.cjs\`. Lo sostiene tests/mon-admin.cjs (falla
        si admin.html quedó desincronizado de tv.html).
     Qué agrega sobre tv.html: celdas clickeables (m³/h picking · armado, las de
     «NPs por Día» y las tandas) que abren un pop-up con el desglose, armado con lo
     que el tablero YA tiene en memoria. Es la pestaña «🛠️ Mon. Admin» del monitor
     del admin; la TV de pared sigue usando tv.html, liviano y de solo lectura.
     ═══════════════════════════════════════════════════════════════════════════ -->`;

const CSS = `
/* ── Capa admin (sólo admin.html, inyectada por build-admin.cjs) ──────────── */
.cx{cursor:pointer}
.cx:hover{outline:2px solid #38bdf8;outline-offset:-2px;background:#0e1830}
#pop{position:fixed;inset:0;z-index:50;display:flex;align-items:center;justify-content:center;
  background:rgba(2,6,23,.74);padding:3vh 3vw}
#pop.hide{display:none!important}
.pop-card{background:#0f1a2e;border:1px solid #334155;border-radius:1vh;min-width:min(78vw,360px);
  max-width:min(92vw,920px);max-height:88vh;overflow:auto;box-shadow:0 10px 40px rgba(0,0,0,.6)}
.pop-hd{display:flex;align-items:center;justify-content:space-between;gap:1vw;padding:1.1vh 1.3vw;
  border-bottom:1px solid #1e293b;position:sticky;top:0;background:#0f1a2e;z-index:1}
.pop-hd h3{font-size:calc(2.4*var(--u));color:#f8fafc;font-weight:900;margin:0;line-height:1.2}
.pop-x{cursor:pointer;background:#1e293b;color:#e2e8f0;border:1px solid #334155;border-radius:.6vh;
  font-size:calc(2.2*var(--u));font-weight:900;padding:.2vh 1vw;line-height:1.3;flex:0 0 auto}
.pop-x:hover{background:#334155}
.pop-bd{padding:1.1vh 1.3vw;font-size:calc(2.1*var(--u));color:#e2e8f0}
.pop-bd table{width:100%;border-collapse:collapse;margin:.4vh 0}
.pop-bd th{font-size:calc(1.7*var(--u));color:#93c5fd;text-align:left;padding:.4vh .7vw;
  border-bottom:1px solid #1e293b;text-transform:uppercase;letter-spacing:.03em}
.pop-bd td{font-size:calc(2*var(--u));padding:.4vh .7vw;border-bottom:1px solid #16203a;font-weight:700}
.pop-bd td.num,.pop-bd th.num{text-align:right;font-variant-numeric:tabular-nums}
.pop-bd table.pop-cmp{width:auto;margin:.4vh auto}
.pop-bd table.pop-cmp th,.pop-bd table.pop-cmp td{padding:.4vh 1vw;text-align:center}
.pop-tot td{border-top:2px solid #334155;font-weight:900;color:#f8fafc}
.pop-sub{color:#94a3b8;font-size:calc(1.85*var(--u));margin:.2vh 0 1vh;line-height:1.4}
.pop-k{color:#f8fafc;font-weight:900}
.pop-empty{color:#64748b;padding:1.5vh;text-align:center;font-weight:700}
/* v26.50 (Luis): puntaje 1-10 de picking — SÓLO en el admin (la TV de los operarios no lo lleva). */
.op-punt{font-weight:900;text-align:center;font-variant-numeric:tabular-nums;border-left:1px solid #1e293b}
.op-punt.prov{color:#94a3b8;font-weight:700}
.op-punt.alto{color:#4ade80}.op-punt.bajo{color:#f87171}
.op-aj{color:#94a3b8;font-weight:600;font-size:.72em}
</style>`;

/* La capa admin va DENTRO del IIFE principal, así ve a esc/n1/nH/npLabel/resumirCliente/
 * diaEtiqueta/monCamionDeTanda/nombreCorto/fmtMin/resumenDias/RD_EST ya declaradas.
 * (Las dos únicas regex con backslash van con \\ para sobrevivir el string de este generador.) */
const ADMIN = `
/* ═══════════════════════════════════════════════════════════════════════════
   CAPA ADMIN — inyectada por monitor/build-admin.cjs (sólo en admin.html).
   Clickear una celda abre el desglose con datos que el tablero ya tiene en memoria.
   ═══════════════════════════════════════════════════════════════════════════ */
function abrirPop(titulo, html) {
  var p = el("pop"); if (!p) return;
  p.innerHTML = '<div class="pop-card"><div class="pop-hd"><h3>' + titulo + '</h3>' +
    '<span class="pop-x" id="popX" title="Cerrar (Esc)">✕ Cerrar</span></div>' +
    '<div class="pop-bd">' + html + '</div></div>';
  p.classList.remove("hide");
}
function cerrarPop() { var p = el("pop"); if (p) { p.classList.add("hide"); p.innerHTML = ""; } }
function popNum(x) { return '<td class="num">' + n1(x) + '</td>'; }
function popTablaTandas(pares) {   // [[tanda, m3], …]
  if (!pares.length) return '<div class="pop-empty">Sin tandas</div>';
  var tot = 0;
  var body = pares.map(function (p) { tot += Number(p[1]) || 0;
    return '<tr><td class="pop-k">' + esc(p[0]) + '</td>' + popNum(p[1]) + '</tr>'; }).join("");
  return '<table><thead><tr><th>Tanda</th><th class="num">m³</th></tr></thead><tbody>' +
    body + '<tr class="pop-tot"><td>Total</td>' + popNum(tot) + '</tr></tbody></table>';
}
function popRitmo(leg, sub) {
  var D = window.__MA_D || {}, M = window.__MA_M3 || {};
  var row = (D.horas || []).filter(function (o) { return String(o.legajo) === String(leg); })[0] || {};
  var det = (M[leg] || { pick: {}, arm: {} })[sub] || {};   // v26.55: el m³ de una tanda pickeada ya es lo PICKEADO
  var pares = Object.keys(det).map(function (t) { return [t, det[t]]; }).sort(function (a, b) { return b[1] - a[1]; });
  var tot = pares.reduce(function (s, p) { return s + (Number(p[1]) || 0); }, 0);
  var hs = Number(sub === "pick" ? row.hs_pick : row.hs_arm) || 0;
  var lab = sub === "pick" ? "picking" : "armado";
  var head = '<div class="pop-sub" style="text-align:center"><span class="pop-k">' + esc(nombreCorto(row.nombre, leg)) + '</span></div>';
  if (!pares.length) return head + '<div class="pop-empty">No cerró ninguna tanda de ' + lab + ' hoy' +
    (hs > 0.05 ? ' (tiene ' + nH(hs) + ' h cargadas)' : '') + '</div>';
  /* v25.93 (Luis): Tanda · m³ · Min trab · Ritmo, y Total. Min trab = de punta a punta (apertura → cierre
     TP/TAP); las pausas adentro (baño, comida, limpieza, conteo, timbre, permiso) van entre paréntesis
     «60 (-2)» y el ritmo es el real, de punta a punta (Luis, v25.97). */
  var op = sub === "pick" ? "TP" : "TAP", PAUSA = { AT: 1, PB: 1, Limp: 1, PC: 1, CT: 1, Perm: 1 };
  var ms = function (x) { return new Date(x).getTime(); };
  var evs = (D.eventos || []).filter(function (ev) {
    return String(ev.legajo == null ? "" : ev.legajo).trim() === String(leg) && ev.ts_inicio && dayKey(ev.ts_cliente) === hoyKey(); });
  var pausas = evs.filter(function (ev) { return PAUSA[ev.opcion]; }).map(function (ev) { return [ms(ev.ts_inicio), ms(ev.ts_cliente)]; });
  var mins = {}, pmin = {};
  evs.forEach(function (ev) {
    if (ev.opcion !== op) return;
    var t = String(ev.texto || "").trim().toUpperCase(), i = ms(ev.ts_inicio), f = ms(ev.ts_cliente);
    if (!t || !isFinite(i) || !isFinite(f) || f <= i) return;
    var p = 0; pausas.forEach(function (q) { var o = Math.min(f, q[1]) - Math.max(i, q[0]); if (o > 0) p += o; });
    mins[t] = (mins[t] || 0) + (f - i) / 60000; pmin[t] = (pmin[t] || 0) + p / 60000;
  });
  var rit = function (m3, mi) { return (mi > 0.5 && m3 > 0) ? n1(m3 / (mi / 60)) : "—"; };
  var fm = function (mi, pa) { if (!(mi > 0)) return "—"; var r = Math.round(pa);
    return Math.round(mi) + (r > 0 ? ' <span style="color:#fca5a5">(-' + r + ')</span>' : ''); };
  /* v26.54 (Luis, 04/10: «¿cuánto debería decir si era difícil?»): en PICKING, dos columnas más —
     Dif. (grado 1-10 y nivel de la tanda, GV_Picking_Tanda vía gv_picking_grado) y Ajust. = ritmo ×
     (1 + 0,1 × (grado − 5)): Baja ×0,6-0,7 · Media ×0,8-1,0 · Alta ×1,1-1,3 · Muy alta ×1,4-1,5.
     Sin grado todavía (el caché se recalcula cada 10 min) la fila dice «—» y no entra al total ajustado. */
  var esPick = sub === "pick", G = esPick ? (window.__MA_GRADO || {}) : {};
  var gradoDe = function (t) { return G[t + "|" + leg] || G[t] || null; };
  var tm = 0, tp = 0, tAj = 0, tAjOk = true, body = pares.map(function (p) { var mi = mins[p[0]] || 0, pa = pmin[p[0]] || 0; tm += mi; tp += pa;
    var extra = "";
    if (esPick) {
      var g = gradoDe(p[0]), mu = g ? Number(g.multiplicador) : NaN;
      if (g && isFinite(mu)) { tAj += (Number(p[1]) || 0) * mu;
        extra = '<td title="' + esc("grado " + g.grado + " de 10 · " + (g.lineas || 0) + " líneas · " + (g.paradas || 0) + " paradas · " + (g.esc || 0) + " con escalera · ×" + n1(mu)) + '">' +
          g.grado + ' <small style="color:#94a3b8">' + esc(String(g.nivel || "")) + '</small></td><td class="pop-k">' + rit((Number(p[1]) || 0) * mu, mi) + '</td>'; }
      else { tAjOk = false; extra = '<td title="todavía sin grado (el caché se recalcula cada 10 min)">—</td><td>—</td>'; }
    }
    return '<tr><td class="pop-k">' + esc(p[0]) + '</td><td>' + n1(p[1]) + '</td><td>' + fm(mi, pa) + '</td><td>' +
      rit(Number(p[1]) || 0, mi) + '</td>' + extra + '</tr>'; }).join("");
  var thAj = esPick ? '<th title="Dificultad de la tanda: grado 1-10 (decil de min/caja) y nivel">Dif.</th><th title="Ritmo × (1 + 0,1 × (grado − 5)): Baja ×0,6-0,7 · Media ×0,8-1,0 · Alta ×1,1-1,3 · Muy alta ×1,4-1,5">Ajust. m³/h</th>' : '';
  var tdAj = esPick ? '<td></td><td class="pop-k">' + (tAjOk && pares.length ? rit(tAj, tm) : "—") + '</td>' : '';
  var nota = esPick ? '<div class="pop-sub" style="margin-top:.6vh">Ajust. = ritmo × (1 + 0,1 × (grado − 5)). Baja ×0,6-0,7 · Media ×0,8-1,0 · Alta ×1,1-1,3 · Muy alta ×1,4-1,5. Una tanda difícil a 0,5 m³/h vale 0,55-0,65.</div>' : '';
  return head + '<table class="pop-cmp"><thead><tr><th>Tanda</th><th>m³' + (esPick ? ' pick.' : '') + '</th><th>Min trab</th><th>Ritmo m³/h</th>' + thAj + '</tr></thead><tbody>' +
    body + '<tr class="pop-tot"><td>Total</td><td>' + n1(tot) + '</td><td>' + fm(tm, tp) +
    '</td><td>' + rit(tot, tm) + '</td>' + tdAj + '</tr></tbody></table>' + nota;
}
/* v26.54: grado de dificultad por tanda (gv_picking_grado, lectura con la clave pública). Se pide para las
   tandas de picking que el tablero ya tiene en __MA_M3, se guarda por «tanda|legajo» y por tanda, y se
   relee en cada render si pasaron 5 min o aparecieron tandas nuevas. Si falla, el pop-up dice «—». */
var GRADO_TS = 0, GRADO_KEYS = "", GRADO_VUELO = false;
function cargarGrados() {
  var M = window.__MA_M3 || {}, ts = {};
  Object.keys(M).forEach(function (leg) { Object.keys((M[leg] || {}).pick || {}).forEach(function (t) { ts[t] = 1; }); });
  var lista = Object.keys(ts).sort(), key = lista.join(",");
  if (!lista.length || GRADO_VUELO) return;
  if (key === GRADO_KEYS && (Date.now() - GRADO_TS) < 300000) return;
  GRADO_VUELO = true;
  fetch(SB_URL + "/rest/v1/rpc/gv_picking_grado", { method: "POST", cache: "no-store",
    headers: Object.assign({ "Content-Type": "application/json" }, H), body: JSON.stringify({ p_tandas: lista }) })
  .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
  .then(function (rows) {
    var g = {};
    (rows || []).forEach(function (o) { var t = String(o.tanda || "").toUpperCase(); if (!t) return;
      g[t + "|" + String(o.legajo)] = o; if (!g[t]) g[t] = o; });
    window.__MA_GRADO = g; GRADO_TS = Date.now(); GRADO_KEYS = key; GRADO_VUELO = false;
    if (window.__MA_INSTR) window.__MA_INSTR();
  }).catch(function (e) { GRADO_VUELO = false; console.warn("[admin] gv_picking_grado:", e && e.message); });
}
function popHoras(leg) {
  /* v25.89 (Luis): dos columnas. Prod = SÓLO picking y armado; todo lo demás es No prod, tiempo muerto incluido. */
  var D = window.__MA_D || {};
  var o = (D.horas || []).filter(function (x) { return String(x.legajo) === String(leg); })[0] || {};
  var N = function (x) { return Number(x) || 0; };
  var pick = N(o.hs_pick), arm = N(o.hs_arm), mov = N(o.hs_mov), dec = N(o.hs_noprod), tot = N(o.hs_total);
  var otros = Math.max(0, N(o.hs_prod) - pick - arm);
  var muerto = Math.max(0, tot - N(o.hs_prod) - mov - dec);
  var noTot = Math.max(0, tot - pick - arm);
  var P = [["Picking", pick], ["Armado", arm]];
  var Q = [["Movimiento (guardado · racks · recepción)", mov], ["Carga camión · remitos", otros],
    ["Baño · comida · timbre · limpieza · conteo · permiso · cancelaciones", dec], ["Tiempo muerto", muerto]];
  var n = Math.max(P.length, Q.length), body = "";
  for (var i = 0; i < n; i++) {
    var a = P[i], b = Q[i];
    body += '<tr>' + (a ? '<td>' + esc(a[0]) + '</td><td class="num">' + nH(a[1]) + '</td>' : '<td></td><td></td>') +
      '<td style="border-left:2px solid #334155">' + esc(b[0]) + '</td><td class="num">' + nH(b[1]) + '</td></tr>';
  }
  body += '<tr class="pop-tot"><td>Total prod</td><td class="num">' + nH(pick + arm) + '</td>' +
    '<td style="border-left:2px solid #334155">Total no prod</td><td class="num">' + nH(noTot) + '</td></tr>';
  return '<div class="pop-sub">' + esc(nombreCorto(o.nombre, leg)) + ' · jornada ' + nH(tot) + ' h' + (o.en_jornada ? '' : ' · ✓ ya cerró la jornada') + '</div>' +
    '<table><thead><tr><th colspan="2" style="color:#4ade80">Prod</th><th colspan="2" style="color:#fbbf24;border-left:2px solid #334155">No prod</th></tr></thead><tbody>' + body + '</tbody></table>';
}
var POP_EST = { salio: "Salió", facturado: "Facturado", armado: "Armado", proceso: "En proceso", pendiente: "Pendiente" };
function popDiaBucket(dia, sub) {
  var D = window.__MA_D || {}, desp = D.despachadas || new Set();
  var filas = (D.arbol || []).filter(function (r) {
    if (String(r.fecha || "").slice(0, 10) !== dia) return false;
    var np = String(r.np || "").trim().replace(/\\.0+$/, "");
    var sal = desp.has(np);
    if (sub === "salio") return sal;
    var est = RD_EST.indexOf(r.estado) >= 0 ? r.estado : "pendiente";
    return est === sub && !sal;
  });
  var head = '<div class="pop-sub">' + esc(diaEtiqueta(dia)) + ' · ' + (POP_EST[sub] || sub) + ' · ' + filas.length + ' NP</div>';
  if (!filas.length) return head + '<div class="pop-empty">Ninguna NP en este estado</div>';
  var tot = 0;
  var body = filas.map(function (r) {
    tot += Number(r.m3) || 0;
    return '<tr><td class="pop-k">' + esc(npLabel(r.empresa, r.np)) + '</td>' +
      '<td>' + esc(resumirCliente(r.razon_social || r.cliente || "") || "—") + '</td>' +
      '<td>' + esc(String(r.tanda || "—").toUpperCase()) + '</td>' + popNum(r.m3) + '</tr>';
  }).join("");
  return head + '<table><thead><tr><th>NP</th><th>Cliente</th><th>Tanda</th><th class="num">m³</th></tr></thead><tbody>' +
    body + '<tr class="pop-tot"><td colspan="3">Total</td>' + popNum(tot) + '</tr></tbody></table>';
}
function popDiaM3(dia) {
  var D = window.__MA_D || {}, pares = [];
  (D.prog || new Map()).forEach(function (v) { if (v.fechaRaw === dia) pares.push([v.tanda, v.m3]); });
  pares.sort(function (a, b) { return b[1] - a[1]; });
  return '<div class="pop-sub">' + esc(diaEtiqueta(dia)) + ' · m³ por tanda</div>' + popTablaTandas(pares);
}
function popTanda(code) {
  var D = window.__MA_D || {};
  var v = (D.prog && D.prog.get) ? D.prog.get(code) : null;
  if (!v) return '<div class="pop-empty">Sin datos de la tanda ' + esc(code) + '</div>';
  var ev = (D.status && D.status.get) ? (D.status.get(code) || {}) : {};
  var est = function (s) { return s === "done" ? "✅ terminado" : (s === "curso" ? "◍ en curso" : "— sin empezar"); };
  var nombres = (D.empleados && D.empleados.nombres) || new Map();
  var act = (D.actividad || []).filter(function (r) { return !r.idle && String(r.tanda || "").toUpperCase() === code; });
  var quien = act.map(function (r) {
    var nom = nombres.get(String(r.legajo)) || ("Leg " + r.legajo);
    var min = Math.round((Date.now() - r.desde) / 60000);
    var q = r.kind === "pick" ? "picking" : (r.kind === "arm" ? "armado" : r.kind);
    return esc(String(nom).trim().split(/\\s+/)[0]) + " (" + q + ", " + fmtMin(min) + ")";
  }).join(" · ");
  var rows = [
    ["Día", esc(diaEtiqueta(v.fechaRaw) || v.fecha || "—")],
    ["m³", n1(v.m3)],
    ["Zona", esc((v.zonas || []).join(" · ") || "—")],
    ["Camión", esc(monCamionDeTanda(v))],
    ["Picking", est(ev.picking) + (ev.picking ? ' <span id="popPickHs" data-k="' + esc(code) + '" style="color:#93c5fd"></span>' : "")],
    ["Armado", est(ev.armado) + (ev.armado ? ' <span id="popArmHs" data-k="' + esc(code) + '" style="color:#93c5fd"></span>' : "")],
    ["Trabajando ahora", quien || "—"],
    ["Clientes", esc((v.clientes || []).join(" · ") || "—")]
  ];
  var tabla = '<table><tbody>' + rows.map(function (r) {
    return '<tr><td class="pop-k">' + r[0] + '</td><td>' + r[1] + '</td></tr>'; }).join("") + '</tbody></table>';
  var nps = '<div class="pop-sub" style="margin-top:1vh">NP (' + (v.nps || []).length + '): ' +
    esc((v.nps || []).join(" · ") || "—") + '</div>';
  var agr = (v.agregados && v.agregados.length) ? '<div class="pop-sub" style="color:#fbbf24">⚠ Agregados: ' +
    v.agregados.map(function (a) { return esc(a.np) + " → " + esc(a.aNp); }).join(" · ") + '</div>' : "";
  return tabla + nps + agr;
}
/* v26.33 (Luis): hora de inicio y fin del picking de la tanda, si las tiene. v26.35 (D15): y del
   armado. Ciclos EP → TP y AP → TAP, por legajo (el cierre trae la apertura en ts_inicio); una
   apertura sin cierre es la fase en curso. EPX / APX (anulados) no entran: el filtro es por
   opción exacta. Legajos 0 y 1 son prueba. Hora AR, con el día delante si no es hoy; la
   duración en H:MM. */
function popHmAR(ts) {
  var h = new Date(ts).toLocaleTimeString("es-AR", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: TZ });
  var dk = dayKey(ts);
  return (dk === hoyKey() ? "" : diaEtiqueta(dk) + " ") + h;
}
function popFaseCiclos(evs, code, abre, cierra) {
  var out = [], abiertos = {};
  (evs || []).forEach(function (e) {
    if (String(e.texto || "").trim().toUpperCase() !== code) return;
    var leg = String(e.legajo == null ? "" : e.legajo).trim();
    if (!leg || leg === "0" || leg === "1") return;
    if (e.opcion === abre) abiertos[leg] = { ini: e.ts_cliente, fin: null };
    else if (e.opcion === cierra) {
      var a = abiertos[leg];
      out.push({ ini: e.ts_inicio || (a && a.ini) || null, fin: e.ts_cliente });
      delete abiertos[leg];
    }
  });
  Object.keys(abiertos).forEach(function (k) { out.push(abiertos[k]); });
  return out.sort(function (x, y) { return String(x.ini || x.fin).localeCompare(String(y.ini || y.fin)); });
}
function popPickHorasTxt(c) {
  return c.map(function (x) {
    if (!x.fin) return "desde " + popHmAR(x.ini);
    if (!x.ini) return "terminó " + popHmAR(x.fin);
    var min = Math.round((new Date(x.fin).getTime() - new Date(x.ini).getTime()) / 60000);
    return popHmAR(x.ini) + " → " + popHmAR(x.fin) + (min >= 0 ? " (" + fmtMin(min) + ")" : "");
  }).join(" · ");
}
function popFaseHoras(code) {
  if (!el("popPickHs") && !el("popArmHs")) return;
  var desde = new Date(Date.now() - 45 * 86400000).toISOString();
  get("Registros_Produccion_Virgilio", "opcion=in.(EP,TP,AP,TAP)&texto=ilike." + encodeURIComponent(code) +
      "&ts_cliente=gte." + encodeURIComponent(desde) +
      "&select=opcion,legajo,texto,ts_cliente,ts_inicio&order=ts_cliente.asc&limit=400")
    .then(function (evs) {
      [["popPickHs", "EP", "TP"], ["popArmHs", "AP", "TAP"]].forEach(function (f) {
        var n = el(f[0]); if (!n || n.getAttribute("data-k") !== code) return;
        var c = popFaseCiclos(evs, code, f[1], f[2]);
        n.textContent = c.length ? "· " + popPickHorasTxt(c) : "";
      });
    })
    .catch(function () { /* sin la hora el pop-up queda como estaba */ });
}
function abrirDesglose(pop, t) {
  if (pop === "rit")   return abrirPop("m³/h " + (t.getAttribute("data-sub") === "pick" ? "picking" : "armado"), popRitmo(t.getAttribute("data-leg"), t.getAttribute("data-sub")));
  if (pop === "hs")    return abrirPop("Horas del operario", popHoras(t.getAttribute("data-leg")));
  if (pop === "punt")  return abrirPop("Puntaje de picking (1-10)", popPuntaje(t.getAttribute("data-leg")));
  if (pop === "dia")   return abrirPop("NPs · " + (POP_EST[t.getAttribute("data-sub")] || ""), popDiaBucket(t.getAttribute("data-dia"), t.getAttribute("data-sub")));
  if (pop === "diam3") return abrirPop("m³ del día", popDiaM3(t.getAttribute("data-dia")));
  if (pop === "tanda") { abrirPop("Tanda " + t.getAttribute("data-k"), popTanda(t.getAttribute("data-k"))); popFaseHoras(t.getAttribute("data-k")); return; }
}
/* Marca las celdas clickeables después de cada render (los nodos son nuevos en cada pintada,
   así que no se acumula). Zip por posición: el orden del DOM es el de los datos. */
/* v26.50 (Luis, 03/10): PUNTAJE 1-10 DE PICKING por operario — sólo acá, nunca en la TV de los
   operarios ("no para ellos"). Lo calcula la base (gv_picking_puntaje_operario: índice = Σ tamaño
   esperado D17 ÷ Σ tiempo real de sus últimas 20 tandas; puntaje = 5,5 + 10 × (índice − 1), 1..10).
   La RPC exige sesión de SUPERVISOR: el token sale de window.parent.sbAuth (el index que embebe
   este iframe). Abierto suelto, sin parent, no se pide nada y la columna dice «—». Se relee cada
   10 min; si la lectura falla, la columna lo dice en el title y no inventa un número. */
var PUNT = null, PUNT_TS = 0, PUNT_ERR = "", PUNT_VUELO = false;
function puntAuth() {
  try { var pa = (window.parent && window.parent !== window) ? window.parent : null;
    return (pa && pa.sbAuth && typeof pa.sbAuth.getAccessToken === "function") ? pa.sbAuth : null; } catch (_e) { return null; }
}
function cargarPuntajes() {
  var auth = puntAuth();
  if (!auth) { PUNT_ERR = "sin sesión de supervisor"; return Promise.resolve(); }
  if (PUNT_VUELO) return Promise.resolve();
  PUNT_VUELO = true;
  return Promise.resolve().then(function () { return auth.getAccessToken(); }).then(function (tok) {
    if (!tok) throw new Error("sin sesión de supervisor");
    return fetch(SB_URL + "/rest/v1/rpc/gv_picking_puntaje_operario", { method: "POST", cache: "no-store",
      headers: { apikey: SB_KEY, Authorization: "Bearer " + tok, "Content-Type": "application/json" },
      body: JSON.stringify({ p_dias: 60 }) });
  }).then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(function (rows) {
      var m = {}; (rows || []).forEach(function (o) { m[String(o.legajo)] = o; });
      PUNT = m; PUNT_TS = Date.now(); PUNT_ERR = ""; PUNT_VUELO = false;
      if (window.__MA_INSTR) window.__MA_INSTR();
    }).catch(function (e) { PUNT_ERR = String((e && e.message) || e); PUNT_VUELO = false; });
}
function puntCelda(leg) {
  var o = PUNT && PUNT[leg];
  if (!o) return '<td class="op-punt" title="' + esc(PUNT_ERR || "sin tandas de picking en 60 días") + '">—</td>';
  var p = Number(o.puntaje_ult), cls = o.publicable ? (p >= 8 ? " alto" : (p <= 3 ? " bajo" : "")) : " prov";
  var tit = "últimas " + Math.min(20, o.tandas) + " tandas: índice " + n1(o.indice_ult) + " → " + p + (o.publicable ? "" : " (provisorio: menos de 10 tandas)") +
    " · período " + o.tandas + " tandas: " + n1(o.indice_per) + " → " + o.puntaje_per;
  return '<td class="op-punt cx' + cls + '" data-pop="punt" data-leg="' + esc(leg) + '" title="' + esc(tit) + '">' + p + (o.publicable ? "" : "*") + '</td>';
}
function popPuntaje(leg) {
  var o = PUNT && PUNT[leg];
  if (!o) return '<div class="pop-empty">' + esc(PUNT_ERR || "Sin tandas de picking en 60 días") + '</div>';
  var tr = (o.tramos || []).map(function (x, i) { return (i * 10 + 1) + "-" + (i * 10 + 10) + ": " + n1(x); }).join(" · ");
  var head = '<div class="pop-sub" style="text-align:center"><span class="pop-k">' + esc(o.nombre || leg) + '</span> · legajo ' + esc(leg) + '</div>' +
    '<div class="pop-sub">Puntaje = 5,5 + 10 × (índice − 1), 1 a 10; índice = tiempo esperado (esquema D17) ÷ tiempo real (picking + cola). ' +
    '1 punto = 10 % de velocidad; 5-6 = el promedio del depósito. Mide velocidad, no calidad.</div>' +
    '<table class="pop-cmp"><thead><tr><th></th><th>Tandas</th><th>Índice</th><th>Puntaje</th></tr></thead><tbody>' +
    '<tr><td class="pop-k">Últimas 20</td><td>' + Math.min(20, o.tandas) + '</td><td>' + n1(o.indice_ult) + '</td><td class="pop-k">' + o.puntaje_ult + (o.publicable ? "" : " (provisorio)") + '</td></tr>' +
    '<tr><td class="pop-k">Período (60 días)</td><td>' + o.tandas + '</td><td>' + n1(o.indice_per) + '</td><td class="pop-k">' + o.puntaje_per + '</td></tr></tbody></table>' +
    (o.margen_pts != null ? '<div class="pop-sub">Margen aprox. ±' + n1(o.margen_pts) + ' puntos (90 %) con esas tandas' + (o.publicable ? "" : " · con menos de 10 tandas el puntaje no se publica") + '.</div>' : "") +
    (tr ? '<div class="pop-sub">Índice por tramo de 10 tandas (de la más vieja a la más nueva): ' + esc(tr) + '</div>' : "");
  var det = o.detalle || [];
  if (!det.length) return head;
  var body = det.map(function (t) {
    return '<tr><td class="pop-k">' + esc(t.tanda) + '</td><td>' + esc(t.fecha) + '</td><td>' + esc(String(t.nivel || "")) + ' (' + t.grado + ')</td><td>' +
      t.lineas + ' / ' + n1(t.cajas) + '</td><td>' + t.paradas + ' / ' + t.esc + '</td><td>' + n1(t.tamano) + '</td><td>' + n1(t.real) + '</td><td class="pop-k">' + n1(t.indice) + '</td></tr>'; }).join("");
  return head + '<table class="pop-cmp"><thead><tr><th>Tanda</th><th>Día</th><th>Dificultad</th><th>Lín / cajas</th><th>Paradas / esc.</th><th>Esperado min</th><th>Real min</th><th>Índice</th></tr></thead><tbody>' + body + '</tbody></table>';
}
function instrumentar() {
  var D = window.__MA_D || {};
  var H = D.horas || [], hi = 0;
  if (!PUNT || (Date.now() - PUNT_TS) > 600000) cargarPuntajes();
  cargarGrados();   // v26.54: el grado de cada tanda pickeada, para el m³/h ajustado
  var ops = document.querySelector("#opsBox table.ops");
  if (ops && !ops.getAttribute("data-punt")) {
    ops.setAttribute("data-punt", "1");
    var hs = ops.querySelectorAll("thead tr");
    if (hs[0]) hs[0].insertAdjacentHTML("beforeend", '<th class="op-punt" title="Sólo en Mon. Admin: no lo ve la TV de los operarios">Punt.</th>');
    if (hs[1]) hs[1].insertAdjacentHTML("beforeend", '<th class="op-punt" title="Puntaje 1-10 de picking: índice de sus últimas 20 tandas (tiempo esperado ÷ real). Tocá para el detalle">1-10<br>picking</th>');
  }
  document.querySelectorAll("#opsBox table.ops tbody tr").forEach(function (tr) {
    if (tr.classList.contains("op-tot-row")) { if (ops && ops.getAttribute("data-punt") && tr.children.length < 7) tr.insertAdjacentHTML("beforeend", "<td></td>"); return; }
    var o = H[hi++];
    if (!o) { if (ops && tr.children.length < 7) tr.insertAdjacentHTML("beforeend", '<td class="op-punt">—</td>'); return; }
    var td = tr.children, leg = String(o.legajo);
    function marca(i, pop, sub) { if (!td[i]) return;
      td[i].className += " cx"; td[i].setAttribute("data-pop", pop); td[i].setAttribute("data-leg", leg);
      if (sub) td[i].setAttribute("data-sub", sub); }
    marca(1, "rit", "pick"); marca(2, "rit", "arm"); marca(3, "hs"); marca(4, "hs");
    /* v26.54: en la celda de m³/h picking, chiquito, el ajustado por dificultad del día («→ 0,6») cuando
       TODAS sus tandas ya tienen grado; el detalle por tanda está en el pop-up */
    if (td[1] && !td[1].querySelector(".op-aj")) {
      var M = window.__MA_M3 || {}, G = window.__MA_GRADO || {}, pk = (M[leg] || {}).pick || {}, s = 0, okG = true, n = 0;
      Object.keys(pk).forEach(function (t) { var g = G[t + "|" + leg] || G[t]; n++;
        if (g && isFinite(Number(g.multiplicador))) s += pk[t] * Number(g.multiplicador); else okG = false; });
      var hp = Number(o.hs_pick) || 0;
      if (n && okG && hp > 0.05 && s > 0) td[1].insertAdjacentHTML("beforeend", ' <small class="op-aj" title="ajustado por dificultad: m³ × (1 + 0,1 × (grado − 5)) ÷ h">→ ' + n1(s / hp) + '</small>');
    }
    if (tr.children.length < 7) tr.insertAdjacentHTML("beforeend", puntCelda(leg));
  });
  var RDS = resumenDias(D.arbol || [], D.despachadas || new Set(), 4), ri = 0;
  var SUBS = ["salio", "facturado", "armado", "proceso", "pendiente"];
  document.querySelectorAll("#fcBox table.rd tbody tr").forEach(function (tr) {
    var x = RDS[ri++]; if (!x) return;
    var td = tr.children;
    if (td[1]) { td[1].className += " cx"; td[1].setAttribute("data-pop", "diam3"); td[1].setAttribute("data-dia", x.key); }
    for (var i = 0; i < 5; i++) { var c = td[2 + i]; if (!c) continue;
      c.className += " cx"; c.setAttribute("data-pop", "dia"); c.setAttribute("data-dia", x.key); c.setAttribute("data-sub", SUBS[i]); }
  });
  document.querySelectorAll("#tandasBox table.tandas tbody tr").forEach(function (tr) {
    if (tr.classList.contains("dia")) return;
    var c = tr.querySelector(".t-tanda"); if (!c) return;
    var code = String(c.textContent || "").replace(/[^A-Za-z0-9].*$/, "").trim().toUpperCase();
    if (!code) return;
    tr.className += " cx"; tr.setAttribute("data-pop", "tanda"); tr.setAttribute("data-k", code);
  });
}
window.__MA_INSTR = instrumentar;
document.addEventListener("click", function (e) {
  if (e.target && e.target.id === "popX") { cerrarPop(); return; }
  var p = el("pop");
  if (p && !p.classList.contains("hide") && e.target === p) { cerrarPop(); return; }
  var t = (e.target && e.target.closest) ? e.target.closest(".cx") : null;
  if (t) abrirDesglose(t.getAttribute("data-pop"), t);
});
document.addEventListener("keydown", function (e) { if (e.key === "Escape") cerrarPop(); });
`;

function build(src) {
  var out = src;
  // 1) título + banner
  out = rep(out, "<title>Monitor TV · Virgilio</title>",
    "<title>Mon. Admin · Virgilio</title>" + BANNER);
  // 2) CSS de la capa admin, antes de cerrar el <style>
  out = rep(out, "\n</style>", CSS.replace(/<\/style>$/, "") + "\n</style>");
  // 3) overlay del pop-up en el body
  out = rep(out, "\n</body>", '\n<div id="pop" class="hide"></div>\n</body>');
  // v25.90 (Luis): la alarma de operario inactivo es SÓLO de la TV del depósito: Mon. Admin no la carga.
  // v26.02 PRUEBA TEMPORAL (01/10, vence 18:40 ART): Mon. Admin la carga en modo "prueba" — sólo muestra
  // al legajo 1 en el baño (gv_alertas_prueba_vivas), nunca la alarma real. Pasada la hora no hace nada.
  out = rep(out, '<script src="alerta-inactivo.js?v=4"></script>\n',
    '<script>window.GV_ALERTA_MODO = "prueba";</script>\n<script src="alerta-inactivo.js?v=4"></script>\n');
  // 4) en pintar(): stash de `d` para que la capa admin lo lea
  out = rep(out,
    "function pintar(d) {\n  var nombres = d.empleados.nombres, horarios = d.empleados.horarios;",
    "function pintar(d) {\n  window.__MA_D = d;\n  var nombres = d.empleados.nombres, horarios = d.empleados.horarios;");
  // 5) al final del render, instrumentar (los boxes ya están pintados)
  out = rep(out,
    "  tickersTodos();   // v25.51: la columna derecha va al ancho del dato; recién acá queda fijo el ancho de la izquierda",
    "  tickersTodos();   // v25.51: la columna derecha va al ancho del dato; recién acá queda fijo el ancho de la izquierda\n  if (window.__MA_INSTR) window.__MA_INSTR();");
  // 6) en pintarHoras(): stash del mapa legajo→{pick,arm} que ya calcula
  out = rep(out,
    "  var suma = function (o) { var s2 = 0; for (var k in o) s2 += o[k]; return s2; };",
    "  window.__MA_M3 = m3;\n  var suma = function (o) { var s2 = 0; for (var k in o) s2 += o[k]; return s2; };");
  // 7) la capa admin, dentro del IIFE principal (antes de cerrarlo)
  out = rep(out,
    "}, RELOAD_CADA_MS);\n})();\n\n})();\n</script>",
    "}, RELOAD_CADA_MS);\n})();\n" + ADMIN + "\n})();\n</script>");
  return out;
}

if (require.main === module) {
  const tv = fs.readFileSync(path.join(__dirname, "tv.html"), "utf8");
  const res = build(tv);
  fs.writeFileSync(path.join(__dirname, "admin.html"), res);
  console.log("admin.html generado — " + (Buffer.byteLength(res) / 1024).toFixed(0) + " KB");
}

module.exports = { build };
