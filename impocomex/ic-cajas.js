/* IMPO COMEX — Cajas vs Packing List (port de CajasMode.jsx).
   Todas las fotos juntas; la IA lee cada una (rótulos y valores) y el código decide qué cara es (master
   frente / lateral, inner, cartón frente / dorso), a qué código va y la comparación contra el PL y la
   Commercial Invoice (backend, _shared/cajas.ts), sin adivinar. El código de barras se decodifica primero
   en la PC (lector local). Todo queda guardado en la base (corrida) y se puede reabrir.
   La lógica (interpretarFoto, leerCodigoBarras, generarPdfCajas, etiquetas) es la del cliente original
   (impocomex/logica/), cargada con IC.mod. */
(function () {
  'use strict';
  const IC = window.IC;

  // Fotos de una carga entera: muchas y pesadas (celular). Los archivos de carpeta se referencian sin
  // leerlos a memoria (ver archivos.js), y cada foto se achica de a una al verificar, así que el tope alto
  // es sólo un techo de seguridad, no memoria usada de golpe.
  const LIMITES_FOTOS = { archivos: 2000, bytes: 6 * 1024 * 1024 * 1024, profundidad: 5 };

  const FORMATO = {
    codigo: '437E', total_cajas: '463', caja_en_rango: '288/463', unidades_por_master: '144', unidades_por_inner: '12',
    peso_bruto_kg: '15,5', peso_neto_kg: '14', medidas_cm: '35 x 34,5 x 32,5', consignatario: 'TIERRA NATIVA SA', made_in: 'MADE IN CHINA',
    codigo_barras: '13 dígitos', articulo: 'nombre impreso', comercializador: 'nombre del frente',
    cuit_importador: 'ej. 30-12345678-9', cuit_comercializador: 'ej. 30-12345678-9',
  };
  const REGION_KEY = {
    codigo: 'codigo', total_cajas: 'numeracion', caja_en_rango: 'numeracion', unidades_por_master: 'cantidad',
    unidades_por_inner: 'cantidad', peso_bruto_kg: 'gw_kg', peso_neto_kg: 'nw_kg', medidas_cm: 'medidas',
    consignatario: 'consignatario', codigo_barras: 'codigo_barras', marca: 'marca', articulo: 'nombre_articulo',
    comercializador: 'comercializador', cuit_importador: 'cuit_importador', cuit_comercializador: 'cuit_comercializador',
  };
  const RESULTADO = {
    ok:          { txt: '✓ OK',          color: '#059669', bg: 'transparent' },
    diferencia:  { txt: '✗ Diferencia',  color: '#dc2626', bg: '#fef2f2' },
    ilegible:    { txt: '? Ilegible',    color: '#b45309', bg: '#fffbeb' },
    sin_dato_pl: { txt: '— Sin dato PL', color: '#64748b', bg: '#f8fafc' },
    falta_foto:  { txt: '📷 Falta foto',  color: '#64748b', bg: '#f8fafc' },
  };

  const pct = (v) => (v === null || v === undefined ? '—' : `${v} %`);
  const SUB = 'font-size:11px;font-weight:400;color:#64748b';
  const NW = 'white-space:nowrap';
  const CAJA_AVISO = { marginTop: 8, padding: '8px 10px', borderRadius: 6, fontSize: 12 };
  const soloDig = (v) => String(v || '').replace(/\D/g, '');
  const cuitOk = (v) => soloDig(v).length === 11;
  const fmtCuit = (v) => { const d = soloDig(v); return d.length === 11 ? `${d.slice(0, 2)}-${d.slice(2, 10)}-${d.slice(10)}` : v; };
  const claveFila = (f) => `${f.codigo}|${f.tipo_caja}|${f.campo}`;
  const normCrudos = (c) => ({ si: [...((c && c.si) || [])].sort(), no: [...((c && c.no) || [])].sort() });
  const fmtN = (n) => String(n).replace('.', ',');
  const esc = (s) => IC.esc(s);

  // Lo que se leyó de una foto sin asignar, para ayudar a elegir el código (ej. "G.W. 15 · N.W. 14 · MEAS 35x34,5x32,5").
  function resumenLectura(l) {
    const m = l.medidas_cm;
    return [
      l.codigo && `código ${l.codigo}`,
      l.numeracion_actual != null && `caja ${l.numeracion_actual}${l.numeracion_total != null ? '/' + l.numeracion_total : ''}`,
      l.cantidad_master != null && `QUANTITY ${l.cantidad_master}`,
      l.cantidad_inner != null && `INNER QTY ${l.cantidad_inner}`,
      l.gw_kg != null && `G.W. ${fmtN(l.gw_kg)}`,
      l.nw_kg != null && `N.W. ${fmtN(l.nw_kg)}`,
      m && m.l != null && m.w != null && m.h != null && `MEAS ${fmtN(m.l)}x${fmtN(m.w)}x${fmtN(m.h)}`,
      (l.codigo_barras_lector || l.codigo_barras) && `barras ${l.codigo_barras_lector || l.codigo_barras}`,
      l.comercializador_nombre && `marca ${l.comercializador_nombre}`,
      l.nombre_articulo && l.nombre_articulo,
    ].filter(Boolean).join(' · ');
  }

  // Aviso de fotos sin asignar: no se compararon hasta que se les elija el código.
  const avisoSinAsignar = (n) => `Hay ${n} foto${n === 1 ? '' : 's'} SIN ASIGNAR: no se pudo saber de qué código ${n === 1 ? 'es' : 'son'} `
    + '(no tienen el código impreso —ej. el lateral de la master— ni en el nombre del archivo), así que NO se compararon. '
    + 'Elegí el código de cada una en el recuadro amarillo "Fotos sin asignar" y tocá Recalcular.';

  async function achicarFoto(file, maxLado = 1600, calidad = 0.85) {
    if (!file.type.startsWith('image/')) return file;
    // createImageBitmap decodifica más formatos y usa menos memoria; si no, cae a <img>. Si nada la abre,
    // tira un Error con mensaje claro (ej. HEIC de celular o archivo dañado) — no un Event ("[object Event]").
    const cargar = async () => {
      if (typeof createImageBitmap === 'function') {
        try { return await createImageBitmap(file); } catch (_) { /* cae a <img> */ }
      }
      const url = URL.createObjectURL(file);
      try {
        return await new Promise((ok, mal) => {
          const i = new Image();
          i.onload = () => ok(i);
          i.onerror = () => mal(new Error('formato de imagen no soportado (ej. HEIC/HEIF de celular) o archivo dañado; convertila a JPG'));
          i.src = url;
        });
      } finally { URL.revokeObjectURL(url); }
    };
    const img = await cargar();
    try {
      const iw = img.width, ih = img.height;
      const escala = Math.min(1, maxLado / Math.max(iw, ih));
      if (escala === 1 && file.size < 1500000) return file;
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(iw * escala);
      canvas.height = Math.round(ih * escala);
      canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise(ok => canvas.toBlob(ok, 'image/jpeg', calidad));
      if (!blob) throw new Error('no se pudo comprimir la imagen');
      return new File([blob], file.name.replace(/\.\w+$/, '') + '.jpg', { type: 'image/jpeg' });
    } finally { if (img.close) img.close(); }
  }

  async function textoYArchivo(fd, prefijo, archivo) {
    const { extractText } = await IC.mod('pdfText');
    const texto = await extractText(archivo);
    if (texto && texto.length > 200) fd.append(`${prefijo}_text`, texto);
    fd.append(`${prefijo}_file`, archivo, archivo.name);
  }

  IC.modo('cajas', async function (el) {
    let ET, FOT;
    try {
      [ET, FOT] = await Promise.all([IC.mod('cajasEtiquetas'), IC.mod('cajasFotos')]);
    } catch (e) {
      IC.pintar(el, `<div class="err-box">No se pudo cargar el modo Cajas: ${esc(e.message || e)}</div>`);
      return;
    }
    if (!el.isConnected) return;
    const { CAMPOS, CARA, cajaDe, pctTxt } = ET;
    const { interpretarFoto } = FOT;
    const api = IC.api;
    const avisar = IC.avisar, confirmar = IC.confirmar;

    const S = {
      plFiles: [], ciFiles: [], fotos: [], tipoEnvio: 'LCL', nroCarga: '',
      loading: false, progress: '', error: null, res: null, soloProblemas: false,
      correcciones: {},   // clave de fila -> valor a mano (pendiente)
      editando: {},       // clave de fila -> true (corregir una diferencia)
      asignar: {},        // foto -> { codigo, cara } (pendiente)
      crudosSel: null,    // { si, no } tildes de parte cruda (pendiente)
      recalculando: false,
      corridas: null,     // lista de corridas guardadas (null = cerrada)
      // Importador (uno por carga). Comercializadores = lista de empresas (cuit+razón) con sus cartones.
      importadores: [], selImp: '', cuitImp: '', razonImp: '',
      comercializadores: [], nuevoCom: { cuit: '', razon: '' },
      // Revisión manual por fila: clave -> { revision:'ok'|'mal'|'', motivo }
      revisiones: {},
      guardando: false,
    };
    const barcodes = new Map();          // nombre de foto -> EAN13 del lector (o null)
    const cartonTxt = {};                // id de comercializador -> texto del input "+ cartón" (no controlado en React)
    const vivo = () => el.isConnected;
    const render = () => { if (vivo()) IC.pintar(el, html()); };
    const panelSinAsignar = () => el.querySelector('[data-k="cajasSinAsignar"]');

    // Avisa (diálogo dentro de la página) si quedaron fotos sin asignar y lleva la vista al recuadro.
    const avisarSinAsignar = async (r) => {
      const n = ((r && r.sin_asignar) || []).length;
      if (!n) return;
      await avisar(avisoSinAsignar(n));
      setTimeout(() => { const p = panelSinAsignar(); if (p) p.scrollIntoView({ behavior: 'smooth', block: 'center' }); }, 50);
    };

    const cargarEntidades = () => api.postJson('/verify-cajas', { accion: 'cuit_entidades_listar' }).then(r => {
      S.importadores = r.importadores || [];
      S.comercializadores = r.comercializadores || [];
      render();
    }).catch(() => {});

    const elegirImportador = (id) => {
      S.selImp = id;
      const e = S.importadores.find(x => x.id === id);
      if (e) { S.cuitImp = fmtCuit(e.cuit); S.razonImp = e.razon_social; }
      render();
    };
    const guardarImportador = async () => {
      if (!cuitOk(S.cuitImp) || !S.razonImp.trim()) { avisar('Completá el CUIT (11 dígitos) y la razón social del importador.'); return; }
      try {
        await api.postJson('/verify-cajas', { accion: 'cuit_entidad_guardar', tipo: 'importador', cuit: soloDig(S.cuitImp), razon_social: S.razonImp.trim() });
        await cargarEntidades();
      } catch (e) { avisar('No se pudo guardar: ' + (e.message || e)); }
    };
    const setComCampo = (campo, val) => { S.nuevoCom = Object.assign({}, S.nuevoCom, { [campo]: val }); render(); };
    const guardarComercializador = async () => {
      // El alta no pide cartón: el servidor registra la razón social sin SRL/SA como cartón y los demás
      // nombres impresos se agregan en la fila del comercializador (+ cartón).
      const { cuit, razon } = S.nuevoCom;
      if (!cuitOk(cuit) || !razon.trim()) { avisar('Completá el CUIT (11 dígitos) y la razón social del comercializador.'); return; }
      try {
        await api.postJson('/verify-cajas', { accion: 'cuit_entidad_guardar', tipo: 'comercializador', cuit: soloDig(cuit), razon_social: razon.trim() });
        S.nuevoCom = { cuit: '', razon: '' }; render();
        await cargarEntidades();
      } catch (e) { avisar('No se pudo guardar: ' + (e.message || e)); }
    };
    const agregarCarton = async (c, carton) => {
      if (!carton.trim()) return;
      try {
        await api.postJson('/verify-cajas', { accion: 'cuit_entidad_guardar', tipo: 'comercializador', cuit: soloDig(c.cuit), razon_social: c.razon_social, carton: carton.trim() });
        await cargarEntidades();
      } catch (e) { avisar('No se pudo agregar el cartón: ' + (e.message || e)); }
    };
    const borrarCarton = async (id) => {
      try { await api.postJson('/verify-cajas', { accion: 'cuit_carton_borrar', id }); await cargarEntidades(); }
      catch (e) { avisar('No se pudo borrar el cartón: ' + (e.message || e)); }
    };
    const borrarComercializador = async (id) => {
      const ok = await confirmar('¿Borrar este comercializador y todos sus cartones?');
      if (!ok) return;
      try { await api.postJson('/verify-cajas', { accion: 'cuit_comercializador_borrar', id }); await cargarEntidades(); }
      catch (e) { avisar('No se pudo borrar: ' + (e.message || e)); }
    };

    const recibirFotos = (nuevas) => {
      const prev = S.fotos;
      const usados = new Set(prev.map(f => f.nombre));
      const agregadas = nuevas.map(file => {
        let nombre = file.name; let n = 2;
        while (usados.has(nombre)) nombre = `${file.name} (${n++})`;
        usados.add(nombre);
        const { codigo } = interpretarFoto(file.name);
        return { file, url: URL.createObjectURL(file), nombre, pistaCodigo: codigo };
      });
      S.fotos = [...prev, ...agregadas];
      render();
    };
    const quitarFoto = (i) => { const l = S.fotos; URL.revokeObjectURL(l[i].url); S.fotos = l.filter((_, k) => k !== i); render(); };
    const urlPorNombre = () => Object.fromEntries(S.fotos.map(f => [f.nombre, f.url]));

    const puedeVerificar = () => S.plFiles.length > 0 && S.fotos.length > 0 && cuitOk(S.cuitImp) && S.razonImp.trim() && !S.loading;

    const limpiarPendientes = () => { S.correcciones = {}; S.editando = {}; S.asignar = {}; S.crudosSel = null; };

    // Verificación EN PARTES: 1) packing list + CI, 2) fotos de a 6 (3 pedidos a la vez), 3) comparar y guardar.
    // Cada pedido tarda menos de ~1 minuto: nunca llega al corte de 150 s del servidor, con las fotos que sean.
    const LOTE_FOTOS = 6, PEDIDOS_A_LA_VEZ = 3;
    // Reintenta sólo cortes de red o del servidor (5xx, 504 por tiempo); un error de datos no se repite.
    const conReintento = async (fn, intentos = 3) => {
      for (let i = 1; ; i++) {
        try { return await fn(); }
        catch (e) {
          const reintentable = /^5\d\d\b|failed to fetch|networkerror|timeout|load failed/i.test(String((e && e.message) || e));
          if (!reintentable || i >= intentos) throw e;
          await new Promise(r => setTimeout(r, 2000 * i));
        }
      }
    };
    const setProgress = (t) => { S.progress = t; render(); };

    const verificar = async () => {
      S.error = null; S.res = null; S.revisiones = {}; limpiarPendientes();
      S.loading = true; render();
      const t0 = Date.now();
      const fotos = S.fotos, plFiles = S.plFiles, ciFiles = S.ciFiles;
      const tipoEnvio = S.tipoEnvio, cuitImp = S.cuitImp, razonImp = S.razonImp, nroCarga = S.nroCarga;
      // Mismo carga_ref para todos los pedidos de esta corrida: el respaldo (fotos + docs) vive junto por carga.
      const cargaRef = new Date().toISOString().replace(/[-:.]/g, '') + '_' + crypto.randomUUID().slice(0, 8);
      try {
        const { leerCodigoBarras } = await IC.mod('barcodeLocal');
        for (let i = 0; i < fotos.length; i++) {
          const f = fotos[i];
          setProgress(`Leyendo códigos de barras ${i + 1}/${fotos.length}...`);
          if (!barcodes.has(f.nombre)) barcodes.set(f.nombre, await leerCodigoBarras(f.file).catch(() => null));
        }

        // 1) Documentos
        setProgress(ciFiles.length ? 'Leyendo packing list y Commercial Invoice...' : 'Leyendo packing list...');
        const fdDoc = new FormData();
        fdDoc.append('accion', 'leer_documentos');
        fdDoc.append('carga_ref', cargaRef);
        await textoYArchivo(fdDoc, 'pl', plFiles[0]);
        if (ciFiles.length) await textoYArchivo(fdDoc, 'ci', ciFiles[0]);
        const docs = await conReintento(() => api.postForm('/verify-cajas', fdDoc));

        // 2) Fotos, de a pocas
        const grupos = [];
        for (let i = 0; i < fotos.length; i += LOTE_FOTOS) grupos.push(fotos.slice(i, i + LOTE_FOTOS));
        const lecturas = [];
        const erroresOcr = [];
        let costo = Number(docs.costo || 0), hechas = 0, siguiente = 0;
        setProgress(`Leyendo fotos con IA: 0/${fotos.length}...`);
        const trabajador = async () => {
          while (siguiente < grupos.length) {
            const grupo = grupos[siguiente++];
            const fd = new FormData();
            fd.append('accion', 'leer_fotos');
            fd.append('carga_ref', cargaRef);
            let n = 0; // índice compacto: una foto que no abre se saltea y no corta el resto
            for (let k = 0; k < grupo.length; k++) {
              let chica;
              try { chica = await achicarFoto(grupo[k].file); }
              catch (e) { erroresOcr.push(`${grupo[k].nombre}: ${e.message || e} (no se pudo abrir; se salteó)`); continue; }
              fd.append(`foto_${n}`, chica, chica.name);
              fd.append(`foto_${n}_nombre`, grupo[k].nombre);
              if (grupo[k].pistaCodigo) fd.append(`foto_${n}_pista_codigo`, grupo[k].pistaCodigo);
              const bc = barcodes.get(grupo[k].nombre);
              if (bc) fd.append(`foto_${n}_barcode`, bc);
              n++;
            }
            if (n > 0) {
              try {
                const r = await conReintento(() => api.postForm('/verify-cajas', fd));
                lecturas.push(...(r.lecturas || []));
                costo += Number(r.costo_usd || 0);
                erroresOcr.push(...(r.errores_ocr || []));
              } catch (e) {
                erroresOcr.push(`${grupo.map(f => f.nombre).join(', ')}: ${e.message || e} (no se leyeron; volvé a verificar)`);
              }
            }
            hechas += grupo.length;
            setProgress(`Leyendo fotos con IA: ${hechas}/${fotos.length}...`);
          }
        };
        await Promise.all(Array.from({ length: Math.min(PEDIDOS_A_LA_VEZ, grupos.length) }, trabajador));
        if (!lecturas.length) throw new Error(`No se pudo leer ninguna foto. ${erroresOcr.slice(0, 3).join(' · ')}`);

        // 3) Comparar y guardar
        setProgress('Comparando y guardando...');
        const r = await conReintento(() => api.postJson('/verify-cajas', {
          accion: 'comparar', carga_ref: cargaRef, pl_items: docs.pl_items, ci: docs.ci, pl_ref: docs.pl_ref, ci_ref: docs.ci_ref,
          ctns_total: docs.ctns_total, lecturas, tipo_envio: tipoEnvio, cuit_importador: soloDig(cuitImp),
          razon_importador: razonImp.trim(), nro_carga: nroCarga.trim() || null, costo_usd: costo,
          errores_ocr: erroresOcr, avisos: docs.avisos || [], duracion_ms: Date.now() - t0,
        }), 2);
        S.res = Object.assign({}, r, { correcciones_aplicadas: [] });
        S.loading = false; S.progress = ''; render();
        if (vivo()) avisarSinAsignar(r);
      } catch (e) {
        const msg = (e && e.message) || (e && e.type ? `error de ${e.type}` : String(e));
        S.error = msg === '[object Event]' ? 'Error al procesar una foto (formato no soportado o archivo dañado).' : msg;
      } finally {
        S.loading = false; S.progress = ''; render();
      }
    };

    // ---- Pendientes (a mano) y recalcular ----
    const filaPorClave = () => new Map(((S.res && S.res.resultados) || []).map(f => [claveFila(f), f]));
    const crudosActual = () => S.crudosSel != null ? S.crudosSel : normCrudos(S.res && S.res.crudos);
    const esCrudo = (c) => { const ca = crudosActual(); return ca.no.includes(c) ? false : ca.si.includes(c) ? true : ((S.res && S.res.crudos_auto) || []).includes(c); };
    const toggleCrudo = (c) => {
      const ca = crudosActual();
      const quiero = !esCrudo(c), auto = ((S.res && S.res.crudos_auto) || []).includes(c);
      const si = ca.si.filter(x => x !== c), no = ca.no.filter(x => x !== c);
      if (quiero !== auto) (quiero ? si : no).push(c);
      S.crudosSel = { si, no };
      render();
    };
    const crudosCambiados = () => !!S.res && JSON.stringify(normCrudos(crudosActual())) !== JSON.stringify(normCrudos(S.res.crudos));
    const hayCorrecciones = () => Object.values(S.correcciones).some(v => String(v).trim());
    const hayAsignaciones = () => Object.values(S.asignar).some(a => a && a.codigo);
    const pendientes = () => hayCorrecciones() || hayAsignaciones() || crudosCambiados();
    const recalculable = () => !!(S.res && S.res.pl_items && S.res.pl_items.length);

    const editar = (f, valor) => { S.correcciones = Object.assign({}, S.correcciones, { [claveFila(f)]: valor }); render(); };
    const recalcular = async () => {
      const res = S.res;
      if (!recalculable()) { avisar('Esta corrida es anterior a r54 y no guardó los datos para recalcular. Volvé a verificar con las fotos.'); return null; }
      const fpc = filaPorClave();
      const nuevas = Object.entries(S.correcciones).filter(([, v]) => String(v).trim()).map(([k, valor]) => {
        const f = fpc.get(k);
        return { codigo: f.codigo, tipo: f.tipo_caja, campo: f.campo, cara: f.cara || null, valor: String(valor).trim() };
      });
      const previas = (res.correcciones_aplicadas || []).filter(c => !nuevas.some(n => n.codigo === c.codigo && n.tipo === c.tipo && n.campo === c.campo));
      const todas = [...previas, ...nuevas];
      const asignaciones = Object.entries(S.asignar).filter(([, a]) => a && a.codigo).map(([foto, a]) => ({ foto, codigo: a.codigo, caras: a.cara ? [a.cara] : null }));
      const sinCara = Object.entries(S.asignar).filter(([foto, a]) => a && a.codigo && !a.cara && !((((res.sin_asignar || []).find(l => l.foto === foto)) || {}).caras || []).length);
      if (sinCara.length) { avisar(`Elegí también qué cara es: ${sinCara.map(([foto]) => foto).join(', ')}.`); return null; }
      S.recalculando = true; S.error = null; render();
      try {
        const r = await api.postJson('/verify-cajas', {
          accion: 'recomparar', corrida_id: res.corrida_id, pl_items: res.pl_items, lecturas: res.lecturas, correcciones: todas,
          asignaciones, crudos: crudosActual(), ci: res.ci, tipo_envio: res.tipo_envio, cuit_importador: res.cuit_importador,
          razon_importador: res.razon_importador, ctns_total: res.ctns_total,
        });
        S.res = Object.assign({}, S.res, { resumen: r.resumen, lectura: r.lectura, resultados: r.resultados, lecturas: r.lecturas,
          sin_asignar: r.sin_asignar, crudos: r.crudos, crudos_auto: r.crudos_auto, correcciones_aplicadas: todas,
          guardado: r.guardado, error_guardar: r.error_guardar });
        limpiarPendientes();
        return r;
      } catch (e) { S.error = e.message || String(e); return null; }
      finally { S.recalculando = false; render(); }
    };

    // Guardar: lo pendiente (valores a mano, asignaciones, crudos) se recalcula y queda en la base; después la
    // revisión manual (bien/mal + motivo). Avisa qué se guardó de verdad.
    const guardar = async () => {
      const res = S.res;
      if (!res || !res.corrida_id) { avisar('Esta corrida no tiene número: no se guardó. Volvé a verificar.'); return; }
      S.guardando = true; render();
      const msgs = [];
      let quedanSinAsignar = (res.sin_asignar || []).length;
      try {
        if (pendientes()) {
          const r = await recalcular();
          if (!r) return;
          quedanSinAsignar = (r.sin_asignar || []).length;
          msgs.push(r.guardado ? 'Resultado recalculado y guardado en la base.' : `El resultado recalculado NO se pudo guardar: ${r.error_guardar || 'error desconocido'}.`);
        }
        const lista = Object.entries(S.revisiones).filter(([, v]) => v.revision || (v.motivo && v.motivo.trim()) || v.cambiada)
          .map(([k, v]) => { const [codigo, tipo_caja, campo] = k.split('|'); return { codigo, tipo_caja, campo, revision: v.revision || null, motivo: v.motivo || '' }; });
        if (lista.length) {
          const r = await api.postJson('/verify-cajas', { accion: 'revision_guardar', corrida_id: res.corrida_id, revisiones: lista });
          msgs.push(`Revisión manual: ${r.guardadas} fila(s) guardada(s).`);
          if (r.no_encontradas && r.no_encontradas.length) msgs.push(`No se encontraron en la base: ${r.no_encontradas.join(', ')}.`);
          S.revisiones = Object.fromEntries(Object.entries(S.revisiones).map(([k, v]) => [k, Object.assign({}, v, { cambiada: false })]));
        }
        if (!msgs.length) msgs.push('No hay cambios para guardar: el resultado de esta corrida ya está en la base.');
        if (quedanSinAsignar) msgs.push(`Ojo: quedan ${quedanSinAsignar} foto(s) sin asignar que no se compararon. Asignales el código y recalculá.`);
        avisar(msgs.join('\n'));
      } catch (e) { avisar('No se pudo guardar: ' + (e.message || e)); }
      finally { S.guardando = false; render(); }
    };

    // ---- Corridas guardadas ----
    const abrirLista = async () => {
      try { const r = await api.postJson('/verify-cajas', { accion: 'corridas_listar' }); S.corridas = r.corridas || []; render(); }
      catch (e) { avisar('No se pudo leer la lista de corridas: ' + (e.message || e)); }
    };
    const abrirCorrida = async (id) => {
      if (pendientes() && !(await confirmar('Hay cambios sin guardar en el resultado actual. ¿Abrir otra corrida igual?'))) return;
      try {
        const r = await api.postJson('/verify-cajas', { accion: 'corrida_abrir', corrida_id: id });
        limpiarPendientes();
        S.revisiones = Object.fromEntries((r.resultados || []).filter(f => f.revision || f.motivo)
          .map(f => [claveFila(f), { revision: f.revision || '', motivo: f.motivo || '' }]));
        S.res = Object.assign({}, r, { correcciones_aplicadas: r.correcciones || [] });
        S.corridas = null;
        render();
        avisarSinAsignar(r);
      } catch (e) { avisar('No se pudo abrir la corrida: ' + (e.message || e)); }
    };

    // Ver de dónde salió un dato: sólo las fotos de ESA cara de ESE código (nunca la foto de otra caja).
    const verFuente = (f) => {
      const res = S.res;
      if (f.resultado === 'falta_foto' || f.tipo_caja === 'documentos') { if (f.detalle) avisar(f.detalle); return; }
      const upn = urlPorNombre();
      const deCara = (l) => (f.cara ? (l.caras || []).includes(f.cara) : (l.tipo === f.tipo_caja));
      const lecturasCod = (((res && res.lecturas) || {})[f.codigo] || []).filter(l => upn[l.foto] && deCara(l));
      const items = lecturasCod.map(l => ({
        src: upn[l.foto],
        region: l.foto === f.foto_nombre ? (l.regiones || {})[REGION_KEY[f.campo]] : undefined,
        etiqueta: `${(l.caras || []).map(c => CARA[c]).join(' + ') || l.tipo} · ${l.foto}${f.detalle ? ' — ' + f.detalle : ''}`,
      }));
      if (!items.length) {
        avisar(`${f.detalle ? f.detalle + '\n\n' : ''}No hay foto de ${f.cara ? CARA[f.cara] : 'esta caja'} cargada en la pantalla${res && res.abierta ? ' (corrida abierta desde la base: las fotos no se guardan)' : ''}.`);
        return;
      }
      const inicio = Math.max(0, lecturasCod.findIndex(l => l.foto === f.foto_nombre));
      IC.lightbox({ items, inicio });
    };

    const setRevision = (f, cambio) => {
      const k = claveFila(f);
      S.revisiones = Object.assign({}, S.revisiones, { [k]: Object.assign({ revision: '', motivo: '' }, S.revisiones[k], cambio, { cambiada: true }) });
    };

    const descargarPdf = async () => {
      try {
        const { generarPdfCajas } = await IC.mod('cajasPdf');
        const res = S.res;
        const bytes = await generarPdfCajas(res, S.revisiones);
        const url = URL.createObjectURL(new Blob([bytes], { type: 'application/pdf' }));
        const a = document.createElement('a');
        a.href = url; a.download = `Verificacion cajas ${(res.pl && res.pl.invoice_ref) || S.nroCarga || ''}`.trim().replace(/[\\/:*?"<>|]/g, '-') + '.pdf';
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 60000);
      } catch (e) { avisar('No se pudo generar el PDF: ' + (e.message || e)); }
    };

    // Input de CUIT (inputCuit del original): borde amarillo si no tiene 11 dígitos. Al salir se formatea
    // escribiendo el campo directo (sin repintar: si no, el click en 💾 que provocó el blur se perdía).
    const inputCuit = (k, val, onInput, onBlur) => {
      const bien = cuitOk(val) || !val;
      return `<input data-k="${k}" value="${esc(val)}" placeholder="ej. 30-12345678-9"
        oninput="${IC.on((e) => onInput(e.target.value))}" onblur="${IC.on((e, inp) => { const v = onBlur(); if (inp.value !== v) inp.value = v; })}"
        style="padding:4px;font-size:12px;width:150px;border:1px solid ${bien ? '#cbd5e1' : '#f59e0b'};background:${bien ? '#fff' : '#fffbeb'}">`;
    };

    // ── render ───────────────────────────────────────────────────────────────────────
    function htmlCorridas() {
      const corridas = S.corridas;
      if (!corridas) return '';
      const btnChico = 'font-size:10px;padding:1px 8px';
      return `<div style="${IC.st(Object.assign({}, CAJA_AVISO, { background: '#f8fafc', border: '1px solid #e2e8f0', marginBottom: 10 }))}">
        <div style="display:flex;align-items:center;margin-bottom:6px">
          <b>Corridas guardadas</b><div style="flex:1"></div>
          <button class="btn btn-secondary" style="${btnChico}" onclick="${IC.on(() => { S.corridas = null; render(); })}">Cerrar</button>
        </div>
        ${corridas.length === 0 ? '<div style="color:#64748b">No hay corridas guardadas.</div>' : `
          <div data-k="cajasCorr" style="overflow-x:auto;max-height:260px">
            <table style="font-size:11px;width:auto">
              <thead><tr><th>Fecha</th><th>PL</th><th>Carga</th><th>Importador</th><th>OK</th><th>Dif.</th><th>Ileg.</th><th>Falta foto</th><th>Graves</th><th>Revisadas</th><th></th></tr></thead>
              <tbody>
                ${corridas.map(c => `<tr>
                  <td style="${NW}">${esc(new Date(c.created_at).toLocaleString('es-AR'))}</td>
                  <td style="${NW}">${esc(c.pl_ref || '—')}</td><td style="${NW}">${esc(c.nro_carga || '—')}</td><td style="${NW}">${esc(c.razon_importador || '—')}</td>
                  <td>${esc(c.ok)}</td><td style="${c.diferencia ? 'color:#dc2626' : ''}">${esc(c.diferencia)}</td><td>${esc(c.ilegible)}</td><td>${esc(c.falta_foto)}</td>
                  <td style="${c.graves ? 'color:#dc2626;' : ''}font-weight:${c.graves ? 700 : 400}">${esc(c.graves)}</td><td>${esc(c.revisadas)}</td>
                  <td><button class="btn btn-secondary" style="${btnChico}" onclick="${IC.on(() => abrirCorrida(c.corrida_id))}">Abrir</button>
                    ${!c.recalculable ? '<span title="Anterior a r54: se ve y se revisa, pero no se puede recalcular" style="color:#94a3b8;margin-left:4px">(solo ver)</span>' : ''}</td>
                </tr>`).join('')}
              </tbody>
            </table>
          </div>`}
      </div>`;
    }

    function htmlComercializadores() {
      const lista = S.comercializadores;
      if (!lista.length) return '';
      return `<div style="display:grid;gap:4px;border-top:1px solid #cbd5e1;padding-top:6px" data-lista-comercializadores>
        ${lista.map(c => `<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;font-size:11px;background:#f8fafc;padding:4px 8px;border-radius:4px">
          <span style="font-weight:600">${esc(c.razon_social)}</span>
          <code style="font-size:11px">${esc(fmtCuit(c.cuit))}</code>
          <span style="color:#94a3b8">cartones:</span>
          ${(c.cartones || []).length === 0 ? '<span style="color:#dc2626">sin cartón</span>' : ''}
          ${(c.cartones || []).map(t => `<span style="display:inline-flex;align-items:center;gap:3px;background:#e2e8f0;border-radius:10px;padding:1px 7px">
            ${esc(t.carton)}
            <button onclick="${IC.on(() => borrarCarton(t.id))}" title="Quitar cartón" style="border:none;background:none;cursor:pointer;color:#64748b;font-size:11px;line-height:1">✕</button>
          </span>`).join('')}
          <input data-k="carton-${esc(c.id)}" placeholder="+ cartón (Enter)" value="${esc(cartonTxt[c.id] || '')}"
            oninput="${IC.on((e) => { cartonTxt[c.id] = e.target.value; })}"
            onkeydown="${IC.on((e) => { if (e.key === 'Enter') { agregarCarton(c, e.target.value); e.target.value = ''; cartonTxt[c.id] = ''; } })}"
            style="font-size:11px;padding:1px 6px;width:120px">
          <button onclick="${IC.on(() => borrarComercializador(c.id))}" title="Borrar comercializador" style="border:none;background:none;cursor:pointer;color:#dc2626;margin-left:auto">🗑</button>
        </div>`).join('')}
      </div>`;
    }

    function htmlFotos() {
      const fotos = S.fotos;
      if (!fotos.length) return '';
      return `<div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:8px">
        ${fotos.map((f, i) => {
          const bc = barcodes.get(f.nombre);
          return `<div style="position:relative;width:84px">
            <img src="${esc(f.url)}" alt="${esc(f.nombre)}" title="${esc(f.nombre)}" onclick="${IC.on(() => IC.lightbox({ src: f.url, etiqueta: f.nombre }))}"
              style="width:84px;height:84px;object-fit:cover;border-radius:4px;display:block;cursor:zoom-in;border:1px solid #e2e8f0">
            <button onclick="${IC.on(() => quitarFoto(i))}" title="Quitar"
              style="position:absolute;top:2px;right:2px;background:rgba(255,255,255,0.9);border:none;border-radius:4px;width:18px;height:18px;font-size:11px;line-height:1;cursor:pointer;color:#dc2626">✕</button>
            ${(f.pistaCodigo || bc) ? `<div style="font-size:9px;color:#94a3b8;${NW};overflow:hidden;text-overflow:ellipsis"
              title="${bc ? esc(`Código de barras leído por la PC: ${bc}`) : ''}">${esc([f.pistaCodigo, bc ? '▮' + bc.slice(-4) : null].filter(Boolean).join(' · '))}</div>` : ''}
          </div>`;
        }).join('')}
        <button class="btn btn-secondary" style="font-size:10px;padding:2px 8px;align-self:flex-start"
          onclick="${IC.on(() => { S.fotos.forEach(f => URL.revokeObjectURL(f.url)); S.fotos = []; barcodes.clear(); render(); })}">Quitar todas</button>
      </div>`;
    }

    function htmlResultado() {
      const res = S.res;
      if (!res) return '';
      const upn = urlPorNombre();
      const filas = res.resultados.filter(f => !S.soloProblemas || f.resultado !== 'ok');
      const codigosPl = [...new Set((res.pl_items || []).map(it => String(it.cod || '').toUpperCase().trim()).filter(Boolean))];
      const faltanM = new Map();
      for (const f of res.resultados || []) if (f.resultado === 'falta_foto') { if (!faltanM.has(f.codigo)) faltanM.set(f.codigo, []); faltanM.get(f.codigo).push(cajaDe(f)); }
      const faltan = [...faltanM];
      const sinAsig = res.sin_asignar || [];
      const pend = pendientes(), recalc = recalculable();
      const irPanel = () => { const p = panelSinAsignar(); if (p) p.scrollIntoView({ behavior: 'smooth', block: 'center' }); };

      const filasHtml = filas.map((f, i) => {
        const r = RESULTADO[f.resultado] || RESULTADO.diferencia;
        const k = claveFila(f);
        const nuevoCodigo = i === 0 || filas[i - 1].codigo !== f.codigo;
        const corregible = f.campo in FORMATO && f.tipo_caja !== 'documentos' && (f.resultado === 'ilegible' || f.resultado === 'diferencia');
        const conInput = corregible && (f.resultado === 'ilegible' || S.editando[k]);
        const rev = S.revisiones[k] || {};
        const url = f.foto_nombre && upn[f.foto_nombre];
        const clic = f.resultado !== 'ok' || f.detalle;
        let fotoCelda;
        if (url) fotoCelda = `<img src="${esc(url)}" alt="" title="${esc(`Ver: ${f.foto_nombre}`)}" onclick="${IC.on(() => verFuente(f))}"
            style="width:34px;height:34px;object-fit:cover;border-radius:3px;cursor:zoom-in;border:1px solid #e2e8f0;display:block">`;
        else if (f.resultado === 'falta_foto') fotoCelda = '<span style="color:#94a3b8">no hay</span>';
        else if (f.foto_nombre) fotoCelda = `<span style="color:#94a3b8" title="${esc(f.foto_nombre)}">(no cargada)</span>`;
        else fotoCelda = f.valor_pl ? '<span style="color:#94a3b8">PL</span>' : '—';
        return `<tr style="background:${r.bg};${nuevoCodigo && i ? 'border-top:2px solid #cbd5e1' : ''}">
          <td style="${NW}">${nuevoCodigo ? `<code>${esc(f.codigo)}</code>` : ''}</td>
          <td style="${NW}">${esc(cajaDe(f))}</td>
          <td style="${NW}">${esc(CAMPOS[f.campo] || f.campo)}</td>
          <td style="${NW}" title="${esc(f.foto_nombre || '')}">
            ${conInput
              ? `<input data-k="corr-${esc(k)}" value="${esc(S.correcciones[k] != null ? S.correcciones[k] : '')}" oninput="${IC.on((e) => editar(f, e.target.value))}"
                  placeholder="${esc(f.valor_foto || FORMATO[f.campo])}"
                  style="font-size:11px;padding:2px 4px;width:140px;border:1px solid #f59e0b;background:#fffbeb">`
              : `${esc(f.valor_foto != null ? f.valor_foto : '—')}${corregible ? `<button onclick="${IC.on(() => { S.editando = Object.assign({}, S.editando, { [k]: true }); render(); })}" title="Corregir a mano (valor mal leído)"
                  style="margin-left:4px;border:none;background:none;cursor:pointer;color:#64748b;font-size:11px">✎</button>` : ''}`}
          </td>
          <td style="font-size:12px">
            <div style="${NW}">${esc(f.valor_pl != null ? f.valor_pl : '—')}</div>
            ${f.calculo ? `<div style="font-size:10px;color:#64748b;white-space:normal;max-width:380px">
              ${String(f.calculo).split(' | ').map(l => `<div>${esc(l)}</div>`).join('')}</div>` : ''}
          </td>
          <td style="${NW};color:${r.color};font-weight:600;cursor:${clic ? 'pointer' : 'default'};text-decoration:${f.detalle ? 'underline dotted' : 'none'}"
            title="${esc(f.detalle || '')}" onclick="${IC.on(() => { if (clic) verFuente(f); })}">
            ${esc(r.txt)}${f.dif_pct ? `<span style="font-weight:400;margin-left:4px">(${esc(pctTxt(f.dif_pct))})</span>` : ''}
            ${f.grave ? '<span style="margin-left:6px;padding:0 5px;border-radius:3px;background:#dc2626;color:#fff;font-size:9px;font-weight:700;letter-spacing:.3px">GRAVE</span>' : ''}
          </td>
          <td style="${NW}">${fotoCelda}</td>
          <td style="${NW}">
            <select data-k="rev-${esc(k)}" onchange="${IC.on((e) => { setRevision(f, { revision: e.target.value }); render(); })}" style="font-size:11px;padding:2px">
              ${IC.opts([['', 'auto'], ['ok', '✓ bien'], ['mal', '✗ mal']], rev.revision || '')}
            </select>
          </td>
          <td>
            <input data-k="mot-${esc(k)}" value="${esc(rev.motivo || '')}" oninput="${IC.on((e) => setRevision(f, { motivo: e.target.value }))}" placeholder="motivo"
              style="font-size:11px;padding:2px 4px;width:200px">
          </td>
        </tr>`;
      }).join('');

      return `<div class="card">
        <div class="card-header">
          <h3>Resultado</h3>
          <span style="font-size:10px;color:${res.error_guardar ? '#dc2626' : '#059669'};margin-left:8px">
            ${esc(res.corrida_id ? `corrida ${String(res.corrida_id).slice(0, 8)} · ${res.error_guardar ? '⚠ no se guardó' : res.abierta ? 'abierta desde la base' : 'guardada ✓'}` : 'sin guardar')}
          </span>
          ${sinAsig.length > 0 ? `<button onclick="${IC.on(irPanel)}" title="Ir a las fotos sin asignar"
            style="margin-left:8px;padding:1px 8px;border-radius:10px;border:1px solid #f59e0b;background:#fef3c7;color:#92400e;font-size:11px;font-weight:700;cursor:pointer">
            ⚠ ${sinAsig.length} foto${sinAsig.length === 1 ? '' : 's'} sin asignar
          </button>` : ''}
          <div style="flex:1"></div>
          <label style="font-size:11px;display:flex;align-items:center;gap:4px">
            <input data-k="soloProb" type="checkbox" ${S.soloProblemas ? 'checked' : ''} onchange="${IC.on((e) => { S.soloProblemas = e.target.checked; render(); })}"> Solo problemas
          </label>
        </div>

        ${res.lectura ? `<div class="stats" style="display:flex;flex-wrap:wrap">
          <div class="stat"><div class="k">Leído de las fotos</div>
            <div class="v" style="${res.lectura.ilegibles ? 'color:' + RESULTADO.ilegible.color : ''}">
              ${esc(pct(res.lectura.pct_leidos))} <span style="${SUB}">${esc(res.lectura.leidos)} de ${esc(res.lectura.campos)} campos</span></div></div>
          <div class="stat"><div class="k">Coincide con lo esperado</div>
            <div class="v" style="${res.lectura.difieren ? 'color:' + RESULTADO.diferencia.color : ''}">
              ${esc(pct(res.lectura.pct_coinciden))} <span style="${SUB}">${esc(res.lectura.coinciden)} de ${esc(res.lectura.comparados)} comparados</span></div></div>
        </div>` : ''}

        <div class="stats" style="grid-template-columns:repeat(5, 1fr)">
          ${Object.entries(RESULTADO).map(([k, r]) => `<div class="stat"><div class="k">${esc(r.txt)}</div>
            <div class="v" style="${res.resumen[k] && k !== 'ok' ? 'color:' + r.color : ''}">${esc(res.resumen[k] || 0)}</div></div>`).join('')}
        </div>

        <div style="font-size:10px;color:#94a3b8;margin:8px 0">
          ${esc(`PL ${(res.pl && res.pl.invoice_ref) || 's/ref'}${res.pl && res.pl.items ? ` · ${res.pl.items} ítems` : ''} · ${res.tipo_envio}`)}
          ${esc(res.ci_resumen ? ` · CI ${res.ci_resumen.invoice_nro || 's/nro'} (comprador ${res.ci_resumen.buyer || '—'}, ${res.ci_resumen.items} ítems)` : ' · sin Commercial Invoice')}
          ${esc(`${res.costo_usd !== undefined ? ` · USD ${Number(res.costo_usd || 0).toFixed(3)}` : ''}${res.duracion_ms ? ` · ${Math.round(res.duracion_ms / 1000)} s` : ''}`)}
        </div>

        ${res.error_guardar ? `<div class="err-box">La corrida NO se pudo guardar en la base: ${esc(res.error_guardar)}</div>` : ''}
        ${res.errores_ocr && res.errores_ocr.length > 0 ? `<div class="err-box">No se pudieron leer algunas fotos: ${esc(res.errores_ocr.join(' · '))}</div>` : ''}
        ${(res.avisos || []).map(a => `<div class="err-box">${esc(a)}</div>`).join('')}

        ${faltan.length > 0 ? `<div style="${IC.st(Object.assign({}, CAJA_AVISO, { background: '#f8fafc', border: '1px solid #e2e8f0' }))}">
          <b>📷 Faltan fotos</b> (no se verificó esa cara; no se usa la foto de otra caja):
          ${faltan.map(([c, caras]) => `<span style="margin-right:10px"><code>${esc(c)}</code>: ${esc(caras.join(', '))}</span>`).join('')}
          ${sinAsig.length > 0 ? `<div style="color:#92400e;margin-top:4px">
            Alguna puede estar entre las ${sinAsig.length} foto(s) sin asignar: asignala y recalculá.</div>` : ''}
        </div>` : ''}

        ${sinAsig.length > 0 ? `<div data-k="cajasSinAsignar" style="${IC.st(Object.assign({}, CAJA_AVISO, { background: '#fffbeb', border: '2px solid #f59e0b' }))}">
          <b>⚠ Fotos sin asignar (${sinAsig.length})</b>: no se pudo saber de qué código son (no tienen el código
          impreso —ej. el lateral de la master— ni en el nombre del archivo) o qué cara muestran, así que <b>no se compararon</b>.
          Mirá lo leído en cada una, elegí el código (y la cara si hace falta) y tocá <b>Recalcular</b>: se re-evalúan contra ese código.
          <div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:6px">
            ${sinAsig.map(l => {
              const a = S.asignar[l.foto] || {};
              const url = upn[l.foto];
              const resumen = resumenLectura(l);
              const setA = (cambio) => { S.asignar = Object.assign({}, S.asignar, { [l.foto]: Object.assign({}, a, cambio) }); render(); };
              return `<div style="width:170px;font-size:10px">
                ${url ? `<img src="${esc(url)}" alt="" onclick="${IC.on(() => IC.lightbox({ src: url, etiqueta: l.foto }))}"
                  style="width:170px;height:100px;object-fit:cover;border-radius:4px;cursor:zoom-in;border:1px solid #e2e8f0">`
                  : '<div style="height:40px;color:#94a3b8">(foto no cargada)</div>'}
                <div style="${NW};overflow:hidden;text-overflow:ellipsis" title="${esc(l.foto)}">${esc(l.foto)}</div>
                <div style="color:#64748b">${esc((l.caras || []).map(c => CARA[c]).join(' + ') || 'no se identificó qué cara es')}</div>
                ${resumen ? `<div style="color:#334155" title="Lo que se leyó en la foto">${esc(resumen)}</div>` : ''}
                <div style="display:flex;gap:4px;margin-top:2px">
                  <select data-k="asc-${esc(l.foto)}" onchange="${IC.on((e) => setA({ codigo: e.target.value }))}" style="font-size:10px;padding:1px">
                    ${IC.opts([['', 'código…'], ...codigosPl.map(c => [c, c])], a.codigo || '')}
                  </select>
                  <select data-k="asf-${esc(l.foto)}" onchange="${IC.on((e) => setA({ cara: e.target.value }))}" style="font-size:10px;padding:1px">
                    ${IC.opts([['', (l.caras || []).length ? 'cara: la detectada' : 'cara…'], ...Object.entries(CARA)], a.cara || '')}
                  </select>
                </div>
              </div>`;
            }).join('')}
          </div>
        </div>` : ''}

        ${codigosPl.length > 0 ? `<div style="${IC.st(Object.assign({}, CAJA_AVISO, { background: '#f8fafc', border: '1px solid #e2e8f0' }))}">
          <b>Partes crudas</b> (no llevan cartón, marca, código de barras ni CUIT). Automático: más de 3 dígitos o con C. Tildá / destildá y recalculá:
          ${codigosPl.map(c => `<label style="margin-right:10px;${NW}">
            <input data-k="crudo-${esc(c)}" type="checkbox" ${esCrudo(c) ? 'checked' : ''} onchange="${IC.on(() => toggleCrudo(c))}" ${!recalc ? 'disabled' : ''}> ${esc(c)}
          </label>`).join('')}
        </div>` : ''}

        <div class="toolbar" style="margin-top:8px">
          <button class="btn btn-secondary" onclick="${IC.on(() => recalcular())}" ${S.recalculando || !pend || !recalc ? 'disabled' : ''}
            title="${!recalc ? 'Corrida anterior a r54: no se puede recalcular' : ''}">
            ${esc(S.recalculando ? 'Recalculando...' : `↻ Recalcular${pend ? ' (hay cambios)' : ''}`)}</button>
          <button class="btn btn-secondary" onclick="${IC.on(() => guardar())}" ${S.guardando || S.recalculando ? 'disabled' : ''}>${S.guardando ? 'Guardando...' : '💾 Guardar'}</button>
          <button class="btn btn-success" onclick="${IC.on(() => descargarPdf())}">⬇ Descargar PDF</button>
          <span style="font-size:10px;color:#94a3b8">Tocá el resultado para ver el motivo y la foto de esa cara. ✎ corrige un valor mal leído. Guardar deja en la base lo corregido y la revisión bien/mal.</span>
        </div>

        <div class="report" data-k="cajasRep" style="overflow-x:auto;max-height:620px">
          <table style="font-size:12px;width:auto">
            <thead><tr>
              <th style="${NW}">Código</th><th style="${NW}">Caja</th><th style="${NW}">Campo</th><th style="${NW}">En la foto</th>
              <th style="${NW}">Esperado / PL</th><th style="${NW}">Resultado</th><th style="${NW}">Foto</th><th style="${NW}">Revisión</th><th style="${NW}">Motivo</th>
            </tr></thead>
            <tbody>
              ${filasHtml}
              ${filas.length === 0 ? '<tr><td colspan="9" style="color:#059669;text-align:center">Sin problemas ✓</td></tr>' : ''}
            </tbody>
          </table>
        </div>
      </div>`;
    }

    function html() {
      const nc = S.nuevoCom;
      return `<div>
        <div class="card">
          <div class="card-header">
            <h3>📐 Cajas vs Packing List</h3>
            <div style="flex:1"></div>
            <button class="btn btn-secondary" style="font-size:11px;padding:3px 10px" onclick="${IC.on(() => abrirLista())}">📂 Corridas guardadas</button>
          </div>
          <div style="font-size:11px;color:#64748b;margin-bottom:10px">
            Subí el packing list, la Commercial Invoice (opcional: nombre del artículo, cantidades y comprador) y <strong>todas las fotos juntas</strong>.
            Cada foto se identifica por lo que tiene impreso: <b>master frente</b> (Para, n/N, MADE IN, PRODUCT CODE, QUANTITY), <b>master lateral</b> (G.W., N.W., MEAS.),
            <b> inner</b> (PRODUCT CODE, INNER QTY), <b>cartón frente</b> (nombre del comercializador) y <b>cartón dorso</b> (CUITs y código de barras).
            El código de barras lo lee primero la PC. Lo ilegible se completa a mano; todo queda guardado.
          </div>

          ${htmlCorridas()}

          <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end">
            <div style="flex:1 1 240px">
              ${IC.dz.html('cajas-pl', { label: 'Packing list (PDF, Excel o foto)', icon: '📄', files: S.plFiles,
                onFiles: (f) => { S.plFiles = f; render(); }, onRemove: (i) => { S.plFiles = S.plFiles.filter((_, x) => x !== i); render(); },
                accept: '.pdf,.xlsx,.xls,.csv,image/*', single: true })}
            </div>
            <div style="flex:1 1 240px">
              ${IC.dz.html('cajas-ci', { label: 'Commercial Invoice (opcional)', icon: '🧾', files: S.ciFiles,
                onFiles: (f) => { S.ciFiles = f; render(); }, onRemove: (i) => { S.ciFiles = S.ciFiles.filter((_, x) => x !== i); render(); },
                accept: '.pdf,.xlsx,.xls,.csv,image/*', single: true })}
            </div>
            <label style="font-size:11px">Tipo de envío<br>
              <select data-k="tipoEnvio" onchange="${IC.on((e) => { S.tipoEnvio = e.target.value; render(); })}" style="padding:4px;font-size:11px">
                ${IC.opts([['LCL', 'LCL (consolidado)'], ['FCL', 'FCL (contenedor)']], S.tipoEnvio)}
              </select>
            </label>
            <label style="font-size:11px">N° carga (opcional)<br>
              <input data-k="nroCarga" value="${esc(S.nroCarga)}" oninput="${IC.on((e) => { S.nroCarga = e.target.value; })}" placeholder="China 52" style="padding:4px;font-size:11px;width:110px">
            </label>
          </div>

          <!-- Importador de la carga -->
          <div style="margin-top:12px;display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end">
            <label style="font-size:11px;font-weight:600;align-self:flex-end;width:96px">Importador</label>
            <label style="font-size:10px;color:#64748b">Guardados<br>
              <select data-k="selImp" onchange="${IC.on((e) => elegirImportador(e.target.value))}" style="padding:4px;font-size:12px;min-width:180px">
                ${IC.opts([['', '— elegir / nuevo —'], ...S.importadores.map(x => [x.id, `${x.razon_social} — ${fmtCuit(x.cuit)}`])], S.selImp)}
              </select>
            </label>
            <label style="font-size:10px;color:#64748b">CUIT<br>${inputCuit('cuitImp', S.cuitImp, (v) => { S.cuitImp = v; render(); }, () => (S.cuitImp = fmtCuit(S.cuitImp)))}</label>
            <label style="font-size:10px;color:#64748b">Razón social (= consignatario)<br>
              <input data-k="razonImp" value="${esc(S.razonImp)}" oninput="${IC.on((e) => { S.razonImp = e.target.value; render(); })}" placeholder="TIERRA NATIVA SA" style="padding:4px;font-size:12px;width:180px">
            </label>
            <button class="btn btn-secondary" style="padding:4px 8px;font-size:11px" onclick="${IC.on(() => guardarImportador())}"
              ${!cuitOk(S.cuitImp) || !S.razonImp.trim() ? 'disabled' : ''} title="Guardar el importador en la lista">💾</button>
          </div>

          <!-- Comercializadores: empresa (CUIT + razón social) con sus cartones (nombres impresos) -->
          <div style="margin-top:8px;display:grid;gap:6px">
            <div style="display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end">
              <label style="font-size:11px;font-weight:600;align-self:flex-end;width:96px">Comercializador</label>
              <label style="font-size:10px;color:#64748b">CUIT<br>
                ${inputCuit('comCuit', nc.cuit, (v) => setComCampo('cuit', v), () => { S.nuevoCom = Object.assign({}, S.nuevoCom, { cuit: fmtCuit(S.nuevoCom.cuit) }); return S.nuevoCom.cuit; })}
              </label>
              <label style="font-size:10px;color:#64748b">Razón social<br>
                <input data-k="comRazon" value="${esc(nc.razon)}" oninput="${IC.on((e) => setComCampo('razon', e.target.value))}" placeholder="LOEKEMEYER SRL" style="padding:4px;font-size:12px;width:180px">
              </label>
              <button class="btn btn-secondary" style="padding:4px 8px;font-size:11px" onclick="${IC.on(() => guardarComercializador())}"
                ${!cuitOk(nc.cuit) || !nc.razon.trim() ? 'disabled' : ''} title="Agregar comercializador">💾</button>
            </div>

            ${htmlComercializadores()}
            <div style="font-size:10px;color:#94a3b8">
              El importador es uno por carga (CUIT y razón social obligatorios): su CUIT va en el dorso del cartón y su razón social
              tiene que ser el consignatario de la master (y el comprador de la CI). El comercializador se identifica por el nombre del
              <b> frente</b> del cartón (ej. "Loke" y "Loekemeyer" → LOEKEMEYER SRL); su CUIT (dorso) tiene que ser el de esa empresa.
            </div>
          </div>

          <div style="margin-top:12px">
            ${IC.dz.html('cajas-fotos', { label: 'Fotos de las cajas (carpeta, .zip, .rar o sueltas)', icon: '🗂️',
              files: [], onFiles: recibirFotos, onRemove: () => {}, accept: 'image/*', limites: LIMITES_FOTOS })}
            <div style="font-size:10px;color:#64748b;margin-top:4px">
              Tirá acá todas las fotos. Qué cara es cada una lo decide lo que tiene impreso. El lateral de la master no trae código:
              conviene que el nombre del archivo lo tenga (ej. "838E (2).jpg"). Click en una foto para verla en grande.
            </div>
            ${htmlFotos()}
          </div>

          <div class="toolbar">
            <button class="btn btn-primary" onclick="${IC.on(() => verificar())}" ${!puedeVerificar() ? 'disabled' : ''}>
              ${esc(S.loading ? (S.progress || 'Verificando...') : '🔍 Verificar cajas')}
            </button>
            ${!S.loading ? `<span style="font-size:10px;color:#94a3b8">${S.fotos.length} foto${S.fotos.length === 1 ? '' : 's'}${!cuitOk(S.cuitImp) ? ' · falta el CUIT del importador' : ''}${!S.razonImp.trim() ? ' · falta la razón social del importador' : ''}</span>` : ''}
          </div>
          ${S.error ? `<div class="err-box">${esc(S.error)}</div>` : ''}
        </div>

        ${htmlResultado()}
      </div>`;
    }

    render();
    cargarEntidades();
  });
})();
