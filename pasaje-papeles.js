/**
 * Módulo Pasaje de Papeles
 * Gestiona documentación intercambiada entre Virgilio y Cervantes
 * v1.1 - Conexión Supabase + Pop-up de captura
 */

let _ppState = {
  activeTab: 'virgilio',
  virgilioData: [],
  cervantesData: [],
  loading: false
};

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
 * Cambia entre pestañas (Virgilio/Cervantes)
 */
function ppSwitchTab(tabName) {
  _ppState.activeTab = tabName;

  // Actualizar botones de tab
  document.querySelectorAll('.pp-tab').forEach(btn => {
    btn.classList.remove('active');
  });
  event.target.classList.add('active');

  // Mostrar/ocultar contenido
  document.getElementById('ppTabVirgilio').classList.remove('active');
  document.getElementById('ppTabCervantes').classList.remove('active');

  if (tabName === 'virgilio') {
    document.getElementById('ppTabVirgilio').classList.add('active');
  } else {
    document.getElementById('ppTabCervantes').classList.add('active');
  }
}

/**
 * Carga datos de documentación desde Supabase
 */
async function ppLoadData() {
  if (_ppState.loading) return;
  _ppState.loading = true;

  try {
    // Cargar Virgilio (mercadería + insumos recibidos, pendientes de enviar a Cervantes)
    const virRes = await sb.from('Pasaje_Papeles')
      .select('*')
      .eq('planta', 'virgilio')
      .order('created_at', { ascending: false })
      .limit(1000);

    _ppState.virgilioData = virRes.data || [];

    // Cargar Cervantes (documentación enviada por Virgilio, pendiente de confirmar)
    const cerRes = await sb.from('Pasaje_Papeles')
      .select('*')
      .eq('planta', 'cervantes')
      .eq('enviado_a_cervantes', true)
      .order('created_at', { ascending: false })
      .limit(1000);

    _ppState.cervantesData = cerRes.data || [];
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
    const d = new Date(dateStr);
    return d.toLocaleDateString('es-AR');
  } catch {
    return dateStr;
  }
}

/**
 * Renderiza la pestaña de Virgilio
 * Muestra documentación recibida que puede marcar como enviada a Cervantes
 */
function ppRenderVirgilio() {
  const container = document.getElementById('ppVirgilioList');
  if (!container) return;

  if (_ppState.virgilioData.length === 0) {
    container.innerHTML = '<div class="pp-empty">Sin documentación registrada todavía</div>';
    return;
  }

  let html = '<table style="width:100%;border-collapse:collapse;font-size:13px;">' +
    '<thead style="background:#f1f5f9;sticky;top:0;">' +
    '<tr>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #cbd5e1;">Fecha Emisión</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #cbd5e1;">Fecha Recepción</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #cbd5e1;">Tipo Doc</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #cbd5e1;">Razón Social</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #cbd5e1;">Tipo</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #cbd5e1;">Fecha DDJJ</th>' +
      '<th style="padding:10px;text-align:center;border-bottom:1px solid #cbd5e1;">Acción</th>' +
    '</tr>' +
    '</thead><tbody>';

  _ppState.virgilioData.forEach(doc => {
    const status = doc.enviado_a_cervantes ? 'sent' : '';
    const btnText = doc.enviado_a_cervantes ? '✓ Enviado' : 'Marcar enviado';
    const btnClass = status ? 'pp-btn-sm sent' : 'pp-btn-sm';

    html += '<tr>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;">' + ppFormatDate(doc.fecha_emision) + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;">' + ppFormatDate(doc.fecha_recepcion) + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;">' + (doc.tipo_documento || '—') + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;">' + (doc.razon_social || '—') + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;">' + (doc.tipo_contenido || '—') + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;">' + ppFormatDate(doc.fecha_ddjj) + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #e2e8f0;text-align:center;">' +
        '<button class="' + btnClass + '" onclick="ppMarkSent(' + doc.id + ')" ' + (doc.enviado_a_cervantes ? 'disabled' : '') + '>' +
          btnText +
        '</button>' +
      '</td>' +
    '</tr>';
  });

  html += '</tbody></table>';
  container.innerHTML = html;
}

/**
 * Renderiza la pestaña de Cervantes
 * Muestra documentación enviada por Virgilio para confirmar recepción
 */
