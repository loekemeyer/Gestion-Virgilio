/* ============================================================================
   ESTADÍSTICAS ISIS — ventas y pedidos por artículo (v26.16 · v26.20, Luis 02/10/2026)
   ----------------------------------------------------------------------------
   Reemplaza la bajada a mano de ISIS de dos reportes mensuales, y desde la v26.20 los
   entrega YA CONFIGURADOS como piden los manuales (Luis: «configuralas de la forma que
   indica el word»):
     · Manual 29 — Estadísticas de ventas mensuales → esta_vtaarticutot1corte_vtas_<mes>_<lk|ch>.xls.
       Sin las columnas F, D y C (paso 21) ni el «Total General» (paso 22): A2:D es lo que se
       pega en Costos («Pegar Estad Vtas Mes LK y CH»), con el código ya como número (paso 25).
     · Manual 31 — Estadística de pedidos → vta_pedidoporarticulotot_pedidos_<lk|ch>_<mes>_<aa>.xls.
       Sin las columnas I, J y K (paso 1), código como número (paso 2), hoja «LK Sep-26» (paso 3).
       El BUSCARV de la Est. Madre sobre B:H (col 7 = unidades, 4 = cajas) no cambia.
       PEDIDOS DISRUPTIVOS (IMPORTANTE del manual 31): la fila del artículo va en ROJO y NEGRITA y
       en la columna I (la siguiente a la última) va el detalle: cliente, cuánto pidió y contra qué
       promedio. Disruptivo = un pedido de un cliente que difiere más de ±50 % del promedio de SUS
       pedidos anteriores de ese artículo en los 12 meses previos; sin pedidos previos =
       incorporación. Lo calcula gv_isis_estad_pedidos_disruptivos (sql/gv_isis_estad_disruptivos_v2620.sql).

   DE DÓNDE SALE:
     · VENTAS: gv_isis_estad_ventas — las facturas y NC de ISIS ya parseadas (sept/26 verificado
       contra el Excel de ISIS artículo por artículo).
     · PEDIDOS: gv_isis_estad_pedidos — sólo los pedidos web del pipeline de Gestión, por fecha del
       pedido (Luis, 02/10). No es el reporte de ISIS, que sólo tiene lo cargado al facturar.

   ⚠ Si una RPC vuelve VACÍA o con error no se baja nada (con la sesión vencida el guard de
   supervisor devuelve 0 filas: regla "una lectura ROTA no es un CERO"). Lo mismo si fallan los
   disruptivos: un archivo sin marcar no se distingue de un mes sin disruptivos.
   ⚠ SheetJS community no escribe estilos: el rojo y la negrita se pegan en el BIFF (eiXlsBytes).

   Vive en su propio archivo (regla v23.98). ?v= atado a APP_VERSION: está en
   SIGUEN_APP_VERSION de scripts/bump-version.cjs y tests/version-tokens.cjs.
   SQL: sql/gv_isis_estadisticas_v2616.sql y sql/gv_isis_estad_disruptivos_v2620.sql.
   Candado: tests/isis-estadisticas.cjs.
   ============================================================================ */

var _EI_MES3 = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];
var _EI_MESV = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"];
var _ei = { res: {}, busy: false };

/* ---------- armado de la hoja (puro: lo prueba tests/isis-estadisticas.cjs) ---------- */

