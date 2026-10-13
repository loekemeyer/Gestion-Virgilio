/* ============================================================================
   ANÁLISIS PRODUCTIVO POR TANDA (v29.64, pedido de Luis 13/10/2026)
   ----------------------------------------------------------------------------
   "en el modulo de operarios de Juan y en el Admin, un boton Analisis Productivo.
    Cuando se abre, permite ver, por tanda, el analisis tecnico (ritmo, velocidad,
    dificultad, ritmo en relacion a la dificultad). Deberia tambien analizar si hubo
    algo muy anomalo en el picking."

   El monitor ya evalúa por OPERARIO y por DÍA (Monitor → Ritmo, plantel.js). Esto es
   la MISMA cuenta abierta POR TANDA, con el detalle línea por línea y los avisos.
   Todo lo calcula la base: gv_analisis_lista / gv_analisis_tanda
   (sql/gv_analisis_productivo_v2964.sql). Acá sólo se dibuja.

   ⚠ QUÉ SIGNIFICA CADA TIEMPO, porque es lo que se lee mal:
     · esperado  = el tamaño D17 de la tanda (fijo + arranque + paradas + cajas + alturas),
                   o sea cuánto tendría que haber tardado POR SU DIFICULTAD.
     · real      = EP→TP menos pausas declaradas y huecos de más de 5 min, más la cola.
     · rendimiento = esperado ÷ real. 100 % = llegó al ritmo esperado.
     · s/caja del PKC = cuándo se TOCÓ OK, no cuándo se levantó la caja: medido el 13/10,
       marcar por ahí da 48 % de las tandas. Por eso va como dato, no como acusación.
     · s en la góndola = de que la pantalla mostró el código a que se confirmó (registro
       por paso, desde el 05/10). ESA es la que mide trabajo: mediana 29 s, 1 % bajo 2 s.

   Quién lo ve: el supervisor (sesión de Google) y los legajos de GV_Analisis_Acceso
   (hoy Juan, legajo 8). Vive en su propio archivo (regla v23.98), con ?v= atado a
   APP_VERSION. Candado: tests/analisis-productivo.cjs.
   ============================================================================ */

var _an = { dias: 14, q: "", lista: null, err: "", cargando: false, filtro: "todas",
            tanda: null, det: null, detErr: "", detCargando: false, legajo: null, marcas: {} };

function _anEsc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
  });
}
function _anN(v, dec) {
  var n = Number(v);
  return isFinite(n) ? n.toLocaleString("es-AR", { minimumFractionDigits: dec || 0, maximumFractionDigits: dec || 0 }) : "—";
}
function _anPct(x) { var n = Number(x); return isFinite(n) && n > 0 ? Math.round(n * 100) + " %" : "—"; }
/* Las horas van en H:MM (regla de unidades v20.x); menos de una hora, en minutos. */
function _anMin(m) {
  var n = Number(m);
  if (!isFinite(n)) return "—";
  if (n < 60) return _anN(n, n < 10 ? 1 : 0) + " min";
  return Math.floor(n / 60) + ":" + ("0" + Math.round(n % 60)).slice(-2);
}
function _anSeg(s) { var n = Number(s); return isFinite(n) ? (n >= 90 ? _anMin(n / 60) : _anN(n, n < 10 ? 1 : 0) + " s") : "—"; }
function _anDia(iso) {
  if (!iso) return "—";
  var p = String(iso).slice(0, 10).split("-");
  if (p.length !== 3) return String(iso);
  var d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
  return ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"][d.getDay()] + " " + p[2] + "/" + p[1];
}
function _anHora(ts) { return ts ? String(ts).slice(11, 16) : "—"; }
/* Verde si llegó al ritmo esperado, rojo si no. Sin dato, gris. */
function _anCol(x) { var n = Number(x); return !(n > 0) ? "#64748b" : (n >= 1 ? "#15803d" : "#b91c1c"); }

function _anRpc(name, args) {
  var sb = window.sb;
  if (!sb || typeof sb.rpc !== "function") return Promise.resolve({ data: null, error: { message: "sin sesión" } });
  try { return Promise.resolve(sb.rpc(name, args || {})).catch(function (e) { return { data: null, error: e }; }); }
  catch (e) { return Promise.resolve({ data: null, error: e }); }
}

