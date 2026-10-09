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
               entrega hasta hoy + N (vencidas también) − E.M. plazo (v28.56: se SUMAN, no el mayor;
               v28.59: E.M. plazo = Est. Madre × días equivalentes de gv_ads_em_dias, con la
               distribución real de lo que tarda un pedido en salir, o fijados por un supervisor)
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
// v28.59 (Luis, 08/10): «No existe 58, sólo 058» (regla v16.23): el código se muestra con el cero adelante.
// stocks_carga_rapida guarda la clave normalizada (norm_cod saca los ceros); esto es sólo cómo se escribe.
// Espejo de cod mostrar de index.html y de public.gv_cod_mostrar().
function _adsCod(c) { var s = String(c == null ? "" : c).toUpperCase().trim(), m = s.match(/^([0-9]+)(.*)$/); return m ? (m[1].length < 3 ? ("000" + m[1]).slice(-3) : m[1]) + m[2] : s; }
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
    "#adsOv button.ads-pct{padding:2px 8px;font-weight:700;}",
    "#adsOv button.ads-pct.on{background:#7c3aed;border-color:#7c3aed;color:#fff;}",
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
    // v28.85 (Luis, 08/10): la letra crece con la pantalla (en 1366 px ~15, en 1920 ~21); todo en em: anchos, rellenos y la descripción
    "#adsOv table{border-collapse:collapse;margin:0 auto;font-size:clamp(14px,1.1vw,26px);background:#fff;}",
    "#adsOv th{background:#ede9fe;color:#3b0764;font-size:.82em;padding:.25em .35em;text-align:center;vertical-align:middle;line-height:1.15;position:sticky;top:0;z-index:1;}",
    "#adsOv td{padding:.15em .35em;text-align:center;vertical-align:middle;border-top:1px solid #eef2f7;white-space:nowrap;}",
    "#adsOv td.desc{max-width:11em;overflow:hidden;text-overflow:ellipsis;}",
    "#adsOv td.tall{line-height:1.2;} #adsOv table.ads-stk td.estp{line-height:1.2;}",
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
    _ads.inc = false;   // v28.95 (Luis): el % es un SNAPSHOT de las OC cerradas, sin la vigente
    _adsRender(); _adsCargarTall(); _adsCargarStock();
  });
  _adsRpc("gv_ads_oc_fechas", { p_n: 13 }).then(function (r) { if (r && Array.isArray(r.data)) { _ads.fechas = r.data; _adsRender(); } });
  _adsRender();
}
function adsClose() { var ov = document.getElementById("adsOv"); if (ov) ov.style.display = "none"; try { adsLoadBadge(); } catch (_e) {} }
function adsTab(t) { _ads.tab = t; _adsRender(); }

function _adsCargarTall() {
  // v29.10: cada cambio de rango invalida las lecturas anteriores (si una vieja llega última, no pisa a la nueva)
  var seq = _ads.seq = (_ads.seq || 0) + 1;
  _ads.tall = null; _ads.tallErr = ""; _ads.tallCerr = null; _adsRender();
  // v28.86: la misma lectura (período CERRADO) alimenta la pestaña 1 y el % para proyectar la OC vigente
  _adsRpc("gv_ads_talleristas", { p_n: _ads.n, p_incluir_actual: false }).then(function (r) {
    if (seq !== _ads.seq) return;
    if (r.error || !Array.isArray(r.data)) _ads.tallErr = "No se pudieron leer las OC: " + ((r.error && r.error.message) || "sin respuesta");
    else if (!r.data.length) _ads.tallErr = "La lectura volvió vacía: no hay OC en el rango (o no hay sesión).";
    else {
      _ads.tall = r.data;
      var m = {}; r.data.forEach(function (x) { m[String(x.proveedor).toUpperCase() + "|" + String(x.codigo).toUpperCase()] = x; });
      _ads.tallCerr = m;
    }
    _adsRender();
  });
  // v28.96 (Luis, 09/10): la pestaña Stock sigue mirando el período CON la OC vigente (su «Últ. OC» es la vigente);
  // y en Entregas talleristas el recuadro de la derecha es la OC VIGENTE, no la última del período cerrado.
  _ads.tallInc = null; _ads.vig = null;
  _adsRpc("gv_ads_talleristas", { p_n: _ads.n, p_incluir_actual: true }).then(function (r) {
    if (seq !== _ads.seq || r.error || !Array.isArray(r.data)) return;
    _ads.tallInc = r.data; if (_ads.stock) _adsRender();
  });
  _adsRpc("gv_ads_talleristas", { p_n: 1, p_incluir_actual: true }).then(function (r) {
    if (seq !== _ads.seq || r.error || !Array.isArray(r.data)) return;
    var m = {}; r.data.forEach(function (x) { m[String(x.pkey || x.proveedor).toUpperCase() + "|" + String(x.codigo).toUpperCase()] = x; });
    _ads.vig = m; _adsRender();
  });
  // v28.86 (Luis, 08/10): el % para PROYECTAR la OC vigente sale del último período CERRADO (sin la OC vigente):
  // con la vigente adentro, lo que ya llegó de ella entraba al % y después se restaba (Garcia 550: 247 × 14 % − 35 = 0).
  // (v29.10: sale de la primera lectura de arriba; antes se pedía dos veces la misma.)
}
/* v28.44 (Luis): la ENTREGA PROY. que se carga a mano en la OC vigente (consultándole al tallerista,
   Ordenes_Compra.gv_entrega_proy) manda sobre la estimación por ritmo. Clave proveedor|código|fecha de la OC.
   Si la lectura falla, queda la estimación por ritmo (no se inventa un 0). */
