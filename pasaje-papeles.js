/**
 * Módulo Pasaje de Papeles
 * Gestiona documentación intercambiada entre Virgilio y Cervantes
 * v1.0 - Esqueleto inicial
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
 * Por ahora, solo esqueleto
 */
function ppLoadData() {
  if (_ppState.loading) return;
  _ppState.loading = true;

  // TODO: Conectar con Supabase
  // - Tabla: Pasaje_Papeles (o similar)
  // - Campos: id, tipo (VIRGILIO/CERVANTES), descripcion, fecha_recepcion,
  //   enviado_a (planta destino), confirmado, fecha_confirmacion

  ppRenderVirgilio();
  ppRenderCervantes();
  _ppState.loading = false;
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

  let html = '';
  _ppState.virgilioData.forEach(doc => {
    const status = doc.enviado_a_cervantes ? 'sent' : '';
    const btnText = doc.enviado_a_cervantes ? '✓ Enviado' : 'Marcar enviado';
    const btnClass = status ? `pp-btn-sm ${status}` : 'pp-btn-sm';

    html += `
      <div class="pp-doc-item">
        <div class="pp-doc-info">
          <div class="pp-doc-title">${doc.descripcion || 'Sin descripción'}</div>
          <div class="pp-doc-desc">${doc.detalles || ''}</div>
          <div class="pp-doc-date">Recibido: ${doc.fecha_recepcion || '—'}</div>
        </div>
        <div class="pp-doc-action">
          <button class="${btnClass}" onclick="ppMarkSent(${doc.id})" ${doc.enviado_a_cervantes ? 'disabled' : ''}>
            ${btnText}
          </button>
        </div>
      </div>
    `;
  });

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

  let html = '';
  _ppState.cervantesData.forEach(doc => {
    const status = doc.confirmado ? 'received' : '';
    const btnText = doc.confirmado ? '✓ Confirmado' : 'Confirmar recepción';
    const btnClass = status ? `pp-btn-sm ${status}` : 'pp-btn-sm';

    html += `
      <div class="pp-doc-item">
        <div class="pp-doc-info">
          <div class="pp-doc-title">${doc.descripcion || 'Sin descripción'}</div>
          <div class="pp-doc-desc">${doc.detalles || ''}</div>
          <div class="pp-doc-date">Enviado por Virgilio: ${doc.fecha_envio || '—'}</div>
        </div>
        <div class="pp-doc-action">
          <button class="${btnClass}" onclick="ppMarkReceived(${doc.id})" ${doc.confirmado ? 'disabled' : ''}>
            ${btnText}
          </button>
        </div>
      </div>
    `;
  });

  container.innerHTML = html;
}

/**
 * Marca un documento como enviado a Cervantes (desde Virgilio)
 */
function ppMarkSent(docId) {
  console.log('Marcando documento', docId, 'como enviado a Cervantes');
  // TODO: Actualizar en Supabase
  // UPDATE Pasaje_Papeles SET enviado_a_cervantes=true WHERE id=docId
}

/**
 * Marca un documento como confirmado por Cervantes
 */
function ppMarkReceived(docId) {
  console.log('Marcando documento', docId, 'como recibido en Cervantes');
  // TODO: Actualizar en Supabase
  // UPDATE Pasaje_Papeles SET confirmado=true, fecha_confirmacion=now() WHERE id=docId
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