function _anCss() {
  if (document.getElementById("anCss")) return;
  var st = document.createElement("style"); st.id = "anCss";
  st.textContent = [
    "#anOv{position:fixed;inset:0;z-index:9650;background:#f1f5f9;display:none;flex-direction:column;font-family:system-ui,Segoe UI,Arial,sans-serif;color:#0f172a;}",
    "#anOv *{box-sizing:border-box;}",
    "#anOv button{width:auto;margin-top:0;padding:6px 12px;font-size:14px;line-height:1.25;border-radius:9px;border:1px solid #cbd5e1;background:#fff;color:#0f172a;cursor:pointer;font-weight:600;}",
    "#anOv input{width:auto;margin-top:0;font:inherit;font-size:15px;padding:5px 8px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;}",
    "#anOv .an-top{display:flex;align-items:center;gap:8px;padding:9px 12px;background:#0f766e;color:#fff;flex-wrap:wrap;}",
    "#anOv .an-top .tit{font-weight:800;font-size:17px;}",
    "#anOv .an-top .sp{flex:1;}",
    "#anOv .an-top button{background:rgba(255,255,255,.14);color:#fff;border-color:rgba(255,255,255,.35);}",
    "#anOv .an-bar{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding:7px 12px;background:#fff;border-bottom:1px solid #e2e8f0;font-size:14px;}",
    "#anOv .an-bar .chip{padding:4px 11px;border-radius:13px;border:1px solid #cbd5e1;background:#f8fafc;cursor:pointer;}",
    "#anOv .an-bar .chip.on{background:#0f766e;color:#fff;border-color:#0f766e;font-weight:700;}",
    "#anOv .an-body{flex:1;overflow:auto;padding:10px 12px 26px;}",
    "#anOv .an-wrap{max-width:1000px;margin:0 auto;}",
    /* lista */
    "#anOv .an-t{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:8px 11px;margin-bottom:8px;cursor:pointer;}",
    "#anOv .an-t:hover{border-color:#0f766e;}",
    "#anOv .an-t .h{display:flex;align-items:baseline;gap:9px;flex-wrap:wrap;}",
    "#anOv .an-t .cod{font-size:19px;font-weight:900;letter-spacing:.3px;}",
    "#anOv .an-t .d{font-size:13px;color:#64748b;}",
    "#anOv .an-t .f{margin-left:auto;}",
    "#anOv .an-t .l{font-size:13.5px;color:#334155;margin-top:3px;}",
    "#anOv .an-t .l b{font-weight:800;}",
    "#anOv .al{display:inline-block;background:#dc2626;color:#fff;border-radius:11px;padding:1px 9px;font-size:12.5px;font-weight:800;}",
    /* detalle */
    "#anOv .an-cab{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:9px 12px;margin-bottom:9px;}",
    "#anOv .an-cab .cod{font-size:23px;font-weight:900;}",
    "#anOv .an-cab .m{font-size:13.5px;color:#475569;margin-top:2px;}",
    "#anOv .an-sec{font-size:15px;font-weight:800;margin:12px 0 6px;color:#0f172a;}",
    "#anOv .an-cards{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:8px;}",
    "#anOv .an-card{background:#fff;border:1.5px solid #e2e8f0;border-radius:11px;padding:6px 12px;text-align:center;min-width:92px;flex:1 1 92px;}",
    "#anOv .an-card b{display:block;font-size:22px;line-height:1.2;}",
    "#anOv .an-card span{font-size:11.5px;color:#475569;line-height:1.2;display:block;}",
    "#anOv .an-av{border-radius:10px;padding:7px 11px;margin-bottom:6px;font-size:14px;line-height:1.3;border-left:5px solid;}",
    "#anOv .an-av.alta{background:#fef2f2;border-color:#dc2626;color:#7f1d1d;font-weight:600;}",
    "#anOv .an-av.media{background:#fffbeb;border-color:#d97706;color:#78350f;}",
    "#anOv .an-av.baja{background:#f8fafc;border-color:#94a3b8;color:#334155;}",
    "#anOv .an-tblwrap{overflow:auto;background:#fff;border:1px solid #e2e8f0;border-radius:11px;}",
    "#anOv table{border-collapse:collapse;width:100%;font-size:13.5px;}",
    "#anOv th{background:#ccfbf1;color:#134e4a;font-size:11.5px;padding:4px 6px;text-align:center;line-height:1.15;position:sticky;top:0;}",
    "#anOv td{padding:3px 6px;text-align:center;border-top:1px solid #eef2f7;white-space:nowrap;}",
    "#anOv td.t{text-align:left;max-width:170px;overflow:hidden;text-overflow:ellipsis;}",
    "#anOv tr.mala td{background:#fef2f2;}",
    "#anOv .nota{font-size:12.5px;color:#64748b;margin:6px 0;line-height:1.35;}",
    "#anOv .an-bar .an-sep{width:10px;}",
    "#anOv .mk{display:inline-block;border-radius:11px;padding:1px 8px;font-size:12px;font-weight:800;margin-right:5px;}",
    "#anOv .mk-a{background:#fee2e2;color:#991b1b;} #anOv .mk-r{background:#dcfce7;color:#166534;}",
    "#anOv .an-mk{display:flex;align-items:center;gap:7px;flex-wrap:wrap;background:#fff;border:1px solid #e2e8f0;border-radius:11px;padding:7px 10px;margin-bottom:8px;}",
    "#anOv .an-mk-t{flex:1;font-size:13.5px;color:#334155;font-weight:700;min-width:150px;}",
    "#anOv .an-mk-b{font-size:13px;padding:5px 11px;}",
    "#anOv .an-mk-b.a{background:#fef2f2;border-color:#fca5a5;color:#991b1b;}",
    "#anOv .an-mk-b.r{background:#f0fdf4;border-color:#86efac;color:#166534;}",
    "#anOv .an-concl{background:#ecfeff;border:1px solid #a5f3fc;border-radius:11px;padding:9px 12px;margin-bottom:9px;font-size:15px;line-height:1.35;color:#155e75;font-weight:600;}",
    "#anOv .msg{text-align:center;padding:26px;color:#64748b;}",
    "#anOv .err{text-align:center;padding:16px;color:#b91c1c;font-weight:700;}"
  ].join("\n");
  document.head.appendChild(st);
}

