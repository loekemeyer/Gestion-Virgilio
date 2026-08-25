/**
 * Módulo Pasaje de Papeles
 * Lista toda la documentación registrada en Pasaje_Papeles (Virgilio).
 * v4.0 - Dos secciones colapsables: Pendiente / Enviada + timer + checkbox
 */

let _ppState = {
  data: [],
  loading: false,
  timerInterval: null,
  collapsed: { pendiente: false, enviada: true, recibida: true } // enviada y recibida arrancan colapsadas
};

/* Helper: headers para Supabase REST con anon key */
function _ppHeaders(extra) {
  var h = { apikey: SUPABASE_KEY, Authorization: 'Bearer ' + SUPABASE_KEY, 'Content-Type': 'application/json' };
  if (extra) Object.keys(extra).forEach(function (k) { h[k] = extra[k]; });
  return h;
}

/**
 * Abre el modal de Pasaje de Papeles
 */
function openPasajePapeles() {
  var modal = document.getElementById('pasajePapelesModal');
  if (!modal) return;
  modal.classList.add('show');
  ppLoadData();
}

/**
 * Cierra el modal de Pasaje de Papeles
 */
function closePasajePapeles() {
  var modal = document.getElementById('pasajePapelesModal');
  if (!modal) return;
  modal.classList.remove('show');
  _ppStopTimer();
}

/** Arranca el timer que actualiza los relojes cada segundo */
function _ppStartTimer() {
  _ppStopTimer();
  _ppState.timerInterval = setInterval(_ppTickTimers, 1000);
}

/** Para el timer */
function _ppStopTimer() {
  if (_ppState.timerInterval) {
    clearInterval(_ppState.timerInterval);
    _ppState.timerInterval = null;
  }
}

/** Actualiza todos los <span> con clase pp-timer */
function _ppTickTimers() {
  var spans = document.querySelectorAll('.pp-timer[data-ts]');
  var now = Date.now();
  spans.forEach(function (sp) {
    var ts = parseInt(sp.getAttribute('data-ts'), 10);
    if (!ts) return;
    sp.textContent = _ppFormatElapsed(now - ts);
  });
}

/**
 * Formatea milisegundos a "XD XH XM XS"
 */
function _ppFormatElapsed(ms) {
  if (ms < 0) ms = 0;
  var totalSec = Math.floor(ms / 1000);
  var d = Math.floor(totalSec / 86400);
  var h = Math.floor((totalSec % 86400) / 3600);
  var m = Math.floor((totalSec % 3600) / 60);
  var s = totalSec % 60;
  var parts = [];
  if (d > 0) parts.push(d + 'D');
  if (h > 0 || d > 0) parts.push(h + 'H');
  if (m > 0 || h > 0 || d > 0) parts.push(m + 'M');
  parts.push(s + 'S');
  return parts.join(' ');
}

/**
 * Carga TODOS los documentos de Pasaje_Papeles y renderiza
 */
async function ppLoadData() {
  if (_ppState.loading) return;
  _ppState.loading = true;

  var container = document.getElementById('ppDocList');
  if (container) container.innerHTML = '<div class="pp-empty">Cargando documentación…</div>';

  try {
    // (v4.7 traía acá los remitos de VENTA/RR vía sync_pasaje_rr; se quitó por pedido del usuario.)
    // v4.2 — dos consultas: TODOS los pendientes (paginado, nunca se caen del corte
    // aunque sean viejos) + los últimos 500 enviados. Antes un solo limit=500 mezclado
    // podía dejar un pendiente viejo fuera de la lista aunque el badge lo contara.
    var res = await Promise.all([
      supaFetchAllSafe(SUPABASE_URL + '/rest/v1/Pasaje_Papeles', 'enviado=eq.false&order=created_at.desc&select=*'),
      fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?enviado=eq.true&order=created_at.desc&limit=500&select=*', {
        headers: _ppHeaders(), cache: 'no-store'
      }).then(function (r) { return r.ok ? r.json() : []; })
    ]);
    _ppState.data = (res[0] || []).concat(res[1] || []);
  } catch (e) {
    console.error('ppLoadData error:', e);
    _ppState.data = [];
  }

  ppRenderList();
  _ppState.loading = false;
}

/**
 * Formatea fecha ISO a legible
 */