function _adsCargarEntregaProy() {
  var sb = window.sb; _ads.epOc = {};
  if (!sb || typeof sb.from !== "function") return;
  try {
    var d = new Date(Date.now() - 45 * 864e5).toISOString().slice(0, 10);
    Promise.resolve(sb.from("Ordenes_Compra").select("fecha,proveedor,codigo,gv_entrega_proy").not("gv_entrega_proy", "is", null).gte("fecha", d))
      .then(function (r) {
        if (!r || r.error || !Array.isArray(r.data)) return;
        var m = {};
        r.data.forEach(function (x) { m[_adsEpKey(x.proveedor, x.codigo, x.fecha)] = Number(x.gv_entrega_proy); });
        _ads.epOc = m; if (_ads.stock) _adsRender();
      }).catch(function () {});
  } catch (e) {}
}
// v29.10: el código va SIN ceros adelante de los dos lados — Ordenes_Compra guarda «058» y stock / talleristas «58»
// (norm_cod): sin esto la Entrega proy. cargada en la OC de un código con cero adelante no se encontraba nunca.
function _adsEpKey(prov, cod, fecha) { return String(prov || "").trim().toUpperCase() + "|" + String(cod || "").trim().toUpperCase().replace(/^0+(?=[0-9])/, "") + "|" + String(fecha || "").slice(0, 10); }
function _adsCargarStock() {
  _ads.stock = null; _ads.stockErr = ""; _adsCargarEntregaProy();
  _adsRpc("gv_ads_stock3").then(function (r) {
    if (r.error || !Array.isArray(r.data)) _ads.stockErr = "No se pudo leer el stock: " + ((r.error && r.error.message) || "sin respuesta");
    else if (!r.data.length) _ads.stockErr = "La lectura del stock volvió vacía (no se dibuja como «sin quiebres»).";
    else _ads.stock = r.data;
    _adsRender();
  });
}

