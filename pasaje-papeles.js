/**
 * Módulo Pasaje de Papeles
 * Gestiona documentación intercambiada entre Virgilio y Cervantes
 * v1.2 - Usa fetch + REST (no depende de sb del scope de initAuth)
 */

let _ppState = {
  activeTab: 'virgilio',
  virgilioData: [],
  cervantesData: [],
  loading: false
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
  const modal = document.getElementById('pasajePapelesModal');
  if (!modal) return;
  modal.classList.add('show');
  ppLoadData();
}

/**
 * Cierra el modal de Pasaje de Papeles
 */
function closePasajePapeles() {
  const modal = document.getElementById('pasajePapelesModal');
  if (!modal) return;
  modal.classList.remove('show');
}

/**
 * Cambia de pestaña
 */
function ppSwitchTab(tab) {
  _ppState.activeTab = tab;
  // Tabs: los botones no tienen data-tab, determinar activo por posición
  var tabs = document.querySelectorAll('#pasajePapelesModal .pp-tab');
  tabs.forEach(function (el) { el.classList.remove('active'); });
  if (tab === 'virgilio' && tabs[0]) tabs[0].classList.add('active');
  if (tab === 'cervantes' && tabs[1]) tabs[1].classList.add('active');
  // Contenido
  var vTab = document.getElementById('ppTabVirgilio');
  var cTab = document.getElementById('ppTabCervantes');
  if (vTab) vTab.style.display = tab === 'virgilio' ? 'block' : 'none';
  if (cTab) cTab.style.display = tab === 'cervantes' ? 'block' : 'none';
}

/**
 * Carga datos de documentación desde Supabase
 */
async function ppLoadData() {
  if (_ppState.loading) return;
  _ppState.loading = true;

  try {
    // Cargar Virgilio (mercadería + insumos recibidos, pendientes de enviar a Cervantes)
    var virRes = await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?planta=eq.virgilio&order=created_at.desc&limit=1000&select=*', {
      headers: _ppHeaders(), cache: 'no-store'
    }).then(function (r) { return r.ok ? r.json() : []; });
    _ppState.virgilioData = virRes || [];

    // Cargar Cervantes (documentación enviada por Virgilio, pendiente de confirmar)
    var cerRes = await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?planta=eq.cervantes&enviado_a_cervantes=eq.true&order=created_at.desc&limit=1000&select=*', {
      headers: _ppHeaders(), cache: 'no-store'
    }).then(function (r) { return r.ok ? r.json() : []; });
    _ppState.cervantesData = cerRes || [];
  } catch (e) {
    console.error('ppLoadData error:', e);
  }

  ppRenderVirgilio();
  ppRenderCervantes();
  _ppState.loading = false;
}

/**
 * Formatea fecha ISO a legible
 */
function ppFormatDate(dateStr) {
  if (!dateStr) return '—';
  try {
    return new Date(dateStr).toLocaleDateString('es-AR', {
      timeZone: 'America/Argentina/Buenos_Aires',
      day: '2-digit', month: '2-digit', year: 'numeric'
    });
  } catch (e) { return dateStr; }
}

/**
 * Renderiza tabla Virgilio
 */
function ppRenderVirgilio() {
  const container = document.getElementById('ppVirgilioList');
  if (!container) return;

  const data = _ppState.virgilioData;
  if (!data.length) {
    container.innerHTML = '<div style="padding:20px;text-align:center;color:#64748b;">Sin documentación pendiente</div>';
    return;
  }

  let html = '<table class="stk-tbl" style="font-size:13px;"><thead><tr>' +
    '<th>Recepción</th><th>Tipo</th><th>N° Remito</th><th>N° Factura</th><th>Proveedor</th><th>Contenido</th><th>Estado</th><th></th>' +
    '</tr></thead><tbody>';

  data.forEach(function (row) {
    const estado = row.enviado_a_cervantes
      ? '<span style="color:#16a34a;font-weight:700;">✅ Enviado</span>'
      : '<span style="color:#dc2626;font-weight:700;">⏳ Pendiente</span>';
    const acciones = row.enviado_a_cervantes
      ? ''
      : '<button class="stk-btn ok" onclick="ppMarkSent(' + row.id + ')" style="font-size:12px;padding:4px 10px;">Marcar enviado</button>';
    var tipoLabel = row.tipo_documento === 'ambos' ? 'Rto + Fc' : row.tipo_documento === 'remito' ? 'Remito' : row.tipo_documento === 'factura' ? 'Factura' : (row.tipo_documento || '—');
    var nroRto = row.numero_remito ? row.numero_remito + (row.fecha_remito ? '<br><small>' + ppFormatDate(row.fecha_remito) + '</small>' : '') : '—';
    var nroFc = row.numero_factura ? row.numero_factura + (row.fecha_factura ? '<br><small>' + ppFormatDate(row.fecha_factura) + '</small>' : '') : '—';

    html += '<tr>' +
      '<td>' + ppFormatDate(row.created_at) + '</td>' +
      '<td>' + tipoLabel + '</td>' +
      '<td>' + nroRto + '</td>' +
      '<td>' + nroFc + '</td>' +
      '<td>' + (row.razon_social || '—') + '</td>' +
      '<td>' + (row.tipo_contenido || '—') + '</td>' +
      '<td>' + estado + '</td>' +
      '<td>' + acciones + '</td>' +
    '</tr>';
  });

  html += '</tbody></table>';
  container.innerHTML = html;
}

