/* IMPO COMEX dentro de Gestión Virgilio — base (Elías, 09/10/2026: «migrar completamente a Gestión»).
   Sin build: script clásico, todo cuelga de window.IC, el HTML se arma en strings como el resto de
   importación y los eventos van por onclick="…". Lo abre openImpoComex2() (importacion.js).

   Qué hay acá (lo que comparten los 12 modos):
     IC.abrir / IC.cerrar / IC.ir(modo)  la pantalla completa (#icOv) y el cambio de modo
     IC.api                               pedidos a las functions por la puerta Impo_Comex_web (sesión de Google)
     IC.avisar / IC.confirmar             diálogos dentro de la página (promesas), como dialogos.jsx
     IC.on(fn)                            registra un handler y devuelve el texto para onclick="…"
     IC.pintar(el, html)                  reemplaza el HTML conservando foco, selección, scroll y <details>
     IC.mod(nombre) / IC.lib(nombre)      la lógica (impocomex/logica/, ES modules copiados tal cual) y
                                          las librerías (impocomex/vendor/), a demanda
     IC.dz / IC.pdf / IC.lightbox / IC.md / IC.cab / IC.items / IC.corregirRelev   componentes
   La lógica de parseo NO se reescribió: es la misma del cliente original (logica/). */
(function () {
  'use strict';
  const IC = window.IC = window.IC || {};

  IC.empresa = {
    id: 'loekemeyer', nombre: 'Loekemeyer', color: '#be185d',
    supabaseUrl: 'https://hrxfctzncixxqmpfhskv.supabase.co',
    // Clave publicable (no es secreta). La puerta valida que la sesión sea de un supervisor.
    anonKey: 'sb_publishable_BqpAgZH6ty-9wft10_YMhw_0rcIPuWT',
  };
  IC.BUILD = '2026-10-09-r81';
  IC.url = (p) => new URL('impocomex/' + p, document.baseURI).href;
  const VER = () => { try { return typeof APP_VERSION !== 'undefined' ? APP_VERSION : String(Date.now()); } catch (_) { return String(Date.now()); } };

  // ── utilidades de HTML ───────────────────────────────────────────────────────────────
  IC.esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const SIN_PX = new Set(['zIndex', 'opacity', 'flex', 'flexGrow', 'flexShrink', 'fontWeight', 'lineHeight', 'order', 'zoom']);
  // Estilo de React ({ fontSize: 11, padding: '4px 8px' }) → texto CSS. Los números van en px.
  IC.st = (o) => {
    if (!o) return '';
    return Object.keys(o).filter(k => o[k] !== undefined && o[k] !== null && o[k] !== false && o[k] !== '').map(k => {
      const v = o[k];
      const prop = k.replace(/[A-Z]/g, m => '-' + m.toLowerCase());
      return prop + ':' + (typeof v === 'number' && !SIN_PX.has(k) ? v + 'px' : v);
    }).join(';');
  };
  // <option>s con la elegida marcada. lista: ['a','b'] o [[valor, texto], …]
  IC.opts = (lista, val) => lista.map(o => {
    const [v, t] = Array.isArray(o) ? o : [o, o];
    return `<option value="${IC.esc(v)}"${String(v) === String(val ?? '') ? ' selected' : ''}>${IC.esc(t)}</option>`;
  }).join('');

  // Handlers: guardan la función y devuelven el texto para el atributo. Reciben (event, elemento).
  const FN = new Map(); let fnN = 0;
  IC.on = (fn) => {
    const id = ++fnN; FN.set(id, fn);
    if (FN.size > 200000) { for (const k of FN.keys()) { if (k > id - 150000) break; FN.delete(k); } }
    return `IC._f(${id},event,this)`;
  };
  IC._f = (id, ev, el) => { const fn = FN.get(id); if (fn) return fn(ev, el); };

  // Reemplaza el contenido conservando lo que React conservaba solo: el campo con foco (y lo
  // seleccionado), el scroll de las cajas y si un <details> quedó abierto. Se identifican por
  // data-k (o id); sin eso, se rearman como vienen en el HTML.
  IC.pintar = (el, html) => {
    if (!el) return;
    const clave = (n) => n.getAttribute && (n.getAttribute('data-k') || n.id);
    const act = document.activeElement;
    let foco = null;
    if (act && el.contains(act) && clave(act)) {
      foco = { k: clave(act) };
      try { foco.s = act.selectionStart; foco.e = act.selectionEnd; } catch (_) {}
    }
    const scroll = new Map(), abiertos = new Map();
    el.querySelectorAll('[data-k],[id]').forEach(n => {
      const k = clave(n); if (!k) return;
      if (n.scrollTop || n.scrollLeft) scroll.set(k, [n.scrollTop, n.scrollLeft]);
      if (n.tagName === 'DETAILS' && n.hasAttribute('data-k')) abiertos.set(k, n.open);
    });
    el.innerHTML = html;
    const busca = (k) => el.querySelector(`[data-k="${CSS.escape(k)}"]`) || (document.getElementById(k) && el.contains(document.getElementById(k)) ? document.getElementById(k) : null);
    abiertos.forEach((open, k) => { const n = busca(k); if (n && n.tagName === 'DETAILS') n.open = open; });
    scroll.forEach(([t, l], k) => { const n = busca(k); if (n) { n.scrollTop = t; n.scrollLeft = l; } });
    if (foco) {
      const n = busca(foco.k);
      if (n && n.focus) { n.focus({ preventScroll: true }); try { if (foco.s != null) n.setSelectionRange(foco.s, foco.e); } catch (_) {} }
    }
  };

  // ── carga a demanda ──────────────────────────────────────────────────────────────────
  // La lógica se importa SIN ?v=: los módulos se importan entre sí con ruta relativa, y con dos URLs
  // distintas el navegador tendría dos copias (pasa con CONTROLANTE de la DDJJ).
  const MODS = {};
  IC.mod = (n) => (MODS[n] = MODS[n] || import(IC.url('logica/' + n + '.js')).catch(e => { delete MODS[n]; throw e; }));
  const LIBS = { xlsx: 'xlsx.mjs', 'xlsx-js-style': 'xlsx-js-style.js', 'pdf-lib': 'pdf-lib.js', fflate: 'fflate.js' };
  IC.lib = (n) => (MODS['lib:' + n] = MODS['lib:' + n] || import(IC.url('vendor/' + LIBS[n])).catch(e => { delete MODS['lib:' + n]; throw e; }));
  const SCRIPTS = {};
  IC.script = (archivo) => (SCRIPTS[archivo] = SCRIPTS[archivo] || new Promise((ok, mal) => {
    const s = document.createElement('script');
    s.src = IC.url(archivo) + '?v=' + encodeURIComponent(VER());
    s.onload = () => ok(); s.onerror = () => { delete SCRIPTS[archivo]; mal(new Error('No se pudo cargar ' + archivo)); };
    document.head.appendChild(s);
  }));

  // ── diálogos (dialogos.jsx) ──────────────────────────────────────────────────────────
  const cola = [];
  let dlgFoco = null;
  function dlgMostrar() {
    const d = cola[0]; let ov = document.getElementById('icDlg');
    if (!d) { if (ov) ov.remove(); return; }
    if (!ov) { ov = document.createElement('div'); ov.id = 'icDlg'; (document.getElementById('icOv') || document.body).appendChild(ov); }
    if (!dlgFoco) dlgFoco = document.activeElement;
    const conf = d.tipo === 'confirmar';
    ov.setAttribute('role', 'presentation');
    ov.style.cssText = 'position:fixed;inset:0;background:rgba(15,23,42,0.45);z-index:9500;display:flex;align-items:center;justify-content:center;padding:16px;font-family:system-ui,-apple-system,sans-serif';
    ov.innerHTML = `<div role="${conf ? 'alertdialog' : 'dialog'}" aria-modal="true" style="background:#fff;border-radius:10px;padding:16px;width:min(560px,100%);box-shadow:0 12px 32px rgba(0,0,0,0.25)">
      <div style="font-size:13px;color:#1e293b;white-space:pre-wrap;max-height:60vh;overflow-y:auto;line-height:1.45">${IC.esc(d.mensaje)}</div>
      <div style="display:flex;justify-content:flex-end;gap:8px;margin-top:14px">
        ${conf ? `<button class="btn btn-secondary" data-r="0">${IC.esc(d.cancelar)}</button>` : ''}
        <button class="btn btn-primary" data-r="1" id="icDlgOk"${d.peligro ? ' style="background:#b91c1c"' : ''}>${IC.esc(d.aceptar)}</button>
      </div></div>`;
    ov.querySelectorAll('button[data-r]').forEach(b => { b.onclick = () => dlgCerrar(b.getAttribute('data-r') === '1'); });
    ov.onkeydown = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); dlgCerrar(false); }
      else if (e.key === 'Enter' && document.activeElement && document.activeElement.id === 'icDlgOk') { e.preventDefault(); dlgCerrar(true); }
    };
    const ok = document.getElementById('icDlgOk'); if (ok) ok.focus();
  }
  function dlgCerrar(v) {
    const d = cola.shift(); const previo = dlgFoco;
    if (!cola.length) { dlgFoco = null; const ov = document.getElementById('icDlg'); if (ov) ov.remove(); if (previo && document.contains(previo) && previo.focus) previo.focus(); }
    else dlgMostrar();
    if (d) d.resolve(v);
  }
  function dlgPedir(d) { return new Promise(resolve => { cola.push(Object.assign({}, d, { resolve })); if (cola.length === 1) dlgMostrar(); }); }
  IC.confirmar = (mensaje, o = {}) => dlgPedir({ tipo: 'confirmar', mensaje, aceptar: o.aceptar || 'Aceptar', cancelar: o.cancelar || 'Cancelar', peligro: !!o.peligro });
  IC.avisar = (mensaje, o = {}) => dlgPedir({ tipo: 'avisar', mensaje, aceptar: o.aceptar || 'Aceptar' }).then(() => undefined);

  // ── acceso (web.js) y cliente de las functions (api.js) ──────────────────────────────
  async function tokenWeb() {
    const cli = window.sb;
    if (!cli || !cli.auth) return null;
    const { data } = await cli.auth.getSession();
    return (data && data.session && data.session.access_token) || null;
  }
  IC.tokenWeb = tokenWeb;
  async function accesoWeb() {
    const token = await tokenWeb();
    if (!token) return 'sin_sesion';
    const { data, error } = await window.sb.rpc('es_supervisor_virgilio');
    if (error || data !== true) return 'no_supervisor';
    return 'ok';
  }
  // Completa el controlante de la DDJJ (datos personales) desde la puerta. Sin esto el modo DDJJ no
  // encuentra el cuadro 4.A y lo avisa como alerta, que es lo que tiene que pasar.
  async function cargarDatosPrivados() {
    const token = await tokenWeb(); if (!token) return false;
    const r = await fetch(`${IC.empresa.supabaseUrl}/functions/v1/Impo_Comex_web/datos-ddjj`, {
      headers: { apikey: IC.empresa.anonKey, Authorization: `Bearer ${token}` },
    });
    if (!r.ok) return false;
    const { CONTROLANTE } = await IC.mod('lib/ddjjTemplate');
    Object.assign(CONTROLANTE, (await r.json()).controlante || {});
    return true;
  }

  async function mensajeError(r) {
    const texto = await r.text();
    try {
      const j = JSON.parse(texto);
      if (j && j.codigo === 'sin_sesion') return 'Se cerró la sesión. Entrá de nuevo desde Gestión Virgilio.';
      if (j && j.codigo === 'no_supervisor') return 'Sólo los supervisores de Gestión Virgilio pueden usar IMPO COMEX.';
      if (j && j.codigo === 'token_invalido') return 'Esta copia del programa no tiene acceso al servidor. Abrilo desde Gestión Virgilio → Pedidos Importación → IMPO COMEX.';
      if (j && j.error) return j.error;
    } catch (_) { /* no era JSON */ }
    return `${r.status} ${texto}`;
  }
  const BASE_FN = () => `${IC.empresa.supabaseUrl}/functions/v1/Impo_Comex_web`;
  async function pedir(path, opciones = {}) {
    const headers = Object.assign({ apikey: IC.empresa.anonKey }, opciones.headers || {});
    const token = await tokenWeb();
    if (!token) throw new Error('Se cerró la sesión. Entrá de nuevo desde Gestión Virgilio.');
    headers.Authorization = `Bearer ${token}`;
    const r = await fetch(`${BASE_FN()}${path}`, Object.assign({}, opciones, { headers }));
    if (!r.ok) throw new Error(await mensajeError(r));
    return r;
  }
  IC.api = {
    async get(path) { return (await pedir(path)).json(); },
    async postForm(path, formData) { return (await pedir(path, { method: 'POST', body: formData })).json(); },
    async postJson(path, payload) {
      return (await pedir(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) })).json();
    },
    // Ediciones (function Impo_Comex_editar)
    async editar(accion, params = {}) { const r = await this.postJson('/editar', Object.assign({ accion }, params)); return r.data; },
    async descargar(path, nombre) {
      const r = await pedir(path);
      IC.bajarBlob(await r.blob(), nombre);
    },
  };
  IC.bajarBlob = (blob, nombre) => {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = nombre;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  };

  // ── pantalla ─────────────────────────────────────────────────────────────────────────
  const TITULO = 'Verificación IMPO COMEX';
  IC.modos = {};                       // nombre → function (el) { … } (cada ic-<modo>.js se registra)
  IC.modo = (nombre, fn) => { IC.modos[nombre] = fn; };
  const ARCHIVO_MODO = { lakout: 'ic-lakout.js', multidoc: 'ic-multidoc.js', marks: 'ic-marks.js', estimar: 'ic-estimar.js',
    full: 'ic-full.js', ddjj: 'ic-ddjj.js', cajas: 'ic-cajas.js', inal: 'ic-inal.js', vencimientos: 'ic-inal.js',
    autorizacion: 'ic-autorizacion.js', history: 'ic-history.js' };
  let vista = 'home', acceso = 'verificando', verGestion = '';
  IC.vistaActual = () => vista;
  let cssPuesto = false;

  IC.abrir = function () {
    if (!cssPuesto) {
      const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = IC.url('ic.css') + '?v=' + encodeURIComponent(VER());
      document.head.appendChild(l); cssPuesto = true;
    }
    let ov = document.getElementById('icOv');
    if (!ov) { ov = document.createElement('div'); ov.id = 'icOv'; document.body.appendChild(ov); }
    ov.style.display = '';
    document.documentElement.style.overflow = 'hidden';
    vista = 'home'; acceso = 'verificando';
    marco();
    fetch('version.json', { cache: 'no-store' }).then(r => r.ok ? r.json() : null)
      .then(j => { if (j && j.version) { verGestion = j.version; const f = document.getElementById('icVerGest'); if (f) f.textContent = verGestion; } }).catch(() => {});
    accesoWeb().then(a => { acceso = a; if (a === 'ok') cargarDatosPrivados().catch(() => {}); marco(); })
      .catch(() => { acceso = 'sin_sesion'; marco(); });
  };
  IC.cerrar = function () {
    const ov = document.getElementById('icOv'); if (ov) { ov.innerHTML = ''; ov.style.display = 'none'; }
    document.documentElement.style.overflow = '';
    IC.pdf.limpiar();
  };
  // Esc no cierra la pantalla entera (se perdería lo cargado): sólo los diálogos y el visor de fotos.

  function marco() {
    const ov = document.getElementById('icOv'); if (!ov) return;
    if (acceso !== 'ok') {
      const txt = acceso === 'verificando' ? 'Verificando la sesión…'
        : acceso === 'no_supervisor' ? 'Sólo los supervisores de Gestión Virgilio pueden usar IMPO COMEX.'
        : 'Entrá a Gestión Virgilio con tu cuenta de Google y abrí de nuevo Importación → 🛃 IMPO COMEX.';
      ov.innerHTML = `<div class="app web" style="padding:40px;text-align:center"><h1>${TITULO}</h1><p style="font-size:16px">${IC.esc(txt)}</p>
        ${acceso !== 'verificando' ? `<p><a href="#" onclick="event.preventDefault();IC.cerrar()">← Volver a Gestión Virgilio</a></p>` : ''}</div>`;
      return;
    }
    ov.innerHTML = `<div class="app web">
      <div class="header">
        <span style="font-size:22px">🔍</span>
        <h1>${TITULO}</h1>
        <span class="badge" style="background:${IC.empresa.color}">${IC.esc(IC.empresa.nombre)}</span>
        <div class="spacer"></div>
        <button id="icInicio" onclick="IC.ir('home')" style="${vista === 'home' ? 'display:none' : ''}">← Inicio</button>
        <a href="#" onclick="event.preventDefault();IC.cerrar()" style="margin-left:8px;font-size:13px">← Volver a Gestión</a>
      </div>
      <div id="icMain"></div>
      <footer style="margin-top:30px;padding:12px 8px;border-top:1px solid #e2e8f0;font-size:10px;color:#94a3b8;text-align:center;line-height:1.5">
        <div><strong>${TITULO}</strong> — Gestión Virgilio <span id="icVerGest">${IC.esc(verGestion || '…')}</span> · build ${IC.BUILD}</div>
      </footer></div>`;
    pintarVista();
  }

  IC.ir = function (v) {
    vista = v;
    const b = document.getElementById('icInicio'); if (b) b.style.display = v === 'home' ? 'none' : '';
    IC.pdf.limpiar();
    pintarVista();
    const ov = document.getElementById('icOv'); if (ov) ov.scrollTop = 0;
  };

  async function pintarVista() {
    const main = document.getElementById('icMain'); if (!main) return;
    const v = vista;
    if (v === 'home') { IC.home(main); return; }
    main.innerHTML = '<div class="loading"><span class="pulse">⏳</span>Abriendo…</div>';
    try {
      await IC.script(ARCHIVO_MODO[v]);
      if (vista !== v) return;
      const fn = IC.modos[v];
      if (!fn) throw new Error('No está el modo ' + v);
      main.innerHTML = '';
      fn(main, { tabInicial: v === 'vencimientos' ? 'vencimientos' : undefined });
    } catch (e) {
      main.innerHTML = `<div class="err-box">${IC.esc(e.message || e)}</div>`;
    }
  }

  // ── Home + Cargas creadas hoy ────────────────────────────────────────────────────────
  const MODOS_HOME = [
    ['lakout', '🏛️', 'Verificar Lakout (1 PDF bundle)', 'Subi 1 PDF del lakout completo (Despacho + BL + HKINV + PL + Libre Circ pegados). Auto-extrae todas las secciones, hace cross-docs y audit calc AFIP.', '~30 seg · ~$0.20'],
    ['multidoc', '📁', 'Verificar Docs Separados', 'Subí los documentos que tengas (CI, PL, BL, Despacho, HKINV, Libre Circ, Pesaje): ninguno es obligatorio y se comparan entre ellos por artículo, totales y referencias. La Libre Circ sale de la base si ya está cargada.', '~1 min · ~$0.20'],
    ['marks', '📦', 'Analizar Shipping Marks', 'Compará el Shipping Mark (Excel) contra la Proforma Invoice: comprador, product code y QUANTITY vs Qty/Outer. Opcional: fotos de las cajas verificadas por IA.', 'comparación gratis · fotos ~$0.10'],
    ['cajas', '📐', 'Cajas vs Packing List', 'Fotos de la última master box y de la inner box por código. Lee lo impreso (n/N, cantidad, pesos, medidas, consignatario) y lo compara contra el packing list.', '~20 seg · ~$0.05 por código'],
    ['inal', '🛡️', 'INAL: certificados y vencimientos', 'Certificados CE (ANMAT/SENASA) y RNE ordenados por vencimiento, artículos certificados (código, marca, descripción, importador, elaborador), NCM de cada producto y alta desde el PDF.', 'gratis · carga ~$0.02'],
    ['autorizacion', '📝', 'Autorización de Importación (envases)', 'Completa el formulario del gestor para SENASA solo con la factura, el packing list, el BL y los certificados CE / RNE que subís, y controla que sean de la misma carga. Revisás los datos y descargás el Word.', '~30 seg · ~$0.20'],
    ['estimar', '💵', 'Estimar Nacionalización', 'Subi PI/CI proveedor (Excel) y calcula cuanto vas a pagar de impuestos AFIP antes del despacho. NCM auto detectado (codigo / fuzzy / LLM).', '~30 seg · ~$0.05'],
    ['ddjj', '🏦', 'Declaración para presentar al Banco', 'DDJJ 20320 (Com. "A" 7030, Credicoop). Elegís si la mercadería está en tránsito o con despacho a plaza, subís la DDJJ completada + la CI, y chequea cómo se llenó y si se modificó la redacción del formulario.', '~10 seg · gratis'],
    ['full', '🔍', 'Verificación Completa (legacy)', 'Modo viejo con PI. Subis PI, CI, PL, Despacho, BL, Libre Circ. Cruza vs Relevamiento + histórico.', '~1 min · ~$0.05'],
    ['history', '📊', 'Historial y Comparador', 'Ver cargas anteriores, buscar por código, comparar precios y packing de un artículo a través del tiempo.', 'gratis'],
  ];
  IC.home = function (el) {
    el.innerHTML = `<div>
      <h2 style="margin:12px 0;font-size:14px;color:#475569">¿Qué querés hacer?</h2>
      <div class="mode-grid">${MODOS_HOME.map(([k, ic, t, p, tag]) => `
        <div class="mode-card" data-modo="${k}" onclick="IC.ir('${k}')">
          <div class="icon">${ic}</div><h3>${IC.esc(t)}</h3><p>${IC.esc(p)}</p><span class="tag">${IC.esc(tag)}</span>
        </div>`).join('')}</div>
      <div id="icHoy"></div></div>`;
    cargasHoy.cargar();
  };

  // CargasHoy.jsx: lista las cargas creadas hoy con botón para borrarlas (limpiar testeos).
  const cargasHoy = {
    S: { cargas: [], loading: false, borrando: null, error: null },
    pintar() {
      const el = document.getElementById('icHoy'); if (!el) return;
      const S = this.S;
      const filas = S.cargas.map(c => {
        const desp = (c.despachos || [])[0];
        const itemsCount = (c.despachos || []).length;
        const alertasCount = (c.inconsistencias || []).length;
        const hora = c.created_at ? new Date(c.created_at).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }) : '-';
        return `<tr>
          <td>${IC.esc(c.id)}</td>
          <td><strong>${c.nro_carga ? IC.esc(c.nro_carga) : '<em style="color:#94a3b8">sin nro</em>'}</strong></td>
          <td>${IC.esc(c.proveedor || '-')}</td>
          <td style="font-size:10px">${IC.esc((desp && desp.nro_despacho) || '-')}</td>
          <td>${desp && desp.valor_fob_total ? '$' + Number(desp.valor_fob_total).toFixed(0) : '-'}</td>
          <td>${itemsCount}</td><td>${alertasCount}</td><td style="font-size:10px">${hora}</td>
          <td><button onclick="${IC.on(() => this.borrar(c.id, c.nro_carga))}" ${S.borrando === c.id ? 'disabled' : ''}
            title="Borrar carga + todos sus despachos/items/alertas"
            style="background:#fee2e2;border:1px solid #fca5a5;color:#991b1b;padding:3px 8px;border-radius:4px;font-size:10px;cursor:pointer">${S.borrando === c.id ? '⏳' : '🗑 Borrar'}</button></td></tr>`;
      }).join('');
      IC.pintar(el, `<div class="card" style="margin-top:16px;border-left:3px solid #f59e0b">
        <div class="card-header"><h3 style="font-size:13px">🗓️ Cargas creadas hoy (${S.cargas.length})</h3><div style="flex:1"></div>
          <button class="btn" onclick="${IC.on(() => this.cargar())}" ${S.loading ? 'disabled' : ''} style="font-size:11px">${S.loading ? '⏳' : '🔄 Refrescar'}</button></div>
        <div style="font-size:11px;color:#64748b;margin-bottom:8px">Usalo para borrar testeos / cargas que no querés que queden en el historial.</div>
        ${S.error ? `<div class="err-box" style="font-size:11px">${IC.esc(S.error)}</div>` : ''}
        ${!S.loading && !S.cargas.length ? '<div style="font-size:11px;color:#94a3b8;padding:8px;text-align:center">Sin cargas creadas hoy.</div>' : ''}
        ${S.cargas.length ? `<div class="report" data-k="hoyRep" style="max-height:260px"><table style="font-size:11px"><thead><tr>
          <th>ID</th><th>N° Carga</th><th>Proveedor</th><th>N° Despacho</th><th>FOB</th><th>Items</th><th>Alertas</th><th>Hora</th><th></th></tr></thead>
          <tbody>${filas}</tbody></table></div>` : ''}</div>`);
    },
    async cargar() {
      const S = this.S; S.loading = true; S.error = null; this.pintar();
      try {
        const hoy = new Date();
        const inicioDia = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate()).toISOString();
        S.cargas = (await IC.api.editar('cargas_hoy', { desde: inicioDia })) || [];
      } catch (e) { S.error = e.message || String(e); }
      S.loading = false; this.pintar();
    },
    async borrar(cargaId, nroCarga) {
      if (!(await IC.confirmar(`Borrar carga ${nroCarga} (id=${cargaId}) y todos sus despachos/items/alertas? Esta accion no se puede deshacer.`, { aceptar: 'Sí, borrar', peligro: true }))) return;
      this.S.borrando = cargaId; this.pintar();
      try {
        // La base borra en cascada despachos, items, alertas, parseos y libre circulacion.
        await IC.api.editar('borrar_carga', { carga_id: cargaId });
        await this.cargar();
      } catch (e) { IC.avisar('Error al borrar: ' + (e.message || String(e))); }
      this.S.borrando = null; this.pintar();
    },
  };

  // ── Zona de subida (DropZone.jsx) ────────────────────────────────────────────────────
  // Uso: IC.dz.html(id, { label, icon, files, onFiles(arr), onRemove(i), accept, single, limites, rerender })
  //   files: el array que guarda el modo; onFiles/onRemove lo cambian y el modo vuelve a pintar.
  // La zona guarda sola su estado propio (procesando, aviso, ver todos) por id.
  const VISIBLES = 8, ABRIR_HASTA = 12;
  const DZ = {};
  function porOrigen(archivos, ignorados, SEP) {
    const origenes = new Map();
    const de = (nombre) => {
      const i = nombre.indexOf(SEP);
      if (i >= 0) return [nombre.slice(0, i), nombre.slice(i + SEP.length)];
      return /\.(zip|rar)$/i.test(nombre) ? [nombre, ''] : [null, nombre];
    };
    const item = (o) => { if (!origenes.has(o)) origenes.set(o, { nombre: o, leidos: [], ignorados: [] }); return origenes.get(o); };
    for (const f of archivos) { const [o, resto] = de(f.name); if (o) item(o).leidos.push(resto); }
    for (const x of ignorados) { const [o, resto] = de(x.nombre); if (o) item(o).ignorados.push({ nombre: resto, motivo: x.motivo }); }
    const lista = [...origenes.values()];
    if (lista.length === 1) {
      const unico = lista[0]; const sub = new Map();
      const partir = (resto) => { const i = resto.indexOf(SEP); return i >= 0 ? [`${unico.nombre}${SEP}${resto.slice(0, i)}`, resto.slice(i + SEP.length)] : [unico.nombre, resto]; };
      const itemSub = (o) => { if (!sub.has(o)) sub.set(o, { nombre: o, leidos: [], ignorados: [] }); return sub.get(o); };
      for (const n of unico.leidos) { const [o, r] = partir(n); itemSub(o).leidos.push(r); }
      for (const x of unico.ignorados) { const [o, r] = partir(x.nombre); itemSub(o).ignorados.push({ nombre: r, motivo: x.motivo }); }
      if (sub.size > 1) return [...sub.values()];
    }
    return lista;
  }
  IC.dz = {
    html(id, o) {
      const z = DZ[id] = DZ[id] || { drag: false, procesando: false, aviso: null, verTodos: false };
      z.o = Object.assign({ accept: 'application/pdf,image/*,.xlsx,.xls', single: false, files: [] }, o);
      return `<div class="zone" id="icdz-${IC.esc(id)}">${this.cuerpo(id)}</div>`;
    },
    // Vuelve a pintar sólo la zona (estado propio: procesando, aviso, ver todos, arrastrando).
    repintar(id) { const el = document.getElementById('icdz-' + id); if (el && DZ[id]) IC.pintar(el, this.cuerpo(id)); },
    // Olvida el estado de la zona (lo que pasa al desmontar el componente en React).
    olvidar(id) { delete DZ[id]; },
    cuerpo(id) {
      const z = DZ[id], o = z.o, files = o.files || [];
      const uid = `icup-${id}`, uidCarpeta = `icup-dir-${id}`;
      const lista = z.verTodos ? files : files.slice(0, VISIBLES);
      const A = z.aviso;
      const avisoHtml = !A ? '' : `<div style="font-size:10px;margin-top:3px;color:${A.error ? '#b91c1c' : '#b45309'}">
        ${A.error ? `<div>${IC.esc(A.error)}</div>` : ''}
        ${A.primero ? `<div>Esta zona usa un solo archivo: se tomó "${IC.esc(A.primero)}".</div>` : ''}
        ${A.origenes.map((x, oi) => `<details data-k="dzo-${IC.esc(id)}-${oi}" ${x.leidos.length + x.ignorados.length <= ABRIR_HASTA ? 'open' : ''} style="color:#334155;margin-top:2px">
          <summary style="cursor:pointer">${/\.(zip|rar)$/i.test(x.nombre) ? '📦' : '📁'} <strong>${IC.esc(x.nombre)}</strong>: <span style="color:${x.leidos.length ? '#059669' : '#b91c1c'}">${x.leidos.length} leído${x.leidos.length === 1 ? '' : 's'}</span>${x.ignorados.length ? `<span style="color:#b45309"> · ${x.ignorados.length} ignorado${x.ignorados.length === 1 ? '' : 's'}</span>` : ''}</summary>
          <div style="padding-left:12px;max-height:180px;overflow-y:auto">
            ${x.leidos.map(n => `<div style="color:#059669">✓ ${IC.esc(n)}</div>`).join('')}
            ${x.ignorados.map(y => `<div style="color:#b45309">✗ ${IC.esc(y.nombre || x.nombre)}: ${IC.esc(y.motivo)}</div>`).join('')}
          </div></details>`).join('')}
        ${A.ignorados.length ? `<details data-k="dzi-${IC.esc(id)}" ${A.ignorados.length <= 5 ? 'open' : ''}><summary style="cursor:pointer">${A.ignorados.length} ignorado${A.ignorados.length > 1 ? 's' : ''}</summary>
          ${A.ignorados.slice(0, 30).map(x => `<div>${IC.esc(x.nombre)}: ${IC.esc(x.motivo)}</div>`).join('')}
          ${A.ignorados.length > 30 ? `<div>… y ${A.ignorados.length - 30} más</div>` : ''}</details>` : ''}
      </div>`;
      return `<div class="label"><span>${o.icon || ''} ${IC.esc(o.label || '')}</span>${files.length ? `<span class="count">${files.length}</span>` : ''}</div>
        <input id="${uid}" type="file" accept="${IC.esc(o.accept + ',.zip,.rar')}" ${o.single ? '' : 'multiple'} style="display:none"
          onchange="${IC.on((e) => { this.recibir(id, this.entradasInput(e.target.files)); e.target.value = ''; })}">
        <input id="${uidCarpeta}" type="file" webkitdirectory directory multiple style="display:none"
          onchange="${IC.on((e) => { this.recibir(id, this.entradasInput(e.target.files)); e.target.value = ''; })}">
        <div class="drop ${z.drag ? 'dragging' : ''} ${files.length ? 'has-files' : ''}"
          ondragover="${IC.on((e) => { e.preventDefault(); if (!z.drag) { z.drag = true; e.currentTarget.classList.add('dragging'); } })}"
          ondragleave="${IC.on((e) => { z.drag = false; e.currentTarget.classList.remove('dragging'); })}"
          ondrop="${IC.on((e) => { e.preventDefault(); z.drag = false; this.soltar(id, e.dataTransfer); })}"
          onclick="${IC.on(() => { if (!z.procesando) document.getElementById(uid).click(); })}">
          ${z.procesando ? '⏳ Abriendo archivos...' : files.length ? `✓ ${files.length} archivo${files.length > 1 ? 's' : ''}` : '📎 Arrastrá archivos, carpetas, .zip o .rar, o hacé click'}
        </div>
        ${!o.single ? `<div style="font-size:10px;margin-top:2px"><button type="button" ${z.procesando ? 'disabled' : ''}
          onclick="${IC.on(() => document.getElementById(uidCarpeta).click())}"
          style="background:none;border:none;color:#2563eb;cursor:pointer;padding:0;font-size:10px">📁 Elegir carpeta</button></div>` : ''}
        ${avisoHtml}
        ${files.length ? `<div class="files-list" data-k="dzl-${IC.esc(id)}">
          ${lista.map((f, i) => `<div class="f"><span title="${IC.esc(f.name)}">${IC.esc(f.name)}</span><button onclick="${IC.on(() => o.onRemove && o.onRemove(i))}" title="Quitar">✕</button></div>`).join('')}
          ${files.length > VISIBLES ? `<button type="button" onclick="${IC.on(() => { z.verTodos = !z.verTodos; this.repintar(id); })}"
            style="background:none;border:none;color:#2563eb;cursor:pointer;padding:0;font-size:10px">${z.verTodos ? 'ver menos' : `ver los ${files.length}`}</button>` : ''}
        </div>` : ''}`;
    },
    // Las entradas se arman en el momento del evento (el DataTransfer vence al terminar el evento).
    entradasInput(files) { const arr = Array.from(files || []); return IC.mod('archivos').then(m => m.entradasDeInput(arr)); },
    soltar(id, dt) {
      // entradasDeSoltar lee dt.items YA: hay que llamarla adentro del evento. El módulo puede no estar
      // cargado todavía: por eso se precarga al abrir la pantalla (IC.mod('archivos') en IC.abrir).
      if (archivosMod) this.recibir(id, archivosMod.entradasDeSoltar(dt));
      else { const files = Array.from(dt.files || []); this.recibir(id, IC.mod('archivos').then(m => m.entradasDeInput(files))); }
    },
    async recibir(id, entradasPromesa) {
      const z = DZ[id]; if (!z) return;
      z.procesando = true; z.aviso = null; this.repintar(id);
      try {
        const m = await IC.mod('archivos');
        const entradas = await entradasPromesa;
        const o = z.o;
        const r = await m.expandir(entradas, Object.assign({ accept: o.accept }, o.limites ? { limites: o.limites } : {}));
        const elegidos = o.single ? r.archivos.slice(0, 1) : r.archivos;
        if (elegidos.length && o.onFiles) o.onFiles(elegidos);
        const origenes = porOrigen(r.archivos, r.ignorados, m.SEP);
        const sueltos = r.ignorados.filter(x => !x.nombre.includes(m.SEP) && !/\.(zip|rar)$/i.test(x.nombre));
        if (r.error || origenes.length || sueltos.length || (o.single && r.archivos.length > 1) || !r.archivos.length) {
          z.aviso = {
            error: r.error || (!r.archivos.length && !r.ignorados.length ? 'No se encontró ningún archivo.' : null),
            origenes, ignorados: sueltos, primero: o.single && r.archivos.length > 1 ? r.archivos[0].name : null,
          };
        }
      } catch (e) {
        z.aviso = { error: `No se pudieron leer los archivos: ${e.message || e}`, origenes: [], ignorados: [] };
      }
      z.procesando = false;
      this.repintar(id);
    },
  };
  let archivosMod = null;

  // ── Visor de PDFs (PdfViewer.jsx) ────────────────────────────────────────────────────
  // IC.pdf.html(id, files, { height, title })  files: { slot: File } | File[] | [{ name, file }]
  const PV = {};
  IC.pdf = {
    lista(files) {
      if (!files) return [];
      if (Array.isArray(files)) return files.map((f, i) => f instanceof File ? { label: f.name, file: f } : { label: f.name || `Doc ${i + 1}`, file: f.file });
      return Object.entries(files).filter(([, f]) => f instanceof File).map(([slot, f]) => ({ label: `${slot}: ${f.name}`, file: f }));
    },
    html(id, files, o = {}) {
      const list = this.lista(files);
      let v = PV[id];
      const firma = list.map(x => x.file);
      if (!v || v.firma.length !== firma.length || v.firma.some((f, i) => f !== firma[i])) {
        if (v) v.urls.forEach(u => URL.revokeObjectURL(u));
        v = PV[id] = { firma, urls: list.map(x => URL.createObjectURL(x.file)), idx: 0 };
      }
      v.list = list; v.o = o;
      if (!list.length) return '';
      return `<div id="icpv-${IC.esc(id)}">${this.cuerpo(id)}</div>`;
    },
    cuerpo(id) {
      const v = PV[id], list = v.list, o = v.o; const height = o.height || 600, title = o.title || '📄 Vista previa';
      const idx = Math.min(v.idx, list.length - 1); const act = list[idx], url = v.urls[idx];
      return `<div style="border:1px solid #cbd5e1;border-radius:6px;overflow:hidden;background:white">
        <div style="padding:6px 10px;background:#f1f5f9;border-bottom:1px solid #cbd5e1;display:flex;align-items:center;gap:6px">
          <span style="font-size:12px;font-weight:600;color:#475569">${IC.esc(title)}</span>
          <span style="font-size:10px;color:#64748b">(${list.length} archivo${list.length > 1 ? 's' : ''})</span></div>
        ${list.length > 1 ? `<div style="display:flex;overflow-x:auto;border-bottom:1px solid #cbd5e1;background:#f8fafc">${list.map((it, i) =>
          `<button onclick="${IC.on(() => { v.idx = i; const el = document.getElementById('icpv-' + id); if (el) el.innerHTML = this.cuerpo(id); })}"
            style="padding:4px 10px;font-size:10px;border:none;cursor:pointer;background:${i === idx ? '#3b82f6' : 'transparent'};color:${i === idx ? 'white' : '#475569'};border-right:1px solid #e2e8f0;white-space:nowrap">${IC.esc(it.label.length > 30 ? it.label.slice(0, 27) + '...' : it.label)}</button>`).join('')}</div>` : ''}
        ${url ? `<iframe src="${url}" title="${IC.esc(act.label)}" style="width:100%;height:${height}px;border:none;display:block"></iframe>` : ''}
        <div style="padding:4px 10px;background:#f8fafc;border-top:1px solid #e2e8f0;font-size:10px;color:#64748b">${IC.esc(act.file.name)} · ${(act.file.size / 1024).toFixed(0)} KB</div>
      </div>`;
    },
    limpiar() { Object.keys(PV).forEach(k => { PV[k].urls.forEach(u => URL.revokeObjectURL(u)); delete PV[k]; }); },
  };

  // ── Visor de fotos (Lightbox.jsx) ────────────────────────────────────────────────────
  function normRegion(r) {
    if (!Array.isArray(r) || r.length !== 4 || r.some(n => typeof n !== 'number' || !isFinite(n))) return null;
    let [a, b, c, d] = r;
    const mx = Math.max(a, b, c, d);
    const div = mx > 1 ? (mx <= 100 ? 100 : (mx <= 1000 ? 1000 : mx)) : 1;
    a /= div; b /= div; c /= div; d /= div;
    if (c > a && d > b && (a + c > 1.02 || b + d > 1.02)) { c -= a; d -= b; }
    a = Math.min(Math.max(a, 0), 1); b = Math.min(Math.max(b, 0), 1);
    c = Math.min(c, 1 - a); d = Math.min(d, 1 - b);
    return (c > 0.01 && d > 0.01) ? [a, b, c, d] : null;
  }
  IC.normRegion = normRegion;
  // IC.lightbox({ src, region, alt, etiqueta } | { items: [...], inicio }, onClose)
  IC.lightbox = function (p, onClose) {
    p = p || {};
    const lista = p.items && p.items.length ? p.items : (p.src ? [{ src: p.src, region: p.region, alt: p.alt, etiqueta: p.etiqueta }] : []);
    const total = lista.length; if (!total) return;
    let idx = Math.min(Math.max(p.inicio || 0, 0), total - 1), escala = 1;
    const previo = document.activeElement;
    const ov = document.createElement('div');
    ov.id = 'icLb'; ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-modal', 'true');
    (document.getElementById('icOv') || document.body).appendChild(ov);
    const cerrar = () => { document.removeEventListener('keydown', tecla); ov.remove(); if (previo && document.contains(previo) && previo.focus) previo.focus(); if (onClose) onClose(); };
    const zoom = (d) => { escala = Math.min(6, Math.max(1, +(escala + d).toFixed(2))); pintar(); };
    const ir = (d) => { idx = (idx + d + total) % total; escala = 1; pintar(); };
    const tecla = (e) => {
      if (document.getElementById('icDlg')) return;
      if (e.key === 'Escape') { e.preventDefault(); cerrar(); }
      else if (e.key === 'ArrowRight') ir(1);
      else if (e.key === 'ArrowLeft') ir(-1);
      else if (e.key === '+' || e.key === '=') zoom(0.25);
      else if (e.key === '-' || e.key === '_') { escala = Math.max(escala - 0.25, 1); pintar(); }
      else if (e.key === '0') { escala = 1; pintar(); }
    };
    document.addEventListener('keydown', tecla);
    ov.onclick = cerrar;
    ov.addEventListener('wheel', (e) => { e.preventDefault(); zoom(e.deltaY < 0 ? 0.25 : -0.25); }, { passive: false });
    const boton = 'background:#fff;border:none;border-radius:6px;width:36px;height:36px;font-size:18px;line-height:1;cursor:pointer;padding:0;margin:0';
    const flecha = boton + ';position:fixed;top:50%;transform:translateY(-50%);width:44px;height:60px;font-size:26px;opacity:0.9';
    function pintar() {
      const it = lista[Math.min(idx, total - 1)] || lista[0];
      const reg = normRegion(it.region);
      ov.style.cssText = `position:fixed;inset:0;background:rgba(15,23,42,0.8);z-index:9400;display:flex;align-items:flex-start;justify-content:center;padding:20px;overflow:auto;cursor:${escala > 1 ? 'grab' : 'zoom-out'}`;
      ov.innerHTML = `<figure style="margin:0;display:flex;flex-direction:column;align-items:center;gap:6px">
          <span data-img="1" style="position:relative;display:inline-block;line-height:0;transform:scale(${escala});transform-origin:center top;transition:transform 0.05s">
            <img src="${IC.esc(it.src)}" alt="${IC.esc(it.alt || '')}" style="max-width:90vw;max-height:82vh;object-fit:contain;border-radius:6px;display:block">
            ${reg ? `<span data-region="1" style="position:absolute;left:${reg[0] * 100}%;top:${reg[1] * 100}%;width:${reg[2] * 100}%;height:${reg[3] * 100}%;border:3px solid #f59e0b;border-radius:3px;box-shadow:0 0 0 9999px rgba(15,23,42,0.30);pointer-events:none"></span>` : ''}
          </span>
          ${(it.etiqueta || total > 1 || reg) ? `<figcaption style="color:#e2e8f0;font-size:12px;background:rgba(0,0,0,0.45);padding:3px 10px;border-radius:4px;max-width:80vw;text-align:center">${total > 1 ? `[${idx + 1}/${total}] ` : ''}${IC.esc(it.etiqueta || '')}${reg ? '  ·  zona aproximada' : ''}</figcaption>` : ''}
        </figure>
        ${total > 1 ? `<button data-b="ant" style="${flecha};left:14px" title="Anterior (←)">‹</button><button data-b="sig" style="${flecha};right:14px" title="Siguiente (→)">›</button>` : ''}
        <div data-b="barra" style="position:fixed;top:14px;right:18px;display:flex;gap:6px">
          <button data-b="menos" style="${boton}" title="Alejar (−)">−</button>
          <button data-b="mas" style="${boton}" title="Acercar (+)">+</button>
          <button data-b="real" style="${boton}" title="Tamaño real (0)">⤢</button>
          <button data-b="cerrar" style="${boton}" aria-label="Cerrar" title="Cerrar (Esc)">✕</button>
        </div>`;
      const q = (s) => ov.querySelector(s);
      q('[data-img]').onclick = (e) => e.stopPropagation();
      q('[data-b="barra"]').onclick = (e) => e.stopPropagation();
      q('[data-b="menos"]').onclick = () => zoom(-0.25);
      q('[data-b="mas"]').onclick = () => zoom(0.25);
      q('[data-b="real"]').onclick = () => { escala = 1; pintar(); };
      q('[data-b="cerrar"]').onclick = cerrar;
      if (total > 1) { q('[data-b="ant"]').onclick = (e) => { e.stopPropagation(); ir(-1); }; q('[data-b="sig"]').onclick = (e) => { e.stopPropagation(); ir(1); }; }
    }
    pintar();
    return cerrar;
  };

  // ── Markdown (Markdown.jsx) → HTML ───────────────────────────────────────────────────
  function inline(text) {
    if (typeof text !== 'string') return IC.esc(text);
    const parts = text.split(/\*\*(.*?)\*\*/g);
    return parts.map((s, i) => i % 2 === 1 ? `<strong>${IC.esc(s)}</strong>` : s.split('`').map((t, j) => j % 2 === 1 ? `<code>${IC.esc(t)}</code>` : IC.esc(t)).join('')).join('');
  }
  function mdTabla(lines) {
    const rows = lines.filter(l => !l.trim().match(/^\|[-:\s|]+\|$/));
    const parsed = rows.map(r => r.split('|').slice(1, -1).map(c => c.trim()));
    if (!parsed.length) return '';
    return `<table><thead><tr>${parsed[0].map(h => `<th>${inline(h)}</th>`).join('')}</tr></thead><tbody>${parsed.slice(1).map(row => `<tr>${row.map(c => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  }
  IC.md = function (text) {
    if (!text) return '';
    const lines = String(text).split('\n'); const els = [];
    let tbl = [], inCode = false;
    const flush = () => { if (tbl.length) els.push(mdTabla(tbl)); tbl = []; };
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      if (l.includes('```')) { inCode = !inCode; continue; }
      if (inCode) continue;
      if (l.trim().startsWith('|')) { tbl.push(l); continue; }
      if (tbl.length) flush();
      if (l.startsWith('### ')) els.push(`<h4>${inline(l.slice(4))}</h4>`);
      else if (l.startsWith('## ')) els.push(`<h3>${inline(l.slice(3))}</h3>`);
      else if (l.startsWith('# ')) els.push(`<h2>${inline(l.slice(2))}</h2>`);
      else if (l.startsWith('- ') || l.startsWith('* ')) els.push(`<p style="padding-left:12px">• ${inline(l.slice(2))}</p>`);
      else if (l.trim()) els.push(`<p>${inline(l)}</p>`);
    }
    if (tbl.length) flush();
    return els.join('');
  };

  // ── Cabecera editable del despacho (EditableCabecera.jsx) ────────────────────────────
  const FIELDS = [
    { group: 'Cabecera', key: 'nro_despacho', label: 'Nº Despacho', type: 'text' },
    { group: 'Cabecera', key: 'fecha_oficializacion', label: 'Fecha Oficializ', type: 'date' },
    { group: 'Cabecera', key: 'aduana', label: 'Aduana', type: 'text' },
    { group: 'Cabecera', key: 'canal_selectivo', label: 'Canal', type: 'select', options: ['VERDE', 'NARANJA', 'ROJO'] },
    { group: 'Cabecera', key: 'modo_envio', label: 'Modo', type: 'select', options: ['LCL', 'FCL', 'AVION'] },
    { group: 'Cabecera', key: 'iibb_inscripcion', label: 'IIBB', type: 'select', options: ['S', 'N', 'E'] },
    { group: 'Partes', key: 'importador_nombre', label: 'Importador', type: 'text' },
    { group: 'Partes', key: 'cuit_importador', label: 'CUIT Importador', type: 'text' },
    { group: 'Partes', key: 'despachante_nombre', label: 'Despachante', type: 'text' },
    { group: 'Partes', key: 'cuit_despachante', label: 'CUIT Despachante', type: 'text' },
    { group: 'Partes', key: 'agente_transporte', label: 'Agente Transporte', type: 'text' },
    { group: 'Partes', key: 'cuit_agente_transporte', label: 'CUIT Agente', type: 'text' },
    { group: 'Partes', key: 'exportador', label: 'Vendedor/Exportador', type: 'text' },
    { group: 'Transporte', key: 'vessel', label: 'Vapor', type: 'text' },
    { group: 'Transporte', key: 'vto_embarque', label: 'Vto Embarque', type: 'date' },
    { group: 'Transporte', key: 'fecha_arribo', label: 'Fecha Arribo', type: 'date' },
    { group: 'Transporte', key: 'deposito', label: 'Depósito', type: 'text' },
    { group: 'Cargas', key: 'total_bultos', label: 'Bultos', type: 'number' },
    { group: 'Cargas', key: 'peso_bruto_total', label: 'Peso Bruto (kg)', type: 'number' },
    { group: 'Cargas', key: 'cbm_total', label: 'CBM (m³)', type: 'number' },
    { group: 'Cargas', key: 'tn_total', label: 'TN total', type: 'number' },
    { group: 'Valores USD', key: 'valor_fob_total', label: 'FOB', type: 'number' },
    { group: 'Valores USD', key: 'flete_total', label: 'Flete', type: 'number' },
    { group: 'Valores USD', key: 'seguro_total', label: 'Seguro', type: 'number' },
    { group: 'Valores USD', key: 'valor_cif_total', label: 'CIF', type: 'number' },
    { group: 'Valores USD', key: 'cotiz_dolar', label: 'Cotiz USD/ARS', type: 'number' },
    { group: 'Liquidación', key: 'derecho_importacion_total', label: 'Derechos', type: 'number' },
    { group: 'Liquidación', key: 'tasa_estadistica_total', label: 'Tasa Estad', type: 'number' },
    { group: 'Liquidación', key: 'iva_total', label: 'IVA 21%', type: 'number' },
    { group: 'Liquidación', key: 'iva_adic_total', label: 'IVA Adic 20%', type: 'number' },
    { group: 'Liquidación', key: 'ganancias_total', label: 'Ganancias 6%', type: 'number' },
    { group: 'Liquidación', key: 'iibb_total', label: 'IIBB', type: 'number' },
  ];
  const CAB = {};
  // IC.cab.html(despachoId, { onChanged }) — se carga sola la primera vez.
  IC.cab = {
    html(despachoId, o = {}) {
      let c = CAB[despachoId];
      if (!c) { c = CAB[despachoId] = { data: null, loading: true, saving: null, saved: null }; this.cargar(despachoId); }
      c.o = o;
      return `<div id="iccab-${IC.esc(despachoId)}">${this.cuerpo(despachoId)}</div>`;
    },
    olvidar(despachoId) { delete CAB[despachoId]; },
    repintar(id) { const el = document.getElementById('iccab-' + id); if (el && CAB[id]) IC.pintar(el, this.cuerpo(id)); },
    async cargar(id) {
      const c = CAB[id];
      try { c.data = await IC.api.editar('despacho_get', { id }); } catch (e) { IC.avisar('Error cargando cabecera: ' + (e.message || e)); }
      c.loading = false; this.repintar(id);
    },
    async guardar(id, key, value) {
      const c = CAB[id]; c.saving = key; this.repintar(id);
      const v = value === '' ? null : value;
      try { await IC.api.editar('despacho_update', { id, campo: key, valor: v }); }
      catch (e) { c.saving = null; this.repintar(id); IC.avisar('Error: ' + (e.message || e)); return; }
      c.saving = null; c.saved = key; this.repintar(id);
      setTimeout(() => { if (c.saved === key) { c.saved = null; this.repintar(id); } }, 1500);
      if (c.o && c.o.onChanged) c.o.onChanged();
    },
    cuerpo(id) {
      const c = CAB[id];
      if (c.loading) return '<div style="padding:10px;font-size:11px;color:#64748b">Cargando cabecera...</div>';
      if (!c.data) return `<div class="err-box">Despacho id=${IC.esc(id)} no encontrado</div>`;
      const data = c.data;
      const groups = [...new Set(FIELDS.map(f => f.group))];
      return `<div><div style="font-size:11px;color:#64748b;margin-bottom:8px">✏️ Editá cualquier campo (guarda al salir). Útil para corregir lo que el LLM no extrajo bien.</div>
        ${groups.map(g => `<div style="margin-bottom:12px">
          <div style="font-size:11px;font-weight:700;color:#475569;margin-bottom:4px;border-bottom:1px solid #e2e8f0;padding-bottom:2px">${IC.esc(g)}</div>
          <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:6px">
          ${FIELDS.filter(f => f.group === g).map(f => {
            const v = data[f.key]; const vacio = v == null || v === '';
            const borde = `1px solid ${vacio ? '#fca5a5' : '#cbd5e1'}`;
            const dis = c.saving === f.key ? 'disabled' : '';
            const campo = f.type === 'select'
              ? `<select data-k="cab-${id}-${f.key}" ${dis} onchange="${IC.on((e) => { data[f.key] = e.target.value; this.guardar(id, f.key, e.target.value); })}" style="padding:4px;font-size:11px;border:${borde};border-radius:4px"><option value="">-</option>${IC.opts(f.options, v)}</select>`
              : `<input data-k="cab-${id}-${f.key}" type="${f.type}" value="${IC.esc(v ?? '')}" ${dis}
                  oninput="${IC.on((e) => { data[f.key] = f.type === 'number' ? (e.target.value === '' ? '' : Number(e.target.value)) : e.target.value; })}"
                  onblur="${IC.on((e) => this.guardar(id, f.key, f.type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value))}"
                  style="padding:4px;font-size:11px;border:${borde};border-radius:4px;background:${vacio ? '#fef2f2' : 'white'}">`;
            return `<div style="display:flex;flex-direction:column;font-size:11px">
              <label style="color:${vacio ? '#dc2626' : '#475569'};margin-bottom:2px">${IC.esc(f.label)} ${vacio ? '<span style="color:#dc2626" title="Sin extraer">⚠</span>' : ''}${c.saved === f.key ? '<span style="color:#10b981;margin-left:4px">✓</span>' : ''}</label>
              ${campo}</div>`;
          }).join('')}</div></div>`).join('')}</div>`;
    },
  };

  // ── Tabla de ítems editable (EditableItems.jsx) ──────────────────────────────────────
  // IC.items.html(clave, { table, filterValue, columns:[{key,label,type,minWidth}], onChanged })
  const IT = {};
  IC.items = {
    html(k, o) {
      const id = k + '';
      let t = IT[id];
      if (!t || t.table !== o.table || t.filterValue !== o.filterValue) {
        t = IT[id] = { table: o.table, filterValue: o.filterValue, rows: [], loading: true, saving: null };
        this.cargar(id);
      }
      t.o = o;
      return `<div id="icit-${IC.esc(id)}">${this.cuerpo(id)}</div>`;
    },
    olvidar(k) { delete IT[k + '']; },
    repintar(id) { const el = document.getElementById('icit-' + id); if (el && IT[id]) IC.pintar(el, this.cuerpo(id)); },
    async cargar(id) {
      const t = IT[id];
      try { t.rows = (await IC.api.editar('items_list', { tabla: t.table, filtro_id: t.filterValue })) || []; }
      catch (e) { IC.avisar('Error cargando items: ' + (e.message || e)); }
      t.loading = false; this.repintar(id);
    },
    async guardar(id, rowId, key, value) {
      const t = IT[id]; t.saving = rowId; this.repintar(id);
      try { await IC.api.editar('item_update', { tabla: t.table, id: rowId, campo: key, valor: value === '' ? null : value }); }
      catch (e) { t.saving = null; this.repintar(id); IC.avisar('Error guardando: ' + (e.message || e)); return; }
      t.saving = null; this.repintar(id);
      if (t.o.onChanged) t.o.onChanged();
    },
    async agregar(id) {
      const t = IT[id];
      try { const data = await IC.api.editar('item_insert', { tabla: t.table, filtro_id: t.filterValue }); t.rows = [...t.rows, data]; this.repintar(id); if (t.o.onChanged) t.o.onChanged(); }
      catch (e) { IC.avisar('Error agregando: ' + (e.message || e)); }
    },
    async borrar(id, rowId) {
      if (!(await IC.confirmar('¿Eliminar este artículo?', { aceptar: 'Sí, borrar', peligro: true }))) return;
      const t = IT[id];
      try { await IC.api.editar('item_delete', { tabla: t.table, id: rowId }); t.rows = t.rows.filter(r => r.id !== rowId); this.repintar(id); if (t.o.onChanged) t.o.onChanged(); }
      catch (e) { IC.avisar('Error eliminando: ' + (e.message || e)); }
    },
    cuerpo(id) {
      const t = IT[id], cols = t.o.columns || [];
      if (t.loading) return '<div style="padding:10px;font-size:11px;color:#64748b">Cargando...</div>';
      return `<div><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px">
          <span style="font-size:11px;color:#64748b">${t.rows.length} filas · Editá cualquier celda (se guarda al salir) · Clic en 🗑 para borrar</span>
          <button onclick="${IC.on(() => this.agregar(id))}" class="btn btn-success" style="padding:3px 10px;font-size:11px">+ Agregar fila</button></div>
        <div class="report" data-k="itrep-${IC.esc(id)}" style="max-height:450px;overflow-x:auto"><table style="min-width:1400px">
          <thead><tr><th>#</th>${cols.map(c => `<th style="white-space:nowrap">${IC.esc(c.label)}</th>`).join('')}<th></th></tr></thead>
          <tbody>${t.rows.map((r, i) => `<tr style="opacity:${t.saving === r.id ? 0.5 : 1}"><td style="color:#94a3b8">${i + 1}</td>
            ${cols.map(c => {
              const mw = c.minWidth ?? (c.key === 'descripcion' ? 320 : c.key === 'ncm' ? 130 : c.key === 'nro_certificado' ? 180 : c.type === 'number' ? 90 : 110);
              const val = r[c.key] ?? '';
              return `<td style="padding:0;min-width:${mw}px"><input data-k="it-${IC.esc(id)}-${IC.esc(r.id)}-${c.key}" type="${c.type || 'text'}" value="${IC.esc(val)}" title="${IC.esc(val)}"
                oninput="${IC.on((e) => { r[c.key] = c.type === 'number' ? (e.target.value === '' ? '' : Number(e.target.value)) : e.target.value; })}"
                onblur="${IC.on((e) => this.guardar(id, r.id, c.key, c.type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value))}"
                style="border:none;width:100%;padding:3px 5px;font-size:11px;background:transparent;min-width:${mw}px"></td>`;
            }).join('')}
            <td><button onclick="${IC.on(() => this.borrar(id, r.id))}" style="background:none;border:none;cursor:pointer;color:#dc2626;font-size:12px">🗑</button></td></tr>`).join('')}
          </tbody></table></div></div>`;
    },
  };

  // ── Corregir relevamiento desde una alerta (CorregirRelevamiento.jsx) ───────────────
  // IC.corregirRelev({ alerta, codigo, marca, descripcion, onClose, onSaved })
  IC.corregirRelev = function (p) {
    const alerta = p.alerta || {};
    const S = {
      accion: alerta.tipo === 'codigo_pre_split_e' ? 'agregar_variante' : 'agregar_nuevo',
      form: { cod_lk: p.codigo || '', cod_ch: '', marca: p.marca === 'CHEF' || p.marca === 'CH' ? 'CH' : 'LK', nombre_producto: p.descripcion || '', proveedor: '', inal: null },
      saving: false, matches: [], searched: false,
    };
    const ov = document.createElement('div'); ov.id = 'icCorr';
    (document.getElementById('icOv') || document.body).appendChild(ov);
    const cerrar = () => { ov.remove(); if (p.onClose) p.onClose(); };
    const buscar = async () => {
      const code = (p.codigo || '').trim(); if (!code) return;
      try { S.matches = (await IC.api.editar('productos_buscar', { codigo: code })) || []; }
      catch (e) { IC.avisar('Error buscando: ' + (e.message || e)); S.matches = []; }
      S.searched = true; pintar();
    };
    const guardar = async () => {
      S.saving = true; pintar();
      try {
        const f = S.form;
        if (S.accion === 'agregar_nuevo' || S.accion === 'agregar_variante') {
          await IC.api.editar('producto_insert', { producto: { cod_lk: f.cod_lk || null, cod_ch: f.cod_ch || null, marca: f.marca, nombre_producto: f.nombre_producto || null, proveedor: f.proveedor || null, inal: f.inal } });
        } else if (S.accion === 'actualizar_marca') {
          const m = S.matches[0];
          if (!m) { IC.avisar('Sin match: buscá primero en el relevamiento.'); return; }
          await IC.api.editar('producto_update', { id: m.id, campo: 'marca', valor: f.marca === 'LK' && m.marca === 'LK' ? 'LK' : 'CH' });
        } else if (S.accion === 'toggle_inal') {
          const m = S.matches[0];
          if (!m) { IC.avisar('Sin match: buscá primero en el relevamiento.'); return; }
          await IC.api.editar('producto_update', { id: m.id, campo: 'inal', valor: m.inal === 'SI' ? null : 'SI' });
        }
        if (p.onSaved) p.onSaved();
        cerrar(); return;
      } catch (e) { IC.avisar('Error: ' + (e.message || e)); }
      finally { S.saving = false; if (document.contains(ov)) pintar(); }
    };
    const campo = (k, ph) => `<input data-k="cr-${k}" value="${IC.esc(S.form[k])}" ${ph ? `placeholder="${IC.esc(ph)}"` : ''} oninput="${IC.on((e) => { S.form[k] = e.target.value; })}" style="width:100%;padding:4px;font-size:11px">`;
    function pintar() {
      const f = S.form;
      IC.pintar(ov, `<div style="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);display:flex;align-items:center;justify-content:center;z-index:9300;font-family:system-ui,-apple-system,sans-serif;color:#1e293b">
        <div style="background:white;border-radius:8px;padding:20px;min-width:500px;max-width:700px;max-height:90vh;overflow:auto">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
            <h3 style="margin:0;font-size:14px">📝 Corregir Relevamiento</h3>
            <button onclick="${IC.on(cerrar)}" style="background:none;border:none;font-size:20px;cursor:pointer">✕</button></div>
          <div style="background:#fffbeb;padding:8px;border-radius:4px;font-size:11px;margin-bottom:12px"><strong>Alerta:</strong> ${IC.esc(String(alerta.descripcion || '').slice(0, 200))}</div>
          <div style="margin-bottom:10px"><button class="btn" onclick="${IC.on(buscar)}" style="font-size:11px">🔍 Buscar en relevamiento</button>
            ${S.searched ? `<div style="margin-top:8px;font-size:11px">${!S.matches.length ? '<em style="color:#dc2626">No se encontró el código en relevamiento</em>'
              : `<div>${S.matches.length} match(es) encontrado(s):<ul style="margin:4px 0;padding-left:18px">${S.matches.map(m => `<li style="font-size:11px">cod_lk=${IC.esc(m.cod_lk)} / cod_ch=${IC.esc(m.cod_ch)} | marca=${IC.esc(m.marca)} | "${IC.esc(m.nombre_producto)}" | INAL=${IC.esc(m.inal || '-')}</li>`).join('')}</ul></div>`}</div>` : ''}
          </div>
          <div style="margin-bottom:10px"><label style="font-size:11px;font-weight:600">¿Qué corregir?</label>
            <select data-k="cr-accion" onchange="${IC.on((e) => { S.accion = e.target.value; pintar(); })}" style="width:100%;padding:6px;font-size:11px;margin-top:4px">
              ${IC.opts([['agregar_nuevo', '➕ Agregar nuevo código al relevamiento'], ['agregar_variante', '➕ Agregar variante CHEF/LK del código existente'], ['actualizar_marca', '✏️ Actualizar marca del producto existente'], ['toggle_inal', '⚡ Toggle INAL=SI/NO del producto existente']], S.accion)}
            </select></div>
          ${(S.accion === 'agregar_nuevo' || S.accion === 'agregar_variante') ? `<div style="display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin-bottom:12px">
            <div><label style="font-size:11px">cod_lk (LOEKEMEYER)</label>${campo('cod_lk')}</div>
            <div><label style="font-size:11px">cod_ch (CHEF)</label>${campo('cod_ch')}</div>
            <div><label style="font-size:11px">marca principal</label><select data-k="cr-marca" onchange="${IC.on((e) => { f.marca = e.target.value; })}" style="width:100%;padding:4px;font-size:11px">${IC.opts(['LK', 'CH'], f.marca)}</select></div>
            <div><label style="font-size:11px">proveedor</label>${campo('proveedor', 'OWNLAND, KANGLI, HONG TAI...')}</div>
            <div style="grid-column:span 2"><label style="font-size:11px">nombre_producto</label>${campo('nombre_producto')}</div>
            <div><label style="font-size:11px">INAL</label><select data-k="cr-inal" onchange="${IC.on((e) => { f.inal = e.target.value || null; })}" style="width:100%;padding:4px;font-size:11px">${IC.opts([['', '- (no aplica)'], ['SI', 'SI (requiere Libre Circ)']], f.inal || '')}</select></div>
          </div>` : ''}
          <div style="display:flex;gap:8px;justify-content:flex-end">
            <button onclick="${IC.on(cerrar)}" class="btn" style="font-size:11px">Cancelar</button>
            <button onclick="${IC.on(guardar)}" ${S.saving ? 'disabled' : ''} class="btn btn-primary" style="font-size:11px">${S.saving ? 'Guardando...' : '💾 Guardar y volver'}</button>
          </div></div></div>`);
    }
    pintar();
  };

  // Precarga lo que la zona de subida necesita en el momento de soltar.
  IC.mod('archivos').then(m => { archivosMod = m; }).catch(() => {});
})();