/* ── apertura ─────────────────────────────────────────────────────────────── */
function openAnalisisProductivo(legajo) {
  _anCss();
  var ov = document.getElementById("anOv");
  if (!ov) { ov = document.createElement("div"); ov.id = "anOv"; document.body.appendChild(ov); }
  ov.style.display = "flex";
  // El supervisor va sin legajo (manda su sesión); el operario manda el suyo.
  _an.legajo = legajo || (typeof window.gvLegajoActual === "function" ? window.gvLegajoActual() : null) || null;
  _an.tanda = null; _an.det = null; _an.detErr = "";
  _anRender(); _anCargar();
}
function anCerrar() { var ov = document.getElementById("anOv"); if (ov) ov.style.display = "none"; }
function anDias(n) { _an.dias = n; _anCargar(); }
function anBuscar(v) { _an.q = String(v || "").toUpperCase().trim(); _anRender(); }
function anVolver() { _an.tanda = null; _an.det = null; _an.detErr = ""; _anRender(); }

function _anCargar() {
  if (_an.cargando) return;
  _an.cargando = true; _an.err = ""; _an.lista = null; _anRender();
  _anRpc("gv_analisis_lista", { p_dias: _an.dias, p_legajo: _an.legajo }).then(function (r) {
    if (r.error || !r.data) {
      var m = String((r.error && r.error.message) || "sin respuesta");
      // Una lectura rota NO es "no hay tandas" (regla «una lectura ROTA no es un CERO»).
      _an.err = /ACCESO/.test(m)
        ? "El Análisis Productivo es para el supervisor y los legajos habilitados."
        : "No se pudo leer: " + m;
    } else _an.lista = r.data;
    _an.cargando = false; _anRender();
  });
  // Las marcas van en su propia lectura: si falla, la lista se ve igual (sin los banderines).
  _anRpc("gv_analisis_marcas", { p_dias: _an.dias, p_legajo: _an.legajo }).then(function (r) {
    if (r && !r.error && r.data && typeof r.data === "object") { _an.marcas = r.data; _anRender(); }
  });
}
function anFiltro(f) { _an.filtro = f; _anRender(); }
function anMarcar(estado) {
  if (!_an.tanda) return;
  var nota = null;
  if (estado === "anomala" || estado === "revisada") {
    nota = prompt(estado === "anomala"
      ? "¿Qué tiene de raro esta tanda? (queda anotado; se puede dejar vacío)"
      : "¿Alguna nota? (se puede dejar vacío)", (_an.marcas[_an.tanda] || {}).nota || "");
    if (nota === null) return;
  }
  _anRpc("gv_analisis_marcar", { p_tanda: _an.tanda, p_estado: estado, p_nota: nota, p_legajo: _an.legajo })
    .then(function (r) {
      if (r && r.error) { alert("No se pudo marcar: " + (r.error.message || r.error)); return; }
      if (estado === "sin") delete _an.marcas[_an.tanda];
      else _an.marcas[_an.tanda] = { estado: estado, nota: nota, por: _an.legajo || "", at: new Date().toISOString() };
      _anRender();
    });
}

