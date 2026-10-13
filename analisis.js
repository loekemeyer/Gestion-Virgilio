/* ============================================================================
   ANÁLISIS PRODUCTIVO POR TANDA (v29.64, pedido de Luis 13/10/2026)
   Rediseño visual v29.81 — es la PANTALLA DE REFERENCIA del sistema de diseño
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
function _anCol(x) { var n = Number(x); return !(n > 0) ? "var(--gv-ink-2)" : (n >= 1 ? "var(--gv-ok)" : "var(--gv-error)"); }
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
    /* Lo genérico (tipografía, color, botón, chip, tabla, details, veredicto, item,
       estados) vive en gv-ui.css. Acá va SÓLO el layout propio de esta pantalla. */
    "#anOv{position:fixed;inset:0;z-index:9650;display:none;flex-direction:column;}",
    /* barra superior */
    "#anOv .an-top{display:flex;align-items:center;gap:var(--gv-sp-4);padding:11px var(--gv-sp-5);",
    "  background:var(--gv-dark);color:#fff;flex-wrap:wrap;}",
    "#anOv .an-top .tit{font-weight:700;font-size:var(--gv-fs-lg);letter-spacing:.2px;}",
    "#anOv .an-top .sp{flex:1;}",
    "#anOv .an-top button{background:rgba(255,255,255,.10);color:#fff;border-color:rgba(255,255,255,.35);}",
    "#anOv .an-bar{display:flex;align-items:center;gap:7px;flex-wrap:wrap;padding:9px var(--gv-sp-5);",
    "  background:var(--gv-surface);border-bottom:1px solid var(--gv-line);font-size:var(--gv-fs-md);}",
    "#anOv .an-bar .an-sep{width:var(--gv-sp-3);}",
    "#anOv .an-body{flex:1;overflow:auto;padding:var(--gv-sp-5) var(--gv-sp-5) var(--gv-sp-8);}",
    "#anOv .an-wrap{max-width:1040px;margin:0 auto;}",
    /* ── lista: una tarjeta por tanda ── */
    "#anOv .an-t{background:var(--gv-surface);border:1px solid var(--gv-line);border-radius:var(--gv-r);",
    "  padding:11px var(--gv-sp-5);margin-bottom:9px;cursor:pointer;display:grid;",
    "  grid-template-columns:1fr auto;gap:var(--gv-sp-4) var(--gv-sp-5);align-items:center;transition:border-color .12s;}",
    "#anOv .an-t:hover{border-color:var(--gv-dark);}",
    "#anOv .an-t .cod{font-size:var(--gv-fs-xl);font-weight:800;letter-spacing:.4px;line-height:1;}",
    "#anOv .an-t .d{font-size:var(--gv-fs-sm);color:var(--gv-ink-2);margin-top:3px;}",
    "#anOv .an-t .f{text-align:right;white-space:nowrap;}",
    "#anOv .an-t .fases{grid-column:1/-1;display:flex;gap:22px;flex-wrap:wrap;",
    "  border-top:1px solid var(--gv-line-soft);padding-top:var(--gv-sp-3);}",
    "#anOv .an-t .l{display:flex;align-items:baseline;gap:7px;font-size:var(--gv-fs-sm);color:var(--gv-ink-2);}",
    "#anOv .an-t .l .r{font-size:var(--gv-fs-lg);font-weight:800;font-variant-numeric:tabular-nums;}",
    /* el rótulo de 4 letras va en mayúscula a propósito: es una etiqueta, no una palabra que leer */
    "#anOv .an-t .l .q{font-size:var(--gv-fs-xs);letter-spacing:.6px;color:var(--gv-ink-2);font-weight:700;text-transform:uppercase;}",
    "#anOv .mk{margin-right:6px;}",
    /* ── detalle ── */
    "#anOv .an-hd{margin:var(--gv-sp-1) 0 var(--gv-sp-4);}",
    "#anOv .an-hd .cod{font-size:var(--gv-fs-2xl);font-weight:800;letter-spacing:.5px;line-height:1.05;}",
    "#anOv .an-hd .sub{font-size:var(--gv-fs-md);color:var(--gv-ink-2);margin-top:var(--gv-sp-2);}",
    "#anOv .gv-state{margin-bottom:var(--gv-sp-4);}",
    "#anOv .an-state-nota{font-size:var(--gv-fs-sm);color:var(--gv-ink-2);font-weight:500;}",
    "#anOv .an-mk-b{font-size:var(--gv-fs-sm);padding:6px var(--gv-sp-4);}",
    "#anOv .an-mk-b.a{border-color:var(--gv-error-line);color:var(--gv-error);}",
    "#anOv .an-mk-b.r{border-color:var(--gv-ok-line);color:var(--gv-ok);}",
    /* el dato principal */
    "#anOv .an-hero{display:grid;grid-template-columns:repeat(auto-fit,minmax(248px,1fr));",
    "  gap:var(--gv-sp-4);margin-bottom:var(--gv-sp-5);}",
    "#anOv .an-fase{background:var(--gv-surface);border:1px solid var(--gv-line);",
    "  border-radius:var(--gv-r);padding:var(--gv-sp-5) var(--gv-sp-5);}",
    "#anOv .an-fase .cmp{font-size:var(--gv-fs-md);color:var(--gv-ink);font-weight:600;}",
    "#anOv .an-fase .who{font-size:var(--gv-fs-md);color:var(--gv-ink-2);margin-top:3px;}",
    "#anOv .an-fase .tags{display:flex;gap:6px;flex-wrap:wrap;margin-top:9px;}",
    "#anOv .an-fase .tag{font-size:var(--gv-fs-sm);color:var(--gv-ink-2);background:var(--gv-surface-2);",
    "  border-radius:var(--gv-r-pill);padding:3px 9px;}",
    "#anOv .an-fase .tag.d3{background:var(--gv-error-bg);color:var(--gv-error);}",
    "#anOv .an-fase .tag.d2{background:var(--gv-warn-bg);color:var(--gv-warn);}",
    /* lo plegado */
    "#anOv .an-in{padding:var(--gv-sp-1) var(--gv-sp-5) var(--gv-sp-5);}",
    "#anOv .an-kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(104px,1fr));",
    "  gap:var(--gv-sp-4) 6px;margin:var(--gv-sp-2) 0 var(--gv-sp-4);}",
    "#anOv .an-kpi div b{display:block;font-size:var(--gv-fs-xl);font-weight:700;line-height:1.15;font-variant-numeric:tabular-nums;}",
    "#anOv .an-kpi div span{display:block;font-size:var(--gv-fs-sm);color:var(--gv-ink-2);margin-top:1px;}",
    "#anOv .an-kv{font-size:var(--gv-fs-sm);color:var(--gv-ink-2);line-height:1.5;}",
    "#anOv .an-kv b{color:var(--gv-ink);font-weight:700;}",
    "#anOv .an-gl{font-size:var(--gv-fs-md);color:var(--gv-ink-2);line-height:1.55;}",
    "#anOv .an-gl b{color:var(--gv-ink);}",
    "@media(max-width:560px){#anOv .an-body{padding:var(--gv-sp-4) 11px var(--gv-sp-8);}",
    "  #anOv .an-fase{padding:var(--gv-sp-4) 13px;}}"
  ].join("\n");
  document.head.appendChild(st);
}

