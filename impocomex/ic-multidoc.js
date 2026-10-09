/* IMPO COMEX — Verificar Docs Separados (port de MultiDocMode.jsx).
   Mismo flujo: el despacho se pre-procesa (texto o tramos por /verify-lakout), el resto se manda a
   /verify-multi-doc con el texto extraído en el navegador; vista previa y después «Guardar en DB». */
(function () {
  'use strict';
  const IC = window.IC;

  const ALERTA_RELEVAMIENTO_TIPOS = new Set([
    'codigo_no_relevamiento', 'codigo_pre_split_e', 'marca_mismatch_relevamiento',
    'inal_relevamiento_desactualizado', 'relevamiento_inconsistente',
  ]);
  function parseAlerta(a) {
    const m1 = /Codigo (\S+)\s*\(([^)]+)\)/.exec(a.descripcion || '') || /Item (\S+):/.exec(a.descripcion || '') || /"([^"]+)"\s*\(([^)]*)\)/.exec(a.descripcion || '');
    return { codigo: (m1 && m1[1]) || '', marca: (m1 && m1[2]) || '', descripcion: a.descripcion || '' };
  }

  const SLOTS = [
    { key: 'despacho', label: 'Despacho (OM-1993)', icon: '🏛️', required: false, hint: 'PDF del despacho oficializado (hace falta para guardar)' },
    { key: 'ci',       label: 'CI (Commercial Invoice)', icon: '📄', required: false, hint: 'Factura comercial del proveedor' },
    { key: 'pl',       label: 'PL (Packing List)', icon: '📦', required: false, hint: 'Lista de empaque' },
    { key: 'bl',       label: 'BL (Bill of Lading)', icon: '🚢', required: false, hint: 'Conocimiento de embarque' },
    { key: 'hkinv',    label: 'HKINV (NTL Cargo)', icon: '💼', required: false, hint: 'Solo si vendor es NTL Cargo intermediario' },
    { key: 'libre_circulacion', label: 'Libre Circulación INAL', icon: '✅', required: false, hint: 'Opcional: si no se sube, se busca en la base la ya cargada con la misma factura, BL o N° de carga' },
    { key: 'pesaje',   label: 'Pesaje Real (Gemez)', icon: '⚖️', required: false, hint: 'Ticket de balanza al ingreso a depósito fiscal' },
  ];

  // Auto-asignar slot por nombre de archivo
  function autoSlotFromName(name) {
    const n = name.toLowerCase();
    if (/despacho|lakout|om[\s-]*1993/i.test(n)) return 'despacho';
    if (/(invoice|ci[\s_-]|factura)/i.test(n) && !/hkinv|ntl/i.test(n)) return 'ci';
    if (/packing|^pl[\s_-]|^7[\s_-]+pl/i.test(n)) return 'pl';
    if (/^6[\s_-]+bl|^bl[\s_-]|bill.*lading|telex/i.test(n)) return 'bl';
    if (/hkinv|ntl[\s_-]*cargo/i.test(n)) return 'hkinv';
    if (/libre[\s_-]*circ|inal|anmat|pd-2025|autorizaci[oó]n/i.test(n)) return 'libre_circulacion';
    if (/gemez|pesaje|balanza|peso[\s_-]*real/i.test(n)) return 'pesaje';
    return null;
  }

  // Lo que React mostraba de un valor: null / undefined / booleanos no se ven.
  const ver = (v) => (v == null || v === false || v === true) ? '' : IC.esc(v);

  IC.modo('multidoc', function (el) {
    // La lógica se precarga; se espera de verdad adentro de run().
    IC.mod('pdfText').catch(() => {}); IC.mod('lakoutTramos').catch(() => {});
    // Al entrar, las zonas y la cabecera arrancan de cero (en React se montaban de nuevo).
    IC.dz.olvidar('multi-bulk'); SLOTS.forEach(s => IC.dz.olvidar(`multi-${s.key}`));

    const S = {
      files: {}, nroCarga: '', loading: false, saving: false, progress: '', result: null, error: null,
      showCabecera: false, showPdf: false, pdfN: 0,
    };
    function render() { if (el.isConnected) IC.pintar(el, html()); }

    // Guardar preview: reenvia parsed_data de cada slot como pre_merged para hacer solo el insert
    async function guardarPreview() {
      const result = S.result;
      if (!(result && result.preview) || !(result && result.parsed_data)) return;
      S.saving = true; S.error = null; render();
      try {
        const fd = new FormData();
        fd.append('nro_carga', S.nroCarga.trim() || result.nro_carga || 'sin-num');
        for (const [slotKey, data] of Object.entries(result.parsed_data)) {
          if (!data) continue;
          fd.append(`${slotKey}_text`, JSON.stringify(data));
          fd.append(`${slotKey}_pre_merged`, 'true');
        }
        // preview=false default -> inserta en DB
        const j = await IC.api.postForm('/verify-multi-doc', fd);
        // Otro despacho → la cabecera se monta de cero (React); el mismo id queda montado.
        if (j && j.despacho_id && j.despacho_id !== result.despacho_id) IC.cab.olvidar(j.despacho_id);
        S.result = j;
      } catch (e) { S.error = e.message || String(e); }
      finally { S.saving = false; render(); }
    }

    // Drop multi-archivo: auto-asigna por nombre
    function handleDropMulti(fs) {
      const next = Object.assign({}, S.files);
      const unmatched = [];
      for (const f of fs) {
        // Solo el nombre del archivo: la carpeta o el comprimido de origen ("Carga 41 › INAL › …") no dicen el tipo.
        const slot = autoSlotFromName(f.name.split(' › ').pop());
        if (slot && !next[slot]) {
          next[slot] = f;
          IC.dz.olvidar(`multi-${slot}`);
        } else if (slot && next[slot]) {
          // ya hay uno, ignorar y avisar
          unmatched.push({ name: f.name, reason: `Ya hay archivo en slot ${slot}` });
        } else {
          unmatched.push({ name: f.name, reason: 'No se reconocio el tipo (ver hints abajo)' });
        }
      }
      S.files = next;
      if (unmatched.length) {
        S.error = 'Algunos archivos no se asignaron automaticamente:\n' + unmatched.map(u => `- ${u.name}: ${u.reason}`).join('\n');
      } else {
        S.error = null;
      }
      render();
    }

    function setSlot(slot, file) {
      S.files = Object.assign({}, S.files, { [slot]: file });
      IC.dz.olvidar(`multi-${slot}`);   // la zona del slot se desmonta (queda el archivo)
      render();
    }
    function removeSlot(slot) {
      const next = Object.assign({}, S.files);
      delete next[slot];
      S.files = next;
      render();
    }

    async function run() {
      // Ningún documento es obligatorio: se compara lo que se suba (con 2 o más hay cruce entre ellos).
      const requiredOk = Object.keys(S.files).length >= 1;
      if (!requiredOk) return;
      const files = S.files, nroCarga = S.nroCarga;
      if (S.result && S.result.despacho_id) IC.cab.olvidar(S.result.despacho_id);   // sin resultado la cabecera se desmonta
      S.loading = true; S.error = null; S.result = null; S.progress = 'Iniciando...'; render();
      const setProgress = (p) => { S.progress = p; render(); };
      try {
        const { analyzePdf, extractText } = await IC.mod('pdfText');
        const { unirTramos } = await IC.mod('lakoutTramos');
        // STEP 1: Pre-procesar slot despacho (chunking + extraccion via verify-lakout endpoint)
        // Esto resuelve el caso scan dominante donde un solo PDF de 20 paginas no se procesa bien
        let despachoPreMerged = null;
        const despachoFile = files.despacho;
        if (despachoFile) {
          setProgress(`Pre-procesando despacho (${despachoFile.name})...`);
          try {
            const a = await analyzePdf(despachoFile);
            if (a.mode === 'text-only' && a.text) {
              // Texto suficiente, una sola llamada
              despachoPreMerged = { _from_text: true, _text: a.text.slice(0, 150000) };
            } else if (a.mode === 'chunks' && a.chunks && a.chunks.length) {
              setProgress(`Despacho scan: procesando ${a.chunks.length} chunks...`);
              const chunkResults = [];
              for (const c of a.chunks) {
                const cfd = new FormData();
                cfd.append('nro_carga', nroCarga.trim());
                cfd.append('chunk_index', String(c.index));
                cfd.append('chunk_total', String(c.total));
                cfd.append('chunk_pages_desc', `paginas ${c.firstPage}-${c.lastPage}`);
                if (c.text) cfd.append('pdf_text', c.text.slice(0, 20000));
                cfd.append('file', new Blob([c.bytes], { type: 'application/pdf' }), `${despachoFile.name}-chunk${c.index + 1}.pdf`);
                const resp = await IC.api.postForm('/verify-lakout', cfd);
                chunkResults.push(resp);
              }
              // Unión de tramos compartida con Lakout (lakoutTramos.js)
              despachoPreMerged = unirTramos(chunkResults.map(r => r.data));
            }
          } catch (e) {
            console.warn('despacho pre-process fallo, fallback a vision directo:', e);
          }
        }

        // STEP 2: Build form para verify-multi-doc con todos los slots
        setProgress('Subiendo todos los slots al endpoint multi-doc...');
        const fd = new FormData();
        fd.append('nro_carga', nroCarga.trim());
        for (const slot of SLOTS) {
          const file = files[slot.key];
          if (!file) continue;
          if (slot.key === 'despacho' && despachoPreMerged) {
            if (despachoPreMerged._from_text) {
              fd.append('despacho_text', despachoPreMerged._text);
            } else {
              // Mandar JSON pre-merged como text para que server lo use directamente
              fd.append('despacho_text', JSON.stringify(despachoPreMerged));
              fd.append('despacho_pre_merged', 'true');
            }
          }
          // CI, PL y el resto: el texto se extrae en el navegador (PDF digital o Excel), igual que
          // Packing vs Cajas. Un escaneo o una foto van como archivo y los lee la IA.
          if (slot.key !== 'despacho') {
            const texto = await extractText(file).catch(() => '');
            if (texto && texto.length > 200) fd.append(`${slot.key}_text`, texto);
          }
          fd.append(`${slot.key}_file`, file, file.name);
        }
        setProgress('Procesando docs en paralelo (puede tardar 1-2 min)...');
        fd.append('preview', 'true'); // preview por default, guardar requiere boton
        const j = await IC.api.postForm('/verify-multi-doc', fd);
        S.result = j;
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false;
        S.progress = '';
        render();
      }
    }

    function abrirCorregir(a) {
      const p = parseAlerta(a);
      IC.corregirRelev({
        alerta: a, codigo: p.codigo, marca: p.marca, descripcion: p.descripcion,
        onClose: () => {},
        onSaved: () => IC.avisar('✓ Relevamiento actualizado.'),
      });
    }

    function htmlResultado() {
      const result = S.result;
      if (!result) return '';
      const procesados = result.slots_processed || [];
      const conDespacho = procesados.includes('despacho');
      const nro = S.nroCarga.trim();
      const alertas = result.alertas || [];
      const advertencias = result.advertencias || [];
      return `<div class="card">
        <div class="card-header">
          <h3>${result.duplicado ? '🔁 Duplicado'
            : result.preview ? `👁 Vista Previa — Carga ${IC.esc(result.nro_carga || '?')}`
            : `✅ Guardado — Carga ${IC.esc(result.nro_carga || '?')}`}</h3>
          <div style="flex:1"></div>
          ${result.preview && !result.duplicado && !conDespacho ? '<span style="font-size:11px;color:#64748b">Sin despacho: es sólo verificación, no se guarda.</span>' : ''}
          ${result.preview && !result.duplicado && conDespacho ? `<button class="btn btn-primary" onclick="${IC.on(guardarPreview)}" ${S.saving || !nro ? 'disabled' : ''}
              title="${!nro ? 'Poné el N° de carga para guardar' : ''}"
              style="background:#10b981;border-color:#059669;font-size:13px">${S.saving ? '⏳ Guardando...' : '💾 Guardar en DB'}</button>` : ''}
        </div>

        ${result.preview ? `<div class="alert menor" style="margin-bottom:10px;background:#eff6ff;border-left-color:#3b82f6">
          <strong>👁 Vista previa:</strong> Los docs NO se guardaron en la base de datos. Revisa abajo y aprieta <strong>💾 Guardar en DB</strong> si esta todo OK.
        </div>` : ''}

        ${result.duplicado ? `<div class="alert importante" style="margin-bottom:10px"><strong>⚠️</strong> ${ver(result.mensaje)}</div>` : ''}

        <div class="stats">
          <div class="stat"><div class="k">N° Despacho</div><div class="v" style="font-size:12px">${IC.esc(result.nro_despacho || '-')}</div></div>
          <div class="stat"><div class="k">Items</div><div class="v">${ver(result.items_count)}</div></div>
          <div class="stat"><div class="k">Slots procesados</div><div class="v" style="font-size:11px">${(result.slots_processed && result.slots_processed.length) || 0}</div></div>
          <div class="stat"><div class="k">Costo</div><div class="v">$${result.costo_usd != null ? IC.esc(result.costo_usd.toFixed(4)) : ''}</div></div>
          <div class="stat"><div class="k">Duracion</div><div class="v">${((result.duracion_ms || 0) / 1000).toFixed(1)}s</div></div>
        </div>

        ${alertas.length > 0 ? `<div style="margin-top:10px">
          <div style="font-size:12px;font-weight:600;color:#b91c1c;margin-bottom:4px">🚨 Alertas (${alertas.length})</div>
          <div class="alerts">${alertas.map(a => `<div class="alert ${IC.esc(a.severidad)}">
            <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">
              <div style="flex:1"><strong>${a.severidad === 'critica' ? '🔴' : a.severidad === 'importante' ? '🟡' : a.severidad === 'menor' ? '🟢' : 'ℹ️'} ${ver(a.severidad)}:</strong> ${ver(a.descripcion)}</div>
              ${ALERTA_RELEVAMIENTO_TIPOS.has(a.tipo) ? `<button onclick="${IC.on(() => abrirCorregir(a))}"
                class="btn" style="font-size:10px;padding:3px 8px;white-space:nowrap">📝 Corregir Relevamiento</button>` : ''}
            </div></div>`).join('')}</div>
        </div>` : ''}

        ${result.despacho_id ? `<div style="margin-top:12px">
          <div style="display:flex;align-items:center;gap:10px;margin-bottom:6px">
            <h4 style="margin:0;font-size:13px;color:#334155">✏️ Cabecera Despacho:</h4>
            <button onclick="${IC.on(() => { S.showCabecera = !S.showCabecera; if (S.showCabecera) IC.cab.olvidar(result.despacho_id); render(); })}" class="btn" style="font-size:10px;padding:3px 8px">
              ${S.showCabecera ? '▼ Ocultar editor' : '▶ Mostrar/editar campos'}</button>
          </div>
          ${S.showCabecera ? IC.cab.html(result.despacho_id) : ''}
        </div>` : ''}

        ${advertencias.length > 0 ? `<div style="margin-top:10px">
          <div style="font-size:12px;font-weight:600;color:#92400e;margin-bottom:4px">⚠️ Advertencias (${advertencias.length})</div>
          <div class="alerts">${advertencias.map(w => `<div class="alert menor" style="background:#fffbeb;border-left-color:#f59e0b">
            ${w.tipo ? `<code style="font-size:10px;margin-right:6px">${IC.esc(w.tipo)}</code>` : ''}${ver(w.descripcion)}</div>`).join('')}</div>
        </div>` : ''}

        ${result.parsed_data ? `<div style="margin-top:12px">
          <details data-k="md-parsed">
            <summary style="cursor:pointer;font-size:12px;font-weight:600;color:#475569">📊 Data extraida por slot (debug)</summary>
            <pre data-k="md-parsed-pre" style="font-size:10px;background:#f1f5f9;padding:8px;border-radius:5px;max-height:400px;overflow:auto">${IC.esc(JSON.stringify(result.parsed_data, null, 2))}</pre>
          </details>
        </div>` : ''}
      </div>`;
    }

    function html() {
      const nDocs = Object.keys(S.files).length;
      const requiredOk = nDocs >= 1;
      return `<div>
      <div class="card">
        <div class="card-header"><h3>📁 Modo Docs Separados — CI / PL / BL / Despacho</h3></div>

        <div style="display:flex;gap:10px;align-items:flex-end;margin-bottom:10px">
          <label style="font-size:11px;color:#475569">
            N° Carga <span style="color:#94a3b8">(para guardar)</span><br>
            <input data-k="md-nro" value="${IC.esc(S.nroCarga)}" placeholder="ej. China 49"
              oninput="${IC.on((e) => { S.nroCarga = e.target.value; render(); })}"
              style="padding:6px;border:1px solid #cbd5e1;border-radius:5px;margin-top:3px;width:150px;font-size:12px">
          </label>
          <span style="font-size:11px;color:#64748b;padding-bottom:6px">Subi todos los archivos juntos (auto-asigna slots por nombre) o uno por slot.</span>
        </div>

        <div style="margin-bottom:14px">
          ${IC.dz.html('multi-bulk', { label: 'Soltar todos los archivos juntos', icon: '🎯', files: [], onFiles: handleDropMulti, onRemove: () => {}, accept: '.pdf,.xlsx,.xls,.csv,image/*' })}
        </div>

        <div style="display:grid;grid-template-columns:repeat(auto-fit, minmax(280px, 1fr));gap:10px">
          ${SLOTS.map(slot => {
            const file = S.files[slot.key];
            return `<div class="zone" style="border:${file ? '2px solid #10b981' : (slot.required ? '1px solid #fca5a5' : '1px dashed #cbd5e1')};border-radius:6px;padding:8px">
              <div class="label" style="font-size:12px">
                <span>${slot.icon} ${IC.esc(slot.label)}</span>
                ${slot.required ? '<span style="color:#dc2626;margin-left:4px">*</span>' : ''}
                ${file ? '<span class="count" style="background:#10b981;color:white">✓</span>' : ''}
              </div>
              <div style="font-size:10px;color:#94a3b8;margin-bottom:4px">${IC.esc(slot.hint)}</div>
              ${file ? `<div class="f" style="font-size:11px">
                  <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${IC.esc(file.name)}</span><button onclick="${IC.on(() => removeSlot(slot.key))}" title="Quitar">✕</button>
                </div>`
                : IC.dz.html(`multi-${slot.key}`, { label: '', icon: '', files: [], single: true,
                    accept: slot.key === 'despacho' ? 'application/pdf' : '.pdf,.xlsx,.xls,.csv,image/*',
                    onFiles: fs => { if (fs[0]) setSlot(slot.key, fs[0]); }, onRemove: () => {} })}
            </div>`;
          }).join('')}
        </div>

        <div class="toolbar" style="margin-top:14px">
          <button class="btn btn-primary" onclick="${IC.on(run)}" ${S.loading || !requiredOk ? 'disabled' : ''}>
            ${S.loading ? `Procesando... ${IC.esc(S.progress)}` : `📁 Verificar (${nDocs} docs)`}
          </button>
          ${nDocs > 0 ? `<button class="btn" onclick="${IC.on(() => { S.showPdf = !S.showPdf; if (S.showPdf) S.pdfN++; render(); })}" style="margin-left:8px">
            ${S.showPdf ? '▼ Ocultar PDFs' : `👁 Ver PDFs (${nDocs})`}</button>` : ''}
          <span style="font-size:11px;color:${!requiredOk ? '#dc2626' : '#64748b'};margin-left:10px">
            ${nDocs === 0 ? 'Subí los documentos que tengas: se comparan entre ellos.'
              : nDocs === 1 ? 'Con un solo documento no hay contra qué comparar (sí se controlan códigos e INAL).'
              : `Se comparan ${nDocs} documentos entre sí.`}
          </span>
        </div>

        ${S.showPdf && nDocs > 0 ? `<div style="margin-top:10px">${IC.pdf.html(`multi-pdf-${S.pdfN}`, S.files, { height: 500, title: '📄 Documentos subidos' })}</div>` : ''}

        ${S.loading && S.progress ? `<div class="loading"><span class="pulse">📊</span> ${IC.esc(S.progress)}</div>` : ''}
        ${S.error ? `<div class="err-box">${IC.esc(S.error)}</div>` : ''}
      </div>
      ${htmlResultado()}
    </div>`;
    }

    render();
  });
})();
