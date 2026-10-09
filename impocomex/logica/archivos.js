// Expande lo que el usuario suelta o elige en una zona de subida: carpetas, .zip y .rar, anidados
// (carpeta → zip → zip → PDF). Nunca manda un directorio crudo al servidor: eso cortaba el pedido con
// "Failed to fetch". Cada archivo conserva su ruta en el nombre ("Familia A › inal.zip › CE.pdf"),
// que el servidor usa para agrupar los documentos de un mismo trámite.
// Plan: .planning/PLAN-2026-09-15-correcciones-y-archivos.md (fase A)

import { unzipSync } from '../vendor/fflate.js';
import { createExtractorFromData } from '../vendor/unrar.js';
const unrarWasmUrl = new URL('../vendor/unrar.wasm', import.meta.url).href;

export const SEP = ' › ';
export const LIMITES = { archivos: 300, bytes: 300 * 1024 * 1024, profundidad: 5 };

const BASURA = /(^|›\s*|\/)(__MACOSX|\.DS_Store|Thumbs\.db|desktop\.ini|~\$[^›/]*)(\s*›|\/|$)/i;
const OTRO_COMPRIMIDO = /\.(7z|tar|gz|tgz|bz2|xz|arj|cab|zipx)$/i;

const MIME = {
  pdf: 'application/pdf', jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp',
  gif: 'image/gif', bmp: 'image/bmp', tif: 'image/tiff', tiff: 'image/tiff', heic: 'image/heic',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', xls: 'application/vnd.ms-excel',
  csv: 'text/csv', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

export const extension = (nombre) => {
  const m = String(nombre).match(/\.([A-Za-z0-9]{1,5})$/);
  return m ? m[1].toLowerCase() : '';
};

// "application/pdf,image/*,.xlsx" → nombre → ¿se acepta?
export function aceptaDe(accept) {
  const exts = new Set();
  for (const p of String(accept || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean)) {
    if (p.startsWith('.')) exts.add(p.slice(1));
    else if (p === 'image/*') ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'tif', 'tiff', 'heic'].forEach(e => exts.add(e));
    else {
      const ext = Object.entries(MIME).find(([, m]) => m === p)?.[0];
      if (ext) { exts.add(ext); if (ext === 'jpg') exts.add('jpeg'); }
    }
  }
  return (nombre) => exts.size === 0 || exts.has(extension(nombre));
}

// El WASM de unrar se carga una sola vez. En las pruebas se reemplaza (ver `_pruebas`).
let wasmRar = null;
let cargarWasmRar = async () => (await fetch(unrarWasmUrl)).arrayBuffer();
export const _pruebas = { usarWasmRar(fn) { cargarWasmRar = fn; wasmRar = null; } };

function leerZip(bytes) {
  let entradas;
  try { entradas = unzipSync(bytes); } catch (e) { throw new Error(`no se pudo abrir el .zip (${e.message})`); }
  return Object.entries(entradas)
    .filter(([ruta]) => !ruta.endsWith('/'))
    .map(([ruta, datos]) => ({ ruta: ruta.split('/').filter(Boolean).join(SEP), datos }));
}

async function leerRar(bytes) {
  if (!wasmRar) wasmRar = await cargarWasmRar();
  const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  let extractor;
  try {
    extractor = await createExtractorFromData({ wasmBinary: wasmRar.slice(0), data });
  } catch (e) {
    throw new Error(/password|encrypt/i.test(String(e.message)) ? 'el .rar tiene contraseña' : `no se pudo abrir el .rar (${e.message})`);
  }
  const lista = extractor.getFileList();
  const cabeceras = [...lista.fileHeaders];
  if (lista.arcHeader?.flags?.headerEncrypted || cabeceras.some(h => h.flags?.encrypted)) throw new Error('el .rar tiene contraseña');
  const salida = [];
  for (const f of extractor.extract().files) {
    if (f.fileHeader.flags.directory || !f.extraction) continue;
    salida.push({ ruta: f.fileHeader.name.split(/[\\/]/).filter(Boolean).join(SEP), datos: f.extraction });
  }
  return salida;
}

// Un "archivo" que en realidad es una carpeta no se puede leer.
async function esCarpeta(file) {
  if (file.size > 0 || file.type) return false;
  try { await file.slice(0, 1).arrayBuffer(); return false; } catch { return true; }
}

/**
 * entradas: Array<{ file: File, ruta?: string }>. ruta = camino relativo con SEP (carpetas soltadas).
 * Devuelve { archivos: File[], ignorados: [{ nombre, motivo }], error: string | null }.
 */
