/* IMPO COMEX — Historial y Comparador (port de History.jsx).
   Mismos pedidos: editar('cargas_lista', { limite: 50 }), /compare-historical y el Excel por carga. */
(function () {
  'use strict';
  const IC = window.IC;

  IC.modo('history', async function (el) {
    const api = IC.api;
    const S = { cargas: [], loading: true, proveedor: '', codigo: '', comparador: null };
    const vivo = () => el.isConnected;
    function render() { if (vivo()) IC.pintar(el, html()); }

    async function comparar() {
      if (!S.proveedor || !S.codigo) return;
      try {
        const j = await api.get(`/compare-historical?proveedor=${encodeURIComponent(S.proveedor)}&codigo=${encodeURIComponent(S.codigo)}`);
        S.comparador = j;
      } catch (e) {
        S.comparador = { error: e.message };
      }
      render();
    }

    async function downloadExcel(cargaId) {
      try { await api.descargar(`/export-excel?carga_id=${cargaId}`, `verificacion_carga_${cargaId}.xlsx`); }
      catch (e) { IC.avisar('No se pudo descargar el Excel: ' + (e.message || e)); }
    }

    // El botón Buscar se habilita con los dos campos: se toca sólo el botón (no se repinta mientras se tipea).
    function botonBuscar() {
      const b = el.querySelector('[data-k="hi-buscar"]');
      if (b) b.disabled = !S.proveedor || !S.codigo;
    }

    const usd = (v) => (v != null ? v.toFixed(2) : '');

    function html() {
      const comparador = S.comparador, cargas = S.cargas, loading = S.loading;
      return `<div>
      <div class="card">
        <div class="card-header"><h3>📊 Comparador de artículo</h3></div>
        <div style="display:flex;gap:8px;align-items:flex-end">
          <label style="font-size:11px">
            Proveedor<br>
            <input data-k="hi-prov" value="${IC.esc(S.proveedor)}" placeholder="OWNLAND"
              oninput="${IC.on((e) => { S.proveedor = e.target.value; botonBuscar(); })}"
              style="padding:6px;border:1px solid #cbd5e1;border-radius:5px;margin-top:3px">
          </label>
          <label style="font-size:11px">
            Código<br>
            <input data-k="hi-cod" value="${IC.esc(S.codigo)}" placeholder="574E"
              oninput="${IC.on((e) => { S.codigo = e.target.value; botonBuscar(); })}"
              style="padding:6px;border:1px solid #cbd5e1;border-radius:5px;margin-top:3px">
          </label>
          <button class="btn btn-primary" data-k="hi-buscar" onclick="${IC.on(comparar)}" ${!S.proveedor || !S.codigo ? 'disabled' : ''}>Buscar</button>
        </div>

        ${comparador && !comparador.error && comparador.apariciones > 0 ? `<div style="margin-top:12px">
            <div class="stats">
              <div class="stat"><div class="k">Apariciones</div><div class="v">${IC.esc(comparador.apariciones)}</div></div>
              <div class="stat"><div class="k">Precio Prom.</div><div class="v">$${IC.esc(usd(comparador.precio_promedio))}</div></div>
              <div class="stat"><div class="k">Precio Min/Max</div><div class="v" style="font-size:11px">$${IC.esc(usd(comparador.precio_min))} / $${IC.esc(usd(comparador.precio_max))}</div></div>
              <div class="stat"><div class="k">Uni/Master</div><div class="v">${IC.esc(comparador.uni_master_promedio)}</div></div>
            </div>
            <div class="report" data-k="hi-comp" style="margin-top:10px;max-height:300px">
              <table>
                <thead><tr><th>Carga</th><th>Fecha</th><th>Precio</th><th>Cant</th><th>Uni/Master</th><th>CBM/Caja</th></tr></thead>
                <tbody>
                  ${(comparador.cargas || []).map(c => `<tr>
                      <td>${IC.esc(c.nro_carga)}</td>
                      <td>${IC.esc(c.fecha)}</td>
                      <td>$${IC.esc(usd(c.precio))}</td>
                      <td>${IC.esc(c.cantidad)}</td>
                      <td>${IC.esc(c.uni_master)}</td>
                      <td>${IC.esc(c.cbm_caja)}</td>
                    </tr>`).join('')}
                </tbody>
              </table>
            </div>
          </div>` : ''}
        ${comparador && comparador.apariciones === 0 ? '<div style="margin-top:10px;font-size:11px;color:#64748b">Sin histórico para ese artículo.</div>' : ''}
        ${comparador && comparador.error ? `<div class="err-box">${IC.esc(comparador.error)}</div>` : ''}
      </div>

      <div class="card">
        <div class="card-header">
          <h3>📋 Últimas cargas procesadas</h3>
          <span style="font-size:11px;color:#64748b;margin-left:8px">${cargas.length} cargas</span>
        </div>
        ${loading ? '<div class="loading">Cargando...</div>' : ''}
        ${!loading && cargas.length === 0 ? '<p style="font-size:12px;color:#64748b">Todavía no hay cargas procesadas.</p>' : ''}
        ${!loading && cargas.length > 0 ? `<div class="report" data-k="hi-cargas" style="max-height:400px">
            <table>
              <thead><tr><th>ID</th><th>N° Carga</th><th>Proveedor</th><th>Modo</th><th>Fecha</th><th></th></tr></thead>
              <tbody>
                ${cargas.map(c => `<tr>
                    <td>${IC.esc(c.id)}</td>
                    <td>${IC.esc(c.nro_carga)}</td>
                    <td>${IC.esc(c.proveedor || '-')}</td>
                    <td>${IC.esc(c.modo)}</td>
                    <td>${IC.esc(c.fecha || (c.created_at ? c.created_at.slice(0, 10) : ''))}</td>
                    <td><button class="btn btn-secondary" style="padding:2px 6px;font-size:10px" onclick="${IC.on(() => downloadExcel(c.id))}">📥 Excel</button></td>
                  </tr>`).join('')}
              </tbody>
            </table>
          </div>` : ''}
      </div>
    </div>`;
    }

    render();
    try { S.cargas = (await api.editar('cargas_lista', { limite: 50 })) || []; }
    catch (e) { console.error('historial:', e); }
    S.loading = false;
    render();
  });
})();