function ppRenderCervantes() {
  const container = document.getElementById('ppCervantesList');
  if (!container) return;

  if (_ppState.cervantesData.length === 0) {
    container.innerHTML = '<div class="pp-empty">Sin documentación pendiente de Virgilio</div>';
    return;
  }

  let html = '<table style="width:100%;border-collapse:collapse;font-size:13px;">' +
    '<thead style="background:#f0fdf4;sticky;top:0;">' +
    '<tr>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #bbf7d0;">Fecha Emisión</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #bbf7d0;">Enviado por V.</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #bbf7d0;">Tipo Doc</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #bbf7d0;">Razón Social</th>' +
      '<th style="padding:10px;text-align:left;border-bottom:1px solid #bbf7d0;">Tipo</th>' +
      '<th style="padding:10px;text-align:center;border-bottom:1px solid #bbf7d0;">Acción</th>' +
    '</tr>' +
    '</thead><tbody>';

  _ppState.cervantesData.forEach(doc => {
    const status = doc.confirmado ? 'received' : '';
    const btnText = doc.confirmado ? '✓ Confirmado' : 'Confirmar recepción';
    const btnClass = status ? 'pp-btn-sm received' : 'pp-btn-sm';

    html += '<tr style="background:' + (doc.confirmado ? '#f0fdf4' : '#fff') + ';">' +
      '<td style="padding:10px;border-bottom:1px solid #bbf7d0;">' + ppFormatDate(doc.fecha_emision) + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #bbf7d0;">' + ppFormatDate(doc.fecha_recepcion) + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #bbf7d0;">' + (doc.tipo_documento || '—') + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #bbf7d0;">' + (doc.razon_social || '—') + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #bbf7d0;">' + (doc.tipo_contenido || '—') + '</td>' +
      '<td style="padding:10px;border-bottom:1px solid #bbf7d0;text-align:center;">' +
        '<button class="' + btnClass + '" onclick="ppMarkReceived(' + doc.id + ')" ' + (doc.confirmado ? 'disabled' : '') + '>' +
          btnText +
        '</button>' +
      '</td>' +
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
    await sb.from('Pasaje_Papeles')
      .update({ enviado_a_cervantes: true })
      .eq('id', docId);
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
    await sb.from('Pasaje_Papeles')
      .update({
        confirmado: true,
        fecha_confirmacion: new Date().toISOString()
      })
      .eq('id', docId);
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

  const html = `
    <div style="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px;" onclick="if(event.target===this)ppCloseCaptureDialog()">
      <div style="background:#fff;border-radius:12px;padding:24px;max-width:480px;width:100%;box-shadow:0 20px 25px rgba(0,0,0,.15);">
        <h2 style="margin:0 0 16px;font-size:18px;color:#0f172a;">${titulo}</h2>

        <div style="margin-bottom:14px;">
          <label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Fecha de emisión *</label>
          <input type="date" id="ppCaptureDate" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;">
        </div>

        <div style="margin-bottom:14px;">
          <label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Tipo de documento *</label>
          <select id="ppCaptureDocType" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;">
            <option value="">Seleccionar...</option>
            <option value="factura">Factura</option>
            <option value="remito">Remito</option>
            <option value="ambos">Factura + Remito</option>
          </select>
        </div>

        <div style="margin-bottom:20px;">
          <label style="display:block;font-size:13px;font-weight:600;color:#475569;margin-bottom:4px;">Razón Social *</label>
          <input type="text" id="ppCaptureRazonSocial" placeholder="Nombre del proveedor" style="width:100%;padding:10px;border:1px solid #cbd5e1;border-radius:8px;box-sizing:border-box;font-size:14px;">
        </div>

        <div style="display:flex;gap:10px;justify-content:flex-end;">
          <button onclick="ppCloseCaptureDialog()" style="padding:10px 20px;border:1px solid #cbd5e1;border-radius:8px;background:#fff;color:#334155;font-weight:600;cursor:pointer;">Cancelar</button>
          <button onclick="ppSaveDocument('${tipoContenido}')" style="padding:10px 20px;border:none;border-radius:8px;background:#1e6bd6;color:#fff;font-weight:600;cursor:pointer;">Guardar</button>
        </div>
      </div>
    </div>
  `;

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
  const fecha = document.getElementById('ppCaptureDate')?.value;
  const tipoDoc = document.getElementById('ppCaptureDocType')?.value;
  const razonSocial = document.getElementById('ppCaptureRazonSocial')?.value;

  if (!fecha || !tipoDoc || !razonSocial) {
    alert('Completá todos los campos');
    return;
  }

  try {
    await sb.from('Pasaje_Papeles').insert({
      planta: 'virgilio',
      tipo_documento: tipoDoc,
      razon_social: razonSocial,
      tipo_contenido: tipoContenido,
      fecha_emision: fecha,
      legajo_usuario: (typeof legajoInput !== 'undefined' && legajoInput?.value) || null
    });

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