export async function expandir(entradas, { accept, limites = LIMITES } = {}) {
  const acepta = aceptaDe(accept);
  const archivos = [];
  const ignorados = [];
  let bytes = 0;
  let error = null;

  const procesar = async (ruta, leer, original, nivel) => {
    if (error) return;
    if (BASURA.test(ruta)) return;
    const ext = extension(ruta);

    if (ext === 'zip' || ext === 'rar') {
      if (nivel >= limites.profundidad) {
        ignorados.push({ nombre: ruta, motivo: 'demasiados comprimidos uno dentro de otro' });
        return;
      }
      let internos;
      try { internos = ext === 'zip' ? leerZip(await leer()) : await leerRar(await leer()); }
      catch (e) { ignorados.push({ nombre: ruta, motivo: e.message }); return; }
      if (!internos.length) ignorados.push({ nombre: ruta, motivo: 'comprimido vacío' });
      for (const it of internos) await procesar(`${ruta}${SEP}${it.ruta}`, async () => it.datos, null, nivel + 1);
      return;
    }
    if (OTRO_COMPRIMIDO.test(ruta)) {
      ignorados.push({ nombre: ruta, motivo: 'formato comprimido no soportado: usar .zip o .rar' });
      return;
    }
    if (!acepta(ruta)) {
      ignorados.push({
        nombre: ruta,
        motivo: ext ? 'tipo de archivo que esta zona no usa' : 'sin extensión: si es una carpeta, arrastrala o usá "Elegir carpeta"',
      });
      return;
    }

    let file = original;
    if (!file || file.name !== ruta) file = original
      // Carpeta/soltar: envolver el File original para ponerle la ruta, SIN leerlo a memoria (referencia
      // al blob; se lee recién cuando hace falta). Antes se leía cada archivo entero acá y una carpeta de
      // muchas fotos reventaba el límite de memoria.
      ? new File([original], ruta, { type: original.type || MIME[ext] || '' })
      // Comprimido: los bytes ya están en memoria (descomprimidos), así que se materializan.
      : new File([await leer()], ruta, { type: MIME[ext] || '' });
    if (archivos.length + 1 > limites.archivos) {
      error = `Demasiados archivos (más de ${limites.archivos}). Subí las familias por partes.`;
      return;
    }
    bytes += file.size;
    if (bytes > limites.bytes) {
      error = `Demasiado grande (más de ${Math.round(limites.bytes / 1024 / 1024)} MB descomprimido). Subí las familias por partes.`;
      return;
    }
    archivos.push(file);
  };

  for (const { file, ruta } of entradas) {
    if (await esCarpeta(file)) {
      ignorados.push({ nombre: file.name, motivo: 'es una carpeta: arrastrala o usá "Carpeta"' });
      continue;
    }
    await procesar(ruta || file.name, async () => new Uint8Array(await file.arrayBuffer()), file, 0);
  }
  return { archivos: error ? [] : archivos, ignorados, error };
}

// Entradas de un "soltar". Hay que pedir las entradas antes de cualquier await: después del evento
// el DataTransfer deja de ser válido.
export function entradasDeSoltar(dataTransfer) {
  const items = [...(dataTransfer.items || [])].filter(i => i.kind === 'file');
  const conEntrada = items.map(i => ({ entry: i.webkitGetAsEntry?.(), file: i.getAsFile() }));
  const archivosSueltos = [...(dataTransfer.files || [])];

  return (async () => {
    if (!conEntrada.some(x => x.entry)) return archivosSueltos.map(file => ({ file, ruta: file.name }));
    const salida = [];
    const recorrer = async (entry, ruta) => {
      if (entry.isFile) {
        const file = await new Promise((ok, mal) => entry.file(ok, mal));
        salida.push({ file, ruta });
      } else if (entry.isDirectory) {
        const lector = entry.createReader();
        for (;;) {
          const lote = await new Promise((ok, mal) => lector.readEntries(ok, mal));
          if (!lote.length) break;
          for (const e of lote) await recorrer(e, `${ruta}${SEP}${e.name}`);
        }
      }
    };
    for (const { entry, file } of conEntrada) {
      if (entry) await recorrer(entry, entry.name);
      else if (file) salida.push({ file, ruta: file.name });
    }
    return salida;
  })();
}

// Entradas de un <input type="file"> (con o sin webkitdirectory).
export const entradasDeInput = (files) =>
  [...files].map(file => ({ file, ruta: file.webkitRelativePath ? file.webkitRelativePath.split('/').join(SEP) : file.name }));

// Carpeta o comprimido de origen: agrupa los documentos de un mismo trámite.
export const grupoDe = (nombre) => (String(nombre).includes(SEP) ? String(nombre).slice(0, String(nombre).lastIndexOf(SEP)) : '');
