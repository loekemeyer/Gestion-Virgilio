/* ============================================================================
   PLANTEL DE LA SEMANA (v29.46) — PPP → solapa «Plantel»
   ----------------------------------------------------------------------------
   Pedido: "cuántas horas necesito para pickear, cuántas para armar y cuántas van
   fijo a otras tareas (carga de camión…), para armar un plantel lógico de una
   semana entera, con las mismas personas, sin pasar los 10 días hábiles".

   Todo lo calcula la base (gv_ppp_plantel, sql/gv_ppp_plantel_v2946.sql):
     · m³ de la semana = el MAYOR entre
         - NO VENCER:   lo programado sin pickear / sin armar cuyo límite de armado
                        (fecha del pedido + meta hábiles − 2 hábiles) cae antes del viernes;
         - NO ACUMULAR: lo que entra por semana (promedio de las últimas N semanas).
     · horas = m³ ÷ m³/h MEDIDO (horas reales de picking / armado de las últimas N
       semanas, GV_Plantel_Dia, que llena un cron cada noche).
     · tareas fijas = promedio por día hábil de carga + remitos y de movimiento
       (guardado, recepción, racks, insumos) × hábiles de la semana.
     · personas = horas ÷ (horas útiles por persona por día × hábiles).
   El front sólo muestra y deja cambiar las horas útiles por persona (no se guarda
   en la base: es por navegador). Una lectura que falla lo DICE.
   Candado: tests/ppp-plantel.cjs.
   ============================================================================ */

var _plantel = { semana: 1, meta: 10, hist: 4, util: null, data: null, err: "", cargando: false, clave: "" };

(function () {
  try {
    var g = JSON.parse(localStorage.getItem("gv_plantel_cfg") || "{}");
    if (g.meta > 0) _plantel.meta = g.meta;
    if (g.hist > 0) _plantel.hist = g.hist;
    if (g.util > 0) _plantel.util = g.util;
  } catch (_e) {}
})();

function _plantelGuardarCfg() {
  try { localStorage.setItem("gv_plantel_cfg", JSON.stringify({ meta: _plantel.meta, hist: _plantel.hist, util: _plantel.util })); } catch (_e) {}
}

function _plN(v, dec) {
  var n = Number(v);
  if (!isFinite(n)) return "—";
  return n.toLocaleString("es-AR", { minimumFractionDigits: dec, maximumFractionDigits: dec });
}
/* horas → H:MM (regla de unidades: los tiempos en hora:minutos, redondeado al minuto) */
function _plHM(h) {
  var n = Number(h);
  if (!isFinite(n)) return "—";
  var m = Math.round(n * 60), hh = Math.floor(m / 60), mm = m % 60;
  return hh + ":" + (mm < 10 ? "0" : "") + mm;
}
function _plDia(iso) {
  try { return (typeof gvDiaTxt === "function") ? gvDiaTxt(iso) : String(iso || ""); } catch (_e) { return String(iso || ""); }
}

function plantelCargar(forzar) {
  var clave = [_plantel.semana, _plantel.hist, _plantel.meta].join("|");
  if (_plantel.cargando) return;
  if (!forzar && _plantel.clave === clave && (_plantel.data || _plantel.err)) return;
  _plantel.cargando = true; _plantel.clave = clave; _plantel.err = "";
  fetch(SUPABASE_URL + "/rest/v1/rpc/gv_ppp_plantel", {
    method: "POST",
    headers: { apikey: SUPABASE_KEY, Authorization: "Bearer " + SUPABASE_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ p_semana: _plantel.semana, p_semanas: _plantel.hist, p_meta: _plantel.meta, p_dias_antes: 2 }),
    cache: "no-store"
  }).then(function (r) {
    if (!r.ok) return r.text().then(function (t) { throw new Error("HTTP " + r.status + " " + String(t || "").slice(0, 160)); });
    return r.json();
  }).then(function (j) {
    if (!j || !j.hist) throw new Error("respuesta vacía");
    _plantel.data = j;
  }).catch(function (e) {
    _plantel.data = null;
    _plantel.err = "No se pudo leer el plantel: " + ((e && e.message) || e) + ". Probá «Actualizar».";
  }).then(function () {
    _plantel.cargando = false;
    if (typeof _pppTab !== "undefined" && _pppTab === "plantel" && typeof pppRenderProg === "function") pppRenderProg();
  });
}