// v28.56 (Luis): cuánto tarda un pedido en salir (días). Lo da gv_ads_config: manual o promedio de 2 semanas.
function _adsLead() { var c = (typeof _ads !== "undefined" && _ads.cfg) || {}; var l = Number(c.lead_dias); return isFinite(l) && c.lead_dias != null ? l : 12; }
// v28.59 (Luis, D4): días equivalentes de Est. Madre que caen en un plazo de H días. Los calcula la base
// (gv_ads_em_dias): con la distribución real de las últimas 2 semanas, o max(0, H − días) si se fijaron a mano.
function _adsEmDias(H) {
  var c = (typeof _ads !== "undefined" && _ads.cfg) || {}, e = c.em_dias && Number(c.em_dias[String(H)]);
  return isFinite(e) && c.em_dias && c.em_dias[String(H)] != null ? e : Math.max(0, H - _adsLead());
}
function _adsLeadTxt(x) { return String(Math.round(Number(x) * 10) / 10).replace(".", ","); }
function adsSetLead(v) {
  var t = String(v == null ? "" : v).trim().replace(",", "."), d = t === "" ? null : Number(t);
  if (d != null && !(d >= 0 && d <= 60)) { alert("Días entre 0 y 60 (vacío = automático)."); _adsRender(); return; }
  _adsRpc("gv_ads_lead_guardar", { p_dias: d }).then(function (r) {
    if (r.error) { alert("No se guardó: " + (r.error.message || r.error)); return; }
    _ads.cfg = Object.assign({}, _ads.cfg || {}, r.data || {}); _ads.stock = null; _adsRender(); _adsCargarStock();
    try { adsLoadBadge(); } catch (_e) {}
  });
}
function adsSetN(v) { _ads.n = Math.max(1, Math.min(12, parseInt(v, 10) || 4)); _adsCargarTall(); }
function adsSetUmbral(v) { var n = parseFloat(String(v).replace(",", ".")); if (n > 0 && n <= 100) { _ads.umbral = n / 100; _adsRender(); } }
function adsGuardarCfg() {
  _adsRpc("gv_ads_config_guardar", { p_umbral: _ads.umbral, p_n: _ads.n, p_incluir: false }).then(function (r) {
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
  // v28.95: sin la OC vigente, la n-ésima cerrada es la (n+1)-ésima fecha
  var f = (_ads.fechas || []).filter(function (x) { return Number(x.n) === n + 1; })[0];
  if (!f || !f.fecha) return String(n) + (_ads.fechas ? " - sin OC" : "");
  var p = String(f.fecha).slice(0, 10).split("-");
  return n + " - " + p[2] + "." + p[1] + "." + p[0].slice(2);
}
function _adsBar(p, al) { var w = Math.max(0, Math.min(1, p || 0)) * 100; return '<span class="bar"><i class="' + (al ? "r" : "") + '" style="width:' + w.toFixed(0) + '%"></i></span>'; }

function _adsHtmlTall() {
  var h = '<div class="ads-bar">Rango últimas cerradas <select onchange="adsSetN(this.value)">';
  for (var n = 1; n <= 12; n++) h += '<option value="' + n + '"' + (n === _ads.n ? " selected" : "") + ">" + _adsOpcRango(n) + "</option>";
  h += '</select> OC' +
    ' · Alerta debajo de <input type="number" min="1" max="100" style="width:60px" value="' + Math.round(_ads.umbral * 100) + '" onchange="adsSetUmbral(this.value)"> %' +
    ' <button onclick="adsGuardarCfg()" title="Guarda rango y umbral para el badge del panel (vale para todos)">Guardar para el badge</button>' +
    ' <button class="xl" onclick="adsExcelTall()">Descargar Excel</button></div>';
  h += '<div class="ads-body">';
  if (_ads.tallErr) return h + '<div class="err">' + _adsEsc(_ads.tallErr) + "</div></div>";
  if (!_ads.tall) return h + '<div class="msg">Leyendo OC…</div></div>';
  var g = adsAgruparTalleristas(_ads.tall, _ads.umbral);
  // v28.90 (Luis, 08/10): sin el renglón «OC del … · N de M talleristas debajo del …»
  h += '<table><thead><tr><th>Tallerista</th><th>Art.</th><th>Pedido<br>(cajas)</th><th>Entregado<br>(cajas)</th><th>%</th><th></th></tr></thead><tbody>';
  g.forEach(function (t) {
    h += '<tr class="t' + (t.alerta ? " al" : "") + '" onclick="adsToggle(decodeURIComponent(\'' + encodeURIComponent(t.pkey).replace(/'/g, "%27") + '\'))"><td><b>' + (_ads.abiertos[t.pkey] ? "▾ " : "▸ ") + _adsEsc(t.proveedor) + "</b></td><td>" + t.arts.length +
      "</td><td>" + _adsN(t.pedido) + "</td><td>" + _adsN(t.entregado) + '</td><td class="pct">' + _adsPct(t.pct) + "</td><td>" + _adsBar(t.pct, t.alerta) + "</td></tr>";
    if (_ads.abiertos[t.pkey]) {
      h += '<tr class="sub"><td colspan="6"><table style="margin:4px auto"><thead><tr><th rowspan="2">Cód.</th><th rowspan="2">Descripción</th><th rowspan="2" title="Cuántas OC del rango incluyen este artículo">OC<br>evaluadas</th><th rowspan="2">Pedido</th><th rowspan="2" title="Cajas que recibió Virgilio de este proveedor en el período, hasta lo pedido">Recib.<br>Virgilio</th><th rowspan="2">%</th><th colspan="3" class="ug" title="La OC vigente (la de esta semana): pedida y recibida">OC vigente</th></tr><tr><th class="u1">Fecha</th><th class="u2">Pedida</th><th class="u3">Recibida</th></tr></thead><tbody>';
      t.arts.forEach(function (a) {
        var v = _adsVig(a) || {};
        var al = a.pct != null && Number(a.pct) < _ads.umbral;
        h += "<tr><td><b>" + _adsEsc(_adsCod(a.codigo)) + '</b></td><td class="desc" title="' + _adsEsc(a.descripcion) + '">' + _adsEsc(a.descripcion) + "</td><td>" + a.ocs +
          "</td><td>" + _adsN(a.pedido) + "</td><td>" + _adsN(a.entregado) + '</td><td class="' + (al ? "neg" : "") + '">' + _adsPct(a.pct) +
          '</td><td class="u1">' + _adsFecha(v.ult_fecha) + '</td><td class="u2">' + _adsN(v.ult_cant) + '</td><td class="u3">' + _adsN(v.ult_rec) + "</td></tr>";
      });
      h += "</tbody></table></td></tr>";
    }
  });
  return h + "</tbody></table></div>";
}

/* % que viene entregando cada tallerista en ese código (rango de la pestaña 1). */
function _adsPctCod(cod) {
  var t = _ads.tallInc || null;   // v28.96: con la OC vigente (lo que usaba la pestaña Stock antes de la v28.95)
  if (!t) return null;
  return t.filter(function (r) { return String(r.codigo).toUpperCase() === String(cod).toUpperCase(); });
}
/* Filas de la pestaña Stock en quiebre al horizonte elegido. Puro: lo prueba el test. */
function adsFiltrarStock(rows, horiz, q, hOrden) {
  var campo = "saldo" + horiz;
  // v28.42 (Luis): se ordena por el saldo del lapso ELEGIDO, de mayor déficit a menor (antes siempre por el de 10 d)
  var ko = "saldo" + (hOrden || horiz || 10);
  return (rows || []).filter(function (r) {
    if (horiz && !(Number(r[campo]) < 0)) return false;
    if (q && (String(r.cod) + " " + _adsCod(r.cod) + " " + String(r.descripcion || "")).toUpperCase().indexOf(q) < 0) return false;
    return true;
  }).sort(function (a, b) {
    return (Number(a[ko]) - Number(b[ko])) || (Number(a.saldo10) - Number(b.saldo10)) || (Number(a.saldo20) - Number(b.saldo20)) || (Number(a.saldo30) - Number(b.saldo30));
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
    ' · <span title="Cuánto tarda un pedido desde que entra hasta que sale. Si se escribe a mano, queda guardado.">Tarda en salir: <input id="adsLead" style="width:46px" value="' + _adsLeadTxt(_adsLead()) + '" onchange="adsSetLead(this.value)"> d</span>' +
    ' <button class="ads-pct' + ((_ads.cfg || {}).lead_manual != null ? '' : ' on') + '" onclick="adsSetLead(\'\')" title="Promedio real de las últimas 2 semanas">%</button>' +
    ' · Excel: ' + [10, 20, 30].map(function (d) { return '<button class="xl" onclick="adsExcelStock(' + d + ')">' + d + ' días</button>'; }).join(" ") + '</div>';
  h += '<div class="ads-body">';
  if (_ads.stockErr) return h + '<div class="err">' + _adsEsc(_ads.stockErr) + "</div></div>";
  if (!_ads.stock) return h + '<div class="msg">Leyendo stock…</div></div>';
  var f = adsFiltrarStock(rows, ver, _ads.q, H);
  // v28.90 (Luis, 08/10): sin el renglón explicativo «Todo a N días · …»
  // v28.82 (Luis, 08/10): sin el recuadro «Período»: Últ. OC · Pedido · Recibido · Estim. pend. con el mismo encabezado que el resto
  h += '<table class="ads-stk"><thead><tr><th>Cód.</th><th>Descripción</th><th title="Tallerista de la OC vigente del código">Tallerista</th><th>Stk</th><th>Comp.<br>' + H + 'd</th><th title="Est. Madre del mes × (' + H + ' − ' + _adsLeadTxt(_adsLead()) + ' días que tarda en salir) / 30: los pedidos que entran y salen dentro del plazo">E.M. plazo<br>' + H + 'd</th>' +
    '<th>Saldo<br>' + H + 'd</th><th title="Fecha de la última OC del código">Últ.<br>OC</th>' +
    '<th title="Lo pedido en la última OC, uno por tallerista">Pedido</th><th title="Lo que recibió Virgilio de la última OC, uno por tallerista">Recib.</th>' +
    '<th title="Por tallerista, X/Y de la última OC: X = lo que va a entregar (lo cargado en la OC; con * si la casilla está vacía: la OC × el % que entregó en el período anterior), menos lo ya entregado · Y = lo pedido menos lo ya entregado">Pend.<br>est.</th></tr></thead><tbody>';   // v28.62 (Luis, 08/10): sin Proporción en pantalla (sigue en el Excel)
  if (!f.length) h += '<tr><td colspan="11" class="msg">Ningún código en quiebre a ' + H + " días.</td></tr>";
  f.forEach(function (r) {
    var c = _adsStockCalc(r, H), disp = c.disp, proy = c.proy, comp = c.comp, em = c.em, saldo = c.saldo;
    // v28.60 (Luis, 08/10): a la izquierda del código, el tallerista de la OC vigente
    // v28.91 (Luis, 08/10): orden Cód · Descripción · Tallerista
    h += '<tr><td><b>' + _adsEsc(_adsCod(r.cod)) + '</b></td><td class="desc" title="' + _adsEsc(r.descripcion) + '">' + _adsEsc(r.descripcion) +
      '</td><td class="tall">' + (c.tallAct.length ? c.tallAct.map(_adsEsc).join("<br>") : "—") + '</td><td title="Góndola ' + _adsN(r.terminado) + " · racks " + _adsN(r.racks) + " · a guardar " + _adsN(r.a_guardar) + " · excedente " + _adsN(r.excedente) + '">' + _adsN(disp) +
      "</td><td>" + _adsN(comp) + '</td><td title="' + _adsN(proy) + ' por mes">' + _adsN(Math.round(em)) +
      '</td><td class="' + (saldo < 0 ? "neg" : "pos") + '">' + _adsN(saldo) + "</td>";
    // v27.78 (Luis): el recuadro es del PERÍODO (las N OC del rango), no de la última OC; la fecha sí es la de la última OC
    var fUlt = c.fechaUlt ? _adsFecha(c.fechaUlt) : '<span class="neg">sin OC</span>';
    if (c.pedP == null) h += '<td>' + fUlt + '</td><td colspan="3">' + (_ads.tallInc ? "sin OC en el período" : "…") + "</td>";
    else h += '<td>' + fUlt + '</td><td>' + (c.ultPed.length ? c.ultPed.map(function (v) { return _adsN(v); }).join("<br>") : "—") + '</td><td>' + (c.ultRec.length ? c.ultRec.map(function (v) { return _adsN(v); }).join("<br>") : "—") +
      '</td><td class="estp" title="' + _adsEsc((c.estDist.length ? c.estDist : c.estDet).join("\n")) + '">' + (c.estXY.length ? c.estXY.map(function (y) { return '<b>' + _adsEsc(y.pend) + '</b>'; }).join("<br>") : "—") + "</td>";   // v28.64: X/Y, una fila por tallerista   // v27.85 (Luis): el reparto por tallerista va en el tooltip
    h += "</tr>";
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
  var estH = 0, estDet = [], estArr = [];
  // v27.97 (Luis, 07/10, caso 609): la OC de la semana REEMPLAZA a la anterior, así que sólo se estima entrega
  // de los talleristas que están en la OC ACTUAL del código (la de fecha más nueva). El que salió de la OC no entrega más.
  var ultOc = pc.reduce(function (m, x) { var f = x.ult_fecha ? String(x.ult_fecha).slice(0, 10) : ""; return f > m ? f : m; }, "");
  var tallAct = ultOc ? pc.filter(function (x) { return String(x.ult_fecha || "").slice(0, 10) === ultOc; }).map(function (x) { return x.proveedor; })
              : (r.oc_prov ? String(r.oc_prov).split(" + ") : []);
  // v28.47 (Luis, 07/10): la OC completa ya ES la cobertura (30 días × índice): la entrega estimada es CUÁNTO DE LA OC
  // VIGENTE va a entregar cada tallerista, sin escalar al plazo. Declarado en la OC (gv_entrega_proy) si está; si no,
  // cantidad de la OC vigente × el % que viene entregando en el período. Menos lo que ya recibió de esa OC (ya es stock).
  pc.forEach(function (x) {
    if (ultOc && String(x.ult_fecha || "").slice(0, 10) !== ultOc) return;
    var ped = Number(x.pedido) || 0, ent = Number(x.entregado) || 0;
    var cer = (typeof _ads !== "undefined" && _ads.tallCerr) ? _ads.tallCerr[String(x.proveedor).toUpperCase() + "|" + String(r.cod).toUpperCase()] : null;
    if (cer && Number(cer.pedido) > 0) { ped = Number(cer.pedido); ent = Number(cer.entregado) || 0; }   // v28.86: % del último período cerrado
    var pct = ped > 0 ? Math.min(1, ent / ped) : 0;
    var cant = Number(x.ult_cant) || 0, rec = Number(x.ult_rec) || 0;
    var ep = (typeof _ads !== "undefined" && _ads.epOc && typeof _adsEpKey === "function") ? _ads.epOc[_adsEpKey(x.proveedor, r.cod, ultOc)] : null;
    var oc = ep != null && isFinite(ep), e;
    var xp = oc ? Math.round(ep) : Math.round(cant * pct);   // v28.64: lo proyectado de la OC (sin restar lo recibido)
    if (oc) { e = Math.max(0, xp - rec); estDet.push(x.proveedor + ": " + e + " (declarado en la OC: " + xp + ", ya recibió " + rec + ")"); }
    else { e = Math.max(0, xp - rec); estDet.push(x.proveedor + ": " + e + " (OC " + cant + " × " + Math.round(pct * 100) + " % que viene entregando, ya recibió " + rec + ")"); }
    estH += e; estArr.push({ p: x.proveedor, e: e, oc: oc, x: xp, y: cant, r: rec });
  });
  // v27.82 (Luis): la entrega estimada discriminada por tallerista, con su parte de lo estimado
  var _epTxt = function (y) { return y.oc ? " · cargado en la OC" : ""; };
  var estDist = estArr.length > 1 ? estArr.map(function (y) { return y.p + " " + (estH > 0 ? _adsPct(y.e / estH) : "—") + " (" + _adsN(y.e) + ")" + _epTxt(y); })
              : estArr.length ? [estArr[0].p + " (" + _adsN(estArr[0].e) + ")" + _epTxt(estArr[0])] : [];
  // v28.60 (Luis, 08/10, «058 me da −15, no −16»): la E.M. plazo que se MUESTRA sale del mismo saldo del servidor
  // (disp − comp − saldo): si la base cambia cómo cuenta los días (gv_ads_em_dias), la columna y el saldo no se desfasan.
  var _sal = Number(r["saldo" + H]);
  var _em = isFinite(_sal) ? Math.max(0, disp - comp - _sal) : proy * (typeof _adsEmDias === "function" ? _adsEmDias(H) : Math.max(0, H - 12)) / 30;
  return { disp: disp, proy: proy, comp: comp, em: _em, saldo: _sal, tallAct: tallAct, estH: pc.length ? estH : null, estOc: estArr.some(function (y) { return y.oc; }), estDet: estDet, estDist: estDist, estCaj: estArr.map(function (y) { return y.p + ": " + _adsN(y.e) + (y.oc ? "" : "*"); }),
           estCalc: estArr.some(function (y) { return !y.oc; }),
           ultPed: estArr.map(function (y) { return y.y; }), ultRec: estArr.map(function (y) { return y.r; }),   // v28.83 (Luis): pedido y recibido de la ÚLTIMA OC, uno por tallerista
           // v28.82: X = lo que falta (proyectado de la OC − lo ya recibido). v28.64 (Luis, 08/10): «X/Y» por tallerista: X = proyectado de entrega (con * si es estimado: la casilla de la OC
           // está VACÍA; un 0 cargado es dato y va sin *), Y = lo pedido en la última OC
           // v28.87 (Luis, 08/10): Pend. est. = X/Y. Y = lo que FALTA de la OC (pedido − ya entregado). X = lo cargado en la OC
           // (casilla vacía no es 0) o, sin dato, lo proyectado con el % del período cerrado (con *), menos lo ya entregado.
           estXY: estArr.map(function (y) { var t = _adsN(y.e) + (y.oc ? "" : "*") + "/" + _adsN(Math.max(0, y.y - y.r)); return { p: y.p, txt: t, pend: t }; }),
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
  st = st.replace(/<fonts[\s\S]*?<\/fonts>/, '<fonts count="3"><font><sz val="10"/><name val="Arial"/><family val="2"/></font><font><sz val="' + (cfg.fuente || 10) + '"/><name val="Arial"/><family val="2"/></font><font><b/><sz val="' + (cfg.fuente || 10) + '"/><name val="Arial"/><family val="2"/></font></fonts>')
         .replace(/<cellXfs[\s\S]*?<\/cellXfs>/, '<cellXfs count="6"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="' + (cfg.bordeRot ? 2 : 1) + '" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>'
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"' + W + '/></xf>'
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"' + ' applyAlignment="1"><alignment vertical="center"' + W + '/></xf>'   // v28.00 (Luis): TODO centrado en vertical, como su Excel
           + '<xf numFmtId="0" fontId="' + F + '" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>'
           // v28.01 (Luis): columna en NEGRITA (el Saldo del Excel de stock), centrada como los datos
           + '<xf numFmtId="0" fontId="2" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"' + W + '/></xf>'
           // v28.92 (Luis): fila-título de grupo (Excel de talleristas): negrita, fondo gris · v28.94: centrada
           + '<xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf></cellXfs>')
         .replace(/<cellXfs count="6"/, '<cellXfs count="7"')
         .replace(/<fills[\s\S]*?<\/fills>/, '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/><bgColor indexed="64"/></patternFill></fill></fills>');
  // v27.91 (Luis): el rótulo lleva el borde de abajo grueso de su Excel
  // v28.28 (Luis): TODOS los bordes marcados (cuadrícula al imprimir): 1 = fino en las 4 caras; 2 = el rótulo con el de abajo grueso.
  var _T = '<color indexed="64"/>';
  st = st.replace(/<borders[\s\S]*?<\/borders>/, '<borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border>'
    + '<border><left style="thin">' + _T + '</left><right style="thin">' + _T + '</right><top style="thin">' + _T + '</top><bottom style="thin">' + _T + '</bottom><diagonal/></border>'
    + '<border><left style="thin">' + _T + '</left><right style="thin">' + _T + '</right><top style="thin">' + _T + '</top><bottom style="medium">' + _T + '</bottom><diagonal/></border></borders>');
  cfb.FileIndex[iSt].content = enc.encode(st);
  var izq = {}; (cfg.izq || []).forEach(function (i) { izq[i] = 3; }); (cfg.izqSin || []).forEach(function (i) { izq[i] = 4; }); (cfg.negrita || []).forEach(function (i) { izq[i] = 5; });
  var tit = {}; (cfg.titulos || []).forEach(function (i) { tit[String(i + 1)] = 1; });
  var nCol = cfg.anchos.length, letra = String.fromCharCode(64 + nCol);
  var merges = (cfg.titulos || []).map(function (i) { return '<mergeCell ref="A' + (i + 1) + ':' + letra + (i + 1) + '"/>'; });
  var colN = function (L) { var n = 0; for (var k = 0; k < L.length; k++) n = n * 26 + (L.charCodeAt(k) - 64); return n - 1; };
  var cols = '<cols>' + cfg.anchos.map(function (w, i) { return '<col min="' + (i + 1) + '" max="' + (i + 1) + '" width="' + w + '" customWidth="1"/>'; }).join("") + '</cols>';
  cfb.FullPaths.forEach(function (p, i) {
    if (!/\/xl\/worksheets\/sheet\d+\.xml$/.test(p)) return;
    var x = dec.decode(new Uint8Array(cfb.FileIndex[i].content));
    x = x.replace(/<cols>[\s\S]*?<\/cols>/, "");
    x = x.replace(/<sheetData/, cols + "<sheetData");
    x = x.replace(/<c r="([A-Z]+)(\d+)"( s="\d+")?/g, function (_m, L, r) {
      if (r === "1") return '<c r="' + L + r + '" s="1"';
      if (tit[r]) return '<c r="' + L + r + '" s="6"';
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
    x = x.replace(/<\/sheetData>/, '</sheetData>' + (cfg.margenStd ? '<pageMargins left="0.70866141732283461" right="0.70866141732283461" top="0.74803149606299213" bottom="0.74803149606299213" header="0.31496062992125984" footer="0.31496062992125984"/>' : '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>') + '<pageSetup paperSize="9"' + (cfg.escala ? ' scale="' + cfg.escala + '"' : '') + ' orientation="portrait" fitToWidth="1" fitToHeight="0"/>');
    // v28.93 (Luis): mergeCells va ANTES de pageMargins (orden del esquema); al revés Excel dice «problema con el contenido»
    if (merges.length) x = x.replace(/<mergeCells[\s\S]*?<\/mergeCells>/, "").replace(/<\/sheetData>/, '</sheetData><mergeCells count="' + merges.length + '">' + merges.join("") + '</mergeCells>');
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
/* v28.96: la fila del artículo en la OC VIGENTE (mismo tallerista); null si no está en la vigente. */
function _adsVig(a) { return _ads.vig ? _ads.vig[String(a.pkey || a.proveedor).toUpperCase() + "|" + String(a.codigo).toUpperCase()] || null : null; }
function _adsPctNum(x) { return x == null || !isFinite(x) ? "" : Math.round(x * 100); }
function adsExcelTall() {
  if (!_ads.tall) { alert("Todavía se están leyendo las OC."); return; }
  var g = adsAgruparTalleristas(_ads.tall, _ads.umbral);
  // v28.92 (Luis, 08/10): sin columna Tallerista — una fila-título por tallerista con su %, y debajo sus artículos
  var aoa = [["Cód.", "Descripción", "OC evaluadas", "Pedido", "Recibio Virgilio", "%", "Fecha OC vigente", "Pedido OC vigente", "Recibido OC vigente"]], tits = [];
  g.forEach(function (t) {
    tits.push(aoa.length);
    aoa.push([t.proveedor + " · " + (t.pct == null || !isFinite(t.pct) ? "—" : Math.round(t.pct * 100) + "%"), "", "", "", "", "", "", "", ""]);
    t.arts.forEach(function (a) {
      var v = _adsVig(a) || {};
      aoa.push([_adsCod(a.codigo), a.descripcion || "", _adsNum(a.ocs), _adsNum(a.pedido), _adsNum(a.entregado),
        (a.pct == null || !isFinite(a.pct) ? "" : Math.round(a.pct * 100) + "%"), v.ult_fecha ? _adsFecha(v.ult_fecha) : "", _adsNum(v.ult_cant), _adsNum(v.ult_rec)]);
    });
  });
  return _adsXlsx(aoa, "Talleristas", "ADS_talleristas_" + _ads.n + "OC",
    // v27.88 (Luis, 07/10): formato de su Excel «ADS_talleristas_4OC_20261007»: Arial 14, rótulo alto 72, filas de 18, sus anchos
    { anchos: [12.42578125, 23, 7.42578125, 7.5703125, 7.5703125, 8.42578125, 8.28515625, 7.5703125, 8.28515625], izq: [1], fuente: 14, altoRot: 72, titulos: tits, altos: aoa.map(function (_f, i) { return i ? (tits.indexOf(i) >= 0 ? 22 : 18) : null; }) });
}
// v27.94: sin llamador desde la v27.98 (Luis: en el Excel va «Pettofrezza: 0», nombre + cajas, ver estCaj).
function _adsEstSinPct(arr) {
  return (arr || []).map(function (s) { var m = String(s).match(/\((\d+)\)\s*$/); return m ? m[1] : String(s); });
}
function adsExcelStock(H) {
  if (!_ads.stock) { alert("Todavía se está leyendo el stock."); return; }
  var f = adsFiltrarStock(_ads.stock, H, "");
  // v27.87 (Luis, 07/10): el formato es el de su Excel «ADS_stock_10d_20261007_1»: Arial 14, rótulo de alto 72,
  // todo con ajuste de texto, sus anchos y sus rótulos; el alto de cada fila según el texto más largo.
  // v27.91 (Luis, 07/10, «ADS_stock_10d_20261007_3»): optimización horizontal — cada tallerista en su sub-fila
  // (salto de línea dentro de la celda), descripción sin ajuste, rótulo con borde de abajo, escala 75 (v27.99: «_5», G 8 · L 19,14).
  // v28.54 (Luis, 08/10): «*» en Entr est OC y en Entr. est. x tall. = CALCULADO (OC × % que viene entregando), no cargado a mano en la OC.
  // v28.01 (Luis): el Saldo es lo más importante — primera columna de datos (C) y en negrita.
  // v28.92 (Luis, 08/10): el Excel es la tabla de la pantalla — Cód · Descripción · Tallerista · Stk · Comp · E.M. plazo ·
  // Saldo · Últ. OC · Pedido · Recib. · Pend. est. (una sub-fila por tallerista). El Saldo sigue en negrita.
  var aoa = [["Cód.", "Descripción", "Tallerista", "Stk", "Comp. " + H + "d", "E.M. plazo " + H + "d", "Saldo " + H + "d",
              "Últ. OC", "Pedido", "Recib.", "Pend. est."]];
  f.forEach(function (r) {
    var c = _adsStockCalc(r, H), sin = c.pedP == null;
    aoa.push([_adsCod(r.cod), r.descripcion || "", c.tallAct.length ? c.tallAct.join("\n") : "—", c.disp, c.comp, Math.round(c.em), _adsNum(c.saldo),
      c.fechaUlt ? _adsFecha(c.fechaUlt) : "sin OC",
      sin ? "" : c.ultPed.map(function (v) { return _adsN(v); }).join("\n"), sin ? "" : c.ultRec.map(function (v) { return _adsN(v); }).join("\n"),
      sin ? "" : c.estXY.map(function (y) { return y.pend; }).join("\n")]);
  });
  return _adsXlsx(aoa, "Quiebre " + H + " d", "ADS_stock_" + H + "d",
    { anchos: ADS_XLS_STOCK_ANCHOS, izq: [2], izqSin: [1], negrita: [6], fuente: 14, altoRot: 72, wrap: true, bordeRot: true, escala: 68, margenStd: true, altos: _adsAltos(aoa, ADS_XLS_STOCK_ANCHOS, [2, 8, 9, 10], 2, 1.4) });
}
// v28.30 (Luis, «ADS_stock_10d_20261007_8_1», *"ese es el formato que quiero"*): sus anchos exactos, filas de 2 renglones mínimo, escala 68
var ADS_XLS_STOCK_ANCHOS = [8.7109375, 23, 14.85546875, 6.28515625, 7.140625, 7.140625, 6.7109375, 7.7109375, 7.140625, 7.140625, 9.7109375];   // v28.92: columnas de la pantalla
/* alto de cada fila (Arial 14 con ajuste): renglones del texto más largo × 18 pt; ~1,35 de ancho por carácter */
function _adsAltos(aoa, anchos, cols, minRen, porCar) {
  return aoa.map(function (f, i) {
    if (!i) return null;
    var n = minRen || 1; cols.forEach(function (c) {
      var cpl = Math.max(1, Math.floor(anchos[c] / (porCar || 1.35))), k = 0;   // cada sub-fila (\n) cuenta sus renglones
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
  // v28.42 (Luis): ACUMULADOS — cada pastilla dice cuántos quiebran a ese plazo (10 ⊂ 20 ⊂ 30), no los que recién quiebran
  return { rojo: q10, naranja: q20, amarillo: q30 };
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
    [["rojo", "#dc2626", "#fff", "10d", "a 10 días"], ["naranja", "#ea580c", "#fff", "20d", "a 20 días"], ["amarillo", "#facc15", "#422006", "30d", "a 30 días"]].forEach(function (x) {
      if (c[x[0]] > 0) h += '<span class="ads-sem" data-n="' + c[x[0]] + '" style="height:18px;line-height:18px;padding:0 5px;border-radius:9px;background:' + x[1] + ';color:' + x[2] + ';font-size:12px;font-weight:800;text-align:center;white-space:nowrap;box-shadow:0 1px 3px rgba(0,0,0,.3);" title="' + c[x[0]] + ' artículo(s) quiebran ' + x[4] + ' (acumulado: incluye los que ya quiebran antes)">' + c[x[0]] + '<span style="font-size:9px;font-weight:700;margin-left:3px;opacity:.85;">' + x[3] + "</span></span>";
    });
    s.innerHTML = h; s.style.display = h ? "flex" : "none";
  });
}
