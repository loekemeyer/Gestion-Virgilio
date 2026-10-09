/* IMPO COMEX — Estimar Nacionalización (port de EstimarMode.jsx).
   Subí PI/CI (xls/pdf) y calcula cuánto vas a pagar:
    - Lee items + descripciones + cantidades + FOB
    - NCM auto vía /ncm-detect (3 capas)
    - Calcula derechos/IVA/gan/IIBB/SIM/flete LCL
    - Output: total estimado a pagar */
(function () {
  'use strict';
  const IC = window.IC;

  const ALIQUOTAS_NCM = {
    '8205.51.00.300Z': { derechos: 0.18 },
    '8205.51.00.400E': { derechos: 0.18 },
    '8205.51.00.900G': { derechos: 0.18 },
    '7323.93.00.910T': { derechos: 0.35 }, // INAL acero alimentos
    '8210.00.90.400N': { derechos: 0.18 },
    '8210.00.90.900Q': { derechos: 0.18 },
    '9604.00.00.300R': { derechos: 0.18 },
    '8211.91.00.000Z': { derechos: 0.20 },
    '8215.99.00.000F': { derechos: 0.18 },
  };
  const DEFAULT_DERECHOS = 0.18;

  // Tarifas LCL aproximadas por CBM (USD)
  function calcFleteLCL(cbm) {
    const base = Math.max(40, cbm * 70); // mix de costo flete + desconsolidado + log fee + AGP
    const log_fee = 35;
    const manejo = 90;
    const dep_fiscal = 519 + 480;
    return base + log_fee + manejo + dep_fiscal;
  }

  function calcSeguro(fobUsd) {
    return fobUsd * 0.005; // ~0.5% del FOB (estimado)
  }

  IC.modo('estimar', function (el) {
    const api = IC.api;
    const S = {
      files: [],
      items: [], // [{ codigo, descripcion, cantidad, precio_unitario, fob, ncm, ncm_confidence, ncm_capa }]
      loading: false, progress: '', error: null,
      cotiz: 1450, iibbInsc: 'S', modo: 'LCL', cbmTotal: 0,
    };
    const vivo = () => el.isConnected;
    // Arriba (archivo + parámetros) y abajo (resultado) se pintan por separado: así tipear la cotización o el
    // CBM recalcula el resultado sin repintar el campo que se está escribiendo.
    function render() {
      if (!vivo()) return;
      if (!el.querySelector('[data-sec="est-top"]')) el.innerHTML = '<div><div data-sec="est-top"></div><div data-sec="est-res"></div></div>';
      IC.pintar(el.querySelector('[data-sec="est-top"]'), htmlTop());
      renderRes();
    }
    function renderRes() { if (vivo()) IC.pintar(el.querySelector('[data-sec="est-res"]'), htmlRes()); }

    const parseFile = async () => {
      if (!S.files.length) return;
      S.loading = true; S.error = null; S.progress = 'Leyendo archivo...'; render();
      try {
        const file = S.files[0];
        let extractedItems = [];

        if (/\.(xlsx|xls)$/i.test(file.name)) {
          // Excel: parsear con SheetJS
          S.progress = 'Parseando Excel...'; render();
          const m = await IC.lib('xlsx'); const XLSX = m.default || m;
          const buf = await file.arrayBuffer();
          const wb = XLSX.read(buf, { type: 'array' });
          const ws = wb.Sheets[wb.SheetNames[0]];
          const rows = XLSX.utils.sheet_to_json(ws, { defval: null });
          // Buscar headers típicos: ITEM NO / DESCRIPTION / T.QTY / UNIT PRICE / AMOUNT
          for (const r of rows) {
            const cod = r['ITEM NO.'] || r['ITEM NO'] || r['Item'] || r['Codigo'] || null;
            const desc = r['DESCRIPTION'] || r['Description'] || r['Descripcion'] || null;
            const cant = Number(r['T.QTY'] || r['QTY'] || r['Cantidad'] || 0) || null;
            const pu = Number(r['UNIT PRICE'] || r['Unit Price'] || r['Precio Unit'] || 0) || null;
            const fob = Number(r['AMOUNT'] || r['Amount'] || r['Total'] || (cant && pu ? cant * pu : 0)) || null;
            if (desc && cant && fob) {
              extractedItems.push({ codigo: cod ? String(cod).trim() : null, descripcion: String(desc).trim(), cantidad: cant, precio_unitario: pu, fob });
            }
          }
        } else if (file.type === 'application/pdf' || /\.pdf$/i.test(file.name)) {
          // PDF: extraer texto y mandar a LLM si escaneado
          S.progress = 'Extrayendo texto PDF...'; render();
          const { analyzePdf } = await IC.mod('pdfText');
          const a = await analyzePdf(file); // eslint-disable-line no-unused-vars
          // Por ahora simple: prompt al LLM directamente con el texto/imagen
          S.progress = 'Llamando LLM para extraer items...'; render();
          const fd = new FormData();
          fd.append('file', file);
          fd.append('prompt_extra', 'Extrae items de esta PI/CI: codigo, descripcion, cantidad, precio_unitario, fob_amount. Devuelve JSON {items: [...]}.');
          // Reuso verify-lakout como hack rápido (hace text+vision). En producción: endpoint dedicado /parse-pi-ci
          IC.avisar('Extracción PI desde PDF: usá /verify-lakout o convertí PI a Excel. Por ahora, sube la PI como Excel (.xlsx).');
          S.loading = false; render();
          return;
        } else {
          throw new Error('Formato no soportado. Subi .xlsx, .xls o .pdf');
        }

        if (!extractedItems.length) {
          throw new Error('No se detectaron items en el archivo. Verifica que tenga columnas ITEM NO / DESCRIPTION / T.QTY / UNIT PRICE / AMOUNT');
        }

        S.progress = `Detectando NCM para ${extractedItems.length} items...`; render();
        const r = await api.postJson('/ncm-detect', { items: extractedItems });
        const itemsConNcm = r.items || [];
        S.items = itemsConNcm;

        // CBM total estimado: 0.5 m3 / 1000 USD FOB (regla heurística)
        const fobTotal = itemsConNcm.reduce((s, it) => s + (Number(it.fob) || 0), 0);
        const cbmEstimado = Math.max(1, fobTotal / 2000);
        S.cbmTotal = cbmEstimado;
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false;
        S.progress = '';
        render();
      }
    };

    const updateItem = (i, key, value) => {
      S.items = S.items.map((it, x) => x === i ? Object.assign({}, it, { [key]: value }) : it);
      renderRes();
    };

    function htmlTop() {
      return `<div class="card">
        <div class="card-header"><h3>💵 Estimar Nacionalización</h3></div>

        <div style="font-size:11px;color:#64748b;margin-bottom:8px">
          Subi una PI/CI del proveedor (Excel o PDF) y calcula cuanto vas a pagar de impuestos.
          NCM se detecta automaticamente (codigo exacto / fuzzy / LLM).
        </div>

        ${IC.dz.html('pi-file', {
          label: 'PI / CI (xlsx)', icon: '📄', files: S.files,
          onFiles: (f) => { S.files = f; render(); },
          onRemove: (i) => { S.files = S.files.filter((_, x) => x !== i); render(); },
          accept: '.xlsx,.xls,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          single: true,
        })}

        <div style="display:flex;gap:10px;align-items:flex-end;margin-top:10px">
          <label style="font-size:11px">Cotiz USD/ARS<br>
            <input data-k="est-cotiz" type="number" value="${IC.esc(S.cotiz)}" oninput="${IC.on((e) => { S.cotiz = Number(e.target.value); renderRes(); })}" style="padding:4px;font-size:11px;width:90px">
          </label>
          <label style="font-size:11px">IIBB<br>
            <select data-k="est-iibb" onchange="${IC.on((e) => { S.iibbInsc = e.target.value; renderRes(); })}" style="padding:4px;font-size:11px">
              ${IC.opts([['S', 'S (inscripto)'], ['N', 'N (no inscripto)'], ['E', 'E (exento)']], S.iibbInsc)}
            </select>
          </label>
          <label style="font-size:11px">Modo<br>
            <select data-k="est-modo" onchange="${IC.on((e) => { S.modo = e.target.value; })}" style="padding:4px;font-size:11px">
              ${IC.opts([['LCL', 'LCL'], ['FCL', 'FCL'], ['AVION', 'Avión']], S.modo)}
            </select>
          </label>
          <label style="font-size:11px">CBM total<br>
            <input data-k="est-cbm" type="number" step="0.1" value="${IC.esc(S.cbmTotal)}" oninput="${IC.on((e) => { S.cbmTotal = Number(e.target.value); renderRes(); })}" style="padding:4px;font-size:11px;width:80px">
          </label>
        </div>

        <div class="toolbar" style="margin-top:10px">
          <button class="btn btn-primary" onclick="${IC.on(parseFile)}" ${S.loading || !S.files.length ? 'disabled' : ''}>
            ${S.loading ? IC.esc(`${S.progress}`) : '🧮 Calcular nacionalización'}
          </button>
        </div>

        ${S.error ? `<div class="err-box" style="margin-top:10px">${IC.esc(S.error)}</div>` : ''}
      </div>`;
    }

    function htmlRes() {
      const items = S.items;
      if (!(items.length > 0)) return '';
      // Cálculo total
      const fobTotal = items.reduce((s, it) => s + (Number(it.fob) || 0), 0);
      const flete = calcFleteLCL(S.cbmTotal);
      const seguro = calcSeguro(fobTotal);
      const cif = fobTotal + flete + seguro;
      const iibbPct = S.iibbInsc === 'S' ? 0.003516 : 0;

      // Por item (cada uno con su NCM y alícuota)
      const calcItems = items.map(it => {
        const fob = Number(it.fob) || 0;
        const pct = it.ncm && ALIQUOTAS_NCM[it.ncm] ? ALIQUOTAS_NCM[it.ncm].derechos : DEFAULT_DERECHOS;
        const cifIt = fob + (fobTotal > 0 ? (flete + seguro) * (fob / fobTotal) : 0);
        const derecho = cifIt * pct;
        const estad = cifIt * 0.03;
        const baseIva = cifIt + derecho + estad;
        const iva = baseIva * 0.21;
        const ivaAdic = baseIva * 0.20;
        const ganancias = baseIva * 0.06;
        const iibb = baseIva * iibbPct;
        const total = derecho + estad + iva + ivaAdic + ganancias + iibb;
        return Object.assign({}, it, { cifIt, pct, derecho, estad, iva, ivaAdic, ganancias, iibb, total });
      });
      const totalImp = calcItems.reduce((s, it) => s + it.total, 0) + 10; // SIM $10
      const totalConCifEnPesos = (cif + totalImp) * S.cotiz;
      const capaBg = (c) => c === 'codigo' ? '#dcfce7' : c === 'fuzzy' ? '#dbeafe' : c === 'llm' ? '#fef3c7' : '#fee2e2';
      const conf = (it) => { const v = it.ncm_confidence?.toFixed?.(2); return v ?? '-'; };

      return `<div class="card">
        <div class="card-header"><h3>Resultado — ${items.length} items</h3></div>

        <div class="report" data-k="est-rep" style="max-height:500px;overflow-x:auto">
          <table style="min-width:1200px;font-size:11px">
            <thead>
              <tr>
                <th>Cod</th><th>Descripción</th><th>Cant</th><th>FOB USD</th>
                <th>NCM (auto)</th><th>conf</th><th>capa</th>
                <th>CIF</th><th>%der</th><th>Derecho</th><th>IVA</th><th>Total imp</th>
              </tr>
            </thead>
            <tbody>
              ${calcItems.map((it, i) => `<tr style="background:${it.ncm_confidence < 0.7 ? '#fffbeb' : 'transparent'}">
                <td><code>${IC.esc(it.codigo || '-')}</code></td>
                <td style="max-width:200px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${IC.esc(it.descripcion)}</td>
                <td>${IC.esc(it.cantidad)}</td>
                <td>$${(it.fob || 0).toFixed(2)}</td>
                <td>
                  <input data-k="est-ncm-${i}" value="${IC.esc(it.ncm || '')}" oninput="${IC.on((e) => updateItem(i, 'ncm', e.target.value))}"
                    style="width:130px;font-size:10px;padding:2px;border:1px solid #cbd5e1">
                </td>
                <td>${IC.esc(conf(it))}</td>
                <td><span style="font-size:9px;padding:1px 4px;background:${capaBg(it.ncm_capa)}">${IC.esc(it.ncm_capa ?? '')}</span></td>
                <td>$${it.cifIt.toFixed(2)}</td>
                <td>${(it.pct * 100).toFixed(0)}%</td>
                <td>$${it.derecho.toFixed(2)}</td>
                <td>$${it.iva.toFixed(2)}</td>
                <td><strong>$${it.total.toFixed(2)}</strong></td>
              </tr>`).join('')}
            </tbody>
          </table>
        </div>

        <div class="stats" style="margin-top:10px">
          <div class="stat"><div class="k">FOB Total</div><div class="v">$${fobTotal.toFixed(2)}</div></div>
          <div class="stat"><div class="k">Flete (LCL)</div><div class="v">$${flete.toFixed(2)}</div></div>
          <div class="stat"><div class="k">Seguro</div><div class="v">$${seguro.toFixed(2)}</div></div>
          <div class="stat"><div class="k">CIF</div><div class="v">$${cif.toFixed(2)}</div></div>
          <div class="stat"><div class="k">SIM</div><div class="v">$10</div></div>
          <div class="stat"><div class="k" style="color:#dc2626">Total Imp.</div><div class="v" style="color:#dc2626">$${totalImp.toFixed(2)}</div></div>
          <div class="stat"><div class="k">% s/FOB</div><div class="v">${((totalImp / fobTotal) * 100).toFixed(1)}%</div></div>
          <div class="stat"><div class="k">Total ARS</div><div class="v">$${IC.esc(totalConCifEnPesos.toLocaleString('es-AR', { maximumFractionDigits: 0 }))}</div></div>
        </div>

        <div style="font-size:10px;color:#64748b;margin-top:10px">
          ⚠ Estimacion. El despachante usa CBM/peso reales y tarifas exactas. NCMs con confianza baja (filas amarillas) requieren revisar manualmente.
        </div>
      </div>`;
    }

    render();
  });
})();
