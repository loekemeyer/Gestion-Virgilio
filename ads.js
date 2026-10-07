/* ============================================================================
   ADS — ALERTAS DAMIÁN STOCK (v27.21, pedido de Luis 06/10/2026)
   ----------------------------------------------------------------------------
   "Necesitamos una señal clara de que hay problemas de abastecimiento."

   PESTAÑA 1 · ENTREGAS TALLERISTAS
     Se elige un rango de OC (las últimas 2…12 generadas) y por cada tallerista
     (el proveedor de la OC) y cada artículo se mide cuánto se le pidió y cuánto
     entregó. La OC de cada semana REEMPLAZA a la anterior (lleva lo que faltaba +
     lo nuevo), así que lo pedido NO es la suma de las OC:
        pedido = 1.ª OC del rango + Σ max(0, OC_k − lo que faltaba de OC_{k−1})
     Ejemplo de Luis: OC1 300 (entregó 150), OC2 200 (entregó 100) → pedido 350,
     entregado 250. Lo entregado es lo que RECIBIÓ VIRGILIO de ese proveedor y código
     en el período (talleristas + prov AT), topado en lo pedido (v27.28, D6). Por defecto
     la OC más nueva NO entra: su semana corre.
     Tallerista con % < umbral (50 % por defecto, editable) → badge VIOLETA en el
     botón ADS del panel, con cuántos son. Rango y umbral viven en Stock_Config
     (ads_n_ocs, ads_umbral, ads_incluir_actual): el badge es el mismo para todos.
   PESTAÑA 2 · STOCK (quiebres a 10, 20 y 30 días)
     saldo N = (góndola + racks + a guardar + excedente) − el MAYOR entre las NP programadas
               sin pickear con entrega hasta hoy + N (vencidas también) y Est. Madre × N/30
               (v27.92, Luis D3: no la suma — lo comprometido ya es parte de la Est. Madre)
     Negativo = quiebre. Sólo artículos CON TALLERISTA (v27.23: los importados sin tallerista no van).
     Con la última OC del código (cuánto se recibió) y el %
     que viene entregando ese tallerista en ese artículo (rango de la pestaña 1).

   Backend: sql/gv_ads_alertas_damian_v2720.sql + sql/gv_ads_excedente_semaforo_v2722.sql (gv_ads_talleristas, gv_ads_stock3 (v27.30: + recibido por Virgilio desde la OC),
   gv_ads_badge, gv_ads_badge_stock, gv_ads_config, gv_ads_config_guardar). Sólo lectura salvo la config.
   ⚠ Una lectura que falla se DICE, no se dibuja como "todo bien" (regla "una
   lectura ROTA no es un CERO"). Vive en su propio archivo (regla v23.98), con ?v=
   atado a APP_VERSION. Candado: tests/ads-alertas.cjs.
   ============================================================================ */

var _ads = { tab: "tall", cfg: null, tall: null, tallErr: "", stock: null, stockErr: "",
             n: 4, inc: true, umbral: 0.5, abiertos: {}, horiz: 10, q: "", cargando: 0 };

function _adsRpc(name, args) {
  var sb = window.sb;
  if (!sb || typeof sb.rpc !== "function") return Promise.resolve({ data: null, error: { message: "sin sesión" } });
  try { return Promise.resolve(sb.rpc(name, args || {})).catch(function (e) { return { data: null, error: e }; }); }
  catch (e) { return Promise.resolve({ data: null, error: e }); }
}
function _adsEsc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
function _adsN(v, dec) { var n = Number(v); return isFinite(n) ? n.toLocaleString("es-AR", { minimumFractionDigits: dec || 0, maximumFractionDigits: dec || 0 }) : "—"; }
function _adsPct(x) { return isFinite(x) && x != null ? _adsN(x * 100) + " %" : "—"; }
function _adsFecha(d) { if (!d) return "—"; var s = String(d).slice(0, 10).split("-"); return s.length === 3 ? s[2] + "/" + s[1] : String(d); }

/* Agrupa las filas (tallerista, artículo) por tallerista. Puro: lo prueba el test. */
function adsAgruparTalleristas(rows, umbral) {
  var m = {};
  (rows || []).forEach(function (r) {
    var k = r.pkey || r.proveedor;
    var t = m[k] || (m[k] = { pkey: k, proveedor: r.proveedor, arts: [], pedido: 0, entregado: 0 });
    t.arts.push(r); t.pedido += Number(r.pedido) || 0; t.entregado += Number(r.entregado) || 0;
  });
  var out = Object.keys(m).map(function (k) {
    var t = m[k]; t.pct = t.pedido > 0 ? t.entregado / t.pedido : null;
    t.alerta = t.pct != null && t.pct < umbral;
    t.arts.sort(function (a, b) { return (Number(a.pct) || 0) - (Number(b.pct) || 0) || (Number(b.pedido) || 0) - (Number(a.pedido) || 0); });
    return t;
  });
  out.sort(function (a, b) { return (a.pct == null ? 9 : a.pct) - (b.pct == null ? 9 : b.pct) || b.pedido - a.pedido; });
  return out;
}

