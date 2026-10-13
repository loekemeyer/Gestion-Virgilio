/* ============================================================================
   ANÁLISIS PRODUCTIVO POR TANDA (v29.64, pedido de Luis 13/10/2026)
   Rediseño visual v29.75 — es la PANTALLA DE REFERENCIA del sistema de diseño
   de la app (regla «GV-UI» en CLAUDE.md). Al tocar acá, no romper esos 8 puntos.
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
/* Los textos de los avisos los arma la base sin tildes (vienen de un plpgsql). Acá sólo se
   acentúan y se les saca el relleno: es cosmético, no cambia ni un número. */
var _AN_TILDES = { codigo: "código", codigos: "códigos", mostro: "mostró", tardo: "tardó",
  declaro: "declaró", despues: "después", segun: "según", numero: "número", pickeo: "pickeó",
  confirmo: "confirmó", termino: "terminó", mas: "más", minimo: "mínimo", maximo: "máximo",
  gondola: "góndola", gondolas: "góndolas", deposito: "depósito", dificil: "difícil",
  rapido: "rápido", ultimo: "último", ultima: "última", linea: "línea", lineas: "líneas",
  reconfirmo: "reconfirmó", sin: "sin" };
function _anTxt(s) {
  var t = String(s == null ? "" : s).replace(/^\s*Hay\s+/i, "");
  // "1 codigo(s)" → "1 código" · "3 codigo(s)" → "3 códigos"
  t = t.replace(/(\d+)\s+([A-Za-zÁÉÍÓÚáéíóúñÑ]+)\(s\)(\s+[a-záéíóúñ]+[ao]s\b)?/g, function (_m, n, w, part) {
    var uno = Number(n) === 1;
    // "1 codigo(s) confirmados" → "1 código confirmado"; "3 codigo(s) confirmados" queda igual.
    return n + " " + w + (uno ? "" : "s") + (part ? (uno ? part.slice(0, -1) : part) : "");
  });
  t = t.replace(/[A-Za-zÁÉÍÓÚáéíóúñÑ]+/g, function (w) {
    var k = _AN_TILDES[w.toLowerCase()];
    if (!k) return w;
    return w[0] === w[0].toUpperCase() ? k.charAt(0).toUpperCase() + k.slice(1) : k;
  });
  return t.charAt(0).toUpperCase() + t.slice(1);
}

function _anRpc(name, args) {
  var sb = window.sb;
  if (!sb || typeof sb.rpc !== "function") return Promise.resolve({ data: null, error: { message: "sin sesión" } });
  try { return Promise.resolve(sb.rpc(name, args || {})).catch(function (e) { return { data: null, error: e }; }); }
  catch (e) { return Promise.resolve({ data: null, error: e }); }
}

/* ── estilos ──────────────────────────────────────────────────────────────────
   Sistema de diseño GV-UI: un dato principal por pantalla, tres niveles de
   jerarquía, color sólo cuando significa algo, explicaciones plegadas.          */
