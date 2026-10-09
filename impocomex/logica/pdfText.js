// Extraccion en el navegador con detección inteligente:
// - PDF con buen texto -> devuelve texto (el backend no recibe el PDF, menos memoria)
// - PDF con poco texto (scan dominante) -> split en chunks de 5 páginas + texto parcial
// - Excel -> CSV por hoja

import * as pdfjs from '../vendor/pdf.min.mjs';
const pdfWorker = new URL('../vendor/pdf.worker.min.mjs', import.meta.url).href;
import * as XLSX from '../vendor/xlsx.mjs';
import { PDFDocument } from '../vendor/pdf-lib.js';

pdfjs.GlobalWorkerOptions.workerSrc = pdfWorker;

const MIN_CHARS_PER_PAGE = 200;   // menos que esto = scan dominante
const CHUNK_PAGES = 5;            // paginas por chunk cuando hay que vision-ear

// Campos de formulario con valor (widgets). Los PDF de GDE (CE, IF de ANMAT) guardan el número y la fecha del
// documento en campos, no en el texto: sin esto la IA no ve ni el número ni la emisión.
async function camposDePagina(page) {
  try {
    return (await page.getAnnotations())
      .filter(a => a.subtype === 'Widget' && typeof a.fieldValue === 'string' && a.fieldValue.trim())
      .map(a => `${a.fieldName || 'campo'}: ${a.fieldValue.trim().replace(/\s+/g, ' ')}`);
  } catch {
    return [];
  }
}

/**
 * Analiza un PDF y devuelve:
 *  { mode: 'text-only',  text, numPages, charsPerPage }
 *  { mode: 'chunks',     chunks: [{index, total, firstPage, lastPage, bytes, text}], numPages }
 *  { mode: 'fail',       error }
 * opciones.campos: antepone a cada página sus campos de formulario ("[Campos del documento] fecha: ... | ...").
 * No cuentan para decidir si hay texto suficiente: un escaneo con campos sigue yendo como imagen.
 */
export async function analyzePdf(file, opciones = {}) {
  try {
    const raw = await file.arrayBuffer();

    // 1) Leer con pdfjs para extraer texto
    const pdf = await pdfjs.getDocument({ data: raw.slice(0) }).promise;
    const numPages = pdf.numPages;
    const textosPage = [];
    const conCampos = [];
    for (let i = 1; i <= numPages; i++) {
      const page = await pdf.getPage(i);
      const content = await page.getTextContent();
      const texto = content.items.map(it => it.str || '').join(' ');
      textosPage.push(texto);
      const campos = opciones.campos ? await camposDePagina(page) : [];
      conCampos.push(campos.length ? `[Campos del documento] ${campos.join(' | ')}\n${texto}` : texto);
    }
    await pdf.destroy();

    const charsPerPage = numPages ? textosPage.join('\n\n--- PAGINA ---\n\n').trim().length / numPages : 0;
    const textCompleto = conCampos.join('\n\n--- PAGINA ---\n\n').trim();

    if (charsPerPage >= MIN_CHARS_PER_PAGE) {
      // Texto suficiente — modo text-only
      return { mode: 'text-only', text: textCompleto, numPages, charsPerPage };
    }

    // 2) Scan dominante — split en chunks con pdf-lib
    const src = await PDFDocument.load(raw);
    const chunks = [];
    const nChunks = Math.ceil(numPages / CHUNK_PAGES);
    for (let i = 0; i < nChunks; i++) {
      const start = i * CHUNK_PAGES;
      const end = Math.min(start + CHUNK_PAGES, numPages);
      const doc = await PDFDocument.create();
      const indices = Array.from({ length: end - start }, (_, k) => start + k);
      const copied = await doc.copyPages(src, indices);
      copied.forEach(p => doc.addPage(p));
      const bytes = await doc.save();
      const chunkText = conCampos.slice(start, end).join('\n\n').trim();
      chunks.push({
        index: i,
        total: nChunks,
        firstPage: start + 1,
        lastPage: end,
        bytes,
        text: chunkText,
      });
    }
    return { mode: 'chunks', chunks, numPages, charsPerPage };
  } catch (e) {
    return { mode: 'fail', error: e.message };
  }
}

// Retrocompat
export async function extractPdfText(file, opciones = {}) {
  const r = await analyzePdf(file, opciones);
  return r.mode === 'text-only' ? r.text : '';
}

export async function extractXlsxText(file) {
  try {
    const buf = await file.arrayBuffer();
    const wb = XLSX.read(buf, { type: 'array' });
    const out = [];
    for (const name of wb.SheetNames) {
      const ws = wb.Sheets[name];
      const csv = XLSX.utils.sheet_to_csv(ws, { blankrows: false });
      if (csv.trim()) out.push(`=== HOJA "${name}" ===\n${csv}`);
    }
    return out.join('\n\n').slice(0, 30000);
  } catch (e) {
    console.warn('extractXlsxText failed for', file.name, e.message);
    return '';
  }
}

export async function extractText(file, opciones = {}) {
  const ext = (file.name.split('.').pop() || '').toLowerCase();
  if (['xlsx','xls','csv'].includes(ext)) return extractXlsxText(file);
  if (ext === 'pdf') return extractPdfText(file, opciones);
  return '';
}