function plantelSemana(s) { _plantel.semana = s; plantelCargar(false); if (typeof pppRenderProg === "function") pppRenderProg(); }
function plantelSet(campo, v) {
  var n = parseFloat(String(v).replace(",", "."));
  if (campo === "util") { _plantel.util = (n > 0 && n <= 12) ? n : null; _plantelGuardarCfg(); if (typeof pppRenderProg === "function") pppRenderProg(); return; }
  if (campo === "meta" && n >= 3 && n <= 30) _plantel.meta = Math.round(n);
  if (campo === "hist" && n >= 1 && n <= 8) _plantel.hist = Math.round(n);
  _plantelGuardarCfg();
  plantelCargar(false);
  if (typeof pppRenderProg === "function") pppRenderProg();
}

/* La cuenta de la semana, pura (la usa la pantalla y el test). */
function plantelCalc(d, utilOverride) {
  var h = d.hist || {}, s = d.semana || {}, hab = Number(d.habiles) || 0;
  var rp = Number(h.ritmo_pick) || 0, ra = Number(h.ritmo_arm) || 0;
  var filas = [
    /* v29.47: la hora de picking la da la base POR DIFICULTAD (horas_pick: lo que vence, con el estimado D17
       de sus tandas × el factor medido; lo que entra, al promedio; el mayor). Sin ese dato, m³ ÷ m³/h. */
    (function () {
      var m3 = Number(s.m3_pick) || 0;
      var hp = (s.horas_pick != null && isFinite(Number(s.horas_pick))) ? Number(s.horas_pick) : (rp > 0 ? m3 / rp : null);
      return { k: "pick", tarea: "Picking", m3: m3, ritmo: (hp > 0 ? m3 / hp : rp), horas: hp, porDif: s.horas_pick != null };
    })(),
    { k: "arm", tarea: "Armado", m3: Number(s.m3_arm) || 0, ritmo: ra, horas: ra > 0 ? (Number(s.m3_arm) || 0) / ra : null },
    { k: "carga", tarea: "Carga camión y remitos", fijo: true, porDia: Number(h.carga_dia) || 0, horas: (Number(h.carga_dia) || 0) * hab },
    { k: "mov", tarea: "Guardado, recepción, racks e insumos", fijo: true, porDia: Number(h.mov_dia) || 0, horas: (Number(h.mov_dia) || 0) * hab }
  ];
  var total = filas.reduce(function (a, f) { return a + (f.horas || 0); }, 0);
  var util = (utilOverride > 0) ? utilOverride : (Number(h.util_persona_dia) || 0);
  var porPersona = util * hab;
  var exacto = porPersona > 0 ? total / porPersona : null;
  filas.sort(function (a, b) { return (b.horas || 0) - (a.horas || 0); });
  return { filas: filas, total: total, util: util, porPersona: porPersona, exacto: exacto,
           personas: exacto == null ? null : Math.ceil(exacto - 1e-9), sinRitmo: !(rp > 0 && ra > 0) };
}

