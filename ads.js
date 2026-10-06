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
     saldo N = (góndola + racks + a guardar + excedente) − NP programadas sin pickear con
               entrega hasta hoy + N (las vencidas también) − Est. Madre × N/30
     Negativo = quiebre. Sólo artículos CON TALLERISTA (v27.23: los importados sin tallerista no van).
     Con la última OC del código (cuánto se recibió) y el %
     que viene entregando ese tallerista en ese artículo (rango de la pestaña 1).

   Backend: sql/gv_ads_alertas_damian_v2720.sql + sql/gv_ads_excedente_semaforo_v2722.sql (gv_ads_talleristas, gv_ads_stock2,
   gv_ads_badge, gv_ads_badge_stock, gv_ads_config, gv_ads_config_guardar). Sólo lectura salvo la config.
   ⚠ Una lectura que falla se DICE, no se dibuja como "todo bien" (regla "una
   lectura ROTA no es un CERO"). Vive en su propio archivo (regla v23.98), con ?v=
   atado a APP_VERSION. Candado: tests/ads-alertas.cjs.
   ============================================================================ */

var _ads = { tab: "tall", cfg: null, tall: null, tallErr: "", stock: null, stockErr: "",
             n: 4, inc: false, umbral: 0.5, abiertos: {}, horiz: 10, q: "", cargando: 0 };

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
    "#adsOv .tp{font-size:11px;color:#64748b;}"
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
    if (c) { _ads.cfg = c; _ads.n = Number(c.n_ocs) || 4; _ads.inc = !!c.incluir_actual; _ads.umbral = Number(c.umbral) || 0.5; }
    _adsRender(); _adsCargarTall(); _adsCargarStock();
  });
  _adsRender();
}
function adsClose() { var ov = document.getElementById("adsOv"); if (ov) ov.style.display = "none"; try { adsLoadBadge(); } catch (_e) {} }
function adsTab(t) { _ads.tab = t; _adsRender(); }

function _adsCargarTall() {
  _ads.tall = null; _ads.tallErr = ""; _adsRender();
  _adsRpc("gv_ads_talleristas", { p_n: _ads.n, p_incluir_actual: _ads.inc }).then(function (r) {
    if (r.error || !Array.isArray(r.data)) _ads.tallErr = "No se pudieron leer las OC: " + ((r.error && r.error.message) || "sin respuesta");
    else if (!r.data.length) _ads.tallErr = "La lectura volvió vacía: no hay OC en el rango (o no hay sesión).";
    else _ads.tall = r.data;
    _adsRender();
  });
}
function _adsCargarStock() {
  _ads.stock = null; _ads.stockErr = "";
  _adsRpc("gv_ads_stock2").then(function (r) {
    if (r.error || !Array.isArray(r.data)) _ads.stockErr = "No se pudo leer el stock: " + ((r.error && r.error.message) || "sin respuesta");
    else if (!r.data.length) _ads.stockErr = "La lectura del stock volvió vacía (no se dibuja como «sin quiebres»).";
    else _ads.stock = r.data;
    _adsRender();
  });
}

function adsSetN(v) { _ads.n = Math.max(1, Math.min(52, parseInt(v, 10) || 4)); _adsCargarTall(); }
function adsSetInc(v) { _ads.inc = !!v; _adsCargarTall(); }
function adsSetUmbral(v) { var n = parseFloat(String(v).replace(",", ".")); if (n > 0 && n <= 100) { _ads.umbral = n / 100; _adsRender(); } }
function adsGuardarCfg() {
  _adsRpc("gv_ads_config_guardar", { p_umbral: _ads.umbral, p_n: _ads.n, p_incluir: _ads.inc }).then(function (r) {
    if (r.error) { alert("No se guardó: " + (r.error.message || r.error)); return; }
    _ads.cfg = r.data; alert("Guardado: el badge usa las últimas " + _ads.n + " OC y " + Math.round(_ads.umbral * 100) + " %.");
    try { adsLoadBadge(); } catch (_e) {}
  });
}
function adsToggle(k) { _ads.abiertos[k] = !_ads.abiertos[k]; _adsRender(); }
function adsHoriz(h) { _ads.horiz = h; _adsRender(); }
function adsBuscar(v) { _ads.q = String(v || "").trim().toUpperCase(); _adsRender(); var i = document.getElementById("adsQ"); if (i) { i.focus(); i.setSelectionRange(i.value.length, i.value.length); } }

function _adsBar(p, al) { var w = Math.max(0, Math.min(1, p || 0)) * 100; return '<span class="bar"><i class="' + (al ? "r" : "") + '" style="width:' + w.toFixed(0) + '%"></i></span>'; }