/* ── apertura ─────────────────────────────────────────────────────────────── */
function openAnalisisProductivo(legajo) {
  _anCss();
  var ov = document.getElementById("anOv");
  if (!ov) { ov = document.createElement("div"); ov.id = "anOv"; ov.className = "gv"; document.body.appendChild(ov); }
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
    var c = function (n, t) { return '<span class="gv-chip' + (_an.dias === n ? ' on' : '') + '" onclick="anDias(' + n + ')">' + t + '</span>'; };
    var f = function (k, t) { return '<span class="gv-chip' + (_an.filtro === k ? ' on' : '') + '" onclick="anFiltro(\'' + k + '\')">' + t + '</span>'; };
    h += '<div class="an-bar">' + c(7, "7 d") + c(14, "14 d") + c(30, "30 d") + c(60, "60 d") +
         '<span class="an-sep"></span>' + f("todas", "Todas") + f("avisos", "Con avisos") + f("marcadas", "Marcadas") +
         '<input id="anQ" placeholder="Buscar tanda" value="' + _anEsc(_an.q) + '" oninput="anBuscar(this.value)" style="width:128px">' +
         '<button onclick="_anCargar()">Actualizar</button></div>';
  }
  h += '<div class="an-body"><div class="an-wrap">' + (_an.tanda ? _anDetalleHtml() : _anListaHtml()) + '</div></div>';
  ov.innerHTML = h;
}

function _anListaHtml() {
  if (_an.err) return '<div class="gv-err">' + _anEsc(_an.err) + '</div>';
  if (_an.cargando || !_an.lista) return '<div class="msg">Calculando…</div>';
  var t = (_an.lista.tandas || []).filter(function (x) {
    if (_an.q && String(x.tanda).indexOf(_an.q) < 0) return false;
    if (_an.filtro === "avisos") return (Number(x.alerta) || 0) > 0;
    if (_an.filtro === "marcadas") return !!_an.marcas[x.tanda];
    return true;
  });
  if (!t.length) return '<div class="gv-msg">' + (_an.filtro === "marcadas" ? "Ninguna tanda marcada en el período."
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
      '<div class="f">' + _anMarcaChip(x.tanda) + (al ? '<span class="gv-badge err">' + al + ' avisos</span>' : '') + '</div>' +
      '<div class="fases">' + (fase(x.pick, "Pick") || '') + (fase(x.arm, "Arm") || '') +
      (!x.pick && !x.arm ? '<div class="l"><span>Sin picking ni armado medidos</span></div>' : '') + '</div></div>';
  });
  return h;
}