/**
 * Renderiza tabla Cervantes
 */
function ppRenderCervantes() {
  const container = document.getElementById('ppCervantesList');
  if (!container) return;

  const data = _ppState.cervantesData;
  if (!data.length) {
    container.innerHTML = '<div style="padding:20px;text-align:center;color:#64748b;">Sin documentación pendiente de confirmar</div>';
    return;
  }

  let html = '<table class="stk-tbl" style="font-size:13px;"><thead><tr>' +
    '<th>Fecha</th><th>Tipo Doc</th><th>Razón Social</th><th>Contenido</th><th>Estado</th><th></th>' +
    '</tr></thead><tbody>';

  data.forEach(function (row) {
    const estado = row.confirmado
      ? '<span style="color:#16a34a;font-weight:700;">✅ Confirmado</span>'
      : '<span style="color:#f59e0b;font-weight:700;">📨 Recibido (sin confirmar)</span>';
    const acciones = row.confirmado
      ? ''
      : '<button class="stk-btn ok" onclick="ppMarkReceived(' + row.id + ')" style="font-size:12px;padding:4px 10px;">Confirmar recepción</button>';

    html += '<tr>' +
      '<td>' + ppFormatDate(row.fecha_emision) + '</td>' +
      '<td>' + (row.tipo_documento || '—') + '</td>' +
      '<td>' + (row.razon_social || '—') + '</td>' +
      '<td>' + (row.tipo_contenido || '—') + '</td>' +
      '<td>' + estado + '</td>' +
      '<td>' + acciones + '</td>' +
    '</tr>';
  });

  html += '</tbody></table>';
  container.innerHTML = html;
}

/**
 * Marca un documento como enviado a Cervantes (desde Virgilio)
 */
async function ppMarkSent(docId) {
  try {
    await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?id=eq.' + docId, {
      method: 'PATCH',
      headers: _ppHeaders({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ enviado_a_cervantes: true })
    });
    ppLoadData();
  } catch (e) {
    console.error('ppMarkSent error:', e);
    // silencioso — no interrumpir al operador
  }
}

/**
 * Marca un documento como confirmado por Cervantes
 */
async function ppMarkReceived(docId) {
  try {
    await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles?id=eq.' + docId, {
      method: 'PATCH',
      headers: _ppHeaders({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ confirmado: true, fecha_confirmacion: new Date().toISOString() })
    });
    ppLoadData();
  } catch (e) {
    console.error('ppMarkReceived error:', e);
    // silencioso — no interrumpir al operador
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
    // Marcar vacíos en rojo
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
  const overlay = document.getElementById('ppCaptureOverlay');
  if (overlay) overlay.remove();
  window._ppCapture = null;
}

/**
 * Graba documentación en Pasaje_Papeles (best-effort, silencioso)
 */
async function _ppSaveToSupabase(tipoContenido, data) {
  try {
    // Mapear tipoDoc a tipo_documento para la tabla
    var tipoDocLabel = data.tipoDoc;
    if (tipoDocLabel === 'remito_factura') tipoDocLabel = 'ambos';

    var payload = {
      planta: 'virgilio',
      tipo_documento: tipoDocLabel,
      tipo_contenido: tipoContenido,
      razon_social: data.proveedor || null,
      numero_remito: data.nroRemito || null,
      numero_factura: data.nroFactura || null,
      fecha_remito: data.fechaRemito || null,
      fecha_factura: data.fechaFactura || null,
      fecha_emision: data.fechaRemito || data.fechaFactura || null,
      legajo_usuario: (typeof legajoInput !== 'undefined' && legajoInput && legajoInput.value) ? legajoInput.value : null
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

// Exportar para que esté disponible globalmente
window.openPasajePapeles = openPasajePapeles;
window.closePasajePapeles = closePasajePapeles;
window.ppSwitchTab = ppSwitchTab;
window.ppLoadData = ppLoadData;
window.ppRenderVirgilio = ppRenderVirgilio;
window.ppRenderCervantes = ppRenderCervantes;
window.ppMarkSent = ppMarkSent;
window.ppMarkReceived = ppMarkReceived;
window.ppShowCaptureDialog = ppShowCaptureDialog;
window.ppCloseCaptureDialog = ppCloseCaptureDialog;
window.ppSaveDocument = ppSaveDocument;
window._ppCapRenderStep1 = _ppCapRenderStep1;
window._ppCapRenderStep2 = _ppCapRenderStep2;
window._ppCapSave = _ppCapSave;
