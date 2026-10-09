// Verificacion de la DDJJ 20320 (Banco Credicoop) contra el caso de pago y la CI.
//
// Todo client-side, gratis. Lo que el texto del PDF NO permite saber (tildes de
// checkbox, firmas) se devuelve como checklist manual — no se inventa.
//
// Ver docs/DDJJ-20320-Banco.md

import {
  FORM_ID, FORM_FECHA, FORM_PAGINAS, ANCLAS, CASOS,
  EMPRESAS_DDJJ, CONTROLANTE, OPCION_4B, checklistManual,
} from './ddjjTemplate.js';

// ---------------------------------------------------------------- normalizacion

const ACCENTS = { á:'a', à:'a', ä:'a', â:'a', ã:'a', é:'e', è:'e', ë:'e', ê:'e', í:'i', ì:'i', ï:'i', î:'i', ó:'o', ò:'o', ö:'o', ô:'o', õ:'o', ú:'u', ù:'u', ü:'u', û:'u', ñ:'n', ç:'c' };

/** Normalizacion suave: minusculas, sin acentos, espacios colapsados. Conserva digitos y puntuacion. */
export function soft(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[áàäâãéèëêíìïîóòöôõúùüûñç]/g, c => ACCENTS[c])
    .replace(/\s+/g, ' ')
    .trim();
}

// Confusiones tipicas del OCR de estos escaneos: 6->o, l/1->i, 5/$->s, 3->e, etc.
// Se aplica a AMBOS lados de la comparacion, asi que las referencias normativas
// (7030, 10.10.2.2) siguen siendo distinguibles entre si.
const SKEL = {
  '0':'o', '6':'o', 'º':'o', '°':'o',
  '1':'i', 'l':'i', '|':'i', '!':'i',
  '5':'s', '$':'s', '§':'s',
  '3':'e', '4':'a', '@':'a', '9':'g', '8':'b', '7':'t', '2':'z',
};

/** Esqueleto para comparar prosa escaneada: solo letras, con confusiones OCR unificadas. */
export function skel(s) {
  const base = soft(s).replace(/[^a-z0-9]/g, '');
  let out = '';
  for (const ch of base) out += (SKEL[ch] || ch);
  return out;
}

function trigrams(s) {
  const set = new Set();
  for (let i = 0; i + 3 <= s.length; i++) set.add(s.slice(i, i + 3));
  return set;
}

/**
 * Cuanto de `frase` esta contenido en `texto` (0..1). Robusto a ruido de OCR.
 * Frases de menos de 4 caracteres utiles no tienen trigramas -> substring exacto.
 */
export function containment(frase, texto) {
  const sa = skel(frase), sb = skel(texto);
  if (sa.length < 4) return sa && sb.includes(sa) ? 1 : 0;
  const a = trigrams(sa), b = trigrams(sb);
  let hit = 0;
  for (const t of a) if (b.has(t)) hit++;
  return hit / a.size;
}

// ---------------------------------------------------------------- paginado

const SEP = /\n\s*---\s*PAGINA\s*---\s*\n/i;

/** Parte el texto de pdfText.js (o de un dump propio) en paginas. */
export function splitPaginas(texto) {
  const t = String(texto || '');
  if (SEP.test(t)) return t.split(SEP);
  const alt = t.split(/^=+\s*PAGE\s+\d+\s*=+$/mi);
  return alt.length > 1 ? alt.slice(1) : [t];
}

// ---------------------------------------------------------------- de-OCR de digitos

const DEOCR_DIG = { o:'0', O:'0', Q:'0', i:'1', I:'1', l:'1', L:'1', s:'5', S:'5', b:'6', B:'8', g:'9', G:'6', z:'2', Z:'2', t:'7', T:'7', e:'3', A:'4' };
const digitize = s => String(s).replace(/[a-zA-Z]/g, c => DEOCR_DIG[c] ?? c);

const num = s => {
  if (s == null) return null;
  // "14.000,50" (es) o "14,000.50" (en) o "14000"
  let t = String(s).replace(/\s/g, '');
  if (/,\d{2}$/.test(t) && /\./.test(t)) t = t.replace(/\./g, '').replace(',', '.');
  else t = t.replace(/,/g, '');
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
};

