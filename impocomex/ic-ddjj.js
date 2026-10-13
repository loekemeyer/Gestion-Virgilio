/* IMPO COMEX — Declaración para presentar al Banco (port de DdjjMode.jsx).
   Declaración Jurada 20320 (Banco Credicoop). Reglas de llenado: docs/DDJJ-20320-Banco.md
   Todo el chequeo corre en el navegador (gratis). Los tildes de checkbox y las firmas NO se pueden leer
   del texto del PDF -> van como checklist manual.
   El controlante (datos personales) NO está acá: lo completa ic-base.js en CONTROLANTE al entrar. */
(function () {
  'use strict';
  const IC = window.IC;

  const COLOR = { alerta: '#dc2626', revisar: '#b45309', ok: '#059669' };
  const ICONO = { alerta: '✗', revisar: '⚠', ok: '✓' };
  const thS = { border: '1px solid #e2e8f0', background: '#f1f5f9', padding: '3px 7px', textAlign: 'left', fontWeight: 600, whiteSpace: 'nowrap', width: '1%' };
  const tdS = { border: '1px solid #e2e8f0', padding: '3px 7px', whiteSpace: 'nowrap', width: '1%' };
  const st = (...o) => IC.st(Object.assign({}, ...o));

  IC.modo('ddjj', async function (el) {
    el.innerHTML = '<div class="loading"><span class="pulse">⏳</span>Abriendo…</div>';
    let pdfText, chk, tpl;
    try {
      [pdfText, chk, tpl] = await Promise.all([IC.mod('pdfText'), IC.mod('lib/ddjjCheck'), IC.mod('lib/ddjjTemplate')]);
    } catch (e) {
      if (el.isConnected) el.innerHTML = `<div class="err-box">${IC.esc(e.message || e)}</div>`;
      return;
    }
    if (!el.isConnected) return;
    const { analyzePdf } = pdfText;
    const { verificarDdjj, hoyStr, fmtUsd } = chk;
    const { CASOS, EMPRESAS_DDJJ, CONTROLANTE, OPCION_4B, FORM_ID, FORM_FECHA, VALORES_CRITICOS } = tpl;

    const S = {
      caso: null,            // null | 'transito' | 'despacho'
      ddjjFiles: [], ciFiles: [],
      monto: '', empresa: 'CHEF', fechaFirma: hoyStr(),
      loading: false, progress: '', error: null, res: null,
      tildado: {}, verAnclas: false,
    };
    const vivo = () => el.isConnected;

    const preview = () => {
      const l = [];
      if (S.ddjjFiles[0]) l.push({ name: 'DDJJ 20320', file: S.ddjjFiles[0] });
      if (S.ciFiles[0]) l.push({ name: 'CI', file: S.ciFiles[0] });
      return l;
    };
    const reset = () => { S.res = null; S.error = null; S.tildado = {}; };

    // Tres partes que se pintan por separado: el formulario, el resultado y el visor de PDF. El visor sólo se
    // repinta si cambian los archivos (repintarlo recarga el iframe del PDF en cada tecla).
    let firmaPrev = null;
    const sec = (k) => el.querySelector(`[data-sec="${k}"]`);
    function render() {
      if (!vivo()) return;
      if (!S.caso) { firmaPrev = null; IC.pintar(el, paso1()); return; }
      if (!sec('dj-top')) { el.innerHTML = '<div><div data-sec="dj-top"></div><div data-sec="dj-res"></div><div data-sec="dj-prev"></div></div>'; firmaPrev = null; }
      IC.pintar(sec('dj-top'), formulario());
      renderRes();
      const pv = preview(); const firma = pv.map(x => x.file);
      if (!firmaPrev || firma.length !== firmaPrev.length || firma.some((f, i) => f !== firmaPrev[i])) {
        firmaPrev = firma;
        IC.pintar(sec('dj-prev'), pv.length ? `<div class="card">${IC.pdf.html('ddjj-preview', pv, { height: 620, title: '📄 Documentos subidos (mirar tildes y firma aca)' })}</div>` : '');
      }
    }
    function renderRes() { if (vivo() && sec('dj-res')) IC.pintar(sec('dj-res'), S.res ? resultado(S.res) : ''); }

    const verificar = async () => {
      reset();
      if (!S.ddjjFiles.length) { S.error = 'Subi la Declaracion Jurada 20320 completada (PDF).'; render(); return; }
      const montoNum = Number(String(S.monto).replace(/\./g, '').replace(',', '.'));
      if (!Number.isFinite(montoNum) || montoNum <= 0) { S.error = 'Ingresa el monto a transferir en USD.'; render(); return; }
      S.loading = true; render();
      try {
        S.progress = 'Leyendo la DDJJ...'; render();
        const a = await analyzePdf(S.ddjjFiles[0]);
        const ddjjTexto = a.text || (a.chunks || []).map(c => c.text).join('\n\n--- PAGINA ---\n\n');
        if (!ddjjTexto || ddjjTexto.length < 500) {
          throw new Error('El PDF de la DDJJ no tiene capa de texto legible (escaneo sin OCR). Pasalo por OCR o verificalo a mano.');
        }

        let ciTexto = '';
        if (S.ciFiles.length) {
          S.progress = 'Leyendo la CI...'; render();
          const b = await analyzePdf(S.ciFiles[0]);
          ciTexto = b.text || (b.chunks || []).map(c => c.text).join('\n');
        }

        S.progress = 'Verificando...'; render();
        S.res = verificarDdjj({ ddjjTexto, ciTexto, caso: S.caso, montoTransferir: montoNum, empresa: S.empresa, fechaFirma: S.fechaFirma });
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false; S.progress = '';
        render();
      }
    };

    // ------------------------------------------------------------ paso 1: el caso
    function paso1() {
      return `<div>
        <div class="card">
          <div class="card-header"><h3>🏦 Declaracion para presentar al Banco</h3></div>
          <div style="font-size:11px;color:#64748b">
            DDJJ <code>${IC.esc(FORM_ID)} (${IC.esc(FORM_FECHA)})</code> — Com. "A" 7030 y compl. del BCRA, Banco Credicoop.
            Elegi en que situacion esta la mercaderia al momento del pago.
          </div>
        </div>
        <div class="mode-grid">
          ${Object.values(CASOS).map(c => `<div class="mode-card" onclick="${IC.on(() => { reset(); S.caso = c.id; render(); })}">
            <div class="icon">${c.id === 'transito' ? '🚢' : '📥'}</div>
            <h3>${IC.esc(c.label)}</h3>
            <p>${IC.esc(c.desc)}</p>
            <span class="tag"${c.reglasDefinidas ? '' : ' style="color:#b45309;background:#fffbeb"'}>
              ${c.reglasDefinidas ? 'reglas cargadas · gratis' : 'reglas a definir · gratis'}
            </span>
          </div>`).join('')}
        </div>
      </div>`;
    }

    function formulario() {
      const cfg = CASOS[S.caso];
      const emp = EMPRESAS_DDJJ[S.empresa];
      return `<div class="card">
        <div class="card-header">
          <button class="back" onclick="${IC.on(() => { S.caso = null; reset(); IC.dz.olvidar('ddjj-form'); IC.dz.olvidar('ddjj-ci'); render(); })}">← Cambiar caso</button>
          <h3>🏦 ${IC.esc(cfg.label)}</h3>
        </div>

        <div style="font-size:11px;color:#64748b;margin-bottom:10px">${IC.esc(cfg.desc)}</div>

        ${!cfg.reglasDefinidas ? `<div style="font-size:11px;background:#fffbeb;border:1px solid #fcd34d;color:#92400e;padding:6px 9px;border-radius:6px;margin-bottom:10px">
          ⚠ Las reglas de llenado de este caso todavia no estan definidas en <code>docs/DDJJ-20320-Banco.md</code>.
          Se chequea formulario, redaccion, fechas, importe y cuadros; el tilde de pagina 2 queda como control manual.
        </div>` : ''}

        <div style="display:flex;gap:12px;flex-wrap:wrap">
          <div style="flex:1;min-width:240px">${IC.dz.html('ddjj-form', {
            label: 'Declaracion Jurada 20320 (completada)', icon: '📝', files: S.ddjjFiles, accept: '.pdf', single: true,
            onFiles: (f) => { S.ddjjFiles = f; reset(); render(); },
            onRemove: (i) => { S.ddjjFiles = S.ddjjFiles.filter((_, x) => x !== i); render(); },
          })}</div>
          <div style="flex:1;min-width:240px">${IC.dz.html('ddjj-ci', {
            label: 'Commercial Invoice (CI)', icon: '📄', files: S.ciFiles, accept: '.pdf', single: true,
            onFiles: (f) => { S.ciFiles = f; reset(); render(); },
            onRemove: (i) => { S.ciFiles = S.ciFiles.filter((_, x) => x !== i); render(); },
          })}</div>
        </div>

        <div style="display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end;margin-top:12px">
          <label style="font-size:11px">Monto a transferir (USD)<br>
            <input data-k="dj-monto" value="${IC.esc(S.monto)}" oninput="${IC.on((e) => { S.monto = e.target.value; const habia = S.res || S.error; reset(); if (habia) render(); })}"
              placeholder="14000" inputmode="decimal"
              style="padding:5px;font-size:12px;width:120px">
          </label>
          <label style="font-size:11px">Empresa<br>
            <select data-k="dj-emp" onchange="${IC.on((e) => { S.empresa = e.target.value; reset(); render(); })}" style="padding:5px;font-size:12px">
              ${IC.opts(Object.values(EMPRESAS_DDJJ).map(e2 => [e2.id, `${e2.id} — ${e2.razonSocial}`]), S.empresa)}
            </select>
          </label>
          <label style="font-size:11px">Fecha de firma<br>
            <input data-k="dj-fecha" value="${IC.esc(S.fechaFirma)}" oninput="${IC.on((e) => { S.fechaFirma = e.target.value; const habia = S.res || S.error; reset(); if (habia) render(); })}"
              placeholder="dd/mm/aaaa" style="padding:5px;font-size:12px;width:100px">
          </label>
          <div style="font-size:10px;color:#64748b;padding-bottom:4px">
            Caracter invocado: <strong>${IC.esc(emp.caracterFirmante)}</strong>
          </div>
        </div>

        <div class="toolbar" style="margin-top:12px">
          <button class="btn btn-primary" onclick="${IC.on(verificar)}" ${S.loading || !S.ddjjFiles.length ? 'disabled' : ''}>
            ${S.loading ? IC.esc(S.progress || 'Verificando...') : '🔍 Verificar declaracion'}
          </button>
        </div>

        ${S.error ? `<div class="err-box" style="margin-top:10px">${IC.esc(S.error)}</div>` : ''}
      </div>`;
    }

    // ---------------------------------------------------------------- resultado
    function resultado(res) {
      const { resumen, hallazgos, anclas, checklist, datos, ci, empresa, montoTransferir } = res;
      const bloqueado = resumen.alerta > 0;
      const faltan = checklist.filter(c => !S.tildado[c.id]).length;
      const verAnclas = S.verAnclas;

      return `<div class="card">
        <div class="card-header"><h3>Resultado</h3></div>

        <div style="${st({
          display: 'inline-block', padding: '6px 12px', borderRadius: 6, fontSize: 13, fontWeight: 700,
          background: bloqueado ? '#fef2f2' : '#f0fdf4',
          border: `1px solid ${bloqueado ? '#fca5a5' : '#86efac'}`,
          color: bloqueado ? '#b91c1c' : '#166534',
        })}">
          ${IC.esc(bloqueado ? `✗ ${resumen.veredicto} — ${resumen.alerta} problema${resumen.alerta > 1 ? 's' : ''}` : `✓ ${resumen.veredicto}`)}
        </div><span style="font-size:11px;color:#64748b;margin-left:10px">${IC.esc(resumen.ok)} ok · ${IC.esc(resumen.revisar)} a revisar · ${IC.esc(resumen.alerta)} alertas ·
          ${IC.esc(empresa.razonSocial)} · ${IC.esc(fmtUsd(montoTransferir))}
        </span>

        <div style="overflow-x:auto;margin-top:10px">
          <table style="border-collapse:collapse;font-size:12px;width:auto">
            <thead>
              <tr>
                <th style="${st(thS)}">&nbsp;</th>
                <th style="${st(thS)}">Campo</th>
                <th style="${st(thS, { whiteSpace: 'normal' })}">Detalle</th>
              </tr>
            </thead>
            <tbody>
              ${hallazgos.map(h => `<tr style="background:${h.nivel === 'alerta' ? '#fef2f2' : h.nivel === 'revisar' ? '#fffbeb' : 'transparent'}">
                <td style="${st(tdS, { color: COLOR[h.nivel], fontWeight: 700 })}">${IC.esc(ICONO[h.nivel])}</td>
                <td style="${st(tdS)}">${IC.esc(h.campo)}</td>
                <td style="${st(tdS, { whiteSpace: 'normal', minWidth: 320 })}">${IC.esc(h.msg)}</td>
              </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h3>Control visual obligatorio</h3>
          <span style="font-size:11px;color:${faltan ? '#b45309' : '#059669'}">
            ${faltan ? `${faltan} sin confirmar` : 'todo confirmado ✓'}
          </span>
        </div>
        <div style="font-size:11px;color:#64748b;margin-bottom:8px">
          Los tildes de los checkbox y la firma no se pueden leer del texto del PDF. Mirá el documento en el visor
          de abajo y confirmá cada punto. Regla base: cuadro 4.A con <strong>${IC.esc(CONTROLANTE.denominacion)}</strong>,
          tildado solo <em>Es controlante</em>, y punto 4.B opcion <strong>${IC.esc(OPCION_4B)})</strong>.
        </div>
        ${checklist.map(c => `<label style="display:flex;gap:7px;align-items:flex-start;font-size:12px;padding:3px 0;cursor:pointer">
          <input type="checkbox" data-k="dj-chk-${IC.esc(c.id)}" ${S.tildado[c.id] ? 'checked' : ''}
            onchange="${IC.on((e) => { S.tildado = Object.assign({}, S.tildado, { [c.id]: e.target.checked }); renderRes(); })}">
          <span style="color:${S.tildado[c.id] ? '#94a3b8' : '#334155'};text-decoration:${S.tildado[c.id] ? 'line-through' : 'none'}">
            ${IC.esc(c.txt)}
          </span>
        </label>`).join('')}
      </div>

      <div class="card">
        <div class="card-header">
          <h3>Redaccion del formulario</h3>
          <button class="back" onclick="${IC.on(() => { S.verAnclas = !S.verAnclas; renderRes(); })}">
            ${verAnclas ? 'ocultar detalle' : 'ver detalle'}
          </button>
        </div>
        <div style="font-size:12px">
          Formulario leido: <code>${IC.esc(datos.formId || '—')} (${IC.esc(datos.formFecha || '—')})</code> ·
          ${IC.esc(datos.paginasDetectadas)} paginas ·
          <strong style="color:${COLOR.ok}">${IC.esc(anclas.ok)} ok</strong>${anclas.revisar > 0 ? ` · <strong style="color:${COLOR.revisar}">${IC.esc(anclas.revisar)} parcial</strong>` : ''}${anclas.alerta > 0 ? ` · <strong style="color:${COLOR.alerta}">${IC.esc(anclas.alerta)} no encontrada${anclas.alerta > 1 ? 's' : ''}</strong>` : ''}
          de ${IC.esc(anclas.total)} frases clave.
        </div>
        <div style="font-size:10px;color:#94a3b8;margin-top:4px">
          Comparacion tolerante a ruido de OCR. Una frase "no encontrada" puede ser texto modificado por el banco
          o un escaneo malo: leerla a mano en el PDF antes de firmar.
        </div>

        <div style="font-size:11px;background:#fffbeb;border:1px solid #fcd34d;color:#92400e;padding:7px 9px;border-radius:6px;margin-top:10px">
          <strong>⚠ Los numeros finos NO se pueden verificar por OCR.</strong> Un cambio de un digito (30% → 50%,
          12/12/2023 → otra fecha, un punto normativo) no lo detecta la comparacion de texto. Coteja a ojo contra
          el PDF que estos valores sigan igual:
          <div style="overflow-x:auto;margin-top:6px">
            <table style="border-collapse:collapse;font-size:11px;width:auto">
              <tbody>
                ${VALORES_CRITICOS.map(v => `<tr>
                  <td style="${st(tdS, { background: '#fef3c7', fontWeight: 600 })}">Pag. ${IC.esc(v.pag)}</td>
                  <td style="${st(tdS, { whiteSpace: 'normal' })}">${IC.esc(v.items.join(' · '))}</td>
                </tr>`).join('')}
              </tbody>
            </table>
          </div>
        </div>
        ${verAnclas ? `<div class="report" data-k="dj-anclas" style="max-height:380px;overflow:auto">
          <table style="border-collapse:collapse;font-size:11px;width:auto">
            <thead><tr><th style="${st(thS)}">Pag</th><th style="${st(thS)}">%</th><th style="${st(thS, { whiteSpace: 'normal' })}">Frase del formulario</th></tr></thead>
            <tbody>
              ${anclas.items.filter(a => a.estado !== 'ok').concat(anclas.items.filter(a => a.estado === 'ok')).map(a => `<tr style="background:${a.estado === 'alerta' ? '#fef2f2' : a.estado === 'revisar' ? '#fffbeb' : 'transparent'}">
                <td style="${st(tdS, { textAlign: 'center' })}">${IC.esc(a.pag)}${a.movida ? `→${IC.esc(a.paginaHallada)}` : ''}</td>
                <td style="${st(tdS, { textAlign: 'right', color: COLOR[a.estado] })}">${Math.round(a.score * 100)}</td>
                <td style="${st(tdS, { whiteSpace: 'normal' })}">${IC.esc(a.txt)}</td>
              </tr>`).join('')}
            </tbody>
          </table>
        </div>` : ''}
      </div>

      ${ci ? `<div class="card">
        <div class="card-header"><h3>Datos leidos de la CI</h3></div>
        <table style="border-collapse:collapse;font-size:12px;width:auto">
          <tbody>
            <tr><td style="${st(tdS)}">Invoice</td><td style="${st(tdS)}"><code>${IC.esc(ci.invoice || '—')}</code></td></tr>
            <tr><td style="${st(tdS)}">Fecha</td><td style="${st(tdS)}">${IC.esc(ci.fecha || '—')}</td></tr>
            <tr><td style="${st(tdS)}">Importador</td><td style="${st(tdS)}">${IC.esc(ci.consignee || '—')}${ci.cuit ? ` · ${IC.esc(ci.cuit)}` : ''}</td></tr>
            <tr><td style="${st(tdS)}">Total CI</td><td style="${st(tdS)}">${IC.esc(fmtUsd(ci.total))}</td></tr>
          </tbody>
        </table>
      </div>` : ''}`;
    }

    render();
  });
})();