function anAbrir(tanda) {
  _an.tanda = tanda; _an.det = null; _an.detErr = ""; _an.detCargando = true; _anRender();
  _anRpc("gv_analisis_tanda", { p_tanda: tanda, p_legajo: _an.legajo }).then(function (r) {
    if (r.error || !r.data) _an.detErr = "No se pudo leer la tanda: " + String((r.error && r.error.message) || "sin respuesta");
    else _an.det = r.data;
    _an.detCargando = false; _anRender();
  });
}

/* ── render ───────────────────────────────────────────────────────────────── */
function _anRender() {
  var ov = document.getElementById("anOv"); if (!ov) return;
  var h = '<div class="an-top"><span class="tit">📈 Análisis Productivo</span>' +
          (_an.tanda ? '<button onclick="anVolver()">← Tandas</button>' : '') +
          '<span class="sp"></span><button onclick="anCerrar()">✕ Cerrar</button></div>';
  if (!_an.tanda) {
    var c = function (n, t) { return '<span class="chip' + (_an.dias === n ? ' on' : '') + '" onclick="anDias(' + n + ')">' + t + '</span>'; };
    var f = function (k, t) { return '<span class="chip' + (_an.filtro === k ? ' on' : '') + '" onclick="anFiltro(\'' + k + '\')">' + t + '</span>'; };
    h += '<div class="an-bar">' + c(7, "7 días") + c(14, "14 días") + c(30, "30 días") + c(60, "60 días") +
         '<span class="an-sep"></span>' + f("todas", "Todas") + f("avisos", "Con avisos") + f("marcadas", "🚩 Marcadas") +
         '<input id="anQ" placeholder="Buscar tanda…" value="' + _anEsc(_an.q) + '" oninput="anBuscar(this.value)" style="width:120px">' +
         '<button onclick="_anCargar()">Actualizar</button></div>';
  }
  h += '<div class="an-body"><div class="an-wrap">' + (_an.tanda ? _anDetalleHtml() : _anListaHtml()) + '</div></div>';
  ov.innerHTML = h;
}