function _adsCss() {
  if (document.getElementById("adsCss")) return;
  var st = document.createElement("style"); st.id = "adsCss";
  st.textContent = [
    "#adsOv{position:fixed;inset:0;z-index:9600;background:#f1f5f9;display:none;flex-direction:column;font-family:system-ui,Segoe UI,Arial,sans-serif;color:#0f172a;}",
    "#adsOv *{box-sizing:border-box;}",
    "#adsOv button{width:auto;margin-top:0;padding:5px 12px;font-size:13px;line-height:1.25;border-radius:8px;border:1px solid #cbd5e1;background:#fff;color:#0f172a;cursor:pointer;}",
    "#adsOv input,#adsOv select{width:auto;margin-top:0;font:inherit;font-size:14px;padding:4px 6px;border:1px solid #cbd5e1;border-radius:7px;background:#fff;}",
    "#adsOv .ads-top{display:flex;align-items:center;gap:8px;padding:8px 12px;background:#4c1d95;color:#fff;flex-wrap:wrap;}",
    "#adsOv .ads-top .tit{font-weight:800;font-size:17px;margin-right:6px;}",
    "#adsOv .ads-top button.tab{background:rgba(255,255,255,.12);color:#fff;border-color:rgba(255,255,255,.3);}",
    "#adsOv .ads-top button.tab.on{background:#fff;color:#4c1d95;font-weight:800;}",
    "#adsOv .ads-top .sp{flex:1;}",
    "#adsOv .ads-bar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;padding:7px 12px;background:#fff;border-bottom:1px solid #e2e8f0;font-size:13px;}",
    "#adsOv .ads-bar .chip{padding:3px 10px;border-radius:12px;border:1px solid #cbd5e1;background:#f8fafc;cursor:pointer;}",
    "#adsOv .ads-bar .chip.on{background:#4c1d95;color:#fff;border-color:#4c1d95;font-weight:700;}",
    "#adsOv .ads-body{flex:1;overflow:auto;padding:10px 12px;}",
    "#adsOv table{border-collapse:collapse;margin:0 auto;font-size:13px;background:#fff;}",
    "#adsOv th{background:#ede9fe;color:#3b0764;font-size:11.5px;padding:4px 6px;text-align:center;line-height:1.15;position:sticky;top:0;z-index:1;}",
    "#adsOv td{padding:3px 6px;text-align:center;border-top:1px solid #eef2f7;white-space:nowrap;}",
    "#adsOv td.desc{max-width:200px;overflow:hidden;text-overflow:ellipsis;}",
    "#adsOv tr.t{cursor:pointer;}",
    "#adsOv tr.t:hover{background:#faf5ff;}",
    "#adsOv tr.al td.pct{color:#b91c1c;font-weight:800;}",
    "#adsOv tr.sub td{background:#fafafa;font-size:12px;color:#334155;}",
    "#adsOv .neg{color:#b91c1c;font-weight:800;}",
    "#adsOv .pos{color:#15803d;}",
    "#adsOv .bar{display:inline-block;width:70px;height:7px;border-radius:4px;background:#e2e8f0;vertical-align:middle;overflow:hidden;}",
    "#adsOv .bar i{display:block;height:100%;background:#16a34a;}",
    "#adsOv .bar i.r{background:#dc2626;}",
    "#adsOv .msg{text-align:center;padding:30px;color:#64748b;}",
    "#adsOv .err{text-align:center;padding:20px;color:#b91c1c;font-weight:700;}",
    "#adsOv .res{text-align:center;font-size:13px;color:#334155;margin:0 0 8px;}",
    "#adsOv .tp{font-size:11px;color:#64748b;}",
    // v27.29: Fecha · Pedida · Recibida de la última OC se leen juntas: un recuadro las encierra
    "#adsOv tr.sub th{position:static;}",
    "#adsOv .ads-body > table > thead{position:sticky;top:0;z-index:2;} #adsOv .ads-body > table > thead th{position:static;}",
    "#adsOv .ads-body > table .ug,#adsOv .ads-body > table .u1,#adsOv .ads-body > table .u2,#adsOv .ads-body > table .u3{background:#f5f3ff;}",
    "#adsOv .ads-body > table .ug{border:2px solid #7c3aed;border-bottom:0;} #adsOv .ads-body > table .u1{border-left:2px solid #7c3aed;} #adsOv .ads-body > table .u3{border-right:2px solid #7c3aed;}",
    "#adsOv .ads-body > table tbody tr:last-child .u1,#adsOv .ads-body > table tbody tr:last-child .u2,#adsOv .ads-body > table tbody tr:last-child .u3{border-bottom:2px solid #7c3aed;}",
    "#adsOv tr.sub .ug,#adsOv tr.sub .u1,#adsOv tr.sub .u2,#adsOv tr.sub .u3{background:#f5f3ff;}",
    "#adsOv tr.sub .ug{border:2px solid #7c3aed;border-bottom:0;}",
    "#adsOv tr.sub .u1{border-left:2px solid #7c3aed;}",
    "#adsOv tr.sub .u3{border-right:2px solid #7c3aed;}",
    "#adsOv tr.sub tbody tr:last-child .u1,#adsOv tr.sub tbody tr:last-child .u2,#adsOv tr.sub tbody tr:last-child .u3{border-bottom:2px solid #7c3aed;}"
  ].join("\n");
  document.head.appendChild(st);
}

