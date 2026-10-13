/* IMPO COMEX — Verificación Completa legacy (port de FullMode.jsx).
   El despacho va por /verify-lakout y el resto (PI, CI, PL, BL, Libre Circ) por /analyze-docs,
   los dos en vista previa; «Guardar en DB» reenvía lo extraído con pre_merged. */
(function () {
  'use strict';
  const IC = window.IC;

  const ARTICULOS_COLS = [
    { key: 'codigo', label: 'Código' },
    { key: 'descripcion', label: 'Descripción' },
    { key: 'cantidad', label: 'Cantidad', type: 'number' },
    { key: 'cajas', label: 'Cajas', type: 'number' },
    { key: 'uni_master', label: 'Uni/Master', type: 'number' },
    { key: 'uni_inner', label: 'Uni/Inner', type: 'number' },
    { key: 'precio', label: 'Precio Unit', type: 'number' },
    { key: 'total', label: 'Total FOB', type: 'number' },
    { key: 'cbm', label: 'CBM total', type: 'number' },
    { key: 'cbm_caja', label: 'CBM/caja', type: 'number' },
    { key: 'gw_ctn', label: 'GW/ctn', type: 'number' },
    { key: 'nw_ctn', label: 'NW/ctn', type: 'number' },
    { key: 'medidas_l', label: 'L (cm)', type: 'number' },
    { key: 'medidas_w', label: 'W (cm)', type: 'number' },
    { key: 'medidas_h', label: 'H (cm)', type: 'number' },
  ];

  const DOC_TYPES = [
    { id: 'PI',          label: 'Proforma Invoice', icon: '📋' },
    { id: 'CI',          label: 'Commercial Invoice', icon: '🧾' },
    { id: 'PL',          label: 'Packing List', icon: '📦' },
    { id: 'DESPACHO',    label: 'Despacho', icon: '🏛️' },
    { id: 'BL',          label: 'Bill of Lading', icon: '🚢' },
    { id: 'LIBRE_CIRC',  label: 'Libre Circulación', icon: '✅' },
  ];

  // Lo que React mostraba de un valor: null / undefined / booleanos no se ven.
  const ver = (v) => (v == null || v === false || v === true) ? '' : IC.esc(v);
  const ITEMS_KEY = 'full-articulos';
  const dzId = (t) => 'full-' + t;

  IC.modo('full', function (el) {
    IC.mod('pdfText').catch(() => {});
    // Al entrar, zonas y tabla editable arrancan de cero (en React se montaban de nuevo).
    DOC_TYPES.forEach(d => IC.dz.olvidar(dzId(d.id)));
    IC.items.olvidar(ITEMS_KEY);

    const S = {
      nroCarga: '',
      filesByType: { PI: [], CI: [], PL: [], DESPACHO: [], BL: [], LIBRE_CIRC: [] },
      loading: false, saving: false, progress: '', result: null, richRows: null, error: null,
    };
    function render() { if (el.isConnected) IC.pintar(el, html()); }

    // Guardar preview (despacho + resto docs) reenviando data ya extraida con pre_merged
    async function guardarPreview() {
      const result = S.result;
      if (!(result && result.preview)) return;
      const nroCarga = S.nroCarga;
      S.saving = true; S.error = null; render();
      try {
        let cargaIdFinal = null;
        let despPersisted = null;
        let restoPersisted = null;
        // 1. Guardar despacho (verify-lakout) si existe en preview
        if (result.despachoPreview && result.despachoPreview.data) {
          const fd = new FormData();
          fd.append('nro_carga', nroCarga.trim());
          fd.append('pdf_text', JSON.stringify(result.despachoPreview.data));
          fd.append('filename', 'despacho.pdf');
          fd.append('pre_merged', 'true');
          despPersisted = await IC.api.postForm('/verify-lakout', fd);
          cargaIdFinal = despPersisted.carga_id || null;
        }
        // 2. Guardar resto (analyze-docs) si existe
        if (result.restoPreview && result.restoPreview.articulos) {
          const fd = new FormData();
          fd.append('nro_carga', nroCarga.trim());
          fd.append('pre_merged', 'true');
          fd.append('pre_articulos', JSON.stringify(result.restoPreview.articulos));
          fd.append('pre_reporte', result.restoPreview.reporte || '');
          if (result.restoPreview.proveedor) fd.append('pre_proveedor', result.restoPreview.proveedor);
          if (result.restoPreview.nro_carga_detectado) fd.append('pre_nro_carga_detectado', result.restoPreview.nro_carga_detectado);
          // Los artículos van a la misma carga que creó el despacho (antes quedaban en una segunda carga).
          if (cargaIdFinal) fd.append('carga_id', String(cargaIdFinal));
          restoPersisted = await IC.api.postForm('/analyze-docs', fd);
          if (!cargaIdFinal) cargaIdFinal = restoPersisted.carga_id || null;
        }
        const finalResult = Object.assign({}, result, {
          preview: false, persisted: true,
          carga_id: cargaIdFinal,
          despacho_id: despPersisted ? despPersisted.despacho_id : undefined,
        });
        S.result = finalResult;
        // Como en React: la vista enriquecida se pide antes de que se monte la tabla editable (items_list).
        const rica = cargaIdFinal ? IC.api.get(`/export-excel?carga_id=${cargaIdFinal}&format=json`) : null;
        if (rica) rica.catch(() => {});
        IC.items.olvidar(ITEMS_KEY);   // la tabla se monta de cero (en React se montaba al aparecer carga_id)
        render();
        if (rica) {
          try { S.richRows = await rica; }
          catch (_) {}
        }
      } catch (e) {
        S.error = e.message || String(e);
      } finally { S.saving = false; render(); }
    }

    const setFiles = (t) => (fs) => { S.filesByType = Object.assign({}, S.filesByType, { [t]: [...S.filesByType[t], ...fs] }); render(); };
    const removeFile = (t) => (i) => { S.filesByType = Object.assign({}, S.filesByType, { [t]: S.filesByType[t].filter((_, x) => x !== i) }); render(); };
    const totalFiles = () => Object.values(S.filesByType).reduce((s, f) => s + f.length, 0);
    const typesWithFiles = () => Object.entries(S.filesByType).filter(([, f]) => f.length > 0).map(([k]) => k);

    async function run() {
      if (typesWithFiles().length < 2 || !S.nroCarga.trim()) return;
      const filesByType = S.filesByType, nroCarga = S.nroCarga;
      S.loading = true; S.error = null; S.result = null; S.richRows = null; S.progress = 'Preparando...';
      IC.items.olvidar(ITEMS_KEY);   // sin resultado la tabla editable se desmonta (React)
      render();
      const setProgress = (p) => { S.progress = p; render(); };
      try {
        const { extractText } = await IC.mod('pdfText');
        // ESTRATEGIA: separar el DESPACHO (pesado, se procesa con split chunked via verify-lakout)
        //   del resto de los docs (PI, CI, PL, BL, Libre Circ) -> analyze-docs con menos peso.
        // Esto evita WORKER_RESOURCE_LIMIT cuando hay muchos PDFs grandes juntos.

        const despachoFiles = filesByType.DESPACHO || [];
        const restoFiles = [...filesByType.PI, ...filesByType.CI, ...filesByType.PL, ...filesByType.BL, ...filesByType.LIBRE_CIRC];

        let despResult = null;
        const progresoTotal = (despachoFiles.length ? 1 : 0) + (restoFiles.length ? 1 : 0);
        let pasoActual = 0;

        // Paso 1: Despacho (si hay) -> verify-lakout
        if (despachoFiles.length > 0) {
          pasoActual++;
          setProgress(`[${pasoActual}/${progresoTotal}] Extrayendo texto del despacho...`);
          const texto = await extractText(despachoFiles[0]);
          const fd1 = new FormData();
          fd1.append('nro_carga', nroCarga.trim());
          // El servidor usa el texto solo si tiene más de 500 caracteres; si no, necesita el PDF
          // (antes con 201–500 caracteres no se mandaba el PDF y respondía 400).
          if (texto.length > 500) {
            fd1.append('pdf_text', texto.slice(0, 150000));
            fd1.append('filename', despachoFiles[0].name);
          } else {
            fd1.append('file', despachoFiles[0]);
          }
          fd1.append('preview', 'true'); // preview por default, Guardar requiere boton
          setProgress(`[${pasoActual}/${progresoTotal}] Procesando despacho (preview)...`);
          despResult = await IC.api.postForm('/verify-lakout', fd1);
        }

        // Paso 2: resto de docs -> analyze-docs
        let restoResult = null;
        if (restoFiles.length > 0) {
          pasoActual++;
          setProgress(`[${pasoActual}/${progresoTotal}] Extrayendo texto de ${restoFiles.length} docs...`);
          const fd2 = new FormData();
          const textos = {};
          const nombresSoloTexto = [];
          for (const f of restoFiles) {
            const t = await extractText(f);
            if (t.length > 200) {
              textos[f.name] = t.slice(0, 20000);
              nombresSoloTexto.push(f.name);
            } else {
              // No se pudo extraer -> mandar el archivo
              fd2.append('files', f);
            }
          }
          fd2.append('nro_carga', nroCarga.trim());
          if (Object.keys(textos).length) fd2.append('pdf_texts', JSON.stringify(textos));
          if (nombresSoloTexto.length) fd2.append('nombres_solo_texto', JSON.stringify(nombresSoloTexto));
          fd2.append('preview', 'true');
          setProgress(`[${pasoActual}/${progresoTotal}] Analizando IA preview (${Object.keys(textos).length} texto, ${restoFiles.length - Object.keys(textos).length} vision)...`);
          restoResult = await IC.api.postForm('/analyze-docs', fd2);
        }

        // Combinar resultados — PREVIEW (no persistido)
        const d = despResult || {}, r = restoResult || {};
        const combined = {
          preview: true, persisted: false,
          nro_carga: d.nro_carga || r.nro_carga,
          proveedor: d.proveedor || r.proveedor,
          costo_usd: (d.costo_usd || 0) + (r.costo_usd || 0),
          modelo: d.modelo || r.modelo,
          articulos_count: r.articulos_count,
          items_count: d.items_count,
          alertas: [...(d.alertas || []), ...(r.alertas || [])],
          advertencias: [...(d.advertencias || []), ...(r.advertencias || [])],
          reporte: r.reporte,
          despachoPreview: despResult,
          restoPreview: restoResult,
        };
        S.result = combined;
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false; S.progress = ''; render();
      }
    }

    async function downloadExcel() {
      const result = S.result;
      if (!(result && result.carga_id)) return;
      try { await IC.api.descargar(`/export-excel?carga_id=${result.carga_id}`, `verificacion_carga_${result.carga_id}.xlsx`); }
      catch (e) { IC.avisar('No se pudo descargar el Excel: ' + (e.message || e)); }
    }

    function celdaRica(k, v) {
      if (v == null || v === '') return '<span style="color:#cbd5e1">—</span>';
      if (typeof v === 'number') return (k.includes('USD') || k.includes('FOB') || k.includes('CIF') || k.includes('IVA')) ? `$${IC.esc(v.toFixed(2))}` : IC.esc(v);
      return IC.esc(String(v));
    }

    function htmlResultado() {
      const result = S.result;
      if (!result) return '';
      const rich = S.richRows;
      const filas = rich && rich.rows && rich.rows.length > 0 ? rich.rows : null;
      return `<div class="card">
        <div class="card-header">
          <h3>${result.preview ? '👁 Vista Previa — Reporte de verificación' : '✅ Guardado — Reporte de verificación'}</h3>
          <div style="flex:1"></div>
          ${result.preview ? `<button class="btn btn-primary" onclick="${IC.on(guardarPreview)}" ${S.saving ? 'disabled' : ''}
            style="background:#10b981;border-color:#059669;font-size:13px">${S.saving ? '⏳ Guardando...' : '💾 Guardar en DB'}</button>` : ''}
          ${result.carga_id ? `<button class="btn btn-success" onclick="${IC.on(downloadExcel)}">📥 Excel</button>` : ''}
        </div>

        ${result.preview ? `<div class="alert menor" style="margin-bottom:10px;background:#eff6ff;border-left-color:#3b82f6">
          <strong>👁 Vista previa:</strong> Los docs NO se guardaron en la base de datos. Revisa y aprieta <strong>💾 Guardar en DB</strong>.
        </div>` : ''}

        <div class="stats">
          <div class="stat"><div class="k">Carga ID</div><div class="v">${IC.esc(result.carga_id || (result.preview ? '—' : '?'))}</div></div>
          <div class="stat"><div class="k">Artículos</div><div class="v">${ver(result.articulos_count ?? 0)}</div></div>
          <div class="stat"><div class="k">Costo</div><div class="v">$${result.costo_usd != null ? IC.esc(result.costo_usd.toFixed(4)) : ''}</div></div>
          <div class="stat"><div class="k">Modelo</div><div class="v" style="font-size:11px">${ver(result.modelo)}</div></div>
        </div>

        ${result.carga_id ? `<div style="margin-top:12px">
          <h4 style="margin:0 0 6px;font-size:13px;color:#334155">✏️ Artículos de la carga (editable):</h4>
          ${IC.items.html(ITEMS_KEY, {
            table: 'articulos_carga', filterValue: result.carga_id, columns: ARTICULOS_COLS,
            onChanged: async () => {
              try {
                const r = await IC.api.get(`/export-excel?carga_id=${result.carga_id}&format=json`);
                S.richRows = r; render();
              } catch (_) {}
            },
          })}
        </div>` : ''}

        ${filas ? `<div style="margin-top:12px">
          <h4 style="margin:0 0 6px;font-size:13px;color:#334155">📋 Vista enriquecida (${filas.length} artículos) — cruzada con Pedido Damián:</h4>
          <div class="report" data-k="full-rich" style="max-height:400px;overflow-x:auto">
            <table style="min-width:1800px">
              <thead><tr>${Object.keys(filas[0]).map(col => `<th style="white-space:nowrap">${IC.esc(col)}</th>`).join('')}</tr></thead>
              <tbody>${filas.map(row => `<tr>${Object.entries(row).map(([k, v]) => `<td style="white-space:nowrap">${celdaRica(k, v)}</td>`).join('')}</tr>`).join('')}</tbody>
            </table>
          </div>
        </div>` : ''}

        <details data-k="full-md" style="margin-top:12px">
          <summary style="cursor:pointer;font-size:12px;color:#64748b;font-weight:600">Ver reporte markdown completo</summary>
          <div class="report" data-k="full-md-rep">${IC.md(result.reporte)}</div>
        </details>
      </div>`;
    }

    function html() {
      const tw = typesWithFiles(), nro = S.nroCarga.trim();
      return `<div>
      <div class="card">
        <div class="card-header"><h3>🔍 Verificación Completa</h3></div>

        <div style="display:flex;gap:10px;align-items:flex-end;margin-bottom:10px">
          <label style="font-size:11px;color:#475569">
            N° Carga <span style="color:#dc2626">*</span><br>
            <input data-k="full-nro" value="${IC.esc(S.nroCarga)}" placeholder="ej. China 48"
              oninput="${IC.on((e) => { S.nroCarga = e.target.value; render(); })}"
              style="padding:6px;border:1px solid #cbd5e1;border-radius:5px;margin-top:3px;width:150px;font-size:12px">
          </label>
          <span style="font-size:11px;color:#64748b;padding-bottom:6px">Proveedor y tipo de envío se autodetectan de los docs.</span>
        </div>
        <p style="margin:0 0 10px;font-size:11px;color:#64748b">Subí PI, CI, PL, Despacho, BL y Libre Circulación.</p>

        <div class="zones">
          ${DOC_TYPES.map(d => IC.dz.html(dzId(d.id), { label: d.label, icon: d.icon, files: S.filesByType[d.id], onFiles: setFiles(d.id), onRemove: removeFile(d.id) })).join('')}
        </div>

        <div class="toolbar">
          <button class="btn btn-primary" onclick="${IC.on(run)}" ${S.loading || tw.length < 2 || !nro ? 'disabled' : ''}>
            ${S.loading ? IC.esc(S.progress) : `🔍 Verificar (${totalFiles()} archivos, ${tw.length} tipos)`}
          </button>
          <span style="font-size:11px;color:#94a3b8">Mín. 2 tipos de documentos</span>
        </div>

        ${S.loading ? `<div class="loading"><span class="pulse">📊</span> ${IC.esc(S.progress)}</div>` : ''}
        ${S.error ? `<div class="err-box">${IC.esc(S.error)}</div>` : ''}
      </div>
      ${htmlResultado()}
    </div>`;
    }

    render();
  });
})();