function _anListaHtml() {
  if (_an.err) return '<div class="err">' + _anEsc(_an.err) + '</div>';
  if (_an.cargando || !_an.lista) return '<div class="msg">Calculando…</div>';
  var t = (_an.lista.tandas || []).filter(function (x) {
    if (_an.q && String(x.tanda).indexOf(_an.q) < 0) return false;
    if (_an.filtro === "avisos") return (Number(x.alerta) || 0) > 0;
    if (_an.filtro === "marcadas") return !!_an.marcas[x.tanda];
    return true;
  });
  if (!t.length) return '<div class="msg">' + (_an.filtro === "marcadas" ? "Ninguna tanda marcada en el período."
    : _an.filtro === "avisos" ? "Ninguna tanda con avisos en el período."
    : "No hay tandas con picking o armado terminado en el período.") + '</div>';
  var h = '';
  t.forEach(function (x) {
    var al = Number(x.alerta) || 0;
    h += '<div class="an-t" onclick="anAbrir(\'' + _anEsc(x.tanda) + '\')">' +
      '<div class="h"><span class="cod">' + _anEsc(x.tanda) + '</span>' +
      '<span class="d">' + _anDia(x.dia) + ' · ' + _anN(x.m3, 3) + ' m³</span>' +
      '<span class="f">' + _anMarcaChip(x.tanda) + (al ? '<span class="al">⚠ ' + al + '</span>' : '') + '</span></div>';
    if (x.pick) h += '<div class="l">🛒 <b>' + _anEsc(x.pick.nombre || x.pick.legajo) + '</b> · ' +
      '<b style="color:' + _anCol(x.pick.indice) + '">' + _anPct(x.pick.indice) + '</b> · ' +
      _anEsc(x.pick.nivel || "") + ' · ' + _anMin(x.pick.real_min) + ' de ' + _anMin(x.pick.esperado_min) + '</div>';
    if (x.arm) h += '<div class="l">🔨 <b>' + _anEsc(x.arm.nombre || x.arm.legajo) + '</b> · ' +
      '<b style="color:' + _anCol(x.arm.indice) + '">' + _anPct(x.arm.indice) + '</b> · ' +
      _anEsc(x.arm.nivel || "") + ' · ' + _anMin(x.arm.real_min) + ' de ' + _anMin(x.arm.esperado_min) + '</div>';
    h += '</div>';
  });
  return h + '<div class="nota"><b>Rendimiento</b> = lo que tendría que haber tardado por su dificultad ÷ lo que tardó de verdad. ' +
    '100 % o más = llegó al ritmo. El ⚠ cuenta los avisos fuertes: un código que el picking dio completo y el armado ' +
    'declaró faltante, y los códigos confirmados sin tiempo de verdad frente a la góndola.</div>';
}

function _anMarcaChip(tanda) {
  var m = _an.marcas[tanda]; if (!m) return "";
  return m.estado === "anomala"
    ? '<span class="mk mk-a" title="' + _anEsc(m.nota || "") + '">🚩 anómala</span>'
    : '<span class="mk mk-r" title="' + _anEsc(m.nota || "") + '">✓ revisada</span>';
}

/* La CONCLUSIÓN en una frase: lo primero que se lee, antes de los números.
   Se arma con lo que ya devolvió la base; no hay una segunda cuenta acá. */
function _anConclusion(d) {
  var p = d.picking, a = d.armado, av = d.avisos || [], out = [];
  var altas = av.filter(function (x) { return x.sev === "alta"; }).length;
  if (p) {
    var i = Number(p.indice), pct = isFinite(i) && i > 0 ? Math.round(100 / i) : null;
    out.push("El picking lo hizo " + _anEsc(p.nombre || p.legajo) + " en " + _anMin(p.real_min) +
      (pct != null ? (pct > 110 ? ", un " + (pct - 100) + " % MÁS de lo esperado"
                    : pct < 90 ? ", un " + (100 - pct) + " % MENOS de lo esperado"
                    : ", prácticamente lo esperado") : "") +
      " para una tanda de dificultad " + _anEsc(String(p.nivel || "").toLowerCase()) + ".");
  }
  if (a) {
    var j = Number(a.indice), pj = isFinite(j) && j > 0 ? Math.round(100 / j) : null;
    out.push("El armado lo hizo " + _anEsc(a.nombre || a.legajo) + " en " + _anMin(a.real_min) +
      (pj != null ? (pj > 110 ? ", un " + (pj - 100) + " % más de lo esperado"
                   : pj < 90 ? ", un " + (100 - pj) + " % menos" : ", en lo esperado") : "") + ".");
  }
  out.push(altas ? ("Hay " + altas + " cosa(s) para mirar de cerca.")
                 : av.length ? "Nada grave: los avisos son para mirar, no para alarmarse."
                             : "No se encontró nada raro.");
  return out.join(" ");
}

function _anCard(valor, rotulo, color) {
  return '<div class="an-card"><b' + (color ? ' style="color:' + color + '"' : '') + '>' + valor + '</b><span>' + rotulo + '</span></div>';
}