function plantelHtml() {
  plantelCargar(false);
  var P = _plantel, d = P.data;
  var btn = function (s, t) {
    return '<button class="pl-sem' + (P.semana === s ? ' on' : '') + '" onclick="plantelSemana(' + s + ')">' + t + '</button>';
  };
  var css = '<style>' +
    '.pl-wrap{max-width:860px;margin:0 auto;padding:6px 10px 30px;font-size:14px;color:#0f172a;}' +
    '.pl-bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;justify-content:center;margin:4px 0 12px;}' +
    '.pl-wrap button{width:auto;margin:0;padding:7px 12px;font-size:13px;border-radius:9px;cursor:pointer;}' +
    '.pl-sem{background:#eef2ff;color:#3730a3;border:1px solid #c7d2fe;font-weight:700;}' +
    '.pl-sem.on{background:#1e6bd6;color:#fff;border-color:#1e6bd6;}' +
    '.pl-in{display:inline-flex;align-items:center;gap:5px;font-size:12.5px;color:#475569;}' +
    '.pl-in input{width:58px;padding:5px 6px;font-size:13px;text-align:center;border:1px solid #cbd5e1;border-radius:7px;box-sizing:border-box;}' +
    '.pl-tbl{border-collapse:collapse;margin:0 auto 12px;}' +
    '.pl-tbl th,.pl-tbl td{padding:5px 9px;text-align:center;border-bottom:1px solid #e2e8f0;}' +
    '.pl-tbl th{font-size:12px;color:#64748b;line-height:1.15;}' +
    '.pl-tbl td.t{text-align:left;}' +
    '.pl-tbl tr.tot td{font-weight:800;border-top:2px solid #94a3b8;}' +
    '.pl-big{display:flex;justify-content:center;gap:14px;flex-wrap:wrap;margin:6px 0 14px;}' +
    '.pl-card{border:1.5px solid #c7d2fe;background:#eef2ff;border-radius:12px;padding:8px 16px;text-align:center;}' +
    '.pl-card b{display:block;font-size:30px;line-height:1.1;color:#1e3a8a;}' +
    '.pl-card span{font-size:12px;color:#475569;}' +
    '.pl-h{font-size:13px;font-weight:800;color:#334155;text-align:center;margin:10px 0 4px;}' +
    '.pl-nota{font-size:12px;color:#64748b;text-align:center;margin:2px 0;}' +
    '.pl-err{background:#fef2f2;border:1px solid #fca5a5;color:#991b1b;border-radius:10px;padding:10px;text-align:center;margin:10px 0;}' +
    '.pl-roja{color:#b91c1c;font-weight:800;}' +
    '</style>';
  var h = css + '<div class="pl-wrap">';
  h += '<div class="pl-bar">' + btn(0, "Esta semana") + btn(1, "Próxima semana") + btn(2, "En 2 semanas") +
    '<label class="pl-in">Demora máx. <input type="number" min="3" max="30" value="' + P.meta + '" onchange="plantelSet(\'meta\', this.value)"> días hábiles</label>' +
    '<label class="pl-in">Historia <input type="number" min="1" max="8" value="' + P.hist + '" onchange="plantelSet(\'hist\', this.value)"> semanas</label>' +
    '<button onclick="plantelCargar(true)" style="background:#fff;border:1px solid #cbd5e1;color:#334155;">Actualizar</button></div>';

  if (P.err) return h + '<div class="pl-err">' + escapeHtml(P.err) + '</div></div>';
  if (!d) return h + '<div class="pl-nota">Calculando…</div></div>';

  var c = plantelCalc(d, P.util), hi = d.hist || {}, pe = d.pendiente || {}, se = d.semana || {};
  var dias = (d.dias || []).map(function (x) {
    return x.habil ? _plDia(x.dia) : '<span class="pl-roja">' + _plDia(x.dia) + ' no hábil</span>';
  }).join(" · ");
  h += '<div class="pl-nota">' + dias + ' — <b>' + (d.habiles || 0) + ' días hábiles</b>' +
    (P.semana === 0 ? ' (desde hoy)' : '') + '</div>';

  if (!(d.habiles > 0)) return h + '<div class="pl-err">La semana elegida no tiene días hábiles por delante.</div></div>';

  h += '<div class="pl-big">' +
    '<div class="pl-card"><b>' + (c.personas == null ? "—" : c.personas) + '</b><span>personas toda la semana' +
      (c.exacto != null ? ' (' + _plN(c.exacto, 1) + ')' : '') + '</span></div>' +
    '<div class="pl-card"><b>' + _plHM(c.total) + '</b><span>horas de trabajo</span></div>' +
    '<div class="pl-card"><b>' + _plN(hi.ops_dia, 1) + '</b><span>personas por día hoy (últ. ' + P.hist + ' sem.)</span></div>' +
    '</div>';

  h += '<table class="pl-tbl"><thead><tr><th>Tarea</th><th>m³<br>semana</th><th>m³/h<br>medido</th><th>Horas<br>semana</th></tr></thead><tbody>';
  c.filas.forEach(function (f) {
    h += '<tr><td class="t">' + f.tarea + (f.fijo ? ' <span style="color:#64748b;font-size:12px;">(fija: ' + _plHM(f.porDia) + ' por día)</span>' : '') + '</td>' +
      '<td>' + (f.fijo ? '—' : _plN(f.m3, 2)) + '</td>' +
      '<td>' + (f.fijo ? '—' : (f.ritmo > 0 ? _plN(f.ritmo, 2) : '—')) + '</td>' +
      '<td><b>' + (f.horas == null ? '—' : _plHM(f.horas)) + '</b></td></tr>';
  });
  h += '<tr class="tot"><td class="t">Total</td><td colspan="2"></td><td>' + _plHM(c.total) + '</td></tr></tbody></table>';

  h += '<div class="pl-nota">Horas útiles por persona por día: ' +
    '<label class="pl-in"><input type="number" step="0.25" min="1" max="12" value="' + (c.util > 0 ? Math.round(c.util * 100) / 100 : "") + '" onchange="plantelSet(\'util\', this.value)"></label> ' +
    (P.util ? '(cargado a mano · <a href="#" onclick="plantelSet(\'util\', 0);return false;">usar el medido: ' + _plHM(hi.util_persona_dia) + '</a>)' :
      '(medido: lo que se registra en tareas sobre una jornada de ' + _plHM(hi.jornada_persona_dia) + ')') +
    ' × ' + d.habiles + ' hábiles = ' + _plHM(c.porPersona) + ' por persona.</div>';
  if (c.sinRitmo) h += '<div class="pl-err">Falta el ritmo medido de picking o armado en la historia elegida.</div>';

  h += '<div class="pl-h">De dónde salen los m³ de la semana (se toma el mayor)</div>';
  h += '<table class="pl-tbl"><thead><tr><th></th><th>Picking<br>m³</th><th>Armado<br>m³</th></tr></thead><tbody>' +
    '<tr><td class="t">Para que no pase de ' + d.meta + ' días hábiles' +
      (d.habiles_antes > 0 ? ' <span style="color:#64748b;font-size:12px;">(descontado lo que se hace antes, ' + d.habiles_antes + ' hábiles al ritmo de hoy)</span>' : '') + '</td>' +
      '<td>' + _plN(se.oblig_pick, 2) + '</td><td>' + _plN(se.oblig_arm, 2) + '</td></tr>' +
    '<tr><td class="t">Para no acumular: lo que entra (' + _plN(d.demanda_semana, 2) + ' m³ por semana)</td>' +
      '<td>' + _plN(se.no_acumular, 2) + '</td><td>' + _plN(se.no_acumular, 2) + '</td></tr>' +
    '</tbody></table>';
  if (se.horas_pick != null) {
    var _dr = (Number(se.min_m3_est_oblig) > 0 && Number(se.min_m3_est_hist) > 0) ? Number(se.min_m3_est_oblig) / Number(se.min_m3_est_hist) : null;
    h += '<div class="pl-nota"><b>Picking por dificultad</b>: lo que vence lleva ' + _plHM(se.horas_pick_oblig) +
      ' (estimado por tanda: líneas, paradas, alturas y cajas × ' + _plN(se.factor_real, 2) + ', lo que de verdad tarda contra lo estimado)' +
      (_dr ? ' — es ' + (_dr >= 1 ? 'más difícil' : 'más fácil') + ' que el promedio (' + _plN(_dr, 2) + ' veces los minutos por m³)' : '') +
      '. Lo que entra, al promedio: ' + _plHM(se.horas_pick_noacum) + '. Se toma el mayor.</div>';
  }

  h += '<div class="pl-h">Cómo estamos hoy</div>';
  h += '<table class="pl-tbl"><tbody>' +
    '<tr><td class="t">Programado sin pickear / sin armar</td><td>' + _plN(pe.m3_pick, 2) + ' m³ / ' + _plN(pe.m3_arm, 2) + ' m³ · ' + (pe.nps || 0) + ' NP</td></tr>' +
    '<tr><td class="t">Ya pasaron los ' + d.meta + ' días hábiles</td><td' + (pe.nps_vencidas > 0 ? ' class="pl-roja"' : '') + '>' + (pe.nps_vencidas || 0) + ' NP · ' + _plN(pe.m3_vencido, 2) + ' m³</td></tr>' +
    '<tr><td class="t">Pedido pendiente más viejo</td><td' + (pe.habiles_mas_viejo > d.meta ? ' class="pl-roja"' : '') + '>' + (pe.pedido_mas_viejo ? _plDia(pe.pedido_mas_viejo) + ' · ' + pe.habiles_mas_viejo + ' días hábiles' : '—') + '</td></tr>' +
    '<tr><td class="t">Se procesa por día (últ. ' + P.hist + ' sem.)</td><td>' + _plN(hi.m3_dia_pick, 2) + ' m³ pickeo · ' + _plN(hi.m3_dia_arm, 2) + ' m³ armado</td></tr>' +
    '<tr><td class="t">Entra por día</td><td>' + _plN((Number(d.demanda_semana) || 0) / 5, 2) + ' m³</td></tr>' +
    '</tbody></table>';

  var ps = pe.por_semana_limite || [];
  if (ps.length) {
    h += '<div class="pl-h">Lo pendiente, por semana en que vence el armado</div>';
    h += '<table class="pl-tbl"><thead><tr><th>Semana<br>(lunes)</th><th>Sin pickear<br>m³</th><th>Sin armar<br>m³</th></tr></thead><tbody>';
    ps.forEach(function (x) {
      var fin = new Date(String(x.semana) + "T12:00:00"); fin.setDate(fin.getDate() + 4);
      var venc = fin.toISOString().slice(0, 10) < String(d.hoy);   // el viernes de esa semana ya pasó
      h += '<tr' + (venc ? ' class="pl-roja"' : '') + '><td>' + _plDia(x.semana) + (venc ? ' (vencido)' : '') + '</td><td>' + _plN(x.m3_pick, 2) + '</td><td>' + _plN(x.m3_arm, 2) + '</td></tr>';
    });
    h += '</tbody></table>';
  }
  h += '<div class="pl-nota">Horas medidas del ' + _plDia(hi.desde) + ' al ' + _plDia(hi.hasta) + ' (' + (hi.dias || 0) + ' días con gente). ' +
    'No cuenta lo que todavía está en A Programar ni en Cuarentena.</div>';
  return h + '</div>';
}

