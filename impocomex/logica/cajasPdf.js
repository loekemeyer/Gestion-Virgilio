// Genera el PDF del resultado de Cajas: lo que está bien, lo que está mal y el porqué (motivo), con la cara
// de cada dato, la cuenta de los pesos y su %, las fotos que faltan y las que no se pudieron asignar.
// Usa la revisión manual (bien/mal + motivo) si la hay; si no, el resultado automático y su explicación.
// Planes: .planning/PLAN-2026-09-16-cajas-articulo-carton.md (r51), PLAN-2026-09-18-cajas-caras-ci-pesos.md (r54)

import { PDFDocument, StandardFonts, rgb } from '../vendor/pdf-lib.js';
import { CAMPOS, CARA, cajaDe, pctTxt } from './cajasEtiquetas.js';

const clave = (f) => `${f.codigo}|${f.tipo_caja}|${f.campo}`;

// Estado final de una fila según la revisión manual o, si no hay, el automático.
function estadoFinal(f, rev) {
  const r = rev?.revision;
  if (r === 'ok') return 'bien';
  if (r === 'mal') return 'mal';
  if (f.resultado === 'ok') return 'bien';
  if (f.resultado === 'diferencia') return 'mal';
  if (f.resultado === 'falta_foto') return 'falta';
  return 'pendiente'; // ilegible / sin_dato_pl
}

