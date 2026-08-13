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
  document.querySelectorAll('.pp-tab').forEach(function (el) { el.classList.remove('active'); });
  var activeBtn = document.querySelector('.pp-tab[data-tab="' + tab + '"]');
  if (activeBtn) activeBtn.classList.add('active');
  document.querySelectorAll('.pp-tab-content').forEach(function (el) { el.style.display = 'none'; });
  var activeContent = document.getElementById('ppTab_' + tab);
  if (activeContent) activeContent.style.display = 'block';
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
  const container = document.getElementById('ppTab_virgilio');
  if (!container) return;

  const data = _ppState.virgilioData;
  if (!data.length) {
    container.innerHTML = '<div style="padding:20px;text-align:center;color:#64748b;">Sin documentación pendiente</div>';
    return;
  }

  let html = '<table class="stk-tbl" style="font-size:13px;"><thead><tr>' +
    '<th>Fecha</th><th>Tipo Doc</th><th>Razón Social</th><th>Contenido</th><th>Estado</th><th></th>' +
    '</tr></thead><tbody>';

  data.forEach(function (row) {
    const estado = row.enviado_a_cervantes
      ? '<span style="color:#16a34a;font-weight:700;">✅ Enviado</span>'
      : '<span style="color:#dc2626;font-weight:700;">⏳ Pendiente</span>';
    const acciones = row.enviado_a_cervantes
      ? ''
      : '<button class="stk-btn ok" onclick="ppMarkSent(' + row.id + ')" style="font-size:12px;padding:4px 10px;">Marcar enviado</button>';

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
 * Renderiza tabla Cervantes
 */
function ppRenderCervantes() {
  const container = document.getElementById('ppTab_cervantes');
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
    alert('Error al marcar como enviado');
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
    alert('Error al confirmar recepción');
  }
}

/**
 * Muestra pop-up para registrar nueva documentación recibida
 * Se llama desde recepcion.js cuando se completa una recepción
 * @param tipoContenido - 'mercaderia' o 'insumo'
 */
function ppShowCaptureDialog(tipoContenido) {
  const titulo = tipoContenido === 'mercaderia' ? 'Nueva documentación — Mercadería recibida' : 'Nueva documentación — Insumo recibido';

  const html = '<div style="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px;" onclick="if(event.target===this)ppCloseCaptureDialog()">' +
    '<div style="background:#fff;border-radius:12px;padding:24px;max-width:480px;width:100%;box-shadow:0 20px 25px rgba(0,0,0,.15);">' +
    '<h2 style="margin:0 0 16px;font-size:18px;color:#0f172a;">' + titulo + '</h2>' +
    '<div style="margin-bottom:14px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Fecha de emisión *</label><input type="date" id="ppCaptureDate" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;"></div>' +
    '<div style="margin-bottom:14px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Tipo de documento *</label><select id="ppCaptureDocType" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;"><option value="">Seleccionar...</option><option value="factura">Factura</option><option value="remito">Remito</option><option value="ambos">Factura + Remito</option></select></div>' +
    '<div style="margin-bottom:20px;"><label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Razón Social *</label><input type="text" id="ppCaptureRazonSocial" placeholder="Nombre del proveedor" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;"></div>' +
    '<div style="display:flex;gap:10px;justify-content:flex-end;">' +
    '<button onclick="ppCloseCaptureDialog()" style="padding:10px 20px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;color:#334155;font-weight:600;cursor:pointer;">Cancelar</button>' +
    '<button onclick="ppSaveDocument(\'' + tipoContenido + '\')" style="padding:10px 20px;border:none;border-radius:8px;background:#1e6bd6;color:#fff;font-weight:600;cursor:pointer;">Guardar</button>' +
    '</div></div></div>';

  const container = document.createElement('div');
  container.id = 'ppCaptureOverlay';
  container.innerHTML = html;
  document.body.appendChild(container);
}

/**
 * Cierra el diálogo de captura
 */
function ppCloseCaptureDialog() {
  const overlay = document.getElementById('ppCaptureOverlay');
  if (overlay) overlay.remove();
}

/**
 * Guarda el documento capturado en Supabase
 */
async function ppSaveDocument(tipoContenido) {
  const fecha = document.getElementById('ppCaptureDate') ? document.getElementById('ppCaptureDate').value : '';
  const tipoDoc = document.getElementById('ppCaptureDocType') ? document.getElementById('ppCaptureDocType').value : '';
  const razonSocial = document.getElementById('ppCaptureRazonSocial') ? document.getElementById('ppCaptureRazonSocial').value : '';

  if (!fecha || !tipoDoc || !razonSocial) {
    alert('Completá todos los campos');
    return;
  }

  try {
    var res = await fetch(SUPABASE_URL + '/rest/v1/Pasaje_Papeles', {
      method: 'POST',
      headers: _ppHeaders({ Prefer: 'return=minimal' }),
      body: JSON.stringify({
        planta: 'virgilio',
        tipo_documento: tipoDoc,
        razon_social: razonSocial,
        tipo_contenido: tipoContenido,
        fecha_emision: fecha,
        legajo_usuario: (typeof legajoInput !== 'undefined' && legajoInput && legajoInput.value) ? legajoInput.value : null
      })
    });

    if (!res.ok) {
      var errText = await res.text().catch(function () { return 'HTTP ' + res.status; });
      throw new Error(errText);
    }

    ppCloseCaptureDialog();
    openPasajePapeles();
  } catch (e) {
    console.error('ppSaveDocument error:', e);
    alert('Error al guardar: ' + (e.message || 'error desconocido'));
  }
}

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