/* ============================================================================
   RITMO DE PICKING (v29.47, Thomas 12/10, D4) — Monitor → pestaña «Ritmo».
   Por día y por operario: estimado inicial (por dificultad, ANTES de pickear),
   esperado (D17 con lo que de verdad pickeó), real (tiempo pickeando sin pausas ni
   huecos de +5 min) y horas del monitor. Rendimiento = esperado ÷ real: ≥ 100 % llegó.
   Todo lo calcula gv_ritmo_picking (sólo supervisor). El monitor de pared (kiosko)
   no muestra las pestañas, así que esto no lo ven los operarios.
   ============================================================================ */
var _ritmo = { dias: 14, data: null, err: "", cargando: false, abiertos: {} };

function _rtPct(x) { var n = Number(x); return isFinite(n) && n > 0 ? Math.round(n * 100) + " %" : "—"; }
function _rtMin(m) { var n = Number(m); return isFinite(n) && m != null ? _plHM(n / 60) : "—"; }
function _rtCol(x) { var n = Number(x); return !(n > 0) ? "#64748b" : (n >= 1 ? "#15803d" : "#b91c1c"); }

function ritmoCargar() {
  var box = document.getElementById("ritmoContent"); if (!box) return;
  if (_ritmo.cargando) return;
  _ritmo.cargando = true; _ritmo.err = "";
  ritmoRender();
  var sb = window.sb;
  var hoy = new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 10);
  var d0 = new Date(Date.now() - 3 * 3600 * 1000 - (_ritmo.dias - 1) * 86400000).toISOString().slice(0, 10);
  var p = (sb && typeof sb.rpc === "function")
    ? sb.rpc("gv_ritmo_picking", { p_desde: d0, p_hasta: hoy })
    : Promise.resolve({ data: null, error: { message: "sin sesión de supervisor" } });
  Promise.resolve(p).then(function (r) {
    if (!r || r.error) throw new Error((r && r.error && r.error.message) || "sin respuesta");
    if (!r.data || !r.data.total) throw new Error("respuesta vacía");
    _ritmo.data = r.data;
  }).catch(function (e) {
    _ritmo.data = null;
    var m = String((e && e.message) || e);
    _ritmo.err = /SUPERVISOR/.test(m) ? "El ritmo por operario es sólo para supervisores: entrá con tu cuenta." : ("No se pudo leer el ritmo: " + m);
  }).then(function () { _ritmo.cargando = false; ritmoRender(); });
}
function ritmoDias(n) { _ritmo.dias = n; ritmoCargar(); }
function ritmoToggleDia(d) { _ritmo.abiertos[d] = !_ritmo.abiertos[d]; ritmoRender(); }

