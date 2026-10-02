/* ============================================================================
   ESTADÍSTICAS ISIS — ventas y pedidos por artículo (v26.16, pedido de Luis 02/10/2026)
   ----------------------------------------------------------------------------
   Reemplaza la bajada a mano de ISIS de dos reportes mensuales, con el MISMO
   archivo que da ISIS («Microsoft Excel 97-2000 Sólo datos», formato Típico):
     · Manual 29 — Estadísticas de ventas mensuales (Ventas › Ventas por Artículo,
       Detalle) → esta_vtaarticutot1corte_vtas_<mes>_<lk|ch>.xls. Lo usa Costos
       ("AAA COSTOS Vigente", hoja «Pegar Estad Vtas Mes LK y CH").
     · Manual 31 — Estadística de pedidos (Ventas › Pedidos › Totales de Pedidos
       por artículo) → vta_pedidoporarticulotot_pedidos_<lk|ch>_<mes>_<aa>.xls. Lo
       usa la Estadística Madre (BUSCARV sobre B:H, col 7 = unidades, 4 = cajas).

   LAYOUT: el del export crudo de ISIS (Crystal), columna por columna — ventas en
   A..P (los blancos C, D, F, H, J, L, P incluidos: el paso 21 del manual 29 borra
   F, D y C), la fila «Total General» corrida una columna a la izquierda como la
   escribe Crystal, y el pie «Impreso por:» con fecha y hora. Arial 10, cantidades
   #,##0.000 / #,##0.00. Así los pasos de los manuales siguen igual.

   DE DÓNDE SALE:
     · VENTAS: gv_isis_estad_ventas(emp, desde, hasta) — las facturas y NC de ISIS ya
       parseadas. Verificado contra los Excel de ISIS de sept/26: CH 163 de 163
       artículos idénticos en las 5 columnas; LK 183 de 184, totales exactos. La
       única diferencia: ISIS separa 55219 / 55219ZZ y la factura impresa dice 55219.
     · PEDIDOS: gv_isis_estad_pedidos(emp, desde, hasta) — lo que pidieron los
       clientes en la página (LK / Chef) por FECHA DEL PEDIDO. NO es el reporte de
       ISIS, que sólo tiene lo cargado en ISIS al facturar y no está en la base
       (sept/26 LK: ISIS 11.068 cajas, página 26.297). Importe = unidades × lista.

   ⚠ Si una RPC vuelve VACÍA no se baja nada: con la sesión vencida el guard de
   supervisor devuelve 0 filas, y un Excel vacío se pegaría en Costos como si el
   mes no hubiera vendido (regla "una lectura ROTA no es un CERO").

   Vive en su propio archivo (regla v23.98). ?v= atado a APP_VERSION: está en
   SIGUEN_APP_VERSION de scripts/bump-version.cjs y tests/version-tokens.cjs.
   SQL: sql/gv_isis_estadisticas_v2616.sql. Candado: tests/isis-estadisticas.cjs.
   ============================================================================ */

var _EI_MES3 = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
var _EI_MESV = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"];
var _ei = { res: {}, busy: false };

/* ---------- armado de la hoja (puro: lo prueba tests/isis-estadisticas.cjs) ---------- */