function _eiNum(v) { var n = Number(v); return isFinite(n) ? n : 0; }
function _eiPut(ws, r, c, v, z) {
  var a = _eiAddr(r, c);
  if (typeof v === "number") ws[a] = z ? { t: "n", v: v, z: z } : { t: "n", v: v };
  else ws[a] = z ? { t: "s", v: String(v), z: z } : { t: "s", v: String(v) };
}
function _eiAddr(r, c) {
  var s = "", n = c + 1;
  while (n > 0) { var m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
  return s + (r + 1);
}
/* «Convertir en número» (paso 25 del manual 29, paso 2 del 31): el código todo dígitos va como NÚMERO
   (026 → 26, igual que lo convierte Excel); el que lleva letras (026L, 437E) queda texto. */
function eiCodVal(cod) {
  var s = String(cod == null ? "" : cod).trim();
  return /^\d+$/.test(s) ? Number(s) : s;
}
function _eiCols(ws, anchos) { ws["!cols"] = anchos.map(function (w) { return { wch: w }; }); }

/* Formatos MARCA de una fila disruptiva: se ven igual que los normales y eiXlsBytes les pone la
   letra roja y negrita (SheetJS community no escribe estilos: el color se pega en el BIFF). */
var _EI_MARCA = { s: "@", n2: "#,##0.00;-#,##0.00", n0: "0;-0" };

/* VENTAS configurada (manual 29): el export de ISIS sin las columnas F, D y C (paso 21) y sin los
   blancos que deja Crystal, sin «Total General» ni pie (el paso 22 los saca). A2:D = lo que se pega
   en Costos: código · descripción · bonificación · cantidad. */
function eiHojaVentas(rows, o) {
  o = o || {};
  var ws = {}, r = 0, Q = "#,##0.000", P = "#,##0.00";
  ["Artículo", "Descripción", "Bonificación", "Cantidad", "Máximo", "Promedio", "Mínimo", "Total", "% Particip."]
    .forEach(function (h, i) { _eiPut(ws, 0, i, h); });
  (rows || []).forEach(function (x) {
    r++;
    _eiPut(ws, r, 0, eiCodVal(x.cod));
    _eiPut(ws, r, 1, String(x.descripcion == null ? "" : x.descripcion));
    _eiPut(ws, r, 2, 0, Q);
    _eiPut(ws, r, 3, _eiNum(x.cantidad), Q);
    _eiPut(ws, r, 4, _eiNum(x.precio_max), P);
    _eiPut(ws, r, 5, _eiNum(x.promedio), P);
    _eiPut(ws, r, 6, _eiNum(x.precio_min), P);
    _eiPut(ws, r, 7, _eiNum(x.total), P);
    _eiPut(ws, r, 8, _eiNum(x.particip), P);
  });
  ws["!ref"] = "A1:" + _eiAddr(Math.max(r, 1), 8);
  _eiCols(ws, [9, 34, 11, 12, 12, 12, 12, 14, 9]);
  return ws;
}

/* PEDIDOS configurada (manual 31): el export de ISIS sin las columnas I, J y K (paso 1). Queda
   A Div · B código · C descripción · D caja · E cajas · F bonif · G unidad · H unidades: el BUSCARV
   de la Est. Madre sobre B:H (col 7 = unidades, col 4 = cajas) no cambia.
   o.disrup = { cod: [pedidos disruptivos] } (eiDisrupMapa): esa fila va en ROJO y NEGRITA y en la
   columna siguiente a la última (I) va el detalle — quién, cuánto y contra qué promedio. */
function eiHojaPedidos(rows, o) {
  o = o || {};
  var ws = {}, r = 0, P = "#,##0.00", dis = o.disrup || {}, hayDis = false;
  _eiPut(ws, 0, 1, "Artículo"); _eiPut(ws, 0, 3, "Med."); _eiPut(ws, 0, 4, "Cantidad"); _eiPut(ws, 0, 5, "Bonificac.");
  _eiPut(ws, 0, 6, "Med."); _eiPut(ws, 0, 7, "Cantidad");
  (rows || []).forEach(function (x) {
    r++;
    var lista = dis[_eiCodKey(x.cod)] || null;
    var zs = lista ? _EI_MARCA.s : null, zn = lista ? _EI_MARCA.n2 : P;
    var cod = eiCodVal(x.cod);
    _eiPut(ws, r, 0, "Div", zs);
    _eiPut(ws, r, 1, cod, lista ? (typeof cod === "number" ? _EI_MARCA.n0 : _EI_MARCA.s) : null);
    _eiPut(ws, r, 2, String(x.descripcion == null ? "" : x.descripcion), zs);
    _eiPut(ws, r, 3, "caja", zs);
    _eiPut(ws, r, 4, _eiNum(x.cajas), zn);
    _eiPut(ws, r, 5, 0, zn);
    _eiPut(ws, r, 6, "unidad", zs);
    /* sin UxB la base devuelve unidades vacías: la celda queda vacía (el BUSCARV da error y el SI.ERROR del
       manual 31 lo deja en blanco), nunca las cajas disfrazadas de unidades */
    if (x.unidades != null && x.unidades !== "") _eiPut(ws, r, 7, _eiNum(x.unidades), zn);
    if (lista) { _eiPut(ws, r, 8, eiDisrupTexto(lista, o.emp), _EI_MARCA.s); hayDis = true; }
  });
  if (hayDis) _eiPut(ws, 0, 8, "Pedido disruptivo (±50 % del promedio de sus pedidos de 12 meses)");
  ws["!ref"] = "A1:" + _eiAddr(Math.max(r, 1), hayDis ? 8 : 7);
  _eiCols(ws, hayDis ? [5, 9, 30, 6, 10, 10, 7, 11, 90] : [5, 9, 30, 6, 10, 10, 7, 11]);
  return ws;
}

/* ---------- pedidos disruptivos (gv_isis_estad_pedidos_disruptivos) ---------- */
function _eiCodKey(c) { return String(c == null ? "" : c).trim().toUpperCase(); }
function _eiN(v, dec) {
  var n = Number(v); if (!isFinite(n)) return "—";
  var neg = n < 0, s = Math.abs(n).toFixed(dec || 0).split(".");
  var ent = s[0].replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return (neg ? "-" : "") + ent + (s[1] && /[1-9]/.test(s[1]) ? "," + s[1] : "");
}
function _eiDdMm(f, conAnio) {
  var p = String(f || "").slice(0, 10).split("-");
  return p.length === 3 ? p[2] + "/" + p[1] + (conAnio ? "/" + p[0].slice(2) : "") : String(f || "");
}
/* lo pedido: unidades y cajas; sin UxB, sólo cajas (nunca las cajas disfrazadas de unidades) */
function _eiCant(u, cj) {
  return (u != null && u !== "" && isFinite(Number(u))) ? _eiN(u, 0) + " u (" + _eiN(cj, 1) + " cj)" : _eiN(cj, 1) + " cj";
}
function eiDisrupMapa(filas) {
  var m = {};
  (filas || []).forEach(function (d) { var k = _eiCodKey(d.cod); if (!k) return; (m[k] = m[k] || []).push(d); });
  return m;
}
/* el comentario de la fila: incorporaciones primero, después el desvío más grande; hasta 5 y «+N más» */
function eiDisrupTexto(lista, emp) {
  var pre = String(emp || "").toLowerCase() === "lk" ? "LK " : (emp ? "CH " : "");
  var l = (lista || []).slice().sort(function (a, b) {
    var ia = a.tipo === "incorporacion" ? 1 : 0, ib = b.tipo === "incorporacion" ? 1 : 0;
    if (ia !== ib) return ib - ia;
    return Math.abs(_eiNum(b.desvio)) - Math.abs(_eiNum(a.desvio));
  });
  var MAX = 5, txt = l.slice(0, MAX).map(function (d) {
    var quien = String(d.razon_social || "").trim() || "Cliente";
    quien += " (" + pre + String(d.cliente == null ? "" : d.cliente) + ")";
    var cuanto = _eiCant(d.unidades, d.cajas) + " el " + _eiDdMm(d.fecha);
    if (d.tipo === "incorporacion") return "★ Incorporación: " + quien + " pidió " + cuanto;
    var pct = Math.round(_eiNum(d.desvio) * 100);
    var hist = "prom. " + _eiCant(d.prom_unidades, d.prom_cajas) + " en " + _eiN(d.pedidos_hist, 0) + " ped." +
      (_eiNum(d.hist_fc) > 0 ? " (" + _eiN(d.hist_fc, 0) + " por factura ISIS)" : "") +
      (d.hist_desde ? " desde " + _eiDdMm(d.hist_desde, true) : "");
    return (pct >= 0 ? "▲ +" : "▼ ") + pct + "%: " + quien + " pidió " + cuanto + " · " + hist;
  });
  if (l.length > MAX) txt.push("+" + (l.length - MAX) + " más");
  return txt.join(" | ");
}

/* nombre de la hoja: «LK Sep-26» (la «LK MES-AÑO» del manual 31); un rango suelto lleva las fechas */
function eiNombreHoja(emp, desde, hasta) {
  var e = String(emp || "").toLowerCase() === "lk" ? "LK" : "CH";
  var dd = String(desde || "").split("-"), hh = String(hasta || "").split("-");
  if (dd.length !== 3 || hh.length !== 3) return e;
  var mesEntero = dd[2] === "01" && dd[0] === hh[0] && dd[1] === hh[1] &&
    Number(hh[2]) === new Date(Date.UTC(Number(hh[0]), Number(hh[1]), 0)).getUTCDate();
  if (mesEntero) { var m = _EI_MES3[Number(dd[1]) - 1] || ""; return e + " " + m.charAt(0).toUpperCase() + m.slice(1) + "-" + dd[0].slice(2); }
  return e + " " + dd[2] + "." + dd[1] + "-" + hh[2] + "." + hh[1] + "-" + hh[0].slice(2);
}

/* .xls Excel 97 (BIFF8), con dos parches sobre el stream «Workbook» antes de bajarlo:
   1) letra Arial 10 como ISIS (SheetJS la escribe en 12): altura de los FONT (0x0031);
   2) la fila disruptiva en ROJO y NEGRITA: se agrega un FONT rojo/negrita y los XF de celda cuyo
      formato es una MARCA (_EI_MARCA) pasan a usarlo. Insertar un registro corre lo que sigue, así
      que se corrige el puntero absoluto de cada BOUNDSHEET (SheetJS no escribe INDEX, DBCELL ni
      EXTSST, que también lo tendrían: si algún día aparecen, no se marca nada y se avisa). */
function _eiU16(c, p) { return c[p] | (c[p + 1] << 8); }
function _eiBiffEstilos(c) {
  var recs = [], p = 0;
  while (p + 4 <= c.length) {
    var t = _eiU16(c, p), len = _eiU16(c, p + 2);
    recs.push({ t: t, p: p, len: len });
    p += 4 + len;
    if (t === 0x0A) break;                         /* EOF del globals */
  }
  var fonts = recs.filter(function (r) { return r.t === 0x31; });
  fonts.forEach(function (r) { if (r.len >= 2) { c[r.p + 4] = 200 & 255; c[r.p + 5] = 200 >> 8; } });
  /* qué índices de formato son marca: «@» es el 49 de fábrica; los otros, por su texto */
  var marcas = { 49: true }, txtMarca = [_EI_MARCA.n2, _EI_MARCA.n0];
  recs.forEach(function (r) {
    if (r.t !== 0x41E || r.len < 5) return;
    var d = r.p + 4, ifmt = _eiU16(c, d), cch = _eiU16(c, d + 2), hi = c[d + 4] & 1, s = "";
    for (var i = 0; i < cch; i++) s += String.fromCharCode(hi ? _eiU16(c, d + 5 + 2 * i) : c[d + 5 + i]);
    if (txtMarca.indexOf(s) >= 0) marcas[ifmt] = true;
  });
  var nf = fonts.length, ifntRojo = nf >= 4 ? nf + 1 : nf;    /* el índice 4 de FONT no existe en BIFF */
  var xfs = recs.filter(function (r) {
    if (r.t !== 0xE0 || r.len < 20) return false;
    var d = r.p + 4;
    return !(_eiU16(c, d + 4) & 0x0004) && marcas[_eiU16(c, d + 2)];   /* XF de celda con formato marca */
  });
  if (!xfs.length || !fonts.length) return { bytes: c, marcadas: 0 };
  if (recs.some(function (r) { return r.t === 0xFF || r.t === 0x20B || r.t === 0xD7; })) return { bytes: c, marcadas: -1 };
  xfs.forEach(function (r) {
    var d = r.p + 4;
    c[d] = ifntRojo & 255; c[d + 1] = ifntRojo >> 8;
    c[d + 9] |= 0x0C;                               /* fAtrNum + fAtrFnt: esta XF manda su letra */
  });
  var ult = fonts[fonts.length - 1], tam = 4 + ult.len;
  var nuevo = c.slice(ult.p, ult.p + tam);
  nuevo[4] = 200 & 255; nuevo[5] = 200 >> 8;          /* 10 pt */
  nuevo[6] |= 0x01;                                   /* grbit bit 0: negrita (redundante con bls; algunos lectores sólo miran éste) */
  nuevo[8] = 0x0A; nuevo[9] = 0;                      /* icv 10 = rojo de la paleta */
  nuevo[10] = 700 & 255; nuevo[11] = 700 >> 8;        /* bls 700 = negrita */
  var corte = ult.p + tam, out = new Uint8Array(c.length + tam);
  out.set(c.subarray(0, corte), 0); out.set(nuevo, corte); out.set(c.subarray(corte), corte + tam);
  recs.forEach(function (r) {
    if (r.t !== 0x85) return;
    var d = r.p + 4 + (r.p >= corte ? tam : 0);
    var pos = (out[d] | (out[d + 1] << 8) | (out[d + 2] << 16) | (out[d + 3] << 24)) >>> 0;
    if (pos >= corte) pos += tam;
    out[d] = pos & 255; out[d + 1] = (pos >>> 8) & 255; out[d + 2] = (pos >>> 16) & 255; out[d + 3] = (pos >>> 24) & 255;
  });
  return { bytes: out, marcadas: xfs.length };
}
function eiXlsBytes(X, ws, hoja) {
  var wb = X.utils.book_new();
  X.utils.book_append_sheet(wb, ws, String(hoja || "Sheet1").slice(0, 31));
  var u8 = new Uint8Array(X.write(wb, { bookType: "biff8", type: "array" }));
  try {
    if (!X.CFB) return u8;
    var cfb = X.CFB.read(u8, { type: "array" });
    var ent = (cfb.FileIndex || []).find(function (f) { return f && (f.name === "Workbook" || f.name === "Book"); });
    if (!ent || !ent.content) return u8;
    /* un stream grande CFB lo devuelve como Array, no Uint8Array: se normaliza antes de parchar */
    var c = ent.content instanceof Uint8Array ? ent.content : Uint8Array.from(ent.content);
    var r = _eiBiffEstilos(c);
    if (r.marcadas < 0 && typeof console !== "undefined") console.warn("estadisticas: el .xls trae INDEX/EXTSST, la fila disruptiva no se pintó");
    ent.content = r.bytes; ent.size = r.bytes.length;
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

var _EI_RPC_DISRUP = "gv_isis_estad_pedidos_disruptivos";
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
    ".ei-t td small{display:block;font-weight:500;color:#64748b;font-size:11px;}",
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
      '<div class="ei-nota">Los archivos salen <b>ya configurados</b> como piden los manuales: ventas sin las columnas F, D y C ni el «Total General» (se pega A2:D en Costos); pedidos sin I, J y K, hoja «LK Mes-Año», código como número. ' +
        '<b>Ventas</b> sale de las facturas y notas de crédito de ISIS ya leídas por Gestión (sept/26 verificado artículo por artículo). ' +
        '<b>Pedidos</b> son los pedidos web de la página, por fecha del pedido. ' +
        '<b>En rojo y negrita</b> va el artículo con un pedido que se aparta más del 50 % del promedio de los pedidos de ese cliente de los 12 meses anteriores (o una incorporación), con el detalle en la columna I; mientras la página no tenga 12 meses, el promedio usa también las facturas de ISIS. ' +
        'Si un reporte vuelve vacío no se baja nada.</div>' +
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
  var h = '<tr><th>Reporte</th><th>Artículos</th><th>Cantidad<br><small>cajas / unid.</small></th><th>Total<br>$</th><th>En rojo<br><small>disruptivos</small></th><th></th></tr>';
  _EI_REP.forEach(function (r) {
    var x = _ei.res[r.k] || {};
    var cant = x.cajas != null ? (_eiFmt(x.cajas, 0) + ' cj · ' + _eiFmt(x.cant, 0) + ' u') : (x.cant != null ? _eiFmt(x.cant, 0) + ' u' : '—');
    h += '<tr><td class="r">' + _eiEsc(r.t) + '<small>' + _eiEsc(r.man) + '</small></td>' +
      (x.err ? '<td colspan="4"><span class="err">' + _eiEsc(x.err) + '</span></td>'
             : '<td>' + (x.n != null ? _eiFmt(x.n, 0) : '—') + '</td><td>' + cant + '</td><td>' + (x.tot != null ? _eiFmt(x.tot, 2) : '—') + '</td>' +
               '<td>' + (x.disArt != null ? _eiFmt(x.disArt, 0) + ' art.<small>' + _eiFmt(x.disPed, 0) + ' pedidos</small>' : '—') + '</td>') +
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
  var args = { p_empresa: r.emp, p_desde: desde, p_hasta: hasta };
  /* pedidos: también los disruptivos (manual 31, IMPORTANTE), en paralelo */
  var res = await Promise.all([_eiRpc(r.rpc, args), r.tipo === "pedidos" ? _eiRpc(_EI_RPC_DISRUP, args) : Promise.resolve(null)]);
  var q = res[0], qd = res[1];
  if (q.error) { _ei.res[k] = { err: "No pude leer: " + (q.error.message || q.error) + ". No se bajó nada." }; eiPintar(); return false; }
  var rows = Array.isArray(q.data) ? q.data : [];
  if (!rows.length) { _ei.res[k] = { err: "Volvió vacío (sin datos en el período o sin sesión de supervisor). No se bajó nada." }; eiPintar(); return false; }
  /* sin los disruptivos el archivo saldría sin marcar y nadie sabría que faltan: no se baja */
  if (qd && qd.error) { _ei.res[k] = { err: "No pude leer los pedidos disruptivos: " + (qd.error.message || qd.error) + ". No se bajó nada." }; eiPintar(); return false; }
  var dis = qd && Array.isArray(qd.data) ? qd.data : [];
  var mapa = eiDisrupMapa(dis);
  var o = { emp: r.emp, disrup: mapa };
  var ws = r.tipo === "ventas" ? eiHojaVentas(rows, o) : eiHojaPedidos(rows, o);
  _eiBajar(eiXlsBytes(X, ws, eiNombreHoja(r.emp, desde, hasta)), eiNombre(r.tipo, r.emp, desde, hasta));
  var s = { n: rows.length, cant: 0, tot: 0 };
  if (r.tipo === "pedidos") {
    s.disArt = rows.filter(function (x) { return mapa[_eiCodKey(x.cod)]; }).length;
    s.disPed = dis.length;
  }
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

/* ============================================================================
   EST. MADRE y COSTOS por mes (v27.36, Luis 06/10/2026)
   ----------------------------------------------------------------------------
   El módulo «Estadísticas ISIS» sale del panel supervisor y su lógica pasa a la pestaña
   📈 Est. Madre de Stock y Compras:
     · «⬆ Subir Estadística Madre» lee el Excel de la Est. Madre y guarda el ORDEN de los códigos
       de la hoja «Loeke Madre…» (LK) y «Chef Madre / Chef Master» (CH), con el TIPO de cada código
       (505 número, '026' texto) y los renglones en blanco / títulos, para que lo que se baja se pegue
       al lado sin correr una fila.
     · «⬆ Subir Costos» hace lo mismo con los bloques «Loeke» y «Chef» de «Aportes Gastos» (o un
       «costo lk final» suelto: celda «Loeke» con «Uni x mes…» al lado).
     · «⬇ Bajar por mes»: se eligen meses y sale Pedidos LK / Pedidos CH (orden de la Est. Madre)
       o Facturación LK / CH (orden de Costos), una columna por mes, del más nuevo al más viejo,
       SIEMPRE EN UNIDADES.
   LK suma lo de Chef con L (031 = 031 de LK + 031L de Chef): es la cuenta de las dos planillas
   (BUSCARV + SUMAR.SI.CONJUNTO del código&"L"). Verificado: costos 031 ago/26 = 7.056 + 3.336.
   Colores de la Est. Madre (su formato condicional, Luis 06/10): celeste = el mes pasa la E.Madre × 1,3 ·
   amarillo = pasa la E.Madre (columna «E.Madre Uni x Mes» / «Est Madre Uni», capturada al subir).
   Pedido DISRUPTIVO (gv_isis_estad_pedidos_disruptivos, regla v26.20): letra roja negrita y el detalle
   como COMENTARIO de esa celda.
   Plantillas: tabla GV_Est_Plantilla (sql/gv_est_plantilla_v2736.sql). Candado: tests/est-madre-mes.cjs.
   ============================================================================ */

var _EM_MES_L = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre"];
var _em = { pl: {}, sel: {}, msg: "", busy: false, leido: false };

/* clave de cruce de un código: mayúsculas, sin espacios, sin ceros a la izquierda (026 = 26) */
function emKey(c) { return String(c == null ? "" : c).trim().toUpperCase().replace(/\s+/g, "").replace(/^0+(?=[0-9])/, ""); }
function _emEsCodigo(s) { return /^[0-9A-Z][0-9A-Z.\-\/]{0,13}$/i.test(String(s).trim()) && /[0-9]/.test(String(s)); }
function _emTxt(cell) { return cell == null || cell.v == null ? "" : String(cell.v).trim(); }

/* filas de una plantilla a partir de una columna de códigos, desde la fila r0 hasta la última con código */
function _emFilas(ws, X, colCod, colDesc, r0, rFin, cortarEnVacio, colEm) {
  var filas = [], ult = -1;
  for (var r = r0; r <= rFin; r++) {
    var c = ws[X.utils.encode_cell({ r: r, c: colCod })];
    var v = c && c.v != null && String(c.v).trim() !== "" ? c.v : null;
    if (cortarEnVacio) {   /* costos: el bloque sigue aunque haya una fila en blanco; corta en 3 seguidas o en el encabezado del otro bloque */
      if (v == null) { var vac = 0; for (var q = r; q <= rFin && q < r + 3; q++) { var cq = ws[X.utils.encode_cell({ r: q, c: colCod })]; if (!cq || cq.v == null || String(cq.v).trim() === "") vac++; } if (vac >= 3) break; }
      else if (/^(loeke|chef)$/i.test(String(v).trim())) break;
    }
    var d = colDesc != null ? _emTxt(ws[X.utils.encode_cell({ r: r, c: colDesc })]) : "";
    if (v == null) { filas.push({ c: null }); continue; }
    var t = String(v).trim();
    if (c.t !== "n" && !_emEsCodigo(t)) { filas.push({ c: null, t: t }); ult = filas.length - 1; continue; }
    var f = c.t === "n" ? { c: String(v), n: true, d: d } : { c: t, d: d };
    if (colEm != null) { var ce = ws[X.utils.encode_cell({ r: r, c: colEm })]; if (ce && ce.t === "n" && isFinite(ce.v)) f.em = ce.v; }
    filas.push(f);
    ult = filas.length - 1;
  }
  return filas.slice(0, ult + 1);
}
function _emBuscarEnc(ws, X, re, maxFil) {
  var rg = X.utils.decode_range(ws["!ref"] || "A1:A1");
  for (var r = rg.s.r; r <= Math.min(rg.e.r, maxFil || 15); r++)
    for (var c = rg.s.c; c <= Math.min(rg.e.c, 60); c++) {
      var t = _emTxt(ws[X.utils.encode_cell({ r: r, c: c })]);
      if (t && re.test(t)) return { r: r, c: c };
    }
  return null;
}
/* Est. Madre: hoja «Loeke Madre…» → columna «Cod Nuevo Isis»; «Chef Madre…» / «Chef Master» → «Cod. Isis».
   Se descartan las copias («(2)») y las auxiliares («por menor vta»). Devuelve { lk, ch } (lo que encontró). */
function emParsearMadre(X, wb) {
  var out = {};
  [["lk", /^\s*loeke\s+madre/i], ["ch", /^\s*chef\s+(madre|master)/i]].forEach(function (par) {
    var mejor = null;
    wb.SheetNames.forEach(function (nom) {
      if (!par[1].test(nom) || /\(\d+\)|menor|\bpor\b/i.test(nom)) return;
      var ws = wb.Sheets[nom]; if (!ws || !ws["!ref"]) return;
      var enc = _emBuscarEnc(ws, X, /^cod(\.|igo)?\s*(nuevo\s*)?isis$/i, 15);
      if (!enc) return;
      var de = null, ce = null;
      for (var c = 0; c <= 30; c++) {
        var t = _emTxt(ws[X.utils.encode_cell({ r: enc.r, c: c })]);
        if (de == null && /^descrip/i.test(t)) de = c;
        /* «E.Madre Uni x Mes» (LK, col I) / «Est Madre Uni» (CH, col J): la de HOY, no las «… 10/25» de la derecha */
        if (ce == null && /^e(st)?\.?\s*madre\s*uni(\s*x\s*mes)?$/i.test(t.replace(/\s+/g, " "))) ce = c;
      }
      var rg = X.utils.decode_range(ws["!ref"]);
      /* v27.38 (Luis, 06/10): «COD ART es lo importante, es lo que trackeamos». Si la hoja tiene «Cod.Art.»
         (Chef Madre: B y D), manda esa columna —la que más códigos tiene— y no «Cod. Isis», que en Chef guarda
         códigos viejos de ISIS (7053800, «H Lider») en los discontinuados. LK no tiene «Cod.Art.»: sigue «Cod Nuevo Isis». */
      var colCod = enc.c, mejorArt = -1;
      for (var ca = 0; ca <= 30; ca++) {
        if (!/^cod\.?\s*art/i.test(_emTxt(ws[X.utils.encode_cell({ r: enc.r, c: ca })]))) continue;
        var nArt = _emFilas(ws, X, ca, null, enc.r + 1, rg.e.r, false).filter(function (f) { return f.c; }).length;
        if (nArt > mejorArt) { mejorArt = nArt; colCod = ca; }
      }
      var filas = _emFilas(ws, X, colCod, de, enc.r + 1, rg.e.r, false, ce);
      var n = filas.filter(function (f) { return f.c; }).length;
      if (!mejor || n > mejor.n) mejor = { hoja: nom, filas: filas, n: n, meta: { fila_enc: enc.r + 1, col_cod: X.utils.encode_col(colCod), fila_desde: enc.r + 2, col_em: ce == null ? null : X.utils.encode_col(ce) } };
    });
    if (mejor && mejor.n >= 5) out[par[0]] = mejor;
  });
  return out;
}
/* Costos: celda «Loeke» / «Chef» con «Uni x mes…» a la derecha; el bloque sigue hacia abajo hasta la primera vacía. */
function emParsearCostos(X, wb) {
  var out = {}, noms = wb.SheetNames.slice();
  var ia = noms.findIndex(function (n) { return /aportes\s*gastos/i.test(n); });
  if (ia > 0) { noms.unshift(noms.splice(ia, 1)[0]); }
  noms.forEach(function (nom) {
    var ws = wb.Sheets[nom]; if (!ws || !ws["!ref"]) return;
    var rg = X.utils.decode_range(ws["!ref"]);
    for (var r = rg.s.r; r <= rg.e.r; r++)
      for (var c = rg.s.c; c <= Math.min(rg.e.c, 60); c++) {
        var t = _emTxt(ws[X.utils.encode_cell({ r: r, c: c })]).toLowerCase();
        var emp = t === "loeke" ? "lk" : t === "chef" ? "ch" : null;
        if (!emp || out[emp]) continue;
        if (!/^uni\s*x/i.test(_emTxt(ws[X.utils.encode_cell({ r: r, c: c + 1 })]))) continue;
        var filas = _emFilas(ws, X, c, null, r + 1, rg.e.r, true);
        var n = filas.filter(function (f) { return f.c; }).length;
        if (n >= 5) out[emp] = { hoja: nom, filas: filas, n: n, meta: { fila_enc: r + 1, col_cod: X.utils.encode_col(c), fila_desde: r + 2 } };
      }
  });
  return out;
}

/* meses "AAAA-MM" → etiqueta de la columna, como la escriben las planillas */
function emRotulo(tipo, ym) {
  var p = String(ym).split("-"), a = p[0], m = Number(p[1]);
  if (tipo === "fac") return "Vtas " + _EM_MES_L[m - 1] + " " + a + " Uni";
  var m3 = _EI_MES3[m - 1]; return m3.charAt(0).toUpperCase() + m3.slice(1) + " " + a.slice(2) + " Uni";
}
function emRangoMes(ym) {
  var p = String(ym).split("-"), a = Number(p[0]), m = Number(p[1]);
  var fin = new Date(Date.UTC(a, m, 0)).getUTCDate();
  return { desde: a + "-" + String(m).padStart(2, "0") + "-01", hasta: a + "-" + String(m).padStart(2, "0") + "-" + String(fin).padStart(2, "0") };
}
/* suma por clave las filas de una RPC; si emp destino es LK, las de Chef con L van al código base */
function emAcumular(mapa, filas, campo, soloL) {
  (filas || []).forEach(function (x) {
    var cod = String(x.cod == null ? "" : x.cod).trim().toUpperCase();
    if (soloL) { var m = /^(.*[0-9E])L$/.exec(cod); if (!m) return; cod = m[1]; }
    var k = emKey(cod); if (!k) return;
    var e = mapa[k] || (mapa[k] = { u: 0, sinUxb: 0 });
    if (!e.cod) e.cod = cod;
    if (!e.d && x.descripcion) e.d = String(x.descripcion).trim();
    var v = x[campo];
    if (v == null || v === "") e.sinUxb += _eiNum(x.cajas); else e.u += _eiNum(v);
  });
  return mapa;
}
function emDisAcumular(mapa, filas, soloL) {
  (filas || []).forEach(function (d) {
    var cod = String(d.cod == null ? "" : d.cod).trim().toUpperCase();
    if (soloL) { var m = /^(.*[0-9E])L$/.exec(cod); if (!m) return; cod = m[1]; }
    var k = emKey(cod); if (k) (mapa[k] = mapa[k] || []).push(d);
  });
  return mapa;
}

/* Un código vendido que NO está en la planilla va a su código base si la planilla lo tiene: la factura dice la
   variante (727EN, 865ED, 599EZ, 55219ZZ) y la estadística de ISIS / la planilla la cuenta en el base (727E, 865E…).
   Medido ago/26: así el Costos CH da igual a la planilla en 727E (396) y 865E (204). Lo que queda sin lugar se
   devuelve en «sueltos» y la pantalla lo dice: nunca se pierden unidades en silencio. */
function emReubicar(u, enPl, ignorarL) {
  var sueltos = [];
  Object.keys(u || {}).forEach(function (k) {
    if (enPl[k]) return;
    if (ignorarL && /[0-9E]L$/.test(k)) return;   /* lo de Chef con L ya está en la fila LK del código base */
    var m = /^(\d+E?)[A-Z]{1,2}$/.exec(k), base = m && m[1];
    if (base && enPl[base]) {
      var e = u[base] || (u[base] = { u: 0, sinUxb: 0 });
      e.u += u[k].u; e.sinUxb += u[k].sinUxb; e.de = (e.de || []).concat(k); delete u[k];
    } else if (u[k].u || u[k].sinUxb) sueltos.push(k);
  });
  return sueltos;
}
/* arma la hoja. tipo "ped" (A cód · B descripción · meses) o "fac" (A cód · meses).
   datos[ym] = { u: {clave: {u, sinUxb}}, dis: {clave: [...]} }. Devuelve { ws, estilo(col,row) } */
function emArmarHoja(X, tipo, emp, pl, meses, datos) {
  var ws = {}, conDesc = tipo === "ped", c0 = conDesc ? 2 : 1, disr = {}, nDis = 0, nSin = 0, nAma = 0, nCel = 0;
  var put = function (r, c, cell) { ws[X.utils.encode_cell({ r: r, c: c })] = cell; };
  put(0, 0, { t: "s", v: tipo === "fac" ? (emp === "lk" ? "Loeke" : "Chef") : (emp === "lk" ? "Cod Nuevo Isis" : "Cod. Isis") });
  if (conDesc) put(0, 1, { t: "s", v: "Descripcion" });
  meses.forEach(function (ym, j) { put(0, c0 + j, { t: "s", v: emRotulo(tipo, ym) }); });
  var hdr = { 0: true }, enPl = { lk: {}, ch: {}, x: {} }, sueltos = {};
  (pl.filas || []).forEach(function (f) { if (f.c) enPl[f.src || "x"][emKey(f.c)] = true; });
  meses.forEach(function (ym) {
    (pl.filas.some(function (f) { return f.src; }) ? ["lk", "ch"] : ["x"]).forEach(function (sr) {
      var d = (sr === "x" ? datos : (datos[sr] || {}))[ym];
      if (d) emReubicar(d.u, enPl[sr], sr === "ch" || (sr === "x" && emp === "ch")).forEach(function (k) {
        var id = sr + "|" + k;
        if (!sueltos[id]) sueltos[id] = { sr: sr, k: k, cod: (d.u[k] && d.u[k].cod) || k, d: (d.u[k] && d.u[k].d) || "" };
      });
    });
  });
  (pl.filas || []).forEach(function (f, i) {
    var r = i + 1;
    /* encabezado intermedio (el «Chef» de Costos, en la misma columna que LK): rótulo + meses, como la fila 1 */
    if (f.h) { hdr[r] = true; put(r, 0, { t: "s", v: f.h }); meses.forEach(function (ym, j) { put(r, c0 + j, { t: "s", v: emRotulo(tipo, ym) }); }); return; }
    if (!f.c) { if (f.t) put(r, 0, { t: "s", v: f.t }); return; }
    put(r, 0, f.n ? { t: "n", v: Number(f.c) } : { t: "s", v: String(f.c) });
    if (conDesc && f.d) put(r, 1, { t: "s", v: String(f.d) });
    var k = emKey(f.c);
    meses.forEach(function (ym, j) {
      var d = (f.src ? (datos[f.src] || {}) : datos)[ym] || {}, e = (d.u || {})[k], lista = (d.dis || {})[k];
      var cell = { t: "n", v: e ? Math.round(e.u * 100) / 100 : 0 };
      var notas = [];
      var ref = X.utils.encode_cell({ r: r, c: c0 + j }), est = 0;
      /* colores de la Est. Madre (Luis, 06/10, su formato condicional): celeste = mes > E.Madre × 1,3 · amarillo = mes > E.Madre */
      if (tipo === "ped" && f.em > 0 && cell.v > f.em) { est = cell.v > f.em * 1.3 ? 2 : 1; if (est === 2) nCel++; else nAma++; }
      if (lista && lista.length) { notas.push(eiDisrupTexto(lista, emp).split(" | ").join("\n")); est += 10; nDis++; }
      if (est) disr[ref] = est;
      if (e && e.de) notas.push("Incluye lo facturado como " + e.de.join(", ") + ".");
      if (e && e.sinUxb) { notas.push("Sin UxB cargada: " + _eiN(e.sinUxb, 1) + " cajas no se pudieron pasar a unidades."); nSin++; }
      if (notas.length) { cell.c = [{ a: "Gestion", t: notas.join("\n\n") }]; cell.c.hidden = true; }
      put(r, c0 + j, cell);
    });
  });
  /* v27.40 (Luis, 06/10): lo que tenemos en nuestra data y NO está en la planilla va AL FONDO, con la fila entera en
     NARANJA, para que lo ubiquen a mano. Un renglón en blanco antes; la última columna dice de qué empresa es. */
  var nf = (pl.filas || []).length, naranja = {}, lista = Object.keys(sueltos).map(function (id) { return sueltos[id]; })
    .sort(function (a, b) { return a.sr === b.sr ? String(a.cod).localeCompare(String(b.cod), "es", { numeric: true }) : (a.sr < b.sr ? 1 : -1); });
  var cNota = c0 + meses.length;
  if (lista.length) {
    nf++;
    lista.forEach(function (x) {
      nf++; var r = nf; naranja[r] = true;
      put(r, 0, /^\d+$/.test(x.cod) ? { t: "n", v: Number(x.cod) } : { t: "s", v: x.cod });
      if (conDesc) put(r, 1, { t: "s", v: x.d || "" });
      meses.forEach(function (ym, j) {
        var d = (x.sr === "x" ? datos : (datos[x.sr] || {}))[ym] || {}, e = (d.u || {})[x.k];
        put(r, c0 + j, { t: "n", v: e ? Math.round(e.u * 100) / 100 : 0 });
      });
      put(r, cNota, { t: "s", v: "No está en la planilla" + (x.sr === "x" ? "" : " (" + (x.sr === "lk" ? "Loeke" : "Chef") + ")") + (x.d && !conDesc ? " · " + x.d : "") + ": ubicarlo a mano" });
    });
  }
  ws["!ref"] = "A1:" + X.utils.encode_cell({ r: Math.max(nf, 1), c: lista.length ? cNota : c0 + meses.length - 1 });
  ws["!cols"] = [{ wch: 12 }].concat(conDesc ? [{ wch: 34 }] : []).concat(meses.map(function () { return { wch: tipo === "fac" ? 22 : 13 }; })).concat(lista.length ? [{ wch: 48 }] : []);
  return {
    ws: ws, nDis: nDis, nSin: nSin, nAma: nAma, nCel: nCel, sueltos: lista.map(function (x) { return (x.sr === "x" ? "" : x.sr.toUpperCase() + " ") + x.cod; }),
    estilo: function (ref) {
      var m = /^([A-Z]+)(\d+)$/.exec(ref); if (!m) return 0;
      if (hdr[Number(m[2]) - 1]) return 1;
      if (naranja[Number(m[2]) - 1]) return X.utils.decode_col(m[1]) >= c0 && X.utils.decode_col(m[1]) < cNota ? 9 : 8;   /* fila entera naranja */
      if (X.utils.decode_col(m[1]) < c0) return 0;
      var e = disr[ref] || 0, fondo = e % 10, rojo = e >= 10;
      return 2 + fondo * 2 + (rojo ? 1 : 0);   /* 2 número · 3 rojo · 4 amarillo · 5 amarillo+rojo · 6 celeste · 7 celeste+rojo */
    }
  };
}
/* Costos: LK y Chef van en la MISMA columna, como en «Aportes Gastos» (Loeke en la fila 8, Chef en la 266):
   bloque LK, las filas en blanco que haya entre los dos, el rótulo «Chef» y el bloque CH. Así se copia la
   columna entera y se pega una sola vez. Cada fila lleva src (lk / ch) para saber de qué empresa cuenta. */
function emPlantillaCostos(lk, ch) {
  var filas = [];
  (lk.filas || []).forEach(function (f) { filas.push(Object.assign({ src: "lk" }, f)); });
  var gap = ch.meta && lk.meta && ch.meta.fila_enc && lk.meta.fila_desde
    ? ch.meta.fila_enc - (lk.meta.fila_desde + (lk.filas || []).length) : 1;
  for (var g = 0; g < Math.max(0, Math.min(gap, 20)); g++) filas.push({ c: null });
  filas.push({ c: null, h: "Chef" });
  (ch.filas || []).forEach(function (f) { filas.push(Object.assign({ src: "ch" }, f)); });
  return { filas: filas, n: (lk.n || 0) + (ch.n || 0) };
}
/* .xlsx con estilos: 0 normal · 1 encabezado negrita centrado · 2 número #,##0 · 3 disruptivo (letra roja negrita)
   · 4/5 amarillo (> E.Madre) · 6/7 celeste (> E.Madre × 1,3), con o sin disruptivo · 8/9 naranja (sin fila en la planilla). SheetJS community no escribe
   estilos: se reescribe styles.xml. */
function emXlsxBytes(X, hojas, tam) {
  var wb = X.utils.book_new();
  hojas.forEach(function (h) { X.utils.book_append_sheet(wb, h.ws, String(h.nombre).slice(0, 31)); });
  var u8 = X.write(wb, { type: "array", bookType: "xlsx" });
  var cfb = X.CFB.read(new Uint8Array(u8), { type: "array" });
  var dec = new TextDecoder(), enc = new TextEncoder(), sz = tam || 10;
  var iSt = cfb.FullPaths.findIndex(function (p) { return /\/xl\/styles\.xml$/.test(p); });
  if (iSt < 0) throw new Error("xlsx sin styles.xml");
  var st = dec.decode(new Uint8Array(cfb.FileIndex[iSt].content));
  var font = function (b, rojo) { return '<font>' + (b ? '<b/>' : '') + '<sz val="' + sz + '"/>' + (rojo ? '<color rgb="FFFF0000"/>' : '') + '<name val="Arial"/><family val="2"/></font>'; };
  st = st.replace(/<numFmts[\s\S]*?<\/numFmts>/, "").replace(/<numFmts[^>]*\/>/, "")
    .replace(/<fonts[\s\S]*?<\/fonts>/, '<fonts count="3">' + font(false) + font(true) + font(true, true) + '</fonts>')
    .replace(/<fills[\s\S]*?<\/fills>/, '<fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
      '<fill><patternFill patternType="solid"><fgColor rgb="FFFFFF00"/><bgColor indexed="64"/></patternFill></fill>' +
      '<fill><patternFill patternType="solid"><fgColor rgb="FFBDD7EE"/><bgColor indexed="64"/></patternFill></fill>' +
      '<fill><patternFill patternType="solid"><fgColor rgb="FFFFC000"/><bgColor indexed="64"/></patternFill></fill></fills>')
    .replace(/<cellXfs[\s\S]*?<\/cellXfs>/, function () {
      var xn = function (font, fill) { return '<xf numFmtId="3" fontId="' + font + '" fillId="' + fill + '" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/>'; };
      return '<cellXfs count="10"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>' +
        xn(0, 0) + xn(2, 0) + xn(0, 2) + xn(2, 2) + xn(0, 3) + xn(2, 3) +
        '<xf numFmtId="0" fontId="1" fillId="4" borderId="0" xfId="0" applyFont="1" applyFill="1"/>' + xn(1, 4) + '</cellXfs>';   /* 8/9 naranja: sin fila en la planilla */
    });
  cfb.FileIndex[iSt].content = enc.encode(st);
  var n = 0;
  cfb.FullPaths.forEach(function (p, i) {
    var m = /\/xl\/worksheets\/sheet(\d+)\.xml$/.exec(p); if (!m) return;
    var h = hojas[Number(m[1]) - 1]; if (!h) return;
    var x = dec.decode(new Uint8Array(cfb.FileIndex[i].content));
    x = x.replace(/<c r="([A-Z]+\d+)"( s="\d+")?/g, function (_m, ref) { return '<c r="' + ref + '" s="' + h.estilo(ref) + '"'; })
         .replace(/<sheetView workbookViewId="0"\/>/, '<sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView>');
    cfb.FileIndex[i].content = enc.encode(x); n++;
  });
  return X.CFB.write(cfb, { fileType: "zip", type: "array" });
}

/* ---------- pantalla: barra arriba de la Est. Madre + pop-up de meses ---------- */
var _EM_SAL = [
  { k: "plk", tipo: "ped", emp: "lk", t: "Pedidos LK", pl: "madre_lk" },
  { k: "pch", tipo: "ped", emp: "ch", t: "Pedidos CH", pl: "madre_ch" },
  { k: "flk", tipo: "fac", emp: "lk", t: "Facturación LK", pl: "costos_lk" },
  { k: "fch", tipo: "fac", emp: "ch", t: "Facturación CH", pl: "costos_ch" },
  /* las dos tildadas → un solo archivo con LK y Chef en la misma columna, como «Aportes Gastos» */
  { k: "fac", tipo: "fac", emp: "lk", t: "Facturación LK + CH", pl: "costos_lk", pl2: "costos_ch" }
];
var _EM_CHK = [["plk", "Pedidos LK"], ["pch", "Pedidos CH"], ["flk", "Facturación LK"], ["fch", "Facturación CH"]];
function _emCss() {
  if (document.getElementById("emCss")) return;
  var st = document.createElement("style"); st.id = "emCss";
  st.textContent = [
    /* v27.44 (Luis, 06/10: «inentendible… más grande, más visible, sin el texto de abajo; los meses con un calendario»):
       tres pasos grandes, uno al lado del otro — 1 subir · 2 meses (calendario) · 3 descargar */
    "#emBar{display:flex;justify-content:center;padding:10px 12px;background:#f1f5f9;border-bottom:1px solid #cbd5e1;font:15px system-ui,Segoe UI,Arial,sans-serif;color:#0f172a;}",
    "#emBar .sec-box{display:grid;gap:8px;justify-items:center;border:2px solid #1e3a8a;border-radius:14px;background:#fff;padding:10px 14px;max-width:100%;box-shadow:0 2px 8px rgba(15,23,42,.08);}",
    "#emBar .tit{font-size:15px;font-weight:900;letter-spacing:.8px;text-transform:uppercase;color:#1e3a8a;}",
    "#emBar .pasos{display:flex;flex-wrap:wrap;gap:12px;align-items:stretch;justify-content:center;}",
    "#emBar .paso{display:flex;flex-direction:column;gap:8px;align-items:center;justify-content:flex-start;border:1px solid #e2e8f0;border-radius:12px;padding:8px 12px;background:#f8fafc;}",
    "#emBar .paso-t{font-size:13px;font-weight:900;color:#475569;text-transform:uppercase;letter-spacing:.5px;}",
    "#emBar .paso-t .n{display:inline-block;width:22px;height:22px;line-height:22px;border-radius:50%;background:#1e3a8a;color:#fff;text-align:center;margin-right:6px;font-size:13px;}",
    "#emBar button{width:auto;margin-top:0;padding:10px 16px;font-size:15px;line-height:1.2;border:none;border-radius:10px;font-weight:800;cursor:pointer;background:#1e3a8a;color:#fff;}",
    "#emBar button:disabled{opacity:.45;cursor:not-allowed;}",
    "#emBar .subir{display:flex;flex-direction:column;align-items:center;gap:2px;min-width:230px;}",
    "#emBar .subir small{font-size:12.5px;font-weight:700;opacity:.9;}#emBar .subir small .no{color:#fecaca;}",
    /* calendario: año arriba con flechas, los 12 meses en 4 × 3 */
    "#emBar .cal{display:grid;gap:6px;}",
    "#emBar .cal-h{display:flex;align-items:center;justify-content:space-between;gap:8px;}",
    "#emBar .cal-h b{font-size:17px;}",
    "#emBar .cal-h button{background:#e2e8f0;color:#0f172a;padding:4px 12px;font-size:17px;}",
    "#emBar .cal-g{display:grid;grid-template-columns:repeat(4,58px);gap:5px;}",
    "#emBar .cal-g button{padding:8px 0;font-size:15px;background:#fff;color:#0f172a;border:1px solid #cbd5e1;font-weight:700;text-transform:capitalize;}",
    "#emBar .cal-g button.on{background:#1e3a8a;color:#fff;border-color:#1e3a8a;}",
    "#emBar .cal-g button.otro{box-shadow:inset 0 -3px 0 #1e3a8a;}",
    "#emBar .cal-g button:disabled{background:#f1f5f9;color:#cbd5e1;border-color:#e2e8f0;opacity:1;}",
    "#emBar .cal-pie{display:flex;gap:6px;justify-content:center;}",
    "#emBar .cal-pie button{background:#e2e8f0;color:#0f172a;padding:5px 10px;font-size:13px;}",
    "#emBar .chks{display:grid;grid-template-columns:repeat(2,auto);gap:6px;}",
    "#emBar label.ck{display:flex;gap:7px;align-items:center;font-weight:800;cursor:pointer;white-space:nowrap;padding:8px 12px;border:1px solid #cbd5e1;border-radius:10px;background:#fff;font-size:15px;}",
    "#emBar label.ck.on{border-color:#1e3a8a;background:#dbeafe;}",
    "#emBar label.ck input{width:18px;height:18px;margin:0;}",
    "#emBar #emBajarSel{background:#15803d;font-size:17px;padding:12px 20px;}",
    "#emBar .msg{font-size:14px;font-weight:800;color:#1e3a8a;text-align:center;max-width:1000px;}#emBar .msg.err{color:#b91c1c;}"
  ].join("\n");
  document.head.appendChild(st);
}
function _emFecha(t) { var d = new Date(t); return isNaN(d) ? "" : String(d.getDate()).padStart(2, "0") + "/" + String(d.getMonth() + 1).padStart(2, "0"); }
function _emMesCorto(ym) { var p = String(ym).split("-"), m = _EI_MES3[Number(p[1]) - 1] || ""; return m + " " + String(p[0]).slice(2); }
function _emMesesOpc() {
  var hoy = new Date(), out = [];
  for (var i = 0; i <= 18; i++) { var d = new Date(hoy.getFullYear(), hoy.getMonth() - i, 1); out.push(d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")); }
  return out;
}
/* el estado de cada planilla va DENTRO de su botón (sin renglón de texto abajo) */
function _emPlEstado(base) {
  var p = function (emp) {
    var x = _em.pl[base + "_" + emp];
    return x ? emp.toUpperCase() + " ✓ " + (x.subido_en ? _emFecha(x.subido_en) : "") : '<span class="no">' + emp.toUpperCase() + " falta</span>";
  };
  return p("lk") + " · " + p("ch");
}
function emBarPintar() {
  var b = document.getElementById("emBar"); if (!b) return;
  _emCss();
  var hoy = new Date(), ymHoy = hoy.getFullYear() + "-" + String(hoy.getMonth() + 1).padStart(2, "0");
  if (!_em.limpio && !Object.keys(_em.sel).length) _em.sel[_emMesesOpc()[1]] = true;   /* default: el último mes cerrado */
  if (!_em.chk) _em.chk = { plk: true, pch: true, flk: true, fch: true };
  if (!_em.anio) _em.anio = hoy.getFullYear();
  var anioMin = hoy.getFullYear() - 2, A = _em.anio;
  var sel = Object.keys(_em.sel).sort().reverse();
  var algun = _EM_CHK.some(function (c) { return _em.chk[c[0]]; });
  var otrosAnios = sel.filter(function (ym) { return Number(ym.slice(0, 4)) !== A; }).length;
  var cal = '<div class="cal">' +
    '<div class="cal-h"><button type="button" onclick="emCalAnio(-1)"' + (A <= anioMin ? " disabled" : "") + ' title="Año anterior">‹</button>' +
      '<b>' + A + '</b><button type="button" onclick="emCalAnio(1)"' + (A >= hoy.getFullYear() ? " disabled" : "") + ' title="Año siguiente">›</button></div>' +
    '<div class="cal-g">' + _EI_MES3.map(function (m, i) {
      var ym = A + "-" + String(i + 1).padStart(2, "0");
      return '<button type="button" data-ym="' + ym + '" class="' + (_em.sel[ym] ? "on" : "") + '"' + (ym > ymHoy ? " disabled" : "") +
        ' onclick="emToggleMes(\'' + ym + '\')">' + m + '</button>';
    }).join("") + '</div>' +
    '<div class="cal-pie"><button type="button" onclick="emMesesLimpiar()">Limpiar</button>' +
      (otrosAnios ? '<span style="font-size:13px;font-weight:700;color:#475569;align-self:center">+' + otrosAnios + ' de otro año</span>' : '') + '</div>' +
  '</div>';
  b.innerHTML = '<div class="sec-box"><div class="tit">Importar / exportar</div><div class="pasos">' +
    '<div class="paso"><div class="paso-t"><span class="n">1</span>Subir planillas</div>' +
      '<button type="button" class="subir" onclick="emSubir(\'madre\')">⬆ Subir Estadística Madre<small>' + _emPlEstado("madre") + '</small></button>' +
      '<button type="button" class="subir" onclick="emSubir(\'costos\')">⬆ Subir Costos<small>' + _emPlEstado("costos") + '</small></button>' +
    '</div>' +
    '<div class="paso"><div class="paso-t" id="emMesesBtn"><span class="n">2</span>Meses: ' +
      (sel.length ? _eiEsc(sel.map(_emMesCorto).join(", ")) : "ninguno") + '</div>' + cal + '</div>' +
    '<div class="paso"><div class="paso-t"><span class="n">3</span>Descargar</div>' +
      '<div class="chks">' + _EM_CHK.map(function (c) {
        return '<label class="ck' + (_em.chk[c[0]] ? " on" : "") + '"><input type="checkbox"' + (_em.chk[c[0]] ? " checked" : "") + ' onchange="emChk(\'' + c[0] + '\', this.checked)">' + c[1] + '</label>';
      }).join("") + '</div>' +
      '<button type="button" id="emBajarSel"' + (_em.busy || !sel.length || !algun ? " disabled" : "") + ' onclick="emBajarSeleccionados()">' + (_em.busy ? "Armando…" : "⬇ Descargar seleccionados") + '</button>' +
    '</div>' +
    '</div>' +
    (_em.msg ? '<div class="msg' + (_em.msgErr ? ' err' : '') + '">' + _eiEsc(_em.msg) + '</div>' : '') +
    (_em.res ? '<div class="msg' + (_em.resErr ? ' err' : '') + '">' + _eiEsc(_em.res) + '</div>' : '') +
    '<input type="file" id="emFile" accept=".xlsx,.xlsm,.xls" style="display:none" onchange="emArchivo(this)">' +
  '</div>';
  if (!_em.leido) { _em.leido = true; emLeerPlantillas(); }
}
function emPintar() { emBarPintar(); }
function emCalAnio(d) { _em.anio = (_em.anio || new Date().getFullYear()) + d; emBarPintar(); }
function emMesesLimpiar() { _em.sel = {}; _em.limpio = true; emBarPintar(); }
function emToggleMes(ym) { if (_em.sel[ym]) delete _em.sel[ym]; else _em.sel[ym] = true; _em.limpio = true; emBarPintar(); }
function emChk(k, on) { _em.chk = _em.chk || {}; _em.chk[k] = !!on; emBarPintar(); }
/* baja lo tildado, de a uno (el navegador frena descargas pegadas); Facturación LK + CH juntas = UN archivo */
async function emBajarSeleccionados() {
  var c = _em.chk || {}, ks = [];
  if (c.plk) ks.push("plk");
  if (c.pch) ks.push("pch");
  if (c.flk && c.fch) ks.push("fac"); else if (c.flk) ks.push("flk"); else if (c.fch) ks.push("fch");
  var res = [], err = false;
  for (var i = 0; i < ks.length; i++) {
    var ok = await emBajar(ks[i]);
    res.push(_em.res); if (!ok) err = true;
    if (i < ks.length - 1) await new Promise(function (r) { setTimeout(r, 700); });
  }
  _em.res = res.join("  ·  "); _em.resErr = err; emBarPintar();
  return !err;
}
async function emLeerPlantillas() {
  var q = await _eiRpc("gv_est_plantilla_leer", {});
  if (q.error) { _em.msg = "No pude leer las plantillas: " + (q.error.message || q.error); _em.msgErr = true; }
  else (q.data || []).forEach(function (p) {
    p.n = (p.filas || []).filter(function (f) { return f && f.c; }).length;
    _em.pl[p.clave] = p;
  });
  emBarPintar(); emPintar();
}
function emSubir(cual) {
  _em.subiendo = cual;
  var f = document.getElementById("emFile"); if (f) { f.value = ""; f.click(); }
}
async function emArchivo(inp) {
  var file = inp && inp.files && inp.files[0]; if (!file) return;
  var cual = _em.subiendo;
  _em.msg = "Leyendo " + file.name + "…"; _em.msgErr = false; emBarPintar();
  try {
    var X = await _eiXlsx();
    var buf = new Uint8Array(await file.arrayBuffer());
    var nombres = X.read(buf, { type: "array", bookSheets: true }).SheetNames;
    var quiero = cual === "madre"
      ? nombres.filter(function (n) { return /^\s*(loeke\s+madre|chef\s+(madre|master))/i.test(n); })
      : (nombres.filter(function (n) { return /aportes\s*gastos/i.test(n); }).length ? nombres.filter(function (n) { return /aportes\s*gastos/i.test(n); }) : nombres.slice(0, 5));
    if (!quiero.length) throw new Error(cual === "madre" ? "no encontré las hojas «Loeke Madre» / «Chef Madre»" : "no encontré la hoja «Aportes Gastos»");
    var wb = X.read(buf, { type: "array", sheets: quiero, cellFormula: false, cellHTML: false, cellStyles: false });
    var res = cual === "madre" ? emParsearMadre(X, wb) : emParsearCostos(X, wb);
    var ks = Object.keys(res);
    if (!ks.length) throw new Error(cual === "madre" ? "ninguna hoja tiene la columna «Cod Nuevo Isis» / «Cod. Isis»" : "no encontré la celda «Loeke» / «Chef» con «Uni x mes…» al lado");
    var dichos = [];
    for (var i = 0; i < ks.length; i++) {
      var r = res[ks[i]], clave = cual + "_" + ks[i];
      var q = await _eiRpc("gv_est_plantilla_guardar", { p_clave: clave, p_archivo: file.name, p_hoja: r.hoja, p_filas: r.filas, p_meta: r.meta });
      if (q.error) throw new Error("no se pudo guardar " + clave + ": " + (q.error.message || q.error));
      dichos.push(ks[i].toUpperCase() + " " + r.n + " códigos (hoja «" + r.hoja + "»)");
    }
    _em.msg = "✓ " + (cual === "madre" ? "Est. Madre" : "Costos") + ": " + dichos.join(" · ");
    _em.msgErr = false; _em.leido = true;
    await emLeerPlantillas();
  } catch (e) { _em.msg = "No se subió: " + (e && e.message || e); _em.msgErr = true; emBarPintar(); }
}
async function emBajar(k) {
  var s = _EM_SAL.find(function (z) { return z.k === k; }); if (!s || _em.busy) return false;
  var pl = _em.pl[s.pl];
  if (s.pl2) pl = _em.pl[s.pl2] && pl ? emPlantillaCostos(pl, _em.pl[s.pl2]) : null;
  var meses = Object.keys(_em.sel).sort().reverse();
  if (!pl) { _em.res = "Falta subir la plantilla."; _em.resErr = true; emPintar(); return false; }
  if (!meses.length) { _em.res = "Elegí al menos un mes."; _em.resErr = true; emPintar(); return false; }
  _em.busy = true; _em.res = "Armando " + s.t + "…"; _em.resErr = false; emPintar();
  try {
    var X = await _eiXlsx(), datos = {};
    var rpc = s.tipo === "ped" ? "gv_isis_estad_pedidos" : "gv_isis_estad_ventas", campo = s.tipo === "ped" ? "unidades" : "cantidad";
    await Promise.all(meses.map(async function (ym) {
      var rg = emRangoMes(ym), a = function (emp) { return { p_empresa: emp, p_desde: rg.desde, p_hasta: rg.hasta }; };
      var llamadas = [_eiRpc(rpc, a(s.emp))];
      if (s.emp === "lk") llamadas.push(_eiRpc(rpc, a("ch")));
      if (s.tipo === "ped") { llamadas.push(_eiRpc(_EI_RPC_DISRUP, a(s.emp))); if (s.emp === "lk") llamadas.push(_eiRpc(_EI_RPC_DISRUP, a("ch"))); }
      var r = await Promise.all(llamadas);
      r.forEach(function (q) { if (q.error) throw new Error(emRotulo(s.tipo, ym) + ": " + (q.error.message || q.error)); });
      if (!Array.isArray(r[0].data) || !r[0].data.length) throw new Error(emRotulo(s.tipo, ym) + " volvió vacío (sin datos o sin sesión de supervisor)");
      var u = emAcumular({}, r[0].data, campo, false), dis = {}, i = 1;
      if (s.emp === "lk") { emAcumular(u, r[1].data, campo, true); i = 2; }
      if (s.tipo === "ped") { emDisAcumular(dis, r[i].data, false); if (s.emp === "lk") emDisAcumular(dis, r[i + 1].data, true); }
      if (s.pl2) {   /* Costos LK + CH en una columna: LK = LK + Chef con L; CH = lo de Chef con su código */
        if (!Array.isArray(r[1].data) || !r[1].data.length) throw new Error(emRotulo(s.tipo, ym) + " de Chef volvió vacío");
        (datos.lk = datos.lk || {})[ym] = { u: u, dis: {} };
        (datos.ch = datos.ch || {})[ym] = { u: emAcumular({}, r[1].data, campo, false), dis: {} };
      } else datos[ym] = { u: u, dis: dis };
    }));
    var h = emArmarHoja(X, s.tipo, s.emp, pl, meses, datos);
    h.nombre = s.t;
    /* v27.40: ANTES de bajar se avisa qué códigos nuestros no están en la planilla (van al fondo, en naranja) */
    if (h.sueltos.length && typeof window !== "undefined" && typeof window.confirm === "function" &&
        !window.confirm(h.sueltos.length + " código(s) con " + (s.tipo === "ped" ? "pedidos" : "facturación") + " NO están en la planilla:\n\n" +
          h.sueltos.join(", ") + "\n\nVan al final de la lista con la fila en NARANJA para que los ubiques a mano. ¿Bajar el archivo?")) {
      _em.busy = false; _em.res = "No se bajó: " + h.sueltos.length + " código(s) sin fila en la planilla (" + h.sueltos.join(", ") + ")."; _em.resErr = true; emPintar(); return false;
    }
    var nom = s.t.replace(/\s+/g, "_").replace("ó", "o") + "_" + meses.slice().reverse().map(function (ym) { var p = ym.split("-"); return _EI_MES3[Number(p[1]) - 1] + p[0].slice(2); }).join("-") + ".xlsx";
    gvXlsxBajar(emXlsxBytes(X, [h], s.tipo === "fac" ? 14 : 10), nom);
    _em.res = "✓ " + s.t + ": " + meses.length + " mes(es), " + pl.n + " códigos" + (h.nCel ? " · " + h.nCel + " celestes (> E.Madre +30 %)" : "") + (h.nAma ? " · " + h.nAma + " amarillas (> E.Madre)" : "") + (h.nDis ? " · " + h.nDis + " disruptivas" : "") + (h.nSin ? " · " + h.nSin + " sin UxB (ver comentario)" : "") +
      (h.sueltos.length ? " · 🟧 " + h.sueltos.length + " sin fila en la planilla, al final en naranja: " + h.sueltos.join(", ") : "");
    _em.resErr = false;
  } catch (e) { _em.res = "No se bajó nada: " + (e && e.message || e); _em.resErr = true; }
  _em.busy = false; emPintar();
  return !_em.resErr;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { eiHojaVentas: eiHojaVentas, eiHojaPedidos: eiHojaPedidos, eiXlsBytes: eiXlsBytes, eiNombre: eiNombre,
                     eiNombreHoja: eiNombreHoja, eiCodVal: eiCodVal, eiDisrupMapa: eiDisrupMapa, eiDisrupTexto: eiDisrupTexto,
                     emKey: emKey, emParsearMadre: emParsearMadre, emParsearCostos: emParsearCostos, emArmarHoja: emArmarHoja, emPlantillaCostos: emPlantillaCostos, emReubicar: emReubicar,
                     emXlsxBytes: emXlsxBytes, emAcumular: emAcumular, emDisAcumular: emDisAcumular, emRotulo: emRotulo, emRangoMes: emRangoMes };
}
