/* IMPO COMEX — Autorización de Importación de Envases (port de AutorizacionMode.jsx).
   Formulario "Autorización de Importación de Envases" del gestor (SENASA).
   Se suben factura, packing list, BL y certificados CE / RNE; el servidor los lee con IA, controla que
   sean de la misma carga y arma los datos en código, solo con esos documentos (sin la base);
   acá se revisan, se corrigen y se descarga el Word completado.
   Planes: .planning/PLAN-2026-09-15-autorizacion-envases.md, PLAN-2026-09-15-autorizacion-solo-documentos.md */
(function () {
  'use strict';
  const IC = window.IC;
  const E = IC.esc;

  const UNIDADES = ['Unidad', 'Kilogramo', 'Gramo', 'Litro', 'Mililitro', 'Metro', 'Centímetro', 'Otro (especificar)'];
  const FUENTE = {
    factura: 'factura', packing_list: 'packing list', bl: 'BL', certificado: 'certificado subido', rne: 'RNE subido',
    pd: 'PDF devuelto', manual: 'cargado a mano',
  };
  // "2026-10-20" (input de fecha) -> "20/10/2026" (formulario)
  const fechaForm = (iso) => (/^\d{4}-\d{2}-\d{2}$/.test(iso) ? iso.split('-').reverse().join('/') : iso);
  const soloDig = (v) => String(v || '').replace(/\D/g, '');
  const RESULTADO = {
    critica: { texto: '✗ no coincide', color: '#b91c1c' },
    importante: { texto: '⚠ revisar', color: '#b45309' },
    ok: { texto: '✓ coincide', color: '#059669' },
    sin_datos: { texto: '— sin datos', color: '#94a3b8' },
  };
  const SECCIONES = [
    ['importador', 'Datos del Importador', [['razon_social', 'Nombre o Razón Social'], ['cuit', 'CUIT del importador'], ['rne', 'RNE (obligatorio)']]],
    ['deposito', 'Datos del Depósito', [['provincia', 'Provincia'], ['departamento', 'Departamento'], ['localidad', 'Localidad'],
      ['domicilio', 'Domicilio'], ['piso_dpto', 'Piso / Dpto.'], ['factura', 'Factura n°']]],
    ['transporte', 'Datos del Transporte', [['fecha_arribo', 'Fecha de arribo (dd/mm/aaaa)'],
      ['bl_numero', 'BL / Guía aérea / CRT N° (sin guiones)'], ['pais_procedencia', 'País de procedencia']]],
  ];
  const CAMPOS_PRODUCTO = [
    ['certificado', 'Certificado de Autorización de Envases'], ['pais_origen', 'País de origen'],
    ['elaborador', 'Nombre o Razón social del Elaborador'], ['denominacion', 'Denominación'],
    ['marca_codigo', 'Marca / código comercial'], ['lote', 'Lote (solo si posee)'], ['cantidad', 'Cantidad de unidades'],
    ['unidad', 'Unidad de medida'], ['peso_bruto', 'Peso Bruto (Kg, dos decimales máximo)'],
  ];
  // Vacíos que no hace falta avisar antes de descargar.
  const OPCIONALES = new Set(['piso_dpto', 'lote', 'departamento']);
  const NW = 'white-space:nowrap';
  const valores = (grupo) => Object.fromEntries(Object.entries(grupo).map(([k, c]) => [k, c.valor]));
  const ZONAS = ['aut-formenv', 'aut-pd', 'aut-factura', 'aut-pl', 'aut-bl', 'aut-certs', 'aut-form'];

  // Campo (Campo de React): input / select / textarea + la leyenda de fuente.
  function campoHtml(dk, campo, onChange, { lista, opcional, largo } = {}) {
    const falta = !opcional && !String(campo.valor).trim();
    const estilo = `font-size:12px;padding:3px 5px;width:100%;box-sizing:border-box;background:${falta ? '#fffbeb' : '#fff'};border:1px solid ${falta ? '#f59e0b' : '#cbd5e1'};border-radius:4px`;
    const df = falta ? ' data-falta="1"' : '';
    const h = IC.on((ev) => onChange(ev.target.value));
    let ctl;
    if (lista) {
      ctl = `<select data-k="${dk}" onchange="${h}" style="${estilo}"${df}>
        ${!campo.valor ? '<option value="">—</option>' : ''}
        ${lista.map(u => `<option value="${E(u)}"${String(campo.valor) === u ? ' selected' : ''}>${E(u)}</option>`).join('')}</select>`;
    } else if (largo) {
      ctl = `<textarea data-k="${dk}" oninput="${h}" rows="2"${df} style="${estilo};resize:vertical;font-family:inherit">${E(campo.valor)}</textarea>`;
    } else {
      ctl = `<input data-k="${dk}" value="${E(campo.valor)}" oninput="${h}" style="${estilo}"${df}>`;
    }
    return `${ctl}<span style="${NW};font-size:10px;color:${falta ? '#b45309' : '#94a3b8'}">${E(falta ? 'completar' : !String(campo.valor).trim() ? 'opcional' : (FUENTE[campo.fuente] || 'editado'))}</span>`;
  }

  function tablaControles(cc) {
    return `<table style="font-size:11px;width:auto">
      <thead><tr><th style="${NW}">Control</th><th style="${NW}">Resultado</th><th>Detalle</th></tr></thead>
      <tbody>${cc.map(c => `<tr>
        <td style="${NW}">${E(c.control)}</td>
        <td style="${NW};${RESULTADO[c.resultado] ? `color:${RESULTADO[c.resultado].color};` : ''}font-weight:${c.resultado === 'critica' ? 700 : 400}">${E((RESULTADO[c.resultado] && RESULTADO[c.resultado].texto) || c.resultado)}</td>
        <td style="max-width:560px;${c.resultado === 'sin_datos' ? 'color:#94a3b8' : ''}">${E(c.detalle)}</td>
      </tr>`).join('')}</tbody></table>`;
  }

  IC.modo('autorizacion', async function (el) {
    const miVista = IC.vistaActual();
    const inst = {}; el.__icInst = inst;
    const vivo = () => el.isConnected && el.__icInst === inst && IC.vistaActual() === miVista;
    ZONAS.forEach(z => IC.dz.olvidar(z));   // pantalla nueva = zonas nuevas (como al montar en React)

    const S = {
      factura: [], pl: [], bl: [], certs: [],
      pd: [],              // PDF devuelto por SENASA (opcional), para contrastar
      formulario: [],
      loading: false, progress: '', error: null, res: null, datos: null, avisosWord: [], descargado: null,
      fechaArribo: '',     // AAAA-MM-DD: no viene en los documentos
      rneManual: '',       // RNE del importador a mano (opcional), si no se sube el RNE
      modo: 'crear',       // 'crear' | 'archivos_pd' | 'form_pd'
      formEnviado: [],     // PDF del formulario enviado a SENASA (modo form_pd)
      empresasRne: [],     // {razon_social, rne} guardadas (RNE único por empresa)
      razonRne: '',        // razón social para guardar/elegir el RNE por empresa
    };
    function render() { if (vivo()) IC.pintar(el, html()); }

    const recargarEmpresas = () => IC.api.postJson('/autorizacion-envases', { accion: 'rne_listar' })
      .then(r => { S.empresasRne = r.empresas || []; render(); }).catch(() => {});
    const elegirEmpresa = (rne) => { const em = S.empresasRne.find(x => x.rne === rne); if (em) { S.razonRne = em.razon_social; S.rneManual = em.rne; } };
    const guardarRne = async () => {
      if (!S.razonRne.trim() || !soloDig(S.rneManual)) { IC.avisar('Completá la razón social y el RNE (solo números) para guardarlo.'); return; }
      try {
        await IC.api.postJson('/autorizacion-envases', { accion: 'rne_guardar', razon_social: S.razonRne.trim(), rne: soloDig(S.rneManual) });
        await recargarEmpresas();
        IC.avisar('RNE guardado para ' + S.razonRne.trim() + '.');
      } catch (e) { IC.avisar('No se pudo guardar: ' + (e.message || e)); }
    };

    const cambiarModo = (m) => {
      // Entrar o salir de "Formulario Vs PDF" rearma las zonas (en React eran otro árbol).
      if ((m === 'form_pd') !== (S.modo === 'form_pd')) ZONAS.forEach(z => IC.dz.olvidar(z));
      S.modo = m; S.error = null; S.res = null; S.datos = null; S.avisosWord = []; S.descargado = null; render();
    };

    const leer = async () => {
      S.error = null; S.res = null; S.datos = null; S.avisosWord = []; S.descargado = null;
      S.loading = true; render();
      try {
        const [{ extractText }, { numeroRne }] = await Promise.all([IC.mod('pdfText'), IC.mod('docxAutorizacion')]);
        const fd = new FormData();
        fd.append('accion', 'leer');
        fd.append('carga_ref', new Date().toISOString().replace(/[-:.]/g, '') + '_' + crypto.randomUUID().slice(0, 8));
        if (S.fechaArribo) fd.append('fecha_arribo', S.fechaArribo);
        if (S.rneManual.trim()) fd.append('rne_manual', S.rneManual.trim());
        const grupos = [['factura', S.factura], ['pl', S.pl], ['bl', S.bl], ['cert', S.certs]];
        const total = grupos.reduce((s, [, fs]) => s + fs.length, 0);
        let n = 0;
        for (const [prefijo, fs] of grupos) {
          for (let i = 0; i < fs.length; i++) {
            S.progress = `Preparando documentos ${++n}/${total}...`; render();
            fd.append(`${prefijo}_${i}`, fs[i], fs[i].name);
            const texto = await extractText(fs[i], { campos: true });
            if (texto) fd.append(`texto_${prefijo}_${i}`, texto);
          }
        }
        if (S.pd[0]) {
          fd.append('pd_0', S.pd[0], S.pd[0].name);
          const tpd = await extractText(S.pd[0], { campos: true });
          if (tpd) fd.append('texto_pd_0', tpd);
        }
        S.progress = 'Leyendo documentos con IA...'; render();
        const r = await IC.api.postForm('/autorizacion-envases', fd);
        S.res = r;
        const aut = r.autorizacion;
        // Por si el servidor todavía no toma la fecha cargada: se pone igual en el formulario.
        if (S.fechaArribo && aut.transporte.fecha_arribo?.fuente !== 'manual') {
          aut.transporte = { ...aut.transporte, fecha_arribo: { valor: fechaForm(S.fechaArribo), fuente: 'manual' } };
        }
        // El formulario ya dice "RNE:": solo el número (el servidor viejo lo manda con "RNE" delante).
        if (aut.importador?.rne?.valor) aut.importador = { ...aut.importador, rne: { ...aut.importador.rne, valor: numeroRne(aut.importador.rne.valor) } };
        S.datos = aut;
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false; S.progress = ''; render();
      }
    };

    // Modo "Formulario Vs PDF SENASA": el PDF que se envió a SENASA vs el PDF devuelto (dos PDFs, sin IA).
    const verificarFormPd = async () => {
      S.error = null; S.res = null; S.datos = null;
      S.loading = true; render();
      try {
        const { extractText } = await IC.mod('pdfText');
        S.progress = 'Leyendo los PDF...'; render();
        const textoForm = await extractText(S.formEnviado[0], { campos: true });
        const textoPd = await extractText(S.pd[0], { campos: true });
        if (!textoForm || !textoPd) throw new Error('No se pudo leer el texto de alguno de los PDF (¿es un escaneo sin texto?).');
        S.progress = 'Comparando...'; render();
        const r = await IC.api.postJson('/autorizacion-envases', { accion: 'contrastar_form_pd', texto_form: textoForm, texto_pd: textoPd });
        S.res = r;
      } catch (e) {
        S.error = e.message || String(e);
      } finally {
        S.loading = false; S.progress = ''; render();
      }
    };

    const cambiar = (grupo, clave, valor) => {
      const d = S.datos;
      S.datos = { ...d, [grupo]: { ...d[grupo], [clave]: { ...d[grupo][clave], valor } } }; render();
    };
    const cambiarProducto = (i, clave, valor) => {
      const d = S.datos;
      S.datos = { ...d, productos: d.productos.map((p, k) => (k === i ? { ...p, [clave]: { ...p[clave], valor } } : p)) }; render();
    };
    const quitarProducto = (i) => { const d = S.datos; S.datos = { ...d, productos: d.productos.filter((_, k) => k !== i) }; render(); };

    const vaciosDe = (datos) => datos ? [
      ...SECCIONES.flatMap(([g, , campos]) => campos.filter(([k]) => !OPCIONALES.has(k) && !String(datos[g][k].valor).trim()).map(([, l]) => l)),
      ...datos.productos.flatMap((p, i) => CAMPOS_PRODUCTO.filter(([k]) => !OPCIONALES.has(k) && !String(p[k].valor).trim())
        .map(([, l]) => `${l} (certificado ${i + 1})`)),
    ] : [];

    // Al cancelar para completar a mano: cursor en el primer campo que falta.
    const irAlPrimerVacio = () => {
      const c = el.querySelector('[data-falta="1"]');
      if (!c) return;
      c.scrollIntoView({ block: 'center', behavior: 'smooth' });
      c.focus({ preventScroll: true });
    };

    const descargar = async () => {
      const datos = S.datos;
      const vacios = vaciosDe(datos);
      const criticas = (datos?.controles || []).filter(c => c.resultado === 'critica');
      const igual = { aceptar: 'Descargar igual', cancelar: 'Volver' };
      if (criticas.length && !(await IC.confirmar(`Los documentos no parecen de la misma carga:\n\n- ${criticas.map(c => `${c.control}: ${c.detalle}`).join('\n- ')}\n\n¿Descargar igual?`, igual))) return;
      if (!datos.productos.length && !(await IC.confirmar('No hay ningún certificado para el formulario. ¿Descargar igual?', igual))) return;
      if (vacios.length && !(await IC.confirmar(`Quedan ${vacios.length} campo(s) vacío(s):\n\n- ${vacios.join('\n- ')}\n\n¿Descargar igual?`,
        { aceptar: 'Descargar igual', cancelar: 'Completar' }))) { irAlPrimerVacio(); return; }
      S.error = null; render();
      try {
        const { llenarAutorizacion } = await IC.mod('docxAutorizacion');
        const plantilla = S.formulario[0]
          ? await S.formulario[0].arrayBuffer()
          : await (await fetch(IC.url('plantillas/autorizacion-envases.docx'))).arrayBuffer();
        const { bytes, avisos } = llenarAutorizacion(plantilla, {
          importador: valores(datos.importador),
          deposito: valores(datos.deposito),
          transporte: valores(datos.transporte),
          productos: datos.productos.map(p => valores(Object.fromEntries(CAMPOS_PRODUCTO.map(([k]) => [k, p[k]])))),
        });
        S.avisosWord = avisos;

        const nombre = `Autorizacion importacion envases - Factura ${String(datos.deposito.factura.valor || 's-n').replace(/[\\/:*?"<>|]/g, '-')}.docx`;
        const url = URL.createObjectURL(new Blob([bytes], { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }));
        const a = document.createElement('a');
        a.href = url; a.download = nombre;
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 60_000);
        S.descargado = nombre;
      } catch (e) {
        S.error = e.message || String(e);
      }
      render();
    };

    const GRILLA = 'display:grid;grid-template-columns:max-content minmax(200px, 560px) max-content;gap:4px 8px;align-items:center';
    const ETIQ = 'font-size:11px;color:#475569;white-space:nowrap';
    const TXT = 'font-size:10px;color:#94a3b8;margin-top:3px';

    const dzSuma = (id, label, icon, clave, accept) => IC.dz.html(id, Object.assign({ label, icon, files: S[clave],
      onFiles: fs => { S[clave] = [...S[clave], ...fs]; render(); },
      onRemove: i => { S[clave] = S[clave].filter((_, x) => x !== i); render(); } }, accept ? { accept } : {}));
    const dzUno = (id, label, icon, clave, accept) => IC.dz.html(id, { label, icon, files: S[clave], single: true, accept,
      onFiles: fs => { S[clave] = fs; render(); },
      onRemove: () => { S[clave] = []; render(); } });

    function html() {
      const { modo, loading, progress, res, datos } = S;
      const controles = datos?.controles || [];
      const criticas = controles.filter(c => c.resultado === 'critica');
      const vacios = vaciosDe(datos);

      let contraste = '';
      if (res?.contraste) {
        const cc = res.contraste.controles || [];
        const crit = cc.filter(c => c.resultado === 'critica');
        const imp = cc.filter(c => c.resultado === 'importante');
        contraste = `<div class="card">
          <div class="card-header"><h3>${modo === 'form_pd' ? 'Formulario enviado Vs PDF devuelto' : 'Archivos Vs PDF devuelto'}</h3></div>
          <div style="font-size:12px;font-weight:700;margin:6px 0;color:${crit.length ? '#b91c1c' : imp.length ? '#b45309' : '#059669'}">
            ${E(crit.length ? `✗ No coincide (${crit.length} grave${crit.length > 1 ? 's' : ''})` : imp.length ? 'Hay datos para revisar' : '✓ Todo coincide')}
            ${res.contraste.numero ? `<span style="font-weight:400;color:#64748b"> · ${E(res.contraste.numero)}</span>` : ''}
          </div>
          <div class="report" data-k="aut-contraste" style="overflow-x:auto">${tablaControles(res.contraste.controles || [])}</div>
        </div>`;
      }

      let formulario = '';
      if (datos) {
        const hayImp = controles.some(c => c.resultado === 'importante');
        const avisos = datos.avisos || [];
        const errores = res.errores || [];
        formulario = `<div class="card">
          <div class="card-header">
            <h3>Formulario</h3>
            <div style="flex:1"></div>
            <span style="font-size:10px;color:#94a3b8">USD ${Number(res.costo_usd || 0).toFixed(3)} · ${Math.round(res.duracion_ms / 1000)} s</span>
          </div>
          ${controles.length > 0 ? `<div style="margin-bottom:12px">
            <div style="font-size:12px;font-weight:700;margin:6px 0;color:${criticas.length ? '#b91c1c' : hayImp ? '#b45309' : '#059669'}">
              ${E(criticas.length
                ? `✗ Los documentos no parecen de la misma carga (${criticas.length} control${criticas.length > 1 ? 'es' : ''})`
                : hayImp ? 'Controles de misma carga: hay datos para revisar'
                  : `✓ Controles de misma carga: ${controles.filter(c => c.resultado === 'ok').length} coinciden`)}
            </div>
            <div class="report" data-k="aut-controles" style="overflow-x:auto">${tablaControles(controles)}</div>
          </div>` : ''}

          ${(avisos.length > 0 || errores.length > 0) ? `<div class="alerts" style="margin-bottom:10px">
            ${errores.map(e => `<div class="alert critica">No se pudo leer: ${E(e)}</div>`).join('')}
            ${avisos.map(a => `<div class="alert importante">${E(a)}</div>`).join('')}
          </div>` : ''}

          ${SECCIONES.map(([grupo, titulo, campos]) => `<div style="margin-bottom:12px">
            <div style="font-size:12px;font-weight:700;margin:6px 0">${E(titulo)}</div>
            <div style="${GRILLA}">
              ${campos.map(([k, l]) => `<label style="${ETIQ}">${E(l)}</label>${campoHtml(`aut-${grupo}-${k}`, datos[grupo][k], v => cambiar(grupo, k, v), { opcional: OPCIONALES.has(k) })}`).join('')}
            </div></div>`).join('')}

          ${datos.productos.map((p, i) => `<div style="border:1px solid #e2e8f0;border-radius:6px;padding:10px;margin-bottom:10px">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;flex-wrap:wrap">
              <strong style="font-size:12px">Datos de Producto y Lote · certificado ${i + 1} de ${datos.productos.length}</strong>
              <span style="font-size:10px;color:#64748b">códigos de la factura: ${(p.codigos || []).map(c => `<code style="margin-right:3px">${E(c)}</code>`).join('')}</span>
              <div style="flex:1"></div>
              <button class="btn btn-secondary" style="padding:1px 8px;font-size:10px" onclick="${IC.on(() => quitarProducto(i))}"
                title="No incluir este certificado en el formulario">Quitar</button>
            </div>
            <div style="${GRILLA}">
              ${CAMPOS_PRODUCTO.map(([k, l]) => `<label style="${ETIQ}">${E(l)}</label>${campoHtml(`aut-p${i}-${k}`, p[k], v => cambiarProducto(i, k, v),
                { lista: k === 'unidad' ? UNIDADES : null, opcional: OPCIONALES.has(k), largo: k === 'denominacion' })}`).join('')}
            </div></div>`).join('')}

          ${datos.sin_certificado.length > 0 ? `<div style="margin-bottom:10px">
            <div style="font-size:12px;font-weight:700;margin:6px 0">
              Códigos de la factura sin certificado de envases (${datos.sin_certificado.length}) — no van en el formulario
            </div>
            <div class="report" data-k="aut-sincert" style="overflow-x:auto;max-height:260px;margin-top:4px">
              <table style="font-size:11px;width:auto">
                <thead><tr><th style="${NW}">Código</th><th style="${NW}">Descripción</th><th style="${NW};text-align:right">Cantidad</th><th style="${NW}">Pista</th></tr></thead>
                <tbody>${datos.sin_certificado.map(s => `<tr>
                  <td style="${NW}"><code>${E(s.codigo)}</code></td>
                  <td style="max-width:320px">${E(s.descripcion || '—')}</td>
                  <td style="${NW};text-align:right">${E(s.cantidad ?? '—')}</td>
                  <td style="max-width:320px;color:${s.pista ? '#b45309' : '#94a3b8'}">${E(s.pista || '—')}</td>
                </tr>`).join('')}</tbody>
              </table>
            </div></div>` : ''}

          <div class="toolbar">
            <button class="btn btn-success" onclick="${IC.on(descargar)}">⬇ Descargar Word completado</button>
            <span style="font-size:10px;color:${vacios.length ? '#b45309' : '#059669'}">
              ${E(vacios.length ? `${vacios.length} campo(s) para completar` : 'Todos los campos completos')}</span>
          </div>
          ${S.descargado ? `<div style="font-size:11px;color:#059669;margin-top:6px">Descargado: ${E(S.descargado)}</div>` : ''}
          ${S.avisosWord.length > 0 ? `<div class="alerts">${S.avisosWord.map(a => `<div class="alert importante">${E(a)}</div>`).join('')}</div>` : ''}
          <div style="font-size:10px;color:#94a3b8;margin-top:8px">
            El formulario tiene carácter de declaración jurada: revisá cada dato antes de enviarlo al gestor.
          </div>
        </div>`;
      }

      const zonas = modo === 'form_pd' ? `
        <div style="display:grid;grid-template-columns:repeat(auto-fill, minmax(260px, 1fr));gap:10px">
          <div>
            ${dzUno('aut-formenv', 'Formulario enviado a SENASA (PDF)', '📄', 'formEnviado', 'application/pdf')}
            <div style="${TXT}">El PDF del formulario que se presentó a SENASA.</div>
          </div>
          <div>
            ${dzUno('aut-pd', 'PDF devuelto por SENASA', '✅', 'pd', 'application/pdf')}
            <div style="${TXT}">La Autorización de Libre Circulación (PD-…-APN-DNIYCA#SENASA).</div>
          </div>
        </div>` : `
        <div style="display:grid;grid-template-columns:repeat(auto-fill, minmax(260px, 1fr));gap:10px">
          ${dzSuma('aut-factura', 'Factura (obligatoria)', '🧾', 'factura')}
          ${dzSuma('aut-pl', 'Packing list', '📦', 'pl')}
          ${dzSuma('aut-bl', 'BL / Guía aérea / CRT', '🚢', 'bl', 'application/pdf,image/*')}
          <div>
            <label for="aut-fecha-arribo" style="display:block;font-size:12px;font-weight:600;color:#334155;margin-bottom:4px">
              📅 Fecha de arribo de la mercadería
            </label>
            <input id="aut-fecha-arribo" data-k="aut-fecha-arribo" type="date" value="${E(S.fechaArribo)}" oninput="${IC.on((ev) => { S.fechaArribo = ev.target.value; render(); })}"
              style="font-size:13px;padding:5px 8px;border:1px solid ${S.fechaArribo ? '#cbd5e1' : '#f59e0b'};border-radius:6px;background:${S.fechaArribo ? '#fff' : '#fffbeb'}">
            <div style="${TXT}">
              No viene en los documentos: cargala acá. Se usa también para ver si algún certificado vence antes del arribo.
            </div>
          </div>
          <div>
            <label style="display:block;font-size:12px;font-weight:600;color:#334155;margin-bottom:4px">
              🛡️ RNE del importador (opcional)
            </label>
            <select data-k="aut-empresa" onchange="${IC.on((ev) => { if (ev.target.value) elegirEmpresa(ev.target.value); render(); })}"
              style="font-size:12px;padding:5px 6px;border:1px solid #cbd5e1;border-radius:6px;width:100%;max-width:300px;margin-bottom:4px" title="Empresas guardadas">
              <option value="" selected>${S.empresasRne.length ? '— elegir empresa guardada —' : '— no hay empresas guardadas —'}</option>
              ${S.empresasRne.map(em => `<option value="${E(em.rne)}">${E(em.razon_social)} — ${E(em.rne)}</option>`).join('')}
            </select>
            <div style="display:flex;gap:6px;flex-wrap:wrap;align-items:center">
              <input data-k="aut-razon" value="${E(S.razonRne)}" oninput="${IC.on((ev) => { S.razonRne = ev.target.value; render(); })}" placeholder="Razón social (para guardar)"
                style="font-size:12px;padding:5px 8px;border:1px solid #cbd5e1;border-radius:6px;width:180px">
              <input id="aut-rne" data-k="aut-rne" value="${E(S.rneManual)}" oninput="${IC.on((ev) => { S.rneManual = ev.target.value; render(); })}" placeholder="00306900"
                style="font-size:13px;padding:5px 8px;border:1px solid #cbd5e1;border-radius:6px;width:120px">
              <button type="button" class="btn btn-secondary" style="padding:4px 8px;font-size:11px" onclick="${IC.on(guardarRne)}"
                ${!S.razonRne.trim() || !soloDig(S.rneManual) ? 'disabled' : ''} title="Guardar el RNE de esta empresa">💾</button>
            </div>
            <div style="${TXT}">
              Elegí una empresa guardada (autocompleta el RNE), o cargá razón social + RNE y guardá (💾). El RNE va al formulario y se verifica (único por empresa) contra la base y el PDF devuelto.
            </div>
          </div>
          ${dzSuma('aut-certs', 'Certificados CE / RNE (con su anexo IF)', '🛡️', 'certs', 'application/pdf,image/*')}
          ${modo === 'archivos_pd' ? `<div>
              ${dzUno('aut-pd', 'PDF devuelto por SENASA', '✅', 'pd', 'application/pdf')}
              <div style="${TXT}">La Autorización de Libre Circulación (PD-…-APN-DNIYCA#SENASA).</div>
            </div>` : ''}
          <div>
            ${dzUno('aut-form', 'Formulario (.docx)', '📄', 'formulario', '.docx')}
            ${!S.formulario.length ? `<div style="${TXT}">Si no subís uno, se usa el incluido (versión del 27/08/2026).</div>` : ''}
          </div>
        </div>`;

      return `<div>
        <div class="card">
          <div class="card-header"><h3>📝 Autorización de Importación de Envases</h3></div>
          <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px">
            ${[['crear', '📝 Crear formulario'], ['form_pd', '📄 Formulario Vs PDF SENASA'], ['archivos_pd', '🗂️ Archivos Vs PDF SENASA']].map(([m, t]) =>
              `<button onclick="${IC.on(() => cambiarModo(m))}" class="btn ${modo === m ? 'btn-primary' : 'btn-secondary'}" style="font-size:12px;padding:5px 10px">${E(t)}</button>`).join('')}
          </div>
          <div style="font-size:11px;color:#64748b;margin-bottom:10px">
            ${modo === 'crear' ? 'Armá el formulario del gestor (SENASA) con la <strong>factura</strong> y, si los tenés, el <strong>packing list</strong> (peso bruto), el <strong>BL</strong> (número) y los <strong>certificados CE / RNE</strong>. Todo sale de estos documentos (no de la base) y se controla que sean de la misma carga; lo que falta queda vacío para completar.' : ''}
            ${modo === 'form_pd' ? 'Compará el <strong>PDF que se envió a SENASA</strong> contra el <strong>PDF que devolvió SENASA</strong>, campo por campo (sin IA). No arma el formulario.' : ''}
            ${modo === 'archivos_pd' ? 'Compará los <strong>documentos de la carga</strong> (factura, PL, BL, certificados CE / RNE) contra el <strong>PDF devuelto por SENASA</strong>.' : ''}
          </div>
          ${zonas}
          <div class="toolbar">
            ${modo === 'form_pd'
              ? `<button class="btn btn-primary" onclick="${IC.on(verificarFormPd)}" ${loading || !S.formEnviado.length || !S.pd.length ? 'disabled' : ''}>
                  ${E(loading ? (progress || 'Comparando...') : '🔍 Comparar formulario vs PDF devuelto')}</button>`
              : `<button class="btn btn-primary" onclick="${IC.on(leer)}" ${loading || !S.factura.length ? 'disabled' : ''}>
                  ${E(loading ? (progress || 'Leyendo...') : (modo === 'archivos_pd' ? '🔍 Verificar archivos vs PDF devuelto' : '🔍 Leer documentos y armar formulario'))}</button>`}
            ${!loading && modo !== 'form_pd' ? '<span style="font-size:10px;color:#94a3b8">~30 seg · ~USD 0,20</span>' : ''}
          </div>
          ${S.error ? `<div class="err-box">${E(S.error)}</div>` : ''}
        </div>
        ${contraste}
        ${formulario}
      </div>`;
    }

    render();
    recargarEmpresas();
  });
})();
