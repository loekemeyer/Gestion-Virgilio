/* IMPO COMEX — Analizar Shipping Marks (port de MarksMode.jsx).
   A) Comparación Shipping Mark vs Proforma Invoice (en el navegador, exacto):
        - "For:" de cada item (SM)  vs  Buyer/Comprador (PI)
        - Product Code (SM)         vs  Product Code (PI)   [canoniza sufijo: 931 = 931E]
        - Nombre del artículo (SM)  vs  Product Name (PI)   [ignora paréntesis/caso]
        - QUANTITY (SM)             vs  Qty/Outer (PI)
        - Cobertura de códigos en ambos sentidos (SM sin PI / PI sin SM)
      PI puede ser Excel (columnas) o PDF (texto).
   B) Verificación de fotos de cajas contra el Shipping Mark (LLM /verify-marks) */
(function () {
  'use strict';
  const IC = window.IC;

  const CODE_RE = /^\d{3}[A-Za-z]?$/;                 // 3 cifras + letra opcional (999E)
  const canon = c => String(c ?? '').trim().toUpperCase().replace(/\s+/g, '').replace(/[A-Z]+$/, '');
  const normTxt = s => String(s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const LABEL = /inner box mark|printing|master box mark|front|side mark|made in china|product code|quantity|g\.w|n\.w|meas|^for\b/i;

  let XLSX = null;   // se carga a demanda (vendor/xlsx.mjs)
  async function cargarXlsx() { if (!XLSX) { const m = await IC.lib('xlsx'); XLSX = m.default || m; } return XLSX; }

  function nameMatch(a, b) {
    if (!a || !b) return null;
    const norm = s => normTxt(String(s).replace(/\(.*?\)/g, ''));   // ignora lo que va entre paréntesis
    const na = norm(a), nb = norm(b); if (!na || !nb) return null;
    return na === nb || na.includes(nb) || nb.includes(na);
  }

  // ---- Shipping Mark (Excel) -> [{code, name, forName, quantity}] ----
  async function parseShippingMark(file) {
    await cargarXlsx();
    const wb = XLSX.read(await file.arrayBuffer(), { type: 'array' });
    const items = []; let cur = null, pendingName = '';
    for (const name of wb.SheetNames) {
      const rows = XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, defval: '' });
      for (const row of rows) for (const cell of row) {
        const s = String(cell ?? ''); if (!s) continue;
        if (/Inner\s*Qty/i.test(s)) {                        // celda inner box -> nuevo item
          const mc = s.match(/Product\s*code\s*[:：]\s*([A-Za-z0-9\-]+)/i);
          cur = { code: mc ? mc[1] : '', name: pendingName, forName: '', quantity: null };
          pendingName = ''; items.push(cur);
        } else if (/For\s*[:：]/i.test(s) && /QUANTITY/i.test(s)) {   // celda master box
          if (!cur) { cur = { code: '', name: '', forName: '', quantity: null }; items.push(cur); }
          const mf = s.match(/For\s*[:：]\s*([^\/\n\r]+)/i); if (mf) cur.forName = mf[1].replace(/\s+/g, ' ').trim();
          const mm = s.match(/PRODUCT\s*CODE\s*[:：]\s*([A-Za-z0-9\-]+)/i); if (mm && !cur.code) cur.code = mm[1];
          const mq = s.match(/QUANTITY\s*[:：]\s*([\d,]+)/i); if (mq) cur.quantity = Number(mq[1].replace(/,/g, ''));
        } else if (!LABEL.test(s)) {                          // candidato a nombre del artículo
          const nm = s.split('/')[0].replace(/\s+/g, ' ').trim();
          if (nm && /[a-z]/i.test(nm)) pendingName = nm;
        }
      }
    }
    return items.filter(i => CODE_RE.test(i.code));
  }

  // ---- Proforma Invoice EXCEL: parse estructural -> {buyer, items:[{canon,raw,name,qtyOuter}]} ----
  function parsePIExcel(wb) {
    let buyer = ''; const items = [];
    for (const name of wb.SheetNames) {
      const rows = XLSX.utils.sheet_to_json(wb.Sheets[name], { header: 1, defval: '' });
      let hIdx = -1, codeCol = -1, outerCol = -1, nameCol = -1;
      for (let r = 0; r < rows.length; r++) {
        const row = rows[r];
        for (let c = 0; c < row.length; c++) {
          const v = String(row[c] ?? '').trim();
          if (/^(BUYER|Comprador|Consignee)\b/i.test(v) && !buyer) {
            for (let k = c + 1; k < row.length; k++) { const nx = String(row[k] ?? '').trim(); if (nx) { buyer = nx; break; } }
          }
        }
        if (hIdx < 0) {
          const norm = row.map(x => String(x ?? '').toLowerCase().replace(/\s+/g, ''));
          const cc = norm.findIndex(x => x.includes('productcode'));
          const oc = norm.findIndex(x => x.includes('qty/outer') || x.includes('outer'));
          const nc = norm.findIndex(x => x.includes('productname'));
          if (cc >= 0 && oc >= 0) { hIdx = r; codeCol = cc; outerCol = oc; nameCol = nc; }
        }
      }
      if (hIdx >= 0) for (let r = hIdx + 1; r < rows.length; r++) {
        const code = String(rows[r][codeCol] ?? '').trim();
        if (/^total/i.test(code)) break;
        if (!CODE_RE.test(code)) continue;
        items.push({
          canon: canon(code), raw: code,
          name: nameCol >= 0 ? String(rows[r][nameCol] ?? '').replace(/\s+/g, ' ').trim() : '',
          qtyOuter: Number(String(rows[r][outerCol] ?? '').replace(/[^0-9.]/g, '')) || null,
        });
      }
    }
    return { buyer, items };
  }

  // ---- Proforma Invoice PDF/texto ----
  function piBuyerFromText(text) {
    const m = text.match(/(?:BUYER|Comprador|Consignee|Buyer|Importer)\s*[:：]\s*([\s\S]*?)(?:Original\s*of\s*country|Address|Add\s*[:：]|Certificate|\n\r?\n|\r\n\r?\n)/i);
    return (m ? m[1] : '').replace(/\s+/g, ' ').trim();
  }
  function piOuterForText(text, code) {
    const digits = String(code).trim().toUpperCase().replace(/[A-Z]+$/, '');
    if (!/^\d{3}$/.test(digits)) return null;
    const re = new RegExp(`\\b${digits}[A-Za-z]?\\b[\\s\\S]{0,320}?US?\\$?\\s*[\\d,]+\\.\\d{1,2}\\s+(\\d+)\\s+(\\d+)\\b`, 'i');
    const m = text.match(re);
    return m ? Number(m[2]) : null;
  }
  function piItemsFromText(text) {
    const map = new Map();
    const re = /(?<![$\d.])\b(\d{3}[A-Za-z])\b/g;
    let m; while ((m = re.exec(text))) { const raw = m[1]; const c = canon(raw); if (!map.has(c)) map.set(c, raw); }
    return [...map].map(([cn, raw]) => ({ canon: cn, raw, name: '', qtyOuter: piOuterForText(text, raw) }));
  }

  async function parsePI(file) {
    if (/\.(xlsx|xls)$/i.test(file.name)) {
      await cargarXlsx();
      const wb = XLSX.read(await file.arrayBuffer(), { type: 'array' });
      const { buyer, items } = parsePIExcel(wb);
      const textoLLM = wb.SheetNames.map(n => XLSX.utils.sheet_to_csv(wb.Sheets[n], { FS: ' ' })).join('\n');
      return { buyer, items, textoLLM };
    }
    let text = '';
    if (/\.pdf$/i.test(file.name)) { const { analyzePdf } = await IC.mod('pdfText'); const a = await analyzePdf(file); text = a.text || ''; }
    else if (/\.(csv|txt)$/i.test(file.name)) text = await file.text();
    return { buyer: piBuyerFromText(text), items: piItemsFromText(text), textoLLM: text };
  }

  function construirComparacion(smItems, pi) {
    const piBy = {}; pi.items.forEach(it => piBy[it.canon] = it);
    const smCanons = new Set(smItems.map(s => canon(s.code)));
    const forName = smItems[0]?.forName || '';
    const esperado = pi.buyer || forName;
    const rows = smItems.map(s => {
      const p = piBy[canon(s.code)];
      return {
        code: s.code, smName: s.name, piName: p ? p.name : '', forName: s.forName, smQty: s.quantity,
        piOuter: p ? p.qtyOuter : null, piFound: !!p,
        qtyOk: p && s.quantity != null && p.qtyOuter != null ? Number(s.quantity) === Number(p.qtyOuter) : null,
        nameOk: p ? nameMatch(s.name, p.name) : null,
        forOk: esperado && s.forName ? normTxt(s.forName) === normTxt(esperado) : null,
      };
    });
    return {
      buyer: pi.buyer, forName,
      buyerOk: pi.buyer && forName ? normTxt(pi.buyer) === normTxt(forName) : null,
      rows,
      smNotInPi: rows.filter(r => !r.piFound).map(r => r.code),
      piNotInSm: pi.items.filter(it => !smCanons.has(it.canon)).map(it => it.raw),
      forMismatch: rows.filter(r => r.forOk === false).map(r => r.code),
      nameMismatch: rows.filter(r => r.nameOk === false).map(r => r.code),
    };
  }

  IC.modo('marks', function (el) {
    const api = IC.api;
    const S = {
      smFiles: [], piFiles: [], masterFotos: [], innerFotos: [],
      tipoEnvio: 'LCL', loading: false, progress: '', error: null,
      comp: null, reporte: '', meta: null,
    };
    const vivo = () => el.isConnected;
    function render() { if (vivo()) IC.pintar(el, html()); }

    const analizar = async () => {
      S.error = null; S.comp = null; S.reporte = ''; S.meta = null;
      const totalFotos = S.masterFotos.length + S.innerFotos.length;
      if (!S.smFiles.length) { S.error = 'Subi el Shipping Mark (Excel).'; render(); return; }
      if (!S.piFiles.length && totalFotos === 0) { S.error = 'Subi la Proforma Invoice (para comparar) y/o fotos (para verificar cajas).'; render(); return; }
      S.loading = true; render();
      try {
        S.progress = 'Leyendo Shipping Mark...'; render();
        const smItems = await parseShippingMark(S.smFiles[0]);
        if (!smItems.length) throw new Error('No pude leer articulos del Shipping Mark (con "Product code" / "QUANTITY").');

        let piTextLLM = '';
        if (S.piFiles.length) {
          S.progress = 'Leyendo Proforma Invoice...'; render();
          const pi = await parsePI(S.piFiles[0]);
          piTextLLM = pi.textoLLM || '';
          S.comp = construirComparacion(smItems, pi); render();
        }

        if (totalFotos > 0) {
          S.progress = 'Analizando fotos con IA...'; render();
          const expected = [{ documento: S.smFiles[0].name, contenido: JSON.stringify(smItems, null, 1) }];
          if (piTextLLM) expected.push({ documento: S.piFiles[0].name, contenido: piTextLLM.slice(0, 8000) });
          const fd = new FormData();
          fd.append('tipo_envio', S.tipoEnvio);
          fd.append('articulos', JSON.stringify(expected));
          S.masterFotos.forEach(f => fd.append('photos_TODOS_master', f, f.name));
          S.innerFotos.forEach(f => fd.append('photos_TODOS_inner', f, f.name));
          const r = await api.postForm('/verify-marks', fd);
          S.reporte = r.reporte || '(sin reporte)';
          S.meta = { modelo: r.modelo, costo: r.costo_usd, ms: r.duracion_ms };
        }
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false; S.progress = '';
        render();
      }
    };

    const short = s => (s && s.length > 24 ? s.slice(0, 24) + '…' : s);
    const zona = (id, label, icon, key, accept, single) => IC.dz.html(id, {
      label, icon, files: S[key], accept, single,
      onFiles: (f) => { S[key] = f; render(); },
      onRemove: (i) => { S[key] = S[key].filter((_, x) => x !== i); render(); },
    });
    const ok = (t) => `<span style="color:#059669">${t}</span>`;

    function html() {
      const comp = S.comp;
      const resumen = comp ? {
        match: comp.rows.filter(r => r.qtyOk === true).length,
        diff: comp.rows.filter(r => r.qtyOk === false).length,
      } : null;
      return `<div>
      <div class="card">
        <div class="card-header"><h3>📦 Analizar Shipping Marks</h3></div>
        <div style="font-size:11px;color:#64748b;margin-bottom:10px">
          <strong>Compara el Shipping Mark contra la Proforma Invoice</strong>: comprador vs "For:", product code,
          nombre del artículo, QUANTITY vs Qty/Outer, y qué códigos faltan en cada documento. Los dos pueden ser
          Excel o PDF. Opcional: fotos de las cajas verificadas por IA.
        </div>

        <div style="display:flex;gap:12px;flex-wrap:wrap">
          <div style="flex:1;min-width:240px">${zona('marks-sm', 'Shipping Mark (Excel)', '🏷️', 'smFiles', '.xlsx,.xls', true)}</div>
          <div style="flex:1;min-width:240px">${zona('marks-pi', 'Proforma Invoice (Excel o PDF)', '📄', 'piFiles', '.pdf,.xlsx,.xls,.csv', true)}</div>
        </div>

        <div style="display:flex;gap:12px;margin-top:10px;flex-wrap:wrap">
          <div style="flex:1;min-width:240px">${zona('marks-master', 'Fotos Master Box (opcional)', '📦', 'masterFotos', 'image/*', false)}</div>
          <div style="flex:1;min-width:240px">${zona('marks-inner', 'Fotos Inner Box (opcional)', '📥', 'innerFotos', 'image/*', false)}</div>
        </div>

        <div style="display:flex;gap:10px;align-items:flex-end;margin-top:10px">
          <label style="font-size:11px">Tipo de envio<br>
            <select data-k="mk-tipo" onchange="${IC.on((e) => { S.tipoEnvio = e.target.value; render(); })}" style="padding:4px;font-size:11px">
              ${IC.opts([['LCL', 'LCL (consolidado)'], ['FCL', 'FCL (contenedor)']], S.tipoEnvio)}
            </select>
          </label>
        </div>

        <div class="toolbar" style="margin-top:10px">
          <button class="btn btn-primary" onclick="${IC.on(analizar)}" ${S.loading || !S.smFiles.length ? 'disabled' : ''}>
            ${S.loading ? IC.esc(S.progress || 'Analizando...') : '🔍 Analizar'}
          </button>
        </div>

        ${S.error ? `<div class="err-box" style="margin-top:10px">${IC.esc(S.error)}</div>` : ''}
      </div>

      ${comp ? `<div class="card">
        <div class="card-header"><h3>Shipping Mark vs Proforma Invoice</h3></div>

        <div style="font-size:12px;margin-bottom:6px">
          <strong>Comprador:</strong> For (SM): <code>${IC.esc(comp.forName || '—')}</code>  vs
          Buyer (PI): <code>${IC.esc(comp.buyer || '—')}</code>
          ${comp.buyerOk === true ? ok('✓ coincide') : ''}
          ${comp.buyerOk === false ? '<span style="color:#b45309">⚠ distinto (revisar — puede ser intermediario, ej. NTL Cargo)</span>' : ''}
        </div>

        <div style="font-size:11px;margin-bottom:8px;line-height:1.7">
          <div>Qty/Outer: <strong style="color:#059669">${resumen.match} ok</strong>${resumen.diff > 0 ? ` · <strong style="color:#dc2626">${resumen.diff} distinto</strong>` : ''}</div>
          <div>Nombres: ${comp.nameMismatch.length === 0
            ? ok('✓ coinciden')
            : `<span style="color:#dc2626">⚠ distinto en: ${IC.esc(comp.nameMismatch.join(', '))}</span>`}</div>
          <div>For por ítem: ${comp.forMismatch.length === 0
            ? ok('✓ todos = comprador')
            : `<span style="color:#dc2626">⚠ distinto en: ${IC.esc(comp.forMismatch.join(', '))}</span>`}</div>
          <div>En SM y NO en PI (${comp.smNotInPi.length}): ${comp.smNotInPi.length
            ? `<span style="color:#b45309">${IC.esc(comp.smNotInPi.join(', '))}</span>` : ok('ninguno ✓')}</div>
          <div>En PI y NO en SM (${comp.piNotInSm.length}): ${comp.piNotInSm.length
            ? `<span style="color:#b45309">${IC.esc(comp.piNotInSm.join(', '))}</span>` : ok('ninguno ✓')}</div>
        </div>

        <div class="report" data-k="mk-rep" style="max-height:420px;overflow-x:auto">
          <table style="font-size:12px">
            <thead><tr>
              <th>Code</th><th>Artículo (SM)</th><th>Artículo (PI)</th><th>QTY (SM)</th><th>Outer (PI)</th><th>Estado</th>
            </tr></thead>
            <tbody>
              ${comp.rows.map(r => `<tr style="background:${(r.qtyOk === false || r.forOk === false || r.nameOk === false) ? '#fef2f2' : (!r.piFound ? '#fffbeb' : 'transparent')}">
                <td><code>${IC.esc(r.code)}</code></td>
                <td title="${IC.esc(r.smName)}">${IC.esc(short(r.smName) || '—')}</td>
                <td title="${IC.esc(r.piName)}" style="color:${r.nameOk === false ? '#dc2626' : 'inherit'}">${IC.esc(r.piFound ? (short(r.piName) || '—') : '—')}</td>
                <td>${IC.esc(r.smQty ?? '—')}</td>
                <td>${IC.esc(r.piFound ? (r.piOuter ?? '') : '—')}</td>
                <td>
                  ${!r.piFound ? '<span style="color:#b45309">⚠ no está en PI</span>' : ''}
                  ${r.piFound && r.qtyOk === true ? ok('✓ OK') : ''}
                  ${r.piFound && r.qtyOk === false ? `<span style="color:#dc2626">✗ ${IC.esc(r.smQty)} ≠ ${IC.esc(r.piOuter)}</span>` : ''}
                  ${r.nameOk === false ? '<span style="color:#dc2626"> · nombre≠</span>' : ''}
                  ${r.forOk === false ? '<span style="color:#dc2626"> · For≠comprador</span>' : ''}
                </td>
              </tr>`).join('')}
            </tbody>
          </table>
        </div>
        <div style="font-size:10px;color:#94a3b8;margin-top:8px">
          Comparación exacta client-side. Códigos 3 cifras (931 = 931E). Nombres ignoran texto entre paréntesis.
          "No está en PI" puede ser otro embarque o PI escaneado — verificá manual.
        </div>
      </div>` : ''}

      ${S.reporte ? `<div class="card">
        <div class="card-header"><h3>Verificación de fotos (IA)</h3></div>
        ${S.meta ? `<div style="font-size:10px;color:#94a3b8;margin-bottom:8px">
          ${IC.esc(S.meta.modelo ?? '')} · $${Number(S.meta.costo || 0).toFixed(3)} · ${IC.esc(S.meta.ms ?? '')} ms
        </div>` : ''}
        <div class="report" data-k="mk-ia" style="padding:12px">${IC.md(S.reporte)}</div>
      </div>` : ''}
    </div>`;
    }

    render();
  });
})();
