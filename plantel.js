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
    { k: "pick", tarea: "Picking", m3: Number(s.m3_pick) || 0, ritmo: rp, horas: rp > 0 ? (Number(s.m3_pick) || 0) / rp : null },
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