function _anFaseHtml(f, esPick) {
  if (!f) return '';
  var h = '<div class="an-sec">' + (esPick ? '🛒 Picking' : '🔨 Armado') + ' — ' + _anEsc(f.nombre || f.legajo) +
    ' <span style="font-weight:600;color:#64748b;font-size:13px">' +
    _anHora(esPick ? f.ep : f.ap) + ' a ' + _anHora(esPick ? f.tp : f.tap) + '</span></div>';
  h += '<div class="an-cards">' +
    _anCard(_anPct(f.indice), "rendimiento<br>(esperado ÷ real)", _anCol(f.indice)) +
    _anCard(_anEsc(f.nivel || "—") + '<span style="font-size:13px;color:#64748b"> ' + (f.grado || "") + '/10</span>', "dificultad") +
    _anCard(_anMin(f.esperado_min), "esperado<br>por su dificultad") +
    _anCard(_anMin(f.real_min), "real<br>(sin pausas ni huecos)") +
    _anCard(_anN(f.m3_h, 2), "m³ por hora") +
    _anCard(_anN(f.cajas_h, 0), "cajas por hora") +
    (esPick ? _anCard(_anSeg(f.seg_linea), "por código") : _anCard(_anN(f.nps, 0), "pedidos")) +
    '</div>';
  h += '<div class="nota">De punta a punta ' + _anMin(f.bruto_min) + '; pausas declaradas ' + _anMin(f.pausa_min) +
    (esPick ? '; huecos de más de 5 min ' + _anMin(f.huecos_min) : '') +
    '; cola hasta la tarea siguiente ' + _anMin(f.cola_min) + '. ' +
    (f.est_ini_min != null ? 'Antes de empezar, el sistema había estimado ' + _anMin(f.est_ini_min) + '. ' : '') +
    (f.prom_operario != null ? 'Este operario viene en ' + _anPct(f.prom_operario) + ' en sus últimas tandas. ' : '') +
    (f.prom_grado != null ? 'El promedio del depósito en tandas de esta dificultad es ' + _anPct(f.prom_grado) + '.' : '') +
    '</div>';
  if (esPick) h += '<div class="nota">' + _anN(f.lineas, 0) + ' códigos · ' + _anN(f.cajas, 0) + ' cajas · ' +
    _anN(f.paradas, 0) + ' paradas · ' + _anN(f.esc, 0) + ' con escalera' +
    (Number(f.n_mx) ? ' · ' + _anN(f.n_mx, 0) + ' sin stock en góndola al empezar' : '') +
    (Number(f.n_f) ? ' · ' + _anN(f.n_f, 0) + ' sin celda en el Mapa' : '') + '.</div>';
  return h;
}