const fmtUsd = n => n == null ? '—' : 'USD ' + n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// ---------------------------------------------------------------- extraccion DDJJ

const RX_FECHA = /(\d{1,2}\s*\/\s*\d{1,2}\s*\/\s*\d{2,4})/;
const cleanFecha = f => String(f).replace(/\s/g, '');

/** Normaliza dd/mm/aa o dd/mm/aaaa -> dd/mm/aaaa */
function fechaLarga(f) {
  if (!f) return null;
  const p = cleanFecha(f).split('/');
  if (p.length !== 3) return null;
  let [d, m, y] = p;
  if (y.length === 2) y = (Number(y) > 70 ? '19' : '20') + y;
  return `${d.padStart(2, '0')}/${m.padStart(2, '0')}/${y}`;
}

export function extraerDdjj(paginas) {
  const p1 = soft(paginas[0] || '');
  const p2 = soft(paginas[1] || '');
  const p5 = soft(paginas[4] || '');
  const todo = soft(paginas.join('\n'));

  // --- Lugar + fecha del encabezado
  let lugar = null, fechaEncabezado = null;
  const mLug = p1.match(/i?ugar\s*[:;.]?\s*(.{1,40}?)\s+[fr]e?cha\s*[:;.]?\s*(\d{1,2}\s*\/\s*\d{1,2}\s*\/\s*\d{2,4})/);
  if (mLug) { lugar = mLug[1].trim(); fechaEncabezado = fechaLarga(mLug[2]); }

  // --- Fecha del parrafo B.C.L. ("solicitud de transferencia al exterior de fecha ...")
  let fechaSolicitud = null;
  const mSol = p1.match(/de\s+[fr]e?cha\s+(\d{1,2}\s*\/\s*\d{1,2}\s*\/\s*\d{2,4})\s+por\s+el/);
  if (mSol) fechaSolicitud = fechaLarga(mSol[1]);
  if (!fechaSolicitud) {
    const all = [...p1.matchAll(new RegExp(RX_FECHA.source, 'g'))].map(m => fechaLarga(m[1]));
    if (all.length > 1) fechaSolicitud = all[1];
  }

  // --- Importe del encabezado ("por el importe de usd 14000")
  let importe = null, importeRaw = null, monedaAclarada = false;
  const mImp = p1.match(/[il1]mp[o06]rte\s+de\s*[:\s]*(u\s*\.?\s*[s5$]\s*\.?\s*d|usd|u\$s|d[o06]iares?)\s*\.?\s*([\d][\d.,]*)/);
  if (mImp) { monedaAclarada = true; importeRaw = mImp[2]; importe = num(mImp[2]); }
  if (importe == null) {
    const m2 = p1.match(/\b(usd|u\$s|u\.?s\.?d)\s*\.?\s*([\d][\d.,]*)/);
    if (m2) { monedaAclarada = true; importeRaw = m2[2]; importe = num(m2[2]); }
  }
  if (importe == null) {
    const m3 = p1.match(/[il1]mp[o06]rte\s+de\s*[:\s]*([\d][\d.,]*)/);
    if (m3) { monedaAclarada = false; importeRaw = m3[1]; importe = num(m3[1]); }
  }

  // --- Cuadro de posiciones arancelarias (pagina 2)
  const posiciones = [];
  const RX_NCM = /([0-9oOsSiIlLbBgGzZtTeE]{4})\s*[.\-,]\s*([0-9oOsSiIlL]{2})\s*[.\-,]\s*([0-9oOsSiIlL]{2})\s*[.\-,]\s*([0-9oOsSiIlL]{3})\s*([a-z])?\s+(usd|u\$s|u\.?s\.?d|d[o06]iares?)\s+([\d][\d.,]*)/gi;
  let m;
  while ((m = RX_NCM.exec(p2))) {
    const ncm = `${digitize(m[1])}.${digitize(m[2])}.${digitize(m[3])}.${digitize(m[4])}${(m[5] || '').toUpperCase()}`;
    posiciones.push({ ncm, moneda: 'USD', monto: num(m[7]), montoRaw: m[7] });
  }

  // --- Cuadro 4.A pagina 5: controlante
  const cuitDigits = CONTROLANTE.cuit.replace(/\D/g, '');
  const p5digits = p5.replace(/\D/g, '');
  const controlante = {
    apellidoOk: containment(CONTROLANTE.apellido, p5) >= 0.85,
    domicilioOk: containment(CONTROLANTE.domicilio, p5) >= 0.75,
    cuitOk: p5digits.includes(cuitDigits),
    cuitEncontrado: (p5.match(/\b(\d{2}\s*-\s*\d{7,8}\s*-\s*\d)\b/) || [])[1] || null,
  };

  // --- Version del formulario (pie de pagina)
  const mForm = todo.match(/\b(2[o0]32[o0]\s*-\s*\d)\s*\(\s*(\d{1,2}\s*\/\s*\d{1,2}\s*\/\s*\d{4})\s*\)/);
  const formId = mForm ? digitize(mForm[1]).replace(/\s/g, '') : null;
  const formFecha = mForm ? cleanFecha(mForm[2]) : null;

  return {
    lugar, fechaEncabezado, fechaSolicitud,
    importe, importeRaw, monedaAclarada,
    posiciones, controlante,
    formId, formFecha,
    paginasDetectadas: paginas.length,
  };
}