export async function generarPdfCajas(res, revisiones = {}) {
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const A4 = [595.28, 841.89];
  const M = 40, ANCHO = A4[0] - M * 2;
  let page = doc.addPage(A4);
  let y = A4[1] - M;

  // Helvetica (WinAnsi): se reemplazan los caracteres que no puede dibujar.
  const sanear = (s) => String(s ?? '').replace(/[×]/g, 'x').replace(/[÷]/g, '/').replace(/[–—]/g, '-').replace(/≥/g, '>=')
    .replace(/[^\x20-\x7E -ÿ]/g, ' ');
  const nueva = () => { page = doc.addPage(A4); y = A4[1] - M; };
  const parte = (texto, fnt, size, ancho) => {
    const palabras = sanear(texto).split(/\s+/); const lineas = []; let ln = '';
    for (const w of palabras) {
      const t = ln ? ln + ' ' + w : w;
      if (fnt.widthOfTextAtSize(t, size) > ancho && ln) { lineas.push(ln); ln = w; } else ln = t;
    }
    if (ln) lineas.push(ln);
    return lineas;
  };
  const linea = (texto, { size = 10, fnt = font, color = rgb(0.1, 0.12, 0.16), gap = 3, x = M } = {}) => {
    for (const l of parte(texto, fnt, size, ANCHO - (x - M))) {
      if (y - size < M) nueva();
      page.drawText(l, { x, y: y - size, size, font: fnt, color });
      y -= size + gap;
    }
  };
  const espacio = (h = 6) => { y -= h; if (y < M) nueva(); };
  const gris = rgb(0.4, 0.45, 0.5);

  const fecha = new Date().toLocaleString('es-AR');
  linea('Verificación de Cajas vs Packing List', { size: 16, fnt: bold });
  espacio(2);
  linea(`Packing list: ${res.pl?.invoice_ref || 's/ref'}  ·  Tipo: ${res.tipo_envio || ''}  ·  ${fecha}`, { size: 9, color: gris });
  linea(res.ci_resumen ? `Commercial Invoice: ${res.ci_resumen.invoice_nro || 's/nro'} · comprador ${res.ci_resumen.buyer || '-'} · ${res.ci_resumen.items} ítems` : 'Sin Commercial Invoice', { size: 9, color: gris });
  if (res.razon_importador || res.cuit_importador) linea(`Importador: ${res.razon_importador || ''} ${res.cuit_importador ? '(CUIT ' + res.cuit_importador + ')' : ''}`, { size: 9, color: gris });
  if (res.corrida_id) linea(`Corrida: ${res.corrida_id}`, { size: 8, color: rgb(0.6, 0.63, 0.68) });
  espacio(4);

  const filas = res.resultados || [];
  const con = (estado) => filas.filter(f => estadoFinal(f, revisiones[clave(f)]) === estado);
  const mal = con('mal'), bien = con('bien'), pend = con('pendiente'), falta = con('falta');
  const graves = mal.filter(f => f.grave).length;
  const nSin = (res.sin_asignar || []).length;
  linea(`Resumen: ${bien.length} bien · ${mal.length} mal${graves ? ` (${graves} grave${graves === 1 ? '' : 's'})` : ''} · ${pend.length} a revisar · ${falta.length} fotos que faltan${nSin ? ` · ${nSin} sin asignar (no comparadas)` : ''}`, { size: 11, fnt: bold });
  espacio(6);

  // Fotos que faltan, por código.
  if (falta.length) {
    linea(`Faltan fotos (${falta.length}) — esa cara no se verificó`, { size: 12, fnt: bold, color: rgb(0.35, 0.38, 0.42) });
    const porCod = new Map();
    for (const f of falta) { if (!porCod.has(f.codigo)) porCod.set(f.codigo, []); porCod.get(f.codigo).push(cajaDe(f)); }
    for (const [c, caras] of porCod) linea(`${c}: ${caras.join(', ')}`, { size: 9.5, x: M + 8 });
    espacio(6);
  }
  const sinAsig = res.sin_asignar || [];
  if (sinAsig.length) {
    linea(`Fotos sin asignar (${sinAsig.length}) — no se compararon`, { size: 12, fnt: bold, color: rgb(0.7, 0.4, 0.05) });
    for (const l of sinAsig) linea(`${l.foto}: ${(l.caras || []).map(c => CARA[c]).join(' + ') || 'no se identificó qué cara es'}`, { size: 9, x: M + 8 });
    espacio(6);
  }

  const bloque = (titulo, lista, color, conMotivo) => {
    linea(titulo, { size: 12, fnt: bold, color });
    if (!lista.length) { linea('— ninguno', { size: 9, color: rgb(0.5, 0.53, 0.58) }); espacio(4); return; }
    for (const f of lista) {
      const rev = revisiones[clave(f)];
      const pctF = f.dif_pct ? `  (${pctTxt(f.dif_pct)})` : '';
      const cab = `${f.grave ? 'GRAVE  ' : ''}${f.codigo}  [${cajaDe(f)}]  ${CAMPOS[f.campo] || f.campo}${pctF}`;
      const val = f.valor_foto != null || f.valor_pl != null ? `   foto: ${f.valor_foto ?? '—'}  /  esperado: ${f.valor_pl ?? '—'}` : '';
      linea(cab + val, { size: 9.5, fnt: bold, color: f.grave ? rgb(0.72, 0.11, 0.11) : rgb(0.15, 0.17, 0.2) });
      if (f.calculo) for (const c of String(f.calculo).split(' | ')) linea(c, { size: 8.5, color: gris, x: M + 12 });
      if (conMotivo) {
        const motivo = (rev?.motivo && rev.motivo.trim()) ? rev.motivo.trim() : (f.detalle || '');
        if (motivo) linea('Motivo: ' + motivo, { size: 9, color: rgb(0.35, 0.38, 0.42), x: M + 12 });
        if (rev?.revision) linea('Revisión manual: ' + (rev.revision === 'ok' ? 'BIEN' : 'MAL'), { size: 8.5, color: rgb(0.45, 0.48, 0.52), x: M + 12 });
      }
      espacio(3);
    }
    espacio(4);
  };

  bloque(`Incorrecto (${mal.length})`, mal, rgb(0.72, 0.11, 0.11), true);
  bloque(`A revisar / no leído (${pend.length})`, pend, rgb(0.7, 0.4, 0.05), true);
  bloque(`Correcto (${bien.length})`, bien, rgb(0.02, 0.45, 0.3), false);

  return doc.save();
}