function ppFormatDate(dateStr) {
  if (!dateStr) return '—';
  // Fecha "pelada" (YYYY-MM-DD, sin hora): formatear con las partes tal cual.
  // Si se la pasa a new Date() se interpreta como medianoche UTC y al mostrarla
  // en hora Argentina (UTC-3) retrocede un día → mostraba el remito/factura un
  // día antes que la fecha real cargada.
  var d = String(dateStr).match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (d) return d[3] + '/' + d[2] + '/' + d[1];
  try {
    return new Date(dateStr).toLocaleDateString('es-AR', {
      timeZone: 'America/Argentina/Buenos_Aires',
      day: '2-digit', month: '2-digit', year: 'numeric'
    });
  } catch (e) { return dateStr; }
}

/** Formatea un timestamp a "DD/MM/AAAA HH:MM" (hora Argentina). */
function ppFormatDateTime(ts) {
  if (!ts) return '—';
  try {
    return new Date(ts).toLocaleString('es-AR', {
      timeZone: 'America/Argentina/Buenos_Aires',
      day: '2-digit', month: '2-digit', year: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: false
    }).replace(',', '');
  } catch (e) { return String(ts); }
}

/** Toggle de sección colapsable */
function ppToggleSection(section) {
  _ppState.collapsed[section] = !_ppState.collapsed[section];
  var body = document.getElementById('ppSec_' + section);
  var arrow = document.getElementById('ppArrow_' + section);
  if (body) body.style.display = _ppState.collapsed[section] ? 'none' : '';
  if (arrow) arrow.textContent = _ppState.collapsed[section] ? '▶' : '▼';
}

/**
 * Genera el HTML de una sección colapsable con header y tabla
 */
// v4.7 — Encabezado de RESPONSABILIDAD (agrupa sus 2 módulos: Pendiente + Enviada).
function _ppGroupHeader(title, sub) {
  return '<div style="margin:4px 0 10px;padding:11px 15px;background:linear-gradient(90deg,#1e293b,#334155);' +
    'color:#fff;border-radius:10px;display:flex;align-items:center;gap:10px;box-shadow:0 2px 8px rgba(2,6,23,.18);">' +
    '<span style="font-weight:800;font-size:16px;letter-spacing:.02em;">' + title + '</span>' +
    (sub ? '<span style="margin-left:auto;font-weight:600;font-size:12.5px;opacity:.85;">' + sub + '</span>' : '') +
    '</div>';
}
// v4.7 — `kind` ('pendiente'|'enviada') decide el comportamiento (color, timer, columnas de
// confirmación); `key` es el id único de colapso (para poder repetir Pendiente/Enviada por
// responsabilidad — Virgilio y Alan). 'enviada' agrupa enviados + confirmados (el estado
// "Recibido el…" se ve dentro de cada fila).
function _ppBuildSection(key, kind, icon, title, rows, showTimer) {
  var collapsed = _ppState.collapsed[key];
  var count = rows.length;
  var esPend = (kind === 'pendiente');
  var headerColor = esPend ? '#dc2626' : '#16a34a';
  var esEnviada = (kind === 'enviada');

  var html = '<div style="margin-bottom:16px;">';

  // Header colapsable
  html += '<div onclick="ppToggleSection(\'' + key + '\')" style="display:flex;align-items:center;gap:8px;padding:10px 14px;' +
    'background:' + (esPend ? '#fef2f2' : '#f0fdf4') + ';border:1px solid ' + (esPend ? '#fecaca' : '#bbf7d0') + ';' +
    'border-radius:8px;cursor:pointer;user-select:none;">' +
    '<span id="ppArrow_' + key + '" style="font-size:12px;color:#64748b;width:14px;">' + (collapsed ? '▶' : '▼') + '</span>' +
    '<span style="font-size:16px;">' + icon + '</span>' +
    '<span style="font-weight:700;font-size:15px;color:#0f172a;">' + title + '</span>' +
    '<span style="margin-left:auto;background:' + headerColor + ';color:#fff;font-size:12px;font-weight:700;' +
    'padding:2px 8px;border-radius:10px;min-width:20px;text-align:center;">' + count + '</span>' +
    '</div>';

  // Cuerpo (tabla)
  html += '<div id="ppSec_' + key + '" style="' + (collapsed ? 'display:none;' : '') + 'margin-top:6px;">';

  if (!count) {
    html += '<div style="padding:12px 14px;color:#94a3b8;font-size:14px;font-style:italic;">' +
      (esPend ? 'Sin documentación pendiente' : 'Sin documentación enviada') + '</div>';
  } else {
    html += '<div class="pp-tblwrap"><table class="pp-tbl"><thead><tr>' +
      '<th>Fecha DDJJ</th><th>Tipo</th><th>N° Remito</th><th>N° Factura</th><th>Razón Social</th><th>Contenido</th>';
    if (showTimer) html += '<th>Tiempo sin enviar</th>';
    // v4.1 — demora entre la fecha del documento y cuándo se cargó al sistema + carpeta destino
    html += '<th title="Cuánto tardó en cargarse al sistema desde la fecha del documento">Demora carga</th>';
    if (esEnviada) html += '<th>Enviado</th>';
    if (esEnviada) html += '<th title="Carpeta 1: Rto+Fc de proveedores · Carpeta 2: solo remito o solo factura · Carpeta 3: talleristas">Carpeta</th>';
    if (esEnviada) html += '<th>Confirmar recepción</th>';
    if (!esEnviada) html += '<th>Enviado</th>';
    html += '</tr></thead><tbody>';

    rows.forEach(function (row) {
      html += _ppBuildRow(row, showTimer, esEnviada);
    });

    html += '</tbody></table></div>';
  }

  html += '</div></div>';
  return html;
}