function openAds() {
  _adsCss();
  var ov = document.getElementById("adsOv");
  if (!ov) { ov = document.createElement("div"); ov.id = "adsOv"; document.body.appendChild(ov); }
  ov.style.display = "flex";
  _adsRpc("gv_ads_config").then(function (r) {
    var c = r && r.data;
    if (c) { _ads.cfg = c; _ads.n = 4;   // v27.75 (Luis): el rango abre siempre en 4
      _ads.inc = c.incluir_actual == null ? true : !!c.incluir_actual; _ads.umbral = Number(c.umbral) || 0.5; }
    _ads.inc = true;
    _adsRender(); _adsCargarTall(); _adsCargarStock();
  });
  _adsRpc("gv_ads_oc_fechas", { p_n: 12 }).then(function (r) { if (r && Array.isArray(r.data)) { _ads.fechas = r.data; _adsRender(); } });
  _adsRender();
}
function adsClose() { var ov = document.getElementById("adsOv"); if (ov) ov.style.display = "none"; try { adsLoadBadge(); } catch (_e) {} }
function adsTab(t) { _ads.tab = t; _adsRender(); }

function _adsCargarTall() {
  _ads.tall = null; _ads.tallErr = ""; _adsRender();
  _adsRpc("gv_ads_talleristas", { p_n: _ads.n, p_incluir_actual: true }).then(function (r) {
    if (r.error || !Array.isArray(r.data)) _ads.tallErr = "No se pudieron leer las OC: " + ((r.error && r.error.message) || "sin respuesta");
    else if (!r.data.length) _ads.tallErr = "La lectura volvió vacía: no hay OC en el rango (o no hay sesión).";
    else _ads.tall = r.data;
    _adsRender();
  });
}
function _adsCargarStock() {
  _ads.stock = null; _ads.stockErr = "";
  _adsRpc("gv_ads_stock3").then(function (r) {
    if (r.error || !Array.isArray(r.data)) _ads.stockErr = "No se pudo leer el stock: " + ((r.error && r.error.message) || "sin respuesta");
    else if (!r.data.length) _ads.stockErr = "La lectura del stock volvió vacía (no se dibuja como «sin quiebres»).";
    else _ads.stock = r.data;
    _adsRender();
  });
}

function adsSetN(v) { _ads.n = Math.max(1, Math.min(12, parseInt(v, 10) || 4)); _adsCargarTall(); }
function adsSetUmbral(v) { var n = parseFloat(String(v).replace(",", ".")); if (n > 0 && n <= 100) { _ads.umbral = n / 100; _adsRender(); } }
function adsGuardarCfg() {
  _adsRpc("gv_ads_config_guardar", { p_umbral: _ads.umbral, p_n: _ads.n, p_incluir: true }).then(function (r) {
    if (r.error) { alert("No se guardó: " + (r.error.message || r.error)); return; }
    _ads.cfg = r.data; alert("Guardado: el badge usa las últimas " + _ads.n + " OC y " + Math.round(_ads.umbral * 100) + " %.");
    try { adsLoadBadge(); } catch (_e) {}
  });
}
function adsToggle(k) { _ads.abiertos[k] = !_ads.abiertos[k]; _adsRender(); }
function adsHoriz(h) { if (h) { _ads.horiz = h; _ads.todos = false; } else _ads.todos = true; _adsRender(); }
function adsBuscar(v) { _ads.q = String(v || "").trim().toUpperCase(); _adsRender(); var i = document.getElementById("adsQ"); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } }

// v27.73 (Luis): el rango va de 1 a 12 y cada opción dice la fecha de la OC más vieja que entra ("1 - 07.10.26").
function _adsOpcRango(n) {
  var f = (_ads.fechas || []).filter(function (x) { return Number(x.n) === n; })[0];
  if (!f || !f.fecha) return String(n) + (_ads.fechas ? " - sin OC" : "");
  var p = String(f.fecha).slice(0, 10).split("-");
  return n + " - " + p[2] + "." + p[1] + "." + p[0].slice(2);
}
function _adsBar(p, al) { var w = Math.max(0, Math.min(1, p || 0)) * 100; return '<span class="bar"><i class="' + (al ? "r" : "") + '" style="width:' + w.toFixed(0) + '%"></i></span>'; }

