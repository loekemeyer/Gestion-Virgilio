/* IMPO COMEX — Modo Lakout, 1 PDF (port de LakoutMode.jsx).
   Mismos pedidos a /verify-lakout (texto, tramos con visión, re-extract de cabecera, preview y Guardar),
   mismo Excel y la misma lógica de PDF (logica/pdfText.js, logica/lakoutTramos.js, sin reescribir). */
(function () {
  'use strict';
  const IC = window.IC;

  // Texto máximo que se manda del PDF (antes 50.000 sin aviso: se perdían CI, PL y Libre Circulación del final).
  const MAX_TEXTO = 150000;

  // Tipos de alerta que ofrecen botón "Corregir en Relevamiento"
  const ALERTA_RELEVAMIENTO_TIPOS = new Set([
    'codigo_no_relevamiento',
    'codigo_pre_split_e',
    'marca_mismatch_relevamiento',
    'inal_relevamiento_desactualizado',
    'relevamiento_inconsistente',
  ]);

  // Extrae codigo + marca del mensaje de la alerta (best-effort regex)
  function parseAlerta(a) {
    const m1 = /Codigo (\S+)\s*\(([^)]+)\)/.exec(a.descripcion || '') || /Item (\S+):/.exec(a.descripcion || '') || /"([^"]+)"\s*\(([^)]*)\)/.exec(a.descripcion || '');
    return {
      codigo: (m1 && m1[1]) || '',
      marca: (m1 && m1[2]) || '',
      descripcion: a.descripcion || '',
    };
  }

  const DESPACHO_COLS = [
    { key: 'nro_item', label: 'N°', type: 'number' },
    { key: 'ncm', label: 'NCM' },
    { key: 'descripcion', label: 'Descripción' },
    { key: 'cantidad', label: 'Cantidad', type: 'number' },
    { key: 'unidad', label: 'Unidad' },
    { key: 'valor_fob', label: 'FOB USD', type: 'number' },
    { key: 'valor_cif', label: 'CIF USD', type: 'number' },
    { key: 'derecho_importacion', label: 'Derecho USD', type: 'number' },
    { key: 'tasa_estadistica', label: 'Tasa Est. USD', type: 'number' },
    { key: 'iva', label: 'IVA USD', type: 'number' },
    { key: 'nro_certificado', label: 'INAL / Cert' },
  ];

  const DZ_ID = 'lakout-pdf', PDF_ID = 'lakout-pdf-ver', ITEMS_ID = 'lakout-items';
  const em = (t) => `<em style="color:#94a3b8">${t}</em>`;

  IC.modo('lakout', async function (el) {
    const api = IC.api;
    // Cada entrada al modo arranca de cero (como montar el componente).
    IC.dz.olvidar(DZ_ID); IC.items.olvidar(ITEMS_ID);

    const S = {
      files: [], nroCarga: '', loading: false, saving: false, result: null,
      richRows: null, error: null, showCabecera: false, showPdf: false,
    };
    const vivo = () => el.isConnected;
    function render() { if (vivo()) IC.pintar(el, html()); }
    // React desmontaba la cabecera y los ítems al ocultarlos o cambiar el resultado: acá se olvida su estado.
    function olvidarResultado() {
      if (S.result && S.result.despacho_id != null) IC.cab.olvidar(S.result.despacho_id);
      IC.items.olvidar(ITEMS_ID);
    }
    function setResult(j) { olvidarResultado(); S.result = j; }

    // Persistir preview en DB cuando user aprueba con boton Guardar
    async function guardarPreview() {
      const result = S.result;
      if (!(result && result.preview) || !(result && result.data)) return;
      S.saving = true; S.error = null; render();
      try {
        const fd = new FormData();
        fd.append('nro_carga', S.nroCarga.trim() || result.nro_carga || 'sin-num');
        fd.append('pdf_text', JSON.stringify(result.data));
        fd.append('filename', (S.files[0] && S.files[0].name) || 'lakout.pdf');
        fd.append('pre_merged', 'true');
        // preview=false (default) -> hace insert real
        const j = await api.postForm('/verify-lakout', fd);
        if (!vivo()) return;
        setResult(j); render();
        if (j.carga_id) {
          try { S.richRows = await api.get(`/export-excel?carga_id=${j.carga_id}&format=json`); }
          catch (_) {}
        }
      } catch (e) { S.error = e.message || String(e); }
      finally { S.saving = false; render(); }
    }

    async function run() {
      if (!S.files.length || !S.nroCarga.trim()) return;
      S.loading = true; S.error = null; setResult(null); S.richRows = null; render();
      const nroCarga = S.nroCarga;
      try {
        const [{ analyzePdf }, { unirTramos, CABECERA_CRITICA, CABECERA_RELEER }] =
          await Promise.all([IC.mod('pdfText'), IC.mod('lakoutTramos')]);
        const file = S.files[0];
        const analisis = await analyzePdf(file);

        // MODO 1: PDF con texto suficiente
        if (analisis.mode === 'text-only') {
          const fd = new FormData();
          fd.append('nro_carga', nroCarga.trim());
          fd.append('pdf_text', analisis.text.slice(0, MAX_TEXTO));
          // Con muy poco texto el servidor lee el PDF como imagen: hay que mandarlo.
          if (analisis.text.length <= 500) fd.append('file', file, file.name);
          fd.append('filename', file.name);
          fd.append('preview', 'true'); // no inserta en DB hasta apretar Guardar
          const j = await api.postForm('/verify-lakout', fd);
          if (analisis.text.length > MAX_TEXTO) {
            j.advertencias = [...(j.advertencias || []), { tipo: 'texto_cortado',
              descripcion: `El PDF tiene ${analisis.text.length.toLocaleString('es-AR')} caracteres de texto y se leyeron los primeros ${MAX_TEXTO.toLocaleString('es-AR')}: las últimas páginas pueden haber quedado afuera. Separá el lakout en dos PDF.` }];
          }
          setResult(j);
          return;
        }

        // MODO 2: scan dominante -> chunks con vision, merge client-side
        if (analisis.mode === 'chunks') {
          const chunkResults = [];
          let costoTotal = 0;
          for (const c of analisis.chunks) {
            const fd = new FormData();
            fd.append('nro_carga', nroCarga.trim());
            fd.append('chunk_index', String(c.index));
            fd.append('chunk_total', String(c.total));
            fd.append('chunk_pages_desc', `paginas ${c.firstPage}-${c.lastPage}`);
            if (c.text) fd.append('pdf_text', c.text.slice(0, 20000));
            fd.append('file', new Blob([c.bytes], { type: 'application/pdf' }), `${file.name}-chunk${c.index + 1}.pdf`);
            const resp = await api.postForm('/verify-lakout', fd);
            chunkResults.push(resp);
            costoTotal += resp.costo_usd || 0;
          }

          // Unión de tramos (lakoutTramos.js): conserva todas las secciones, no solo la cabecera.
          const merged = unirTramos(chunkResults.map(r => r.data));

          // Re-extract pass: si la cabecera quedó incompleta (faltan campos críticos como flete/seguro),
          // hacer una llamada extra al chunk 1 con prompt focalizado en cabecera.
          const cabeceraIncompleta = CABECERA_CRITICA.some(k => !merged[k]);
          if (cabeceraIncompleta && analisis.chunks && analisis.chunks.length > 0) {
            try {
              const c0 = analisis.chunks[0];
              const fd0 = new FormData();
              fd0.append('nro_carga', nroCarga.trim());
              fd0.append('chunk_index', '0');
              fd0.append('chunk_total', String(analisis.chunks.length));
              fd0.append('chunk_pages_desc', `paginas ${c0.firstPage}-${c0.lastPage} (re-extract cabecera)`);
              if (c0.text) fd0.append('pdf_text', c0.text.slice(0, 20000));
              fd0.append('file', new Blob([c0.bytes], { type: 'application/pdf' }), `${file.name}-rex.pdf`);
              const respRex = await api.postForm('/verify-lakout', fd0);
              const dr = respRex.data || {};
              for (const k of CABECERA_RELEER) {
                if ((merged[k] == null || merged[k] === 0) && dr[k] != null) merged[k] = dr[k];
              }
              costoTotal += respRex.costo_usd || 0;
            } catch (e) { /* fallback: continuar sin re-extract */ }
          }

          // Ahora una última llamada al backend con los datos ya mergeados como pdf_text
          // PREVIEW: aplica cross-validacion vs Relevamiento pero NO inserta en DB hasta Guardar
          const fd = new FormData();
          fd.append('nro_carga', nroCarga.trim());
          fd.append('pdf_text', JSON.stringify(merged));
          fd.append('filename', file.name);
          fd.append('pre_merged', 'true');
          fd.append('preview', 'true');
          const j = await api.postForm('/verify-lakout', fd);
          j.chunks_info = { total: analisis.chunks.length, pagesPdf: analisis.numPages, charsPerPage: analisis.charsPerPage.toFixed(0), costoChunks: costoTotal };
          j.costo_usd = (j.costo_usd || 0) + costoTotal;
          setResult(j);
          return;
        }

        S.error = 'No se pudo procesar el PDF: ' + (analisis.error || 'motivo desconocido');
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false;
        render();
      }
    }

    async function downloadExcel() {
      const result = S.result;
      if (!(result && result.carga_id)) return;
      try { await api.descargar(`/export-excel?carga_id=${result.carga_id}`, `verificacion_carga_${result.carga_id}.xlsx`); }
      catch (e) { IC.avisar('No se pudo descargar el Excel: ' + (e.message || e)); }
    }

    // ── pantalla ──────────────────────────────────────────────────────────────────────
    function html() {
      const files = S.files;
      const puedeCorrer = !(S.loading || !files.length || !S.nroCarga.trim());
      return `<div>
      <div class="card">
        <div class="card-header">
          <h3>🏛️ Modo Lakout — 1 PDF</h3>
        </div>

        <div style="display:flex;gap:10px;align-items:flex-end;margin-bottom:10px">
          <label style="font-size:11px;color:#475569">
            N° Carga <span style="color:#dc2626">*</span><br>
            <input data-k="lk-nro" value="${IC.esc(S.nroCarga)}" placeholder="ej. China 48"
              oninput="${IC.on((e) => {
                S.nroCarga = e.target.value;
                // Sólo cambia si se puede apretar Analizar: no se repinta (el visor de PDF se recargaría).
                const b = el.querySelector('[data-k="lk-run"]');
                if (b) b.disabled = S.loading || !S.files.length || !S.nroCarga.trim();
              })}"
              style="padding:6px;border:1px solid #cbd5e1;border-radius:5px;margin-top:3px;width:150px;font-size:12px">
          </label>
          <span style="font-size:11px;color:#64748b;padding-bottom:6px">
            El proveedor se autodetecta del contenido del PDF.
          </span>
        </div>

        <div>
          ${IC.dz.html(DZ_ID, {
            label: 'Despacho PDF', icon: '🏛️', files,
            onFiles: (arr) => { S.files = arr; render(); },
            onRemove: (i) => { S.files = S.files.filter((_, x) => x !== i); render(); },
            accept: 'application/pdf', single: true,
          })}
        </div>

        <div class="toolbar">
          <button class="btn btn-primary" data-k="lk-run" onclick="${IC.on(run)}" ${puedeCorrer ? '' : 'disabled'}>
            ${S.loading ? 'Procesando... (15-30 seg)' : '📄 Analizar Despacho'}
          </button>
          ${files.length > 0 ? `<button class="btn" onclick="${IC.on(() => { S.showPdf = !S.showPdf; render(); })}" style="margin-left:8px">
              ${S.showPdf ? '▼ Ocultar PDF' : '👁 Ver PDF'}
            </button>` : ''}
        </div>

        ${S.showPdf && files.length > 0 ? `<div style="margin-top:10px">
            ${IC.pdf.html(PDF_ID, files, { height: 500, title: '📄 Despacho subido' })}
          </div>` : ''}

        ${S.loading ? '<div class="loading"><span class="pulse">📊</span> OCR + extracción estructurada...</div>' : ''}
        ${S.error ? `<div class="err-box">${IC.esc(S.error)}</div>` : ''}
      </div>
      ${S.result ? htmlResultado(S.result) : ''}
    </div>`;
    }

    function htmlResultado(result) {
      const richRows = S.richRows;
      const titulo = result.duplicado
        ? (result.iguales ? '🔁 Duplicado — sin cambios' : '⚠️ Duplicado — con cambios')
        : result.preview
          ? `👁 Vista Previa — Carga ${result.nro_carga || '?'}`
          : `✅ Guardado — Carga ${result.nro_carga || '?'}`;
      const costo = result.costo_usd != null ? result.costo_usd.toFixed(4) : '';
      const icoSev = (s) => s === 'critica' ? '🔴' : s === 'importante' ? '🟡' : s === 'menor' ? '🟢' : 'ℹ️';

      const diferencias = (result.diferencias && result.diferencias.length > 0) ? `<div style="margin-top:12px">
          <h4 style="margin:0 0 6px;font-size:13px;color:#b45309">Diferencias vs registro anterior (${result.diferencias.length})</h4>
          <div class="report" data-k="lk-dif" style="max-height:250px">
            <table>
              <thead><tr><th>Campo</th><th>Antes (en DB)</th><th>Ahora (PDF nuevo)</th></tr></thead>
              <tbody>
                ${result.diferencias.map(d => `<tr style="background:#fffbeb">
                    <td><code>${IC.esc(d.campo)}</code></td>
                    <td>${d.antes == null ? em('null') : IC.esc(String(d.antes))}</td>
                    <td style="font-weight:600">${d.ahora == null ? em('null') : IC.esc(String(d.ahora))}</td>
                  </tr>`).join('')}
              </tbody>
            </table>
          </div>
          <div style="font-size:11px;color:#64748b;margin-top:6px">
            Los datos NO se actualizaron. Si querés reemplazar el registro anterior, tendrás que borrarlo primero (futuro: botón "Actualizar").
          </div>
        </div>` : '';

      const alertas = (result.alertas && result.alertas.length > 0) ? `<div style="margin-top:10px">
          <div style="font-size:12px;font-weight:600;color:#b91c1c;margin-bottom:4px">🚨 Alertas detectadas (${result.alertas.length})</div>
          <div class="alerts">
            ${result.alertas.map(a => `<div class="alert ${IC.esc(a.severidad)}">
                <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px">
                  <div style="flex:1">
                    <strong>${icoSev(a.severidad)} ${IC.esc(a.severidad)}:</strong> ${IC.esc(a.descripcion)}
                  </div>
                  ${ALERTA_RELEVAMIENTO_TIPOS.has(a.tipo) ? `<button
                      onclick="${IC.on(() => {
                        const pa = parseAlerta(a);
                        IC.corregirRelev({
                          alerta: a, codigo: pa.codigo, marca: pa.marca, descripcion: pa.descripcion,
                          onSaved: () => IC.avisar('✓ Relevamiento actualizado. Las próximas cargas usarán este dato.'),
                        });
                      })}"
                      class="btn"
                      style="font-size:10px;padding:3px 8px;white-space:nowrap"
                    >📝 Corregir Relevamiento</button>` : ''}
                </div>
              </div>`).join('')}
          </div>
        </div>` : '';

      const advertencias = (result.advertencias && result.advertencias.length > 0) ? `<div style="margin-top:10px">
          <div style="font-size:12px;font-weight:600;color:#92400e;margin-bottom:4px">⚠️ Advertencias de proceso (${result.advertencias.length}) — revisar manualmente</div>
          <div class="alerts">
            ${result.advertencias.map(w => `<div class="alert menor" style="background:#fffbeb;border-left-color:#f59e0b">
                ⚠️ ${IC.esc(w.descripcion)}
              </div>`).join('')}
          </div>
        </div>` : '';

      const cabecera = result.despacho_id ? `<div style="margin-top:12px">
          <div style="display:flex;align-items:center;gap:10px;margin-bottom:6px">
            <h4 style="margin:0;font-size:13px;color:#334155">✏️ Cabecera Despacho:</h4>
            <button onclick="${IC.on(() => {
              if (S.showCabecera) IC.cab.olvidar(result.despacho_id); // al ocultarla, React la desmontaba
              S.showCabecera = !S.showCabecera; render();
            })}" class="btn"
              style="font-size:10px;padding:3px 8px">
              ${S.showCabecera ? '▼ Ocultar editor' : '▶ Mostrar/editar campos'}
            </button>
          </div>
          ${S.showCabecera ? IC.cab.html(result.despacho_id) : ''}
        </div>` : '';

      const items = result.despacho_id ? `<div style="margin-top:12px">
          <h4 style="margin:0 0 6px;font-size:13px;color:#334155">✏️ Items del despacho (editable):</h4>
          ${IC.items.html(ITEMS_ID, {
            table: 'despacho_items',
            filterValue: result.despacho_id,
            columns: DESPACHO_COLS,
            onChanged: async () => {
              // Refrescar tabla rica despues de editar
              try {
                const rich = await api.get(`/export-excel?carga_id=${result.carga_id}&format=json`);
                S.richRows = rich; render();
              } catch (_) {}
            },
          })}
        </div>` : '';

      let tabla = '';
      if (richRows && richRows.rows && richRows.rows.length > 0) {
        tabla = `<div style="margin-top:12px">
          <h4 style="margin:0 0 6px;font-size:12px">Vista enriquecida (${richRows.rows.length} artículos) — cruzada con Pedido Damián:</h4>
          <div class="report" data-k="lk-rich" style="max-height:400px;overflow-x:auto">
            <table style="min-width:1800px">
              <thead>
                <tr>
                  ${Object.keys(richRows.rows[0]).map(col => `<th style="white-space:nowrap">${IC.esc(col)}</th>`).join('')}
                </tr>
              </thead>
              <tbody>
                ${richRows.rows.map(row => `<tr>
                    ${Object.entries(row).map(([k, v]) => {
                      // wrap en columnas tipo descripcion/nombre/observaciones/articulo
                      const wrapCol = /desc|nombre|observ|comentario|articulo/i.test(k);
                      const s = v == null || v === '' ? null : String(v);
                      const estilo = wrapCol
                        ? 'white-space:normal;word-break:break-word;min-width:240px;max-width:360px'
                        : 'white-space:nowrap';
                      const cont = v == null || v === '' ? '<span style="color:#cbd5e1">—</span>'
                        : typeof v === 'number' ? IC.esc(k.includes('USD') || k.includes('FOB') || k.includes('CIF') || k.includes('IVA') ? `$${v.toFixed(2)}` : v)
                        : IC.esc(s);
                      return `<td style="${estilo}" title="${IC.esc(s ?? '')}">${cont}</td>`;
                    }).join('')}
                  </tr>`).join('')}
              </tbody>
            </table>
          </div>
        </div>`;
      } else if (result.data && result.data.items) {
        tabla = `<div style="margin-top:12px">
          <h4 style="margin:0 0 6px;font-size:12px">Items extraídos (basico):</h4>
          <div class="report" data-k="lk-basico" style="max-height:400px;overflow-x:auto">
            <table style="min-width:1100px">
              <thead><tr>
                <th style="min-width:30px">N°</th>
                <th style="min-width:90px">Código</th>
                <th style="min-width:130px">NCM</th>
                <th style="min-width:360px">Descripción</th>
                <th style="min-width:70px">Cant</th>
                <th style="min-width:90px">FOB USD</th>
                <th style="min-width:130px">INAL</th>
              </tr></thead>
              <tbody>
                ${result.data.items.map((it, i) => `<tr>
                    <td>${IC.esc(it.nro_item ?? it.nro ?? (i + 1))}${it.subitem_nro ? `.${IC.esc(it.subitem_nro)}` : ''}</td>
                    <td>${IC.esc(it.codigo || '-')}</td>
                    <td style="font-size:10px">${IC.esc(it.ncm || '-')}</td>
                    <td style="white-space:normal;word-break:break-word" title="${IC.esc(it.descripcion || '')}">${IC.esc(it.descripcion || '-')}</td>
                    <td>${typeof it.cantidad === 'boolean' ? '' : IC.esc(it.cantidad)}</td>
                    <td>${typeof it.valor_fob === 'number' ? `$${it.valor_fob.toFixed(2)}` : '-'}</td>
                    <td style="font-size:10px">${IC.esc(it.nro_certificado || '-')}</td>
                  </tr>`).join('')}
              </tbody>
            </table>
          </div>
        </div>`;
      }

      return `<div class="card">
          <div class="card-header">
            <h3>${IC.esc(titulo)}</h3>
            <div style="flex:1"></div>
            ${result.preview && !result.duplicado ? `<button class="btn btn-primary" onclick="${IC.on(guardarPreview)}" ${S.saving ? 'disabled' : ''}
                style="background:#10b981;border-color:#059669;font-size:13px">
                ${S.saving ? '⏳ Guardando...' : '💾 Guardar en DB'}
              </button>` : ''}
            ${result.carga_id ? `<button class="btn btn-success" onclick="${IC.on(downloadExcel)}">📥 Descargar Excel</button>` : ''}
          </div>

          ${result.preview ? `<div class="alert menor" style="margin-bottom:10px;background:#eff6ff;border-left-color:#3b82f6">
              <strong>👁 Vista previa:</strong> El despacho NO se guardó en la base de datos. Revisa los datos abajo y aprieta <strong>💾 Guardar en DB</strong> si esta todo OK.
            </div>` : ''}

          ${result.duplicado ? `<div class="alert ${result.iguales ? 'menor' : 'importante'}" style="margin-bottom:10px">
              <strong>${result.iguales ? '✅' : '⚠️'}</strong> ${IC.esc(result.mensaje)}
            </div>` : ''}

          <div class="stats">
            <div class="stat"><div class="k">Proveedor</div><div class="v" style="font-size:13px">${IC.esc(result.proveedor || '-')}</div></div>
            <div class="stat"><div class="k">N° Despacho</div><div class="v" style="font-size:12px">${IC.esc(result.nro_despacho || '-')}</div></div>
            <div class="stat"><div class="k">Items</div><div class="v">${IC.esc(result.items_count)}</div></div>
            <div class="stat"><div class="k">Costo</div><div class="v">$${IC.esc(costo)}</div></div>
          </div>

          ${result.extraccion_incompleta ? `<div class="err-box" style="margin-top:10px">
              ⚠️ Extracción incompleta: solo ${IC.esc(result.items_count)} item(s) detectados pero el FOB total es alto. Considerá reintentar.
            </div>` : ''}

          ${diferencias}
          ${alertas}
          ${advertencias}
          ${cabecera}
          ${items}
          ${tabla}
        </div>`;
    }

    render();
  });
})();