function _anCss() {
  if (document.getElementById("anCss")) return;
  var st = document.createElement("style"); st.id = "anCss";
  st.textContent = [
    "#anOv{position:fixed;inset:0;z-index:9650;background:#f6f7f9;display:none;flex-direction:column;",
    "  font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#0f172a;-webkit-font-smoothing:antialiased;}",
    "#anOv *{box-sizing:border-box;}",
    "#anOv button{width:auto;margin-top:0;padding:7px 13px;font-size:14px;line-height:1.2;border-radius:10px;",
    "  border:1px solid #d7dde5;background:#fff;color:#0f172a;cursor:pointer;font-weight:600;}",
    "#anOv button:hover{border-color:#94a3b8;}",
    "#anOv input{width:auto;margin-top:0;font:inherit;font-size:15px;padding:6px 10px;border:1px solid #d7dde5;border-radius:10px;background:#fff;}",
    /* barra superior */
    "#anOv .an-top{display:flex;align-items:center;gap:10px;padding:11px 16px;background:#0f172a;color:#fff;flex-wrap:wrap;}",
    "#anOv .an-top .tit{font-weight:700;font-size:16px;letter-spacing:.2px;}",
    "#anOv .an-top .sp{flex:1;}",
    "#anOv .an-top button{background:rgba(255,255,255,.10);color:#fff;border-color:rgba(255,255,255,.25);}",
    "#anOv .an-bar{display:flex;align-items:center;gap:7px;flex-wrap:wrap;padding:9px 16px;background:#fff;border-bottom:1px solid #e6eaef;font-size:14px;}",
    "#anOv .an-bar .chip{padding:5px 12px;border-radius:999px;border:1px solid #e2e8f0;background:#fff;cursor:pointer;color:#475569;}",
    "#anOv .an-bar .chip.on{background:#0f172a;color:#fff;border-color:#0f172a;font-weight:700;}",
    "#anOv .an-bar .an-sep{width:8px;}",
    "#anOv .an-body{flex:1;overflow:auto;padding:14px 16px 40px;}",
    "#anOv .an-wrap{max-width:1040px;margin:0 auto;}",
    /* ── lista ── */
    "#anOv .an-t{background:#fff;border:1px solid #e6eaef;border-radius:14px;padding:11px 14px;margin-bottom:9px;cursor:pointer;",
    "  display:grid;grid-template-columns:1fr auto;gap:10px 14px;align-items:center;transition:border-color .12s;}",
    "#anOv .an-t:hover{border-color:#0f172a;}",
    "#anOv .an-t .cod{font-size:20px;font-weight:800;letter-spacing:.4px;line-height:1;}",
    "#anOv .an-t .d{font-size:12.5px;color:#64748b;margin-top:3px;}",
    "#anOv .an-t .f{text-align:right;white-space:nowrap;}",
    "#anOv .an-t .fases{grid-column:1/-1;display:flex;gap:22px;flex-wrap:wrap;border-top:1px solid #f1f5f9;padding-top:8px;}",
    "#anOv .an-t .l{display:flex;align-items:baseline;gap:7px;font-size:13px;color:#64748b;}",
    "#anOv .an-t .l .r{font-size:17px;font-weight:800;}",
    "#anOv .an-t .l .q{font-size:11px;letter-spacing:.6px;color:#94a3b8;font-weight:700;text-transform:uppercase;}",
    "#anOv .al{display:inline-block;background:#dc2626;color:#fff;border-radius:999px;padding:2px 10px;font-size:12.5px;font-weight:700;}",
    "#anOv .mk{display:inline-block;border-radius:999px;padding:2px 9px;font-size:12px;font-weight:700;margin-right:6px;}",
    "#anOv .mk-a{background:#fee2e2;color:#991b1b;} #anOv .mk-r{background:#dcfce7;color:#166534;}",
    /* ── detalle: encabezado ── */
    "#anOv .an-hd{margin:2px 0 12px;}",
    "#anOv .an-hd .cod{font-size:30px;font-weight:800;letter-spacing:.5px;line-height:1.05;}",
    "#anOv .an-hd .sub{font-size:13.5px;color:#64748b;margin-top:4px;}",
    /* ── detalle: estado + acciones ── */
    "#anOv .an-state{display:flex;align-items:center;gap:10px;flex-wrap:wrap;background:#fff;border:1px solid #e6eaef;",
    "  border-left:5px solid #94a3b8;border-radius:12px;padding:10px 14px;margin-bottom:12px;}",
    "#anOv .an-state.alta{border-left-color:#dc2626;} #anOv .an-state.media{border-left-color:#d97706;} #anOv .an-state.ok{border-left-color:#16a34a;}",
    "#anOv .an-state .v{font-size:16px;font-weight:700;flex:1;min-width:180px;}",
    "#anOv .an-state.alta .v{color:#991b1b;} #anOv .an-state.media .v{color:#92400e;} #anOv .an-state.ok .v{color:#166534;}",
    "#anOv .an-state .nota{font-size:13px;color:#64748b;font-weight:500;}",
    "#anOv .an-mk-b{font-size:13px;padding:6px 12px;}",
    "#anOv .an-mk-b.a{border-color:#fca5a5;color:#991b1b;} #anOv .an-mk-b.r{border-color:#86efac;color:#166534;}",
    /* ── detalle: el dato principal ── */
    "#anOv .an-hero{display:grid;grid-template-columns:repeat(auto-fit,minmax(248px,1fr));gap:12px;margin-bottom:14px;}",
    "#anOv .an-fase{background:#fff;border:1px solid #e6eaef;border-radius:14px;padding:14px 16px;}",
    "#anOv .an-fase .q{font-size:11.5px;letter-spacing:1px;text-transform:uppercase;color:#94a3b8;font-weight:700;}",
    "#anOv .an-fase .big{font-size:46px;font-weight:800;line-height:1.02;letter-spacing:-1px;margin:2px 0 1px;}",
    "#anOv .an-fase .cmp{font-size:15px;color:#0f172a;font-weight:600;}",
    "#anOv .an-fase .who{font-size:13.5px;color:#64748b;margin-top:3px;}",
    "#anOv .an-fase .tags{display:flex;gap:6px;flex-wrap:wrap;margin-top:9px;}",
    "#anOv .an-fase .tag{font-size:12px;color:#475569;background:#f1f5f9;border-radius:999px;padding:3px 9px;}",
    "#anOv .an-fase .tag.d3{background:#fee2e2;color:#991b1b;} #anOv .an-fase .tag.d2{background:#ffedd5;color:#9a3412;}",
    /* ── detalle: hallazgos ── */
    "#anOv .an-av{display:flex;gap:9px;align-items:flex-start;background:#fff;border:1px solid #e6eaef;border-radius:11px;",
    "  padding:9px 13px;margin-bottom:7px;font-size:14.5px;line-height:1.35;color:#0f172a;}",
    "#anOv .an-av .dot{width:9px;height:9px;border-radius:50%;flex:0 0 9px;margin-top:6px;background:#94a3b8;}",
    "#anOv .an-av.alta{background:#fef4f4;border-color:#fecaca;} #anOv .an-av.alta .dot{background:#dc2626;}",
    "#anOv .an-av.media .dot{background:#d97706;}",
    "#anOv .an-av.baja{color:#475569;}",
    /* ── detalle: lo plegado ── */
    "#anOv details{background:#fff;border:1px solid #e6eaef;border-radius:12px;margin-bottom:8px;overflow:hidden;}",
    "#anOv summary{cursor:pointer;padding:11px 14px;font-size:14.5px;font-weight:700;color:#0f172a;list-style:none;display:flex;align-items:center;gap:8px;}",
    "#anOv summary::-webkit-details-marker{display:none;}",
    "#anOv summary::before{content:'›';display:inline-block;font-size:19px;color:#94a3b8;transform:rotate(0deg);transition:transform .15s;line-height:1;}",
    "#anOv details[open] summary::before{transform:rotate(90deg);}",
    "#anOv summary .n{font-weight:500;color:#94a3b8;font-size:13.5px;}",
    "#anOv .an-in{padding:2px 14px 14px;}",
    "#anOv .an-kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(104px,1fr));gap:10px 6px;margin:4px 0 10px;}",
    "#anOv .an-kpi div b{display:block;font-size:19px;font-weight:700;line-height:1.15;}",
    "#anOv .an-kpi div span{display:block;font-size:11.5px;color:#64748b;margin-top:1px;}",
    "#anOv .an-kv{font-size:13px;color:#64748b;line-height:1.5;}",
    "#anOv .an-kv b{color:#334155;font-weight:700;}",
    "#anOv .an-gl{font-size:13.5px;color:#475569;line-height:1.55;}",
    "#anOv .an-gl b{color:#0f172a;}",
    /* ── tabla ── */
    "#anOv .an-tblwrap{overflow:auto;border-top:1px solid #eef2f7;}",
    "#anOv table{border-collapse:collapse;width:100%;font-size:13.5px;}",
    "#anOv th{background:#f8fafc;color:#64748b;font-size:11px;font-weight:700;letter-spacing:.3px;text-transform:uppercase;",
    "  padding:7px 8px;text-align:center;line-height:1.2;position:sticky;top:0;border-bottom:1px solid #e6eaef;}",
    "#anOv td{padding:6px 8px;text-align:center;border-top:1px solid #f1f5f9;white-space:nowrap;}",
    "#anOv td.t{text-align:left;max-width:210px;overflow:hidden;text-overflow:ellipsis;color:#475569;}",
    "#anOv tr.mala td{background:#fef4f4;}",
    "#anOv .msg{text-align:center;padding:40px 20px;color:#94a3b8;font-size:15px;}",
    "#anOv .err{text-align:center;padding:22px;color:#b91c1c;font-weight:700;}",
    "@media(max-width:560px){#anOv .an-body{padding:12px 11px 40px;}#anOv .an-hd .cod{font-size:25px;}",
    "  #anOv .an-fase .big{font-size:38px;}#anOv .an-fase{padding:12px 13px;}}"
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
function anCerrar() { var ov = document.getElementById("anOv"); if (ov) ov.style.display = "none"; try { anLoadBadge(); } catch (_e) {} }
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
      try { anLoadBadge(); } catch (_e) {}
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
  var h = '<div class="an-top"><span class="tit">Análisis Productivo</span>' +
          (_an.tanda ? '<button onclick="anVolver()">← Tandas</button>' : '') +
          '<span class="sp"></span><button onclick="anCerrar()">Cerrar</button></div>';
  if (!_an.tanda) {
    var c = function (n, t) { return '<span class="chip' + (_an.dias === n ? ' on' : '') + '" onclick="anDias(' + n + ')">' + t + '</span>'; };
    var f = function (k, t) { return '<span class="chip' + (_an.filtro === k ? ' on' : '') + '" onclick="anFiltro(\'' + k + '\')">' + t + '</span>'; };
    h += '<div class="an-bar">' + c(7, "7 d") + c(14, "14 d") + c(30, "30 d") + c(60, "60 d") +
         '<span class="an-sep"></span>' + f("todas", "Todas") + f("avisos", "Con avisos") + f("marcadas", "Marcadas") +
         '<input id="anQ" placeholder="Buscar tanda" value="' + _anEsc(_an.q) + '" oninput="anBuscar(this.value)" style="width:128px">' +
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
  var fase = function (f, rot) {
    if (!f) return '';
    return '<div class="l"><span class="q">' + rot + '</span>' +
      '<b class="r" style="color:' + _anCol(f.indice) + '">' + _anPct(f.indice) + '</b>' +
      '<span>' + _anEsc(f.nombre || f.legajo) + ' · ' + _anMin(f.real_min) + ' de ' + _anMin(f.esperado_min) + '</span></div>';
  };
  var h = '';
  t.forEach(function (x) {
    var al = Number(x.alerta) || 0;
    h += '<div class="an-t" onclick="anAbrir(\'' + _anEsc(x.tanda) + '\')">' +
      '<div><div class="cod">' + _anEsc(x.tanda) + '</div>' +
      '<div class="d">' + _anDia(x.dia) + ' · ' + _anN(x.m3, 3) + ' m³</div></div>' +
      '<div class="f">' + _anMarcaChip(x.tanda) + (al ? '<span class="al">' + al + ' avisos</span>' : '') + '</div>' +
      '<div class="fases">' + (fase(x.pick, "Pick") || '') + (fase(x.arm, "Arm") || '') +
      (!x.pick && !x.arm ? '<div class="l"><span>Sin picking ni armado medidos</span></div>' : '') + '</div></div>';
  });
  return h;
}

function _anMarcaChip(tanda) {
  var m = _an.marcas[tanda]; if (!m) return "";
  return m.estado === "anomala"
    ? '<span class="mk mk-a" title="' + _anEsc(m.nota || "") + '">Anómala</span>'
    : '<span class="mk mk-r" title="' + _anEsc(m.nota || "") + '">Revisada</span>';
}

/* El VEREDICTO en una línea: lo primero que se lee. Dice qué hacer, no repite los
   números que el bloque de abajo ya muestra en grande. */
function _anVeredicto(d) {
  var av = d.avisos || [];
  var altas = av.filter(function (x) { return x.sev === "alta"; }).length;
  if (altas) return { sev: "alta", txt: altas === 1 ? "1 hallazgo fuerte: mirar de cerca" : altas + " hallazgos fuertes: mirar de cerca" };
  var medias = av.filter(function (x) { return x.sev === "media"; }).length;
  if (medias) return { sev: "media", txt: medias === 1 ? "1 cosa para mirar" : medias + " cosas para mirar" };
  if (av.length) return { sev: "ok", txt: "Nada grave" };
  return { sev: "ok", txt: "Sin hallazgos" };
}

function _anKpi(valor, rotulo, color) {
  return '<div><b' + (color ? ' style="color:' + color + '"' : '') + '>' + valor + '</b><span>' + rotulo + '</span></div>';
}

/* El bloque grande de una fase: el rendimiento es EL dato, el resto lo acompaña. */
function _anHeroFase(f, esPick) {
  if (!f) return '<div class="an-fase"><div class="q">' + (esPick ? "Picking" : "Armado") +
    '</div><div class="big" style="color:#cbd5e1">—</div><div class="who">Todavía sin terminar</div></div>';
  var g = Number(f.grado) || 0;
  return '<div class="an-fase"><div class="q">' + (esPick ? "Picking" : "Armado") + '</div>' +
    '<div class="big" style="color:' + _anCol(f.indice) + '">' + _anPct(f.indice) + '</div>' +
    '<div class="cmp">' + _anMin(f.real_min) + ' · esperado ' + _anMin(f.esperado_min) + '</div>' +
    '<div class="who">' + _anEsc(f.nombre || f.legajo) + ' · ' +
      _anHora(esPick ? f.ep : f.ap) + '–' + _anHora(esPick ? f.tp : f.tap) + '</div>' +
    '<div class="tags"><span class="tag' + (g >= 9 ? ' d3' : g >= 6 ? ' d2' : '') + '">' +
      _anEsc(f.nivel || "—") + ' ' + (g || "?") + '/10</span>' +
    '<span class="tag">' + _anN(f.m3_h, 2) + ' m³/h</span>' +
    '<span class="tag">' + _anN(f.cajas_h, 0) + ' cajas/h</span>' +
    (esPick ? '<span class="tag">' + _anSeg(f.seg_linea) + '/código</span>'
            : '<span class="tag">' + _anN(f.nps, 0) + ' pedidos</span>') + '</div></div>';
}

/* El detalle de una fase va PLEGADO: no es lo que se mira primero. */
function _anFaseHtml(f, esPick) {
  if (!f) return '';
  var h = '<details><summary>' + (esPick ? 'Picking' : 'Armado') + ' — detalle' +
    '<span class="n">' + _anEsc(f.nombre || f.legajo) + '</span></summary><div class="an-in">';
  h += '<div class="an-kpi">' +
    _anKpi(_anPct(f.indice), "rendimiento", _anCol(f.indice)) +
    _anKpi(_anMin(f.esperado_min), "esperado") +
    _anKpi(_anMin(f.real_min), "real") +
    _anKpi(_anEsc(f.nivel || "—") + " " + (f.grado || "?") + "/10", "dificultad") +
    _anKpi(_anN(f.m3_h, 2), "m³ por hora") +
    _anKpi(_anN(f.cajas_h, 0), "cajas por hora") +
    (esPick ? _anKpi(_anSeg(f.seg_linea), "por código") : _anKpi(_anN(f.nps, 0), "pedidos")) +
    '</div>';
  h += '<div class="an-kv">Punta a punta <b>' + _anMin(f.bruto_min) + '</b> · pausas <b>' + _anMin(f.pausa_min) + '</b>' +
    (esPick ? ' · huecos de +5 min <b>' + _anMin(f.huecos_min) + '</b>' : '') +
    ' · cola <b>' + _anMin(f.cola_min) + '</b>' +
    (f.est_ini_min != null ? ' · estimado antes de empezar <b>' + _anMin(f.est_ini_min) + '</b>' : '') + '</div>';
  if (esPick) h += '<div class="an-kv">' + _anN(f.lineas, 0) + ' códigos · ' + _anN(f.cajas, 0) + ' cajas · ' +
    _anN(f.paradas, 0) + ' paradas · ' + _anN(f.esc, 0) + ' con escalera' +
    (Number(f.n_mx) ? ' · ' + _anN(f.n_mx, 0) + ' sin stock en góndola al empezar' : '') +
    (Number(f.n_f) ? ' · ' + _anN(f.n_f, 0) + ' sin celda en el Mapa' : '') + '</div>';
  if (f.prom_operario != null || f.prom_grado != null)
    h += '<div class="an-kv">' +
      (f.prom_operario != null ? 'Este operario viene en <b>' + _anPct(f.prom_operario) + '</b> en sus últimas tandas. ' : '') +
      (f.prom_grado != null ? 'El depósito en tandas de esta dificultad: <b>' + _anPct(f.prom_grado) + '</b>.' : '') + '</div>';
  return h + '</div></details>';
}

function _anGlosarioHtml(d) {
  return '<details><summary>Cómo se leen estos números</summary><div class="an-in an-gl">' +
    '<b>Rendimiento</b>: lo que tendría que haber tardado por su dificultad ÷ lo que tardó. 100 % = llegó al ritmo.<br>' +
    '<b>Esperado</b>: el tamaño de la tanda según el esquema de dificultad (códigos, cajas, paradas, alturas).<br>' +
    '<b>Real</b>: de que tomó la tanda a que la cerró, menos pausas declaradas y huecos de más de 5 minutos, más la cola.<br>' +
    '<b>Desde el anterior</b>: lo que pasó entre que confirmó el código de arriba y éste.<br>' +
    '<b>Normal del código</b>: lo que tarda ese código habitualmente (mediana de 120 días, con sus cajas).<br>' +
    '<b>Frente a la góndola</b>: de que la pantalla mostró el código a que lo confirmó. Ésa es la que mide trabajo de verdad.<br>' +
    '<b>s por caja</b>: sale del momento en que se tocó OK, no de cuándo se levantó la caja. Un número chico solo no prueba nada.' +
    (d.nota_paso ? '<br><b>Ojo</b>: ' + _anEsc(d.nota_paso) : '') + '</div></details>';
}

function _anTablaHtml(L) {
  var h = '<details open><summary>Código por código<span class="n">' + L.length + '</span></summary>' +
    '<div class="an-tblwrap"><table><thead><tr>' +
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
  return h + '</tbody></table></div></details>';
}

function _anDetalleHtml() {
  if (_an.detErr) return '<div class="err">' + _anEsc(_an.detErr) + '</div>';
  if (_an.detCargando || !_an.det) return '<div class="msg">Calculando…</div>';
  var d = _an.det, cab = d.cabecera || {};
  var sub = [_anN(cab.m3, 3) + " m³", (cab.clientes || []).join(" · "), cab.zona,
             (cab.nps || []).join(" · "), cab.fecha_entrega ? "entrega " + _anDia(cab.fecha_entrega) : ""]
            .filter(function (x) { return x; }).join(" · ");
  var h = '<div class="an-hd"><div class="cod">' + _anEsc(d.tanda) + '</div>' +
          '<div class="sub">' + _anEsc(sub) + '</div></div>';

  // Estado + acciones: una sola fila. El veredicto manda; marcar está al lado.
  var v = _anVeredicto(d), mk = _an.marcas[d.tanda] || null;
  h += '<div class="an-state ' + v.sev + '">' +
    '<span class="v">' + (mk ? (mk.estado === "anomala" ? "Marcada ANÓMALA" : "Marcada revisada") : v.txt) + '</span>' +
    (mk && mk.nota ? '<span class="nota">' + _anEsc(mk.nota) + '</span>' : '') +
    (mk ? '<span class="nota">' + v.txt + '</span>' : '') +
    '<button class="an-mk-b a" onclick="anMarcar(\'anomala\')">Anómala</button>' +
    '<button class="an-mk-b r" onclick="anMarcar(\'revisada\')">Revisada</button>' +
    (mk ? '<button class="an-mk-b" onclick="anMarcar(\'sin\')">Sacar marca</button>' : '') +
    '</div>';

  // El dato principal: rendimiento de cada fase, grande.
  h += '<div class="an-hero">' + _anHeroFase(d.picking, true) + _anHeroFase(d.armado, false) + '</div>';

  // Hallazgos: una línea cada uno, con punto de color. Sin título cuando no hay nada que decir.
  var av = (d.avisos || []).slice(0, 8);
  if (av.length) av.forEach(function (a) {
    h += '<div class="an-av ' + _anEsc(a.sev) + '"><span class="dot"></span><span>' + _anEsc(_anTxt(a.texto)) + '</span></div>';
  });
  if ((d.avisos || []).length > 8)
    h += '<div class="an-av baja"><span class="dot"></span><span>y ' + ((d.avisos || []).length - 8) + ' más, de menor peso</span></div>';

  h += _anFaseHtml(d.picking, true);
  h += _anFaseHtml(d.armado, false);
  if ((d.lineas || []).length) h += _anTablaHtml(d.lineas);
  h += _anGlosarioHtml(d);
  return h;
}

/* v29.72 (Luis, D4): el badge = tandas con avisos DUROS que nadie marcó todavía (ni anómala ni
   revisada), de los últimos 14 días. Se apaga marcándolas. Una lectura rota NO lo apaga: lo deja
   como estaba (un 0 que no es un 0 real es peor que no mostrar nada). */
function anLoadBadge(legajo) {
  var leg = legajo || _an.legajo ||
            (typeof window.gvLegajoActual === "function" ? window.gvLegajoActual() : null) || null;
  return _anRpc("gv_analisis_badge", { p_dias: 14, p_legajo: leg }).then(function (r) {
    if (!r || r.error || !r.data) return;
    var n = Number(r.data.pendientes) || 0, av = Number(r.data.con_aviso) || 0;
    [document.getElementById("anBadge"), document.getElementById("anBadgeOp")].forEach(function (b) {
      if (!b) return;
      if (!(n > 0)) { b.style.display = "none"; return; }
      b.style.display = ""; b.textContent = n;
      b.title = n + " tanda(s) de los últimos 14 días con avisos y sin revisar (de " + av + " con avisos)";
    });
  });
}

/* El botón en la botonera del operario: sólo para los legajos habilitados. */
function anMostrarBotonOperario(legajo) {
  var b = document.getElementById("btnAnalisisOp");
  if (!b) return;
  b.style.display = "none";
  if (!legajo) return;
  _anRpc("gv_analisis_acceso_ok", { p_legajo: String(legajo) }).then(function (r) {
    if (r && !r.error && r.data === true) {
      b.style.display = ""; b.setAttribute("data-legajo", String(legajo));
      try { anLoadBadge(String(legajo)); } catch (_e) {}
    }
  });
}