/**
 * v4.1 — Demora entre la fecha del documento (remito o factura, la más vieja) y
 * cuándo se cargó al sistema (created_at). La fecha del doc no tiene hora → se
 * toma 00:00 hora Argentina. Verde <24h · ámbar 1-2 días · rojo >2 días.
 */
function _ppDemoraCargaHtml(row) {
  var base = row.fecha_remito || row.fecha_factura || row.fecha_emision;
  if (!base || !row.created_at) return '<span style="color:#94a3b8;">—</span>';
  var m = String(base).match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return '<span style="color:#94a3b8;">—</span>';
  var t0 = new Date(m[1] + '-' + m[2] + '-' + m[3] + 'T00:00:00-03:00').getTime();
  var ms = new Date(row.created_at).getTime() - t0;
  if (isNaN(ms) || ms < 0) ms = 0;
  var totalH = Math.floor(ms / 3600000);
  var d = Math.floor(totalH / 24), h = totalH % 24;
  var txt = d > 0 ? d + 'd ' + h + 'h' : h + 'h';
  var col = d >= 2 ? '#dc2626' : (d >= 1 ? '#b45309' : '#16a34a');
  return '<span style="font-weight:800;color:' + col + ';font-variant-numeric:tabular-nums;">' + txt + '</span>';
}

/**
 * Genera el HTML de una fila
 */
