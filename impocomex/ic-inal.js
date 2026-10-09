/* IMPO COMEX — INAL: certificados y vencimientos (port de InalMode.jsx + VencimientosInal.jsx).
   Una sola pantalla (r68: se unieron "NCM e INAL por producto" y "Vencimientos INAL"): vencimientos de
   cada certificado, una fila por artículo certificado (código, marca, descripción, importador,
   elaborador, N° y vencimiento), NCM por producto y alta desde el PDF. Todo va por la edge function
   Impo_Comex_inal-certificados. Se registra como 'inal' y como 'vencimientos' (tabInicial). */
(function () {
  'use strict';
  const IC = window.IC;
  const E = IC.esc;

  // ── VencimientosInal ────────────────────────────────────────────────────────────────
  const ESTADO_V = {
    vencido:         { txt: 'Vencido',         color: '#dc2626', bg: '#fef2f2', barra: '#dc2626' },
    por_vencer:      { txt: 'Por vencer',      color: '#b45309', bg: '#fffbeb', barra: '#f59e0b' },
    vigente:         { txt: 'Vigente',         color: '#059669', bg: 'transparent', barra: '#10b981' },
    sin_vencimiento: { txt: 'Sin vencimiento', color: '#64748b', bg: '#f8fafc', barra: '#cbd5e1' },
  };
  const ORDEN_ESTADO = ['vencido', 'por_vencer', 'vigente', 'sin_vencimiento'];
  const NW = 'white-space:nowrap';
  const SUB = 'font-size:10px;color:#64748b;font-weight:400';
  const fechaV = (f) => (f ? String(f).slice(0, 10).split('-').reverse().join('/') : '—');

  // V: estado propio de la solapa { propios, error, cargando, estado, tipo, buscar, abierto }
  // p: { certificados (si viene, va embebido), onRefrescar, onBorrar, venc (módulo), render }
  function vencNuevo() { return { propios: null, error: null, cargando: false, estado: 'todos', tipo: 'todos', buscar: '', abierto: null }; }
  async function vencRefrescar(V, render) {
    V.cargando = true; V.error = null; render();
    try { V.propios = (await IC.api.get('/inal-certificados?articulos=1')).certificados || []; }
    catch (e) { V.error = e.message || String(e); }
    finally { V.cargando = false; render(); }
  }
  function vencHtml(V, p) {
    const { AVISO_DIAS, falta, hoyLocal, vigenciaUsada } = p.venc;
    const render = p.render;
    const embebido = Array.isArray(p.certificados);
    const lista = embebido ? p.certificados : V.propios;
    const onBorrar = p.onBorrar;

    const hoy = hoyLocal();
    const certificados = (lista || [])
      .map(c => Object.assign({}, c, falta(c.fecha_vencimiento, hoy), { usada: vigenciaUsada(c.fecha_emision, c.fecha_vencimiento, hoy) }))
      .sort((a, b) => (a.dias ?? Infinity) - (b.dias ?? Infinity) || String(a.numero).localeCompare(String(b.numero)));
    const cuenta = { todos: certificados.length };
    for (const k of ORDEN_ESTADO) cuenta[k] = certificados.filter(c => c.estado === k).length;
    const tipos = [...new Set(certificados.map(c => c.tipo).filter(Boolean))].sort();
    const proximo = certificados.find(c => c.dias !== null && c.dias >= 0);

    const texto = V.buscar.trim().toUpperCase();
    const filas = certificados.filter(c =>
      (V.estado === 'todos' || c.estado === V.estado) &&
      (V.tipo === 'todos' || c.tipo === V.tipo) &&
      (!texto || [c.numero, c.titular_razon_social, c.marcas, c.fabricante, ...(c.codigos || [])]
        .some(v => String(v ?? '').toUpperCase().includes(texto))));
    const ncol = onBorrar ? 7 : 6;

    const filaHtml = (c) => {
      const e = ESTADO_V[c.estado];
      const codigos = c.codigos || [];
      let h = `<tr style="background:${e.bg}">
        <td style="${NW}" title="${E(c.descripcion || '')}"><code>${E(c.numero)}</code>
          <div style="${SUB}">${E([c.tipo, c.organismo].filter(Boolean).join(' · '))}</div></td>
        <td style="${NW}" title="${E(c.titular_cuit ? `CUIT ${c.titular_cuit}` : '')}">${E(c.titular_razon_social || '—')}</td>
        <td style="${NW};font-weight:600">${E(fechaV(c.fecha_vencimiento))}</td>
        <td style="${NW}"><div style="color:${e.color};font-weight:600">${E(c.texto)}</div>
          ${c.dias !== null && c.dias !== 0 ? `<div style="${SUB}">${E(c.dias < 0 ? `${e.txt} · hace ${-c.dias} días` : `${e.txt} · ${c.dias} días`)}</div>` : ''}
          ${c.dias === 0 ? `<div style="${SUB}">${E(e.txt)}</div>` : ''}</td>
        <td style="${NW}">
          ${c.usada === null ? '<span style="color:#94a3b8">—</span>' : `<span style="display:inline-flex;align-items:center;gap:4px"
              title="${E(`Emitido el ${fechaV(c.fecha_emision)}: ${c.usada} % de la vigencia ya transcurrido`)}">
              <span style="display:inline-block;width:56px;height:6px;background:#e2e8f0;border-radius:3px;overflow:hidden">
                <span style="display:block;width:${c.usada}%;height:100%;background:${e.barra}"></span></span>
              <span style="font-size:10px;color:#64748b">${E(c.usada)} %</span></span>`}
          ${c.fecha_emision ? `<div style="${SUB}">desde ${E(fechaV(c.fecha_emision))}</div>` : ''}</td>
        <td style="${NW}">${codigos.length
          ? `<button class="btn btn-secondary" style="padding:1px 6px;font-size:10px" onclick="${IC.on(() => { V.abierto = V.abierto === c.id ? null : c.id; render(); })}">${codigos.length} ${V.abierto === c.id ? '▲' : '▼'}</button>`
          : '<span style="color:#94a3b8">—</span>'}</td>
        ${onBorrar ? `<td style="${NW}"><button onclick="${IC.on(() => onBorrar(c))}" title="Borrar certificado"
            style="background:none;border:none;color:#dc2626;cursor:pointer;font-size:12px">🗑</button></td>` : ''}
      </tr>`;
      if (V.abierto === c.id) {
        const nom = new Map((c.productos || []).map(x => [x.codigo, x.descripcion]));
        h += `<tr><td colspan="${ncol}" style="font-size:11px;background:#f8fafc;white-space:normal">
          <div style="margin-bottom:4px;color:#475569">${E(c.fabricante ? `${c.fabricante} · ` : '')}Marcas: ${E(c.marcas || '—')}</div>
          <div style="display:grid;grid-template-columns:repeat(auto-fill, minmax(260px, 1fr));gap:2px 12px">
            ${codigos.map(k => `<div><code>${E(k)}</code> <span style="color:${nom.get(k) ? '#0f172a' : '#94a3b8'}">${E(nom.get(k) || 'sin nombre en el catálogo')}</span></div>`).join('')}
          </div></td></tr>`;
      }
      return h;
    };

    return `<div class="${embebido ? '' : 'card'}">
      ${!embebido ? `<div class="card-header">
          <h3>⏳ Vencimientos INAL</h3>
          <div style="flex:1"></div>
          <span style="font-size:10px;color:#94a3b8">Hoy ${E(fechaV(hoy))}</span>
          <button class="btn btn-secondary" style="padding:3px 8px;font-size:11px" onclick="${IC.on(() => (p.onRefrescar ? p.onRefrescar() : vencRefrescar(V, render)))}" ${V.cargando ? 'disabled' : ''}
            title="Volver a leer de la base">${V.cargando ? '⏳' : '🔄'}</button>
        </div>` : ''}
      ${V.error ? `<div class="err-box">${E(V.error)}</div>` : ''}
      ${!lista && !V.error ? '<div class="loading"><span class="pulse">●</span>Cargando...</div>' : ''}
      ${lista ? `
        <div class="stats" style="display:flex;flex-wrap:wrap">
          ${['todos', ...ORDEN_ESTADO].map(k => {
            const e = ESTADO_V[k];
            const activo = V.estado === k;
            return `<div class="stat" onclick="${IC.on(() => { V.estado = activo ? 'todos' : k; render(); })}"
                style="cursor:pointer;${activo ? 'outline:2px solid #2563eb' : ''}" title="${activo ? 'Mostrar todos' : 'Filtrar'}">
                <div class="k" style="${NW}">${E(k === 'todos' ? 'Certificados' : k === 'por_vencer' ? `Por vencer (≤ ${AVISO_DIAS} días)` : e.txt)}</div>
                <div class="v" style="${k !== 'todos' && k !== 'vigente' && cuenta[k] ? `color:${e.color}` : ''}">${cuenta[k]}</div>
              </div>`;
          }).join('')}
          ${proximo ? `<div class="stat">
              <div class="k">Próximo vencimiento</div>
              <div class="v" style="font-size:13px;color:${ESTADO_V[proximo.estado].color};${NW}">
                ${E(proximo.texto)} <span style="font-size:11px;font-weight:400;color:#64748b">${E(proximo.numero)} · ${E(fechaV(proximo.fecha_vencimiento))}</span>
              </div></div>` : ''}
        </div>

        <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin:10px 0 8px">
          ${['todos', ...tipos].map(t => `<button class="btn ${V.tipo === t ? 'btn-primary' : 'btn-secondary'}"
              style="padding:2px 8px;font-size:10px" onclick="${IC.on(() => { V.tipo = t; render(); })}">${E(t === 'todos' ? 'Todos los tipos' : t)}</button>`).join('')}
          <input data-k="venc-buscar" value="${E(V.buscar)}" oninput="${IC.on((ev) => { V.buscar = ev.target.value; render(); })}" placeholder="Buscar número, titular, marca o código"
            style="font-size:11px;padding:3px 6px;width:240px">
          ${(V.estado !== 'todos' || V.tipo !== 'todos' || texto) ? `<span style="font-size:10px;color:#64748b">${filas.length} de ${certificados.length}</span>` : ''}
        </div>

        <div class="report" data-k="venc-rep" style="overflow-x:auto;max-height:560px">
          <table style="font-size:12px;width:auto">
            <thead><tr>
              <th style="${NW}">Certificado</th><th style="${NW}">A nombre de</th><th style="${NW}">Vence</th>
              <th style="${NW}">Falta</th><th style="${NW}">Vigencia usada</th><th style="${NW}">Códigos</th>
              ${onBorrar ? '<th></th>' : ''}
            </tr></thead>
            <tbody>
              ${filas.map(filaHtml).join('')}
              ${filas.length === 0 ? `<tr><td colspan="${ncol}" style="color:#64748b;text-align:center">
                  ${certificados.length ? 'Ningún certificado con ese filtro.' : 'No hay certificados guardados.'}</td></tr>` : ''}
            </tbody>
          </table>
        </div>

        <div style="font-size:10px;color:#94a3b8;margin-top:8px">
          Los días se cuentan con la fecha de esta PC. "Por vencer" = vence en ${AVISO_DIAS} días o menos.
          ${embebido ? 'Para cargar o corregir un certificado: "+ Cargar certificado" (con el mismo número lo actualiza).' : 'Para cargar, corregir o borrar certificados: "INAL: certificados y vencimientos".'}
        </div>` : ''}
    </div>`;
  }

  // ── InalMode ────────────────────────────────────────────────────────────────────────
  const ESTADO = {
    vigente:         { txt: 'Vigente',         color: '#059669', bg: 'transparent' },
    por_vencer:      { txt: 'Por vencer',      color: '#b45309', bg: '#fffbeb' },
    vencido:         { txt: 'Vencido',         color: '#dc2626', bg: '#fef2f2' },
    sin_vencimiento: { txt: 'Sin vencimiento', color: '#64748b', bg: '#f8fafc' },
  };
  const CAMPOS_FORM = [
    ['numero', 'Número'], ['tipo', 'Tipo'], ['organismo', 'Organismo'],
    ['fecha_emision', 'Emisión'], ['vigencia_anios', 'Vigencia (años)'], ['fecha_vencimiento', 'Vencimiento'],
    ['titular_razon_social', 'Importador (titular)'], ['titular_cuit', 'CUIT importador'],
    ['fabricante', 'Elaborador (fabricante)'], ['pais_origen', 'País de origen'], ['marcas', 'Marcas'], ['expediente', 'Expediente'], ['anexo_if', 'Anexo IF'],
    ['deposito', 'Depósito (RNE)'], ['descripcion', 'Descripción'], ['notas', 'Notas'],
  ];
  const fecha = f => (f ? f.split('-').reverse().join('/') : '—');
  const TABS = [
    ['vencimientos', '⏳ Vencimientos'], ['articulos', '📦 Artículos certificados'],
    ['productos', 'NCM por producto'], ['cargar', '+ Cargar certificado'],
  ];

  // Códigos del borrador con su marca y descripción (lo que el anexo dice de cada uno).
  function filasDe(codigos, productos) {
    const por = new Map((productos || []).map(p => [String(p.codigo || '').toUpperCase().trim(), p]));
    const lista = [...new Set([...(codigos || []), ...por.keys()].map(c => String(c || '').toUpperCase().trim()).filter(Boolean))];
    return lista.map(codigo => ({ codigo, marca: por.get(codigo)?.marca || '', descripcion: por.get(codigo)?.descripcion || '' }));
  }
  const codigosDe = filas => [...new Set(filas.map(f => f.codigo.trim().toUpperCase()).filter(Boolean))];

  async function modoInal(el, opts) {
    const miVista = IC.vistaActual();
    const inst = {}; el.__icInst = inst;
    const vivo = () => el.isConnected && el.__icInst === inst && IC.vistaActual() === miVista;
    el.innerHTML = '<div class="loading"><span class="pulse">●</span>Cargando...</div>';
    const venc = await IC.mod('vencimientos');
    if (!vivo()) return;

    // Estado de cada solapa (se reinicia al cambiar de solapa, como al desmontar en React).
    const nuevo = {
      vencimientos: vencNuevo,
      articulos: () => ({ buscar: '', estado: 'todos' }),
      productos: () => ({ filtro: 'todos', editando: null, ncm: '', enfocar: false }),
      cargar: () => { IC.dz.olvidar('inal-docs'); return { files: [], loading: false, progress: '', error: null, avisos: [], borradores: [] }; },
    };
    const tabInicial = (opts && opts.tabInicial) || 'vencimientos';
    const S = { tab: tabInicial, data: null, error: null, cargando: false, sub: nuevo[tabInicial]() };

    function render() {
      if (!vivo()) return;
      IC.pintar(el, html());
      if (S.tab === 'productos' && S.sub.enfocar) {
        S.sub.enfocar = false;
        const inp = el.querySelector('[data-k="inal-ncm"]'); if (inp) inp.focus();
      }
    }
    function setTab(t) { if (t !== S.tab) { S.tab = t; S.sub = nuevo[t](); } render(); }

    const refrescar = async () => {
      S.cargando = true; S.error = null; render();
      try { S.data = await IC.api.get('/inal-certificados?productos=1&articulos=1'); }
      catch (e) { S.error = e.message || String(e); }
      finally { S.cargando = false; render(); }
    };

    function html() {
      const t = S.tab, d = S.data;
      return `<div><div class="card">
        <div class="card-header" style="flex-wrap:wrap">
          <h3>🛡️ INAL: certificados y vencimientos</h3>
          <div style="flex:1"></div>
          ${TABS.map(([k, txt]) => `<button class="btn ${t === k ? 'btn-primary' : 'btn-secondary'}"
            style="padding:4px 12px;font-size:12px" onclick="${IC.on(() => setTab(k))}">${E(txt)}</button>`).join('')}
          <button class="btn btn-secondary" style="padding:4px 10px;font-size:12px" onclick="${IC.on(refrescar)}" ${S.cargando ? 'disabled' : ''}
            title="Volver a leer de la base">${S.cargando ? '⏳' : '🔄'}</button>
        </div>
        ${S.error ? `<div class="err-box">${E(S.error)}</div>` : ''}
        ${!d && !S.error && t !== 'cargar' ? '<div class="loading"><span class="pulse">●</span>Cargando...</div>' : ''}
        ${d && t === 'vencimientos' ? vencHtml(S.sub, { certificados: d.certificados || [], onRefrescar: refrescar, venc, render }) : ''}
        ${d && t === 'articulos' ? articulosHtml(S.sub, d.articulos || []) : ''}
        ${d && t === 'productos' ? productosHtml(S.sub, d.productos || []) : ''}
        ${t === 'cargar' ? cargarHtml(S.sub) : ''}
      </div></div>`;
    }

    // ── Artículos certificados ────────────────────────────────────────────────────────
    // Una fila por código certificado. Marca y descripción: las del certificado para ese código; si el
    // certificado no las trae, las del producto (productos_referencia) y, si no, las generales del CE.
    // Un código se busca también en sus versiones con y sin letras: 437 encuentra 437E y 437EL,
    // 025E encuentra 25. Se compara el número pelado (sin ceros adelante ni letras).
    const numDe = c => (String(c ?? '').toUpperCase().trim().match(/^0*(\d+)/) || [])[1] || '';
    function artFilas(A, articulos) {
      const texto = A.buscar.trim().toUpperCase();
      const numBuscado = /^\d+[A-Z]*$/.test(texto) ? numDe(texto) : '';
      return articulos.filter(a =>
        (A.estado === 'todos' || a.estado === A.estado) &&
        (!texto || (numBuscado && numDe(a.codigo) === numBuscado) ||
          [a.codigo, a.descripcion_de, a.marca, a.descripcion, a.importador, a.elaborador, a.numero]
            .some(v => String(v ?? '').toUpperCase().includes(texto))));
    }
    // Baja lo que se ve (búsqueda y filtro aplicados), con las mismas 7 columnas + estado.
    // Excel en formato cuadro sinóptico: rótulo arriba del dato (partido en 2 líneas), ancho según el
    // dato, todo centrado, sin color ni relleno, ordenado por gravedad (vencido → sin vencimiento).
    async function artDescargar(A) {
      const filas = artFilas(A, (S.data && S.data.articulos) || []);
      try {
        const m = await IC.lib('xlsx-js-style'); const XS = m.default || m;
        const GRAV = { vencido: 0, por_vencer: 1, vigente: 2, sin_vencimiento: 3 };
        const orden = [...filas].sort((a, b) =>
          (GRAV[a.estado] ?? 3) - (GRAV[b.estado] ?? 3)
          || (a.dias_restantes ?? 1e9) - (b.dias_restantes ?? 1e9)
          || String(a.codigo).localeCompare(String(b.codigo), 'es', { numeric: true }));
        const cols = [
          ['Código', a => a.codigo],
          ['Marca', a => a.marca || '—'],
          ['Descripción', a => a.descripcion || '—'],
          ['Nombre\ntomado de', a => (a.descripcion_prio > 1 ? a.descripcion_de : '')],
          ['Importador', a => a.importador || '—'],
          ['Elaborador', a => a.elaborador || '—'],
          ['N°\ncertificado', a => a.numero || '—'],
          ['Vence', a => fecha(a.fecha_vencimiento)],
          ['Días\nrestantes', a => (a.dias_restantes == null ? '—' : a.dias_restantes)],
          ['Estado', a => (ESTADO[a.estado] || ESTADO.sin_vencimiento).txt],
        ].filter(([, f]) => orden.some(a => f(a) !== '' && f(a) !== '—'));   // sin columnas vacías
        const hoy = new Date().toLocaleDateString('es-AR');
        const aoa = [[`Artículos con certificado INAL · al ${hoy} · ${orden.length} artículos`],
          cols.map(c => c[0]), ...orden.map(a => cols.map(([, f]) => f(a)))];
        const ws = XS.utils.aoa_to_sheet(aoa);
        ws['!merges'] = [{ s: { r: 0, c: 0 }, e: { r: 0, c: cols.length - 1 } }];
        const borde = { style: 'thin', color: { rgb: '000000' } };
        const bordes = { top: borde, bottom: borde, left: borde, right: borde };
        const centro = { horizontal: 'center', vertical: 'center', wrapText: true };
        for (let r = 0; r < aoa.length; r++) for (let c = 0; c < cols.length; c++) {
          const ref = XS.utils.encode_cell({ r, c });
          if (!ws[ref]) ws[ref] = { t: 's', v: '' };
          ws[ref].s = r === 0 ? { font: { bold: true, sz: 16 }, alignment: centro }
            : { font: { bold: r === 1, sz: r === 1 ? 16 : 14 }, alignment: centro, border: bordes };
        }
        // Ancho = el dato más largo (el rótulo ya va partido); texto largo se corta en 45 y hace 2 líneas.
        ws['!cols'] = cols.map((c) => ({ wch: Math.min(45, Math.max(
          ...c[0].split('\n').map(x => x.length), ...orden.map(a => String(c[1](a)).length)) + 2) }));
        ws['!rows'] = [{ hpt: 24 }, { hpt: 40 }];
        const wb = XS.utils.book_new();
        XS.utils.book_append_sheet(wb, ws, 'Artículos certificados');
        XS.writeFile(wb, `articulos-certificados-${new Date().toISOString().slice(0, 10)}.xlsx`);
      } catch (e) { IC.avisar('No se pudo armar el Excel: ' + (e.message || e)); }
    }
    function articulosHtml(A, articulos) {
      const filas = artFilas(A, articulos);
      const cuenta = k => articulos.filter(a => a.estado === k).length;
      return `
        <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin-bottom:8px">
          <input data-k="art-buscar" value="${E(A.buscar)}" oninput="${IC.on((ev) => { A.buscar = ev.target.value; render(); })}" placeholder="Buscar código, marca, descripción, importador, elaborador o N°"
            style="font-size:13px;padding:5px 8px;width:380px;max-width:100%">
          ${['todos', 'vencido', 'por_vencer', 'vigente'].map(k => `<button class="btn ${A.estado === k ? 'btn-primary' : 'btn-secondary'}"
              style="padding:3px 10px;font-size:12px" onclick="${IC.on(() => { A.estado = k; render(); })}">
              ${E(k === 'todos' ? `Todos (${articulos.length})` : `${ESTADO[k].txt} (${cuenta(k)})`)}</button>`).join('')}
          <span style="font-size:12px;color:#64748b">${filas.length} artículo${filas.length === 1 ? '' : 's'}</span>
          <div style="flex:1"></div>
          <button class="btn btn-success" style="padding:3px 12px;font-size:12px" onclick="${IC.on(() => artDescargar(A))}"
            ${!filas.length ? 'disabled' : ''} title="Baja lo que se ve, con la búsqueda y el filtro aplicados">⬇ Descargar Excel</button>
        </div>
        <div class="report" data-k="art-rep" style="overflow-x:auto;max-height:620px">
          <table style="font-size:13px;width:auto">
            <thead><tr>
              <th style="${NW}">Código</th><th style="${NW}">Marca</th><th>Descripción</th>
              <th style="${NW}">Importador</th><th style="${NW}">Elaborador</th><th style="${NW}">N° Certificado</th><th style="${NW}">Vencimiento</th>
            </tr></thead>
            <tbody>
              ${filas.map(a => {
                const e = ESTADO[a.estado] || ESTADO.sin_vencimiento;
                return `<tr style="background:${e.bg}">
                  <td style="${NW}"><code>${E(a.codigo)}</code></td>
                  <td style="${NW}">${E(a.marca || '—')}</td>
                  <td style="min-width:200px;max-width:360px">
                    ${a.descripcion ? E(a.descripcion) : '<span style="color:#94a3b8">sin nombre en el catálogo</span>'}
                    ${a.descripcion && a.descripcion_prio > 1 ? `<span style="color:#94a3b8;font-size:11px;margin-left:6px"
                        title="El código exacto no está en el catálogo: el nombre sale de esta versión del código">(de ${E(a.descripcion_de)})</span>` : ''}
                  </td>
                  <td style="${NW}">${E(a.importador || '—')}</td>
                  <td style="min-width:160px;max-width:280px">${E(a.elaborador || '—')}</td>
                  <td style="${NW}"><code style="font-size:12px">${E(a.numero)}</code></td>
                  <td style="${NW}"><span style="font-weight:600">${E(fecha(a.fecha_vencimiento))}</span>
                    ${a.estado !== 'vigente' ? `<span style="color:${e.color};font-weight:600;margin-left:6px">${E(e.txt)}</span>` : ''}</td>
                </tr>`;
              }).join('')}
              ${filas.length === 0 ? `<tr><td colspan="7" style="color:#64748b;text-align:center">
                  ${articulos.length ? 'Ningún artículo con ese filtro.' : 'No hay artículos certificados.'}</td></tr>` : ''}
            </tbody>
          </table>
        </div>`;
    }

    // ── NCM por producto ──────────────────────────────────────────────────────────────
    const FILTROS = [
      ['todos', 'Todos'], ['sin_ncm', 'Sin NCM'], ['sin_certificado', 'Sin certificado'],
      ['variante', 'Certificado de otra variante'], ['conflicto', 'NCM en conflicto'],
    ];
    async function guardarNcm(P, p) {
      try {
        await IC.api.postJson('/inal-certificados', { accion: 'guardar_ncm', producto_id: p.producto_id, ncm: P.ncm.trim() });
        P.editando = null; refrescar();
      } catch (e) { IC.avisar('Error: ' + (e.message || e)); }
    }
    function productosHtml(P, productos) {
      const cuenta = {
        todos: productos.length,
        sin_ncm: productos.filter(p => !p.ncm).length,
        sin_certificado: productos.filter(p => !p.certificado_id).length,
        variante: productos.filter(p => p.tipo_match === 'base').length,
        conflicto: productos.filter(p => p.conflicto).length,
      };
      const f = P.filtro;
      const lista = productos.filter(p =>
        f === 'todos' ? true :
        f === 'sin_ncm' ? !p.ncm :
        f === 'sin_certificado' ? !p.certificado_id :
        f === 'variante' ? p.tipo_match === 'base' :
        p.conflicto);
      return `
        <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:8px">
          ${FILTROS.map(([k, t]) => `<button class="btn ${f === k ? 'btn-primary' : 'btn-secondary'}"
            style="padding:2px 8px;font-size:10px" onclick="${IC.on(() => { P.filtro = k; render(); })}">${E(t)} (${cuenta[k]})</button>`).join('')}
        </div>
        <div style="font-size:10px;color:#94a3b8;margin-bottom:6px">
          "Sin certificado" incluye productos que no requieren INAL: el control real se hace en cada despacho según el NCM.
          "Otra variante" = el CE cubre el mismo código base con otro sufijo o marca; confirmar que esté autorizado.
        </div>
        <div class="report" data-k="prod-rep" style="overflow-x:auto;max-height:520px">
          <table style="font-size:12px;width:auto">
            <thead><tr>
              <th style="${NW}">Prov.</th><th style="${NW}">LK</th><th style="${NW}">CH</th><th>Producto</th>
              <th style="${NW}">NCM</th><th style="${NW}">Fuente</th><th style="${NW}">Certificado</th><th style="${NW}">Estado</th>
            </tr></thead>
            <tbody>
              ${lista.map(p => {
                const e = p.estado ? (ESTADO[p.estado] || ESTADO.sin_vencimiento) : null;
                const ncmCel = P.editando === p.producto_id
                  ? `<span style="display:inline-flex;gap:3px">
                      <input data-k="inal-ncm" value="${E(P.ncm)}" oninput="${IC.on((ev) => { P.ncm = ev.target.value; })}" placeholder="7323.93.00.910T"
                        style="font-size:11px;padding:2px;width:120px"
                        onkeydown="${IC.on((ev) => { if (ev.key === 'Enter') guardarNcm(P, p); if (ev.key === 'Escape') { P.editando = null; render(); } })}">
                      <button class="btn btn-success" style="padding:1px 6px;font-size:10px" onclick="${IC.on(() => guardarNcm(P, p))}">✓</button>
                    </span>`
                  : `<span style="cursor:pointer" title="${E(p.conflicto ? `Vistos en despachos: ${(p.ncms_vistos || []).join(', ')}` : 'Click para editar')}"
                      onclick="${IC.on(() => { P.editando = p.producto_id; P.ncm = p.ncm || ''; P.enfocar = true; render(); })}">
                      ${p.ncm ? `<code>${E(p.ncm)}</code>` : '<span style="color:#94a3b8">+ cargar</span>'}
                      ${p.conflicto ? '<span style="color:#dc2626"> ⚠</span>' : ''}
                    </span>`;
                return `<tr style="${p.conflicto ? 'background:#fef2f2' : ''}">
                  <td style="${NW}">${E(p.proveedor)}</td>
                  <td style="${NW}"><code>${E(p.cod_lk || '')}</code></td>
                  <td style="${NW}"><code>${E(p.cod_ch || '')}</code></td>
                  <td style="max-width:260px;overflow:hidden;text-overflow:ellipsis;${NW}" title="${E(p.nombre_producto)}">${E(p.nombre_producto)}</td>
                  <td style="${NW}">${ncmCel}</td>
                  <td style="${NW};font-size:10px;color:#64748b">${E(p.ncm_fuente || '')}</td>
                  <td style="${NW}">${p.numero
                    ? `<code style="font-size:10px">${E(p.numero)}</code>${p.tipo_match === 'base' ? '<span style="color:#b45309" title="Cubre otra variante del mismo código base"> ≈</span>' : ''}`
                    : '<span style="color:#94a3b8">—</span>'}</td>
                  <td style="${NW};${e ? `color:${e.color};` : ''}font-weight:${e ? 600 : 400}">${E(e ? e.txt : '')}</td>
                </tr>`;
              }).join('')}
            </tbody>
          </table>
        </div>`;
    }

    // ── + Cargar certificado ──────────────────────────────────────────────────────────
    // Un borrador por certificado encontrado: { datos, filas, existente, estado: null | 'guardando' | 'guardado' | 'descartado', error }
    async function extraer(C) {
      C.error = null; C.avisos = []; C.borradores = [];
      C.loading = true; render();
      try {
        const { extractText } = await IC.mod('pdfText');
        const files = C.files;
        const fd = new FormData();
        fd.append('accion', 'extraer');
        for (let i = 0; i < files.length; i++) {
          C.progress = `Preparando ${i + 1}/${files.length}...`; render();
          fd.append(`archivo_${i}`, files[i], files[i].name);
          const texto = await extractText(files[i], { campos: true });
          if (texto) fd.append(`texto_${i}`, texto);
        }
        C.progress = 'Leyendo certificados con IA...'; render();
        const r = await IC.api.postForm('/inal-certificados', fd);
        const lista = r.borradores || (r.borrador ? [r.borrador] : []);
        C.borradores = lista.map(b => {
          const { codigos, productos, ...datos } = b;
          const numero = String(b.numero || '').toUpperCase().trim();
          return { datos, filas: filasDe(codigos, productos), existente: r.existentes?.[numero] || (lista.length === 1 ? r.existente : null), estado: null, error: null };
        });
        C.avisos = r.errores || [];
      } catch (e) {
        C.error = e.message || String(e);
      } finally { C.loading = false; C.progress = ''; render(); }
    }
    const cambiar = (C, i, cambio) => { C.borradores = C.borradores.map((b, k) => (k === i ? Object.assign({}, b, cambio) : b)); };
    async function guardarUno(C, i, lista = C.borradores) {
      const b = lista[i];
      cambiar(C, i, { estado: 'guardando', error: null }); render();
      try {
        await IC.api.postJson('/inal-certificados', {
          accion: 'guardar', certificado: b.datos,
          codigos: codigosDe(b.filas),
          productos: b.filas.map(f => ({ codigo: f.codigo.trim().toUpperCase(), marca: f.marca || null, descripcion: f.descripcion || null })),
        });
        cambiar(C, i, { estado: 'guardado' }); render();
        refrescar();
        return true;
      } catch (e) {
        cambiar(C, i, { estado: null, error: e.message || String(e) }); render();
        return false;
      }
    }
    async function guardarTodos(C) {
      const lista = C.borradores;
      for (let i = 0; i < lista.length; i++) {
        if (!lista[i].estado && lista[i].datos.numero) await guardarUno(C, i, lista);
      }
    }
    // cambio de un dato del borrador i (cada tecla: el botón Guardar depende del número)
    const setDato = (C, i, k, v) => { const b = C.borradores[i]; cambiar(C, i, { datos: Object.assign({}, b.datos, { [k]: v }) }); render(); };
    const setFilas = (C, i, filas) => { cambiar(C, i, { filas }); render(); };

    function tablaCodigosHtml(C, i, filas) {
      const inp = 'font-size:13px;padding:3px 5px;width:100%';
      // las filas se leen del estado en el momento del evento (no de este render)
      const filasAhora = () => C.borradores[i].filas;
      return `<div style="margin-top:4px">
        <div style="font-size:12px;color:#475569;margin-bottom:4px">
          Artículos cubiertos (${codigosDe(filas).length}) — marca y descripción de cada código según el anexo. Si quedan vacías se usan las del producto.
        </div>
        <table style="font-size:13px;width:100%">
          <thead><tr><th style="width:110px">Código</th><th style="width:200px">Marca</th><th>Descripción</th><th style="width:30px"></th></tr></thead>
          <tbody>
            ${filas.map((f, k) => `<tr>
              <td><input data-k="inal-b${i}-c${k}-codigo" value="${E(f.codigo)}" oninput="${IC.on((ev) => { const fs = filasAhora(); setFilas(C, i, fs.map((g, x) => (x === k ? Object.assign({}, g, { codigo: ev.target.value }) : g))); })}" style="${inp};font-family:monospace"></td>
              <td><input data-k="inal-b${i}-c${k}-marca" value="${E(f.marca)}" oninput="${IC.on((ev) => { const fs = filasAhora(); setFilas(C, i, fs.map((g, x) => (x === k ? Object.assign({}, g, { marca: ev.target.value }) : g))); })}" style="${inp}"></td>
              <td><input data-k="inal-b${i}-c${k}-descripcion" value="${E(f.descripcion)}" oninput="${IC.on((ev) => { const fs = filasAhora(); setFilas(C, i, fs.map((g, x) => (x === k ? Object.assign({}, g, { descripcion: ev.target.value }) : g))); })}" style="${inp}"></td>
              <td><button onclick="${IC.on(() => setFilas(C, i, filasAhora().filter((_, x) => x !== k)))}" title="Quitar código"
                style="background:none;border:none;color:#dc2626;cursor:pointer">✕</button></td>
            </tr>`).join('')}
          </tbody>
        </table>
        <button class="btn btn-secondary" style="padding:3px 10px;font-size:12px;margin-top:4px"
          onclick="${IC.on(() => setFilas(C, i, [...filasAhora(), { codigo: '', marca: '', descripcion: '' }]))}">+ Agregar código</button>
      </div>`;
    }

    function cargarHtml(C) {
      const bs = C.borradores;
      const pendientes = bs.filter(b => !b.estado || b.estado === 'guardando');
      const terminado = bs.length > 0 && pendientes.length === 0;
      return `<div>
        <div style="font-size:11px;color:#64748b;margin-bottom:8px">
          Subí el <strong>CE</strong> junto con su <strong>anexo IF</strong> (o la ficha técnica), que es donde están el titular,
          el fabricante y los códigos. Para un RNE alcanza con el PDF del RNE. Podés soltar la <strong>carpeta o el .zip / .rar</strong> que
          mandó el proveedor, aunque traiga varias familias: se lee cada carpeta o comprimido por separado y te muestro un borrador
          por certificado para revisar antes de guardar.
        </div>
        ${IC.dz.html('inal-docs', { label: 'Documentos de los trámites', icon: '📑', files: C.files,
          onFiles: fs => { C.files = [...C.files, ...fs]; render(); },
          onRemove: i => { C.files = C.files.filter((_, x) => x !== i); render(); },
          accept: '.pdf,image/*' })}
        <div class="toolbar">
          <button class="btn btn-primary" onclick="${IC.on(() => extraer(C))}" ${C.loading || !C.files.length ? 'disabled' : ''}>
            ${E(C.loading ? (C.progress || 'Leyendo...') : '🔍 Leer documentos')}
          </button>
          ${C.files.length > 0 && !C.loading ? `<button class="btn btn-secondary" onclick="${IC.on(() => { C.files = []; C.borradores = []; C.avisos = []; render(); })}">Limpiar</button>` : ''}
        </div>
        ${C.error ? `<div class="err-box">${E(C.error)}</div>` : ''}
        ${C.avisos.length > 0 ? `<div class="alerts">${C.avisos.map(a => `<div class="alert importante">No se pudo leer: ${E(a)}</div>`).join('')}</div>` : ''}

        ${bs.length > 0 ? `<div class="toolbar" style="margin-top:10px">
          <strong style="font-size:12px">${bs.length} certificado${bs.length > 1 ? 's' : ''} encontrado${bs.length > 1 ? 's' : ''}</strong>
          ${bs.length > 1 && pendientes.length > 0 ? `<button class="btn btn-success" onclick="${IC.on(() => guardarTodos(C))}" ${bs.some(b => b.estado === 'guardando') ? 'disabled' : ''}>
              💾 Guardar todos (${pendientes.length})</button>` : ''}
          ${terminado ? `<button class="btn btn-primary" onclick="${IC.on(() => { refrescar(); setTab('articulos'); })}">Ver certificados</button>` : ''}
        </div>` : ''}

        ${bs.map((b, i) => `<div style="margin-top:10px;border:1px solid #e2e8f0;border-radius:6px;padding:10px;opacity:${b.estado === 'descartado' ? 0.5 : 1};${b.estado === 'guardado' ? 'background:#f0fdf4' : ''}">
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:6px">
            <strong style="font-size:12px">${i + 1}. ${E(b.datos.numero || 'Sin número')}</strong>
            <span style="font-size:10px;color:#64748b" title="${E(b.datos.archivo_nombre || '')}">
              ${String(b.datos.archivo_nombre || '').split(' | ').length} documento(s)</span>
            <div style="flex:1"></div>
            ${b.estado === 'guardado' ? '<span style="font-size:11px;color:#059669;font-weight:600">✓ Guardado</span>' : ''}
            ${b.estado === 'descartado' ? '<span style="font-size:11px;color:#64748b">Descartado</span>' : ''}
          </div>
          ${b.existente && !b.estado ? `<div class="alert importante" style="margin-bottom:8px">
              ${E(b.existente.numero)} ya está cargado. Guardar lo actualiza y reemplaza su lista de códigos.</div>` : ''}
          ${!b.estado || b.estado === 'guardando' ? `
            <div style="display:grid;grid-template-columns:repeat(auto-fill, minmax(220px, 1fr));gap:8px">
              ${CAMPOS_FORM.map(([k, label]) => `<label style="font-size:11px;color:#475569;${['descripcion', 'notas', 'deposito'].includes(k) ? 'grid-column:1 / -1' : ''}">
                ${E(label)}<br>
                ${k === 'tipo'
                  ? `<select data-k="inal-b${i}-${k}" onchange="${IC.on((ev) => setDato(C, i, 'tipo', ev.target.value))}" style="font-size:12px;padding:3px">
                      ${IC.opts([['CE', 'CE'], ['RNE', 'RNE'], ['OTRO', 'Otro']], b.datos.tipo || 'CE')}</select>`
                  : k === 'organismo'
                    ? `<select data-k="inal-b${i}-${k}" onchange="${IC.on((ev) => setDato(C, i, 'organismo', ev.target.value || null))}" style="font-size:12px;padding:3px">
                        ${IC.opts([['', '—'], 'ANMAT', 'SENASA', 'INAL', 'OTRO'], b.datos.organismo || '')}</select>`
                    : `<input data-k="inal-b${i}-${k}" value="${E(b.datos[k] ?? '')}" oninput="${IC.on((ev) => setDato(C, i, k, ev.target.value))}"
                        type="${k.startsWith('fecha') ? 'date' : k === 'vigencia_anios' ? 'number' : 'text'}"
                        style="font-size:12px;padding:3px;width:100%">`}
              </label>`).join('')}
            </div>
            <div style="font-size:10px;color:#94a3b8;margin:4px 0 8px">
              Si el vencimiento queda vacío se calcula como emisión + vigencia.
            </div>
            ${tablaCodigosHtml(C, i, b.filas)}
            ${b.error ? `<div class="err-box">${E(b.error)}</div>` : ''}
            <div class="toolbar">
              <button class="btn btn-success" onclick="${IC.on(() => guardarUno(C, i))}" ${b.estado === 'guardando' || !b.datos.numero ? 'disabled' : ''}>
                ${b.estado === 'guardando' ? 'Guardando...' : '💾 Guardar certificado'}</button>
              <button class="btn btn-secondary" onclick="${IC.on(() => { cambiar(C, i, { estado: 'descartado' }); render(); })}" ${b.estado === 'guardando' ? 'disabled' : ''}>Descartar</button>
            </div>`
          : `<div style="font-size:11px;color:#475569">
              ${E(b.datos.titular_razon_social || '—')} · vence ${E(b.datos.fecha_vencimiento || '—')} · ${codigosDe(b.filas).length} códigos
            </div>`}
        </div>`).join('')}
      </div>`;
    }

    render();
    refrescar();
  }

  IC.modo('inal', modoInal);
  IC.modo('vencimientos', modoInal);
})();
