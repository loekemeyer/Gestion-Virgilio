// Lector local de códigos de barras EAN-13 (sin IA, sin red): decodifica las BARRAS de la foto con
// @zxing/library. Es determinista: si lo lee, el número es exacto (lo confirma el dígito verificador).
// Si no lo puede leer devuelve null y queda la lectura de la IA como respaldo.
// Plan: .planning/PLAN-2026-09-18-cajas-caras-ci-pesos.md

import {
  EAN13Reader, DecodeHintType, RGBLuminanceSource, BinaryBitmap, HybridBinarizer, GlobalHistogramBinarizer,
} from '../vendor/zxing.js';

export function ean13Valido(codigo) {
  const d = String(codigo || '').replace(/\D/g, '');
  if (d.length !== 13) return false;
  let s = 0;
  for (let i = 0; i < 12; i++) s += Number(d[i]) * (i % 2 === 0 ? 1 : 3);
  return (10 - (s % 10)) % 10 === Number(d[12]);
}

const HINTS = new Map([[DecodeHintType.TRY_HARDER, true]]);

// Decodifica una imagen en escala de grises (un byte por pixel). Devuelve el EAN-13 o null.
export function decodificarLuminancia(lum, ancho, alto) {
  for (const Binarizador of [HybridBinarizer, GlobalHistogramBinarizer]) {
    try {
      const r = new EAN13Reader().decode(new BinaryBitmap(new Binarizador(new RGBLuminanceSource(lum, ancho, alto))), HINTS);
      const texto = r?.getText?.() || '';
      if (ean13Valido(texto)) return texto;
    } catch { /* no encontró código con este binarizador */ }
  }
  return null;
}

function luminancia(ctx, w, h) {
  const { data } = ctx.getImageData(0, 0, w, h);
  const out = new Uint8ClampedArray(w * h);
  for (let i = 0, j = 0; i < out.length; i++, j += 4) out[i] = (data[j] * 299 + data[j + 1] * 587 + data[j + 2] * 114) / 1000;
  return out;
}

async function cargarImagen(file) {
  if (typeof createImageBitmap === 'function') {
    try { return await createImageBitmap(file); } catch { /* sigue con <img> */ }
  }
  const url = URL.createObjectURL(file);
  try {
    return await new Promise((ok, mal) => { const i = new Image(); i.onload = () => ok(i); i.onerror = mal; i.src = url; });
  } finally { URL.revokeObjectURL(url); }
}

// Lee el EAN-13 de una foto (File). Prueba dos tamaños y la foto girada 90° (el código puede estar vertical).
export async function leerCodigoBarras(file) {
  if (!file || !String(file.type || '').startsWith('image/')) return null;
  let img;
  try { img = await cargarImagen(file); } catch { return null; }
  const W = img.width, H = img.height;
  for (const lado of [1600, 1000, 2400]) {
    const escala = Math.min(1, lado / Math.max(W, H));
    if (lado === 2400 && escala < 1 && Math.max(W, H) <= 1600) continue;
    const w = Math.round(W * escala), h = Math.round(H * escala);
    for (const giro of [0, 90]) {
      const canvas = document.createElement('canvas');
      canvas.width = giro ? h : w;
      canvas.height = giro ? w : h;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (giro) { ctx.translate(h, 0); ctx.rotate(Math.PI / 2); }
      ctx.drawImage(img, 0, 0, w, h);
      const codigo = decodificarLuminancia(luminancia(ctx, canvas.width, canvas.height), canvas.width, canvas.height);
      if (codigo) { img.close?.(); return codigo; }
    }
    if (escala === 1) break;
  }
  img.close?.();
  return null;
}