function _ppBuildRow(row, showTimer, showConfirm) {
  var tipoLabel = row.tipo_documento === 'ambos' ? 'Rto + Fc'
    : row.tipo_documento === 'remito' ? 'Remito'
    : row.tipo_documento === 'factura' ? 'Factura'
    : (row.tipo_documento || '—');

  var nroRto = row.numero_remito
    ? row.numero_remito + (row.fecha_remito ? '<br><small>' + ppFormatDate(row.fecha_remito) + '</small>' : '')
    : '—';
  var nroFc = row.numero_factura
    ? row.numero_factura + (row.fecha_factura ? '<br><small>' + ppFormatDate(row.fecha_factura) + '</small>' : '')
    : '—';

  var contenido = row.tipo_contenido === 'mercaderia' ? 'Mercadería'
    : row.tipo_contenido === 'insumo' ? 'Insumo'
    : (row.tipo_contenido || '—');

  var enviado = !!row.enviado;
  var rowId = row.id;

  // Checkbox
  var checkCell = '<label style="display:flex;align-items:center;justify-content:center;cursor:pointer;margin:0;">' +
    '<input type="checkbox" ' + (enviado ? 'checked' : '') +
    ' onchange="ppToggleEnviado(' + rowId + ', this.checked)" ' +
    'style="width:20px;height:20px;cursor:pointer;accent-color:#16a34a;">' +
    '</label>';

  // v4.8 — código del proveedor/tallerista (remitos de recepción) como chip antes del nombre.
  var proveedor = (row.cod_proveedor
      ? '<span title="Código de proveedor" style="display:inline-block;background:#eef2ff;border:1px solid #c7d2fe;color:#3730a3;border-radius:6px;padding:0 6px;font-weight:800;font-size:11.5px;margin-right:6px;font-variant-numeric:tabular-nums;">' + row.cod_proveedor + '</span>'
      : '') + (row.razon_social || '—');
  if (row.cuit) {
    proveedor += '<br><small>' + row.cuit + '</small>';
  }

  var html = '<tr data-ppid="' + rowId + '">' +
    '<td>' + ppFormatDate(row.created_at) + '</td>' +
    '<td>' + tipoLabel + '</td>' +
    '<td>' + nroRto + '</td>' +
    '<td>' + nroFc + '</td>' +
    '<td>' + proveedor + '</td>' +
    '<td>' + contenido + '</td>';

  if (showTimer) {
    var tsMs = row.created_at ? new Date(row.created_at).getTime() : 0;
    html += '<td style="text-align:center;white-space:nowrap;">' +
      '<span class="pp-timer" data-ts="' + tsMs + '" style="font-variant-numeric:tabular-nums;font-size:13px;color:#dc2626;font-weight:600;">' +
      _ppFormatElapsed(Date.now() - tsMs) + '</span></td>';
  }

  // v4.1 — Demora de carga: fecha del documento (remito/factura, 00:00 AR) → created_at.
  html += '<td style="text-align:center;white-space:nowrap;">' + _ppDemoraCargaHtml(row) + '</td>';

  // Día/hora en que se marcó como enviado (solo sección enviada).
  if (showConfirm) {
    html += '<td style="text-align:center;white-space:nowrap;font-size:12.5px;color:#334155;font-variant-numeric:tabular-nums;">' +
      ppFormatDateTime(row.enviado_en) + '</td>';
  }

  // v4.1 — Carpeta destino (solo sección enviada): la misma lógica del confirm, visible en la tabla.
  if (showConfirm) {
    var carp = _ppGetFolderNumber(row);
    html += '<td style="text-align:center;font-weight:800;color:#1e40af;">' + (carp ? '📁 ' + carp : '—') + '</td>';
  }

  // Columna "Confirmar recepción" solo para enviada
  if (showConfirm) {
    if (row.confirmado) {
      // Ya fue recibido: mostrar fecha de confirmación
      html += '<td style="text-align:center;font-size:13px;color:#16a34a;font-weight:600;">' +
        'Recibido el ' + ppFormatDateTime(row.fecha_confirmacion) + '</td>';
    } else {
      // No recibido aún: mostrar botón
      var btnHtml = '<button data-row-id="' + rowId + '" onclick="ppConfirmarRecepcion(this.getAttribute(' + "'" + 'data-row-id' + "'" + '))" ' +
        'style="padding:6px 12px;border:none;border-radius:6px;background:#0d9488;color:#fff;font-weight:600;cursor:pointer;font-size:13px;">OK?</button>';
      html += '<td style="text-align:center;">' + btnHtml + '</td>';
    }
  }

  if (!showConfirm) html += '<td style="text-align:center;">' + checkCell + '</td>';
  html += '</tr>';
  return html;
}

/**
 * Renderiza las dos secciones colapsables en ppDocList
 */
function ppRenderList() {
  var container = document.getElementById('ppDocList');
  if (!container) return;

  var data = _ppState.data;

  // Lista única (como antes): pendiente de enviar · enviado sin confirmar · recibido (confirmado).
  // (Los remitos de VENTA/RR se sacaron por pedido del usuario — se materializaban con origen='rr'.)
  var pendientes = [];
  var enviados = [];   // enviados pero todavía sin confirmar recepción
  var recibidos = [];  // ya confirmados como recibidos
  data.forEach(function (row) {
    if (!row.enviado) pendientes.push(row);
    else if (row.confirmado) recibidos.push(row);
    else enviados.push(row);
  });

  var html =
    _ppBuildSection('pendiente', 'pendiente', '⏳', 'Documentación pendiente', pendientes, true) +
    _ppBuildSection('enviada', 'enviada', '✅', 'Documentación enviada', enviados, false) +
    _ppBuildSection('recibida', 'enviada', '📥', 'Recibidos (confirmados)', recibidos, false);

  container.innerHTML = html;

  // Badge: lo no confirmado (pendientes de enviar + enviados sin confirmar).
  var sinConfirmar = data.filter(function (r) { return !r.confirmado; }).length;
  _ppUpdateBadge(sinConfirmar);

  if (pendientes.length) _ppStartTimer();
  else _ppStopTimer();
}