function ritmoRender() {
  var box = document.getElementById("ritmoContent"); if (!box) return;
  var R = _ritmo, d = R.data;
  var css = '<style>' +
    '#ritmoContent{overflow:auto;}' +
    '.rt-wrap{background:#fff;color:#0f172a;border-radius:10px;padding:10px 12px 16px;max-width:980px;margin:0 auto;font-size:14px;}' +
    '.rt-wrap button{width:auto;margin:0;padding:6px 12px;font-size:13px;border-radius:9px;cursor:pointer;background:#eef2ff;color:#3730a3;border:1px solid #c7d2fe;font-weight:700;}' +
    '.rt-wrap button.on{background:#1e6bd6;color:#fff;border-color:#1e6bd6;}' +
    '.rt-bar{display:flex;gap:8px;justify-content:center;flex-wrap:wrap;margin-bottom:10px;}' +
    '.rt-cards{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-bottom:10px;}' +
    '.rt-card{border:1.5px solid #e2e8f0;border-radius:12px;padding:6px 14px;text-align:center;}' +
    '.rt-card b{display:block;font-size:26px;line-height:1.15;}' +
    '.rt-card span{font-size:12px;color:#475569;}' +
    '.rt-tbl{border-collapse:collapse;margin:0 auto 12px;}' +
    '.rt-tbl th,.rt-tbl td{padding:4px 8px;text-align:center;border-bottom:1px solid #e2e8f0;}' +
    '.rt-tbl th{font-size:12px;color:#64748b;line-height:1.15;}' +
    '.rt-tbl td.t{text-align:left;}' +
    '.rt-tbl tr.dia{cursor:pointer;} .rt-tbl tr.dia:hover{background:#f1f5f9;}' +
    '.rt-tbl tr.sub td{font-size:12.5px;color:#334155;background:#f8fafc;}' +
    '.rt-h{font-size:13px;font-weight:800;color:#334155;text-align:center;margin:8px 0 4px;}' +
    '.rt-nota{font-size:12px;color:#64748b;text-align:center;margin:2px 0;}' +
    '.rt-err{background:#fef2f2;border:1px solid #fca5a5;color:#991b1b;border-radius:10px;padding:10px;text-align:center;}' +
    '</style>';
  var b = function (n, t) { return '<button class="' + (R.dias === n ? 'on' : '') + '" onclick="ritmoDias(' + n + ')">' + t + '</button>'; };
  var h = css + '<div class="rt-wrap">' +
    '<div class="rt-bar">' + b(7, "7 días") + b(14, "14 días") + b(28, "28 días") +
    '<button onclick="ritmoCargar()" style="background:#fff;border-color:#cbd5e1;color:#334155;">Actualizar</button></div>';
  if (R.err) { box.innerHTML = h + '<div class="rt-err">' + escapeHtml(R.err) + '</div></div>'; return; }
  if (!d) { box.innerHTML = h + '<div class="rt-nota">' + (R.cargando ? 'Calculando…' : '') + '</div></div>'; return; }
  var t = d.total || {};
  h += '<div class="rt-cards">' +
    '<div class="rt-card"><b style="color:' + _rtCol(t.indice) + '">' + _rtPct(t.indice) + '</b><span>rendimiento picking<br>(esperado ÷ real)</span></div>' +
    '<div class="rt-card"><b>' + _rtMin(t.esperado_min) + '</b><span>horas esperadas<br>(estimado inicial ' + _rtMin(t.est_ini_min) + ')</span></div>' +
    '<div class="rt-card"><b>' + _rtMin(t.real_min) + '</b><span>horas reales<br>pickeando</span></div>' +
    '<div class="rt-card"><b>' + _rtMin(t.mon_min) + '</b><span>horas de picking<br>del monitor (' + _rtPct(t.indice_mon) + ')</span></div>' +
    '<div class="rt-card"><b style="color:#b45309">' + _rtMin((Number(t.mon_min) || 0) - (Number(t.real_min) || 0)) + '</b><span>pérdida: pausas, huecos<br>y cola (monitor − real)</span></div>' +
    '</div>';
  var ops = d.operarios || [];
  h += '<div class="rt-h">Por operario</div>';
  h += '<table class="rt-tbl"><thead><tr><th>Operario</th><th>Tandas</th><th>Estimado<br>inicial</th><th>Esperado</th><th>Real</th><th>Rend.</th><th>Días que<br>llegó</th><th>Monitor</th><th>Pérdida</th></tr></thead><tbody>';
  ops.forEach(function (o) {
    h += '<tr><td class="t">' + escapeHtml(o.nombre || o.legajo) + '</td><td>' + (o.tandas || 0) + '</td>' +
      '<td>' + _rtMin(o.est_ini_min) + '</td><td>' + _rtMin(o.esperado_min) + '</td><td>' + _rtMin(o.real_min) + '</td>' +
      '<td style="font-weight:800;color:' + _rtCol(o.indice) + '">' + _rtPct(o.indice) + '</td>' +
      '<td>' + (o.dias_medidos ? o.dias_llego + ' de ' + o.dias_medidos : '—') + '</td>' +
      '<td>' + _rtMin(o.mon_min) + '</td><td>' + _rtMin(o.perdida_min) + '</td></tr>';
  });
  if (!ops.length) h += '<tr><td colspan="9">Sin picking en el período.</td></tr>';
  h += '</tbody></table>';
  var filas = d.filas || [];
  h += '<div class="rt-h">Por día <span style="font-weight:600;color:#64748b">(tocá un día para ver los operarios)</span></div>';
  h += '<table class="rt-tbl"><thead><tr><th>Día</th><th>Operarios</th><th>Tandas</th><th>Estimado<br>inicial</th><th>Esperado</th><th>Real</th><th>Rend.</th><th>Monitor</th></tr></thead><tbody>';
  (d.dias || []).forEach(function (x) {
    var k = String(x.dia);
    h += '<tr class="dia" onclick="ritmoToggleDia(\'' + k + '\')"><td class="t">' + (R.abiertos[k] ? '▾ ' : '▸ ') + _plDia(k) + '</td><td>' + (x.ops || 0) + '</td><td>' + (x.tandas || 0) + '</td>' +
      '<td>' + _rtMin(x.est_ini_min) + '</td><td>' + _rtMin(x.esperado_min) + '</td><td>' + _rtMin(x.real_min) + '</td>' +
      '<td style="font-weight:800;color:' + _rtCol(x.indice) + '">' + _rtPct(x.indice) + '</td><td>' + _rtMin(x.mon_min) + '</td></tr>';
    if (R.abiertos[k]) filas.filter(function (f) { return String(f.dia) === k; }).forEach(function (f) {
      h += '<tr class="sub"><td class="t" colspan="2">&nbsp;&nbsp;' + escapeHtml(f.nombre || f.legajo) + '</td><td>' + (f.tandas || 0) + '</td>' +
        '<td>' + _rtMin(f.est_ini_min) + '</td><td>' + _rtMin(f.esperado_min) + '</td><td>' + _rtMin(f.real_min) + '</td>' +
        '<td style="font-weight:800;color:' + _rtCol(f.indice) + '">' + _rtPct(f.indice) + '</td><td>' + _rtMin(f.mon_min) + '</td></tr>';
    });
  });
  h += '</tbody></table>';
  h += '<div class="rt-nota"><b>Estimado inicial</b>: el tiempo que calculó el sistema antes de pickear, por la dificultad de la tanda (líneas, paradas, alturas, cajas). ' +
    '<b>Esperado</b>: la misma cuenta con lo que se pickeó de verdad. <b>Real</b>: el tiempo pickeando, sin pausas ni huecos de más de 5 min. ' +
    '<b>Monitor</b>: todas las horas de picking que registró el monitor. Rendimiento ≥ 100 % = llegó al ritmo esperado.</div>' +
    '<div class="rt-nota">Las tandas pickeadas antes del 12/10 tienen el estimado inicial reconstruido (con el stock de ese día, no el del momento). ' +
    'Una línea de pallet entero (más de 30 cajas) el modelo la cuenta como 30: el estimado se queda corto en esas tandas.</div>';
  box.innerHTML = h + '</div>';
}