function _anMarcaChip(tanda) {
  var m = _an.marcas[tanda]; if (!m) return "";
  return m.estado === "anomala"
    ? '<span class="gv-badge err mk" title="' + _anEsc(m.nota || "") + '">Anómala</span>'
    : '<span class="gv-badge ok mk" title="' + _anEsc(m.nota || "") + '">Revisada</span>';
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
  if (!f) return '<div class="an-fase"><div class="gv-label">' + (esPick ? "Picking" : "Armado") +
    '</div><div class="big gv-hero" style="color:var(--gv-muted)">—</div><div class="who">Todavía sin terminar</div></div>';
  var g = Number(f.grado) || 0;
  return '<div class="an-fase"><div class="gv-label">' + (esPick ? "Picking" : "Armado") + '</div>' +
    '<div class="big gv-hero" style="color:' + _anCol(f.indice) + '">' + _anPct(f.indice) + '</div>' +
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
    '<div class="gv-tblwrap"><table class="gv-tbl"><thead><tr>' +
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
      '<td>' + _anN(x.cajas, 0) + (Number(x.pedidas) > Number(x.cajas) ? ' <span style="color:var(--gv-error)">de ' + _anN(x.pedidas, 0) + '</span>' : '') + '</td>' +
      '<td>' + _anSeg(x.seg) + '</td><td>' + _anSeg(x.esp_seg) + '</td>' +
      '<td' + (Number(x.ratio) > 6 ? ' style="color:var(--gv-error);font-weight:800"' : '') + '>' + (x.ratio != null ? _anN(x.ratio, 1) + "×" : "—") + '</td>' +
      '<td' + (x.seg_vista != null && Number(x.seg_vista) < 2 ? ' style="color:var(--gv-error);font-weight:800"' : '') + '>' + _anSeg(x.seg_vista) + '</td>' +
      '<td>' + (x.seg_caja != null ? _anN(x.seg_caja, 1) : "—") + '</td></tr>';
  });
  return h + '</tbody></table></div></details>';
}

function _anDetalleHtml() {
  if (_an.detErr) return '<div class="gv-err">' + _anEsc(_an.detErr) + '</div>';
  if (_an.detCargando || !_an.det) return '<div class="msg">Calculando…</div>';
  var d = _an.det, cab = d.cabecera || {};
  var sub = [_anN(cab.m3, 3) + " m³", (cab.clientes || []).join(" · "), cab.zona,
             (cab.nps || []).join(" · "), cab.fecha_entrega ? "entrega " + _anDia(cab.fecha_entrega) : ""]
            .filter(function (x) { return x; }).join(" · ");
  var h = '<div class="an-hd"><div class="cod">' + _anEsc(d.tanda) + '</div>' +
          '<div class="sub">' + _anEsc(sub) + '</div></div>';

  // Estado + acciones: una sola fila. El veredicto manda; marcar está al lado.
  var v = _anVeredicto(d), mk = _an.marcas[d.tanda] || null;
  h += '<div class="gv-state ' + v.sev + '">' +
    '<span class="v">' + (mk ? (mk.estado === "anomala" ? "Marcada ANÓMALA" : "Marcada revisada") : v.txt) + '</span>' +
    (mk && mk.nota ? '<span class="an-state-nota">' + _anEsc(mk.nota) + '</span>' : '') +
    (mk ? '<span class="an-state-nota">' + v.txt + '</span>' : '') +
    '<button class="an-mk-b a" onclick="anMarcar(\'anomala\')">Anómala</button>' +
    '<button class="an-mk-b r" onclick="anMarcar(\'revisada\')">Revisada</button>' +
    (mk ? '<button class="an-mk-b" onclick="anMarcar(\'sin\')">Sacar marca</button>' : '') +
    '</div>';

  // El dato principal: rendimiento de cada fase, grande.
  h += '<div class="an-hero">' + _anHeroFase(d.picking, true) + _anHeroFase(d.armado, false) + '</div>';

  // Hallazgos: una línea cada uno, con punto de color. Sin título cuando no hay nada que decir.
  var av = (d.avisos || []).slice(0, 8);
  if (av.length) av.forEach(function (a) {
    h += '<div class="gv-item ' + _anEsc(a.sev) + '"><span class="dot"></span><span>' + _anEsc(_anTxt(a.texto)) + '</span></div>';
  });
  if ((d.avisos || []).length > 8)
    h += '<div class="gv-item baja"><span class="dot"></span><span>y ' + ((d.avisos || []).length - 8) + ' más, de menor peso</span></div>';

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