/**
 * Marca/desmarca un documento como enviado en Supabase
 */
async function ppToggleEnviado(id, checked) {
  // Actualizar estado local inmediatamente
  var row = _ppState.data.find(function (r) { return r.id === id; });
  var prevEnviadoEn = row ? row.enviado_en : null;
  var nuevoEnviadoEn = checked ? new Date().toISOString() : null;
  if (row) { row.enviado = checked; row.enviado_en = nuevoEnviadoEn; }

  // Re-renderizar completo (la fila cambia de sección)
  ppRenderList();

  // Persistir en Supabase (enviado + día/hora de envío)
  try {
    var res = await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?id=eq.' + id, {
      method: 'PATCH',
      headers: _ppHeaders({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ enviado: checked, enviado_en: nuevoEnviadoEn })
    });
    if (!res.ok) console.warn('ppToggleEnviado HTTP', res.status);
  } catch (e) {
    console.warn('ppToggleEnviado error:', e);
    // Revertir estado local si falló
    if (row) { row.enviado = !checked; row.enviado_en = prevEnviadoEn; }
    ppRenderList();
  }
}

/**
 * Registra documentación recibida en Pasaje_Papeles.
 * Se llama desde recepcion.js (mercadería) y desde index.html (insumos).
 *
 * Si viene con prefill completo (mercadería): graba directo, sin popup.
 * Si viene sin prefill (insumos): muestra popup para capturar datos.
 *
 * @param tipoContenido - 'mercaderia' o 'insumo'
 * @param prefill - { tipoDoc, nroRemito, nroFactura, fechaRemito, fechaFactura, proveedor }
 */
function ppShowCaptureDialog(tipoContenido, prefill) {
  var pf = prefill || {};

  // Si viene con datos completos de mercadería → guardar directo, sin popup
  if (pf.tipoDoc && pf.proveedor) {
    _ppSaveToSupabase(tipoContenido, pf);
    return;
  }

  // Sin prefill (insumos): popup para capturar datos
  _ppShowCapturePopup(tipoContenido, pf);
}

/**
 * Popup para capturar documentación (usado por insumos)
 */
function _ppShowCapturePopup(tipoContenido, pf) {
  var titulo = tipoContenido === 'mercaderia' ? 'Documentación — Mercadería' : 'Documentación — Insumo recibido';
  var provVal = pf.proveedor || '';

  // Estado del popup
  window._ppCapture = { tipoDoc: '', nroRemito: '', nroFactura: '', fechaRemito: '', fechaFactura: '', proveedor: provVal };

  var container = document.createElement('div');
  container.id = 'ppCaptureOverlay';
  container.innerHTML = '<div style="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px;" onclick="if(event.target===this)ppCloseCaptureDialog()">' +
    '<div style="background:#fff;border-radius:12px;padding:24px;max-width:480px;width:100%;box-shadow:0 20px 25px rgba(0,0,0,.15);">' +
    '<h2 style="margin:0 0 16px;font-size:18px;color:#0f172a;">' + titulo + '</h2>' +
    '<div id="ppCapBody"></div>' +
    '</div></div>';
  document.body.appendChild(container);

  _ppCapRenderStep1(tipoContenido);
}

/** Paso 1 del popup: elegir tipo de documento */
function _ppCapRenderStep1(tipoContenido) {
  var body = document.getElementById('ppCapBody');
  if (!body) return;
  var tipos = [
    { key: 'remito', label: '📄 Remito', color: '#4f46e5' },
    { key: 'factura', label: '🧾 Factura', color: '#0d9488' },
    { key: 'remito_factura', label: '📄🧾 Remito y Factura', color: '#1e6bd6' }
  ];
  var html = '<div style="font-size:14px;font-weight:700;color:#475569;margin-bottom:12px;">¿Qué documentación recibís?</div>';
  tipos.forEach(function (t) {
    html += '<button onclick="window._ppCapture.tipoDoc=\'' + t.key + '\';_ppCapRenderStep2(\'' + tipoContenido + '\')" style="width:100%;padding:16px;margin-bottom:8px;border:none;border-radius:10px;background:' + t.color + ';color:#fff;font-size:16px;font-weight:800;cursor:pointer;text-align:left;">' + t.label + '</button>';
  });
  html += '<button onclick="ppCloseCaptureDialog()" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;color:#334155;font-weight:600;cursor:pointer;margin-top:4px;">Cancelar</button>';
  body.innerHTML = html;
}