// ---------------------------------------------------------------- extraccion CI

export function extraerCi(texto) {
  const t = String(texto || '');
  const s = soft(t);

  const mInv = t.match(/invoice\s*(?:no|n[°ºo*]|number|#)?\s*[.:]+\s*([A-Za-z0-9][A-Za-z0-9\-\/\.]{2,25})/i);
  const mDate = t.match(/\bdate\s*[.:]+\s*([A-Za-z]{3,10}\.?\s*\d{1,2},?\s*\d{4}|\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{2,4})/i);
  const mTo = t.match(/^[ \t]*(?:to|messrs?|buyer|consignee|importer)\s*[:：]\s*(.+)$/im);
  const mCuit = t.match(/\b(\d{2}\s*-\s*\d{8}\s*-\s*\d)\b/);

  // Total: preferir el que sigue a "TOTAL", si no el mayor US$ del doc.
  let total = null;
  const mTot = s.match(/total\s*[:：]?[^\n]{0,120}?us?\s*\$?\s*([\d][\d.,]*)/);
  if (mTot) total = num(mTot[1]);
  if (total == null) {
    const todos = [...s.matchAll(/us\s*\$\s*([\d][\d.,]*)/g)].map(x => num(x[1])).filter(n => n != null);
    if (todos.length) total = Math.max(...todos);
  }

  // "TO: CHEF SRL INVOICE NO.: CQ-8952" -> cortar en la etiqueta siguiente / doble espacio
  const consignee = mTo
    ? mTo[1].split(/\s{2,}|\b(?:invoice|inv\.?\s*no|date|p\.?o\.?\s*no|order)\b/i)[0].replace(/\s+/g, ' ').trim()
    : null;

  return {
    invoice: mInv ? mInv[1].trim() : null,
    fecha: mDate ? mDate[1].trim() : null,
    consignee,
    cuit: mCuit ? mCuit[1].replace(/\s/g, '') : null,
    total,
  };
}

// ---------------------------------------------------------------- anclas / redaccion

const UMBRAL_OK = 0.90;
const UMBRAL_REV = 0.75;

export function chequearAnclas(paginas) {
  const porPagina = paginas.map(p => soft(p));
  const items = ANCLAS.map(a => {
    const pagTexto = porPagina[a.pag - 1] || '';
    let score = containment(a.txt, pagTexto);
    let paginaHallada = a.pag;
    if (score < UMBRAL_OK) {                       // puede haberse corrido de pagina
      porPagina.forEach((p, i) => {
        const s2 = containment(a.txt, p);
        if (s2 > score) { score = s2; paginaHallada = i + 1; }
      });
    }
    const estado = score >= UMBRAL_OK ? 'ok' : score >= UMBRAL_REV ? 'revisar' : 'alerta';
    return { ...a, score, paginaHallada, estado, movida: paginaHallada !== a.pag && score >= UMBRAL_OK };
  });
  return {
    items,
    ok: items.filter(i => i.estado === 'ok').length,
    revisar: items.filter(i => i.estado === 'revisar').length,
    alerta: items.filter(i => i.estado === 'alerta').length,
    total: items.length,
  };
}

// ---------------------------------------------------------------- verificacion

const hoyStr = (d = new Date()) =>
  `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;

function add(out, nivel, campo, msg) { out.push({ nivel, campo, msg }); }

/**
 * @param {object} p
 * @param {string} p.ddjjTexto   texto crudo del PDF de la DDJJ
 * @param {string} [p.ciTexto]   texto crudo del PDF de la CI
 * @param {'transito'|'despacho'} p.caso
 * @param {number} p.montoTransferir
 * @param {'CHEF'|'TN'} p.empresa
 * @param {string} [p.fechaFirma] dd/mm/aaaa (default: hoy)
 */
export function verificarDdjj({ ddjjTexto, ciTexto, caso, montoTransferir, empresa, fechaFirma }) {
  const paginas = splitPaginas(ddjjTexto);
  const d = extraerDdjj(paginas);
  const ci = ciTexto ? extraerCi(ciTexto) : null;
  const anclas = chequearAnclas(paginas);
  const cfg = CASOS[caso] || CASOS.despacho;
  const emp = EMPRESAS_DDJJ[empresa] || EMPRESAS_DDJJ.CHEF;
  const fFirma = fechaFirma || hoyStr();
  const hallazgos = [];

  // ---- 1. Formulario correcto
  if (!d.formId) {
    add(hallazgos, 'alerta', 'Formulario', 'No pude leer el codigo de formulario al pie. Verificar a mano que sea 20320-4 (13/04/2026).');
  } else if (d.formId !== FORM_ID || d.formFecha !== FORM_FECHA) {
    add(hallazgos, 'alerta', 'Formulario',
      `El formulario es ${d.formId} (${d.formFecha}) y la referencia es ${FORM_ID} (${FORM_FECHA}). EL BANCO CAMBIO EL FORMULARIO — revisar la redaccion completa antes de firmar.`);
  } else {
    add(hallazgos, 'ok', 'Formulario', `${FORM_ID} (${FORM_FECHA}) — coincide con la referencia.`);
  }

  if (d.paginasDetectadas !== FORM_PAGINAS) {
    add(hallazgos, 'alerta', 'Paginas', `El PDF tiene ${d.paginasDetectadas} paginas y el formulario tiene ${FORM_PAGINAS}.`);
  }

  // ---- 2. Redaccion
  if (anclas.alerta > 0) {
    add(hallazgos, 'alerta', 'Redaccion',
      `${anclas.alerta} de ${anclas.total} frases clave NO aparecen en el texto. Puede ser texto modificado o escaneo malo — mirar el detalle.`);
  } else if (anclas.revisar > 0) {
    add(hallazgos, 'revisar', 'Redaccion',
      `${anclas.revisar} de ${anclas.total} frases clave con coincidencia parcial (probable ruido de OCR). Revisar el detalle.`);
  } else {
    add(hallazgos, 'ok', 'Redaccion', `Las ${anclas.total} frases clave del formulario estan presentes.`);
  }

  // ---- 3. Pagina 1: lugar / fechas / importe
  if (!d.lugar) add(hallazgos, 'revisar', 'Lugar', 'No pude leer el campo "Lugar". Debe decir "Bs.As".');
  else if (containment('bs as', d.lugar) >= 0.6 || /b[s5]\s*\.?\s*a[s5]|buen[o0]s/.test(d.lugar)) add(hallazgos, 'ok', 'Lugar', `"${d.lugar}"`);
  else add(hallazgos, 'alerta', 'Lugar', `Dice "${d.lugar}" y deberia decir "Bs.As".`);

  if (!d.fechaEncabezado) add(hallazgos, 'revisar', 'Fecha encabezado', 'No pude leerla. Debe ser la fecha de la firma.');
  else if (d.fechaEncabezado === fFirma) add(hallazgos, 'ok', 'Fecha encabezado', d.fechaEncabezado);
  else add(hallazgos, 'alerta', 'Fecha encabezado', `Dice ${d.fechaEncabezado} y la fecha de firma indicada es ${fFirma}.`);

  if (!d.fechaSolicitud) add(hallazgos, 'revisar', 'Fecha solicitud', 'No pude leer la fecha del parrafo B.C.L. Debe ser igual a la del encabezado.');
  else if (d.fechaEncabezado && d.fechaSolicitud !== d.fechaEncabezado)
    add(hallazgos, 'alerta', 'Fecha solicitud', `Encabezado ${d.fechaEncabezado} ≠ parrafo B.C.L. ${d.fechaSolicitud}. Tienen que ser la misma.`);
  else add(hallazgos, 'ok', 'Fecha solicitud', d.fechaSolicitud);

  if (d.importe == null) {
    add(hallazgos, 'alerta', 'Importe', 'No pude leer el importe del encabezado.');
  } else {
    if (!d.monedaAclarada) add(hallazgos, 'alerta', 'Importe', `Se lee ${d.importeRaw} pero SIN aclarar moneda. Tiene que decir "usd ${d.importeRaw}".`);
    else add(hallazgos, 'ok', 'Importe', `usd ${d.importeRaw} (${fmtUsd(d.importe)})`);
    if (montoTransferir != null && Math.abs(d.importe - montoTransferir) > 0.01)
      add(hallazgos, 'alerta', 'Importe vs transferencia', `DDJJ ${fmtUsd(d.importe)} ≠ monto a transferir ${fmtUsd(montoTransferir)}.`);
  }

  // ---- 4. Pagina 2: cuadro de posiciones
  const sumaPos = d.posiciones.reduce((a, p) => a + (p.monto || 0), 0);
  if (!d.posiciones.length) {
    add(hallazgos, cfg.posicionesObligatorias ? 'alerta' : 'revisar', 'Posiciones arancelarias',
      'El cuadro de la pagina 2 esta vacio o no lo pude leer.' + (caso === 'despacho'
        ? ' Aunque el cuadro diga "solo sin despacho a plaza", el banco pide completarlo igual.'
        : ' Sin despacho a plaza es obligatorio completarlo.'));
  } else {
    add(hallazgos, 'ok', 'Posiciones arancelarias',
      d.posiciones.map(p => `${p.ncm} · ${p.moneda} ${p.montoRaw}`).join('  |  '));
    const refImp = d.importe ?? montoTransferir;
    if (refImp != null && Math.abs(sumaPos - refImp) > 0.01)
      add(hallazgos, 'alerta', 'Suma del cuadro',
        `La suma de las posiciones (${fmtUsd(sumaPos)}) no da igual al importe (${fmtUsd(refImp)}). En un pago parcial la/s posicion/es cargadas tienen que cubrir exactamente el monto a girar.`);
    else if (refImp != null)
      add(hallazgos, 'ok', 'Suma del cuadro', `${fmtUsd(sumaPos)} = importe declarado.`);
  }

  // ---- 5. Pagina 5: controlante
  const c = d.controlante;
  if (c.apellidoOk && c.cuitOk) add(hallazgos, 'ok', 'Cuadro 4.A (controlante)', `${CONTROLANTE.denominacion} · ${CONTROLANTE.cuit}${c.domicilioOk ? ' · ' + CONTROLANTE.domicilio : ''}`);
  else {
    if (!c.apellidoOk) add(hallazgos, 'alerta', 'Cuadro 4.A (controlante)', `No encuentro "${CONTROLANTE.denominacion}" en la pagina 5.`);
    if (!c.cuitOk) add(hallazgos, 'alerta', 'Cuadro 4.A (CUIT)', `No encuentro el CUIT ${CONTROLANTE.cuit}${c.cuitEncontrado ? ` (leo "${c.cuitEncontrado}")` : ''}.`);
  }
  if (c.apellidoOk && !c.domicilioOk) add(hallazgos, 'revisar', 'Cuadro 4.A (domicilio)', `Verificar a mano "${CONTROLANTE.domicilio}".`);

  // ---- 6. Cruce con la CI
  if (ci) {
    const partes = [ci.invoice && `Invoice ${ci.invoice}`, ci.fecha, ci.total != null && fmtUsd(ci.total)].filter(Boolean);
    add(hallazgos, 'ok', 'CI leida', partes.join(' · ') || '(datos incompletos)');

    if (ci.total != null && montoTransferir != null) {
      if (montoTransferir > ci.total + 0.01)
        add(hallazgos, 'alerta', 'Monto vs CI', `Se quiere girar ${fmtUsd(montoTransferir)} y la CI es de ${fmtUsd(ci.total)}.`);
      else if (Math.abs(montoTransferir - ci.total) <= 0.01)
        add(hallazgos, 'ok', 'Monto vs CI', `Pago TOTAL de la CI (${fmtUsd(ci.total)}).`);
      else
        add(hallazgos, 'ok', 'Monto vs CI', `Pago PARCIAL: ${fmtUsd(montoTransferir)} de ${fmtUsd(ci.total)} (saldo ${fmtUsd(ci.total - montoTransferir)}). Adjuntar nota con el detalle de los pagos parciales.`);
    }

    const nombreOk = emp.alias.some(a => containment(a, ci.consignee || '') >= 0.8);
    const cuitOk = emp.cuit && ci.cuit && ci.cuit.replace(/\D/g, '') === emp.cuit.replace(/\D/g, '');
    if (nombreOk || cuitOk) add(hallazgos, 'ok', 'Empresa vs CI', `${emp.razonSocial} — CI a nombre de "${ci.consignee || ci.cuit}".`);
    else add(hallazgos, 'alerta', 'Empresa vs CI', `Elegiste ${emp.razonSocial} pero la CI figura a "${ci.consignee || '—'}"${ci.cuit ? ` (CUIT ${ci.cuit})` : ''}.`);
  } else {
    add(hallazgos, 'revisar', 'CI', 'No subiste la CI — no se pudo cruzar monto ni importador.');
  }

  // ---- 7. Caso seleccionado
  if (caso === 'despacho') {
    add(hallazgos, 'revisar', 'Tilde pagina 2',
      `Confirmar VISUALMENTE que este tildado "${cfg.checkboxEsperado}". El texto del PDF no permite leer los tildes.`);
  } else {
    add(hallazgos, 'revisar', 'Tilde pagina 2',
      'Mercaderia en transito: confirmar VISUALMENTE cual opcion se tildo (anticipado / vista / MiPyME / financiada) y que NO sea "con despacho". Reglas de este caso todavia no definidas en el .md.');
  }
  add(hallazgos, 'revisar', 'Paginas 3 y 4', 'Confirmar VISUALMENTE que no se tildo nada.');
  add(hallazgos, 'revisar', 'Punto 4.B (pag. 5)', `Confirmar VISUALMENTE que este tildada SOLO la opcion ${OPCION_4B}).`);
  add(hallazgos, 'revisar', 'Firma (pag. 6)', `Firma + aclaracion + caracter invocado "${emp.caracterFirmante}".`);

  const resumen = {
    alerta: hallazgos.filter(h => h.nivel === 'alerta').length,
    revisar: hallazgos.filter(h => h.nivel === 'revisar').length,
    ok: hallazgos.filter(h => h.nivel === 'ok').length,
  };
  resumen.veredicto = resumen.alerta > 0 ? 'NO PRESENTAR' : 'REVISAR Y FIRMAR';

  return {
    caso: cfg, empresa: emp, fechaFirma: fFirma, montoTransferir,
    datos: d, ci, anclas, hallazgos, resumen,
    checklist: checklistManual(caso, emp.id),
  };
}

export { fmtUsd, hoyStr };