function _anDetalleHtml() {
  if (_an.detErr) return '<div class="err">' + _anEsc(_an.detErr) + '</div>';
  if (_an.detCargando || !_an.det) return '<div class="msg">Calculando…</div>';
  var d = _an.det, cab = d.cabecera || {};
  var h = '<div class="an-cab"><div class="cod">' + _anEsc(d.tanda) + '</div><div class="m">' +
    _anN(cab.m3, 3) + ' m³ · ' + _anEsc((cab.clientes || []).join(" · ") || "—") +
    (cab.zona ? ' · ' + _anEsc(cab.zona) : '') + '</div>' +
    '<div class="m">NP: ' + _anEsc((cab.nps || []).join(" · ") || "—") +
    (cab.fecha_entrega ? ' · entrega ' + _anDia(cab.fecha_entrega) : '') + '</div></div>';

  var mk = _an.marcas[d.tanda] || null;
  h += '<div class="an-mk">' +
    '<span class="an-mk-t">' + (mk ? (mk.estado === "anomala" ? '🚩 Marcada como ANÓMALA' : '✓ Marcada como revisada') +
        (mk.nota ? ' — ' + _anEsc(mk.nota) : '') + (mk.por ? ' <small>(' + _anEsc(mk.por) + ')</small>' : '')
      : 'Sin marcar') + '</span>' +
    '<button class="an-mk-b a" onclick="anMarcar(\'anomala\')">🚩 Anómala</button>' +
    '<button class="an-mk-b r" onclick="anMarcar(\'revisada\')">✓ Revisada</button>' +
    (mk ? '<button class="an-mk-b" onclick="anMarcar(\'sin\')">✕ Sacar marca</button>' : '') +
    '</div>';
  h += '<div class="an-concl">' + _anConclusion(d) + '</div>';
  h += '<div class="an-sec">Qué se encontró</div>';
  (d.avisos || []).forEach(function (a) {
    h += '<div class="an-av ' + _anEsc(a.sev) + '">' +
      (a.sev === "alta" ? "🔴 " : a.sev === "media" ? "🟠 " : "⚪ ") + _anEsc(a.texto) + '</div>';
  });
  if (!(d.avisos || []).length) h += '<div class="an-av baja">Sin avisos: el picking y el armado no tienen nada raro.</div>';

  h += _anFaseHtml(d.picking, true);
  h += _anFaseHtml(d.armado, false);

  var L = d.lineas || [];
  if (L.length) {
    h += '<div class="an-sec">Código por código</div><div class="an-tblwrap"><table><thead><tr>' +
      '<th>#</th><th>Código</th><th>Descripción</th><th>Góndola</th><th>Cajas</th>' +
      '<th>Desde el<br>anterior</th><th>Normal<br>del código</th><th>Veces<br>lo normal</th>' +
      '<th>Frente a<br>la góndola</th><th>s por<br>caja</th></tr></thead><tbody>';
    L.forEach(function (x) {
      var mala = (Number(x.ratio) > 6 && Number(x.seg) > 300) ||
                 (x.seg_vista != null && Number(x.seg_vista) >= 0 && Number(x.seg_vista) < 2 && Number(x.cajas) >= 3) ||
                 (Number(x.falto_armado) > 0 && Number(x.cajas) >= Number(x.pedidas));
      h += '<tr' + (mala ? ' class="mala"' : '') + '><td>' + _anN(x.orden, 0) + '</td>' +
        '<td><b>' + _anEsc(x.cod) + '</b></td><td class="t">' + _anEsc(x["desc"] || "") + '</td>' +
        '<td>' + _anEsc(x.sector || "—") + (x.es_exc ? " ·EXC" : "") + '</td>' +
        '<td>' + _anN(x.cajas, 0) + (Number(x.pedidas) > Number(x.cajas) ? ' <span style="color:#b91c1c">de ' + _anN(x.pedidas, 0) + '</span>' : '') + '</td>' +
        '<td>' + _anSeg(x.seg) + '</td><td>' + _anSeg(x.esp_seg) + '</td>' +
        '<td' + (Number(x.ratio) > 6 ? ' style="color:#b91c1c;font-weight:800"' : '') + '>' + (x.ratio != null ? _anN(x.ratio, 1) + "×" : "—") + '</td>' +
        '<td' + (x.seg_vista != null && Number(x.seg_vista) < 2 ? ' style="color:#b91c1c;font-weight:800"' : '') + '>' + _anSeg(x.seg_vista) + '</td>' +
        '<td>' + (x.seg_caja != null ? _anN(x.seg_caja, 1) : "—") + '</td></tr>';
    });
    h += '</tbody></table></div>';
    h += '<div class="nota"><b>Desde el anterior</b>: lo que pasó entre que confirmó el código de arriba y éste. ' +
      '<b>Normal del código</b>: lo que tarda ese código habitualmente (mediana de 120 días, con sus cajas). ' +
      '<b>Frente a la góndola</b>: de que la pantalla mostró el código a que lo confirmó — ésa es la que mide trabajo de verdad. ' +
      '<b>s por caja</b> sale del momento en que se tocó OK, no de cuándo se levantó la caja: un número chico solo no prueba nada.</div>';
  }
  if (d.nota_paso) h += '<div class="nota">⚠ ' + _anEsc(d.nota_paso) + '</div>';
  return h;
}

/* El botón en la botonera del operario: sólo para los legajos habilitados. */
function anMostrarBotonOperario(legajo) {
  var b = document.getElementById("btnAnalisisOp");
  if (!b) return;
  b.style.display = "none";
  if (!legajo) return;
  _anRpc("gv_analisis_acceso_ok", { p_legajo: String(legajo) }).then(function (r) {
    if (r && !r.error && r.data === true) { b.style.display = ""; b.setAttribute("data-legajo", String(legajo)); }
  });
}