/** Paso 2 del popup: campos según tipo elegido */
function _ppCapRenderStep2(tipoContenido) {
  var body = document.getElementById('ppCapBody');
  if (!body) return;
  var cap = window._ppCapture;
  var hasR = cap.tipoDoc === 'remito' || cap.tipoDoc === 'remito_factura';
  var hasF = cap.tipoDoc === 'factura' || cap.tipoDoc === 'remito_factura';
  var hoyAR = '';
  try { hoyAR = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Argentina/Buenos_Aires' }); } catch (_e) {}

  var html = '';
  if (hasR) {
    html += '<div style="margin-bottom:12px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">N° de Remito</label><input type="text" inputmode="numeric" id="ppCapNroRemito" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;" value="' + (cap.nroRemito || '') + '"></div>';
    html += '<div style="margin-bottom:12px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Fecha de Remito</label><input type="date" id="ppCapFechaRemito" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;" value="' + (cap.fechaRemito || hoyAR) + '"></div>';
  }
  if (hasF) {
    html += '<div style="margin-bottom:12px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">N° de Factura</label><input type="text" inputmode="numeric" id="ppCapNroFactura" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;" value="' + (cap.nroFactura || '') + '"></div>';
    html += '<div style="margin-bottom:12px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Fecha de Factura</label><input type="date" id="ppCapFechaFactura" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;" value="' + (cap.fechaFactura || hoyAR) + '"></div>';
  }
  html += '<div style="margin-bottom:14px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Proveedor / Origen</label><input type="text" id="ppCapProveedor" placeholder="Nombre" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;" value="' + (cap.proveedor || '') + '"></div>';
  html += '<div style="display:flex;gap:10px;justify-content:flex-end;">' +
    '<button onclick="_ppCapRenderStep1(\'' + tipoContenido + '\')" style="padding:10px 20px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;color:#334155;font-weight:600;cursor:pointer;">‹ Atrás</button>' +
    '<button onclick="_ppCapSave(\'' + tipoContenido + '\')" style="padding:10px 20px;border:none;border-radius:8px;background:#1e6bd6;color:#fff;font-weight:600;cursor:pointer;">Guardar</button>' +
    '</div>';
  body.innerHTML = html;
}

/** Guardar desde el popup */
function _ppCapSave(tipoContenido) {
  var cap = window._ppCapture;
  var hasR = cap.tipoDoc === 'remito' || cap.tipoDoc === 'remito_factura';
  var hasF = cap.tipoDoc === 'factura' || cap.tipoDoc === 'remito_factura';

  // Leer valores del DOM
  if (hasR) {
    var elNR = document.getElementById('ppCapNroRemito');
    var elFR = document.getElementById('ppCapFechaRemito');
    cap.nroRemito = elNR ? elNR.value.replace(/\D/g, '') : '';
    cap.fechaRemito = elFR ? elFR.value : '';
  }
  if (hasF) {
    var elNF = document.getElementById('ppCapNroFactura');
    var elFF = document.getElementById('ppCapFechaFactura');
    cap.nroFactura = elNF ? elNF.value.replace(/\D/g, '') : '';
    cap.fechaFactura = elFF ? elFF.value : '';
  }
  var elProv = document.getElementById('ppCapProveedor');
  cap.proveedor = elProv ? elProv.value.trim() : '';

  // Validar campos requeridos
  var ok = true;
  if (hasR && !cap.nroRemito) ok = false;
  if (hasF && !cap.nroFactura) ok = false;
  if (!cap.proveedor) ok = false;
  if (!ok) {
    ['ppCapNroRemito', 'ppCapNroFactura', 'ppCapFechaRemito', 'ppCapFechaFactura', 'ppCapProveedor'].forEach(function (id) {
      var el = document.getElementById(id);
      if (el && !el.value.trim()) el.style.borderColor = '#dc2626';
      else if (el) el.style.borderColor = '#cbd5e1';
    });
    return;
  }

  ppCloseCaptureDialog();
  _ppSaveToSupabase(tipoContenido, cap);
}

/**
 * Cierra el diálogo de captura
 */
function ppCloseCaptureDialog() {
  var overlay = document.getElementById('ppCaptureOverlay');
  if (overlay) overlay.remove();
  window._ppCapture = null;
}

/**
 * Busca el CUIT de un proveedor por razón social.
 * Intenta primero en Proveedores (art terminado), luego en otras fuentes.
 */
async function _ppFetchCuit(razonSocial) {
  if (!razonSocial) return null;
  try {
    var rs = razonSocial.trim();
    // Buscar en Proveedores (art terminado, tiene CUIT)
    var res = await fetch(
      SUPABASE_URL + '/rest/v1/Proveedores?razon_social=ilike.' + encodeURIComponent('%' + rs + '%') + '&select=cuit&limit=1',
      { headers: _ppHeaders(), cache: 'no-store' }
    ).then(function (r) { return r.ok ? r.json() : []; });
    if (res && res[0] && res[0].cuit) return res[0].cuit;

    // Si no encontró en Proveedores, no hay CUIT disponible (talleristas, insumos, etc. no tienen CUIT en el sistema)
    return null;
  } catch (_e) { return null; }
}

/**
 * Graba documentación en Pasaje_Papeles (best-effort, silencioso)
 */
async function _ppSaveToSupabase(tipoContenido, data) {
  try {
    var tipoDocLabel = data.tipoDoc;
    if (tipoDocLabel === 'remito_factura') tipoDocLabel = 'ambos';

    // Buscar CUIT del proveedor (async, no bloquea)
    var cuit = await _ppFetchCuit(data.proveedor);

    var payload = {
      planta: 'virgilio',
      tipo_documento: tipoDocLabel,
      tipo_contenido: tipoContenido,
      razon_social: data.proveedor || null,
      cod_proveedor: data.codProveedor || null,   // v4.8 — código del proveedor/tallerista (recepción)
      numero_remito: data.nroRemito || null,
      numero_factura: data.nroFactura || null,
      fecha_remito: data.fechaRemito || null,
      fecha_factura: data.fechaFactura || null,
      fecha_emision: data.fechaRemito || data.fechaFactura || null,
      legajo_usuario: (typeof legajoInput !== 'undefined' && legajoInput && legajoInput.value) ? legajoInput.value : null,
      enviado: false,
      cuit: cuit
    };

    var res = await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles', {
      method: 'POST',
      headers: _ppHeaders({ Prefer: 'return=minimal' }),
      body: JSON.stringify(payload)
    });
    if (!res.ok) console.warn('ppSave HTTP', res.status);
  } catch (e) {
    console.warn('ppSave error (silencioso):', e);
  }
}