function _adsHtmlTall() {
  var h = '<div class="ads-bar">Rango: últimas <select onchange="adsSetN(this.value)">';
  for (var n = 1; n <= 12; n++) h += '<option value="' + n + '"' + (n === _ads.n ? " selected" : "") + ">" + _adsOpcRango(n) + "</option>";
  h += '</select> OC' +
    ' · Alerta debajo de <input type="number" min="1" max="100" style="width:60px" value="' + Math.round(_ads.umbral * 100) + '" onchange="adsSetUmbral(this.value)"> %' +
    ' <button onclick="adsGuardarCfg()" title="Guarda rango y umbral para el badge del panel (vale para todos)">Guardar para el badge</button>' +
    ' <button class="xl" onclick="adsExcelTall()">Descargar Excel</button></div>';
  h += '<div class="ads-body">';
  if (_ads.tallErr) return h + '<div class="err">' + _adsEsc(_ads.tallErr) + "</div></div>";
  if (!_ads.tall) return h + '<div class="msg">Leyendo OC…</div></div>';
  var g = adsAgruparTalleristas(_ads.tall, _ads.umbral);
  var nAl = g.filter(function (t) { return t.alerta; }).length;
  var d0 = null, d1 = null; _ads.tall.forEach(function (r) { if (!d0 || r.desde < d0) d0 = r.desde; if (!d1 || r.hasta > d1) d1 = r.hasta; });
  h += '<div class="res">OC del ' + _adsFecha(d0) + " al " + _adsFecha(d1) + " · <b" + (nAl ? ' class="neg"' : "") + ">" + nAl + "</b> de " + g.length +
    " talleristas debajo del " + Math.round(_ads.umbral * 100) + " % · tocá uno para ver sus artículos</div>";
  h += '<table><thead><tr><th>Tallerista</th><th>Art.</th><th>Pedido<br>(cajas)</th><th>Entregado<br>(cajas)</th><th>%</th><th></th></tr></thead><tbody>';
  g.forEach(function (t) {
    h += '<tr class="t' + (t.alerta ? " al" : "") + '" onclick="adsToggle(decodeURIComponent(\'' + encodeURIComponent(t.pkey).replace(/'/g, "%27") + '\'))"><td><b>' + (_ads.abiertos[t.pkey] ? "▾ " : "▸ ") + _adsEsc(t.proveedor) + "</b></td><td>" + t.arts.length +
      "</td><td>" + _adsN(t.pedido) + "</td><td>" + _adsN(t.entregado) + '</td><td class="pct">' + _adsPct(t.pct) + "</td><td>" + _adsBar(t.pct, t.alerta) + "</td></tr>";
    if (_ads.abiertos[t.pkey]) {
      h += '<tr class="sub"><td colspan="6"><table style="margin:4px auto"><thead><tr><th rowspan="2">Cód.</th><th rowspan="2">Descripción</th><th rowspan="2" title="Cuántas OC del rango incluyen este artículo">OC<br>evaluadas</th><th rowspan="2">Pedido</th><th rowspan="2" title="Cajas que recibió Virgilio de este proveedor en el período, hasta lo pedido">Recib.<br>Virgilio</th><th rowspan="2">%</th><th colspan="3" class="ug" title="Pedida y recibida de la última OC del artículo">Última OC</th></tr><tr><th class="u1">Fecha</th><th class="u2">Pedida</th><th class="u3">Recibida</th></tr></thead><tbody>';
      t.arts.forEach(function (a) {
        var al = a.pct != null && Number(a.pct) < _ads.umbral;
        h += "<tr><td><b>" + _adsEsc(a.codigo) + '</b></td><td class="desc" title="' + _adsEsc(a.descripcion) + '">' + _adsEsc(a.descripcion) + "</td><td>" + a.ocs +
          "</td><td>" + _adsN(a.pedido) + "</td><td>" + _adsN(a.entregado) + '</td><td class="' + (al ? "neg" : "") + '">' + _adsPct(a.pct) +
          '</td><td class="u1">' + _adsFecha(a.ult_fecha) + '</td><td class="u2">' + _adsN(a.ult_cant) + '</td><td class="u3">' + _adsN(a.ult_rec) + "</td></tr>";
      });
      h += "</tbody></table></td></tr>";
    }
  });
  return h + "</tbody></table></div>";
}

/* % que viene entregando cada tallerista en ese código (rango de la pestaña 1). */
function _adsPctCod(cod) {
  if (!_ads.tall) return null;
  return _ads.tall.filter(function (r) { return String(r.codigo).toUpperCase() === String(cod).toUpperCase(); });
}
/* Filas de la pestaña Stock en quiebre al horizonte elegido. Puro: lo prueba el test. */
function adsFiltrarStock(rows, horiz, q) {
  var campo = "saldo" + horiz;
  return (rows || []).filter(function (r) {
    if (horiz && !(Number(r[campo]) < 0)) return false;
    if (q && (String(r.cod) + " " + String(r.descripcion || "")).toUpperCase().indexOf(q) < 0) return false;
    return true;
  }).sort(function (a, b) {
    return (Number(a.saldo10) - Number(b.saldo10)) || (Number(a.saldo20) - Number(b.saldo20)) || (Number(a.saldo30) - Number(b.saldo30));
  });
}

function _adsHtmlStock() {
  var rows = _ads.stock || [];
  var H = _ads.horiz || 10, ver = _ads.todos ? 0 : H;   // v27.30: TODO va al horizonte elegido
  var n10 = rows.filter(function (r) { return Number(r.saldo10) < 0; }).length,
      n20 = rows.filter(function (r) { return Number(r.saldo20) < 0; }).length,
      n30 = rows.filter(function (r) { return Number(r.saldo30) < 0; }).length;
  var h = '<div class="ads-bar">Quiebre a: ' +
    [[10, n10], [20, n20], [30, n30], [0, rows.length]].map(function (x) {
      var on = x[0] ? (!_ads.todos && H === x[0]) : !!_ads.todos;
      return '<span class="chip' + (on ? " on" : "") + '" onclick="adsHoriz(' + x[0] + ')">' + (x[0] ? x[0] + " días · " + x[1] : "todos · " + x[1]) + "</span>";
    }).join(" ") +
    ' · <input id="adsQ" placeholder="Buscar código" style="width:130px" value="' + _adsEsc(_ads.q) + '" oninput="adsBuscar(this.value)">' +
    ' · Excel: ' + [10, 20, 30].map(function (d) { return '<button class="xl" onclick="adsExcelStock(' + d + ')">' + d + ' días</button>'; }).join(" ") + '</div>';
  h += '<div class="ads-body">';
  if (_ads.stockErr) return h + '<div class="err">' + _adsEsc(_ads.stockErr) + "</div></div>";
  if (!_ads.stock) return h + '<div class="msg">Leyendo stock…</div></div>';
  var f = adsFiltrarStock(rows, ver, _ads.q);
  h += '<div class="res">Todo a ' + H + ' días · sólo artículos con tallerista · disponible = góndola + racks + a guardar + excedente · comprometido = NP programadas sin pickear con entrega hasta ese día · en cajas</div>';
  h += '<table><thead><tr><th rowspan="2">Cód.</th><th rowspan="2">Descripción</th><th rowspan="2">Stk</th><th rowspan="2">Comprom.<br>' + H + ' d</th><th rowspan="2" title="Est. Madre del mes × ' + H + '/30">Est. Madre<br>' + H + ' d</th>' +
    '<th rowspan="2">Saldo<br>' + H + ' d</th>' +
    '<th colspan="6" class="ug" title="Pedido y recibido de las últimas ' + _ads.n + ' OC (el rango de Entregas talleristas), sumando todos los talleristas · recibido = lo que recibió Virgilio, hasta lo pedido">Período (' + _ads.n + ' OC)</th></tr>' +
    '<tr><th class="u1">Fecha<br>últ. OC</th><th class="u2">Pedido<br>período</th><th class="u2">Recibido<br>período</th><th class="u2">%</th>' +
    '<th class="u2" title="Lo que se estima que entreguen en ' + H + ' días: por tallerista, su ritmo del período (recibido ÷ días desde su 1.ª OC del rango) × ' + H + ', hasta lo que le falta entregar">Entrega<br>est. ' + H + ' d</th>' +
    '<th class="u3" title="Tallerista al que le corresponde; si son varios, la parte de cada uno en lo pedido del período">Proporción</th></tr></thead><tbody>';
  if (!f.length) h += '<tr><td colspan="12" class="msg">Ningún código en quiebre a ' + H + " días.</td></tr>";
  f.forEach(function (r) {
    var c = _adsStockCalc(r, H), disp = c.disp, proy = c.proy, comp = c.comp, em = c.em, saldo = c.saldo;
    var dist = c.dist.length ? c.dist.map(_adsEsc).join("<br>") : "—";
    h += "<tr><td><b>" + _adsEsc(r.cod) + '</b></td><td class="desc" title="' + _adsEsc(r.descripcion) + '">' + _adsEsc(r.descripcion) +
      '</td><td title="Góndola ' + _adsN(r.terminado) + " · racks " + _adsN(r.racks) + " · a guardar " + _adsN(r.a_guardar) + " · excedente " + _adsN(r.excedente) + '">' + _adsN(disp) +
      "</td><td>" + _adsN(comp) + '</td><td title="' + _adsN(proy) + ' por mes">' + _adsN(Math.round(em)) +
      '</td><td class="' + (saldo < 0 ? "neg" : "pos") + '">' + _adsN(saldo) + "</td>";
    // v27.78 (Luis): el recuadro es del PERÍODO (las N OC del rango), no de la última OC; la fecha sí es la de la última OC
    var fUlt = c.fechaUlt ? _adsFecha(c.fechaUlt) : '<span class="neg">sin OC</span>';
    if (c.pedP == null) h += '<td class="u1">' + fUlt + '</td><td colspan="4" class="u2">' + (_ads.tall ? "sin OC en el período" : "…") + "</td>";
    else h += '<td class="u1">' + fUlt + '</td><td class="u2">' + _adsN(c.pedP) + '</td><td class="u2">' + _adsN(c.recP) +
      '</td><td class="u2' + (c.pctP != null && c.pctP < _ads.umbral ? " neg" : "") + '">' + _adsPct(c.pctP) +
      '</td><td class="u2" title="' + _adsEsc((c.estDist.length ? c.estDist : c.estDet).join("\n")) + '"><b>' + _adsN(c.estH) + "</b></td>";   // v27.85 (Luis): el reparto por tallerista va en el tooltip
    h += '<td class="u3">' + dist + "</td></tr>";
  });
  return h + "</tbody></table></div>";
}

/* Cuenta de una fila de la pestaña Stock al horizonte H. La usan la pantalla y el Excel (una sola cuenta). */
function _adsStockCalc(r, H) {
  var disp = Number(r.disponible) || 0, proy = Number(r.proy_mes) || 0, comp = Number(r["comp" + H]) || 0;
  var pc = _adsPctCod(r.cod) || [];
  // v27.33 (Luis): Dist = a qué tallerista le corresponde; con varios, la parte de cada uno en lo pedido del período.
  // Lo que entregó cada uno está en la pestaña Entregas talleristas.
  var totPed = pc.reduce(function (s, x) { return s + (Number(x.pedido) || 0); }, 0);
  var dist = pc.length > 1 ? pc.map(function (x) { return x.proveedor + " " + (totPed > 0 ? _adsPct((Number(x.pedido) || 0) / totPed) : "—") + " (" + _adsN(x.pedido) + ")"; })   // v27.75: con las cajas
           : pc.length ? [pc[0].proveedor + " (" + _adsN(pc[0].pedido) + ")"] :   // v27.76 D1: uno solo, también con las cajas
           (r.oc_prov ? [r.oc_prov] : []);
  // v27.78: pedido y recibido del período = suma de todos los talleristas del código en las N OC del rango
  var recP = pc.reduce(function (s, x) { return s + (Number(x.entregado) || 0); }, 0);
  var fechaUlt = r.oc_fecha || pc.reduce(function (m, x) { return x.ult_fecha && (!m || x.ult_fecha > m) ? x.ult_fecha : m; }, null) || null;
  // v27.81 (Luis): entrega estimada a H días, proporcional a cómo viene entregando cada tallerista:
  // ritmo = recibido ÷ días desde su 1.ª OC del período; estimado = ritmo × H, topado en lo que le falta.
  var hoy = Date.now(), estH = 0, estDet = [], estArr = [];
  pc.forEach(function (x) {
    var ped = Number(x.pedido) || 0, ent = Number(x.entregado) || 0, falta = Math.max(0, ped - ent);
    var t0 = x.desde ? Date.parse(String(x.desde).slice(0, 10) + "T12:00:00-03:00") : NaN;
    var dias = isFinite(t0) ? Math.max(1, (hoy - t0) / 864e5) : null;
    var e = dias ? Math.min(falta, Math.round(ent / dias * H)) : 0;
    estH += e; estDet.push(x.proveedor + ": " + e + " (faltan " + falta + ")"); estArr.push({ p: x.proveedor, e: e });
  });
  // v27.82 (Luis): la entrega estimada discriminada por tallerista, con su parte de lo estimado
  var estDist = estArr.length > 1 ? estArr.map(function (y) { return y.p + " " + (estH > 0 ? _adsPct(y.e / estH) : "—") + " (" + _adsN(y.e) + ")"; })
              : estArr.length ? [estArr[0].p + " (" + _adsN(estArr[0].e) + ")"] : [];
  return { disp: disp, proy: proy, comp: comp, em: proy * H / 30, saldo: Number(r["saldo" + H]), estH: pc.length ? estH : null, estDet: estDet, estDist: estDist,
           pedP: pc.length ? totPed : null, recP: pc.length ? recP : null, pctP: pc.length && totPed > 0 ? recP / totPed : null,
           fechaUlt: fechaUlt, dist: dist };
}

/* v27.34 (Luis): Excel de cada pestaña — talleristas, y stock uno por rango (10/20/30).
   v27.40 (Luis): el formato lo dio Luis con su Excel («ADS_talleristas_4OC», 06/10) y la regla es
   OPTIMIZACIÓN HORIZONTAL: anchos fijos chicos (los suyos), rótulo en 2-3 renglones (fila 1 de alto 45,
   centrado y con ajuste), datos centrados salvo tallerista / descripción / dist (a la izquierda), Arial 10,
   fila 1 congelada, zoom 130 y al imprimir entra a lo ancho de la hoja. */
function _adsXlsxFormato(XLSX, wb, cfg) {
  var u8 = XLSX.write(wb, { type: "array", bookType: "xlsx" });
  var cfb = XLSX.CFB.read(new Uint8Array(u8), { type: "array" });
  var dec = new TextDecoder(), enc = new TextEncoder();
  var iSt = cfb.FullPaths.findIndex(function (p) { return /\/xl\/styles\.xml$/.test(p); });
  if (iSt < 0) throw new Error("xlsx sin styles.xml");
  var st = dec.decode(new Uint8Array(cfb.FileIndex[iSt].content));
  // v27.90 (Luis): la fuente 0 (estilo Normal) queda en Arial 10 — de ella sale la UNIDAD del ancho de columna;
  // si se le cambia el tamaño, los mismos anchos se ven distintos que en su Excel. El tamaño grande va en la fuente 1.
  var F = cfg.fuente ? 1 : 0, W = cfg.wrap ? ' wrapText="1"' : '';
  st = st.replace(/<fonts[\s\S]*?<\/fonts>/, '<fonts count="2"><font><sz val="10"/><name val="Arial"/><family val="2"/></font><font><sz val="' + (cfg.fuente || 10) + '"/><name val="Arial"/><family val="2"/></font></fonts>')
         .replace(/<cellXfs[\s\S]*?<\/cellXfs>/, '<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="' + (cfg.bordeRot ? 1 : 0) + '" xfId="0" applyFont="1"' + (cfg.bordeRot ? ' applyBorder="1"' : '') + ' applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"' + W + '/></xf>'
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="0" xfId="0" applyFont="1"' + (W ? ' applyAlignment="1"><alignment' + W + '/></xf>' : '/>')
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>');
  // v27.91 (Luis): el rótulo lleva el borde de abajo grueso de su Excel
  if (cfg.bordeRot) st = st.replace(/<borders[\s\S]*?<\/borders>/, '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="medium"><color indexed="64"/></bottom><diagonal/></border></borders>');
  cfb.FileIndex[iSt].content = enc.encode(st);
  var izq = {}; (cfg.izq || []).forEach(function (i) { izq[i] = 3; }); (cfg.izqSin || []).forEach(function (i) { izq[i] = 4; });
  var colN = function (L) { var n = 0; for (var k = 0; k < L.length; k++) n = n * 26 + (L.charCodeAt(k) - 64); return n - 1; };
  var cols = '<cols>' + cfg.anchos.map(function (w, i) { return '<col min="' + (i + 1) + '" max="' + (i + 1) + '" width="' + w + '" customWidth="1"/>'; }).join("") + '</cols>';
  cfb.FullPaths.forEach(function (p, i) {
    if (!/\/xl\/worksheets\/sheet\d+\.xml$/.test(p)) return;
    var x = dec.decode(new Uint8Array(cfb.FileIndex[i].content));
    x = x.replace(/<cols>[\s\S]*?<\/cols>/, "");
    x = x.replace(/<sheetData/, cols + "<sheetData");
    x = x.replace(/<c r="([A-Z]+)(\d+)"( s="\d+")?/g, function (_m, L, r) {
      if (r === "1") return '<c r="' + L + r + '" s="1"';
      return '<c r="' + L + r + '" s="' + (izq[colN(L)] || 2) + '"';
    });
    if (cfg.altos) x = x.replace(/<row r="(\d+)"([^>]*)>/g, function (m, r, at) {
      var h = cfg.altos[Number(r) - 1]; if (!h || r === "1") return m;
      return '<row r="' + r + '"' + at.replace(/ ht="[^"]*"| customHeight="[^"]*"/g, "") + ' ht="' + h + '" customHeight="1">';
    });
    x = x.replace(/<row r="1"([^>]*)>/, function (_m, at) { return '<row r="1"' + at.replace(/ ht="[^"]*"| customHeight="[^"]*"/g, "") + ' ht="' + (cfg.altoRot || 45) + '" customHeight="1"' + (cfg.bordeRot ? ' thickBot="1"' : '') + '>'; });
    x = x.replace(/<sheetViews>[\s\S]*?<\/sheetViews>/, "")
         .replace(/<dimension[^>]*\/>/, function (d) { return d + '<sheetViews><sheetView zoomScale="130" zoomScaleNormal="130" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr baseColWidth="10" defaultRowHeight="12.75"/>'; });
    x = x.replace(/<sheetFormatPr[^>]*\/>(?=[\s\S]*<sheetFormatPr)/, "");
    if (!/<sheetPr/.test(x)) x = x.replace(/(<worksheet[^>]*>)/, '$1<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
    x = x.replace(/<pageMargins[^>]*\/>/, "");
    x = x.replace(/<\/sheetData>/, '</sheetData><pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/><pageSetup paperSize="9"' + (cfg.escala ? ' scale="' + cfg.escala + '"' : '') + ' orientation="portrait" fitToWidth="1" fitToHeight="0"/>');
    cfb.FileIndex[i].content = enc.encode(x);
  });
  return XLSX.CFB.write(cfb, { fileType: "zip", type: "array" });
}
function _adsXlsx(aoa, hoja, nombre, cfg) {
  if (typeof pppLoadXlsx !== "function") { alert("No pude cargar el generador de Excel."); return Promise.resolve(); }
  return pppLoadXlsx().then(function (XLSX) {
    var ws = XLSX.utils.aoa_to_sheet(aoa);
    var wb = XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb, ws, hoja);
    var bytes = _adsXlsxFormato(XLSX, wb, cfg);
    var d = new Date(), p2 = function (n) { return String(n).padStart(2, "0"); };
    var fn = nombre + "_" + d.getFullYear() + p2(d.getMonth() + 1) + p2(d.getDate()) + ".xlsx";
    if (typeof gvXlsxBajar === "function") gvXlsxBajar(bytes, fn);
    else { var a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([bytes])); a.download = fn; document.body.appendChild(a); a.click(); a.remove(); }
  }).catch(function (e) { alert("No se pudo armar el Excel: " + (e && e.message || e)); });
}
/* ancho de una columna de texto según su dato (Arial 10 ≈ 0,9 de un carácter estándar), con tope */
function _adsAnchoTexto(aoa, i, min, max) {
  var w = min; aoa.slice(1).forEach(function (f) { var n = String(f[i] == null ? "" : f[i]).length * 0.9 + 1; if (n > w) w = n; });
  return Math.round(Math.min(w, max) * 100) / 100;
}
function _adsNum(v) { var n = Number(v); return v == null || v === "" || !isFinite(n) ? "" : n; }
function _adsPctNum(x) { return x == null || !isFinite(x) ? "" : Math.round(x * 100); }
function adsExcelTall() {
  if (!_ads.tall) { alert("Todavía se están leyendo las OC."); return; }
  var g = adsAgruparTalleristas(_ads.tall, _ads.umbral);
  var aoa = [["Tallerista", "Cód.", "Descripción", "OC evaluadas", "Pedido", "Recibio Virgilio", "%", "Fecha última OC", "Pedido última OC", "Recibido última OC"]];
  g.forEach(function (t) {
    t.arts.forEach(function (a) {
      aoa.push([t.proveedor, String(a.codigo), a.descripcion || "", _adsNum(a.ocs), _adsNum(a.pedido), _adsNum(a.entregado),
        (a.pct == null || !isFinite(a.pct) ? "" : Math.round(a.pct * 100) + "%"), a.ult_fecha ? _adsFecha(a.ult_fecha) : "", _adsNum(a.ult_cant), _adsNum(a.ult_rec)]);
    });
  });
  return _adsXlsx(aoa, "Talleristas", "ADS_talleristas_" + _ads.n + "OC",
    // v27.88 (Luis, 07/10): formato de su Excel «ADS_talleristas_4OC_20261007»: Arial 14, rótulo alto 72, filas de 18, sus anchos
    { anchos: [12.7109375, 12.42578125, 23, 7.42578125, 7.5703125, 7.5703125, 8.42578125, 8.28515625, 7.5703125, 8.28515625], izq: [0, 2], fuente: 14, altoRot: 72, altos: aoa.map(function (_f, i) { return i ? 18 : null; }) });
}
function adsExcelStock(H) {
  if (!_ads.stock) { alert("Todavía se está leyendo el stock."); return; }
  var f = adsFiltrarStock(_ads.stock, H, "");
  // v27.87 (Luis, 07/10): el formato es el de su Excel «ADS_stock_10d_20261007_1»: Arial 14, rótulo de alto 72,
  // todo con ajuste de texto, sus anchos y sus rótulos; el alto de cada fila según el texto más largo.
  // v27.91 (Luis, 07/10, «ADS_stock_10d_20261007_3»): optimización horizontal — cada tallerista en su sub-fila
  // (salto de línea dentro de la celda), descripción sin ajuste, rótulo con borde de abajo, escala 74.
  var aoa = [["Cód", "Descripción", "Stk", "Comprom " + H + " d", "E M " + H + " d", "Saldo " + H + " d",
              "Fecha últ. OC", "Ped período", "Rec período", "% período", "Entr est " + H + " d", "Entr. est. x tall.", "Proporción"]];
  f.forEach(function (r) {
    var c = _adsStockCalc(r, H);
    aoa.push([String(r.cod), r.descripcion || "", c.disp, c.comp, Math.round(c.em), _adsNum(c.saldo),
      c.fechaUlt ? _adsFecha(c.fechaUlt) : "sin OC", _adsNum(c.pedP), _adsNum(c.recP), _adsPctNum(c.pctP), _adsNum(c.estH), c.estDist.join("\n"), c.dist.join("\n")]);
  });
  return _adsXlsx(aoa, "Quiebre " + H + " d", "ADS_stock_" + H + "d",
    { anchos: ADS_XLS_STOCK_ANCHOS, izq: [11, 12], izqSin: [1], fuente: 14, altoRot: 72, wrap: true, bordeRot: true, escala: 74, altos: _adsAltos(aoa, ADS_XLS_STOCK_ANCHOS, [11, 12]) });
}
var ADS_XLS_STOCK_ANCHOS = [7.7109375, 14.85546875, 6, 7.140625, 6.28515625, 6, 5.5703125, 8.7109375, 6.28515625, 5.28515625, 6.28515625, 23.28515625, 27.42578125];   // los de su Excel, exactos
/* alto de cada fila (Arial 14 con ajuste): renglones del texto más largo × 18 pt; ~1,35 de ancho por carácter */
function _adsAltos(aoa, anchos, cols) {
  return aoa.map(function (f, i) {
    if (!i) return null;
    var n = 1; cols.forEach(function (c) {
      var cpl = Math.max(1, Math.floor(anchos[c] / 1.35)), k = 0;   // cada sub-fila (\n) cuenta sus renglones
      String(f[c] == null ? "" : f[c]).split("\n").forEach(function (t) { if (t) k += Math.ceil(t.length / cpl); });
      n = Math.max(n, k);
    });
    return n * 18;
  });
}

function _adsRender() {
  var ov = document.getElementById("adsOv"); if (!ov || ov.style.display === "none") return;
  var h = '<div class="ads-top"><span class="tit">ADS · Alertas Damián Stock</span>' +
    '<button class="tab' + (_ads.tab === "tall" ? " on" : "") + '" onclick="adsTab(\'tall\')">Entregas talleristas</button>' +
    '<button class="tab' + (_ads.tab === "stock" ? " on" : "") + '" onclick="adsTab(\'stock\')">Stock</button>' +
    '<span class="sp"></span><button onclick="adsClose()">Cerrar</button></div>';
  h += _ads.tab === "stock" ? _adsHtmlStock() : _adsHtmlTall();
  ov.innerHTML = h;
}

/* Badges del botón del panel (v27.22, Luis D3): a la IZQUIERDA el violeta = talleristas a revisar
   (gv_ads_badge, con la config guardada); a la DERECHA el semáforo de quiebres (gv_ads_badge_stock):
   rojo = quiebre a 10 días · naranja = los que recién quiebran a 20 · amarillo = los que recién
   quiebran a 30. Cada artículo cuenta UNA vez, en su color más urgente. Una lectura rota no apaga
   lo que ya se mostraba: no pinta nada. */
function adsSemaforoCuentas(q) {
  var q10 = Number(q && q.q10) || 0, q20 = Number(q && q.q20) || 0, q30 = Number(q && q.q30) || 0;
  return { rojo: q10, naranja: Math.max(0, q20 - q10), amarillo: Math.max(0, q30 - q20) };
}
function adsLoadBadge() {
  var b = document.getElementById("adsBadge");
  if (b) _adsRpc("gv_ads_badge").then(function (r) {
    if (!r || r.error) return;
    var n = Number(r.data);
    if (!(n > 0)) { b.style.display = "none"; return; }
    b.style.display = ""; b.textContent = n;
    b.title = n + " tallerista(s) entregaron menos del umbral de lo pedido en el rango de OC";
  });
  var s = document.getElementById("adsSemaf");
  if (s) _adsRpc("gv_ads_badge_stock").then(function (r) {
    if (!r || r.error || !r.data) return;
    var c = adsSemaforoCuentas(r.data), h = "";
    /* v27.25 (Luis): cada pastilla dice su plazo (10d / 20d / 30d) al lado del número */
    [["rojo", "#dc2626", "#fff", "10d", "a 10 días"], ["naranja", "#ea580c", "#fff", "20d", "recién a 20 días"], ["amarillo", "#facc15", "#422006", "30d", "recién a 30 días"]].forEach(function (x) {
      if (c[x[0]] > 0) h += '<span class="ads-sem" data-n="' + c[x[0]] + '" style="height:18px;line-height:18px;padding:0 5px;border-radius:9px;background:' + x[1] + ';color:' + x[2] + ';font-size:12px;font-weight:800;text-align:center;white-space:nowrap;box-shadow:0 1px 3px rgba(0,0,0,.3);" title="' + c[x[0]] + ' artículo(s) quiebran ' + x[4] + ' (cada artículo cuenta una vez, en su color más urgente)">' + c[x[0]] + '<span style="font-size:9px;font-weight:700;margin-left:3px;opacity:.85;">' + x[3] + "</span></span>";
    });
    s.innerHTML = h; s.style.display = h ? "flex" : "none";
  });
}