function _adsHtmlTall() {
  var h = '<div class="ads-bar">Rango: últimas <select onchange="adsSetN(this.value)">';
  [2, 3, 4, 5, 6, 8, 10, 12].forEach(function (n) { h += '<option' + (n === _ads.n ? " selected" : "") + ">" + n + "</option>"; });
  h += '</select> OC · <label><input type="checkbox"' + (_ads.inc ? " checked" : "") + ' onchange="adsSetInc(this.checked)"> incluir la OC en curso</label>' +
    ' · Alerta debajo de <input type="number" min="1" max="100" style="width:60px" value="' + Math.round(_ads.umbral * 100) + '" onchange="adsSetUmbral(this.value)"> %' +
    ' <button onclick="adsGuardarCfg()" title="Guarda rango y umbral para el badge del panel (vale para todos)">Guardar para el badge</button></div>';
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
      h += '<tr class="sub"><td colspan="6"><table style="margin:4px auto"><thead><tr><th>Cód.</th><th>Descripción</th><th title="Cuántas OC del rango incluyen este artículo">OC<br>evaluadas</th><th>Pedido</th><th title="Cajas que recibió Virgilio de este proveedor en el período, hasta lo pedido">Recib.<br>Virgilio</th><th>%</th><th>Última<br>OC</th><th>Pedida</th><th>Recibida</th></tr></thead><tbody>';
      t.arts.forEach(function (a) {
        var al = a.pct != null && Number(a.pct) < _ads.umbral;
        h += "<tr><td><b>" + _adsEsc(a.codigo) + '</b></td><td class="desc" title="' + _adsEsc(a.descripcion) + '">' + _adsEsc(a.descripcion) + "</td><td>" + a.ocs +
          "</td><td>" + _adsN(a.pedido) + "</td><td>" + _adsN(a.entregado) + '</td><td class="' + (al ? "neg" : "") + '">' + _adsPct(a.pct) +
          "</td><td>" + _adsFecha(a.ult_fecha) + "</td><td>" + _adsN(a.ult_cant) + "</td><td>" + _adsN(a.ult_rec) + "</td></tr>";
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
  var n10 = rows.filter(function (r) { return Number(r.saldo10) < 0; }).length,
      n20 = rows.filter(function (r) { return Number(r.saldo20) < 0; }).length,
      n30 = rows.filter(function (r) { return Number(r.saldo30) < 0; }).length;
  var h = '<div class="ads-bar">Quiebre a: ' +
    [[10, n10], [20, n20], [30, n30], [0, rows.length]].map(function (x) {
      return '<span class="chip' + (_ads.horiz === x[0] ? " on" : "") + '" onclick="adsHoriz(' + x[0] + ')">' + (x[0] ? x[0] + " días · " + x[1] : "todos · " + x[1]) + "</span>";
    }).join(" ") +
    ' · <input id="adsQ" placeholder="Buscar código" style="width:130px" value="' + _adsEsc(_ads.q) + '" oninput="adsBuscar(this.value)"></div>';
  h += '<div class="ads-body">';
  if (_ads.stockErr) return h + '<div class="err">' + _adsEsc(_ads.stockErr) + "</div></div>";
  if (!_ads.stock) return h + '<div class="msg">Leyendo stock…</div></div>';
  var f = adsFiltrarStock(rows, _ads.horiz, _ads.q);
  h += '<div class="res">Sólo artículos con tallerista · disponible = góndola + racks + a guardar + excedente · comprometido = NP programadas sin pickear con entrega hasta ese día · Est. Madre prorrateada · en cajas</div>';
  h += '<table><thead><tr><th>Cód.</th><th>Descripción</th><th>Disp.</th><th>Est.<br>Madre<br>/mes</th><th>Comprom.<br>10 · 20 · 30 d</th>' +
    '<th>Saldo<br>10 d</th><th>Saldo<br>20 d</th><th>Saldo<br>30 d</th><th>Cubre<br>días</th><th>Última OC<br>fecha · prov.</th><th>OC<br>pedida · recib.</th><th>% entrega<br>tallerista</th></tr></thead><tbody>';
  if (!f.length) h += '<tr><td colspan="12" class="msg">Ningún código en quiebre a ' + _ads.horiz + " días.</td></tr>";
  f.forEach(function (r) {
    var s = function (v) { var n = Number(v); return '<td class="' + (n < 0 ? "neg" : "pos") + '">' + _adsN(n) + "</td>"; };
    var pc = _adsPctCod(r.cod) || [];
    var tp = pc.length ? pc.map(function (x) { var al = x.pct != null && Number(x.pct) < _ads.umbral; return '<span class="' + (al ? "neg" : "") + '">' + _adsEsc(x.proveedor) + " " + _adsPct(x.pct) + "</span>"; }).join("<br>") : "—";
    var ocPct = r.oc_cant ? " (" + _adsPct(Number(r.oc_rec) / Number(r.oc_cant)) + ")" : "";
    h += "<tr><td><b>" + _adsEsc(r.cod) + '</b></td><td class="desc" title="' + _adsEsc(r.descripcion) + '">' + _adsEsc(r.descripcion) +
      '</td><td title="Góndola ' + _adsN(r.terminado) + " · racks " + _adsN(r.racks) + " · a guardar " + _adsN(r.a_guardar) + " · excedente " + _adsN(r.excedente) + '">' + _adsN(r.disponible) +
      "</td><td>" + _adsN(r.proy_mes) + "</td><td>" + _adsN(r.comp10) + " · " + _adsN(r.comp20) + " · " + _adsN(r.comp30) + "</td>" +
      s(r.saldo10) + s(r.saldo20) + s(r.saldo30) + "<td>" + (r.dias_cubre == null ? "—" : _adsN(r.dias_cubre)) + "</td>" +
      "<td>" + (r.oc_fecha ? _adsFecha(r.oc_fecha) + ' · <span class="tp">' + _adsEsc(r.oc_prov) + "</span>" : '<span class="neg">sin OC</span>') + "</td>" +
      "<td>" + (r.oc_fecha ? _adsN(r.oc_cant) + " · " + _adsN(r.oc_rec) + ocPct : "—") + "</td><td>" + tp + "</td></tr>";
  });
  return h + "</tbody></table></div>";
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