function _eiNum(v) { var n = Number(v); return isFinite(n) ? n : 0; }
function _eiPut(ws, r, c, v, z) {
  var a = _eiAddr(r, c);
  if (typeof v === "number") ws[a] = z ? { t: "n", v: v, z: z } : { t: "n", v: v };
  else ws[a] = { t: "s", v: String(v) };
}
function _eiAddr(r, c) {
  var s = "", n = c + 1;
  while (n > 0) { var m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
  return s + (r + 1);
}
/* Excel: días desde 1899-12-30, con la fecha LOCAL (Buenos Aires), sin hora */
function eiSerialFecha(d) {
  return Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - Date.UTC(1899, 11, 30)) / 86400000);
}
/* Crystal escribe la hora del pie como 30/11/1999 + hora (serial 36494,xxx): se copia igual */
function eiSerialHora(d) {
  return 36494 + (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400;
}
function _eiPie(ws, r, usuario, cuando, cHoja, fmtFecha, fmtHora) {
  _eiPut(ws, r, 0, "Impreso por:");
  _eiPut(ws, r, 1, usuario || "GESTION");
  _eiPut(ws, r, 2, eiSerialFecha(cuando), fmtFecha);
  _eiPut(ws, r, 3, eiSerialHora(cuando), fmtHora);
  _eiPut(ws, r, cHoja, "Hoja Nro:");
  _eiPut(ws, r, cHoja + 1, 1, "#,##0");
  _eiPut(ws, r, cHoja + 2, "de");
  _eiPut(ws, r, cHoja + 3, 1, "#,##0");
}
function _eiCols(ws, n) { var a = []; for (var i = 0; i < n; i++) a.push({ wch: 10 }); ws["!cols"] = a; }

/* ventas por artículo, detalle — 16 columnas A..P como el export de ISIS */
function eiHojaVentas(rows, o) {
  o = o || {};
  var ws = {}, r = 0, Q = "#,##0.000", P = "#,##0.00";
  _eiPut(ws, 0, 4, "Bonificación"); _eiPut(ws, 0, 6, "Cantidad"); _eiPut(ws, 0, 8, "Máximo");
  _eiPut(ws, 0, 10, "Promedio"); _eiPut(ws, 0, 12, "Mínimo"); _eiPut(ws, 0, 13, "Total"); _eiPut(ws, 0, 14, "% Particip.");
  var sCant = 0, sTot = 0;
  (rows || []).forEach(function (x) {
    r++;
    var cant = _eiNum(x.cantidad), tot = _eiNum(x.total);
    _eiPut(ws, r, 0, String(x.cod == null ? "" : x.cod));
    _eiPut(ws, r, 1, String(x.descripcion == null ? "" : x.descripcion));
    _eiPut(ws, r, 4, 0, Q);
    _eiPut(ws, r, 6, cant, Q);
    _eiPut(ws, r, 8, _eiNum(x.precio_max), P);
    _eiPut(ws, r, 10, _eiNum(x.promedio), P);
    _eiPut(ws, r, 12, _eiNum(x.precio_min), P);
    _eiPut(ws, r, 13, tot, P);
    _eiPut(ws, r, 14, _eiNum(x.particip), P);
    sCant += cant; sTot += tot;
  });
  r++;
  /* la fila de total va corrida una columna a la izquierda: así la escribe Crystal */
  _eiPut(ws, r, 1, "Total General");
  _eiPut(ws, r, 3, 0, Q);
  _eiPut(ws, r, 5, Math.round(sCant * 1000) / 1000, Q);
  _eiPut(ws, r, 12, Math.round(sTot * 100) / 100, P);
  r++;
  _eiPie(ws, r, o.usuario, o.cuando || new Date(), 12, "m/d/yy", "hh\\:mm\\:ss\\ ");
  ws["!ref"] = "A1:" + _eiAddr(r, 15);
  _eiCols(ws, 16);
  return ws;
}

/* totales de pedidos por artículo — 12 columnas A..L como el export de ISIS */
function eiHojaPedidos(rows, o) {
  o = o || {};
  var ws = {}, r = 0, P = "#,##0.00";
  _eiPut(ws, 0, 1, "Artículo"); _eiPut(ws, 0, 3, "Med."); _eiPut(ws, 0, 4, "Cantidad"); _eiPut(ws, 0, 5, "Bonificac.");
  _eiPut(ws, 0, 6, "Med."); _eiPut(ws, 0, 7, "Cantidad"); _eiPut(ws, 0, 8, "Bonificac."); _eiPut(ws, 0, 9, "Mda.");
  _eiPut(ws, 0, 10, "Importe");
  var sImp = 0;
  (rows || []).forEach(function (x) {
    r++;
    var imp = _eiNum(x.importe);
    _eiPut(ws, r, 0, "Div");
    _eiPut(ws, r, 1, String(x.cod == null ? "" : x.cod));
    _eiPut(ws, r, 2, String(x.descripcion == null ? "" : x.descripcion));
    _eiPut(ws, r, 3, "caja");
    _eiPut(ws, r, 4, _eiNum(x.cajas), P);
    _eiPut(ws, r, 5, 0, P);
    _eiPut(ws, r, 6, "unidad");
    /* sin UxB la base devuelve unidades vacías: la celda queda vacía (el BUSCARV da error y el SI.ERROR del
       manual 31 lo deja en blanco), nunca las cajas disfrazadas de unidades */
    if (x.unidades != null && x.unidades !== "") _eiPut(ws, r, 7, _eiNum(x.unidades), P);
    _eiPut(ws, r, 8, 0, P);
    _eiPut(ws, r, 9, "$");
    if (x.importe != null && x.importe !== "") _eiPut(ws, r, 10, imp, P);
    sImp += imp;
  });
  r++;
  _eiPut(ws, r, 7, "Total General");
  _eiPut(ws, r, 9, Math.round(sImp * 100) / 100, "[$$-2C0A]* #,##0.00;[$$-2C0A]* \\-#,##0.00");
  r++;
  _eiPie(ws, r, o.usuario, o.cuando || new Date(), 8, "dd/MM/yyyy", "hh\\:mm\\:ss ");
  ws["!ref"] = "A1:" + _eiAddr(r, 11);
  _eiCols(ws, 12);
  return ws;
}

/* .xls Excel 97 (BIFF8). SheetJS escribe la letra en Arial 12; ISIS la da en 10: se corrige
   la altura de los registros FONT (0x0031) del stream «Workbook» antes de bajarlo. */
function eiXlsBytes(X, ws) {
  var wb = X.utils.book_new();
  X.utils.book_append_sheet(wb, ws, "Sheet1");
  var u8 = new Uint8Array(X.write(wb, { bookType: "biff8", type: "array" }));
  try {
    if (!X.CFB) return u8;
    var cfb = X.CFB.read(u8, { type: "array" });
    var ent = (cfb.FileIndex || []).find(function (f) { return f && (f.name === "Workbook" || f.name === "Book"); });
    if (!ent || !ent.content) return u8;
    var c = ent.content, p = 0;
    while (p + 4 <= c.length) {
      var t = c[p] | (c[p + 1] << 8), len = c[p + 2] | (c[p + 3] << 8);
      if (t === 0x31 && len >= 2) { c[p + 4] = 200 & 255; c[p + 5] = 200 >> 8; }
      if (t === 0x0A) break;                       /* EOF del globals: las hojas no llevan FONT */
      p += 4 + len;
    }
    return new Uint8Array(X.CFB.write(cfb, { type: "array" }));
  } catch (_e) { return u8; }
}

/* nombre del archivo, como lo guardan hoy (mes entero) o con las fechas si es un rango suelto */
function eiNombre(tipo, emp, desde, hasta) {
  var d = String(desde || ""), h = String(hasta || "");
  var dd = d.split("-"), hh = h.split("-");
  var mesEntero = dd.length === 3 && hh.length === 3 && dd[2] === "01" && dd[0] === hh[0] && dd[1] === hh[1] &&
    Number(hh[2]) === new Date(Date.UTC(Number(hh[0]), Number(hh[1]), 0)).getUTCDate();
  var e = String(emp || "").toLowerCase() === "lk" ? "lk" : "ch";
  if (tipo === "ventas") {
    var mv = mesEntero ? _EI_MESV[Number(dd[1]) - 1] : (dd[2] + dd[1] + "-" + hh[2] + hh[1]);
    return "esta_vtaarticutot1corte_vtas_" + mv + "_" + e + ".xls";
  }
  var mp = mesEntero ? _EI_MES3[Number(dd[1]) - 1] + "_" + dd[0].slice(2) : (dd[2] + dd[1] + "-" + hh[2] + hh[1] + "_" + hh[0].slice(2));
  return "vta_pedidoporarticulotot_pedidos_" + e + "_" + mp + ".xls";
}

/* ---------- pantalla ---------- */

function _eiEsc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
function _eiFmt(v, dec) { var n = Number(v); return isFinite(n) ? n.toLocaleString("es-AR", { minimumFractionDigits: dec, maximumFractionDigits: dec }) : "—"; }
function _eiIso(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
function _eiUsuario() {
  var s = "";
  try { s = (typeof __identity !== "undefined" && __identity && (__identity.nombre || __identity.email)) || window.__authEmail || ""; } catch (_e) {}
  s = String(s || "").trim();
  if (s.indexOf("@") > 0) s = s.split("@")[0];
  s = s.split(/\s+/)[0] || "";
  return s ? s.toUpperCase().slice(0, 20) : "GESTION";
}
function _eiRpc(name, args) {
  var sb = window.sb;
  if (!sb || typeof sb.rpc !== "function") return Promise.resolve({ data: null, error: { message: "sin sesión" } });
  try { return Promise.resolve(sb.rpc(name, args || {})).catch(function (e) { return { data: null, error: e }; }); }
  catch (e) { return Promise.resolve({ data: null, error: e }); }
}
async function _eiXlsx() {
  if (window.XLSX) return window.XLSX;
  if (typeof pppLoadXlsx === "function") return pppLoadXlsx();
  return new Promise(function (res, rej) {
    var sc = document.createElement("script"); sc.src = "vendor/xlsx.full.min.js";
    sc.onload = function () { window.XLSX ? res(window.XLSX) : rej(new Error("SheetJS no cargó")); };
    sc.onerror = function () { rej(new Error("No pude cargar SheetJS")); };
    document.head.appendChild(sc);
  });
}
function _eiBajar(bytes, nombre) {
  var blob = new Blob([bytes], { type: "application/vnd.ms-excel" });
  var a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = nombre;
  document.body.appendChild(a); a.click();
  setTimeout(function () { try { URL.revokeObjectURL(a.href); a.remove(); } catch (_e) {} }, 4000);
}

var _EI_REP = [
  { k: "vlk", tipo: "ventas", emp: "lk", t: "Ventas LK", rpc: "gv_isis_estad_ventas", man: "Manual 29 · costos" },
  { k: "vch", tipo: "ventas", emp: "ch", t: "Ventas CH", rpc: "gv_isis_estad_ventas", man: "Manual 29 · costos" },
  { k: "plk", tipo: "pedidos", emp: "lk", t: "Pedidos LK", rpc: "gv_isis_estad_pedidos", man: "Manual 31 · Est. Madre" },
  { k: "pch", tipo: "pedidos", emp: "ch", t: "Pedidos CH", rpc: "gv_isis_estad_pedidos", man: "Manual 31 · Est. Madre" }
];

function _eiCss() {
  if (document.getElementById("eiCss")) return;
  var st = document.createElement("style");
  st.id = "eiCss";
  st.textContent = [
    "#eiOv{position:fixed;inset:0;z-index:9600;background:#f1f5f9;display:none;flex-direction:column;font-family:system-ui,Segoe UI,Arial,sans-serif;color:#0f172a;}",
    "#eiOv *{box-sizing:border-box;}",
    /* el button{width:100%;padding:16px;font-size:22px} global del index se neutraliza acá (pozo de cobranzas / Importados) */
    "#eiOv button{width:auto;margin-top:0;padding:6px 13px;font-size:13px;line-height:1.25;}",
    "#eiOv input{width:auto;margin-top:0;font:inherit;font-size:14px;font-weight:700;text-align:center;padding:5px 6px;border:1px solid #cbd5e1;border-radius:7px;background:#fff;color:#0f172a;}",
    ".ei-top{display:flex;align-items:center;gap:14px;padding:10px 16px;background:linear-gradient(90deg,#1e3a8a,#172554);color:#fff;flex:0 0 auto;flex-wrap:wrap;}",
    ".ei-top b{font-size:17px;}",
    ".ei-top span{font-size:12.5px;opacity:.9;flex:1 1 300px;min-width:0;}",
    ".ei-x{margin-left:auto;background:#fff;color:#172554;border:none;border-radius:8px;font-weight:800;cursor:pointer;}",
    ".ei-body{flex:1;min-height:0;overflow:auto;padding:14px 16px;}",
    ".ei-wrap{width:fit-content;max-width:100%;margin:0 auto;display:grid;gap:12px;justify-items:center;}",
    ".ei-per{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:end;justify-content:center;background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:10px 14px;}",
    ".ei-per label{display:grid;gap:3px;font-size:11.5px;color:#475569;font-weight:600;text-align:center;}",
    ".ei-t{border-collapse:collapse;background:#fff;border:1px solid #e2e8f0;font-variant-numeric:tabular-nums;}",
    ".ei-t th,.ei-t td{padding:6px 10px;text-align:center;border-bottom:1px solid #e2e8f0;white-space:nowrap;font-size:13px;}",
    ".ei-t th{font-size:11.5px;font-weight:800;color:#475569;background:#f8fafc;line-height:1.2;}",
    ".ei-t td.r{font-weight:800;}",
    ".ei-t td.r small{display:block;font-weight:500;color:#64748b;font-size:11px;}",
    ".ei-t td .err{color:#b91c1c;font-weight:700;white-space:normal;max-width:30ch;display:inline-block;}",
    ".ei-t button{background:#1e3a8a;color:#fff;border:none;border-radius:8px;font-weight:800;cursor:pointer;}",
    ".ei-t button:disabled{opacity:.5;cursor:wait;}",
    ".ei-todas{background:#0f172a;color:#fff;border:none;border-radius:8px;font-weight:800;cursor:pointer;}",
    ".ei-nota{max-width:640px;font-size:12px;color:#475569;line-height:1.4;text-align:center;}",
    ".ei-nota b{color:#0f172a;}"
  ].join("\n");
  document.head.appendChild(st);
}

function openEstadisticasIsis() {
  try { if (typeof requireSupervisor === "function" && !requireSupervisor()) return; } catch (_e) {}
  _eiCss();
  var ov = document.getElementById("eiOv");
  if (!ov) { ov = document.createElement("div"); ov.id = "eiOv"; document.body.appendChild(ov); }
  var hoy = new Date();
  var ini = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1), fin = new Date(hoy.getFullYear(), hoy.getMonth(), 0);
  ov.style.display = "flex";
  ov.innerHTML =
    '<div class="ei-top"><b>📑 Estadísticas ISIS por artículo</b>' +
      '<span>Ventas (manual 29) y pedidos (manual 31) con el mismo Excel que da ISIS, sin entrar a ISIS.</span>' +
      '<button class="ei-x" onclick="eiClose()">Cerrar</button></div>' +
    '<div class="ei-body"><div class="ei-wrap">' +
      '<div class="ei-per">' +
        '<label>Mes<input id="eiMes" type="month" value="' + _eiIso(ini).slice(0, 7) + '" onchange="eiMes()"></label>' +
        '<label>Desde<input id="eiDesde" type="date" value="' + _eiIso(ini) + '"></label>' +
        '<label>Hasta<input id="eiHasta" type="date" value="' + _eiIso(fin) + '"></label>' +
        '<button type="button" class="ei-todas" onclick="eiBajarTodas()">⬇ Bajar las 4</button>' +
      '</div>' +
      '<table class="ei-t" id="eiT"></table>' +
      '<div class="ei-nota"><b>Ventas</b> sale de las facturas y notas de crédito de ISIS ya leídas por Gestión: mismas unidades, precios y totales que el reporte de ISIS (sept/26 verificado artículo por artículo). ' +
        '<b>Pedidos</b> es lo que pidieron los clientes en la página, por fecha del pedido: ISIS sólo tiene lo que se cargó al facturar, así que los números no son los mismos que su reporte. ' +
        'El importe de pedidos es a precio de lista. Si un reporte vuelve vacío no se baja nada.</div>' +
    '</div></div>';
  _ei.res = {};
  eiPintar();
}
function eiClose() { var ov = document.getElementById("eiOv"); if (ov) ov.style.display = "none"; }
function eiMes() {
  var m = (document.getElementById("eiMes") || {}).value || "";
  var p = m.split("-");
  if (p.length !== 2) return;
  var a = Number(p[0]), mm = Number(p[1]);
  document.getElementById("eiDesde").value = _eiIso(new Date(a, mm - 1, 1));
  document.getElementById("eiHasta").value = _eiIso(new Date(a, mm, 0));
}
function eiPintar() {
  var t = document.getElementById("eiT");
  if (!t) return;
  var h = '<tr><th>Reporte</th><th>Artículos</th><th>Cantidad<br><small>' + 'cajas / unid.' + '</small></th><th>Total<br>$</th><th></th></tr>';
  _EI_REP.forEach(function (r) {
    var x = _ei.res[r.k] || {};
    var cant = x.cajas != null ? (_eiFmt(x.cajas, 0) + ' cj · ' + _eiFmt(x.cant, 0) + ' u') : (x.cant != null ? _eiFmt(x.cant, 0) + ' u' : '—');
    h += '<tr><td class="r">' + _eiEsc(r.t) + '<small>' + _eiEsc(r.man) + '</small></td>' +
      (x.err ? '<td colspan="3"><span class="err">' + _eiEsc(x.err) + '</span></td>'
             : '<td>' + (x.n != null ? _eiFmt(x.n, 0) : '—') + '</td><td>' + cant + '</td><td>' + (x.tot != null ? _eiFmt(x.tot, 2) : '—') + '</td>') +
      '<td><button type="button" id="eiB_' + r.k + '"' + (x.busy ? ' disabled' : '') + ' onclick="eiBajar(\'' + r.k + '\')">' + (x.busy ? 'Armando…' : '⬇ .xls') + '</button></td></tr>';
  });
  t.innerHTML = h;
}
async function eiBajar(k) {
  var r = _EI_REP.find(function (z) { return z.k === k; });
  if (!r) return false;
  var desde = (document.getElementById("eiDesde") || {}).value, hasta = (document.getElementById("eiHasta") || {}).value;
  if (!desde || !hasta || desde > hasta) { _ei.res[k] = { err: "Elegí un período válido" }; eiPintar(); return false; }
  _ei.res[k] = { busy: true }; eiPintar();
  var X;
  try { X = await _eiXlsx(); } catch (e) { _ei.res[k] = { err: "No pude cargar el generador de Excel: " + (e && e.message || e) }; eiPintar(); return false; }
  var q = await _eiRpc(r.rpc, { p_empresa: r.emp, p_desde: desde, p_hasta: hasta });
  if (q.error) { _ei.res[k] = { err: "No pude leer: " + (q.error.message || q.error) + ". No se bajó nada." }; eiPintar(); return false; }
  var rows = Array.isArray(q.data) ? q.data : [];
  if (!rows.length) { _ei.res[k] = { err: "Volvió vacío (sin datos en el período o sin sesión de supervisor). No se bajó nada." }; eiPintar(); return false; }
  var o = { usuario: _eiUsuario(), cuando: new Date() };
  var ws = r.tipo === "ventas" ? eiHojaVentas(rows, o) : eiHojaPedidos(rows, o);
  _eiBajar(eiXlsBytes(X, ws), eiNombre(r.tipo, r.emp, desde, hasta));
  var s = { n: rows.length, cant: 0, tot: 0 };
  rows.forEach(function (x) {
    if (r.tipo === "ventas") { s.cant += _eiNum(x.cantidad); s.tot += _eiNum(x.total); }
    else { s.cajas = (s.cajas || 0) + _eiNum(x.cajas); s.cant += _eiNum(x.unidades); s.tot += _eiNum(x.importe); }
  });
  _ei.res[k] = s; eiPintar();
  return true;
}
async function eiBajarTodas() {
  for (var i = 0; i < _EI_REP.length; i++) {
    await eiBajar(_EI_REP[i].k);
    await new Promise(function (res) { setTimeout(res, 700); });   /* el navegador frena descargas pegadas */
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { eiHojaVentas: eiHojaVentas, eiHojaPedidos: eiHojaPedidos, eiXlsBytes: eiXlsBytes, eiNombre: eiNombre,
                     eiSerialFecha: eiSerialFecha, eiSerialHora: eiSerialHora };
}