/* Compat: ppSaveDocument redirige a la nueva función */
async function ppSaveDocument(tipoContenido) { _ppCapSave(tipoContenido); }

/**
 * Actualiza el badge del botón "Pasaje de Papeles" en el panel supervisor
 */
function _ppUpdateBadge(pendCount) {
  if (typeof supSetBadge === 'function') {
    supSetBadge('ppBadge', pendCount);
  } else {
    // Fallback manual si supSetBadge no existe
    var b = document.getElementById('ppBadge');
    if (!b) return;
    if (pendCount > 0) {
      b.textContent = String(pendCount);
      b.style.display = '';
      b.className = 'dp-badge';
    } else {
      b.style.display = 'none';
    }
  }
}

/**
 * Carga solo el conteo de pendientes para el badge (sin abrir el modal).
 * Se llama al cargar el panel supervisor.
 */
async function ppLoadBadge() {
  try {
    var res = await fetch(
      SUPABASE_URL + '/rest/v1/Pasaje_Papeles?confirmado=eq.false&select=id',
      { headers: _ppHeaders(), cache: 'no-store' }
    ).then(function (r) { return r.ok ? r.json() : []; });
    _ppUpdateBadge((res || []).length);
  } catch (_e) {}
}

/**
 * Determina si un proveedor es tallerista
 * Por ahora, usa una lista hardcodeada. Puede extenderse con llamada a Supabase.
 */
function _ppEsTallerista(razonSocial) {
  if (!razonSocial) return false;
  var rs = razonSocial.toLowerCase().trim();
  // Lista de talleristas conocidos (se puede expandir)
  var talleristas = ['taller', 'cobertor', 'estampado', 'confeccion', 'costura', 'bordado', 'tejido'];
  return talleristas.some(function (t) { return rs.indexOf(t) >= 0; });
}

/**
 * Determina el número de carpeta (1, 2, o 3) basado en:
 * - Carpeta 1: remitos y facturas de prov (art term + insumos) → tipo_documento === 'ambos'
 * - Carpeta 2: remitos sin factura de prov (art term + insumos) → tipo_documento === 'remito'
 * - Carpeta 3: remitos con/sin factura de talleristas
 */
function _ppGetFolderNumber(row) {
  if (!row) return null;

  // Si es tallerista → Carpeta 3
  if (_ppEsTallerista(row.razon_social)) {
    return 3;
  }

  // Si es proveedor regular:
  // Ambos (remito + factura) → Carpeta 1
  if (row.tipo_documento === 'ambos') {
    return 1;
  }
  // Solo remito → Carpeta 2
  if (row.tipo_documento === 'remito') {
    return 2;
  }
  // Solo factura sin remito → Carpeta 2 (por defecto, ya que no tiene remito)
  if (row.tipo_documento === 'factura') {
    return 2;
  }

  return null;
}

/**
 * Confirma la recepción de un documento
 * Marca confirmado=true y fecha_confirmacion=now, y muestra el número de carpeta
 */
async function ppConfirmarRecepcion(rowId) {
  // Buscar el row en el estado
  var row = _ppState.data.find(function (r) { return r.id === parseInt(rowId, 10); });
  if (!row) {
    alert('Error: Documento no encontrado');
    return;
  }

  if (row.confirmado) {
    alert('Este documento ya fue confirmado como recibido el ' + ppFormatDateTime(row.fecha_confirmacion));
    return;
  }

  // Determinar carpeta
  var folder = _ppGetFolderNumber(row);
  if (!folder) {
    alert('Error: No se pudo determinar la carpeta para este documento');
    return;
  }

  // Confirmar con usuario
  var hoy = new Date().toLocaleDateString('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
    day: '2-digit', month: '2-digit', year: 'numeric'
  });
  var msg = 'Confirmar recepción para documentación enviada el ' + ppFormatDate(row.created_at) + '?\n\n' +
    'Se marcará como:\n' +
    '  Recibido el ' + hoy + '\n' +
    '  Guardar en Carpeta ' + folder;

  if (!confirm(msg)) return;

  // Actualizar estado local
  row.confirmado = true;
  row.fecha_confirmacion = new Date().toISOString();

  // Re-renderizar tabla
  ppRenderList();

  // Persistir en Supabase
  try {
    var res = await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?id=eq.' + rowId, {
      method: 'PATCH',
      headers: _ppHeaders({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ confirmado: true, fecha_confirmacion: row.fecha_confirmacion })
    });
    if (!res.ok) {
      console.warn('ppConfirmarRecepcion HTTP', res.status);
      alert('Aviso: Los datos locales se actualizaron, pero hubo un error al sincronizar con el servidor.');
    } else {
      alert('✓ Recepción confirmada.\nGuardar en Carpeta ' + folder);
    }
  } catch (e) {
    console.warn('ppConfirmarRecepcion error:', e);
    alert('Aviso: Los datos locales se actualizaron, pero hubo un error al sincronizar con el servidor.');
    // Revertir si falla
    row.confirmado = false;
    row.fecha_confirmacion = null;
    ppRenderList();
  }
}

// Exportar globalmente
window.openPasajePapeles = openPasajePapeles;
window.closePasajePapeles = closePasajePapeles;
window.ppLoadData = ppLoadData;
window.ppRenderList = ppRenderList;
window.ppShowCaptureDialog = ppShowCaptureDialog;
window.ppCloseCaptureDialog = ppCloseCaptureDialog;
window.ppSaveDocument = ppSaveDocument;
window.ppToggleEnviado = ppToggleEnviado;
window.ppToggleSection = ppToggleSection;
window.ppLoadBadge = ppLoadBadge;
window.ppConfirmarRecepcion = ppConfirmarRecepcion;
window._ppCapRenderStep1 = _ppCapRenderStep1;
window._ppCapRenderStep2 = _ppCapRenderStep2;
window._ppCapSave = _ppCapSave;
